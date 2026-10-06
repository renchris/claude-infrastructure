# Q4 — Does the capacity gate measure the right thing?

Slot scope: what the gate refused or delayed for limit-recover callers in the last 30 days, and whether
real memory pressure followed. Date 2026-10-06. Tags: MEASURED (I ran it), READ (source/record), INFERRED.

Scripts (read-only, under /tmp): `q4_capacity_gate.py` (raw tally), `q4_capacity_gate2.py` (real rows
only), `q4_sentinel.py` (10 s compressor samples as ground truth).

## Verdict

- The gate held rotations for reasons that were **not memory** in 309 of 323 real refusals (95.7%):
  load 211, active 80, reserve-active 18. Compressor segments at those refusals read at most 14.68%
  (ceiling 50%/90%) and reclaimable headroom at least 23.14 GB (floor 4 GB). MEASURED.
- The one memory term that refused (segments, 13 refusals, 11 sessions, 2 days) refused at a real
  elevated level (48-66% by the sentinel) that kept climbing to 72.56% within 10 min. No panic
  followed. That ceiling was 50% then; it is 90% for swaps since commit 85fb15804 (2026-10-04T16:09Z).
- Since 2026-10-05T00:00Z: 22 limit-recover evaluations, 22 admits, 0 refusals (n small, 2 days).
- The plain headroom term (reclaimable >= 4 GB) refused 0 times in 2,604 rows; the minimum reading
  in the window was 8.74 GB. It cannot bind on this box.
- The gate is a point-in-time level read. Both 2026-09-16 panics (100% of segment limit) went from
  about 7% to over 90% in under 5 minutes, with 82-87 s above 50%. A gate reading 10 min before
  either panic would have admitted at 6.97% and 0.0%. It is not, and cannot be, a panic guard.
- So: "memory is the bottleneck" is not supported by the gate's record. The gate is not what keeps
  recovery at one to two at a time; when it did hold, it was mostly CPU-shaped terms.

## 1. The terms (key question 1)

`lr_capacity_probe_corrected` (scripts/limit-recover/lr-lib.sh:410-440) wraps `cc_capacity_probe`
(scripts/lib/capacity-admit.sh:1135), which is `cc_capacity_admit` (:1155) with the budget, page and
reset inert. Evaluation order is fixed and short-circuits at the first refusal. All READ.

| Term | Input | Default threshold | Under the LR probe | Source |
|---|---|---|---|---|
| load | `vm.loadavg` 1 min / `hw.ncpu` | > 2.0/core refuses | OFF (call-scoped) | capacity-admit.sh:162, 1300-1309; lr-lib.sh:435 |
| headroom | vm_stat free+speculative+inactive+purgeable | < 4 GB refuses | on | capacity-admit.sh:163, 212-225, 1330-1353 |
| segments | (compressor pages/segment + swap used/segment) / `vm.compressor_segment_limit` | > 50% refuses | ceiling 90% (`LR_SEGMENT_PCT`) | capacity-admit.sh:281-313, 1374-1393; lr-lib.sh:436 |
| active | `cc_sp_active` + turn-kind tokens in flight + 1 | > 8 refuses | on, minus limit-corpse beats and the subject itself | capacity-admit.sh:1445-1472; lr-lib.sh:420-433 |
| reserve-headroom | headroom vs floor + operator reserve | < 4 + 6 = 10 GB (operator present) | on | capacity-admit.sh:1495-1500 |
| reserve-active | active vs ceiling - 1, only on proven presence | > 7 refuses | on | capacity-admit.sh:1514-1523 |
| reserve-slots | `cc_sp_trees` + 1 vs 54 - reserve slots | > 54 - 6 | on | capacity-admit.sh:1529-1538 |

Per-caller differences (READ):

| Caller | Terms in force | Wait policy | Source |
|---|---|---|---|
| lr-fleet (recover pool) | headroom, segments(90), active, reserves | re-probe every 20 s up to 120 s, then park; held inside the admit mutex | lr-fleet.sh:548-580 |
| lr-handoff | same | one reading, park (rc 6) on refusal, mint a token on admit | lr-handoff.sh:1453-1472 |
| lr-upgrade | same | one reading, skip on refusal | lr-upgrade.sh:1856-1872 |
| lr-move-batch / lr-move-worker | headroom, segments(90) only (`CC_ADMIT_ACTIVE_TERM=off CC_ADMIT_LOAD_TERM=off CC_ADMIT_RESERVE_TERM=off`) | one reading before /exit; NOTMOVED on refusal | lr-move-batch.sh:151-153; lr-move-worker.sh:128-133 |
| lr-fire-resume (in the pane) | exempt when `LR_ADMIT_MODE=swap` with --no-prompt; else redeems the token; else fresh `cc_capacity_admit` with budget 3 | 3 refusals then admit + page | lr-fire-resume.sh:605-640 |

One inconsistency: the launcher's own fallback is `CC_ADMIT_MAX_SEGMENT_PCT="${LR_SEGMENT_PCT:-50}"`
(lr-fire-resume.sh:623) while the probe defaults to 90 (lr-lib.sh:436). Drivers export 90
(lr-handoff.sh:1675, lr-upgrade.sh:1818, lr-move-worker.sh:147); a direct invocation gets 50.

## 2. Counts (key question 2)

Ledger facts first, because they change the denominators:

- `~/.claude/autonomy/capacity-admit/` and `capacity-fire/` are budget-counter state files, not
  ledgers (134 files in capacity-admit; 128 are per-run `lr-fire-resume.*.refusals`). The rows are written to
  `~/.claude/autonomy/idl.jsonl` (`_cc_admit_emit`, capacity-admit.sh:447-484) plus 8 rotated `.gz`. READ.
- The retained ledger starts 2026-09-17T22:21:23Z. "Last 30 days" is really 18.3 days. MEASURED
  (`q4_capacity_gate.py`: `span_all 2026-09-17 22:21:23 .. 2026-10-06 06:21:46`, 2,604 rows, 0 unparseable).
- The ledger holds drill and test rows under limit-recover names. I count a row as real only when
  the session id in `what` has a record directory under `~/.reso/limit-recover/` and the row is not a
  fixture override. That drops 91 `lr-reconciler "first-turn"` load refusals, 24 + 2 `lr-upgrade`
  rows, 18 + 7 `lr-fire-resume` rows (including `sid-under-test`). MEASURED (`q4_capacity_gate2.py`).
- Move lane: 1 batch directory exists, with 1 batch `capacity.log` and 7 per-session ones.

Real limit-recover rows, 2026-09-17 to 2026-10-06 (n = 862 rows, 118 distinct sessions). MEASURED.

| Caller | Admit | Refuse | Refusals by term |
|---|---|---|---|
| lr-fleet | 267 | 235 | load 164, active 62, reserve-active 8, segments 1 |
| lr-fire-resume | 139 (92 by token, 19 budget-expired) | 70 | load 47, active 17, segments 3, reserve-active 2, token-stale 1 |
| lr-handoff | 100 | 18 | segments 9, reserve-active 8, active 1 |
| lr-upgrade | 26 | 0 | - |
| lr-move-worker | 7 | 0 | - |
| lr-move-batch | 1 (batch-level row, no sid) | 0 | - |
| Total | 539 + 1 | 323 | load 211, active 80, reserve-active 18, segments 13, token 1, headroom 0 |

By day (real refusals): 2026-09-19 carries 286 of 323 (load 210, active 72, reserve-active 4). The
load term was turned off for these callers by commit 0cc4a5177 (2026-09-19T23:44Z); the last real load
refusal is 2026-09-19T23:37:32Z. From 2026-09-20 on: 36 refusals in 16 days (reserve-active 14,
segments 13, active 8, token 1).

All callers, for context (2,604 rows): refusals are load 719, active 181, segments 105 (86 of them
`boot-resume-launch` fixture rows at exactly 99.0% with `(? of ?)` counts), reserve-active 27,
reserve-headroom 3, headroom 0.

## 3. What memory looked like at each refusal (key question 3)

Ground truth is the compressor sentinel (`~/.claude/logs/compressor-sentinel.jsonl`, one sample per
~10 s; 235,384 samples and 684 sampled hours in the 30 days). MEASURED (`q4_sentinel.py`).

| Refusing term | n | Segments at refusal (min / p50 / max) | Max segments in next 10 min | Max in next 60 min | Min headroom within 10 min |
|---|---|---|---|---|---|
| load | 211 | 0.00 / 5.39 / 5.68% | 6.25% | 6.95% | 25.47 GB (n=98) |
| active | 80 | 0.62 / 5.01 / 12.23% | 16.10% | 16.10% | 24.20 GB (n=27) |
| reserve-active | 18 | 2.84 / 12.52 / 14.68% | 17.53% | 36.16% | 23.14 GB (n=17) |
| token-stale | 1 | 11.12% | 11.12% | 11.12% | 23.59 GB |
| segments | 13 | 48.19 / 61.12 / 65.73% | 72.56% | 72.56% | 10.72 GB (n=1) |

Load-per-core on the 211 load refusals: 2.05 to 6.14. Right now (MEASURED, `uptime`, `sysctl`,
`vm_stat`): load 36.69 on 10 cores = 3.67/core, swap 2.18 of 3.07 GB, segments 4.75%, reclaimable
23.55 GB, `kern.memorystatus_vm_pressure_level` 1 (normal), 25 claude processes. The load term would
refuse at this moment on a box with no memory pressure.

Pressure events in the 30 days:

| Event | Evidence | Relation to the gate |
|---|---|---|
| Panic 2026-09-16 15:54 CDT, "100% of segments limit (BAD)" | `~/.claude/logs/panic-attribution.jsonl` (READ); sentinel 6.97% at t-600 s, 93.91% at last sample | Before the retained ledger. A reading 10 min earlier would admit. |
| Panic 2026-09-16 16:28 CDT, same verdict, watchdog timeout | same file; `/Library/Logs/DiagnosticReports/.contents.panic` (READ); sentinel 0.0% at t-600 s, 8.71% at t-300 s, 92.65% at t-120 s | Same. Above 50% for the final 82 s, above 90% for 24 s. |
| Reboot 2026-09-30 15:26 | `shutdown_stall_2026-09-30-152544...shutdownStall`, no panic file (READ) | Not a memory event. |
| 2026-10-04 segments 50-72% for hours | sentinel hourly max: 15Z 60.59, 16Z 70.12, 22Z 65.91, 23Z 70.79, 2026-10-05 00Z 71.81, then 10.73 by 01Z | The only window where a memory term refused LR callers. No panic. |

Time above thresholds over 684 sampled hours: over 50% for 4.96 h (0.72%), over 70% for 0.15 h, over
90% for 0.01 h (the two panics). MEASURED.

Does a rotation add memory? For 145 real relaunch admits (lr-fire-resume, lr-move-worker) with
sentinel coverage, the segment change 5 min later was p50 -0.06 points, p90 +0.49; the 5-min peak
minus the reading at admit was p50 0.00, p90 +1.02, max +24.85. Seven admits (4.8%) were followed by
a rise over 5 points, against 0.98% of 6,343 control samples; three of the seven sit in one 4-minute
window (2026-10-03T02:27-02:31Z), and none reached 50%. The batch of 7 moves on 2026-10-06
06:05-06:20Z ran with segments between 4.13% and 4.58% and swap flat at 2.15 GB. MEASURED.
INFERRED: a swap is close to net-zero on the gated quantity; the 4.8% vs 0.98% gap is confounded by
recoveries happening when the fleet is busy.

`log show` was not sampled: the sentinel and the panic ledger already answer the question at 10 s
resolution.

## 4. How often and how long the gate held a rotation (key question 4)

Method: per session, a run of refusals from any limit-recover caller, closed by the next admit for
that session within 2 h. Duration is first refusal to that admit (or to the last refusal when no
admit followed). This is an upper bound on gate-caused delay: it includes the retry cadence of the
poller or operator. MEASURED (`q4_capacity_gate2.py`).

| First refusing term | Episodes | Session-time held | Median | No admit within 2 h |
|---|---|---|---|---|
| segments | 11 | 70,495 s (19.6 h) | 5,545 s | 1 |
| load | 23 | 20,191 s (5.6 h) | 83 s | 2 |
| active | 14 | 12,347 s (3.4 h) | 197 s | 4 |
| reserve-active | 4 | 1,571 s (0.4 h) | 224 s | 1 |
| token-stale | 1 | 1,128 s | - | 0 |
| Total | 53 episodes, 42 of 118 sessions | 105,732 s (29.4 h) | | 8 |

By era:

- 2026-09-17 to 09-19 (load term on, phantom-active census): 31,918 s, all load and active.
- 2026-09-20 to 10-04: 73,814 s, of which 70,495 s is segments, and 70,013 s of that is nine sessions
  parked on one afternoon (2026-10-04, first refusals 15:53-16:10Z) at the old 50% ceiling. Active
  620 s, reserve-active 1,571 s.
- 2026-10-05 onward: 0 s.

Records agree on the parks: 18 `PARKED capacity` events in per-run `events.jsonl` (9 segments, 9
reserve-active), all 2026-10-04; `results/*.json` holds 1 capacity skip (lr-upgrade, 2026-09-29,
reclaimable 9.14 GB under the 10 GB operator reserve). READ.

## Alternatives considered

- Memory really is binding but under a different name. Rejected for the gate: headroom never fell
  under 8.74 GB and the plain floor refused 0 times.
- The 2026-10-04 segments refusals were correct and prevented a panic. Not shown: the level reached
  72.56% while they were parked and fell to under 11% twice with no panic. One day of evidence.
- The gate is what limits concurrency. Not shown here: refusals are rare since 09-20 and zero since
  10-05. One term could cap a parallel recover pool, though: the active term counts turn-kind
  admission tokens in flight against the ceiling of 8 (capacity-admit.sh:1465-1468), so more than
  about 7 concurrent prompted recoveries would refuse themselves. The move lane has that term off.
  INFERRED from source, not observed.

## Uncertainties

- Ledger coverage is 18.3 days, not 30. Recoveries from 2026-09-06 to 09-17 are not counted.
- The real/drill split relies on a record directory existing for the session id. A real session
  whose directory was cleaned up would be dropped; a drill that used a real session id would be kept.
- Hold durations are session-time upper bounds, not wall-clock and not pure gate delay.
- "0 refusals since the 90% ceiling" rests on 22 evaluations over 2 days at segments under 9%.
- What dropped segments from 70% to under 10% at 2026-10-04 16Z and 2026-10-05 00Z was not traced.
