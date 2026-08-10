# Axis I — Stores & Growth Census
Measured 2026-08-10 on the live machine. Read-only: nothing was modified.
Owner: store-growth census (axis F consumes per-hook-fire read cost only).

## Headline

**12.08 GB censused across 25 stores — but the memory bottleneck is not the disk total.
The three store facts that touch RAM are: (1) an un-activated reaper whose surface grew
810 MB/day and is bounded only by reboot; (2) a 29,922-byte file injected verbatim into
every session's context at every SessionStart, uncapped and append-only-by-design; and
(3) 738 MB of resident Spotlight indexer, driven by a surface that provably excludes
every one of our stores.**

The harness's own stores are all bounded at 30 days by a default nobody set. The
unbounded ones are all ours.

---

## 1. Store table

Size = measured `du -sk` 2026-08-10. "Compactor" = a mechanism that actually bounds it.
"Hot-path readers" = read at SessionStart / UserPromptSubmit / Stop / PostToolUse.

| Store | Size | Growth mode | Compactor? | Hot-path readers × frequency |
|---|---:|---|---|---|
| `~/.claude*/projects` (4 accounts, 7,956 transcripts) | **7,199.9 MB** | append-per-turn, +477 MB/day | ✅ CC `cleanupPeriodDays` default 30 (unset in settings.json) | tail-read by `waiting-recycle.sh` (256 KB/fire, PostToolUse[Bash]) · `boundary-handoff.sh`+`context-econ.sh` (2 MB/fire, Stop) · `dod-persist.sh` full `jq` scan (SessionStart + PreCompact) |
| `~/.claude/archives/claude-code` | 971.4 MB | manual, frozen | ❌ none | none |
| `/private/tmp/claude-501` (harness scratchpads) | **642.1 MB** | +810 MB/day (script's own measurement) | ⚠️ **built, staged, NEVER INSTALLED** | none |
| `~/.claude-versions` (2.1.113/114/183) | 596.6 MB | manual | ❌ none | `current` symlink → 2.1.114 (stable pin) |
| `~/.claude-{156,161,170,183,219,220}` frozen installs | 1,351.6 MB | manual, one dir per eval advance | ❌ none | 220 = **live binary this session**; 219/183 = documented rollback floors |
| `~/.claude/security/agent-sdk-venv` | 296.2 MB | one-shot venv | ❌ none | none |
| `~/.claude/autonomy` | 294.4 MB | mixed (see rows below) | partial | — |
| ├ `autonomy/postland/wt-run-86570` | 85.8 MB | a **git worktree inside a state dir** | ❌ none | postland-verify runner |
| ├ `autonomy/idl.jsonl` + `.chain` + 6 `.chain.*.gz` | 61.7 MB | append-only | ✅ `rotate-autonomy-logs.sh` @25 MiB, KEEP=8 | written by ~every hook (`lib/idl-log.sh`) |
| ├ `autonomy/pages` | 8.6 MB | append | ❌ none | — |
| ├ `autonomy/dod/*.md` (65 files) | 296 KB | **append-only by explicit design** | ❌ **none, and none wanted by its own header** | **`dod-persist.sh` injects the WHOLE file at every SessionStart**; `wrap-ledger.sh` + `completion-assert.sh` read at every Stop |
| `~/.claude/logs` (85 `.log`, 8 `.gz`) | 198.1 MB | append-only, 21 writers | ✅ `rotate-autonomy-logs.sh` hourly, 21 targets + `cc-relogin*` glob | `sessions.log` written at PreCompact |
| `~/.claude*/file-history` (4 accounts, 1,141 session dirs) | 284.4 MB | per-edit snapshots | ✅ CC 30-day (0 entries >30d, verified) | CC internal |
| `~/.claude/session-index.db` (+shm/wal) | 34.5 MB | per-session upsert, 3,017 rows | ❌ no VACUUM / no row retention | `session-index-start.sh` → **`python3 session-search.py --context-inject`, once per SessionStart** |
| `~/.claude/state/session-index.db.bak-2026-07-26` | **49.3 MB** | one-off, orphaned | ❌ none | none — **larger than the live DB it backs up** |
| `~/.claude/plan-history/plans` (606 versions, oldest 143d) | 27.9 MB | `plan-version-commit.sh` on every plan Write/Edit | ⚠️ `prune-plan-history.sh` exists, **launchd=0** | PostToolUse[Write\|Edit\|MultiEdit] |
| `~/.claude/backups` (648 entries, oldest 105d) | 26.2 MB | `backup-before-write.sh` on every overwrite | ⚠️ KEEP_PER_SOURCE=10 (per-source only, **no age bound**) | PreToolUse[Write\|Edit\|MultiEdit] |
| `~/.claude/mailbox` (**2,220 entries**) | 19.3 MB | 254 `.md` + 1,513 `.acked` + 155 `.seen` + 148 `.watching` + 92 `.wakefloor` + 8 stale `.lock` dirs | ❌ none for the sidecars | **`mailbox-drain.sh` at PostToolUse (empty matcher = EVERY tool call)**, UserPromptSubmit, SessionStart |
| `~/Library/Caches/claude-cli-nodejs` | 120.1 MB | CC-internal | ❌ none observed | CC internal |
| `~/.claude*/shell-snapshots` | ~16 MB | per-session | ✅ CC 30-day (0 >30d) | per Bash tool call |
| `~/.claude/watchdog/teardown` (1,578) · `cc-beats` (1,246) · `reap-guard` (1,199) · `state/operator-readout` (243) | ~17 MB | one file per event | ✅ effectively reaped (oldest 10–16d) | `session-beat.sh` at UserPromptSubmit **and** Stop |
| `~/.claude/plans-index.json` | 249 KB | append per plan | ❌ none | `setup-plan-symlinks.sh` at every SessionStart |
| `~/.claude/history.jsonl` (main) | 9.7 MB | append per prompt | ❌ none | CC ↑-history, not per-turn |
| `~/.claude-plans/_all` | symlink → `~/.claude/plans` (**0 files**) | — | n/a | `setup-plan-symlinks.sh` SessionStart |

**Total censused: 12,079.7 MB.**

---

## 2. Findings

### F1 — The largest-growth store has a finished reaper that was never installed
- **Finding:** `scripts/scratchpad-reaper.sh` is complete (liveness-first predicate, 48 h horizon) and its launchd job exists at `launchd/staged/com.claude.scratchpad-reaper.plist` with `StartInterval 21600` — but it is **not in `~/Library/LaunchAgents/`, and has zero executable call sites anywhere in the repo.**
- **Evidence:** `launchd/staged/` holds 3 plists; only `com.claude.relogin.plist` is installed. `grep -rn 'scratchpad-reaper\.sh' scripts hooks bin ~/Library/LaunchAgents` → 0 rows outside the script itself and `reaper-horizon-lint.sh`'s declaration list. The script's own header (`scripts/scratchpad-reaper.sh:4-8`) records the surface at **10.67 GB across 461 session dirs, growing ~810 MB/day, "its ONLY bound is a reboot"**.
- **Cost now:** 642.1 MB live (post-reboot). **23 of 42** worktree scratchpad dirs point at worktrees that no longer exist, holding **214.1 MB**. Two single dirs hold 237.5 MB + 205.9 MB.
- **Re-architecture:** install the staged plist. Nothing to design or build.
- **Sizing:** recovers 214 MB immediately, caps a +810 MB/day leak · effort **XS** · risk low (predicate already requires no-live-pid AND no-recent-transcript AND >48 h).
- **Existing mechanism:** `scratchpad-reaper.sh` + `launchd/staged/com.claude.scratchpad-reaper.plist` — **ACTIVATE, do not build.**

### F2 — A 29,922-byte file is injected verbatim into every session's context, uncapped, and is append-only by design
- **Finding:** `dod-persist.sh` at SessionStart emits the entire durable-DoD file as `additionalContext`. Measured on a dry-run with this repo's cwd: **30,114 B injected** (file = 29,922 B). No `head -c`, no line cap, no window — `grep -nE 'head -c|MAX|LIMIT|truncat' hooks/dod-persist.sh` returns only a `cut -c1-16` on a path hash.
- **Evidence:** `~/.claude/autonomy/dod/3cca03ed68356913.md`, 151 lines, 49 `## <ts>` blocks from 2026-07-19 to 2026-08-10 (**~2.2 appends/day**). The file's own header, written by the producer: *"INTEGRATE-only: each capture APPENDS below; history is never rewritten"* (`hooks/dod-persist.sh` → `persist_dod()`, `>>` only). It also fires at **PreCompact[auto]** (`settings.json`), so a compaction both appends a row and re-injects the whole file.
- **Cost now:** ~7,480 tokens per SessionStart per session. At 15 concurrent sessions ≈ **112K tokens of aggregate context** re-consumed on every restart/recycle wave, plus 30 KB written into each transcript (which the Stop/PostToolUse hooks then tail-read). Trajectory: +1.4 KB/day/repo, so ~150 KB/injection by November on current cadence.
- **Re-architecture:** cap the *injection* (not the file) — inject the last N `## ` blocks or `tail -c 4096`, and fold superseded Scope lines into one "current + prior N" head. The producer's INTEGRATE contract governs the **file**; nothing requires the **consumer** to read all of it.
- **Sizing:** −26 KB/session-start (−87%) · effort **S** (one `awk` in the emit path) · risk low (`wrap-ledger.sh`/`completion-assert.sh` already use `grep … | tail -1`, i.e. they only want the newest line).
- **Existing mechanism:** `hooks/lib/memory-index-budget.sh` already implements exactly this budget shape for MEMORY.md — **reuse it**, don't invent a second one.

### F3 — The Spotlight premise is refuted for our stores; the real index sits somewhere else
- **Finding:** every claude-infrastructure churn directory is **already excluded** from Spotlight by the dot-prefix rule. The 738 MB of resident indexer is driven by `~/Development`'s non-hidden tree.
- **Evidence:** `mdls` on `~/.claude/projects/*/*.jsonl` returns **15 attributes, all `kMDItemFS*`** (filesystem-derived); the control `mdls ~/Development/claude-infrastructure/README.md` returns **27**, including `kMDItemContentType`/`kMDItemKind` — i.e. no index entry for the hidden path. Content-search control: `mdfind -onlyin ~/.claude 'rotate-autonomy-logs'` → **0 hits**; same query in the visible repo → **38 hits**. `mdfind -onlyin ~/Development/.worktrees` (107 worktrees) → **0**. `mdutil -s -a`: indexing enabled on all volumes; **no `.metadata_never_index` / `.noindex` marker exists anywhere** — and none is needed for the dot-dirs.
- **Cost now:** `mds_stores` **537.2 MB RSS** + `corespotlightd` 97.8 MB + `mds` 55.6 MB + 4 workers ≈ **738.5 MB resident**. Indexed surface: `~/Development` = **4,938,949 items**, of which `claude-infrastructure` itself is only 1,788 — the mass is other repos' `node_modules`/build output.
- **Re-architecture:** `mdutil -i off ~/Development` (or a `.metadata_never_index` at `~/Development`). **No code depends on it**: `grep -rlE '\bmdfind\b|\bmdls\b|\bmdutil\b'` across `hooks/ scripts/ bin/ skills/` returns exactly one hit, `scripts/iterm2-perf-parity.sh` (a benchmark). Cursor/VS Code use ripgrep, not Spotlight.
- **Sizing:** plausibly several hundred MB of `mds_stores` RSS + the ongoing `mdworker` wake load · effort **XS** · risk low-medium (Finder/Alfred search over `~/Development` stops working — an operator preference, not a mechanism dependency).
- **Existing mechanism:** none needed — one `mdutil` call.

### F4 — The backup job protects the one store that is fully re-downloadable
- **Finding:** `com.chrisren.restic-claude-archive` (Saturday 02:00, B2, retention 7d/4w/12m/5y) backs up **`~/.claude/archives/claude-code/` and nothing else** — 971 MB of frozen npm tarballs of Claude Code 2.1.112 and 2.1.114.
- **Evidence:** `scripts/restic-claude-archive-backup.sh:2` — *"weekly restic snapshot of `~/.claude/archives/claude-code/`"*; `REPO="b2:${BUCKET}:claude-code-archive"` (line 57). No other source path appears.
- **Cost now:** transcripts (7.2 GB), `session-index.db`, all `memory/MEMORY.md` files, `autonomy/dod`, `autonomy/idl.jsonl` + its tamper-evident chain, `plan-history`, `backups`, and the backlog/decide stores are **unbacked**. `~/.claude/projects` is additionally on a 30-day auto-delete (F5), so it is the store with both the highest value and the shortest guaranteed life.
- **Re-architecture:** point restic at a curated set — `autonomy/{dod,idl.jsonl,idl.jsonl.chain}`, `projects/*/memory/`, `session-index.db`, `plan-history/`, `state/` — and **drop** `archives/claude-code` (recoverable with `npm i @anthropic-ai/claude-code@2.1.114`).
- **Sizing:** protects ~150 MB of irreplaceable state, drops 971 MB of replaceable state from every snapshot · effort **S** · risk low.
- **Existing mechanism:** `restic-claude-archive-backup.sh` — **repoint, don't rebuild.**

### F5 — Transcript retention works; the birth rate is what is moving
- **Finding:** a hard 30-day cliff exists and is CC's own `cleanupPeriodDays` default (**not set** in `settings.json` or `.claude.json`). It reaches `projects/` **including `subagents/` subdirs**, plus `file-history/`, `shell-snapshots/`, `todos/`.
- **Evidence:** age histogram over 7,956 transcripts — 29d bucket = 1,358 files, 30d = 111, **31d = 22, total >30d = 22 vs 7,791 ≤30d**. `file-history` >30d = 0/235; `shell-snapshots` >30d = 0/44; `todos` >30d = 0/4. Subagent transcripts: 4,808 files / 1,807.8 MB, of which >30d = 22 (the same 22).
- **Cost now:** 7.2 GB, but **birth rate is accelerating: 215 → 315 → 477 MB/day** (30d / 7d / 1d windows, measured by `-newerBt`). Steady state at the current rate = **30 × 477 ≈ 14.3 GB**, i.e. the store is only ~half-grown.
- **Re-architecture:** set `cleanupPeriodDays` **explicitly** (it is load-bearing and currently a vendor default that a CC upgrade could change silently); consider 14 days given the index and `file-history` already carry the recall path.
- **Sizing:** 30→14 days recovers ~4 GB and halves the ceiling · effort **XS** · risk medium (destroys resume/forensic reach — coordinate with the `limit-recover` and `lead-crash-watchdog` transcript readers).
- **Existing mechanism:** vendor setting; nothing of ours to change.

### F6 — 2.92 GB of Claude Code binary copies; the rollback ladder needs four of them
- **Finding:** eight parallel copies of the binary. **Live:** `.claude-220` (this session's `ps -o command=` resolves to `~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`). **Ladder per `MANIFEST.jsonl`:** 220 → 219 → 183 (=2.1.215) → `.claude-versions/2.1.114` (stable pin, `current` symlink).
- **Evidence:** `~/.claude-versions/current -> 2.1.114`; MANIFEST entries for 207/215/219/220 each name their rollback target. `.claude-156/161/170` appear only 2× each in launcher greps.
- **Cost now:** 1,351.6 MB (`.claude-NNN`) + 596.6 MB (`.claude-versions`, incl. superseded 2.1.113 at 195 MB) + 971.4 MB (`archives/claude-code`, which duplicates 2.1.114 as both tarball and unpacked tree) = **2,919.6 MB**.
- **Re-architecture:** keep 220 · 219 · 183 · versions/2.1.114. Retire `.claude-156/161/170` and `versions/2.1.113`. Keep `archives/` only until F4's repoint lands (it is currently the restic subject).
- **Sizing:** ~820 MB recoverable now, ~1.8 GB after F4 · effort **XS** · risk low (`npm i @anthropic-ai/claude-code@<v>` recreates any of them).
- **Existing mechanism:** `~/.claude-versions/MANIFEST.jsonl` already encodes the ladder — add a retire rule to it.

### F7 — The mailbox store is drained on every tool call and its sidecars are never pruned
- **Finding:** `mailbox-drain.sh` is wired at **PostToolUse with an empty matcher (every tool call)**, plus UserPromptSubmit and SessionStart. The directory it walks has **2,220 entries**.
- **Evidence:** `settings.json` PostToolUse `[]` → `mailbox-drain.sh post-tool`. Composition: 254 `.md` inboxes · **1,513 `.acked`** · 155 `.seen` · 148 `.watching` · 92 `.wakefloor` · 10 `.posttool` · 9 `.forward` · **8 stale `.lock` dirs, oldest 2026-07-20 (21 days)**. Largest inbox 2.50 MB, second 1.33 MB.
- **Cost now:** 19.3 MB and a 2,220-entry `readdir` on the hottest hook event in the system, ×15 sessions × every tool call. The `.acked` cursors outlive their panes by design accident — nothing deletes them.
- **Re-architecture:** shard by pane UUID prefix (`mailbox/<xx>/<uuid>.*`) or move terminal-state sidecars to `mailbox/archive/` on pane death; break the stale `.lock` dirs at the existing reaper. Cheapest first cut: prune `.acked`/`.seen`/`.watching`/`.wakefloor` whose pane has no `cc-registry` row.
- **Sizing:** −1,900 dir entries off the hottest path · effort **S** · risk low (sidecars are cursors; a missing one re-delivers at most once).
- **Existing mechanism:** `mailbox/archive/` already exists (2 files) — extend the archiver, don't add a reaper.

### F8 — Log rotation coverage is now good; the residual hazard is the launchd-owned files
- **Finding:** `rotate-autonomy-logs.sh` runs hourly (`com.claude.log-rotation`, `StartInterval 3600`) over **21 named targets plus a `cc-relogin*.log` glob**, at 25 MiB / KEEP=8. Last runs: `rotated=0 skipped=25 seal=ok` — i.e. every target is currently under threshold. `cc-reaper.log` (22.1 MB) and `teammate-checkpoint.log` (22.8 MB) are approaching it.
- **Evidence:** `scripts/rotate-autonomy-logs.sh:324-345` (DEFAULT_TARGETS), `:316-323` (the audit that took it from 3 targets to 21), `logs/log-rotation.out.log` tail.
- **Cost now:** 198.1 MB total, of which **85.9 MB is the 8 retained `.gz` rotations** of `bash-commands.log` / `bash-execution.log` (6.5–20.3 MB each). KEEP=8 on a pair of 25 MiB logs is the dominant term, not the live files.
- **Residual hazard:** the script rotates by *rename + recreate*, which is safe **only** for writers holding no persistent fd. The `cc-relogin*` glob matches `cc-relogin-poll.out.log` / `.err.log`, which **are** launchd `StandardOutPath`/`StandardErrorPath` targets. launchd re-opens per job invocation, so the exposure is bounded to a rotation landing mid-run — but it is a real, undocumented seam. (11 other `~/.claude/logs/*.{out,err}.log` files are launchd-owned and correctly absent from the target list.)
- **Sizing:** dropping KEEP 8→4 on the two bash logs recovers ~43 MB · effort **XS** · risk low.
- **Existing mechanism:** `rotate-autonomy-logs.sh` — tune `ROTATE_KEEP`, and either drop the `cc-relogin*` glob or `launchctl kickstart -k` those jobs after rotating them.

### F9 — Stale one-off artifacts that no mechanism owns
| Artifact | Size | Why it exists | Verdict |
|---|---:|---|---|
| `~/.claude/state/session-index.db.bak-2026-07-26` | **49.3 MB** | one-off pre-migration copy | **larger than the 34.5 MB live DB**; nothing reads it |
| `~/.claude/autonomy/postland/wt-run-86570` | **85.8 MB** | a real git worktree (`git worktree list` row, detached HEAD) living inside a state dir | per-run worktree, never removed |
| `~/.claude/projects/-private-tmp-memprobe-row9/memory/MEMORY.md` | **800,017 B** | a memory-budget test fixture | **32× the 24,985 B loader limit**, left in the LIVE memory store |
| `~/.claude/security/agent-sdk-venv` | 296.2 MB | python venv for the security skill | rebuildable in one command |
| `.premirror-bak` files/dirs across the 4 account dirs | ~9 MB, ~60 entries | config-mirror safety copies | no pruner; `settings.json.*.bak` ×14 in one account |
| `~/.claude/backups` oldest entry | 105 days | `KEEP_PER_SOURCE=10` bounds *per source*, not by age | add an age arm |
| `~/.claude/plan-history/plans` oldest entry | 143 days, 606 versions | `prune-plan-history.sh` exists, **launchd=0** | schedule it |

### F10 — `session-index.db` is 34.5 MB for 4.7% search coverage
- `sessions` = **3,017** rows; `sessions_fts` / `sessions_fts_content` / `sessions_fts_docsize` = **142** each. `session_chunks` / `chunks_fts` = 509. `search_log` = 580.
- So the full-text path — the thing `session-search.py --context-inject` runs at **every SessionStart**, via a `python3` process start — indexes 4.7% of the sessions it holds rows for. No `VACUUM`, no row retention: rows outlive the 30-day transcripts they point at.
- Re-architecture: retention-align the `sessions` table to `cleanupPeriodDays`, backfill or drop the FTS tables, `VACUUM`. Effort S, risk low.

---

## 3. Question (c) — hot-path readers × frequency × 15 sessions

Per-fire read sizes measured; multiply by axis F's fire counts.

| Event | Store read | Bytes/fire | Fires |
|---|---|---:|---|
| SessionStart | **`autonomy/dod/<hash>.md` → injected verbatim** | **29,922** | 1 × session (+1 × PreCompact) |
| SessionStart | `session-index.db` via `python3 session-search.py` | 34.5 MB DB, indexed query + interpreter start | 1 × session |
| SessionStart | `plans-index.json` | 249,454 | 1 × session |
| SessionStart | 11 other hooks' combined `additionalContext` | 1,075 | 1 × session |
| SessionStart (harness) | `MEMORY.md` — **capped 24,985 B, tail silently dropped** | 24,985 of 26,382 | 1 × session |
| SessionStart (harness) | `~/.claude/CLAUDE.md` + project `CLAUDE.md` + `.claude/CLAUDE.md` | 59,116 + 58,153 + 2,167 | 1 × session |
| UserPromptSubmit | `mailbox/` readdir (2,220 entries) + own inbox | dir walk | every prompt |
| UserPromptSubmit | `cc-beats/` write + `MEMORY.md` `wc -c`/`grep -c` (memory-nudge) | 26,382 read | every prompt |
| Stop | transcript tail via `context-econ.sh` (`CC_CE_TAIL_BYTES` default **2,000,000**) | up to 2 MB | every turn |
| Stop | `wrap-ledger.sh` (called by `operator-readout.sh`, `completion-assert.sh`, `session-continue.sh`, `boundary-handoff.sh`, `anti-deference-nudge.sh` — **5 Stop hooks**) reads `autonomy/dod`, `autonomy/backlog.jsonl`, `autonomy/decisions`, live git | — | every turn ×5 |
| PostToolUse[Bash] | transcript tail via `waiting-recycle.sh` (`TAIL_B` default **262,144**) + `jq` | 256 KB | every Bash call |
| PostToolUse[*] | `mailbox/` drain — **empty matcher = every tool call** | dir walk of 2,220 | every tool call |
| PreToolUse[Write\|Edit] | `backups/` write + per-source prune | file copy | every write |
| PostToolUse[Write\|Edit] | `plan-history/` version commit + `plans-index.json` update | 249 KB | every plan write |

**Per-session-start context tax from stores: 174,143 B ≈ 43.5K tokens.**
**× 15 sessions ≈ 2.6 MB ≈ 652K tokens of aggregate context**, re-paid on every restart, recycle,
and compaction. The DoD injection (29,922 B) is the only one of these with **no cap at all** —
it is already 20% larger than the entire MEMORY.md budget and grows ~1.4 KB/day.

---

## 4. Question (f) — the MEMORY.md incident, generalized: every byte-capped loader

The incident: a 26,382 B `MEMORY.md` against a 24,985 B limit → **1,397 B silently dropped**, and
the dropped bytes are the *tail* — the newest entries. Live and unresolved at measurement time.

| # | Loader | Cap | Failure mode | Verdict |
|---|---|---:|---|---|
| 1 | `MEMORY.md` (harness) — `hooks/memory-nudge.sh:87`, `hooks/lib/memory-index-budget.sh:104` | 24,985 B | tail dropped; a nudge warns but the drop is real | **live breach: 26,382 B, 1,397 B lost** |
| 2 | `dod-persist.sh` SessionStart injection | **none** | opposite failure — injects everything, forever | **the inverse defect; F2** |
| 3 | `hooks/qos-rewrite.sh:108` — `INPUT=$(head -c 200000)` on hook stdin | 200 KB | a >200 KB `tool_input` is truncated → the QoS decision is made on a partial payload, and JSON parse of a truncated body fails **silently** (`|| exit 0`) | audit: does it fail-open? |
| 4 | `hooks/coldcompile-admit.sh:75` — same idiom | 200 KB | same | same |
| 5 | `lib/context-econ.sh:328` — `CC_CE_TAIL_BYTES` 2 MB | 2 MB | scans transcript tail only; **has a documented tail-MISS fallback to full read** | ✅ correct pattern |
| 6 | `hooks/waiting-recycle.sh:697-727` — `TAIL_B` 262,144 | 256 KB | tail only; **falls back to full `jq` when file > TAIL_B and tail missed** (`:727`) | ✅ correct pattern |
| 7 | `hooks/lead-crash-watchdog.sh:303` `tail -c 16000`, `:1003` `tail -c 65536` | 16/64 KB | crash forensics see only the tail | acceptable |
| 8 | `lib/session-index-helpers.sh` — `[:5000]`, `[:2500]`, `[:500]`, `[:400]` (7 sites) | 400–5,000 chars | search summaries truncated; compounds with the 4.7% FTS coverage (F10) | audit |
| 9 | `hooks/session-index-sweep.sh:143` — `head -c 500` first_prompt | 500 B | first-prompt recall truncated | acceptable |
| 10 | `hooks/anti-deference-nudge.sh:106` — `cut -c1-240` | 240 chars | nudge message truncated | acceptable |
| 11 | `hooks/cc-permission-beacon.sh:169,183` | byte cap | emits `tool_input_truncated:true` + `"<omitted: over byte cap>"` | ✅ **the reference pattern — the drop is a structured, parseable token** |

**Rule this yields:** a loader with a cap must emit a *token* saying it truncated (row 11), or a
*fallback* to the full read (rows 5–6). Rows 1, 3, 4, 8 do neither. Row 2 has no cap at all.

---

## 5. Adversarial pass

Three gaps I went back and measured rather than assumed.

**"You measured disk. The bottleneck is RAM. Prove the link, or say you can't."**
Three links survive; one does not.
- ✅ **Spotlight** — 738.5 MB resident, measured from `ps -Ao rss,comm`. Real RAM, and reducible. But (F3) it is *not* driven by our stores.
- ✅ **Context tax** — 174 KB per session start, ×15 sessions. This is token memory, not host RAM; I am not claiming it frees a byte of the 64 GB. It matters because it inflates every transcript by that much, and transcripts are exactly what the Stop/PostToolUse hooks tail-read at 256 KB–2 MB per fire.
- ✅ **Transient RSS per fire** — a `jq` over a 2 MB tail, a `python3` interpreter start per SessionStart, a `sqlite3` open on a 34.5 MB DB. Axis F owns the fork bill; my contribution is *which stores are large enough to make those reads expensive*, above.
- ❌ **Page cache** — `vm_stat` shows 1,443,593 inactive pages (23.6 GB at 16 KB) and swap 0. Inactive pages are reclaimable on demand, so I will **not** claim the 7.2 GB of transcript churn is costing resident memory. Unproven; do not use it as an argument.

**"Is the 30-day retention real, or did you infer it from a coincidence?"**
Measured, not inferred (F5): a genuine cliff at 7,791 ≤30d vs 22 >30d, with the 29d bucket at
1,358 files. And it reaches the `subagents/` subdirectories (4,808 files, 1.8 GB) — which was the
specific thing I expected it to miss, since those are nested a level deeper. It doesn't miss them.
The finding this *changes*: the transcripts store is **not** the runaway; it is bounded and only
half-grown. The runaway is `/private/tmp/claude-501` (F1).

**"You want to delete 2.9 GB of binaries — prove none of it is load-bearing."**
`ps -o command= -p $PPID` shows this very session executing from `~/.claude-220`. The MANIFEST
names 219 and 183 as the rollback floors and `versions/current → 2.1.114` as the stable pin.
That is four dirs that must stay; the reclaim in F6 is scoped to the other four. Had I not
checked, the obvious cut (`.claude-220`, newest-looking) would have been the live binary.

**Fourth thing a hostile reviewer would still say, and I concede it:** I have not measured whether
installing the scratchpad reaper (F1) races a live session that is *writing* into its scratchpad —
the predicate requires no-live-pid AND no-recent-transcript AND >48 h, which reads sound, but I
did not exercise it. Do not install it blind; run it once with `--dry-run` (if it has one) or
against a copied tree first.

---

## 6. Blockers / uncertainties

- **`mds_stores` on-disk size unmeasured** — `/System/Volumes/Data/.Spotlight-V100` needs sudo; the sandbox denied it. The 537 MB figure is **RSS**, not index size. The brief's "445MB mds_stores" is consistent with an RSS reading.
- **`cleanupPeriodDays` default value is vendor-documented, not read from disk** — the key is absent from both `settings.json` and `.claude.json`. The 30-day behaviour is *measured*; attributing it to that specific default is inference.
- **`~/Library/Caches/claude-cli-nodejs` (120 MB)** — CC-internal; I did not determine what writes it or whether it self-prunes.
- **`cc-relogin*` glob vs launchd fd (F8)** — I did not observe a rotation landing mid-run, so the hazard is reasoned from the create-mode contract, not witnessed.
- **`prune-backups.sh` / `prune-plan-history.sh` / `gate-cleanup.sh` / `branch-reaper.sh` / `ship-backup-reap.sh` all show `launchd=0`** with in-repo callers — they may run from a dispatcher rather than launchd. I did not trace their invocation paths; axis B owns the scheduler census.

---

## 7. Handoff to other axes

- **F** (hook economics): per-fire read sizes are in §3 — 2 MB `context-econ` tail on Stop, 256 KB `waiting-recycle` tail per Bash call, 2,220-entry mailbox readdir per tool call, one `python3` start per SessionStart.
- **B** (scheduled compute): `com.claude.scratchpad-reaper` is **staged, not installed** (F1); `com.claude.lead-reconciler` likewise. Five pruners show launchd=0.
- **D** (worktrees): 23 orphaned scratchpad dirs (214 MB) correspond to removed worktrees — a pane-death signal both axes want; and `autonomy/postland/wt-run-86570` is an 86 MB worktree that `git worktree list` reports but no GC owns.
- **J** (prior art): `scripts/scratchpad-reaper.sh:4-8` and `scripts/rotate-autonomy-logs.sh:316-323` are the two best-documented store audits already in the repo. Neither needs redoing; one needs installing.

---

# Addendum — Wave-2 steer (lead, 2026-08-10)

Spotlight sub-question **DROPPED**. Two independent measurements agree it is falsified:
`CONCURRENCY_PROGRAM.md:1650-1652` (*"`~/Development/.worktrees` returns 0 indexed files … Disk
and FS are not capacity variables on this box"*) and my §F3 (`mdls` 15 vs 27 attributes; `mdfind`
0 vs 38 hits). §F3 stands as recorded, and is **not** a recommendation. Disk totals in §1 are
therefore inventory, not a capacity argument — the load-bearing findings are all **read cost** and
**enforcement**, below.

## 8. The enforcement frame

Only four things on this box ENFORCE: `~/Library/LaunchAgents/*.plist` + `launchctl` (schedule),
`~/.claude/settings.json` (hook wiring), `~/.claude/bin` + PATH (which binary runs), and the live
symlink revision. Everything else — a manifest, a queue, a plan, a `docs/` file — is **advisory
behind a diode**. Each recommendation below names the edge it must cross.

### F11 — The store-bounds ratchet is built, correct, currently reading BREACH, and nothing runs it
- **Finding:** `scripts/store-bounds-census.sh` + `config/store-bounds.manifest` +
  `tests/store-bounds.bats` (317 / 47 / 363 lines) all exist on trunk. Run live just now it
  **exits 1 = BREACH**. It has **zero launchd plists, zero hook entries, zero script call sites.**
- **Evidence:** `grep -rn 'store-bounds-census' ~/Library/LaunchAgents/*.plist hooks/ scripts/ bin/`
  → 0 rows outside the script itself. Live run (rc read directly, not through a pipe): `rc=1`,
  `declared stores: 10 · total measured: 169.0 MB · breaches: 2` —
  `state/session-index.db.bak-* 49.4/1MB` and `logs/cc-reaper.log 22.1/16MB`.
- **What this changes about my §F9:** the 49.3 MB stale DB backup I filed as "no mechanism owns it"
  **is already declared, already over cap, and already has a named owner (row 9) and remedy.** The
  gap was never detection. It is that the detector is unscheduled — so the ratchet has been
  silently correct for 11 days.
- **The trap this creates for the rest of this report:** adding manifest rows for the mailbox, the
  backlog, `plan-history`, `backups` **while the census stays unscheduled produces more undetected
  breaches, not more safety.** Order is load-bearing: schedule first, declare second.
- **Enforcing-store edge:** `~/Library/LaunchAgents/com.claude.store-bounds.plist` + `launchctl
  bootstrap`. No such plist exists in `launchd/` **or** `launchd/staged/` (which holds exactly three:
  `lead-reconciler`, `relogin`, `scratchpad-reaper`) — so unlike F1 this one is not merely un-run,
  it is **unwritten**. Cheapest correct edge: add a `CC_STORE_BOUNDS` step to the existing
  `com.chrisren.cc-reaper` sweep, the same pattern `13-mailbox-gc` already uses — one new plist
  avoided.
- **Sizing:** turns 10 declared bounds from prose into a page · effort **XS** · risk **none by
  construction** (the census never deletes, rotates or truncates — a tested property, `:10-16`).

### F12 — `backlog.jsonl` is event-sourced with no snapshot, so every Stop re-folds 7,097 events to answer a question about 102
- **Finding:** the 92%-of-turn-end-lag call (`scaling-bottlenecks-2026-08-09.md:39-41`) is not slow
  because the store is 2.1 MB. It is slow because the store is a **log, not a state**, and
  `list --blocked` folds the entire history on every read through **60 `jq` call sites**.
- **Evidence (measured now):** `~/.claude/autonomy/backlog.jsonl` = **2,120,703 B / 7,097 events /
  1,534 distinct ids**, span 2026-07-18 → 2026-08-10 (23 d) ⇒ **308 events/day, 90 KB/day**.
  Event mix: `claim` 2026 · `add` 1534 · `reopen` 1358 · `done` 1233 · `block` 663 · `unblock` 277 ·
  `link` 6. Folded state: **`done` 1197 · `open` 233 · `blocked` 102 · `claimed` 2**.
  Timed `cc-backlog list --blocked --json`, n=3: **3.61 s · 4.13 s · 5.90 s** — independently
  reproducing the cited 3.7 s p50 / 7.7 s p90.
- **The compaction ratio, stated as the design:** **78% of folded items are terminally `done`**
  (1197/1534). Their events — roughly `add`+`claim`+`done` each, ≈4,800 of 7,097 (**68%**) — can
  never change the answer to `--blocked`. A fold-to-snapshot (`backlog.snapshot.json` = current
  state, + only events written since its watermark) cuts the read to the ~2,300 live-item events
  and, at 90 KB/day, keeps it there. This is ordinary event-source compaction, not a new idea;
  `rotate-autonomy-logs.sh`'s IDL **epoch** pattern (seal → archive → genesis record naming the
  closed epoch's final `{seq,head}`) is the same shape already implemented in this repo, and a
  snapshot watermark is its exact analogue. **Reuse that vocabulary.**
- 🚨 **The manifest cannot express this bound, and saying so is the finding.** The manifest's
  format is `<glob>|<max_mb>|<owner-row>|<remedy>` — **megabytes only**. The cost here is
  `O(events) × jq forks`, and 2.1 MB is trivially under any sane MB cap, so a naïve row would be a
  **page that never fires**. Two honest options: (i) declare a *deliberately tight* cap as a
  **proxy for event count** — `autonomy/backlog.jsonl|4|5|compact: fold terminal (done) items to a
  snapshot` — which at 90 KB/day fires in **22 days**, and label it in the remedy text as a
  byte-proxy for a fold-time bound; or (ii) extend the census with a second unit. **Take (i).**
  Option (ii) adds a threshold nobody has calibrated, which is exactly the defect the census's own
  header forbids (*"an uncalibrated number in a verdict"*, `:29-31`).
- **Enforcing-store edge, in two parts:** the *compaction* lands in `bin/cc-backlog` (a per-file
  symlink into the checkout ⇒ landing == deploying for this file, no activation). The *fold removal
  from the Stop path* — the ~3.4 s/turn — lands in `hooks/operator-readout.sh:702,749`, also
  symlinked. **Neither needs a C10 activation.** The manifest row is advisory until F11 ships.
- **Sizing:** −3.4 s felt lag per turn-end × every turn × 15 sessions · effort **S** for the
  Stop-path cache, **M** for snapshot compaction · risk low (the log is append-only and preserved;
  the snapshot is derived and rebuildable — never delete the log, per
  `memory/append-only-store-safety-rules.md`, the `mv -f` that destroyed 1,461 lines).

### F13 — The mail strand is 14,773 lines, 90% of it in two boxes, and its fix is a staged migration
- **Finding:** measured now — **14,773 unacked lines** (the map's 14,763 + 10 since). It is **not**
  diffuse: `D40A5752…` holds **8,294** and `D5D419C8…` **5,010** — **13,304 = 90.1% in two
  inboxes**, 13,995 = 94.7% in three. The remaining 251 boxes hold 778 lines between them.
- **Root cause is unchanged and confirmed at code level:** senders are pane-keyed and
  `mailbox_resolve_key` (`hooks/lib/mailbox-pending.sh:565`) has **no sender call site** — its only
  live caller is `hooks/session-continue.sh:214-215`, a *reader*. `hooks/mailbox-drain.sh:128`
  states it in the tree: *"all pane-keyed … and none of them calls `mailbox_resolve_key`, so mail
  lands in"* the unwatched key.
- ⚠️ **Correction to the steer:** the arming migration is **`0007-mailbox-wake-arm-registration.sh`**,
  not 0006 (`0006` is `coldcompile-admit-registration`). `GROUND_UP_REBUILD_MAP.md:19` says "0006";
  the tree says 0007. The map's number is stale — cite the tree.
- **Its status:** `~/.claude/autonomy/migrations/staged/0007-mailbox-wake-arm-registration.json`.
  The ledger's `applied/` bucket holds **exactly one** file (`0001-migrations-ledger-scaffold`);
  **0002 through 0008 are all staged** — i.e. seven consecutive C10 migrations landed and none ran.
  Separately, `pending-activation` is 45 staged / 38 done / **7 un-run**, and one of the seven is
  **`13-mailbox-gc-activate.sh`** — the sweep that archives dead-owner boxes, quarantines dead
  letters, and reaps orphan cursors. That is the fix for my §F7 (2,220-entry mailbox, 1,513 `.acked`
  sidecars) and it is written, tested, gated behind `CC_REAPER_MBXGC=1`, and **off**.
- **Two distinct problems, two edges** — do not conflate them:
  | | Problem | Fix | Enforcing edge |
  |---|---|---|---|
  | delivery | 14,773 lines under an unwatched key | migration **0007** (registers `mailbox-wake-arm.sh` as a SessionStart hook) | **`~/.claude/settings.json`** — C10, operator-run |
  | store growth | 2,220 dir entries, 1,513 orphan cursors, 8 locks ≥21 d | activation **13-mailbox-gc** (`CC_REAPER_MBXGC=1`) | **`~/Library/LaunchAgents/com.chrisren.cc-reaper.plist`** — C10, operator-run |
- **Sizing:** delivery fix unblocks 14,773 stranded lines · GC removes ~1,900 dir entries from the
  **hottest hook path in the system** (`mailbox-drain.sh` at PostToolUse with an empty matcher =
  every tool call) · effort **XS each — both are one operator command** · risk: the GC's own header
  records it sweeping the live mailbox (46 boxes) when run un-gated from a suite, which is precisely
  why it is opt-in; running it via launchd is the sanctioned path.

### F14 — MEMORY.md: the cap silently drops 5 entries, but 163 topic files were never indexed at all
- **Finding:** the cap breach is the smaller half of the problem by 30×.
- **Evidence:** live file = **26,382 B** vs the 24,985 B loader limit (`hooks/memory-nudge.sh:87`),
  **1,397 B over**. Counting entries whose byte offset falls at/after the limit, **5** index lines
  are silently unloaded (the steer said 4; the exact count is 5):
  `invariant-can-live-in-an-absent-token` · `restore-to-snapshot-pins-the-fault` ·
  `abstain-belongs-on-the-branch-the-case-reaches` ·
  `capture-based-probe-cannot-exercise-a-tty-gated-verb` ·
  `guard-universalization-deletes-a-capability-silently`.
  **But:** the memory dir holds **268 topic files** against **105 index entries** (105 distinct
  links, 0 dangling) ⇒ **163 topic files — 61% — have no index line at all** and are unreachable
  whatever the cap does.
- **Why this matters more than the 5:** the 5 are *newest-first* (the cap eats the tail, which is
  where the freshest lessons land) and are recoverable by compaction. The 163 are invisible to
  every reader and to the nudge itself, which measures only `grep -c '^- \['` — **the hook counts
  what is indexed and is structurally blind to what is not.** A compaction pass that shortens the
  105 to fit the cap will make the file *quieter* while leaving 61% of the corpus unreachable.
- **Re-architecture:** (1) shorten to fit — `/compact-memory` exists for exactly this and is
  human-gated; (2) add an **orphan count** to `memory-nudge.sh` beside the byte count (one `comm`
  over `ls *.md` vs the extracted links) so the blindness is measured, not assumed; (3) treat the
  cap as a **budget with a stated eviction policy** rather than a silent tail-drop — the
  `cc-permission-beacon.sh:169,183` pattern (emit `truncated:true` + a parseable token) is the
  in-repo reference, per §4 row 11.
- **Enforcing-store edge:** the file itself is the store and the harness is the loader — **there is
  no C10 here**; the index shortening is an ordinary edit, and the orphan-count addition lands in
  `hooks/memory-nudge.sh`, a per-file symlink (landing == deploying). This is the one
  recommendation in this addendum with **no activation dependency at all** — do it first.

## 9. Ordered recommendations, each with its edge

| # | Action | Effort | Edge that makes it real | Blocked on |
|---|---|---|---|---|
| 1 | MEMORY.md: compact 105 index lines under 24,985 B **and** add the orphan count to `memory-nudge.sh` | XS | file + symlinked hook — **landing == deploying** | nothing |
| 2 | Take `cc-backlog list --blocked --json` off the Stop path (cache/async) | S | `hooks/operator-readout.sh` — symlinked | nothing |
| 3 | Schedule `store-bounds-census.sh` — fold into the existing `cc-reaper` sweep | XS | **`~/Library/LaunchAgents`** + `launchctl` | C10 operator |
| 4 | Run activation **13-mailbox-gc** (`CC_REAPER_MBXGC=1`) | XS | **`com.chrisren.cc-reaper.plist`** | C10 operator |
| 5 | Run migration **0007** (mailbox wake-arm) — and triage why 0002–0008 are all staged | XS | **`~/.claude/settings.json`** | C10 operator |
| 6 | Install `com.claude.scratchpad-reaper.plist` (§F1) | XS | **`~/Library/LaunchAgents`** | C10 operator; **dry-run first** |
| 7 | `cc-backlog` snapshot compaction (fold `done` to a watermark) | M | `bin/cc-backlog` — symlinked | after #2 |
| 8 | Add manifest rows: `autonomy/backlog.jsonl\|4\|5\|…` (byte-proxy, stated as such) · `mailbox/*.acked\|2\|-\|…` · `plan-history/plans\|32\|-\|…` · `backups\|32\|-\|…` | XS | `config/store-bounds.manifest` — **advisory until #3** | **#3** |

**The pattern across 3–6:** four separate, finished, tested mechanisms are each one operator
command from working. Seven migrations and seven activations are staged; `applied/` holds one file.
The recurring failure on this box is not missing mechanism — it is **the C10 gap between a landed
mechanism and the enforcing store**, which is the same shape as `memory/conclusion-must-reach-the-enforcing-store.md`.
Recommendation to lead: the highest-leverage single item is not any one of these — it is a
**platter that collapses 3–6 into one `cc-do` invocation**, since all four are `launchctl`/settings
edits the operator must own and none is individually worth a round-trip.

## 10. Adversarial pass — wave 2

**"Your #1 fix (MEMORY.md compaction) shrinks the file and hides the 163 orphans. You'd be making it
worse."** Conceded, and it is why #1 is stated as *two* actions, not one. Compaction alone lowers
the byte count, silences the nudge, and leaves 61% of the corpus unreachable — a quieter, equally
broken store. The orphan count is the half that must land in the same change.

**"You timed `cc-backlog` three times on a loaded box and called it 92%."** I did not derive the
92% — `scaling-bottlenecks-2026-08-09.md:39-41` did, and I reproduced only the *latency*
(3.61/4.13/5.90 s vs its 3.7 p50 / 7.7 p90) as a consistency check. n=3, no idle control, load
uncontrolled. The **fold ratio** (68% of events belong to terminally-`done` items) is the number my
design rests on, and it is a property of the store, not of the box.

**"Adding manifest rows is what you were asked for; you're recommending against it."** Not against —
**after**. A declared bound with no scheduled reader is a comment. The manifest's own header argues
the class-fix over eight spot-fixes and it is right; F11 just shows the class-fix itself never
reached an enforcing store. Rows without #3 would repeat the exact error one level up.

**Third gap I went looking for and found:** I assumed the mail strand was diffuse across 254
inboxes and would need a per-box policy. It is not — **90.1% is two boxes.** Which means the
delivery fix (0007) and the GC (13) are genuinely independent: the GC would archive 250-odd tiny
dead boxes and barely touch the strand, and 0007 would fix addressing without reducing the 2,220
dir entries. Shipping either alone leaves the other problem fully intact.

**Still unverified, stated as such:** why `applied/` holds only 0001 while 0002–0008 sit staged — I
did not read `scripts/deploy-migrations.sh` or run `--status`, so I cannot say whether these are
awaiting the operator by design or silently failing to a bucket that is empty for a different
reason. Axis B or J should close that; it is the difference between "seven pending operator steps"
and "a broken migration runner", and those have opposite fixes.
