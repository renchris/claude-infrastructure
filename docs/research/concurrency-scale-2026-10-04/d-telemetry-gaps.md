# D — Telemetry gaps: attributing CPU, memory and process load to session → agent → tool work

Measured on this box 2026-10-04 06:40–07:10Z: 1,440–1,680 procs, load 112–160, **0.0% idle on all 10 cores**,
host split user 55–66% / sys 34–45%. Every number is tagged **MEASURED** (run here, method stated) or
**INFERRED** (reasoned or documented, not run). Reproducible probes: `/tmp/concurrency-scale/.probe_*.py`,
`.structs.py`, `/tmp/cs-measure.sh`.

## 0. Answer first

1. **(a) Yes, and without sudo.** A per-session cumulative CPU counter can be built for every uid-501 tree
   from libproc: `proc_pidinfo(PROC_PIDTASKALLINFO)` for ppid, start time and own user/sys time, plus
   `proc_pid_rusage(RUSAGE_INFO_V6)` for **`ri_child_user_time`/`ri_child_system_time`**. Those two fields
   carry the CPU of every child the process has already reaped. That is the piece `ps` cannot supply. A
   `ps`-snapshot census misses **~42% of busy CPU**, because that CPU belongs to processes that started and
   exited between samples. MEASURED over 30 s: host 300 cpu-s busy, live-process `ps` deltas 174.6. The
   live claude pid 82868 shows it plainly: own CPU 270 s, reaped children 1,702 s, of which 920 s is sys.
   The tool and hook churn is the sys-heavy CPU.
2. **The full libproc pass costs ~10 ms of CPU per tick.** Two snapshots, tree classification and env-tag
   reads come to 0.05–0.07 CPU-s. Launched as a fresh `python3`, it costs 0.10 CPU-s and 0.15–0.20 s
   wall. By comparison, the `top -l 1` call that `capacity-alarm.sh` makes every 60 s costs
   **1.5–2.4 CPU-s** (MEASURED ×9). A whole capacity-alarm tick costs **2.8 CPU-s, 4.2 s wall** (MEASURED ×2,
   outputs sandboxed). Moving rung 4 onto `ri_phys_footprint` pays for all the new telemetry about 20 times
   over. libproc's footprint matches top's MEM column within 1%: kitty 1662 vs 1647 MB, node 795 vs 796 MB.
3. **(b) Skip `powermetrics` as a standing daemon.** It needs root. Its unique extras are per-coalition
   dead-task billing, wakeups, cluster residency and energy. Coalitions here are per terminal app (one kitty
   coalition holds 706 procs across about 20 sessions), so coalition granularity is not session granularity.
   Its task sampler walks every task the way `top` does, so its cost is likely at or above `top`'s
   ~2 CPU-s per sample (INFERRED; it could not be run without sudo). Keep it as an on-demand diagnostic.
4. **(c) Two system-wide rates are nearly free.**
   - **Fork rate:** the gap between the PIDs of two forks the sampler already makes. Zero extra cost.
     Measured baseline **~640–975 forks/s**.
   - **Exec rate:** the unprivileged sysctl `security.mac.asp.stats.exec_hook_count`, read in under 1 ms.
     Measured baseline **~440–660 execs/s**.
   - **System sys share:** `host_processor_info`, 16 µs per read.
   - **Per-process sys explainers:** syscall counts, context switches and faults. These come free in the
     same TASKALLINFO struct.
   - **Per-session fork/exec counts** have no unprivileged source. Proxies, plus a root rung for
     on-demand use, are in §1.
5. **Extend `capacity-alarm.sh`; do not add a daemon.** It already owns the per-session cost walk
   (`read_session_tree_mb`, scripts/capacity-alarm.sh:935) and already calls `proc_pidinfo` through python
   ctypes (scripts/capacity-alarm.sh:995-1037). The agent-level join's other half goes into the existing
   `hooks/post-tool-batch.sh` jq call at no extra fork cost. See §4.

## 1. Gap table

| # | Question we cannot answer today | Missing signal | Proposed source (cost) |
|---|---|---|---|
| G1 | Which **session** is burning the CPU, including its short-lived tool and hook children? | Per-session cumulative CPU over the whole tree, **including reaped children**. Today there is only tree RSS (capacity-alarm.sh:935) and a point-in-time `%cpu` in qos-census.sh:299. | Σ over the session tree of task `total_user+total_system` + rusage `ri_child_user+ri_child_system`, with reap correction (§2.3). libproc, 8 ms per snapshot at 1,632 pids. MEASURED. |
| G2 | How much box CPU is invisible to snapshot samplers? | CPU of processes born and dead between ticks. | The same child counters. Budget check: Σ(attributed) vs host busy ticks. MEASURED: `ps`-only sees 58% of busy; libproc with child counters sees 71–82% from uid 501 alone. |
| G3 | User vs sys split, system-wide and per session | Host tick split (no sampler records it); per-tree user/sys. | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` per CPU, 16 µs, MEASURED. Per-tree split from `total_user` vs `total_system` and `ri_child_user` vs `ri_child_system`. |
| G4 | System fork rate and exec rate | No counter is recorded anywhere. | Fork rate: Δpid of the sampler's own child, divided by measured elapsed time (handle the wrap at 99,999). Exec rate: Δ`security.mac.asp.stats.exec_hook_count`. A 4,000-spawn calibration moved it about +1,800 against a noisy ~560/s background, and 4,000 bare forks moved it about 0. So it tracks exec and not fork, but the exact ratio is **unconfirmed** (PARTIAL). |
| G5 | Fork/exec count **per session** | No unprivileged per-process fork counter exists. | Lower bound: count of new (pid, start) pairs per tree per tick. Proxy: Bash calls per session from `tool-batch-census.jsonl` (already logs `sid`, `n`). Exact (root, on demand only): `eslogger exec fork exit`, which needs Full Disk Access and would emit ~1,500 events/s here (too heavy to run continuously, INFERRED); or `accton`, a 40-byte record per exit (~3 GB/day here, INFERRED) carrying command, uid and user/sys but **no pid/ppid**, so it gives counts by command and not by session. |
| G6 | Which **agent** in a session spawned the work | In-process subagents share the claude pid **and** the env tag. MEASURED: this subagent's shell carries the lead's `CLAUDE_CODE_SESSION_ID=c5cd1b06…`. | Join: the tool shell's argv embeds the command verbatim (`zsh -c source …snapshot… && eval '<cmd>'`, MEASURED) → sha of the eval body → PostToolBatch `tool_calls[].tool_use_id` + sha of `tool_input.command` → `tool_use_id` found in `…/<sid>/subagents/agent-<id>.jsonl` → agent. Teammates are separate claude.exe pids and need no join. |
| G7 | How many agents are live per session | No agent count exists. Spawn-depth logs exist; a live count does not. | `…/projects/<proj>/<sid>/subagents/agent-*.jsonl` with mtime under 120 s, plus `.meta.json` (`agentType`, `toolUseId`, `spawnDepth`). Stat only the dirs of live sessions. A global glob costs 2.9 s wall (MEASURED), so do not glob. Example: 8 live of 11 in this session (MEASURED). |
| G8 | Work that **outlives** its parent or its session | Orphans reparented to pid 1 drop out of every ppid walk (TREE_WALK_AWK stops at pid 1, capacity-alarm.sh:886-894). | Env tag `CLAUDE_CODE_SESSION_ID` read through `sysctl KERN_PROCARGS2` (same uid, no sudo). 539 reads took 23 ms (MEASURED). Tags were found on orphaned vitest, tsx and deploy-live trees (MEASURED). A tag naming a dead session marks **ghost work**: 0.3–1.1% of busy (MEASURED). Untagged orphans: map their top ancestor to a launchd label with `launchctl list` (10 ms; e.g. pid 57742 → `gl.reso.postland-verify`, 1064 → `com.reso.sevenrooms-sidecar`). |
| G9 | Who is **starved**: scheduler wait per session | Only system loadavg and the reso `runnable` count (load-sampler.sh:62). | `ri_runnable_time` minus CPU. MEASURED: a utility-QoS spinner got 0.04 s of CPU in 2 s with 2.0 s runnable; a default spinner got 0.45 s. |
| G10 | Did QoS demotion actually move the CPU? | qos-census.sh:50-53 says "PRI is the only unprivileged signal there is". | **Refuted**: `ri_cpu_time_qos_{utility,background,legacy,…}` are per-process, cumulative and unprivileged. The demoted spinner's time landed in `utility` and the plain one's in `legacy` (MEASURED). `ri_user_ptime` gives the P-core share. |
| G11 | Session CPU split into tool work vs hooks vs claude's own JS | All three fold into the claude pid's child counters once reaped. | Live split by the argv class of the root's direct children (`/bin/zsh -c source …snapshot` vs `/bin/bash …/hooks/*.sh` vs MCP servers). The reaped remainder can only be **estimated**: hook invocations (tool-batch-census `n` × registered hook count) × per-hook cost (scripts/hook-fork-census.sh). Exact only with root `eslogger`. Claude's own JS is the root's own `total_user+system`; for 82868 that is 270 s of 1,972 s, ~14% (MEASURED). |
| G12 | System-daemon CPU **caused by our churn** (syspolicyd, XprotectService, fseventsd, logd, mds, WindowServer) | libproc cannot read uid≠501 (431–476 of 1,632 pids failed, MEASURED). | setuid `/bin/ps -axo pid,uid,lstart,time,utime,ucomm` costs 0.03–0.04 CPU-s (MEASURED). Δtime per daemon, regressed on Δexec_hook_count and Δ`sandbox_upcall_count`. MEASURED 30 s: uid≠501 used 23.1 cpu-s (8% of busy); WindowServer 8.6, fseventsd 3.9, syspolicyd 3.1, XprotectService 1.5. |
| G13 | Per-session memory without the 2.34× RSS overcount (capacity-alarm.sh:22-27) | Per-tree footprint. | Σ `ri_phys_footprint` per tree from the same pass (INFERRED to overcount far less than RSS, because clean shared file pages are excluded; not yet compared tree-for-tree). |
| G14 | Is the session root set itself complete? | `cc_sp_census` matches argv only on `claude-code/bin/claude.exe$` or `node_modules/.bin/claude$` (scripts/lib/spawn-presence.sh:184-185). | MEASURED: 2 `claude bg-spare` sessions and 2 `.bin/claude --permission-mode` sessions own a `sessions/<pid>.json` but fail that argv test. 5 live tty sessions have **no** json at all (pids 53373, 4780, 90282, 3040, 3121). Root set = union of `~/.claude*/sessions/<pid>.json` (`pid`, `sessionId`, `procStart`, `kind`, `status`) ∪ `~/.reso/live-sessions/*` (live-session-registry.sh:16,134) ∪ argv-family roots. A root with no id resolves its sid from a Bash-tool child's env tag, else `anon:<pid>:<start>`. |
| G15 | Unattributed uid-501 CPU (Chrome helpers ~20% of busy, stray `grep` 3–5%) | No owner. Chrome helpers carry no session tag and no launchd label (MEASURED). | Report them as named buckets (`other-501:<comm>`) rather than dropping them. For Chrome, a CDP-flag argv test exists already in compressor-sentinel.sh:651-657 and can split automation Chrome from the operator's. |

## 2. Sampler design

### 2.1 Signals collected per tick, in one python ctypes pass

| Level | Signals | Source |
|---|---|---|
| Host | per-CPU user/sys/idle/nice ticks, with E-cores (cpu0-1, perflevel1 = 2 CPUs) separated from P-cores (INFERRED mapping) | `host_processor_info` (call `vm_deallocate` on the returned array; the probe leaks it) |
| Host | `exec_hook_count`, `exec_hook_work_time`, `sandbox_upcall_count/time` | `sysctlbyname` |
| Host | fork-rate stamp: pid of the sampler's own `ps` child (needed anyway for G12) | free |
| Per pid (uid 501) | ppid, pgid, start (s, µs), comm(16), uid; task total_user/total_system, syscalls_unix/mach, csw, faults, threadnum | `proc_pidinfo(pid, PROC_PIDTASKALLINFO=2)` |
| Per pid (uid 501) | child_user/system, runnable_time, cpu_time_qos_*, user_ptime/system_ptime, phys_footprint, instructions/cycles, energy_nj, diskio | `proc_pid_rusage(pid, RUSAGE_INFO_V6)` (layout copied from the SDK `sys/resource.h`) |
| Per pid (other uid) | lstart, time, utime, ucomm | one setuid `ps -axo pid=,uid=,lstart=,time=,utime=,ucomm=` |
| New, unrooted uid-501 pids only | `CLAUDE_CODE_SESSION_ID` env tag | `sysctl {CTL_KERN, KERN_PROCARGS2, pid}`, cached by (pid, start) |
| New direct children of roots that are `zsh -c source …snapshot…` | sha256 of the `eval '…'` body | same KERN_PROCARGS2 read |
| Roots | pid→sid, kind, status, procStart | `~/.claude*/sessions/*.json`, `~/.reso/live-sessions/*` |
| Agents | live count per session; per-agent `toolUseId` and `agentType` | stat + read `subagents/agent-*.meta.json` for **live sessions only** |
| Labels | pid → launchd label | `launchctl list` (10 ms) |

All times come back in mach ticks. Convert with `mach_timebase_info` (125/3 on this box); the converted
values match `ps` (82868 reads 270.1 s from libproc and 4:30 from `ps`).

### 2.2 Interval

- **Session level: the existing 60 s.** Every counter is cumulative, so deltas integrate everything that
  happened inside the interval, short-lived processes included. Only two things are lost: an orphan that
  exits between ticks (launchd reaps it, so its CPU never reaches a session counter) and tree members
  reaped by a reaper outside the tree. The budget check in §2.3 exposes both.
- **Agent level: also 60 s, accepting a bias.** A Bash call caught alive at a tick is attributed exactly.
  The remainder of the session's reaped-child delta is apportioned across that tick's agents by their
  PostToolBatch call counts. The expensive calls (builds, test suites) run longer than 60 s and are caught.
  The bias falls on many cheap calls. If the bias matters, a 10 s cadence of the libproc pass alone costs
  ~0.01–0.03 CPU-s per tick in a persistent loop, ~0.2% of one core (INFERRED from the 0.05–0.07 s
  two-snapshot measurement).

### 2.3 Accounting algorithm (the part the prototype got wrong first)

- `cum(p) = own(p) + child(p)` for every live pid, keyed on (pid, start_s, start_us) so a reused pid cannot
  match.
- Delta for a pid alive at both ticks is `cum_B − cum_A`. A newborn's delta is `cum_B`.
- **Reap correction:** for every pid present at tick A and gone at tick B, walk A's ppid chain to the
  nearest ancestor alive at **both** ticks, and subtract `cum_A(gone)` from that ancestor's delta, for
  **each counter separately** (user and sys as well as the total). Without this, a long-lived child's whole
  lifetime is re-credited when it is reaped. MEASURED failure without the correction: Σ = 512 cpu-s against
  300 cpu-s of host busy. Correcting only at the direct ppid still produced a negative per-session sys
  figure (−289). Propagating the correction to the surviving ancestor closed the budget: Σ(uid 501) =
  214–245 of 300.
- **Positive control, emitted on every row:** `attrib_cpu_s ≤ host_busy_s × 1.05`, or the row carries
  `"accounting":"overflow"`. `unseen = host_busy − Σuid501 − Σother_uid` is reported, never hidden.
  MEASURED unseen: 18–29%. It is kernel, launchd-reaped orphans and residual error.
- Attribution of each pid, first match wins: session tree via ppid walk → env tag of a live session
  (`session-orphan`) → env tag of a dead session (`ghost`) → launchd label of its top ancestor (`launchd:<label>`)
  → `other-501:<comm>` → `other-uid:<comm>` (from `ps`).

**What it shows (MEASURED, two 30 s windows on the corrected prototype):**

| Bucket | Share of busy | User / sys (cpu-s) |
|---|---|---|
| Sessions | 32–38% | 73 / 41 |
| other-501 | 26–28% | Chrome helpers 59–62 cpu-s; `grep` 10–15 |
| launchd jobs | 13–14% | — |
| orphan + ghost | ~2% | — |
| root daemons | ~8% | — |
| unseen | 18–29% | — |

One misleading pre-correction window showed a single session's orphan tree at 292 cpu-s. That is the
artifact the reap rule removes.

### 2.4 Self-cost

| Candidate | Cost per call at ~1,650 procs |
|---|---|
| `ps -axo pid,ppid,cputime,rss,comm` (the brief's) | **0.09 CPU-s (0.01u + 0.08s), 0.18–0.46 s wall**, 9 MB maxrss |
| same with `ucomm` instead of `comm` (no per-pid procargs read) | **0.03–0.04 CPU-s**, 0.06–0.26 s wall |
| `ps -axwwo …,args` | 0.14 CPU-s, 0.44–0.80 s wall, 1.3 MB of output |
| `ps -axwwEo pid,command` (env for all pids) | 0.20 CPU-s, 0.34–0.69 s wall, 2.1–2.9 MB |
| `top -l 1` (any `-n`, any `-stats`) | **1.46–2.43 CPU-s, 3.1–15 s wall** |
| libproc TASKALLINFO + rusage V6, all 1,632 pids | **12 ms CPU, 17 ms wall** (in-process) |
| KERN_PROCARGS2 env read | 539 pids in 23 ms (~0.04 ms each) |
| `host_processor_info` | 16 µs |
| `sysctl -n` exec counters / `vm_stat` | <10 ms wall, ~0 CPU |
| `launchctl list` | ~10 ms |
| Full attribution pass in a fresh `python3` | **0.10 CPU-s (0.06u + 0.04s), 0.15–0.20 s wall, 25 MB** |
| Current whole capacity-alarm tick (kalloc off, footprint damped) | **2.8 CPU-s (0.6u + 2.2s), 4.2 s wall** |

All rows MEASURED. The `ps` rusage keywords `nvcsw/nivcsw/majflt/minflt` print `-` for every process on
macOS, so they are useless (MEASURED). `ps` has `utime` and `time`, and sys = time − utime. `ps` and
`top` are setuid root (`-rwsr-xr-x`, MEASURED), which is why only they can see uid-0 CPU without sudo.

**Net effect of the proposal:** take rung 4's `top -l 1` (capacity-alarm.sh:752 → :824) off the tick, add
the 0.10 CPU-s pass, and the tick falls from ~2.8 to ~1.0 CPU-s. The box gains roughly 1.8 CPU-s per
minute **and** gets the attribution telemetry.

### 2.5 Storage and rotation

- **New file `~/.claude/logs/attrib.jsonl`:** one row per tick. Do not widen `capacity-alarm.jsonl`; its
  row is already ~2 KB and other code parses it.
- **Row shape:**
  `{ts, el_s, host:{busy_s,user_s,sys_s,idle_s,ecore_sys_pct}, forks_per_s, execs_per_s, exec_hook_work_dt, accounting, unseen_s, sessions:[{sid, pid, start, kind, cpu_s, user_s, sys_s, child_s, own_s, runnable_wait_s, qos_util_s, qos_bg_s, pcore_s, fp_mb, procs, new_procs, agents_live, tools_live:[{sha, pid, cpu_s}]}], buckets:{"launchd:<label>":s, "other-501:<comm>":s, "other-uid:<comm>":s, ghost:s}}`.
  Store **deltas**, plus each root's cumulative `cpu_s`, so a missed tick can still be bridged.
- **Size:** ~20 sessions × ~180 B + ~1 KB of buckets ≈ 4–5 KB per row → ~6–7 MB/day (INFERRED).
- **Rotation:** add the path to `DEFAULT_TARGETS` in scripts/rotate-autonomy-logs.sh:429-450 (25 MiB, keep
  8, gzip ≈ 10–20×). That gives ~4 days per generation and ~30 days of history. No new rotator is needed.
- **Agent join half:** in hooks/post-tool-batch.sh:71-82, extend the existing single `jq` call with
  `tuids: [.tool_calls[].tool_use_id]`, `cmd_sha: [.tool_calls[] | select(.tool_name=="Bash") | .tool_input.command | @sha256?]`
  (falling back to an ascii-hash expression if this jq lacks a SHA builtin), and `agent_id: (.agent_id // "-")`.
  This adds 0 forks. Its rotation stays at 4 MiB single-generation (post-tool-batch.sh:39); raise it if
  the join needs longer than ~1 day.

### 2.6 Join to session ids

| Step | Key |
|---|---|
| Process → session | ppid walk to a root whose pid has `sessions/<pid>.json` with matching `procStart`. Else `~/.reso/live-sessions` (pid, sid). Else a child's env tag. Else `anon:<pid>:<start>`. |
| Orphan → session | `CLAUDE_CODE_SESSION_ID` env tag. It survives reparenting because env is inherited (MEASURED on vitest under `cc-jetsam-launch` under an orphaned bash chain). |
| Tool shell → tool_use_id | `sha256(eval body)` = PostToolBatch `cmd_sha` within the same `sid`, with ts inside ±(tick + call duration). If `qos-rewrite.sh` rewrote the command, hash the **final** `tool_input` (PostToolBatch sees the final one; INFERRED, verify). |
| tool_use_id → agent | `grep -l <tool_use_id> <proj>/<sid>/subagents/agent-*.jsonl` offline. No match means the lead's own call. Teammates are their own roots (`--agent-id` argv; the census comment at capacity-alarm.sh:659-660 says claude.exe ≡ teammates). |
| Session → account / worktree | `sessions/<pid>.json` `cwd` plus the config dir it was found in. |

## 3. Alternatives considered and ruled out

- **Standing root `powermetrics` daemon.** Needs a root plist. Coalition-level only. Cost is likely ≥ `top`
  (INFERRED). Its one unique value, dead-task billing, is subsumed by rusage child counters at session
  granularity.
- **`top -l 2` deltas for %CPU.** About 1.7 CPU-s per sample and ~8 s wall (MEASURED), and still blind to
  processes that exit between samples.
- **Continuous `eslogger` or `dtrace`.** Root plus Full Disk Access, or SIP limits. ~1,500 events/s here.
  Reserve for an on-demand per-session fork/exec census (G5, G11).
- **`accton` process accounting.** Root to enable. ~3 GB/day of 40-byte records with no pid/ppid
  (INFERRED from `sys/acct.h`). Gives counts by command, not attribution.
- **Reading env for every pid every tick** (`ps -E`). 0.20 CPU-s against 23 ms for libproc on
  new/unrooted pids only.
- **Rewriting every Bash command to inject `CC_AGENT_ID`.** Works, but `qos-rewrite.sh` already emits
  `updatedInput` (hooks/qos-rewrite.sh:122) and a second rewriter would race it. The sha join reaches the
  same answer read-only.
- **Coalition ids for sessions.** All sessions in a kitty window share one coalition (706 members,
  MEASURED), so coalitions are not session-granular.

## 4. Which sampler to extend

**`scripts/capacity-alarm.sh`** (60 s launchd, Adaptive, Nice 10, LowPriorityIO).

- **Why it fits:**
  - It already owns per-session cost (`read_session_tree_mb`, :935) and the session census (:696).
  - It already uses libproc through python ctypes (:995-1037). The new pass is a sibling of
    `read_coalition_true`, and `CC_CAP_PYTHON` is already a seam (:384).
  - Swapping rung 4's `top` for `ri_phys_footprint` **cuts** its tick cost by ~1.8 CPU-s. Keep the `ps rss`
    fallback (:826) for pids libproc cannot read (uid ≠ 501, e.g. WindowServer).
- **Why not the others:**
  - `compressor-sentinel.sh` is the one sensor that "cannot be starved"; its header argues for keeping
    load off it (:4-19). It already runs two `ps` calls inside `exe_table` (:651-661) every ~12.8 s
    measured tick.
  - `qos-census.sh` runs every 600 s and is a three-state verdict tool. Point it at G10's `ri_cpu_time_qos_*`
    instead; this also retires the "PRI is the only signal" premise at :50-53.
  - The reso `load-sampler.sh` lives in another repo and is resolved from whichever worktree has it
    (`~/.reso/load-sampler-run.sh`).
  - A new daemon would be a fifth sampler on a box with documented sampler-death-under-storm history.
- **The hook half:** extend `hooks/post-tool-batch.sh` (one existing `jq`, 0 extra forks).

## 5. Blockers and open items

- **B1: the `exec_hook_count` ≡ execs ratio is not confirmed.** The background rate (~560/s ± 50) swamps a
  4,000-exec burst. A quiet-box calibration is needed: 20k `posix_spawn` against a 20k bare-fork control.
  Until then, label the field `exec_hook_dt` and do not call it an exec count.
- **B2: `agent_id` on the PostToolBatch payload is unverified.** `tool_use_id` is confirmed
  (tests/post-tool-batch.bats:70-74). The offline transcript join does not need `agent_id`.
- **B3: five live tty sessions have no `sessions/<pid>.json`** (G14), and one maps to sid `scan` in
  live-sessions. Whatever causes that (possibly the startup-hang under investigation elsewhere) also
  degrades root resolution. The fallback chain handles it, but `anon:` rows will exist.
- **B4: the 18–29% unseen residual is not decomposed.** Kernel_task versus launchd-reaped orphans versus
  error has not been split. Check kernel_task Δtime via `ps` (pid 0) first.
- **B5: per-session `phys_footprint` sums have not been compared** against `footprint(1)` for one tree.
  Do that before G13 replaces the RSS-derived `per_session_mb_est`.
- **Adversarial pass (run, integrated above):**
  - Is the child counter populated for the claude.exe runtime? Yes, measured.
  - Does env inheritance survive orphaning? Yes, measured.
  - Is pid reuse handled? Yes, (pid, start) key.
  - Does the accounting close? It did not at first; that found and fixed the reap-propagation bug.
  - Is the root set complete? No; that found G14.
  - Can uid-0 daemons be read? Not by libproc, which is why the setuid `ps` row is in the design.
