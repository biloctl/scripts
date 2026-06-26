$upn = "<UPN>"
$GroupName = "Administrators"
$memberName = "AzureAD\$upn"


Add-LocalGroupMember -Group $GroupName -Member $memberName