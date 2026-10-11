# Dispatch-floor strand rescue and routing telemetry (2026-10-09)

What this records: why the general-lane dispatch floor changed, which designs were rejected and why,
and the replay numbers the new constants rest on. The code lives in `bin/claude-accounts`
(`dispatch_floor_row`, `_dispatch_partition`, `fleet_pace`), `hooks/operator-readout.sh`
(`fire_loop_line`) and `scripts/handoff-fire.sh` (`account_via`, `ranked`); the commit bodies hold
the per-change detail.

## The incident

next2 reached 91% weekly at 2026-10-08 02:00 local with 52 h to its reset, then moved 3 pp in the
next 46 h and received 0 handoff-fire assignments in 108 h. At 10 h to reset it held 6% headroom and
the tool's own nowcast said "strand ~6pp of 6". The flat `DISPATCH_W_FLOOR` (0.10, added 2026-09-27
after a fire walled on next4 at 96-99%) ranked it last.

Two findings changed the picture:

- **The floor was not the whole cause.** Replayed rankings show next2 had the lowest raw general
  score until 2026-10-08 ~20:50Z; the floor was the deciding rule for roughly the last 3 h. Un-parking
  alone changed rank[0] in **0 of 407** fleet sweeps of the episode (a lifted next2 scored 0.37-1.00x
  of the best rival, median 0.63x). `handoff-fire --account auto` takes line 1 only.
- **The larger loss was fleet pace, not selection.** Fleet burn fell from ~2.5 pp/h to ~1 pp/h while
  the three accounts resetting within 22 h of each other needed ~3.4-3.7 pp/h.

## The rule (judge 1 final rule, with judge 2's amendments)

A thin account (weekly headroom < 10%) is **lifted** when `spare >= need * (1 + claims)`, where
`spare = min(nowcast strand, 100*headroom - max(EWMA, flat pace) * hours_to_reset)`,
`need = max(4.0 pp, 0.42 pp/h * hours_to_reset)` and `claims = max(k_phantom, k_placed)` with a
300-minute placement memory. In the general lane a lifted account goes **first** if it is 5h-cold,
outside its login-cliff band, placement memory is tracked, and no roomy account both outscores it and
resets sooner. Every missing, stale or NaN input holds it (the 2026-09-27 behavior).

Replay over the whole utilization ledger (47,986 rows, 3,187 live-thin sweeps of known outcome):

| Measure | Value |
|---|---|
| Sweeps lifted | 90, all in windows that stranded; 0 in windows that walled |
| Threshold sensitivity | 3.0 pp lifts 10 sweeps in walled windows; 2.0 pp lifts 168 |
| 2026-09-26 next4 incident | held throughout (nowcast 0.00 pp) |
| weekly 96% / 13.6 h / zero pace | held (needs 5.5 pp) |
| next2, 2026-10-09T21:46Z snapshot | line 1 (spare 5.38 vs need 5.33), outscored 0.000307 vs 0.000463 |

Simulated on next2's real series and the real fire stream (one fire per line-1 pick, sessions running
to the reset at 0.39 pp/h):

| Variant | Sessions placed | Wall |
|---|---|---|
| Promotion, 15-min claim (design C as proposed) | 4 | T-14.9 h, 4 running |
| Lift + promotion, 15-min claim | 3 | T-13.5 h, 3 running |
| + 300-min claim | 1 | T-3.7 h, 1 running |
| + need = max(4.0, 0.42 x horizon) (shipped) | 1 | none; final 98.0-99.1% |

At the p90 burn of 0.61 pp/h the shipped rule walls one session 0.5-3.2 h before the reset.

## Rejected designs

- **Un-park only (strand-conditioned demotion).** Safe, but rank-inert on the incident (above).
- **Hours-to-reset ramp / session budget, no burn evidence.** Released next4 at 2026-09-26T16:34Z,
  4.3 h before it walled; 55.6% of its historical releases fell in windows that walled anyway; a
  dark transcript walk failed toward release.
- **Promotion with the 15-minute phantom claim.** Piles 2-4 sessions onto ~6 pp within an hour.

## Consequences accepted

- Line 1 of `--rank general` can carry a lower score than line 2. The recycle re-pick compares line
  1's score against the incumbent's, so a promoted line 1 does not trigger a re-pick (conservative).
- Callers that place several sessions on one answer (`cc-offload`, `cc-wave-plan`) and callers that
  never record `--assign` (`lr-handoff.sh --target auto`) pass `CC_ROUTE_DISPATCH_STRAND_FIRST=off`.

## Telemetry added

| Signal | Where | Replay |
|---|---|---|
| Fleet pace line: realised 24 h burn vs what resets within 48 h need, fires on a 30 pp shortfall held for two hourly evaluations | `claude-accounts --readout` / board | first fires 2026-10-09T10:00Z; one prior episode in three weeks (10-03, next4 then stranded 26 pp); 10 episodes in 59 days, each followed by a real strand |
| Dispatcher fire-loop line: a backlog item whose fires keep failing, with its remedy | operator readout | fires 2026-10-05T08Z to 10-09T17Z (one brief refused at the payload gate 243 times across all four accounts) |
| `account_via` + `ranked` on each fire's `handoffs.jsonl` row | per-fire record | answers "why did nothing go to account X" in one query |

The "138 next3 fires with no pane anchor" read was test pollution: `tests/cc-dispatch.bats` wrote its
fixture headers into the live `dispatch-fires.log`. It now pins its own log.

The design and judging ran as two Dynamic Workflows (three independent designs and two adversarial
judges for the floor; two designs and one judge for telemetry), each judge rebuilding the replay
against the worktree binary's own functions.
