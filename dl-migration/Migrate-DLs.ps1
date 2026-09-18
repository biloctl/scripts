<#
.SYNOPSIS
    Step 2 of 2 - Migrate the distribution groups listed in a CSV from synced to cloud-managed.

.DESCRIPTION
    Run ON the Entra Connect server. Only groups in the CSV are touched. If the CSV has a Migrate
    column, only rows with Y / Yes / TRUE / 1 are processed; otherwise every row is.

    Per batch (default 20):
      Export (EXO -> JSON)  ->  Create TMP- shadow group  ->  Move AD group to NoSyncOU
      ->  Start-ADSyncSyncCycle -Delta (local)  ->  wait for EXO to drop synced object
      ->  rename TMP- to original identity + all proxies + X500  ->  re-link nesting  ->  verify

    Progress is written to <InputCsv>-status.csv; re-running the same CSV resumes unfinished rows.

.EXAMPLE
    .\Migrate-DLs.ps1 -InputCsv C:\DLMigration\finance-dls.csv `
        -NoSyncOU "OU=DL-Migrated-NoSync,DC=contoso,DC=com" -DefaultOwner dl-placeholder@contoso.com

    Signs in interactively with your account (needs Exchange Administrator / Recipient Management).
    Owners are set to exactly what the group had on-prem. Groups with no on-prem owner get -DefaultOwner
    (recommended: a shared mailbox or admin group). Your account is never left as an owner.

    Add -WhatIf to dry-run. Add -BatchSize to change the 20 default. Add -MaxBatches 1 to run one batch.

.NOTES
    Prereqs: ExchangeOnlineManagement + ActiveDirectory modules; ADSync module (present on Connect server);
    your cloud account has Exchange Administrator (or Recipient Management) role; your on-prem account can
    move AD groups and is in ADSyncAdmins; NoSyncOU excluded from Connect OU filter.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$InputCsv,
    [string]$TenantMailDomain,                  # optional; auto-detected (*.mail.onmicrosoft.com) if omitted
    [string]$UserPrincipalName,                 # optional, interactive sign-in (default)
    [string]$AppId, [string]$CertThumbprint, [string]$Organization,   # optional, only for unattended cert auth
    [Parameter(Mandatory)][string]$NoSyncOU,
    [string]$DefaultOwner,                      # owner for groups that have none on-prem (e.g. it-admins@contoso.com). If omitted, script tries ownerless.
    [int]$BatchSize = 20,
    [int]$MaxBatches = [int]::MaxValue,
    [int]$DeletionTimeoutMin = 30,
    [int]$ResyncAfterMin = 2,                    # run another delta sync if objects still present after this many minutes
    [string]$DomainController,                   # DC to write AD moves against; ideally the one Entra Connect imports from
    [int]$ReplicationWaitSec = 45,               # pause between AD moves and the first delta sync
    [string]$WorkDir = 'C:\DLMigration',
    [string]$TempPrefix = 'TMP-'
)

# ------------------------------------------------------------------ setup
$ErrorActionPreference = 'Stop'
$exo = Get-Module ExchangeOnlineManagement -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if (-not $exo)                       { throw "ExchangeOnlineManagement module not found. Run: Install-Module ExchangeOnlineManagement -Scope AllUsers -Force" }
if ($exo.Version -lt [version]'3.0') { throw "ExchangeOnlineManagement $($exo.Version) is too old (need 3.0+). Run: Update-Module ExchangeOnlineManagement -Force" }
Import-Module ExchangeOnlineManagement -MinimumVersion 3.0
Import-Module ActiveDirectory
Import-Module ADSync
$ExportDir  = Join-Path $WorkDir 'export'
$StatusFile = [IO.Path]::ChangeExtension($InputCsv, $null).TrimEnd('.') + '-status.csv'
$LogFile    = Join-Path $WorkDir "migrate-$(Get-Date -f yyyyMMdd-HHmm).log"
New-Item -ItemType Directory -Force -Path $ExportDir | Out-Null

function Log { param($Msg,$Level='INFO')
    $l = "{0} [{1}] {2}" -f (Get-Date -f 'yyyy-MM-dd HH:mm:ss'), $Level, $Msg
    Write-Host $l -ForegroundColor $(switch($Level){'WARN'{'Yellow'}'ERROR'{'Red'}'OK'{'Green'}default{'Gray'}})
    Add-Content $LogFile $l
}
function Connect-EXO {
    if (-not (Get-ConnectionInformation | Where-Object State -eq 'Connected')) {
        if ($AppId)                  { Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $CertThumbprint -Organization $Organization -ShowBanner:$false }
        elseif ($UserPrincipalName)  { Connect-ExchangeOnline -UserPrincipalName $UserPrincipalName -ShowBanner:$false }
        else                         { Connect-ExchangeOnline -ShowBanner:$false }
    }
}
function Invoke-EXO { param([scriptblock]$Script, [int]$Retries = 4)
    for ($i = 1; $i -le $Retries; $i++) {
        try { return & $Script }
        catch {
            if ($i -eq $Retries -or $_ -notmatch 'throttl|busy|timed out|OperationTimeout|MicroDelay') { throw }
            Connect-EXO; Start-Sleep ([math]::Pow(2,$i) * 10)
        }
    }
}
function Resolve-Smtp($ids) {
    @($ids | ForEach-Object { "$((Get-Recipient -Identity $_ -ResultSize 1 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Select-Object -First 1).PrimarySmtpAddress)" } |
      Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim().ToLower() } | Select-Object -Unique)
}
function ExportFile($smtp) { Join-Path $ExportDir (($smtp -replace '[^\w\.-]','_') + '.json') }
function TmpSmtp($alias) { "$TempPrefix$alias@$TenantMailDomain" }

# ------------------------------------------------------------------ load input + status
Connect-EXO
if (-not $TenantMailDomain) {
    $TenantMailDomain = (Get-AcceptedDomain | Where-Object { $_.DomainName -like '*.mail.onmicrosoft.com' } | Select-Object -First 1).DomainName
    if (-not $TenantMailDomain) { $TenantMailDomain = (Get-AcceptedDomain | Where-Object { $_.DomainName -like '*.onmicrosoft.com' } | Select-Object -First 1).DomainName }
    if (-not $TenantMailDomain) { throw "Could not detect a *.onmicrosoft.com accepted domain; pass -TenantMailDomain" }
    Log "Using $TenantMailDomain for temporary addresses"
}
$input = Import-Csv $InputCsv
if (-not $input) { throw "$InputCsv is empty" }
if (-not ($input[0].PSObject.Properties.Name -contains 'Smtp')) { throw "CSV needs an 'Smtp' column" }
$hasMigrateCol = $input[0].PSObject.Properties.Name -contains 'Migrate'
$wanted = $input | Where-Object { -not $hasMigrateCol -or $_.Migrate -match '^(y|yes|true|1)$' } |
          ForEach-Object { $_.Smtp.Trim().ToLower() } | Where-Object { $_ } | Select-Object -Unique

# Status progression: Pending -> Exported -> Created -> Unsynced -> Removed -> Cutover -> Verified | Failed
$State = @{}
if (Test-Path $StatusFile) { Import-Csv $StatusFile | ForEach-Object { $State[$_.Smtp] = $_ } }
foreach ($smtp in $wanted) {
    if (-not $State[$smtp]) {
        $State[$smtp] = [pscustomobject]@{ Smtp=$smtp; Status='Pending'; Note=''; AdDN=''; OrigDN=''; Batch=''; Updated='' }
    }
}
function Save-State { $State.Values | Sort-Object Smtp | Export-Csv $StatusFile -NoTypeInformation }
function Set-Status($smtp,$status,$note='') {
    $State[$smtp].Status = $status; $State[$smtp].Note = $note; $State[$smtp].Updated = (Get-Date).ToString('s'); Save-State
}

# Validate pending rows once
foreach ($smtp in @($State.Keys | Where-Object { $State[$_].Status -eq 'Pending' })) {
    $g  = Invoke-EXO { Get-DistributionGroup -Identity $smtp -ErrorAction SilentlyContinue }
    $ad = @(Get-ADGroup -Filter "mail -eq '$smtp'" -ErrorAction SilentlyContinue)
    $why = $null
    if (-not $g)                       { $why = 'Not found in EXO' }
    elseif (-not $g.IsDirSynced)       { $why = 'Already cloud-managed' }
    elseif ($ad.Count -ne 1)           { $why = "AD match count = $($ad.Count)" }
    elseif ($g.RecipientTypeDetails -eq 'RoomList') { $why = 'Room list not supported' }
    if ($why) { Set-Status $smtp 'Failed' "Validation: $why"; Log "$smtp skipped: $why" 'WARN' }
    else { $State[$smtp].AdDN = $ad[0].DistinguishedName; $State[$smtp].OrigDN = $ad[0].DistinguishedName }
}
Save-State
Log "Loaded $($wanted.Count) groups from $InputCsv. Pending: $(@($State.Values | Where-Object Status -eq 'Pending').Count)"

# ------------------------------------------------------------------ steps
function Step-Export($smtp) {
    $g = Invoke-EXO { Get-DistributionGroup -Identity $smtp }
    $members = Invoke-EXO { Get-DistributionGroupMember -Identity $smtp -ResultSize Unlimited } |
        Select-Object @{n='Smtp';e={ "$($_.PrimarySmtpAddress)".Trim().ToLower() }},
                      @{n='Guid';e={ "$($_.ExchangeObjectId)" }},
                      @{n='Id';  e={ if ("$($_.PrimarySmtpAddress)".Trim()) { "$($_.PrimarySmtpAddress)".Trim().ToLower() } else { "$($_.ExchangeObjectId)" } }},
                      Name, RecipientTypeDetails
    $sendAs = @(Invoke-EXO { Get-RecipientPermission -Identity $smtp -ErrorAction SilentlyContinue } |
        Where-Object { $_.Trustee -ne 'NT AUTHORITY\SELF' } | Select-Object -Expand Trustee)
    [ordered]@{
        Name=$g.Name; DisplayName=$g.DisplayName; Alias=$g.Alias; PrimarySmtpAddress=$smtp
        EmailAddresses=@($g.EmailAddresses | ForEach-Object { $_.ToString() }); LegacyExchangeDN=$g.LegacyExchangeDN
        GroupType=$(if ($g.RecipientTypeDetails -eq 'MailUniversalSecurityGroup') {'Security'} else {'Distribution'})
        ManagedBy=(Resolve-Smtp $g.ManagedBy); Members=@($members); Description=($g.Description -join ' ')
        HiddenFromAddressListsEnabled=$g.HiddenFromAddressListsEnabled
        RequireSenderAuthenticationEnabled=$g.RequireSenderAuthenticationEnabled
        AcceptMessagesOnlyFromSendersOrMembers=(Resolve-Smtp $g.AcceptMessagesOnlyFromSendersOrMembers)
        RejectMessagesFromSendersOrMembers=(Resolve-Smtp $g.RejectMessagesFromSendersOrMembers)
        ModerationEnabled=$g.ModerationEnabled; ModeratedBy=(Resolve-Smtp $g.ModeratedBy)
        BypassModerationFromSendersOrMembers=(Resolve-Smtp $g.BypassModerationFromSendersOrMembers)
        SendModerationNotifications=$g.SendModerationNotifications.ToString()
        GrantSendOnBehalfTo=(Resolve-Smtp $g.GrantSendOnBehalfTo); SendAsTrustees=$sendAs
        MemberJoinRestriction=$g.MemberJoinRestriction.ToString(); MemberDepartRestriction=$g.MemberDepartRestriction.ToString()
        ReportToManagerEnabled=$g.ReportToManagerEnabled; ReportToOriginatorEnabled=$g.ReportToOriginatorEnabled
        SendOofMessageToOriginatorEnabled=$g.SendOofMessageToOriginatorEnabled
    } | ConvertTo-Json -Depth 5 | Set-Content (ExportFile $smtp) -Encoding UTF8
}

function Step-Create($smtp) {
    $e = Get-Content (ExportFile $smtp) -Raw | ConvertFrom-Json
    $tmp = TmpSmtp $e.Alias
    if (-not (Invoke-EXO { Get-DistributionGroup -Identity $tmp -ErrorAction SilentlyContinue })) {
        $p = @{ Name="$TempPrefix$($e.Name)"; DisplayName="$TempPrefix$($e.DisplayName)"; Alias="$TempPrefix$($e.Alias)"
                PrimarySmtpAddress=$tmp; Type=$e.GroupType
                MemberJoinRestriction=$e.MemberJoinRestriction; MemberDepartRestriction=$e.MemberDepartRestriction }
        $owners = @($e.ManagedBy | Where-Object { $_ -and "$_".Trim() }); if (-not $owners.Count -and $DefaultOwner) { $owners = @($DefaultOwner) }
        if ($owners.Count) { $p.ManagedBy = $owners; $p.CopyOwnerToMember = $false }
        Invoke-EXO { New-DistributionGroup @p } | Out-Null
        Start-Sleep 5
    }
    # Enforce ownership: exactly the on-prem owners (or DefaultOwner). Never the account running this script.
    $owners = @($e.ManagedBy | Where-Object { $_ -and "$_".Trim() }); if (-not $owners.Count -and $DefaultOwner) { $owners = @($DefaultOwner) }
    try {
        if ($owners.Count) { Invoke-EXO { Set-DistributionGroup -Identity $tmp -ManagedBy $owners -BypassSecurityGroupManagerCheck } }
        else               { Invoke-EXO { Set-DistributionGroup -Identity $tmp -ManagedBy $null -BypassSecurityGroupManagerCheck } }
    } catch {
        Log "  Could not set owners on $tmp to [$($owners -join ',')]: $_  (group was ownerless on-prem; pass -DefaultOwner to avoid this)" 'WARN'
    }
    $s = @{ Identity=$tmp; HiddenFromAddressListsEnabled=$true
            RequireSenderAuthenticationEnabled=$e.RequireSenderAuthenticationEnabled; ModerationEnabled=$e.ModerationEnabled
            SendModerationNotifications=$e.SendModerationNotifications; ReportToManagerEnabled=$e.ReportToManagerEnabled
            ReportToOriginatorEnabled=$e.ReportToOriginatorEnabled; SendOofMessageToOriginatorEnabled=$e.SendOofMessageToOriginatorEnabled
            CustomAttribute15="MigratedFrom:$smtp" }
    if ($e.Description) { $s.Description = $e.Description }
    foreach ($k in 'AcceptMessagesOnlyFromSendersOrMembers','RejectMessagesFromSendersOrMembers','ModeratedBy','BypassModerationFromSendersOrMembers','GrantSendOnBehalfTo') {
        $vals = @($e.$k | Where-Object { $_ -and "$_".Trim() })
        if ($vals.Count) { $s[$k] = $vals }
    }
    $s.BypassSecurityGroupManagerCheck = $true
    Invoke-EXO { Set-DistributionGroup @s }
    foreach ($t in $e.SendAsTrustees) {
        try { Invoke-EXO { Add-RecipientPermission -Identity $tmp -Trustee $t -AccessRights SendAs -Confirm:$false } | Out-Null }
        catch { Log "  SendAs $t -> $tmp failed: $_" 'WARN' }
    }
    # Prefer SMTP; fall back to object GUID for members with no email address. Drop anything blank.
    $memberList = @($e.Members | ForEach-Object { if ($_.Id) { $_.Id } elseif ($_.Smtp) { $_.Smtp } else { $_.Guid } } |
                    Where-Object { $_ -and "$_".Trim() } | Select-Object -Unique)
    $skipped = @($e.Members | Where-Object { -not ($_.Id -or $_.Smtp -or $_.Guid) })
    foreach ($m in $skipped) { Log "  Member '$($m.Name)' has no address or id - skipped" 'WARN' }
    if ($memberList.Count) {
        try { Invoke-EXO { Update-DistributionGroupMember -Identity $tmp -Members $memberList -Confirm:$false -BypassSecurityGroupManagerCheck -ErrorAction Stop } }
        catch { Log "  Bulk member set failed on ${tmp}: $_" 'WARN' }

        # Never trust the bulk call: count what actually landed and top up one by one.
        Start-Sleep 3
        $have = @(Invoke-EXO { Get-DistributionGroupMember -Identity $tmp -ResultSize Unlimited } |
                  ForEach-Object { "$($_.PrimarySmtpAddress)".Trim().ToLower(); "$($_.ExchangeObjectId)" } | Where-Object { $_ })
        $todo = @($memberList | Where-Object { $_ -notin $have })
        if ($todo.Count) {
            Log "  $($todo.Count) of $($memberList.Count) members not present after bulk add on $tmp - adding individually" 'WARN'
            foreach ($m in $todo) {
                try { Invoke-EXO { Add-DistributionGroupMember -Identity $tmp -Member $m -BypassSecurityGroupManagerCheck -ErrorAction Stop } }
                catch { if ("$_" -notmatch 'already a member') { Log "  Member $m not added: $_" 'WARN' } }
            }
        }
    }
}

function Invoke-DeltaSync {
    while (Get-ADSyncConnectorRunStatus) { Start-Sleep 15 }
    Start-ADSyncSyncCycle -PolicyType Delta | Out-Null
    Start-Sleep 20
    while (Get-ADSyncConnectorRunStatus) { Start-Sleep 15 }
}

function Step-Unsync($smtps) {
    foreach ($smtp in $smtps) {
        if ($State[$smtp].AdDN -notlike "*$NoSyncOU") {
            Move-ADObject -Identity $State[$smtp].AdDN -TargetPath $NoSyncOU
            $State[$smtp].AdDN = (Get-ADGroup -Filter "mail -eq '$smtp'").DistinguishedName
        }
        Set-Status $smtp 'Unsynced'
    }
    Log "Running delta sync..."
    Invoke-DeltaSync
    Log "Delta sync complete"
}

function Wait-Removed($smtps) {
    $start = Get-Date; $deadline = $start.AddMinutes($DeletionTimeoutMin); $resynced = $false
    $pending = [System.Collections.Generic.List[string]]$smtps
    while ($pending.Count -and (Get-Date) -lt $deadline) {
        foreach ($smtp in @($pending)) {
            $g = Invoke-EXO { Get-DistributionGroup -Identity $smtp -ErrorAction SilentlyContinue }
            if (-not $g -or -not $g.IsDirSynced) { $pending.Remove($smtp) | Out-Null; Set-Status $smtp 'Removed' }
        }
        if (-not $pending.Count) { break }
        if (-not $resynced -and ((Get-Date) - $start).TotalMinutes -ge $ResyncAfterMin) {
            Log "  Still $($pending.Count) pending after $ResyncAfterMin min - running a second delta sync" 'WARN'
            Invoke-DeltaSync; $resynced = $true
        }
        Log "  Waiting for EXO to drop $($pending.Count) synced objects..."; Start-Sleep 60
    }
    return $pending
}

function Step-Cutover($smtp) {
    $e = Get-Content (ExportFile $smtp) -Raw | ConvertFrom-Json
    $tmp = TmpSmtp $e.Alias
    $addr = @($e.EmailAddresses)                                   # originals only; TMP address is dropped here
    if ($e.LegacyExchangeDN) { $addr += "X500:$($e.LegacyExchangeDN)" }
    Invoke-EXO { Set-DistributionGroup -Identity $tmp -Name $e.Name -DisplayName $e.DisplayName -Alias $e.Alias `
        -EmailAddresses $addr -HiddenFromAddressListsEnabled $e.HiddenFromAddressListsEnabled -BypassSecurityGroupManagerCheck }
}

# Re-link a freshly cut-over child into any already-migrated parent that listed it (covers cross-wave nesting)
function Step-Relink($smtps) {
    $parents = @{}
    foreach ($f in Get-ChildItem $ExportDir -Filter *.json) {
        $e = Get-Content $f.FullName -Raw | ConvertFrom-Json
        foreach ($m in $e.Members | Where-Object { $_.RecipientTypeDetails -like '*Group*' -and $_.Smtp }) {
            if (-not $parents[$m.Smtp]) { $parents[$m.Smtp] = @() }
            $parents[$m.Smtp] += $e.PrimarySmtpAddress
        }
    }
    foreach ($child in $smtps) {
        foreach ($parent in @($parents[$child])) {
            $pg = Invoke-EXO { Get-DistributionGroup -Identity $parent -ErrorAction SilentlyContinue }
            if (-not $pg -or $pg.IsDirSynced) { continue }        # parent not migrated yet; nothing to do
            try { Invoke-EXO { Add-DistributionGroupMember -Identity $parent -Member $child -BypassSecurityGroupManagerCheck -ErrorAction Stop }; Log "  Re-linked $child into $parent" }
            catch { if ($_ -notmatch 'already a member') { Log "  Re-link $child -> $parent failed: $_" 'WARN' } }
        }
    }
}

function Step-Verify($smtp) {
    $e = Get-Content (ExportFile $smtp) -Raw | ConvertFrom-Json
    $g = Invoke-EXO { Get-DistributionGroup -Identity $smtp -ErrorAction SilentlyContinue }
    if (-not $g) { return 'Group not found after cutover' }
    if ($g.IsDirSynced) { return 'Still DirSynced' }
    $nowObjs = @(Invoke-EXO { Get-DistributionGroupMember -Identity $smtp -ResultSize Unlimited })
    $now = @($nowObjs | ForEach-Object { "$($_.PrimarySmtpAddress)".Trim().ToLower() }) + @($nowObjs | ForEach-Object { "$($_.ExchangeObjectId)" })
    $expected = @($e.Members | ForEach-Object { if ($_.Id) { $_.Id } elseif ($_.Smtp) { $_.Smtp } else { $_.Guid } } | Where-Object { $_ -and "$_".Trim() })
    $missing = @($expected | Where-Object { $_ -notin $now })
    $x500ok = -not $e.LegacyExchangeDN -or (@($g.EmailAddresses | ForEach-Object { "$_" }) -contains "X500:$($e.LegacyExchangeDN)")
    if (-not $x500ok) { return 'X500 missing' }
    $me = (Get-ConnectionInformation | Where-Object State -eq 'Connected' | Select-Object -First 1).UserPrincipalName
    if ($me -and -not ($e.ManagedBy -contains $me) -and $DefaultOwner -ne $me) {
        $currentOwners = @(Invoke-EXO { Get-DistributionGroup -Identity $smtp } | Select-Object -Expand ManagedBy |
                           ForEach-Object { (Get-Recipient -Identity $_ -ResultSize 1 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Select-Object -First 1).PrimarySmtpAddress } |
                           ForEach-Object { "$_".ToLower() })
        if ($currentOwners -contains $me.ToLower()) { return "Running account ($me) is an owner - not expected" }
    }
    if ($missing.Count) { return "Missing members: $($missing -join ';')" }
    return $null
}

# ------------------------------------------------------------------ main loop
$batchNo = 0
while ($batchNo -lt $MaxBatches) {
    $batch = @($State.Values | Where-Object Status -in 'Pending','Exported','Created','Unsynced','Removed','Cutover' |
              Sort-Object { switch ($_.Status) {'Cutover'{0}'Removed'{1}'Unsynced'{2}'Created'{3}'Exported'{4}default{5}} }, Smtp |
              Select-Object -First $BatchSize)
    if (-not $batch) { Log "Nothing left to migrate in $InputCsv." 'OK'; break }
    $batchNo++; $stamp = "B$(Get-Date -f yyyyMMddHHmm)-$batchNo"
    Log "===== Batch $batchNo ($stamp): $($batch.Count) groups ====="
    $batch | ForEach-Object { $_.Batch = $stamp }

    foreach ($s in $batch) {
        $smtp = $s.Smtp
        try {
            # Self-heal: export file missing but status says it exists (e.g. export folder was cleared)
            if ($s.Status -in 'Exported','Created' -and -not (Test-Path (ExportFile $smtp))) {
                Log "$smtp export file missing - re-exporting" 'WARN'; $s.Status = 'Pending'
            }
            if ($s.Status -eq 'Pending')  { if ($PSCmdlet.ShouldProcess($smtp,'Export')) { Step-Export $smtp; Set-Status $smtp 'Exported' } }
            if ($s.Status -eq 'Exported') { if ($PSCmdlet.ShouldProcess($smtp,'Create TMP group')) { Step-Create $smtp; Set-Status $smtp 'Created' } }
        } catch { Log "$smtp failed at $($s.Status): $_" 'ERROR'; Set-Status $smtp 'Failed' "At $($s.Status): $_" }
    }

    $toUnsync = @($batch | Where-Object Status -eq 'Created' | Select-Object -Expand Smtp)
    if ($toUnsync -and $PSCmdlet.ShouldProcess("$($toUnsync.Count) AD groups",'Move to NoSyncOU + delta sync')) {
        try { Step-Unsync $toUnsync } catch { Log "Unsync/sync failed: $_" 'ERROR' }
    }

    $toWait = @($batch | Where-Object Status -eq 'Unsynced' | Select-Object -Expand Smtp)
    if ($toWait) {
        foreach ($smtp in (Wait-Removed $toWait)) { Log "$smtp not removed from EXO within timeout; re-run to retry" 'WARN' }
    }

    foreach ($s in @($batch | Where-Object Status -eq 'Removed')) {
        try { if ($PSCmdlet.ShouldProcess($s.Smtp,'Cutover')) { Step-Cutover $s.Smtp; Set-Status $s.Smtp 'Cutover'; Log "Cutover $($s.Smtp)" 'OK' } }
        catch { Log "$($s.Smtp) cutover failed: $_" 'ERROR'; Set-Status $s.Smtp 'Failed' "Cutover: $_" }
    }

    $cut = @($batch | Where-Object Status -eq 'Cutover' | Select-Object -Expand Smtp)
    if ($cut) {
        Step-Relink $cut
        foreach ($smtp in $cut) {
            $issue = Step-Verify $smtp
            if ($issue) { Log "$smtp verify: $issue" 'WARN'; Set-Status $smtp 'Failed' "Verify: $issue" }
            else { Set-Status $smtp 'Verified' }
        }
    }
    Log "Batch $batchNo done. $(($State.Values | Group-Object Status | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ')"
}

# ------------------------------------------------------------------ summary
$State.Values | Group-Object Status | Select-Object Name,Count | Format-Table -AutoSize
$failed = @($State.Values | Where-Object Status -eq 'Failed')
if ($failed) { $failed | Select-Object Smtp,Note | Format-Table -AutoSize -Wrap }
Log "Done. Status file: $StatusFile  Log: $LogFile" 'OK'
