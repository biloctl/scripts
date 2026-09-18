# Relay mail to cloud-managed distribution groups arrives as "external" in Exchange hybrid

Companion to the DL migration scripts. Describes a routing problem that appears the moment a
distribution group moves from on-prem to cloud-managed, and the three on-prem send connector
changes that fix it. Placeholder names throughout (`contoso.com`, `EX01`, etc.).

**Environment:** Exchange Server 2016 hybrid (two mailbox servers), Entra Connect, Exchange Online
tenant `contoso.onmicrosoft.com`. Application SMTP relay is a receive connector on the on-prem
Exchange servers (`AuthMechanism: ExternalAuthoritative`, scoped to internal ranges). Internet mail
leaves via a third-party gateway (smart host).

---

## 1. Symptom

After a distribution group is migrated to cloud-managed, mail relayed to it from on-prem
applications:

- is rejected if the group accepts internal senders only
  (`550 5.7.133 RESOLVER.RST.SenderNotAuthenticatedForGroup`)
- gets the `[EXTERNAL]` subject tag
- shows `X-MS-Exchange-Organization-AuthAs: Anonymous` and
  `X-MS-Exchange-CrossTenant-FromEntityHeader: Internet` in headers

Mail from cloud mailboxes to the same group works. Mail to groups that still exist on-prem works.

## 2. Root cause

On-prem Exchange routes on the **recipient**. While the group existed on-prem, Exchange resolved it
and expanded it locally. Once the object is gone, Exchange has nothing to resolve
`group@contoso.com` against, so it falls through to the `*` send connector and hands the message
to the internet gateway. The gateway delivers it to the tenant's public MX like any other internet
mail, and Exchange Online treats it accordingly.

The hybrid send connector never gets selected because the Hybrid Configuration Wizard only gives it
the `contoso.mail.onmicrosoft.com` address space — it assumes every cloud recipient has an on-prem
object with a `targetAddress`, which is no longer true for migrated groups.

Diagnosis from the header: the hop before `...mail.protection.outlook.com` is the internet gateway,
not your own server.

```
Received: from gateway.example.net (203.0.113.10) by XX.mail.protection.outlook.com ...
X-MS-Exchange-CrossTenant-FromEntityHeader: Internet
X-MS-Exchange-Organization-AuthAs: Anonymous
```

On-prem tracking log confirms the connector chosen:

```powershell
Get-MessageTrackingLog -Server EX01 -Recipients group@contoso.com -Start (Get-Date).AddMinutes(-30) -EventId SENDEXTERNAL |
    fl Timestamp, ConnectorId
```

## 3. Fix: three changes to the hybrid send connector

All on the on-prem Exchange Management Shell. Each takes a few minutes to propagate to transport;
a test sent immediately after a change will use the old configuration.

### 3.1 Pin the connector to Exchange Online (smart host)

If the connector has no smart host, it routes by DNS — it looks up the **recipient domain's** MX.
For `contoso.com` that is your public MX (the internet gateway), which the hybrid connector then
tries to reach with strict TLS validation and fails (`454 4.7.5 Certificate validation failure`).
Mail queues. Pinning a smart host makes the connector always deliver to Exchange Online.

```powershell
Resolve-DnsName contoso.mail.onmicrosoft.com -Type MX | Select NameExchange
# → contoso-mail-onmicrosoft-com.mail.protection.outlook.com

Set-SendConnector "Outbound to Office 365" `
    -SmartHosts "contoso-mail-onmicrosoft-com.mail.protection.outlook.com" -DNSRoutingEnabled $false
```

Smart host authentication stays `None`; Exchange Online identifies your server by the TLS
certificate (connector `Fqdn` / `TlsCertificateName`, `TlsDomain = mail.protection.outlook.com`).
The HCW normally sets this; check whether yours has it before assuming.

### 3.2 Preserve authentication headers (`CloudServicesMailEnabled`)

With this `False`, on-prem strips its `X-MS-Exchange-Organization-*` headers before handing off, so
Exchange Online never learns the message was authenticated (by the externally-secured relay
connector) and still rejects internal-only groups. Must be `True` on the on-prem send connector
**and** on the tenant's inbound connector (`Get-InboundConnector | fl CloudServicesMailEnabled`).

```powershell
Set-SendConnector "Outbound to Office 365" -CloudServicesMailEnabled $true
```

### 3.3 Route your accepted domains over the connector

```powershell
Set-SendConnector "Outbound to Office 365" -AddressSpaces @{Add="SMTP:contoso.com;1","SMTP:fabrikam.com;1"}
```

Exchange picks the most specific address-space match, so `contoso.com` beats `*` regardless of the
cost value (`;1`). Recipients on-prem *can* resolve (mailboxes, remote mailboxes, contacts, on-prem
groups) are unaffected — connector selection only happens for unresolved recipients.

### 3.4 Resulting state

| Property | Value |
|---|---|
| AddressSpaces | `contoso.mail.onmicrosoft.com;1`, `contoso.com;1`, `fabrikam.com;1` |
| SmartHosts | `contoso-mail-onmicrosoft-com.mail.protection.outlook.com` |
| DNSRoutingEnabled | `False` |
| CloudServicesMailEnabled | `True` |
| RequireTLS / TlsAuthLevel / TlsDomain | `True` / `DomainValidation` / `mail.protection.outlook.com` |

## 4. Accepted domains must be InternalRelay

For the address space to have any effect the domain must be `InternalRelay` on-prem.

- **InternalRelay** — unresolved recipients are forwarded to the matching send connector.
- **Authoritative** — unresolved recipients are NDR'd (`550 5.1.10`) *before* routing.
  Migrated groups in an Authoritative domain bounce no matter what the connectors say.

```powershell
Get-AcceptedDomain | fl DomainName, DomainType
Set-AcceptedDomain fabrikam.com -DomainType InternalRelay      # if needed
```

Effect of the change: mail to a nonexistent address in that domain is relayed to Exchange Online
and NDR'd there instead of on-prem. Same outcome for the sender.

`contoso.mail.onmicrosoft.com` being `Authoritative` is normal (HCW default) — it is only ever
reached via `targetAddress`, never by unresolved recipients.

## 5. Verification

On-prem — message took the hybrid connector:

```powershell
Get-MessageTrackingLog -Server EX01 -Recipients group@contoso.com -Start (Get-Date).AddMinutes(-15) -EventId SENDEXTERNAL |
    fl Timestamp, ConnectorId, RecipientStatus, MessageId
# ConnectorId : Outbound to Office 365     RecipientStatus : {250 2.1.5 Recipient OK}
```

Exchange Online — group accepted it (`Get-MessageTrace` v1 is retired; use V2):

```powershell
Get-MessageTraceV2 -MessageId "<id>" -StartDate (Get-Date).AddHours(-1) -EndDate (Get-Date) |
    Get-MessageTraceDetailV2 | ft Date, Event, Detail
# Expect: Expanded / Deliver
```

Header of a delivered message:

| Header | Before | After |
|---|---|---|
| `Received: from … by …mail.protection.outlook.com` | internet gateway | your server's FQDN |
| `X-MS-Exchange-CrossTenant-FromEntityHeader` | `Internet` | `HybridOnPrem` |
| `X-MS-Exchange-Organization-MessageDirectionality` | `Incoming` | `Originating` |
| `X-MS-Exchange-Organization-AuthAs` | `Anonymous` | `Internal` |
| `X-MS-Exchange-Organization-AuthSource` | `*.outlook.com` | `EX01.corp.contoso.com` |
| `X-OrganizationHeadersPreserved` | absent | `EX01.corp.contoso.com` |
| Subject | `[EXTERNAL] …` | no tag |

## 6. Rollback

```powershell
Set-SendConnector "Outbound to Office 365" -AddressSpaces @{Remove="SMTP:contoso.com;1","SMTP:fabrikam.com;1"}
Set-SendConnector "Outbound to Office 365" -CloudServicesMailEnabled $false
Set-SendConnector "Outbound to Office 365" -SmartHosts $null -DNSRoutingEnabled $true
```

Messages already in a delivery queue keep the next hop assigned at categorization; after any
connector change, resubmit affected queues:

```powershell
Get-Queue -Server EX01 | Where MessageCount -gt 0 | fl Identity, NextHopDomain, Status, LastError
Retry-Queue -Identity EX01\<n> -Resubmit $true
```

## 7. Not changed

Internet send connector (`*`), receive connectors (the relay connector was already
`ExternalAuthoritative` and scoped to the relay source ranges), tenant inbound connectors,
distribution group settings.

## 8. Gotchas encountered

- **Propagation.** Every send-connector change took several minutes to become effective.
  Wait five minutes before testing, or the test lies to you.
- **Queues don't re-route themselves.** Anything queued under the old configuration sits until
  resubmitted.
- **`SEND` vs `SENDEXTERNAL`.** Send-connector deliveries log as `SENDEXTERNAL`; filtering on
  `SEND` returns nothing.
- **Two servers, two tracking logs.** `HARECEIVE` on one server means the primary copy was
  processed on the other; query both.
- **HCW re-runs.** The wizard may reset `AddressSpaces` to the onmicrosoft domain only. Re-check
  after any HCW run.
- **Alternatives considered.** Per-group on-prem mail contacts with `targetAddress` (works, but one
  object per group and a cleanup problem later); opening the groups to external senders (works,
  but every opened group becomes reachable from the internet and relay mail stays tagged
  `[EXTERNAL]`). The connector change is one reversible configuration and lets every group keep
  its original sender restriction.
