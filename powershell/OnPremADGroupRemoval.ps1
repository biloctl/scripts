#Input file path to csv file
#Copy and paste table from ticket into Excel. Change email column to UPN and security group column to Group. Other columns can be deleted.




$csvPath = "<FILE_PATH>"

#Import CSV data is being taken from
$csvData = Import-Csv -Path $csvPath

#Creates variables to take and input data
foreach ($entry in $csvData) {
	$userUPN = $entry.'UPN'
	$adGroup = $entry.'Group'
	$user = Get-ADUser -Filter {UserPrincipalName -eq $userUPN}


	#If the user exists in AD, remove the user from the group in the column next to their names. Write failed to remove if issue occurs or user is not in group
	if ($user) {
		try {
			Remove-ADGroupMember -Identity $adGroup -Members $user.SamAccountName -Confirm:$false
			Write-Output "Removed $($user.SamAccountName) from $adGroup"
		} catch {
			Write-Error "Failed to remove $($user.SamAccountName) from $adGroup"
		}
	
	#If no user with the UPN in csv exists, tell no user exists
	} else {
		Write-Error "User with UPN $userUPN not found in AD"
	}
}
