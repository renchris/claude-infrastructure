# Panic #5 — 2026-08-24 20:01:23 PDT — cross-axis synthesis

Synthesizer's merge of five blind evidence axes (task #181), plus the synthesizer's own
primary-data adjudication of the one material inter-axis conflict (sentinel jsonl rows read
directly this session). Machine: MacBookPro18,2 M1 Max, 64GB, macOS 15.6.1; boot session
Aug 13 22:42 → Aug 24 20:01:23 (~10.9d); panic: AppleARMWatchdogTimer, "no checkins from
watchdogd in 93 seconds", Compressor Info "33% of compressed pages limit (OK) and 100% of
segments limit (BAD) with 73 swapfiles".

Axis files (all in this scratchpad):
`jetsam-analysis.md` (A1: who held memory / who was killed) · `log-timeline.md` (A2: unified-log
death spiral) · `node-crashes.md` (A3: user-level crash cluster) · `guard-postmortem.md` (A4: the
shipped guard) · `kernel-zone.md` (A5: wired/zone anomaly).

---

## 0. Verdict, answer first

**A reso-management-app `next-server (v16.2.6)` dev-worker fork storm, run under the Claude Code
agent fleet's QA team (session-6ee7e044, teammates infra-nightly/reso-qa), exhausted the VM
compressor's segment table twice in eleven minutes; the shipped guard caught and froze both waves
in time, then its own Aug-19 unfreeze arm SIGCONT'd the second wave's spawner at 71.8% of the
death ceiling, and the resumed pool drove segments from 72% to 100% in ~2 minutes.** At 100% of
1,629,615 segment slots (reached at only 33% of the pages limit — thrash fragmentation, ~5.4 of
16 pages per segment, uncompactable with 60MB free) the compressor could neither allocate nor
reclaim; jetsam spun futilely (2,740 kills, all small daemons — the fleet sat band-protected at
priority 180 and ~60 browser renderers were not idle-exitable); kernel_task pegged three pri-91
threads; watchdogd starved for 93s; the watchdog fired at 20:01:23.

Magnitude: node processes went **22 → ~747** and **4.0GB → 128.4GB** (85.9% of all process
memory) between the 11:26 baseline and the storm peak; wave 1 alone pushed segments **7% → 78%
in ~2 minutes** (+52GB swap), wave 2 **8% → 82.7% in 2.5 minutes**; total anonymous demand ~134GB
uncompressed on a 64GB machine.

This was the **fifth** panic of the class and the **third** with the same named generator
(v16.2.6 turbopack `process_pool`), whose structural fix — `turbopackPluginRuntimeStrategy:
'workerThreads'` in reso's `next.config.js`, named in the Aug-9 postmortem — was verified absent
15 days later (task #151 still `in_progress`).

---

## 1. Reconciled timeline (kernel + sentinel + jetsam + crash-report evidence merged)

All PDT. Sentinel rows are UTC−7 (02:xxZ = 19:xx PDT). Segment limit = 1,629,615
(= in-core vm_stat pages÷4 + vm.swapusage used÷64KB, per the sentinel's estimator).

| Time | Event | Source |
|---|---|---|
| Aug 13 22:42 | Boot. `data.kalloc.1024` leak starts ratcheting (CC-TUI-triggered, upstream claude-code#44824). | A5 |
| Aug 14–24 | **Chronic pressure every single day**: 78–487 `vm-compressor-space-shortage` jetsam kills/day, all small daemons; 73 swapfiles accumulate; zone reaches 9.5GB by Aug 24 morning; wired 14.4GB at *idle*. | A1 (kill ledger), A5 |
| Aug 21–23 | Crash cluster characterizes the workload class: reso next-server v16.3.0/dev-stack workers in `~/Development/.worktrees` crash-respawn-looping unattended at 3 AM (better-sqlite3 N-API mismatch on stray `/usr/local/bin/node`; libsql exit-finalizer UAF). Ends Aug 23 04:27 — 40h pre-panic; **exonerates user-process crashes as proximate**, proves the dev-worker population churned on after the guard shipped. | A3 |
| Aug 22 21:26 | Last wake; box runs awake 46h35m straight to the panic (16,763 watchdog checkins × 10s ✓). | A2 |
| Aug 24 11:26 | Healthy baseline: 22 node procs / 4.0GB, compressor 1.1GB, free 4.7GB, sentinel reading 4.5%. The 11:26 JetsamEvent is a routine per-process-limit kill (Apple Intelligence service) — different species, zero pressure. | A1, A2, A4 |
| 14:00–17:30 | Survived storms (segments to ~37%; 15:04–15:08 idle-kill tremor of 134 daemons). Sentinel tripped and the box recovered — the guard demonstrably ended single-wave storms (27 trips in the prior 27h). | A2, A4, A5 |
| **19:49:50** | **Storm ignition.** Sentinel census: n jumps 17→166 nodes, 23.6GB RSS; compressor-bytes rate 88.7MB/s. Spawner: `next-server (v16.2.6)` **pid 42897** (age in the later JetsamEvent back-dates its spawn to ≈19:49:50). Owners: claude.exe QA teammates infra-nightly/reso-qa (team session-6ee7e044). | jsonl row 02:49:50Z; A4; A1 |
| **19:50:03** | **TRIP 1** at 36.75% (srate 17,190 seg/s): parent-breaker SIGSTOPs 42897 + 249 workers. Detection latency ~13–28s from ignition — detection was *fast enough*. Actuation of 250 procs stretches the tick to 121s. | A4; jsonl |
| 19:51–19:52 | Spawning already committed keeps landing: segments 77.4% at 19:52:02, **swap 56GB** (+46GB in one 121s tick, 380MB/s swapout). **TRIP 2** 19:52:14 (78.14%) re-freezes 42897 + 57 more kids; freeze debt 308. | jsonl; A4 |
| 19:52:36→19:54 | Rates go negative → **clear-mode releases begin** (`SIGCONT pid=42897 held_s=116` + cohort; all releases in the incident held_s 60–116, none ceiling-mode). Released/never-frozen wave-1 workers **exit en masse**. | A4 snap; jsonl |
| **19:53:34** | Kernel's one unambiguous verdict, mid-peak: `System is unhealthy… {"compressor_exhausted": 1, swap_low: 0, zone: 0}` with **16.4GB** memorystatus_available_pages — proof this is segment exhaustion, never free-RAM shortage. Jetsam main massacre 19:53–19:54: 1,663 kills, all small daemons, ~8.4GB reclaimed, compressor unmoved; `killing_top_process` count 0; 87,152 not-idle-exitable skip lines begin (Browser Helper Renderer ×46,208, Chrome Helper ×15,579). | A2 |
| ~19:53:34–19:55:0x | **JetsamEvent capture window** (written 19:55:24): 747 nodes / 128.4GB (93% already compressed), free 60MB, compressor 1,610,185 pages in-core, wired 21.2GB, zone 9.89GB — the portrait of the peak. (See §2.2: capture precedes the file's write-time.) | A1; §2.2 |
| **19:55:16** | **Real trough** — wave 1 has exited: segments 529K→132K (8.1%), swap 56→5.8GB, in-core compressor 25.4GB→2.9GB, n=18. Three independent kernel counters agree (vm_stat, swapusage, compressor_bytes_used); jetsam kill-rate collapses to ~0 for three minutes — the kernel corroborates the recovery. **By the trip predicate the incident is "over".** | jsonl rows 02:55:02–02:56:09Z (synthesizer-read); A2 kill histogram |
| **19:56:27–19:56:43** | **Wave 2 re-ignition**: +21.3GB compressor bytes in 23s; n=427; **TRIP 3** (43.66%, srate 22,781/s) parent-breaks `next-server` **pid 39672** + 58 kids. Level 72% by 19:57:43 (swap re-swollen to 49GB). | jsonl; A4 |
| **19:57:54** | **The fatal release**: one tick reads srate 536 < 600 during a swapout lull → "clear" → **`SIGCONT pid=39672 held_s=68`** + 37 workers, with the box at **71.81%** of the segment limit. | jsonl row 02:57:54Z; A4 snap |
| 19:58:36–19:58:54 | Resumed pool re-mints: srate +2,870 → +7,770/s; n 427→672 (census 713, 39.9GB resident = a *young, freshly-allocating* population); **82.68%**, swap 61.7GB. **TRIP 4** writes its snapshot; **no actuator output ever reaches disk**. Last sentinel row ever: 19:58:54 — 149s before the panic. | jsonl; A4 |
| ~19:59–20:00 | Segments hit **100%** (~36s from 82.7% at the measured rate). Fragmentation makes the slots unreclaimable (compacting ~1M swapped-out segments needs free RAM; free = 60MB). Jetsam's final futile storm: 877 kills in 19:59; kernel_task spins. | A5 arithmetic; A2 |
| 19:58:39→19:59:50 | Instrument-death cascade: watchdogd's log dies 19:58:39; WindowServer's last act is CoreAnimation fence timeouts 19:59:32–33; logd's last persisted line machine-wide 19:59:36.655; last watchdogd kernel checkin ~19:59:50. | A2 |
| **20:01:23** | PANIC: watchdog timeout, 93s, cpu 3, kernel_task; stackshot itself fails (err 52 — the kernel couldn't allocate its own crash evidence). Reboot 20:02:10; `ResetCounter…diag`: "Boot faults: wdog,reset_in1". | A2 |

---

## 2. Cross-axis reconciliation (where axes conflicted, and who wins)

### 2.1 What caused the ~19:55 segment collapse — jetsam kills (A5) vs wave-1 exit (A4)

**A4 wins; A5's mechanism is refuted; the trough itself is REAL (synthesizer verified in the
primary data).** A5 read the 19:55 JetsamEvent's 3,092 `vm-compressor-space-shortage` kills as
one 19:55:24 kill wave and credited it with the segment crash. A1 proves that ledger is the
**whole boot session's** kill history (daily histogram Aug 14–24: 280/356/487/380/446/406/220/
143/115/78/185; oldest kill Aug 14 02:04), and both A1 (name scan) and A2 (unified log) prove
**zero node/fleet victims ever** — jetsam reclaimed 8.43GB of daemons in the whole spiral while
the collapse returned ~72GB (22.5GB in-core + 50GB swap). Only mass worker **exit** frees that.
The sentinel jsonl (read directly this session) shows the collapse as a coherent 3-instrument
event across six rows (02:52:36→02:56:09Z), beginning **on the same tick the clear-mode SIGCONTs
began** — release → resume → exit → reclaim. A5's *conclusion* survives with the mechanism
corrected: the storm rebuilt from 8% to 83% in ~150s after a full reclaim, so **no kill-the-
workers defense can outlast a live spawner** — only stopping the spawner (or its config) ends a
storm.

### 2.2 747 nodes alive at "19:55:24" (A1) vs n=18 and 8% at 19:55:16–36 (A4/A5 jsonl)

**Both are right about different instants: the JetsamEvent's memoryStatus + survivor table were
captured minutes before the file's 19:55:24 write time.** The .ips header (free 60MB, compressor
1,610,185 pages in-core, 747 nodes holding 121GB) is flatly incompatible with the simultaneous
sentinel rows (in-core 2.9GB, swap 5.8GB, box demonstrably recovered) — but matches the kernel's
own 19:53:34 line (`compressor_size:1610187`) and the 19:53–19:54 kill-storm peak exactly.
Serializing a 2.7MB report (1,368 survivors + 3,109-kill ledger) on a box at 60MB free takes
time; capture ≈ 19:53:34–19:55:0x, write 19:55:24. Consequences: A1's census stands as the
**peak portrait** (its per-process data is untouched), and its spawn-minute histogram shifts
~80–110s earlier — which resolves an internal contradiction (parent 42897 "spawned 19:51" yet
frozen by name at 19:50:03) into a perfect fit (spawn ≈19:49:50 = the sentinel's first sighting
of n=166).

### 2.3 "Browser renderers held the memory" (A2 hypothesis) vs the byte census (A1)

**A1 wins on bytes; A2's finding survives re-scoped as the CPU-spin mechanism.** A2 inferred
holders from 87,152 skip-enumeration lines (61,787 on ~60 renderer pids); A1's per-process page
table shows browsers held 10.0GB (6.4%) vs node's 128.4GB (85.9%). A2 anticipated exactly this
refuter. The renderers matter causally anyway: they are why jetsam's scan degenerated into a
skip-spin (with launchd respawn churn) that contributed to starving watchdogd — the CPU face of
the death, not the memory face.

### 2.4 Kill-count discrepancies (3,109 vs 3,092 vs 2,740)

No conflict once windows align: 3,109 = whole-boot ledger total (A1: 3,092 compressor-space +
17 highwater); 2,740 = unified-log kills inside the 19:49:51–19:59:34 spiral (A2). A5's "3,092
at 19:55:24" is the §2.1 misread.

### 2.5 next-server v16.2.6 (A4, the fatal spawners) vs v16.3.0 (A3, the crash cluster)

Not a conflict — two coexisting populations in different worktrees. The **fatal** generator is
v16.2.6 (sentinel comm strings, trip snapshots), the same version the Aug-9 postmortem indicted;
A3's v16.3.0 crashes (Aug 21–23) show the broader dev-stack churn. The workerThreads fix must be
verified against *every* worktree population, not just reso root.

### 2.6 Naming: "claude.exe" (A1) vs "claude is a Bun binary named `claude`" (A3)

Consistent: CC 2.1.220 sessions appear as `claude.exe` in the jetsam tables (13→16 procs,
4.7→6.8GB — flat through the storm); A3's point is that the *crashing/storming* `node` processes
were not CC binaries. Both axes exclude CC sessions themselves as the storm processes; the +3
sessions are plausibly the QA team session + teammates.

---

## 3. Primary cause (with magnitude)

**An unreclaimed `next-server (v16.2.6)` dev-worker fork storm** under the fleet's reso QA team:
two waves totaling ~730 spawned node workers (~344/min at peak) allocating **~126–134GB of
anonymous memory on a 64GB machine in under 11 minutes** — 128.4GB / 85.9% of all process memory
at peak, 93% of it already compressed — which filled **100% of the VM compressor's 1,629,615
segment slots at only 33% of its pages limit** (thrash fragmentation, ~5.4/16 pages per slot,
uncompactable at 60MB free), wedging kernel reclaim and starving watchdogd into the 20:01:23
watchdog panic.

## 4. Contributing causes (ranked)

1. **The named structural fix never reached the enforcing store**: `turbopackPluginRuntimeStrategy:
   'workerThreads'` absent from reso `next.config.js` 15 days after the Aug-9 postmortem named it;
   task #151 still `in_progress`. Same binary, same pool, third panic. (The repo's own
   `conclusion-must-reach-the-enforcing-store` memory class, re-enacted.)
2. **Release-into-relapse**: the guard's Aug-19 unfreeze arm defines "breach over" as *no trip
   this tick*, inheriting the trip's level-AND-rate predicate — one rate-lull tick at 71.8%
   reads "clear" and SIGCONT'd the primed spawner mid-incident (held 68s; every release in the
   incident was clear-mode, held_s 60–116).
3. **No reclaim lever anywhere**: SIGSTOP stops the ramp but returns zero segments; SIGKILL
   forbidden by design; the Aug-5 "verified lever" (per-pid `memorystatus_control` memlimit)
   never built; jetsam structurally blind to the holders (fleet at band 180; `killing_top_process`
   never engaged; 3,109 kills over 10.9 days reclaimed 9.28GB of daemons).
4. **Trip predicate AND where the research prescribed OR** (panic-compressor-2026-08-05.md §7.7)
   — manufactures "clear" ticks at 72–83% during rate lulls, gating re-trips and driving #2.
5. **Chronic saturation as the launchpad**: compressor-space-shortage kills every one of the
   boot's 10.9 days, 73 swapfiles, and the `data.kalloc.1024` ratchet at 9.5–9.9GB wired
   (CC-TUI-triggered, upstream #44824) + 21.2GB total wired ⇒ ~15% of RAM taxed before the storm
   began; every storm started closer to the cliff (accelerant, not trigger — zone grew +3.7%
   during the 8.5h in which the compressor grew 24×).
6. **Guard throughput at the cliff**: ticks stretched 10s→121/146s under actuation+storm; node
   census up to ~6 stretched ticks stale (read n=166 through the trough, n=18 through wave-2's
   ignition); trip-4's actuation never evidenced on disk; 60s cooldown; 40MB RSS floor spares
   newborn workers.
7. **No admission control on the fork path**: capacity_gate admits *sessions*, not what a session
   spawns; devserver-gc exempts owned servers (the fatal spawners had live owners); the QA lane
   runs bare `tsx`/`next dev` with no process-group memory leash.
8. **The futile-kill spin as CPU thief**: 2,740 respawn/re-kill daemon kills + 87K skip
   enumerations + ~3,000 log lines/s starved userspace (watchdogd, WindowServer, logd) in the
   final two minutes — the proximate path from memory exhaustion to the watchdog.
9. **10.9-day uptime** — the leak, the swapfiles, and the segment-pool fragmentation are all
   boot-scoped ratchets.

## 5. Guard verdict (why the shipped prevention did not prevent)

The sentinel was alive, detected wave 1 within ~13–28s, and froze both spawners in time — but
its actuator (SIGSTOP) can only stop the ramp, never return segments, and its Aug-19 unfreeze
arm re-uses the AND-of-level-and-rate trip predicate as its "breach over" test, so a single
rate-lull tick at 71.8% of the segment limit read as *clear* and SIGCONT'd the primed wave-2
spawner (next-server 39672, held 68s), whose resumed pool grew 427→713 workers and drove
segments from 72% to 100% in ~2 minutes while storm-stretched ticks (10s→146s) never completed
another actuation — with the whole event only possible because the structurally-named generator
fix (workerThreads) was never applied.

Nuance the fixes must respect: the release arm is not uniformly wrong — releasing **workers**
is what produced the wave-1 exit and full reclaim (78%→8%); the fatal act was releasing the
**spawner** while its driver (the QA workload) still wanted workers. And the counterfactual
"never release" is *also* unsafe alone: a permanently frozen wave 1 would have pinned ~78% and
wave 2 would have landed on top of it. Freeze buys time; only spawner-stop, worker-exit, or a
kernel-enforced cap ends a storm.

## 6. Fix directions for claude-infrastructure (ranked; do not implement here)

1. **`scripts/compressor-sentinel.sh` — split the release policy from the trip predicate.**
   Release *workers* early (their exit is the reclaim), but release a **parent/spawner** only on
   level-based hysteresis: pct below ~15% of the segment limit sustained N ticks AND swap back
   near baseline — never on a one-tick rate lull; raise spawner min-hold well above 68s (the
   observed multi-wave horizon is ~10min); probation: re-freeze the spawner on the first
   positive srate after release. (Proximate mechanism of #5; small diff.)
2. **Drive task #151 to done and verify by content**: `turbopackPluginRuntimeStrategy:
   'workerThreads'` landed in reso-management-app `next.config.js` (and audited across
   `~/Development/.worktrees/*` — the fatal pool is v16.2.6, the crash cluster ran v16.3.0),
   plus the Aug-5 §7.3 pipeline leash: wrap the QA/dev lanes' `next dev`/`tsx` in a
   process-group memory ceiling. This removes the generator that has now produced three panics.
3. **Give the sentinel a reclaim rung**: when freeze-debt exists AND level ≥ ~60% and rising —or
   a second trip fires while debt is open — escalate to SIGKILL of the *spawner parent(s)*
   (next-server class; never claude/mcp), because worker exit is the only observed segment
   reclaim (78%→8%); and/or build the Aug-5 §7.6 "verified lever": per-pid
   `memorystatus_control` memlimits stamped on dev-server/worker processes at spawn — the one
   mechanism that still acts when userspace is starved.
4. **Sentinel cliff-mode**: above ~60% pct, skip the census and snapshot (they stretched ticks
   to 121–146s and left trip-4's actuation unevidenced), act from a pre-computed cohort, write
   actuation *intent* to disk before signaling (write-ahead), drop the 60s cooldown, and keep
   the tick ≤10s under load. Also implement the trip predicate's OR form (level>15% OR
   rate>600) at least for re-trip gating, per the Aug-5 research.
5. **Jetsam reachability for the worker class**: stop launching dev workers into the
   band-protected 180 tier — launch QA/dev lanes with a jetsam-eligible band / JetsamProperties
   / the #3 memlimits so macOS's own killer can reach actual holders instead of relaunch-killing
   3,109 daemons for 9.28GB. (Research task: which launchd/spawn attributes reach non-daemon
   children.)
6. **Chronic-pressure telemetry into `capacity-alarm.sh`** (alarm-only is fine here): swapfile
   count (73 at death — alert ≥ ~20), daily `vm-compressor-space-shortage` kill count from the
   jetsam ledger (78–487/day all week — alert > ~50/day), and the unprivileged `zprint`
   `data.kalloc.1024` inuse count (alert ≥ ~4–6GB) feeding a **scheduled-reboot advisory**
   (weekly cadence caps the leak's ~0.9GB/day ratchet while upstream #44824 is open); prefer
   headless/non-TUI workers to cut the leak's trigger surface.
7. **Fix the panic-attribution arm** in the sentinel's startup scan: dedupe on content/mtime,
   not basename — the undated `.contents.panic` currently shadows every dated
   `panic-base+socd-*.panic`, so panic #5 has no ledger row (the "make the next death
   attributable" instrument missed the death it was built for).
8. **Post-reboot hygiene check**: A5 observed **6 compressor-sentinel processes running
   post-reboot** — audit the KeepAlive/wrapper for duplicate-spawn before trusting the guard's
   next incident record.

## 7. Open questions (blocking full confidence)

1. **What issued the 19:49:50 spawn command** — the QA agents' concrete workload (build? test
   sweep?) is unrecovered (argv/command lines died with the boot), and **both reso launchd
   plists were touched 19:52 mid-storm** (A4) — unexplained and worth tracing in fleet logs.
2. **Trip-4 actuation**: completed-but-unlogged vs never-ran. The 19:55 JetsamEvent pre-dates
   trip 4 so cannot show state-T processes; `frozen.tsv` was wiped at reboot. Affects how much
   margin cliff-mode (#4) must buy.
3. **Wave-1's exit mechanism**: resumed-and-finished, crashed (the Aug-23 cluster shows both
   crash modes), or supervisor teardown? Determines how much reclaim a *worker*-release policy
   can be counted on to produce, and whether the no-release counterfactual survives wave 2.
4. **Wave-2 workers' identity**: argv shows bare `node`; the tie to the turbopack pool is the
   parent comm `next-server (v16.2.6)`. If wave 2 was a different pool (e.g. jest-worker),
   fix #2's coverage narrows.
5. **JetsamEvent capture instant** (§2.2) is inferred from instrument contradiction, not
   documented; the zero pid-overlap between kills and survivors is likely builder-side dedupe.
   A pinned capture time would firm the spawn-histogram shift.
6. **`data.kalloc.1024` site attribution** is correlational (upstream #44824: CC-on/off ⇒
   growth-on/off); root-privileged zone logging would confirm the AGX/graphics path; prior
   panics' largestZone values are unrecoverable (their .ips rotated away).
7. **Can jetsam's `killing_top_process` ever engage on this config?** It never did at 60MB free.
   If it structurally cannot, fix #5 has no kernel backstop and #3's memlimits carry the load.
8. Minor instrument: the jsonl `strk` field appears to reflect the *previous* sample's breach
   (offset by one row) — verify against the script before keying any new logic on it.

## 8. Provenance

- A1–A5 details files (this scratchpad) — each axis's own sources listed therein.
- Synthesizer's direct reads this session: `~/.claude/logs/compressor-sentinel.jsonl` rows
  02:45–03:01Z Aug 25 (the fatal window, quoted in §1/§2) and post-reboot tail.
- Key primary documents cited by the axes: `/Library/Logs/DiagnosticReports/JetsamEvent-2026-08-24-{112657,195524}.ips`,
  `.contents.panic`, `panic-base+socd-2026-08-24-200410.000.panic`, `ResetCounter-2026-08-24-200414.diag`,
  unified log (retained from Aug 13 boot), `~/.claude/logs/compressor-sentinel-snap.log`,
  `scripts/compressor-sentinel.sh` + plist + git lineage,
  `docs/research/panic-compressor-2026-08-05.md`, `docs/research/crash-rootcause-2026-08-09.md`,
  `~/Library/Logs/DiagnosticReports/node-*.ips` (25), reso `next.config.js` / `package.json`,
  anthropics/claude-code#44824.

---

## 9. Adversarial verification (two independent verifiers, primary artifacts only)

Both load-bearing claims were re-derived from primary evidence by verifiers instructed to REFUTE
them, treating the axis analyses as testimony and their sources as evidence. Both: **CONFIRMED.**

- **Primary cause** — every element reproduced digit-for-digit: the two-wave next-server (v16.2.6)
  postcss/dev-worker storm under QA team session-6ee7e044 (22→747 node procs, 4.0→128.4 GB, 93.3%
  compressed, 746/747 at band 180), segment exhaustion by fragmentation (100% of 1,629,615 slots at
  33% of the pages limit ≈ 5.3/16 pages per segment — the kernel's own `vm.compressor_segment_limit`
  and `…pages_compressed_limit` sysctls), the fatal release at 19:57:54 verbatim in the sentinel's
  own snap ledger (`SIGCONT pid=39672 held_s=68 kind=parent comm=next-server_(v16.2.6)` +
  `release mode=clear released=37`), TRIP 4's actuation absent from disk, and the terminal sequence
  (watchdogd log dies 19:58:39, logd's last machine-wide line 19:59:36.655, last checkin 19:59:50,
  panic 20:01:23).
- **Guard failure** — the release arm's defect verified at code level: `classify_breach`'s seg arm
  is level AND rate (line 364), and the main loop's `if [ -z "$WHY" ]; then RELMODE=clear` is its
  single-tick negation, releasing everything held ≥ 60 s. JSONL row 02:57:54Z: pct 71.81,
  srate 536.2 — below the 600 rmin, hence "clear".

Material corrections adopted from the verifiers (details in their reports):
1. Node's share at 19:55:24 is 77.0% of all-process rpages / 78.3% of internal footprint by the
   jetsam ledger; "85.9%" is node's share of resident RSS in the sentinel's 19:58:54 aggregate.
   Node anonymous footprint at 19:55 was 121.3 GB.
2. **The storming server ran from `~/Development/reso-qa-runner`** — a reso-management-app clone
   pinned at next **16.2.6**; reso proper is on 16.3.0. The workerThreads fix is absent from BOTH
   `next.config.js` files; the operative checkout is the QA runner clone.
3. The chronic "78–487 compressor-space-shortage kills every day" comes from the 19:55 JetsamEvent's
   own whole-boot kill ledger; the unified log has rotated and cannot independently reproduce the
   per-day figures. Direction (chronic daily pressure, 73 swapfiles, 245.7M lifetime compressions)
   stands.
4. The `data.kalloc.1024` = 9.53→9.89 GB zone growth is confirmed in both same-day reports; its
   attribution to upstream claude-code#44824 exists only in session transcripts and remains
   unverified.
5. Wave-2 spawner pid 39672 is absent from the 19:55:24 snapshot (fresh spawn or capture-window
   effect); the sentinel proves it live with 58 postcss children by 19:56:43.
6. Deduplicated vs raw kill-line counts differ ~2× (2,740 unique (pid,name) in the spiral); the
   log-flood average measured ~1,970 lines/s over 19:59:00–36 (peak-second ~3,000 plausible).

## 10. Remediation shipped (this commit series, branch fix/panic5-sentinel-release)

`scripts/compressor-sentinel.sh` + `tests/compressor-sentinel.bats` (123 cases green) +
`launchd/com.claude.compressor-sentinel.plist` (policy record):

1. **Release split by kind** — a frozen SPAWNER (`kind=parent`) is released only on the
   sustained-calm certificate (pct < `REL_PARENT_PCT` 15 for `REL_PARENT_TICKS` 3 consecutive
   clear ticks — level subsumes swap, since swapped segments are half of SEG_EST) after
   `PARENT_HOLD_MIN_S` 600 s; never on a one-tick rate lull, never at the worker ceiling. Workers
   keep the old clear/ceiling rules (their exit IS the reclaim). The exact fatal tick
   (71.81% @ srate 536, held 68 s) is replayed in the suite and refused.
2. **Probation** — a released spawner is re-frozen on the FIRST breach tick inside
   `PROBATION_S` 300 s, before the detector's streak/cooldown debounce is consulted.
3. **The cliff regime** (`CLIFF_PCT` 60) — above it the trip predicate gains a level-only arm
   (the Aug-5 §7.7 OR form, scoped to where OR is true: nothing benign sits at 60% of the segment
   limit), one breach tick trips, the cooldown no longer gates re-trips, the census and the heavy
   snapshot/follow-up are skipped (ticks stretched 10→146 s under them; trip 4's actuation never
   reached disk), actuation intent is written AHEAD of signals, and nothing is ever released.
4. **The kill rung** (`CC_SENTINEL_KILL`, on under ACT=stop) — when the freeze is losing
   (`kill_due`: a re-trip over held debt, or pct ≥ `KILL_PCT` 60 and still climbing), the frozen
   custody is SIGKILLed: only pids this daemon already froze under the claude/mcp exclusions,
   (pid,lstart)-verified again at kill time, comm belt re-checked, `KILL_MIN_HOLD_S` 30 s so the
   freeze always gets its chance first. Worker exit is the only observed segment reclaim; SIGSTOP
   returns zero segments. This deliberately supersedes the Aug-5 "never SIGKILL / we must be the
   reversible one" rule — reversibility preserved to the end is what panicked the box.
5. **Instrument repairs** — `strk` now logs the current tick's streak (synthesis open question 8);
   `panic_newest` excludes dotfiles so `.contents.panic` can no longer shadow dated reports (the
   defect that left panic #5 with no ledger row — backfilled at the next daemon start);
   `freeze_boot_already` tolerates ±5 s kern.boottime jitter (the double-recorded boot in the live
   ledger); a (pid,lstart) mutex makes the daemon single-instance (6 were observed live post-boot).

Not in this repo (tracked separately): the generator fix
`experimental.turbopackPluginRuntimeStrategy: 'workerThreads'` for reso-management-app AND the
reso-qa-runner clone (task #151), and the QA-lane process-group memory leash.

## 11. Ledger backfill note

`~/.claude/logs/panic-attribution.jsonl` holds `report:".contents.panic"` (recorded 2026-08-18 with
the Aug-9-era verdict). With the dotfile excluded, the next sentinel start records
`panic-base+socd-2026-08-24-200410.000.panic` as a fresh row — the stale row is kept (history is
never rewritten), and readers keying on basename now see dated reports only.
