# This script kicks off a trim job on sharepoint sites
# Import CSV file (assumes it has a column named 'SiteUrl')
$csvPath = "C:\temp\filename.csv"
$sites = Import-Csv -Path $csvPath

# Loop through each site and start the trim job
foreach ($site in $sites) {
    $siteUrl = $site.SiteUrl
    $spSite = Get-SPOSite -Identity $siteUrl

    if ($spSite.EnableAutoExpirationVersionTrim) {
        Write-Host "Starting trim job for site: $siteUrl"
          New-SPOSiteFileVersionBatchDeleteJob -Identity $siteUrl -Automatic -Confirm:$false
    } else {
        Write-Host "Automatic version trimming is not enabled for site: $siteUrl"
    }
}
