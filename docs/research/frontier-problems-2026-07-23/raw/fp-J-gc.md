<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/8ff95a36-691e-4a53-8ae5-be071c48b3b6.jsonl
 turns=80 assistant_texts=7 last_stop=end_turn mail_injections=[] -->

Saturation reached. Attribution resolves the 94G: **46 reso + 25 doc_classifier worktrees** dominate the bytes; claude-infra's 26 pool worktrees are ~4.4M each (~115M total — shell repo, no node_modules). claude-infra's accumulation is **ref-count and file-count, not disk bytes**. Predict-next-call (reso-gc liveness / restic size) would refine but not change the map. Composing.

---

# Accumulation Inventory — claude-infrastructure (live disk truth, 2026-07-23 ~02:00 PT)

**Brief-drift check**: clean — infrastructure GC research, zero BD/legal/competitive triggers.
**Headline correction to brief's framing**: the largest surface is git worktrees (**94G pool**, mostly reso/doc_classifier — NOT claude-infra bytes), and the transcript corpus the brief worried about is **empirically bounded** (CC retention). claude-infra's *own* unbounded accumulation is **refs, rows, and markers**, not gigabytes.

## (a) Accumulation table

| Surface | Size/Count NOW (command) | Growth | Reaper | Last-run evidence | Risk |
|---|---|---|---|---|---|
| **`~/Development/.worktrees` pool** | **94G**, ~100 wts (`du -sh ~/Development/.worktrees`; `git -C … remote` → 46 reso, 26 claude-infra, 25 doc_classifier, 3 reso-web) | reso wt-cc-* @ 2–4G each dominate | `gl.reso.worktree-gc` covers **reso only**; claude-infra share = **NONE** | reso gc loaded (`launchctl list`); 46 reso wts still present | **HIGH (disk)** — but not claude-infra bytes |
| **Local branches** | **233** (`git branch \| wc -l`): 147 `ship/backup-*`, 41 feat, 20 fix, 11 `wt-<hash>`, 3 docs, 2 chore | +1 `ship/backup` **per land** (`ship-land.sh:357`) | **NONE** (grep `branch -[dD]` → only `git-worktree-guard.sh`, a guard) | n/a | **HIGH** — 63% of branches are land-cruft |
| — of which merged-into-main | **134 deletable** (`git branch --merged main`) | monotonic | **NONE** | oldest merged commit 2026-07-15 | MED |
| **Git worktrees (claude-infra)** | **55** (`git worktree list`), **8 prunable** | +1/session | manual `git worktree prune`; `desk-land.sh:81` removes only its **own** TMP_WT | 8 already flagged prunable, never pruned | MED — ref-count + scan cost |
| **`session-index.db`** | **47MB, 5323 rows** (`sqlite3 … COUNT(*)`), rows back to **2025-10-04** | +sessions/day, **ADD-only** | `session-index-sweep.sh` (60s launchd) **upserts only**; grep → no `DELETE FROM sessions`, no `VACUUM` | live (`com.claude.session-search-sweep` loaded) | **HIGH** — queried per statusline; ~3800 ghost rows |
| **Transcripts `.claude/projects`** | 1526 files, **717M**, **+213M/7d** (`find -mtime -7 -printf %s`) | high inflow | **CC/Anthropic retention** (empirical: **0 files >35d**, oldest Jun 30) | oldest transcript Jun-30 | **LOW — bounded** (plateaus) |
| Transcripts `.claude-secondary` | 2396 files, **1.1G**, oldest Jun 28 | same | same retention | oldest Jun-28 | LOW — bounded |
| **`~/.claude/watchdog`** | **2193 files** (~730 sessions), 8.6M, oldest **Apr 17**, **78 stale .pid >7d** (`find -mtime +7`) | +3 files/session | `session-end.sh:42-48` sweeps dead-pid pairs on clean exit | fires only on clean SessionEnd | MED — **partial** (crash + reused-pid escapees) |
| **`~/.claude/archives`** | **971M**, 65 files = frozen CC 2.1.114 node_modules | static; **+~1GB/frozen version** | `restic-claude-archive` + `verify-2114-archive` (integrity, not prune) | restic loaded | LOW now / **latent** |
| **Unrotated logs** | `lead-crash-watchdog.log` 2.1M, `cc-reaper.log` 1.4M/**16297 lines** (`wc -l`), `supervisor.log` 907K | cc-reaper.log fast (reaper ~1/min) | `rotate-autonomy-logs.sh` targets **only** idl + bash-commands + bash-execution | log-rotation ran Jul-23 01:35 | LOW-MED — MB/day, no cap |
| Rotated logs (covered) | bash-commands/execution.log rotate @25MB | bounded | `rotate-autonomy-logs.sh` (keep 8, gzip) | .gz at Jul-19 | LOW — **working** |
| **`autonomy/pages`** | 479 files, 1.9M, oldest **Jul 14** | +pages/day | `autonomy-sweep.sh` prunes **sweep-seen only** (`:110 -mtime +TTL -delete`); pages **not** pruned | sweep alive (idl Jul-23 08:56) | MED — unbounded markers |
| `autonomy/sweep-seen` | 499 files, 0B, oldest Jul 18 | TTL-capped | `autonomy-sweep.sh:110` | **working** (~5d window) | LOW — **working** |
| `autonomy/{comms-alarms,push-records,decisions}` | 288 / 134 / 70 files | +markers/event | **NONE found** | oldest Jul 18-20 | LOW-MED |
| `autonomy/backlog.jsonl` | 291K single file | append | **NONE** (not a rotate target) | — | LOW |
| **`~/.claude/backups`** | 429 files, 3.4M, oldest exactly **Jun 23** (30d) | churns | `prune-backups.sh` (30d + keep-10/basename) | `backup-cleanup.log` Jul-23 00:41 | LOW — **working** |
| `teams/_archive` | 37 dirs, 2.0M | +orphan teams | `team-orphan-reaper.sh` **moves in**, nothing prunes _archive | reaper alive Jul-23 01:55 | LOW |
| **CC-native**: `tasks/` | **1014 files**, 4M, oldest **Jan 22** | slow | **NONE** | — | LOW (count) |
| `history.jsonl` | **8.9M single file** | append, CC-owned | **NONE** (CC-managed) | Jul-22 | LOW |
| `file-history` 60M/1318 · `plan-history` 27M/962 | large, CC-owned | slow | CC-managed (unverified prune) | — | LOW-MED |
| **`/private/tmp/wt-*`** | 40 dirs (18 M-sized 4-5M, rest 0B empty shells) + stray `wt-ci.log`, `glued-token-fix.patch`, `wt-*-batsfull.txt` | +/session | **NONE** (OS `/tmp` cleanup only on reboot) | 0B shells = pruned-wt husks | LOW |
| `/tmp/claude-*-cwd` | ~1/session small files | +/session | **NONE** | oldest Jul 16 | LOW |

## (b) No-reaper list (writer exists, deleter absent)

1. **`ship/backup-*` branches** — `ship-land.sh:357` creates, nothing deletes → **147 accumulated**.
2. **Merged feature branches** — 134 deletable, no post-land `branch -d`.
3. **claude-infra worktrees** — no GC (reso's `gl.reso.worktree-gc` is namespaced to reso).
4. **`session-index.db` rows** — sweep is upsert-only; no row-delete for vanished transcripts, no `VACUUM`.
5. **`autonomy/pages`, `comms-alarms`, `push-records`, `decisions`** — `autonomy-sweep` prunes only `sweep-seen`.
6. **`teams/_archive`** — reaper moves in, never out.
7. **Unrotated logs** — `cc-reaper.log`, `lead-crash-watchdog.log`, `supervisor.log`, `claude-accounts.log` outside rotate targets.
8. **`tasks/`** (1014 files since Jan) · **`history.jsonl`** (single append file) · **`/tmp` litter**.

## (c) Risk ranking (by measured impact, not tidiness)

1. **`ship/backup-*` + merged-branch accrual (233 branches)** — *near-monotonic, no reaper, self-amplifying* (every land adds one). Cost: every `git branch`/`for-each-ref`/`git cherry` is O(refs); `stranded-sweep.sh:66` loops **all 233 branches × `git cherry`** on each land-gate. Not yet a wall but the only surface with a documented *creation-on-cleanup* anti-pattern.
2. **`session-index.db` 47MB / 5323 ghost-heavy rows** — read on **every statusline render** (per prompt). ADD-only + no VACUUM → latency grows monotonically; ~3800 rows index transcripts that no longer exist on disk. Highest *query-frequency* surface.
3. **Worktree file-count → scan cost (EMPIRICAL degradation)** — `5d5ffce`: supervisor liveness `find`-walk hit **~5min vs a 30s sweep interval → overlapping sweeps pinned disk at 1.6k tps while idle** (doc_classifier 1.27M files). Fixed the *scan* (`-prune`), **not** the accumulation. This is the one surface with proven real-world degradation; the fix masked it.
4. **`~/.claude/watchdog` 2193 files** — `session-end.sh` sweeps `*.pid` on every clean exit → O(2193) stat+`kill -0` per session-end; 78 stale + reused-pid false-live escapees (oldest Apr 17).
5. **94G worktree disk** — largest bytes, but **mostly reso/doc_classifier**, and reso has a GC. claude-infra's own share ~235M. Disk-pressure risk is real machine-wide, low *attributable* to this repo.
6. **Everything else (backups, transcripts, sweep-seen, logs-rotated)** — **bounded / working**. Untidy but not degrading.

**Empirical vs theoretical**: #3 is the only *measured* degradation (`5d5ffce` commit body). #1/#2/#4 are *mechanistically certain* unbounded growth with frequency-of-access cost, not yet benchmarked to a wall. #5 disk is measured but mostly out-of-repo.

## (d) Lifecycle-ownership gaps — "who retires a finished unit of work?"

**There is no single owner of 'this work unit is fully retired.'** Each subsystem reaps its own artifact keyed to *its own* trigger, none keyed to *work-unit retirement*:

| Retirement step | Who should own it | Reality |
|---|---|---|
| Land → delete feature branch | ship-land | **Gap** — instead *creates* `ship/backup-*` (`:357`) |
| Land → remove worktree | ship-land / desk-land | **Gap** — desk-land removes only its own TMP_WT (`:81`); dev worktrees persist |
| Land → prune `ship/backup-*` after N | anything | **Gap — none** |
| Session end → clear watchdog | session-end.sh:28-48 | Partial (clean exits only) |
| Session end → deregister cc-registry | session-deregister.sh:25 | Works |
| Transcript pruned → delete DB row | session-index-sweep | **Gap** — sweep never un-indexes; 3800 ghosts |
| Team dead → archive | team-orphan-reaper | Works (but `_archive` never pruned) |

The chain breaks hardest at **land**: the moment a unit is *most provably* retired (content on trunk), the tooling *adds* a branch and *retains* the worktree instead of collapsing them. `cc-reaper` retires **sessions** (panes/quota) elegantly but has no mandate over **git refs / DB rows / markers**. No component consumes a "unit retired" event and fans out the cleanup.

## (e) CANDIDATE FRONTIER PROBLEMS

---
**Name:** Retirement has no owner — cleanup is creation's inverse nowhere
**Evidence:** `ship-land.sh:357` creates `ship/backup-*` on every land (147 now) + deletes no branch/worktree; `git branch --merged main` = 134 undeleted; `session-index-sweep.sh` upsert-only → 5323 DB rows vs transcripts only back to Jun-30 (~3800 ghosts).
**Mechanism class:** Missing lifecycle-completion event; each reaper keyed to a *proxy* trigger (idle, size, mtime-TTL) not to the *semantic* "work unit retired."
**Current mitigations + status:** Per-artifact reapers exist and mostly work (cc-reaper sessions, team-orphan-reaper teams, prune-backups, rotate-logs) — but **no reaper is keyed to landing**; the git/DB/marker artifacts of a retired unit have zero coverage.
**Why it resists normal fixes:** A land is atomic per-session, but retirement is cross-cutting (branch + worktree + backup-branch + DB rows + registry + markers span 4 stores owned by different scripts). No shared "unit id" ties a session → its branch → its worktree → its DB rows → its markers, so no local script *can* fan out the cleanup without a join key that doesn't exist.
**Quantified cost:** 147 backup + 134 merged branches (63% of 233) → O(refs) tax on every `stranded-sweep` (233×`git cherry`/land) and worktree scan; 3800 ghost DB rows on a 47MB DB read per statusline.
**Frontier-fix sketch:** A retirement ledger — stamp each work unit a `unit-id` at worktree creation (session-register already has the hook); on land, emit one `unit-retired` event that a single reaper consumes to fan out: `branch -d` feature + worktree remove + `ship/backup-*` keep-last-N + DB row-delete-where-transcript-absent + marker sweep. Turns N partial reapers into one event-sourced collapse.
**Confidence + stale-risk:** High confidence (all mechanisms disk-verified this session). Stale-risk low over weeks; branch/DB counts only grow — direction is stable.

---
**Name:** ADD-only index over a self-pruning corpus (ghost-row divergence)
**Evidence:** `sqlite3 session-index.db "SELECT COUNT(*),MIN(created_at)"` → 5323 rows, 2025-10-04; oldest on-disk transcript Jun-30 (`find -printf %T`); helper grep shows `DELETE FROM sessions_fts` but **no** `DELETE FROM sessions` / `VACUUM`.
**Mechanism class:** Producer (CC retention) and index (sweep) have divergent lifetimes; index assumes append-only over an ephemeral source.
**Current mitigations + status:** `session-index-sweep.sh` runs 60s (live); indexes new/changed only — never reconciles deletions. No mitigation deployed.
**Why it resists normal fixes:** The sweep can't see a deletion (it iterates *existing* files); detecting a vanished transcript needs an *anti-join* pass (rows whose file_path no longer stat's) that no current trigger performs, plus a VACUUM whose lock could race the 60s sweep.
**Quantified cost:** ~3800 stale rows (71% of table), 47MB read per statusline render (every prompt, every session); grows ~sessions/day forever.
**Frontier-fix sketch:** Add a reconcile pass to sweep (or cc-reconcile): `DELETE FROM sessions WHERE file_path NOT IN (live stat set)` gated behind the existing trylock, periodic `VACUUM` at low-tps window. Ties to the retirement-ledger fix (same row-delete).
**Confidence + stale-risk:** High. Stale-risk very low (monotonic, corpus retention is stable at ~5wk).

---
**Name:** Reaper coverage is enumerated, not derived — new surfaces are born uncovered
**Evidence:** `rotate-autonomy-logs.sh:122` hardcodes 3 target logs → `cc-reaper.log` (16297 lines) + `lead-crash-watchdog.log` (2.1M) grow uncapped; `autonomy-sweep.sh:110` prunes only `sweep-seen` → `pages/`(479), `comms-alarms/`(288) uncovered.
**Mechanism class:** Allow-list reaper config; every *new* writer defaults to uncovered until a human adds it to a target list.
**Current mitigations + status:** `reaper-horizon-lint.sh` exists (grep hit) — unverified whether it flags uncovered surfaces; no evidence it gates new writers.
**Why it resists normal fixes:** Coverage is a config list maintained by hand; the system has no inventory of "dirs/files that grow" to diff against "dirs/files a reaper touches," so a gap is invisible until a surface is large.
**Quantified cost:** Currently sub-degradation (MB-scale), but it's the *generator* of every other no-reaper item in list (b) — 8 uncovered surfaces today.
**Frontier-fix sketch:** Invert to deny-by-default: a manifest of write-paths (derivable from `>>`/`mkdir` greps across hooks+scripts, already partially done in rotate-logs' header) auto-diffed against reaper target-lists in CI; any uncovered growing path fails `reaper-horizon-lint`.
**Confidence + stale-risk:** Med-high (mechanism certain; `reaper-horizon-lint` scope unverified — see blockers). Stale-risk med (a human may wire specific logs any week, shrinking the gap but not closing the class).

---

## Blockers / uncertainties (explicit)
- **`reaper-horizon-lint.sh` scope unread** — it may already flag uncovered surfaces (would downgrade frontier #3). Not opened (saturation).
- **reso `worktree-gc` effectiveness** — 46 reso worktrees persist despite a loaded GC; couldn't tell if active vs GC-lagging (out of claude-infra scope).
- **restic archive repo size** — the 971M frozen tree is restic-backed; repo growth per version-freeze not measured (read-only scope, no restic query run).
- **CC-native `file-history`/`plan-history`/`history.jsonl` prune policy** — assumed CC-managed; not confirmed CC prunes them (60M+27M+8.9M, could be latent).
- **Memory correction:** `com.claude.discovery` **IS loaded now** (`launchctl list` → both dispatcher+discovery status 0) — the "staged-not-loaded dormancy" memory note is stale as of 2026-07-23.