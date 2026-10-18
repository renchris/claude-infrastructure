# B — `cc-lr move` queue latency at the lr-reset-poller

**Basis.** Every number here is **measured** from one snapshot of `~/.reso/limit-recover/poller.log`, copied to
`/tmp/lri-b/poller.snap.log` at 2026-10-18T02:11:38Z: 216,136 lines, 2026-07-12T02:09:11Z..2026-10-18T02:11:38Z,
3,089 `TICK start`, 49 `MOVE-BATCH started`. No rotated `poller.log*` exists. The helpers are
`/tmp/lri-b/analyze.py` (latency, tick durations), `/tmp/lri-b/gaps.py` (per-tick gaps),
`/tmp/lri-b/segs.py` (per-arm segments) and `/tmp/lri-b/expiry.sh`, each run as `python3 -I …` or `bash …`.

- **Latency** is the `MOVE-BATCH started` timestamp minus the UTC time in the batch id.
- **Percentiles** use the nearest-rank method (the ceil(q·n)-th smallest value), so p99 equals the max when n < 100.
- **Code lines.** `lr-reset-poller.sh:N` means the file at HEAD 2b9d938de. It is byte-identical to the deployed
  `/Users/chrisren/Development/claude-infrastructure/scripts/limit-recover/lr-reset-poller.sh` (checked with `diff -q`),
  so it is the code that wrote this log. The worktree copy now has uncommitted edits (a mid-tick drainer) that shift
  every line after :240. `bin/cc-lr:N` is unchanged in the worktree.

## 1. Queue latency (seconds)

**Classes.** A start is a **tick-start kick** if it comes ≤ 60 s after its tick's `TICK start` line, which is
`lrp_move_kick` at `lr-reset-poller.sh:358`. Otherwise it is a **tick-end kick**, from the EXIT trap at
`lrp_tick_end` `:241-246`. The 60 s cut has no borderline cases: tick-start kicks fell 0-22 s after their tick
began, and tick-end kicks fell 287 s or more after it.

| Population | n | p50 | p90 | p99 | max | min | mean |
|---|---|---|---|---|---|---|---|
| **Overall, all classes** | 49 | 221 | 4001 | 5124 | 5124 | 0 | 919 |
| Overall, tick-start kick | 22 | 3 | 23 | 89 | 89 | 0 | 11 |
| Overall, tick-end kick | 27 | 829 | 4533 | 5124 | 5124 | 67 | 1658 |
| **Last 14 d** (from 2026-10-04T02:11:38Z), all | 49 | 221 | 4001 | 5124 | 5124 | 0 | 919 |
| **Window 2026-10-17T23:00Z..10-18T02:10Z** (by request time), all | 15 | 471 | 4240 | 5124 | 5124 | 9 | 1351 |
| Window, tick-start kick | 6 | 11 | 26 | 26 | 26 | 9 | 16 |
| Window, tick-end kick | 9 | 1650 | 5124 | 5124 | 5124 | 68 | 2241 |
| Window by *start* time (drops the 02:00:22Z request, started 02:11:38Z), all | 14 | 68 | 4240 | 5124 | 5124 | 9 | 1399 |

- **Last 14 days = overall.** The move lane's first batch is 2026-10-06T06:07:03Z, so both rows cover the same 49 starts.
- **One start after the snapshot.** Batch `20261018T021322Z-next4-next-22546` started at 02:13:27Z, a tick-start
  kick with 5 s latency. It is not counted above.
- **Waits longer than the intent lifetime.** Intents expire at request time + `until_idle_s` + 900 s
  (`bin/cc-lr:1484`). Six batches started after that point (checked with `/tmp/lri-b/expiry.sh` against each
  batch's `plan.json`). Four are in the window: `…002443Z…84451`, `…003928Z…31080`, `…004329Z…1739` and
  `…005330Z…69593`. The other two are from 2026-10-11T16:37Z.

**Every start in the window:**

| Batch | Requested (Z) | Started (Z) | Latency | Class | Drained by |
|---|---|---|---|---|---|
| 20261017T235745Z-next4-next-69993 | 23:57:45 | 23:57:54 | 9 | start | tick 23:57:50Z (+4 s) |
| 20261017T235745Z-next4-next-69995 | 23:57:45 | 23:57:55 | 10 | start | tick 23:57:50Z (+5 s) |
| 20261017T235745Z-next4-next-69998 | 23:57:45 | 23:57:56 | 11 | start | tick 23:57:50Z (+6 s) |
| 20261017T235745Z-next4-next-70005 | 23:57:45 | 23:58:04 | 19 | start | tick 23:57:50Z (+14 s) |
| 20261017T235746Z-next4-next-69994 | 23:57:46 | 23:58:12 | 26 | start | tick 23:57:50Z (+22 s) |
| 20261018T000816Z-next4-next-49288 | 00:08:16 | 00:17:12 | 536 | end | EXIT of tick 23:57:50Z |
| 20261018T000922Z-next4-next-71757 | 00:09:22 | 00:17:13 | 471 | end | EXIT of tick 23:57:50Z |
| 20261018T002357Z-next4-next-40187 | 00:23:57 | 00:24:20 | 23 | start | tick 00:23:59Z (+21 s) |
| 20261018T002443Z-next4-next-84451 | 00:24:43 | 01:50:07 | 5124 | end | EXIT of tick 00:23:59Z |
| 20261018T003928Z-next4-next-31080 | 00:39:28 | 01:50:08 | 4240 | end | EXIT of tick 00:23:59Z |
| 20261018T004329Z-next2-next-1739 | 00:43:29 | 01:50:10 | 4001 | end | EXIT of tick 00:23:59Z |
| 20261018T005330Z-next4-next-69593 | 00:53:30 | 01:50:11 | 3401 | end | EXIT of tick 00:23:59Z |
| 20261018T012244Z-next4-next-22836 | 01:22:44 | 01:50:14 | 1650 | end | EXIT of tick 00:23:59Z |
| 20261018T014908Z-next2-next-23285 | 01:49:08 | 01:50:16 | 68 | end | EXIT of tick 00:23:59Z |
| 20261018T020022Z-next4-next-2123 | 02:00:22 | 02:11:38 | 676 | end | EXIT of tick 02:00:18Z |

## 2. Tick durations, last 14 days (1,498 closed ticks)

**Estimator.** A tick ends at the timestamp of the last stamped line between its `TICK start` and the next
`TICK start`. When the tick drained a batch at exit, that line is the tick-end `MOVE-BATCH` line.

**Bias: it is a lower bound.** Everything after `CONSOLIDATED` (`:2067`) logs nothing in the usual case: the reroute
clear `:2221`, the parked loop `:2269-2573` and the EXIT trap. So a tick with no tick-end kick reads short by that
silent tail. The tail can be measured only in the 14 ticks that ended with a tick-end `MOVE-BATCH`: it ran
`CONSOLIDATED` → end in p50 151 s, p90 1724 s, max 2162 s (`segs.py`, segment G).

The upper bound is the next tick's start. 0 `TICK-SKIP` lines exist in all 3,089 ticks, so the ticks did not overlap.

| Statistic | Lower bound (last line − start) | Upper bound (next start − start) |
|---|---|---|
| p50 | 49 | 659 |
| p90 | 288 | 986 |
| p99 | 2448 | 3641 |
| max | 5911 | 11213 |
| mean | 169 | 807 |
| ticks ≥ 600 s / ≥ 1800 s / ≥ 3600 s | 85 / 23 / 6 | — |
| share of wall time inside a tick (sum of lower bounds / span) | 0.21 | — |

For comparison, all 3,088 closed ticks since 2026-07-12 give a lower bound of p50 36, p90 260, p99 1589, max 5911.

**The 10 longest, last 14 days (lower bound):**

| Tick start (Z) | Est. end (Z) | Duration (s) | Next TICK (Z) | Last line of the tick |
|---|---|---|---|---|
| 2026-10-12T00:42:25 | 02:20:56 | 5911 | 03:49:18 | CONSOLIDATED 27 ready → 1 winner(s) |
| 2026-10-07T23:27:19 | 10-08T00:55:29 | 5290 | 01:07:37 | CONSOLIDATED 26 ready → 0 winner(s) |
| **2026-10-18T00:23:59** | 01:50:16 | **5177** (exact, tick-end kick) | 02:00:18 | MOVE-BATCH … 20261018T014908Z-next2-next-23285 |
| 2026-10-11T03:51:11 | 05:14:55 | 5024 | 05:26:59 | NUDGE-SKIP e582464c… |
| 2026-10-11T16:36:10 | 17:53:00 | 4610 (exact, tick-end kick) | 17:54:04 | MOVE-BATCH … 20261011T163727Z-next2-next3-67449 |
| 2026-10-12T03:49:18 | 04:54:31 | 3913 | 05:17:41 | CONSOLIDATED 27 ready → 1 winner(s) |
| 2026-10-16T04:50:55 | 05:49:11 | 3496 | 06:51:07 | CONSOLIDATED 2 ready → 0 winner(s) |
| 2026-10-11T17:54:04 | 18:49:49 | 3345 | 19:02:16 | CONSOLIDATED 27 ready → 1 winner(s) |
| 2026-10-14T08:30:53 | 09:25:52 | 3299 | 09:37:24 | CONSOLIDATED 2 ready → 0 winner(s) |
| 2026-10-17T01:47:45 | 02:40:52 | 3187 | 02:58:49 | CONSOLIDATED 2 ready → 0 winner(s) |

## 3. Wall-time attribution — gaps > 60 s between consecutive log lines

**Top-level order of the tick** (`lr-reset-poller.sh` at HEAD):

1. `TICK start` `:248`
2. reconciler watchdog `:258-273`, whose forks are each bounded at 15 s
3. evidence-GC kick `:291-317`
4. tick-start move kick `:358`
5. definitions and setup `:360-1243`
6. request drain `:1245-1596`
7. engagement audit `:1597`
8. upgrade kick `:1659`, which logs `UPGRADE-DRAIN` at `:1627` or `:1653`
9. resume-debt sweep `:1670-1677`, under `lrp_bounded_long` (`timeout -k 5 60`, `:1607-1609`)
10. lock reap `:1686-1694`, under `lrp_bounded` (`timeout -k 3 15`, `:63`, `:74-77`)
11. census `cc-limited --all --json` `:1802-1804`. **Unbounded.** Its ingest prints `LIMITED-NOWAIT` at `:1760`.
12. claim reaper `cc-limited --reaper --persist` `:1836-1838`. **Unbounded.** It prints `CLAIMED-NOT-LIVE` at `:1837`.
13. transcript walk `:1842-1996`: `find -H <store>/projects -maxdepth 2 -name '*.jsonl' -mmin -2880` over 4 stores,
    then per-file `tail`/`grep` and an `lr-audit.py` per candidate. **Unbounded.**
14. lr-select `:2020-2069`, which prints `CONSOLIDATED` at `:2067`
15. reroute clear `:2221`
16. parked loop `:2269-2573`
17. `exit 0` `:2577`, then the EXIT trap `lrp_tick_end` → `lrp_move_kick` → `MOVE-BATCH started` `:351`

Each store's `projects/` holds 18,101-18,201 entries (measured now with `ls | wc -l`). `parked/` holds 2 `*.json`
records (measured now; this may differ from the window).

### Tick 2026-10-18T00:23:59Z → 01:50:16Z (5177 s, 140 lines, 0 unstamped)

| Gap (s) | Line before | Line after | Arm running |
|---|---|---|---|
| 61 | L215867 00:25:16 `UPGRADE-DRAIN started pid 28325 (…lr-upgrade.sh --drain)` | L215868 00:26:17 `RESUME-DEBT: 40b80c03… escalated` | resume-debt sweep `:1670-1677`. Its output is logged only after it returns, and the 61 s spacing sits on its 60 s bound. |
| 1347 | L215871 00:26:33 `LOCK-REAP rc=124 (logged, tick continues)` | L215872 00:49:00 `LIMITED-NOWAIT 81739d08… (next, cap=unknown)` | **census `cc-limited --all --json`** `:1804` (unbounded), up to the ingest's first row |
| 117 | L215885 00:49:09 `LIMITED-NOWAIT bd0889f1… (next4, cap=unknown)` | L215886 00:51:06 `CLAIMED-NOT-LIVE c060ddcd … age 662h48m` | rest of the ingest `:1805` and page-damp `:1812-1825`, plus **`cc-limited --reaper --persist`** `:1838` (unbounded) |
| 2952 | L215996 00:52:26 `CLAIMED-NOT-LIVE f7351f3b … age 16h14m` | L215997 01:41:38 `CONSOLIDATED 2 ready → 0 winner(s)` | **transcript walk** `:1842-1996` + lr-select `:2020-2069`. No line separates the two. |
| 509 | L215997 01:41:38 `CONSOLIDATED 2 ready → 0 winner(s)` | L215998 01:50:07 `MOVE-BATCH started pid 88156 (20261018T002443Z-next4-next-84451)` | silent tail: reroute clear `:2221`, parked loop `:2269-2573`, `exit 0`, EXIT trap → `lrp_move_kick` |

**Coverage.** The gaps above total 4986 s, 96% of 5177 s.

**Remainder (gaps ≤ 60 s):**
- TICK → first MOVE-BATCH took 21 s. The watchdog logged `PAGE recon backup` at 00:24:00, then ran an osascript
  notification and a kickstart of `com.reso.lr-reconciler` (`:264-270`).
- MOVE-BATCH → UPGRADE-DRAIN took 56 s (setup, request drain, engagement audit, upgrade kick).
- RESUME-DEBT → `LOCK-REAP rc=124` took 16 s.
- The 111 `CLAIMED-NOT-LIVE` lines took 80 s.
- The six tick-end MOVE-BATCH lines took 9 s.

### Tick 2026-10-17T23:57:50Z → 00:17:13Z (1163 s, 137 lines, 0 unstamped)

| Gap (s) | Line before | Line after | Arm running |
|---|---|---|---|
| 63 | L215732 23:58:12 `MOVE-BATCH started pid 95204 (20261017T235746Z-next4-next-69994)` | L215733 23:59:15 `UPGRADE-DRAIN started pid 18008` | setup `:360-1243`, request drain `:1245-1596`, engagement audit `:1597`, upgrade kick `:1659` |
| 64 | L215733 23:59:15 `UPGRADE-DRAIN started pid 18008` | L215734 00:00:19 `RESUME-DEBT: 40b80c03… escalated` | resume-debt sweep (60 s bound, plus a 5 s kill) |
| 812 | L215735 00:00:37 `LOCK-REAP rc=124 (logged, tick continues)` | L215736 00:14:09 `LIMITED-NOWAIT 81739d08…` | **census `cc-limited --all --json`** `:1804` |
| 149 | L215860 00:14:29 `CLAIMED-NOT-LIVE f7351f3b …` | L215861 00:16:58 `CONSOLIDATED 2 ready → 0 winner(s)` | **transcript walk + lr-select** |

**Coverage.** The gaps above total 1088 s, 94% of 1163 s.

**Remainder:**
- The five tick-start MOVE-BATCH lines ran 23:57:54-23:58:12, about 1-8 s per sequential detach.
- The lock reap took 18 s, ending at 00:00:37.
- `LIMITED-NOWAIT` → `CLAIMED-NOT-LIVE` took 6 s.
- The silent tail, `CONSOLIDATED` → tick-end `MOVE-BATCH`, took 14 s (00:16:58 → 00:17:12).

### The same arms across all ticks, last 14 days (`segs.py`)

A segment is counted only where both of its anchor lines exist, so the segments do not sum to tick time.

| Segment (anchors) | Arm | n | p50 | p90 | p99 | max | sum (s) |
|---|---|---|---|---|---|---|---|
| A: TICK → UPGRADE-DRAIN | watchdog, move kick, setup, request drain, audit, upgrade kick | 1058 | 1 | 26 | 108 | 692 | 9,986 |
| B: UPGRADE-DRAIN → RESUME-DEBT | resume-debt sweep (60 s bound) | 1026 | 2 | 29 | 62 | 64 | 9,294 |
| C: RESUME-DEBT → LOCK-REAP | lock reap (15 s bound) | 1256 | 15 | 16 | 18 | 245 | 19,434 |
| D: LOCK-REAP → first census row | `cc-limited --all --json` | 1278 | 6 | 71 | 788 | 1514 | 56,613 |
| E: last census row → first CLAIMED-NOT-LIVE | ingest tail + `cc-limited --reaper` | 1485 | 0 | 2 | 36 | 117 | 2,792 |
| F: last CLAIMED-NOT-LIVE → CONSOLIDATED | transcript walk + lr-select | 1493 | 20 | 112 | 1900 | 5711 | 121,725 |
| G: CONSOLIDATED → tick-end MOVE-BATCH | reroute clear + parked loop + EXIT | 14 | 151 | 1724 | 2162 | 2162 | 7,145 |

**Shares of the 253,095 s total lower-bound tick time:** F is 48% and D is 22%.

**Ticks of 30 min or more.** There are 23. F was 751-5,711 s in the 21 that have both anchors (median about 2,100 s).
D was 71-1,514 s in the 19 that have both. The other 2 ticks lack an F anchor.

**Load in the window.** 515 at 20:13 CDT (01:13Z) and 438 at 20:24 CDT, on 10 cores with 0% idle
(`docs/research/load-reinvestigate-2026-10-17/FINDINGS.md:11`, `:23-24`). That is inside the 00:23:59Z tick.

## 4. `LOCK-REAP rc=124`

**What runs.** `lr-reset-poller.sh:1686-1694`:
`_lk_out="$(LR_STATE_DIR="$STATE" lrp_bounded python3 "$LR/lr-lock.py" reap 2>&1)" || log "LOCK-REAP rc=$? …"`.

**The bound.** `lrp_bounded` (`:74-77`) is `timeout -k 3 "$LRP_TIMEOUT_S"`, with `LRP_TIMEOUT_S=${LRP_OSA_TIMEOUT_S:-15}`
(`:63`). The live `~/Library/LaunchAgents/com.reso.lr-reset-poller.plist` sets only `LR_POLLER_AUTOFIRE`, so the
bound is 15 s, then SIGKILL 3 s later. rc 124 is timeout(1)'s "timed out" status, so `rc=124` means the reap was
killed at 15 s.

**What the reap does.** `scripts/limit-recover/lr-lock.py` `cmd_reap` (`:569-604`) walks every
`locks/*.lock`. There are 111 now (`ls`). It classifies each one with `classify` (`:180`), whose transcript lookup
is `glob(<store>/projects/*/<sid>.jsonl)` (`:140-147`) over ~18.1k-entry `projects/` dirs. It archives
ORPHAN/ABANDONED locks older than the TTL of 21,600 s (`:108`).

**How often it times out** (measured with `awk`/`grep -c` on the snapshot):

| Period | Ticks timing out | Share |
|---|---|---|
| Since the first occurrence, 2026-09-24T00:47:06Z | 1,469 of 2,674 | 55% |
| Last 14 days | 1,289 of 1,499 | 86% |
| Window | 6 of 6 | 100% |

0 `LOCK-REAP expired …` lines have ever been logged.

**Cost per tick.** About 15-18 s (segment C: p50 15, p90 16). It is a constant tax on every tick, not a cause of
the 20-85 min ticks.

## 5. Adversarial check: is any queued batch's wait not explained by the tick-boundary drain?

- **MOVE lines.** `grep -c MOVE-SKIP` gives 0. Neither `MOVE-BATCH … could not be started` nor `could not be claimed`
  appears. `grep -c TICK-SKIP` gives 0. Every `MOVE-*` line in the log is a `MOVE-BATCH started`.
- **Batch dirs.** `move/` holds 50 batch dirs. 49 of them match the 49 started lines one-to-one, and every one has
  `request.claimed.json`. The 50th is the post-snapshot `…021322Z…22546`, which started at 02:13:27Z.
  `move/requests/` is empty now.
- **Tick-end starts (27 of 27).** Each request arrived inside the tick that drained it. Each `MOVE-BATCH` is among
  that tick's final lines, followed only by more `MOVE-BATCH` lines and then the next `TICK start` (checked by a
  python pass). So the latency equals the time the in-flight tick had left, and none waited for a later tick.
  Throughout those waits `cc-lr` kept re-sending a plain kickstart every 15 s while the request was unclaimed
  (`bin/cc-lr:1509-1516`; the wait is `CC_LR_MOVE_WAIT_S`, default 600 s, `:1394`), yet no tick started early.
  That fits a no-op kickstart on a running job.
- **Tick-start starts (22 of 22).** A `TICK start` follows the request by 0-6 s, the kickstart starting an idle
  job, with one exception. Batch `20261006T060534Z…64630` waited 89 s: it arrived during the 06:05:16Z tick,
  before the tick-end kick and cc-lr's 15 s re-kick existed (both added in 7368bd1d4, 2026-10-06T07:47:31Z).
  The tick that ran it at 06:07:03Z had another trigger.
- **In-tick delays in the window are explained:**
  - The 23:57:45Z cohort of five started 4-22 s after the tick began, because each batch's detach runs in sequence
    (`:337-356`).
  - The 00:23:57Z batch started 21 s after the tick began, because of the watchdog's page and reconciler kickstart
    (`:264-270`).
- **Caveat on the clock start.** The batch id is stamped at `bin/cc-lr:1470`, before the plan and intents are
  written. The request file is written at `:1496` and the kick is sent at `:1501`. So each latency includes
  cc-lr's own write time, which is only a few seconds (tick-start latencies of 0-3 s when the poller was idle).

**Result: no unexplained latency found.**

## Conclusion

1. Queue latency has two modes. If the poller is idle, the kickstart starts a tick and the batch starts in p50 3 s
   (22 of 49). If a tick is running, the kickstart and every 15 s re-kick do nothing, and the batch waits for the
   EXIT-trap drain (`lr-reset-poller.sh:241-246`): p50 829 s, max 5124 s (27 of 49; 9 of 15 in the window).
2. Every one of those waits equals the remaining time of the tick in flight. There are no MOVE-SKIP lines, no
   claim failures and no TICK-SKIP lines, and 49 of 49 batches were claimed. Six waits outlived their intents
   (`bin/cc-lr:1484`), four of them in the window.
3. Tick length is the latency. Over 14 days ticks run p50 49 s but p99 2448 s and max 5911 s, and 23 ran 30 min
   or more. The 00:23:59Z tick ran 5177 s: transcript walk + lr-select 2952 s, census 1347 s, silent tail 509 s,
   reaper 117 s. Gaps over 60 s account for 96% of it.
4. The long arms are the unbounded ones: `cc-limited --all --json` `:1804`, `cc-limited --reaper` `:1838`, the
   transcript walk `:1842-1996` and the parked loop `:2269-2573`. The bounded arms (resume-debt 60 s, lock reap
   15 s) cost about 80 s per tick. Load was 438-515 on 10 cores during the window.
5. `LOCK-REAP rc=124` means `timeout -k 3 15 python3 lr-lock.py reap` was killed at 15 s. That happened in 86% of
   ticks in 14 days and in 6 of 6 in the window, and no expiry has ever been logged. It adds about 16 s per tick
   and does not cause the long waits.
