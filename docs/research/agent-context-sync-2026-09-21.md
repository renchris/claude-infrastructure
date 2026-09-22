# Always-synced agent context: `docs-source` → `docs`, diff-only — the architecture

*2026-09-21. Research wave of 14 axes (12 productive, 2 adversarial) plus 10 adversarial verifiers on the load-bearing claims. Per-axis reports and verifier reports are in `agent-context-sync-2026-09-21/`. Everything marked **measured** was run on this Mac or against a live Graph tenant during the wave; everything marked **documented** is quoted from a vendor reference; the rest is reasoning and says so.*

## The answer in one screen

**Do not symlink `docs-source` at the OneDrive/SharePoint folder.** The agent's own tools cannot see through it: Claude Code's Glob and Grep are ripgrep wrappers with no follow flag, ripgrep does not descend a symlinked directory met during a walk, BSD `grep -r`/`-R` and `find` do not either, and `git` stores the link as a mode-120000 blob so nothing under it is ever diffed. All of that returns exit 0 with no diagnostic (measured, 3-file fixture: 1 of 3 files found; `find <link> -type f` returns zero rows — the bare form prints only the link). A symlink is *access*, and even that is unreliable; it is never *change awareness*, because it carries no since-token.

**"The diff" comes from three things, never from re-reading the corpus:**

1. **A since-token per source** — Graph `deltaLink` for OneDrive/SharePoint/mail/Teams channels; a persisted FSEvents event id for a local folder; a manifest reconcile for a manual drop. Every one of these tokens expires into a full re-enumeration by design (410 Gone, journal wrap, daemon restart), so the load-bearing decision is making the full reconcile *cheap* (metadata only, zero file bytes), not choosing the perfect token.
2. **A manifest keyed on stable identity, with three hashes.** Identity is the Graph `driveItem.id` (or `(fileid, gen_count)` locally), never the path — a folder rename emits one delta record and no descendants. Hash H0 is the stat tuple (decides whether to read bytes at all); H1 is a canonical content hash (decides whether to convert); H2 is the hash of the converter's *output* (decides whether anything downstream changed). Same-name in-place overwrites are caught with zero download by the provider hash (`quickXorHash`) where the server supplies it, and by H0 — then H1 on the survivors — locally otherwise.
3. **A derived layer that is a pure function of the source, tracked in git.** `docs/mirror/` is 1:1 machine-generated with content-derived frontmatter only; `docs/topics/` is agent-curated and pins the mirror version each page was written against. "What changed since I last looked" is then `git log --since`, and "which curated pages are stale" is one awk pass over `DEPENDS.tsv` (§4.5).

**The golden examples, as they actually work (not as the marketing says):** Cursor's Merkle-sync generation does two-level content addressing — a per-file/dir SHA-256 Merkle tree with a documented 10-minute hash-mismatch poll (security page as archived 2026-01; the sentence is gone from the live page, and its current default search is a local, embedding-free index) for the *what*, and an embedding cache keyed on chunk content hash for the *cost*; its set-semantics sync makes a rename a delete+add and that is where its users see stale indexes. DeepWiki regenerates a whole wiki as one unit on a human button; 12 of 12 public wikis measured stale (median ~1 month). The genuinely reusable incremental machinery lives below prose: Microsoft's own scan guidance (Discover → Crawl → Notify → Process-changes with a daily reconcile), Zoekt's 7-state freshness verdict and tombstone-with-restore-window, LangChain's RecordManager (hash-as-id gives chunk-level reuse), Glean's 20 % stale-deletion circuit breaker, git's index stat cache, ninja's `restat`/`cleandead`, Bazel's action key with the tool version in it, and Time Machine's FSEvents ladder. The one component with **no** precedent anywhere is the many-sources→one-curated-page dependency map; it is the highest-risk part and should be prototyped on ~20 pages first.

**What to measure on the corporate tenant before committing L1** (none of these could be measured here — the work account is logged out, and this Mac has the OneDrive client and File Provider extension installed but no signed-in sync domain, so no dataless placeholder exists to probe): whether `file.hashes.quickXorHash` arrives in delta responses for the SharePoint libraries in scope (Microsoft's guarantee names only OneDrive work/school and home; libraries are unnamed either way); whether the tenant's user-consent policy lets a non-admin consent to `Files.Read.All`/`Sites.Read.All` (the permissions reference says **no admin consent is required** for the delegated variants, but Microsoft's *default* consent policy excludes `Files.Read.All`, `Files.ReadWrite.All`, `Sites.Read.All` and `Sites.ReadWrite.All` from what end users may grant — so it is a tenant setting, not a permission property); whether FSEvents fires on `~/Library/CloudStorage` for a colleague's edit; whether downloaded bytes of a sensitivity-labelled file are the same on two downloads. §9 gives the exact probes.

---

## 1. Scope

**Restatement.** Keep `/docs` — a semantically named, organized, predominantly-markdown folder that the agent can read and grep without a tool call into a binary — always synced to `/docs-source`, an inbox of raw corporate assets from Outlook, Teams, OneDrive and SharePoint (PDF, Excel, Word, PowerPoint) that change in place under the same name, get re-uploaded with messy version suffixes, and get deleted. Tens of thousands of files, tens to hundreds of GB. Corporate macOS, M365 tenant, IT may restrict app registrations. Identify and process only the diff; be token- and operationally-efficient for the agent that consumes `/docs`.

**Question type:** architectural + operational. Cursor/TurboPuffer and DeepWiki were researched as pattern subjects because the ask names them as golden examples.

---

## 2. Golden examples — what transfers and what does not

| System | Mechanism (documented / measured) | Transfers | Does not transfer |
|---|---|---|---|
| **Cursor codebase index** | Merkle tree of per-file + per-directory SHA-256; client and server compare trees root-down, "entries whose hashes differ get synced, entries that match are skipped"; "every 10 minutes we check for hash mismatches" (security page, archived 2026-01); embeddings cached "by chunk content"; obfuscated relative path + line range stored per vector; deletions fall out of set comparison so a rename = delete + add (forum 144970: staff remedy is a manual rebuild) | Two-level content addressing: file-level *what changed* + content-keyed cache for the expensive step. The 10-minute poll over hashes, with a manual `--reconcile`. | The tree itself (it saves re-shipping ~3.2 MB of manifest per 50 k files to a *remote* peer — irrelevant on one filesystem, where a flat manifest is equally O(changes) and detects renames better). Path obfuscation (destroys greppability). The vector store: Cursor's own A/B gives embeddings +0.3 % on code retention overall (+2.6 % past 1,000 files) and its current default search is a local, embedding-free index. |
| **turbopuffer** | Upsert-by-id with whole-document overwrite; one WAL entry per namespace per second, so writes must batch; async indexing with observable `unindexed_bytes` | One write per sync cycle, not per file. Freshness as an observable, not an assumption. | Nothing else; there is no vector store in this design until grep is measurably failing. |
| **DeepWiki / Devin Wiki** | One source commit per whole wiki; human-gated refresh; billed per wiki (Low effort free, Medium ~5-10 ACUs, High ~20-40 ACUs); page manifest is prose "purpose" with no source binding; **measured: 12/12 public wikis stale, median ~1 month, worst 17 months** | The `purpose:` field on a curated page ("what this page is NOT"). The 30-80 page cap as a cost control. | Everything about freshness. Its per-page source citations are the raw material for invalidation and it does not use them. |
| **Zoekt (Sourcegraph)** | 7-state freshness verdict: missing / corrupt / format-version / options-hash / metadata-only / content / equal; incremental skip keyed on a hash of only the build options that can invalidate output; file tombstones in existing shards; deletion is soft (trash, 24 h restore window, vacuum); rename detection OFF; falls back to full build on any unmet precondition and logs it | The multi-state verdict (metadata-only ⇒ rewrite frontmatter, options-mismatch ⇒ converter changed). Soft deletes with a restore window. Loud fallback to full. | Nothing; it is the closest engineering precedent. |
| **Cody embeddings** | Incremental per commit with a 24 h minimum interval per repo; retired partly because keeping the derived layer fresh was an operational burden | Debounce the *expensive* derived layer per subject, never per event. | — |
| **Sphinx** | `note_dependency`: a documented page→source edge set driving affected-document-only rebuilds | The only shipped page↔source dependency model. | — |
| **Microsoft scan guidance** | Discover → Crawl (`/delta`) → Notify (webhook: "something changed under the subscribed folder, call delta" — the notification names the *subscribed folder*, not the item) → Process changes (stored `deltaLink`: "Always remember to keep the URL returned by @odata.deltaLink"); periodic reconciling delta "no more than once per day"; the SharePoint throttling reference adds "Delta with a token is the most efficient way to scan content in SharePoint" (1 RU vs 2 for children paging), and the delta reference is the enumeration that stays complete under concurrent writes | The whole L1 loop, verbatim. | Its cTag advice (delta omits cTag on OneDrive for Business create/modify — use `quickXorHash`). |
| **Onyx (ex-Danswer) SharePoint connector** | Polls delta with a URL-encoded ISO timestamp token; falls back to full delta on 410; **discards Graph's delete tombstones** and recovers deletes from a separate prune job (indexed ids − listed ids); attributes items by `max(createdDateTime, lastModifiedDateTime)` because a copied file keeps its original mtime | `max(created, modified)` for the manual inbox. The id-set prune as a backstop. | Throwing away free tombstones. |
| **LangChain indexing API** | Document id = hash(content + metadata); unchanged chunk ⇒ `record_manager.exists()` ⇒ timestamp refresh only; `incremental`/`scoped_full` cannot delete a vanished source | Hash-as-id for chunk-level reuse; keep positional/temporal fields out of the hashed payload. | Its deletion blindness. |
| **Glean bulk indexing** | The full listing IS the reconcile; anything absent is deleted; a circuit breaker pauses removals for 7 days when deletions would exceed 20 % | The 20 % stale-deletion breaker — floored at 25 rows and scoped per source (§4.1 #6). | — |
| **git index** | Stat tuple (type, exec bit, mtime, ctime, uid, gid, ino, size — st_dev deliberately excluded); racily-clean correction; cache-tree with upward invalidation; `textconv` cache keyed on config string but not binary version (its documented defect) | The stat tuple, both halves of the racily-clean fix, cache-tree invalidation. | Keying a derived-output cache without the converter version. |
| **ninja / Shake / Bazel** | `restat` early cutoff (hash the output, stop if identical); `cleandead` (delete outputs whose rule is gone); action key = digest(inputs, tool + version, normalized args, sorted env) | All three verbs. | A build system. DVC is disqualified: outputs deleted at `repro` start, 343 per-file stages cost ~4 min of bookkeeping, deletion needs three manual steps. |
| **Time Machine / FSEvents** | fseventsd per-volume journal event ids "guaranteed to always be increasing … even across system reboots", valid only with a matching device UUID; `MustScanSubDirs` demands a rescan | The three-tier ladder: live stream → resume-from-stored-id → full metadata walk. | Watchman as the token (its clock encodes daemon pid + start time; any restart is a fresh instance and a full recrawl; journal resync defaulted off in 2021). fswatch (hardcodes SinceNow). |

---

## 3. The symlink question, settled

| Tool the agent uses | Symlinked directory met during a walk | Symlink given as the explicit start path | Fix |
|---|---|---|---|
| Claude Code `Grep` / `Glob` (ripgrep wrappers: `rg --files --glob … --sort=modified` and `rg --hidden --glob '!.git' … --max-columns 500`; neither passes `--follow`, neither input schema has a follow parameter — `sdk-tools.d.ts`, bundle strings for 2.1.114 and 2.1.183) | skipped, exit 0 — symlinked **files** met during the walk are skipped too | traversed (`path` is ripgrep's positional argument) | none available to the agent; aim `path` at the link itself |
| `rg` 15.2 | skipped | traversed | `-L/--follow` |
| BSD `grep -r` and `-R` | skipped (macOS `-R` does **not** follow) | — | `-S` |
| BSD `find` | skipped; **`find <link> -type f` on a symlinked start dir returns 0 rows** (bare `find <link>` prints the link itself) | — | `-H` or trailing `/` |
| zsh `**/` | skipped | — | — |
| `git` | stores `120000 <blob>`; nothing beneath is ever tracked | — | none |
| Watchman `since` | ignores symlink targets | — | none |
| FSEvents | reports the *resolved* path, so a prefix filter on the link path sees zero events | — | watch the canonical path |

All measured on this Mac (macOS 15.7.9, rg 15.2.0, `/usr/bin/grep` 2.6.0-FreeBSD). The two local lessons `recursive-grep-cannot-walk-the-symlink-layer` and `symlinked-store-invisible-to-find` are the same failure already recorded in this repo.

Beyond tooling, a symlink points at a **File Provider** tree. On macOS ≥ 12.1 Files On-Demand cannot be disabled; an online-only file is a *dataless* placeholder (`SF_DATALESS` = 0x40000000 in `st_flags`, a read-only synthetic flag; `stat`/`lstat` succeed without materializing). The first read, write or lookup-in of a dataless object makes the kernel upcall `filecoordinationd` and puts the calling thread to sleep until the download completes — for an ordinary login-session process the default materialization policy is **ON** (measured: `getiopolicy_np` returns ON here), so a plain `cat` **blocks and downloads**, for as long as the network takes. `EDEADLK` is not an oddity: it is the *defined* result whenever materialization is prevented for the calling context — a process whose `IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES` policy is OFF, kernel context, or a sandbox/daemon tree that did not inherit the bit (claude-code #40783 is that case — Cowork's Ubuntu-VM sandbox reading a File Provider path over bindfs, Google Drive primarily with OneDrive listed as also affected). Apple's own `ls -%` opts out via `vfs.nspace.prevent_materialization` so a listing does not materialize dataless *directories*, which otherwise re-request their child list on access — a never-browsed subtree can enumerate as **empty**. Hydration is not durable: macOS evicts under disk pressure. So a stray `rg` or hash walk over the sync root is a multi-hundred-GB download over the corporate VPN followed by eviction — thrash with no lasting index — and it stalls rather than errors.

**Rule:** `docs-source/` is a real directory populated by an acquisition step. The cloud path appears exactly once in the system, inside that step. Land-gate lint: `find docs docs-source -type l` must be empty. And every recursive search or hash walk over `docs-source/` carries a **positive control** — one known-present sentinel file whose absence from the result set fails the run, because every tool in the table above returns exit 0 when it silently traverses nothing.

---

## 4. The architecture

```
 L0  SOURCES      OneDrive · SharePoint libraries · Outlook folders · Teams channels · manual drop
        │
 L1  ACQUIRE      Arm 0 DISCOVER: the in-scope set is one tracked file, docs/_sync/sources.toml — nothing
        │         else in the pipeline names a cloud location.  Then one puller per (source, scope), each
        │         owning a SINCE-TOKEN and emitting the same change-record schema:
        │         {source_id, kind, path, op, provider_hash, etag, size, mtime, bytes?}
        │         arms: Graph delta (primary where reachable) · local FSEvents ladder over the sync
        │         client · manual inbox reconcile.  Every arm ends in a cheap metadata-only full reconcile.
        ▼
 L2  MANIFEST     SQLite + deterministic NDJSON snapshot in git.  Identity = stable id.  Three hashes:
        │         H0 stat tuple → H1 canonical content hash → H2 output hash.  Multi-state verdict per row.
        │         Phase 1 reads ZERO file bytes.  Soft deletes; 20 % circuit breaker.
        ▼
 L3  CONVERT      deterministic-by-construction: write-once cache keyed on
        │         sha256(key_schema_version | converter_id | converter_version | options_hash | unit_id | canonical_hash) — full form in §4.1 #5.
        │         Per-format routing; one file per addressable unit; content-derived frontmatter only;
        │         early cutoff on H2.  Output: docs/mirror/** (pure function of source, never hand-edited).
        ▼
 L4  CURATE       agent-owned docs/topics/**.  Each page pins the mirror versions it was written
        │         against (sources: [{path, at_rendered_sha256}]).  DEPENDS.tsv is DERIVED from that
        │         frontmatter.  Refresh queue = one awk pass (§4.5).  Debounced per page.  STALE banner is
        │         prepended by a deterministic linter, never by the agent.
        ▼
 L5  SURFACE      docs/ in git.  INDEX.md (llms.txt shape, ≤ 25 KB) · CHANGELOG.md (one section per
        │         sync) · tombstones in place · per-directory CLAUDE.md guardrails · docs index as a Skill.
        │         "What changed since <date>" = git log.  No vector index until grep measurably fails.
        ▼
 L6  OPERATE      ONE writer per docs/ repo · two launchd agents (poll, reconcile) · flock + durability
                  order + crash recovery · a commit only when content changed · quiescence gate · hourly
                  reconcile at this scale · budgets for hydration/egress/RU/memory · liveness heartbeat
                  OUTSIDE docs/ with an external watcher · secrets in the Keychain, never in git ·
                  STATE.md the agent reads first, with a read-side contract · compliance: labels carried,
                  IRM quarantined, secret-scanned pages, remote tenant-owned or absent.
```

### 4.1 The seven invariants

1. **Identity is the stable id, never the path.** Graph `driveItem.id` remotely; `(ATTR_CMN_FILEID, ATTR_CMN_GEN_COUNT)` locally; path is a derived, mutable attribute stored beside `prev_path`. Forced independently by four documented facts: a folder rename emits one delta record and no descendant records; `parentReference.path` is not reliably populated; OneDrive-for-Business delete tombstones omit `name`; and delta says "always track items by id".
2. **Three hashes, not one.** H0 = git's stat tuple (`size, mtime_ns, ctime_ns, ino, mode`; never `st_dev`) decides whether to read bytes. H1 = canonical content hash decides whether to convert — for OOXML that is a rollup over sorted `(part name, part bytes)` with all ZIP metadata discarded and a denylist of volatile parts (`docProps/*`, `xl/calcChain.xml`, `printerSettings/*`, `docMetadata/LabelInfo.xml`), because the container's bytes change on every re-save with zero content change: the ZIP local and central-directory headers carry per-entry mod-time fields that writers stamp with the clock (measured on a two-entry ZIP: identical member bytes, a 2 s difference, container sha differs at exactly four offsets — the mod-time field of each entry's local and central-directory header; on an openpyxl-written 9-part xlsx every entry's timestamp moved), and openpyxl rewrites both `dcterms:created` and `dcterms:modified` in `core.xml`. Real Word/Excel saves could not be scripted here (GUI-gated, §9 probe 6), and a LibreOffice no-op re-save changed `xl/styles.xml` and both sheet parts (measured 2026-09-22, `verify/C12-office-resave.md`), so the denylist is a starting point, not a guarantee: the comparator must **log which parts differed** on every "changed" verdict so a new volatile part appears as data, and H2 — not H1 — is what makes a no-op save free. Where the only question is "did the text change", normalized extracted text is the strictly safer key. H2 = sha256 of the converter's output decides whether anything downstream changed (ninja `restat`). Without H2 every no-op Office "Save" becomes a `docs/` commit that says nothing.
3. **Phase 1 reads zero file bytes.** Provider hash (`quickXorHash`) first, stat tuple second, content only on mismatch, and never for a row marked `dataless`. This is the whole design at 100 GB: the bookkeeping is free (measured: a 200 k-row manifest is 31 MB of JSON, loads in 0.12 s, full stat-compare 0.051 s), and every cost is on the byte-reading side, where a read of a placeholder is a download.
4. **Every since-token expires into a cheap full reconcile.** 410 Gone, `EventIdsWrapped`, a UUID change, a Watchman restart, an interrupted enumeration — all collapse to "re-enumerate metadata and diff against the manifest". Build that path first and schedule it on the §4.7 cadence anyway — hourly at this corpus size, daily past ~10⁵ items (Microsoft's own guidance is the ceiling, not the target; abraunegg's `monitor_fullscan_frequency`).
5. **The converter cache is write-once and keyed on producer identity.** `action_key = sha256(key_schema_version | converter_id | converter_version-as-run | normalized_args | sorted_env_allowlist | unit_id | canonical_hash)`. This removes the determinism requirement from the converter (Docling is measurably non-deterministic under its default concurrency; Marker's "deterministic" means "does not hallucinate") and makes a converter upgrade one deliberate, dated bulk re-render instead of an unexplained mass diff. git's `textconv` cache — keyed on config but not binary version — is the documented cautionary tale. `key_schema_version` is bumped ONLY when the key's own composition changes, never for a converter change, which `converter_version` already covers (§4.7 has the migration rule).
6. **Deletes are soft, ownership-aware, and circuit-broken — and absence is evidence only inside a pass that enumerated the scope.** An incremental delta pass returns only changed items, so it may delete only on an explicit tombstone (Graph's `deleted` facet, an FSEvents removal); a source absent from a *full enumeration* is still indistinguishable from an expired token, a throttled page or an unmounted folder. Tombstone the mirror page in place with its body replaced by a stub (keeps citations resolvable without serving dead content to grep), keep it for a bounded window, restore idempotently on reappearance, reap on a policy (180 days). Never delete a curated page because a source vanished — flag it stale. Pause all removals when a full pass would delete more than max(20 % of the scope's live rows, 25) (Glean's breaker, scoped per source so one unmounted drive cannot hide under a corpus-wide denominator, floored so a 40-row pilot does not trip on three real deletions).
7. **The derived layer is git, and only content-derived bytes go in it.** No `converted_at`, no run id, no model caption inline. Freshness cannot ride the filesystem: `git clone` resets every mtime (measured), and Glob orders by that same mtime. Freshness is greppable text — frontmatter, `INDEX.md`, `CHANGELOG.md` — and `git log`.

### 4.2 L1 — acquisition

**Three arms, one change-record schema.** Every arm emits `{source_system, source_id, kind: graph|fileprovider|manual, path, prev_path?, op: created|modified|renamed|deleted|metadata, provider_hash?, etag?, ctag?, size, mtime, modified_by?, bytes_ref?}` so L2 does not know or care where a change came from, and a tenant that later grants Graph access re-keys without a schema change.

**Arm 0 — Discover.** The in-scope set lives in one tracked file, `docs/_sync/sources.toml` (`id, kind: graph_drive|graph_list|graph_mail|graph_channel|fileprovider|manual, drive_id|folder_id|upn, subtree, cadence_seconds, principal, initial_crawl_budget_gb, state: paused|live|retired`), and nothing else in the pipeline names a cloud location. Discovery is a command, not a habit: enumerate `/sites?search=`, `/sites/{id}/drives`, `/me/drives` and **`/me/drive/sharedWithMe`** — a folder shared *into* a user's OneDrive is a `remoteItem` that root delta never enumerates, so it needs its own cursor against its owning drive — diff against `sources.toml`, and print additions for a human to accept. Onboarding a source: append it as `paused` → bootstrap with a budgeted off-peak full enumeration (egress-bound) → the first complete pass flips it to `live`; the bootstrap publishes as its own labelled commit, and absence-based deletion is disabled for that scope until its first full enumeration has completed.

**Arm A — Graph delta (primary wherever reachable).** Cost model, from SharePoint's throttling reference (published defaults Microsoft reserves the right to change — re-read, never re-quote): a delta request carrying a token costs **1 resource unit** (a token-less delta or a children page costs 2; anything touching permissions costs 5) against **two** buckets — the per-app-per-tenant **1,250 RU/min and 1,200,000 RU/24 h** at ≤ 1,000 licences (scaling to 6,250/min and 6 M/24 h at 50,000+), and a **tenant-wide 18,750 RU per 5 min shared by every app in the tenant**, so a co-resident backup or DLP scanner can throttle you well under your own ceiling. Polling one drive every 60 s is ~1,440 RU/day — 0.12 % of the smallest per-app budget. Egress, not request count, bounds the initial crawl: **100 GB/h per delegated user, 400 GB/h per app-tenant**. Throttled requests still count; honour `Retry-After` and pause globally; SharePoint Online does not emit IETF `RateLimit-*` headers (its own best-practices bullet contradicts this — treat the negative as controlling and assert their absence in a test); send `User-Agent: NONISV|<Company>|docs-sync/<ver>`.

Webhooks are optional and cannot replace polling: driveItem notification latency is under a minute on average but **up to 6 hours** at maximum; subscriptions expire at 42,300 min (~29.4 days) and any expiry under 45 min is silently raised to 45; only `changeType=updated` is supported and it covers add/change/delete alike; the notification carries **no information about the change** — `resource` is the *subscribed folder path*, not the item — so the handler must 202 and call delta with the stored link, idempotently against batched duplicates. Scope differs by account type: OneDrive **personal** can subscribe to any subfolder, OneDrive **for Business** to the root only, and a SharePoint document library is not a driveItem subscription at all but a `list` resource (`sites/{id}/lists/{id}`, `Sites.Read.All`). A `notificationUrl` needs a public HTTPS endpoint (or Azure Event Hubs) a corporate laptop does not have.

The puller state machine (full diagram in the B1 report):

```
S0 NEW_SOURCE ── GET /drives/{id}/root/delta?$select=id,name,size,eTag,file,parentReference,deleted,
   │             lastModifiedDateTime,folder&$top=N   (header Prefer: deltaExcludeParent)
   ▼             the FIRST pass on a new source is ALWAYS this token-less full enumeration.
S1 ENUMERATING   ?token=latest is legal only to re-arm a source whose baseline already exists — used as
   │             a bootstrap it mirrors only files edited after today, forever, with no error at any
   │             layer; ?token=<ISO timestamp> (ODB/SPO only) is a resync aid, not a bootstrap.
   │  follow @odata.nextLink; persist the PAGE cursor so a crash resumes, never restarts;
   │  do NOT publish a change set until @odata.deltaLink arrives (an incomplete pass must not
   │  enable absence-based deletion — the breaker needs an explicit enumeration_complete[scope] flag);
   │  until the first full enumeration completes, INDEX.md and STATE.md carry
   │  `baseline: INCOMPLETE <n>/<unknown>` so a partial corpus is never read as whole
   ▼
S2 SYNCED     store the deltaLink in the LOCAL cursor store, in the same transaction as the item
   │          snapshot — never in the committed manifest export: it is a URL carrying a tenant sync
   │          token (§4.7 secret custody); never advance the cursor before
   │          the change set is durably consumed (a consumed-but-unapplied delta looks like
   │          "no changes, forever"); ship a read-only "what would change" mode that does not advance it
   ▼
S3 POLLING    GET <deltaLink> every 60 s–5 min (1 RU)
   ├─ 200 → classify (§4.3) → new deltaLink → S2
   ├─ 410 Gone (resyncChangesApplyDifferences | resyncChangesUploadDifferences) → follow the
   │        Location: nextLink, full METADATA re-enumeration, diff against local state → S1
   ├─ 400 "Provided sync token is malformed" (measured) → OUR cursor store is corrupt: alarm, drop
   │        the cursor deliberately → S0.  Never conflate with 410; the actions are opposite.
   └─ 429/503 → honour Retry-After and PAUSE ALL requests to that service (retries count against
            the same budget); User-Agent NONISV|<Company>|docs-sync/<ver>; RateLimit-* headers
            are not emitted by SPO, so do not build on them
```

One cursor per **drive** (per document library, per user OneDrive): the v1.0 reference's HTTP-request list is root-scoped (its own SDK snippets and `Get-MgDriveItemDelta` take a driveItem id), and rclone reports that off-root delta recurses from the root and discards. Folder-scoped `/items/{id}/delta` was measured working and correctly scoped on consumer OneDrive — treat it as an optimization to measure on the real tenant, never a premise. Filter to `docs-source`'s subtree locally.

Auth rungs, decided *before* the architecture: (i) **app-only** (`client_credentials` + `Files.Read.All`/`Sites.Read.All` or `Sites.Selected`) — tenant-wide, enables webhooks, needs an admin; (ii) **delegated device-code through the first-party Microsoft Graph PowerShell app** (`Connect-MgGraph -Scopes Files.Read -UseDeviceAuthentication`, then `Invoke-MgGraphRequest` against the delta URI) — reaches the operator's own OneDrive with no app registration. Whether it reaches a shared SharePoint library is a **tenant-policy** question, not a permission property: the permissions reference lists *Admin consent required: No* for the delegated variants of `Files.Read`, `Files.Read.All`, `Sites.Read.All` and `Sites.Selected` (the *Yes* belongs to the application column — the wave's first reading of that table was wrong, and abraunegg's table is right), but Microsoft's *default* user-consent policy for a new tenant excludes `Files.Read.All`, `Files.ReadWrite.All`, `Sites.Read.All` and `Sites.ReadWrite.All` from what end users may grant, while a tenant on the legacy policy ("any permission that doesn't require admin consent") lets a non-admin consent to them. `Sites.Selected` is not on the exclusion list but grants nothing until a per-site permission is configured in SharePoint. So: request the scope and design for the runtime outcome (consent screen vs `AADSTS65001` / "Need admin approval" / admin-consent-request flow), and read the tenant's `permissionGrantPolicies` if `Policy.Read.All` is available; (iii) **no Graph at all** → arm B. rclone's v1.75 "no admin mode" scrapes a browser session token with no refresh token, so it cannot host an unattended cursor. A tenant refusing the OneDrive API entirely (AADSTS65005) leaves WebDAV: no delta, no hashes, size+mtime only.

Three traps specific to the corporate population, each a different mechanism: **(1) upload-side enrichment** — SharePoint document libraries inject library metadata (Microsoft names the Document ID added on upload) into files that can carry it (Office, PDF, HTML; never plain text), so the stored bytes, size and `quickXorHash` differ from the local original; Microsoft confirms it in onedrive-api-docs #935 as intended behaviour "since at least SharePoint 2010", it happens through the sync client too, and the often-repeated "not OneDrive for Business" carve-out is a 2018 third-party observation contradicted by a 2021 report — treat it as feature-dependent, not architectural. **(2) serving-time encryption** — a sensitivity-labelled (Purview/AIP) or IRM-protected file is transformed as it is *downloaded* ("encryption settings from the label are enforced" when users download), so it reports one size/hash online and yields different bytes, and **no primary source states whether two downloads of the same unchanged item are byte-identical** — for labelled/IRM files the protection is applied on the download path, which makes cross-download byte identity uncitable rather than merely unmeasured (abraunegg treats the mismatch as a failed download and deletes the file by default). **(3) a server-side sha256 does not exist** (`sha256Hash`: "isn't supported. Don't use"). Therefore the manifest carries `provider_hash` (`quickXorHash`, comparable only to itself, the *change signal*) and `content_hash` (sha256 of what was actually downloaded, the *identity/dedup key*), never equates them, never compares a drag-and-drop local hash with a Graph hash across channels, classifies a mismatch by *where it arose* before choosing a remedy, and — for labelled classes — runs a re-download equality probe before trusting `content_hash` as stable (canonical *text* hash, §4.3, is the dedup key that survives all three).

**Mail** (`/me/mailFolders/{id}/messages/delta`): folder-scoped only, one cursor per folder. Detect with `$select=id,changeKey,subject,from,receivedDateTime,hasAttachments,internetMessageId,conversationId` (omitting `$select` returned ~9 KB of body text for the two messages fetched *during change detection*, measured); fetch bodies and attachments only for the diff. `@removed reason=deleted` is emitted both for a real delete and for a message merely **moved** out of the folder, and read/unread flips arrive as changes — never delete a page on `@removed` without a cross-folder check.

**Teams**: per-**channel** message delta is delegated-capable (`ChannelMessage.Read.All`, admin-consent scope); tenant-wide `chats/getAllMessages/delta` is application-only *and* a protected API needing a written access request. Channel **files** live in the channel's SharePoint library and need no Teams permission at all. No converter in any surveyed project has a Teams backend; the emitter is project-local (one page per channel per month, §4.6).

**The locally installed ms365 MCP server cannot do incremental sync through its named delta tools** (measured: `list-mail-folder-messages-delta` given a valid `$deltatoken` returned a fresh full page and a new token; the parameter is dropped with a `logger.warn` at `dist/graph-tools.js:725`, server 0.143.0). Its `graph-batch` tool passes arbitrary relative Graph GETs and the same token through it returned an empty change set. L1 therefore owns its own Graph HTTP client, or routes through `graph-batch`; token custody is the pipeline's job (the server stores nothing).

**Arm B — local folder over the OneDrive sync client (the no-API path).** Three tiers, each a pure accelerator over the one below, so the bottom alone is a correct pipeline:

| Tier | Mechanism | Role |
|---|---|---|
| T1 live | `fsevents` npm binding (`FSEventStreamCreate` + `FileEvents` + `UseExtendedData`) on the **canonical** `~/Library/CloudStorage/…` path; persist `(eventId, volumeUUID, wallclock)` after each drained batch | sub-second *candidate path set* — FSEvents is not a replayable change log and Apple's header says so |
| T2 catch-up | restart with the stored `eventId` as `sinceWhen`; abort to T3 on a UUID change, `MustScanSubDirs`, `UserDropped`/`KernelDropped`, `EventIdsWrapped`, `RootChanged` (event id 0 — never persist it), or a stale wallclock beyond the journal-horizon budget (~7 days, to be measured) | bounded downtime recovery |
| T3 truth | `getattrlistbulk` walk collecting `(relpath, FILEID, GEN_COUNT, SIZE, MODTIME, FLAGS)` — one syscall per directory, zero file opens, zero downloads; diff against the manifest; hash only rows whose `(FILEID, GEN_COUNT)` moved | the authority; measured at 0.13–0.31 s per 100,000 files on local APFS (`verify/C11-local-walk.md`), so it runs on demand at session start with no daemon |

`ATTR_CMN_GEN_COUNT` is the finding that makes T3 strong: a kernel-maintained monotonic *data*-modification counter. Measured on APFS 15.7.9: it rose on a same-size in-place overwrite whose mtime was rolled backwards (invisible to rsync's quick check) and did **not** move on `chmod`, an xattr write, or `touch` (all of which move ctime and false-positive in git's stat cache); an Office-style safe-save (write temp, rename over) changes `FILEID` and resets the counter, a plain rename keeps `FILEID`, so the pair distinguishes in-place edit, safe-save and rename. Treat `GEN_COUNT == 0`, a decrease, or absence from `ATTR_CMN_RETURNED_ATTRS` as "unknown ⇒ hash it" — that is how an unsupported filesystem (possibly File Provider) fails visibly.

Hydration discipline for every stage that touches the sync root: run under `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)` — inherited by children, so one call before `exec` makes the whole `find`/`rg`/hash subtree fail-closed against accidental download; skip rows whose `st_flags` carry `SF_DATALESS` and record them as `dataless`, a state distinct from *changed* and from *unknown*; treat a zero-child directory in the cloud tree as **unknown**, never empty; pin only the subtrees in scope with "Always Keep on This Device" (folder-inheriting) and hydrate the rest through a budgeted `materialise()` that is the one place a download can happen. Converters must tolerate a source reverting to dataless between the manifest read and the read (ENOENT-shaped retry, not a corruption verdict).

What arm B structurally cannot do: answer "did the content change" without paying for the content. A same-size same-second overwrite with a preserved mtime passes every stat check; only `GEN_COUNT` (if File Provider supports it — unmeasured) or a server hash catches it. That is the cost argument for keeping arm A wherever IT allows it.

**Arm C — manual drag-and-drop inbox.** Same T3 walk, plus: filter on `max(created, modified)`, not mtime — a copied file keeps its original mtime (Onyx documents exactly this miss); quarantine anything whose size/mtime changed within the last N seconds or whose hash differs between two reads (measured: hashing a file mid-write yields a digest that corresponds to no finished version); ignore `~$*` lock files and `*.tmp`; NFC-normalize names and fold `-<COMPUTERNAME>`, `(1)`, `- Copy` conflict suffixes into the dedup step before keying. **Arm precedence:** the Graph arm is authoritative for any object under a synced root; the inbox *refuses* (quarantines with reason `duplicate-of <source_id>` and the mirror path) any drop whose canonical **text** hash matches a live Graph row, or whose (normalized name, size) pair does. Canonical text is the only key that survives the boundary: SharePoint's upload-side enrichment (trap 1) changes `content_hash` and — for PDF and HTML, which have no part denylist — `canonical_sha256` too, so the same document dropped locally and synced from the library would otherwise be mirrored twice under two ids and cited independently.

**Source types and their arm.** A type absent from this table is a `refused` row with a stub page, never a silent zero.

| source | arm / endpoint | notes |
|---|---|---|
| SharePoint document library, OneDrive for Business, personal OneDrive | Graph delta per drive (A) or the sync client (B) | Teams channel files are a library |
| folder shared *into* a OneDrive (`remoteItem`) | its own delta cursor against the owning drive | root delta never enumerates it |
| mailbox folders; **shared mailboxes** | `/me/mailFolders/{id}/messages/delta`; `/users/{upn}/mailFolders/{id}/messages/delta` + `Mail.Read.Shared`, own `principal` | folder-scoped; two-phase fetch |
| attachments | second phase after the message diff; recurse one level into `.msg`/`.eml`; expand `.zip` members with the archive as parent; key on `(internetMessageId, name, size, sha256)` | attachment ids are not stable across a move |
| Teams channel messages | per-channel delta (`ChannelMessage.Read.All`) | inline images are `hostedContents/{id}/$value`, not fetchable from the message HTML |
| Teams 1:1 / group chats | application-only + protected API | outside a delegated design |
| meeting transcripts | the `.vtt` in the organiser's OneDrive `Recordings/` folder (a file, arm A) | `/onlineMeetings/{id}/transcripts` is app-only + protected |
| OneNote | `/onenote/pages?$select=lastModifiedDateTime` per section, reconcile-only on a high-water timestamp; body via `/pages/{id}/content` | **no delta endpoint**; the notebook package carries no hash |
| Loop / `.fluid` | `refused: no converter` | opaque Fluid container |
| Planner, Forms, Whiteboard, Viva, Copilot notebooks | `refused: out of scope` | stated once so the absence is visible |

### 4.3 L2 — manifest and change classifier

SQLite for the working store (Buck2's choice), with a deterministic NDJSON snapshot exported into git so the manifest itself diffs (shard by top-level directory to avoid 200 k-line diffs). Full provenance also lives in each mirror page's frontmatter, so the manifest is a cache, not a single point of truth.

`source` — one row per driveItem or local object:

| field | why |
|---|---|
| `source_id` | stable identity (Graph id; `(volume_uuid, fileid)` locally; content-derived for a manual drop) |
| `source_kind` | `graph` / `fileprovider` / `manual` — which since-token is authoritative |
| `path`, `prev_path` | derived; a rename is *reported* as a rename to L4, not as churn |
| `parent_id`, `name`, `drive_id` | the id→(parent, name) tree paths are re-derived from — a folder rename is an O(subtree) local re-derivation with zero network and zero re-conversion |
| `size, mtime_ns, ctime_ns, ino, mode` | H0 (git's tuple; no `st_dev`) |
| `fileid, gen_count` | macOS per-file change token (arm B) |
| `dataless` | `st_flags & SF_DATALESS`: present but not materialised — never hash, never convert, never read its null hash as a diff |
| `provider_hash` | `quickXorHash` only; `sha256Hash` is documented "isn't supported. Don't use"; comparable only to itself |
| `etag`, `ctag` | Graph change tokens; note delta **omits cTag on OneDrive for Business** create/modify, so cTag is a bonus, never the key |
| `content_hash` | sha256 of downloaded bytes (nullable = not materialised, a distinct state from mismatch) |
| `canonical_hash` | H1 over the normalized part set / extracted text — the key the converter cache uses |
| `first_seen_run`, `last_seen_run` | a live row not stamped with the current *complete* run is a deletion candidate |
| `state` | `live` / `dataless` / `tombstone` / `quarantined` (IRM-encrypted, password-protected, malware-flagged, `pendingOperations`, checked-out) / `refused` (no converter, or out of scope — §4.2) — a failure is a **row**, never a log line |
| `principal` | which signed-in identity saw it (delegated views are per-principal; never merge two users' mirrors) |
| `sensitivity_label` | carried into page frontmatter; excluded above a threshold |

`output` — one row per derived file: `output_path, owner: mirror|curated, source_ids[], unit: whole|sheet:<n>|slide:<n>|page:<n>, action_key, output_hash (H2), converter_id, converter_version, options_hash, built_run, status: ok|failed|skipped-dataless|quarantined`.

`dirnode` — the Merkle layer, copied from git's cache-tree: `path, children_digest, entry_count, valid`; updating a path invalidates every ancestor; recompute bottom-up. This is what makes a no-op scan O(changed).

Classifier, in this order — each step is a zero-byte decision until the last:

```
for each observed object o (identity = source_id, never path):
  stamp last_seen_run
  new row                          → CREATED
  o.path != row.path               → record RENAMED (prev_path); continue classifying content
  o.dataless                       → DATALESS (skip; never open)
  provider_hash both present       → differ ? MAYBE_CHANGED : UNCHANGED        # zero bytes
  provider_hash ABSENT on either   → never read as "unchanged": OneNote items (application/msonenote,
                                     application/octet-stream, package facet) and size-absent/zero items
                                     carry no hash; a $select that omits `file` drops it for EVERY item;
                                     log the absence, fall through to the next rungs
  else ctag both present (files only; omitted on ODB create/modify; never on folders)
                                   → differ ? MAYBE_CHANGED : UNCHANGED   # opaque string compare
  else etag moved but size/mtime hold → METADATA_ONLY (label/rename/move): re-map path, keep markdown
  else stat tuple / (fileid,gen_count) equal
        → racily-clean guard: row.mtime_ns >= manifest.written_at_ns ? MAYBE_CHANGED : UNCHANGED
  else                             → MAYBE_CHANGED
  (eTag/cTag are compared as opaque strings only: their "{GUID},n" shape is an example-response
   observation, not a documented contract; the wave saw the two counters BOTH divergent — eTag 4 / cTag 2 on one live consumer item — and equal across ~35 records, so neither relation may be assumed)
two pass kinds, never confused:
  delta_pass       — incremental; deletes come ONLY from an explicit tombstone (Graph `deleted` facet,
                     FSEvents removal); last_seen_run is stamped but never compared
  full_enumeration — bootstrap crawl, 410 resync, scheduled reconcile, T3 walk; on success sets
                     enumeration_complete[S] = true for scope S = (source_kind, drive_id)
live rows in S with last_seen_run < run_id AND pass_kind == full_enumeration AND enumeration_complete[S]
                                 → DELETION CANDIDATE
if candidates > max(20 % of live rows in S, 25) → BREAKER: suspend removals in S for 7 days, page a
                                 human, keep everything (scoped: one unmounted drive that is 15 % of the
                                 corpus cannot be tombstoned under a global denominator; floored: a
                                 40-row pilot must not trip on three real deletions)
MAYBE_CHANGED ∪ CREATED → materialise (budgeted) → content_hash, canonical_hash
  canonical_hash == row.canonical_hash → TOUCHED_NOT_CHANGED (the Office no-op save): update H0, stop
  else                                 → CHANGED → unit expansion (§4.4) → build with early cutoff
mtime is compared for INEQUALITY only, never "newer than" (a restore or sync write can land an older stamp)
```

Zoekt's seven states map onto this: `missing` (CREATED), `corrupt` (quarantined), `format-version` (key_schema_version bump), `options-hash` (converter/options changed ⇒ every output of that converter is stale, others untouched), `metadata-only`, `content`, `equal`.

### 4.4 L3 — conversion

Per-format routing (measured where marked; the E report holds the fixtures):

| format | converter | why |
|---|---|---|
| `.docx` | **pandoc 3.11** `-f docx -t gfm --extract-media`; Docling for image-heavy | deterministic pure-XML path with real table headers; MarkItDown emits a blank header row (measured) |
| `.xlsx` | **~40-line openpyxl emitter** — open twice (`data_only=True` for values, `False` for formulas), propagate merged-range anchors, emit `value \`=FORMULA\``, heading carries the used range, stub lines for pivots/charts | every off-the-shelf route is wrong: MarkItDown/pandas renders every formula cell as the literal `NaN` when the workbook has no cached values (BI exports, scripts), drops an unheaded column silently, turns `100` into `100.0`, empty into `NaN` (measured). Two non-streaming opens are required (`read_only=True` hides `merged_cells`) and openpyxl's normal mode costs ~50× the file size in RAM, so route any workbook above a threshold (start at 20 MB) to a streaming path that emits a schema + sample page plus a CSV sidecar, recorded as `unit: summary`; converter memory is a §4.7 budget like egress |
| `.pptx` | **MarkItDown** (`<!-- Slide number: N -->` anchors, `### Notes:`) for linear decks; Docling for dense multi-column (reading order, spans) | MarkItDown byte-stable (measured); Docling's pptx backend is pure-XML and expected stable but was not run; both emit speaker notes |
| `.pdf` born-digital | **PyMuPDF4LLM** `table_strategy="lines_strict", page_chunks=True` → `<!-- page: N -->` anchors | 5.5 p/s, byte-stable over 3 runs incl. its auto-Tesseract path (measured); **AGPL-3.0** — legal decision required, MIT fallback is Docling-with-pypdfium at ~half the throughput |
| `.pdf` scanned / table-critical (per-page routing: `len(page.get_text()) < threshold` ⇒ scanned; ruled-line count ⇒ table-critical) | **Docling** with batch sizes pinned to 1, or Marker — always through the write-once cache | Docling's default 2-worker pipeline produced different structure for the same PDF in 6 of 15 runs; batch 1 restored 12/12 (its users' measurement). ~1.3 p/s on an M3 Max with OCR *off* (Docling's own report; the OCR-on rate for scans is unmeasured and lower): tens of GB of scans is a **backfill measured in days at best on one laptop** — budget it or run it server-side |
| `.msg` / `.eml` | **Docling email backend** (`mailparser`, `python-oxmsg`) | MarkItDown has no `.eml` converter: raw MIME with base64 attachments lands in `docs/` (measured) |
| images | extract to `figures/<sha256[:16]>.png`; VLM caption **only into a sidecar** `figures/<sha>.md` | a caption is model output; inline, a model upgrade rewrites the corpus |
| Teams / meeting transcripts | project-local emitter from `chatMessage` JSON; Docling reads WebVTT (prefer VTT over ASR) | no surveyed converter has a Teams backend |

**One file per addressable citation unit:** per sheet (`<Name>.xlsx.d/00-index.md`, `01-<sheet>.md` …) — where **`00-index.md` is the workbook's grep-recall surface and carries what the split takes away**: the workbook's title and path, every sheet's name, used range and column headers, and the union of the sheets' distinctive terms, so one hit resolves the whole workbook. Splitting multiplies the matching-file count against Grep's `head_limit` of 250 (§4.6): measured, a term on 4 sheets of each of 100 workbooks was visible in 64 of 100 workbooks split per sheet and 100 of 100 kept whole, so a completeness-critical search globs `**/00-index.md` first and descends only into the workbooks it names, or runs `rg` via Bash where no cap applies; per email (threads are an L4 artefact built from `Message-ID`/`In-Reply-To`/`References` or Graph `conversationId`, linking the per-message files); PDFs stay one file with page anchors, decks one file with slide anchors below ~40 slides. Address units by `(position, unit content hash)`, never position alone, so an inserted slide does not re-convert the tail. Row caps with a sidecar CSV for giant sheets; `tokens_estimate` in frontmatter; streaming readers only.

**Frontmatter — content-derived fields only** (a direct amendment to the naive list: no `converted_at`):

```yaml
---
source_system: sharepoint
source_id: 01ABCDEF…                  # Graph driveItem id — the only rename-stable identity
source_path: /sites/acme/Shared Documents/Finance/FY26 Budget.xlsx
source_web_url: https://contoso.sharepoint.com/:x:/r/sites/acme/…
source_etag: "{4F2A…},7"
source_modified: 2026-09-14T09:12:00Z
source_modified_by: jane.doe@contoso.com
source_version: 7                     # cTag counter where present, else version-history ordinal
content_sha256: 9f2c1d…               # downloaded bytes
canonical_sha256: 51e0b3…             # normalized parts / extracted text — the dedup key
rendered_sha256: 3ab77e…              # this markdown — what L4 pins
part: {kind: sheet, name: "Q3 Budget", index: 1, of: 2}
converter: xlsx-native@1.2.0
options_hash: sha256:…
sensitivity_label: General
status: current                       # current | deleted | superseded | unreadable | refused
source_title: "FY26 Budget — Q3"      # the document's own human title, not the slug
summary: "Q3 budget by region: spend, forecast, variance; 3 sheets, 412 rows"   # converter-derived from
                                      # title, heading set and used range — never a model caption
tokens_estimate: 4200                 # the agent's read-or-skip gate at a grep hit
unit_index: 1                         # hoisted from part: so a grep can sort units
---
```

`summary` and `tokens_estimate` are the only two fields that answer the agent's question at a grep hit — read this page or skip it; the ids and hashes (38 % of the block, measured on a realistically filled example) are for the pipeline, and `mirror/CLAUDE.md` says so. No `aliases:` here: a synonym is a judgment no converter derives from bytes, and replicated onto every unit of a source it selects the corpus (measured: 1,200 of 1,200 sheet pages matched the alias term through their own frontmatter). Aliases live on the curated page and in `docs/SYNONYMS.tsv` (§4.6).

**Quiescence gate:** convert only when `lastModifiedDateTime` is older than N minutes, `pendingOperations` is absent and (SharePoint) `publication.level` is `published` — otherwise autosave, check-out and half-uploaded states get mirrored. **Unreadable sources become explicit `UNREADABLE` stub pages**, never empty conversions: Graph `/content` returns sensitivity-label-encrypted files as encrypted bytes, and a converter fed those produces an empty page with exit 0.

**Converter contract, enforced at the land gate:** version pinned and recorded by *running* `--version`; idempotent (delta may return the same item twice; write whole files, never append); a double-conversion CI check that quarantines any converter whose two runs differ; NFC for identity with raw bytes in provenance; slugifier: lowercase; NFC; strip diacritics; map dashes; collapse whitespace to `-`; strip `[ ] ( ) # { }` **and the NTFS-illegal set `< > : " / \ | ? *` plus control bytes**; strip trailing dots and spaces; refuse the Windows reserved stems (`con prn aux nul com1-9 lpt1-9`, with or without extension) by suffixing `-doc`; **check case-insensitive collisions and NFD/NFC twins** (measured: APFS silently overwrote `API-Spec.md` with `api-spec.md`, and `aux.md`, `q3?.md` and `report.` all commit on APFS without a murmur; each is uncreatable on NTFS, so a Windows `git clone` fails with `error: invalid path` and yields no working tree — inferred from git's checkout behaviour, no Windows clone was run in this wave) disambiguating with the source id, never a counter; cap any path at 200 characters from the repo root so a Windows colleague's checkout clears `MAX_PATH` (260) without `core.longpaths`, with the original name in frontmatter.

### 4.5 L4 — curation, incrementally

Two tiers with a hard boundary: `docs/mirror/` is a pure function of the source and is never hand-edited (a hand edit makes `rendered_sha256` meaningless and forces a three-way merge nobody maintains); `docs/topics/` is the answer layer, organized by **entity** (client / workstream / decision / person) because corporate queries are entity-shaped, with every claim citing a mirror path.

Curated-page frontmatter carries the dependency edges:

```yaml
---
kind: topic
entity: acme
purpose: >-                           # DeepWiki's required field: what this page is, and is NOT
  What we have agreed with Acme commercially: pricing, discounts, renewal.
  NOT the integration scope — that is acme-integration-scope.md.
sources:
  - {path: ../../../mirror/sharepoint/acme/finance/fy26-budget.xlsx.d/01-q3-budget.md, at_rendered_sha256: 3ab77e…, role: primary}   # three levels up from topics/clients/acme/
  - {path: ../../../mirror/email/2026/09/2026-09-14-acme-kickoff-recap.md, at_rendered_sha256: 71c0aa…, role: corroborating}
depends_on_pages: [acme-integration-scope.md]      # page→page edges, or affected-page regen breaks hierarchy
reviewed_at: 2026-09-21
modified: 2026-09-21T14:40:00Z        # Anthropic's own auto-memory field
aliases: [Acme pricing, Acme MSA terms]
---
```

`docs/DEPENDS.tsv` is **generated by parsing every page's `sources:`** on each sync, with a literal first line `page<TAB>source<TAB>pinned_sha<TAB>role`; columns 1 and 2 are **repo-root-relative** (`docs/topics/…`, `docs/mirror/…`) — the page's own `sources:` entry stays page-relative so a human can follow the link, and the generator normalizes it, erroring on any path that escapes `docs/`. One spelling per store: every consumer (refresh queue, reverse query, STALE linter) uses the repo-relative form from the repo root. A map maintained separately drifts, and the drift is invisible; so does a reader that guesses its own schema. The reverse query is one line (`awk -F'\t' '$2=="docs/mirror/<path>"{print $1}' docs/DEPENDS.tsv`), and the refresh queue — one awk pass; the reviewer's form (`review/scripts/refresh-queue.sh`) ran 0.051 s at 1,600 rows, and the version printed below, which tightens its `SOURCE-DELETED` predicate, adds `SOURCE-UNREADABLE` and an empty-file guard, was re-run on a six-verdict fixture and re-timed at 0.08–0.12 s over 1,600 rows (`verify/C11-local-walk.md` §3) — is:

```sh
#!/bin/sh
# docs/ refresh queue — which curated pages are stale against docs/mirror/.  Run from the repo root.
# rc 0 = every row fresh · 1 = rows need action (printed) · 2 = DEPENDS.tsv unusable.
TSV=${1:-docs/DEPENDS.tsv}
[ -s "$TSV" ] || { echo "$TSV: missing or empty" >&2; exit 2; }
awk -F'\t' 'NR==1 && $1!="page"{exit 2} {exit 0}' "$TSV" || {
  echo "$TSV: missing header (page/source/pinned_sha/role)" >&2; exit 2; }
OUT=$(awk -F'\t' '
  NR==1 { next }
  NF < 3 { printf "MALFORMED\t%s\t(fields=%d)\n", $1, NF; next }
  {
    page=$1; src=$2; pin=$3; cur=""; st=""; ok=0; dash=0
    if (pin == "")               { printf "UNPINNED\t%s\t%s\n", page, src; next }
    if (pin !~ /^[0-9a-f]{64}$/) { printf "BAD-PIN\t%s\t%s\t(len=%d)\n", page, src, length(pin); next }
    while ((getline line < src) > 0) {            # frontmatter only: stop at the closing ---
      if (line == "---") { if (++dash == 2) break; else continue }
      if (line ~ /^rendered_sha256: /) { cur = substr(line, 18); ok = 1 }
      else if (line ~ /^status: /)     { st  = substr(line, 9) }
    }
    close(src)
    if (st == "deleted")        { printf "SOURCE-DELETED\t%s\t%s\n", page, src; next }
    if (st == "unreadable" || st == "refused") { printf "SOURCE-UNREADABLE\t%s\t%s\n", page, src; next }
    if (!ok)                    { printf "MISSING-OR-UNPARSEABLE\t%s\t%s\n", page, src; next }
    if (cur != pin)             { printf "STALE\t%s\t%s\n", page, src; next }
  }' "$TSV" | sort -u)
[ -n "$OUT" ] && { printf '%s\n' "$OUT"; exit 1; }
exit 0
```

Verdict vocabulary, published beside the command in `docs/README.md`: `STALE` (re-synthesize the page) · `SOURCE-DELETED` (the mirror page is a tombstone — re-curate or retire the claim) · `SOURCE-UNREADABLE` (the mirror page is an `UNREADABLE`/`refused` stub — the source is unreadable, not absent; see `_sync/QUARANTINE.tsv`, and never re-curate on it) · `MISSING-OR-UNPARSEABLE` (**a bug in the generator or in path normalization, not a content problem**) · `UNPINNED` / `BAD-PIN` / `MALFORMED` (lint failures). They are separate verdicts because they demand opposite actions, and a broken queue must never present as a tombstone — the first draft's single `TOMBSTONE-OR-MISSING` did exactly that, its `case "$cur" in "$sha"*)` read an empty pin as a match on everything, its `NR>1` dropped the first data row of a headerless file, its unbounded `sed` let a body that quoted the key supply the "current" sha, it exited 0 whatever it found, and it cost 18.8 s where one awk pass costs 0.05 s (all measured on the reviewer's fixture). Ship a fixture (one page, one present source, one tombstone) asserting the queue prints exactly one `STALE` and one `SOURCE-DELETED`: a refresh queue that reports everything is indistinguishable from one that reports nothing. (Parse TSV with `awk -F'\t'`, never `IFS=$'\t' read` — it collapses tab runs and drops empty trailing fields; this repo has that lesson on file.) Write the command into `docs/README.md` verbatim: nothing in the harness will invent it.

Rules that keep incremental curation honest:

- **A deterministic linter, not the agent, prepends `> ⚠ STALE — sources changed since <date>; see DEPENDS.tsv` to any curated page whose pinned hashes no longer match.** The hostile review's sharpest point: a page with confident frontmatter and no mechanical banner is exactly what makes the agent trust stale content.
- **An unpinned or short-pinned citation is a lint failure, never a fresh page.** `at_rendered_sha256` is a full 64-hex sha or the row is rejected; a prefix comparison cannot distinguish "pinned to an abbreviation" from "not pinned".
- **Every curated page must appear in `DEPENDS.tsv`, and that lint is separate from the refresh queue.** A page with no `sources:` is in no row and is therefore never stale — the one drift the pinned-hash mechanism is structurally blind to, and the likeliest one, because the layer is agent-written. Land gate: `comm -23 <(grep -L '^provenance: hand-written' $(find docs/topics -name '*.md' ! -name CLAUDE.md ! -name INDEX.md) | sort) <(awk -F'\t' 'NR>1{print $1}' docs/DEPENDS.tsv | sort -u)` must be empty — the `grep -L` is what implements the adopted-page exception (§10: `provenance: hand-written`, `sources: []`), which the bare form flags by construction (measured on a fixture).
- **`entity:` on every curated page, including decisions and workstreams**, and `docs/_index/by-entity.tsv` (`entity<TAB>page`) generated from the same parse as `DEPENDS.tsv`: level 1 of `topics/` is not one axis (`clients/` and `people/` are entities; `workstreams/` and `decisions/` are types), so "everything about Acme" is `rg -l '^entity: acme' docs/topics` or one lookup in that file, never a Glob.
- **Debounce per page or cluster** (Cody's 24 h floor per repo): cheap deterministic L3 may fire per change; L4 re-synthesis must not fire 40 times for one re-uploaded deck. `role: primary` changing ⇒ rewrite; `corroborating` ⇒ citation-line update.
- **Record page→page edges** (`depends_on_pages`), or affected-page regeneration yields broken hierarchy, duplicate narrative and dead cross-links — the reason every wiki vendor regenerates wholly.
- **Cap accumulated incremental patches per page and schedule a compaction** (Zoekt's delta-shard fallback threshold): a page patched forever drifts from what a from-scratch generation would produce.
- **Store citations as path + content hash, with line ranges display-only**: line-ranged citations rot on any insertion (this repo's `a-record-correction-wave-breaks-the-record` lesson, and DeepWiki's citation form).
- **Lineage and near-duplicates PROPOSE, never decide** (§6): the output of the near-dup pass is `docs/_lineage/DISPUTED.md`, and only canonical-text-hash equality may act automatically.
- **Prototype the dependency map on ~20 pages before scaling.** Nothing surveyed does many-sources→one-page incremental re-synthesis; the local `repo-wiki` skill's structure-pass table ("files this page rests on") is the nearest thing already owned.

### 4.6 L5 — the surface the agent reads

```
docs/
  INDEX.md            llms.txt v2 shape: H1, blockquote with sync generation + the literal "what changed
                      since <date>" git command, ## groups of `- [name](path): one line`, then ## Optional
                      carrying ONLY the per-area index paths — never the mirror tree.  ≤ 200 lines / ≤ 25 KB,
                      enforced by a land-gate lint.  Past ~180 topics the root degrades to one line per
                      AREA and each <area>/INDEX.md owns its own ≤ 25 KB: two Reads to any page, at any size.
  README.md           ~60 lines: how this folder is built; which sources are Graph-delta vs manual; the
                      refresh-queue command and its verdict vocabulary verbatim; who the single writer is;
                      the retention owner and delete procedure for this plaintext copy of tenant data
  SYNONYMS.tsv        term<TAB>expansion<TAB>owner — hand-maintained; the agent greps it first and expands
                      its query with it (the vocabulary-mismatch fix that replaces embeddings)
  CHANGELOG/<yyyy-mm>.md   append-only, one section per content-changing sync: A|M|R|D per path, counts,
                      breaker state; CHANGELOG.md is a generated index of the last 30 days
  DEPENDS.tsv         generated (page ↔ source ↔ pinned sha ↔ role)
  _index/by-entity.tsv generated (entity ↔ page)
  _sync/sources.toml  Arm 0: the in-scope set (tracked)
  _sync/STATE.md      working-tree only (.gitignored): last run per source, cursor AGE + 12-hex fingerprint
                      (never the token), pass kinds, enumeration_complete flags, baseline, counts, quarantined,
                      breaker, auth state, backfill progress — the agent reads this FIRST; a committed
                      STATE.snapshot.md is written only on a cycle that already had a content commit
  _sync/QUARANTINE.tsv generated: source id, path, reason (IRM · password · malware · pending · checked-out ·
                      credential-in-content · duplicate-of · access-unknown · refused)
  _manifest/          index.jsonl shards ONLY (generated, committed — what makes the manifest diffable).
                      The converter cache is NOT here and NOT in git: ~/Library/Caches/docs-sync/<action_key>/,
                      machine-local, rebuildable, garbage-collected (§4.7); docs/.gitignore pins _manifest/cache/
  .gitignore          _sync/STATE.md · _manifest/cache/ · .sync.lock
  .gitattributes      * text=auto eol=lf · *.png binary · *.jsonl -merge · CHANGELOG/*.md merge=union
  topics/             TIER 2 — curated, entity-organized, CLAUDE.md (~15 lines: "synthesis; every claim
    CLAUDE.md          cites a docs/mirror/… page, page-relative from topics/clients/<entity>/ = ../../../mirror/…; the closed aspect vocabulary; run the refresh queue before trusting
                       a STALE page; the read-side contract for STATE.md")
    clients/<entity>/INDEX.md, <entity>-<aspect>.md …
    workstreams/…  decisions/<yyyy-mm-dd>-<slug>.md  people/…
  mirror/             TIER 1 — generated, 1:1, CLAUDE.md (~10 lines: "GENERATED — DO NOT EDIT; edits are
    CLAUDE.md          overwritten each sync; ids and hashes in frontmatter are for the pipeline — read
                       summary: and tokens_estimate:; sync command: …")
    sharepoint/<site>/<library>/<path>/<Name>.md | <Name>.xlsx.d/
    onedrive/<user>/…
    email/<yyyy>/<mm>/<yyyy-mm-dd>-<from-slug>-<subject-slug>.md   +  email/threads/<slug>.md (L4)
    teams/<team>/<channel>/<yyyy-mm>.md          one page per channel per MONTH
  figures/<sha>.png + <sha>.md       one image ≤ 2 MB, directory ≤ 2 GB; above that the figure stays in
                                     the cache and the page carries a `figure-omitted: size` stub
```

Rules and the measurement behind each:

- **Index first, discovery-by-Glob never.** Glob returns at most 100 files ordered by mtime on the ordinary tool path (`globLimits?.maxResults ?? 100` in the 2.1.114 and 2.1.183 bundles; the REPL bridge passes 25,000; the model cannot raise it) with a `truncated` flag — over a 1,192-file corpus that is not a truncation but a *biased sample* on a key `git clone` resets. Grep has its own silent cap: `head_limit` defaults to **250 in every output mode, including `files_with_matches`**, which additionally sorts by mtime descending; pass `head_limit: 0` for any completeness-critical enumeration, or use `rg` via Bash. These constants are version-perishable — re-grep the bundle rather than quote them. `INDEX.md` is the entry point, and its budget is real: 400 topics at one realistic bullet each measured 465 lines / 64,943 chars (≈ 63 KiB, 253 % of the 25 KB budget; ~185 such lines fit), and a 9,000-page mirror tree is 527 KB — so the mirror is never indexed in a file (it is reached by path from a curated page's `sources:` or by `rg` under `docs/mirror/`), and past ~180 topics the root index degrades to one line per area with a per-area index beneath it: two Reads to any page, at any corpus size.
- **Page budget ≤ 400 lines / ≤ 25 KB / ~6 K tokens, hard split at 800 lines.** The binding constraint is tokens, not the Read tool's 2,000-line default (≈ 34 K tokens at this repo's measured 61–73 chars/line; one existing research file here is 146 K chars). 25 KB is Anthropic's own shipped budget for a file meant to be read whole.
- **Names are retrieval signal** (Anthropic's context-engineering guidance says so explicitly), and an entity-first name is only as good as a **closed aspect vocabulary**: lowercase kebab-case, `<entity>-<aspect>.md` where `<aspect>` comes from the published list in `docs/topics/CLAUDE.md` (`commercial · integration-scope · renewal · support-history · …`), extended only by editing that list and enforced by a land-gate lint (measured: three free-hand spellings of one aspect dropped a `*-renewal.md` glob from 80 files to 78 at exit 0, and a widened `*renewal*` recovered two of the three — a type-shaped query fails silently and partially); no abbreviations in filenames — put them in the curated page's `aliases:` — and a `-YYYY-MM-DD` suffix only on point-in-time artefacts, never on living pages (updating one forces a rename that git reports as delete+create: measured, a rename with a 42 %-similar edit shows `D`/`A` at git's default 50 % threshold and `git log --follow` does not cross it). "Renamed" therefore comes from `source_id`, never from git.
- **Tombstones in place, with the body replaced, never retained.** The page stays at its path so citations resolve, and its whole body becomes one stub: `[DELETED UPSTREAM] <title>` · `status: deleted, deleted_at, last_seen_sha256, source_id, superseded_by?` (`status: deleted` is what makes the refresh queue report `SOURCE-DELETED`; dropping `rendered_sha256` alone would report `MISSING-OR-UNPARSEABLE`) · the literal `git show <sha>:<path>` that recovers the last content and a `git log -S'<term>' -- <path>` pointer for content search; plus the CHANGELOG entry, because a set of tombstones is not a timeline. Retaining the body is a wrong-answer path: measured, a live page and a tombstone both matched `rg -n 'unit price'` with contradicting prices, and a `[DELETED UPSTREAM]` H1 on line 7 appears in neither Grep's `content` nor its `files_with_matches` output, so no grep mode could tell the agent which line was dead. Removal alone leaves three states indistinguishable — deleted upstream, never existed, wrong path — which demand opposite actions (Debezium ships a null-valued tombstone for the same reason). Reap on a 180-day policy.
- **Per-directory `CLAUDE.md` guardrails** cost zero context until the agent opens that directory, then arrive exactly when relevant. The docs index ships as a **Skill** (description resident, body on demand); the root `CLAUDE.md` gets three lines: `docs/INDEX.md` is the map, `mirror/` is generated, and the one command that answers "what changed".
- **Freshness is greppable text or `git log`, never mtime.**
- **`aliases:` and `SYNONYMS.tsv` before embeddings — and both live in the curated layer, never on a mirror page.** Grep's real failure is vocabulary mismatch ("PO" vs "purchase order"); the curated page's `aliases:` (agent-owned) and one hand-maintained `docs/SYNONYMS.tsv` (`term<TAB>expansion<TAB>owner`, linked from `INDEX.md`, grepped first to expand a query) close it with no infrastructure. A synonym is a judgment no converter derives from bytes, so it cannot sit in content-derived mirror frontmatter, and replicated onto every unit of a source it selects the corpus (measured: 1,200 of 1,200 sheet pages matched the alias term through their own frontmatter). Cursor's own A/B (+0.3 % overall) and Sourcegraph retiring its embeddings layer are the evidence that vectors are not worth their freshness burden here.
- **The read-side contract for `docs/_sync/STATE.md`**, duplicated in `docs/topics/CLAUDE.md`: `enumeration_complete=false` or `baseline: INCOMPLETE` on any source → the corpus has holes, and a negative answer must read *not found in docs/, and source X was incomplete at <run>*, never a bare "nothing found". Cursor age > 3 × that source's cadence, or the breaker tripped → deletions and tombstones are unreliable; do not assert a document is gone and do not act on a tombstone. `quarantined > 0` → name the count and point at `_sync/QUARANTINE.tsv`; those sources are unreadable, not absent. `auth: REAUTH_REQUIRED` → say the sources are N days stale and a human must re-authenticate. A `⚠ STALE` page is cited *as of* its pinned sha, never as current. STATE.md missing or older than the reconcile interval → treat all of `docs/` as provenance-unknown and say so in the first line. If vectors ever become necessary it is a search-over-the-mirror problem: sqlite-vec, upserts keyed on `rendered_sha256 + chunk hash`, deletes by `source_id` on tombstone.
- **Run the sync, and any broad search over the mirror, in a subagent** so only the summary returns to the lead's context.

### 4.7 L6 — operations

- **Who runs it — decide before week 1.** Exactly **one principal on one machine** is the writer for a given `docs/` repo; everyone else consumes read-only with `git pull --ff-only`, and a consumer that has committed re-clones. The delta cursor, the breaker's denominator and the `principal` column are all per-view state, so two writers produce a manifest that merges two different views of the tenant: measured on a two-clone fixture, concurrent cycles conflict on the `_manifest/index.jsonl` shards and `CHANGELOG.md` every time, and `merge=union` "fixes" the log losslessly while silently keeping two contradictory hashes for one `source_id` in the manifest. If a second writer is genuinely required: disjoint `mirror/<principal>/` and `_manifest/<principal>/` subtrees with `topics/` single-writer (curation is not mergeable); `.gitattributes` with `CHANGELOG/*.md merge=union`, `DEPENDS.tsv merge=union`, `*.jsonl -merge` (refuse to auto-merge shards); per-writer `_sync/STATE-<host>.md`; each writer pushes its own branch and a scheduled job fast-forwards main only when a disjointness lint passes — a writer that cannot fast-forward stops and alarms, never merges.
- **Hosting, decided.** `docs/` is its own git repository on local disk, **outside** any `~/Library/CloudStorage` or OneDrive path — a git dir inside a File Provider tree inherits every §3 failure into the derived layer. Its remote is tenant-owned (GitHub EMU / Azure DevOps) or there is none; with no remote the repo is the only copy, so an encrypted local backup is mandatory and the recovery claims that rest on git — the tombstone's `git show <sha>:<path>` (§4.6) and "`docs/` is the only guaranteed copy of a revision's text" (§5) — are scoped to that backup. The writer commits in the repo; **the agent reads a separate worktree checked out at the `published` tag**, advanced once per cycle after the commit — that is what makes "never a mid-write tree" mechanical. The publisher then copies the untracked `_sync/STATE.md` into that worktree, because a gitignored file does not travel with the tag and the agent reads it first.
- **Cadence, with the arithmetic.** Graph delta poll 60 s–5 min per drive (1 RU each). A full reconcile costs ⌈items / 1,000⌉ delta pages × ~1.35 s per page (rclone #9226's reporter measured 482 pages / ~11 min to conclude nothing changed on a large library; nothing rclone-side was run in this wave): **~50 pages ≈ 1 min at 50 k items**, ~22 min at 1 M. At this corpus size the reconcile runs **hourly**; Microsoft's "no more than once per day" recommendation binds only past ~10⁵ items. The *local* T3 reconcile is sub-second at 10⁵ files on APFS (measured, §9 probe 5), so on local disk it runs at every session start and every 15 min with no watcher; its cost on a File Provider tree is still unmeasured — measure that before choosing the cadence there, and record the number in STATE.md. Poll and reconcile are separate launchd jobs contending for the one lock: the reconcile takes it, the poll skips its turn (rc 75, logged `skipped: lock held`, not failed; a skipped poll is not an incomplete pass). Tier-2 PDF backfill and VLM captioning are separate budgeted off-peak jobs with `backfill: <done>/<total>` in STATE.md; the initial crawl is egress-bound (100 GB/h delegated) and resumable.
- **Two launchd agents, never one job doing both** (launchd will not start a second instance of a running job, so an 11-minute reconcile would silently swallow ten poll intervals): `com.<org>.docs-sync.poll` (`StartInterval 300`) and `com.<org>.docs-sync.reconcile` (`StartCalendarInterval`, off-peak). Both: `ProcessType Background`, `ThrottleInterval 60`, `RunAtLoad true`, `LimitLoadToSessionType Aqua` (the job needs the user's Keychain and the CloudStorage mount), `MaterializeDatalessFiles false` (the per-job key that makes hydration fail-closed), `EnvironmentVariables PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`, logs under `~/Library/Logs/docs-sync/`. a launchd job gets a minimal PATH with no Homebrew (documented behaviour, not measured here), and this Mac's own toolchain shows why that bites: `/bin/bash` is 3.2.57 against the Homebrew 5.3 on the operator's PATH, and `pandoc` is not installed at all (measured — so the recommended `.docx` converter was never run in this wave) — so every script is bash-3.2-clean or pins an absolute interpreter, and every converter is invoked by an absolute path asserted present at startup. **TCC:** `~/Library/CloudStorage` is protected and a background agent cannot prompt — an `EPERM` reads as an empty directory — so grant Full Disk Access to the interpreter launchd execs (an MDM PPPC profile on a managed fleet) and make the walker assert a known-present canary path at startup: a scope returning zero children is `unknown` and never reaches the classifier. **Network:** gate the Graph arm on reachability; no network is `skipped`, not `failed`, so a laptop off VPN neither burns the retry budget nor writes a misleading incomplete-pass flag.
- **Lock, durability order, recovery.** `flock(LOCK_EX|LOCK_NB)` on `<docs>/.sync.lock` whose body is `<pid> <boot_time> <iso8601> <label>`; a lock whose pid is dead *or* whose boot time differs from the current one is stale — break it, log it, and force the next pass to `full_enumeration` because the dead run's scope is unknown. Durable stores are written in one order, each step idempotent and re-runnable from the one before: (1) converter outputs into the cache via `tmp-*` + rename, so a half-written key is never readable; (2) one SQLite transaction (`journal_mode=WAL`, `synchronous=FULL`) carrying `run_id`, `pass_kind`, `enumeration_complete[S]` and the *pending* cursor as data; (3) materialize `docs/` from the manifest (temp + rename per file) and export the NDJSON shards; (4) `git commit` — **this** is "durably consumed"; (5) only now promote the pending cursor to current, in its own transaction. Recovery runs before any source is touched: manifest `tree_sha` ≠ `git rev-parse HEAD^{tree}` means the last cycle died between 3 and 4 — `git reset --hard HEAD && git clean -fd docs/mirror docs/_manifest` and replay from 3 (every byte is reconstructible from manifest + cache, which is why the cache survives the reset); `pending` ≠ `current` cursor means it died between 4 and 5 — the commit is authoritative, adopt `pending`. Never resolve a dirty tree by committing it: that publishes a half-applied change set as a cycle.
- **A commit only when content changed.** One manifest snapshot and one commit per cycle *that changed content*: a cycle whose `mirror/` + `topics/` + `_manifest/` diff is empty commits nothing, so `git log` holds only real change and `git log --since` stays the freshness API (at a 60 s cadence a commit-per-cycle would be 1,440 commits a day of nothing). Cursor ages, pass counters and breaker state are volatile and live in the `.gitignored` `_sync/STATE.md`; a committed `_sync/STATE.snapshot.md` rides along only on a cycle that already had a content commit. Commit subject: `sync: <A>a <M>m <R>r <D>d <sources>` so the log scans without opening the CHANGELOG.
- **Growth.** The converter cache lives at `~/Library/Caches/docs-sync/<action_key>/` — never in `docs/`, never in git (`action_key` includes `canonical_hash`, so every revision mints a new immutable directory; in git that is a second copy of the corpus on day one and one more per edit, forever, that no later deletion reclaims). Land-gate lint: `git ls-files docs | grep -q '_manifest/cache/'` must fail. The cache is garbage-collected by ninja's `cleandead` rule after each successful full enumeration — delete every key that appears in no live `output` row, with a grace of one converter version. `CHANGELOG/` rotates monthly (a year of 5-minute cycles in one file is a 100 k-section file nothing can read). `figures/` caps one image at 2 MB and the directory at 2 GB; no git-LFS.
- **Manifest and key migrations.** The manifest carries `meta(key_schema_version, manifest_schema_version, tree_sha)`; on a mismatch the pipeline **refuses to run** and prints the migration command, never silently re-deriving. `docs-sync migrate` (a) rebuilds SQLite from the committed NDJSON shards — the shards are the durable form, SQLite is a cache — and (b) on a `key_schema_version` bump writes a `KEYMAP-<old>-<new>.tsv` so unchanged inputs are a rename inside the cache and only genuinely changed rows re-render. A re-render that must run is a separate off-peak job with a page budget, resumable, ~10 h per 50 k pages at the ~1.3 p/s tier-2 rate; never inline in a sync cycle.
- **Secret custody — three secrets, three homes, none of them git.** The refresh token → macOS Keychain (`security add-generic-password -s docs-sync -a <upn> -w -T <binary>`), read at start, rewritten on every refresh. The `deltaLink` per drive → `~/Library/Application Support/docs-sync/cursors.sqlite`, mode 0600, on a FileVault volume — it is a URL carrying a tenant sync token, and the first draft of this design would have exported it into git inside the manifest snapshot. Nothing in `docs/`; the committed manifest and `_sync/STATE.snapshot.md` carry a cursor's *age* and a 12-hex *fingerprint*, never the token. Land-gate lint: no committed file matches `token=|deltatoken=|Bearer `. **Auth is a finite resource and its exhaustion must be loud:** on `invalid_grant` / `AADSTS50076` / `AADSTS50173` (inactivity, CAE revocation, a Conditional Access re-auth requirement — the likeliest way this pipeline dies quietly three weeks in), do not retry, do not advance any cursor, write `auth: REAUTH_REQUIRED <utc>` into STATE.md and into the heartbeat store, and exit non-zero — the watcher pages on it and STATE.md is what the agent reads first (STATE.md is gitignored, so nothing is committed for it).
- **Secrets are content here, and git is permanent.** Corporate files carry connection strings in cells, API keys in appendices, passwords in `.msg` bodies; this pipeline converts them to plaintext and commits them. Run gitleaks/trufflehog over every generated page as a **land gate**: a hit quarantines the page to an `UNREADABLE: contains a credential` stub and files the source id, because removing a committed key later does not remove it from history. On offboarding, `docs/` is a full-fidelity plaintext copy of tenant data that survives access revocation — name its retention owner and delete procedure in `docs/README.md`.
- **Liveness is a separate, outward signal, and it is not STATE.md** — STATE.md is written by the puller, so it cannot report the puller's death; its last successful line reads healthy forever. Emit a heartbeat per source to a store outside `docs/` on every completed pass (`last_success_at, run_id, pass_kind, enumeration_complete`), and run a *separate* watcher that pages a channel a human reads when any of: cursor age > 3 × that source's cadence; `enumeration_complete=false` for K consecutive runs; breaker tripped > 24 h; last content commit older than the reconcile interval on a source that reports changes. Judge freshness against the subject (last source change seen), not the wall clock. A line in launchd's stderr is silence.
- **Retirement is an explicit verb, not an absence.** `sources.toml` state `retired` (with `retired_at`, `reason`) is the operator asserting a disappearance is intended: the mirror subtree is tombstoned in one labelled commit **exempt from the breaker** (which exists to catch an *unasserted* mass deletion), the cursor is dropped, and curated pages citing it get a `SOURCE RETIRED — <reason>` banner rather than `STALE`, because no re-curation clears it. Losing *access* stays `quarantined`: under delegated auth a permission gap and a real delete are the same silence — `Prefer: deltashowremovedasdeleted, deltatraversepermissiongaps` annotates them but needs `Sites.FullControl.All`; without it, any scope whose candidate set exceeds the breaker is `access-unknown` until a human rules, never a tombstone.
- **Budgets as first-class state.** Per-run byte budget for `materialise()`, egress per hour, RU per minute (against the narrower of the per-app and tenant-wide buckets), converter memory (openpyxl's normal mode is ~50× the file size); a run that exhausts a budget records `enumeration_complete=false` for that scope, which keeps absence-based deletion disabled and the cursor un-advanced.
- **Compliance is data, not a footnote.** Delegated views are per-principal — record the principal, never merge two users' mirrors. Carry the highest sensitivity label into page frontmatter; exclude above a threshold; IRM-encrypted files are `quarantined` rows with stub pages. A git mirror flattens labels, DLP and ACLs and is an exfiltration channel: keep the remote tenant-owned or absent, and expect Endpoint DLP to be able to block `git`/`node` reads of CloudStorage (policy-dependent).
- **Time is advisory.** Store server and client timestamps separately in UTC ISO-8601; client-supplied `fileSystemInfo` stamps can precede the service's own `createdDateTime` (observed live); mtime never decides.
- **Names, and the repo must check out on Windows.** NFC for identity, raw bytes in provenance, `core.precomposeunicode=true`; the slugifier's Windows rules and 200-character cap (§4.4); `docs/.gitattributes` with `* text=auto eol=lf` and `*.png binary` (a Windows checkout under `core.autocrlf=true` otherwise rewrites every markdown file and reports the corpus modified on first `git status`); a land-gate lint rejecting any tracked path that fails the slugifier or exceeds 200 characters; leave rclone's unicode normalization on if rclone is the transport.
- **rclone, demoted to transport.** `--onedrive-delta` is a cheap *full listing*: the delta call is issued with the token parameter commented out (`backend/onedrive/onedrive.go:1596`, entry point `:1594`, at v1.75.1 per the C4 report; the C3 verifier's re-read of master found the same commented line), rclone persists no `deltaLink` (its only token loop is `ChangeNotify`, seeded from `latest` in a process-local variable), and its sync is "stateless like all of rclone's syncs". The O(changes) door is `rclone copy --files-from-raw changed.txt --no-traverse` (~1 API call per file) with a separate local delete pass (`sync` ignores `--no-traverse`), `--backup-dir` so same-name overwrites stay diffable, `--max-delete` set explicitly, `--use-json-log` parsed with an assertion that a run reporting transfers yielded non-zero parsed rows, and never `--checksum` on the hot path (SharePoint's Office-file enrichment makes it cry wolf on the majority file type).

### 4.8 Budget, latency and the token bill

| | Arm A (Graph delta) | Arm B (local T3 walk over the sync client) |
|---|---|---|
| change-detect latency | ≤ 60 s (poll) | ≤ 15 min (walk every 15 min + at session start) |
| worst case before the reconcile catches it | 6 h (webhook tail, if used) → hourly reconcile at ≤ 10⁵ items | the walk interval → the 15-min T3 walk is itself the full enumeration (§4.7) |
| cost per cycle | 1 RU per drive (0.12 % of the smallest per-app budget at 60 s) | one `getattrlistbulk` walk, zero opens, zero downloads — **0.13–0.31 s per 10⁵ files on local APFS (measured, `verify/C11-local-walk.md`)**; File Provider unmeasured (§9 probe 5) |
| full reconcile | ⌈items / 1,000⌉ × ~1.35 s ≈ 1 min at 50 k | the same walk: sub-second at 10⁵ files locally |
| manifest bookkeeping | 31 MB / 0.12 s load / 0.051 s compare at 200 k rows (measured) | same |
| initial crawl | egress-bound: 100 GB ≈ 1 h floor per delegated user, off-peak, resumable | pin subtrees; hydration is the cost |
| PDF backfill | 5.5 p/s born-digital; ~1.3 p/s tier 2 (OCR off; OCR on is slower) ⇒ days for tens of GB of scans | same |
| **agent tokens per question** | `INDEX.md` ≤ 6 K + `STATE.md` ≤ 0.5 K + 1–3 pages ≤ 6 K each ⇒ **≈ 8–25 K resident, no tool call into a binary** | same |
| agent tokens per sync on the lead | 0 (the sync and any broad mirror search run in a subagent) | 0 |

"Typically under a minute" is an arm-A statement; a laptop on arm B publishes "typically under 15 minutes, guaranteed within 24 hours", and STATE.md says which arm each source is on. The two receipts disagree by ~8× on local SHA-256 throughput (2.4 GB/s vs 290 MB/s, different harnesses) — a full-corpus hash is minutes of CPU either way and hours of hydration, which is why phase 1 reads no bytes.

---

## 5. Same-name updates, renames, and the version mess

**In-place overwrite (same name, new bytes):** keeps the driveItem id; eTag and cTag both change; `quickXorHash` changes; a `driveItemVersion` is minted. Detected in phase 1 with zero download by `provider_hash`. Locally: `GEN_COUNT` moves (in-place) or `FILEID` changes (safe-save). On the tags: cTag is documented as "an eTag for the content … not changed if only the metadata is changed" and eTag as "for the entire item (metadata + content)", **for files** — on folders the roles are near-inverted (cTag moves on any descendant change) and in OneDrive for Business / SharePoint libraries cTag is not returned for folders at all. The `"{GUID},n"` / `"c:{GUID},n"` shape with separate counters is an example-response observation (and one live consumer read in the wave showed a divergent pair; the verifier's reads showed equal pairs) — compare both as opaque strings, never parse or difference them.

**Metadata-only touch (rename, move, label, retention):** eTag moves, hash holds (and cTag holds where present) → `METADATA_ONLY`: re-map the path, rewrite frontmatter, keep the markdown. A sensitivity-label rollout across a library is then a frontmatter sweep, not a corpus re-conversion — *unless* the label encrypts, in which case the served bytes change (§4.2 trap 2) and the item moves to `quarantined`/`UNREADABLE`.

**Re-upload of the same bytes under a new name:** `canonical_sha256` equal, new `source_id` → **alias-of**, never a second page.

**Version history is not a lineage substrate.** `driveItemVersion` exposes no hash (schema and live probe), versions are trimmed by tenant/site/library policy outside the recycle bin, old-version metadata is documented incomplete, and a *copy* is a new driveItem with no history (`conflictBehavior=replace` on copy deletes the target's history). Once a revision is converted and committed, `docs/` in git is the only guaranteed copy of that revision's text.

**Filename version chaos** (`Report v2.xlsx`, `Report_final_FINAL (1).xlsx`, `Report-LAPTOP123.xlsx`):

- Enumerate the *generators* — Graph rename-conflict integer, OneDrive `-<HOSTNAME>` conflict suffix, Explorer `- Copy`, human `v2`/`FINAL`/`draft`, date stamps — and strip a trailing integer **only when an un-suffixed sibling exists** in the same folder or the tombstones. Live counterexamples: `Lyft Receipt 3.pdf` and `Lyft Receipt 4.pdf` are different documents; separately, two probed items had a `createdDateTime` order that is the *inverse* of their client-supplied modified order.
- The family key is the residue after token extraction; refuse any merge whose residues differ by a non-version token (`Report Q1 v2` vs `Report Q2 v2`).
- **Near-duplicate detection proposes, never decides.** 64-bit simhash at k=3 runs at ~0.75 precision on web pages, and same-site pairs — which a corporate library sharing one template is by construction — measure 0.38–0.50 (0.79 for a combined Broder+Charikar algorithm). Run Broder shingling for recall and simhash for precision over template-stripped text; write candidates to `docs/_lineage/DISPUTED.md`.
- **Direction comes from containment, not from filename tokens or a single clock**: Broder's resemblance is not transitive, so chain lineage pairwise between adjacent candidates, never union-find a family; his asymmetric containment `c(A,B)` says which supersedes which, corroborated by the two clocks; disagreement goes to DISPUTED.
- A superseded page keeps its body — it is history, not dead content — so the marker cannot be a banner: a first-body-line `SUPERSEDED — see …` is invisible in every Grep output mode (measured, §4.6), so supersession lives in frontmatter (`status: superseded`, `superseded_by`), which the §4.6 read-side contract makes the agent check at every mirror hit, with the banner kept only for a human opening the file; one family file per document family holds the lineage table (label, source name, item id, both clocks, size, canonical-sha prefix, relation, status). Same item id across rows means in-place overwrite; different ids with equal canonical hash means re-upload or copy.
- A restore that replays an ancestor's hash emits `reverted-to: v_n`; it does not mint a new version and it does not loop.

---

## 6. Failure modes, ranked, and the design element that closes each

| # | Failure (silent-wrong unless noted) | Closed by |
|---|---|---|
| 1 | Reading a dataless placeholder: `EDEADLK`/0-byte read → empty hash recorded → "unchanged forever"; or mass hydration then eviction | `dataless` state from `st_flags`; `setiopolicy_np` materialize-OFF inherited by every stage; budgeted `materialise()`; never hash `st_blocks==0` |
| 2 | SharePoint rewrites Office/PDF/HTML bytes after upload; AIP-labelled files hash differently online vs downloaded | two hash columns never equated; `provider_hash` is the change signal, `content_hash` the identity; never compare across channels |
| 3 | Path-keyed manifest: one folder rename strands a whole subtree (delta emits one record, no descendants, no path) | id→(parent, name) tree; paths derived |
| 4 | Since-token expiry (410, journal wrap, Watchman fresh instance) returns only *existing* files, so deletes are never synthesized | manifest-minus-enumeration on every resync; the scheduled reconcile (hourly at this size, §4.7); tombstones from Graph's `deleted` facet consumed, not discarded |
| 5 | Truncated listing (429 storm, unhydrated tree, interrupted pass) reads as mass deletion | `enumeration_complete[scope]` flag set only by a finished full enumeration; per-scope floored 20 %/7-day breaker; `--max-delete` on any transport |
| 6 | cTag absent on ODB delta; eTag moves on labels/renames → corpus re-pull on every metadata sweep | `quickXorHash` as key; `METADATA_ONLY` class |
| 7 | Converter nondeterminism or a `converted_at` field churns every `rendered_sha256`, marks the whole curated layer stale, and the diff-only design fails closed into a full re-curation | write-once cache keyed on producer identity; content-derived frontmatter only; double-conversion gate |
| 8 | OOXML no-op save changes container bytes | canonical per-part hash + H2 early cutoff |
| 9 | IRM/sensitivity-encrypted files convert to empty pages, exit 0 | classify before converting; `UNREADABLE` stub; quarantined row |
| 10 | Curated page drifts after its sources change and nothing goes red | pinned `at_rendered_sha256`; generated `DEPENDS.tsv`; linter-prepended STALE banner |
| 11 | Symlinked source: Glob/Grep/find/git see nothing, exit 0 | real directory; `find -type l` land-gate lint; positive-control file in every recursive search |
| 12 | Mid-write capture (autosave, `~$` locks, half-copied drop) mirrored as a version that never existed | quiescence gate; two-read hash agreement; ignore lock/tmp patterns |
| 13 | `@removed` on mail for a *moved* message deletes a page | cross-folder check before any mail delete |
| 14 | Per-principal permission divergence; lost access surfacing as delete | `principal` column; never merge mirrors; access loss is a quarantine, not a tombstone |
| 15 | Throttling spiral: retries count against the same RU budget; delegated egress cap mid-crawl | global pause on Retry-After; off-peak resumable crawl; hash-gated downloads |
| 16 | Giant Excel/PDF → multi-hundred-MB markdown page | per-sheet split, row caps + CSV sidecar, `tokens_estimate`, streaming |
| 17 | APFS case-insensitive slug collision; `[` in filenames poisoning globs; NFD/NFC twins | slugifier rules; NFC identity; id-disambiguation |
| 18 | Log-string parsers (rclone English messages) silently yield an empty change set after a version bump | JSON logs + non-zero-rows assertion |
| 19 | Believing the vendor's freshness framing (DeepWiki "auto-syncs"; rclone `--onedrive-delta` "uses delta") | own cursor, own reconcile, both measured |
| 20 | git mirror as exfiltration channel; DLP blocking reads | labels carried, threshold exclusion, tenant-owned remote, DLP tested per tenant |
| 21 | **The puller stops** (launchd unloaded, refresh token dead, machine asleep, crash) while `docs/` still looks healthy and STATE.md is frozen at its last success | heartbeat written outside `docs/` on every completed pass; a *separate* watcher pages on cursor age > 3 × cadence, `enumeration_complete=false` streaks, breaker > 24 h, or last content commit older than the reconcile interval; `auth: REAUTH_REQUIRED` written and exit non-zero on `invalid_grant` |
| 22 | First incremental poll after bootstrap reads every un-touched row as absent and trips the breaker; or `token=latest` used as a bootstrap mirrors only future edits, forever | absence counts only inside a full enumeration; the first pass is always a full enumeration; per-scope floored breaker |
| 23 | Secrets in content (a connection string in a cell, an API key in an appendix) converted to plaintext and committed, where history keeps them after any fix | gitleaks/trufflehog as a land gate; a hit quarantines the page to an `UNREADABLE: contains a credential` stub |
| 24 | The same document mirrored twice — dropped into the inbox and synced from the library — under two ids, cited independently | arm precedence on the canonical text hash; the inbox quarantines duplicates naming the mirror path |
| 25 | Two writers on one `docs/` repo: manifest shards conflict every cycle, and `merge=union` silently keeps two contradictory hashes for one id (measured) | exactly one writer per repo; consumers read-only; `*.jsonl -merge` |

---

## 7. The no-API path, stated honestly

It is **arm B plus arm C with the accelerator removed**, not a degraded arm A. What it keeps: exact created/renamed/deleted detection via the id→tree diff on `(FILEID, GEN_COUNT)`; O(changes) conversion; the whole L2–L6 stack unchanged. What it loses: the zero-byte "did the content change" oracle (a same-size, same-second, mtime-preserving overwrite is invisible to stat; `GEN_COUNT` catches it on APFS and is unmeasured on File Provider), and cloud-side hashes for AIP-labelled files. What it costs: hydration — every content check on an online-only file is a download, so pin the in-scope subtrees and budget the rest. What it needs from IT: nothing beyond the sync client, provided the walker is a plain binary (no Homebrew Watchman, no launchd daemon needed for T3). claude-code #40783 shows a sandboxed Claude reading a File Provider path failing every read with `EDEADLK` — another reason the agent never works from the sync root.

**Portability, stated.** Arm B is macOS-only by construction (FSEvents, `getattrlistbulk`, `ATTR_CMN_GEN_COUNT`, `SF_DATALESS`, `setiopolicy_np`). Arm A is the only portable arm: a Windows or server deployment runs arm A, and the equivalent local tier there is the NTFS USN change journal plus `FILE_ID_INFO` and `FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS` — a separate build, unmeasured here, not a flag. `docs/` itself must stay portable because it is shared: the slugifier's Windows rules and the 200-character path cap (§4.4), `* text=auto eol=lf` in `.gitattributes` (§4.7), and a Windows consumer is read-only.

---

## 8. Alternatives considered and rejected

| Alternative | Why not |
|---|---|
| Symlink `docs-source` → CloudStorage | §3: invisible to every agent tool, hydration on read, no since-token |
| Hash everything each run | 100 GB ≈ minutes of CPU but *hours* of hydration on a File Provider root; mid-write hashes record content that never existed; the manifest already gives O(changes) with zero bytes |
| rclone as the change cursor | full listing per run; no persisted deltaLink; stateless by design — keep it as transport only |
| Watchman as the since-token | clock dies with the daemon; journal resync off by default; ignores symlink targets; Homebrew + launchd approval in a managed fleet |
| DVC / a build system | outputs deleted at repro start; per-file stages quadratic in bookkeeping; deletion manual — steal ninja's `restat` + `cleandead` and Bazel's action key instead |
| Content-defined chunking | 1-byte edit inside a deflate stream left 13 of 11,137 bytes in common; pays only on extracted parts and PDFs |
| A vector index from day one | Cursor's own A/B (+0.3 % overall); Cursor's current default is a local embedding-free index; Sourcegraph retired embeddings over freshness burden; `aliases:` fixes the vocabulary-mismatch case for free |
| DeepWiki-style whole regeneration of the curated layer | unaffordable per change and measured stale in practice; the dependency map makes affected-page regeneration possible |
| Webhooks as the trigger | up to 6 h latency; root-only on OneDrive for Business (any subfolder on personal; a SharePoint library subscribes as a `list`); the payload names the subscribed folder, never the changed item; public HTTPS or Event Hubs required; polling delta at 1 RU is free |
| Graph version history as lineage | no hashes, policy-trimmed, copies lose history |
| MarkItDown for everything | silent `NaN` on formula cells, dropped unheaded columns, no `.eml` converter, 1.9× the characters of PyMuPDF4LLM on a real PDF with worse tables |
| `converted_at` in frontmatter | rewrites every file on any forced re-render; belongs in the manifest |

---

## 9. What to measure first on the corporate tenant

None of these could be measured in this wave (the work account on this Mac is logged out; the OneDrive client and File Provider extension are installed but no sync domain is signed in, so `~/Library/CloudStorage` is empty). Each is one probe, and each decides an arm:

| # | Probe | Decides |
|---|---|---|
| 1 | `GET /sites/{id}/drive/root/delta?$select=id,name,size,eTag,cTag,file,parentReference` on a real SharePoint library and a real OneDrive for Business: count file items whose `file.hashes` lacks `quickXorHash` (expect OneNote and zero-size); is `cTag` present on create/modify records (documented absent on ODB; **unstated for libraries**); is it populated immediately after an upload or does it lag? | whether phase 1 is zero-byte on the corporate population |
| 2 | Non-admin device-code sign-in requesting `Files.Read.All` and `Sites.Read.All`: consent screen, or `AADSTS65001` / "Need admin approval"? If `Policy.Read.All` is grantable, read `permissionGrantPolicies` to see which consent policy the tenant runs | whether arm A reaches client SharePoint without an admin (a tenant setting, not a permission property) |
| 3 | With a since-token watcher on `~/Library/CloudStorage/…` and another on the OneDrive private store, edit a file from the web UI: which fires, with which flags, for (i) a materialized file, (ii) a dataless file, (iii) a never-browsed subtree | whether arm B's T1/T2 exist at all on File Provider |
| 4 | `ls -l% <online-only file>` and `stat -f '%f %z %b'` (expect `%`, full size, 0 blocks, bit 0x40000000 set); then `cat` it under the default policy (expect: blocks, downloads) and under a `setiopolicy_np` materialize-OFF wrapper (expect `EDEADLK`, errno **11** on macOS — the "errno 35" in claude-code #40783 is Linux's number, from that issue's Ubuntu-VM sandbox); then check the same from a launchd agent, whose per-job `MaterializeDatalessFiles` key may differ from the login session | the hydration model every stage assumes, in both contexts the pipeline runs in |
| 4b | Download a sensitivity-labelled file twice and an unlabelled Office file twice from the same library; compare sha256 | whether `content_hash` is a stable identity on the corporate population (undocumented either way) |
| 5 | `getattrlistbulk` walk of the pinned subtree: is `ATTR_CMN_GEN_COUNT` in `RETURNED_ATTRS` on File Provider, and what is the wall-clock cost there? **Local APFS floor now measured (2026-09-22, receipt `verify/C11-local-walk.md`):** a 60-line `getattrlistbulk` walker over 100,000 files in 1,001 directories took 0.31 s on the first pass after creation and 0.13–0.14 s warm; a Python `os.scandir`+`lstat` walk took 0.30 s. T3 alone is fast enough on local disk to run at every session start with no watcher; only the File Provider arm remains unmeasured | whether T3 alone is fast enough to skip the watcher — locally, yes |
| 6 | Open a real tenant `.xlsx`/`.docx`/`.pptx` in Excel/Word/PowerPoint, Save without edits, diff the per-part rollup excluding `docProps/*`. **Attempted here 2026-09-22 and GUI-gated (receipt `verify/C12-office-resave.md`):** scripted Office (AppleScript, files inside each app's sandbox container) never completed a save — Excel returned `-50` on every save form, Word `-1708`, PowerPoint sat on a modal an unattended session cannot answer — so the Office arm needs one manual Save per app on a real file, then the comparator. **LibreOffice's headless round-trip did run:** a no-op re-save changed `xl/styles.xml` and both `xl/worksheets/sheetN.xml` parts, so the volatile-part denylist is NOT sufficient across writers and only the output-hash early cutoff (H2) makes a no-op save free | how narrow H1-on-parts is — for LibreOffice-written files it is not narrow at all; H2 is load-bearing, not an optimization |
| 7 | Convert a 50-file sample twice with each chosen converter, compare bytes | the double-conversion gate's baseline |
| 8 | One real tenant workbook last saved by Excel through the openpyxl emitter | confirms cached values exist where the NaN bug would otherwise be silent |
| 9 | Delta token left idle 30/60/90 days | the real deltaLink lifetime (undocumented) and the reconcile floor |

---

## 10. Build order

1. **Week 0 — decisions that cannot be retrofitted.** Who the single writer is and on which machine; where `docs/` lives (its own repo, outside any cloud-synced path) and whether it has a tenant-owned remote; the AGPL call on PyMuPDF; the in-scope set as `docs/_sync/sources.toml`. **Adopting an existing hand-made `docs/`:** move every existing page into `topics/` — never `mirror/`, which the next sync overwrites — stamped `provenance: hand-written, adopted_at: <date>` with an empty `sources: []`; such a page is exempt from the STALE linter and absent from `DEPENDS.tsv` by design (nothing mechanical can judge it), `INDEX.md` groups adopted pages separately so the agent can see which half of the corpus has mechanical freshness, and converting one is deliberate: add pinned `sources:`, drop `provenance`, and it joins the queue.
2. **Week 1 — the correct pipeline with no accelerators.** Real `docs-source/`; T3 metadata walk + SQLite manifest with the three-hash classifier and multi-state verdict; `openpyxl` emitter, pandoc, MarkItDown-pptx, PyMuPDF4LLM (or Docling-pypdfium pending AGPL clearance); write-once cache; `docs/mirror/` with content-derived frontmatter; `INDEX.md`, `CHANGELOG.md`, `STATE.md`, per-dir `CLAUDE.md`; one commit per cycle; tombstones + breaker; land-gate lints (no symlinks, double-conversion, frontmatter contract). Run the §9 probes in parallel.
3. **Week 2 — Graph arm.** Own Graph client (or `graph-batch`); per-drive delta state machine with 410/400 split and atomic cursor; `quickXorHash`-first classifier; mail folder delta with two-phase fetch; the hourly reconcile (§4.7); throttling discipline.
4. **Week 3 — curation map.** `sources:` frontmatter contract; generated `DEPENDS.tsv`; refresh-queue command in README; STALE linter; debounce; prototype on ~20 curated pages and measure how often affected-page regeneration produces cross-page incoherence before widening.
5. **Then** Teams channel delta + monthly rollups, tier-2 PDF backfill and VLM sidecars as budgeted batches, lineage/near-dup proposals, FSEvents T1/T2 only if the §9 probe 5 number says T3 alone is too slow.

---

## 11. Receipts

Per-axis reports (`agent-context-sync-2026-09-21/`): `A1-cursor`, `A2-deepwiki-indexers`, `B1-graph-drive-delta`, `B2-graph-notify-mail-teams`, `C1-macos-onedrive-symlinks`, `C2-watchman-fsevents`, `C4-rclone`, `D-manifest-buildgraph`, `E-converters`, `F-rag-incremental-ingestion`, `G-agent-docs-conventions`, `H-version-mess`, `I1-hostile-reviewer`, `I2-red-team-symlink-hash`. Verifier reports `verify/C1..C10` with their compiled probes in `verify/experiments/`, plus `verify/C11-local-walk.md` and `verify/C12-office-resave.md` for the two 2026-09-22 measurements. Four post-wave review lenses — `review/facts.md` (receipts), `review/operate.md` (operations), `review/retrieval.md` (the consuming agent), `review/completeness.md` — whose fixture scripts and generated artifacts are in `review/scripts/` (four scripts carry a shebang and a shellcheck-directive header added afterwards so this repo's land gate accepts them; no command was changed; the larger fixture trees they name — `grepfix`, `tomb`, `topics`, `fixture` — were not retained; each report quotes its outputs). A final two-lens audit (internal consistency, receipt traceability) produced the 28 corrections in the commit that added this paragraph. Every table row above names its source axis by mechanism; the reports carry the URLs and quotes, and a reproduction command wherever one was recorded.
