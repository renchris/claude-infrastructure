# q2c — live census: claude memory vs transcript size, and distance to memory pressure

Sampled 2026-10-06 01:28-01:33 local (06:28-06:33Z), read-only (ps, top -l 1, lsof, vm_stat, sysctl, memory_pressure, file reads). No pane, session or repo file other than this one was touched. Tags: MEASURED = I ran it; READ = source or record; INFERRED = derived.

## Verdict

Memory is not the binding constraint right now, and a rotation does not add a process. The machine reads kernel pressure level 1 (normal), compressor segments 4.08% against the move worker's 90% ceiling, swap I/O at zero. What is saturated is CPU: load average 33-64 on 10 cores.

## 1. Census: every claude process, RSS, transcript size

Command: `ps -axo pid=,ppid=,rss=,etime=,tty=,comm=` joined on `~/.claude*/sessions/<pid>.json` (pid to sessionId) and `~/.claude*/projects/*/<sid>.jsonl` (most recently modified copy); footprint from `top -l 1 -stats pid,mem,cmprs`. MEASURED.

`lsof -p 30666` shows no open .jsonl (32 fds, none a transcript): claude appends and closes, so the registry file is the only pid-to-transcript link. MEASURED.

| pid | RSS MiB | footprint MiB (top MEM) | compressed MiB | etime | tty | config dir | status | sid | transcript bytes |
|---|---|---|---|---|---|---|---|---|---|
| 70323 | 857 | 221 | 0 | 17:45 | ttys020 | .claude | busy | e6c3f109 | 932,011 |
| 58517 | 843 | 283 | 0 | 08:47 | ttys022 | .claude-quaternary | busy | 4e9949e0 | 40,395,917 |
| 32870 | 802 | 233 | 0 | 32:32 | ttys001 | .claude-secondary | busy | 335ff504 | 1,098,142 |
| 59566 | 799 | 240 | 0 | 25:28 | ttys011 | .claude-quaternary | busy | e131c8d2 | 2,412,392 |
| 18222 | 684 | 217 | 0 | 03:49 | ttys024 | .claude-secondary | busy (this worker) | d455e2a7 | 932,848 |
| 20981 | 683 | 194 | 0 | 27:15 | ttys008 | .claude-secondary | shell | 680eb505 | 1,586,929 |
| 9874 | 681 | 202 | 0 | 20:17 | ttys015 | .claude-secondary | shell | 4ad354fc | 3,392,639 |
| 30666 | 678 | 203 | 0 | 25:50 | ttys009 | .claude-secondary | idle | 7913752f | 4,345,806 |
| 20588 | 501 | 189 | 0 | 20:04 | ttys017 | .claude-secondary | idle | 4d059264 | 1,284,778 |
| 62442 | 495 | 172 | 0 | 17:55 | ttys019 | .claude-secondary | idle | 404651b1 | 1,645,637 |
| 53051 | 479 | 171 | 0 | 21:17 | ttys005 | .claude-secondary | idle | 1c0f7f90 | 2,310,965 |
| 52600 | 473 | 185 | 0 | 21:18 | ttys003 | .claude-secondary | idle | 7f5deb68 | 2,027,991 |
| 62399 | 471 | 169 | 0 | 17:55 | ttys018 | .claude-secondary | idle | deaa242a | 1,701,791 |
| 59930 | 463 | 166 | 0 | 21:08 | ttys007 | .claude-secondary | idle | 893204d3 | 500,920 |
| 59938 | 435 | 174 | 0 | 21:08 | ttys013 | .claude-secondary | idle | 840ca76c | 3,617,498 |
| 10156 | 344 | 312 | 52 | 4d 11:13 | ttys068 | .claude | bg idle | 9aa483e9 | 9,675,584 |
| 98756 | 277 | 120 | 0 | 11:25 | none | .claude-quaternary | idle, v2.1.278, child of a research-kit python job | e79bf8b9 | none found |
| 98937 | 270 | 115 | 0 | 11:25 | none | .claude-quaternary | same | 3cac8644 | none found |
| 98757 | 268 | 119 | 0 | 11:25 | none | .claude-quaternary | same | 9ecaf71e | none found |
| 98960 | 266 | 112 | 0 | 11:25 | none | .claude-quaternary | same | fb0a0050 | none found |
| 8751 | 70 | 57 | 8 | 4d 01:57 | none | none | bg-spare | none | none |
| 10027 | 55 | 37 | 5 | 4d 11:13 | none | none | bg-pty-host | none | none |
| 8514 | 52 | 36 | 5 | 4d 01:57 | none | none | bg-pty-host | none | none |

Plus pid 9780 (`claude.exe daemon run`, RSS 150 MiB).

Aggregates (MEASURED, python3 over the table):

| population | n | RSS median | RSS mean | RSS sum | footprint median | footprint sum |
|---|---|---|---|---|---|---|
| interactive tty sessions | 15 | 678 MiB | 623 MiB | 9,343 MiB | 194 MiB | 3,019 MiB |
| busy | 5 | 802 MiB (684-857) | | | | |
| shell | 2 | 682 MiB (681-683) | | | | |
| idle | 8 | 476 MiB (435-678) | | | | |
| all claude-binary processes | 24 | | | 10.22 GiB = 16.0% of 64 GiB | | |

Sum of RSS over every process on the box: 45.0-48.1 GiB (two samples; RSS double-counts shared pages).

### Correlation, memory vs transcript bytes (MEASURED, python3)

| pair | n | Pearson | Spearman |
|---|---|---|---|
| RSS vs transcript, tty sessions | 15 | 0.381 | -0.075 |
| RSS vs transcript, tty + bg | 16 | 0.287 | -0.197 |
| RSS vs transcript, tty minus the 40 MB outlier | 14 | -0.072 | -0.266 |
| RSS vs transcript, idle only | 8 | 0.568 | 0.119 |
| footprint vs transcript, tty | 15 | 0.681 | 0.189 |
| footprint vs transcript, tty minus the 40 MB outlier | 14 | -0.044 | 0.002 |

- No rank relation between transcript size and process memory (Spearman within +/-0.27 everywhere). Every positive Pearson rests on one point: the 40.4 MB transcript. INFERRED from the table.
- That one point bounds the slope: a transcript 17-43x larger than its busy peers (40.4 MB vs 0.9-2.4 MB) carries 283 MiB footprint against 217-240 MiB, about +45-65 MiB, and an RSS inside the busy range (843 vs 684-857 MiB). INFERRED, n=1.
- Turn state explains RSS better than transcript size: busy median 802 MiB vs idle median 476 MiB. MEASURED.
- RSS is about 3.2x footprint (678 vs 194 MiB median). The difference is shared and file-backed mapping. The private cost of one more session is nearer the footprint. INFERRED (top MEM taken as phys_footprint).

Limit of this sample: all 15 tty sessions are 3-33 minutes old, because the fleet was rotated within the last half hour (7 of them by batch 20261006T060534Z). Growth of memory with uptime is not observable here. The one long-lived process (bg, 4.5 days) holds 344 MiB RSS, 312 MiB footprint, 52 MiB compressed.

## 2. Machine state

| reading | value | command | tag |
|---|---|---|---|
| physical RAM | 68,719,476,736 B (64 GiB), page 16,384 B | `sysctl hw.memsize hw.pagesize` | MEASURED |
| kernel pressure level | 1 (normal), 7 of 7 samples | `sysctl kern.memorystatus_vm_pressure_level` | MEASURED |
| memory_pressure free percentage | 78% then 69% (2 samples, 3 min apart) | `memory_pressure` | MEASURED |
| swap | total 3072.00M, used 2181.75M, free 890.25M; unchanged over 6 samples in 48 s | `sysctl vm.swapusage` | MEASURED |
| swap I/O rate | 0 swapins, 0 swapouts in the top interval; lifetime 27,725,510 / 42,268,668 | `top -l 1 -n 0` | MEASURED |
| compressor | occupies 1.93 GiB, stores 9.80 GiB (ratio 5.08:1) | `vm_stat` | MEASURED |
| compressor segments | 66,499-66,559 of 1,629,609 = 4.08% | vm_stat + `sysctl vm.compressor_segment_limit vm.compressor_segment_buffer_size` (65,536), formula of capacity-admit.sh:308-312 | MEASURED |
| reclaimable (free+speculative+inactive+purgeable) | 32.0 GiB at 01:28, then 21.7-25.4 GiB over 6 samples at 01:31-01:32 | `vm_stat`, formula of capacity-admit.sh:212-225 | MEASURED |
| free pages alone | 10.0 GiB at 01:28, 0.20-1.39 GiB at 01:31-01:32 | `vm_stat` | MEASURED |
| wired | 11.0-17.4 GiB, oscillating inside 48 s | `vm_stat` | MEASURED |
| anonymous | 33.2-40.2 GiB | `vm_stat` | MEASURED |
| PhysMem | 62G used (17G wired, 2652M compressor), 153M unused | `top -l 1 -n 0` | MEASURED |
| load average | 40.65 / 36.69 / 34.80 / 32.75 / 36.64 / 39.48, then 64.50 (1-min), on 10 CPUs | `sysctl vm.loadavg`, `top` | MEASURED |
| processes | 1085 total, 101 running | `top -l 1 -n 0` | MEASURED |

- Reclaimable fell about 10 GiB between 01:28 and 01:31 while free fell from 10 GiB to under 1.4 GiB. Swap, compressor occupancy and pressure level did not move. A bats suite and a research-kit python job were running. Cause not isolated.
- The claude fleet is 16% of RAM by RSS and about 5% by footprint (3.0 GiB of 64). Most of the 62 GiB "used" is not claude.

## 3. How many more median sessions fit before the move worker's gate trips

Thresholds (READ):
- `lr_capacity_probe_corrected` (scripts/limit-recover/lr-lib.sh:410-440) calls `cc_capacity_probe` with `CC_ADMIT_LOAD_TERM` default off and `CC_ADMIT_MAX_SEGMENT_PCT="${CC_ADMIT_MAX_SEGMENT_PCT:-${LR_SEGMENT_PCT:-90}}"` (lr-lib.sh:435-437). The segment ceiling is 90% for every limit-recover caller; the stock ceiling is 50% (capacity-admit.sh:1375).
- The move worker additionally sets `CC_ADMIT_ACTIVE_TERM=off CC_ADMIT_LOAD_TERM=off CC_ADMIT_RESERVE_TERM=off` (lr-move-worker.sh:132). Two terms remain: segments > 90% refuses (capacity-admit.sh:326-328), reclaimable < 4 GB refuses (`CC_HW_DEFAULT_MIN_HEADROOM_GB=4`, capacity-admit.sh:163, verdict 323-325).
- Segments = pages occupied by compressor / 4 + swap used bytes / 65,536, over `vm.compressor_segment_limit` (capacity-admit.sh:240-243, 308-312).

Room (INFERRED from the measurements above):

| term | now | trips at | room | median sessions that fit |
|---|---|---|---|---|
| segments | 66,499 (4.08%) | 1,466,648 (90%) | 1,400,149 segments = 85.5 GiB of compressed bytes | 129 if each session's full 678 MiB RSS were compressed at 1:1; 451 at footprint 194 MiB and 1:1; about 2,290 at footprint and the measured 5.08:1 |
| reclaimable headroom | 21.7-25.4 GiB (low sample 21.7) | 4 GB | 17.7 GiB | 26 at RSS 678 MiB each; 91 at footprint 194 MiB each |

- The segment ceiling cannot be reached by adding sessions: 85.5 GiB of compressed data exceeds physical RAM. The headroom floor is reached first, at an estimated 26-91 additional sessions, on top of the 15 running.
- The headroom term is optimistic by its own source's account: it counts dirty anonymous inactive pages as free and "fired 0 times in 127 refusals" (capacity-admit.sh:231-236).
- A rotation adds zero sessions (section 4), so these counts are slack for new spawns, not a budget rotation consumes.

Record check (READ): in batch /Users/chrisren/.reso/limit-recover/move/20261006T060534Z-next3-next2-64630 all 7 `<sid>.capacity.log` files contain no refusal text, and all 7 verdicts are MOVED. The four ledgers in ~/.claude/autonomy/capacity-fire (active, headroom, load, segments `.refusals`) are 0 bytes, mtime 01:26.

## 4. Does a rotation add a process or replace one

Replace. The old claude exits before the new one starts. Transient double-residency is zero claude processes; the pane is empty for at least about 3 seconds.

Ordering (READ):
1. Worker takes a slot and runs the kernel-safety read "while the session is still alive in its pane" (lr-move-worker.sh:119-135).
2. Worker runs lr-handoff with `--in-place --no-prompt --no-replace` and `LR_ADMIT_MODE=swap` (lr-move-worker.sh:143-152). lr-handoff skips the probe and token: "one claude out, one in" (lr-handoff.sh:32-33, 320-326, 1443).
3. The recycle types `/exit`; a detached watcher "waits for the typed /exit to land (claude process gone from the tty), then types the relaunch command into the plain shell" (scripts/handoff-fire.sh:9384-9385).
4. The watcher polls at 1 s until `at_shell` is affirmative, bound 600 s (handoff-fire.sh:9475, 9607-9612), then `sleep 2` for the prompt to settle, then types the launcher. It refuses to type while claude is still up.
5. lr-lib.sh:400-403 states the same as a design premise: "the old process exits — releasing its compressed pages — before its replacement starts".

Recorded run (READ, batch above, sid 1c0f7f90): watcher armed 06:08:41Z; handoff.log line 32 "relaunches bash once claude exits"; verdict "pane 3 runs the session on the target, one copy". The successor is pid 53051, 479 MiB RSS 21 minutes later.

What exists transiently beside the session: the worker, lr-handoff, the watcher (bash, 2-7 MiB RSS each by the sizes of sibling bash processes in the ps listing), and a transplanted transcript copy on disk. With lane width 4, up to 4 panes are empty at once, so fleet memory dips during a batch by up to 4 sessions' worth.

Exception (READ): the `/exit` menu's "Move to background and exit" hands the conversation to a background worker under a new session id; one such copy ran about 4 minutes beside its successor (handoff-fire.sh:9481-9489). The move lane sets `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` (lr-move-worker.sh:147), which removes that option (lr-fire-resume.sh:1107). Paths that do not set it can hold two processes for one session.

## 5. Where the batch's time went (READ, 7 events.jsonl files)

| sessions | slot wait | actuate | actuated to first proof | total |
|---|---|---|---|---|
| 4 (1c0f7f90, 7f5deb68, 840ca76c, 893204d3) | 0-1 s | 105-110 s | 57-61 s | 176 s |
| 3 (404651b1, 4d059264, deaa242a) | 167 s | 16-17 s | 95-191 s | 287-385 s |

Slot width was 4 (`slot-wait` detail "width 4"). The second wave's 167 s is a wait for one of 4 slots. No stage records a memory refusal or a memory wait.

## Alternatives considered

- RSS as the per-session cost: overstates by about 3.2x against footprint; both are reported, and the conservative fit count uses RSS.
- lsof for the transcript link: fails, the transcript is not held open; the registry file was used.
- vmmap or footprint(1) for exact private memory: not run, vmmap suspends its target.
- Running lr-*.sh or cc-lr in dry-run for a live probe verdict: not run; the gate's arithmetic was reproduced from source with the same sysctls.

## Uncertainties

- All tty sessions are under 33 minutes old; memory growth over hours and after many turns is unmeasured.
- The transcript slope rests on one 40 MB session.
- The 4 no-tty v2.1.278 sessions have no transcript file under any config dir's projects tree; they are excluded from the correlation.
- top MEM is taken to be phys_footprint.
- The 10 GiB swing in reclaimable within 3 minutes is unexplained; the headroom-based fit count (26-91) moves with it (42-125 at the 32.0 GiB sample).
- Load average 33-64 may include many short-lived hook and test processes; whether CPU load slows a rotation's stages was not measured here.
