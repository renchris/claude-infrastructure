# Bad-outcome ledger, this Mac, 2026-09-04 to 2026-10-04 (30 days)

All times are local CDT (UTC-5). MEASURED = read directly from a file or command on this box. INFERRED = my reading of measured data. The joined load columns come from `~/.claude/logs/capacity-alarm.jsonl` (plus its `.20260919T081621Z.gz` rotation): the nearest sample at or before the event, within 10 minutes. That is 27,838 samples with a median spacing of 70 s.

Machine-readable full ledger (2,932 rows, one per event, with sessions, load_1m, verdict and headroom joined): `/tmp/concurrency-scale/c-outcome-ledger-events.tsv`. Build script: `/tmp/concurrency-scale/c_ledger_build.py`.

## Answers first

**(a) What actually crashes most.** The only native crash reports for the operator-facing parts of the stack are kitty's: 6 crashes, all on 2026-09-15/16, and none since 2026-09-16 20:13. Claude Code (`claude.exe`, Bun) has **0 native crash reports**. WindowServer has **0** hang, spin or crash reports. Chrome/Dia has 2 renderer crashes. The system had **2 kernel panics**, both on 2026-09-16, caused by memory exhaustion from a clang-format swarm. The largest number of process crashes comes from test or dev binaries (bats fixtures, `walkfp`, `fswatch`, `python3.12` BLAS bus errors) and from 17 segfaults in a homebrew `git` daemon. None of those is an outcome the operator sees. (MEASURED: `~/Library/Logs/DiagnosticReports` and `/Library/Logs/DiagnosticReports`, parsed header and body of all 150 `.ips` files.)

**(b) Do crashes and hangs concentrate in high-load windows? Yes for unexplained Claude session deaths and for machine-wide stall; no for kitty.**
- Interactive non-teammate Claude deaths that no pane-close or kill explains (n=36, after removing SIGHUP and SIGTERM): **0.20 per hour at ≥25 sessions vs about 0.02 per hour at <20 sessions** (roughly 10×), and **0.32 per hour at load_1m ≥100 vs 0.02 per hour at <25**. MEASURED, but n is small and the deaths arrive in bursts.
- The machine stalls: the capacity-alarm sampler fires about every 60 s. Its median gap is 69 s at load <25, 124 s at load 25–100 and **261 s at load ≥100**. At load ≥100, **71%** of gaps exceed 3 minutes, against 0.2% at load <25. MEASURED. This is the clearest objective "lag" signal in the data.
- Kitty crashes are **not** load-correlated: 5 of 6 happened at load <15. Their cause is NULL `fonts_data` and a `tick_lock` race, triggered by font-group churn and remote-control or chord calls.

**(c) Resource-exhaustion signatures.** Memory is the only resource that actually ran out (two compressor-segment panics on 09-16, plus near-misses at 73% on 10-01 and 45–51% on 09-23 and 09-29/30). fd, pty and maxproc show **no exhaustion in interactive use**: ptys peaked at 102 of 511, current processes are 1,683 of maxproc 16,000, and open files are 13,339 of 491,520. The one EMFILE (Errno 24) signature is confined to `postland-verify` test runs under launchd's 256 soft `maxfiles`. Claude stderr shows no ENOMEM, EMFILE, EAGAIN or "JavaScript heap" errors.

**(d) Terminal dying vs Claude dying.** The two produce different shapes in `claude-crashes.jsonl`:
- **When the terminal dies**, many interactive sessions die within about 20 s, mostly logged as `RECYCLE/clean-exit` with exit 0, the rest with exit 129 (SIGHUP) or no status, and `concurrent_claude` falls toward 0. Two such events: 09-16 20:13:44 (kitty SIGSEGV, 6 deaths) and **10-01 13:29:44 (kitty pid 610 wedged and was killed, 31 deaths in 22 s)**.
- **When only Claude dies**, it is a singleton or a small group while the other sessions survive. Of the 57 singleton or small-group lead deaths: 13 are SIGHUP from a pane closing, 8 are SIGTERM from an external kill, 2 are SIGKILL (137), 9 are `suspected-oom-large-context` (a guess from transcript size) and 25 are `abrupt-unknown` (no exit status was captured).
- **Kernel panics leave no rows at all**, because the watchdog dies with the box.

So the "hard crash" the operator remembers at high concurrency is, by evidence: the 09-16 panics (memory, not session count), the 10-01 kitty wedge-and-kill, or a burst of unexplained deaths at ≥25 sessions. Claude itself never produced a native crash.

## Coverage and blind spots (read before trusting the counts)

- **DiagnosticReports only goes back to 2026-09-26** in both directories, because the OS has purged older reports. Earlier crash reports (kitty 09-15/16, panics 09-16) are taken from research docs that quoted them at the time. MEASURED: oldest file `cc-jetsam-launch-2026-09-26-201733.ips`. Both `Retired/` directories are empty.
- **Reboots come from `last reboot` (wtmp)**: there are only 3 in the window (09-16 15:50, 09-16 16:28, 09-30 15:26). So there was **no panic between 09-04 and 09-15** and none since 09-16. MEASURED.
- **`claude-crashes.jsonl` CRASH rows are mostly not crashes.** 2,421 of 2,694 CRASH rows in the window are headless `claude -p` (`entrypoint=sdk-cli`) runs, nearly all token-efficiency eval fixtures under `/private/tmp/tokeff-*`. They are logged `abrupt-unknown` because no `cc-close-attrib` wrapper is present (09-24 alone has 1,316). Another 171 are Agent-Teams teammates, killed in groups at teardown (bursts of same-project sessions with near-identical transcript sizes). 102 have no transcript. Only **73 are interactive lead sessions**. MEASURED: tagged with each transcript's `entrypoint` field and its top-level `teamName`/`agentName`.
- **The WindowServer check covers the last hour only** (as the brief bounded it). It found 0 `connectionIsUnresponsive: 1`, 326 "Clearing datagram buffer… connectionIsUnresponsive: 0" (some client is not draining events, but WindowServer is not hung), and 3 coreanimation fence timeouts. The suggested predicate `CONTAINS "hang"` matches only `observedProcessStatesDidChange`, so it is a false-positive filter. MEASURED: `/tmp/concurrency-scale/ws_hang_1h.txt`, `/tmp/concurrency-scale/ws_unresp_1h.txt`.
- `pmset -g log` ran longer than 120 s and returned no "Shutdown Cause" lines in the retained window.

## Ledger: operator-visible and system outcomes, one row per event

| timestamp (CDT) | outcome type | process | cause signature | sessions / load_1m / verdict | source | grade |
|---|---|---|---|---|---|---|
| 09-04 06:25:01, :11 | claude lead death ×2 | claude | exit 129 SIGHUP (pane closed) | 24 / 13 / OK | claude-crashes.jsonl | MEASURED |
| 09-04 14:03:50–14:04:12 | claude lead death ×4 | claude | exit 143 external SIGTERM | 21 / 20 / WARN | claude-crashes.jsonl | MEASURED |
| 09-05 19:30:54 | claude lead death | claude | abrupt-unknown | 24 / 12 / OK | claude-crashes.jsonl | MEASURED |
| 09-05 23:12:53 | claude lead death | claude | abrupt-unknown | 27 / 44 / ALARM | claude-crashes.jsonl | MEASURED |
| 09-06 18:23:29 | claude lead death | claude | exit 143 SIGTERM | 34 / 30 / ALARM | claude-crashes.jsonl | MEASURED |
| 09-07 21:58:04 | claude lead death | claude | exit 137 SIGKILL (oom-or-force) | 20 / 19 / WARN | claude-crashes.jsonl | MEASURED |
| 09-07 23:57:51 | claude lead death | claude | exit 137 SIGKILL | 25 / **224** / ALARM | claude-crashes.jsonl | MEASURED |
| 09-08 17:48:07 | claude lead death | claude | exit 143 SIGTERM | 23 / 52 / ALARM | claude-crashes.jsonl | MEASURED |
| 09-10 05:49:17, 05:50:13 | claude lead death ×2 | claude | abrupt-unknown | 20 / 15 / WARN | claude-crashes.jsonl | MEASURED |
| 09-10 14:54:56 | claude lead death | claude | exit 129 SIGHUP | 20 / 19 / WARN | claude-crashes.jsonl | MEASURED |
| 09-13 20:42:56 | claude lead death | claude | exit 129 SIGHUP | 23 / 55 / ALARM (headroom 6.6 GB, the 30-day minimum at any lead death) | claude-crashes.jsonl | MEASURED |
| 09-15 00:15:22 | kitty crash | kitty (stock /Applications) | SIGSEGV on KittyChildMon: `objc_msgSend` ← `glfwPostEmptyEvent`, a stale NSLock (`tick_lock` race) | load low (night) | docs/research/kitty-childmon-crash-attribution-2026-09-17.md | MEASURED (doc quotes the .ips, now purged) |
| 09-16 13:56:59, 13:57:17 | kitty crash ×2 | kitty (stock) | SIGSEGV pc=0, via `builtin_exec` (watcher/kitten load); unattributed | <15 sessions / <15 load | docs/research/kitty-title-band-crash-population-2026-09-16.md | MEASURED (doc) |
| 09-16 13:58:06, 13:58:14 | kitty crash ×2 | kitty (stock) | SIGSEGV @0x8: NULL `os_window->fonts_data` (`update_pointer_shape`) | same | docs/research/kitty-crash-attribution-2026-09-17.md | MEASURED (doc) |
| 09-16 ~15:50 (report 15:54:00) | **kernel panic** | kernel | watchdog timeout 91 s; compressor **100% of segments (BAD)**, 74 swapfiles; 10× clang-format at 242/274 GB footprint from kitty `./autoformat`; sentinel seg_pct peaked at 93.9% at 15:48 | 16 / – / – | docs/research/kernel-watchdog-panic-2026-09-16.md; ~/.claude/logs/panic-attribution.jsonl; compressor-sentinel.jsonl.20260918T110813Z.gz | MEASURED |
| 09-16 16:28:04 | **kernel panic** | kernel | watchdog timeout 94 s; compressor 67% pages / **100% segments (BAD)**, 65 swapfiles; 37 min after boot; seg_pct 92.6% at 16:25:58 | – | /Library/Logs/DiagnosticReports/.contents.panic | MEASURED |
| 09-16 17:16–20:19 | claude lead death ×4 | claude | abrupt-unknown ×2, suspected-oom ×2 | 5–7 / 8–27 / OK–WARN | claude-crashes.jsonl | MEASURED |
| 09-16 20:13:49 | **kitty crash → terminal mass death** | kitty (stock) | SIGSEGV @0x20 `viewport_for_window`, NULL `fonts_data` (combine chord); 6 interactive sessions die 20:13:44–:59, conc 7→4 | 7 / 17 / WARN | docs/research/kitty-crash-attribution-2026-09-17.md; claude-crashes.jsonl | MEASURED |
| 09-17 00:19–00:34, 09-18 00:42 | claude lead death ×3 | claude | abrupt-unknown, suspected-oom, SIGHUP | 6–7 / 8–12 / OK | claude-crashes.jsonl | MEASURED |
| 09-19 16:10:46 | claude lead death | claude | abrupt-unknown | 14 / 17 / WARN | claude-crashes.jsonl | MEASURED |
| 09-19 17:23–17:30 | claude lead death ×5 | claude | exit 129 SIGHUP (panes closed) | 16–17 / 28–32 / ALARM | claude-crashes.jsonl | MEASURED |
| 09-19 19:16:38 | claude lead death | claude | abrupt-unknown (inside a 9-death teammate teardown burst) | 33 / 76 / ALARM | claude-crashes.jsonl | MEASURED |
| 09-20 18:44:27, :34 | claude lead death ×2 | claude | exit 129 SIGHUP | 12 / 9 / WARN | claude-crashes.jsonl | MEASURED |
| 09-20 22:05:23 | claude lead death | claude | exit 143 SIGTERM | 9 / 28 / ALARM | claude-crashes.jsonl | MEASURED |
| 09-22 23:26:06, 23:46:15 | claude lead death ×2 | claude | abrupt-unknown | 14–17 / **132–152** / ALARM | claude-crashes.jsonl | MEASURED |
| 09-24 ~16:00 | coreaudiod spin onset | coreaudiod | IO-context leak latch on a burst of about 16 afplay/min from the headless harness; ~200% CPU until restart | high (eval waves) | docs/research/coreaudiod-spin-2026-09-29.md | MEASURED (doc) |
| 09-25 10:32:05 | claude lead death | claude | abrupt-unknown | 14 / 47 / ALARM | claude-crashes.jsonl | MEASURED |
| 09-29 00:18:51 | coreaudiod spin onset | coreaudiod | leak latch at load ~75; cpu_resource diag 00:25 (71% CPU over 127 s) | ALARM | coreaudiod-spin-2026-09-29.md; /Library/Logs/DiagnosticReports/coreaudiod_2026-09-29-002730_*.cpu_resource.diag | MEASURED |
| 09-29 06:51:25 | jetsam event (test) + **kernel-memory near-miss** | `hog` ×5 (test fixture) | per-process-limit kills of a test hog. The same snapshot shows **data.kalloc.1024 = 14.2 GB** (zone map 16.0 of 24.9 GB cap), coreaudiod 37 GB resident, 1,051 procs, 17 claude.exe | – | /Library/Logs/DiagnosticReports/JetsamEvent-2026-09-29-065125.ips | MEASURED |
| 09-29 16:19:30 | claude lead death | claude | abrupt-unknown | 24 / **103** / ALARM | claude-crashes.jsonl | MEASURED |
| 09-30 15:25:44 | shutdown stall → reboot 15:26 | system | shutdownStall spindump during the operator's restart (clears coreaudiod leak and kalloc) | – | /Library/Logs/DiagnosticReports/shutdown_stall_2026-09-30-152544_*.shutdownStall; `last reboot` | MEASURED |
| 09-30 18:10:22 ×2, 19:51, 22:23 ×2 | claude lead death ×5 | claude | abrupt-unknown | 31 / **181** / ALARM (19:51 and 22:23 have no sample within 10 min: sampler starved) | claude-crashes.jsonl | MEASURED |
| 09-30 21:26:41 | claude lead death | claude | exit 143 SIGTERM | 31 / 71 / ALARM | claude-crashes.jsonl | MEASURED |
| 10-01 12:39:45 (onset 09-30 15:29) | **kitty wedge (hang)** | kitty pid 610 | child-monitor stops reaping (59 zombies with ppid 610); talk thread stops calling accept(); 32 Claude panes | high | docs/research/kitty-quit-research-2026-10-01.md | MEASURED (doc) |
| 10-01 13:29:44–13:30:06 | **terminal mass death** | kitty 610 killed → SIGHUP to all panes | 31 interactive deaths in 22 s (17 exit 0, 13 no status, 1 exit 129); conc 2→0 | ~32 before | claude-crashes.jsonl | MEASURED |
| 10-01 16:50:11 | claude lead death | claude | abrupt-unknown | **38 / 260** / ALARM | claude-crashes.jsonl | MEASURED |
| 10-01 19:35:18–19:38:16 | claude lead death ×3 | claude | abrupt-unknown | 33–35 / 29–34 / ALARM | claude-crashes.jsonl | MEASURED |
| 10-01 20:15–22:18 | claude lead death ×4 | claude | suspected-oom ×3, abrupt-unknown ×1 | 24–27 / 39–**264** / ALARM | claude-crashes.jsonl | MEASURED |
| 10-01 22:32–23:36 | **compressor near-miss (73% of segments)** | python3.12 (36.9 GB) + Blender (20.5 GB) | not Claude; seg_pct passed the 70% alarm; swap 30 GB | 21 / 25–49 / ALARM | compressor-sentinel.jsonl; capacity-alarm.jsonl | MEASURED |
| 10-02 00:18:16, :42 | browser renderer crash ×2 | Dia Browser Helper (Renderer) | EXC_BREAKPOINT SIGTRAP | night | ~/Library/Logs/DiagnosticReports/Browser Helper (Renderer)-2026-10-02-*.ips | MEASURED |
| 10-02 01:19:01 / 01:23:00 | jetsam event (test) / claude jetsam-oom | hog (test) / 1 teammate | per-process-limit; 878 procs, 28 claude.exe, largest = kitty | 19 / – | JetsamEvent-2026-10-02-011901.ips; claude-crashes.jsonl | MEASURED |
| 10-02 12:32:16–12:32:36 | claude lead death ×6 | claude | 3 suspected-oom, 2 abrupt-unknown, 1 SIGHUP; a pane-close sweep ran at 12:31:03 | 27 / 33 / ALARM | claude-crashes.jsonl; ~/.claude/logs/pane-close.jsonl | MEASURED / INFERRED (sweep caused it) |
| 09-28 → 10-03 (17 events) | git segfault | `/opt/homebrew/*/git`, parent launchd | SIGSEGV in `CFNotificationCenterAddObserver`; asi: "multi-threaded process forked… crashed on child side of fork pre-exec". Probably fsmonitor--daemon | 10–30 / spread | ~/Library/Logs/DiagnosticReports/git-2026-*.ips | MEASURED (signature) / INFERRED (fsmonitor) |
| 09-26 → 10-03 (131 events) | test/dev crashes | bash ×31 (self-kill SIGSEGV, parent agentsync-launcher or exited), cc-jetsam-launch ×22 (DYLD: bats fixture dylib "not valid mach-o"), walkfp ×12, fswatch ×13, gtimeout ×8, python3.12 ×12 (BLAS EXC_ARM_DA_ALIGN), codesign launch-constraint ×6, simulator ×16, swift-frontend ×2, node ×2 (resvg abort) | test fixtures and probes, not operator-facing | 14:00–19:00 clusters | ~/Library/Logs/DiagnosticReports/*.ips | MEASURED |

Not outcomes but recorded: 46 disk-write and CPU resource `.diag` notices ("Action taken: none"). The largest are kitty-coalition `git` with 137 GB dirtied over 3.75 h (10-01 15:34), kitty-coalition `rm`/`cp` 34 GB, and Dia Browser Helper 34 GB (`/Library/Logs/DiagnosticReports/*.diag`).

## Frequency by type (30 days)

| outcome type | count | per day | notes |
|---|---|---|---|
| headless `claude -p` "CRASH" | 2,421 | 81 | eval runs ending without a wrapper; **not real crashes** |
| teammate deaths (CRASH) | 171 | 5.7 | mostly group teardown |
| test/dev-tool crashes (.ips) | 131 | (9 days retained) | fixtures |
| no-transcript CRASH | 102 | 3.4 | unattributable |
| **interactive lead-session deaths** | **73** | **2.4** | 57 singleton or small-group + 16 in terminal mass deaths |
| of which unexplained (not SIGHUP/SIGTERM) | 36 | 1.2 | the population that correlates with load |
| git daemon segfault | 17 | ~2/day since 09-28 | |
| kitty native crash | 6 | – | all 09-15/16; 0 in the 18 days since |
| terminal mass-death events | 2 | – | 09-16 20:13 (crash), 10-01 13:29 (wedge then kill) |
| kitty wedge | 1 | – | 10-01 |
| kernel panic | 2 | – | both 09-16 |
| coreaudiod spin latch | 2 | – | 09-24, 09-29 |
| compressor ≥70% near-miss | 1 | – | 10-01 22:32 (non-Claude) |
| shutdown stall | 1 | – | 09-30 |
| jetsam events | 2 (+1 claude jetsam-oom) | – | test hog kills |
| WindowServer hang/spin | 0 | – | no reports; 1 h log clean |
| claude.exe native crash | 0 | – | |

## Frequency by hour (CDT)

| hour | 00 | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 | 09 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| lead deaths (73) | 3 | 0 | 0 | 0 | 0 | 2 | 2 | 0 | 0 | 0 | 1 | 0 | 6 | 14 | 5 | 0 | 3 | 7 | 6 | 7 | 7 | 2 | 4 | 4 |
| teammate deaths (171) | 30 | 3 | 10 | 5 | 0 | 5 | 7 | 2 | 3 | 0 | 2 | 10 | 5 | 2 | 10 | 6 | 7 | 10 | 8 | 11 | 7 | 7 | 10 | 11 |
| git segv (17) | 1 | 2 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 6 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 1 | 2 | 0 | 1 | 1 |
| test/dev crashes | 1 | 4 | 1 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 1 | 21 | 18 | 4 | 4 | 9 | 7 | 3 | 2 | 9 | 1 |

The 13:00 lead spike is almost entirely the 10-01 13:29 kitty kill. Lead deaths otherwise sit from 12:00 to 23:00, which is the operator's fleet hours. INFERRED: these hour counts follow when the fleet is busy, so they say little about time of day on their own.

## Clustering with load (time-weighted exposure; event rate per hour of exposure)

Exposure is 657 h of sampled time, each sample capped at 300 s. The verdict split is OK 203 h, WARN 222 h, **ALARM 232 h (35% of all time)**.

| sessions | exposure h | lead deaths, unexplained (36) | teammate deaths (171) | kitty crashes | git segv |
|---|---|---|---|---|---|
| <10 | 138 | 6 (0.043/h) | 11 (0.08/h) | 1 | 0 |
| 10–14 | 181 | 3 (0.017/h) | 32 (0.18/h) | 1 | 2 |
| 15–19 | 144 | 1 (0.007/h) | 54 (0.37/h) | 4 | 10 |
| 20–24 | 112 | 7 (0.062/h) | 31 (0.28/h) | 0 | 1 |
| **25–29** | 39 | **9 (0.231/h)** | 22 (0.57/h) | 0 | 2 |
| **30+** | 43 | **7 (0.163/h)** | 17 (0.39/h) | 0 | 1 |

| load_1m (10 cores) | exposure h | lead unexplained | teammate | sampler median gap |
|---|---|---|---|---|
| <15 | 299 | 5 (0.017/h) | 41 (0.14/h) | 69 s (all <25) |
| 15–25 | 177 | 5 (0.028/h) | 41 (0.23/h) | |
| 25–50 | 104 | 12 (0.115/h) | 39 (0.38/h) | 124 s (25–100) |
| 50–100 | 48 | 2 (0.042/h) | 20 (0.41/h) | |
| **100+** | 28 | **9 (0.321/h)** | 26 (0.91/h) | **261 s; 71% of gaps >3 min** |

Which outcome types cluster with high load:
- **They cluster:** unexplained lead deaths (about 10× above 25 sessions or above load 100), teammate deaths (about 6× at load ≥100), sampler starvation (the lag), coreaudiod leak latching (both onsets in bursts under load), and test-crash bursts (all in ALARM, because tests are part of the load). MEASURED rates. The causal direction is INFERRED and could run either way, because deaths come in bursts: only 9 of the ≥100-load deaths fall across about 5 distinct episodes.
- **They do not cluster:** kitty crashes (5 of 6 at load <15), the git fsmonitor segfault (spread across 10–30 sessions), and Dia renderer crashes. The kernel panics were memory-driven: compressor segments at 100% from 242–274 GB of clang-format footprint, at 16 sessions. That is unrelated to session count.
- **Spurious:** headless "deaths" show 26/h at load ≥100 vs 0.35/h at <15. That is reverse causation: eval waves produce both the load and the unwrapped exits. Do not use this series as an outcome.
- Memory headroom at lead deaths had a median of **29.7 GB** and a minimum of 6.6 GB. INFERRED: the 15–30-session deaths are **not memory exhaustion** in the RAM sense. The pattern points to CPU/scheduler starvation (load 100–260 on 10 cores) or kills by fleet tooling, not jetsam.

## Resource-exhaustion check (c)

| limit | observed peak | cap | verdict | source |
|---|---|---|---|---|
| ptys | 102 (09-11) | kern.tty.ptmx_max 511 | not exhausted | capacity-alarm `ptys_used` |
| processes | 1,683 now; 1,051 in the 09-29 jetsam snapshot | kern.maxproc 16,000 / per uid 10,666 | not exhausted | `ps -A`, sysctl, JetsamEvent |
| open files | 13,339 system-wide now | kern.maxfiles 491,520 | not exhausted | sysctl kern.num_files |
| per-process fds | Errno 24 in 5 of 14 postland test windows | launchd soft maxfiles **256** (sessions have 1,048,576) | test runner only | docs/research/postland-fd-exhaustion-2026-09-23.md |
| compressor segments | **100%** at both panics; 73% on 10-01; 45–51% on 09-23 and 09-29/30 | 70% alarm | **exhausted twice** | panic report; compressor-sentinel.jsonl |
| kernel zone data.kalloc.1024 | 14.2 GB (09-29) | zone map 24.9 GB | ratchet; cleared by the 09-30 reboot | JetsamEvent-2026-09-29; docs/research/kalloc-ratchet-2026-10.md |
| ENOMEM / EAGAIN / "fork: retry" / "JavaScript heap" | 0 hits in 160 Claude stderr logs since 09-04 and in close-records | – | absent | ~/.claude/logs/stderr/, close-records/ |
| other stderr | "SessionEnd hook … database is locked" (sqlite contention at session end) | – | minor | stderr/20261001T141747-20102.log |

## Adversarial pass: gaps found and how they were handled

1. *Is "abrupt-unknown" really crashes?* No. I checked by joining each death to its transcript entrypoint and team fields, which removed about 2,600 false rows. The residue still contains 25 lead deaths with no exit status. Some are probably pane closes by operator or tooling that the wrapper never saw.
2. *Did the panics show up in the death ledger?* No, they produced 0 rows, so any ledger built only from `claude-crashes.jsonl` misses the worst outcomes. They were added from wtmp and the panic files.
3. *Kitty 13:56–13:58 cluster (4 crashes):* 0 Claude deaths at that time. That kitty instance held no fleet panes; possibly a separate watcher-loaded window. INFERRED.
4. *Missing data at high load:* 281 of 2,932 events (9.6%) have no capacity sample within 10 min. That is 264 headless events plus 17 of the 511 others (3.3%), including 3 lead deaths during starved windows on 09-30. Starved windows are also under-sampled, so exposure there is undercounted, which pushes the high-load rates up. The two effects pull in opposite directions; treat the ~10× as order-of-magnitude.
5. Not checked: `log show` beyond 1 h (bounded by the brief), hangs inside Claude's own UI (not observable from files), and kitty crashes between 09-17 and 09-25, which rest only on the 09-30 doc saying kitty pid 73832 ran from 09-16 20:13 until the 09-30 reboot without crashing.
