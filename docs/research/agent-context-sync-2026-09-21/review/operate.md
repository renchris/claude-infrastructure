# Review — lens: the person who has to run this

Target: `docs/research/agent-context-sync-2026-09-21.md` (481 lines).
Fixtures: `./mm.sh` (two-machine git), `./win.sh` (filename portability + launchd interpreter),
`./depends.sh` (the document's verbatim refresh-queue loop). All under
`/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/2825e1e5-98df-4f46-bfe1-b2eb576e2e10/scratchpad/review/`.

What I did: walked §10 week 1 → week 3 as a build order, then re-read §4.2 (state machine),
§4.3 (classifier), §4.6 (tree), §4.7 (operations) as specifications an engineer must implement
without asking the author a question. 14 findings. The design's *change-detection* core holds;
everything that fails is at the seams where a second machine, a second person, a restart, a
clock, or a colleague's laptop enters — and §10 has no step for any of them.

---

## CRITICAL

### 1. The classifier deletes the whole corpus on the first incremental poll (§4.3, line 225)

`live rows with last_seen_run < run_id (and pass_complete) → DELETION CANDIDATE`

A delta poll returns **only changed items**, then a `@odata.deltaLink`. `pass_complete` is defined
twice in the document as "the deltaLink arrived / the listing was not truncated" (§4.2 line 131,
§6 row 5) — which is **true of every successful incremental poll**. So a poll that returns 3
changed items stamps 3 rows, and the other 49,997 have `last_seen_run < run_id` with
`pass_complete` true. They all become deletion candidates; 99.99 % > 20 %, so the breaker latches
for 7 days on the very first poll and stays latched. §4.1's field table hedges with "the current
*complete* run" in italics and never defines *complete*; nothing in the document distinguishes
"this pass saw every item" from "this pass finished".

**Fix — replace line 225 and line 226 with:**

```
# Absence-based deletion is legal ONLY after a pass that enumerated the whole scope.
# Two pass kinds, never one flag:
#   delta_pass       — incremental; deletes come ONLY from Graph's `deleted` facet / FSEvents
#                      Removed. NEVER from absence. last_seen_run is stamped but not compared.
#   full_enumeration — bootstrap crawl, 410 resync, daily reconcile, T3 walk. Sets
#                      enumeration_complete=true for (source_kind, drive_id) on success.
live rows in scope S with last_seen_run < run_id
   AND pass_kind == full_enumeration AND enumeration_complete[S]   → DELETION CANDIDATE
if candidates > max(20 % of live rows in S, 25)                    → BREAKER: suspend removals
                                                                     7 days, alarm, keep everything
# The denominator is PER SCOPE S = (source_kind, drive_id). A global denominator lets one
# unmounted OneDrive that is 15 % of the corpus be fully tombstoned under the breaker.
# The absolute floor (25) stops a 40-row pilot corpus from tripping on three real deletions.
```

And in §4.1 invariant 6, append: *"Absence is evidence of deletion only inside a pass that
enumerated the scope. An incremental pass may only delete on an explicit tombstone."*

### 2. No crash recovery, no lock specification, no durability ordering (§4.7 "One lock, one commit")

The whole operational contract is nine words: *"A machine-wide lock per `docs/` root; temp+rename
for every file."* An implementer cannot write that. Unanswered: what kind of lock; what happens to
a lock whose holder was SIGKILLed; what happens to a worktree holding 40 k written-but-uncommitted
mirror files when the process dies before the single commit; what SQLite journal mode; and in what
order the four durable stores (converter cache, manifest, git, cursor) must be written so that no
crash produces a state the next run misreads. §4.2 says *"never advance the cursor before the
change set is durably consumed"* without defining *consumed*, and §4.2's `S1` says *"persist the
PAGE cursor so a crash resumes"* — a second, differently-shaped crash story with no relation to the
first. `grep -ci 'flock\|stale lock\|WAL mode\|migration'` on the document: 0 for each.

**Fix — add to §4.7:**

```
- **Lock.** `flock(LOCK_EX|LOCK_NB)` on `<docs>/.sync.lock`, whose body is
  `<pid> <boot_time> <iso8601> <label>`. A lock whose pid is dead, or whose recorded boot_time
  differs from the current one, is stale: log it, break it, and force the next pass to
  full_enumeration (the previous run's scope is unknown). Never a bare pidfile — pids are
  reissued. One lock per docs/ root covers poll, reconcile and curation; see finding 11 for
  the two launchd labels that contend for it.
- **Durability order, one cycle. Each step is idempotent and re-runnable from the step before:**
  1. write converter outputs into `cache/<action_key>/` (write-once; a partial dir is `tmp-*`
     and renamed on completion, so a half-written key is never readable)
  2. SQLite (`PRAGMA journal_mode=WAL; synchronous=FULL`) rows updated in ONE transaction,
     carrying `run_id`, `pass_kind`, `enumeration_complete`, and the pending cursor as data
  3. materialise `docs/` from the manifest: temp+rename per file; then export the NDJSON shards
  4. `git add -A && git commit` (one commit) — this is "durably consumed"
  5. only now `UPDATE cursor SET delta_link=<pending>` in its own transaction
- **Recovery, run before acquiring any source.** If HEAD's tree ≠ the manifest's expected tree
  (compare the manifest's `tree_sha` column against `git rev-parse HEAD^{tree}`), the last cycle
  died between 3 and 4: `git reset --hard HEAD && git clean -fd docs/mirror docs/_sync` and replay
  from step 3 — every byte is reconstructible from the manifest plus the cache, which is why the
  cache must survive a reset (finding 3). If the cursor's `pending` differs from `delta_link`, the
  cycle died between 4 and 5: the commit is authoritative, adopt `pending`. NEVER resolve a dirty
  tree by committing it — that publishes a half-applied change set as a cycle.
```

### 3. `_manifest/cache/` is inside git, write-once, and never collected — the repo grows without bound (§4.6 tree, §4.1 invariant 5)

The tree puts `_manifest/cache/<key>/ (write-once converter outputs)` under `docs/`, which is the
git repo. `action_key` includes `canonical_hash`, so **every revision of every item mints a new
immutable directory that nothing ever deletes** — and its contents are byte-identical to what
`mirror/` already holds. At 50 k items that is a second full copy of the corpus on day one, plus
one more copy per edit, forever, inside git history where even deleting it later reclaims nothing.
`grep -c gitignore` on the document: **0**. Nothing else in §4.6 has a growth model either:
`figures/<sha>.png` is unbounded binaries with no size cap and no LFS decision; `CHANGELOG.md` is
one append-only file written every cycle; tombstones are reaped at 180 days from the worktree but
remain in history by construction.

**Fix — replace the `_manifest/` line in the §4.6 tree and add a growth bullet to §4.7:**

```
  _manifest/          index.jsonl shards ONLY (generated, committed — this is what makes the
                      manifest diffable).  The converter cache is NOT here and NOT in git:
                      it lives at $XDG_CACHE_HOME/docs-sync/cache/<action_key>/ (default
                      ~/Library/Caches/docs-sync/), is machine-local, and is fully rebuildable
                      from docs-source.  Land-gate lint: `git ls-files docs | grep -q '_manifest/cache/'`
                      must fail, and `docs/.gitignore` pins `_manifest/cache/`.
```

```
- **Growth budget, enforced at the land gate.** The cache is out of git (above) and garbage-collected
  by ninja's `cleandead` rule: after a successful full_enumeration, delete every `cache/<key>/`
  whose key appears in no live `output` row, plus a grace window of one converter version.
  `CHANGELOG.md` rotates monthly (`docs/CHANGELOG/<yyyy-mm>.md`, with `CHANGELOG.md` a generated
  index of the last 30 days) or a year of 5-minute cycles is a 100 k-section file nothing can read.
  `figures/` caps a single image at 2 MB and the directory at 2 GB, over which the figure is left
  in the cache and the page carries a `figure-omitted: size` stub — a git repo is not a blob store
  and a corporate tenant's remote may enforce a push size limit.
```

### 4. Two colleagues on two laptops cannot share one `docs/` repo — measured, and the document has no owner model

`grep -ci 'single writer\|one writer\|who runs\|branch\|push'`: 0, 0, 0, 0, 0. The only multi-user
content is §4.7's *"record the principal, never merge two users' mirrors"*, which is about
permission divergence, not about git. The lock is explicitly *"machine-wide"*, so it does not exist
across machines. Measured on a fixture with two clones syncing concurrently (`./mm.sh`):

- plain merge ⇒ **conflicts on both `CHANGELOG.md` and `MANIFEST.jsonl`**, i.e. on every cycle
  where two machines each ran once — the steady state, not a corner case;
- `merge=union` on both ⇒ `CHANGELOG.md` merges losslessly (out of chronological order), and
  `MANIFEST.jsonl` **silently corrupts**: `{"id":"A","h":"1"}` and `{"id":"A","h":"2"}` both survive,
  so the manifest now carries two contradictory hashes for one `source_id` and the next classifier
  run picks whichever `sort` puts first. A union driver is right for the log and catastrophic for
  the state.

**Fix — add a new §4.7 subsection:**

```
**Who runs it (decide this before week 1).** Exactly ONE principal on ONE machine is the writer
for a given `docs/` repo. Everyone else consumes it read-only with `git pull --ff-only`; a
consumer that has committed is out of the protocol and re-clones. Rationale: the delta cursor,
the deletion breaker's denominator and the `principal` column are all per-view state, and two
writers produce a manifest that is a merge of two different views of the tenant — measured to
conflict on MANIFEST.jsonl and CHANGELOG.md on every concurrent cycle, and to corrupt the
manifest silently under `merge=union`.

If a second writer is genuinely required, all four of these are mandatory and none is optional:
  - `mirror/<principal>/…` and `_manifest/<principal>/…` — disjoint subtrees, so two writers
    never touch one path. `topics/` stays single-writer; curation is not mergeable.
  - `docs/.gitattributes`:
        CHANGELOG/*.md  merge=union
        DEPENDS.tsv     merge=union
        *.jsonl         -merge          # REFUSE to auto-merge manifest shards; union corrupts them
    with `_sync/STATE-<hostname>.md` per writer and `STATE.md` generated from them.
  - the cursor store is **never** committed (finding 5).
  - each writer pushes to its own branch and a scheduled job fast-forwards `main` only when the
    disjointness lint passes; a writer that cannot fast-forward stops and alarms — it must never
    merge, because it cannot know whether the other view saw the same tenant.
```

### 5. Secret custody is absent: the delta token and the refresh token have no home, and the default one is git (§4.2 auth rungs, §4.6 tree)

`grep -ci 'keychain\|secret\|Conditional Access'`: 0, 0, 0. §4.2 chooses device-code auth and says
only *"token custody is the pipeline's job (the server stores nothing)"*. A `@odata.deltaLink` is a
URL with a bearer-adjacent sync token in it; §4.2 says to store it *"ATOMICALLY with the item
snapshot"*, and the item snapshot is the NDJSON manifest that §4.3 exports **into git** — so the
naive implementation commits tenant sync tokens to a shared repo, and §4.7's own "git mirror is an
exfiltration channel" paragraph never notices. Nothing states where the device-code **refresh
token** lives on a laptop, that it expires (inactivity, CAE revocation, a Conditional Access
re-auth requirement), or what an unattended launchd job does when it does — which is the single
most likely way this pipeline dies quietly three weeks in.

**Fix — add to §4.7:**

```
- **Secret custody.** Three secrets, three homes, none of them git:
  `refresh_token` → macOS Keychain (`security add-generic-password -s docs-sync -a <upn> -w -T <binary>`),
  read at start and rewritten on every refresh; `delta_link` per drive → `~/Library/Application
  Support/docs-sync/cursors.sqlite`, mode 0600, on a FileVault volume; nothing in `docs/`.
  The committed manifest and STATE.md carry a cursor's `age` and `fingerprint` (sha256 of the token,
  first 12 hex) — never the token. Land-gate lint: no committed file matches
  `token=|deltatoken=|Bearer `.
- **Auth is a finite resource and its exhaustion must be loud.** A delegated refresh token dies on
  inactivity, on a CAE revocation event, and on a Conditional Access policy that demands interactive
  re-auth; an unattended job cannot recover any of them. On `invalid_grant` / `AADSTS50076` /
  `AADSTS50173`: do NOT retry, do NOT advance any cursor, write `auth: REAUTH_REQUIRED <utc>` into
  `_sync/STATE.md`, commit that alone, and exit non-zero so launchd's log shows it. STATE.md is what
  the agent reads first, so the agent's next session says "my sources are N days stale and need a
  human to re-auth" instead of reading a frozen mirror as current.
```

---

## MAJOR

### 6. First-run bootstrap: `?token=latest` is offered with no warning that it never mirrors the corpus (§4.2 state machine)

`S0` lists *"bootstrap alternatives: `?token=latest` (future changes only, no crawl)"* as a
peer of the full delta, with no rule for choosing. An engineer under time pressure picks it — it
is the fast one — and gets a pipeline that is permanently correct about changes and permanently
blind to every file nobody touches again. The document never says what the manifest, `INDEX.md` or
`STATE.md` look like before the first complete pass, and never states the precondition the
deletion breaker needs.

**Fix — replace the `S0` bootstrap parenthetical with:**

```
   bootstrap: the FIRST pass on a new source is ALWAYS a token-less full delta
   (pass_kind=full_enumeration). `?token=latest` is legal only to re-arm a source whose baseline
   already exists in the manifest — used as a bootstrap it yields a pipeline that mirrors only
   files edited after today and never the corpus, with no error at any layer.
   `?token=<ISO timestamp>` (ODB/SPO only) backfills from a known point and is a resync aid,
   not a bootstrap.
   Before the first full_enumeration completes for a scope: manifest rows exist with
   first_seen_run set and enumeration_complete[S]=false; `docs/mirror/` is published
   incrementally (a partial mirror is useful); `INDEX.md` and `STATE.md` carry
   `baseline: INCOMPLETE <n>/<unknown> items` so the agent never reads a partial corpus as whole;
   deletion detection is STRUCTURALLY unreachable (finding 1) — the breaker cannot arm until at
   least one full_enumeration has completed for that scope.
```

### 7. `key_schema_version` appears twice, is never defined, and bumping it re-renders everything with no procedure and no cost statement (§4.1 invariant 5, §4.3)

It is the first component of `action_key` and it maps Zoekt's `format-version`. Bumping it
invalidates **every** key for **every** converter at once — 50 k items, including the tier-2 PDF
population §4.4 measures at 1.3 p/s on an M3 Max, i.e. *days* of laptop backfill. The document
calls a converter upgrade *"one deliberate, dated bulk re-render"* and never says how long one
takes, when it may run, or how the old cache is reclaimed (write-once, no GC — see finding 3).
`grep -ci 'migration\|migrate'`: 0. There is also no schema-migration path for the SQLite store.

**Fix — add to §4.1 invariant 5 and a new §4.7 bullet:**

```
`key_schema_version` is bumped ONLY when the key's own composition changes (a field added or
redefined) — never for a converter change, which `converter_version` already covers. Because a bump
invalidates every key for every format simultaneously, treat it as a migration, not a config edit:

- **Manifest and key migrations.** The manifest carries `meta(key_schema_version, manifest_schema_version,
  tree_sha)`. On a mismatch the pipeline REFUSES to run and prints the migration command; it never
  silently re-derives. `docs-sync migrate` (a) rebuilds SQLite from the committed NDJSON shards —
  which is why the shards are the durable form and SQLite is a cache — and (b) for a
  key_schema_version bump, writes a `cache/KEYMAP-<old>-<new>.tsv` mapping old→new keys for every
  row whose inputs are unchanged, so the bulk re-render is a *rename inside the cache* and costs no
  conversion at all. Only rows whose inputs genuinely changed re-render.
- A re-render that does have to run is scheduled, budgeted and resumable: a tier-2 PDF backfill at
  the measured 1.3 p/s is ~10 h per 50 k pages on one laptop, so it runs as its own launchd job
  off-peak with a per-run page budget, and every cycle it does not finish records
  `backfill: <done>/<total>` in STATE.md. Never inline it in a sync cycle.
```

### 8. launchd is named five times and specified nowhere — and the two things that will actually break it are unstated (§4.7, §7, §9 probe 4)

The document says *"launchd every N min"*, and §9 probe 4 notices in passing that a launchd job's
`MaterializeDatalessFiles` key *"may differ from the login session"* — then §4.7's hydration
discipline is written entirely for the login-session case. There is no plist, and the two failure
modes an engineer hits on day one are absent:

- **PATH.** launchd gives a job a minimal PATH with no Homebrew. Measured on this Mac:
  `command -v bash` → `/opt/homebrew/bin/bash` (5.3), but `/bin/bash` is **3.2.57**, and
  `command -v pandoc` → **ABSENT**. A `#!/usr/bin/env bash` converter script that works in the
  operator's shell gets bash 3.2 under launchd and a `pandoc: command not found` per docx.
- **TCC.** `~/Library/CloudStorage` is TCC-protected. A background LaunchAgent cannot show a consent
  prompt; it gets EPERM, which the T3 walk sees as an empty directory — and §4.2 already rules that
  a zero-child cloud directory is *unknown, never empty*, so this must be wired to that rule.

**Fix — add to §4.7:**

```
- **launchd, concretely.** Two LaunchAgents, never one job doing both (launchd will not start a
  second instance of a running job, so an 11-minute reconcile silently swallows ten poll intervals):
  `com.<org>.docs-sync.poll` (StartInterval 300) and `com.<org>.docs-sync.reconcile`
  (StartCalendarInterval, off-peak). Both:
      ProcessType            Background        # I/O-throttled, correct for this work
      ThrottleInterval       60                # launchd's floor is 10 s; do not fight it
      RunAtLoad              true
      EnvironmentVariables   PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
      MaterializeDatalessFiles  false          # the launchd key that makes hydration fail-closed
      StandardOutPath/StandardErrorPath  ~/Library/Logs/docs-sync/<label>.log
      LimitLoadToSessionType Aqua              # needs the user's Keychain and CloudStorage mount
  Every script is `#!/bin/bash` tested against **bash 3.2** (`/bin/bash` on macOS 15; the shell on
  the operator's PATH here is Homebrew 5.3) or a pinned interpreter by absolute path. Every external
  converter is invoked by absolute path resolved at install time and asserted present at startup.
- **TCC/FDA.** `~/Library/CloudStorage` is TCC-protected and a background agent cannot prompt: it
  receives EPERM, which a directory walk reports as an empty directory. Grant Full Disk Access to the
  *interpreter that launchd execs* (on a managed fleet this is an MDM PPPC profile, not a settings
  toggle), and make the walker assert readability of a known-present canary path at startup — a
  scope that returns zero children is `unknown`, never `empty`, and must never reach the classifier.
- **Network.** Gate the Graph arm on reachability before the first request
  (`nc -z -G 3 graph.microsoft.com 443` or equivalent); a laptop off VPN otherwise burns the run's
  retry budget and writes a misleading `pass_complete=false`. No network is `skipped`, not `failed`.
```

### 9. Windows colleagues will fail to clone the repo, and the stated slugifier is what breaks it (§4.4 converter contract, §4.7 Names)

`grep -ci Windows` on the document: **0** — while `I1-hostile-reviewer.md:69` in its own evidence
base raises *"semantic renames in docs/ overflow Windows colleagues' 260-char git checkouts"*.
§4.7 discusses Graph's 400/520-character limits and never NTFS's 260. Worse, the slugifier in §4.4
strips `[ ] ( ) # { }` and nothing else. Measured (`./win.sh`): `mirror/meeting: notes.md`,
`mirror/q3?.md`, `mirror/aux.md` and `mirror/report.` are all created and committed **without a
murmur on APFS**. Every one of the four is uncreatable on NTFS (`: ? * " < > |` are illegal, a
trailing dot is stripped, `aux` is a reserved device name), so a Windows colleague's `git clone`
fails with `error: invalid path` and gets **no working tree at all** — a total, not partial,
failure. The document also has no `.gitattributes` line-ending policy, so a Windows checkout with
default `core.autocrlf=true` rewrites every markdown file and the next `git status` there shows the
whole corpus modified.

**Fix — replace the §4.4 slugifier clause and add to §4.7 Names:**

```
slugifier: lowercase; NFC; strip diacritics; map dashes; collapse whitespace to `-`; strip
`[ ] ( ) # { }` AND the NTFS-illegal set `< > : " / \ | ? *` plus control bytes; strip trailing
dots and spaces; refuse the Windows reserved stems (`con prn aux nul com1-9 lpt1-9`, with or
without extension) by suffixing `-doc`; check case-insensitive collisions (APFS silently overwrote
`API-Spec.md` with `api-spec.md`, measured) and NFD/NFC twins, disambiguating with the source id,
never a counter. Cap any single path at **200 characters relative to the repo root**, so a Windows
colleague cloning into `C:\Users\<name>\<repo>` stays under MAX_PATH 260 without needing
`core.longpaths`; the original name lives in frontmatter.
```

```
- **The repo must check out on Windows.** Ship `docs/.gitattributes` with `* text=auto eol=lf` and
  `*.png binary` (without it a Windows `core.autocrlf=true` checkout reports the entire corpus
  modified on the first `git status`), and a land-gate lint that rejects any tracked path failing the
  slugifier's Windows rules or exceeding 200 chars. A Windows consumer is read-only by finding 4;
  if a Windows machine ever becomes a *writer*, arm B is a different implementation — no
  `SF_DATALESS` (use `FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS` / `_OFFLINE`), no `getattrlistbulk`
  (use the NTFS USN change journal as the T2/T3 substrate) — and that is a separate build, not a flag.
```

### 10. One commit per cycle at a 60 s–5 min cadence destroys `git log` — which is the document's own primary freshness API (§4.7, §4.1 invariant 7)

§4.1 invariant 7 and §4.6 make `git log --since` *the* answer to "what changed since I last
looked". §4.7 then mandates *"one manifest snapshot, one `CHANGELOG` section and one git commit per
cycle"* at a 60 s–5 min cadence: **288 to 1,440 commits per day**. And `_sync/STATE.md` is a
committed file carrying *"per-source cursor age"*, so the tree diff is non-empty **every cycle by
construction** even when nothing in the corpus changed — there is no such thing as a no-op cycle.
Within a week `git log --since=1.week docs/` is ~10 k commits of which a handful touched content,
and the one command the agent is told to run is unusable.

**Fix — replace the §4.7 "One lock, one commit" bullet's second half with:**

```
one manifest snapshot and one git commit per cycle **that changed content** — a cycle whose
`docs/mirror` + `docs/topics` + `docs/_manifest` diff is empty commits NOTHING, so `git log`
contains only real change and `git log --since` stays the freshness API. Cursor ages, pass
counters and breaker state are volatile and live in `docs/_sync/STATE.md`, which is
**`.gitignore`d**; a committed `_sync/STATE.snapshot.md` is written only on a cycle that already
had a content commit, so STATE never manufactures a commit. The agent reads the working-tree
STATE.md (always current) and `git log` (always meaningful). Commit subject:
`sync: <A>a <M>m <R>r <D>d <src-list>` so the log is scannable without opening the CHANGELOG.
```

### 11. The daily reconcile has no cost, no budget and no concurrency model — and its own evidence base computed the number (§4.7 Cadence)

§4.7 says only *"daily full reconcile regardless (Microsoft's ceiling is 'no more than once per
day')"*, which reads as "this is expensive and rationed". `C4-rclone.md:328` — this wave's own
report — already did the arithmetic: *"Tier A's floor is ⌈n/1000⌉ delta pages × ~1.35 s. At 50k
items that is ~50 pages / ~1 min — negligible, run it hourly."* The document quotes the 1.35 s
figure only as an indictment of rclone and never applies it to its own reconcile, so the
implementer is left unable to size the one pass everything else falls back to. Separately, the
poll loop and the reconcile share one cursor and one lock and the document never says how they
interleave — and §4.7's own local T3 walk cost is unmeasured (§9 probe 5), so the *local* arm's
reconcile has no number at all.

**Fix — replace the §4.7 Cadence bullet:**

```
- **Cadence, with the arithmetic.** Graph delta poll 60 s–5 min per drive (1 RU each). Full
  reconcile = ⌈items/1000⌉ delta pages × ~1.35 s/page (rclone's measured page floor, C4): **~50
  pages ≈ 1 min at 50 k items**, ~22 min at 1 M. At this corpus size the reconcile is cheap enough
  to run **hourly**; Microsoft's "no more than once per day" becomes the binding constraint only
  past ~10⁵ items. The LOCAL T3 reconcile cost is UNMEASURED (§9 probe 5) — measure it before
  choosing its cadence and record the number in STATE.md, never assume parity with the Graph arm.
  Poll and reconcile are separate launchd labels contending for the one docs/ lock: the reconcile
  takes it, the poll skips its turn (`rc=75`, logged as `skipped: lock held by reconcile`, not
  failed) and its `pass_complete` is unaffected — a skipped poll is not an incomplete pass.
  Tier-2 PDF backfill and VLM captioning are budgeted off-peak batch jobs (§7 note), never inline.
```

### 12. Nothing stops the manual inbox and the Graph arm mirroring the same file twice — and the stated dedup key cannot (§4.2 arm C, §5)

§5's rule is *"Re-upload of the same bytes under a new name: `canonical_sha256` equal, new
`source_id` → alias-of, never a second page."* The overlap case an operator hits immediately is a
colleague dragging into the manual inbox a file that is *also* in a synced library. The dedup then
rests on `canonical_sha256` matching across arms — and §4.2 trap 1, in this same document,
establishes that SharePoint **mutates the bytes on upload** (Document ID injection into Office,
PDF and HTML). For OOXML the `docProps/*` denylist happens to absorb it; for **PDF and HTML there
is no canonical-parts normalisation at all**, so the local original and the library copy have
different `content_hash` *and* different `canonical_sha256`, the alias-of rule misses, and the same
document is mirrored twice under two paths with two `source_id`s — then cited independently by
curated pages. The document never connects its own trap to its own dedup rule, and never states a
precedence between arms.

**Fix — add to §4.2 arm C:**

```
**Arm precedence, and why canonical-parts hashing cannot carry it.** The Graph arm is authoritative
for any object under a synced root: the manual inbox REFUSES (quarantines with reason
`duplicate-of <source_id>`) any drop whose canonical TEXT hash matches a live Graph row, or whose
(normalized-name, size) pair does, and names the arm that owns it. Canonical *text* is the only key
that survives the boundary: §4.2 trap 1's upload-side Document ID injection changes `content_hash`
and, for PDF and HTML — which have no part denylist — changes `canonical_sha256` too, so two copies
of one document hash differently on both keys and the §5 alias-of rule misses them. A drop that is
NOT under any synced root is a first-class source with its own `source_id`; a drop that is, is a
human trying to be helpful and must be told (in the quarantine row) that the file is already
mirrored, with the mirror path.
```

---

## MINOR

### 13. "armed" means both "suppressed" and "enabled", 238 lines apart

§4.2 line 131: *"an incomplete pass must not **arm** deletions"* — armed = deletions can happen.
§4.7 line 369: *"records `pass_complete=false`, which keeps the deletion breaker **armed**"* —
armed = deletions cannot happen. Same word, opposite senses, on the one flag whose misreading is
finding 1's mass deletion.

**Fix:** delete the word from both. §4.2: *"an incomplete pass must not ENABLE absence-based
deletion"*. §4.7: *"…records `pass_complete=false`, which keeps `deletions_enabled=false` and the
cursor un-advanced"*. Name the manifest field `deletions_enabled` and never write "armed" about it.

### 14. The refresh-queue loop §4.5 tells you to ship verbatim reports every page as missing (measured)

§4.5 says *"Write the command into `docs/README.md` verbatim: nothing in the harness will invent
it."* Run it against the frontmatter form the same section specifies — `sources: [{path:
../../mirror/…}]`, page-relative — and column 2 of `DEPENDS.tsv` is `../../mirror/…`, so the loop
opens `docs/../../mirror/…`, i.e. two levels **above the repo root**. Measured (`./depends.sh`): a
present, unchanged source yields `TOMBSTONE-OR-MISSING`, and since the STALE linter is built on
this queue, every curated page gets bannered. The `2>/dev/null` on the `sed` is what hides it —
collapsing "source deleted" and "my path arithmetic is wrong" into one verdict, which is this
repo's own `predicate-error-exit-is-indistinguishable-from-false` lesson.

**Fix — state the normalisation and make the missing case loud:**

```
`DEPENDS.tsv` column 2 is **repo-root-relative** (`docs/mirror/…`), normalised from each page's
page-relative `sources:` entry at generation time — the generator resolves it against the page's
own directory and errors on any path escaping `docs/`. The queue then reads "$s" directly:

  cur=$(sed -n 's/^rendered_sha256: //p' "$s") || { echo "READ-FAILED	$p	$s"; continue; }
  [ -e "$s" ] || { echo "SOURCE-GONE	$p	$s"; continue; }
  [ -z "$cur" ] && { echo "NO-HASH-IN-SOURCE	$p	$s"; continue; }

Three distinct verdicts, because they demand opposite actions: a broken queue must never present
as a tombstone. Ship a fixture (one page, one present source, one deleted source) that asserts the
queue prints exactly one STALE and one SOURCE-GONE — a refresh queue that reports everything is
indistinguishable from one that reports nothing.
```

---

## What held

- §3's symlink verdict, §4.1's three-hash split, the `GEN_COUNT` finding and the classifier's
  zero-byte ordering: I tried to find a cheaper wrong answer and could not. The `dataless` /
  `unknown` / `changed` three-way split and the "zero-child cloud directory is unknown" rule are
  exactly the distinctions an operator needs, and both are stated in the right place.
- §9's probe list is honest about what was not measured and each probe decides a named arm. Probes
  4 and 4b in particular are the two that would otherwise be discovered in production.
- §4.4's per-format routing and the write-once cache keyed on producer identity survive the
  migration question once finding 7's KEYMAP is added; the key composition itself is right.
- The ordering of §10 is right (correct pipeline before accelerators, Graph arm second, curation map
  last with a 20-page prototype). My findings are all things to add to weeks 1 and 2, not
  reorderings: findings 1, 2, 3, 6, 9, 10 and 13 belong in week 1, 5, 8 and 11 in week 1's
  operational half, 4 and 7 before a second person is given the repo, 12 and 14 in week 3.
