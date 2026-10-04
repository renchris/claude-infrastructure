# Running more concurrent Claude Code agents: measured bottlenecks and the path to 1000 (M1 Max, 2026-10-04)

**Labels.** **M** means MEASURED and **I** means INFERRED. Sources are the report files beside this README (raw scripts and samples stayed in `/tmp/concurrency-scale/` and are not kept):

| Code | File |
|---|---|
| w1 | w1-audit-report.md |
| a1 | a1-capacity-knee.md |
| a2 | a2-cpu-attribution.md |
| b | b-agent-concurrency.md |
| c | c-outcome-ledger.md |
| d | d-telemetry-gaps.md |
| e | e-per-agent-cost.md |
| f | f-quota-ceiling.md |
| g | g-hardware.md |
| h | h-hostile-review.md |
| i | i-redteam-cpu.md |
| j | j-startup-hang.md |
| hs | hs.sample |

`/sk` means the value as corrected by the skeptic verdict on that report. Live numbers were taken at load ~70-170. This research workflow's own lead process used 1.3-1.7 cores during those measurements (M, w1/sk, i/sk).

## 1. Answer

1. **The knee is a rising band, not a wall.** In resident sessions, burst share climbs from about 12 sessions, and the clearest within-day step is between 12-14 and 15-17 sessions (20 of 26 days) (M, a1/sk). In working agents, median load per core sits at the 2.5 alarm line from about 3 active agents, and load per core reaches 10 or more with a median of only 9 active agents (M, b/sk).
2. **"~100 agents" is not a working count.** Your actual workload peaked at 50 active agents. It never reached 100 even counting open transcripts (max 79, including probe runs). It averaged about 20 open agents (M, b/sk, f).
3. **What saturates is CPU spent on work the sessions spawn, not Claude itself and not memory.** The claude binaries use 0.5-0.8 of 10 cores. Session trees with their tool and hook children use 2.0-3.1 cores. Short-lived processes, created at 530-650 per second, carry 2.0-3.6 cores. Automation browser trees take 3.5-3.8 cores, and root daemons including security scanning take 1.2-1.4 cores. Meanwhile 23-29 GB of memory stays reclaimable (M, w1/sk, i/sk, a2/sk).
4. **What actually crashes is the terminal and, through non-Claude memory runaways, the kernel.**
   - On 10-01, killing a wedged kitty took down 31 sessions in 26 s. The same warning sign (189 unreaped zombie processes) is present now on kitty 48854.
   - Both 09-16 kernel panics came from a clang-format swarm that filled compressor segments to 100%.
   - claude.exe has 0 native crash reports in the 7.5 days that are retained.
   - Unexplained lead-session deaths run only ~2-3.6x higher per session-hour at 25 or more sessions (M, c/sk).
5. **Tonight's launch hangs were a separate fault.** Bun's once-per-process system-CA keychain query waited 15-46 min on a backlogged secd, with no timeout. `CLAUDE_CODE_CERT_STORE=bundled` removes that query, at the cost of trust anchors that exist only in the system keychain (M, j/sk).
6. **For 1000 agents, quota binds long before hardware.** At today's duty cycle it needs at least ~260-390 Max accounts ($52-78K/month), and ~1,000-3,100 if the agents work continuously. Today's 4 accounts are already saturated (I, f/sk).
7. **Landing and terms bind next; hardware is the solvable part.**
   - One trunk lands ~44 changes/day (M, h/sk), against an optimistic ceiling of ~185-570/day. 1000 agents would need ~2,200-2,700/day (I, h/sk).
   - Anthropic ties Max limits to "ordinary, individual usage" and may enforce "without prior notice", so a large account fleet can be lost all at once (h/sk).
   - The hardware (~5-20 Linux 16-core boxes) can be bought (I, g/sk).

## 2. Bottleneck model

**Where the knee is**
- **Resident sessions.** P(load ≥25) rises from ~12 sessions and does not plateau. The within-day step is clearest from 12-14 to 15-17 sessions (20 of 26 days, one-sided p 0.005). The "knee at 12" rests on only 9-15 h of data per level (M, a1/sk).
- **Working agents.** Median load per core is ≥2.5 from ~3 active agents. At load per core ≥10 the median is 9 active agents, 26 open transcripts and ~17 claude processes (M, b/sk). The 2.5/core line is uncalibrated: 2.53 was fatal once and 5.98 was survived (M, b/sk). The two units agree if about a third of sessions are active (I, a1/sk).
- **Lag proxy.** These are 10-s sentinel ticks arriving ≥5 s late:
  - 1.0% of ticks at load 40-80, 3.3% at 80-160 and 15.6% at ≥160 (M, a1).
  - 2.5-3x more often at 15-19 sessions than at 10-14 (M, a1/sk).
- **Session count explains ~2% of load variance.** About 95% of the variance sits inside a fixed session count. Actively working agents predict load 2-5x better than open sessions do (M, a1/sk, b).
- **"2.7x per-session cost since August."** Since 09-16, load rises 2.0-5.6x more steeply with session count, depending on the estimator. That reflects more bursts at each session level, not a larger direct cost per session. Part of it may be a census undercount (M, a1/sk; I).

**Resources**

| Resource | Current use (busy periods) | Ceiling | Evidence |
|---|---|---|---|
| CPU, whole box | 0% idle with 34-39% sys in bursts. Time-weighted load is ≥20 for 36-52% of the time and ≥175 for 6-12% (48 h / 24 h) (M, w1/sk) | 10 cores (8P+2E) | `top`; `~/.reso/load.jsonl` weighted by sample gap |
| Process creation (spawn tax) | 530-650 new pids/s, ranging 356-1,198 with load. exec_hook 305-410/s. A trivial spawn costs 1.7-3.2 ms of CPU, so creation alone takes 1.0-3.6 cores (M, a1/sk, a2/sk, i/sk, g/sk) | No hard cap. Per-fork wall cost rises with contention: `/usr/bin/true` p50 10.7-35.7 ms now vs 2.4 ms in August (M, e, e/sk) | PID advance; `security.mac.asp.stats.exec_hook_count` |
| Short-lived processes (all owners) | 2.0-3.6 cores (M, a2/sk, i/sk) | n/a | `proc_pid_rusage` child counters |
| Session trees (claude + tool + hook children) | 2.0-3.1 cores without the measuring workflow, 3.5-4.5 with it. The claude binaries alone use 0.5-0.8 cores (M, w1/sk, i/sk, a1/sk) | n/a | `.probe_attrib4.py` |
| Hook chain | 20 hooks per Bash call (13 on 08-09). At least 228-240 ms of CPU per call. The Stop chain has p50 ~10 s, and session-continue is cancelled on ~84% of Stops (M, e/sk, w1/sk) | Per-hook timeouts of 5-10 s overshoot 2-3x under load (M, j) | `~/.claude/settings.json`; transcripts |
| Automation browsers | Browser trees use 3.5-3.8 cores; the hottest agent-browser tree ~1.7 cores. The 7 agent-browser trees hold 9.55 GB of RSS. They run at PRI 47-55 against claude's 31, and render on the CPU through SwiftShader (M, a2/sk, i/sk, w1/sk) | n/a | `ps` tree walks |
| System daemons, incl. security scanning | Root daemons use 1.2-1.4 cores (12-14% of busy): WindowServer ~0.45, kernel_task ~0.4, coreaudiod ~0.25. XprotectService plus syspolicyd use 0.07-0.52 cores and vary widely (M, i/sk, a2/sk, g/sk) | XProtect's first-exec scan is single-threaded. That comes from one run in August; its ceiling is unknown (g/sk) | setuid `ps` deltas |
| launchd fleet jobs | 6-16% of busy (0.6-1.8 cores). They account for 51-68% of process births in 8-10 s samples (M, a2/sk, w1/sk, d/sk) | n/a | births polled at 160-200 Hz |
| Unattributed | 6-9% of busy. At most 0.3 core is kernel time that no process owns (M, a2/sk, d/sk, i/sk) | n/a | host ticks minus attributed CPU |
| Memory | 23-29 GB reclaimable headroom. Swap is flat at 1.75 of 3 GB, with 0 compressions/s. 0 claude jetsam kills in 7 days (M, w1/sk, i/sk) | 64 GB. Compressor segments hit 100% at both 09-16 panics. Runaways (clang-format at 242-274 GB footprint, fseventsd 40 GB, coreaudiod 37 GB) arrived while 8-18 GB of headroom was logged (M, c/sk, a1/sk) | `capacity-alarm.jsonl`; panic files |
| Kernel zone kalloc.1024 | 3.48 GB, growing 0.76-1.05 GB/day (M, w1/sk) | The 6 GB policy alarm arrives in ~2.4-3.3 days. The previous boot reached 14.78 GB without a zone-attributed panic (w1/sk) | `capacity-alarm` kalloc field |
| Terminal (kitty) | 189 unreaped zombies on kitty 48854 (M, c/sk) | One wedge killed 31 sessions in 26 s on 10-01. The blast radius is every pane in that kitty instance (M, c/sk) | `ps` |
| secd (keychain) | 84 parked handlers during the 02:02 hang. No backlog after 02:05:37 (M, j/sk) | A single daemon, and Claude Code's CA load waits on it with no timeout (j/sk) | `j-secd-now.sample` |
| fds / ptys / processes | Peaks: ptys 102 of 511, processes 1,683 of 16,000, files 13,339 of 491,520 (M, c) | Not binding | `sysctl` |
| Quota | 4 Max accounts. All 16 weekly windows since 09-12 closed at 100%. next and next2 were walled in 34% and 45% of last-7-day samples (M, f/sk) | 100 weekly pp per account per 168 h, i.e. 0.595 pp/h (M, f) | `account-utilization.jsonl`; cost-state |
| Landing (one trunk) | ~44 lands/day. 36% of CAS attempts are stale (M, h/sk) | Optimistic lane: ~185-570 lands/day (I, h/sk) | `~/.claude/land.log` |
| Oversight | 71 permission blocks/day over the last 7 days, ~5% of them waiting more than 1 h. That is 0.15-0.18 blocks per session-hour (M, h/sk) | A budget of about 1 page/h (h) | permission-archive |

**Cost per agent, by kind**

| Kind | Memory | CPU idle | CPU working | Hooks fired | Quota draw |
|---|---|---|---|---|---|
| Pane session (lead) | 360-510 MB: process 248-397 MB footprint plus the ms-365 MCP at 101-103 MB. RSS overstates footprint 1.3-2.8x (M, e) | 0.7-3.5% of a core (M, e) | The session tree averages ~0.1 core and reaches 0.5-0.9 core when busy (M, w1/sk). Marginal cost is 0.15-0.17 core per resident session at a 30-60 min lag (M, a1/sk) | 18 SessionStart, 13 Stop per turn, 20 per Bash call (M, e) | 0.156-0.232 weekly pp per open hour, counting its subagents (M, f/sk) |
| In-process subagent or workflow agent | 0.6-11 MB (M, e/sk) | ≈0 | The lead pays ~10% of a core fixed plus ~0.8% per active agent (r 0.32). Each active subagent adds 0.42 runnable processes (M, e/sk, e) | 20 per Bash call. No SubagentStart/Stop hooks are configured (M, e) | ~0.4-1.4 pp per hour alive (I: subagent duty 0.38-0.77 × 1.06-1.85 pp per generating hour, f/sk) |
| Named teammate | ~380 MB plus a pane plus 246 MB of worktree disk (M, e, quoting August data on 2.1.220; not re-measured) | As a session | As a session | WorktreeCreate + 18 + 13 + the per-tool chain | As a session |
| Headless `claude -p` | ~295 MB (August, quoted in e). A warm bg-spare measured 298 MB (M, e) | ~0.7% (M, e) | 1.0-1.3 runnable processes at 100% mid-turn (August, quoted in e) | SessionStart, Stop and per-tool. `--bare` strips hooks but is API-key only, so it is unusable on Max (M, e) | As a session |
| Warm bg-spare (2.1.284 daemon) | ~298 MB each, and the session census does not count it (M, e, a1/sk) | 0.72% (M, e) | n/a | n/a | 0 until claimed |
| One Bash call (any kind) | n/a | n/a | At least 228-240 ms of CPU for hook dispatch at load 100-150 (M, e/sk). The real chain is 0.5-1.1 s (I, e) | 20 | n/a |
| One agent-browser run | 1.0-2.9 GB RSS (M, e) | Tabs left on challenge pages keep animating and burning CPU (M, w1) | 0-1.7 cores per tree (M, e, i/sk) | n/a | n/a |

### Tonight's incidents

**New `claude` launches hang (secd)**

- **Symptom.**
  - Four launches (pids 53373, 3040, 3121, 4780) sat 896-2,743 s (15-46 min) before registering a session. The main thread of pid 4780 was in `mach_msg` in 881 of 881 samples (M, j/sk).
  - All four released together at ~02:05:49, without a secd restart (M, j/sk).
  - Earlier warning sign: session ca3b517d took 181 s to register at 00:26 (M, j).
- **Path.** Bun's `us_load_system_certificates_macos` runs under `std::call_once`, calls `SecItemCopyMatching` (kSecClassCertificate, kSecMatchLimitAll), and that becomes a synchronous XPC call to secd with no timeout. Claude Code 2.1.284 defaults to `CLAUDE_CODE_CERT_STORE` = `bundled,system`. Confirmed from the binary's strings, the Bun source and the docs. The claude.exe frame is unsymbolicated (j/sk).
- **secd.**
  - 84 handlers were parked at 02:02:30. The backlog cleared abruptly at 02:05:37 while load was ~100, and it had not rebuilt 14 min later at load 64-116 (M, j/sk).
  - "Load above 60 predicts it" is refuted, and the trigger is unidentified.
  - Automation Chrome was 8 of 28 secd peers and about half of its 53 connections. An orphaned headless Chrome with a /tmp profile (pid 92826, ppid 1) wrote to secd just before the drain (M, j/sk).
- **Fix.** Set `CLAUDE_CODE_CERT_STORE=bundled` in the `env` block of `~/.claude/settings.json`.
  - A shell export misses the bg and daemon sessions, which inherit the environment of whatever shell started the supervisor.
  - A typo silently falls back to `bundled,system`.
  - It drops trust in the mkcert root and "VoiceInk Dev". September logs loaded 6 system CAs. Add `NODE_EXTRA_CA_CERTS` if Claude Code's own TLS reaches mkcert-signed hosts (I).
  - The token read via the `security` CLI also stalled: 537 keychain-timeout lines, the latest taking 34-50 s. Under the same stall, expect a bounded delay or a missing token (M, j/sk).
  - It has not been verified by a live launch. Verify with one launch under `CLAUDE_CODE_DEBUG_LOGS` and grep for `CA certs: stores=bundled`.

**Hammerspoon screenshot and clipboard delays**

None of the reports diagnoses this. The evidence below comes from the artifacts in the same directory, read for this report.

- At 01:57:55 CDT, `hs.sample` (1,701 samples at 1 ms intervals) shows Hammerspoon's main thread waiting for events in 1,608 samples (94.5%). It was inside an `hs.timer` callback in ~79 samples (4.6%), where Lua walks a directory with `hs.fs` (`dir_iter`, `stat`, `readdir`) (M, hs).
- In six `top` samples Hammerspoon used 4.0-4.3% of a core, at PRI 60 against claude's 31 (M, `a2work/top1-6.txt`, `a2work/pri.txt`).
- So Hammerspoon itself was neither blocked nor starved when sampled. The delay most likely sits in the work it hands off: the capture and pasteboard processes or the services they call. Those run in the same saturated run queue that held up secd (I).
- Next step: sample Hammerspoon and its spawned children while a screenshot or clipboard action is visibly delayed, and time each step. A sample taken at rest cannot show the stall.

## 3. Fix list

Ranked by headroom gained per unit of effort. Effort: S is under a day, M is a few days, L is a week or more, or a purchase.

| Rank | Fix | Expected gain | Owner | Effort |
|---|---|---|---|---|
| 1 | `CLAUDE_CODE_CERT_STORE=bundled` in the settings.json `env` block (plus `NODE_EXTRA_CA_CERTS` for the mkcert root if needed). Verify with one debug launch | Removes the system-CA secd query that blocked launches for 15-46 min (M, j/sk). The token read can still stall for a bounded time | operator-only (settings.json). The shell-export variant is agent-drivable but misses bg sessions | S |
| 2 | `AGENT_BROWSER_IDLE_TIMEOUT_MS=1800000` in settings.json `env`, plus a skill rule: one named session per task, close it when done, no more than 2 animated tabs. The 7 agent-browser trees are not orphans. They are setsid daemons owned by 2 live sessions, so an orphan reaper would find nothing (e/sk) | Up to ~1.7-2 cores and part of 9.55 GB of RSS once idle trees exit (M base, w1/sk, i/sk; gain I) | operator-only (env); skill text agent-drivable | S |
| 3 | launch-film `render.mjs`: one render at a time, Chrome under `taskpolicy -c utility`, spawn inside `try`, and signal handlers. This class produces the true /tmp-profile Chrome orphans | Caps render bursts of 1.4-8.9 cores (median ~7), which ran for 71 min, at one utility-band tree (M, w1; gain I) | agent-drivable (other repo) | S |
| 4 | `research-block.sh` fast exit when there is no program and no route file | Saves 0.3-0.6 s per tool call and removes the top PreToolUse timeout source (144 calls stalled over 5 s in 6 h). About 0.04-0.1 core (M/I, w1) | agent-drivable | S |
| 5 | launchd priority bands: capacity-alarm and qos-census to Standard, deploy-live and worktree-gc to utility, pollers to Background | capacity-alarm goes from 5-13 back toward ~55 rows/h at peak. deploy-live stops starving (a `git fetch` ran 18+ min on 0.06 s of CPU). ~0.25-0.3 core of pollers leaves the interactive band (M, w1, w1/sk) | operator-only | S |
| 6 | browser-spin-guard: a logged per-session close instead of `close --all` | Ends ~26 fleet-wide browser wipes (12 in 71 min) that killed 0 spinning processes (M, w1) | agent-drivable | S |
| 7 | Launch watchdog in `cc-close-attrib`: name any launch that has not registered after 20 s, and never kill it | Turns a silent 15-46 min hang into a named, logged event (I, j) | agent-drivable | S |
| 8 | Session census root set = `sessions/*.json` ∪ `~/.reso/live-sessions` ∪ argv families (bg-spare, `.bin/claude --permission-mode`) | Corrects the denominators. 6 bg-spare processes were uncounted against a census of 25 (M, a1/sk, d). Needed to test whether the 2.0-5.6x steeper post-09-16 slope is real | agent-drivable | S |
| 9 | Fork-churn fixes: `lead-supervisor` `assess()` does one jq read; `teammate-checkpoint` seeds its index and skips unchanged trees; stop the stale bg job 9aa483e9 | ~380 fewer forks per sweep (sweeps take 10-19 min against a 30 s interval). Ends 4-6 s stalls on every 5th tool call (~0.035 core). Frees 0.55 GB (M/I, w1) | agent-drivable; the bg-job stop is operator-only | S |
| 10 | Stop chain: profile session-continue, raise its timeout to the measured p90, make operator-readout async if supported | Turn end has p50 ~10 s, and session-continue is cancelled on ~84% of Stops, so its gate rarely runs (M, w1/sk) | agent-drivable; the timeout is operator-only | M |
| 11 | Telemetry sampler (section 4) | Attributes 92-94% of busy CPU to an owner, against 60-69% for ps/top snapshots. Dropping `top` saves 1.5-1.7 CPU-s per tick (M, a2/sk, d/sk). Answers the 2.7x question | agent-drivable (plist band operator-only) | M |
| 12 | Hook stdin: log payload byte counts first, then replace byte-wise `read -d ''` with jq or cat where payloads are large | ~10x faster per byte: 0.3 s against 0.03 s per 400 KB at load ~80 (M, w1/sk). Whether it causes the post-tool-batch timeouts is unproven | agent-drivable | S |
| 13 | One planned restart window at the 6 GB kalloc alarm: the boot-resume `.start` fix first, then the kalloc root capture, the patched kitty with `ulimit -n 8192`, and panes split across several kitty instances | Removes the wedge class behind 31 deaths in 26 s (189 zombies now). Splitting caps the blast radius per instance (M, c/sk; I) | operator-only; the boot-resume fix and the w3-p6 merge are agent-drivable | M |
| 14 | Batch QoS: a PATH shim (`cc-qos-exec`) for ffmpeg, magick, tesseract, shellcheck and pytest; add them to the 4-row `qos-batch.patterns`; deny-with-reason for compound lines the shim cannot reach | Moves ~0.3 core on average, and 2-3 cores at burst peaks, below the sessions. Today only 3.5-4.3% of CPU is demoted and 99.8% of batch commands are compound (M, w1/sk). No CPU is removed, and batch work runs ~2.4x slower | agent-drivable | M |
| 15 | agent-browser under the same utility clamp; verify that helper PRI drops from 47-55 to 20 | ~1.7 cores per hot tree stop outranking claude (M, w1/sk). Unverified whether the clamp reaches Chrome's own threads | agent-drivable | M |
| 16 | Fleet agent shape: headless leads carrying in-process subagents or workflow agents; a lean per-tool hook profile (20 → no more than 2) for bulk agents; no per-agent MCP or browser; the drift guard sees all 20 Bash matchers | Per agent, 0.6-11 MB instead of 295-510 MB. Removes at least 228-240 ms of CPU per Bash call (0.5-1.1 s, I). At 1000 agents it avoids ~740 hook processes/s and 9-42 cores (M/I, e/sk) | operator-only (settings.json); agent-drivable (scripts, guards) | L |
| 17 | SessionStart: fold the non-gating hooks into one process, or mark them async | Startup span for multi-hook sessions is p95 10.1 s, max 35.5 s (M, j/sk) | operator-only | M |
| 18 | Linux pilot box (section 5): browser and tool offload first, then 10-20 sessions under tmux | Offload gives the Mac 1.3-1.7x headroom, since 22-40% of its CPU is offloadable (I, g/sk). The pilot measures the Linux multiplier, which is unmeasured (plausibly 1.25-2.0x) | operator-only (purchase); porting agent-drivable | L |
| 19 | Upstream: move the CA load off the main thread with a timeout. File it with `hang-4780.sample` | The real fix for the hang class | upstream | S to file |
| 20 | Hygiene, w1 rows #19-#23: git pack threads, a `git log -S` advisory, the CC 2.1.289 gate, and the rest | Each under 0.1 core (I, w1) | mixed | S |

## 4. Telemetry

**What exists**

| Source | Cadence | Carries | Blind to |
|---|---|---|---|
| `capacity-alarm.jsonl` | Nominally 60 s. Real median 154 s and mean 199 s; 5-13 rows/h at peak (M, d/sk, w1/sk) | Load, reclaimable headroom, session census, coalition counts, top 3 processes by RSS | CPU by process. A tick costs 11.4-12.9 CPU-s (M, d/sk) |
| `~/.reso/load.jsonl` | 10 s, kept 14 days | loadavg, R-state count, top 3 by RSS (a2) | CPU attribution |
| compressor-sentinel | 10 s ticks | Tick lateness, the best lag proxy we have. Per-process CPU only on memory-triggered trips, ranked by RSS (a1, a2) | CPU-heavy, small-RSS work |
| qos-census | 600 s | bats priority bands only. 51% of its busy-band rows are SIGNAL-DEAD (M, a2) | Every other kind of batch work |
| tool-batch-census, bash-execution.log | Per batch or call | Counts and session id. Subagents fold into the lead's sid (M, a2) | Duration, CPU, agent id |
| claude-crashes.jsonl | Per death | ~95% of rows are `abrupt-unknown`, and 2,421 of the 2,694 CRASH rows in the window are headless eval runs (M, c, a1) | Cause. The 32 abrupt-unknown lead deaths have no stderr (M, c/sk) |
| land.log, account-utilization.jsonl, cost-state, permission-archive | Per event | Landing, quota and oversight (h/sk, f) | Per-account stream concurrency above ~20 |

**What is blind**
- **CPU by session, agent and tool, including reaped children.** Short-lived processes are 20-29% or more of busy CPU (M, a2/sk).
- **Work reparented to pid 1.** agent-browser daemons, render Chrome and per-session watchdogs drop out of every ppid walk and every per-session sum (M, w1/sk).
- **Busy periods.** They are under-sampled by every sampler (M, a2, w1/sk).
- **System rates.** Spawn rate, exec rate and the user/sys split are never logged (d).
- **Felt lag.** The sampler gap measures a nice-10 background job, not interactive latency (c/sk).
- **Launches that never register.** The secd hang was invisible to all telemetry (j).
- **Hook payload sizes.** These are needed to settle the `read -d` question (w1/sk).
- **The `ps %cpu` premise.** It decays within seconds, which breaks browser-spin-guard's premise (M, a2/sk).

**The sampler to build: extend `scripts/capacity-alarm.sh` with libproc attribution (no new daemon)**

1. **One python ctypes pass per tick** over all uid-501 pids, keyed on (pid, start):
   - `proc_pidinfo(PROC_PIDTASKALLINFO)`: ppid, start time, own user/sys time, syscalls, context switches, faults.
   - `proc_pid_rusage(RUSAGE_INFO_V6)`: `ri_child_user/system`, `ri_runnable_time`, `ri_cpu_time_qos_*`, `ri_phys_footprint`.
   - Delta = cum_B − cum_A.
   - Reap correction: subtract a vanished pid's last cumulative value from its nearest ancestor that is alive at both ticks, separately for each counter.
   - Cost: 0.10 CPU-s as a fresh python3, ~10 ms in-process (M, d/sk).
2. **Host counters:**
   - `host_processor_info` user/sys/idle (16 µs).
   - Fork rate from the pid advance of the sampler's own child.
   - The `exec_hook_count` delta, stored as `exec_hook_dt` rather than as an exec count (M, d/sk).
3. **Other uids:** one setuid `ps -axo pid=,uid=,lstart=,time=,utime=,ucomm=` (0.03-0.04 CPU-s). This covers WindowServer, kernel_task, syspolicyd, XprotectService and secd (M, d).
4. **Ownership.** Walk ppid to a root in the union root set (fix row 8). For new unrooted pids:
   - Read `CLAUDE_CODE_SESSION_ID` through KERN_PROCARGS2 (539 reads in 23 ms) (M, d).
   - Otherwise use the launchd label from `launchctl list`.
   - Otherwise file it under `other-501:<comm>`.
   - Split automation Chrome from yours with compressor-sentinel's existing CDP argv test.
5. **Agent join.** Extend the existing single jq call in `hooks/post-tool-batch.sh` with `tool_use_id`s, a sha of each Bash command, `agent_id` and the payload byte count. That adds 0 forks. Match the tool shell's `eval` body hash offline (d).
6. **Replace `top`.** Swap rung 4's `top -l 1` for `ri_phys_footprint`, and keep the `ps` RSS fallback for WindowServer. This saves 1.5-1.7 CPU-s per tick (M, d/sk).
7. **Add two latency signals:**
   - Launch-to-registration time (`startedAt − procStart`), plus a count of claude pids older than 20 s with no session JSON.
   - A normal-priority 1 ms wake-latency probe reporting p50/p90/p99. The skeptic measured p50 1.6 ms and p99 17.4 ms at load 83-102 (I; M, i/sk).
8. **Cadence.** Fix the launchd band first (fix row 5). If that is not enough, run only the libproc pass in a persistent 10 s loop, at ~0.2% of a core (I, d).
9. **Output.** Write `~/.claude/logs/attrib.jsonl` with deltas plus a cumulative value per root, ~4-5 KB per row, rotated by `rotate-autonomy-logs.sh` (I, d).
10. **Positive control on every row.** Require attributed ≤ host busy × 1.05, otherwise mark the row `accounting: overflow`. Always report `unseen`; expect 6-9% (M, d/sk, a2/sk).

Before trusting the numbers:
- Calibrate `exec_hook` on a quiet box: 20k `posix_spawn` against 20k bare forks.
- Compare one tree's footprint sum with `footprint(1)`.
- Tag the measuring workflow's own tree so it can be excluded.

## 5. Scaling path

**Unit.** An agent here is a sustained, time-averaged open agent (a session with its subagents) at today's ~14% in-flight duty. Today that is ~20 open, 5 busy and 2.6 generating on 4 accounts, which are saturated (M, f). Quota follows generating hours, not how the agents are counted.

| | 100 agents | 250 agents | 1000 agents |
|---|---|---|---|
| Relative to today | 5x the time-average; about today's peak open count | 12.5x | 50x |
| Binding constraints, in order | Quota, then CPU on the one Mac | Quota and terms exposure, then landing and oversight | Terms, quota, landing and oversight; hardware last |
| Accounts at today's duty (0.262-0.390 per agent; I, f/sk) | 26-39 ($5.2-7.8K/mo) | 66-98 ($13-19.5K/mo) | 262-390 ($52-78K/mo) |
| Accounts if every agent works continuously (~1 each; I, f) | ~100 ($20K/mo) | ~250 ($50K/mo) | ~1,000 ($200K/mo) |
| Accounts if always generating (1.78-3.11 each; I, f/sk) | 178-311 ($36-62K/mo) | 445-778 ($89-156K/mo) | 1,780-3,110 ($356-622K/mo) |
| Phone numbers (max 3 accounts each) | 9-13 | 22-33 | 88-130 |
| Hardware (I, g/sk; Linux multiplier unmeasured) | The Mac as cockpit (~13 agents comfortable) plus 1-2 Ryzen 9950X/128 GB | 2-5 Ryzen 9950X plus a browser-pool host | ~5-20 Ryzen 9950X-class, or 4-8 Threadripper 9980X, plus pooled browser hosts |
| Hardware cost | $3.5-9K | $7-22.5K | $18-90K (9950X) or $56-152K (9980X) |
| Lands/day needed vs a 185-570/day ceiling (I, h/sk) | ~220 | ~550 | ~2,200-2,700 (4-15x over) |
| Stale-gate share per round (I: Poisson on a 386 s gate; today's observed 36% is burstier) | ~60% | ~90% | ~100% |
| Permission blocks/h; pages/h stuck over 1 h (I, h/sk) | 15-18; ~1 | 37-45; ~2 | 150-180; 7-9 |
| Verdict | Feasible if 26-39 accounts is acceptable on terms grounds | Hardware can be bought. Landing needs batched landing or more trunks. Oversight is over budget | Infeasible on personal Max accounts |

**Linux box recommendation.** One Ryzen 9 9950X with 128 GB DDR5 and 2 TB NVMe, at ~$3.5-4.5K. Re-quote it: 64 GB kits rose ~40% in a month (g/sk).
1. Use it first as the CDP browser pool and heavy-tool host. That moves the largest CPU category and ~9.5 GB of RSS off the Mac.
2. Then run sessions in tmux with one `CLAUDE_CONFIG_DIR` per account and a 1-year `claude setup-token` token per account (g).
3. Port the hooks first, because hooks run where the session runs. About 35-45% of scripts and 37-50 hooks call macOS-only commands (M, g/sk).

What Linux adds:
- Cheaper process spawn (by how much is unmeasured on our mix).
- No XProtect and no WindowServer.
- A cgroup `MemoryMax` per session, which contains the runaway class behind the panics.
- 4M pids and 4096 ptys (g).

Quota is per account, so moving sessions to Linux changes nothing about it (g).

**What is infeasible, and why**
- **Quota.** It costs a linear $200 per 2.6-3.8 open agents. Those rates are supply-capped floors. These 4 accounts cannot buy overage (`can_purchase_credits=false`), and Fable is capped at 50 pp per account per week (h/sk, f).
  - Levers that stay inside your constraint: lower duty per open agent, and a cheaper tier for bulk agents. Sonnet 5.5 draws ~0.8x Opus 5.5 per hour; Haiku is unmeasured (I, f).
  - One account can feed ~4 generating streams for 5 h before the 5-hour window walls it (I, f).
- **Terms.** Re-fetched 2026-10-04 (h/sk):
  - https://code.claude.com/docs/en/legal-and-compliance: "Advertised usage limits for Pro and Max plans assume ordinary, individual usage of Claude Code and the Agent SDK." Also: Anthropic "reserves the right to take measures to enforce these restrictions and may do so without prior notice."
  - https://www.anthropic.com/legal/consumer-terms (effective Oct 8, 2025):
    - §12: Anthropic may suspend or terminate access "at any time without notice to you if we believe that you have breached these Terms", with no refund after a termination for violation.
    - §2: "You also may not make your Account available to anyone else."
    - §3(7): restricts bot or script access "except when … via an Anthropic API Key or where we otherwise explicitly permit it". That makes large scripted fleets less settled than "Claude Code is permitted".
  - https://www.anthropic.com/legal/aup (effective Sept 15, 2025): "throttle, suspend, or terminate".
  - https://support.claude.com/en/articles/8287232-verifying-your-phone-number: at most three accounts per phone number.
  - No clause bans multiple accounts per person. The "not against terms" quote is secondary and undated.
  - Enforcement scale is generic: 11.4M accounts banned Jan-Jun 2026, with 42k of 398k appeals overturned. GitHub #12786 is a closed client bug, not evidence of device-level enforcement.
  - The loss mode for hundreds of personal accounts run as one fleet is all of them at once.
- **Landing.** The optimistic lane's ceiling is set by gate duration (p50 151-467 s by half-month), not by the lock. Only shorter gates, batched landing or more trunks move it (h/sk).
- **Oversight.** 7-9 stuck pages per hour at 1000 is far over a 1 page/h budget (I, h/sk).
- **Operations.**
  - Hundreds of logins, each with its own re-login date.
  - The usage endpoint already returned 1,764 `429 poll-throttled` lines on 4 accounts (M, f).
  - No per-account concurrency throttle was seen up to ~20 streams per account. Higher counts are untested (M, f/sk).

The verdict would change only outside your constraint: a Team or Enterprise seat model, plus multiple trunks (h).

## 6. Skeptic corrections

**Refuted or weakened claims**
- w1: "load 175-290" describes only the audit's own peak window. Time-weighted, load is ≥175 for just 6-12% of the time.
- w1: "room for 35-40 more sessions" leaves out ~9.5 GB of reparented browser trees, and CPU binds first.
- w1: so little CPU is demoted partly because `qos-batch.patterns` has only 4 rows and lists no media or OCR tools. Media averages ~0.3 core, and reaches 2-3 cores only at peaks.
- w1: "reboot in ~3 days" is the 6 GB policy alarm, at 2.4-3.3 days. The reboot is precautionary, since the prior boot reached 14.78 GB.
- w1: the Stop chain is worse than reported (p50 ~10 s, ~84% session-continue cancels). `read -d` costs ~0.3 s per 400 KB, not 1.98 s, and its causal link to the timeouts is unproven.
- a1: the knee is a band rising from ~12 sessions, not a threshold. The clearest step is 12-14 → 15-17, and the bootstrap CI is +0.01 to +0.40.
- a1: 21 of 26 days is one-sided p 0.0012. The test does not control for activity and does not locate a knee.
- a1: the late-tick ratio is ~2.5-3x, not 7x, once 09-02 is excluded.
- a1: "2.7x per-session cost" ranges 2.0-5.6x by estimator, and reflects more bursts, not a larger direct cost.
- a1: the marginal resident session costs 0.5-1.7 load depending on lag, or 0.15-0.17 core at a 30-60 min lag.
- a1: "~6 cores to short-lived execs" was a residual. The measured figure is 2.0-3.6 cores.
- a1: memory killed the box at 5-22 sessions through runaways that arrived with 8-18 GB of headroom logged.
- a2: the dark share is 20-29% short-lived processes plus 6-8% unattributed, not 54%.
- a2: refuted. "~9 ms per spawn ≈ 5.4 cores" does not hold: spawns cost 2-4.6 ms and short-lived processes total 2.0-2.9 cores.
- a2: browsers are 35-38% of the box, not ~20%. Session trees are ~38%, not "claude 8%".
- a2: "load is driven by what a call launches" is not established.
- a2: launchd's share of births is 51-68% and unstable. By CPU it is 6-12%.
- b: the peak of 70 was a headless probe burst. Operator workload peaked at 50.
- b: median load per core is ≥2.5 from ~3 active agents. That line is uncalibrated and does not measure lag.
- b: the per-agent coefficients are unstable and change sign. "300 load/core at 1000" is unreliable.
- b: `headroom_gb` cannot bind, and swap reached 40.6 GB within the window.
- c: "0 Claude native crashes" covers 7.5 days, not 30, and 32 abrupt-unknown deaths have no stderr.
- c: unexplained deaths are ~3.6x (raw) or ~2x (episodes) per session-hour, not 10x.
- c: the sampler gap measures starvation of a nice-10 job, not interactive lag.
- c: whether kitty crashes track load is indeterminate (3 episodes), and the wedge precursor is live.
- c: the cause of the unexplained deaths is unknown. The 10-02 pane-close sweep refused every pane.
- d: ps misses 31-39% of busy CPU, and churn explains about three quarters of that.
- d: refuted. "Unseen 18-29%" double-counts root daemons; the true figure is ~9%.
- d: refuted. Ticks cost 11.4-12.9 CPU-s about every 154 s, so dropping `top` saves 0.5-0.6 CPU-s/min, not 1.8.
- d: spawn and exec rates depend on load. Label the exec field `exec_hook_dt`.
- d: 4 of the 5 sessions without a JSON were the startup hang, and the fifth was an attach client.
- e: a subagent costs 0.6-11 MB, not 0-5 MB.
- e: the lead pays ~10% of a core fixed plus ~0.8% per agent, which is 8-23 cores at 1000, not 19.
- e: its ceilings work out to 55-100 and 110-200 agents from its own inputs, and both are upper bounds.
- e: the agent-browser trees belong to live sessions; they are not orphans.
- f: 1.06 pp per generating hour on the one clean week; the prior week was 1.85.
- f: 0.156-0.232 pp per open hour, i.e. 2.6-3.8 agents per account at most, as a supply-capped floor.
- f: 1000 open agents need at least 260-390 accounts. Always-generating agents need 2,000-3,100.
- f: not every rate_limit error was a quota wall: 3 long-context throttles occurred on 09-30. Wall hits were understated about 10x. No concurrency throttle was seen.
- g: refuted. "~10 agents per core pinned" came from the brief. The measured figure is 2-5 pinned and ~1.3 comfortable.
- g: the spawn tax is 1.0-3.6 cores.
- g: the Linux "10x" is Go wall time measured in a VM. The multiplier itself is unmeasured.
- g: the 9950X ranking depends on that multiplier, and each box holds ~50-130 agents.
- g: the XProtect ceiling of 250/450 agents is unsupported.
- g: the quota gap is 40-500x the current accounts, not 14-24x.
- g: refuted. Offload frees 22-40% of the Mac's CPU (1.3-1.7x), not 2-3x.
- h: the stale-gate rate is 36% per CAS attempt, and the per-round green gate has p50 386 s.
- h: the ceiling is 185-570 lands/day, after 3 rounds plus statics and ratchets.
- h: the current rate is 44 lands/day, not 70. That projects to ~2,700/day at 1000 (~11x). There were 8 real reverts, not 25.
- h: its quota figures come from August data and run low. Current data gives 286 accounts (open) or ~1,000 (busy).
- h: current enforcement is 11.4M bans, and #12786 is a client bug.
- h: oversight at 1000 is 150-180 blocks/h and 7-9 pages/h.
- i: refuted. Kernel time that no process owns is at most ~0.3 core, not ~6 cores.
- i: refuted. The box creates ~630 forks/s, not ~10 execs/s, and churn costs ~3.6 cores.
- i: refuted. Session-spawned work is 3-4.5 cores plus 1.7 cores of agent-browser, not 0.5 core.
- i: more cores halve queueing only if demand stays fixed, and demand grows with agents.
- i: the slowdown at load ~90 is x5-8. Keystroke wait is unmeasured.
- j: the hang was bounded at 15-46 min, not a deadlock.
- j: F1 belongs in the settings.json `env` block. It is unverified, the token read can still stall, and it loses mkcert trust.
- j: secd's backlog did not rebuild under load, and its trigger is unknown.
- j: Chrome was 8 of 28 secd peers, pid 33442 was misattributed, and /tmp-profile Chrome also writes to secd.
- j: multi-hook startup over n=68 has p50 2.9 s and p95 10.1 s.

**Cross-report conflicts, resolved**

| Conflict | Resolution |
|---|---|
| Fork rate: i ~10/s vs a1, a2, d, g, w1 at hundreds/s | Hundreds per second: 530-650/s typical. i diffed surviving processes only (M, a1/sk, i/sk) |
| CPU missing from `top`: i "6 cores of kernel", a2 "54% dark", d "unseen 18-29%" | Reaped children 2.0-3.6 cores, root daemons 1.2-1.4, unseen 6-9% (M, a2/sk, d/sk, i/sk) |
| Agent share: i 0.4-0.6 cores, a2 8% vs d 32-38% | Both are right for the binary. Session trees use 2.0-3.1 cores without the observer (M, w1/sk) |
| Memory: i "103 MB unused", e "1.25 GB unused" vs w1 22-26 GB | Free pages vs reclaimable pages; both are correct. Headroom is not a margin against runaways (a1/sk) |
| Per-session marginal: 0.03 vs 0.05-0.09 vs 0.1 core | ~0.1 core on average, heavy-tailed. 0.15-0.17 core at a 30-60 min lag (M, w1/sk, a1/sk) |
| Knee unit: a1 12-15 sessions vs b 5-9 working agents | Consistent if ~1/3 of sessions are active. b's active count is the better control (a1/sk) |
| Per-subagent cost: b 0.43 load/core vs e ~0.04 | e: a mechanistic measurement. b's is a confounded fit (b/sk) |
| Ceiling: e 50-80 agents vs a1/b history | History governs the ceiling you will actually hit. e's are upper bounds (e/sk) |
| Quota: h 160/450 accounts, g 6.2-11 sessions vs f 286/1,008 | f, with current data, as a floor: 260-390 / ~1,000 / 2,000-3,100 (f/sk, h/sk) |
| Peak concurrency: b 70 vs f max 213 per 10-min bin | b's per-minute count. f's bins stack sequential subagents (f/sk) |
| agent-browser "orphans" (e, i) vs "live tabs" (w1) | w1 is right. The true orphans are /tmp-profile headless Chrome (e/sk, j/sk) |
| Hooks per Bash call: a2 ~18 vs e, w1 20 | 20: 11 Pre + 8 Post + 1 Batch (e/sk) |
| Deaths vs sessions: a1 flat vs c 10x | ~2-3.6x per session-hour; a1's normalization is right (c/sk) |
| Kitty risk: c "quiet since 09-16" vs w1 "live" | w1: 189 zombies on 48854 now (c/sk) |
| capacity-alarm cadence: d 60 s | Median 154 s, mean 199 s (d/sk) |
| w1 internally: kalloc "reboot in 3 days" (§1) vs "not the trigger" (§4) | §4: the prior boot ran to 14.78 GB and ended in a shutdown stall (w1/sk) |
| Missing session JSONs: d G14 vs j | The same 4 pids were the hang, and both reports are stale after 02:05:49 (j/sk) |