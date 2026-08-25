# Adversarial verification — GUARD-FAILURE claim (2026-08-24 20:01 PDT panic #5)

Verifier: read-only, primary-evidence pass. Sources re-read directly: `scripts/compressor-sentinel.sh`
(repo @ `fd60f868b`), its git history, the live runtime logs
(`~/.claude/logs/compressor-sentinel.jsonl`, `…-snap.log`, `…-frozen.tsv`),
`/Library/Logs/DiagnosticReports/JetsamEvent-2026-08-24-195524.ips`,
`/Library/Logs/DiagnosticReports/panic-base+socd-2026-08-24-200410.000.panic`,
`~/.claude/logs/panic-attribution.jsonl`, `~/Development/reso-qa-runner/next.config.js` + its git
history, and the repo docs that name the structural fix. All times below UTC (logs are `date -u`);
PDT = UTC−7, so the 20:01:23 PDT panic = 2026-08-25T03:01:23Z.

## Verdict: CONFIRMED (every load-bearing element verified; four precision nuances listed at end)

## Element-by-element

### 1. "The sentinel was alive and froze both storm waves in time" — TRUE
- JSONL rows are continuous through the whole storm (02:49:50 → 02:58:54; stretched, never absent).
- Wave 1: `═══ TRIP 2026-08-25T02:50:03Z why=seg+cbu+swap ═══` at **36.75%** of the segment limit
  (snap-log line 47468). Actuator: `SIGSTOP parent pid=42897 kids=249 comm=next-server_(v16.2.6)`
  + 249 child SIGSTOPs (`actuator: SIGSTOPped 249 process(es)`). Second trip 02:52:14Z (78.14%)
  froze 57 more + re-signalled 42897.
- Wave 2: `═══ TRIP 2026-08-25T02:56:43Z why=seg+cbu+swap ═══` at **43.66%**. Actuator:
  `SIGSTOP parent pid=39672 kids=58 comm=next-server_(v16.2.6)` + 58 children
  (snap lines 48412-48549). Both trips are far below the kernel's 98% edge — "in time" holds.

### 2. "Its actuator (SIGSTOP) reclaims no segments" — TRUE
- Code: the only signals sent are `kill -STOP` (lines 1226, 1241) and `kill -CONT` (line 757);
  a kill path is excluded by design (header §4a: "must never SIGKILL … the reversible one").
- Empirically: during wave-2's hold (spawner + 58 biggest frozen, 02:56:43→02:57:54) segments ROSE
  711,540 → 1,170,154 (43.66% → 71.81%) and swap-used rose 18.1 GB → 49.5 GB. A freeze stops
  minting; it frees nothing, and the frozen pool's resident pages keep being compressed/swapped.

### 3. "Aug-19 unfreeze arm reuses the AND-of-level-and-rate trip predicate as its 'breach over' test" — TRUE
- The unfreeze arm was added in `5305ee34c` (2026-08-19 01:46 PDT, "the actuator called SIGSTOP
  'the reversible one' and nothing ever reversed it — 59 one-way freezes across 109 trips").
- Main loop (lines 1288-1290): `if [ -z "$WHY" ]; then RELMODE=clear; else RELMODE=ceiling; fi`
  where `WHY` is the output of `classify_breach` — the very trip predicate, whose seg arm (line 364)
  is `seg > lim*pct/100 && rate > rmin` (level AND rate, rmin=600 seg/s). So "breach over" =
  ONE tick of NOT(level AND rate): a rate lull below 600 seg/s at ANY level reads as clear, and
  `release_frozen … clear` SIGCONTs everything held ≥ `HOLD_MIN_S`=60 s (lines 742-768).
- The release policy comment (line 712-715) even states it: "clear — the breach is over (no trip
  this tick)". The predicate asymmetry (level-AND-rate to trip, single-tick negation to release)
  is exactly the claimed defect.

### 4. "One rate-lull tick at 71.8% read as clear and SIGCONT'd the primed wave-2 spawner (next-server 39672, held 68s)" — TRUE, verbatim
- JSONL 02:57:54Z: `seg=1170154 pct=71.81 srate=536.2` — 536.2 < 600, so the seg arm is false at
  71.81% of limit; cbu/swap arms also below their thresholds (crate 1.2 MB/s). The NEXT row's
  `strk=0` proves 02:57:54 evaluated as no-breach.
- Snap ledger: `SIGCONT pid=39672 held_s=68 kind=parent comm=next-server_(v16.2.6)` followed by
  `actuator: release mode=clear released=37 held=22 stale=0` (lines 48656, 48708). 68 s ≥ the 60 s
  HOLD_MIN, frozen ~02:56:46, released at the 02:57:54 tick. 36 workers released with it; 22
  (frozen later in the 02:56:43 actuation loop, still < 60 s) stayed frozen to the death.
- "Primed": the pool had jumped 18 → 427 node procs in the ~90 s before the freeze — an active
  rebuild queue.

### 5. "Whose resumed pool grew 427→713 workers" — TRUE (with a census-scope footnote)
- Census `n`: 427 (02:56:43 census, stale-repeated to 02:58:15) → 672 (02:58:54 census).
- The 02:58:54 trip snapshot's by-executable table: `39942.8 MB x713 node` — the 713.
- Attribution to the RESUMED spawner is airtight: a SIGSTOPped parent cannot fork, so every worker
  born 02:56:46→02:57:54 is impossible; the last snapshot's top-RSS is dominated by fresh
  `node /Users/chrisren/Development/reso-qa-runner/.next/dev/build/postcss.js` rows with
  **PPID 39672** and pids 71xxx-73xxx (post-release births), each 130-165 MB.

### 6. "Drove segments from 72% to 100% in ~2 minutes" — TRUE
- 71.81% at 02:57:54 → 75.05% (02:58:36) → 82.68% (02:58:54, the last row ever written; its own
  trip snapshot's vm_stat corroborates: 1,610,733 pages occupied ÷ 4 = 402,683 in-core segs +
  61.7 GB swap ÷ 64 KiB = 941 k swapped ⇒ 1.35 M ≈ 82.7%).
- Kernel endpoint (primary, re-read tonight): `panic-base+socd-2026-08-24-200410.000.panic` —
  "Compressor Info: 33% of compressed pages limit (OK) and **100% of segments limit (BAD)** with
  73 swapfiles". Watchdog panic 03:01:23 after 93 s of no checkins ⇒ wedge onset ~02:59:50.
  02:57:54 → ~02:59:50 ≈ 2 minutes. (To the panic timestamp itself it is 3.5 min.)
- Swap trace of the ramp: 49.5 GB (02:57:54) → 61.7 GB (02:58:54) — ~200 MB/s of new compressed
  segments streaming to disk while in-core sat pinned at ~402 k segs.

### 7. "Storm-stretched ticks (10s→146s) never completed another actuation" — TRUE
- `el` (measured elapsed per tick, config 10 s): 28 s (02:50:03), **121 s** (02:52:02), **146 s**
  (02:55:02), 65 s (02:57:43), 20 s, 16 s. Max 146 s as claimed.
- After the fatal release: the same predicate's clear ticks (02:57:54/02:58:05/02:58:15) also RESET
  the 2-consecutive-breach streak, then breach 02:58:36 (strk 1) + 02:58:54 (strk 2) fired
  `═══ TRIP 2026-08-25T02:58:54Z why=seg+swap ═══` — but the snap log's final bytes are that
  trip's own snapshot (top-30 + vm_stat) with ZERO `SIGSTOP`/`actuator:` lines after it, and the
  JSONL's next row is post-reboot (03:05:13Z). The last-chance actuation never completed; the box
  wedged during it.

### 8. "A generator whose named structural fix (workerThreads) had never been applied" — TRUE
- Both waves' spawners are the SAME app: `next-server (v16.2.6)` for `~/Development/reso-qa-runner`
  (wave-1 42897's and wave-2 39672's children both run
  `…/reso-qa-runner/.next/dev/build/postcss.js` per the trip snapshots' full argv).
- The named fix: `experimental.turbopackPluginRuntimeStrategy: 'workerThreads'` —
  `docs/research/crash-rootcause-2026-08-09.md:152` ("Fix shipped in the installed 16.2.6 …
  structurally removes the child processes"), verified unset in all 3 eligible apps on Aug 9
  (`docs/research/scaling-bottlenecks-2026-08-09/05-crash-closure.md:20`; filed `d60fd1f9c375`
  for reso-qa-runner).
- Live re-check tonight: `grep turbopackPluginRuntimeStrategy|workerThreads` → 0 hits in
  `reso-qa-runner/next.config.js`, `reso-management-app/next.config.*`,
  `agent-build-hackathon/next.config.*`. And `git log --all -S 'turbopackPluginRuntimeStrategy'`
  in reso-qa-runner → **zero commits ever**; next.config.js last changed 2026-07-03, before the
  fix was even named. Never applied, not applied-and-reverted.

## Corroborating context found during verification (not in the claim)
- The identical clear-mode release had ALREADY fired on wave 1: at 02:52:36 (level **76.31%**,
  srate −1353.9) `release mode=clear released=184 held=108`, including
  `SIGCONT pid=42897 held_s=116 kind=parent`; the remaining 108 released at 02:55:02. The box
  survived that one only because the wave-1 pool collapsed anyway — the kernel's memorystatus was
  mass-killing on this axis at the same minutes (`JetsamEvent-2026-08-24-195524.ips`: 3,092
  process rows with reason `vm-compressor-space-shortage`, 747 node rows across its event window)
  and the sentinel's trough at 02:55-02:56 (seg 8%, n 166→18, swap 26.6→5.9 GB) shows the pool
  exiting/dying. Wave 2 was the same release defect against a spawner with a live queue.
- 22 wave-2 workers were still frozen at death — direct evidence that holding a freeze does not
  shed segments (element 2), and that the release, not the freeze, is what changed the outcome.

## Nuances / precision corrections (none overturn the claim)
1. **"Froze both storm waves" = froze the spawner + the ≥40 MB burst cohort**, not the whole wave:
   wave-2 froze 59 of ~427 node procs (the RSS floor is live-tuned to 40,960 kB, cap 400). The
   under-floor young majority kept running, which is why segments climbed 43.66%→71.8% DURING the
   hold. The freeze stopped the minting (parent), not the climb.
2. **427/713 are box-wide node counts** (census `comm ~ ^node`; by-exe table), including ~14-18
   baseline non-worker node procs (MCP servers etc., n=14 pre-storm). The growth (+245…+286) is
   the postcss pool of 39672 and post-dates the SIGCONT.
3. **"~2 minutes" uses the wedge onset** (~02:59:50, from the 93 s watchdog silence); to the panic
   timestamp it is 3m29s. The last measured point is 82.68% at 02:58:54.
4. **The >100 s tick-stretches (121 s/146 s) occurred in the wave-1/inter-wave window**; wave-2's
   max was 65 s. The final trip's actuation was prevented by the wedge itself, with the
   streak-reset (by the same negated predicate) + 60 s cooldown having delayed re-trip to 02:58:54.
   The claim's compressed phrasing is directionally right.
5. Side-finding on the JetsamEvent header (affects the CONTEXT briefing, not the claim): the
   19:55:24 report's `memoryStatus` block (compressorSize 1,610,185 pages, free 3,838…) matches
   the wave-1 saturation plateau, not the 19:55:16-19:55:24 trough the sentinel measured
   (occupied 188 k pages, cbu 1.59 GB, swap 5.87 GB — three independent sysctls agreeing); the
   report is an aggregated kill ledger whose header snapshot precedes its write time. Treating
   its numbers as "state at 19:55:24" would be wrong either way it is resolved.

## The mechanism, in one paragraph (as verified)
The sentinel ticked through the whole storm and tripped early both times (36.75%, 43.66%). Its only
weapon is SIGSTOP, which caps demand but reclaims nothing, so the level kept rising on the unfrozen
under-floor workers and the paging-out of the frozen pool. The Aug-19 unfreeze arm then asked "is
the breach over?" with the negation of the trip conjunction: at 02:57:54, one tick of srate
536.2/s < 600 at 71.81% of the segment limit answered "yes", and `release mode=clear` SIGCONT'd
spawner 39672 (held 68 s) plus 36 workers. The resumed next-server refilled its postcss pool
(427→672 census, 713 by-exe; +~280 workers, all PPID 39672), pushing segments 71.8%→82.7% by
02:58:54 and to the kernel's "100% of segments limit (BAD)" by the ~02:59:50 wedge — ~2 minutes —
while the re-armed trip (delayed by the same predicate's streak-reset, the 60 s cooldown, and
storm-stretched ticks) fired at 02:58:54 and died mid-actuation. The generator was reso-qa-runner's
`next-server (v16.2.6)`, whose named structural fix
(`experimental.turbopackPluginRuntimeStrategy: 'workerThreads'`) has never existed in any revision
of its `next.config.js`.
