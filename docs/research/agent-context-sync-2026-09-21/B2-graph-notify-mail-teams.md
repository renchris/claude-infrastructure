# B2 — Graph change notifications, mail delta, Teams delta, and what the local ms365 MCP actually exposes

Measured 2026-09-21 against `@softeria/ms-365-mcp-server` **0.143.0** (installed at
`/Users/chrisren/Library/Application Support/fnm/node-versions/v22.21.1/installation/lib/node_modules/@softeria/ms-365-mcp-server`,
wired in `~/.claude.json` → `mcpServers.ms365`) and learn.microsoft.com v1.0 docs.

---

## Verdict, first

**The layered hypothesis survives, with one correction and one hard boundary.**

1. **L1 acquisition is sound and every source has a real since-token** — driveItem/SharePoint-drive delta, mail-folder delta, per-channel Teams delta. Notifications are a *doorbell*, never a payload: Microsoft's own scale guidance is literally `Discover → Crawl → Notify → Process changes (delta)`.
2. **CORRECTION — the local MCP server cannot do incremental sync through its delta tools.** `get-drive-delta`, `list-mail-folder-messages-delta`, `list-calendar-events-delta` expose **no `$deltatoken` / `$skiptoken` parameter**, and an unrecognized parameter is **silently dropped with a `logger.warn`**. Measured: passing a valid `$deltatoken` to `list-mail-folder-messages-delta` returned a **fresh full-sync page with a new token**. The escape hatch that *does* work is **`graph-batch`** (arbitrary relative Graph GET URLs) — measured round-trip returned `"value": []`. The pipeline must therefore own its own Graph HTTP client, or route every delta call through `graph-batch`.
3. **HARD BOUNDARY — tenant-wide Teams chat history is not reachable under delegated auth at all.** `chats/getAllMessages/delta` is **"Delegated (work or school account) | Not supported"**, application-only, and a *protected API* requiring a written access request. Per-**channel** delta *is* delegated-capable; per-**chat** (1:1/group) is the gap.

---

## Table — per source

| Source | Endpoint | Since-token | What changes are reported | Deletes | Auth / licensing gate | Limits | Evidence |
|---|---|---|---|---|---|---|---|
| **OneDrive / SharePoint files** | `GET /drives/{id}/root/delta`, `/sites/{siteId}/drive/root/delta`, `/me/drive/root/delta`, `/groups/{gid}/drive/root/delta` | `token=<deltaToken>` in `@odata.deltaLink`; also `token=latest` (empty body + current token) and `token=<ISO timestamp>` (**ODB/SharePoint only**) | Latest **state** per item, not per change: *"The delta feed shows the latest state for each item, not each change. If an item were renamed twice, it would only show up once, with its latest name."* Create/modify/rename/move/permission-change | `deleted` facet on the item. *"Deleted items are returned with the `deleted` facet. Items with this property set should be removed from your local state."* | Delegated least-priv **Files.Read**; app **Files.Read.All**. No metering | 410 Gone → `resyncChangesApplyDifferences` / `resyncChangesUploadDifferences` + `Location` header with a fresh nextLink. `parentReference.path` is absent; **"When using delta you should always track items by id"**. ODB omits `ctag` on Create/Modify and `ctag`+`name` on Delete. 429/503 + `Retry-After` | [driveitem-delta](https://learn.microsoft.com/en-us/graph/api/driveitem-delta?view=graph-rest-1.0) |
| **SharePoint site inventory** | `GET /sites` + delta (beta rollout per scan guidance); local MCP has `get-sharepoint-sites-delta` → `/sites/delta()` | deltaLink | new site collections, site-structure changes | — | `Sites.Read.All` (workScopes in endpoints.json) | *"Delta query support for site enumeration is currently rolling out to the Microsoft Graph Beta version."* | [scan-guidance](https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/scan-guidance); `dist/endpoints.json` |
| **Outlook mail** | `GET /me/mailFolders/{id}/messages/delta` — **folder-scoped only**, no mailbox-wide delta | `$deltatoken` / `$skiptoken`; `changeType=created|updated|deleted` | Created/updated/deleted **plus noise you must tolerate**: *"Delta queries for messages can return change events that don't match the filter conditions specified in the initial request… `@removed` entries with `"reason": "deleted"` when an item is deleted or **moved from the folder**… Read/unread state changes… Delta tracking operates at the **collection** level, not the message-level"* | `@removed` with `"reason": "deleted"` (same signal for move-out) | Delegated least-priv **Mail.ReadBasic**; `Mail.Read` for bodies. No metering | Supports `$select`, `$top`, `$expand`. `$filter` only `receivedDateTime ge|gt`; `$orderby` only `receivedDateTime desc`; **no `$search`**. `Prefer: odata.maxpagesize={x}` | [message-delta](https://learn.microsoft.com/en-us/graph/api/message-delta?view=graph-rest-1.0) |
| **Teams — channel messages** | `GET /teams/{team-id}/channels/{channel-id}/messages/delta` | `$deltatoken` / `$skiptoken` | new + updated messages (root posts; replies need `…/replies`) | not documented on this path | **Delegated (work or school): `ChannelMessage.Read.All`, `Group.ReadWrite.All`, `Group.Read.All`.** Application: `ChannelMessage.Read.Group`, `ChannelMessage.Read.All`, … Not metered, not a protected API | Per-channel only; 8-month horizon not stated for this path | [Get-MgTeamChannelMessageDelta](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.teams/get-mgteamchannelmessagedelta?view=graph-powershell-1.0) |
| **Teams — one chat** | `GET /chats/{chat-id}/messages/delta` (cmdlet requires `-ChatId`) | `$deltatoken` / `$skiptoken` | new + updated | undocumented | **UNDOCUMENTED** — the cmdlet reference ships *no* permissions table for this path | undocumented | [Get-MgChatMessageDelta](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.teams/get-mgchatmessagedelta?view=graph-powershell-1.0) |
| **Teams — all of a user's chats** | `GET /users/{id}/chats/getAllMessages/delta` | `$deltatoken` / `$skiptoken` | new or updated across 1:1, group, meeting chats | not surfaced as `@removed`; `deletedDateTime` on the message | **Delegated (work or school): "Not supported." Delegated (personal): "Not supported." Application: `Chat.Read.All` / `Chat.ReadWrite.All`** — plus *protected API* access request | *"Delta only returns messages within the last eight months."* `$top` upper limit **50**; `$filter` only `lastModifiedDateTime gt` | [chatmessage-delta](https://learn.microsoft.com/en-us/graph/api/chatmessage-delta?view=graph-rest-1.0) |
| **Teams — export APIs** | `GET /users/{id}/chats/getAllMessages`, `/teams/{id}/channels/getAllMessages` (+ `getAllRetainedMessages`) | no delta; incremental via `$filter=lastModifiedDateTime gt … and lt …` | everything in the window, incl. control/system messages, reactions, edit history | soft-deleted readable ≤21 d (≤30 d with hold/retention) | *"Microsoft Teams APIs in Microsoft Graph that access sensitive data are considered protected APIs."* App perms only: `Chat.Read.All`, `ChannelMessage.Read.All`, `User.Read.All`. *"To use Microsoft Teams Export APIs, organizations must have an active Microsoft Teams license assigned to the users whose data is being exported."* **No longer metered** | `$top` ≤250 and *"a maximum hint and not a guaranteed page size"*; order not guaranteed | [export-teams-content](https://learn.microsoft.com/en-us/microsoftteams/export-teams-content), [teams-licenses](https://learn.microsoft.com/en-us/graph/teams-licenses) |
| **Change notifications (all sources)** | `POST /subscriptions`, `PATCH` to renew, `POST /subscriptions/{id}/reauthorize` | n/a — carries an **id**, not content | Basic notification = *"Change notifications that don't contain resource data other than the **id** of the resource that changed."* Drives only support `update`: *"An 'update' indicates that content within the drive has changed or that new content has been added or deleted."* | not distinguished on drives | No `Subscription.*` scope — caller needs read perm on the resource. Teams chatMessage **notification** resources were model=A/B metered; **no longer metered since 2025-08-25** | Max expiry: **driveItem 42,300 min (<30 d)** · **SharePoint list 42,300 min** · **message/event/contact 10,080 min (<7 d)**, rich = 1,440 min · **Teams chatMessage/chat/channel 4,320 min (3 d)**. Latency: **driveItem & list avg <1 min, max 6 hours**; message avg <1 min max 3 min; chatMessage avg <10 s max 1 min. Teams: 10,000 subs/org shared across *all* Teams resources; mail 1,000 active subs/mailbox | [change-notifications-overview](https://learn.microsoft.com/en-us/graph/change-notifications-overview), [scan-guidance](https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/scan-guidance) |

---

## The local MCP server — what it can and cannot do (empirical)

**Delta surface is 5 tools, and none of them accept a token.** `dist/endpoints.json` (326 endpoints) contains exactly:
`get-drive-delta` (`/drives/{drive-id}/items/{driveItem-id}/delta()`), `get-sharepoint-sites-delta`,
`list-calendar-events-delta`, `list-calendar-view-delta`, `list-mail-folder-messages-delta`.
**There is no Teams `chatMessage` delta tool and no `getAllMessages` tool at all.**

Each delta tool's zod parameter list (`dist/generated/client.js:6083-6132`, `10086-10145`) is
`$top,$skip,$search,$filter,$count,$select,$orderby,$expand` (+`changeType` for mail). No `$deltatoken`, no `$skiptoken`, no free-form URL.

**Unknown params are dropped silently.** `dist/graph-tools.js:640-726` walks the caller's params; the
`odataParams` whitelist is `filter,select,expand,orderby,skip,top,count,search,format`; anything not in
`parameterDefinitions`, not a path param, not an OData param and not a body field hits:

```js
} else {
  logger.warn(`Dropping unrecognized parameter '${paramName}' for tool ${tool.alias}`);
}
```

**Measured, this session (read-only, operator's own mailbox):**

| Call | Result |
|---|---|
| `graph-batch` GET `/me/mailFolders/inbox/messages/delta?$top=1&$select=id,subject,receivedDateTime` | `200`, 1 item, `@odata.deltaLink` with `$deltatoken=W14TifTy…` |
| `graph-batch` GET same path **with that `$deltatoken`** | `200`, **`"value": []`**, same token returned → **incremental sync works via graph-batch** |
| `list-mail-folder-messages-delta` with `mailFolderId=inbox`, `$top=2`, `$deltatoken=<the same token>` | **token ignored** → 2 most-recent messages returned again, **new** deltatoken → a fresh full sync, not a diff |

Two corollaries from that last row:
- **`mailFolderId`, not `mailFolder-id`** — the hyphenated form fails schema validation (`Required at mailFolderId`).
- **Response cost is real.** Those 2 messages came back with full `body.content` (~9 KB of newsletter text) because no `$select` was given. The server sets `Prefer: outlook.body-content-type="text"` by default (`MS365_MCP_BODY_FORMAT`, `graph-tools.js:780`), so bodies arrive as plaintext — useful for a markdown mirror, ruinous if you fetch bodies during change *detection*. Detect with `$select=id,changeKey,subject,from,receivedDateTime,hasAttachments,internetMessageId`; fetch bodies only for the diff.

**Pagination / deltaLink handling.** Pagination is **on by default** (`paginationAllowed()` returns `true`
when `MS365_MCP_ALLOW_PAGINATION` is unset, `lib/param-descriptions.js:9-13`) but is **opt-in per call**
via `fetchAllPages: true`. Caps: `MS365_MCP_MAX_PAGES` default **100**, `MS365_MCP_MAX_ITEMS` default
**10,000** (`graph-tools.js:75,880-881`). When merging pages it strips `@odata.nextLink` and **preserves
the final `@odata.deltaLink`** (`graph-tools.js:882-917`), and `graph-client.js:260,289` keeps
`@odata.nextLink`/`@odata.deltaLink` while stripping other `@odata.*` annotations — so an initial crawl
*can* be completed through the MCP and the token *is* handed back to the caller.

**The server persists nothing.** There is no deltaLink store anywhere in `dist/`; the token exists only
in the tool's text response. **Token custody is the pipeline's job** — which is exactly right for the L1
"since token" design, but means an agent that forgets to write it down has thrown away the diff.

**Also present and useful:** `create-subscription`, `list-subscriptions`, `update-subscription`,
`reauthorize-subscription`, `delete-subscription`; `get-channel-files-folder` (Teams channel → the
SharePoint `driveId` + folder id, i.e. the bridge from a Teams channel to a delta-able drive);
`get-download-url`, `download-bytes-to-file` (out-of-band byte fetch, writes straight to a local path in
stdio mode). Teams coverage is flat list endpoints only (`list-chat-messages`, `list-channel-messages`).

---

## Answers to the four key questions

**(a) Can Teams messages be pulled incrementally under delegated auth without protected-API approval?**
**Partly — channels yes, chats no.**
- `/teams/{team}/channels/{channel}/messages/delta` — **yes**, delegated `ChannelMessage.Read.All` (admin-consent scope, but an ordinary one). Not protected, not metered. Cost: you must enumerate teams+channels and hold one token per channel.
- `/users/{id}/chats/getAllMessages/delta` — **no**. `Delegated (work or school account) | Not supported`, application-only, *and* protected: *"Microsoft Teams APIs in Microsoft Graph that access sensitive data are considered protected APIs."*
- `/chats/{chat-id}/messages/delta` — **undocumented permissions**. The cmdlet exists and takes a `-ChatId`, but Microsoft ships no permissions table for it. Treat as unverified; probe it before designing around it.
- Practical consequence: for the /docs-source use case, **Teams *files* are not in Teams** — they live in the channel's SharePoint library (`get-channel-files-folder` → `driveId`), so channel documents are covered by the drive-delta path and need no Teams message permission at all. Only the *conversation text* needs these scopes.

**(b) Do mail delta responses include body/attachments or only ids?**
**Full message by default, ids only if you ask.** The doc's own example returns `body: {contentType, content}`;
measured, the MCP returned complete plaintext bodies. `$select` is supported (`id` always returned), so
you choose. **Attachments are a separate hop** — delta returns `hasAttachments` and supports `$expand`,
but the MCP's own `$expand` description warns *"expanding a non-navigation property such as a message
body fails… an unsupported value may be ignored rather than reported"*; use `list-mail-attachments` +
`download-bytes-to-file` per changed message.

**(c) Subscription webhooks need a public HTTPS endpoint — what are the non-webhook options?**
Three delivery channels: **webhooks**, **Azure Event Hubs**, **Azure Event Grid**. Webhooks are
non-negotiable on the public endpoint: *"Before you can receive a notification via webhooks, you must
create a publicly accessible, HTTPS-secured endpoint that is addressable via URL. If your endpoint isn't
publicly accessible, Microsoft Graph doesn't send notifications"* — plus a 10-second plaintext
`validationToken` echo, a 3-second 2xx budget, a "slow" mark at >10% timeouts in 10 min and a "drop" mark
at >15%, with *"Dropped notifications can't be recovered."*
Event Hubs removes the public URL (*"You don't rely on publicly exposed notification URLs… You can ignore
the validation message"*) but substitutes Azure: *"You need to provision an event hub… You need to
provision an Azure Key Vault or add the Microsoft Graph Change Tracking service to the Data Sender role
on your event hub"*, with `notificationUrl: EventHub:https://<ns>.servicebus.windows.net/eventhubname/<hub>?tenantId=<domain>`.
**For a corporate macOS laptop with restricted Entra, the honest fourth option is no subscription at all:
poll delta on a timer.** The measured empty-diff call is nearly free (`"value": []`), and Microsoft's own
scale guidance already prescribes a periodic delta as the safety net — *"we recommend no more than once
per day for this periodic check"* — with the caveat that it also warns *"Polling the service repeatedly
or at high rates causes your app to be throttled."* A 15-min-to-hourly cadence per drive sits between
those two sentences and is a judgement call, not a documented number.

**(d) Does the local MCP persist deltaLinks or hand them back?**
**Hands them back, stores nothing** — and cannot accept one back, per the finding above.

---

## Adversarial pass — three things that would bite the design

1. **Microsoft's two file-change docs contradict each other on `cTag`, and the wrong one is the friendlier one.** scan-guidance says *"you can use the cTag property to determine if the contents of the file have changed since the last time you downloaded it."* driveitem-delta's Remarks says delta query **omits `ctag`** for **OneDrive for Business** on Create/Modify — i.e. exactly the corporate case. Whether `$select=cTag` forces it back is **undocumented**. The safe content identity is **`file.hashes.quickXorHash`**: *"quickXorHash is the only value that is guaranteed to be available for both OneDrive for work or school and OneDrive for home"* (and *"sha256Hash — This property isn't supported. Don't use."*). This is what makes same-name-overwrite detectable without downloading — **but only if you `$select` `file`/`file.hashes` and store the hash in L2**. Fall back to `(size, lastModifiedDateTime, eTag)` where the hash is absent.
2. **A folder rename emits exactly one change event and no descendants** — *"renaming a folder doesn't result in any descendants of the folder being returned from delta"*, and `parentReference.path` is never populated. An L2 manifest keyed on **full path** silently rots the instant someone renames `/docs-source/Client A/` . Key on `driveId+itemId`, store `parentReference.id`, and re-derive paths from your own tree. This also means the messy-version-suffix case (`Deck v3 FINAL.pptx` → `Deck v4.pptx`) arrives as an id-stable rename, which is *better* than the operator feared: same id ⇒ same L3 markdown page, one provenance update.
3. **"Always synced" has a 6-hour worst case you cannot engineer away.** driveItem and SharePoint-list notification latency is *"Less than 1 minute"* average, *"6 hours"* maximum — an order of magnitude worse than mail (3 min) or Teams (1 min). A webhook-only design will occasionally look broken. State the SLA as *typically <1 min, guaranteed within 6 h, plus a daily reconciling delta*, and drive the UI from git (L5) rather than from notification arrival.

Two smaller traps: the delta `410 Gone` resync is a **full re-enumeration of the drive**, so the L2
manifest must be able to diff a full listing against itself cheaply (this is the one case where the whole
corpus is re-listed — metadata only, no bytes); and `token=latest` / `token=<timestamp>` (ODB+SharePoint
only) lets you **skip the initial crawl entirely** when you only care about changes from now on, which is
the cheapest possible bootstrap for a 100 GB library.

---

## Alternatives considered and ruled out

| Alternative | Ruled out because |
|---|---|
| Use the MCP's `get-drive-delta` / `list-mail-folder-messages-delta` as L1 | Silently drops the token → every call is a full sync. Measured. |
| `chats/getAllMessages` + `$filter=lastModifiedDateTime gt <last run>` as the Teams diff | Application permission + protected-API approval + Teams licence for every exported user. Also *"If a message is retrieved through metered APIs multiple times, it's billed multiple times"* — historically; metering ended 2025-08-25, but the approval gate did not. |
| Event Grid / Event Hubs for a laptop-hosted pipeline | Needs an Azure subscription, an Event Hubs namespace, and Key Vault or an RBAC role assignment on `Microsoft Graph Change Tracking` (appId `0bf30f3b-4a52-48df-9a82-234910c4a086`) — the same IT dependency the no-API path exists to avoid. |
| Paging `/children` instead of delta for the initial crawl | *"Other approaches, such as paging through the children collection of a folder, are not guaranteed to return every single item if any writes take place during the enumeration. Using delta is the only way to guarantee that you've read all of the data you need to."* |
| Mailbox-wide mail delta | Does not exist. Delta is folder-scoped (`/me/mailFolders/{id}/messages/delta`); one token per folder. |

---

## Pipeline-slot mapping

| Slot | Concrete mechanism |
|---|---|
| **L1 acquisition** | One `token=latest`-or-full `drive/root/delta` per document library + per OneDrive; one folder-scoped `messages/delta` per watched mail folder; one `channels/{id}/messages/delta` per watched channel. Calls issued over **own HTTP client or `graph-batch`**, never the MCP delta tools. Optional `create-subscription` per drive as a doorbell, with `update-subscription` renewal inside the 42,300-min ceiling; without it, a timer. |
| **L2 manifest** | Key `(driveId, itemId)`; store `quickXorHash` (or `size+lastModifiedDateTime+eTag`), `parentReference.id`, `name`, and the per-source token. Change classes: new id · same id new hash (in-place overwrite) · same id new name/parent (rename/move) · `deleted` facet · `@removed reason=deleted` for mail. |
| **L3 converters** | Fetch bytes only for hash-changed items — `get-download-url` for large files, `download-bytes-to-file` for mail attachments and anything Graph won't pre-authenticate. Mail bodies already arrive as plaintext via the `Prefer: outlook.body-content-type` default. |
| **L4 curation** | Driven by the L2 change set, so the agent's read set is O(changes). |
| **L5 git** | Unchanged by this axis. |

---

## Named gaps

- **`/chats/{chat-id}/messages/delta` permissions are undocumented.** Needs a live probe in the target tenant.
- **Whether `$select=cTag` restores `cTag` in an ODB delta feed** is undocumented; the two Microsoft docs disagree on whether `cTag` is usable at all.
- **8-month delta horizon** is documented for `getAllMessages/delta` only; not stated for the per-channel path.
- **Per-folder (non-root) driveItem delta.** The MCP tool and the SDK model `/drives/{id}/items/{itemId}/delta`, but the reference page's HTTP request list is **root-scoped only**. Treat drive-root delta as the contract; a single-document-library `/docs-source` makes this moot.
- **No documented polling cadence** between scan-guidance's "no more than once per day" safety net and its throttling warning.
- The subscription ceilings and latencies quoted here are from a doc page dated `updated_at: 2026-04-07`; re-read before committing to a renewal schedule.

## Sources

- https://learn.microsoft.com/en-us/graph/api/driveitem-delta?view=graph-rest-1.0
- https://learn.microsoft.com/en-us/graph/api/message-delta?view=graph-rest-1.0
- https://learn.microsoft.com/en-us/graph/api/chatmessage-delta?view=graph-rest-1.0
- https://learn.microsoft.com/en-us/graph/api/chatmessage-delta?view=graph-rest-beta
- https://learn.microsoft.com/en-us/graph/change-notifications-overview
- https://learn.microsoft.com/en-us/graph/change-notifications-delivery-webhooks
- https://learn.microsoft.com/en-us/graph/change-notifications-delivery-event-hubs
- https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/scan-guidance
- https://learn.microsoft.com/en-us/graph/api/resources/hashes?view=graph-rest-1.0
- https://learn.microsoft.com/en-us/graph/teams-licenses
- https://learn.microsoft.com/en-us/microsoftteams/export-teams-content
- https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.teams/get-mgteamchannelmessagedelta?view=graph-powershell-1.0
- https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.teams/get-mgchatmessagedelta?view=graph-powershell-1.0
