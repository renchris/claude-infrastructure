# "Clean and landed" is not "nothing in hand" — in-process children are invisible to the ledger

**The rule.** An advisory that decides *"nothing would be lost"* from repository state is blind to
everything that lives in the PROCESS: in-process subagents, Dynamic Workflow waves, anything whose
only record is a file being appended to right now. A lead waiting on a wave is clean, landed and
DoD-complete **by construction** — it landed its last merge and is now waiting — so the ledger reads
its best possible value at exactly the moment the most expensive thing is in flight. Before acting
on a "free win", ask what is running that git cannot see.

## The incident (2026-09-20, claude-infrastructure)

`hooks/boundary-handoff.sh` fired at a turn boundary:

> ⟳ FREE WIN — context 42% at an IDLE boundary the ledger reads ✅ — clean, landed, no DoD
> remainder, no operator step outstanding. **Nothing is in hand, so a successor loses nothing** …
> recycle now with `handoff-fire.sh --recycle`.

Three Dynamic Workflow waves were live in that process: a 9-hour adversarial verifier and two
hardening waves. `--recycle` replaces the process, so acting on the advice would have killed all
three mid-tool — leaving whatever commits they had already made and **no report, no return value,
no journal result row**.

That is not a hypothetical cost. The same plan's W2 implementer (`wf_3e1667c1-a38`) died exactly
this way at its own lead's recycle; its wave report had to be reconstructed from six commit bodies
by the next session, and `reports/W2.md` still opens by saying so.

## Why the polarity matters, and what the fix is

- **A free win must YIELD to a live wave.** Its entire claim is that the recycle is free. It is not.
  Suppress, and keep the arm armed for the genuinely idle boundary that follows.
- **A forced drain must NOT yield.** At a real context wall the recycle happens regardless, so the
  right treatment is to fire and say *collect the waves first*. Suppressing there trades a lost wave
  for a lost session.

This is the same split an existing guard already made one axis over: the free-win arm was already
suppressed by an in-flight operator exchange (`freewin-conversation-hold`), for the same reason —
the ledger cannot see a conversation either. The generalisation the first guard missed is that a
**conversation is not the only thing in flight**.

## Detecting it, and two traps in the detector itself

Workflow agents share the session's pid, so there is no process to count. The evidence is file-based:
a run is live when its `journal.jsonl` has more `started` than `result` rows **and** some
`agent-*.jsonl` under it was written recently (the freshness leg is what stops an abandoned run
holding the arm down forever).

Both bugs below were in the first version of that detector, and both read as a clean "no waves":

1. **The path.** Run dirs are at `<transcript path without .jsonl>/subagents/workflows/<runId>/` —
   a SIBLING of the transcript file, not a child of its parent. Using the parent silently searched
   every session's tree and counted 0 against three live runs.
2. **The counter.** `grep -c` PRINTS its count and EXITS 1 when the count is zero, so
   `grep -c … || printf '0'` emits **both**: the substitution becomes `"0\n0"`, the comparison
   `[ 3 -gt "0 0" ]` ERRORS, and `2>/dev/null || continue` reads that error as a clean false. The
   guard disabled itself for precisely the freshest kind of wave — one that has produced nothing yet.

Run the detector against a real session with known live waves before shipping it. Both defects were
invisible to reasoning and obvious to one execution.

## Companions

- `docs/lessons/predicate-error-exit-is-indistinguishable-from-false.md` — trap 2's general form.
- `docs/lessons/fixture-shape-hides-address-bugs.md` — why a fixture must carry the real directory
  shape, or trap 1 is unreachable.
- `docs/lessons/a-gate-s-surface-is-not-its-traffic.md` — a guard proven reachable is not a guard
  the work still crosses.
