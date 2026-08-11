# READINESS wave briefs (2026-08-11)

Design + rationale: `docs/plans/BACKLOG_CONSOLIDATION_2026-08-09.md` § READINESS (2026-08-11).
W0 (the ratchet instrument) landed inline as `c61ee7147`.

These three briefs are **durable copies of what was written to fire W1-W3**, kept here because the
filed backlog rows point at them and a brief that lives only in `/tmp` does not survive a reboot —
which is this wave's own defect (a conclusion parked where no enforcing store reads it).

| wave | brief | backlog id | condition |
|---|---|---|---|
| W1 · the conjunction | `wave-one-admission-gate.md` | `d73a772a8468` | `readiness-wave-one-admission-gate` |
| W2 · the second screen | `wave-two-second-screen.md` | `0e8a10c501af` | `readiness-wave-two-second-screen` |
| W3 · act, and brake | `wave-three-actuator-brake.md` | `df003b95630b` | `readiness-wave-three-actuator-brake` |

**Why filed rather than fired.** All three were composed and W1 was fired twice on 2026-08-11.
The cold fire hit the INC-4 cold-worktree autosubmit race (pane 393, task-less, left visible for
`cc-reaper`), and the warm re-fire was refused by the capacity gate — **load 21.89 on 10 cores =
2.19/core against a 2.0 ceiling**. That refusal is the gate working, not a failure to route around:
another Opus session would have slowed every live one. The waves are therefore condition-keyed
backlog rows, so the dispatcher admits them when the box has headroom.

Ownership is **disjoint by file** so all three may run concurrently:
W1 owns `bin/cc-dispatch` + `bin/cc-venue`; W2 owns `bin/cc-premise`; W3 owns `bin/cc-backlog` +
`scripts/backlog-consolidation-trigger.sh`. Do not widen a wave's file set — the readiness verdict
deliberately lives in the dispatcher's decision journal rather than the ledger, which is what keeps
W1 out of `bin/cc-backlog`.

The worktree `~/Development/.worktrees/readiness-w1` was provisioned by the failed fire and is
KEPT on purpose: a warm re-fire (`handoff-fire.sh --cwd <that path>`) is the documented recovery
and avoids re-running the race.
