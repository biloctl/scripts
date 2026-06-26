# Use this script to add users to a cloud security group using a CSV with UPNs. Currently set up to not use a header in csv

# Install module if needed
# Install-Module Microsoft.Graph -Scope AllUsers

Connect-MgGraph -Scopes "Group.ReadWrite.All","User.Read.All"
#Select-MgProfile -Name "v1.0"

# ==== Variables ====
$GroupId = "<ObjectID>"   # Replace with your group ObjectId
$CsvPath = "C:\Temp\OU-UPNs.csv"                   # One UPN per line or CSV with header

# ==== Load UPNs ====
$upns = Get-Content $CsvPath   # If CSV has header, use: (Import-Csv $CsvPath).UPN

# ==== Add members ====
foreach ($upn in $upns) {
    try {
        $user = Get-MgUser -UserId $upn -ErrorAction Stop
        New-MgGroupMemberByRef -GroupId $GroupId -BodyParameter @{
            '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
        }
        Write-Host "Added $upn"
    } catch {
        Write-Warning "Failed for $($upn): $($_.Exception.Message)"
    }
}
