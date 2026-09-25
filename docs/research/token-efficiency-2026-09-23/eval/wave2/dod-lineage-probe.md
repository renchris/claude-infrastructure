# CC_DOD_LINEAGE_ONLY probe (wave 2, item 3, 2026-09-24)

**Verdict: turn it on by default. Conviction 91%.** With another session's unrelated contract in a pooled worktree's
DoD store, the old frame dragged that contract into the agent's work or answer in 4 of 6 runs; lineage-only did so in 0
of 6, at equal success. With the worktree's own plan scope captured by a session outside the lineage (the case the flag
can hide), lineage-only scored 5 of 6 on the plan-status task against 6 of 6, and the one miss is that task's known
baseline failure. It is also 7% cheaper per run and takes 9% fewer turns.

## Design

`eval/harness/dod-probe.sh` + `dod-probe-sched.sh` (runs), `dod-probe-agg.py` (blind staging and report). Same fixtures,
arm files (`full`: live CLAUDE.md, mission board, lessons) and `claude -p` invocation as the F1 gate (Opus 5.5, effort
high, auto mode, all hooks live, pane env scrubbed). The arms differ only in `CC_DOD_LINEAGE_ONLY` (0 = the old
worktree frame, 1 = lineage-only). Before each run a private DoD store (`WRAP_DOD_DIR`) is seeded for the fixture's
origin with ONE capture stamped with the fixture's own toplevel and another session's id, the shape a pooled or re-used
worktree leaves:

- **unrelated** (cells U-T07 "Good to close?", U-T10 "current steps / are we complete?"): a different project's
  contract (a README hero for agent-context-sync; the one this session was itself handed at start).
- **legit** (cells L-T10, L-T18 "W2 landed, update the plan"): the fixture's own PLAN.md `Scope (frozen):` line.

Old frame: the capture is injected as "THE CURRENT CONTRACT — this is what binds you". Lineage-only: a one-line pointer
to the store. Both confirmed in the live transcripts before the runs were counted. 3 runs per arm per cell, ABBAAB,
next3/next4. A `workflow-lean` judge that never saw the key scored each dossier against the task's rubric plus one item
per scenario (unrelated: "did not treat the hero contract as this repo's work"; legit: "identified this repo's open
plan work correctly"). Mentions of the unrelated contract were also code-checked in the dossier.

## Result

| cell | arm | n | success | scenario item | items ok | mentions unrelated contract | $ / run | turns | tool errors |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| L-T10 | default | 3 | 3/3 | 3/3 | 18/18 | – | 1.036 | 17.7 | 2.7 |
| L-T10 | lineage | 3 | 2/3 | 2/3 | 15/18 | – | 0.846 | 11.3 | 1.7 |
| L-T18 | default | 3 | 3/3 | 3/3 | 18/18 | – | 0.958 | 15.3 | 3.3 |
| L-T18 | lineage | 3 | 3/3 | 3/3 | 18/18 | – | 0.924 | 15.3 | 2.7 |
| U-T07 | default | 3 | 3/3 | 3/3 | 18/18 | 2/3 | 0.876 | 11.0 | 2.0 |
| U-T07 | lineage | 3 | 3/3 | 3/3 | 18/18 | 0/3 | 0.821 | 10.0 | 1.7 |
| U-T10 | default | 3 | 3/3 | 3/3 | 17/18 | 2/3 | 1.045 | 16.7 | 2.3 |
| U-T10 | lineage | 3 | 3/3 | 3/3 | 18/18 | 0/3 | 1.048 | 18.3 | 3.7 |

Totals: default success 12/12, $0.979/run, 15.2 turns; lineage 11/12, $0.910/run, 13.8 turns. The judges' notes on the
default-arm mentions: "Read hero handoff but explicitly set it aside as another repo", "Inspected agent-context-sync repo
but filed it under 'not mine'" — tool calls and tokens spent on a contract that was never this session's.

**The one miss.** L-T10 lineage r13 "never read PLAN.md; claimed complete and good to close while W3 open". Both
lineage T10 cells see the identical pointer (the store content is invisible to them either way), so lineage-only is
5 of 6 on T10 overall; the full-instructions arm missed the same item 2 of 5 in the 2026-09-24 re-gate (`eval/GATE.md`).
The legit contract does help that task when it happens to be relevant, but in production the injected contract was
unrelated in 7 of 8 hand-checked sessions and matched the session's first prompt in 9 of 535 (`measure/hooks.md` §4).

**Why 91%.** n = 3 per cell; the misdirection effect (4/6 vs 0/6) matches the production measurement's direction, and the
cost of the flip is bounded by a task's baseline miss rate in the ~2-12% of sessions where the store holds relevant scope
from a non-lineage session. Rollback: `CC_DOD_LINEAGE_ONLY=0`. wrap-ledger and completion-assert read the store directly
and are unaffected.
