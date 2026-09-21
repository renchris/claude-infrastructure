# C4 — rclone as the OneDrive/SharePoint → `docs-source` acquisition engine

**Verdict, up front:** rclone is the right **transport** for L1 and the wrong **change detector**.
`--onedrive-delta` does **not** give you `O(changes)`. It is a *recursive-listing* accelerator
(`ListR`/`--fast-list`) that calls `/root/delta` **with no token**, i.e. a full enumeration of the
drive on every single run. rclone has a second, real delta-token loop — but it is wired only to
`ChangeNotify` (mount/VFS polling), it starts at `token=latest`, and its token lives in a local
variable that dies with the process. **No stock rclone command persists a `deltaLink` across runs.**
So the lead's sample row — *"Golden example: rclone `--onedrive-delta`"* against *"O(changes) listing
since a deltaLink"* — is **wrong as written** and needs correcting in the design doc.

The consequence is concrete and measured: a stateless `rclone sync` of a ~0.5M-item SharePoint
library spent **482 `/delta` calls and ~11 minutes** deciding *nothing had changed* (issue #9226,
below). That is the per-run floor rclone imposes unless you supply the change set yourself.

Versions pinned throughout. Latest release at time of writing: **v1.75.1 (2026-09-04)**
(`https://downloads.rclone.org/version.txt`, fetched 2026-09-21).

**Instrument caveat (blocker):** `rclone` is **not installed on this machine** (`which rclone` → not
found). Every claim below is from **source at `rclone/rclone@master`** or **released docs**, not from
a local execution. Nothing here was measured by me; the one performance measurement quoted is a
third party's, in the issue thread.

---

## 1. The two delta paths in the OneDrive backend — the load-bearing finding

| | Path A — `ListR` (what `--onedrive-delta` enables) | Path B — `ChangeNotify` |
|---|---|---|
| Entry point | `backend/onedrive/onedrive.go:1594` | `backend/onedrive/onedrive.go:3077` |
| Request | `GET /root/delta` with **`// "token": {token},` commented out** (`:1596`) | `GET /drives/{driveID}/root/delta?token=<token>` (`:3139-3153`) |
| First token | none ⇒ **full enumeration** | `changeNotifyStartPageToken` → `delta?token=latest` (`:3118-3122`) ⇒ sees only changes **after process start** |
| Token persistence | n/a | `nextDeltaToken` is a **local variable** in the goroutine (`:3080`, `:3109`); dies with the process |
| Reaches `sync`/`copy`/`check` | **yes** (advertises `ListR` ⇒ `--fast-list`) | **no** — consumed by VFS polling (`--poll-interval`) only |
| Deletes | tombstones dropped: `if item.Deleted != nil { continue }` (`fs/…/onedrive.go:1377`) | reported only if the item still carries a `file`/`folder` facet (`:3166-3189`) |

Empirical, source-quoted:

> `{ Name: "delta", Default: false, Help: … "If set rclone will use delta listing to implement recursive listings." … "**However** the delta listing API **only** works at the root of the drive. If you use it not at the root then it recurses from the root and discards all the data that is not under the directory you asked for."` — `backend/onedrive/onedrive.go:427-444`; identical text in `docs/content/onedrive.md:833-865` (released, v1.75.1).

> `// ListR only supported if delta set` / `if !f.opt.Delta { f.features.ListR = nil }` — `onedrive.go:1219-1221`.

And the flag's own doc says what it is *for*, and it is not sync:

> "Setting this flag speeds up these things greatly: `rclone lsf -R onedrive:` / `rclone size onedrive:` / `rclone rc vfs/refresh recursive=true`" — `docs/content/onedrive.md:841-845`.

**Theoretical (reasoning):** `--track-renames` carries the same architectural stamp —
`docs/content/docs.md:2786`: *"`--track-renames` is stateless like all of rclone's syncs."* Statelessness
is a design commitment of the whole tool, not an omission in the OneDrive backend. Do not expect a
future flag to turn `rclone sync` into an `O(changes)` operation; expect to own the cursor yourself.

### Cost arithmetic for Path A (empirical, third-party)

`--onedrive-list-chunk` default is **1000** (`docs/content/onedrive.md:654-665`), so a full delta
enumeration is ⌈items/1000⌉ requests. Measured in rclone#9226 by the reporter, on a SharePoint
library of "nearly two million folders and one million files":

> "In this run, there were `482` calls to the `/delta` API." … `09:34:58` start → `09:45:51` "There was nothing to transfer" — **~653 s, ~1.35 s/call** (chscott, 2026-03-09).

After ncw's fix, the same run: "there was a single call to the `/delta` API", `09:47:06` → `09:47:08`.
Merged 2026-07-12, shipped **v1.75.0 (2026-07-31)** as *"Fix unnecessarily listing dst directory when
src listing finished"* (`docs/content/changelog.md`, v1.75.0 sync section). Issue state via GitHub API:
`9226 closed completed`.

⚠️ **Read that fix narrowly.** It early-outs the **destination** listing once the **source** listing
finishes and nothing is left to transfer. In our pipeline the remote is the **source**, so it does
**not** help: the full remote enumeration is exactly what must complete. It helps only the inverse
direction (local → SharePoint).

---

## 2. Capability table (sample-row shape)

| Mechanism | Gives | Golden example / pin | Limits | Pipeline slot |
|---|---|---|---|---|
| `--onedrive-delta` (`delta = true`) | `ListR`/`--fast-list`: whole-drive listing in ⌈n/1000⌉ requests instead of one request per directory; server-side **QuickXorHash + size + mtime for free in the listing** | added **v1.65.0** (2023-11-26), *"Implement ListR method which gives `--fast-list` support … This must be enabled with the `--onedrive-delta` flag"* (changelog v1.65.0) | **Not incremental** (no token, `:1596`). **Root-only** — off-root recurses from root and discards. Reporter measured 482 calls / 11 min for ~0.5M items | L1 listing accelerator — **not** a change cursor |
| `rclone sync` default comparison | size + modtime, no download, no hash read | `docs/content/docs.md` §`--size-only`: *"Normally rclone will look at modification time and size of files to see if they are equal."* OneDrive mtime accurate to 1 s (`onedrive.md:290-293`) | **Same-name in-place overwrite is caught** (mtime moves). A same-size, same-mtime content swap is **not** | L1/L2 — the cheap change test |
| `--checksum` | QuickXorHash on both sides; catches same-size/same-mtime swaps | QuickXorHash is registered **globally** by the backend (`onedrive.go:122 hash.RegisterHash("quickxor", …)`) and `local` returns `hash.Supported()` (`backend/local/local.go:1200`) ⇒ **rclone can compute quickxor over local files** | Local side has no stored hash — *"on backends (such as local) where hashes must be computed on the fly"* (`docs/content/bisync.md:395-399`) ⇒ reads the entire local corpus each run. 100s of GB ⇒ audit-only, never the hot path | L2 verification, run on a schedule |
| `--track-renames` (+ `--track-renames-strategy hash`) | a rename becomes a local `Move`, not a re-download | `docs.md:2772-2807`; default strategy `hash` (`:2809-2830`) | *"stateless like all of rclone's syncs"*; **incompatible with `--no-traverse`**; forces `--delete-after`; extra RAM for all candidates; hash strategy dies on the SharePoint Office-file mutation (§4) | L1 rename handling (Tier A only) |
| `--use-json-log` + `-v` | **NDJSON change list**: each line carries `"object"` (the path) and `"objectType"` alongside `msg` | `fs/log.go:147-164` (`"object", object, "objectType", …`); `--use-json-log` since **v1.49.0**, slog rewrite **v1.70.0**. Action strings: `"Copied (new)"`, `"Copied (replaced existing)"`, `"Copied (server-side copy)"` (`fs/operations/copy.go:169,204-237`), `"Deleted"` (`operations.go:566,581`), `"Updated modification time in destination"` (`operations.go:354`) | Log format, not an API: the strings are unversioned English. Gate on `.msg` prefix `Copied`/`Deleted`, and pin the rclone version | L2 — *what did this pull change?* |
| `rclone check --combined -` | a **machine-readable diff** with a stable 5-symbol vocabulary: `= ` identical, `- ` dest-only, `+ ` source-only, `* ` present-both-differ, `! ` error | `rclone.org/commands/rclone_check/`; also `--differ`, `--missing-on-src`, `--missing-on-dst`, `--match`, `--error` as separate files | Compares two live trees ⇒ costs a full listing of both (and a full local hash pass with `--checksum`) | L2 reconciler / drift auditor — the right *audit*, wrong *cursor* |
| `rclone lsjson -R --hash --hash-type quickxor` | a content-addressed **manifest** (Path, Size, ModTime, Hashes, **ID**) in one pass | `rclone.org/commands/rclone_lsjson/` | full listing per run; with `--onedrive-delta` that is ⌈n/1000⌉ requests | L2 manifest producer — cheapest honest snapshot |
| `rclone bisync` | **the only rclone command that keeps state between runs**: prior listings in `~/.cache/rclone/bisync` as `path1..path2.lst`, and computes `New`/`Newer`/`Older`/`Deleted` per side against them | `docs/content/bisync.md:151-154`; `--track-renames` support **v1.66**; `--compare`/`--ignore-listing-checksum` v1.66 | Still **lists both sides in full each run** — the state saves *transfers*, not *listing*. Bidirectional (wrong shape for a read-only inbox). Scale: user-reported **1.96M files ⇒ 140 MB listing, ~30 s load, ~1 GB RAM** (`bisync.md:1879-1881`). Critical error renames `.lst`→`.lst-err` and **blocks all future runs until `--resync`** (`:975-977`). `--max-delete` default 50% abort | L2 reference implementation to copy, **not** to deploy |
| `--files-from-raw` + `--no-traverse` (with `copy`/`delete`) | **the genuine `O(changes)` door**: *"an rclone command does not traverse the remote. Instead it addresses each path/file named in the file individually. For each path/file name, that requires typically 1 API call."* (`docs/content/filtering.md:625-630`) | `filtering.md:607-640`, `:714` | `--no-traverse` *"is not compatible with `sync` and will be ignored if you supply it with `sync`"* (`docs.md:2326-2331`) ⇒ **`copy` only, so deletes need their own pass**; incompatible with `--track-renames` | **L1 transport for Tier B** |
| `--backup-dir <dir>` | replaced/deleted files are **moved aside instead of destroyed** — gives L3 the *previous* bytes of a same-name overwrite, and is Microsoft's own documented workaround for SharePoint's "item not found" on replace/delete (`onedrive.md:1268-1283`) | `onedrive.md:1276-1283` | costs disk; you own retention | L1→L3 — makes same-name updates diffable |
| `--user-agent "ISV\|rclone.org\|rclone/v1.75.1"` | SharePoint traffic decoration; MS blocks undecorated heavy callers | `onedrive.md:1235-1242`: *"If you experience excessive throttling or is being blocked on SharePoint then it may help to set the user agent explicitly"* | cosmetic if your call rate is already abusive | L1 hygiene, **not optional** on SharePoint |
| Backoff | honours `Retry-After` on **429/503** exactly (`onedrive.go:962-973`), pacer `minSleep 10ms`/`maxSleep 2s`/`decayConstant 2` (`:49-51`, `:1163`) | source | pacer is per-`Fs`; `--transfers`/`--checkers`/`--tpslimit` are yours to set. MS: *"Apps that do not honor the retry after duration before calling back will be blocked due to abusive calling patterns"* (scan-guidance) | L1 |

### Auth in a locked-down tenant — three rungs, all released

1. **Own app registration, single-tenant.** Set `auth_url`/`token_url` to
   `https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/{authorize,token}`; account type
   *"Accounts in this organizational directory only"* (`onedrive.md:181-199`). Device-code flow exists
   for headless boxes (rclone "remote setup").
2. **App-only (client credentials)** — `client_credentials = true` + `tenant`; needs
   `Files.Read.All` / `Sites.Read.All` / `Sites.Selected` as **Application** permissions and an admin
   grant; *"the 'onedrive' option does not work. You can use the 'sharepoint' option or … type it in
   manually with the 'driveid' option"* (`onedrive.md:202-240`). MS's own scanning guidance prefers
   exactly this shape: *"Most scanning applications will want to operate with Application permissions."*
3. **No app registration at all — "no admin mode", shipped v1.75.0 (2026-07-31)** (changelog v1.75.0
   Onedrive: *"Add support for no admin mode (TaterLi)"*). You read `driveAccessToken` /
   `.driveUrl` out of your own logged-in SharePoint session's network tab and configure
   `tenant_url` + `drive_id` + a synthetic `token` JSON with an empty `refresh_token`
   (`onedrive.md:240-289`). **Hard limit, stated in the doc:** *"Since the exact expiry time cannot be
   determined from web traffic, set the expiry to a future date. Note that the token will eventually
   expire and you will need to repeat the process."* Manual, recurring, human-in-the-loop — a bridge,
   not an architecture.

Terminal failure mode worth pre-recognising: `access_denied` **AADSTS65005** — *"This means that
rclone can't use the OneDrive for Business API with your account. You can't do much about it, maybe
write an email to your admins."* (`onedrive.md:1284-1297`). Its documented fallback is the **WebDAV**
backend (`rclone.org/webdav/#sharepoint`) — which has **no delta, no QuickXorHash**, i.e. a full
recursive listing every run and size+mtime only. That is the true floor of the no-API path.

Also standing: **"If you don't use rclone for 90 days the refresh token will expire"**
(`onedrive.md:1113-1119`) — a cron that idles a quarter dies silently.

---

## 3. The concrete recipes

### Tier A — rclone-only. Correct, deletes mirrored, change list emitted. `O(total items)` listing, `O(changes)` bytes.

```sh
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
rclone sync "spo:Shared Documents" /docs-source/spo-clientx \
  --onedrive-delta --fast-list \
  --track-renames --track-renames-strategy hash \
  --backup-dir "/docs-source-attic/spo-clientx/$STAMP" \
  --user-agent "ISV|rclone.org|rclone/v1.75.1" \
  --transfers 4 --checkers 8 --tpslimit 10 \
  --max-delete 100 \
  --use-json-log --log-level INFO --log-file "/var/log/pull-$STAMP.ndjson"
```

Then derive the change set **from the log, not from a re-scan**:

```sh
jq -r 'select(.object != null) | select(.msg|test("^(Copied|Deleted|Moved)")) | [.msg,.object] | @tsv' \
  "/var/log/pull-$STAMP.ndjson" > "/docs-source/.changes/$STAMP.tsv"
```

Why each clause, and the traps:

- **`--onedrive-delta --fast-list`** — turns the listing from one request per folder into ⌈n/1000⌉.
  **Point the remote at the library/drive ROOT.** Off-root it *"recurses from the root and discards
  all the data that is not under the directory you asked for"* (`onedrive.md:849-852`) — correct, and
  a pure waste. For a SharePoint document library the library root *is* the drive root, so this is
  free; for a personal OneDrive where you want one subfolder, it is a trap.
- **No `--checksum`.** OneDrive mtime is second-accurate and rclone writes it to the local file, so
  size+mtime catches in-place same-name overwrites at zero cost. `--checksum` would re-hash the whole
  local corpus every run (`bisync.md:395-399`). Run it **weekly, as an audit** instead:
  `rclone check --checksum --combined - "spo:Shared Documents" /docs-source/spo-clientx`, and page
  the human on any `*` or `!` line.
- **`--backup-dir`** does double duty: it is MS's documented workaround for SharePoint returning
  *"item not found"* on replace/delete of Office and web files (`onedrive.md:1268-1283`), **and** it
  preserves the pre-overwrite bytes so L3 can diff v_n against v_n+1 of a same-named file. Without
  it, an in-place overwrite is unrecoverable and the converter can only see the new state.
- **`--max-delete 100`** — the blast-radius brake. A permission change, a re-scoped `Sites.Selected`
  grant, or a partial listing presents as mass deletion. bisync ships this instinct as a 50% default
  (`bisync.md`); `sync` does not, so set it.
- **`--track-renames`** buys you a local `Move` instead of a re-download when someone reorganises
  folders. It is `hash`-strategy by default and therefore **dies on SharePoint Office files** (§4) —
  degrade to `--track-renames-strategy modtime,leaf` (`docs.md:2809-2830`) for Office-heavy libraries.
- **`--use-json-log`** is the change list. Verified in source, not inferred: `fs/log.go:147-164`
  attaches `"object"` and `"objectType"` to every `fs.Infof(obj, …)`, and the action strings are
  literals in `fs/operations/copy.go:169-237` and `operations.go:566-581`. **Theoretical caveat:**
  those strings are unversioned English prose; pin the rclone version and assert the parser finds
  a non-zero count when `sync` reports transfers, or a silent string change becomes a silent empty
  change set.

### Tier B — you own the `deltaLink`. `O(changes)` end to end. This is what the design needs.

rclone stops being the change detector and becomes pure transport:

1. `GET /drives/{driveId}/root/delta` once, follow `@odata.nextLink` to the end, store the final
   `@odata.deltaLink`. MS: *"Always remember to keep the URL returned by @odata.deltaLink so you can
   efficiently check for the changes later on."* (scan-guidance).
2. Subsequent runs: `GET <deltaLink>` → only changed items. Send
   `Prefer: deltashowremovedasdeleted, deltatraversepermissiongaps` (delta reference, "Scanning
   permissions hierarchies") if you also care about permission-driven visibility changes.
3. Partition into `changed.txt` / `deleted.txt`.
4. Bytes: `rclone copy "spo:Shared Documents" /docs-source/spo-clientx --files-from-raw changed.txt
   --no-traverse` — *"For each path/file name, that requires typically 1 API call"* (`filtering.md:628-630`).
5. Deletes: `rclone delete /docs-source/spo-clientx --files-from-raw deleted.txt` — it is a **local**
   delete, so it is free; `rclone delete` *"obeys include/exclude filters so can be used to
   selectively delete files"* (`rclone_delete.md`, `versionIntroduced: v1.27`). *Theoretical:* an
   empty `--files-from` list selects nothing (*"Rclone processes the path/file names in the order of
   the list, and no others"*, `filtering.md:609-610`) — but I did not execute it, so gate it on a
   non-empty file anyway.

**Four Graph facts that dictate Tier B's data model — all empirical, all from the delta reference, and
each one breaks a path-keyed mirror:**

- *"**When using delta you should always track items by id**"* — and *"renaming a folder doesn't
  result in any descendants of the folder being returned from delta"*, and *"The `parentReference`
  property on items won't include a value for **path**."* ⇒ one folder rename emits **one** event and
  **zero** descendant events. A path-keyed manifest silently keeps the whole subtree at its old path.
  You must hold an **id → path** map and recompute the subtree yourself.
- Tombstones on **OneDrive for Business omit `name`** (delta reference, "Properties omitted by delta
  query": Delete ⇒ `ctag`, `name`). A delete tells you only an **id** ⇒ without the id→path map you
  cannot even name the file to delete locally.
- *"The delta feed shows the latest state for each item, not each change. If an item were renamed
  twice, it would only show up once, with its latest name."* and *"The same item may appear more than
  once in a delta feed … You should use the last occurrence you see."* ⇒ your reducer must be
  last-write-wins per id within a page set, not append-only.
- Token loss is recoverable **twice over**: `HTTP 410 Gone` with `resyncChangesApplyDifferences` /
  `resyncChangesUploadDifferences` plus a `Location` header starting a fresh enumeration — and, on
  **OneDrive for Business and SharePoint only**, `?token=<URL-encoded timestamp>` (*"Using a timestamp
  in place of a token is only supported on OneDrive for Business and SharePoint"*). So a lost cursor
  costs one full enumeration at worst, and often just a timestamp.

**Webhooks replace polling** — this is the piece rclone structurally cannot host. MS: *"Polling the
service repeatedly or at high rates causes your app to be throttled due to excessive calling
patterns"*; drives support the `update` change type; *"We recommend using delta query with your last
change token immediately after you subscribe to webhooks to ensure that you don't miss any changes";*
and, for the safety net, *"you may want to provide a periodic delta query … We recommend no more than
once per day for this periodic check."* That last sentence is the cadence for the Tier A reconcile
pass: **daily at most, and off-peak** — *"Throttling and / or performance slowdowns have a higher
tendency to occur during peak hours … Off peak hours are typically nights and weekends in your
region's time zone."*

### Where rclone can delta a subfolder — it cannot, and neither (documented) can Graph

`onedrive.go:1594` hard-codes `/root/delta`. The temptation is to call this an rclone gap and reach
for `/items/{id}/delta`. **The v1.0 reference's "HTTP request" block lists only root forms:**
`GET /drives/{drive-id}/root/delta`, `/groups/{groupId}/drive/root/delta`, `/me/drive/root/delta`,
`/sites/{siteId}/drive/root/delta`, `/users/{id}/drive/root/delta`. The page's SDK snippets do use an
`.Items["{driveItem-id}"].Delta` builder, so the capability plainly exists in the SDK surface — but it
is **not in the documented v1.0 HTTP contract**, so treat per-folder delta as unsupported until you
measure it against your own tenant. **Design implication:** scope by **drive**, one cursor per
document library / per user OneDrive, exactly as MS's own guidance does (*"Each user's OneDrive
contains a single drive that you can monitor. SharePoint site collections and subsites may have
multiple drives, one for each document library"*). Do not design around one cursor for a subfolder.

---

## 4. SharePoint gotchas that specifically attack *this* corpus

The inbox is PDFs, **Word/Excel/PowerPoint** — the exact file types SharePoint mutates:

> *"It is a known issue that Sharepoint (not OneDrive or OneDrive for Business) silently modifies
> uploaded files, mainly Office files (.docx, .xlsx, etc.), causing file size and hash checks to
> fail."* — `onedrive.md:1244-1267`, whose prescription is `--ignore-checksum --ignore-size`.

**This is the sharpest single caveat in this axis, and it cascades:** the documented cure disables
the two comparators a content-addressed pipeline is built on. Consequences, mostly theoretical
(reasoning from the cited mechanism):

- `--checksum` and `rclone check --checksum` will report `*` (differ) on clean, unchanged Office
  files ⇒ your drift auditor cries wolf on exactly the majority file type.
- `--track-renames-strategy hash` (the default) cannot match Office files ⇒ every folder
  reorganisation becomes a full re-download. Use `modtime,leaf`.
- Do **not** globally set `--ignore-size`: it blinds the cheap size+modtime test too. Better: keep
  size+modtime as the hot path, and scope `--ignore-checksum` to the audit job, treating a hash
  mismatch on an Office extension as *suspect*, never as *changed*, until a byte compare says
  otherwise. Note this affects **SharePoint specifically**, not OneDrive/OneDrive for Business.

Other live edges:

| Edge | Quote / cite | Bite on this pipeline |
|---|---|---|
| Versioning | *"Every change in a file OneDrive causes the service to create a new version of the file. This counts against a users quota. For example changing the modification time of a file creates a second version"* (`onedrive.md:1154-1160`) | **Non-issue for a read-only pull** — nothing is written upward. It only bites if `docs/` is ever synced back, or if a script sets mtimes remotely. `--onedrive-no-versions` is an *upload*-side flag (`onedrive.md:665-687`) and is not needed here. The lead's brief lists this as a live risk; on a download-only design it is not. |
| Path length | *"The entire path, including the file name, must contain fewer than 400 characters"* (`onedrive.md:1136-1143`) | your local mirror path *prefix* is additive — a deep library plus a long `docs-source/<tenant>/<site>/` prefix can exceed macOS/Git limits even where OneDrive is fine |
| Illegal chars | *"if a file has a `?` in it will be mapped to `？`"* (`onedrive.md:1120-1130`, plus the encoding table) | **the local filename is not the remote filename.** Any provenance frontmatter must record the remote **item id** and raw name, never rely on the path round-tripping |
| Case insensitivity | *"OneDrive is case insensitive so you can't have a file called 'Hello.doc' and one called 'hello.doc'"* (`:1120-1123`) | harmless on default case-insensitive APFS; **a hazard if `docs-source` is ever on a case-sensitive volume or in a Linux container** |
| Unicode normalisation | `--no-unicode-normalization`: *"Sometimes, an operating system will store filenames containing unicode parts in their decomposed form (particularly macOS). Some cloud storage systems will then recompose the unicode, resulting in duplicate files"* (`docs.md`) | macOS NFD vs SharePoint NFC. **Leave rclone's default normalisation ON.** Setting this flag on macOS manufactures duplicate files. |
| 100k files/folder | *"OneDrive seems to be OK with at least 50,000 files in a folder, but at 100,000 rclone will get errors listing the directory like `couldn't list files: UnknownError:`"* (`:1144-1153`, issue #2707) | a single flat "Shared Documents" dumping ground is a real failure mode at corporate scale |
| AV block | *"server reports this file is infected with a virus - use --onedrive-av-override to download anyway"*; and the override *"works reliably with application permissions (client_credentials). With delegated (user) login on OneDrive for Business, Microsoft often still blocks the download."* (`onedrive.md:799-832`) | a single flagged file can wedge a run; the workaround's reliability **depends on which auth rung you chose** |
| `cTag` — **two MS docs contradict each other** | scan-guidance: *"you can use the cTag property to determine if the contents of the file have changed since the last time you downloaded it."* Delta reference, same product: OneDrive for Business, Create/Modify ⇒ properties **omitted by delta query**: `ctag`. | **Do not build change detection on `cTag` from a delta feed on ODB/SharePoint.** Use `file.hashes.quickXorHash` + `size` + `lastModifiedDateTime`, and `eTag` only as a tiebreak. Found by reading the two pages against each other; flagging it because the guidance page is the one an implementer reaches first. |

---

## 5. Adversarial pass — what I tried to break, and what survived

- **"Maybe `--onedrive-delta` does persist a token and the commented line is dead code."** Refuted
  two ways: the commented `token` is the *only* token reference in the `ListR` path, and the config
  option's own help text lists only `lsf -R` / `size` / `vfs/refresh` as beneficiaries — no
  sync/copy. A persisted cursor would also need a store, and rclone has exactly one such store
  (`~/.cache/rclone/bisync`), owned by bisync.
- **"bisync is therefore the answer."** No. Its state removes *transfer* work, not *listing* work —
  it refreshes both sides' listings every run (`bisync.md:1879-1890` measures the listing as the
  dominant cost at 1.96M files). It is also bidirectional, which is the wrong safety posture for a
  read-only inbox, and its critical-error mode **locks out all future runs until a human runs
  `--resync`** (`:975-977`) — an unattended pipeline that can wedge on its own error handling.
- **"`--fast-list` alone gets the win."** `--fast-list` is inert on OneDrive unless `delta = true` —
  `ListR` is explicitly nil'd otherwise (`onedrive.go:1219-1221`).
- **"#9226's fix makes the enumeration cheap."** It early-outs the **destination**. Our remote is the
  **source**. No help in this direction — stated because the changelog line reads as if it were
  general.
- **"`--max-age` gives a cheap incremental."** *Theoretical, and it doesn't:* the filter is applied
  while listing, so the listing still happens in full; you save transfers, which size+modtime already
  saved. It also silently misses any item whose mtime the service rewrote backwards.
- **"482 delta calls for 3M items contradicts `list_chunk=1000`."** It does — 3M items should be
  ~3000 pages. Most likely the run was cancelled early, or the reporter's counts describe a different
  scope than the delta-covered set. **I am quoting the wall-clock and call count, not endorsing the
  item count**; the usable figure is **~1.35 s per 1000-item page**, which is the number to plan with.
- **Unverified, and it is the gap that matters most:** I could not execute anything —
  no local `rclone`, no tenant. Specifically untested: whether a real SharePoint document library's
  delta response actually carries `file.hashes.quickXorHash` on every item (the design's
  same-name-overwrite detection assumes it does; Graph's own omission table says only `ctag` goes
  missing on Create/Modify, so the reasoning is sound but it is reasoning), and whether
  `--files-from-raw` + `--no-traverse` really costs one API call per file against SharePoint rather
  than one *plus* a metadata round trip.

---

## 6. Design implications for the L1–L5 hypothesis

1. **Keep rclone. Demote it.** It is L1 *transport* and L2 *auditor*, not the change cursor. The
   layered design's *"per-source since token (Graph deltaLink)"* is exactly right and must be
   **your** code, not a flag.
2. **Correct the sample row in the design doc.** `rclone --onedrive-delta` is not a golden example of
   `O(changes)`; it is a golden example of a **cheap full listing**. The real golden example of
   `O(changes)` on this stack is Microsoft's own scan-guidance loop: *Discover → Crawl → Notify
   (webhook) → Process changes (delta query)*, with `?token=latest` to arm the cursor without a crawl.
3. **Key the manifest on Graph item id, not path.** Forced by three independent Graph facts (folder
   rename emits no descendants; `parentReference.path` absent; ODB tombstones omit `name`). A
   path-keyed manifest is not a style choice here, it is a correctness bug waiting for the first
   folder rename.
4. **One cursor per drive.** Not per folder — the documented v1.0 delta surface is root-only, and
   rclone's is too.
5. **`--backup-dir` is load-bearing, not hygiene.** It is what makes a same-name in-place overwrite
   *diffable* by L3 and simultaneously dodges SharePoint's replace/delete 404.
6. **Two change lists, two purposes.** `--use-json-log` NDJSON is the *"what did my pull do"* record
   (L2 change set → L4 curation trigger). `rclone check --combined` is the *"did my mirror drift"*
   record — schedule it, don't inline it.
7. **Budget the reconcile pass explicitly.** Tier A's floor is ⌈n/1000⌉ delta pages × ~1.35 s. At
   50k items that is ~50 pages / ~1 min — negligible, run it hourly. At 1M items it is ~1000 pages /
   ~22 min — MS's own cadence advice (*"no more than once per day"*, off-peak) becomes the binding
   constraint, and Tier B stops being an optimisation and becomes the only viable design.
8. **Decide the auth rung before the architecture.** Rung 2 (app-only) enables webhooks, tenant-wide
   scope, and the reliable AV override — i.e. Tier B. Rung 3 ("no admin mode", v1.75.0) is a
   human-refreshed token with no `refresh_token` and cannot host an unattended cursor. AADSTS65005
   drops you to WebDAV: no delta, no hashes, full listing every run. **The no-API path is not a
   degraded Tier B; it is Tier A with the accelerator removed**, and the design should say so rather
   than promise parity.

## 7. Open questions a tenant could settle in an hour

- Does a SharePoint document library's `/root/delta` response include `file.hashes.quickXorHash` for
  every item, or only for some? (Decides whether same-name-overwrite detection needs a per-item
  follow-up call.)
- Does `GET /drives/{id}/items/{folderId}/delta` work on v1.0 in practice, despite being absent from
  the documented HTTP request forms? (Would allow one cursor per project folder instead of per drive.)
- Measured cost of `rclone copy --files-from-raw --no-traverse` per file against SharePoint —
  one API call, as `filtering.md` claims, or more?
- Observed `deltaLink` lifetime before `410 Gone` in this tenant. MS documents the error but no TTL;
  this sets the reconcile cadence and whether the timestamp-token fallback is ever needed.
- Whether the SharePoint Office-file mutation reaches **downloaded** bytes (changing the local hash
  run-to-run) or only the server-side stored size/hash. The rclone doc describes upload-side
  corruption; a pure-download pipeline may be unaffected, which would restore `--checksum` as a
  usable auditor.
