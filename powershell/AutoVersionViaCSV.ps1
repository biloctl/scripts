# Import CSV file (assumes it has a column named 'SiteUrl')
$csvPath = "C:\temp\filename.csv"
$sites = Import-Csv -Path $csvPath

# Loop through each site and start the trim job
foreach ($site in $sites) {
    $siteUrl = $site.SiteUrl
    $spSite = Get-SPOSite -Identity $siteUrl

    if ($spSite.EnableAutoExpirationVersionTrim) {
        Write-Host "Automatic Trim Enabled: $siteUrl"
    } else {
        Write-Host "Automatic version trimming is not enabled for site: $siteUrl"
            Set-SPOSite -Identity $siteUrl -EnableAutoExpirationVersionTrim:$true -Confirm:$false
    }
}