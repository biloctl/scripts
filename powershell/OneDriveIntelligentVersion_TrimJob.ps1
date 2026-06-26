# Turns on auto versioning on OneDrives and kicks off trim job
# Get all OneDrive sites
$OneDriveSites = Get-SPOSite -IncludePersonalSite $true -Limit All | Where-Object {$_.Url -like "*-my.sharepoint.com/personal*"}

# Enable auto-expiration version trimming and create trim jobs for each OneDrive site
foreach ($site in $OneDriveSites) {
    # Enable auto-expiration version trimming
    Set-SPOSite -Identity $site.Url -EnableAutoExpirationVersionTrim $true -Confirm:$false

    # Run a version trim batch delete job
      New-SPOSiteFileVersionBatchDeleteJob -Identity $site.Url -Automatic -Confirm:$false 
}