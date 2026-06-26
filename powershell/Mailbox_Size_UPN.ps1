#This script gets the mailbox size of users from a CSV
# Import the CSV file
$users = Import-Csv -Path "C:\temp\users.csv"

# Create an array to store results
$mailboxSizes = @()

foreach ($user in $users) {
    $mailbox = Get-MailboxStatistics -Identity $user.UserPrincipalName
    $mailboxSizes += [PSCustomObject]@{
        UserPrincipalName = $user.UserPrincipalName
        DisplayName       = $mailbox.DisplayName
        TotalItemSize     = $mailbox.TotalItemSize.ToString()
        ItemCount         = $mailbox.ItemCount
        LastLogonTime     = $mailbox.LastLogonTime
    }
}

# Export results to CSV
$mailboxSizes | Export-Csv -Path "C:\temp\MailboxSizes1.csv" -NoTypeInformation