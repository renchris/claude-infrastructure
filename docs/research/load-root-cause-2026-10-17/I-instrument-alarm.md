# Axis I: continuous attribution instrument and event-fired alarms

**Date:** 2026-10-17, measured 02:35-02:45 CDT (07:35-07:45Z). Load at the time: `sysctl -n vm.loadavg` gave `{ 143.35 122.28 90.17 }`, well below the lead's 365-520 peak. The four agent-context-sync gates had mostly finished; only r13-d and r13-ra still had pytest processes.
**Mode:** read-only. I signalled no process, ran no suite and ran no reaper. The only scratch file is one `ps` snapshot at `/tmp/I-alarm-ps.txt`, taken once.
**Labels:** MEASURED means I name the command. ESTIMATED means I name the method.

---

## 0. Answers first

1. **The box already has an attribution instrument. Its alarms are what fail.** `scripts/lib/capacity-attrib.py` (764 lines) does per-session CPU attribution through libproc: `proc_pid_rusage` own and reaped-child counters, `(pid, start)` keys, a reap correction, a join to session roots, and fork and exec rates. It writes `~/.claude/logs/attrib.jsonl` on every capacity-alarm tick. The design is `docs/research/concurrency-scale-2026-10-04/d-telemetry-gaps.md` §2. There are three faults:
   - **(a) It runs from a one-shot 60 s launchd job that stretches under load.** Its own tick gap `el_s` reads p50 65.6 s, p90 250.9 s, max 496.3 s (MEASURED, python over all 471 rows of attrib.jsonl). The instrument goes blind at the moment it is needed.
   - **(b) Its fork rate aliases.** `forks_per_s` is a pid delta across one tick (capacity-attrib.py:679-683). Pids wrap at 99,999. 110 of 471 rows (23%) span a long enough tick that one full wrap at the measured ~800 forks/s fits inside it, so the number can be off by a whole wrap.
   - **(c) Nothing turns it into an event that names a cause.** The pages come from `scripts/capacity-alarm.sh` rungs on host scalars (load per core, headroom, segments). Over 8,807 rows that verdict read non-green 82% of the time (ALARM 4,050, WARN 3,187, OK 1,570; MEASURED, python over capacity-alarm.jsonl). The load rung alone was ALARM in 46% of rows. Its remedy text tells the operator to "shed by CLOSING idle sessions" (capacity-alarm.sh:1943, :2004), which is the one lever the operator ruled out.
2. **What to build:** extend `scripts/lib/capacity-attrib.py` with a long-lived `--daemon` mode. It would use one `sysctl(KERN_PROC_ALL)` read plus one `proc_pid_rusage` pass every 5 s, with no fork per sample. A small detector layer turns its series into **cause-named state changes**: heavy-gate concurrency per repo, fork/exec CPU by lineage, the vnode **recycle rate** (not vnode fill), zombie slope by parent, MCP fan-out and orphans, worktree inventory drift, and instrument starvation. Each one has hysteresis, an occurrence key and a "name a cause or stay silent" rule. Events go through the existing sinks: `bin/cc-desk-page` for acute events and `bin/cc-backlog add --condition` for chronic ones.
3. **Self-cost (MEASURED components, ESTIMATED total):** about 6-7 ms CPU per 5 s tick, roughly 0.13-0.2% of one core, one fork per minute, about 25 MB RSS. Today's always-on instruments cost about 5-8% of one core (§3). This is a detection fix, not a load fix. Instruments are under 1% of box CPU and under 1% of the fork rate.
4. **Two premises in the brief are wrong** (§6):
   - "vnode table pinned" is not a signal. `kern.num_vnodes == kern.maxvnodes` holds by design on this kernel: `vfs.vnstats.num_vnodes_min == num_vnodes_max == 263168`, with 232-240k of those vnodes free. The signal is `vfs.vnstats.num_newvnode_calls` at **25,516/s now**, against a 16-day mean of about 2,500/s.
   - `scripts/tui-load.sh` is a synthetic TUI load generator used for terminal bake-offs (tui-load.sh:1-8). It is not a monitor.

---

## 1. Inventory: what exists (file:line, cadence, measured cost)

| Instrument | Cadence and shape | What it sees | Cost / health (MEASURED unless noted) |
|---|---|---|---|
| `scripts/compressor-sentinel.sh` (2,218 lines) | KeepAlive bash loop, 10 s (`launchd/com.claude.compressor-sentinel.plist:36-40,102`) | compressor segments level and rate, swap, `ps` census every 6 ticks; **actuator** SIGSTOP/SIGKILL on storms (header :4-60) | pid 63160, own 1,854 s plus reaped children 14,813 s over 16 d 8.5 h, so **1.18% of one core** (ctypes `proc_pid_rusage` v2 on pid 63160 vs `ps -o etime`). Tick `el` p50 11, p90 20, p99 45, max 205 s (python over the last 3,000 rows of compressor-sentinel.jsonl). Each tick forks `date`, `vm_stat`+`awk`, about 9 `sysctl` and about 4 `awk` (:1871-1940) |
| `scripts/capacity-alarm.sh` (2,090 lines) | launchd StartInterval 60 (`plutil -p` on the plist) | 9 rungs: swap delta, headroom, pressure, max proc, segments, coalition, **load/core**, swapfiles, kalloc. Per-rung transition pages (:1970-2016); combined page rewritten every tick (:1911-1951) | Plist comment says 0.56-0.58 s per tick (`launchd/com.claude.capacity-alarm.plist:12`). d-telemetry §2.4 measured 2.8 CPU-s per tick before the `top` removal and about 1.0 CPU-s after (ESTIMATED 1-4.7% of one core). Launches python3 up to 5 times per tick (:388, :845, :1027, :1071, :1178). `launchctl list` last exit 2 (ALARM) |
| `scripts/lib/capacity-attrib.py` (764 lines) | one-shot per capacity-alarm tick, state in `.attrib-state.json` | per-session tree CPU (own + reaped child), user/sys split, `forks_per_s`, `exec_hook_dt`, runnable wait, footprint, buckets by launchd label and other uid | Fresh-python pass 0.10 CPU-s (d-telemetry §2.4). Rows: `el_s` p90 251 s. **17/471 rows have `unseen_s > busy_s` yet are marked `"accounting":"ok"`**: the positive control checks only overflow (:693) |
| reso `scripts/load-sampler.sh` (another repo, 118 lines) | KeepAlive bash, 10 s, Nice 5 (`~/Library/LaunchAgents/gl.reso.load-sampler.plist`) | loadavg, runnable count, top-3 RSS, semaphore holders → `~/.reso/load.jsonl` | pid 54721: 12.1 CPU-s in 16 min 44 s, so **1.2% of one core** (ctypes rusage) |
| `scripts/qos-census.sh` | StartInterval 600 | QoS clamp coverage; three-state verdict (:1-50) | not measured |
| `scripts/fseventsd-watch.sh` | StartInterval 300 | fseventsd RSS/CPU | two instances seen (pid 36442 and child 38614) |
| `scripts/teammate-reap-alarm.sh` | StartInterval 600 | teammate reap | **instance 23015 had been running 18:21 on a 600 s interval** (ps snapshot), i.e. starved |
| `hooks/lead-crash-watchdog.sh` (2,390 lines) | one bash per session, 30 s poll | lead death | 32 alive (ps snapshot). pid 13565: 685 CPU-s in 15.5 d (0.05%/core); pid 8140: 40.8 s in 1 d (0.046%). ×32 is about **1.5% of one core** (ESTIMATED by extrapolation) |
| `hooks/lib/page-damp.sh` (65 lines) | library | send-side damping keyed on a state fingerprint, TTL 1800 s (:14-23, :30-48) | the correct contract; reuse it |
| `bin/cc-desk-page` | sink | desk → Notification Center/Pushover ladder; logs `delivered`/`read_proven` to idl.jsonl (:1-40) | the correct acute sink |
| `bin/cc-backlog add --condition SLUG` | sink | idempotent rows keyed on project+condition (:12-17) | the correct chronic sink. The occurrence key comes for free |
| `scripts/lib/capacity-admit.sh` | admission term | spawn-path capacity term; its header records why a load gate is refuted (:1-25) | a gate, so out of scope under the operator's constraint |
| `hooks/qos-rewrite.sh:25` | hook | QoS demotion, "NOT admission control" | out of scope (demotion is forbidden by the constraint) |
| `scripts/tui-load.sh` | tool | **synthetic Ink-TUI load generator** for bake-offs (:1-30) | not an instrument |

Prior research this builds on:
- `max-load-per-core-derivation-2026-08-25.md` §1: "no threshold on load-per-core separates the box's deaths from the loads it survived". 2.53/core was fatal, yet it sits below 14 of 15 survived readings. **A load-per-core page cannot be calibrated, by derivation.**
- `load-ceiling-derivation-2026-08-24.md` §1 and `marginal-load-per-session-2026-08-25.md` §2: the per-session Δload denominator has a 30× estimator spread, so session count is not a usable cause either.
- `concurrency-scale-2026-10-04/d-telemetry-gaps.md` §4: "Extend capacity-alarm.sh; do not add a daemon … a new daemon would be a fifth sampler". That advice landed as capacity-attrib.py. This document keeps its spirit but argues that the attribution half must now become long-lived (§2.1).

### 1.1 Page directory: the always-firing trap, MEASURED

`ls ~/.claude/autonomy/pages | wc -l` returned **410** entries: 199 `deploy-degraded-<hash>.page` (dated Oct 9-17), 196 UUID-named 11-byte pages (one epoch each), the capacity-alarm combined page and 3 rung pages (kalloc, load, maxproc), compressor-sentinel, nightly-regression, plus the `damp/` dir with **5,502** markers. Standing pages that nobody retracts are noise, not events. Any new detector must retract on clear (the capacity-alarm.sh:1946-1951 pattern) and must not mint per-hash pages.

### 1.2 Current-state numbers the sampler would carry (MEASURED 07:35-07:45Z)

| Signal | Value | Command |
|---|---|---|
| fork rate | **830/s** | python: pid delta of two `/usr/bin/true` children 10 s apart |
| exec rate | **558/s** | Δ`security.mac.asp.stats.exec_hook_count` / 10 s |
| vnode create/recycle | **25,516/s** new, 25,428/s recycled | Δ`vfs.vnstats.num_newvnode_calls`, Δ`num_recycledvnodes` / 10 s |
| vnode 16-d mean | ~2,520/s (ESTIMATED: 3.594e9 recycled / 16.5 d uptime) | `sysctl vfs.vnstats.num_recycledvnodes` |
| vnode fill | 263,168/263,168, but **free 232,497-240,146** | `sysctl -a | grep vnstats` |
| host split | user 576.7 s / sys 516.2 s / idle 0.7 s over 109.4 s | last attrib.jsonl row |
| zombies | 225: **222 under kitty pid 44163** (207 `login`, 6 zsh, 6 bash) | in-process `KERN_PROC_ALL` parse; also the ps snapshot |
| zombie slope | ~4.4/h (ESTIMATED: 222 / 50.6 h kitty uptime, assuming none reaped) | `ps -o etime= -p 44163` |
| ms-365-mcp-server | 29 procs, 996 MB RSS, mostly 1-2 per session | ps snapshot + lineage walk |
| heavy jobs | 8 pytest-family (7 under session a482dd6c in r13-d), 55 bats procs (postland-verify `wt-run-65926`), 2 xcodebuild (r13-d) | ps snapshot + lineage walk |
| top CPU by lineage (ps pcpu) | session a482dd6c r13-d 101.6, fseventsd 100.6, Dia 43.1, WindowServer 38.1, claude-infrastructure session 28.7 | ps snapshot + lineage walk |
| worktrees | 325 top-level entries, 5,294 dirs at depth ≤2; volume 49% used, 3.7 TiB free | `ls | wc -l`, `df -h` |

---

## 2. Design: one long-lived sampler and a cause-named event layer

### 2.1 Why long-lived, and why fork-free, with numbers

Under load, every bash instrument stretches. The sentinel's p99 tick is 45 s at a 10 s cadence, and capacity-alarm's attribution p90 is 251 s at a 60 s cadence (MEASURED above). The reason is that each tick pays dozens of fork+exec round trips. Each exec passes the ASP exec hook (`exec_hook_count` +558/s system-wide) and then waits in a run queue holding about 100-175 runnable threads. A single resident process needs **one** scheduling slot per tick and no exec at all. That is the only design whose tick does not degrade with the storm it measures. compressor-sentinel.sh:14-17 already records that a sampler's death "was the earliest machine-readable distress signal".

Per-tick primitives, MEASURED in-process with python ctypes on this box at 1,429 procs:
- `sysctl({CTL_KERN, KERN_PROC, KERN_PROC_ALL})`: **0.43 ms CPU**, 904 KB. It returns pid, ppid, `p_stat` (zombies included), comm, uid and start time for **all uids**, with no setuid `ps`.
- Parsing it from one `bytes` copy: **0.83 ms CPU**. A naive `buf.raw` slice per field cost 99 ms, so the implementation must copy once.
- `proc_pid_rusage(RUSAGE_INFO_V2)` over every pid: **3.0 ms CPU**, 988/1,426 readable (uid 501).
- `host_processor_info`: 16 µs (d-telemetry §2.4). `sysctlbyname` counters cost microseconds each.

ESTIMATED per-tick budget: 1.3 ms table + 3.0 ms rusage + ≤1 ms `KERN_PROCARGS2`/`PROC_PIDVNODEPATHINFO`, done only for **new** pids whose comm is in the heavy-job set (about 0.04 ms each, d-telemetry §2.4) + ~0.5 ms to encode and append a row. That gives **6-7 ms per 5 s, about 0.13% of one core**. Two passes run at 60 s: the existing setuid `ps -axo …ucomm` for other-uid CPU (0.03-0.04 CPU-s, d-telemetry §2.4) and `launchctl list` (~10 ms). They add about 0.07%. Worktree readdir runs every 600 s and is negligible. **Total ≈ 0.2% of one core, 1 fork per minute, ~25 MB RSS.**

### 2.2 Fork rate without a fork, wrap-safe

Read the **pid cursor**, meaning the pid of the newest-started process in the `KERN_PROC_ALL` table. Its delta per tick, normalised by measured elapsed time, gives the system fork rate. At 5 s it only aliases above 99,899/5 ≈ 20,000 forks/s, about 24× today's rate. This replaces the per-tick `ps` child pid (capacity-attrib.py:345-370, :679-683). The exec rate stays Δ`exec_hook_count`.

**Per-lineage fork counts are not available unprivileged, and the design states this instead of guessing:**
- I prototyped snapshot diffing. KERN_PROC_ALL at 1 s for 10 s saw **46 new pids/s alive at a sample against 830/s actually forked, about 5.5% coverage**. It is biased toward long-lived children. By lineage it saw top:bash 124, session r13-ra 111, session wt-cc-142226-72029 76, top:sleep 62, …; by comm, bash 201, sleep 104, awk 25, git 24, jq 16.
- kqueue cannot follow descendants: `NOTE_TRACK, NOTE_TRACKERR, and NOTE_CHILD are no longer supported as of 10.5` (SDK `sys/event.h:356`).

So lineage attribution uses the **reaped-child CPU** counters, which capture every short-lived child exactly (capacity-attrib.py:5-17). The daemon reports "fork/exec CPU by lineage" plus the coverage ratio (seen-alive/forked). Exact per-lineage fork counts are an operator-approved, alarm-fired burst: `sudo eslogger fork exec exit` for ~20 s (root and Full Disk Access), never always-on.

### 2.3 Row shape (compact series)

- **Every 5 s**, about 250 B: `t, el, load1, usr, sys, idle, forks_s, exec_s, vn_new_s, vn_free, zomb, zomb_top_ppid, seg_pct, swap_mb, n_gate, n_mcp, top3_lineage_cpu`. That is about 4.3 MB/day.
- **Every 60 s:** today's attrib row (~5 KB, sessions, buckets, other-uid), about 7 MB/day as now.

Both rotate through `scripts/rotate-autonomy-logs.sh` (size-gated, :2-10). The daemon also overwrites `~/.claude/logs/attrib-latest.json` atomically each tick, so readers never parse the jsonl.

### 2.4 Detectors: each emits (state, occurrence-key, cause text)

| ID | Raise when (Schmitt: raise ≥3 consecutive 5-s ticks; clear after 10 min below the clear line) | Cause identity in the key (no counts, no timestamps; page-damp.sh:14-17) | Sink | Would fire now? |
|---|---|---|---|---|
| D1 gate-concurrency | ≥2 concurrent full gates (pytest with `-n`/xdist parent, bats suite root, xcodebuild) **in the same repo** (git common dir from the root's cwd), or summed gate workers > 1.5×ncpu | `gate:<repo>:{worktree set}` | desk page | **Yes**, at the lead's time: 4 × `pytest -n auto` in agent-context-sync r13-{p,b,d,ra}. Text: "4 concurrent full gates in agent-context-sync (r13-p,b,d,ra), about 40 xdist workers on 10 cores, sessions …" |
| D2 fork/exec storm by lineage | forks_s > max(p95 of trailing 7 d × 1.5, abs floor) **and** one lineage holds ≥30% of reaped-child sys CPU | `forks:<lineage>` | desk page | Likely (830/s; top lineage session a482dd6c at 2.7 cores in the 07:34Z row) |
| D3 vnode churn | vn_new_s > 3× trailing-7-d median for 5 min | `vnode-churn:<top sys-CPU lineages>`, explicitly marked correlational | backlog row (`--condition vnode-churn`) | **Yes**: 25.5k/s vs ~2.5k/s |
| D4 zombie slope | zombies under one ppid with slope > 0 sustained 6 h, or > 100 | `zombies:<parent comm>:<pid@start>` | backlog row | **Yes**: kitty 44163, 222 `login`/zsh/bash zombies |
| D5 MCP fan-out | per server name: count > live sessions using it, or any server whose session root is dead (ppid 1 / ghost) | `mcp:<server>:orphans` | backlog row | Unknown. 29 ms-365 for 32 sessions; orphan check not run |
| D6 worktree drift | entry count up >20 since the last successful `worktree-gc` row, or GC job exit ≠ 0 | `worktrees:<root>:gc-rc<rc>` | backlog row | Possibly: `com.claude.worktree-gc-infra` last exit **3** (`launchctl list`) |
| D7 instrument starved | any instrument's measured tick > 3× nominal (own el, sentinel `el`, capacity-alarm row gap), or a StartInterval job still running past its next interval | `starved:<instrument>` | desk page | **Yes**: attrib el p90 251 s; teammate-reap-alarm running 18 min on a 600 s interval |
| D8 kernel-bound | sys ≥ user for 5 min **with** D2 or D3 raised | joins the D2/D3 key | annotation only | n/a |
| record-only | load/core, headroom, raw vnode fill, session count | never paged | series | (these are the 82%-non-green signals) |

Compressor and memory stay owned by compressor-sentinel, which already pages and acts. The sampler records them and never pages on them.

### 2.5 How the alarms avoid the always-firing trap

1. **Name a cause or stay silent.** A detector that cannot attach a cause identity records "unattributed excess" in the series and never pages. After 6 h of unattributed excess it files **one** backlog row, `instrument-gap:<signal>`, which turns blindness into work. This is the rule the load rung breaks: it is a host scalar with no cause, and it read ALARM in 46% of 8,807 rows.
2. **The occurrence key carries the cause, never the level.** A raise fires once per key. Membership growth inside the same key rewrites the page file but sends nothing. A clear retracts **that** key (`.claude/rules/agent-operating-lessons-situational.md:196`, "clearing on the same KIND not the same OCCURRENCE disarms the alarm"). Acute keys are damped through `hooks/lib/page-damp.sh` (TTL 1800). Chronic keys use `cc-backlog add --condition <key>`, which is idempotent by construction (bin/cc-backlog:12-13).
3. **Hysteresis and dwell:** 3 ticks (15 s) to raise, 10 min below a lower line to clear.
4. **Thresholds relative to the sampler's own trailing 7-day quantiles, floored by physical constants.** Example floors: gate workers vs ncpu, zombie slope > 0. The physical floor matters because a box that has stormed all week would otherwise learn the storm as its baseline.
5. **Flap budget with self-demotion.** A detector that raises more than 6 times per day files one `detector-flapping:<id>` backlog row and drops to record-only until its threshold is edited. That turns a mis-set threshold into a single event instead of a stream (the 570-page incident cited in page-damp.sh:5-7).
6. **Remedy text names a streamline action, never "close sessions".** For D1, for example: "gates share one repo; route through the shared gate pool / gate memo; worker oversubscription is 4×". This also requires rewriting capacity-alarm.sh:1943 and :2004.
7. **Clears are pages too, but one line long.** A standing page whose condition has passed is misinformation (capacity-alarm.sh:1905-1909).

### 2.6 Which existing tool to extend, and what stays separate

- **Extend `scripts/lib/capacity-attrib.py`.** It already holds the libproc ctypes bindings (:153-175), `list_pids`/`read_pid` (:192-246), `host_ticks` (:295), `session_roots` (:390-420), the reap-correction accounting and the attrib.jsonl contract. Add `--daemon --interval 5`. Keep the 60 s full attribution row unchanged, so every reader of attrib.jsonl keeps working. Add the detectors as a sibling module in `scripts/lib/`.
- **Host it on the existing `com.claude.capacity-alarm` label** rather than a new plist (no "fifth sampler"; d-telemetry §4). Today the plist uses `StartInterval` 60 (`launchd/com.claude.capacity-alarm.plist:101-116`). Switch it to KeepAlive, running the daemon. The daemon runs `capacity-alarm.sh` as a child every 60 s with `CC_CAP_ATTRIB_FROM=attrib-latest.json`, so the bash rungs **read** the attribution instead of spawning python (capacity-alarm.sh:842-845). Rung logic and per-rung pages stay unchanged. install.sh already does bootout+bootstrap of every `launchd/*.plist` (install.sh:1195), so this rides the normal deploy.
- **Keep `compressor-sentinel.sh` independent.** It is the actuator that must survive the sampler's own death (compressor-sentinel.sh:4-19). It could later read the daemon's table for its census, but only as an optional fast path with its own `ps` fallback.
- **The reso `load-sampler.sh`** (1.2% of a core, MEASURED) duplicates loadavg, runnable and top-3. The one thing only it has is semaphore holders. It could read `attrib-latest.json` and add only `sem`. That is cross-repo, so it is listed as an open question.

---

## 3. Measured share of load for this axis

Always-on instruments today:
- sentinel 1.18% (MEASURED)
- reso sampler 1.2% (MEASURED)
- lead-crash-watchdog ×32 ≈ 1.5% (ESTIMATED from 2 measured instances)
- capacity-alarm ≈ 1-4.7% (ESTIMATED from documented 0.57-2.8 CPU-s per tick at 60 s)

That totals **≈ 5-8.6% of ONE core, i.e. ≈ 0.5-0.9% of box CPU**. Fork contribution: sentinel ~20 forks per tick (~2/s), reso sampler ~1-1.5/s and capacity-alarm ~100 per tick (~1.7/s) are ESTIMATED from reading their tick bodies, so **≈ 5/s of 830/s (<1%)**. Replacing capacity-alarm's attribution python launch and the reso sampler's `ps` calls with the daemon saves ≈ 1.3-1.5% of one core (ESTIMATED). **The load win is small. The value of this axis is that the other axes' causes (gate concurrency, fork lineage, vnode churn, zombies, MCP fan-out, worktree drift) arrive as named events while they are still forming.**

---

## 4. Recommendations (detail for the structured return)

- **R1 (P0)** `capacity-attrib.py --daemon` (5 s fork-free core, 60 s full row) on the capacity-alarm label; capacity-alarm reads `attrib-latest.json`.
- **R2 (P0)** Detector layer D1-D7 with occurrence keys, hysteresis, cause-or-silence and flap self-demotion; sinks `cc-desk-page` and `cc-backlog --condition`.
- **R3 (P1)** Fix the two silent accounting defects now, independent of R1:
  - `forks_per_s` alias: mark it null when `el_s × 800 > 99,899`, or switch to the pid cursor (capacity-attrib.py:679-683).
  - `accounting:"underflow"` when attributed < 0 or `unseen_s > busy_s × 1.05` (capacity-attrib.py:691-693). 17/471 rows are affected today.
- **R4 (P1)** Rewrite capacity-alarm's remedy lines (:1943, :2004) to name the attributed streamline action. Demote the load rung (:1970 loop, `load`) to record-only: no page file, kept in the jsonl.
- **R5 (P2)** D6 worktree drift as the event source for the worktree axis: a GC rc ≠ 0 or net growth since the last GC row files a condition-keyed backlog row. The prune itself stays with worktree-gc.sh's safety gates (worktree-gc.sh:11-36).
- **R6 (P2, operator-only)** An alarm-fired 20 s `eslogger fork exec exit` burst (root + Full Disk Access) when D2 raises with lineage coverage < 50%, so the fork lineage is exact instead of correlational.

Verify recipes for each are in the structured return. All of them start with **replay**: the detectors run offline over the existing capacity-alarm.jsonl (8,807 rows), attrib.jsonl and compressor-sentinel.jsonl. Acceptance:
- pages/day ≤ 6 per detector;
- every page names a cause;
- a positive control (rows from the 2026-10-16 four-gate window) must raise D1;
- a negative control (2026-10-15, 915 OK rows) must raise nothing.

---

## 5. Options considered and rejected

- **"vnode table pinned" alarm on `num_vnodes == maxvnodes`.** REFUTED. `vfs.vnstats.num_vnodes_min == num_vnodes_max == desired_vnodes == 263168` and `num_free_vnodes` reads 232-240k (MEASURED, `sysctl -a | grep vnstats`), so the table is always "full". It would fire 100% of the time. Use the `num_newvnode_calls` rate instead.
- **Load-per-core page.** No separating threshold exists (max-load-per-core-derivation §1), and it was non-green in 54% of rows (46% ALARM) (MEASURED). Keep it record-only.
- **Folding the sampler into compressor-sentinel.** Rejected. It would load the one un-starvable actuator (its header :4-19; d-telemetry §4).
- **A brand-new daemon or plist.** Rejected. It would be a fifth sampler (d-telemetry §4), and loading a new daemon is an operator act (agent-operating-lessons.md:53). Re-using the capacity-alarm label avoids both.
- **kqueue `NOTE_TRACK` for lineage.** Unsupported since 10.5 (SDK sys/event.h:356).
- **Snapshot-diff fork attribution.** 5.5% coverage (MEASURED prototype), biased to long-lived children.
- **Always-on Endpoint Security / `eslogger`.** Needs root and FDA. At 830 forks/s and 558 execs/s, the JSON stream is a real load (cost not measured). Alarm-fired burst only (R6).
- **Standing `powermetrics`.** Needs root, is coalition-level only, and costs at least as much as `top` (d-telemetry §3).
- **`top -l 1` in the tick.** 1.46-2.43 CPU-s per call (d-telemetry §2.4).
- **Throttle, QoS demotion or a spawn gate as the actuator.** Out under the operator's constraint. These alarms only report and name.

---

## 6. Corrections to the brief

- `scripts/tui-load.sh` is a load **generator** for terminal bake-offs (:1-30), not an instrument.
- "vnode table pinned" is the steady state, not a fault (§5). The live fault signal is 10× vnode churn.
- "compressor-sentinel x7": I saw one sentinel daemon (pid 63160). The other counts in the brief were probably its transient subshells. Not verified.
- Load dropped from the lead's 365-520 to 143 between the lead's measurement and mine, so the current-state numbers above are a different moment.

## 7. Open questions

- Vnode-churn attribution per process needs root (`fs_usage -f filesys`). Unprivileged, D3 can only name correlated sys-CPU lineages.
- Who writes the 196 UUID-named 11-byte pages and the 199 `deploy-degraded-<hash>` pages, and why they are never retracted. I did not trace the producers.
- Whether the reso repo will let its `load-sampler.sh` read `attrib-latest.json` (cross-repo).
- The MCP "fails to connect within 30 s" symptom is not visible to a process sampler. It needs the Claude Code side (session debug log or MCP startup timing). D5 can only see counts and orphans.
- The `exec_hook_work_time` units (550,224,484,981 cumulative) were not established, so I make no claim about ASP exec-hook CPU share.
