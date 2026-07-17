# Workflow Seam-Gates — Phase-2 plan-template addendum

Distilled from the doc_classifier program (Phase 1 research → Phase 2 Agent-Teams plan →
Phase 3 implementation, 1 week+, 2026-07). Purpose: carry the hard-won lessons into the
**next program (Phase 4 — Azure Gov) and every program after**, so the same class of
mid-implementation stops does not recur.

## The unifying diagnosis: misses are *seam* failures

Every mid-implementation stop in doc_classifier traced to the same shape — **two things,
each individually certified "100/100," whose *interface* was never verified:**

| Stop | The seam that failed |
|---|---|
| n50k S3 O(N²) OOM | algorithm (`combinations(docs,2)`) × test-corpus shape (uniform 1-page → every pair matches) |
| "defined-not-wired" (recurring 10× in the BUILD_LOG) | a feature's *definition* × its *wiring* to every production entry path |
| 13 h zombie session | a teammate's *actual liveness* × the lead's *assumption* it was alive |
| Every re-assessment stop | what is *knowable at phase N* × what is *only produced by phase N+1* |

Internal-completeness metrics ("100/100 knowledge", "100/100 plan") are **structurally
blind to seams by construction** — they measure each component's internals, not the joins.
The frontier-hole trigger already names this at the top of the stack ("a never-derivation-
swept seam between ≥2 subsystems"); the fix is to **pull seam-hunting forward into every
phase exit**, not treat it as a frontier-tier afterthought.

## The six moves (prioritized by leverage)

1. **Encode decision *rules*, not just decisions.** The single biggest autonomy lever.
   The n50k fork was *already determined* by the standing value (lossless/byte-identical → b);
   it became a human stop only because a "cross-cutting correctness change" tripped an
   escalation reflex. Pre-specify, per anticipated decision-class, the **criteria + risk
   thresholds** that map execution-outputs → action, so the agent decides and keeps running.
   *(This is the drive-by-default principle, lifted into the plan itself.)*
2. **Resource-complexity ledger in the plan.** Per stage: worst-case **time AND memory in N
   at target scale**, including worst-case match/branch rates. A five-minute mechanical pass
   flags the entire O(N²)-class *before* a line is written.
3. **Reachability gate, not definition gate.** For every feature/flag/contract, a test that
   it reaches production `RunSpec` through *all* entry paths — kills "defined-not-wired" as a
   class, not one instance at a time.
4. **Fixtures are first-class, with a pathology audit.** Synthetic-data shapes (the uniform
   1-page corpus was a *known property of the generator*) bite harder than production data
   because they are extreme. Model their pathologies explicitly.
5. **A phase-exit adversarial pass aimed at the *next* phase's failure mode.** research-exit
   asks "what breaks at scale / at seams?"; plan-exit asks "what's the resource cost, and
   which decisions are execution-gated?"; implement-exit asks "what's defined-but-not-wired?"
6. **Seams first-class at every phase boundary.** Every phase exit and every subsystem
   boundary gets an *owned, adversarial* seam audit that targets the interaction, not the
   components. This is where 100/100-certified parts go to fail together.

## The calibrated-certification meta-fix

Stop certifying "100/100" *absolutely*. Certify **"100/100 against the criteria reachable at
this phase, with *this explicit list* still execution-gated."** That single change dissolves
the "we said 100/100 and still had to stop" frustration: the stop becomes "we said 100/100 on
what was knowable, and the verification ladder surfaced the rest — exactly as designed." The
right metric is not *zero stops* (that process is either trivial or over-padded) but **cheap
self-caught stops + minimal human stops** (human stops reduced to genuinely info-gated
decisions). A stop caught at the ladder, pre-production, is the system *working*.

## Session-lifecycle: never silent-idle (2026-07-17)

A session must always be in exactly one of three states — **working**, **pinging for drive**
(blocked → surface to the human), or **done → notify + close**. *Silent-idle is a bug.*

- **Blocked / owned-wait on a long external run** (e.g. a multi-hour scale run): must
  periodically **surface status** ("waiting on X, ~N hr, healthy") so it reads as
  *waiting*, not *stuck*. Unavoidable idle is fine; unavoidable *silence* is not.
- **Done + verified + landed + no open scope**: should **proactively self-close** (notify
  the desk/operator, then close) — not sit idle waiting for the reaper. The autonomous
  reaper (`cc-reaper`) is the *backstop*, never the proactive path.
- **Not working**: ping to be driven forward — never sit silent.

## Ready-to-use Phase-2 checklist

- [ ] **Decision-rule table** — every anticipated fork has pre-encoded criteria + risk thresholds.
- [ ] **Resource-complexity ledger** — per stage: time + memory in N at target scale + worst-case rates.
- [ ] **Reachability tests** — every feature/flag reaches production through all entry paths.
- [ ] **Fixture pathology audit** — synthetic-data extremes modeled as first-class facts.
- [ ] **Phase-exit adversarial pass** — aimed at the *next* phase's failure mode.
- [ ] **Seam audits** — owned, adversarial, at every phase boundary + subsystem interface.
- [ ] **Calibrated certification** — "100/100 vs phase-reachable criteria; execution-gated: <list>".
- [ ] **Never-idle lifecycle** — sessions surface-status on long waits, self-close on done+landed.
