# Kernel-side axis: 21.2 GB wired / 11 GB zone map / data.kalloc.1024 at 9.2 GiB

Axis analysis for the 2026-08-24 20:01:23 watchdog panic (panic #5). Read-only investigation,
2026-08-24 ~20:15-20:40 PDT. Written by the kernel-zone subagent of task #181.
(Note: the orchestrator's target path rendered as `undefined/kernel-zone.md`; resolved to this
scratchpad file.)

## Verdict (answer first)

**`data.kalloc.1024` at 9.2 GiB is a cumulative, boot-scoped kernel-side leak that the Claude
Code fleet TRIGGERS but does not consist of — a known upstream issue
([anthropics/claude-code#44824](https://github.com/anthropics/claude-code/issues/44824)) — and it
was an ACCELERANT of the compressor-segment exhaustion, not its proximate cause.** Three facts
force this reading:

1. **The zone does not track the instantaneous fleet.** At 11:26 (healthy morning) the fleet was
   955 processes / 84,114 fds / 22 node — yet the zone was already **9.53 GB**. At 19:55 (4,477
   processes / 1,155,990 fds / 747 node) it was 9.89 GB — **+3.7% while the fleet grew ~14× in
   fd terms**. Post-reboot with 782 processes it is **12.3 MB** (11,981 elements in use). A
   per-fd/per-watcher/per-socket bookkeeping driver is arithmetically excluded: 84K fds × 1 KB =
   86 MB, two orders of magnitude short of 9.5 GB. The zone is a **ratchet built over the
   10.9-day boot session**, not a function of current load.
2. **The proximate killer was the compressor segment table, and its arithmetic closes without
   the zone.** `vm.compressor_segment_limit` = 1,629,615 slots (= 133.5 GB pool ÷ 80 KB alloc; 64
   KB payload per segment). At the last sentinel tick (19:58:54, 2.5 min pre-panic): 61.7 GB swap
   ÷ 64 KB ≈ 963K swapped-out slots + ~400K in-core ≈ 1.35M = **82.7% — measured**, climbing at
   +7,770 slots/s after peaking at +22,780/s. That reaches 100% right at the watchdog window.
   The demand was the fleet's anonymous memory (134 GB uncompressed for a 64 GB machine), not
   kernel metadata.
3. **The zone's real contribution is a standing ~9.5 GB wired tax (15% of RAM)** that displaced
   ~9.5 GB of working set into compressor+swap all day, bringing every storm ~16 GB closer to the
   segment cliff (together with the rest of the leaked-era wired baseline). At the measured final
   ramp (~8-23K slots/s ≈ 0.5-1.5 GB/s of compressed displacement) that headroom is worth only
   tens of seconds in the terminal storm — an accelerant, not the trigger.

The panic is therefore **doubly fleet-shaped**: userspace demand (the respawning node storm)
exhausted the segment table, while the fleet's own TUI rendering had — over 11 days — leaked away
a seventh of physical RAM into a kernel zone nothing could reclaim short of reboot.

## The measured numbers (all four time points)

| Metric | 11:26 (healthy-ish) | 19:55 (jetsam, T-6min) | 20:01 panic | now (post-reboot, ~20:15) |
|---|---|---|---|---|
| processes | 955 | 4,477 | — | 782 |
| total fds | 84,114 | **1,155,990** | — | ~6,714 open files (kern.num_files) |
| node procs (fds) | 22 (2,650) | **747 (986,250 = 85% of all fds)** | — | ~17 claude/node, ≤46 fds each |
| wired | 942,185 pg = 14.4 GB | 1,389,270 pg = **21.2 GB** | — | 233,070 pg = 3.6 GB |
| zone map | 11.16 GB / 24.95 GB cap (44.7%) | 11.83 GB (47.4%) | — | (n/a unprivileged) |
| data.kalloc.1024 | **9,532,801,024 (9.53 GB)** | **9,886,433,280 (9.89 GB)** | ~same ("Zone info" in panic) | **11,981 elems ≈ 12.3 MB** |
| compressor stored/occupied | 541,772 pg stored / 66,897 pg occupied (1.0 GB) | 8,772,415 pg stored (134 GB uncompressed) / 1,610,185 pg (24.6 GB) | 33% of pages limit, **100% of segments limit**, 73 swapfiles | 0 |
| free | 4.4 GB | **60 MB** (3,838 pg) | — | 24.5 GB |
| swap used | ~3.7 GB (sentinel) | 26.6 GB at 19:55:02 → 61.7 GB by 19:58:54 | ~73 GB (73 swapfiles) | 0 (only sleepimage in /private/var/vm) |

Sources: JetsamEvent-2026-08-24-112657.ips + -195524.ips headers (`tail -n +2 | jq .memoryStatus`),
`.contents.panic` (world-readable), `~/.claude/logs/compressor-sentinel.jsonl`, `vm_stat`,
`sysctl`, unprivileged `zprint`.

## 1. What populates data.kalloc.1024 — and why the usual suspects are excluded

xnu (this build: xnu-11417.140.69) splits kalloc into three heaps
([osfmk/kern/kalloc.h](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/kalloc.h)):
`kalloc.type.*` (typed, per-signature), the default heap, and **KHEAP_DATA_BUFFERS — the
`data.kalloc.N` zones — restricted by design to "pure bags of bytes with no pointers or
length/offset fields"** (security segregation against heap spray). This constraint is the key
analytical lever: **pointer-bearing kernel structs cannot live in this zone.** Applying it to the
suspect list from the axis brief:

| Suspect | Lives in data.kalloc.1024? | Scales with | Can it reach 9.5 GB here? |
|---|---|---|---|
| kqueue/knotes (fs + fd watchers) | **No** — knote/kqueue are pointer-bearing, kalloc.type/own zones | (b) watchers | No (wrong heap) |
| socket buffers | **No** — mbufs/clusters are their own zones (separate mbuf map) | (c) connections | No (wrong zones) |
| vnodes / name cache | **No** — own `vnodes` zone (263K vnodes now ≈ normal) | (d) open files | No |
| Mach ports / ipc entries | **No** — typed ipc zones | (a) processes | No |
| Skywalk | **No** — own `skmem` arenas; VM_KERN_MEMORY_SKYWALK = **7.4 MB** now | (c) | No (measured trivial) |
| fileproc/fileglob (per-fd) | **No** — typed | (d) | No |
| **pipe ring buffers** | **Yes** — pipe data buffers are kalloc_data, size classes incl. 1024 | (a)+(d): fleet stdio/MCP pipes | Only ~0.1-0.6 GB at observed fd counts (≤1 KB buffer per small pipe; 84K fds at 11:26 ⇒ ≪1 GB) |
| **Mach message bodies** (ipc_kmsg data), OOL small data | **Yes** — data heap | (a) XPC traffic | Transient (queued msgs only); qlimits cap depth |
| **IOKit OSData / driver data buffers** (incl. GPU/graphics submission-adjacent ~1 KB buffers) | **Yes** | rendering/compositor traffic, NOT object counts | **Yes — if never freed.** The only candidate compatible with a ratchet that ignores fleet size |
| EndpointSecurity message buffers | Yes (data-shaped) | ES clients | No third-party ES clients here; queues are bounded |

Conclusion of the taxonomy: **nothing that scales with (a) process count, (b) watchers, (c)
connections, or (d) open files can produce 9.5 GB in this zone at the observed populations** —
the countable per-object candidates either live in other heaps or are 20-100× too small. What
fits is a **never-freed ~1 KB data-buffer leak whose allocation rate tracks activity volume
(terminal rendering), accumulating monotonically per boot** — which is exactly what the external
record documents.

## 2. External confirmation — this is a known Claude-Code-triggered kernel leak

[anthropics/claude-code#44824](https://github.com/anthropics/claude-code/issues/44824) ("Claude
Code CLI triggers macOS kernel memory leak (kalloc.1024) → kernel panic", closed as duplicate;
related: [#32752](https://github.com/anthropics/claude-code/issues/32752) node-pty ~18 GB/hr,
[#23252](https://github.com/anthropics/claude-code/issues/23252) 12 GB on macOS 15.5,
[#11315](https://github.com/anthropics/claude-code/issues/11315),
[#33673](https://github.com/anthropics/claude-code/issues/33673); ghostty#10289 — terminal-side
mitigation shipped in Ghostty v1.3) reports, on Apple Silicon (M1 Pro, macOS 15.7.4/15.7.5 —
same AGXG13X driver family as this M1 Max on 15.6.1):

- `data.kalloc.1024` grows **~27-42 MB/min while Claude Code runs — 0 MB/min without it**;
  killing Claude Code **stops growth but frees nothing** (ratchet, reboot-only recovery).
- Reaches **11-14 GB** and panics — their signature: `userspace watchdog timeout: no successful
  checkins from WindowServer`, `Zone info: data.kalloc.1024 11G / 13G`. Ours: watchdogd timeout
  with the same zone as largest at 9.9 GB. (On 16 GB machines the leak itself wedges the
  compositor; on this 64 GB machine with a 24.9 GB zoneMapCap the leak stays sub-critical and the
  box dies by the compressor path first — two presentations, one leak.)
- Reproduced across iTerm2 (Metal on/off), Terminal.app, minimized windows; the reporter's chain:
  Ink/React TUI redraw flood → terminal → WindowServer → AGX GPU driver → 1 KB kernel data
  allocations never freed. The in-kernel allocation site is the reporter's inference
  (medium confidence); the correlation (CC on/off ⇒ growth on/off) and the zone identity are
  measured (high confidence).

Our two-point + baseline data independently reproduces the shape: ~9.5 GB after 10.9 days of
continuous multi-pane fleet operation (average ~0.6 MB/min — duty-cycle-diluted vs. their single
attended session), flat against fleet-size swings, 12 MB after reboot. **No evidence for an
independent macOS 15.6 Skywalk/ES leak was found** (searches; and Skywalk's tag measures 7.4 MB).

## 3. The kill chain — where the zone sits in causality

Sentinel log (`~/.claude/logs/compressor-sentinel.jsonl`, 10 s ticks, UTC; local = UTC-7) and the
19:55 JetsamEvent give the full final sequence. Segment limit = 1,629,615.

| Local time | Event |
|---|---|
| Aug 13 22:42 | Boot. Zone starts ratcheting (leak active whenever TUI sessions render). |
| Aug 24 08:00-13:00 | Quiet: segments 4-6% of limit, swap ~3.8 GB. **11:26 header: zone already 9.53 GB; wired already 14.4 GB** (zone map 11.2 GB of it). The 11:26 JetsamEvent itself is noise — a `per-process-limit` kill of `IntelligencePlatformComputeServi` (Apple Intelligence, 200 fds). |
| 14:00-16:00 | Storm #1: segments to 37.4% (608K), swap 9.2 GB; subsides 16:00-19:00 (8-16%). |
| 19:00-19:55 | Storm #2: sentinel node census `n` hits **672**; segments climb; swap 26.6 GB at 19:55:02, segment count already collapsing (-4,892/s) as the kernel begins killing. |
| **19:55:24** | JetsamEvent: **3,092 processes killed `vm-compressor-space-shortage`** (+17 highwater) out of 4,477. Free was 60 MB; compressor 24.6 GB occupied / 134 GB stored-uncompressed. Segments crash 529K → 132K by 19:55:26; swap 26.6 → 5.8 GB. **The box survived this.** |
| 19:56:27-19:58:54 | **Re-ignition**: the fleet's supervisors/respawners rebuild the storm — 301K → 711K → 1,164K → **1,347,363 segments (82.7%)**, swap 61.7 GB, rates to +22,780 seg/s. Last sentinel line 19:58:54; the sentinel (10 s cadence) never writes again — starved with everything else. |
| ~19:59-20:00 | Extrapolated 100% of segment slots (panic line confirms: "33% of compressed pages limit (OK) and 100% of segments limit (BAD) with 73 swapfiles and OK swap space"). Compressor refuses new pages; reclaim wedges; watchdogd's last checkin ≈ 19:59:50. |
| **20:01:23** | `watchdog timeout: no checkins from watchdogd in 93 seconds` — AppleARMWatchdogTimer, kernel_task (756 threads), cpu 3. Stackshot itself failed ("Bytes Filled 240, err 52") — the kernel could not even allocate its own crash evidence. |

**Why "100% of segments at 33% of pages" (the fragmentation signature):** the two limits are
calibrated together — 1,629,615 segments × 16 pages (64 KB ÷ 4 KB avg compressed page) =
26,073,840 = exactly `vm.compressor_segment_pages_compressed_limit`. Hitting the slot limit at
only 33% of the page limit means segments averaged ~5.4 stored pages (~25-33% packed): 197M
lifetime decompressions (thrash) pull pages out of segments leaving holes, and compacting
~1M swapped-OUT segments requires swapping them in — which requires the free memory that no
longer exists. Slots become unreclaimable at exactly the moment they are exhausted. The prior
panic doc (`docs/research/panic-compressor-2026-08-05.md` §4, "the burst strands segments; a cold
swapper loses the race") named this mechanism; panic #5 is the same class at larger scale, with
the re-ignition-after-jetsam twist.

**The zone's causal role, quantified:** wired 21.2 GB + compressor 24.6 GB left ~18 GB for all of
userspace at 19:55. Of the wired, 11.0 GB was zone map, 9.9 GB of that the leak zone. Without the
leak (healthy wired ~5-6 GB), the same 134 GB anonymous demand still exceeds physical RAM ~2×,
still swaps ~50-90 GB, still consumes ~0.8-1.4M segment slots. The leak moved the cliff ~15%
closer and made the whole day run degraded (14.4 GB wired at *idle*), but the segment table was
killed by demand volume + fragmentation, and would plausibly have been killed by the re-ignition
storm regardless. Conversely the leak **alone** could not have panicked this 64 GB box for weeks
more (zone-map jetsam engages at ~95% of the 24.9 GB cap; the leak was at 40%).

## 4. Wired accounting (21.2 GB at 19:55)

- **Zone map: 11.03 GB** (of which data.kalloc.1024 = 9.21 GiB = 83.6% of zone map used; the
  remaining ~1.8 GB is every other kernel zone — normal at this process count).
- **Non-zone wired ≈ 10.2 GB**, grown +6.2 GB during 11:26→19:55 while zone map grew only
  +0.67 GB — i.e., the death-spiral's wired growth was NOT the leak. Attributable (measured now
  at 782 procs, scaling with the 4,477-proc storm): pmap/PTE (723 MB now → multi-GB at 5.7×
  procs with giant V8 address spaces), compressor segment metadata for 1.63M slots, boot-stolen
  1.88 GB, GPU/ANE/display DMA (~0.9 GB now), kernel stacks, IOSurface for WindowServer (largest
  process in both headers). Exact split needs root-privileged zprint/footprint; not obtainable
  read-only post-reboot.

## 5. Adjacent-axis notes (for the merging lead)

- The shipped guard (`scripts/compressor-sentinel.sh`) **saw everything and could act on
  nothing it was built for**: its actuator is DEFAULT OFF (`CC_SENTINEL_ACT=stop` opt-in), its
  cooldown is 60 s, and the fatal re-ramp went 8% → 83% in ~150 s with trip streaks visible
  (`strk:1` at 19:56:43, 19:57:54, 19:58:54). Whether it was armed, and why the 19:55
  jetsam reprieve was immediately squandered by respawners, is the fleet/guard axis.
- **6 compressor-sentinel processes are running post-reboot** — duplicate-spawn worth a look.
- The 19:55 jetsam killing 3,092 processes and the storm rebuilding within 90 s is the
  strongest single fact for the fleet axis: the demand generator survives kernel-level mass
  kills (respawn loops), so no in-kernel defense can end a storm — only the spawner can.
- fseventsd logged a cpu_resource diag Aug 23 19:27 (`fseventsd_2026-08-23-192756...diag`,
  not readable without sudo) — consistent with heavy fs churn, unrelated to this zone (fs
  watchers don't allocate here; §1).

## 6. What to do about THIS axis (recommendations, not actions — read-only session)

1. **Instrument the ratchet, unprivileged**: `zprint` without sudo returns the `cur inuse`
   element count (col 7) even though sizes read 0K — `data.kalloc.1024` live bytes ≈ inuse ×
   1024. A slow-cadence (5-15 min, with timeout; NOT inside the sentinel's hot tick — zprint
   hangs under storms, sentinel header §7.7) rung that logs this + alerts at e.g. 4 GB turns an
   invisible 11-day ratchet into a scheduled-reboot decision. Post-reboot baseline: 11,981
   elements.
2. **Reboot cadence while the leak exists upstream**: at this fleet's average ~0.6 MB/min
   (~0.9 GB/day, bursty), a weekly reboot caps the tax at ~6-7 GB; the 10.9-day uptime is what
   let it reach 9.9 GB.
3. **Reduce the trigger surface**: the leak tracks TUI redraw volume, not work done. Headless
   (`claude -p`) / detached workers render no Ink UI; fewer live panes = lower leak rate.
   Ghostty ≥1.3 shipped a terminal-side mitigation for the same class (ghostty#10289) — relevant
   to the kitty/iTerm2 terminal decision already tracked in this repo.
4. **Track the upstream issues** (#44824 and its duplicate-target thread) for an Anthropic-side
   render-throttle fix and any macOS fix; on a macOS update, re-measure the ratchet under
   identical fleet load before trusting it.

## Refuters (what would overturn this reading)

- `data.kalloc.1024` growing for hours with ZERO Claude Code/TUI sessions running would break
  the CC-trigger attribution (points instead at an independent macOS leak).
- A controlled A/B showing the zone scaling ~linearly with held-open pipes/fds into the GB range
  would rehabilitate the bookkeeping theory this analysis excludes on arithmetic.
- A future compressor-segment panic with this zone <1 GB would confirm the accelerant-only role
  even more strongly (half-shown already: the 07-30/08-05/08-09 panics were the same class, but
  their JetsamEvent files have rotated away, so their largestZone values are unknown).
- Root-privileged zone logging (zlog/kmem tracing on a dev kernel) attributing the 1 KB
  allocations to a non-graphics subsystem would correct the in-kernel site attribution (which is
  medium-confidence, inherited from #44824's correlational evidence).

## Method notes

- Jetsam `.ips` headers carry `zoneMapSize/zoneMapCap/largestZone/largestZoneSize` — the only
  boot-time-series of zone state available without root; only Aug 24's two files survive
  rotation.
- The sentinel's `seg` estimator (occupied-pages÷4 + swap÷64 KB) and the jetsam's
  `compressorSize` are different instruments sampled seconds apart during a collapse — each is
  used above only for its own claim.
- `swap` in the sentinel JSONL is bytes, not MB, despite the field-name history.
- Unprivileged `zprint` reporting inuse-but-not-size is undocumented behavior verified live this
  session; treat as a macOS-15.6-observed fact, re-verify after OS updates.
