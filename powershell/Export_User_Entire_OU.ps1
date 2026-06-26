# Export all users' UPN from OU. No header in csv

# Set your OU distinguished name and output path
$OU = '<DN of OU>'
$OutCsv = 'C:\Temp\OU-UPNs.csv'



# Export UPNs only (no header)
Get-ADUser -SearchBase $OU `
           -LDAPFilter '(&(objectCategory=person)(objectClass=user))' `
           -Properties UserPrincipalName `
           -ResultSetSize $null |
    Select-Object -ExpandProperty UserPrincipalName |
    Set-Content -Path $OutCsv -Encoding UTF8