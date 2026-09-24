<#
.SYNOPSIS
    Step 1 of 2 - Export an inventory of synced distribution groups under an AD OU to CSV.

.DESCRIPTION
    Read-only. Enumerates mail-enabled groups in AD under -SearchBase, looks each one up in Exchange Online,
    and writes a CSV you edit by hand to decide what gets migrated (then feed to Migrate-DLs.ps1).
    Columns: Migrate, Smtp, DisplayName, Alias, Type, MemberCount, Owners, HiddenFromGAL, Moderated,
             RestrictedSenders, AdOU, Note
    Set Migrate = Y on the rows you want, or delete the rows you don't.

.EXAMPLE
    .\Export-DLInventory.ps1 -SearchBase "OU=Finance,OU=Groups,DC=contoso,DC=com" `
        -OutputCsv C:\DLMigration\finance-dls.csv -WithMemberCounts

    Signs in interactively. Add -UserPrincipalName you@contoso.com to pre-fill the account.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SearchBase,          # AD OU to enumerate (includes sub-OUs)
    [string]$OutputCsv = "C:\DLMigration\dls-$(Get-Date -f yyyyMMdd-HHmm).csv",
    [string]$UserPrincipalName,                          # optional, for interactive sign-in
    [switch]$WithMemberCounts                            # adds one EXO call per group
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path (Split-Path $OutputCsv) | Out-Null
$exo = Get-Module ExchangeOnlineManagement -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if (-not $exo)                       { throw "ExchangeOnlineManagement module not found. Run: Install-Module ExchangeOnlineManagement -Scope AllUsers -Force" }
if ($exo.Version -lt [version]'3.0') { throw "ExchangeOnlineManagement $($exo.Version) is too old (need 3.0+). Run: Update-Module ExchangeOnlineManagement -Force" }
Import-Module ExchangeOnlineManagement -MinimumVersion 3.0
Import-Module ActiveDirectory
if (-not (Get-ConnectionInformation | Where-Object State -eq 'Connected')) {
    if ($UserPrincipalName) { Connect-ExchangeOnline -UserPrincipalName $UserPrincipalName -ShowBanner:$false }
    else                    { Connect-ExchangeOnline -ShowBanner:$false }
}

Write-Host "Enumerating mail-enabled groups under $SearchBase ..."
$Domain = (($SearchBase -split ',DC=',2)[1] -replace ',DC=','.')
$adGroups = Get-ADGroup -Server $Domain -SearchBase $SearchBase -SearchScope Subtree -Filter "mail -like '*'" -Properties mail,DistinguishedName
Write-Host "Found $($adGroups.Count) in AD. Looking up in Exchange Online..."

$i = 0
$rows = foreach ($ad in $adGroups) {
    $i++; if ($i % 50 -eq 0) { Write-Host "  $i / $($adGroups.Count)" }
    $smtp = $ad.mail.ToLower()
    $note = @()
    $g = Get-DistributionGroup -Filter "EmailAddresses -eq 'smtp:$smtp'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $g) {
        $g = Get-DynamicDistributionGroup -Filter "EmailAddresses -eq 'smtp:$smtp'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($g) { $note += 'DYNAMIC DL - not supported' } else { $note += 'NOT FOUND IN EXO' }
    }
    elseif (-not $g.IsDirSynced)                     { $note += 'Already cloud-managed' }
    if ($g -and $g.RecipientTypeDetails -eq 'RoomList') { $note += 'Room list' }
    # The EXO object must be THIS AD group, not another object that carries this address as an alias
    if ($g -and "$($g.PrimarySmtpAddress)".ToLower() -ne $smtp) { $note += "EXO MATCH IS A DIFFERENT OBJECT (primary $($g.PrimarySmtpAddress), name '$($g.Name)')" }
    if ($g -and $g.RecipientTypeDetails -eq 'MailUniversalSecurityGroup') { $note += 'MAIL-ENABLED SECURITY GROUP - check for permissions use before migrating' }

    $count = ''
    if ($WithMemberCounts -and $g -and -not $note) {
        try { $count = @(Get-DistributionGroupMember -Identity $smtp -ResultSize Unlimited -ErrorAction Stop).Count }
        catch { $count = 'ERR' }
    }

    [pscustomobject]@{
        Migrate           = ''
        Smtp              = $smtp
        DisplayName       = if ($g) { $g.DisplayName } else { $ad.Name }
        Alias             = if ($g) { $g.Alias } else { '' }
        Type              = if ($g.RecipientTypeDetails -eq 'MailUniversalSecurityGroup') {'Security'} elseif ($g) {'Distribution'} else {''}
        MemberCount       = $count
        Owners            = if ($g) { (($g.ManagedBy | ForEach-Object { "$_" }) -join ';') } else { '' }
        HiddenFromGAL     = if ($g) { $g.HiddenFromAddressListsEnabled } else { '' }
        Moderated         = if ($g) { $g.ModerationEnabled } else { '' }
        RestrictedSenders = if ($g) { ($g.AcceptMessagesOnlyFromSendersOrMembers.Count -gt 0) } else { '' }
        AdDomain          = $Domain
        AdOU              = ($ad.DistinguishedName -split ',',2)[1]
        Note              = ($note -join '; ')
    }
}

$rows | Sort-Object AdOU, Smtp | Export-Csv $OutputCsv -NoTypeInformation -Encoding UTF8
Write-Host "`nWrote $($rows.Count) rows to $OutputCsv" -ForegroundColor Green
Write-Host "Ready to migrate: $(@($rows | Where-Object { -not $_.Note }).Count)   Flagged (see Note): $(@($rows | Where-Object Note).Count)" -ForegroundColor Yellow
