# Script creates a new cloud distribution group
# Adds members via a csv. Header should be labelled  UserPrincipalName

$GroupName = "<Desired DL Name>"
$GroupEmail = "<DesiredEmail>"
$inputpath = "C:\temp\names.csv"


Connect-ExchangeOnline
Write-Output "Creating New Group" 
#Create new group  
New-DistributionGroup -Name $GroupName -PrimarySmtpAddress $GroupEmail

#Add members to new group
Write-Output "Adding Members to New Group" 
import-csv $inputPath | foreach {Add-DistributionGroupMember -Identity $GroupEmail -Member $_.UserPrincipalName -Confirm:$false -ErrorAction SilentlyContinue}