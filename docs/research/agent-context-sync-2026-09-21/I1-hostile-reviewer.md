# I1 — Hostile review of the L1–L5 "always-synced docs/" design at M365 scale

Verdict: the layered design is sound in shape and wrong in three premises. It assumes (1) the source bytes are stable and readable, (2) the local filesystem is a filesystem, and (3) a "since token" is a durable cursor. In a corporate M365 tenant on macOS, all three are false in ways that produce **wrong pages with no error**, not crashes. Ranked below by severity × likelihood. `[E]` = empirical (cited), `[T]` = theoretical (derived).

## Ranked failure modes

### 1. No-API path reads placeholders, not files (sev: critical · likelihood: certain on macOS 12.1+)
- Trigger: L1's watcher or a converter opens a file under `~/Library/CloudStorage/OneDrive-*` that OneDrive has not hydrated. Since the File Provider rewrite, "New files or folders created online or on another device appear as online-only" by default. [E] https://support.microsoft.com/en-us/onedrive/save-disk-space-with-onedrive-files-on-demand-for-mac
- Symptom: Anthropic's own bug: "All attempts to read file contents from FileProvider-backed paths fail with `EDEADLK` (errno 35, 'Resource deadlock avoided'). Directory listing and file metadata access work correctly." Root cause "The bridge is not using `NSFileCoordinator`", evidence "`Blocks: 0` in `stat` output". [E] https://github.com/anthropics/claude-code/issues/40783. Worse than the error: a naive hasher that `open()`s and gets 0 bytes records the *empty* hash in the L2 manifest, and the file is then "unchanged" forever (silent). [T]
- Also: a full grep/hash pass over a synced library is a mass-hydration request against a 300k-item guidance ceiling ("we recommend syncing no more than a total of 300,000 items") and hundreds of GB of laptop disk, and macOS evicts under disk pressure, turning hydrated files dataless again between runs. [E] https://support.microsoft.com/en-us/office/restrictions-and-limitations-in-onedrive-and-sharepoint-64883a5d-228e-48f5-b3d2-eb39e07630fa
- Design change: L1 must never hash a file whose `st_blocks == 0`; classify it `placeholder` in the manifest and either request hydration through coordinated access or fall back to Graph `/content` for that item. The watcher observes metadata; only the acquisition step may claim content. Treat "hydrate everything" as a budgeted job, not an implicit side effect of `find`.

### 2. SharePoint rewrites uploaded Office/PDF/HTML bytes, so local hash ≠ server hash (sev: high · likelihood: certain on SharePoint sites)
- Trigger: any file placed in a SharePoint library (not plain OneDrive). Issue #935: "the file size reported by MS Graph doesn't match the original file size" for "PDFs, MS Office Documents, HTML files (Text files do NOT exhibit this behavior)... Standard OneDrive Business accounts do not exhibit this behavior". [E] https://github.com/OneDrive/onedrive-api-docs/issues/935. abraunegg's client was "100% re-written... to negate the impacts where SharePoint will *modify* your file post upload, breaking file integrity as the file you have locally, is not the file that is stored online." [E] https://github.com/abraunegg/onedrive/blob/master/docs/sharepoint-libraries.md
- Symptom: L2's "content-addressed" identity flaps. A drag-and-drop copy and the same file fetched via Graph hash differently; a dedupe across sources (Teams attachment vs SharePoint copy) fails; a converted page is redone on every round trip.
- Design change: content-address per *source channel*, never across; identity key = `(driveId, itemId)`; change key = `file.hashes.quickXorHash` from the same channel. Do not compare a drag-and-drop inbox hash against a Graph hash.

### 3. Delta omits cTag on OneDrive for Business, and eTag moves on metadata-only edits (sev: high · likelihood: certain)
- Trigger: L2 keys change detection on `eTag`/`lastModifiedDateTime` (default SDK fields) instead of content hash. Graph: "cTag — An eTag for the content of the item. This eTag isn't changed if only the metadata is changed" while "eTag — eTag for the entire item (metadata + content)". [E] https://learn.microsoft.com/en-us/graph/api/resources/driveitem?view=graph-rest-1.0. But the delta reference says for OneDrive for Business "Create/Modify — Properties omitted by delta query: `ctag`"; the scan guidance's advice "you can use the cTag property to determine if the contents of the file have changed" is therefore unusable straight off the delta feed on ODB. [E] https://learn.microsoft.com/en-us/graph/api/driveitem-delta?view=graph-rest-1.0 · https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/scan-guidance
- Symptom: sensitivity-label assignment, retention label, rename, a comment, a view — each re-downloads and re-converts the file; on a 100k-file library a tenant-wide label rollout is a full re-pull. [T]
- Design change: change key = `file.hashes.quickXorHash` ("the only value that is guaranteed to be available for both OneDrive for work or school and OneDrive for home" [E] https://learn.microsoft.com/en-us/graph/api/resources/hashes?view=graph-rest-1.0) + `size`; treat eTag/mtime as advisory only. `$select` it explicitly in the deltaLink.

### 4. Both "since tokens" die, and after resync deletes are never synthesized (sev: high · likelihood: high over months)
- Trigger (Graph): "if a client tries to reuse an old token after being disconnected for a long time, or if server state has changed... the service returns an `HTTP 410 Gone`... and a `Location` header containing a new nextLink that starts a fresh delta enumeration from scratch. After finishing the full enumeration, compare the returned items with your local state." [E] driveitem-delta (above). Trigger (watchman): "A fresh instance result set will only include files that currently exist" when the clock "was produced by a different watchman process" — i.e. after any daemon restart/reboot. [E] https://facebook.github.io/watchman/docs/file-query.html
- Symptom: full re-enumeration cost (2 RU per page without token vs 1 with) is the visible part. The silent part: neither mechanism reports deletions across the gap. A pipeline that "applies the change set" after resync never removes pages for files deleted during the outage — the agent keeps reading them.
- Design change: L2 must implement "manifest minus enumeration = tombstones" as a first-class operation, run on every 410 and every `is_fresh_instance:true`. Store the deltaLink in git alongside the manifest so a restored checkout resumes from a known cursor.

### 5. Throttling budget makes the initial crawl hours-to-days, and self-inflicted retries make it worse (sev: high · likelihood: certain at 10^5 files)
- Numbers: per app per tenant "1 min · 0–1,000 licences · 1,250" resource units, "24 H · 1,200,000"; delta with token = 1 RU, download = 1 RU, list children = 2 RU, permissions = 5 RU; delegated per-user "Requests · 5 min · 3,000", "Egress · 1 H · 100 GB". "Throttled requests count towards usage limits, so failure to honor `Retry-After` may result in more throttling." "SharePoint Online does not return or support `IETF RateLimit` headers." [E] https://learn.microsoft.com/en-us/sharepoint/dev/general-development/how-to-avoid-getting-throttled-or-blocked-in-sharepoint-online
- Arithmetic [T]: 100k files = 100k downloads ≥ 80 min at the 1,250/min ceiling even with perfect pacing; add `$expand=permissions` and it is 5×. Delegated auth caps at ~600 req/min per user regardless. Running the OneDrive sync client on the same laptop at the same time is explicitly named as a throttling cause ("Running the OneDrive Sync client while also running migration applications or applications that crawl sites... may trigger throttling"). Steady state is cheap: a token-bearing delta poll is 1 RU, so polling every minute costs 1,440 RU/day of 1.2M.
- Design change: single-flight global pause on 429/503 (scan guidance: "pause all further requests... especially important in multi-threaded scenarios"), decorate `User-Agent: NONISV|Company|App/1.0`, crawl off-peak, one AppID ("Don't create separate AppIDs"), and downloads gated by hash-changed only.

### 6. Encrypted (IRM/sensitivity-label) files convert to empty or garbage pages with no error (sev: high · likelihood: high in any regulated tenant)
- Trigger: label with encryption. "the Graph API will still return the file normally... The difference is that the file you receive will still be encrypted". [E] https://learn.microsoft.com/en-us/answers/questions/5626392/will-microsoft-graph-driveitem-apis-return-files-n. `extractSensitivityLabels` cannot open DKE-protected files. [E] https://learn.microsoft.com/en-us/graph/api/driveitem-extractsensitivitylabels?view=graph-rest-1.0
- Symptom: delta lists a normal `.docx`; L3 runs markitdown/pandoc on an RMS container; output is empty text or a zip-listing; the page exists, has provenance frontmatter, and says nothing — the agent concludes "the contract has no clause X". The no-API path is identical: the synced bytes are the encrypted bytes.
- Design change: L3 classifies before converting (RMS `EncryptedPackage` OLE stream / `.pfile` / label metadata); emits a stub page whose body is exactly `UNREADABLE: encrypted by sensitivity label <name>` so grep finds a refusal, not silence. Never let an empty conversion commit.

### 7. Compliance: the docs/ mirror is a data-exfiltration channel and DLP will eventually block or audit it (sev: critical · likelihood: medium, tenant-dependent)
- Trigger: git pushes a markdown mirror of labeled content to a repo host; Endpoint DLP "Accessed by unallowed apps" prevents listed apps from reading protected files; on macOS only the explicit restricted-apps list is supported. Conditional Access App Control "Block download" and unmanaged-device policies stop the sync client path outright. [E] https://learn.microsoft.com/en-us/purview/endpoint-dlp-learn-about · https://learn.microsoft.com/en-us/purview/sensitivity-labels-sharepoint-onedrive-files
- Symptom: silent partial coverage (blocked reads look like absent files) or a compliance incident with the operator's name on it. Plaintext markdown strips the label that the source carried.
- Design change: docs/ inherits the *highest* label of its sources into frontmatter and a repo-level policy; exclusion list by label is a hard gate in L1; repo remote must be tenant-owned (GitHub EMU / Azure DevOps) or none. This is a dimension the hypothesis does not have.

### 8. Permission divergence: the mirror is one principal's view, and lost access looks like nothing happened (sev: high · likelihood: certain with delegated auth)
- Trigger: delegated delta "restricted to content that the current user has access to" [E] scan-guidance. Items shared into a user's OneDrive are `remoteItem` links; rclone's warning "the delta listing API **only** works at the root of the drive" [E] https://rclone.org/onedrive/ — shared folders from other drives are not enumerated by `/me/drive/root/delta`. Removing the caller's permission does not by default surface as `deleted`; Microsoft's own scanning headers (`deltashowremovedasdeleted, deltatraversepermissiongaps`) exist because of this and require `Sites.FullControl.All`. [E] driveitem-delta
- Symptom: colleague A's docs/ ≠ colleague B's; a page persists after the team lost access; a client-shared folder silently never enters the mirror.
- Design change: one deltaLink per *drive* (site document libraries by `/sites/{id}/drives`), never per user; app-only where IT allows; where delegated, send the removed-as-deleted headers and record the principal in the manifest so two people's mirrors are never merged.

### 9. Giant Excel and long PDFs break the 1:1 mirror premise (sev: medium · likelihood: certain)
- Numbers: openpyxl normal mode "approximately 50 times the original file size, for example 2.5 GB for a 50 MB Excel file" [E] https://openpyxl.readthedocs.io/en/stable/performance.html. A 1M-row sheet as a markdown table is ~100–300 MB and ~50–100M tokens; a 500-page PDF is ~300k+ tokens. [T]
- Symptom: converter OOM on the laptop; or a page the agent can `grep` but never `Read`; L4's dependency map points at a single unreadable blob.
- Design change: L3 is 1:N, not 1:1 — per-sheet files, row cap with a sidecar CSV, a schema+sample summary page, PDFs split at the outline with a TOC page; frontmatter carries `tokens_estimate` so the agent chooses grep over read. Streaming readers only (`read_only=True`).

### 10. Converter nondeterminism turns L5's git diff into noise (sev: medium · likelihood: high)
- Evidence of position-dependent output: markitdown "OCR text is matched to images by position", placeholder-prefix collision drops blocks at ≥11 images. [E] https://github.com/microsoft/markitdown/issues/2383. Any LLM-captioning or OCR stage is nondeterministic by construction; PDF layout engines reorder columns between versions. [T]
- Symptom: `git diff` shows churn on unchanged sources; L4 re-curates no-ops; a real change hides inside 400 lines of reflowed noise; git history stops answering "what changed since I last looked".
- Design change: converter contract = idempotent, version-pinned (`converter: markitdown@x.y.z` in frontmatter), image assets named by content hash, output canonicalised (whitespace, table alignment) before commit; a CI check converts a fixture twice and refuses any converter whose output differs. Re-convert only when source hash or converter version changes.

### 11. Checked-out / autosaved / pending files: the mirror captures a transient (sev: medium · likelihood: high)
- Checkout "prevent[s] your changes from being visible until the document is checked in" [E] https://learn.microsoft.com/en-us/graph/api/driveitem-checkout?view=graph-rest-1.0; the `publication` facet "isn't returned by default". `pendingOperations` "indicates that one or more operations that might affect the state of the driveItem are pending". [E] driveitem resource. Office autosave produces a version every few seconds and "The delta feed shows the latest state for each item, not each change." [E] driveitem-delta
- Symptom: L3 converts mid-edit states; a week of delta polls yields 200 conversions of one deck; a stale checked-in copy is mirrored while the author's draft is the truth.
- Design change: quiescence gate — convert only when `lastModifiedDateTime` is older than N minutes and `pendingOperations` is absent; `$select=publication` and record `level`.

### 12. Time is not a change signal: second precision, client-claimed mtimes, sync-time overwrites (sev: medium · likelihood: certain)
- rclone: "Modification times differ by -143.88454ms" caused endless re-uploads because OneDrive stores seconds [E] https://github.com/rclone/rclone/issues/8090; `fileSystemInfo` is "File system information on client. Read-write." (client-asserted) vs server `lastModifiedDateTime`; OneSync-class tools stamp local mtime with sync time. [E] https://github.com/madeyouclickstudio/OneSync/issues/3
- Design change: mtime never decides; store both timestamps as UTC ISO-8601 with their provenance (`server`/`client`) in frontmatter; timezone-naive strings are a bug.

### 13. Unicode normalization and path length split one file into two (sev: medium · likelihood: high for non-ASCII names)
- macOS keeps two copies under `~/Library/CloudStorage/...` and `~/Library/Group Containers/...` with `Årsoversigt.PDF` vs a differently-normalized twin [E] https://learn.microsoft.com/en-us/answers/questions/5154133/onedrive-on-mac-is-keeping-two-copies-of-all-downl; SharePoint path ≤ 400 decoded chars and local root + relative ≤ 520. [E] https://learn.microsoft.com/en-us/answers/questions/5198400/maxpath-limits-in-sharepoint-url
- Symptom: watcher path bytes ≠ Graph `name` bytes → create+delete pairs each run; semantic renames in docs/ overflow Windows colleagues' 260-char git checkouts.
- Design change: NFC-normalize for identity, keep raw bytes in provenance, `git config core.precomposeunicode true`; docs/ paths are short slugs with the original name in frontmatter.

### 14. Concurrency: the agent reads mid-write (sev: medium · likelihood: high)
- Trigger: the sync job rewrites `docs/x.md` while Claude greps; the OneDrive client drops `~$` lock files and `.tmp` into docs-source. [E] restrictions page (`~$` names, TMP not synced)
- Design change: write temp + atomic rename; the agent reads only a committed ref (`docs/` = a worktree checked out at tag `published`), and a `docs/_sync/STATE.md` stamp (deltaLink time, last success, item counts) is the first thing CLAUDE.md tells the agent to read.

### 15. Curated layer drift with no mechanical staleness signal (sev: high · likelihood: certain)
- The hypothesis says "agent-driven incremental curation guided by a page↔source dependency map". Nothing in that sentence fails loudly: when a source hash changes and the agent's re-curation is skipped, deferred, or wrong, the curated page still carries a confident date. [T]
- Design change: a deterministic linter, not the agent, prepends `> STALE: source <path> changed <date>, page not re-curated` to any page whose `sources:` hashes no longer match the manifest — staleness must be the first grep hit, written by code.

### 16. Duplicates and conflict copies (sev: low-medium · likelihood: certain)
- OneDrive "creates a duplicate file and appends your computer's network name" on conflicts [E] https://learn.microsoft.com/en-us/answers/questions/5655076/duplicate-onedrive-folders-appearing-with-my-devic; humans upload `_v3_FINAL`. Same bytes surface via Teams, mail attachment, and SharePoint.
- Design change: stem-clustering + "canonical = latest server-modified per stem" pointer page; cross-source dedupe by hash *within* a channel (see #2).

### 17. Webhooks are unavailable on a laptop; subscriptions are root-only and payload-free (sev: low · likelihood: certain)
- "On OneDrive for Business, you can subscribe to only the root folder"; notifications carry no driveItem data; endpoint must answer validation over public HTTPS. [E] https://learn.microsoft.com/en-us/graph/api/subscription-post-subscriptions?view=graph-rest-1.0
- Design change: accept polling; a token-bearing delta poll is 1 RU, so a 60 s cadence is affordable (#5). Do not build the webhook leg for the laptop case.

## Three dimensions the hypothesis does not mention
1. **Entitlement/compliance as data.** Labels, DLP, IRM, retention and per-principal ACLs are properties of the source that the mirror must carry or refuse; a git repo flattens all of them (#6, #7, #8).
2. **The source mutates and hides bytes on its own.** SharePoint enrichment, versions/autosave, checkout, encryption, malware quarantine — "content-addressed" presumes a byte-stable, readable origin; none of these are (#2, #6, #11).
3. **The local filesystem is a cache with a network behind it.** Dataless placeholders, eviction, EDEADLK, NFD names, `~$` locks — the no-API path is not POSIX, and the watcher observes metadata only (#1, #13, #14).

## Key questions
- **Breaks first at scale:** no-API path — the very first hash pass over `~/Library/CloudStorage` (placeholders, #1). API path — the initial crawl hits the 1,250 RU/min ceiling within the first minute and the 100 GB/h delegated egress within the first hour of a hundreds-of-GB pull (#5).
- **Silently wrong docs:** encrypted bytes converted to empty pages (#6); deletes never synthesized after 410/fresh-instance (#4); 0-byte placeholder hashed as "unchanged" (#1); permission loss leaving pages behind (#8); mid-edit/checked-out captures (#11); converter noise masking real diffs (#10).
- **What makes the agent trust stale content:** a page with confident frontmatter and no mechanical STALE banner (#15); no sync-state stamp to read first (#14); git history that "looks committed" while the cursor died weeks ago (#4).

## Alternatives considered, ruled out
- Symlinking docs-source → `~/Library/CloudStorage`: rejected — it inherits #1 wholesale and gives no change feed (File Provider does not expose a since-cursor to third parties).
- Graph Data Connect / SharePoint Premium indexers: rejected for this operator — tenant-admin provisioning, batch cadence, and IT restriction on app registrations is the stated constraint.
- mtime/size-only change detection (rsync-style): rejected by #2, #3, #12.
- Whole-repo Copilot/Search connectors: out of scope — the deliverable is grep-able markdown in the agent's cwd.

## Uncertainties named
- Exact ODB driveItem subscription max lifetime not re-verified this pass (irrelevant given #17).
- Whether `NSFileCoordinator`-wrapped reads from a Python/Node process reliably hydrate on current macOS is inferred from the claude-code issue's proposed fix, not measured.
- SharePoint enrichment (#2) is user-reported (issue #935 + abraunegg); Microsoft has not documented which transforms it applies.
- Endpoint DLP on macOS: restricted-apps *list* enforcement is documented; whether `git`/`node` are blockable targets in practice depends on tenant policy.

## Adversarial self-pass (integrated)
- Objection "delta gives hashes so #2 is moot": only within Graph; the design's inbox path (drag-and-drop) hashes local bytes, which differ from server bytes for Office/PDF on SharePoint sites — the cross-channel comparison is exactly what fails.
- Objection "polling is too expensive": refuted by RU table — 1 RU per token-bearing delta call.
- Objection "#1 is a Cowork-bridge bug, not a general one": the `Blocks: 0` mechanism is File Provider's, and Microsoft's own doc makes online-only the default for new files; any uncoordinated reader is exposed.
- Objection "#15 is unfalsifiable": it is — that is the finding; the design has no arm that can go red on curation drift, so one must be added.
