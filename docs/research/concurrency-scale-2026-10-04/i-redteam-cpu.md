# Red-team: "lag and crashes = CPU saturation from session-spawned work" (2026-10-04 01:40-02:00)

**Verdict: half right, wrong half named.** The run queue IS saturated and IS the lag mechanism,
but the agents' own work is 0.4-0.6 of 10 cores. Browsers, security daemons and ~6 cores of
kernel time no surviving process owns are the load. Crashes are a separate story.

## State (load 120-164, 0% idle, 60/40 user/sys, ~1400 procs, 8100-8900 threads)

| Measurement | Value | Source |
|---|---|---|
| Per-process CPU sum | **366% (2 s), 396% (5 s)** vs 1000% busy | `top -l 2 -s N`, 2nd sample |
| Chrome + Dia / claude ×20 / Python+shell | 143-171% + 75% / **40-58%** (max 8.3 each) / 22% + 18% | same |
| XprotectService, syspolicyd, fseventsd, mds | 33, 11, 6, 11% | same |
| WindowServer / kernel_task | 28-66% / 33-40% | same |
| CPU share, pri-31 process | **×8-20 slowdown** (0.12 s cpu → 0.94-2.34 s wall) | python loop ×3 |
| Wake latency, 1 ms sleep | p50 1.3 / p90 5.4 / p99 26 / max 96 ms | python ×200 |
| fork+exec `/bin/true` | 2-10 ms | `time` ×60 |
| Exec churn | 84-110 new pids/10 s; 316k of 328k faults/s from procs dying inside the window; 1.2 GB/s zero-fill | pid diff; `vm_stat -c 3 2` |
| Memory | 103 MB unused, 7.4 GB compressor, swap 1.7/3 GB, **0 compress/s, 0 swap/s**, pressure 0 | `vm_stat`, `sysctl` |
| Thermal / disk / GPU / API | none recorded / 2.4-5.2k tps, 3 U-state procs / 60% util, 12.2 GB alloc / 0.10 s TLS RTT | `pmset`, `iostat`, `ioreg`, `curl -w` |
| Limits | ptys 44/511, procs 1443/16000, 203 zombies (187 under kitty, no fds) | `sysctl`, `ps` |

## Alternatives

**WindowServer / GPU compositing — partly explains load, not the limiter.** 28-66% of one core,
pri 79, not pegged. kitty holds **8 OS windows / 8 tabs / 20 panes, all active** (`kitty @ ls`);
`machine-lag-and-kitty-2026-08-06.md` §6a-bis showed cost scales with OS-window count (8 → 1 is
the lever). GPU 60% is driven by agent-browser Chrome 65489 (GPU helper 35-62% CPU) and Dia.

**kitty renderer — ruled out for lag.** 0.8-1.0% CPU, **pri 47** (GUI boost; default threads
are 31), `repaint_delay 16 / input_delay 5` (kitty.conf:944,950). Scheduled ahead of the crowd.
The 187 zombies cost nothing but show stalled child reaping — relevant to crashes, not lag.

**Compressor / swap — ruled out now; real on 09-29.** Zero compressions and swap traffic over
10 s; the 7.4 GB compressor and 1.7 GB swap are static. "68% free" is `memory_pressure`'s
reclaimable figure. `JetsamEvent-2026-09-29`: free 424 MB, **coreaudiod 38 GB** (34 MB today).
Both jetsam files kill only `hog` (per-process-limit, 3840 pages) — the repo's own
`bin/cc-jetsam-exec` probe, not an OOM.

**pty / fd / proc limits — ruled out.** 44/511, 1443/16000, 245,760 fds/proc.

**Disk / fsevents — ruled out as limiter; adds sys.** Reads come from a repo-wide `grep -l
ms365`, `session-index-sweep.sh find`, `cc-teardown find`, `du`, XProtect scans. 3 procs in U.

**Network / API — ruled out.** 100 ms round trip; agents at 3-8% CPU are waiting, not computing.

**Claude Code's event loop — partly explains the *felt* typing lag.** The TUI is raw-mode: the
echo is Ink re-rendering in node at **pri 31** (bg-spare nice 5). At load 120-164 that thread
gets 1/12-1/16 core (measured ×8-20), so each keystroke waits tens-hundreds of ms while kitty
and WindowServer sit above it idle. Typing lag is the agent starving, not the terminal.

**Exec churn + Gatekeeper — partly explains sys.** ~10 execs/s at 2-10 ms plus syspolicyd 11%,
XprotectService 33%, 316k faults/s from exec'd images. Hooks grew to PreToolUse 20 / PostToolUse
15 (`~/.claude/settings.json`) vs 12 at 392 ms/Bash call in the 08-06 doc §10. Yet processes
younger than 10 s hold only 0.13-0.38 core — churn is a tax, not 4 cores.

**Unattributed kernel time — the open axis.** Per-process CPU sums to 3.7-4.0 cores at 0% idle
at two window sizes; the 07-29 doc's table shows the same gap. ~6 cores belong to no surviving
task: scheduler/IPC over 8k threads, fault handling, interrupts. Needs `sudo powermetrics` or
`spindump` — out of bounds here.

## Key questions

(a) Typing lag is **not** kitty/WindowServer (pri 47/79, ~1%/~40%); it is node at pri 31 at
1/12 share. (b) 42% sys is **not** compressor (0/s) or thermal; it is churn + Gatekeeper + faults
+ ~6 cores unattributed, all scaling with process/thread count. (c) Doubling cores halves the
starvation (164/20 vs 164/10) but removes nothing while an orphaned headless Chrome burns 148%
(parent agent-browser 65435, reparented to launchd), browsers hold 1.5-2.5 cores and kitty keeps
8 OS windows; cutting agents touches 0.5 of 10 cores.

## Blockers
"Lag" unresolved between typing echo and agent speed — both reduce to run-queue share.
Unattributed kernel time needs sudo. No kitty/WindowServer/claude crash reports in 7 days; kitty
crash attribution stands as in `kitty-crash-attribution-2026-09-17.md`.
