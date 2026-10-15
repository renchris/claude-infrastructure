---
status: in-progress
---

# Load reduction and UserPromptSubmit hook timeouts (2026-10-11)

Scope (frozen): stop the UserPromptSubmit hook timeouts at their root, restore the claude-accounts board `live` column, surface the 5h reset time on the board when 5h >= 80%, and reduce machine load — never by killing or pausing session work. Delivered as Wave 1 (WP1-WP6) landed + converged, WP7 sent to its branch owner, operator steps O1-O6 filed.

Design and evidence: `docs/research/load-hook-timeouts-2026-10-11/DESIGN.md` (ranked items, file:line sites, verify recipes; `<\task-notification>` there means the literal `<task-notification>` tag), `investigations.json` (6 verified investigations, adversarial verdicts), `census-prototype.py` (KERN_PROCARGS2 census, 0.16 s for 41 procs at load ~480 where `ps -wwEo` never finished).

## Phase 0 — Agent Team Orchestration

- **Execution locus per wave:** Wave 1 = **L+Workflow** — the operator invoked ultracode, so the recycled lead runs one Workflow with one `isolation: 'worktree'` code-writing slot per WP (default agent, not workflow-lean), then lands the branches itself one at a time. Wave 2/3 = **S** (dispatched handoff sessions), only after Wave 1 is converged and O5's exec trace has run. Wave 4 (Stop hooks) = **S**, one dispatched session, with the four hooks done lead-inline (**L**) inside it: all four share `scripts/wrap-ledger.sh` and `hooks/lib/`, and their suites misreport when run inside a teammate (assignee guards read the runner's ancestry).
- **Lead context budget:** keep ≥50% free; the lead only reviews diffs, lands, converges and files. Succession point: after Wave 1 converges, or at 60% fill, whichever is first.
- **Load etiquette for every slot (machine at load ~400-600):** run only the bats files your WP names, never the full suite; no `ps -A`/`ps -ax` in new code; never kill/signal anything.

## Root cause (one paragraph)

All hooks of one event run in parallel, so a prompt waits on the slowest. 3 of 7 prompt hooks cause all 162 cancels in 40 min: `handoff-intent-nudge` (95) runs a full-table argv `ps -axo pid=,ppid=,command=` (via `hooks/lib/agent-identity.sh:51` `agent_is_assignee`) BEFORE its cheap intent grep; measured 559 s once during a `ps` wave. `mailbox-drain` (39) and `memory-nudge` (28) are fork-heavy (40-75 forks/prompt). The same full-table walk underlies the Stop-hook cancels (~1,130 of 1,490). Full-table `ps` comes in waves where it blocks uninterruptibly for minutes (Claude Code 2.1.293 itself spawns `ps -A` and leaves timed-out children; 224 orphans under launchd seen), while `pgrep` (sysmond XPC) and single-pid `ps -p` stay fast. The board's `live ?` is the same: `concurrency()` `ps -wwEo` times out every sweep since 01:04 UTC; `subprocess.run` then blocks on the stuck child, and `heal()` refuses token refreshes too (login risk). Steady load (~370-400) is runnable work + ~29k spawns/min, not the `ps` pile; hooks are ~20-24% of spawns, ~21k/min are unattributed (O5).

## Wave 1 — work packages (disjoint files; full detail in DESIGN.md "Ranked items")

| WP | Files owned | Item | Status |
|---|---|---|---|
| WP1 | `hooks/handoff-intent-nudge.sh`, `tests/handoff-intent-nudge-fastpath.bats` (new) | jq parse; exit on `<task-notification>` prompts; intent grep BEFORE assignee check | **DONE** `a52745362` `faff4ae23` — live; 10/10 on trunk |
| WP2 | `hooks/lib/agent-identity.sh`, `hooks/teammate-auto-shutdown.sh`, `tests/agent-identity-walk.bats` (new) | per-hop `ps -o … -p` ancestry walk feeding the unchanged awk; seam `CC_WF_PSTABLE_FILE` unchanged | **DONE** `51a821560` `f6495d5b6` — live; 14/14 on trunk; no early stop (nested `claude -p` under a teammate still reads as the teammate) |
| WP3 | `hooks/memory-nudge.sh`, `hooks/lib/episodic_cue.sh`, `hooks/lib/idl-log.sh`, `scripts/idl-expected-fires.tsv`, `tests/memory-nudge-*.bats` | due-check first; `-nt` caches; daily prune; ≤15 forks on a non-due prompt | **DONE** `943d94638` — live; non-due prompt 39 → 4-7 external calls |
| WP4 | `hooks/mailbox-drain.sh`, `hooks/lib/mailbox-pending.sh`, `hooks/lib/goal-state.sh`, `tests/mailbox-drain.bats` | one jq parse; skip ancestry walk when alias current; incremental goal scan | **DONE** `dc11e310b` `c3b3d0bd5` `935a85bf1` `827b93fb1` `de5ce4dd1` — live; 4 review rounds (COUNT ONCE vs rotation check, mid-line offset straddle, below-floor stale cache) |
| WP5 | `bin/claude-accounts`, `scripts/lib/claude_census.py` (new), `tests/account-fact-derivation.bats`, `tests/claude-accounts-core.bats`, `tests/accounts-board.bats` | (C) KERN_PROCARGS2 census replaces `ps -wwEo` at :697, Popen+kill-never-wait; (D) `; resets in 1h 12m` on the ▲ line (:7225) and out-of-5h sentence, plus `△` line for 80% ≤ 5h < 85% (`router.S_RESET_SHOW`) | **(C) DROPPED** — superseded by the accounts-freshness native census (`988eb2107`, bounded reap `030f021a1`, `census:"ab"`), which already restored non-null `k` on all 4 accounts; our findings sent to pane 297, branch `load-wp5` not landed. **(D) DONE** `5e2a32bfb` — live. `scripts/lib/claude_census.py` therefore does not exist |
| WP6 | `hooks/research-precognition-nudge.sh`, `hooks/handed-off-session-guard.sh`, `hooks/session-beat.sh` + their bats | drop python3 starts; session-beat self-detaches | **DONE** `de69938a4` `a646160d2` `0d2be4405` `400b15ec4` — live; only the PROMPT beat detaches (stop and limited stay synchronous for cc-await-ping's arm baseline and stop-failure-marker) |
| WP7 | branch `lr-poller-decisions` (owner session holds it) | evidence-gc leak: `LR_EVIDENCE_GC=off` in tests, live-path guard, `taskpolicy -c utility` | **SENT** to pane 303; owner landed the live-path gate, single-flight and utility band in `b4d609a80`; declined items 1 and 5 (unreachable behind the live-path gate) |

Wave 1 landing notes (2026-10-12): Workflow worktree slots start at origin/main, not the lead's branch (first run burned at the base check). Two pre-existing trunk issues surfaced and were fixed in-wave: `tests/memory-nudge-forks.bats` SC2155 (bats-shellcheck gate) and `tests/lr-autorecover-drill.bats` stale since `d30f1f3ad` (`f122d1739`). Cancel check: baseline 23 UserPromptSubmit cancels / 30 min (03:56-04:26Z, 70 transcripts: 15 handoff-intent-nudge, 5 mailbox-drain, 3 memory-nudge); counter `/tmp/wf-load-lead/count-cancels.py <minutes>`. Post-converge (all six live): 0 cancels 09:25-09:56Z over 15 transcripts — but at load ~22-25, not the baseline's 400-600, so this is not a controlled comparison; re-count during the next high-load period before calling the timeouts gone. **High-load re-count (2026-10-12 23:16-23:46Z, load 520-680, 25 transcripts): 0 UserPromptSubmit cancels** (baseline rate predicts ~8); positive control in the same window found 30 other cancels — Stop: operator-readout.sh 13, session-continue.sh 9, boundary-handoff.sh 3, completion-assert.sh 3; PreToolUse agent-teams-enforce.sh 2. UserPromptSubmit timeouts: fixed. Stop-hook cancels remain (out of this scope's frozen DoD). claude-accounts cache: non-null `k` on all 4 accounts (1/1/18/1, native agrees), 09:28Z.

## Wave 2/3 (after Wave 1; S locus)

WP8 other `ps -wwEo` consumers → shared census (`tools/auth/auth-timeseries.sh:58`, `bin/cc-relogin`, `bin/cc-reaper`, `scripts/supervisor-e2e.sh`); WP9 cc-bats bounded queue replaces waivable refusal; WP10 migration for O1/O3; WP11 lead-crash-watchdog → one kqueue watcher; WP12 foreground-run-queue load signal for gates. Gate WP11/WP12 on O5. **O5 ANSWERED (2026-10-12):** hooks are ≈3–5% of execs; ≈84% is agent-context-sync test runs in its `b13/r5-*` worktrees and 7.4% was postland-verify's per-file `head` (fixed) — so WP11 and the hook-consolidation half of item 12 stay parked (docs/research/load-hook-timeouts-2026-10-11/O5-EXEC-TRACE.md).

Wave 2 outcome (2026-10-12, dispatched session for backlog item 55f0aafea981; two teammates):

| WP | Status |
|---|---|
| WP8 | **DONE** `a0c09994c` `bae21a7ad`. The "shared census" premise was dropped with WP5 (C), so no module exists to move to; the native census is still in-file in `bin/claude-accounts` and still in A/B soak. Of the four sites only two were unbounded: `auth-timeseries.sh` now takes ONE bounded snapshot per batch (was 5 unbounded walks), never waits on a stuck `ps`, writes `n_live: null` (not 0) when it has no census, and skips a batch while the previous run is alive; `cc-relogin` `live_sessions` joins `ps` on a daemon thread at 15 s and returns -1 (fail closed). `cc-reaper` was already bounded (`_rp_bounded`, 30 s); `supervisor-e2e.sh` has no full-table `ps`. Tests: auth-timeseries-schedule + cc-relogin 96/96. |
| WP9 | **DECISION** `b74c6368bbdb` (class C, conviction 65 for building it): a waiting queue reverses `bin/cc-bats`'s recorded R1 rule ("a shedder that waits amplifies"), while the refusal it would replace is bypassed 170-430 times a day (`~/.claude/state/bats-waivers.jsonl`, 10-09..10-12). Not built. |
| WP10 | **DONE** `870767fe8` (0064: `timeout: 5` on handed-off-session-guard.sh + `PYTEST_XDIST_AUTO_NUM_WORKERS=3`, c10, `--confirm settings.json`) · `f01b9c595` (0065: session-search-sweep `SESSION_INDEX_SWEEP_MIN_INTERVAL_S=300` in its plist env, public-publish 10800 → 86400 s plus `fleet.manifest`, c10 reload `--confirm launchd`). Precedent `7820cd375` (0055) for repo plist edits plus a c10 reload. `install.sh` reloads a changed `run` plist at converge, so O3 likely takes effect on the converge; 0065 `--verify` reads it back. |
| WP11/WP12 | Gated on O5 (`1fa5c54f8b87`, needs sudo). Not started. |

## Wave 4 — Stop-hook cancels (2026-10-12, dispatched session)

Scope (frozen): cut the Stop-hook `hook_cancelled` rate at high load for operator-readout, session-continue, boundary-handoff and completion-assert, without changing what any of them decides or prints; land each fix through the project-local /ship and converge.

Baseline (2026-10-12 23:16-23:46Z, load 520-680, 25 active transcripts, `count-cancels.py 30 --event Stop`): operator-readout 13 · session-continue 9 · boundary-handoff 3 · completion-assert 3.

Root cause: process starts, not transcript size (a 28 MB transcript scans in 0.2 s; live transcripts are p90 6 MB). Each start costs ~25 ms at a load of 400, and the four hooks made 170-500 of them on their slow paths, most inside `scripts/wrap-ledger.sh`. The ledger's memo key carries `--session` and `WRAP_BUSY`, so the hooks of one Stop asked three different questions and computed up to three ledgers concurrently; any ask without `WRAP_BUSY=off` also ran the BUSY probe (`ps -eo` over the whole table plus `lsof`, bounded at 8 s, against 5 s hook timeouts).

| Hook | Slow path, external process starts (measured with exec-logging PATH stubs under /bin/bash) | What changed | Commit |
|---|---|---|---|
| operator-readout | full render ≈500 live (10-31 s at load 380-560); fixture 230 → 187; in-TTL Stop 26 | `cc-resume-debt list` no longer starts basename per meta file (172 live; 43 → 3 for 40 metas); ledger fields read in the shell (was `grep \| head \| cut` each); one stdin jq; no dirname, no `cut` after digests | `d60b350d7` |
| session-continue | idle Stop with ledger computed: 173-190 live; fixture 103 → 87; 33 on a memo hit | one stdin jq (was 4-6); RUNG/TRUNK/AHEAD/SHAS read in the shell | `4ac344417` |
| completion-assert | done claim: 301 live (9.3 s at load 380); fixture 153 → 98; no close tell 20 → 15 | no python3 when the session has no route record (the research-block.sh precedent); ledger asked with `WRAP_BUSY=off`; one ancestry walk per Stop (`CC_CA_ASSIGNEE_MEMO`); 18 ledger fields read in the shell | `26b6c2a2e` |
| boundary-handoff | free-win Stop (35-73% fill): fixture 139 → 110; 57 when session-continue's memo exists | free-win ledger ask uses `WRAP_BUSY=off`, which is session-continue's memo key, so the two share one compute; RUNG read in the shell; one stdin jq | `80f004d0f` |
| wrap-ledger (shared) | 11 dirname starts per compute → 0 | script directory by parameter expansion | `da3949756` |

Parity: `tests/{operator-readout,session-continue,completion-assert,boundary-handoff}-forks.bats` rebuild the pre-change hook and ledger from git (`tests/stop-hook-forks-helpers.bash`, base `e1fbd8a5a`) and compare stdout, stderr, IDL rows and latch/state files byte for byte, including nine malformed stdin payloads per hook. Each suite's count tests go red when its hook is reverted (run 2026-10-12). Direct regression suites: 36 files, 35 green; `wrap-ledger-research` case 7 is a wall-clock assertion (7-12 s against a 10 s limit) that fails on the unchanged ledger too.

Landed `0c814ef6a` (smoke partial at its 900 s budget, 0 not-ok), live layer converged 2026-10-13 02:23Z. Stop cancels after, same counter (`count-cancels.py <min> [since] --event Stop`):

| Window | 1-min load | Transcripts | operator-readout | session-continue | boundary-handoff | completion-assert |
|---|---|---|---|---|---|---|
| before, 10-12 23:16-23:46Z | 520-680 | 25 | 13 | 9 | 3 | 3 |
| before, 10-13 01:22-02:24Z (62 min) | mean 54, max 176 | 273 | 4 | 6 | 0 | 3 |
| after, 10-13 02:24-02:55Z | mean 22, max 32 | 21 | 0 | 0 | 0 | 0 |

The after row is NOT the controlled comparison: load fell to ~25 before the land (the agent-context-sync test runs stopped) and far fewer transcripts were active, so it shows no regression, not the size of the cut. The high-load row (30 min with every 1-min sample ≥ 300) is still owed; re-run `python3 -I docs/research/load-hook-timeouts-2026-10-11/count-cancels.py 30 --event Stop` during the next such period and add it here. No such period came while the dispatched session waited: one sample a minute from the 02:24Z converge to 04:51Z (110 samples, none 03:54-04:32Z when the sampler had stopped) ranged 16-78. The re-count is filed as backlog row `eb3d6f848add`, parked `not-yet-true` until load holds ≥ 300 for 30 min.

Learnings: (1) the one-jq stdin parse is safe only with the original per-field reads kept as the fallback for anything that is not a newline-free string, since `jq -r` prints non-strings and multi-document input differently. (2) A memo set inside `$(…)` dies with the subshell: completion-assert's ancestry memo has to be primed in the main shell before the first guard that runs in a substitution. (3) A parity test that crosses a wall-clock bound measures the box: the hook bounds `cc-resume-debt list` at 3 s, so the pre-change arm dropped the stranded line under load, which is also what the live hook did.

Not done, on purpose: the ancestry walk is still one `ps -p` per hop (up to 8) in each hook, because Wave 1 ruled out an early stop; the BUSY probe's full-table `ps -eo` (`hooks/lib/proc-scope.sh:32`) still runs under operator-readout's own ledger ask, which is the one reader that prints BUSY; `cb_system_live` (`hooks/lib/cc-beat.sh:67`) starts one jq per beat file (7,344 files) for a session with no beat of its own.

### Wave 4b — Stop-hook DURATIONS (2026-10-14, dispatched session `stop-hook-durations`)

Scope (frozen): bring the p95 runtime of operator-readout (10 s Stop timeout), session-continue, completion-assert and boundary-handoff (5 s each) under half their timeout on this machine, with byte-identical verdicts and output; land each fix through the project-local /ship and converge.

Why a second pass: after `0c814ef6a` went live, 2026-10-13 02:24Z → 10-14 20:05Z still recorded 854 `hook_cancelled` (operator-readout 451, session-continue 274, completion-assert 99, boundary-handoff 30), only 27 of them in minutes with 1-min load ≥ 300. Wave 4 cut process counts but never timed a run against its limit. 08:00-20:11Z on 10-14 (median load 15): operator-readout p50 7.5 s, 4.8 cancels/h; session-continue 4.1/h; completion-assert 1.6/h; boundary-handoff 0.5/h. History records a success only when a hook prints, so for the three mostly-silent hooks cancels/hour is the only unbiased history metric; p95 comes from replays.

Method (scripts in `docs/research/load-hook-timeouts-2026-10-11/`): `stop-hook-durations.py <since> [until]` (per-hook runs, cancels, cancels/h, p50/p95/p99 from history); `cutreplay.py <hook> <n> <outdir>` rebuilds the EXACT Stop input of recorded cancels (the transcript cut just before that Stop's attachments, plus its subagents dir and cwd); each was replayed in a sandbox (CLAUDE_CONFIG_DIR, mailbox, TMPDIR and every write seam pointed at copies, shared caches seeded warm), old trunk tree vs new tree, the four hooks concurrent as the harness runs them, timed and traced with bash 5 `PS4=$EPOCHREALTIME` and exported `SHELLOPTS` so child scripts trace too.

Where the time went (measured, not assumed):

| Site | Measured on a real cancelled Stop | Cause |
|---|---|---|
| `session_unlanded_mine` (`hooks/lib/session-writes.sh`) | session-continue 162 s, tm2-plan worktree | one `grep -qxF` fork per file of a large `trunk..HEAD` diff |
| `session_dirty_mine` | session-continue 4-6.4 s, ~/Development/personal | `git status -uall` 2.0 s (484 untracked files under asset trees; `-uno` 20 ms) + one `grep` per record |
| `peer-owned.sh` readers + repeated transcript reads | completion-assert 24 s (it then returned `decision: block` — the live hook was killed at 5 s, i.e. the gate failed OPEN) | 4× `git status -uall`, 16× the same transcript jq, one `stat` + `grep` fork per record (507 records) |
| completion-assert D1 | 2.1 s, once hit its 5 s bound | uncached `cc-backlog list --blocked` (10 MB fold) |
| operator-readout | 5-8.5 s alone at load ~25 | ledger (with BUSY probe 1.65 s) and `cc-research pending` (0.6-1.3 s) run after, not beside, the other reads |
| BUSY probe (`session-busy.sh`) | 1.65 s | proc-scope's ancestor/descendant walks interpreted in bash over ~1,300 rows (36k traced lines) |
| boundary-handoff | 65-530 ms replayed | no own cost; it waits on the shared no-session ledger memo |

Changes (all keep the same answer; parity proven old-vs-new on replays: stdout, stderr and IDL rows byte-identical):
- `session-writes.sh`: per-run memo (`SW_RUN_MEMO`, made by `sw_run_memo_init` in the hook's main shell, removed by an EXIT trap) for transcript reads (rc 0/1 only) and the full porcelain; `_sw_has_line` + `_sw_isect` (one awk hash join, probe in-shell, awk failure falls back to the full set) replace per-record grep; `_sw_canon_lines` (one `cd`/`pwd -P` per distinct dir); `session_dirty_mine` reads `-uno` plus `-uall` restricted to the written paths as literal pathspecs (falls back to the full read for submodules, >400 paths, a failed narrowed read, or a memoized snapshot).
- `peer-owned.sh`: one porcelain snapshot per run, lazily batched `stat -f %m` (64 per call; a misaligned batch falls back per path), in-shell membership; `dirt_edited_by_live_peer` keeps its exact `printf | grep` for a newline-bearing path.
- `completion-assert.sh`: memo initialized before the attribution terms; D1 reads operator-readout's exact-keyed backlog cache first (read-only; miss = the old bounded call).
- `operator-readout.sh`: § PREFETCH — the ledger and `cc-research pending` start in the background at the top of `render_block` with the identical commands and are collected by `wait` where they were read.
- `session-busy.sh`: `_sb_ancestors` / `_sb_descendants`, one awk each, rule-for-rule copies of proc-scope's walks (proc-scope itself untouched: it is gate-cleanup's SIGKILL selector); differential-tested against proc-scope on random and adversarial tables (12-pass cap, cycles, sessions, blanks).

Replay results so far (load ~25, real cancelled Stops, four hooks concurrent): completion-assert 12.3 s → 3.2-4.4 s; session-continue 4.0-4.7 s → 1.2-2.0 s; operator-readout alone 4.9-6.6 s → 2.6-4.6 s (before the BUSY awk). Open: the ledger itself is fork-bound (~60-90 starts plus sibling CLIs); at load ~170 each start costs ~0.1 s, so a cold ledger is 6-10 s regardless of the fixes above — the remaining floor for boundary-handoff and session-continue under load.

Landed and converged: `a432bcec0` (session-writes), `fd9e12d1e` (completion-assert), `6af62766a` (operator-readout), `7db5c3fe8` (this section); the live checkout reached `7db5c3fe8` at 2026-10-14T22:33:52Z.

Live before/after (2026-10-15, `stop-hook-durations.py`, records de-duplicated by uuid across the mirrored account dirs). The after window ran at much lower load than either before window, so the raw cancels/h overstate the gain; the load-matched columns count only minutes with 1-min load ≤ 40 (same history, inline filter over `capacity-alarm.jsonl`).

| hook (Stop timeout) | before 10-13 02:24Z → 10-14 20:05Z, 41.68 h, load median 27 / p95 254 | before 10-14 15:30Z → 21:30Z, 6.00 h, load 21 / 195 | after 10-14 22:34Z → 10-15 04:36Z, 6.04 h, load 16 / 35 | load ≤ 40 only: before 22.27 h → after 5.50 h |
|---|---|---|---|---|
| operator-readout (10 s) | 321 / 643 runs = 7.70/h | 31 = 5.17/h | 1 / 67 = 0.17/h | 2.25/h → 0.18/h |
| session-continue (5 s) | 225 / 261 = 5.40/h | 28 = 4.67/h | 3 / 11 = 0.50/h | 1.80/h → 0.55/h |
| completion-assert (5 s) | 90 / 90 = 2.16/h | 17 = 2.83/h | 8 / 8 = 1.33/h | 1.26/h → 1.45/h (not improved) |
| boundary-handoff (5 s) | 28 / 28 = 0.67/h | 3 = 0.50/h | 1 / 1 = 0.17/h | 0.00/h → 0.18/h (one event) |

operator-readout from history (it prints on every run, so its percentiles are unbiased): p50 10.0 s / p95 10.4 s (41.68 h window), 7.0 s / 10.2 s (6 h window) → 3.5 s / 7.4 s after; p95 is still above half its timeout. For the other three, history records only cancels and printing runs, so cancels/h is the metric (memory: stop-hook-history-durations-are-biased-to-printers).

Verdict: operator-readout and session-continue improved materially at matched load; completion-assert did NOT — every one of its 8 after-window records is a cancel at ~5.1 s, at 1-min load 11-28, in `~/Development/personal` (4), the `tm2-plan` worktree (2), a launch-film dir and a `wt-cc-*` worktree; session-continue's 3 cancels and boundary-handoff's 1 share those Stops (tm2-plan 03:23-03:24Z) plus one in this worktree (03:50Z, load 25). Open: completion-assert's remaining cost at moderate load is not the large-diff / untracked-tree reads the replays measured, and the ledger fork floor above remains for the others.

completion-assert, second pass (2026-10-15). All 8 after-window cancels rebuilt with `cutreplay.py` and replayed against the live hook alone at load 45-60: 3.0-6.2 s, and 7 of 8 would have answered `decision: block` — real done-claims the live hook was killed on, i.e. the gate failed open. Two serial costs, both duplicates of work a sibling hook does at the same Stop:
- D1's `cc-backlog list --blocked --json` 2.8 s (cold 10 MB fold) after a 1.3 s ledger. It misses operator-readout's shared cache exactly when the session has just written the backlog (session 99e83151 closed a row at 03:40:47Z, then cancelled at 03:41:23Z), which is when D1 matters.
- Its own ledger: `--session $SID` put it on a memo key of its own. Measured in the memo dir: per Stop, one flag-keyed and one env-keyed (`CLAUDE_CODE_SESSION_ID`) ledger, identical but for the `*_SRC` labels and BUSY, none of which completion-assert reads — so it computed a third cold ledger beside session-continue's and boundary-handoff's shared one.

Changes (`hooks/completion-assert.sh`, byte-identical stdout on all 8 replays old vs new; `tests/completion-assert-durations.bats` C4, C5): D1's inputs moved above the ledger and its read prefetched into the run memo beside it (collected at D1 or before either ledger abstain; kill switch `CC_CA_D1_PREFETCH=off`); the `--session` flag dropped when the environment already resolves to the same session, so the hook joins the shared single-flight key (any other environment keeps the flag; kill switch `CC_CA_SHARED_LEDGER=off`). Replays: case 6 6.1 → 3.8 s, case 1 4.4 → 3.3 s (the D1 cases); simulated four-way Stop, completion-assert's ledger wait 1.83 → 1.21 s cold. The ledger itself stays the floor: 0.94 s at load 17, 3.4 s at load ~50 in a claude-infrastructure worktree, its largest single term `cc-decide list --open --class C` (0.3 s at load 17).

Landed `151363d40` (completion-assert, above; direct suites durations 8/8, forks 8/8, assignee-shared-cwd 9/9, completion-assert 185/185); live checkout converged to it 2026-10-15T06:14:28Z.

Second after-window, 2026-10-15T06:15Z → 12:16Z (6.02 h, 1-min load median 13 / p95 36), same script:

| hook (Stop timeout) | before 10-14 15:30Z → 21:30Z (load 21 / 195) | after 1, 10-14 22:34Z → 10-15 04:36Z (load 16 / 35) | after 2, post-`151363d40` (load 13 / 36) |
|---|---|---|---|
| operator-readout (10 s) | 5.17/h; p50 7.0 s / p95 10.2 s | 0.17/h; 3.5 s / 7.4 s | 2 / 30 runs = 0.33/h; 3.2 s / 10.1 s |
| session-continue (5 s) | 4.67/h | 0.50/h | 2 / 8 = 0.33/h |
| completion-assert (5 s) | 2.83/h | 1.33/h | 2 / 2 = 0.33/h |
| boundary-handoff (5 s) | 0.50/h | 0.17/h | 1 / 1 = 0.17/h |

Every after-2 cancel falls in three Stops, none after 07:21Z (the last ~5 h clean): 06:15:34Z in this worktree, a minute after the deploy's `install.sh` (completion-assert + session-continue together); 06:23:35Z operator-readout alone (load 39 → 55); 07:20:43Z in `tm2-plan` during a load spike (25 → 46-55 over 07:13-07:22Z), where all four hooks cancelled together. The load logger sampled through both, so neither was a machine stall. Uncached, the same ledger in `tm2-plan` is 1.1 s at load 25 (largest term `cc-research verdict` 0.46 s, an active research program there).

Verdict against the frozen scope: each hook's own cost is now well inside its timeout at ordinary load, and completion-assert, the one hook the first pass did not move, went 2.83 → 0.33 cancels/h. NOT met: "p95 under half the timeout" for operator-readout (history p95 10.1 s from 2 cancels in 30 runs); for the three silent hooks history cannot give a p95 (it records only cancels and printing runs). What remains is correlated whole-Stop cancels at load spikes, whose shared dependency is the ledger's per-call fork cost (it scales ~3× from load 17 to 50) plus operator-readout's own BUSY-on ledger computed beside the shared one. Open, for a separate wave: cut the ledger's fork count under load (largest terms `cc-research verdict`, `cc-decide list`, `git cherry`), and let operator-readout reuse the shared BUSY-off ledger for the fields it has rather than computing a second one.

## Operator-only (file with cc-backlog / cc-decide; never edit settings.json or plists)

O1 `timeout: 5` on `handed-off-session-guard.sh` + `PYTEST_XDIST_AUTO_NUM_WORKERS=3` (migration, c10) · O2 decision: `CC_SENTINEL_KILL=off` for compressor-sentinel (128 SIGKILLs since 10-07 conflict with "never kill work"; recommend off, 75%) · O3 plist throttles (session-index sweep 60 s → 300 s; public-publish daily) · O4 Claude Code upgrade via cc-upgrade + upstream report on the `ps -A` child leak · O5 30 s `eslogger exec` trace to attribute ~21k spawns/min · O6 optional cleanup of non-work orphans.

Filed 2026-10-11: O1 `4ae1c7d77e2b` · O2 decision `f3d6b2b1a2b9` (class C, conviction 75; CORRECTED (2026-10-12): superseded by `5bb842d8a406`, recommendation reversed to KEEP the kill rung at 88% — it is the guard added after SIGSTOP alone failed to prevent panic #5, docs/research/panic-2026-08-24-fifth-watchdog.md; pair with O1's worker cap). RULED (2026-10-12, operator): keep the kill rung — no config change; `5bb842d8a406` actioned · O3 `73ea54aec513` · O4 `c2aa7ab8be97` · O5 `1fa5c54f8b87` (runs `bash /tmp/loadinv/o5-exec-trace.sh`) · O6 `ad60ef86e98e`. WP7 sent to pane 303 (`lr-poller-decisions-303`) via cc-notify, delivered unread at send time.

## Already done this session (2026-10-11)

- Blender headless launch-film render (pid 12507, Cycles 128 spp, frames 1-1500, `use_overwrite=False`) moved to the background QoS band with `taskpolicy -b -p 12507` at the operator's request: PRI 31 → 4, still rendering on spare E-core capacity; load 1-min fell ~600 → ~400. Irreversible in place (restart resumes at the last frame). Memory (17-18 GB) cannot be capped live.

## Rejected (why in DESIGN.md)

`ps` shim on PATH for Claude Code; blanket `taskpolicy -c background` (background band starves at saturation — use `utility` for must-finish work); load-threshold early exits; `async: true` for heavy hooks; new precompute daemons.
