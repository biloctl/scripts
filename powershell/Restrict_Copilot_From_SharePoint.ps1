# How CSV Should be laid out with SiteURL being the column header
# SiteURL
# https://yourtenant.sharepoint.com/sites/HR
# https://yourtenant.sharepoint.com/sites/Finance

$CSV = "c:\temp\publicsites.csv"
$TenantURL = "https://<name>-admin.sharepoint.com"
# Connect to SharePoint Online
Connect-SPOService -Url $TenantURL

# Import CSV and apply restriction to each site
Import-Csv -Path $CSV | ForEach-Object {
    $siteUrl = $_.SiteURL
    Write-Host "Restricting content discoverability for site: $siteUrl"
    Set-SPOSite -Identity $siteUrl -RestrictContentOrgWideSearch $true
}