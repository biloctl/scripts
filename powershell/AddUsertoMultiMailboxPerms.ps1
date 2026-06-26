#CSV needs header name "mailboxname"


$UPN = "<UPN>"
Import-Csv -Path "C:\path\to\permissions.csv" | ForEach-Object {
            Add-MailboxPermission -Identity $_.mailboxname -User $UPN -AccessRights FullAccess -InheritanceType All -AutoMapping $true
            Add-RecipientPermission $_.mailboxname -Trustee $UPN -AccessRights SendAs -Confirm:$false
        }




#OR

#If you want to do multiple or different users use UPN head and list different UPNs

Import-Csv -Path "C:\path\to\permissions.csv" | ForEach-Object {
            Add-MailboxPermission -Identity $_.mailboxname -User $_.UPN -AccessRights FullAccess -InheritanceType All -AutoMapping $true
            Add-RecipientPermission $_.mailboxname -Trustee $_.UPN -AccessRights SendAs -Confirm:$false
        }