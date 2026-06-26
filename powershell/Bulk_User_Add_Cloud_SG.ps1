# Add user to cloud SG via CSV with header name UserPrincipalName
Connect-MgGraph -Scopes "Group.ReadWrite.All"
# Import CSV file containing UPNs
$users = Import-Csv $outputPath
# Find security group object ID and enter below
$groupID = "<objectID>"

# Loop through each user and add to the group
foreach ($user in $users) {
    $upn = $user.UserPrincipalName
    $userObj = Get-MgUser -UserId $upn
    if ($userObj) {
        New-MgGroupMember -GroupId $groupID -DirectoryObjectId $userObj.Id
        Write-Host "Added $upn to group"
    } else {
        Write-Host "User $upn not found"
    }
}