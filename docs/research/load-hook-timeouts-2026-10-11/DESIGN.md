# Load and hook-timeout reduction design (synthesis of 6 verified investigations)

## Bottom line

- **What drives the load.** The steady load of about 350–400 is not the `ps` pile. It comes from runnable work: multi-threaded claude, node and Python processes, plus about 29.4k process spawns per minute (one 60 s sample). CPU is 0% idle with 48–53% system time, under swap and compressor pressure.
  - The `ps` storms come in waves and make things worse during hook-timeout storms. At 22:31 the pile was down to 4 while load stayed at about 350.
  - Hooks account for about 20–24% of spawns across all hook events (the Bash-call chain alone is about 10–14%). About 21k spawns per minute are not attributed to anything yet. A root exec trace by the operator is the measurement that should come before any large refactor.
- **Why UserPromptSubmit hooks time out.** Only 3 of the 7 hooks ever time out (162 cancels in about 40 minutes of transcripts):
  - `handoff-intent-nudge` (95): runs a full-table argv `ps` before its cheap intent grep.
  - `mailbox-drain` (39) and `memory-nudge` (28): too many process forks per run.
  - The hooks run in parallel, so a prompt waits for the slowest one.
  - The same full-table walk in `agent-identity.sh` sits under the Stop hooks that account for about 1,130 of all 1,490 hook cancels.
- **Why the board shows `live ?`.** `concurrency()` runs `ps -wwEo` with a 10 s timeout. Under load it times out, and `subprocess.run` then blocks waiting on a `ps` stuck in uninterruptible wait. The keepwarm job's own 225 s alarm kills the tick and leaks the `ps` to launchd. Every sweep since 01:04 UTC has failed this way. The same failure makes `heal()` refuse every token refresh, so this is a login risk, not just a display bug.
- **5h reset time.** It is already stored per row (`session_reset_at`). The narrow startup board and the ▲ note at `bin/claude-accounts:7225` just never print it.

## Corrected model: claims discarded or fixed

| Claim | Status | Use instead |
|---|---|---|
| The `ps` pile is the largest share of load | REFUTED | Symptom and amplifier. Load stayed about 350 with 3–4 `ps` processes alive. |
| Timed-out UserPromptSubmit hooks orphan `ps` to launchd | NOT SHOWN | Orphans confirmed from keepwarm SIGALRM kills (pid 61721) and `timeout`-wrapped `ps`. The hook's own `ps` finishes in under 1 s between waves. |
| Stuck `ps` blocks all full-table walks; retrying never helps | REFUTED | Episodic. Between waves `ps -A` takes 0.1 s and `KERN_PROC_ALL` 24 ms. Single-pid `ps -p` stays fast during a wave unless the target pid is itself stuck. |
| `pgrep` is fast because it avoids a full walk | CORRECTED | It is answered by the sysmond daemon over XPC (libsysmon). |
| PROC_PIDTBSDINFO failures mean `ps` is stuck mid-exec | REFUTED | It is a permission result: `/bin/ps` runs setuid root. |
| Test runs are the largest producer | REFUTED | They hold 15 of 222 R/U processes. The 46 pytest workers belong to agent-context-sync, not this repo. |
| The cc-bats bound fails because of its load term | CORRECTED | It fails through the `CC_BATS_MAX_ROOTS=0` waiver, which the refusal message prints ready to paste (`bin/cc-bats` ~:675). 271 waivers on 10-11 and 10-12. |
| The 20-hook Bash chain is 20–25% of spawns | CORRECTED | The Bash chain is about 10–14%. All hook events together are about 20–24%. Treat the ~190 spawns/call figure as a CPU-equivalent, not a spawn count. |
| `handed-off-session-guard` falls back to a 60 s timeout | CORRECTED | 30 s, the UserPromptSubmit default. Its common path measured 0.4–0.7 s, so this is latent risk, not a current cause. |
| Claude Code's `ps` children come from killProcessTree | PLAUSIBLE, NOT PROVEN | Several CC helpers spawn `ps`. Inference: every hook cancel triggers CC's `ps -A` tree walk with no timeout, so fixing hook timeouts also starves the storm. |

## Ranked items (impact per risk)

### Tier 1: agent-landable, high impact, low risk

**1. handoff-intent-nudge: cheap gates first** (`hooks/handoff-intent-nudge.sh`)
- **Sites:**
  - `:15-18`: python3 JSON parse.
  - `:21`: `/handoff` case.
  - `:28-38`: assignee block that sources `lib/agent-identity.sh`.
  - `:40`: intent grep.
- **Change:**
  1. Replace the python parse with one `jq -r '.prompt // empty'`.
  2. Add `case "$PROMPT" in '<\task-notification>'*) exit 0;;`. Verified in a transcript: machine prompts carry content starting `<\task-notification>`. Whether the hook's stdin `prompt` field carries the same text is inference; pin it in the test.
  3. Run the `:40` grep before the `:28-38` assignee check, so `ps` only runs on prompts that actually mention a handoff.
  - The hook only adds context and never blocks, so the reorder cannot change any blocking outcome.
- **Verify:** new `tests/handoff-intent-nudge-fastpath.bats`:
  - A `ps` stub on PATH writes a marker and exits 1. A non-intent prompt and a task-notification prompt both leave no marker.
  - An intent prompt from an assignee (via the `CC_WF_PSTABLE_FILE` fixture) still suppresses the nudge.
  - Mutant: put the old order back and the marker test must fail.
  - After converge: count `hook_cancelled` for this hook over 1 h, using the same jq method as `/tmp/loadinv/ups.jsonl`.
- **Impact:** removes up to 95 of 162 cancels (59%). Machine prompts are 5.5–9.8x human prompts (44 vs 5 in the measured hour), so the early exit also drops roughly 90% of this hook's firings.
- **Risk:** very low.

**2. agent-identity: per-hop ancestry walk instead of a full-table scan** (`hooks/lib/agent-identity.sh:33-88`)
- **Change:** when `CC_WF_PSTABLE_FILE` is unset, replace `ps -axo pid=,ppid=,command=` (:51) with a bash loop:
  - For each hop, run `ps -o pid=,ppid=,command= -p "$cur"` and append that row to a small table.
  - Get the next pid with `read -r _ pp _ <<<"$row"`. No `set -- $row`, because argv can contain globs.
  - Stop at pid 0/1, at `maxhop`, or (optional) at the nearest claude/claude.exe ancestor.
  - Pipe the small table into the **unchanged** awk program at `:53-88`. The three-flag and cross-field checks and the test seam stay byte-identical.
  - Bash 3.2 is safe: the hooks use `#!/bin/bash`, and here-strings work there.
- **Same change elsewhere:** `hooks/teammate-auto-shutdown.sh:313` has its own `ps -axo` table.
  - Read `:298-330` first.
  - If it is an ancestry walk, call the lib instead.
  - If it scans the whole fleet, get candidates with `pgrep -x 'claude|claude.exe'`, then read each pid with `ps -o command= -p`.
- **Optional second step:** cache the verdict per `session_id`, validated by a builtin `kill -0` on the recorded claude pid.
- **Verify:** new `tests/agent-identity-walk.bats`:
  - A `ps` stub that hangs (`sleep 30`) on `-axo` and answers `-p` from a fixture: the call returns in under 1 s with the right id.
  - A brief that merely mentions the flags is still a non-match.
  - Pid 1 and 8-hop termination.
  - The seam path is unchanged.
  - Mutant: the old `-axo` form times out the first test.
- **Regression suites:** `session-continue.bats`, `completion-assert.bats`, `operator-surface-scope.bats`, `mechanical-arm-exemption.bats`, `completion-assert-assignee-shared-cwd.bats`, `stop-failure-marker.bats`, `plan-agent-teams-locus.bats`.
- **Impact:** removes the only known unbounded step from 15+ hooks, including the Stop hooks with 355, 309, 168, 112, 98 and 89 cancels. Typical cost is about 3–4 small forks instead of one 550 KB argv read that can stall. Fewer hook cancels should also mean fewer CC-spawned `ps -A` walks (inference).
- **Risk:** low to medium, because this is the security-relevant identity check. Early-stop changes one edge case: a `claude -p` nested under a teammate stops reading as an assignee. That is arguably a fix; pin it with a test either way.

**3. claude-accounts: kernel census instead of `ps -wwEo` (C), plus the 5h reset clause (D)** (`bin/claude-accounts`)
- **(C) census:**
  - New `scripts/lib/claude_census.py`, prototype at `/tmp/loadinv/accounts-live-sysctl-census.py`. It lists candidates with `pgrep -x 'claude|claude.exe|node'`, then reads each pid's argv and env with a ctypes `sysctl` call (`KERN_PROCARGS2`). It has a CLI: `python3 -I … --json`.
  - Measured under load of about 480: 41 claude processes in 0.16 s, 0 failures. The same `ps` call never finished.
  - In `concurrency()` (`:642-763`), replace `:697` with the module. Keep every filter (argv0 spelling, headless check on `head[1:7]`, last `CLAUDE_CONFIG_DIR=`, `by_dir`/`mirror_next`, `argv_sid`) and the None contract.
  - Any remaining subprocess uses `Popen(start_new_session=True)` + `communicate(timeout)`. On timeout: `kill()` and return None, **never `wait()`**. That one change prevents the tick stall.
  - Optional, display only: past 600 s, `k_shown` (`:3107-3118`) renders the last real count with its age (`41~12m`) instead of `?`. The gates keep reading `k=None`.
- **(D) reset clause:**
  - Add `_reset5_clause(r)` after `fmt_board_t` (`:6573`). It uses `hrs_until(session_reset_at)` (`:1514`) first, then `session_reset_h`. It returns `; resets in 1h 12m` via `fmt_board_t`, or `; its 5-hour window has reset since this reading`.
  - Append it to the ▲ note (`:7225`) and the "out of 5-hour quota" sentence (`:7270-7275`). The ▲ line becomes 69 cells, inside the 76-cell budget.
  - For the requested ~80% threshold: add cfg `router.S_RESET_SHOW` (default 0.80). For `S_RESET_SHOW ≤ sp < S_CUT`, emit `△ \`acct\` — 5h at 82%; resets in …`. This costs at most 1 board row per account inside that band.
  - Update the "board-only" note in `fmt_board_t`'s docstring.
- **Verify:**
  - `tests/account-fact-derivation.bats`: a stub census with a hanging `ps` returns within its bound; the None contract is preserved; attribution parity with the old parser on a fixture.
  - `tests/claude-accounts-core.bats` (near `:1519`, helpers `row()`/`rd()`): 88% plus a reset 72 min out matches `resets in 1h 1[12]m`; 50% gives no clause; 82% gives the `△` line; an elapsed stamp gives "has reset since"; a wire-rejected row carries the clause. Mutant: delete the clause and the first test fails.
  - `tests/accounts-board.bats`: a new fixture through `WIDTH_CHECK` (`:381-390`). Leave `NARROW_FIXTURE` alone.
  - Live check: the next keepwarm tick logs no `ps UNAVAILABLE`, and `/tmp/claude-accounts-cache.json` has non-null `k` on all four accounts.
- **Impact:** the board column works again. `heal()` can refresh tokens again; today it refuses every sweep. No more leaked uninterruptible `ps` per keepwarm tick (~20 per hour), and sweeps are no longer killed at 225 s.
- **Risk:** low to medium. `KERN_PROCARGS2` is the same kernel source `ps -E` reads, and same-uid is required as today.

**4. evidence-gc leak** (unlanded branch `lr-poller-decisions`, `scripts/limit-recover/lr-reset-poller.sh:283-300`, confirmed on that branch)
- **Change:**
  - The test setup exports `LR_EVIDENCE_GC=off`.
  - The kick refuses when `$LR` is not the live install path.
  - Single-flight check from the shell before detaching.
  - Use `taskpolicy -c utility`, not `-b`. The background band never runs while the CPU is saturated, which is why 38–47 of these sit runnable for hours with about 0.01 s CPU.
  - Add the case to `scripts/test-hermeticity-lint.sh`.
- **Owner:** this branch has an active owner session. Send the fix to the owner; do not commit to its branch.
- **Verify:** bats for the poller suite asserts no detached `lr-lock.py` survives a test run (`pgrep -f` count before and after, scoped to the test's `$STATE`).
- **Impact:** about −40 load-average points (runnable starved processes; inference that they count toward load) and no new orphans, which arrive at about 20 per hour.
- **Risk:** low; test-only.

### Tier 2: agent-landable, medium impact

**5. memory-nudge: due check first, then measure** (`hooks/memory-nudge.sh:95-112, :136-246, :266-406, :447, :607-613`; `hooks/lib/episodic_cue.sh:93-124`; `hooks/lib/idl-log.sh:117-133`)
- **Change:**
  - Compute COUNT first.
  - Gate the stats work with a strictly weaker cost check: if the raw file size is below ROTATE_AT, skip `_mn_stats`, `wc` and `cut`.
  - Cache MEM/WANT/RROOT per cwd, and the STATS line keyed by the index file, checked with the builtin `[ "$MEM" -nt "$cache" ]` (zero forks).
  - Run the `find -delete` prune once a day via a stamp. 1,007 counter files sit in one directory shared by all accounts.
  - Add a builtin `case` keyword filter before the episodic jq.
  - Emit the shadow-abstain row with one printf.
  - `idl-log.sh`: replace `dirname` with `${p%/*}`, and only `mkdir` when the directory is missing (builtin `-d` test).
  - Keep IDL row counts per prompt the same, or update `scripts/idl-expected-fires.tsv` in the same commit.
  - The rotor stays latched per index state per day by design. It may be detached via `scripts/lib/detach.sh`.
- **Verify:**
  - `memory-nudge-budget.bats`, `-episodic`, `-interval` and `-ruling-shadow` all green.
  - New fork-count test: PATH stubs log every external call on a non-due prompt; assert ≤15.
- **Impact:** about 40–75 process creations per prompt drop to about 10–15 (it measured 1.39 s at load ~420). Removes the 28 cancels.
- **Risk:** moderate; telemetry rows feed audits.

**6. mailbox-drain** (`hooks/mailbox-drain.sh:93-95, :156, :273-279, :489-492, :900-904`; `hooks/lib/mailbox-pending.sh:176-197, :224-237, :520-560, :829-860`; `hooks/lib/goal-state.sh:53-73`)
- **Change:**
  - One `jq @tsv` parse instead of two.
  - In `mailbox_alias_write`, test `tip == sess` before the `ps` ancestry walk.
  - Incremental `goal_live_condition`: store the byte offset and last record per transcript, rescan if the offset is larger than the file, and anchor the grep on `"type":"goal_status"`.
  - Count mailbox lines once per drain.
  - **Drop** the proposed `read -t 0.05` swap: hooks run under `/bin/bash` 3.2, which does not take fractional read timeouts (verify before relying on it either way).
- **Verify:** `tests/mailbox-drain.bats` plus new tests:
  - A truncated transcript forces a rescan.
  - An empty-inbox run makes no `ps` call when the alias is current.
  - Timing: under 0.4 s with a sandboxed state directory.
  - `session-continue.bats` as a regression check, since it shares `goal-state.sh`.
- **Impact:** the empty-inbox path drops from about 1.0 s to about 0.3 s, removing most of the 39 cancels.
- **Risk:** moderate, because goal-state readers are shared.

**7. Small prompt hooks: interpreter starts** (`hooks/research-precognition-nudge.sh:34-44`, `hooks/handed-off-session-guard.sh:39-64`, `hooks/session-beat.sh:42-134`)
- **Change:**
  - research-precognition: skip `python3 router.py` when no program resolves; just unlink `route-state/<sid>.json` in bash.
  - handed-off-session-guard: one `jq @tsv` replaces two python3 starts. Exit-2 blocking stays intact.
  - session-beat: one `jq @tsv`, the regex with `[[ =~ ]]`, and it detaches itself and exits immediately. That gets it off the prompt path without the operator setting `async`, which has no enforced timeout and can pile up.
- **Verify:** `research-*`, `handed-off-session-guard.bats`, `handed-off-guard-superseded.bats` and `session-beat.bats` green. The 60 s beat freshness contract is still met.
- **Impact:** about 4 python3 starts and 5 jq calls fewer per prompt per session.
- **Risk:** low.

**8. Other `ps -wwEo` consumers move to the shared census** (wave 2; depends on item 3)
- **Sites:**
  - `tools/auth/auth-timeseries.sh:58`. One instance has been wedged for 2h43m. Also add skip-if-previous-run-alive.
  - `bin/cc-relogin` (~:253).
  - `bin/cc-reaper` (~:1295).
  - `scripts/supervisor-e2e.sh`.
- **Verify:** `auth-timeseries-schedule.bats`, plus the cc-relogin and cc-reaper suites with a hanging-`ps` stub.
- **Impact:** removes the remaining sources of long-wedged `ps`.
- **Risk:** low to medium. `cc-reaper` selects processes to kill, so keep its selection logic unchanged.

**9. cc-bats: a real queue instead of a waivable refusal** (`bin/cc-bats:595` `load_term_true`, `:629-680`)
- **Change:**
  - Drop the load term. It is always true at 25–90 per core, so it decides nothing.
  - Cap at K=3 roots.
  - On refusal, wait in the queue with a bounded wait (`--wait`, the default when unattended) instead of exiting 75.
  - The waiver becomes queue priority, not `MAX_ROOTS=0`, and the ready-to-paste bypass line goes away.
- **Verify:** `tests/cc-bats-admission.bats`: a 4th root waits, then admits when a slot frees. The wait is bounded. A nested run takes no slot.
- **Impact:** about 6 concurrent roots drop to 3, and the 271/day bypass goes away. Work is delayed, never dropped.
- **Risk:** longer time to verification.

### Tier 3: larger; gate on the exec trace (O5)

**10. lead-crash-watchdog: one watcher instead of 38 polling daemons** (`hooks/lead-crash-watchdog.sh:1809-1820` identity check, `~:1950-2041` poll loop; `bin/cc-deathwatch-kqueue`)
- **Change:** each per-session daemon currently runs `kill -0` plus two `ps -o` calls every 30 s. Replace them with one machine-wide kqueue NOTE_EXIT watcher. Pid plus start-time pinning must carry over.
- **Size:** about 400 LOC; split into watcher and registration.
- **Verify:** all `lead-crash-*.bats`.
- **Impact:** about −400 spawns/min (about 1.4%) and about −76 `ps`/min.
- **Risk:** medium, because crash-detection semantics have to carry over exactly.

**11. Load signal for the gates** (`scripts/ship-land.sh:2036` `load_above_ceiling`; capacity-admit; `scripts/convoy-gauge.sh`)
- **Change:** gate on the foreground run queue (convoy-gauge `run_default`/`run_ui`) instead of `vm.loadavg`, which counts starved background-band work, including the gates' own deferred backlog. The "141 of 224 runnable threads are background-band" figure is reported but was not verified.
- **Risk:** medium; `ship-land.sh` is the landing gate.

**12. PostToolUse consolidation and in-process prompt hooks ("mods")**
- One serial post-tool dispatcher; `config/hook-chains.d` is at least 4 members stale.
- A `prompt.submit` plugin for the advisory nudges only. This revisits rejected candidate C8: the fleet is now at or above its 2.1.289 revisit trigger, but whether pane teammates and `-p` sessions load the plugin is unprobed.
- Build either only once the exec trace shows hook spawns are the share worth chasing. Both need operator wiring.

## Work packages (disjoint file ownership, each under 500 LOC)

| WP | Wave | Files owned | ~LOC | Items |
|---|---|---|---|---|
| WP1 | 1 | `hooks/handoff-intent-nudge.sh`, `tests/handoff-intent-nudge-fastpath.bats` (new) | 40 | 1 |
| WP2 | 1 | `hooks/lib/agent-identity.sh`, `hooks/teammate-auto-shutdown.sh`, `tests/agent-identity-walk.bats` (new) | 120 | 2 |
| WP3 | 1 | `hooks/memory-nudge.sh`, `hooks/lib/episodic_cue.sh`, `hooks/lib/idl-log.sh`, `scripts/idl-expected-fires.tsv`, `tests/memory-nudge-*.bats` | 200 | 5 |
| WP4 | 1 | `hooks/mailbox-drain.sh`, `hooks/lib/mailbox-pending.sh`, `hooks/lib/goal-state.sh`, `tests/mailbox-drain.bats` | 200 | 6 |
| WP5 | 1 | `bin/claude-accounts`, `scripts/lib/claude_census.py` (new), `tests/account-fact-derivation.bats`, `tests/claude-accounts-core.bats`, `tests/accounts-board.bats` | 300 | 3 (C+D) |
| WP6 | 1 | `hooks/research-precognition-nudge.sh`, `hooks/handed-off-session-guard.sh`, `hooks/session-beat.sh` + their bats | 100 | 7 |
| WP7 | 1, sent to branch owner | `lr-poller-decisions`: `scripts/limit-recover/lr-reset-poller.sh`, its bats setup, `scripts/test-hermeticity-lint.sh` | 40 | 4 |
| WP8 | 2 (after WP5) | `tools/auth/auth-timeseries.sh`, `bin/cc-relogin`, `bin/cc-reaper`, `scripts/supervisor-e2e.sh` + bats | 150 | 8 |
| WP9 | 2 | `bin/cc-bats`, `tests/cc-bats-admission.bats` | 150 | 9 |
| WP10 | 2 | `migrations/0061-*.sh` (new; written by the agent, run by the operator), `launchd/*.plist` sources | 120 | O1–O3 |
| WP11 | 3 | `hooks/lead-crash-watchdog.sh`, `bin/cc-deathwatch-kqueue`, `tests/lead-crash-*.bats` | 400 | 10 |
| WP12 | 3 | `scripts/ship-land.sh` (load fn only), `scripts/convoy-gauge.sh`, capacity-admit | 150 | 11 |

Wave 1 is six agent packages plus one sent to the branch owner, within the 6-teammate cap. Each lands through the project-local `/ship`, then converges with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`.

## Operator-only actions (settings.json and plists are c10; decisions are the operator's)

- **O1.** One migration (WP10) for settings.json:
  - `"timeout": 5` on `handed-off-session-guard.sh`, and decide the same for `keychain-guard.sh` and `waiting-recycle.sh`. `migrations/0009:203-214` deliberately leaves this fleet-wide call to `scripts/settings-hook-timeouts.sh`.
  - Env `PYTEST_XDIST_AUTO_NUM_WORKERS=3`: 46 to about 12–18 workers, machine-wide.
- **O2.** Decision: compressor-sentinel's SIGKILL rung conflicts with "killing work is not an option". It has sent 128 real SIGKILLs since 10-07, the last four to pytest spawners between 01:01 and 01:58Z on 10-12.
  - An opt-out already exists: add `CC_SENTINEL_KILL=off` (`scripts/compressor-sentinel.sh:173`) to `com.claude.compressor-sentinel.plist`. SIGSTOP stays as the panic guard.
  - Recommendation: turn the kill rung off, about 75% conviction. Pair it with O1's worker cap.
- **O3.** Plist throttles: session-search-sweep `SESSION_INDEX_SWEEP_MIN_INTERVAL_S=300` (`hooks/session-index-sweep.sh:89-97`; today it walks 17,334 directories every 60 s), and public-publish every 3 h → daily. Keep keepwarm at 180 s; WP5 makes it cheap.
- **O4.** Upgrade Claude Code through the cc-upgrade gate.
  - Sessions run 2.1.293 from `~/.claude-293`, while `claude --version` on PATH reports 2.1.291.
  - 2.1.296 adds per-hook durations to `--debug`, which replaces the cancel-only sampling.
  - File an upstream report: the killProcessTree `ps -A` path has no timeout and never kills the child.
  - CORRECTED (2026-10-17): the code path is now confirmed in the 2.1.293 binary. The killProcessTree helper spawns `ps -A -o pid= -o ppid=` with no timeout and resolves only on `close`. A sibling `ps -A` call passes `{timeout}`. The report is drafted in `UPSTREAM_PS_A_REPORT_DRAFT.md` and is not yet posted, pending the operator's OK.
- **O5.** The gating measurement: a 30 s root exec trace (`eslogger exec`) to attribute the roughly 21k unattributed spawns per minute.
- **O6.** Optional cleanup of non-work leftovers: evidence-gc orphans, lead-crash-watchdogs 1–2 days old, the wedged `auth-timeseries` `ps` (pid 28973). Blender at 18 GB RSS is the largest memory consumer.

## Designs rejected

- **A `ps` shim on PATH for Claude Code:** changes harness behavior for every session; too risky.
- **Blanket `taskpolicy -c background` at spawn:** at saturation the background band never runs. Work stays runnable for hours and inflates the load average (the evidence-gc case). Use `-c utility` for work that must finish; use background only for work with an abandon deadline.
- **Nudges exit early above a loadavg threshold:** loadavg is permanently above any such threshold here and is inflated by starved work, so the nudges would simply be off. Fix the slow steps instead.
- **`async: true` for heavy hooks:** saves no CPU and has no enforced timeout, so runs pile up. Acceptable only for side-effect hooks with their own deadline (item 7 does it inside the script instead).
- **A new daemon to precompute prompt-hook state:** every daemon is new load. Prefer lazy caches checked with builtin `-nt` (zero forks) inside the hook. Reuse producers that already exist (keepwarm for the board).

**Prompt-hook rules, summed up:** no unbounded step in a UserPromptSubmit hook (no full-table `ps`, no whole-transcript scan). Cheap predicate before measurement. Early exit on `<\task-notification>` prompts for human-intent nudges. `$SECONDS` checkpoints that exit 0 silently past 3 s and bump a skip counter file, so the skip rate stays measurable. Explicit timeouts on every hook (O1).

## Open gaps

- Spawn attribution (O5).
- Whether uninterruptible `ps` counts toward macOS load (inferred no, from XNU's runnable-only count).
- Whether the hook's stdin `prompt` field is the `<\task-notification>…` text; pin it in WP1's test.
- Whether 2.1.293 or later fixes CC's `ps` handling.

Evidence is under `/tmp/loadinv/`: `ups.jsonl`, `cancelled.jsonl`, `hin.trace`, `aia.trace`, `ps-kpid-all.tsv`, `ps-producers.txt`, `accounts-live-sysctl-census.py`, `hooks.md`, `changelog.md`.