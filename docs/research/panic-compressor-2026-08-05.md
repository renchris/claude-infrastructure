# The 2026-08-05 00:18 panic — the allocator finally has a face: a 670-process node spawn storm into a cold swapper

**Question (operator).** Third machine-killing crash in six days under "light" usage (5 Claude Code
sessions, kitty). Find the true root cause the previous investigations missed, and fix it so the box
stops lagging, freezing, and crashing.

**Answer, one line.** The box was killed by **compressor-segment exhaustion via thrash**: a
**~670-process node spawn storm** (kitty coalition 147 → 817 procs in ≤12 min) — ignited by a
backgrounded `pnpm design:gate` whose own `next dev` cold-compile is a documented 3-4-minute
multi-GB burst — drove the VM compressor to **491 MiB/s of compression with 0.68% useful work**
(22.6M compressions + 13.6M decompressions in 720 s netting +246,884 pages), which stranded
partially-filled segments until the **segment table hit 100% at 31% packing**; the swapper started
**cold** (2 GiB store, zero swapouts in 21 h) and lost the race creating 68 swapfiles mid-storm;
pageout stalled, jetsam itself starved (94 s), launchd's exec path wedged, watchdogd missed 94 s of
checkins, and the ARM watchdog pulled the plug. **Not OOM** — 20 GB was free at escalation and the
kernel's pressure flag was still `false` at death.

Produced by a 9-agent forensics wave (A1 unified log · A2 systemstats+microstackshots · A3 panic
stackshot · A4 sensor postmortem · A5 fleet-job census · A6 per-session bash forensics · A7 wreckage
· A8 xnu mechanics · A9 hostile review) + lead-side config reads. Machine: MacBookPro18,2 · M1 Max ·
64 GiB · macOS 15.6.1 (xnu-11417.140.69). All times PDT (UTC-7) unless suffixed Z.

---

## 1. The crash census — four panics, one recurring class

The boot chain is gapless (each panic's decoded `Calendar` + ~30-48 s = the next file's `Boot`):

| Panic (decoded) | Uptime | Class | Compressor line | Swapfiles | Panicked task |
|---|---|---|---|---|---|
| Jul 30 02:18:05 | 55.3 h | **segment exhaustion** | 33% pages / **100% segments** | 67 | kernel_task, 731 thr |
| Jul 31 11:45:38 | 33.5 h | threadprice spinlock (self-inflicted control) | 0% / 7% | 0 | threadprice, 8,368 thr |
| Jul 31 18:13:12 | 6.5 h | **segment exhaustion** | 31% / **100%** | 66 | kernel_task, 726 thr |
| **Aug 5 00:18:22** | 102.1 h | **segment exhaustion** | 31% / **100%** | 68 | kernel_task, 739 thr — panicked thread IS `VM_compressor` (tid 2332, 631 s CPU) |

Three structural facts settled this session:

- **A `.panic` filename and its `date` field are the WRITE time, not the panic time.** The
  "Jul 30 08:30" file is the 02:18 panic — proven three ways, decisively by the watchdogd checkin
  counter (19,871 × 10.0 s = 55.2 h = the decoded uptime; an 08:30 panic would need 22,127). The box
  sat at a locked FileVault screen until 08:30. There was exactly one Jul-30 panic.
- **Only `panic-full-*` files carry a stackshot** (tonight's: 1,318 procs / 9,338 threads decoded);
  `panic-base+socd-*` files carry `err 52`, 240 bytes. Tonight's full stackshot is why the allocator
  is now named.
- **Uptime is exonerated** (6.5 h → 102 h spread). It was already known this is a RATE failure;
  tonight adds the missing noun: the thing whose rate matters is *segment* consumption, and the fuel
  is *never-exiting near-zero-CPU processes*.

## 2. The measured timeline (merged from all instruments)

| Time (PDT) | Event | Source |
|---|---|---|
| Aug 2 19:59-20:08 | *(prior boot event, context)* one `claude.exe` grows 24→40 GB in 7 min; swap engages EARLY (18 GiB store, MPL=2 warn); coalition peaks **170.85 GiB / 515 procs — and the box survives**. The swap it left behind (407 MB used) latches the capacity-alarm's rung-1 into a **59-hour always-ALARM** | A4, A2-F15/16 |
| 23:00-23:01 (Aug 4) | TCC storm onset: kitty-attributed camera/mic auth checks jump 2/min → **1,744/min** (~870×) — headless-Chrome automation (fare-scraping + capture loop); trustd+tccd reach 63% of all userspace log volume | A1-F7 |
| 00:06:21 | **MemoryPressureLevels sampler dies** — its file-mates keep writing 10 more minutes; unique gap in 102 h. Earliest casualty | A2-F6 |
| 00:06:22 | Last systemstats sample: kitty coalition **147 procs / 40.5 GiB**; free 6.9 GiB; swapouts frozen for 21 h (cold swapper) | A2 |
| 00:07:11 | chrome-headless-shell pid 86343 starts a ~0.5 Hz "Capturing" power-assertion cycle | A1 |
| 00:10:00-05 | 14,514 `ASP: Unable to apply provenance sandbox` for fnm node in ~6 s — mass node-exec flurry | A1 |
| 00:10:52 / 00:11:05 | day-first-session jobs fire (backup-cleanup, plan-history-prune) — trivial, complete | A5-F6 |
| **00:11:17** | Session `2b3223b7` launches **`pnpm design:gate` `run_in_background:true`** (logged `Exit: 0` at 00:11:22 — false success, see §5). Gate = `playwright test --project=visual-regression --workers=1` + its own `webServer: pnpm dev` | A6-F4 |
| 00:11:31-00:12:22 | The session's 5 teammates (bi-*) shut down and are reaped | A6 |
| 00:12:55 | Gate's globalSetup done (DB seeded) → **`next dev` boot + cold compile begins** — in-repo comment: *"Cold dev-compile is ~3-4min"* on this app | A6, playwright.config.ts:35-50 |
| **00:13:15** | **Onset**: microstackshot sample rate bursts 4×, **82% node** | A2-F9 |
| 00:13:01 → starved | capacity-alarm's last row (seg 15.2%, "quiet"); its next run **hangs inside `zprint`** (still TH_WAIT at PRI-4 at the panic) — the background QoS band starves first | A4-F2, A5-F1 |
| 00:13:58 | First kernel pressure response: `memorystatus: killing_idle_process` (idle-exit band, 1 Hz metronome, 106 kills, none effective) | A1-F1 |
| 00:06→00:18 (720 s) | **kitty coalition 147 → 817 procs (+670, ~1/s)**; compressions **+22.6M (491 MiB/s)**, decompressions +13.6M, net retained **+246,884 pages (0.68% useful work)**; file cache **15.5 GiB → 3.8 MiB**; purgeable → 0; wired +6.4 GiB; swap store 2 GiB/~2 files → **68 files, created cold mid-storm** | A2 |
| 00:16:15 | `memorystatus: System is unhealthy` + `{"compressor_exhausted": 1}` (~20 GB still free); first `vm-compressor-space-shortage` kills; **launchd↔jetsam livelock** (2,358 spawns vs 2,252 kills in 21 s, peak 221/s, 86.5% victims lived <500 ms); jetsam eats the exec path (amfid 133×, sandboxd 119×) while skipping Chrome renderers 12,782× ("not idle-exitable") and never touching a single node | A1-F3/4/5/6 |
| 00:15:24-00:16:16 | System-wide idle-XPC reap (119 coalition exits — structurally unique in 102 h) → relaunch storm → 154 `xpcproxy` stubs alive at death, unable to get pages | A2-F10/11 |
| 00:16:36.795 | **Last persisted log line of the boot** (logd starved 12 s before watchdogd's last checkin) | A1-F9 |
| 00:16:48 | watchdogd's last checkin. At death: watchdogd pri-97, turnstile-boosted 3 hops onto a launchd thread blocked in an apfs/decmpfs page-in that needed a free page that did not exist; `VM_memorystatus_1` (jetsam) itself unrun for 94.1 s; kernel `memoryPressure = false`; free = 906 pages (14.8 MiB); 90.3% of thread backtraces truncated because userspace was paged out | A3-F4/5/11 |
| **00:18:22** | `panic: watchdog timeout: no checkins from watchdogd in 94 seconds` | A3 |

## 3. The allocator

**At death: 724 `node` processes held 141.94 GiB nominal RSS = 92.5% of all resident memory, all in
the kitty coalition (817 procs / 146.72 GiB), which had been 147 procs twelve minutes earlier**
(A2-F1/F2; count is wrap-immune). Within them, a leaked cohort with an identical fingerprint
(A3-F6): **665 processes × 8 threads × ~179 MiB median × ~1.4 s lifetime CPU × 3 pageIns**,
burst-spawned (median pid gap 5), same signed binary, never exited — ≈116 GiB of anonymous memory
dirtied once and never referenced again: the ideal generator of sparse compressor segments.

The 8-thread/one-async-I/O signature (positive-controlled live: bare node = 7 threads; one threadpool
engagement = +1) is a node process that loaded a full ~140 MiB module graph, performed exactly one
async I/O, and parked forever — **a worker-pool child waiting on IPC that nothing ever reaps**.

**The igniter is named; the amplifier is documented in the repo's own comments:**

- `pnpm design:gate`, backgrounded at 00:11:17, boots its own `pnpm dev`; `next dev` cold-compiles
  the visited routes — *"Cold dev-compile is ~3-4min"* (e2e/playwright.config.ts:44-49, citing the
  prior "landing-storm" incident, SHIP_LANDING_CONCURRENCY_SCALE.md Addendum 2026-07-04). Setup
  finished 00:12:55; the compile spans exactly the fatal window; the session's own 18×30s poll on
  the gate is the row in-flight at the panic.
- Worker-pool spawn amplification under starvation is a *known, previously-measured* mode in this
  repo: vitest.config.ts:52-58 — *"vitest's default fan-out on a 10-core box produced 16 'Failed to
  start forks worker' errors and 2 of 182 files NEVER RAN … the pool's own worker-start deadline
  races a starved fork"* — mitigated only for the postland lane via `VITEST_MAX_FORKS`; every other
  lane (sessions running `pnpm test:unit`, 4 of which ran in the final 39 min; `next` build/dev
  worker pools; anything tinypool/jest-worker-shaped) retains the default fan-out and the
  respawn-on-timeout amplifier.
- Standing baseline at ignition: **≈7 resident stale `next dev` servers** across worktrees (the
  session's own census at 00:10:56), 2 backgrounded `pnpm build`, repeated `agent-browser` Chromium
  launches, and the 78-minute TCC/signature-verification storm (~456 verifications/s) — all inside
  the same coalition and page pool.

**Identity — three agents disagree productively, and the reconciliation is testable:**

- A7 (live fingerprint): every Claude session spawns a **3-deep `chrome-devtools-mcp` node chain**
  (`npm exec` → shim → main, ~165 MB each; live RSS 158-172 MB vs panic median 178.5 MB — exact
  match). 724 ÷ 3 ≈ 241 chains against 6 live sessions ⇒ orphaned MCP/browser-driver trees.
- A3 (refutation): live *working* chains run 12 threads; the cohort runs exactly 8 — a node that did
  ONE async I/O then parked.
- A2 (dating, wrap-immune): the population arrived **inside the final 12 minutes** (147 → 817), so
  "accumulated over 4.25 days" (A7's pid-range reading) is an artifact of mixing the 34 long-lived
  12-thread servers into the burst cohort (A3 separates them cleanly: burst pid-range 53556-62785,
  median gap 5).

**Reconciling hypothesis (fits all three):** node **stdio-server chains** (MCP/browser-driver
family) **burst-spawned during the fatal window and parked *unconnected*** — a spawned-but-never-
spoken-to stdio server is precisely 8 threads, ~170 MB of module graph, one stdin read, no exit.
ASP exec-telemetry is inconclusive (provenance lines are not 1:1 with spawns: 14,514 in 6 s at
00:10, only ~35-52/min during the storm), so the exact spawner — a retrying MCP/browser bridge,
the gate's pipeline, or the sessions' agent-browser open/close loops — is **formally open**. The
sentinel's on-ramp argv capture (§7.1) closes it at the next occurrence by construction.

## 4a. Kernel mechanics (A8 — verified against xnu-11417.140.69 source, this exact build)

- **The segment % counts swapped-out segments** (`panic_display_compressor_stats()` prints raw
  `c_segment_count`; `vm_compressor_out_of_space()` compares it, un-subtracted, to the limit —
  vm_compressor.c:595-600). The limit is really "total compressed data the kernel may *track*,
  RAM + disk = 124.3 GiB" — which is why the box died at ~31% RAM-equivalent occupancy with disk
  idle. At death ≈472K segments were in-core (28.83 GB) and ≈1.16M lived in the 68 swapfiles.
- **The provisioning assumes 4:1 compression** (pages limit = segments × 16). The observed
  31%/100% inverts to **4.96 pages/segment ≈ 1.25:1 effective compression** — the codec's
  incompressible path stores such pages RAW at 16 KiB (4/segment), and a 60-73% raw fraction
  reproduces the arithmetic exactly (model inversion, not yet a measurement — the live
  discriminator Δinput_bytes/Δcompressed_bytes is now sampled by the sentinel). A9's competing
  reading — segments ~69-75% *empty* (holes from thrash) — fits the same two percentages; the two
  mechanisms have different remedies and the discriminator decides at the next ramp.
- **Compaction cannot save either variant under load**: major compaction *refuses* segment pairs
  ≥90% full (raw-store variant has nothing to squeeze, vm_compressor.c:2340-2352), its trigger
  needs ≥⅛ of buffer pages to be holes, and the death spiral starves the compaction threads
  regardless (only the two `VM_compressor` threads were running at death).
- **A slot is freed only when a segment is COMPLETELY empty** (`c_seg_free_locked` asserts
  `c_slots_used == 0`) — one live page pins 64 KiB of pool forever. Hence: many long-lived,
  never-referenced-again processes = permanently pinned sparse segments.
- **No kill could have fired**: macOS ships **CONFIG_JETSAM off**. The release-kernel
  compressor-exhaustion branch can only kill IDLE-band processes (measured: it harvested ~2 MB
  Apple daemons), and the sole real safety net (`no_paging_space_action`) requires ONE process
  holding **>50% of the entire compressor** (>66 GiB tonight) — structurally untrippable by a
  fleet of 200 MB workers. Expected log line for fleet-shaped leaks, verbatim: *"unable to find
  any eligible processes to take action on"*.
- **The kernel's own edge signal fires at 98%** of the segment limit — **7.6 s** of warning at
  tonight's ramp. Any actuator keyed on the kernel's edge is too late by construction; it must
  key on *rate*, far below the ceiling.
- **The wedge shape**: at the ceiling `c_compress_page()` returns `KERN_RESOURCE_SHORTAGE` and
  the pageout thread **re-activates** each dirty page instead of freeing it — a live-lock, not a
  panic; the death is the external ARM watchdog noticing watchdogd starved. Matches all three
  reports.

## 4b. Two arms, one panic (A7) — and the second arm is not a memory bug

```
ARM 1 (memory)  node population burst → compressor at segment ceiling → kernel_task pegged
                → watchdogd starved → PANIC (×3)
ARM 2 (exec)    chronic spawn storm (hooks/tools/MCP per call) → launchd/xpcproxy/syspolicyd/tccd
                backlog → WindowServer main thread turnstile-blocked on the tccd send port
                → whole-desktop FREEZE (Jul 31 18:10 .spin: 40 s dead, 5 min before that panic)
```
The arms share the victim (watchdogd) but not the cause; 154 stuck xpcproxy stubs at tonight's
death and syspolicyd's 55,699 CPU-s Gatekeeper-commit `.diag` are ARM-2 signatures. A fix to one
arm does not cover the other. ARM 2 is also the "lag/freeze" the operator experiences on days with
no panic.

## 4. The mechanism — the burst strands segments; a cold swapper loses the race

Because `compressor_segment_pages_compressed_limit / compressor_segment_limit` = exactly **16**, the
panic line is a packing readout: **occupancy = pages% ÷ segments%** → 31-33% at all three deaths
(~5 of 16 pages per 64 KiB segment). The pool is provisioned for 124.3 GiB on a 64 GiB box —
fully-packed segments can never exhaust; only under-packed ones can (established Jul 30; the live
mechanism measured tonight):

1. Demand (~0.5 GB/s dirty) exceeds RAM → compressor compresses at 491 MiB/s.
2. The working set still exceeds RAM → recently-compressed pages fault straight back
   (+13.6M decompressions). Each decompression leaves a hole in a sealed segment.
3. Net effect measured: **36.2M page ops to retain 246,884 pages (0.68%)** — segments are consumed
   at compression rate while page count barely moves: 100% segments at 31% pages.
4. Drain requires swapout, and the swapper was **cold**: 2 GiB store, swapouts frozen for 21 h,
   forced to create 68 swapfiles mid-storm. The decisive control (A2-F15/16): on Aug 2 the same
   coalition reached **170.85 GiB / 515 procs and survived** — swap had engaged *early* (+796K
   swapouts, 18 GiB store, MPL=2 for 22 min). Footprint and count nouns do not separate fatal from
   survived; **burst-into-cold-swapper does** (n=2 fatal, n≥1 survived-at-4.2× — ordering, not a
   threshold).
5. Every kernel defense was structurally out of position: jetsam's idle-exit band killed ~2 MB Apple
   daemons and *skipped* the holders (Chrome "not idle-exitable"; node never touched); the
   compressor-space-shortage killer fired 2,903 failed kills in the last minute; kernel
   `memoryPressure` stayed `false` to the end (so anything keyed on pressure — including macOS's own
   warn level — never fired); and by the final 94 s jetsam itself was starved off-CPU.

## 5. Why every guard missed (sensor postmortem, A4)

| Defect | Evidence |
|---|---|
| **59-hour latched ALARM = zero bits** | rung-1 is `swap>0 ⇒ ALARM`; macOS `vm.swapusage used` decays ~8 MB/5.5 h and only resets at reboot. Latched by the Aug-2 event; 2,961 consecutive ALARM rows; exactly **one** notification ever reached the operator (Aug 2 20:04). Three genuinely new signals (max_proc 40 GB; seg 53.5%; pressure 2) arrived *inside* the latch and were invisible — already-ALARM ⇒ no state change ⇒ no page |
| **The missed sample hung inside its own probe** | run N+1 (~00:14) blocked in `zprint` (kernel zone-map walk under the very lock the storm contends) — still `TH_WAIT`, PRI-4 `darwinBG`, at the panic. `zprint` is 89% of the script's wall time (4.3-5.2 s idle). The sensor's slowest read blocks on the resource being exhausted — **no interval fixes that** |
| **ProcessType Adaptive did not escape the background band** | the child ran basePriority 4 / `darwinBG`. The background band starved ~3 min before foreground (launchd interval jobs stopped completing at 00:13:01 while sessions' Bash calls ran to 00:15:33) — the sensor sits in the first band to die |
| **Headroom counts unreclaimable pages** | at death the rung-2 formula reads 9.62 GB "headroom" (OK) from `inactive` while pageout was recovering **77 of 3,094 requested pages (2.5%)** |
| **Every fix filed after Jul-31 was unshipped** | adaptive cadence: rejected in-code; rung-6 re-noun: explicitly backlogged; actuator: deliberately not built ("operator decision"); per-coalition cap: absent; interpreter-free probe: absent. Only a PATH fix landed — and was reverted |
| **Telemetry false-success** | `bash-execution.log` is PostToolUse with `.tool_response.exitCode // 0`: every `run_in_background` workload logs `Exit: 0` seconds after launch — the allocator was recorded as a 5-second success. In-flight detection requires the pre/post log diff, and 2 of 4 "in-flight" candidates turn out to be permission denials that never ran |
| **Population invisible to the walk** | the ps tree-walk stops at ppid 1, so reparented orphans leave the count: it read **73** while the coalition held ~800 (0.089×, far worse than the filed 0.57×). The count noun is also *refuted outright*: 817 died where 996 survived |

## 6. What separates fatal from survived (and what does not)

**Refuted nouns** (do not rebuild alarms on these): process count (817 fatal < 996 survived) ·
coalition footprint (170.85 GiB survived vs 146.72 fatal) · MiB/proc (458 survived vs 142.6 fatal) ·
node CPU share (77% survived vs 59% fatal) · memory-pressure level (false at death, all three) ·
headroom/free (20 GB free at escalation; W2/W3 read healthy 12-20 min before death) · uptime (6.5 h
vs 102 h).

**Discriminators that held across all three deaths:**
1. **Compression *rate* with thrash** — 491 MiB/s sustained with decompressions ≈ 60% of
   compressions and ~0% net retention. No benign counterpart observed in 102 h.
2. **Segment occupancy** — pages%÷segments% ≤ ~33% while segment fill climbs. Readable live as
   `vm.compressor_segment_pages_compressed / (16 × segments_in_use)`; input/compressed-bytes ratio
   discriminates fragmentation-vs-incompressibility (A3-F8).
3. **Cold swapper at burst onset** — swapouts frozen for hours + tiny swap store when a burst lands.
4. **Background-band sampler death** — the *absence* of the 60-s row is itself the earliest
   machine-readable distress signal (fired ~3 min before the wedge in all three events; the
   MemoryPressureLevels sampler died 12 min early tonight).

## 7. Remediation (ranked by how directly it addresses the measured cause)

1. **A sentinel that cannot be starved and cannot hang** *(interim v1 live this session; daemonize)*:
   10 s cadence, reads ONLY counter sysctls (`vm.compressor_bytes_used`, input/compressed bytes,
   swapusage) — no zprint on the hot path (timeout-wrapped, slow lane only); NOT in the background
   band; durable JSONL. On ramp (>64 MB/s sustained): capture **full argv** of node/chrome/build
   trees (closes the attribution gap forever) + top-RSS snapshots at 5 s cadence.
2. **An actuator, because detection alone saved nothing three times**: on thrash signature
   (compression rate + decompression ratio + swap-create burst), **SIGSTOP the burst cohort**
   (newest node workers by spawn order, never claude.exe/UI), snapshot, page loudly, hold for
   triage. SIGSTOP stops the demand instantly, is reversible, and cannot kill work — a frozen
   worker is recoverable; a panicked box is not.
3. **Leash the known bursty pipelines** (driver-side): run `design:gate` / `pnpm build` /
   `test:unit` under a process-group memory leash (poll tree-RSS, SIGSTOP+alert at ceiling);
   `VITEST_MAX_FORKS`-class caps for *every* lane, not just postland; the gate's dev-server boot
   should refuse to cold-compile when free+cache headroom is below a floor.
4. **Reap the standing waste**: stale `next dev` servers (7 resident at ignition), parked worker
   orphans (ppid 1 + <2 s CPU + parked >10 min + >100 MB — alert-then-reap), and the broken kitty
   pane self-close chain (task #141) that lets session trees outlive their panes.
5. **Capacity-alarm surgery**: rung-1 keyed on swap *delta/rate* (never level); alarm on state
   *transitions* with per-rung slugs (so a new signal inside a standing alarm still pages);
   timeout-wrap or remove `zprint` from the tick; move the job out of the background band; emit the
   §6 discriminators (occupancy, thrash ratio, swapout rate).
6. **Per-process footprint caps — the verified lever** (A8): `memorystatus_control(MEMORYSTATUS_
   CMD_SET_MEMLIMIT_PROPERTIES)` sets a **phys_footprint ledger limit (resident + compressed +
   swapped — exactly the quantity that consumes segments)** on ANY live pid, root, fatal or soft,
   **not jetsam-gated** (kern_memorystatus.c:9055; call via `syscall(SYS_memorystatus_control,…)`,
   header is private). Soft limits (L2) on agent-spawned processes convert the kernel's "no
   eligible processes" dead-end into a targeted kill at the edge; launchd's `JetsamProperties.
   JetsamMemoryLimit` (Apple ships it on 4 of its own daemons on this box) is the plist form.
   VA-based rlimits (ulimit -v / HardResourceLimits) ARE enforced on modern xnu — contrary to
   folklore — but cap the wrong noun (reserved VA, false-kill-prone). No compaction tunables exist
   on release kernels; `kern.max_task_pmem` is boot-latched and system-wide — do not use.
7. **Sensor recipe without zprint on the hot path** (A8): in-core segments ≈ vm_stat
   "Pages occupied by compressor" ÷ 4; swapped-out segments = `vm.swapusage used ÷ 65536`
   (**exact** — swap is allocated in 64 KiB compressed chunks); their sum tracks `c_segment_count`
   from cheap sysctls alone. Add Δ`vm.compressor_input_bytes`/Δ`compressed_bytes` (true ratio),
   Δ(`vm.wk_compression_failures`+`vm.lz4_compression_failures`) (raw-store rate), and the free
   late edge `log stream` on "System is unhealthy". Trip on **level >15% of limit OR rate >600
   segments/s sustained 10 s** (ramp budget: full pool in 6.3-12.3 min at observed rates; the
   kernel's own edge leaves 7.6 s). `zprint`'s zone row is the exact numerator, root-free — but it
   hangs under the very storm it measures (00:14 run still TH_WAIT at panic): slow lane only,
   timeout-wrapped.
8. **Warm-swapper question** (open): the survived-at-170 GiB instance had swap engaged early;
   whether deliberate pre-warming is safe is untested — do NOT probe limits by reaching them
   (the threadprice lesson). The leash + actuator make it moot if they work.

## 8. The "once a day" experience, deconstructed (A9/A7) — three mechanisms, not one

wtmp shows exactly 5 boots Jul 27→Aug 5: one clean pair + 4 panic reboots — **zero hidden
freeze-then-power-cycle events**. The daily phenomenology is:

1. **Machine panics** — 3 organic in 6 days, all compressor-class (this doc).
2. **UI hangs / watchdog kills** (ARM 2): WindowServer .spin Jul 31 18:10, iTerm2/cmux
   cpu_resource reports, the Jul 29-31 era.
3. **Daily userspace crash noise that involves no panic at all** — and 89 of 104 `.ips` are two
   deterministic generators: **35 bash "crashes" are our own test suite's deliberate
   `kill -SEGV $$` positive control** (tests/cc-close-attrib.bats:81, coalition
   com.claude.postland-verify — it litters real crash reports daily and polluted this census), and
   **25 node SIGSEGVs are one `@libsql@0.5.29` napi-finalizer use-after-free** — diagnosed to root
   cause on Aug 2 in a session whose write-up (`NODE_SEGFAULT_ABRUPT_SESSION_CLOSE_2026-08-02.md`)
   **was never landed** (exists only in a transcript; the fix never shipped; 18 more crashes
   followed). Aug 2 had 23 node crashes and zero panics — fixing the panic class does not touch
   this noise, and vice versa.

**Standing loads found in the same sweep** (chronic headroom tax + why the box "lives
pre-fragmented" at ~15% segments / ~55% fill): a **screen recording left running 24 h** (10.4
CPU-hours, screencapture pid 43370); **tmux running with debug logging ON** — 137.44 GB of pane
output written to disk (`log_vwrite` in every sample); Next-dev servers re-offending to the
137 GB disk-write limit tier; syspolicyd/logd/mds_stores burning 13K-59K CPU-s each on the
fleet's exec/log/file churn; ~7 stale `next dev` servers resident at ignition.

**Tonight-only condition (A9): the box ran on BATTERY (83%)** — all prior panics were on AC.
On-battery QoS clamping slows exactly the background machinery (compaction, swap, samplers) that
loses the race. Contributing condition, not the cause; heavy pipelines should refuse or warn on
battery.

## Method notes (traps that would have silently falsified this investigation)

- `log` is a zsh builtin — a bare `log show` returns rc=1/empty and reads as "no data"; invoke
  `/usr/bin/log`. `--end` across a reboot is silently ignored ("Wall Clock adjustment detected") —
  slice by textual timestamp, never trust the bound.
- A `.panic` filename (and its `date` field) is the report *write* time; only the `Epoch Time →
  Calendar` block dates the panic. The watchdogd checkin counter (×10.0 s) dates it from inside the
  panic string, immune to file metadata.
- PostToolUse bash telemetry defaults `exitCode // 0`: every backgrounded workload logs instant
  success; "no Exit row" cannot exist. In-flight = pre-log ∖ post-log, and most of that diff is
  permission denials — read the transcript before convicting a row.
- The last sample before a blackout cannot testify about the blackout (systemstats showed a frozen
  swap counter through 00:06; the panic shows 68 swapfiles — the swapper fired violently inside the
  unsampled window).
- Summed `residentMemoryBytes` from a stackshot double-counts shared/compressed pages (153 GiB on a
  64 GiB box) — use it for *shares*, `memoryStatus` for totals.
- Microstackshot record format corrections: ts is u64 at +0x08; `seq` = core id (0-9); name at
  +0x7f (a +0x80 read truncates every name's first char); records 676-1,756 B (892 is the mode). A
  truncated gzip recovers via `zlib.decompressobj` — tonight that salvaged the ONLY instrument
  covering the fatal gap.
- Sibling-agent claims were re-derived, not inherited: A4's "population pre-existed the gap"
  (fault-count reasoning) is superseded by A2's wrap-immune 147→817 coalition series; A1's
  "00:18:22 is ~2 min late" is superseded by A3's decoded Calendar epoch (00:18:22 confirmed).

Related: `panic-iterm2-coalition-2026-07-31.md` · `iterm2-freeze-30-sessions-2026-07-30.md` ·
`panic-threadprice-2026-07-31.md` · [[compressor-segment-exhaustion-panic]] ·
[[darwin-qos-band-mechanics]] · [[alarm-polarity-and-attention-budget]] ·
[[liveness-proxy-cannot-be-output-age]] · [[threshold-noun-and-units]]
