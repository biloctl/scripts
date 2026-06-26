<#
.SYNOPSIS
  Zero‐touch upload of this device’s Autopilot hash to Intune via Graph, using JSON.

.DESCRIPTION
  • Hard-codes TenantId/ClientId at top  
  • Pulls Autopilot info in memory  
  • Connects to Graph via SPN + LocalMachine cert  
  • Posts a single JSON payload to create a WindowsAutopilotDeviceIdentity  
  • Tags it “<Tagofyouchoice>”  
#>
# Uses Friendly name of cert. Default is Autopilot_hash_uploader. Change to whatever desired

# ─── 1. Hard-coded values ─────────────────────────────────────────────────────
$TenantId = '<TenantID>'
$ClientId = '<ClientID>'
$GroupTag = '<GroupTag>'

# ─── 2. Install/import modules ───────────────────────────────────────────────
if (-not (Get-Module -ListAvailable Microsoft.Graph)) {
    Install-Module Microsoft.Graph -Force
}
if (-not (Get-Module -ListAvailable WindowsAutopilotIntune)) {
    Install-Module WindowsAutopilotIntune -Force
}
Import-Module Microsoft.Graph, WindowsAutopilotIntune

# ─── 3. Retrieve Autopilot hash ──────────────────────────────────────────────
Write-Host "Fetching Autopilot hash…" -ForegroundColor Cyan
$ap = Get-WindowsAutopilotInfo
if (-not $ap) {
    Throw "Failed to get Autopilot info. Run as Admin."
}

# ─── 4. Load cert from LocalMachine\My ───────────────────────────────────────
$cert = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object FriendlyName -EQ 'Autopilot_hash_uploader'
if (-not $cert) {
    Throw "Cert 'Autopilot_hash_uploader' not found in LocalMachine\My."
}

# ─── 5. Connect to Graph as SPN + cert ──────────────────────────────────────
Write-Host "Connecting to Microsoft Graph…" -ForegroundColor Cyan
Connect-MgGraph `
  -ClientId             $ClientId `
  -TenantId             $TenantId `
  -CertificateThumbprint $cert.Thumbprint `
  -Scopes               DeviceManagementServiceConfig.ReadWrite.All

# ─── 6. Build JSON payload ─────────────────────────────────────────────────
$body = @{
  deviceSerialNumber    = $ap.SerialNumber
  windowsProductKey     = $ap.ProductKeyId
  hardwareIdentifier    = $ap.HardwareHash
  manufacturer          = $ap.Manufacturer
  model                 = $ap.Model
  groupTag              = $GroupTag
} | ConvertTo-Json

# ─── 7. Send POST to create identity ────────────────────────────────────────
Write-Host "Uploading Autopilot record…" -ForegroundColor Cyan
$response = Invoke-MgGraphRequest `
  -Method POST `
  -Uri '/deviceManagement/windowsAutopilotDeviceIdentities' `
  -Body $body `
  -ContentType 'application/json'

# ─── 8. Check the result ────────────────────────────────────────────────────
if ($response.Id) {
  Write-Host "✅ Success! Device ID $($response.Id) created." -ForegroundColor Green
} else {
  Write-Host "❌ Failed to create record:" -ForegroundColor Red
  $response | Format-List
}