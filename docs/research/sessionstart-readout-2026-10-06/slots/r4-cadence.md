# R4: producer cadence, tick cost, and the setitimer crash (com.claude.accounts-keepwarm)

Slot: read-only. Nothing was kickstarted, booted out, loaded or edited. Raw extracts saved beside this file: `/tmp/ssr-research/r4-launchd-6h.txt` (unified log, 236 lines), `/tmp/ssr-research/r4-ticks.tsv` (113 spawn/exit pairs), `/tmp/ssr-research/r4-ticks-kind.tsv` (each tick joined to its out-log line and to the next3 wire reads in its window).

## Verdict

- **The producer is not running every 6 min 14 s. It sweeps every 185.6 s (p50 start to start).** The ~370 s spacing comes from the recorder: `record_utilization` appends at most one batch per 300 s, gated on the jsonl file's mtime (`bin/claude-accounts:5483` `UTIL_MIN_INTERVAL_S = 300`, gate at `:5510`). With sweeps about 185 s apart, every second sweep is recorded. Intake defect 3 in the plan has the wrong premise.
- **next3 was wire-read on every sweep.** 71 of 71 keepwarm `swept` ticks after next3 entered the near-wall band (01:53:05Z) contain a `probe next3: wire` line. Other callers did 18 more reads. Total: 90 next3 wire reads, median gap 189 s.
- **Neither launchd QoS nor usage-endpoint throttling spaces the reads.** The job is ProcessType Standard. launchd re-arms StartInterval at job **exit**, so the period is 180 s plus the run time. There were 0 throttle/held lines on 2026-10-06.
- **There is one real producer defect: the setitimer crash.** A variable is shadowed. `get_data` rebinds `deadline` to an epoch time (`time.time() + 240`, `:5835`) and then passes it to `_arm_sweep_bound`, which subtracts `time.monotonic()` (`:5750`). The result is ~1.79e9 s, which macOS refuses because it is above its 1e8 s itimer limit (EINVAL). This fires only at the end of an outage, and it costs that tick both its sweep and its board.
- **The incident is not a cadence miss.** The board's read was 82 s old when the server refused (wire read 06:01:41.86Z, refusal 06:03:04Z). A 180 s producer, or any cadence the ~90 s usage-endpoint throttle allows, cannot close that gap. The fix belongs to the wording and precision slots.

## Timeline of recent ticks (UTC; spawn and exit from launchd's unified log, kind and took_ms from the out log)

Source for spawn/exit: `log show --last 6h --info --debug --predicate 'eventMessage CONTAINS "com.claude.accounts-keepwarm"'`. Spawn is the xpcproxy line "Launch constraint set". Exit is launchd's "service inactive". I aligned out-log lines to ticks positionally and checked the alignment two ways: every post-01:53 `swept` tick has a next3 wire read inside its spawn/exit window (71/71), and no `served-cache` tick does (0/20). The board mtime 01:01:46 CDT equals the exit at 06:01:46.138.

| spawn | exit | wall s | kind | age_s | took_ms | next3 wire read (claude-accounts.log) | jsonl batch |
|---|---|---|---|---|---|---|---|
| 05:36:55.885 | 05:36:59.749 | 3.86 | swept | 0 | 3691 | in tick | 05:36:59 |
| 05:39:59.761 | 05:40:03.954 | 4.19 | swept | 0 | 3970 | in tick | gated |
| (other caller) | | | | | | 05:42:57.6, 0.99 allowed_warning | **05:43:11** (written by the other caller) |
| 05:43:03.965 | 05:43:09.914 | 5.95 | **served-cache (lock degrade)** | **186** | 5784 | none (lock held by the 05:42:5x sweep) | |
| 05:46:09.927 | 05:46:17.812 | 7.88 | swept | 0 | 7510 | 05:46:11.2 | gated |
| 05:49:17.830 | 05:49:27.406 | 9.58 | swept | 1 | 9061 | 05:49:20.4 | **05:49:26** |
| 05:52:27.419 | 05:52:34.934 | 7.51 | swept | 0 | 7180 | 05:52:28.8 | gated |
| 05:55:34.948 | 05:55:40.248 | 5.30 | swept | 0 | 5054 | 05:55:36.1 | **05:55:39** |
| (other caller) | | | | | | 05:57:46.9, 0.99 allowed_warning | gated |
| 05:58:40.261 | 05:58:40.870 | 0.61 | served-cache | 51 | 422 | none | |
| 06:01:40.885 | 06:01:46.138 | 5.25 | swept (**incident board**) | 0 | 5083 | 06:01:41.86, 0.99 allowed_warning | **06:01:45** |
| *refusal* | | | | | | session 4ad354fc, 06:03:04 (plan, incident) | |
| (other caller) | | | | | | **06:03:49.2, 1.0 rejected** | gated (first rejected read; absent from jsonl) |
| 06:04:46.156 | 06:04:47.154 | 1.00 | served-cache | 51 | 411 | none (serves the 06:03:5x cache) | |
| (other caller) | | | | | | 06:05:29.4, 1.0 rejected | gated |
| 06:07:47.170 | 06:08:13.876 | 26.71 | swept | 2 | 19239 | 06:07:56.7 | **06:08:11** (first jsonl `rejected`) |
| 06:11:13.895 | 06:11:43.112 | 29.22 | swept | 4 | 26206 | 06:11:23.9 | gated |
| (other caller ×2) | | | | | | 06:12:27, 06:13:36 | 06:13:51 (other caller) |
| 06:14:43.132 | 06:14:48.118 | 4.99 | served-cache | 56 | 3950 | none | |
| 06:17:48.131 | 06:18:14.854 | 26.72 | swept | 6 | 22961 | 06:17:52.9 | gated |
| ~06:21:14.9 | ~06:21:15.7 (out mtime) | ~0.9 | served-cache | 41 | 623 | none (other caller at 06:20:32) | 06:20:34 |
| ~06:24:15.7 | | | swept | 1 | 14749 | 06:24:17.6 | |

Exit codes: every tick in the window wrote its final `keepwarm:` line (113 ticks, 113 lines, all `board=/tmp/claude-accounts-board.txt`), and that print is the verb's last statement (`:7821-7826`), so each exited 0 (reasoned). The err log has not changed since 2026-09-30T17:02:42 CDT (measured: `stat`). `launchctl print` reports `last exit code = 0`.

## (a) Distributions (measured, 113 ticks, 2026-10-06 00:21:48Z to 06:18:14Z)

| metric | n | min | p50 | p90 | p99 | max |
|---|---|---|---|---|---|---|
| exit to next spawn (s) | 112 | 180.009 | 180.017 | 180.034 | 180.046 | 180.047 |
| spawn to spawn (s) | 112 | 180.374 | 185.599 | 201.658 | 225.802 | 235.369 |
| spawn to exit, wall (s) | 113 | 0.365 | 5.566 | 23.236 | 45.782 | 55.349 |
| took_ms, swept | 93 | | 9359 | 20527 | | 42502 |
| took_ms, served-cache | 20 | | 854 | 5882 | | 7002 |
| startup overhead (wall minus took_ms, ms) | 113 | 141 | 342 | 3011 | | 12847 |

- Kind split: **93 swept (82%), 20 served-cache (18%)**. Of the 20 served ticks, 18 found a cache ≤90 s old because another caller had swept, and 2 were lock-degrade ticks at 01:30:30 (age 189, 5882 ms) and 05:43:03 (age 186, 5784 ms).
- Over the last 480 out lines (~25 h; script over `accounts-keepwarm.out.log`): swept 387, took p50 4359 ms, p90 18552 ms, max 42502 ms; served 93, p50 416 ms. `reset_pending` was set on 12 ticks; `board=FAILED` on 0.
- **Why `--max-age 90` with StartInterval 180 gives this spacing.** launchd re-arms at exit (measured above: exit to spawn 180.0 s ± 0.05 s on all 112 intervals, while start to start ranges up to 235 s and never shows a skipped 360 s slot). A tick therefore always finds its own last cache about 180 s old, which is past 90, so it sweeps. It serves the cache only when another caller swept in the previous 90 s, or when another sweep holds the lock for more than `lock_wait_s` 5 (`accounts.json:25`). `--max-age 90` never drives the cadence; it only suppresses duplicate sweeps.
- **The recorder halves the visible series.** In the window there were 55 jsonl batches against ≥111 sweeps (93 keepwarm plus ≥18 other-caller): 46 written inside keepwarm ticks, 9 by other callers. Spacing over all batches since 2026-10-01: min 300.09 s, p10 350.7, p50 377.7, p90 450.6 (script over `account-utilization.jsonl`). **Consequence for R3:** the jsonl puts next3's first `rejected` at 06:08:11, but `claude-accounts.log` has it at 06:03:49.2, 262 s earlier. Any dwell-at-0.99 analysis must read the `probe <acct>: wire —` lines in `~/.claude/logs/claude-accounts.log`, because those carry every read with its timestamp (`:2481`).

## (b) The setitimer crash

**Code path (current lines; the traceback's 5051/5128/6882 match commit 90ae83707 exactly, measured with `git show 90ae83707:bin/claude-accounts | grep -n`):**

1. `--keepwarm`: `get_data(cfg, fresh=False, …, max_age=90)` (`:7798`) with no `--max-wait`, so `deadline = None` (`:5794-5795`).
2. The cache is older than 90 s, so it takes the lock path: `elif not _acquire_lock(lock, cfg, allow_degrade=True)`. That waits `lock_wait_s` 5 s behind another holder and returns False (`:5709-5716`).
3. The grace re-read finds nothing within 600 s (`:5826-5829`).
4. **`deadline = time.time() + _fresh_lock_wait_s(cfg)` (`:5835`) rebinds the function-level `deadline` to epoch seconds.** The loop takes the lock before 240 s.
5. The post-lock re-read misses (`:5857`). Then `disarm = _arm_sweep_bound(deadline)` (`:5861`). `deadline` is no longer None, so it installs `_expire` and calls `signal.setitimer(ITIMER_REAL, max(deadline - time.monotonic(), 0.01))` (`:5750`).
6. The argument is about time.time() minus monotonic, which is **~1.79e9 s** (measured at 06:19Z: `time.time()-time.monotonic()` = 1790799961.8). XNU's `itimerfix` rejects `tv_sec > 100000000` with EINVAL (https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/kern_time.c). I measured this in a throwaway `python3` process: `setitimer(ITIMER_REAL, 1e8)` succeeds, `1e8+1` and `1.79e9` both raise `[Errno 22] Invalid argument`, and `inf` raises `OverflowError`. So the cause is **a value too large**, not inf, nan or a negative; the `max(…, 0.01)` clamp cannot catch it.

**Origin:** `_arm_sweep_bound(deadline)` arrived in 30c8aad4e (2026-09-29 00:47 CDT, "weighted, voidable, ttl'd assignment ledger"). It reads a name that the 2026-07-29 elif branch (1b3da02a3) already reused for its own wall-clock bound. The bug was latent until that branch acquired the lock.

**Precondition and frequency:** the crash needs all three of: no `--max-wait`, no cache within the 600 s grace, and another holder that keeps the lock more than 5 s and then releases it within 240 s. That is the moment an outage ends. It is recorded once, in `accounts-keepwarm.err.log` (mtime 2026-09-30T17:02:42 CDT = 22:02:42Z). The utilization series has a gap from 09-30 21:38:03Z to 22:03:10Z (1506 s; measured, a gap scan over the jsonl), which fits a cache older than 600 s with the crash on the recovery tick. The err log is not rotated: `scripts/rotate-autonomy-logs.sh` has no keepwarm entry (grep). The other 3 `ItimerError` hits under `~/.claude/logs` are this research's own commands. Other callers that reach the same branch (`--rank`, `/accounts`, any call without `--max-wait`) send the traceback to their own stderr, so their count is unmeasured.

**What it loses:** the exception propagates before `cache_write` (`:5873`) and `write_board` (`:7818`). That tick does not sweep, leaves the >600 s cache in place, writes no board, and exits 1. launchd starts the next tick 180 s after that exit, so recovery slips by one period. On a platform that accepted the value, the same bug would silently replace keepwarm's SIG_DFL `alarm(225)` (`:7790-7791`) with a ~57-year `_expire` timer and remove the deadline. **Catching `ItimerError` is therefore the wrong fix.**

**Test gap:** `tests/claude-accounts-fresh-lock-bound.bats` covers `--fresh` expiry (tests 1-5) but never a non-fresh caller with no servable cache that then **wins** the lock.

## (c) `launchctl print gui/501/com.claude.accounts-keepwarm` (measured 06:16:54Z, read-only)

- `state = not running`, `runs = 2418`, `last exit code = 0`, `run interval = 180 seconds`, `minimum runtime = 10`, `exit timeout = 5`, `spawn type = daemon (3)`, `jetsam priority = 40`.
- ProcessType: the installed plist is byte-identical to `launchd/staged/com.claude.accounts-keepwarm.plist` (measured: `diff`), and that file sets `ProcessType Standard` (`:127`), Standard since 2026-09-24 per its own comment (`:91`). The job is **not** in the Background band. I am inferring that `spawn type = daemon (3)` is Standard's encoding; it is not Background.
- Throttle: there is no throttle state. Runs shorter than the 10 s `minimum runtime` (for example 0.365 s) still respawned at exit + 180.0 s, so ThrottleInterval adds nothing at this interval (measured above).
- runningboardd logged "not RunningBoard jetsam managed" twice (02:52:07Z, 04:54:07Z). It had no effect on timing.

## (d) Usage-endpoint throttling is not what spaces the reads

- 429/held lines in `claude-accounts.log` (`grep '429 poll-throttled\|usage poll held'`): **0 on 2026-10-06**. The last was 2026-10-04T17:04:24Z. Per-day counts: 09-22 84, 09-28 36, 10-01 121, 10-02 6, 10-04 90.
- The backoff is `USAGE_BACKOFF_BASE_S = 180`, cap 600 (`:1824-1825`). It holds the usage **poll** only. The wire read is `/v1/messages` and sits outside that throttle (`:2421-2424`), and it fired on every swept tick.
- The read spacing is launchd's exit-anchored 180 s plus the run time. Other callers' sweeps fill in between (next3 read gaps: min 12, p50 189, p90 235, max 275 s).

## Tick cost

- **Wall:** spawn to exit p50 5.57 s, p90 23.2 s, max 55.3 s. Swept took_ms p50 9.4 s. Served p50 0.85 s.
- **Biggest cost driver: the census walk.** 37 of 93 swept ticks logged `working_concurrency: walk exceeded budget_s=15.0`; their took_ms p50 is 18.0 s, against 4.3 s (p90 10.0 s) for the other 56. Load average at measurement was 32 / 67 / 60 on 10 cores (`sysctl vm.loadavg hw.ncpu`).
- **Start-up:** spawn to `t0` is p50 0.34 s, p90 3.0 s, max 12.8 s. This is bash, perl and python import plus `load_cfg`, which `took_ms` does not count.
- **Network and tokens:** a swept tick makes 4 usage-endpoint GETs (0 tokens) and one wire call per near-wall account. Each wire call is ~25 tokens (`:57`). In the window only next3 was near-wall: 71 keepwarm wire reads ≈ 1.8k tokens over 4.4 h, out of 90 next3 reads machine-wide (estimate: 25 × count). A served tick makes no network calls.
- **Rate:** 113 ticks in 21,360 s gives a mean period of 190.7 s, about 453 ticks/day (estimated from the window).

## (e) Near-wall accounts read on every tick, at zero added tokens

- **This already holds for sweeps:** 71/71 swept ticks read next3 (`wire_wanted`, `:1338-1344`, `:2477-2485`). A served tick serves a read at most 90 s old by construction (`--max-age 90`). There is no per-account poll budget that skips a near-wall account.
- **The remaining zero-token staleness is board-side, not read-side:**
  1. Only keepwarm writes the board (`:7818`; plist comment). A fresher sweep by another caller reaches the board only at the next keepwarm tick. Example: the read at 06:03:49 saw `rejected`, but the board kept the 06:01:46 "still accepts work" text until 06:04:47, 58 s later (inferred from served `age_s=51` at the 06:04:47 exit).
  2. A lock-degrade tick (2/113) renders a board from a ~186 s cache while the holder's fresh sweep lands seconds later (05:43:09.9 board against the 05:43:11 sweep). The board then stays on that older data for one more period.
  3. The census-walk overrun puts ~15 s between a wire read and its board write (06:07:56.7 read, 06:08:13.9 board).
- **More reads cannot be had for free.** Every extra near-wall read is one more ~25-token wire call, and shortening StartInterval also adds usage polls against the ~90 s endpoint throttle that caused the 2026-08-11 incident (plist `:60-89`).

## Fixes, with conviction

1. **Stop the shadowing (95%).** At `bin/claude-accounts:5835` and `:5841`, give the lock-wait bound its own name, for example `wedge_at = time.time() + _fresh_lock_wait_s(cfg)` with `if time.time() >= wedge_at:`. `deadline` then stays None for no-`--max-wait` callers, and `_arm_sweep_bound` becomes the no-op it was designed to be. Keepwarm keeps its `alarm(225)` and perl `240`; other callers keep `_arm_hold_ceiling`.
   - Control test, in `tests/claude-accounts-fresh-lock-bound.bats` style: fixture `lock_wait_s: 1` with no cache; a python helper holds the flock for ~3 s and then releases; run `claude-accounts --json` with neither `--fresh` nor `--max-wait`. Assert rc is not 1 and stderr has no `ItimerError`. Before the fix this fails with rc 1 on macOS.
   - Static guard: no `deadline = time.time()` inside `get_data`.
2. **Record wire-status transitions past the 300 s gate (70%).** In `record_utilization` (`:5510`), skip the mtime gate when any row's `wire_{5h,7d}_status` differs from the value in the cache's `prev` snapshot. Simpler variant: skip it when any row carries a non-`allowed` wire status.
   - Growth is bounded to near-wall periods (+~4 rows per sweep during them). The series would then catch the 06:03:49 transition instead of 06:08:11, which is what R3 needs. No tokens, no added reads.
3. **Keepwarm waits for the holder instead of degrading (45%).** Give `--keepwarm` its own longer lock wait (for example 60 s, under its 225 s alarm). The post-lock re-read (`:5857`) would then serve the holder's fresh cache rather than a 186 s grace cache.
   - Effect is 2 of 113 ticks (1.8%) and one stale board period each. The keepwarm process holds nothing while it waits, so it is safe.
4. **Correct the record (80%, docs only).** Plan intake defect 3 should read "sweeps 185.6 s apart (p50); the 6 min figure is `UTIL_MIN_INTERVAL_S`". The plist comment should say StartInterval is exit-anchored (period = 180 + run time), which its "worst-case age = interval + sweep" arithmetic already assumes.

**Alternatives considered and rejected:**
- Shortening StartInterval (adds tokens and usage polls; breaks the 2× throttle margin the plist rules is a correctness knob).
- Catching `ItimerError` (hides a bound-removal bug on other platforms).
- Back to ProcessType Background (the plist records 3h40m starvation at PRI 4).
- Having every sweeper write the board (closes gap (e)1, ≤ one period, 58 s at the incident). It adds `readout_lines` + `apply_burn` to interactive callers at an unmeasured cost; 25% conviction, needs a latency measurement first.

## Open questions and blockers

- Which non-keepwarm callers swept at 05:42:57, 05:57:46, 06:03:49, 06:05:29, 06:12:27, 06:13:36 and 06:20:32 is not attributed. A session ran `claude-accounts --readout` at 06:03:54Z (`bash-commands.log`), which is after the 06:03:49 read, so the 06:03:49 sweep came from something else.
- The board text at 06:04:47 (rendered from the post-rejection cache) was not captured. That it showed `rejected` is inferred from `age_s=51` and the 06:03:49 read.
- The time of the err log's `FreshLockWedged` line is unknown. With keepwarm's `alarm(225)`, a 5 + 240 s wait should be killed first, so that line probably predates the 2026-09-24 deadline (inferred).
- The out log has no timestamps. Aligning it to launchd's log only works while the unified log retains `--info --debug` entries. Adding an ISO `ts=` to the `keepwarm:` line (`:7821`) would make the out log self-timing (zero cost; 75%).
