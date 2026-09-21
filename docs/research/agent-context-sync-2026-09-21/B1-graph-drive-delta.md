# B1 — Microsoft Graph driveItem `delta`: mechanism spec for an L1 acquisition layer

Axis: is `driveItem: delta` a sound "since-token" primitive for L1, and what exactly does a change record carry?

**Verdict.** Delta is the right L1 primitive for OneDrive/SharePoint and is cheap enough to poll (1 resource unit per token'd call). Three load-bearing surprises against the lead's hypothesis: (1) the change record does **not** reliably carry a content hash you can equate with the hash of the bytes you later download — sensitivity-labelled (AIP) Office files return one hash online and different bytes on download, which breaks a naive content-addressed manifest; (2) delegated `Files.Read.All` and `Sites.Read.All` are **admin-consent-required** per Microsoft's own permissions reference, so the no-app-registration device-code path reaches only the signed-in user's own OneDrive (`Files.Read`) — client SharePoint libraries are admin-gated, making the no-API path the *primary* for those, not a fallback; (3) `cTag` — the one field Microsoft's own scan guidance tells you to use for "did content change" — is **omitted from delta responses on OneDrive for Business**.

All `updated_at` dates below are the Learn page's own `updated_at` frontmatter, read 2026-09-21.

---

## 1. Mechanism table

| Mechanism | Gives | Golden example | Limits | Pipeline slot | Evidence |
|---|---|---|---|---|---|
| `GET /drives/{id}/root/delta` · `/sites/{siteId}/drive/root/delta` · `/me/drive/root/delta` · `/users/{id}/drive/root/delta` · `/groups/{gid}/drive/root/delta` | O(changes) recursive listing since a `deltaLink`, incl. deletes | rclone `--onedrive-delta`; abraunegg `onedrive --monitor` | Only these five forms are documented, in **both** v1.0 and beta | L1 | [driveitem-delta v1.0](https://learn.microsoft.com/en-us/graph/api/driveitem-delta?view=graph-rest-1.0) (`updated_at 2026-06-06`) HTTP request block; [beta source](https://raw.githubusercontent.com/microsoftgraph/microsoft-graph-docs-contrib/main/api-reference/beta/api/driveitem-delta.md) L42-46 |
| `@odata.nextLink` / `@odata.deltaLink` | cursor persistence | — | "Your app should continue calling with the `@odata.nextLink` until you no longer see an `@odata.nextLink` returned, or you see a response with an empty set of changes." | L1 state | same page, intro |
| `?token=latest` | current cursor with **no** enumeration — `{"value":[], "@odata.deltaLink": …}` | rclone `changeNotifyStartPageToken` (`backend/onedrive/onedrive.go:3118-3129`) | gives you a "changes only from now" cursor; you then never learn the existing corpus | L1 bootstrap | same page Example 3; **measured** (§3, call 1b) |
| `?token=<ISO8601>` | cursor from a wall-clock instant | — | "Using a timestamp in place of a token is only supported on OneDrive for Business and SharePoint." + "Clients should use the deltaLink provided by `delta` queries when possible, rather than generating their own token." | L1 disaster recovery | same page Example 4 |
| `deleted` facet | tombstones | — | "Deleted items are returned with the `deleted` facet… you should only delete a folder locally if it is empty after syncing all the changes." | L2 change set | same page, intro + Note |
| `file.hashes.quickXorHash` | server-side content fingerprint → detect same-name in-place overwrite **without downloading** | rclone `onedrive.go:2311-2320` decodes `file.Hashes.QuickXorHash` | "**quickXorHash** is the only value that is guaranteed to be available for both OneDrive for work or school and OneDrive for home." `sha256Hash`: "This property isn't supported. Don't use." | L2 manifest | [hashes resource](https://learn.microsoft.com/en-us/graph/api/resources/hashes?view=graph-rest-1.0) (`updated_at 2025-04-09`); **measured present in a delta payload** (§3) |
| `eTag` / `cTag` | version counters | — | `cTag` = "An eTag for the content of the item. This eTag isn't changed if only the metadata is changed." `eTag` = "eTag for the entire item (metadata + content)." **But delta omits `cTag` on ODB.** | L2 change classifier | [driveItem resource](https://learn.microsoft.com/en-us/graph/api/resources/driveitem?view=graph-rest-1.0) (`updated_at 2026-05-01`) + delta Remarks |
| `HTTP 410 Gone` + `resyncChangesApplyDifferences` / `resyncChangesUploadDifferences` + `Location:` header | forced re-enumeration | abraunegg `--resync` (exit 78 = `EX_CONFIG` when required) | "the service returns an `HTTP 410 Gone` error with an error response containing one of the error codes below, and a `Location` header containing a new nextLink that starts a fresh delta enumeration from scratch" | L1 recovery | delta page, resync table |
| `Prefer: deltaExcludeParent` | suppress the unchanged ancestor chain | — | "the response includes the items that have changed, and not the parent items in the hierarchy" — sent as a **request header named `deltaExcludeParent`**, not a `Prefer` value | L1 payload trim | delta page, Request headers |
| `Prefer: deltashowremovedasdeleted, deltatraversepermissiongaps, deltashowsharingchanges` | permission-change annotation `@microsoft.graph.sharedChanged:"True"` | — | "applicable to SharePoint and OneDrive for Business but not consumer OneDrive"; "your application will need to request **Sites.FullControl.All**" | not needed for L1 (we don't mirror ACLs) | delta page, Scanning permissions hierarchies |
| `Prefer: hierarchicalsharing` | sharing info only at hierarchy roots | — | avoids a follow-up permission GET per item | payload trim | same |
| Webhook `POST /subscriptions` on `/drives/{id}/root` | avoid polling | scan-guidance recommended pattern | ODB/SPO: **root folder only** (`/drives/{id}/root`, `/users/{id}/drive/root`); consumer OneDrive: "any folder". `changeType` **`updated` only**. Max expiry **42,300 min (~29.4 d)**. Latency avg <1 min, **max 6 hours**. Requires a public HTTPS `notificationUrl`. Payload says *something changed*, not *what* — you still call delta. | L1 trigger (optional) | [change-notifications overview](https://learn.microsoft.com/en-us/graph/api/resources/change-notifications-api-overview?view=graph-rest-1.0) (`updated_at 2026-04-07`); [subscription resource](https://learn.microsoft.com/en-us/graph/api/resources/subscription?view=graph-rest-1.0) (`updated_at 2026-09-17`) |

### Cost model (the number that decides poll-vs-webhook)

| Item | Value | Source |
|---|---|---|
| **Delta *with* a token** | **1 resource unit** | [SPO throttling](https://learn.microsoft.com/en-us/sharepoint/dev/general-development/how-to-avoid-getting-throttled-or-blocked-in-sharepoint-online) (`updated_at 2026-08-10`): "we lower the resource unit cost of delta requests with a token to 1 resource unit, although it's a multi-item query" |
| Delta *without* a token (initial crawl page) | 2 RU | same: "The delta request without a token is considered a multi-item query and costs 2 resource units per request." |
| Download file content | 1 RU | same, Resource units table |
| Per-app-per-tenant budget | **1,250 RU/min** (0–1,000 licenses) → 6,250 RU/min (50,000+); **1,200,000 RU/24 h** → 6,000,000 | same, Application Throttling table |
| Per-user budget | 3,000 requests / 5 min; **egress 100 GB/hour** | same, User Throttling table |
| Per-app-per-tenant egress | **400 GB/hour** | same, Application Throttling table |
| Global Graph ceiling | 130,000 requests / 10 s per app across all tenants | [throttling-limits](https://learn.microsoft.com/en-us/graph/throttling-limits) (`updated_at 2026-09-17`) |
| Throttle signal | 429 or 503 + **`Retry-After`**. "SharePoint Online does not return or support `IETF RateLimit` headers." | SPO throttling, RateLimit headers §. ⚠️ the same page's best-practice bullet says "Use the `Retry-After` and `RateLimit` HTTP headers" — **internally contradictory**; build only on `Retry-After` |
| Decoration | `NONISV\|CompanyName\|AppName/Version` (enterprise) or `ISV\|…`. "Well-decorated traffic will be prioritized over traffic that isn't properly decorated." | SPO throttling, How to decorate |

**Arithmetic (theoretical, from the cited units):** polling one drive's deltaLink every 60 s = 1,440 RU/day out of ≥1,200,000 — **0.12%** of the smallest tenant budget. Polling 50 SharePoint libraries every 5 min = 14,400 RU/day, 1.2%. Polling is not the constraint; **egress is**. A 200 GB initial crawl against a *delegated* token hits the 100 GB/hour per-user ceiling in hour two.

---

## 2. Puller state machine

```
                     ┌──────────────────────────────────────────┐
                     │ S0  NEW_SOURCE (driveId recorded)        │
                     └──────────────┬───────────────────────────┘
                                    │ GET /drives/{id}/root/delta
                                    │   ?$select=<minimal>&$top=N
                                    │   header: deltaExcludeParent
                                    ▼
      ┌──────────────► ┌──────────────────────────────┐
      │  @odata.       │ S1  ENUMERATING              │  persist page cursor
      │  nextLink      │  ingest items → id-keyed tree │  (a crash mid-enumerate
      └────────────────┤  DO NOT publish change set    │   must resume, not restart)
                       └──────────────┬────────────────┘
                        @odata.deltaLink
                                    ▼
                       ┌──────────────────────────────┐
                       │ S2  SYNCED                    │  fsync deltaLink + a
                       │  store deltaLink ATOMICALLY   │  monotonic sync_epoch
                       │  with the item snapshot       │
                       └──────────────┬────────────────┘
                        tick (60 s–5 min) or webhook
                                    ▼
                       ┌──────────────────────────────┐
                       │ S3  POLLING                   │
                       │  GET <deltaLink>  (1 RU)      │
                       └───┬──────┬──────┬──────┬──────┘
             200 ─────────┘      │      │      └───────── 429/503
              │                  │      │                     │
              │                400    410                     ▼
              ▼                  │      │            S6 BACKOFF: sleep
        classify changes         │      │            Retry-After; PAUSE ALL
        (§4) → L2 change set     │      │            requests to the service
        new deltaLink → S2       │      │            → S3
                                 │      │
                                 │      └──► S4 RESYNC
                                 │            follow `Location:` nextLink
                                 │            (a fresh full enumeration)
                                 │            → S1, then diff the result
                                 │            against local state:
                                 │            resyncChangesApplyDifferences →
                                 │              server wins, incl. deletes
                                 │            resyncChangesUploadDifferences →
                                 │              keep both where unsure
                                 │            (we are read-only: both collapse
                                 │             to "server wins", but log which)
                                 │
                                 └──► S5 MALFORMED  ← measured: a bogus token
                                       returns 400 invalidRequest "Provided
                                       sync token is malformed", NOT 410.
                                       This is OUR bug (corrupt cursor store),
                                       not a service resync. Alarm + drop the
                                       cursor deliberately → S0. Never loop.
```

Two invariants the states exist to protect:

- **Never advance the stored cursor before the change set is durably consumed.** A consumed-but-unapplied delta is unrecoverable: the next call returns nothing and the miss looks like "no changes forever". (Same failure shape as *"A reader that cannot prove delivery must not consume"*.) abraunegg ships exactly this discipline as a feature — its read-only status command "does not advance the stored Microsoft Graph delta cursor… it can be run repeatedly without consuming the pending changes it is reporting" (`docs/usage.md:1335`).
- **Schedule a periodic full re-enumeration anyway.** Microsoft: "you may want to provide a periodic delta query to ensure that no changes are missed… We recommend no more than once per day for this periodic check" ([scan-guidance](https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/scan-guidance), `updated_at 2026-05-14`). abraunegg ships `monitor_fullscan_frequency` — "the client deliberately does not use the stored Microsoft Graph `/delta` link for that pass and instead performs a broader online reconciliation pass" (`usage.md:773`). Two independent mature implementations refuse to trust the cursor indefinitely; so should L1.

---

## 3. Measured, not quoted — live Graph reads, 2026-09-21

Instrument: `mcp__ms365__graph-batch` against `ren.chris@outlook.com` (**consumer OneDrive, `driveType: personal`**, drive `A29C86DED2D9BE1E`). Read-only GETs. The work/school account on this machine (`chris@reso.gl`) is logged out, so **nothing here is measured on SharePoint or OneDrive for Business** — that is the single biggest gap in this report.

| # | Call | Result |
|---|---|---|
| 1a | `/me/drive/root/delta?$top=2` | 200, `@odata.nextLink`, first item is the **root itself** (`"root": {}`) — hence `deltaExcludeParent` |
| 1b | `/me/drive/root/delta?token=latest` | 200, `{"value":[], "@odata.deltaLink": …}` — zero-cost cursor confirmed |
| 2a | `/me/drive/root/delta?$top=8&$select=id,name,file,eTag,cTag,size,lastModifiedDateTime,parentReference,deleted` | 200, `$select` honoured and prunes payload |
| 2b | `/me/drive/root/children?$top=6` | 19 root children |
| 3a | `/me/drive/items/A29C86DED2D9BE1E!219/delta?$top=3` | **200 — the undocumented folder-scoped form works and is genuinely scoped**: returns the folder plus descendants whose `parentReference.path` is `/drive/root:/Email attachments` |
| 3b | `/me/drive/root/delta?$top=5000&$select=id` | 200 in **one page** with a `deltaLink`, 117 ids — whole-drive recursion confirmed; `$top=5000` neither errors nor is clamped to an error |
| 3c | `/me/drive/root/delta?token=bogus-token-xyz` | **400** `invalidRequest` — `"Provided sync token is malformed"`. Not 410. |

Verbatim field shape of one changed file in the delta feed (call 2a):

```json
{
  "eTag": "\"{D2D9BE1E-86DE-209C-80A2-A70000000000},2\"",
  "id": "A29C86DED2D9BE1E!167",
  "lastModifiedDateTime": "2011-06-23T05:29:20Z",
  "name": "Chris Ren's Resumé.docx",
  "cTag": "\"c:{D2D9BE1E-86DE-209C-80A2-A70000000000},2\"",
  "size": 27452,
  "parentReference": {
    "driveType": "personal", "driveId": "A29C86DED2D9BE1E",
    "id": "A29C86DED2D9BE1E!sea8cc6beffdb43d7976fbc7da445c639",
    "path": "/drive/root:",
    "siteId": "2d47f4c3-30f1-4e35-ad1c-8165698a7692"
  },
  "file": {
    "mimeType": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "hashes": {
      "quickXorHash": "yAQCtG7vHPwzpm7cVDHxqC8W5ck=",
      "sha1Hash": "888339DA8B2A39B97C362757FE6455288E190E5C",
      "sha256Hash": "5BA23EDFDD48E0A3897C19B81869A62BAE5225ADD1153FDE1AE216844D1F5ED5"
    }
  }
}
```

Three measurements that **contradict the reference docs**:

1. **`file.hashes` IS in the delta payload** (answers key question (a) for consumer OneDrive, empirically). All three of quickXor/sha1/sha256 populated — including the one the docs call unsupported. Do **not** design on sha256: `hashes` resource says "`sha256Hash` … This property isn't supported. Don't use." A field that is populated today and documented as unsupported is a field that can vanish without a changelog entry.
2. **`parentReference.path` IS populated** (`/drive/root:`, `/drive/root:/Email attachments`), against the delta page's Remark: "The `parentReference` property on items won't include a value for **path**." rclone's change-notify path depends on this (`onedrive.go:getItemFullPath` reads `parent.Path`), so it is not a consumer-only accident — but it is undocumented behaviour. **Use it as an optimization; keep an id→parent tree as truth.** The Remark's *reason* is the durable half and is what actually binds: "renaming a folder doesn't result in any descendants of the folder being returned from **delta**. **When using delta you should always track items by id**."
3. **An undocumented `isAuthoritative: false` field** appears on every item. Do not read it.

---

## 4. Key questions, answered

### (a) Are hashes present in delta responses? Which hash?
- **Consumer OneDrive: yes, measured** (§3) — quickXor + sha1 + sha256.
- **ODB / SharePoint: only quickXorHash is guaranteed to exist at all**, and I could not measure it. "quickXorHash is the only value that is guaranteed to be available for both OneDrive for work or school and OneDrive for home" ([hashes](https://learn.microsoft.com/en-us/graph/api/resources/hashes?view=graph-rest-1.0)), preceded by "Not all services provide a value for all hash properties listed." rclone defaults **all** OneDrive backends to QuickXorHash since 1.62 and phased SHA1 out ([rclone.org/onedrive](https://rclone.org/onedrive/)).
- **Design rule:** `quickXorHash` is the change detector. It must be *optional* in the manifest schema, with a declared fallback ladder (`quickXorHash` → `size`+`lastModifiedDateTime` → download-and-hash). A pipeline that assumes the hash is present will silently stop detecting changes on the one library that doesn't emit it — an aggregate-green failure.

🚨 **The hash you read is not the hash of the bytes you will download.** abraunegg, `docs/usage.md:131,135`: "If you are using OneDrive Business Accounts and your organisation implements Azure Information Protection, these AIP files will report as one size & hash online, but when downloaded, will report a totally different size and hash… the Microsoft Graph API lack[s] any capability to identify up-front that a file utilises AIP, thus zero capability to differentiate between AIP and non-AIP files for failure detection." And rclone: SharePoint "silently modifies uploaded files, mainly Office files (.docx, .xlsx, etc.), causing file size and hash checks to fail."

**Consequence for L2:** keep **two** hashes per item and never equate them — `source_hash` (server quickXorHash, the *change* signal) and `bytes_hash` (sha256 of what we actually downloaded, the *identity/dedupe* key). A corporate tenant with Purview/AIP labels on Office documents is exactly the population this hits, and the failure is silent: every labelled PDF/DOCX looks permanently "changed" or permanently "unchanged" depending on which side you trusted.

### (b) How is an in-place same-name overwrite represented?
`id` is stable; the version counter in `eTag`/`cTag` increments and `quickXorHash` changes. Doc basis: `cTag` = "An eTag for the content of the item. This eTag isn't changed if only the metadata is changed"; `eTag` = "eTag for the entire item (metadata + content)". Observed format pairs them on one counter: `eTag "{GUID},2"` / `cTag "c:{GUID},2"`. The overwrite also mints a `driveItemVersion` (`/versions` relationship), a third independent signal. *Theoretical* — I could not write to the operator's drive to confirm the increment.

🚨 **`cTag` is unusable from an ODB delta payload.** Delta Remarks, OneDrive for Business table: Create/Modify omits **`ctag`**; Delete omits `ctag`, `name`. Yet scan-guidance says "you can use the cTag property to determine if the contents of the file have changed since the last time you downloaded it." **Microsoft's own scanning guidance prescribes a field its own delta API strips on the exact service the guidance is about.** Following it costs one extra `GET /items/{id}` per changed item (2 RU each) for a signal `quickXorHash` already gives you for free in the same payload. Classifier, in order: `quickXorHash` differs → content change, re-convert. Hash absent and (`size`, `lastModifiedDateTime`) differ → probable content change, re-convert. Only `eTag` moved → metadata touch (rename, label, move), **do not re-convert** — re-map the path and keep the derived markdown.

### (c) Folder moves and renames — does every child re-appear?
**No, and this is the single most consequential field-level fact for a path-shaped `/docs` mirror.** "renaming a folder doesn't result in any descendants of the folder being returned from **delta**." The rename arrives as one item (the folder) with a new `name`; a move arrives as one item with a new `parentReference.id`. Every descendant's path silently changes with **zero** delta records. Plus: "The delta feed shows the latest state for each item, not each change. If an item were renamed twice, it would only show up once, with its latest name." And "The same item may appear more than once in a delta feed… You should use the last occurrence you see."

**Design rule:** L2's authority is an `id → (parent_id, name)` table. Paths are *derived* by walking it. A folder rename is an O(subtree) local re-derivation with **no** network cost and **no** re-conversion — which is precisely the win over re-crawling, and precisely what a path-keyed manifest throws away.

### (d) Practical limits
| | Answer |
|---|---|
| **deltaLink lifetime** | **Undocumented for driveItems.** The only published change-tracking-token lifetime is for identity/education: "delta links for identity and access and education resources have a lifetime of seven (7) days instead of the previous lifetime of thirty (30) days" ([M365 dev blog, 2020-07-03](https://devblogs.microsoft.com/microsoft365dev/duration-of-change-tracking-tokens-for-identity-and-education-resources/)) — that post does not cover OneDrive/SharePoint. Treat 410 as an ordinary operating state on any cadence, not an exception. Community guidance (weaker source, [MS Q&A](https://learn.microsoft.com/en-us/answers/questions/5856205/microsoft-graph-delta-api-clarification-on-delta-t)): tokens left unused are likelier to be dropped — i.e. *polling keeps the token alive*, which argues for a floor on poll interval, not just a ceiling. |
| **Page size** | `$select`, `$expand`, `$top` supported. No documented max. `$top=5000` accepted without error and returned 117 items + deltaLink in one page (§3b). Server picks; **always follow `nextLink`, never assume a page count.** |
| **Throttling** | 429/503 + `Retry-After`, no IETF RateLimit headers on SPO-backed resources. "When waiting for 429 or 503 recovery you should ensure that you pause all further requests you are making to the service… especially important in multi-threaded scenarios." Off-peak = nights/weekends in the tenant's region. |
| **Webhook latency** | avg <1 min, **max 6 hours** ([subscription](https://learn.microsoft.com/en-us/graph/api/resources/subscription?view=graph-rest-1.0), Latency table). A webhook is a *hint*, never an SLA. |
| **Webhook scope** | ODB/SPO: drive **root only** — you cannot subscribe to `/docs-source` as a subfolder. Consumer: any folder. |
| **Memory** | abraunegg, `usage.md:85`: "approximately 1GB of memory for every 100,000 objects stored online" during a full scan, because the client retrieves all objects before processing. Stream the initial enumerate to disk; do not hold it. |

### (e) Permission scopes and whether device-code works without an app registration

| Scope | Type | AdminConsentRequired |
|---|---|---|
| `Files.Read` | Delegated | **No** |
| `Files.Read.All` | Delegated | **Yes** |
| `Files.Read.All` | Application | Yes |
| `Sites.Read.All` | Delegated | **Yes** |
| `Sites.Selected` | Delegated **and** Application | **Yes** |

Source: [permissions-reference](https://learn.microsoft.com/en-us/graph/permissions-reference) (`updated_at 2026-09-15`), per-permission tables.

Delta's own least-privileged set: Delegated (work/school) `Files.Read`; Application `Files.Read.All`. Scan-guidance pushes Application permissions for scanners — "most scanning applications will want Application permissions" — and notes the grant is tenant-wide, not admin-personal: "the permission grant is being associated with the tenant and application, rather than the administrator user."

**Device-code without an app registration: yes for the user's own OneDrive, no for a client SharePoint library.** `Connect-MgGraph -Scopes "Files.Read" -UseDeviceAuthentication` uses the first-party Microsoft Graph PowerShell app, and `Invoke-MgGraphRequest -Method GET -Uri https://graph.microsoft.com/v1.0/me/drive/root/delta` is a complete zero-registration puller ([authentication-commands](https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands?view=graph-powershell-1.0), `updated_at 2026-05-06`). But `Files.Read` is "the signed-in user's files" only; the moment L1 must read a shared SharePoint document library it needs `Files.Read.All`, `Sites.Read.All` or `Sites.Selected` — **all three admin-consent-required**. IT also has two independent blocks on that same page's own instructions: set the app's **"Assignment required? → Yes"** and restrict **Users and groups**.

⚠️ **Conflicting evidence, stated rather than reconciled.** abraunegg's `docs/application-security.md:37-39` tabulates delegated `Files.Read`, `Files.Read.All` **and** `Sites.Read.All` as "Admin consent required: **No**" — a screenshot of what the Entra consent UI showed for their app, against Microsoft's own permission-metadata flag saying Yes for the latter two. Both are cited above; I did not run the arm that would settle it (a device-code consent attempt in a real locked-down tenant, which is the operator's to run and is destructive of nothing). The discriminator is most likely the tenant's **user-consent policy** setting, which can independently forbid *any* user consent regardless of the flag. **Plan for the stricter reading**: assume SharePoint-via-Graph needs an admin ticket.

---

## 5. Adversarial pass — where this axis argues *against* the hypothesis

1. **L2 keyed on "content-addressed" is under-specified and will break on AIP.** Split it: server hash = change signal, local bytes hash = identity. See (a).
2. **The no-API path is not a fallback for client SharePoint; it is the likely primary.** All the scopes that reach a shared library are admin-gated. The OneDrive sync client already holds a delegated token the tenant has blessed, materialises the library on disk, and hands you FSEvents. L1's Graph arm should be scoped to *the operator's own OneDrive*, and the SharePoint arm designed as local-watcher-first with Graph as the upgrade once an admin says yes. Design the manifest so both arms produce the same change records.
3. **A file-watcher arm cannot see a rename as a rename either.** abraunegg's own known-issue #876/#2579: in standalone (non-daemon) mode "renaming or moving folders locally that have already been synchronized leads to the data being deleted online and then re-uploaded" — because "the client lacks the capability to track file system changes (including renames and moves) that occur when it is not running." A watcher that isn't running during the rename degrades to delete+create, i.e. a full re-conversion of a subtree. Mitigation is the *same* id-tree as the Graph arm, keyed on `(size, bytes_hash)` to re-link an orphaned delete against a new create.
4. **Delta on a subfolder is undocumented.** It works (§3a, consumer), and rclone reports the opposite for its own usage: "the delta listing API **only** works at the root of the drive. If you use it not at the root then it recurses from the root and discards all the data that is not under the directory you asked for." Two readings of one API, and neither v1.0 nor beta lists the item-scoped path. **Design for whole-drive delta + local filtering.** A subfolder-scoped cursor is an optimization to measure on the real tenant, never a premise.
5. **Egress, not request count, is the initial-crawl wall.** 100 GB/h per user, 400 GB/h per app-tenant. For "tens to hundreds of GB" the first crawl is a multi-hour off-peak job with its own resumable cursor — and it should download only files the converter will actually consume, not the whole corpus. Delta gives you `size` and `file.mimeType` *before* any download; filter there.
6. **410 and 400 demand opposite actions and look alike from a status-code switch.** 410 → follow `Location`, full re-enumerate, diff. 400 "Provided sync token is malformed" → our cursor store is corrupt; re-enumerating hides the bug. Measured, §3c.
7. **`sha256Hash` is documented as unsupported and is populated.** Every consumer of it is one silent service change from a false "unchanged" verdict. Use `quickXorHash`.
8. **Microsoft's scanning guidance contradicts Microsoft's delta reference** (cTag). When two vendor pages disagree, the reference page describing the *response shape* wins over the conceptual page describing *intent*.

## 6. Named blockers

- **Not measured on SharePoint / OneDrive for Business at all.** `chris@reso.gl` is logged out (mission-board `needs 3dc0ca0a21f2`). Every §3 measurement is `driveType: personal`. The three questions that need re-running there: does `file.hashes.quickXorHash` appear in an ODB/SPO delta payload; is `cTag` really absent; does `/items/{id}/delta` scope or recurse from root.
- **In-place-overwrite representation is reasoned, not measured** — it needs a write to a drive, which is outside this task's read-only boundary.
- **The admin-consent fork (§4e) is unsettled** and is the one fact that decides whether the Graph arm reaches client SharePoint at all.
- **deltaLink lifetime is unknowable from documentation.** Do not put a number in the design; put a 410 handler in it.
