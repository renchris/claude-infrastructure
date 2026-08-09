# Why this box keeps panicking — root cause, and why five "resolutions" did not stick

**Date:** 2026-08-09 (written between panics #5 and #6 and finished after #6)
**Status:** root cause CONFIRMED from primary evidence · actuator ARMED tonight (operator-authorized)
**Supersedes nothing — completes:** `panic-compressor-2026-08-05.md` (mechanism), `machine-lag-and-kitty-2026-08-06.md` (fleet census), `panic-iterm2-coalition-2026-07-31.md` (coalition-attribution artifact). This doc adds the two Aug-9 panics, the cross-event synthesis, the failure-to-stick analysis, and the arming record.

---

## 1. Verdict

**The machine dies of VM-compressor SEGMENT exhaustion caused by burst storms of fleet-spawned
`node` dev-tooling processes — and it kept dying because every shipped remedy was a detector,
while both built actuators sat deliberately disarmed awaiting an operator decision that was never
actually put to the operator.**

The kill chain, each link now measured at least twice:

1. **Ignition** — a dev-tooling burst under the autonomous CC fleet: `next dev` cold-compile /
   `next-server (v16.2.6)` postcss worker pool (Aug-9 ×3 waves), a 68-proc node fan-out with esbuild
   (Aug-5 near-miss), `pnpm design:gate` → `next dev` (Aug-5 panic), GB-scale `eslint`/`next build`
   singles. Storm shape: **hundreds of 60–180 MB near-idle node interpreters appearing in 1–3
   minutes** (measured 18→372 procs in 90 s; 700 procs / 38.9 GB; 736 / 44.7 GB).
2. **Kill mechanism** — the horde's anonymous pages flood the compressor, which exhausts its
   **segment structures at only ~28 % mean segment fill** (100 % of `vm.compressor_segment_limit`
   = 1,629,615 while the compressed-pages axis reads 31–32 % "OK"): fragmentation/compaction
   starvation, worst-cased by near-incompressible pages (1.24:1 ratio measured at the Aug-5 04:27
   event). Swap grew at 457–580 MB/s; 66–68 swapfiles.
3. **Why macOS cannot save itself** — the entire CC fleet sits in **jetsam band 180** (killed last);
   only ~7.6 GB was jetsam-reachable below it at the Aug-5 04:27 event. `CONFIG_JETSAM` is off;
   `no_paging_space_action` needs one process >50 % of the whole compressor — untrippable by a fleet
   of small workers. The kernel's own `memoryPressure` flag read **False at the moment of death**
   in both decoded panics. Jetsam's only act at both near-misses: killing a 15 MB Apple daemon.
4. **Death** — with the pageout path wedged, userspace stalls system-wide (TH_RUN collapsed 235→6
   with 10 idle cores; watchdogd's pri-97 thread parked in `mach_msg` receive, *not* CPU-starved),
   watchdogd misses 91–94 s of checkins, and `AppleARMWatchdogTimer` panics the box.

**The GUI dialogs that drove two weeks of misdiagnosis are artifacts.** "Force Quit: kitty 4.73 TB
(paused)" and the earlier "iTerm2 at ~500 GB" modal attribute the *coalition* (every process the
terminal's tree hosts) or bare virtual address space (every arm64 proc carries ~395 GB VSZ;
12 × 395 GB = 4.74 TB) to the visible GUI app. The dialog lists **only GUI apps**, so a headless
700-process storm is structurally invisible in it. kitty's real anonymous memory at the measured
moments: **0.11–0.17 GB** (resident 1.4–1.8 GB, mostly IOSurface shared with WindowServer); it sat
in jetsam band 0 (first to be killed), was itself suspended by memorystatus ("paused"), and did
41 M page faults as a *victim*. **kitty is exonerated as cause** — and cannot have initiated the
series anyway: crash #1 predates the kitty bundle's existence on this box by 2.5 h.

## 2. The incident ledger (all eight events)

| # | When (PDT) | Event | Class | Primary evidence |
|---|---|---|---|---|
| 0 | 07-30 ~21:53 | iTerm2 GUI freeze (no reboot) | WindowServer mach-port/window saturation — **distinct failure mode** | `iterm2-freeze-30-sessions-2026-07-30.md` |
| 1 | 07-30 02:18 | Panic (uptime 55.3 h) | **Segment exhaustion** — 33 %/100 %, 67 swapfiles, 20 GB free | `memory/compressor-segment-exhaustion-panic.md` |
| 2 | 07-31 11:46 | Panic (uptime 33.5 h) | **Unrelated** — spinlock timeout at 8,368 threads from a research subagent's unbounded `threadprice` benchmark; compressor 0 %/7 % | `panic-threadprice-2026-07-31.md` |
| 3 | 07-31 18:13 | Panic (uptime 6.5 h) | **Segment exhaustion** — 31 %/100 %; "iTerm2 ~500 GB" modal = coalition artifact; fleet 257→1,002 procs / 5.5→139.5 GiB in <12 min | `panic-iterm2-coalition-2026-07-31.md` |
| 4 | 08-05 00:18 | Panic (uptime 102.1 h) | **Segment exhaustion** — 31 %/100 %, 68 swapfiles; panicked thread IS `VM_compressor`; ignited by backgrounded `pnpm design:gate` → `next dev` cold compile; ~670-proc storm | `panic-compressor-2026-08-05.md` + panic file |
| — | 08-05 04:27 · 08-06 21:46 | Two near-misses (same boot) | Jetsam events: fleet in band 180, jetsam freed 15 MB; 68-proc node fan-out ≤10 min old (9.9 GB, coalition 2558 = launchd-origin); later the sustained-thrash profile (4.5 M compressions) | `JetsamEvent-*.ips`, decoded in this investigation (W2) |
| 5 | 08-09 03:39 | Panic (uptime 4.14 d) | **Segment exhaustion** — 32 %/100 %, 68 swapfiles; storm: 34→301→481→**700 node procs / 38.9 GB** (03:34→03:36), mostly `postcss.js` workers of `next-server (v16.2.6)` pid 36923; swap +457 MB/s; sentinel tripped ×3 with full-argv attribution, **actuator disarmed** | `panic-full-2026-08-09-034124`, `compressor-sentinel-snap.log` |
| 6 | 08-09 04:17 | Panic (uptime **38 min**) | **Segment exhaustion** — 32 %/100 %, 66 swapfiles; TWO waves on the fresh boot: 18→372 procs in 90 s at 04:07 (peaked 88.5 %, self-recovered to 3.4 % when the wave exited), second wave 619→736 procs / 44.7 GB at 04:13 → death 04:17; stackshot failed (240 B, err 52) | user-supplied panic text + sentinel JSONL rows t=174–176 |

Uptime-at-death is NOT the mechanism (55 h · 6.5 h · 102 h · 4.1 d · 38 min): the storm is an acute
event, not an accumulation. The Aug-5/Aug-9 "~4.2-day" pairing is coincidence of workload cadence
(both panics landed within 2 % of `PID_MAX` at a ~23.5 k-forks/day rate — a linear clock correlated
with uptime, flagged and not excluded, but the 38-minute panic #6 refutes any uptime-threshold story).

## 3. Attribution at every instrumented moment

| Moment | node fleet | claude sessions | kitty (anon / resident) | Verdict |
|---|---|---|---|---|
| Aug-5 00:18 panic | **141.9 GB / 724 procs (91 % of footprint)** | 2.0 GB / 6 | — / 1.39 GB | node fleet |
| Aug-5 04:27 jetsam | 14.6 GB / 87 (68 of them one 10-min fan-out) | 3.6 GB / 17 | 0.17 / 1.40 GB | node fleet |
| Aug-6 21:46 jetsam | 7.6 GB / 20 (four 1.0–1.4 GB, 6.5 h old) | 4.5 GB / 15 | 0.11 / 1.53 GB | node + claude thrash |
| Aug-9 03:36 (T-3 min) | **38.9 GB / 700** (postcss horde) | 4.0 GB / 12 | 0.13 GB RSS | node fleet |
| Aug-9 00:31 (early) | 9.5 GB / 34 (eslint 1.9 GB @127 % CPU, `next build` 3.5 GB pair) | — | — | dev-tooling singles |
| Aug-9 03:41 panic | **140.6 GB / 780 procs (91 %)** | 5.3 GB / 13 | — / 1.78 GB | node fleet |
| Aug-9 04:14 (boot #1) | **44.7 GB / 736** | 3.5 GB / 14 + 2.3 GB / 8 agents | 0.15 GB | node fleet |

(Panic-file `residentMemoryBytes` is footprint (resident+compressed) — validated within 2–4 %.
Storm members averaged **62–75 MB** on Aug-9 — below the actuator's stock 100 MB floor; see §6.)

## 4. The guard record — detection worked; authority was withheld

- `compressor-sentinel` (shipped 08-05 after panic #4, `13bfa557`): rate-keyed, Standard-band,
  10 s internal loop, snapshot names the cohort by full argv (the 08-07 `ba1caec5` fix). **91 trips
  Aug 6–9** (82 on Aug 7 alone — storms the box survived by luck). At panic #5 it tripped at 03:34,
  03:35, 03:36 — segments 4.97 %→87.29 % in five minutes — wrote three snapshots naming
  `next-server` pid 36923 and its postcss children, wrote its page file at 03:36, and printed
  `actuator: DISARMED (CC_SENTINEL_ACT=off) — detection only`. The box died at 03:39.
- **The SIGSTOP actuator is field-proven on this box.** On 08-06/07 a second, session-orphan
  sentinel instance ran ARMED and logged `actuator: SIGSTOPped 1 process(es)` against a real burst
  (`machine-lag-and-kitty-2026-08-06.md:434-441` — "two instances, two policies, one log").
- **The page channel structurally cannot act in time**: its only consumer is `autonomy-sweep`
  (300 s cadence, notification-only, 556 accumulated `.page` files). The whole fatal ramp fits
  inside one sweep interval. This is the `conclusion-must-reach-the-enforcing-store` class exactly:
  the sentinel's conclusion reached a *file*; the only enforcing store in reach was the kernel via
  SIGSTOP, and that path was the disarmed one.
- `devserver-gc` (hourly, dry-run): its 03:40 boot-#1 run logged **`reaped=1`** — it would have
  removed an ownerless dev server 27 minutes before the 04:07 storm, had `DEVGC_ACT=1` been set.
- Jetsam events, `capacity-alarm`, `cc-reaper`, `capacity-admit`: all either blind to this axis,
  band-starved during the event, fail-open, or self-defeating under load (inventory with citations:
  W7 §4; `lag-meltdown-2026-08-07.md:33`).

## 5. Why five "resolutions" did not stick (the operator's actual question)

1. **Detection ships; actuation waits for a decision that is never put.** Five investigations,
   five detectors, zero armed actuators. The arming was written down four times
   (plist comment; `31-compressor-sentinel-activate.sh:18-21,162`; remediation item #14 of 16 in
   `machine-lag-and-kitty-2026-08-06.md:564`; backlog `95e3a1909400` state=blocked) and asked
   exactly once — as a line item deep in a 645-line doc. No decision packet ever existed, so no
   close ever surfaced it as *the* blocking question. `panic-compressor-2026-08-05.md:207` had
   already written the indictment: *"Every fix filed after Jul-31 was unshipped."* Its item 2:
   *"An actuator, because detection alone saved nothing three times."* It then saved nothing a
   fourth and fifth time.
2. **The wrong suspect was visible and the right one was not.** macOS's dialogs name GUI apps and
   coalition owners — iTerm2, then kitty. Both were investigated (correctly exonerated each time),
   consuming two investigation cycles and one terminal migration whose actual justification was the
   *separate* WindowServer-freeze incident (#0).
3. **The record self-destructs and the index is over cap.** Only 2 of 5 panic files survive
   (Jul-30/31 rotated); a panic wiped `/tmp` twice — the second time (tonight, panic #6) it deleted
   six of this investigation's own delivered reports mid-session. `MEMORY.md` exceeds its loader
   cap, and the four crash memory files have **zero index hits** — a fresh session cannot find the
   incident memory at all (five backlog items about this are themselves blocked).
4. **The relief machinery is disabled by the condition it relieves.** Background-band samplers die
   ~3 min before every wedge; `cc-reaper`'s classify phase bound-fires under load and yields no
   candidates; `capacity-admit` fails open ("spawn UNGATED"). Guards for this event must be
   Standard-band, rate-keyed, and self-actuating — which is precisely the sentinel's design.

## 6. What changed tonight (landed with this doc)

1. **The actuator is ARMED** — operator authorization given in-session ("arm it", 2026-08-09
   ~04:2x, after panics #5 and #6). Live: `~/Library/LaunchAgents/com.claude.compressor-sentinel.plist`
   wrapper now exports `CC_SENTINEL_ACT=stop`; job reloaded (bootout→bootstrap); **verified by the
   loaded job definition** (`launchctl print` shows the exports in ProgramArguments; exec preserves
   env). Mirrored in-repo in `launchd/com.claude.compressor-sentinel.plist` (this commit).
2. **Cohort tuned to the measured storm shape**: `CC_SENTINEL_ACT_RSS_KB=40960` (storm members
   averaged 62–75 MB — the stock 100 MB floor would have spared most of the horde) and
   `CC_SENTINEL_ACT_CAP=400` (waves measured at 372–736 members; 200/trip covers half a wave per
   60 s cooldown). Values validated against the script's env seams (`--once` clean).
3. **This document** — the cross-event synthesis, so the next session starts from the conclusion,
   not from the dialog's decoy.

SIGSTOP does not free memory — it freezes *demand* (a stopped horde stops dirtying), which is
sufficient at a 15–20 % trip point and is reversible/lossless (`SIGCONT`). The cohort test is comm
`^node`, newest-first, never claude/mcp-shaped, never SIGKILL.

## 7. Remaining work (filed, not prosed)

| Item | Why | Where filed |
|---|---|---|
| **Arm `devserver-gc`** (`DEVGC_ACT=1`) | Removes ownerless `next dev` spawners between storms; would have reaped one at 03:40 tonight; dry-run log is clean (keeps live-owner servers) | backlog `898f8eafb809` (pre-existing) — recommendation upgraded by tonight's evidence |
| **Sentinel parent-breaker** — **DELIVERED**, see §7-bis | The spawner (`next-server`, comm ≠ `^node`) is outside the cohort and keeps minting between trips; when the frozen cohort shares one non-claude parent, SIGSTOP the parent too | backlog `55e09eef8d38` — closed |
| **Next.js postcss worker storm — remedy is a CONFIG FLAG, not an upgrade** (W11, delivered) | **No released Next fixes it**: `process_pool/mod.rs` byte-identical v16.2.6↔v16.2.12 (sha1 `4ae43bcf`), v16.3.0 adds diagnostics only; upstream #95108 (exact symptom match) was bot-auto-closed 30 s after filing, untriaged. Source-level mechanism: bootup semaphore gains +1 permanent permit per completed boot; scheduler spawns fresh with ZERO delay whenever `queued_tasks` spikes (mass invalidation from fleet edits); idle heap unbounded; the only reaper fires after whole-app module-graph COMPLETION, which continuous edits prevent. Fix shipped in the installed 16.2.6: `experimental.turbopackPluginRuntimeStrategy: 'workerThreads'` in reso's next.config — structurally removes the child processes AND the `fork()` abort (`node-2026-08-09-041046.ips`: next-swc aborting in `_malloc_fork_parent` at 04:10:46 — which is why wave 1 "self-recovered": the spawner died mid-fork). Known bounded risk: pre-#96592 (unreleased), a failing plugin can leak worker THREADS — one V8 heap, not 700 PIDs. Also worth filing a reproduction upstream — this machine's evidence exceeds the original report's. | reso task (this board) updated with the exact edit; execution via reso's own rails per cross-repo policy |
| **`memorystatus_control` per-pid memlimit lever** | The one kernel-enforced per-process cap available on macOS (root; phys_footprint ledger); never built | W7 §4 finding — backlog |
| **MEMORY.md over-cap repair** | The crash memories are unindexed; the loader drops the tail | pre-existing blocked items (`150c50055e1c` et al.) |
| kitty IOSurface churn test + `close_on_child_death` | ~1 GB non-purgeable GPU pool at 24 panes, growth-vs-plateau undetermined; dead panes retain surfaces (secondary, non-causal) | task #90 (in progress) + W4 §Open |

## 7-bis. The parent-breaker, as built (`scripts/compressor-sentinel.sh`)

Delivered against the §7 row. It reaches the spawner without widening the cohort rule, which stays
deliberately under-inclusive: **after the burst cohort is selected, every eligible parent owning
≥ `CC_SENTINEL_ACT_PARENT_MIN` (3) of it is SIGSTOPped, biggest first, at most
`CC_SENTINEL_ACT_PARENT_CAP` (4) per trip.** Three decisions in it are not what the filed sketch
implied, and each is the reason it can fire at all:

- **A count, not unanimity.** "The cohort shares one non-claude parent" reads naturally as *all
  children agree*, and that rule would have retired its own main path: a real cohort picks up strays
  — a worker from another worktree, a second server — and one stray vetoes the break forever. Per
  parent and ranked also answers the two-`next dev` case, which unanimity answers with silence while
  both keep minting.
- **The parent is stopped FIRST, then the children.** Freezing up to 400 children is 400 `kill(2)`
  calls; a spawner left running through that window mints processes that are invisible to this trip
  (they postdate the `ps` read) and survive into the next 60 s cooldown. Parent-first makes the
  cohort a closed set. Both selections read ONE `ps -axwwo pid=,ppid=,rss=,comm=,args=` for the same
  reason — two reads seconds apart during a 300-in-90-s churn can attribute a child to a recycled pid.
- **It rides `CC_SENTINEL_ACT=stop` as an OPT-OUT (`CC_SENTINEL_ACT_PARENT=off`), not a second arm.**
  A separately-defaulted-off flag would have shipped inert on the one box it was written for — the
  live job's arming export is inside the plist wrapper, and nothing would have said so: the trip
  snapshot would look exactly as it does today. Every armed trip now prints a parent-break verdict,
  *including the negative one*, so "found none" and "not wired" are different lines in the log.

Five exclusions, each for a distinct failure: **pid ≤ 1** (launchd — and the bucket the kernel
reparents an *already-exited* spawner's children into, i.e. the one guaranteed to clear any
threshold); **the daemon and its launcher**; **claude/claude.exe by comm and anything claude/mcp-shaped
by argv** (SIGSTOP is only reversible while something survives to send `SIGCONT`, and that something
is the operator's session); **a parent already in the cohort** (one process, one signal — otherwise
the log reports two spawners stopped over one pid); **a parent with no row in this table** (exited
between spawning and the read — printing it would fabricate a comm).

Proof: `tests/compressor-sentinel.bats` §5b — 11 cases over the pure selector, every absence
assertion paired with a positive control, plus an end-to-end daemon run that drives ps-routing →
cohort → attribution → kill attempt → verdict against impossible pids (`999xxx`, above macOS
`PID_MAX`), so the chain is proven without signalling anything on this machine. §5's cohort cases
gained a ppid column and one new per-site mutant (`RSS is read from the RSS column, never from the
ppid beside it`) — an off-by-one there would have re-admitted the whole fleet silently.

## 8. Acceptance test (the difference between "armed" and "verified")

A bounded live fire-drill, runnable any quiet moment: balloon a decoy `node` process (comm `node`,
>40 MB, dirtying fast) until the live sentinel trips, and confirm the snap log prints
`actuator: SIGSTOPped …` naming the decoy and the decoy's state reads `T`; then `SIGCONT`, kill,
and watch segments drain. Manual abort bound: kill the decoy at 30 % segments regardless — the
drill must not depend on the mechanism under test. (The 08-06 orphan-instance SIGSTOP already
demonstrates the path end-to-end; the drill re-proves it with tonight's tuned floor/cap.)

**Drill attempt 2026-08-09 04:50 — clean no-trip, verification stands on three other legs.**
`memory_pressure -S -l critical` + an 80 MB decoy ran 180 s without moving the compressor
(segments held 0.00 % throughout; the simulator's allocation never exceeded free RAM on the
post-reboot box, and macOS compresses only under genuine free-page exhaustion — synthesizing
segment pressure cheaply is not possible without a ~30-40 GB dirty ballooner). Aborted clean at
the time bound; decoy released and killed. The armed state therefore rests on: (1) the loaded
job definition carries the exports (`launchctl print` ProgramArguments; exec preserves env),
(2) the `tests/compressor-sentinel.bats` case named *"CC_SENTINEL_ACT=stop reaches the actuator
branch"* proves the branch is wired (named, not line-numbered: a line number in a growing suite
points at whatever moved into it), (3) the 08-06 field SIGSTOP of a real burst by the orphan armed
instance. The standing observable: the next genuine trip's snap line must read
`actuator: SIGSTOPped N process(es)` — any `actuator: DISARMED` line after 2026-08-09 04:36 PDT is a
regression to escalate. **Second observable, added with §7-bis:** the same trip must also carry an
`actuator: parent-break …` line. Its absence means the live daemon is still running pre-parent-breaker
bytes (it `exec`s the script once and holds it; new bytes reach it only on restart), not that no
spawner was found — "found none" prints its own line.

## 9. Residuals (named, unresolved, honest)

- ~~What exactly spawns 300+ postcss workers in 90 s~~ **RESOLVED by W11 at source level** (see §7):
  queue-spike → zero-delay spawn preference + monotonically widening bootup semaphore + a reaper
  gated on a graph completion that never comes. The Aug-2 25-crash node burst is also resolved:
  an **unrelated** third-party napi addon SIGSEGV (`index.node`, uuid `15297104…`), not postcss.
- The 08-09 00:38 triple-SIGTERM (`session-sigterm-forensics-2026-08-09.md`) remains unlinked to
  the panics — open, per its own doc.
- W10 (hostile-review alternates axis) was killed by panic #6 before delivering; its named
  candidates were independently measured minor at every instrumented moment (mds_stores 0.53–0.75 GB,
  Dia flat 0.49 GB, WindowServer flat 1.55–1.78 GB), but its `.diag` resource-report reads and
  disk/SMART checks were not recovered.
- The pid-wrap co-factor (both 4-day panics within 2 % of PID_MAX) — flagged by W1, refuted as a
  *threshold* by panic #6, not further investigated.
