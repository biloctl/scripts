# This script enables auto version on sharepoint sites and then kicks off a trim job
# Check if script is running in PowerShell 7
if ($psversionTable.PSVersion.major -eq 7) {
    Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell
}

# Connect to SharePoint Online
$spAdminUrl = "https://<your-tenant>-admin.sharepoint.com"
Connect-SPOService -Url $spAdminUrl

# Get all SharePoint Sites
$spoSites = Get-SPOSite -Limit All

# Process each site
$spoSites | ForEach-Object{
    $site = $_
    Write-Host "Creating cleanup job for site: $($site.Url)"
    
    # Check if Version History Limits is enabled for each site
    if ($null -eq (Get-SPOSite -Identity $site.Url).EnableAutoExpirationVersionTrim) 
    {
        # Enable Version History Limits
        Set-SPOSite -Identity $site.Url -EnableAutoExpirationVersionTrim:$true -Confirm:$false
    
        # Create a batch to trim versions based on the automatic logic
        try {
            New-SPOSiteFileVersionBatchDeleteJob -Identity $site.Url -Automatic -Confirm:$false 
            Write-Host "Batch trim job created for site: $($site.Url)" -ForegroundColor Green
        } catch {
            Write-Host "Unable to create job for site: $($site.Url)"
            Write-Host $_.Exception.Message
        }
    }else{
        Write-Host "Version History Limits already enabled for site: $($site.Url)" -ForegroundColor Cyan
    }
}

# Disconnect from SharePoint Online
Disconnect-SPOService