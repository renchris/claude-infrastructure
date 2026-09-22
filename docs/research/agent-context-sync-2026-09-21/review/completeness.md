# Completeness review — `agent-context-sync-2026-09-21.md`

Lens: WHAT IS MISSING. Read-only pass over all 481 lines plus the 14 axis reports and `verify/C1..C10`.
Checks are greps over the document and its receipts (`grep-matrix.txt` in this directory holds the
term-by-term counts, main doc vs axis reports).

## Part 1 — are the four asked questions answered explicitly, and where

All four are answered, and each has a sentence you can point at. This part is not a finding; it is the
baseline the findings below are measured against.

| ask | answered | the sentence |
|---|---|---|
| (a) is symlinking reliable for always-on awareness of created/updated/deleted | §3, and in line 7 of the summary | *"A symlink is **access**, and even that is unreliable; it is never **change awareness**, because it carries no since-token."* — with the per-tool table at §3 (Glob/Grep, rg, BSD grep, find, zsh, git, Watchman, FSEvents) and the `find <link>` → zero rows measurement |
| (b) how to identify the diff instead of re-pulling tens-to-hundreds of GB, incl. same-name updates | §"The answer in one screen" items 1–3, invariant 3, §5 first paragraph | *"**Phase 1 reads zero file bytes.** Provider hash (`quickXorHash`) first, stat tuple second, content only on mismatch"*; and for same-name: *"**In-place overwrite (same name, new bytes):** keeps the driveItem id; eTag and cTag both change; `quickXorHash` changes … Detected in phase 1 with zero download by `provider_hash`."* |
| (c) golden examples (Cursor/TurboPuffer, Cognition DeepWiki) for updating only against the diff | §2, 12-row table | *"Cursor does two-level content addressing — per-file/dir SHA-256 Merkle tree polled every 10 minutes for the **what**, and an embedding cache keyed on chunk content hash for the **cost**"*; *"DeepWiki regenerates a whole wiki as one unit on a human button; 12 of 12 public wikis measured stale (median ~1 month)."* |
| (d) the 100th-percentile architecture for auto-pointed or hand-dropped sources, token- and operationally-efficient | §4 (L0–L6 diagram + 4.1–4.7); hand-dropped is *"**Arm C — manual drag-and-drop inbox**"*; token efficiency is §4.6 | the L0–L6 block, the seven invariants, and §4.6's page/index budgets |

One sub-question of (a)+(d) is **not** answered — "always-on" for the local/hand-dropped arm has no
cadence number and no latency claim scoped to it. That is finding 6.

## Part 2 — findings, ranked by how much a reader would miss them

### 1 · CRITICAL — nothing detects the puller dying; the design's own failure table has no row for it

§6 ranks 20 failure modes and every one is a *content* fault. The mode that kills "always synced" in
practice — the launchd job stops firing, the token is never refreshed, the process is SIGKILLed, the
laptop was asleep for nine days — has no row, no closer, and no emitter. `_sync/STATE.md` cannot report
it: the dying process is STATE.md's only writer, so its last successful line stays on disk looking
healthy (this repo's `fail-safe-default-mimics-the-healthy-state` and `liveness-proxy-cannot-be-output-age`
lessons). "alert"/"alerting"/"heartbeat"/"liveness" appear **0 times** in the document; "alarm" appears
twice, both as the *word* inside a classifier branch (400 malformed token; breaker trip) with no channel.
Add to §4.7, as its own bullet:

> - **Liveness is a separate, outward signal, and it is not STATE.md.** STATE.md is written by the puller,
>   so it cannot report the puller's death — it will read healthy forever at the moment of the last
>   success. Emit a heartbeat per source to a store outside `docs/` on every completed pass
>   (`last_success_at`, `run_id`, `pass_complete`), and run a **separate** watcher, not the puller, that
>   pages when any of: cursor age > 3 × that source's cadence; `pass_complete=false` for K consecutive
>   runs; the breaker armed > 24 h; the last `docs/` commit older than the daily-reconcile interval.
>   Judge freshness against the **subject** (last source change seen) and not the wall clock, or a quiet
>   weekend reads as an outage and a busy Monday hides a two-week freeze. The page goes to a channel a
>   human actually reads; a line in launchd's stderr is silence.

And a row in §6:

> | 21 | Puller stops (launchd unloaded, token dead, machine asleep, crash): `docs/` still present, every page still confidently dated, STATE.md frozen at its last success | heartbeat to a store outside `docs/`; external watcher on cursor age / pass_complete streak / commit age; `git log -1 --format=%cI docs/` in the agent's own freshness check |

### 2 · CRITICAL — the "Discover" stage of the loop the doc says it takes verbatim is not in the architecture, and there is no source registry

§2 credits Microsoft's scan guidance as *"Discover → Crawl → Notify → Process changes"* with transfer
*"The whole L1 loop, verbatim."* §4.2 implements Crawl, Notify and Process and **drops Discover**. There
is no answer to: which drives/libraries/folders are in scope, where that list lives, who edits it, how a
new one is added, or how the set is enumerated (`/sites?search=`, `/sites/{id}/drives`,
`/me/drive/sharedWithMe`). `sharedWithMe` and `remoteItem` appear **0 times** in the document — yet I1
§8 records that a folder shared into the user's OneDrive is a `remoteItem` and is **not enumerated by
root delta**, so an entire client-shared library can be in scope, look configured, and silently never
enter the mirror. "onboard" appears 0 times. Add as §4.2 arm-0, before Arm A:

> **Arm 0 — Discover (the stage Microsoft's loop starts with).** The in-scope set lives in one tracked
> file, `docs/_sync/sources.toml`: `[[source]] id, kind (graph_drive|graph_mail|graph_channel|
> fileprovider|manual), drive_id|folder_id, subtree, cadence_seconds, principal, initial_crawl_budget_gb,
> state (live|paused|retired)`. Nothing else in the pipeline may name a cloud location. Discovery is a
> command, not a background behaviour: enumerate `/sites?search=`, `/sites/{id}/drives`,
> `/me/drives`, and **`/me/drive/sharedWithMe`** (a folder shared in is a `remoteItem` and is invisible
> to root delta — it needs its own cursor against its *owning* drive), diff against `sources.toml`, and
> print the additions for a human to accept. Onboarding a source is then: append the row `state=paused`
> → bootstrap with `?token=latest` if history is not wanted, else a budgeted initial crawl off-peak
> (egress-bound at 100 GB/h delegated) → first complete pass sets `state=live`. A bootstrap emits
> thousands of CREATEs, so it publishes as its **own** commit, labelled, never mixed into a sync cycle,
> and the deletion breaker is disarmed for that source's first complete pass only.

### 3 · MAJOR — `STATE.md` is "what the agent reads first" with no rule for anything it might say

`pass_complete` appears four times, all producer-side: L2 arms the breaker with it, §4.7 sets it false on
a budget exhaustion, §6 row 5 cites it. Nowhere does the document say what the **consuming agent** does
when it reads `pass_complete=false`, a cursor 11 days old, a tripped breaker, or 40 quarantined rows.
That is the one surface where the entire freshness apparatus reaches the reader, and it is left as
"reads this FIRST". Without a read-side rule the honest machinery produces the exact failure it was built
to stop: the agent answers *"there is no such clause"* from a corpus it has been told is incomplete
(this repo's `zero-claim-must-name-its-excluded-strata`, and `empty-vs-no-surface`: absence and
"the surface never arrived" demand opposite actions). Add to §4.6, and put the same five lines in
`docs/topics/CLAUDE.md` so they are resident exactly when it matters:

> **The read-side contract (`docs/_sync/STATE.md`).** Every condition has one required behaviour:
> - `pass_complete=false` on any source → the corpus has holes. A negative answer must say
>   *"not found in docs/, and source X was incomplete at <run>"*. Never report a bare "nothing found".
> - cursor age > 3 × cadence, or breaker armed → deletions and tombstones are unreliable; do not assert
>   that a document is gone, and do not act on a tombstone.
> - `quarantined > 0` → name the count and point at `_sync/QUARANTINE.tsv`; those sources are
>   unreadable, not absent.
> - a page carrying the `⚠ STALE` banner → cite it as *as of* its pinned sha, never as current.
> - STATE.md itself missing or older than the daily reconcile → treat the whole of `docs/` as
>   provenance-unknown and say so in the first line of the answer.

### 4 · MAJOR — no way to retire a source, and the 20 % breaker makes a legitimate descope undeliverable

"retire" appears twice, both about Sourcegraph/Cody retiring an embeddings layer. Invariant 6 plus §6
row 5 mean that a library legitimately removed from scope — project ended, access handed back, a site
archived — presents exactly as catastrophic data loss: every row misses `last_seen_run`, candidates blow
past 20 %, the breaker suspends removals for 7 days and alarms, and then either it mass-deletes anyway or
the subtree lives forever under a standing alarm. Both outcomes are wrong, and the design has no verb
for the operator's assertion that this deletion is intended. Failure 14 has the same hole from the other
side: it prescribes *"access loss is a quarantine, not a tombstone"* without the discriminator that
separates lost access from real deletion — on delegated auth those are the same silence, and the header
pair that annotates them (`Prefer: deltashowremovedasdeleted, deltatraversepermissiongaps`, recorded in
B1/C4/F) needs `Sites.FullControl.All` and appears **0 times** in the document. Add to §4.7:

> - **Retirement is an explicit verb, not an absence.** `sources.toml` state `retired` (with
>   `retired_at`, `reason`) is the operator asserting that this subtree's disappearance is intended: the
>   mirror subtree is tombstoned in one labelled commit **exempt from the 20 % breaker** (the breaker
>   exists to catch an *unasserted* mass deletion), the cursor is dropped, and curated pages citing it
>   get a `SOURCE RETIRED — see <reason>` banner rather than `STALE`, because no re-curation will ever
>   clear it. Losing *access* is the different case and stays `quarantined`: with delegated auth a
>   permission gap and a real delete are the same silence, so record which one you can distinguish —
>   `Prefer: deltashowremovedasdeleted, deltatraversepermissiongaps` annotates them but needs
>   `Sites.FullControl.All`; without it, any source whose candidate set exceeds the breaker is
>   `access-unknown` until a human rules, never a tombstone.

### 5 · MAJOR — the M365 source inventory stops at four types; the classifier itself names a fifth it never handles

L0 lists OneDrive · SharePoint · Outlook · Teams · manual drop, and the L5 tree has exactly
`sharepoint/ onedrive/ email/ teams/`. Grepped against the document: **Planner 0, Forms 0, Whiteboard 0,
Viva 0, Copilot 0, shared mailbox 0, hostedContents 0, OneNote 2, Loop 0** (the two "Loop" hits are
"does not loop"; "zip" appears once, about OOXML container metadata). The gap is not hypothetical —
§4.3's own classifier says *"OneNote items (application/msonenote, application/octet-stream, package
facet) … carry no hash"*, so OneNote is admitted as a population inside the change classifier while
having no acquisition arm, no converter row, and no mirror directory. Five of these are structurally
different from a file, not merely unlisted: a OneNote section has **no delta endpoint** at all, a
`.loop`/`.fluid` file's bytes are an opaque Fluid container that no converter reads, a shared mailbox is
`/users/{upn}/mailFolders/…/delta` with `Mail.Read.Shared` rather than `/me/…`, an image pasted into a
Teams message is a `hostedContents` reference that is not fetchable from the message HTML, and an
attachment can itself be a `.msg` or a `.zip`. Add a table at the end of §4.2 and one refusal rule:

> **Source types and their arm.** A type absent from this table is a `refused` row in the manifest with
> a stub page — never a silent zero.
>
> | type | arm | note |
> |---|---|---|
> | OneDrive / SharePoint files | A (delta) / B | the covered case |
> | Outlook mail, own mailbox | A (`/me/mailFolders/{id}/messages/delta`) | per-folder cursor |
> | Outlook mail, **shared mailbox** | A, `/users/{upn}/mailFolders/{id}/messages/delta` + `Mail.Read.Shared` | separate `principal`; delegated-access-dependent |
> | attachments | A, two-phase after the message diff | recurse one level into `.msg`/`.eml`; expand `.zip` to members with the archive as parent; attachment ids are not stable across a move — key on `(internetMessageId, name, size, sha256)` |
> | Teams channel messages | A (`ChannelMessage.Read.All`) | project-local emitter |
> | Teams inline images / files | A, `hostedContents/{id}/$value` (images) or the channel's SharePoint library (files) | the message HTML URL is not fetchable; images are not in the library |
> | meeting transcripts | A, the `.vtt` in the organiser's OneDrive `Recordings/` folder — prefer it; `/onlineMeetings/{id}/transcripts` is app-only + protected-API | record where the VTT came from; never ASR the mp4 |
> | **OneNote** | A, `/onenote/pages?$select=lastModifiedDateTime` polled per section — **there is no delta for OneNote**, so its arm is reconcile-only and its cursor is a high-water timestamp | HTML body via `/pages/{id}/content`; the driveItem package carries no hash, so the package is not the unit |
> | **Loop / `.fluid`** | none | bytes are an opaque Fluid container; `refused: no converter`, stub page, one row |
> | Planner · Forms · Whiteboard · Viva Engage · Copilot notebooks | none in phase 1 | each is a different Graph resource with its own (or no) change feed; `refused: out of scope`, stated once so the absence is visible |

### 6 · MAJOR — no cost / latency / token table; the one SLA sentence describes only arm A, and arm B's cadence is the literal letter N

The user's ask names token- and operational-efficiency, and the numbers exist — scattered across §4.2
(1 RU, 1,440 RU/day, 0.12 %, 100 GB/h), §4.4 (5.5 p/s, 1.3 p/s, *"a backfill measured in days"*), §4.6
(25 KB ≈ 6 K tokens), invariant 3 (31 MB manifest, 0.12 s load, 0.051 s compare) — but nothing adds them
up, and the **token** side is never costed at all: there is no figure for what one agent question against
`docs/` costs, which is the half of the ask that motivates the whole mirror. Two specific holes: §4.7
publishes *"typically under a minute, guaranteed within 6 hours, plus a daily reconcile"*, which is arm
A's webhook-plus-poll profile and is false for a laptop running arm B, where the same section says
*"launchd every N min"* and **N is never chosen anywhere in the document**; and the receipts disagree
with each other on the hash number nobody quotes (`D-manifest-buildgraph.md` 2,384 MB/s → 100 GB ≈ 42 s;
`I2-red-team-symlink-hash.md` 290 MB/s → ≈ 6 min), an 8× spread that only a table would have caught.
Add as §4.8:

> ### 4.8 Budget, latency and the token bill
>
> | quantity | arm A (Graph) | arm B/C (local) | source |
> |---|---|---|---|
> | change-detect latency, steady state | poll 60 s (1 RU) ⇒ ≤ 60 s | **T3 walk every 15 min** + at session start ⇒ ≤ 15 min | §4.2 / this decision |
> | worst case before the daily reconcile | 6 h (webhook max, if webhooks are used at all) | 24 h | §4.2 |
> | cost per steady-state cycle | 1 RU per drive; 1,440 RU/day = 0.12 % of the smallest per-app budget | one `getattrlistbulk` walk, 0 file opens, 0 downloads — **wall-clock unmeasured, §9 probe 5** | §4.2 / §9 |
> | manifest bookkeeping at 200 k rows | 31 MB, 0.12 s load, 0.051 s stat-compare | same | invariant 3 |
> | initial crawl | egress-bound: 100 GB/h per delegated user ⇒ 100 GB ≈ 1 h floor, off-peak, resumable | hydration-bound; pin in-scope subtrees instead | §4.2 |
> | scanned-PDF backfill | 1.3 p/s (Docling, batch 1) ⇒ days on one laptop; born-digital 5.5 p/s | same | §4.4 |
> | **agent tokens per question** | `INDEX.md` ≤ 6 K + `STATE.md` ≤ 0.5 K + 1–3 pages ≤ 6 K each ⇒ **≈ 8–25 K resident per answer**, no tool call into a binary | same | §4.6 budgets |
> | agent tokens per sync, on the lead | 0 — the sync and any broad mirror search run in a subagent; only the summary returns | same | §4.6 |
>
> The per-arm split matters for what is published: *"typically under a minute"* is arm A only. A laptop
> on arm B publishes *"typically under 15 minutes, guaranteed within 24 hours"*, and STATE.md states
> which arm each source is on.

### 7 · MAJOR — where `docs/` lives is never decided, and the "reads a committed ref" rule has no mechanism

The word "repo" appears 39 times and never resolves: is `docs/` its own repository, a directory in an
existing one, what its remote is (§4.7 offers *"tenant-owned or absent"*, and "absent" silently withdraws
the git-based recovery that §4.6's tombstones and invariant 7 rest on), and — the trap nobody states —
whether `docs/` may sit **inside** the sync root, which would put the git objects themselves behind File
Provider and re-import every §3 failure into the derived layer. §4.7 also asserts *"the agent reads a
committed ref, never a mid-write tree"* while L5 describes one directory that both the writer and the
agent use; no mechanism bridges that, and "worktree" appears 0 times (I1 §14 proposed exactly one). Add
to §4.7:

> - **Hosting, decided.** `docs/` is its own git repository on local disk, **outside** any
>   `~/Library/CloudStorage` or `~/OneDrive` path — a git dir inside a File Provider tree inherits every
>   §3 failure into the derived layer. Its remote is tenant-owned (GitHub EMU / Azure DevOps) or there is
>   none; with no remote, the repo is the only copy, so a local encrypted backup is mandatory and
>   invariant 7's recovery claims are scoped to it. The writer commits in the repo; **the agent reads a
>   separate worktree checked out at the `published` tag**, advanced once per cycle after the commit —
>   that is what makes "never a mid-write tree" mechanical rather than aspirational, and it is what the
>   one lock protects.

### 8 · MAJOR — no security review beyond exfiltration; a secret inside a mirrored file lands in git history permanently

§6 row 20 and §4.7's compliance bullet cover labels, DLP and the remote's ownership. Four items with no
mention at all (`secret` 0, `keychain` 0, `gitignore` 0 hits): (i) corporate files contain credentials —
a connection string in an Excel cell, an API key in a Word appendix, a password in a `.msg` — and this
pipeline converts them to plaintext markdown and commits them, where git history keeps them after any
later fix; (ii) the Graph refresh token / device-code credential has no stated custody (Keychain vs a
dotfile) while the `deltaLink` cursor is not a secret and can be tracked; (iii) offboarding — what
happens to `docs/` when the operator's tenant access is revoked; (iv) the mirror's own log and
`CHANGELOG.md` quote file names and `modified_by` addresses. Add a §4.7 bullet:

> - **Secrets are content here, and git is permanent.** Run a secret scanner (gitleaks/trufflehog) over
>   every generated page as a **land gate**, not a review step: a hit quarantines the page to an
>   `UNREADABLE: contains a credential` stub and files the source id, because once a key is committed,
>   removing it later does not remove it from history. Pipeline credentials live in the Keychain, never
>   beside the manifest; `deltaLink` cursors are not secrets and are tracked deliberately. On
>   offboarding, `docs/` is a full-fidelity plaintext copy of tenant data that survives revocation —
>   name its retention owner and its delete procedure in `docs/README.md`.

### 9 · MODERATE — greenfield assumption: no migration path for the hand-made `docs/` that already exists

"migration" appears 0 times, and §10's week 1 begins *"Real `docs-source/`"* with an empty `docs/`. The
operator's existing hand-written docs are not in any manifest, have no `sources:`, and the rules as
written give them two bad fates: dropped into `mirror/` where the next sync overwrites them
(`GENERATED — DO NOT EDIT`), or left loose where the STALE linter cannot judge them and `DEPENDS.tsv`
never mentions them. Add to §10 step 1:

> **Adopting an existing hand-made `docs/`.** Move every existing page into `topics/` — never into
> `mirror/`, which the next sync overwrites — and stamp each with `provenance: hand-written,
> adopted_at: <date>` and an empty `sources: []`. A page with no `sources:` is **exempt from the STALE
> linter and absent from `DEPENDS.tsv`** by design, which is the honest state: nothing mechanical can
> judge its freshness. Converting one is a deliberate act — add `sources:` with pinned
> `at_rendered_sha256` values, drop the `provenance` field, and it joins the refresh queue from then on.
> `docs/INDEX.md` groups adopted pages separately so the agent can see which half of the corpus has
> mechanical freshness and which does not.

### 10 · MODERATE — the design is macOS-only and never says so, and the Windows path limit its own receipt raised is dropped

Scope names *"Corporate macOS"*, and arm B is built entirely of macOS primitives (FSEvents,
`getattrlistbulk`, `ATTR_CMN_GEN_COUNT`, `SF_DATALESS`, `setiopolicy_np`). "Windows" appears **0 times**
in the document, so a reader cannot tell whether a Windows colleague, or a server-side deployment, is
out of scope or unconsidered — and `docs/` in git is by construction a shared artefact. I1 §13 named the
concrete consequence and it did not survive into the document: §4.7 carries SharePoint's 400/520-char
limits but not the **260-char `MAX_PATH` ceiling on a Windows git checkout**, which the deep semantic
slug paths of §4.6 will breach. Add to §7:

> **Portability, stated.** Arm B is macOS-only by construction (FSEvents, `getattrlistbulk`,
> `ATTR_CMN_GEN_COUNT`, `SF_DATALESS`). Arm A is the only portable arm: a Windows or server deployment
> runs arm A and, for a local tier, the equivalent primitives are the NTFS USN change journal and
> `FILE_ID_INFO` — unmeasured here, and a separate piece of work. `docs/` itself must stay portable
> because it is shared: keep every generated path under **200 characters** so a Windows colleague's
> checkout clears `MAX_PATH` (260), with the original name in frontmatter.

### 11 · MINOR — the `.xlsx` emitter's own memory cost is unbudgeted and contradicts "streaming readers only"

§4.4 specifies *"open twice (`data_only=True` for values, `False` for formulas), propagate merged-range
anchors"* and §4.6 says *"streaming readers only"*. openpyxl's `read_only=True` does not expose
`merged_cells`, so the specified emitter cannot be a streaming reader, and I1 §9's measurement —
openpyxl normal mode at *"approximately 50 times the original file size, for example 2.5 GB for a 50 MB
Excel file"* — makes two simultaneous non-streaming opens the single largest resident-memory event in
the pipeline, on a laptop. Nothing in §4.7's budgets covers converter memory. Add one clause to the
`.xlsx` row:

> …two non-streaming opens are required (`read_only=True` hides `merged_cells`), and openpyxl's normal
> mode costs ~50× the file size in RAM, so route any workbook above a size threshold (start at 20 MB) to
> a streaming path that emits a schema + sample page plus a CSV sidecar, and record it as
> `unit: summary`, not as a full conversion. Converter memory is a §4.7 budget like egress.
