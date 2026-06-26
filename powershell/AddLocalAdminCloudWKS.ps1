<# 
.SYNOPSIS
  Adds one or more AzureAD users to the local Administrators group.

.DESCRIPTION
  Loops through the list of user UPNs and ensures each is a member 
  of the built-in Administrators group. Skips any already present.

.PARAMETER Users
  Array of AzureAD user UPNs, e.g. "john.doe@contoso.com".

.EXAMPLE
  .\Add-AzureADUserToLocalAdmins.ps1 -Users @("alice@contoso.com","bob@contoso.com")
#>

Param(
    [Parameter(Mandatory=$true)]
    [string[]]$Users
)

$GroupName = "Administrators"

foreach ($upn in $Users) {
    # Build the full member name for AzureAD accounts
    $memberName = "AzureAD\$upn"

    # Add user/s to local admin group
    Add-LocalGroupMember -Group $GroupName -Member $memberName
}