# Panel H-CAP-1 — raw return: `cap-gauges`

Fable 5 baseline-blind derivation panelist, 2026-08-09. Session `f2c51d03-3b5b-4cb6-97e2-c3a42fcf87ee`.
Recovered from the teammate's own transcript after the named-teammate spawn returned no value to the lead (see the write-up for that defect). Verbatim, unedited.

---

<!-- 2026-08-09T21:03:02.676Z -->

I'll derive first (done in-model), then run a tight batch of read-only probes to confirm/refute the derived numbers — sysctl limits, vm_stat, pty count, process/thread census.

---

<!-- 2026-08-09T21:06:46.428Z -->

## GAUGE TABLE — lying condition stated mechanically

| Gauge (as used on this box) | Claims to measure | True aggregation | Lying condition (mechanism) | Fires in time? |
|---|---|---|---|---|
| **1-min loadavg** (`vm.loadavg`; consumed by `scripts/lib/capacity-admit.sh:157`) | CPU saturation | EWMA (~5 s kernel ticks) of *runnable* thread count. Darwin excludes threads blocked on I/O, locks, and **vm_fault/compressor waits** | The worst incident class on this box — memory thrash — parks threads in vm_fault, emptying the runqueue: **load reads LOW during the thrash.** Also: 1-min time constant means a 30 s spawn burst is over before the gauge reaches 63% of it; and asymmetric cores + QoS bands mean the background band (E-cores, PRI=4) is fully starved at load ≈ 2 on a "10-core" ceiling. Measured now: load 6.5 with only **3 runnable** — the number is churn residue, not demand | No — for both memory cliff and sub-minute bursts |
| **`head_gb` = free+speculative+inactive+purgeable** (`capacity-admit.sh:163-174`, commented "what a new session can take WITHOUT swapping") | Admittable memory headroom | vm_stat queue sizes | **`inactive` conflates evictable file-backed pages with anonymous pages reclaimable only BY compressing/swapping — vm_stat has no inactive-anon line, so the conflation is structural, not a tuning error.** At 150 near-idle sessions, ~all their anon working sets age onto the inactive queue: head_gb reads tens of GB "takeable without swapping" that is 100% compress-to-take. The comment asserts the exact opposite of the mechanism. Also fails OPEN on a dead probe (line 65) — an unreadable gauge admits | No — overstates headroom worst exactly at the target scale (many idle sessions) |
| **memorystatus pressure level** (`kern.memorystatus_vm_pressure_level`, now =1) | Kernel's own memory verdict | Staircase off free-page thresholds + compressor occupancy | Compressor silently absorbs tens of GB while level stays 1; the 1→4 transition happens in seconds when idle sessions wake *concurrently* (broadcast prompt → decompression storm). A level gauge with cliff dynamics: always green until unactionably late | No |
| **Swap used** (`vm.swapusage` — currently **0.00M total: no swapfile even exists**) | Memory overcommit | Integral of the LAST stage — compressor must approach its limit before the first pageout | Reading 0 is compatible with being minutes from the cliff; and being an integral, alarming on level misses the rate that is the actual signal | No |
| **Pageout/swapout rates** (vm_stat deltas) | Thrash | Compressor→disk spill only | Compressor-internal churn (compressions+decompressions both climbing, zero pageouts) is the first thrash stage and shows only in two counters nothing alarms on; pageins are polluted by file-backed image faults from every fork/exec | Partially — if someone sampled compressions/decompressions, which nothing does |
| **CPU %** (top: 15.8 us / **19.8 sy** now, near-idle fleet) | Compute headroom | All-core cycle average | Band starvation invisible: taskpolicy-background work confined to 2 E-cores stalls completely at ~20% aggregate. And CPU% counts cycles, not latency lost queuing in single-threaded XPC daemons. 19.8% sys at near-idle is fork/hook churn — the cost that scales with session count is in the *sys* column and nobody splits it | No for the failures that matter |
| **Per-proc/sum RSS** (`ps`) | Fleet footprint | Resident pages incl. multiply-counted shared pages; **excludes compressed pages** | The inversion: as pressure rises, pages migrate to the compressor and LEAVE RSS — **sum-of-RSS improves as the box approaches the cliff.** (Now: sum 25.6 GB ≈ PhysMem 33 GB only because compressor=0.) VSZ is noise — measured 299 T vsize. Honest metric is phys_footprint, which `ps` cannot show | No — wrong direction under pressure |
| **Proc/thread/fd/disk counts** | Table occupancy | Direct | These gauges *don't* lie — they're just unread, and (measured) all far from their limits at this scale | Would, if anything read them |

## NEGATIVE SPACE — resources no gauge on this box watches

1. **The ptmx clone pool — `kern.tty.ptmx_max` = 511 [CONFIRMED]**, 24 allocated now. No sysctl reports occupancy; the only census is `ls /dev | grep -c '^ttys'`. Every pane, every split-right handoff, every script/pty wrapper holds one. It is the only kernel table on this box sized in **hundreds** — everything else is 10⁴–10⁶ — and it is invisible to load, memory, pressure, and the admission gate. Exhaustion = `posix_openpt` ENXIO: new sessions and pty-using tool calls fail while every gauge is green. [DERIVED, limit CONFIRMED by probe]
2. **Compressor occupancy vs its own limit + compression ratio** (`vm.compressor_bytes_used`, compressions/decompressions rates) — the actual stage-before-swap scarcity. A `compressor-sentinel.sh` exists in-tree, but the *admission* path (`capacity-admit.sh`) reads loadavg + head_gb only — the sentinel's knowledge does not gate spawns. [EVIDENCE: grep of capacity-admit.sh]
3. **Shared single-process chokepoints**: one iTerm2 process hosts every pane (one run loop, one fd table, GUI coalition); WindowServer holds wired unified-memory GPU buffers per visible pane, attributed to no fleet process; fseventsd/cfprefsd/notifyd take 150-client fan-in serially. Per-process gauges structurally cannot attribute this cost to the fleet that causes it. [DERIVED]
4. **Fork/exec + XPC handshake bandwidth**: hooks fork per tool call; 19.8% sys at near-idle is the baseline tax. Latency degradation in this path (every spawn serializing on opendirectoryd/launchd) has no level-gauge at all. [DERIVED; baseline sys% CONFIRMED]
5. **The inactive-anon/inactive-file split itself** — unmeasurable from vm_stat by construction; any headroom formula built on vm_stat inherits the lie (this is what makes finding #2 in the table unfixable by tuning). [DERIVED]

## BURST WALKTHROUGH — 300 small near-idle processes in 1–3 min

- **t=0–60 s** (first ~150 spawns): sys% spikes (fork + XPC fan-in); instantaneous runq spikes but 1-min load reads only ~half the burst mean — and is uninterpretable anyway (the gate's own header records loadavg **346** at a healthy boot storm). head_gb drops from ~30 GB but reads green. Pressure 1, swap 0, compressor 0. Pageins climb — indistinguishable from normal image faults. pty pool: 24 → ~175. **Nothing red.**
- **t=60–120 s**: first wave already idle → **load DECAYS while the burst continues** (EWMA forgets faster than idle procs re-demand). Memory: 300 × ~50 MB ≈ 15 GB, absorbed by the 19.7 GB free + speculative eviction; every memory gauge green. Procs 748→~1,650 (vs 16,000), threads ~3,460→~8,000 (vs 81,920), fds ~2% of table. pty: ~350. **Still nothing red.**
- **t=120–180 s**: pty allocation crosses **511**. Every subsequent pane/wrapper open fails ENXIO. At that instant the box reads: load ~3–6 and falling · CPU mostly idle · head_gb 15–25 GB · pressure 1 · swap 0 · every counted table ≤10% of limit. **The admission gate ADMITS the spawn whose pty open then fails.**

**First-exhausted resource: the ptmx clone pool (511).** If the burst is headless (no ptys), nothing exhausts *during* it — instead the trap arms: 300 idle anon working sets age onto the inactive queue, head_gb keeps counting them as takeable, and the first synchronized wake is the cliff — a decompression storm that loadavg is mechanically blind to (blocked threads) and the pressure staircase reports only after the fact.

## FALSIFIABLE RUNTIME PREDICTIONS

1. **Pty ratio ≥1.5/session.** `echo "$(ls /dev | grep -c '^ttys') ptys / <live session count>"` — predict ≥1.5×; at 150 sessions predict ≥225/511 (>44%) with pressure level still 1. Breach (ratio ≈1.0) weakens, doesn't kill, the pty-first claim.
2. **Pty exhaustion precedes every gauge.** Staging probe: `for i in $(seq 1 40); do (script -q /dev/null sleep 120 &); done; ls /dev | grep -c '^ttys'` — count rises by ~40 and no gauge moves. Extrapolated failure point: allocation 511 → predict `script`/pane open fails with "out of pty devices" while `sysctl -n kern.memorystatus_vm_pressure_level` = 1 and load1/ncpu < 1.0. (Lead runs the full-scale version, bounded.)
3. **head_gb inflation on an idled fleet.** After ≥30 min fleet idle: from one `vm_stat`, compute A = free+speculative+purgeable and B = A+inactive (the gate's sum). Predict B ≥ 2×A — i.e., ≥half the gate's "takeable without swapping" memory is compress-only. If B ≈ A, my inactive-anon model is wrong.
4. **Sum-RSS inversion.** Once `sysctl -n vm.compressor_bytes_used` > 8 GB, `ps -axo rss= | awk '{s+=$1} END{print s/1048576}'` reads LOWER than the same fleet read at compressor=0. If sum-RSS rises monotonically with pressure, refuted.
5. **Sys% superlinearity.** `top -l 2 -n 0 | grep 'CPU usage' | tail -1` at 150 sessions: predict sys ≥ 40% (from 19.8% at ~15-session scale). If sys stays <25% at 10× sessions, my fork/XPC-churn scaling model is refuted.

## REFUTED (by measurement, this session)

- **Per-UID proc slots as first wall** — derived limit ~2–4 k; measured `kern.maxprocperuid`=10,666, occupancy 446. Not the wall.
- **Thread table** — 3,460 / 81,920 (per-task 16,384). Not the wall.
- **System fd table** — 6,853 / 491,520; per-proc soft limit here is 1,048,576, not the 256 default I derived. Not the wall.
- **Swapfile disk-space exhaustion** — 4.9 TiB free. Not the wall (though `vm.swapusage total=0.00M` confirms no swapfile exists yet — first pressure event pays swapfile-creation latency, a one-time stall I had not derived).

## CAMPAIGN CANDIDATE

**Occupancy-table admission** — replace rate/level proxies with one probe reading every *finite table* as fraction-of-limit (`ttys/511`, `procs/16000`, `procs-uid/10666`, `threads/81920`, `files/491520`, `compressor_bytes/limit`) and gating on max-fraction. The pty blind spot becomes a no-op (it's just the fullest row); the loadavg-ceiling debate the gate's own header documents (§8.5.2 retraction, boot-storm 346) becomes a no-op (saturation proxies stop being load-bearing); compressor blindness becomes a no-op (it's a row, not a separate sentinel). Tables lie far less than proxies: they ARE the resource.

---
**Contamination noted:** project MEMORY.md + CLAUDE.md auto-loaded (mention QoS band mechanics, compressor-sentinel, capacity tooling); set aside — all gauge derivations were built before the repo grep, which was run only to pin lying conditions to the gauges the live gate actually consumes (`capacity-admit.sh` = loadavg + head_gb, fail-open). **Probes spent:** 5 Bash batches, all read-only (sysctl/vm_stat/ps/top -l 1/df/rg + one 30-line file window); nothing forked wide, nothing written.
