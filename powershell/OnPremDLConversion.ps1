#INSTRUCTIONS
# Last line removes SMTP from old distro. This removes it from EAC and frees up email on next AD sync with Azure

#Group ID for the group that you want to migrate to EntraID
$groupId = "<Entra Object ID>"
$onpremDL = "<AD Group Name (Pre Windows 2000)>"

#Connect to Graph to get all the members from the group
Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All" -ContextScope Process

#Get Group Name, email and save it to create the new group 
Write-Output "Getting Group information"
$Group = Get-MgGroup -GroupId $groupId
$GroupName = $Group.DisplayName+'C'
$GroupEmail = 'Cloud'+$Group.Mail
$outputPath = "C:\temp\"+$GroupName+".csv"
$outputPath2 = "C:\temp\$GroupName+Owners.csv"


# Fetch all members of the group
Write-Output "Getting All Group Members"
$allMembers = Get-MgGroupMember -GroupId $groupId -All

# Initialize a List to store member information
$Report = [System.Collections.Generic.List[Object]]::new()

# Loop through each member, get detailed user info, and add it to the List
foreach ($member in $allMembers) {
    $user = Get-MgUser -UserId $member.Id
    $ReportLine = [PSCustomObject]@{
        Id                = $user.Id
        DisplayName       = $user.DisplayName
        UserPrincipalName = $user.UserPrincipalName
    }
    $Report.Add($ReportLine)
}

# Export report to CSV file
$Report | Export-Csv -Path $outputPath -NoTypeInformation -Encoding utf8


# Connect to exchange online
Connect-ExchangeOnline
Write-Output "Creating New Group" 
#Create new group remmeber this is a copy of the on-premise group 
New-DistributionGroup -Name $GroupName -PrimarySmtpAddress $GroupEmail

#Add members exported from the on-prem DL
Write-Output "Adding Members to New Group" 
import-csv $outputPath | foreach {Add-DistributionGroupMember -Identity $GroupEmail -Member $_.UserPrincipalName -Confirm:$false -ErrorAction SilentlyContinue}

# Get on-prem DL owners and export
Write-Output "Getting Group Owners"
(Get-DistributionGroup -Identity $groupid ).ManagedBy | ForEach-Object {
   Get-Recipient -Identity $_ | Select-Object DisplayName, GUID
} | Export-Csv -Path $outputpath2 -NoTypeInformation

#Add owners exported from the on-prem DL 
Write-Output "Adding Owners to New Group" 
Import-Csv $outputPath2 | foreach{Set-DistributionGroup -Identity $GroupEmail -Managedby $_.GUID}

#Remove Mail and Proxy Address of Old/On-Prem Group
Write-Output "Removing Email from Old Group"
Set-ADGroup -Identity $onpremDL -Clear proxyAddresses, mail
