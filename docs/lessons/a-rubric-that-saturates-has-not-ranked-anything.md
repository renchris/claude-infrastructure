# A question that returns one answer for most of a population has not ranked it

**2026-09-21.** `cc-jev rank` scored 140 indexed memory rules on a four-level scale. **118 of them
— 84.3% — came back `often`**, 21 `occasionally`, 1 `almost-never`, and **0 `nearly-always`**: a
four-level scale using three levels with most of its mass in one bucket. Its companion boolean,
`superseded`, ranged 0.08–0.89 with **zero** rows at or above the 0.90 band `hooks/lib/jev.sh`
defines as the only actionable one — so by its own library's rule it produced **no verdicts at
all**.

Every individual verdict was defensible. Spot-checks read correctly. **The ordering was worthless**,
and the run reported `SCORED 140 of 146` and a tidy demotion list over it.

## The rule

**Discriminating power is a property of the POPULATION, not of the model or the prompt — so the run
has to measure and report its own.** Before acting on any ranking, scoring or classification pass,
ask what fraction of its answers landed in the largest bucket. At ~80% or more, the question
carried almost no information about *this* corpus, however sound each judgment was in isolation.

Report it in the output, not in a later analysis. A near-constant question must be named as such
**by the run that produced it**, or it is discovered by hand weeks later — if at all, because a
saturated ranking looks exactly like a confident one.

## Why it recurs, and the shape that hides it

The corpus here had already survived a curation pass. Asking "how often would this rule change what
you do?" of a set of rules that were *kept because they change what you do* is near-constant **by
construction**. The question was good; the population had no variance along its axis.

This is the same failure that killed the deference arm one level up (`jev-at-cost-api-2026-09-18.md`
Addendum 4): its gate's two halves selected **disjoint** sets on real closes — the confident rows
were classed `value_fork`, the `drivable` rows topped out below the threshold — and nobody could see
it until the answers were crosstabbed. Both are properties of the data, invisible to any amount of
re-reading the code.

## What to do instead when it saturates

A forced comparison has no scale to saturate: *given these five, which one*, then *given this
challenger and this incumbent and one slot, which*. There is no bucket to pile into. It is usually
also closer to the decision actually being made — a full index is a **swap** problem, not a scoring
problem, and "this one is good" changes nothing when there is no free slot.

**Add the new question BESIDE the old one, never in place of it.** A swap trades one unvalidated
rubric for another and leaves you unable to say which was at fault; asked together in one call, a
single pass measures whether the new one discriminates, and a closing line states how many items
the two rules disagree about. If that number is zero, the new question reproduced the old one and
bought nothing — which is a real outcome and must be visible in the run.

## Companions

- `docs/research/jev-at-cost-api-2026-09-18.md` Addendum 4 — the anti-correlated gate.
- `docs/research/jev-100p-2026-09-21/VERDICT.md` — the wave this came out of.
- `scripts/jev/rank-memory.sh` § RUBRIC DISCRIMINATION — the implementation, with `--report` to
  re-read any past run for free.
- [[alarm-polarity-and-attention-budget]] — an alarm that always fires says as little as one that
  cannot. Same arithmetic, on the other side of the decision.
- [[an-imported-threshold-can-sit-above-the-model-s-output-range]] — the adjacent failure: a
  threshold outside the output range lands the arm inert. That one is about the CUT; this one is
  about the SPREAD, and a spread that is absent cannot be rescued by moving the cut.
