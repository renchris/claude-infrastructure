# An imported threshold can sit above the model's output range, and the test moves with it

**The rule.** A threshold imported from another task's calibration can sit **above the subject's
entire output range on yours**, so the feature lands completely INERT — and every test still
passes, because the test's fixture value was written against that same imported constant and moved
with it. Before shipping a threshold, measure the subject's OUTPUT RANGE on YOUR task and assert
the constant falls inside it; and never let a test's fixture value be derived from the constant it
is guarding.

## The incident (2026-09-19)

`CC_JEV_MIN_P` shipped at **0.98**. Measured on `tests/fixtures/jev-synthetic-closes.json` (n=20 —
10 deferrals, 6 finished, 4 genuine blockers) through the production question block via
`scripts/jev/synthetic-probe.sh`:

| population | P(defers) range | mean |
|---|---|---|
| true deferrals | **0.81 – 0.95** | 0.93 |
| finished work | 0.05 – 0.08 | 0.06 |
| genuine blockers | 0.20 – 0.93 | 0.43 |

The top of the whole deferral range is 0.95. **0.98 is unreachable**, so the arm fired **0 of 10**
on true positives. It landed doing nothing at all. Corrected to **0.90**, which is measured here.

Where 0.98 came from: §2's calibration of a *different* task — a phishing bench, where p≥0.98
decides 7.0% of cases at 97.8% accuracy. The number was real; it simply does not transfer.

## Why no test caught it

The arm's own unit test pinned **0.97** as its "below threshold" case. That assertion is true only
while the default is 0.98 — i.e. only while the feature is inert. The fixture was chosen *relative
to* the constant under guard, so moving the constant moved the test with it and the pair stayed
green in every arm. This is the [green-in-both-arms](green-in-both-arms-is-an-equivalence-guard-not-a-red-proof.md)
shape with an extra turn of the screw: there was no mutation that could kill it, because the mutant
and the oracle share a variable.

**The discipline that follows:** a test guarding a threshold must pin a LITERAL drawn from the
measured output range, never an expression over the constant, and never a value picked by reading
the constant's current default.

## The three checks this makes routine

1. **Range assertion before ship.** Run the subject on your own task's fixture, print
   `min/max/mean` per population, and assert `min(population) ≤ constant ≤ max(population)`. A
   constant outside the observed range is a landed no-op, not a conservative setting.
2. **Decouple the oracle.** Grep the test for the constant's name. If the fixture value is computed
   from it — or was obviously chosen by looking at it — replace it with a measured literal and
   record where that literal came from.
3. **Grep the OLD value across the whole tree.** A threshold's *documentation* is as distributed as
   its callers, and prose does not move when the constant does. Correcting `CC_JEV_MIN_P` left two
   comments still naming `0.98` as the live gate — in `hooks/anti-deference-nudge.sh` and
   `tests/fixtures/jev-mock-gateway.mjs` — where a reader would have taken them for the shipped
   behaviour. Nothing executes a comment, so no gate can catch this: `git grep` the retired literal
   and read each hit, keeping the ones that describe the PAST and fixing the ones that claim the
   PRESENT.

## What the same probe vindicated, so the lesson is not "the number was the bug"

Specificity was perfect at every threshold down to p≥0.5: 0/6 false fires on finished work, 0/4 on
genuine blockers. The case built to break it — *"Dropping the legacy orders table is irreversible
on production data"* — scored **0.93** on the boolean, squarely inside the deferral range, and was
correctly suppressed by the second question (`blocker_class = destructive_or_production`). The
boolean alone cannot separate a deferral from a genuine blocker; the ranges overlap at 0.93.

And recall is **not** threshold-bound: on true deferrals `blocker_class` splits `none` (4) /
`drivable` (3) / `value_fork` (3), and the arm requires `drivable`, so **any threshold ≤ 0.93
yields the same 3/10**. Tuning the number buys nothing — the choice question is the binding
constraint. Reading the inert constant as "the recall problem" would have sent the next session to
tune a number that cannot move the result.

## Honest limit on the measurement

n=20, **synthetic, authored by the agent whose prose the arm judges** — the most favourable
possible population. It establishes exactly two things: the shipped constant was unreachable, and
specificity survives contact with the real model. It does NOT establish recall on real closes.
`cc-jev pilot` against the 85 genuine labels is the only instrument that can, and it should
**re-derive** the threshold rather than inherit it — inheriting is the defect this lesson names.

Re-run: `bash scripts/jev/synthetic-probe.sh` (needs a key; sends no private data).

## Companions

- [init-state-is-not-runtime-state](../../.claude/rules/agent-operating-lessons.md) — *a threshold
  you QUOTE is not a rate you MEASURED*; this incident is that rule's sharpest instance.
- [published-figure-decays-with-its-source](../../.claude/rules/agent-operating-lessons.md) — a
  figure carried across contexts has a half-life; here it had none to begin with.
- [green-in-both-arms](green-in-both-arms-is-an-equivalence-guard-not-a-red-proof.md) — the test
  that passes before and after guards nothing.

Source: `docs/research/jev-at-cost-api-2026-09-18.md` § Addendum 2.
