# DL Migration: synced AD distribution groups → cloud-managed Exchange Online

Two PowerShell scripts that convert Entra Connect–synced distribution groups into cloud-managed
Exchange Online distribution groups, in controlled waves, without losing addresses, members,
owners, sender restrictions, or the ability to reply to old mail.

Built and used against: Exchange Server 2016 hybrid, Entra Connect (Azure AD Connect),
`ExchangeOnlineManagement` 3.x, Windows PowerShell 5.1. Run on the Entra Connect server.

## Why this exists

A synced distribution group is read-only in Exchange Online and there is no "convert to cloud"
command. The only path is: capture everything → take the object out of sync scope → let Entra
Connect delete the cloud copy → recreate it cloud-side with the same identity. Doing that by hand
for thousands of groups is error-prone; doing it wrong strands addresses or breaks replies to old
threads (missing `X500:` proxy). These scripts automate the whole sequence and are resumable.

## Flow

```
Export-DLInventory.ps1   → CSV of every synced DL under an AD OU (you edit this to pick a wave)
Migrate-DLs.ps1          → for each group in the CSV, in batches:
   1. export the group from EXO to JSON (members, owners, all proxies, LegacyExchangeDN, settings)
   2. create a hidden TMP- shadow group in EXO with everything populated
   3. move the AD object to a non-synced OU
   4. run a delta sync, wait for EXO to drop the synced copy (auto second sync if slow)
   5. the moment a group drops, rename TMP- to the original name/alias and restore all
      proxy addresses + X500:<old LegacyExchangeDN>
   6. re-link nested memberships into already-migrated parents
   7. verify members and addresses
```

Progress is tracked in `<input>-status.csv`. Kill it any time; re-running the same command resumes
each group at the step it reached.

## Prerequisites

- Domain-joined host with the `ActiveDirectory` and `ExchangeOnlineManagement` (≥ 3.0) modules,
  plus the `ADSync` module (present on the Entra Connect server).
- Run the console as an on-prem account that can move group objects and is in `ADSyncAdmins`.
- When prompted, sign in to Exchange Online with a cloud account holding Exchange Administrator
  (or Recipient Management).
- An OU excluded from Entra Connect's OU filter, in the **same domain** as the groups being
  migrated (cross-domain moves are refused).
- A cloud-only mail user or mail-enabled security group to use as `-DefaultOwner` for groups that
  have no owner on-prem (Exchange Online may refuse to leave a group ownerless). A throwaway
  mail user that you delete afterwards works; the groups simply become ownerless again.

## Usage

```powershell
# 1. Inventory one business unit (read-only)
.\Export-DLInventory.ps1 -SearchBase "OU=Finance,OU=Groups,DC=contoso,DC=com" `
    -OutputCsv C:\DLMigration\finance-dls.csv -WithMemberCounts

# 2. Edit the CSV: put Y in the Migrate column for the rows you want (or delete the rest).
#    Rows with anything in the Note column will be refused until resolved.

# 3. Migrate, 20 at a time
.\Migrate-DLs.ps1 -InputCsv C:\DLMigration\finance-dls.csv `
    -NoSyncOU "OU=DL-Migrated-NoSync,DC=contoso,DC=com" `
    -DefaultOwner dl-placeholder@contoso.com
```

Useful switches: `-WhatIf` (dry run), `-BatchSize`, `-MaxBatches 1` (pilot), `-IncludeSecurityGroups`,
`-DomainController` (write AD moves to the DC Entra Connect imports from), `-TenantMailDomain`
(auto-detected if omitted).

## What is preserved

Primary and all secondary SMTP addresses, `X500:` of the old `LegacyExchangeDN`, display name,
alias, owners, members (including nested groups and members with no email address, by GUID),
`RequireSenderAuthenticationEnabled`, accept/reject sender lists, moderation settings,
Send-As and Send-on-Behalf, join/leave restrictions, hidden-from-GAL, delivery report settings.
`CustomAttribute15` is stamped `MigratedFrom:<address>` on every migrated group.

## Safety checks

The migrate script refuses a row (without touching anything) when:

- the address is not found in EXO, or the EXO object is already cloud-managed
- zero or more than one AD group carries the address (searched forest-wide via Global Catalog)
- the EXO object's primary address differs from the AD group's `mail` — i.e. the address is
  only an **alias** on some other object
- the AD object and EXO object share no SMTP addresses, or their `legacyExchangeDN` differs
- it is a mail-enabled security group (unless `-IncludeSecurityGroups`; the cloud copy has a
  different SID, so anything using the on-prem group for permissions would break)
- it is a room list or dynamic distribution group

The running account is never left as an owner; Verify fails a group if it is.

## Known limitations / gotchas

- **One wave at a time.** Each batch is gated by one delta sync plus Exchange Online's
  forward-sync lag (typically 2–10 min). Budget 5–10 minutes per batch regardless of size.
- **Mail flow gap.** A group's address is unreachable between the synced copy disappearing and
  the TMP rename — usually well under a minute, because the rename happens per group as soon as
  it drops. Run waves off-hours if that matters.
- **Do not open the status CSV in Excel during a run.** Excel locks the file and the script
  can't record progress (it retries and shouts, but still). Copy it or use `Import-Csv | ft`.
- **Freeze on-prem DL changes** for groups in flight; anything changed after export is lost.
- **Relay / on-prem senders.** After migration, on-prem Exchange no longer knows the group.
  Mail from on-prem sources (SMTP relay, on-prem mailboxes) will route out your internet
  connector and arrive as *external* unless on-prem is told to route the domain to Exchange
  Online. See `SMTP-Relay-Hybrid-Routing-Change.md`.
- **Accepted domains must be `InternalRelay` on-prem** for every domain the migrated groups use;
  `Authoritative` domains NDR unknown recipients before routing.
- Keep the AD objects in the NoSync OU for a while as rollback: move back to `OrigDN` (recorded
  in the status file), delete the cloud group, run a delta sync.

## Files

| File | Purpose |
|---|---|
| `Export-DLInventory.ps1` | Read-only inventory of synced DLs under an OU, with flags for anything that will be refused |
| `Migrate-DLs.ps1` | The migration engine; resumable, batch-based |
| `SMTP-Relay-Hybrid-Routing-Change.md` | Companion write-up: making on-prem relay mail to migrated groups arrive as internal |
