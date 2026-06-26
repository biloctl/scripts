# scripts

A collection of scripts and configuration profiles I've written for administering Microsoft 365, Entra ID / Active Directory, Exchange Online, SharePoint, OneDrive, and Windows/macOS endpoints via Intune. Most are small, single-purpose tools driven by a CSV or a few variables at the top.

All scripts use placeholder values (e.g. `<UPN>`, `<ObjectID>`, `<TenantID>`) that you'll need to fill in before running.

## Repository layout

```
scripts/
├── powershell/      General admin PowerShell (M365 / Entra / AD / Exchange / SharePoint)
└── intune/          Scripts and profiles deployed through Intune
    ├── windows/
    └── macos/
```

---

## `powershell/`

General administration, run interactively (or scheduled) by an admin.

### Identity & Groups
- **AddLocalADMPlatformScript.ps1** — Adds a single Azure AD user to the local Administrators group.
- **AddLocalAdminCloudWKS.ps1** — Adds one or more Azure AD users to the local Administrators group, looping through a list and skipping any already present.
- **Bulk_User_Add_Cloud_SG.ps1** — Bulk-adds users to a cloud (Entra) security group from a CSV of UPNs, using Microsoft Graph.
- **CSV_User_Add_Security_Group.ps1** — Adds users to a cloud security group from a CSV of UPNs via Microsoft Graph, with per-user success/failure output.
- **Export_User_Entire_OU.ps1** — Exports all user UPNs from a given Active Directory OU to a CSV.
- **OnPremADGroupRemoval.ps1** — Removes users from on-prem AD groups based on a CSV mapping of UPN to group.

### Exchange & Mail
- **AddUsertoMultiMailboxPerms.ps1** — Grants a user FullAccess and SendAs permissions across multiple mailboxes listed in a CSV.
- **CSVDistroMemberAdd.ps1** — Creates a new cloud distribution group and adds members to it from a CSV.
- **Mailbox_Size_UPN.ps1** — Reports mailbox size and statistics (item count, last logon, etc.) for users listed in a CSV.
- **OnPremDLConversion.ps1** — Migrates an on-prem distribution list to a cloud Exchange Online group: copies members and owners, then clears the mail/proxy addresses from the old group.

### SharePoint & OneDrive
- **AutoVersionViaCSV.ps1** — Enables auto-expiration version trimming on specific SharePoint sites listed in a CSV.
- **IntelligentVersionTrimJob.ps1** — Enables auto versioning across all SharePoint sites in the tenant and kicks off trim jobs.
- **OneDriveIntelligentVersion_TrimJob.ps1** — Enables auto-expiration version trimming on all OneDrive sites and starts trim jobs.
- **TrimJobViaCSV.ps1** — Kicks off version trim jobs on SharePoint sites listed in a CSV (where auto-trimming is already enabled).
- **Restrict_Copilot_From_SharePoint.ps1** — Restricts org-wide search discoverability (limiting Copilot exposure) on SharePoint sites listed in a CSV.

### Endpoint
- **HP_Debloater.ps1** — Removes HP and Microsoft preinstalled bloatware from Windows devices; intended to run during an Autopilot/provisioning process.

---

## `intune/windows/`

Written to run under Intune (Win32 app install/detect, platform scripts, remediations). Most run as SYSTEM in 64-bit PowerShell.

- **Install-CopilotRemoval.ps1** — Removes the Microsoft Copilot app from Windows and prevents it for new users, falling back to a policy disable on legacy builds. Logs to `C:\ProgramData\IntuneScripts\RemoveCopilot\`.
- **Detect-CopilotRemoved.ps1** — Detection script that reports success when Copilot is absent (no AppX, no provisioned package) or disabled by policy.
- **SetBackground.ps1** — Sets the desktop wallpaper via the registry and drops a marker file so deployment can be detected.
- **Background_Detection_Script.ps1** — Detection script that checks whether the wallpaper file is present.
- **UninstallLockscreen.ps1** — Removes the lock-screen wallpaper file.
- **uninstall-githubdesktop.ps1** — Uninstalls GitHub Desktop (per-user Squirrel install and/or MSI) and removes desktop shortcuts. *(Note: helper functions are defined but the main calling block is not yet wired up.)*
- **Upload-AutopilotHash.ps1** — Zero-touch upload of a device's Autopilot hardware hash to Intune via Microsoft Graph, authenticating as a service principal with a LocalMachine certificate and tagging the device with a group tag. Requires the `WindowsAutopilotIntune` module and an app registration with `DeviceManagementServiceConfig.ReadWrite.All`.

## `intune/macos/`

Shell scripts and `.mobileconfig` configuration profiles for macOS endpoints.

### Scripts
- **DeviceRename.sh** — Renames the Mac (ComputerName, LocalHostName, HostName) to a prefix plus the hardware serial number.
- **LocationServices.sh** — Enables macOS Location Services by writing the locationd preference (generic and UUID-scoped keys), fixing ownership, and restarting locationd.
- **MacLocationOn.sh** — Identical to LocationServices.sh (duplicate; enables Location Services).
- **promot-to-admin.sh** — Promotes the currently logged-in console user to the local admin group, with checks for valid user and existing membership.
- **QualysActivation.zsh** — Activates the Qualys Cloud Agent using an ActivationId and CustomerId, handling both the standard and app-bundle install paths.

### Profiles
- **pppcFullDiskAccess.mobileconfig** — PPPC (TCC) profile granting OneDrive Full Disk Access, matched to Microsoft's published OneDrive code-signing identity.
- **SilentKFMOneDrive.mobileconfig** — OneDrive Known Folder Move profile: silent opt-in for the tenant, blocks opt-out, enables Files On-Demand, and disables personal sync.

---

## Prerequisites

Depending on which script you run, you'll need one or more of the following PowerShell modules installed:

- **Microsoft.Graph** — for the Graph-based group/user scripts
- **ExchangeOnlineManagement** — for the Exchange Online / distribution group scripts
- **Microsoft.Online.SharePoint.PowerShell** — for the SharePoint and OneDrive scripts
- **ActiveDirectory** (RSAT) — for the on-prem AD scripts
- **WindowsAutopilotIntune** — for the Autopilot hash upload script

Most scripts connect with a `Connect-*` cmdlet at the top and will prompt for sign-in. The Intune scripts generally assume they're running as SYSTEM via the Intune Management Extension.

## Notes

Provided as-is, with no warranty. Review each script and test in a non-production environment before running against live data.