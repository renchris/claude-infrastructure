# Axis L (red-team): "RAM total binds at ~15 sessions" — REFUTED. What actually binds, ranked, with evidence

**Date:** 2026-08-10 00:04–00:45 PDT · read-only · all numbers measured this session or cited to a named doc/file
**Verdict in one line:** RAM total has never been the binding constraint — the box has died 5× of a
STRUCTURE limit (VM-compressor segment table, exhausted at 28–33% packing with 20GB free and
`memoryPressure=false`), it *feels* limited by ACTIVE-session CPU load (~4–8 active, not 15
resident), and it *refuses* first on self-imposed caps (KMAX=32, quota ~~≈3.9~~ **6.2–11.0**
sustained-active — corrected 2026-08-24, `../scaling-bottlenecks-2026-08-09.md` §2a).
Live control at this instant: **14–15 sessions + a 15-agent research wave = load 100.77 on 10
cores while memory idles** (segments 3.3%, swap 0, 10.4GB free).

---

## 1 · Panic forensics (brief §4a) — what actually died, per report, verified by content this session

On-disk reports read directly (not recalled) from `/Library/Logs/DiagnosticReports/`:

| Report | Panic string (read this session) | What died | Why |
|---|---|---|---|
| `panic-full-2026-08-09-034124.0002.panic` | `watchdog timeout: no checkins from watchdogd in 91 seconds` · **"Compressor Info: 32% of compressed pages limit (OK) and 100% of segments limit (BAD) with 68 swapfiles and OK swap space"** | kernel_task (738 thr) | segment exhaustion; panic #5 |
| `panic-base+socd-2026-08-09-041859.000.panic` | same class, 94s, **32%/100%, 66 swapfiles**; only **210 watchdog checkins** since enable ⇒ ~38 min after the 03:41 reboot — the **boot-resume respawn storm re-killed the box** | kernel_task (733 thr) | panic #6; stackshot failed (err 52, base+socd only) |
| `panic-full-2026-08-05-001952.0002.panic` | same class, 94s, **31%/100%, 68 swapfiles**; panicked thread IS `VM_compressor` (tid 2332) | kernel_task (739 thr) | panic #4 |
| `JetsamEvent-2026-08-06-214613.ips` | bug_type 298; killed **`knowledgeconstructiond` (15MB)** — reason `None` (idle-exit); largestProcess WindowServer; free 49,844 pages (0.76GB); zoneMap 2.21GB / cap 24.9GB (8.9%) | a 15MB Apple daemon | macOS's only reachable relief: the fleet sits in jetsam band 180, killed last |
| `JetsamEvent-2026-08-05-042748.ips` | (decoded by the prior wave, W2 — cited) 68-proc node fan-out ≤10 min old, 9.9GB | near-miss | same |

**Brief correction:** the brief says "FOUR watchdog kernel panics." The full ledger
(`crash-rootcause-2026-08-09.md` §2, cross-checked against on-disk files + wtmp claims in
`panic-compressor-2026-08-05.md` §8) is **8 events in 11 days**: **5 segment-exhaustion watchdog
panics** (Jul-30 02:18 · Jul-31 18:13 · Aug-5 00:18 · Aug-9 03:39 · Aug-9 04:17), 1 unrelated
spinlock panic (threadprice, 8,368 threads in one task — self-inflicted control), 2 jetsam
near-misses, 1 WindowServer freeze (distinct mode, no reboot). Only 3 panic files survive rotation.

**The killer signature, identical at all 5 deaths:** compressed-PAGES axis at 31–33% "OK" while
the SEGMENT axis reads 100% "BAD" ⇒ mean segment fill ~28–33%. The pool is provisioned for more
bytes than the box has RAM (limit 1,629,615 segments; `vm.compressor_segment_limit`, read live
this session) — **fully-packed segments cannot exhaust it; only fragmentation can**. Mechanism
kernel-source-verified in `panic-compressor-2026-08-05.md` §4a (xnu-11417.140.69: slot freed only
at `c_slots_used==0`; compaction refuses ≥90%-full pairs; kernel edge signal at 98% = 7.6s of
warning at observed ramp; `memoryPressure` stayed `false` to the end).

**Who allocates:** never claude sessions. At every instrumented death/near-miss the claude fleet
held **2.0–5.3GB across 6–17 sessions (1.4–3.7% of footprint)** while the node dev-tooling horde
held 38.9–141.9GB (up to 91–92%): `next-server (v16.2.6)` postcss workers (Aug-9: 18→372 procs
in 90s, 700 procs/38.9GB), `pnpm design:gate`→`next dev` cold compile (Aug-5: +670 procs/12min),
esbuild fan-outs, GB-scale tsc/eslint singles (`crash-rootcause-2026-08-09.md` §3).

## 2 · Ranked binding constraints (brief §4d) — what binds first, with evidence · confidence

| # | Constraint | Binds at | Evidence | Confidence |
|---|---|---|---|---|
| **1** | **ACTIVE-session CPU load** (runnable-thread oversubscription; the *felt* "15-session" ceiling) | **~4–8 concurrently-ACTIVE** sessions | 2.5–5 runnable threads per active session; 127/127 historic gate refusals were load, 0 memory (`scaling-bottlenecks-2026-08-09.md` §2 r2, axes 09/07). **Live this session: load 100.77/95.09/70.44 on 10 cores, 58 running / 5,239 threads, 2 stuck — while segments sit at 3.3% and swap 0.** The felt lag also has a non-CPU term: turn-end Stop-hook lag 3.7s p50 / 7.7s p90, 92% one `cc-backlog` call (axis 12) | **High** (measured + live-replicated) |
| **2** | **VM-compressor SEGMENT TABLE under node dev-tooling bursts** (the killer) | minutes after any ignition, at ANY session count (deaths at 5–17 sessions) | 5/5 panics with the 31–33%/100% signature (3 verified on-disk §1); ramp 4.97%→87.29% in 5 min at panic #5; **tonight 00:09:07: live trip at 3,242 seg/s / 192MB/s** (`compressor-sentinel.stderr.log`, read this session) | **High** (primary evidence, twice-measured mechanism) |
| **3** | **Fleet-self-imposed caps** | **33rd session refused** (router KMAX=8×4 accounts); ~~**~3.9 sustained-active**~~ → **6.2–11.0 sustained-active** (quota, 4 Max accounts) | proven on the shipped binary, `handoff-fire.sh:5266` rc2→HALT; quota arithmetic axis 07 (`scaling-bottlenecks-2026-08-09.md` §2 r3–4) — **the 3.9 was corrected 2026-08-24 (§2a): it was priced with a cache-read-68% composition the meter refutes. This does not change rank 3's standing, but it does move the quota sub-term from *below* row 1's ~4–8 load ceiling to *overlapping* it, so load binds first more often than this table implied.** | High (cited; not re-proven here) |
| **4** | **Exec-path serialization — ARM 2** (launchd/xpcproxy/tccd/syspolicyd; desktop FREEZE, no panic) | storms of hook/tool/MCP execs; WindowServer turnstile-blocked on tccd | Jul-31 18:10 .spin (40s dead); 154 stuck xpcproxy stubs at Aug-5 death; syspolicyd 55,699 CPU-s diag; launchd↔jetsam livelock 221 spawns/s (`panic-compressor-2026-08-05.md` §4b). **NO guard exists for this arm** | Medium-high (documented; unguarded; not re-measured tonight) |
| **5** | **RAM total** — real but FAR out | **N≈103–132 RESIDENT** sessions (150+ with MCP consolidation) | arrival cost 340MB/session + ~507MB MCP children (axes 01/08/09); **live now: RSS-sum upper bound 47.3GB, 10.4GB free pages, swap 0.00M total at 14–15 sessions + 15-agent wave**; box SURVIVED a 170.85GiB/515-proc coalition (Aug-2) and DIED at 146.72GiB — footprint does not separate fatal from survived | **High** |
| — | **NOT binding at 15 or 25** (each measured or cited) | — | **ptys 51 in use / 511 `kern.tty.ptmx_max` (10%; ~90 at 25 sessions = 17%)** · procs 1,201 / 16,000 `kern.maxproc` (peak-storm ~2,300 ≈ 14%) · threads 5,239 (storm max decoded 9,338; the 8,368-thread kill was ONE task's spinlock, a different class) · fd (axis 08 not-a-wall; per-proc cap 245,760; direct sum skipped — `lsof` at 1,200 procs is minutes-expensive under load 100) · **disk 5,017GB free** (68 swapfiles ≈ 1.4% of it; "OK swap space" in every panic) · zone map 8.9% · pid-wrap REFUTED (wrap every ~108s live, axis 08) · render (idle panes 0.001 cores) | High |

## 3 · Candidate-constraint arithmetic at 15 and 25 sessions (brief §4b)

| Term | @15 sessions (≈now, measured) | @25 sessions (extrapolated) | Ceiling | Verdict |
|---|---|---|---|---|
| Session RSS (main+helpers, 340MB) + MCP where used (+507MB) | 5.1–12.7GB | 8.5–21.2GB | ~38–42GB usable | not binding |
| Whole-box RSS-sum incl. browsers (7.7GB) | 47.3GB nominal (double-counts; free 10.4GB, swap 0) | ~55–60GB nominal, still swap-light | 64GB + compressor | not binding steady-state |
| Compressor segments **steady-state** | **3.3%** (212,905 comp. pages ÷4 + swap 0 ÷64KiB) | ~5–6% | 1,629,615 | not binding — **residency does not spend segments** (34.5GiB anon = 0.22% of limit, axis 05) |
| Compressor segments **under one ignition** | 13.18%→ trip in min (tonight); 87% in 5 min (Aug-9) | same — ignition-count scales with sessions, amplitude does NOT | 100% = watchdog panic | **binds in minutes, any N** |
| CPU runnable threads | load 100 at ~9–15 active (this instant) | linear in ACTIVE only | 10 cores (load-20 gate) | **binds at ~4–8 active** |
| ptys / procs / threads / fd / disk / zonemap | 10% / 7.5% / 32%¹ / n.m. / <1% / 8.9% | ≤17% / ≤14% / — / — / — / — | see §2 | not binding |

¹ threads vs `kern.num_taskthreads` 16,384 is a per-task bound, not system-wide; the system total is unbounded in practice at this scale.

## 4 · The reactive layer (brief §4c): did it fire and fail to prevent? YES historically — and it is FIXED as of tonight, verified live

- **Detection always worked; authority was withheld.** 91 sentinel trips Aug 6–9. Before panic #5
  it tripped at 03:34/03:35/03:36 with full-argv attribution of the postcss horde and printed
  `actuator: DISARMED (CC_SENTINEL_ACT=off) — detection only`; box died 03:39
  (`crash-rootcause-2026-08-09.md` §4). Five investigations shipped five detectors and zero armed
  actuators — the operator arming question was buried in a 645-line doc, never a decision packet
  (§5.1). capacity-alarm missed a whole event *inside one 600s interval* (green→dead, 2026-07-31)
  and was band-starved 6h24m post-reboot at ProcessType Background (its plist header, read this
  session) — the guard for a starvation event must not live in the band the event starves first.
- **Armed 2026-08-09 04:36 after panics #5/#6** (SIGSTOP, floor 40MB tuned to the measured 62–75MB
  storm members, cap 400, parent-breaker `cb21783b` 16:44). Yesterday's wave found it **running
  stale 08-07 bytes** (its top crash-side finding).
- **Verified end-to-end THIS SESSION, on a real event:** pid 64116 restarted **2026-08-10
  00:04:18** (ps lstart), holding fd 255 on inode 427219920 = the current checkout script (lsof;
  symlink target matches `ls -iL`). At **00:09:07** a genuine trip (3,242 seg/s) printed BOTH
  standing observables from `crash-rootcause-2026-08-09.md` §8: `actuator: SIGSTOPped 1 process(es)
  (cap 400, floor 40960 kB)` **and** `actuator: parent-break none — no eligible parent owns >= 3
  of the 1 selected burst procs` (snap log :33644-33645). Grep of the full snap log: **zero
  DISARMED lines after the 04:36 arming** (last: 2026-08-09T11:14:03Z = 04:14 PDT, pre-arming,
  3 min before panic #6). Segments drained 13.18%→3.3%; state-T census now EMPTY (nothing left frozen).
- **The victim names the margin problem live:** the frozen proc was `tsc --noEmit -p
  tsconfig.json`, 1.73GB, 117% CPU — **legitimate work**, exactly the false-positive class
  yesterday's wave warned about ("ordinary jest/pnpm/tsc enters the cohort... no SIGCONT sender
  exists anywhere in the tree"). The freeze was rate-correct (192MB/s compression is a real ramp)
  and cost one typecheck. The P1 SIGCONT/unfreeze arm and the 91-snapshot offline replay
  (false-positive casualty count) are the named preconditions before widening — both still open.
- **Still fail-green, verified tonight:** `capacity-ramp.sh` `seg_pct()` returns `.pct // 0` on a
  dead/absent sentinel JSONL — a dead sentinel reads as 0% = healthy (script read this session;
  yesterday's P0-6 five-line fix NOT landed).
- **Armed since yesterday's wave:** devserver-gc `DEVGC_ACT=1` (commits `94563cda`/`8c9a3afd`,
  operator-ratified packet `99637eaee7b9`) — the between-storms spawner reaper is now live too.

## 5 · What "session-count ceiling ~15" misattributes (brief §4d)

1. **An acute-burst mechanism to steady-state residency.** Deaths at 5, 6, 13, 14, 17 sessions;
   survival at higher footprint than the fatal events. Sessions are 1.4–3.7% of death-time
   footprint; node dev-tooling is 91–92%.
2. **A structure limit to a byte limit.** 20GB free + `memoryPressure=false` + pages-axis "OK" at
   every death. Counting GB predicts nothing; segment-consumption RATE predicts everything
   (491MiB/s with 0.68% net retention = the fatal shape).
3. **The felt lag to memory.** The daily "box lags at ~15" is ACTIVE-load (r1) + a 3.7s Stop-hook
   tail — 0 of 127 gate refusals ever came from memory; all 91 whole-machine stalls in 47,108
   sentinel samples were segment ramps (axis 12) — lag is the storm's first symptom, not RAM filling.
4. **Self-imposed refusals for kernel walls.** KMAX refuses the 33rd session; quota sustains ~3.9
   active — both fire long before RAM at current per-session cost.
5. **The wrong victim.** GUI dialogs (kitty "4.73TB", iTerm2 "~500GB") attribute coalition/VSZ to
   the visible terminal — two investigation cycles + one terminal migration spent on decoys
   (`crash-rootcause-2026-08-09.md` §1).

## 6 · Cheapest instrumentation to catch the NEXT wall event (brief §4e)

**It exists and caught one tonight.** `com.claude.compressor-sentinel` (Standard-band, KeepAlive,
10s cadence, counter-sysctls only, full-argv trip snapshots, SIGSTOP+parent-break armed) is the
instrument; tonight's trip is the proof-of-life. The cheapest REMAINING gaps, all extensions of
existing daemons, ranked by cost:

| Rank | Gap | Fix | Extends |
|---|---|---|---|
| 1 | Dead sentinel reads healthy in ramp aborts | the 5-line freshness check (mtime vs now) in `capacity-ramp.sh breach()` — **verified still absent tonight** | `capacity-ramp.sh` (P0-6, already specified) |
| 2 | **ARM 2 (exec-path freeze) has NO guard** | new trip reason `why=exec` in the SAME 6th-tick `ps -axwwo` census the sentinel already pays for: xpcproxy row-count + Δ syspolicyd/tccd CPU. ~10 lines, zero new forks | `com.claude.compressor-sentinel` |
| 3 | **claude.exe 4–41GB self-bursts are invisible to the armed guard** — the actuator's own exclusion list (correctly) exempts claude-shaped procs, so the one process class with measured 54 multi-GB bursts/11d has no watcher | page-only (never stop) footprint row per claude.exe in the same census tick; captures argv at burst start (the axis-01 trigger is still unknown for want of exactly this) | `com.claude.compressor-sentinel` |
| 4 | Frozen-legit-work has no release path | SIGCONT arm + the 91-snapshot offline replay before any wider arming | sentinel (P1, filed) |

Anti-recommendation, measured tonight: `log show` over 8h with a narrow predicate **did not return
within 120s on a healthy box at load 100** (backgrounded, still empty at report time) — unified-log
mining is a post-mortem tool, not a wall-event catcher; anything slower than the sentinel's 10s
counter-sysctl tick fails exactly when needed (the zprint lesson, re-demonstrated).

## 7 · Adversarial self-pass (gaps I went back for)

- **"Is the pre-fatal configuration live right now?" YES — cold swapper.** Swapins/Swapouts read
  **0 since boot (~44h)**; swap store 0.00M total. §6.3 of the Aug-5 doc: burst-into-cold-swapper
  is the discriminator that separated all fatal events from the survived-at-170GiB one. The box
  sits in that state whenever it has been healthy for hours — the sentinel is the ONLY compensating
  control. This is why detection-cadence and arming are not optional hardening; they are the wall.
- **"Did the actuator maybe fire on a horde and I'm over-reading one SIGSTOP?"** No — snap shows
  cohort of exactly 1 (a single fat tsc), parent-break correctly declined (<3 children). Small
  event, correct behavior, AND a live false-positive-class datum. Both facts reported.
- **"fd totals unmeasured."** Named as skipped-by-cost (lsof at 1,200 procs under load 100);
  covered by axis 08's not-a-wall verdict + per-proc cap 245,760. If a future wall smells like fd,
  `kern.maxfiles` accounting must be added to the sentinel census — same tick, one sysctl.
- **"Six panics or five?"** The sentinel plist says "#5 (03:39) and #6 (04:17)"; the ledger's #2
  (threadprice spinlock) is a panic but NOT the segment class and NOT watchdog-timeout. Watchdog
  segment-class = 5. Brief's "four" undercounts by one; nothing turns on it.
- **What I could not check read-only:** whether the Aug-10 00:09 trip's igniter (which session ran
  that tsc) traces to this very research wave's own workers — the snap's top-30 argv would say, but
  full attribution of MY OWN wave is axis-N territory (orchestration-econ), left to that worker.

## Sample 6-line row (structure contract)

**Finding:** the armed SIGSTOP actuator is live on current bytes and fired correctly on a real event tonight
**Evidence:** snap log :33644-45 `SIGSTOPped 1` + `parent-break none` at 2026-08-10T07:09:07Z; ps lstart 00:04:18; lsof fd 255 → inode 427219920 = checkout script; zero post-arming DISARMED lines
**Cost now:** one legit 1.73GB `tsc --noEmit` frozen per trip-class event; no SIGCONT path; nothing currently frozen
**Re-architecture:** SIGCONT/unfreeze arm + 91-snapshot offline replay to bound false-positive casualties before widening; then `why=exec` + claude.exe watch rows in the same tick
**Sizing:** ~10–40 lines each, zero new processes, zero new forks (rides existing census tick) · effort S · risk low (page-only rows) / medium (SIGCONT arm)
**Existing mechanism:** `com.claude.compressor-sentinel` — EXTEND, never a new daemon (capacity-alarm's Background-band history is the cautionary control)

## Addendum — the backgrounded log query returned (00:40 PDT)

The 8h `log show` (memorystatus/compressor_exhausted/System-is-unhealthy predicate) completed
after ~3 min wall time: **zero kernel memorystatus kills, zero unhealthy/exhausted events** —
only benign runningboardd `MEMORYSTATUS_CMD_CONVERT_MEMLIMIT_MB` EINVAL chatter. The written
prediction (§6 anti-recommendation) held, and the finding strengthens §4: tonight's 00:09 ramp
was resolved by the sentinel's SIGSTOP entirely below the kernel's own action threshold — the
kernel never had to act. The reactive layer's first armed engagement was a clean intercept.
