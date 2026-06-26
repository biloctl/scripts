# scripts

A collection of PowerShell scripts I've written for day-to-day administration of Microsoft 365, Entra ID / Active Directory, Exchange Online, SharePoint, OneDrive, and Windows endpoints. Most are small, single-purpose tools driven by a CSV or a few variables at the top.

All scripts use placeholder values (e.g. `<UPN>`, `<ObjectID>`, `<your-tenant>`) that you'll need to fill in before running.

## Scripts

### Identity & Groups
- **powershell/AddLocalADMPlatformScript.ps1** — Adds a single Azure AD user to the local Administrators group.
- **powershell/AddLocalAdminCloudWKS.ps1** — Adds one or more Azure AD users to the local Administrators group, looping through a list and skipping any already present.
- **powershell/Bulk_User_Add_Cloud_SG.ps1** — Bulk-adds users to a cloud (Entra) security group from a CSV of UPNs, using Microsoft Graph.
- **powershell/CSV_User_Add_Security_Group.ps1** — Adds users to a cloud security group from a CSV of UPNs via Microsoft Graph, with per-user success/failure output.
- **powershell/Export_User_Entire_OU.ps1** — Exports all user UPNs from a given Active Directory OU to a CSV.
- **powershell/OnPremADGroupRemoval.ps1** — Removes users from on-prem AD groups based on a CSV mapping of UPN to group.

### Exchange & Mail
- **powershell/AddUsertoMultiMailboxPerms.ps1** — Grants a user FullAccess and SendAs permissions across multiple mailboxes listed in a CSV.
- **powershell/CSVDistroMemberAdd.ps1** — Creates a new cloud distribution group and adds members to it from a CSV.
- **powershell/Mailbox_Size_UPN.ps1** — Reports mailbox size and statistics (item count, last logon, etc.) for users listed in a CSV.
- **powershell/OnPremDLConversion.ps1** — Migrates an on-prem distribution list to a cloud Exchange Online group: copies members and owners, then clears the mail/proxy addresses from the old group.

### SharePoint & OneDrive
- **powershell/AutoVersionViaCSV.ps1** — Enables auto-expiration version trimming on specific SharePoint sites listed in a CSV.
- **powershell/IntelligentVersionTrimJob.ps1** — Enables auto versioning across all SharePoint sites in the tenant and kicks off trim jobs.
- **powershell/OneDriveIntelligentVersion_TrimJob.ps1** — Enables auto-expiration version trimming on all OneDrive sites and starts trim jobs.
- **powershell/TrimJobViaCSV.ps1** — Kicks off version trim jobs on SharePoint sites listed in a CSV (where auto-trimming is already enabled).
- **powershell/Restrict_Copilot_From_SharePoint.ps1** — Restricts org-wide search discoverability (limiting Copilot exposure) on SharePoint sites listed in a CSV.

### Endpoint / Device
- **powershell/HP_Debloater.ps1** — Removes HP and Microsoft preinstalled bloatware from Windows endpoints; intended to run during an Autopilot/provisioning process.

## Prerequisites

Depending on which script you run, you'll need one or more of the following PowerShell modules installed:

- **Microsoft.Graph** — for the Graph-based group/user scripts
- **ExchangeOnlineManagement** — for the Exchange Online / distribution group scripts
- **Microsoft.Online.SharePoint.PowerShell** — for the SharePoint and OneDrive scripts
- **ActiveDirectory** (RSAT) — for the on-prem AD scripts

Most scripts connect with a `Connect-*` cmdlet at the top and will prompt for sign-in.

## Notes

Provided as-is, with no warranty. Review each script and test in a non-production environment before running against live data.
