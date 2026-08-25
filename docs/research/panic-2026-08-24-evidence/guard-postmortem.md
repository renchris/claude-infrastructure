# Panic #5 (2026-08-24 20:01:23 PDT) — the guard axis: it was running, it fired, it acted, and its own release policy resumed the storm

**Axis:** the shipped compressor-segment guard — find it, and explain why panic #5 happened anyway.
**Verdict, answer-first:** the guard (`scripts/compressor-sentinel.sh`, launchd `com.claude.compressor-sentinel`) was running with a healthy 10 s tick through the whole of Aug 24, detected the fatal storm at 19:50:03 PDT with the box at 36.75 % of the segment limit, and SIGSTOPped 308 processes including both `next-server (v16.2.6)` spawners — then its own unfreeze arm (shipped Aug 19, commit `5305ee34c`) **SIGCONT'd the spawners and cohort mid-incident** because its "breach is over" test is the same rate-gated trip predicate, which reads *clear* during a one-tick rate lull even at 72 % of the death ceiling. The resumed storm grew from 427 to 672 node processes in the next minute; the final trip at 19:58:54 PDT (82.68 %) wrote its snapshot but no actuator output ever reached disk; the sentinel's log goes dark 149 s before the panic. Underneath that proximate failure: SIGSTOP can only stop the *ramp*, never reclaim the *level* (no kill path exists by design), and the structural remedy named in the Aug 9 postmortem — Next.js `turbopackPluginRuntimeStrategy: 'workerThreads'` — was never applied to reso's `next.config.js` (verified absent today), so the identical v16.2.6 worker-pool generator was still live.

Timestamps below: sentinel logs are UTC (Z); PDT = UTC−7. Panic 2026-08-24 20:01:23 PDT = 2026-08-25 03:01:23 Z.

---

## 1. The guard, as shipped

**File:** `~/Development/claude-infrastructure/scripts/compressor-sentinel.sh` (1,316 lines; live via per-file symlink at `~/.claude/scripts/compressor-sentinel.sh`).
**Runner:** launchd `com.claude.compressor-sentinel` (`~/Library/LaunchAgents/com.claude.compressor-sentinel.plist`, mtime Aug 9 16:17; repo copy `launchd/`). `RunAtLoad` + `KeepAlive`, **no ProcessType** (deliberately Standard band — the Background/Adaptive bands are starved by exactly this event class), internal loop, no StartInterval.

| Property | Value |
|---|---|
| **Samples** (per 10 s tick) | `vm_stat` "Pages occupied by compressor" (÷ derived pages-per-segment = 4 at 16 KiB pages) → in-core segments; `vm.swapusage used ÷ 65536` → swapped segments (exact); `vm.compressor_segment_limit` (= 1,629,615 on this box); `vm.compressor_bytes_used`; diagnostic: input/compressed bytes, WK/LZ4 failures; node census (count/orphans/RSS + pid list) every 6th tick |
| **Trip predicate** (`classify_breach`) | (level > 15 % of limit **AND** rate > 600 seg/s) OR compressor-bytes rate > 64 MB/s OR swap rate > 102.4 MB/s — all rates normalised by *measured* elapsed; **2 consecutive breach ticks** required; **60 s cooldown** after a trip |
| **Action** (armed) | SIGSTOP the burst cohort: comm `^node`, RSS > 40 MB (`CC_SENTINEL_ACT_RSS_KB=40960`), not in previous census, cap 400/trip (`CC_SENTINEL_ACT_CAP=400`); **parent-breaker first**: any non-protected parent owning ≥ 3 of the cohort (cap 4). Never claude/claude.exe/mcp-shaped, never pid ≤ 1, **never SIGKILL** (deliberate: "we are the only actor, so we must be the reversible one") |
| **Unfreeze arm** (added Aug 19) | every tick: release frozen pids — mode `clear` (no trip this tick AND held ≥ 60 s), `ceiling` (held ≥ 600 s, even in breach), `exit` (daemon TERM/INT). (pid,lstart)-guarded |
| **Armed since** | 2026-08-09 04:45 (`bed531d72`) — plist wrapper exports `CC_SENTINEL_ACT=stop` (operator "arm it", after the two Aug 9 panics) |
| **Evidence stores** | `~/.claude/logs/compressor-sentinel.jsonl` (one row/tick), `…-snap.log` (trip snapshots: top-30 by RSS full-argv, by-executable totals, vm_stat, actuator verdicts), `…-frozen.tsv` (freeze ledger), page file, panic/freeze attribution at startup → `panic-attribution.jsonl` |

Ship lineage (git, `--follow`): `13bfa557d` 08-05 01:56 sentinel shipped (detection-only, ~26 h after panic #2) · `ba1caec57` 08-07 snapshot attribution fix · `bed531d72` 08-09 04:45 **actuator armed** + storm-shape tuning (40 MB floor, cap 400) · `cb21783b2` 08-09 16:40 parent-breaker · `77d33bdc0` 08-09 22:47 panic-attribution reader · `6dd3ea468` 08-11 01:33 **cohort-test fix** (until then the armed actuator could not name a single real node process — comm path parsing) · `95a3caf82` 08-13 freeze reader · `5305ee34c` 08-19 01:46 **unfreeze arm** ("59 one-way freezes across 109 trips" — the fix whose policy participated in this death).

## 2. Was it running on Aug 24? Yes — continuously, and it fired

- The daemon instance that died with the box started 2026-08-24T02:28:58Z (Aug 23 19:28 PDT; `"t":1` row) and ticked at ~10 s through to 03:01 Z Aug 25. Five KeepAlive restarts across Aug 23 (00:03, 09:20, 10:39, 21:10, 02:28 Z) — no coverage gap on Aug 24 itself. Post-reboot instance up at 03:05:13 Z (20:05 PDT).
- **At the 11:26 PDT JetsamEvent (18:26 Z):** rows read seg 73,186–73,286 = **4.49–4.50 %** of limit, negative rates, swap 3.7 GB, n = 15–19 node procs. A calm box on this axis — the sentinel correctly did not fire; whatever jetsam recorded at 11:26 (largestProcess WindowServer per the report header) was not a compressor-segment storm and is outside this guard's subject.
- The guard **worked repeatedly that same day**: 27 trips in the 27 h before death (Aug 23 17:00 PDT → Aug 24 19:58 PDT), including survived storms at 14:22, 15:03–15:11, and 17:26–17:27 PDT. Detection + actuation demonstrably broke earlier waves.

## 3. The fatal 11 minutes, tick by tick (all from `compressor-sentinel.jsonl` + `…-snap.log`)

| UTC (PDT−7) | seg % of 1,629,615 | node procs | Event |
|---|---|---|---|
| 02:49:22 (19:49) | 7.21 % | 17 | calm; swap 4.96 GB |
| 02:50:03 (19:50) | **36.75 %** (srate 17,190/s, swap 9.3 GB) | 166 | **TRIP 1** `seg+cbu+swap` → parent-break **SIGSTOP next-server pid 42897 (249 kids)** + SIGSTOP 249 workers; freeze debt 250 |
| 02:52:02 | 77.42 % (el = 121 s — tick stretched by actuator + storm) | 166 | swap 52.2 GB |
| 02:52:14 | 78.14 % | 166 | **TRIP 2** `seg` → re-freeze 42897 (57 more kids); debt 308 |
| ~02:52:3x–02:54 | (rates go negative as wave 1 collapses) | — | **mode=clear release begins: `SIGCONT pid=42897 held_s=116` + early cohort** (snap lines 590+); every release in the incident shows held_s 60–116, i.e. all `clear`-mode, none near the 600 s ceiling |
| 02:55:36 | **7.98 %** | 18 | wave 1's workers exited after resume; swap back to 5.4 GB. By the trip predicate the incident is "over" |
| 02:56:43 (19:56) | 43.66 % (srate 22,781/s) | 427 | **TRIP 3** `seg+cbu+swap` → parent-break **SIGSTOP next-server pid 39672 (58 kids)** + 58 workers |
| 02:57:54 | **71.81 %** — but srate **536.2 < 600**, crate 1.2 MB/s, wrate 37 MB/s → WHY empty | 427 | tick reads **clear** → **`SIGCONT pid=39672 held_s=68`** + 37 workers (held_s 60–61). The spawner resumes at 72 % of the death ceiling |
| 02:58:54 (19:58) | **82.68 %**, swap 57.4 GB, wrate 539 MB/s | **672** | **TRIP 4** `seg+swap` — snapshot written (death census: **node ×713 = 39.9 GB RSS**, claude ×15 = 2.7 GB, next-server 627 MB; vm_stat "Pages occupied by compressor: 1,610,733" ≈ the JetsamEvent's compressorSize 1,610,185), **but no SIGSTOP / actuator-summary lines follow — the actuator never completed (or its output died in page cache)** |
| 02:58:54 → 03:01:23 | — | — | **149 s of darkness** — last JSONL row; snap mtime 19:59; panic 20:01:23 PDT: "33 % of compressed pages limit (OK) and 100 % of segments limit (BAD) with 73 swapfiles" |

332 SIGCONT lines total in the fatal window's snap range. The storm's owners, from the trip snapshots' full-argv top-RSS: teammates `infra-nightly` and `reso-qa` of team `session-6ee7e044` (claude.exe agents, Opus 5), whose reso QA work drove two `next-server (v16.2.6)` instances that each minted worker hordes. (Which lane spawned them is another axis; note `com.reso.qa-nightly` is scheduled 04:17, not 19:50, and both reso plists were touched 19:52 mid-storm.)

## 4. Ranked reasons the guard failed (the suspects)

1. **Release-into-relapse: the Aug-19 unfreeze arm resumed the arsonists mid-incident.** "Clear" is defined as *no trip this tick*, and the trip's seg arm is level-AND-rate — so at 71.8 % level with srate 536/s (64 seg/s under the line) the incident read as over, and `SIGCONT` went to spawner 39672 after a 68 s hold (and to 42897 + cohort at held_s ≤ 116 earlier). HOLD_MIN=60 s was sized to the 60 s cooldown on the assumption "never resume into the ramp we just interrupted" — this ramp was an 11-minute multi-wave event. Every one of the 332 releases was clear-mode (held_s 60–116 « 600); n went 427→672 within a minute of the 39672 release; dead 3.5 min later. Before Aug 19 the freeze was one-way — in *this* storm, staying frozen would have held both spawners through the window.
2. **The actuator can stop the ramp but cannot reclaim the level — and nothing on the box can.** SIGSTOP freezes demand; the 57 GB already swapped and 402 K in-core segments stay owned by frozen/live processes, and swapout of already-compressed segments continued at 539 MB/s. The design deliberately forbids SIGKILL, macOS's own relief is structurally untrippable here (CONFIG_JETSAM off; `no_paging_space_action` needs one proc > 50 % of the compressor), and the fleet sits in jetsam band 180. So each wave *ratchets* the level; only worker exit returns segments — which is why wave 1's collapse (78 %→8 %) looked like recovery and why wave 2 started from a poisoned baseline.
3. **The shipped trip predicate is AND where the research prescribed OR.** `panic-compressor-2026-08-05.md` §7.7: "Trip on **level >15 % of limit OR rate >600 segments/s**". `classify_breach` ships the conjunction (justified in-file: level alone is a standing state, rate alone fires on benign builds). The conjunction is what manufactures "clear" ticks at 72–83 % level during rate lulls — gating re-trips *and* driving suspect 1's releases. An OR predicate would have kept WHY non-empty at every tick past 15 %, forcing `ceiling` (600 s) release mode throughout the incident.
4. **The named structural remedy never reached the enforcing store.** `crash-rootcause-2026-08-09.md` §7 (W11) identified the generator at source level — v16.2.6 turbopack `process_pool` with a widening bootup semaphore and zero-delay spawn — and named the fix: `experimental.turbopackPluginRuntimeStrategy: 'workerThreads'` in reso's next.config ("structurally removes the child processes"). **Verified today: no such key exists in `~/Development/reso-management-app/next.config.js`** (grep rc=1, repo-wide on next.config.*). The item was handed off cross-repo ("execution via reso's own rails") and task #151 ("Permanent fix: dev-worker memory storms") is still `in_progress` 15 days later. Same binary, same pool, 713 workers. This is the repo's own `conclusion-must-reach-the-enforcing-store` memory class, re-enacted.
5. **At the kill moment the actuator was too slow for the box it had to save.** Ticks stretched 10 s → 28/121/146 s under the storm (the trip-1 freeze of 249 procs makes 2 `ps` execs per `record_frozen`, ~2 min of work); trip 4 at 82.68 % wrote its snapshot (two full `ps` renders + vm_stat) with 4,096 free pages (67 MB) on the box, and no actuator line ever hit disk; the final 149 s produced no rows at all. The kernel's own edge leaves 7.6 s at ramp rate; from 83 % at 7.7 K seg/s the margin was ~36 s. Detection at 10 s cadence + 2-tick streak + snapshot-before-actuate spent the whole margin.
6. **Selection blind spots (minor, contributory).** The 40 MB RSS floor spares just-forked workers at the instant of the `ps` read (the horde's members grow after selection); "new since last census" is computed against a census up to 6 stretched ticks stale; and the claude/mcp exclusions (correct — reversibility requires a surviving operator) leave the 15-session claude fleet (2.7 GB) plus system daemons permanently outside the actuator's reach.

Not suspects: the guard being dead (refuted — continuous rows), band starvation of the sentinel itself pre-storm (Standard band held; only in-storm stretch), the 11:26 jetsam as a missed early warning on this axis (box at 4.5 %), PATH/sysctl readability (no SKIP gaps in the fatal window's rows).

## 5. Prior-panic lineage (what each concluded, what shipped)

| Panic | Postmortem | Conclusion | Remediation shipped |
|---|---|---|---|
| #1 Jul 30 02:18 (55 h up) | memory file + task #75/#76 | segment exhaustion, 33 %/100 %, 67 swapfiles | investigation only; "guard" task closed on the *sentinel's* later ship |
| (Jul 31 11:46) | `panic-threadprice-2026-07-31.md` | **unrelated** — spinlock at 8,368 threads from a research subagent's benchmark; "a probe that finds a limit by hitting it" | probe banned |
| (Jul 31 18:13) | `panic-iterm2-coalition-2026-07-31.md` | segment exhaustion; "iTerm2 500 GB" modal = coalition artifact | — |
| #2 Aug 5 00:18 (102 h up) | `panic-compressor-2026-08-05.md` (task #142) | 670-proc node storm into a cold swapper; **every existing rung read healthy at death**; kernel relief untrippable | → sentinel shipped 08-05 (detection-only); §7's ranked list: actuator (item 2), pipeline leash (3), per-pid `memorystatus_control` memlimit (6 — **never built**), the §7.7 sensor recipe |
| #3 Aug 9 03:39 + #4 Aug 9 04:17 (38 min up) | `crash-rootcause-2026-08-09.md` (task #151) | "detection worked; **authority was withheld**" — sentinel tripped ×3 naming the spawner, printed `actuator: DISARMED`; five detectors, zero armed actuators; arming asked once, deep in a 645-line doc | → actuator ARMED 08-09 04:45 + cohort tuned; parent-breaker same day; devserver-gc armed 08-10; Next.js config fix **named but delegated cross-repo, never applied** |
| (Aug 13 21:22 freeze) | `freeze-2026-08-13.md` | different class — update-prepare wedge, not a storm (segments 13–15 %) | freeze-attribution reader added to sentinel startup |
| **#5 Aug 24 20:01** | this doc (task #181) | armed guard fired 4×, froze 308, **released them mid-storm**, died in the dark 149 s later | — |

Pattern across the lineage: each death fixed the previous death's precise gap (no sensor → sensor; wrong band → Standard band; disarmed → armed; horde-only → parent-breaker; blind cohort → fixed comm parse; one-way freeze → release arm) — and each fix's own simplification became the next death's mechanism. The release arm was itself the correct fix for a real defect (59 stranded freezes); its "clear" test just inherited the trip predicate's rate blindness.

## 6. The other capacity/memory gates, and why none covered this

| Gate | Keys on | Why not this event |
|---|---|---|
| `scripts/capacity-alarm.sh` (launchd Adaptive, 60 s) | 7 rungs: swap *growth*, reclaimable headroom, kernel pressure ≥2/4, + scheduler-axis report | **alarm, never a gate** — by design refuses to act; Adaptive band; its own doc concedes the memory rungs read healthy in storm deaths |
| `capacity_gate()` (handoff-fire) + `scripts/lib/capacity-admit.sh` | load/core ≤ 2.0, headroom ≥ 4 GB at **session-spawn admission**; bounded refusals (budget-expired → ADMIT + page, i.e. fail-open) | gates pane/session *fires*; the storm was `next-server` forking *inside* an admitted QA session — no admission point exists on that path |
| `com.claude.devserver-gc` (hourly :40, armed 08-10) | ownerless / idle `next dev` servers | fatal spawners had **live owners** (the QA team session) → structurally exempt; hourly cadence vs an 11-minute storm |
| `com.claude.browser-spin-guard` | browser CPU spin | different axis |
| `cc-reaper` / `cc-eligible` / `cc-ignition-gate` | session lifecycle, quota | not memory; reaper's classify bound-fires under load (per Aug-9 doc) |
| per-pid `memorystatus_control` memlimit (Aug-5 §7.6, "the verified lever") | kernel-enforced phys_footprint cap — exactly the segment-consuming quantity, enforced with no live daemon needed | **never built** (backlogged Aug 5, still absent) — the only mechanism in the inventory that acts when the userland guard is starved |
| QA/build pipeline leash (Aug-5 §7.3) | process-group memory ceiling on `design:gate`/build/test lanes | not present; `com.reso.qa-nightly` launches bare `tsx` with no leash |

## 7. Secondary instrument findings (this session, incidental)

- **The panic-attribution arm missed panic #5.** At 20:05 the fresh sentinel logged `panic-scan: already recorded (.contents.panic)`: `/Library/Logs/DiagnosticReports/` holds both `.contents.panic` (15 KB, mtime 20:04, basename already in the ledger from Aug 18) and the real `panic-base+socd-2026-08-24-200410.000.panic` (366 KB, mtime 20:04). `panic_newest` takes the single newest by mtime and dedupes on basename, so the undated `.contents.panic` shadows every future dated report. The ledger built so "the next death is attributable" has no row for this death (the report itself is still on disk).
- The pre-reboot sentinel stderr (`/tmp/claude-compressor-sentinel.stderr.log` — TRIP/RELEASE/SKIP lines) was lost at reboot (file recreated 20:05); the JSONL + snap carry the record.
- `…-frozen.tsv` is empty now (post-boot release pass drops all stale pids), so the trip-4 freeze-debt state at death is unrecoverable from it.

## 8. What would refute this reading

1. Actuator output from trip 4 found elsewhere (e.g., processes in state `T` in the 19:55 JetsamEvent's process table) → suspect 5 softens from "never completed" to "completed but unrecorded/too late".
2. Evidence the workerThreads strategy was applied via env var / CLI flag rather than next.config (only `next.config.*` was grepped) → weakens suspect 4.
3. Wave-2 workers proven to be something other than the turbopack/postcss pool (their argv shows bare `node`; the parent being `next-server (v16.2.6)` is the tie) → weakens the "same generator" claim, not the release-into-relapse mechanism.
4. A SIGCONT line in the fatal window with held_s ≥ 600 → would show ceiling-mode releases and refute the clear-mode attribution (none observed; max held_s seen = 116).

## Sources (all read this session, read-only)

`scripts/compressor-sentinel.sh` (full) · `~/Library/LaunchAgents/com.claude.compressor-sentinel.plist` · `~/.claude/logs/compressor-sentinel.jsonl` (rows 18:20–18:26 Z, 02:30–03:15 Z) · `~/.claude/logs/compressor-sentinel-snap.log` (trip list; lines 47468–49300) · `~/.claude/logs/panic-attribution.jsonl` · `/tmp/claude-compressor-sentinel.stderr.log` · `git log --follow scripts/compressor-sentinel.sh` + plist · `docs/research/panic-compressor-2026-08-05.md` §5–7 · `docs/research/crash-rootcause-2026-08-09.md` §1–9 · `docs/research/freeze-2026-08-13.md` (headers) · `docs/research/panic-threadprice-2026-07-31.md` (headers) · `~/Library/LaunchAgents/com.reso.qa-nightly.plist` · `~/Development/reso-management-app/next.config.js` (grep) · `/Library/Logs/DiagnosticReports/` listing · task board #75/#76/#142/#151/#181.
