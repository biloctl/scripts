#requires -version 5.1
<#
.SYNOPSIS
  Removes the Microsoft Copilot app from Windows and prevents it for new users.
  Falls back to policy disable if Copilot isn't present as an AppX (legacy builds).

.RUN AS
  SYSTEM (Intune Win32 app). Use 64-bit PowerShell.

.LOG
  C:\ProgramData\IntuneScripts\RemoveCopilot\UninstallCopilot.log

.REFS
  - Appx removal (24H2+ standalone app): https://cloudinfra.net/5-ways-to-remove-copilot-app-from-windows-11/
  - Microsoft guidance to remove/prevent Copilot app via uninstall + policy/AppLocker: https://learn.microsoft.com/windows/client-management/manage-windows-copilot#remove-or-prevent-installation-of-the-copilot-app
#>

$ErrorActionPreference = 'Stop'

$LogRoot = 'C:\ProgramData\IntuneScripts\RemoveCopilot'
$LogPath = Join-Path $LogRoot 'UninstallCopilot.log'
New-Item -Path $LogRoot -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

function Write-Log([string]$Message, [string]$Level='INFO') {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "[$ts][$Level] $Message"
    Add-Content -LiteralPath $LogPath -Value $line
    Write-Output $line
}

Write-Log "===== Start Copilot removal (Win32 app) ====="

$Result = [ordered]@{
    OSVersion                  = (Get-CimInstance Win32_OperatingSystem).Version
    AppxFound                  = $false
    AppxPackagesRemoved        = 0
    ProvisionedRemoved         = 0
    PolicyDisabled             = $false
    RebootNeeded               = $false
    Errors                     = @()
}

try {
    $appx = Get-AppxPackage -AllUsers | Where-Object {
        $_.Name -like '*Microsoft.Copilot*' -or $_.Name -like '*Microsoft.Windows.Copilot*'
    }
    if ($appx) { $Result.AppxFound = $true; Write-Log "Detected Copilot AppX: $($appx.PackageFullName -join ', ')" }
    else { Write-Log "No Copilot AppX detected for any user." }

    $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like '*Copilot*' }
    if ($prov) { Write-Log "Detected provisioned Copilot package(s): $($prov.PackageName -join ', ')" }
    else { Write-Log "No provisioned Copilot package found." }
}
catch { $Result.Errors += "Detection failure: $($_.Exception.Message)"; Write-Log "Detection failure: $($_.Exception.Message)" 'ERROR' }

# Remove AppX for all users (24H2+)
if ($Result.AppxFound) {
    foreach ($pkg in $appx) {
        try {
            Write-Log "Removing AppX for all users: $($pkg.PackageFullName)"
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            $Result.AppxPackagesRemoved++
        } catch {
            $Result.Errors += "Failed AppX remove [$($pkg.PackageFullName)]: $($_.Exception.Message)"
            Write-Log "Failed AppX remove [$($pkg.PackageFullName)]: $($_.Exception.Message)" 'ERROR'
        }
    }
}

# Remove provisioned package (prevents install for new profiles)
if ($prov) {
    foreach ($p in $prov) {
        try {
            Write-Log "Removing provisioned package: $($p.PackageName)"
            $rem = Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop
            $Result.ProvisionedRemoved++
            if ($rem.RestartNeeded) { $Result.RebootNeeded = $true; Write-Log "RestartNeeded signaled by provisioning removal." }
        } catch {
            $Result.Errors += "Failed provisioned remove [$($p.PackageName)]: $($_.Exception.Message)"
            Write-Log "Failed provisioned remove [$($p.PackageName)]: $($_.Exception.Message)" 'ERROR'
        }
    }
}

# Fallback: legacy builds without AppX -> enforce policy disable
if (-not $Result.AppxFound -and -not $prov) {
    try {
        $polKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'
        if (-not (Test-Path $polKey)) { New-Item -Path $polKey -Force | Out-Null }
        New-ItemProperty -Path $polKey -Name 'TurnOffWindowsCopilot' -PropertyType DWord -Value 1 -Force | Out-Null
        $Result.PolicyDisabled = $true
        Write-Log "Policy set: TurnOffWindowsCopilot=1 (legacy disable)."
    } catch {
        $Result.Errors += "Failed to set policy: $($_.Exception.Message)"
        Write-Log "Failed to set policy: $($_.Exception.Message)" 'ERROR'
    }
}

# Verify
try {
    $still = Get-AppxPackage -AllUsers | Where-Object {
        $_.Name -like '*Microsoft.Copilot*' -or $_.Name -like '*Microsoft.Windows.Copilot*'
    }
    if ($still) { Write-Log "Post-check: Copilot AppX still present -> $($still.PackageFullName -join ', ')" 'ERROR' }
    else { Write-Log "Post-check: Copilot AppX is NOT present." }
} catch {
    $Result.Errors += "Post-check error: $($_.Exception.Message)"
    Write-Log "Post-check error: $($_.Exception.Message)" 'ERROR'
}

Write-Log ("Summary: " + ($Result | ConvertTo-Json -Depth 5))
if ($Result.RebootNeeded) { Write-Log "A reboot is recommended to finalize provisioned removal." }
Write-Log "===== End Copilot removal ====="
exit 0
