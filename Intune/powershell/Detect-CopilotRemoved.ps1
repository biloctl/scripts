# Detects "Removed/Blocked" state:
#  - No Copilot AppX for any user
#  - No provisioned Copilot package
#  - OR (fallback) policy TurnOffWindowsCopilot=1 present

try {
    $appx = Get-AppxPackage -AllUsers | Where-Object {
        $_.Name -like '*Microsoft.Copilot*' -or $_.Name -like '*Microsoft.Windows.Copilot*'
    }
} catch { $appx = @() }

try {
    $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like '*Copilot*' }
} catch { $prov = @() }

$policyDisabled = $false
try {
    $val = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -ErrorAction Stop
    if ($val -eq 1) { $policyDisabled = $true }
} catch { }

# Success if Copilot is gone (no AppX + no provisioned), OR policy disabled as fallback
if ( ($appx.Count -eq 0 -and $prov.Count -eq 0) -or $policyDisabled ) {
    Write-Output "Copilot removal/disable detected"
    exit 0
}

# Not detected
exit 1