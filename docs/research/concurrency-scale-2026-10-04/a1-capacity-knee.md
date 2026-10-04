# A1: Capacity knee for concurrent Claude Code sessions (M1 Max, 10 cores, 64 GB)

Date: 2026-10-04. Data: `~/.claude/logs/capacity-alarm.jsonl` plus its 2 rotated .gz files (62,314 rows, 2026-07-30 to 2026-10-04; `load_*` fields exist from 2026-08-07T08:58Z, so 54,390 usable rows), `compressor-sentinel.jsonl` plus 4 .gz (380,522 ten-second ticks from 2026-08-15), `claude-crashes.jsonl` (4,924 rows), `kalloc-sandbox-churn-2.jsonl`, `qos-census.jsonl`, `last reboot`, and two live read-only snapshots (`top`, PID delta).
Every query is a script in `/tmp/concurrency-scale/` (`a1_*.py`), named next to each table. Labels: **[M]** = measured by the named query, **[I]** = inferred.

**The census unit.** `sessions` counts resident `claude` process trees: `.../claude-code/bin/claude.exe` plus `.../node_modules/.bin/claude`, and that includes headless `claude -p` workers and teammates (`scripts/lib/spawn-presence.sh:157-187`). In-process subagents are **not** counted (`spawn-presence.sh:164-166`: "background subagents are in-process"). No log here counts agents, so the operator's "~100 agents at ~15 sessions" cannot be checked from telemetry.

---

## 1. Findings

1. **CPU saturates first. Memory is nowhere near its limit at any session count observed.** Across all session buckets the 5th-percentile headroom stays at 10 GB or more. The p95 compressor-segment use stays at or below 40% (alarm is 70%), and memory-pressure level ≥2 occurs in ≤8% of minutes. The load rung, by contrast, is over its 2.5/core alarm for 19–58% of the time once there are 10 or more sessions. [M] (§2, §3)
2. **The knee is about 12–15 sessions, and it is a jump in how often bursts happen, not a step in baseline load.**
   - In the current boot era (from 2026-09-16), the share of time with load ≥25 (≥2.5/core) jumps from 0.25 at 10–11 sessions to 0.48–0.61 at 12–15.
   - A late 10-second loop is the cleanest "felt lag" proxy we have. Its tick runs ≥5 s late 7× more often at 15–19 sessions than at 10–14 (0.34% vs 0.05%).
   - Within the same day, burst probability was higher at 12–17 sessions than at 5–11 on **21 of 26 days** (sign-test p≈0.001). That controls for era and for the day's workload. [M] (§2, §4)
3. **Load is not linear in sessions; bursts that have nothing to do with the session count dominate it.**
   - Session count explains **2.0%** of load_1m variance (levels R²). In log space it explains 6.5%.
   - 95.2% of the variance sits *inside* a fixed session count.
   - The direct marginal cost of one more resident session is **0.5–0.9 load units** (first differences at a 5–10 min lag, Aug–Sep). That is about 0.05–0.09 of a core.
   - What sessions mainly add is *how often* the box hits a large burst. [M] (§4)
4. **The bursts are process-creation churn: mostly shell scripts spawned by hooks, pollers and tools, not `claude` itself.** In the live snapshot (load 140, 0% idle, 38% sys):
   - 34 `claude.exe` processes used **0.53 cores in total**.
   - All visible processes summed to only 4.0 of 10 cores. The other ~6 cores went to processes that lived less than the 5 s sample window.
   - Fork rate was **~690 per second** (PID delta).
   - XprotectService (0.27 cores), syspolicyd (0.10) and kernel_task (0.31) are the per-exec security and kernel tax.
   - Births logged on 09-30: bash 48%, sleep 14%, git 7%, ps 4%.

   [M] for the snapshot and birth counts; [I] for "unseen CPU = short-lived execs" (§5)
5. **Crashes come in two classes, and neither has a session-count threshold.**
   - **Session-level crashes:** the rate per session-hour is flat across session buckets (1.9–5.4 per 100 session-h) and rises **7×** with load (1.0 at load <10, up to 7.2 at load 80–160).
   - **Kernel panics and forced reboots:** single-process memory runaways caused these (clang-format at 13–19 GB each, fseventsd at 40 GB, node, a 65 GB swap blow-up). They happened at 5–22 sessions.
   - "Crashes at ~15" is largely a base-rate effect: the box spends its median time at 15 sessions (13 in the current era). [M] for the rates and reboot rows; [I] for the base-rate reading (§6)
6. **The load cost per session is about 2.7× higher now than in August.** Hour-weighted mean load per session count is 10.0 + 0.73·sessions for Aug 7–Sep 16, against 11.0 + 1.94·sessions from Sep 16. Ambient load at 2–4 sessions is unchanged (~9–10). [M] (§4)

---

## 2. Bucket table (time-weighted; each row weighted by the interval it represents, capped at 600 s)

Query: `python3 /tmp/concurrency-scale/a1_tw.py [since]`.

Time-weighting matters here. The sampler slows under load: median gap is 66 s when the previous load was <10, 159 s at 50–100, and 213 s at >100 (`a1_tw.py` gap block / inline query in §7). So an unweighted row count under-represents bad periods by about 3×. [M]

### All data since 2026-08-07 (54,390 rows)

| sessions | rows | hours | load/core p50 | p95 | % time ≥2.5/core | compressor GB p50 | p95 | swap GB p50 | p95 | coal_procs p50 | p95 | coal_true p50 | p95 | headroom GB p5 | p50 | seg% p95 | sampler gap p90 s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0-4 | 3942 | 74 | 0.8 | 1.7 | 3% | 0.0 | 4.5 | 0.0 | 0.0 | 52 | 146 | 39 | 87 | 30.6 | 37.6 | 4.7 | 70 |
| 5-9 | 8615 | 179 | 1.2 | 3.7 | 10% | 3.1 | 14.2 | 0.0 | 3.9 | 86 | 797 | 135 | 231 | 20.3 | 29.9 | 9.7 | 82 |
| 10-14 | 15093 | 363 | 1.5 | 5.6 | 19% | 4.5 | 10.9 | 1.6 | 6.5 | 106 | 805 | 193 | 383 | 18.7 | 26.9 | 13.9 | 123 |
| **15-19** | 13660 | 334 | **1.7** | **13.2** | **29%** | 5.8 | 18.5 | 1.6 | 6.8 | 132 | 678 | 243 | 440 | 14.0 | 26.0 | 23.3 | 127 |
| 20-24 | 8388 | 208 | 1.9 | 9.0 | 31% | 6.9 | 16.8 | 1.5 | 6.8 | 182 | 624 | 288 | 457 | 14.5 | 25.8 | 20.9 | 129 |
| 25-29 | 2087 | 59 | 2.3 | 13.0 | 46% | 6.7 | 24.2 | 1.6 | 8.4 | 231 | 528 | 381 | 542 | 12.3 | 25.3 | 27.9 | 146 |
| 30-34 | 1499 | 44 | 2.1 | 11.6 | 43% | 6.4 | 16.6 | 0.0 | 8.4 | 252 | 375 | 419 | 525 | 16.8 | 27.6 | 18.0 | 147 |
| 35-44 | 539 | 17 | 2.8 | 23.0 | 57% | 4.1 | 12.8 | 0.0 | 8.8 | 333 | 449 | 516 | 652 | 21.0 | 26.1 | 13.2 | 169 |
| 45-60 | 567 | 10 | 1.0 | 3.7 | 9% | 2.3 | 2.6 | 0.0 | 0.0 | 234 | 355 | – | – | 27.5 | 32.3 | 13.2 | 64 |

### Current boot era, since 2026-09-16T21:30Z (15,000 rows)

| sessions | hours | load/core p50 | p95 | % time ≥2.5/core | compressor GB p50/p95 | swap GB p50/p95 | coal_procs p50/p95 | headroom p5/p50 | seg% p95 | sampler gap p90 |
|---|---|---|---|---|---|---|---|---|---|---|
| 0-4 | 39 | 0.9 | 1.5 | 2% | 0.8 / 4.7 | 0.0 / 1.0 | 124 / 467 | 31.4 / 35.5 | 4.8 | 71 |
| 5-9 | 91 | 1.2 | 4.9 | 15% | 3.2 / 8.1 | 0.9 / 6.9 | 208 / 814 | 20.8 / 29.6 | 9.9 | 95 |
| 10-14 | 94 | 1.8 | 18.2 | 35% | 6.6 / 15.9 | 0.9 / 4.7 | 532 / 907 | 16.3 / 24.3 | 20.6 | 152 |
| **15-19** | 87 | **2.5** | 16.2 | **50%** | 5.1 / 25.4 | 2.7 / 14.6 | 180 / 845 | **10.3** / 27.4 | **39.5** | 179 |
| 20-24 | 48 | 3.0 | 18.5 | 58% | 5.7 / 19.4 | 2.6 / 8.4 | 468 / 778 | 12.1 / 24.3 | 26.8 | 223 |
| 25-29 | 17 | 3.0 | 16.5 | 53% | 1.0 / 12.4 | 2.5 / 5.9 | 234 / 635 | 19.9 / 33.5 | 25.3 | 192 |
| 30-34 | 17 | 2.9 | 14.9 | 54% | 6.3 / 7.9 | 0.0 / 0.0 | 228 / 371 | 26.1 / 33.1 | 8.6 | 219 |
| 35-44 | 5 | 6.5 | 28.3 | 89% | 5.2 / 7.4 | 0.0 / 0.0 | 379 / 458 | 26.4 / 28.0 | 7.5 | 838 |

Notes [M]:
- The 45–60 row is 10 hours from 08-10 and 08-17 and has low load. Those were most likely idle or stale resident sessions; it is not evidence of a second capacity regime.
- In the current era the median load/core reaches the 2.5/core alarm at 15–19 sessions.

---

## 3. Which resource crosses its threshold first

Query: `a1_rungs.py`, % of rows crossing each rung. Thresholds are taken from the row fields (`load_warn/alarm_per_core` 1.5/2.5, `warn_gb/alarm_gb` 8/3, `seg_warn_pct` 45, `coal_warn` 500, `swap_delta_floor_mb` 256, `proc_warn_gb` 3, `kalloc_warn_gb` 4, `swapfile_warn` 12).

| sessions | load ≥1.5 | **load ≥2.5** | headroom <8 | headroom <3 | seg ≥45 | coal ≥500 | swapΔ >256 MB | pressure ≥2 | max proc ≥3 GB | kalloc ≥4 GB |
|---|---|---|---|---|---|---|---|---|---|---|
| 0-4 | 7.1 | 2.0 | 0.0 | 0.0 | 0.0 | 1.4 | 0.0 | 0.0 | 1.6 | 2.0 |
| 5-9 | 28.7 | 6.4 | 0.0 | 0.0 | 0.0 | 22.1 | 0.3 | 0.0 | 26.4 | 36.6 |
| 10-14 | 43.0 | 12.1 | 0.2 | 0.0 | 0.0 | 10.1 | 0.3 | 0.3 | 11.6 | 47.5 |
| 15-19 | 50.2 | 17.5 | 0.0 | 0.0 | 0.0 | 4.0 | 1.0 | 1.8 | 14.5 | 20.4 |
| 20-24 | 58.7 | 21.0 | 0.0 | 0.0 | 0.1 | 7.3 | 0.6 | 2.1 | 11.9 | 14.8 |
| 25-29 | 65.5 | 30.3 | 0.0 | 0.0 | 0.0 | 3.6 | 1.7 | 4.8 | 22.1 | 3.4 |
| 30-34 | 62.6 | 27.6 | 0.5 | 0.0 | 0.0 | 0.7 | 0.4 | 0.6 | 32.4 | 2.6 |
| 35-44 | 66.2 | 34.7 | 0.9 | 0.0 | 0.0 | 0.0 | 0.9 | 0.2 | 45.5 | 1.5 |

(Unweighted row %, all eras. The kalloc rung only exists from 09-10; it tracks uptime, not sessions, per `docs/research/kalloc-ratchet-2026-10.md` §Answer 4.)

- **The load rung is the only one that rises steadily with sessions, and it is the first to cross.** [M]
- The memory rungs (headroom, pressure, segments, swap delta) cross in ≤5% of rows at any session count. [M]
- "Max single process ≥3 GB" also climbs with sessions (11.6% → 45.5%). More sessions mean more tool processes, so a runaway outlier becomes more likely. That outlier is the mechanism behind every recorded panic (§6). [M] for the rates, [I] for the mechanism
- **Memory as a function of sessions:** headroom slope −0.24 GB/session (R² 0.07), compressor +0.14 GB/session (R² 0.055) since 07-30. In the current era the headroom slope is −0.04 GB/session (R² 0.001). The script's own `per_session_mb_est` median is 706–816 MB. Linear extrapolation reaches headroom 8 GB at about 104 sessions (all eras). The script's `est_room_sessions` reads about 38–40 *more* sessions. Memory therefore binds somewhere between about 40 and 100 more sessions. CPU binds at about 12–15. [M] for slopes (inline query in §7); [I] for the extrapolation

---

## 4. Is load linear in sessions?

Query: `a1_stats.py`, `a1_knee.py <since> <until>`, and the lagged-difference query in §7.

| Estimator | Value | Reading |
|---|---|---|
| Levels OLS load_1m ~ sessions (n=54,390) | slope 0.444, **R² 0.020** | Not identified: bursts swamp it [M] |
| Fit on per-session medians (≥100 rows/level) | 0.199/session, R² 0.24 | Baseline barely moves [M] |
| Fit on per-session p90 | 0.892/session | The tail moves about 4.5× faster than the median [M] |
| Hour-weighted mean, Aug 7–Sep 16 | 10.03 + **0.73**·sessions | [M] |
| Hour-weighted mean, Sep 16→ | 11.01 + **1.94**·sessions | 2.7× per-session cost now [M] |
| First difference, 1 min | 0.36 (R² 0.001) | Attenuated by load-average smoothing [M] |
| First difference, 5 / 10 min lag, Aug–Sep | **0.78 ± 0.06 / 0.94 ± 0.05** (trimmed: 0.49 / 0.51) | The marginal per *resident* session [M]; s.e. understated because windows overlap [I] |
| First difference, 5 / 10 min, Sep 16→ | 0.49 ± 0.11 / 0.72 ± 0.10 | [M] |
| Variance inside a fixed session count | 589.2 of 618.9 = **95.2%** | [M] |

**Burst probability by exact session count in the current era** (time-weighted, ≥3 h per level; `a1_knee.py 2026-09-16T21:30 2026-10-05`):

| sessions | 5 | 7 | 9 | 10 | 11 | **12** | **13** | 14 | 15 | 16 | 18 | 20 | 22 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| P(load ≥25) | 0.09 | 0.09 | 0.19 | 0.26 | 0.25 | **0.48** | **0.61** | 0.36 | 0.57 | 0.43 | 0.69 | 0.47 | 0.72 |
| P(load ≥100) | 0.00 | 0.01 | 0.04 | 0.06 | 0.06 | 0.11 | 0.24 | 0.11 | 0.08 | 0.09 | 0.10 | 0.10 | 0.10 |

- In the Aug–Sep16 era, P(≥25) stays at or below 0.19 through 14 sessions, reaches 0.27 at 15, sits at 0.22–0.31 for 18–22, and 0.35–0.72 at 25+. So that era's knee is around 15, against around 12 now. [M]
- **Paired within-day test:** P(load ≥25) at 12–17 sessions exceeded P at 5–11 sessions on 12/16 days in Aug–Sep16 and 9/10 days after 09-16, with median differences of +0.04 and +0.18. [M] (inline query, §7)

**Answer to (a):** load does not grow linearly in sessions. The baseline grows by about 0.2 load per session. Each session's direct cost is about 0.5–0.9 load. What grows with sessions is the probability of a burst, roughly +1.3 percentage points of ≥2.5/core time per session over the record. That curve steepens at about 12–15 sessions.

---

## 5. Residual variance: what explains load at a fixed session count

Query: `a1_resid.py`. The residual is log(load+1) minus the median for that session count; "x" is the load multiple relative to that median.

**Important limit:** `top_procs` is the top 3 processes by **RSS** (`scripts/capacity-alarm.sh:752,826`), not by CPU. It can mark *conditions* that come with bursts. It cannot attribute CPU.

| Covariate | r with residual | n |
|---|---|---|
| coal_true_procs (process count in the terminal coalition) | **0.275** | 37,680 |
| compressor_gb | 0.197 | 54,391 |
| headroom_gb | −0.196 | 54,391 |
| coal_procs | 0.172 | 54,391 |
| max_proc_gb | 0.159 | 54,391 |
| swap_used_mb | 0.122 | 54,391 |
| uptime_days / kalloc1024_gb / ptys_used | −0.09 / −0.04 / −0.01 | — |

Process count beats session count as a load predictor: load ~ coal_true_procs R² 0.071 against load ~ sessions R² 0.031 on the same rows. [M]

**top_procs present at elevated residual** (≥40 rows):

| process in top-3 RSS | rows | load multiple vs median-for-N | P(≥3× median) |
|---|---|---|---|
| coreaudiod (23–27 GB leak, 09-25 and 09-29) | 249 | **×3.90** | 0.58 |
| Google (Chrome) | 64 | ×2.95 | 0.39 |
| mds_stores / mds (Spotlight) | 125 / 91 | ×2.77 / ×2.50 | 0.49 / 0.21 |
| ugrep | 107 | ×1.91 | 0.21 |
| ffmpeg | 215 | ×1.89 | 0.21 |
| next-server | 3400 | ×1.40 | 0.11 |
| fseventsd (8–40 GB on bad days) | 1719 | ×1.30 | 0.07 |
| tsserver | 4817 | ×1.25 | 0.10 |
| qemu-system-aarch64 (7.4 GB VM) | 3957 | ×1.13 | 0.06 |
| claude.exe as the largest RSS | 745 | ×1.07 | 0.05 |
| Cursor / locationd / Finder / XProtectRemediator | — | ×0.70–0.97 | ≤0.02 |

Local-hour effect: the residual runs ×1.11–1.25 from 20:00 to 02:00 and ×0.89–0.93 from 07:00 to 10:00. [M]

**Live CPU attribution, 2026-10-04 ~06:55Z** (read-only `top -l 2 -s 5`, aggregated by command; PID-delta over 10 s):
- Load 140 (1-minute average); CPU 62% user, 38% sys, **0% idle**. 1,464 processes, 88 running, 215 bash, 195 `<defunct>`, 47 `sleep`. [M]
- Visible CPU totals **402% of 1000%**: Chrome helpers 157%, **claude.exe ×34 = 52.8%**, kernel_task 31%, WindowServer 29%, XprotectService 27%, grep 26%, fseventsd 11%, syspolicyd 10%, node ×33 = 9%, bash ×212 = 3%. [M]
- **Fork rate: about 690 process creations per second** (6,925 PIDs in 10.0 s). [M], assuming macOS allocates PIDs sequentially [I]
- The remaining ~600% of CPU belongs to processes that exited inside the 5 s window: fork, exec, dyld, the XProtect/syspolicyd/AMFI checks, exit. [I]
- Lower-bound birth mix over 1 h on 2026-09-30, from a 1 s `ps` poll that misses most short-lived processes (`kalloc-sandbox-churn-2.jsonl`, 173 windows, 71,934 births, ≥20/s): bash 48.2%, sleep 13.8%, git 7.3%, ps 3.8%, jq 3.1%, Python 2.6%, sed/awk/grep 5.8%, node 1.2%. [M]
- Bats test runs (`qos-census.jsonl`, 4,734 joined minutes) shift median load by only +0.2 to +0.7 at matched session counts. They are not the burst driver. [M]

**Answer to (c):** about 95% of load variance sits inside a fixed session count. That variance tracks process count, which correlates with the residual better than any other logged field. It also comes with memory-pathology processes (coreaudiod and fseventsd leaks, Spotlight, VMs, Chrome). Live, Claude's own processes are about 5% of the box's CPU. The bulk is short-lived exec churn plus the per-exec security tax.

---

## 6. Crashes

Query: `a1_crash.py`; reboots from `last reboot` (local CDT, +5 h = UTC); the inline reboot-join query in §7.

**Session-level crash ledger** (`claude-crashes.jsonl`, class=CRASH since 08-07: 3,062 rows in 423 clusters).
- 73 "mass-death" clusters (≥5 crashes chained within 120 s) hold 2,529 rows.
- The largest are 398, 387, 205, 199 and 189 *distinct* sids within 50–85 min (09-24 and 09-25). Nearly all are `cause:abrupt-unknown`, which is the watchdog's "unsure ⇒ CRASH" catch-all (`hooks/lead-crash-watchdog.sh:143-144`; `scripts/compressor-sentinel.sh:194-196` notes 77% are unattributed).
- These clusters line up with high-load episodes #3, #6, #16, #19 and #20 in §8. [M] for the overlap; [I] that they are short-lived headless sessions and not interactive leads

Crashes outside mass clusters, per 100 session-hours:

| sessions | session-h | crashes | /100 session-h | | load_1m | session-h | crashes | /100 session-h |
|---|---|---|---|---|---|---|---|---|
| 0-4 | 203 | 5 | 2.46 | | 0-10 | 3382 | 34 | **1.01** |
| 5-9 | 1281 | 69 | 5.39 | | 10-20 | 8707 | 138 | 1.58 |
| 10-14 | 4485 | 95 | 2.12 | | 20-40 | 4971 | 168 | 3.38 |
| 15-19 | 5635 | 109 | 1.93 | | 40-80 | 1759 | 93 | 5.29 |
| 20-24 | 4494 | 142 | 3.16 | | 80-160 | 821 | 59 | **7.19** |
| 25-29 | 1562 | 62 | 3.97 | | 160+ | 538 | 31 | 5.76 |
| 30-34 | 1392 | 35 | 2.51 | | | | | |

The crash rate is flat in sessions and rises 7× in load. [M]

**Lag proxy.** This is the compressor-sentinel 10 s loop arriving ≥5 s late (`el` ≥15), joined to the capacity row for that minute (inline query, §7):

| sessions | 0-4 | 5-9 | 10-14 | **15-19** | 20-24 | 25-29 | 30-60 |
|---|---|---|---|---|---|---|---|
| % ticks ≥5 s late | 0.02 | 0.06 | 0.05 | **0.34** | 0.22 | 0.44 | 0.52 |

| load_1m | 0-10 | 10-20 | 20-40 | **40-80** | 80-160 | 160+ |
|---|---|---|---|---|---|---|
| % ticks ≥5 s late | 0.00 | 0.01 | 0.07 | **1.00** | 3.34 | 15.57 |

Lag becomes measurable at load ≥40 (4/core), and the session step is at 15. [M]

**Unclean reboots and panics: the last capacity row before each.**

| Reboot (UTC) | last row | sessions | load_1m | headroom GB | compressor GB | swap GB | seg % | largest proc |
|---|---|---|---|---|---|---|---|---|
| 08-05T07:19 | 07:13 | 5 | (not yet logged) | 24.5 | 10.9 | 0.4 | 15.2 | node 2.7 GB |
| 08-09T10:39 | 10:33 | 13 | 17.9 | 27.4 | 3.8 | 1.1 | 5.0 | WindowServer |
| 08-09T11:18 | 11:09 | 22 | **271** | 10.8 | 32.3 | **29.6** | **66.5** | node 3.7 GB |
| 08-14T05:42 | 04:22 | 8 | 13.1 | 26.9 | 13.7 | 0.0 | 13.8 | node 6.6 GB |
| 08-25T03:02 (panic #5) | 02:58 | 16 | **348** | 8.3 | 25.0 | **65.2** | **91.2** | WindowServer |
| 09-16T20:50 (panic P1) | 20:47 | 17 | 31.7 | 8.5 | 25.4 | 12.3 | 38.7 | clang-format 13 GB ×N |
| 09-16T21:28 (panic P2) | 21:25 | 10 | 55.5 | 17.7 | 23.6 | 0.0 | 30.6 | clang-format 19 GB ×N |
| 09-30T20:26 | 20:24 | 21 | 103 (378 in prior 60 min) | 11.9 | 19.4 | 22.4 | 42.1 | **fseventsd 40 GB** |

- Panics happened at 5–22 sessions, median about 16.
- The load immediately before them (13–348) sits *inside* the survived range: 836 on 09-26 at 14 sessions was survived.
- Every death with data shows a memory-side precursor (swap explosion, segments at 39–91%, or a single runaway process). [M]

The box's median time is at 15 sessions (time-weighted quartiles 11 / 15 / 20 / 25 since 08-07; 8 / 13 / 18 / 24 since 09-16). So "crashes at ~15" is largely where the box usually runs. [M] for quartiles, [I] for the attribution

---

## 7. Prior conclusions: confirmed or contradicted

| Prior claim (file) | Status now |
|---|---|
| Ambient load is about 87% of the numerator; load swings 2× at constant N (`load-ceiling-derivation-2026-08-24.md` §1.3; `max-load-per-core-derivation-2026-08-25.md` §4.1–4.2) | **CONFIRMED and strengthened.** 95.2% of load variance is inside a fixed session count. Load reached 836 at 14 sessions (09-26T04:40Z). Live, claude.exe is about 5% of CPU (prior: 4.2–4.7%). [M] |
| Marginal load per session ≈0.2 working / 0.04 resident (`load-ceiling-derivation-2026-08-24.md` §1.1) | **CONTRADICTED (too low).** First differences give 0.5–0.9 per *resident* session at 5–10 min lag. That fits the 09-08 measurement of 2.390 ± 0.533 per *active* session (commit `7078dfa83`) if about a quarter to a third of sessions are active. [M] for the values; [I] for the reconciliation |
| Level OLS cannot identify the marginal; use first differences (`marginal-load-per-session-2026-08-25.md` §2–4) | **CONFIRMED.** Level slope 0.444 at R² 0.020; median-fit 0.199; first difference 0.5–0.9. Same spread pattern. [M] |
| No load/core threshold separates fatal from survived (`max-load-per-core-derivation-2026-08-25.md` §1) | **CONFIRMED for kernel panics** (pre-death load 13–348, survived up to 836). **Refined:** load *does* separate lag (sentinel lateness 0% below 20 → 15.6% at ≥160) and session-level crash rate (1.0 → 7.2 per 100 session-h). It is a lag signal, not a panic signal. [M] |
| Deaths are compressor/memory-side, invisible to load (`max-load-per-core-derivation` §4.3) | **CONFIRMED** for every reboot with data (table §6). [M] |
| 2.0/core admission ceiling = "busy-box speed bump" | Now refuses about 50% of time at 15–19 sessions in the current era (median 2.5/core). [M] |

Inline queries cited above (same loader `a1_load.py`):
- **Sampler gap vs load:** for each row, the gap to the next row grouped by the previous row's load_1m. Gives medians of 66 / 69 / 107 / 159 / 213 s for loads <10 / 10–25 / 25–50 / 50–100 / >100.
- **Lagged first difference:** `bisect` to the row at t+5 or t+10 min (requiring ≤lag+120 s), then OLS of Δload_1m on Δsessions. Trimmed variant: |Δload| ≤50.
- **Paired within-day test:** per UTC date, the time-weighted P(load_1m ≥25) at sessions 5–11 against 12–17, over days with ≥1 h in both bands.
- **Memory slopes:** OLS of headroom_gb, compressor_gb, active_gb and wired_gb on sessions for three windows (07-30→, 09-16→, 09-30→).
- **Sentinel lag:** each sentinel tick joined to the capacity row of the same UTC minute; `el` ≥15 and ≥30 counted; `el` >600 dropped as sleep/wake gaps.
- **Reboot join:** the last capacity row before each `last reboot` time +5 h, plus the 60-min max load and max sessions.

---

## 8. Worst periods, for the outcome-ledger join

Query: `a1_ep2.py`. An episode is a run of rows with load_1m ≥50, with gaps ≤15 min. Severity = Σ(load−50)·minutes. There are 428 episodes; the top 25 hold 50% of all severity. Full list (JSON): `/tmp/concurrency-scale/a1_episodes.json`. [M]

| # | start UTC | end UTC | peak load (at) | sessions min-max (@peak) | max comp GB | max swap GB | min headroom | top RSS @peak |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-09-26T03:22:29Z | 2026-09-26T05:22:31Z | **836** (04:40) | 13-17 (14) | 19.5 | 1.0 | 10.9 | qemu 7.4G, next-server |
| 2 | 2026-10-04T04:56:44Z | 2026-10-04T06:51:35Z (ongoing) | 386 (05:44) | 20-23 (21) | 11.8 | 1.8 | 20.7 | Chrome 2.0G; coal_true 691 |
| 3 | 2026-09-24T20:06:41Z | 2026-09-24T21:37:35Z | 456 (20:06) | 12-17 (12) | 28.1 | 13.3 | 13.6 | fseventsd 15G, qemu 7.2G |
| 4 | 2026-09-24T05:48:09Z | 2026-09-24T06:27:44Z | 759 (05:48) | 16-20 (20) | 8.5 | 5.8 | 20.4 | WindowServer, kitty |
| 5 | 2026-09-30T22:26:41Z | 2026-10-01T02:37:31Z | 225 (23:01) | 27-33 (29) | 4.9 | 0.0 | 27.2 | post-reboot restart surge (uptime 0.1 d) |
| 6 | 2026-09-25T15:11:42Z | 2026-09-25T16:38:50Z | 614 (16:10) | 8-15 (14) | 12.0 | 1.2 | 18.6 | qemu 7.4G; crash cluster 387 |
| 7 | 2026-09-02T17:28:59Z | 2026-09-02T18:32:35Z | 263 (17:45) | 18 | 6.0 | 1.6 | 27.2 | sentinel tick 986 s late |
| 8 | 2026-09-22T19:06:25Z | 2026-09-22T20:27:14Z | 296 (19:06) | 14-21 (19) | 13.2 | 2.5 | 20.1 | tsserver |
| 9 | 2026-09-23T04:11:45Z | 2026-09-23T05:30:27Z | 275 (05:09) | 14-18 (16) | 13.1 | 2.5 | 19.3 | tsserver |
| 10 | 2026-09-29T08:16:07Z | 2026-09-29T10:12:18Z | 216 (08:16) | 16-23 (23) | 26.5 | 8.4 | 10.0 | **coreaudiod 27G** |
| 11 | 2026-09-30T19:33:10Z | 2026-09-30T20:45:11Z | 378 (19:33) | 0-29 (29) | 24.2 | 22.5 | 9.2 | **fseventsd 39G** → reboot 20:26Z |
| 12 | 2026-08-17T16:23:44Z | 2026-08-17T17:39:43Z | 297 (16:45) | 42-43 (43) | 13.2 | 0.0 | 20.7 | node 3.1G |
| 13 | 2026-09-29T19:37:00Z | 2026-09-29T22:10:45Z | 205 (21:55) | 18-24 (23) | 5.3 | 7.9 | 19.9 | mds_stores 7.8G |
| 14 | 2026-10-01T06:54:08Z | 2026-10-01T08:58:05Z | 635 (07:18) | 28-32 (31) | 8.6 | 0.0 | 24.8 | next-server 9.3G; tick 641 s late |
| 15 | 2026-09-02T16:15:16Z | 2026-09-02T16:58:34Z | 236 (16:47) | 18 | 6.0 | 1.6 | 27.8 | |
| 16 | 2026-09-25T03:45:02Z | 2026-09-25T04:46:52Z | 329 (03:45) | 9-19 (12) | 22.7 | 1.3 | 17.0 | coreaudiod 23G; crash cluster 398 |
| 17 | 2026-09-28T00:51:47Z | 2026-09-28T03:08:42Z | 257 (01:42) | 9-17 (12) | 12.2 | 0.9 | 18.1 | tsserver |
| 18 | 2026-09-29T00:15:24Z | 2026-09-29T02:34:48Z | 336 (01:32) | 11-15 (13) | 15.6 | 0.9 | 15.3 | tsserver |
| 19 | 2026-09-24T15:39:07Z | 2026-09-24T17:00:40Z | 247 (16:34) | 12-22 (13) | 20.4 | 4.6 | 14.2 | fseventsd 8G; crash cluster 205 |
| 20 | 2026-09-25T02:27:56Z | 2026-09-25T03:03:31Z | 225 (02:39) | 11 | 21.8 | 1.8 | 15.8 | coreaudiod 23G |
| 21 | 2026-09-22T15:31:15Z | 2026-09-22T16:45:20Z | 300 (16:41) | 12-21 (16) | 12.7 | 2.6 | 19.8 | tsserver |
| 22 | 2026-09-02T11:46:22Z | 2026-09-02T12:13:33Z | 307 (12:07) | 18 | 6.2 | 1.6 | 28.9 | tick 203 s late |
| 23 | 2026-09-26T02:29:50Z | 2026-09-26T03:07:10Z | 212 (02:55) | 8-17 (17) | 14.0 | 1.0 | 14.9 | qemu 7.4G |
| 24 | 2026-09-02T19:26:21Z | 2026-09-02T19:59:59Z | 219 (19:59) | 18 | 6.0 | 1.6 | 26.8 | tick 169 s late |
| 25 | 2026-09-08T13:12:52Z | 2026-09-08T14:04:01Z | 260 (13:41) | 29-35 (33) | 23.4 | 1.7 | 13.1 | fseventsd 16G |

- Worst days by severity: 09-02, 09-26, 09-24, 09-29, 09-30, 09-25, 10-01, 10-04. [M]
- The worst episodes sit at **12–23 sessions**, not at the session maximum. 21 of the top 25 peaked at 11–23 sessions. [M]
- Crash-cluster windows to join (UTC): 09-25T03:16–04:27 (398 rows), 09-25T15:05–16:29 (387), 09-24T15:25–16:25 (205), 09-24T18:42–19:32 (199), 09-24T20:56–21:45 (189), 09-25T00:08–00:50 (178), 09-28T20:07–20:24 (60), 09-25T05:57–06:00 (54), 08-07T22:57–22:58 (49), 09-25T01:12–01:27 (48), 09-24T20:39–20:53 (43), 09-29T05:45–05:58 (41), 09-23T23:09–23:11 (33), 09-10T04:12–04:19 (31, no-transcript), 09-11T15:22–15:29 (31). [M]

---

## 9. Implication for the 1000-agent goal [I]

- At ~15 sessions the box already sits at a median 2.5/core with 0% idle during bursts. If agents drive exec churn roughly in proportion to their number, ×10 agents means about ×10 churn, against a CPU that has none left. CPU is the wall, and the lever is the *spawn cost per agent action* (hooks, pollers, shell-outs, at about 690 forks/s live), not the session count. Hardware alone would need about an order of magnitude more cores.
- Memory is the second wall: about 40 more sessions by the script's `est_room_sessions`, or about 100 by the headroom slope. That is reached long after CPU, but it is the axis that actually kills the box (§6).

---

## 10. Gaps from the adversarial pass

1. **Sampler survivorship.** Fixed by time-weighting, but gaps are capped at 600 s and 466 gaps longer than 10 min (189 h total) are not represented. The worst stalls are under-counted. Direction of bias: the knee is real and, if anything, understated. [M] for the gap counts
2. **Agents vs sessions.** No log here counts in-process subagents, so this report cannot place the knee in agent units. `coal_true_procs` (r 0.275) is the nearest proxy.
3. **Per-row CPU attribution does not exist historically.** `top_procs` is RSS-ranked. The CPU split rests on one live 5 s snapshot plus a 1 h births log from 09-30. A standing per-command CPU/exec-rate sampler would close this gap.
4. **Era confound.** The 2.7× higher per-session cost after 09-16 comes with a new CC version line (2.1.28x in the crash ledger) and new background services (qemu, coreaudiod leak). I did not attribute it.
5. **Crash-ledger validity.** About 95% of CRASH rows are `abrupt-unknown` and 83% sit in mass clusters of distinct short-lived sids. The "isolated crash" rate is the more trustworthy series. Neither is confirmed as user-visible.
6. **Census-change check.** The census was refactored on 09-07 (`c9e7ba640`, "one census, two consumers") with the stated logic unchanged. I did not test it for a level shift.
