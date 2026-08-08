---
status: open
---

# CONDITION LEASE — one condition, one worker

**Item:** backlog `0bded74c6fa2` (claude-infrastructure) · created 2026-08-07

**Scope (frozen):** the dispatcher leases the CONDITION, not the row, so two ledger rows naming one
piece of work cannot both be dispatched.

## Phase 0 — orchestration: single worker, deliberately

No Agent Team. The four parts are **one mechanism with a strict serial dependency**, not 2+
independent code-writing tasks: P3 discriminates on the exact `verdict=` token P2 emits, P2 governs
only the population P1 creates, and P1/P2/P4 are three guards inside one file (`bin/cc-backlog`)
that share its fold. There is no pair here that is independent (no shared file, no ordering
dependency) *and* separately verifiable — the CLAUDE.md test for a clean parallelization
opportunity — so splitting would add a merge seam through a single 200-line diff and buy nothing.
The read-only measurement phase that chose the design is already complete (below).

## The incident

`cc-backlog`'s event key is `project+title+source`, so two *wordings* of one condition hash to two
ids. Measured 2026-08-07:

| id | filed | source | title |
|---|---|---|---|
| `97f16b6709fa` | 08:47:44Z | `inertness-generator session 2026-08-07` | "inertness faces 3-4: activations-as-migrations + done moves one store right…" |
| `6078392359ac` | 08:47:54Z | `inertness-generator-successor` | "Faces 3-4 of inertness-generator-2026-08-07 §3 + F3 lint…" |

Ten seconds apart, same `project`, same `dodRef`, **neither carrying a `condition`**. Both were
claimed, both dispatched, and two worktrees built the same face-3/face-4 mechanism in parallel to
completion. `97f16b6709fa`'s own closing evidence records the collision: *"faces 3-4 proper were
landed by DUPLICATE-DISPATCH sibling 6078392359ac; this item delivered the surviving delta."* One
worker session, and one worktree's build, thrown away.

A session and its successor each filed the follow-on work. Neither could see the other's row — which
is the whole shape of the defect, and it decides where the fix can live.

## Two candidate predicates, both refuted by measurement

The item's own prescription was "apply the existing `--condition` re-key at dispatch". Measured
before building, on the live ledger (1257 `add` events):

**(a) `.condition` equality — structurally INERT.** `mk_cond_id` hashes `project+condition` into the
*id*, so two rows carrying the same condition are one row by construction. Replaying the ledger:

```
groups with >1 distinct id sharing (project, condition): 0
```

Zero, and not by accident — the id *is* the condition key, so the population a condition-lease would
govern cannot exist. A lease keyed on `.condition` alone could never fire, on any ledger. The
mechanism the item points at is real, but nothing can reach it: the field is settable only at `add`,
by a filer who by construction cannot see the sibling row. (memory:
`work-item-citation-refutes-its-own-remedy`.)

**(b) `.dodRef` equality — measurably HARMFUL.** Both incident rows *do* share a `dodRef`, so it is
the obvious automatic key. Replaying every claim interval in the ledger and counting pairs of
same-`dodRef` items whose claims *overlapped in time* — i.e. exactly the dispatches this lease would
have deferred:

```
same-dodRef groups with >=2 items:   23
CONCURRENT-CLAIM overlaps:           81   (in 7 groups)
  · 70 of them: docs/plans/ORCHESTRATOR_DESK_24X7_PLAN.md   (22 items — one plan, parallel phases)
  ·  5 of them: docs/research/BATS_DEAD_ASSERTIONS_2026-07-25.md
  ·  1 of them: the incident pair
```

≈1 true positive in 81 — a ≥98% false-positive rate, and the false positives are precisely the
Phase-0-orchestrated plans this repo *designs* to run in parallel. The incident's own doc refutes it
most sharply: `docs/research/inertness-generator-2026-08-07.md` holds **three** items, and the third
(`8e8a306f6dc0`, "postland auto-revert actuator is 12% effective") is unrelated work that overlapped
both duplicates. `dodRef` groups the duplicate *with* the non-duplicate, so it cannot separate them
even in the one case it was derived from.

`title` similarity is rejected for the reason already written into `cc-backlog`'s own header: the
ledger holds six more `MEMORY.md`-titled items that are different work, and no pattern separates
those from the 21 that were one condition. *"The caller knows which channel it is in; a regex does
not."*

## What is built

The condition is the right key; what was missing is a way for it to reach rows that **already
exist**, and an arbiter that honours it at dispatch time.

**P1 — `cc-backlog link <id> --condition <slug>`.** Attaches a condition to a row already minted.
Append-only; `fold()` already carries `condition: ($r.condition // $p.condition // "")`, so a `link`
record folds in with no schema change and no status change. This is what creates the population the
lease governs — two *distinct ids* sharing one condition, which `add` alone can never produce. Same
`valid_condition` digit guard as `add`, for the same reason. Changing an existing condition needs
`--force`; re-linking to the same slug is idempotent.

The declarer is the actor who can *see both rows* — a desk pass, a reaper, an agent reading the
ledger — not the filer who cannot. That relocation is the fix.

**P2 — the lease, in `cc-backlog claim` (guard 6).** When the claimed item carries a condition and
another item in the same project shares it and is claimed by a live worker, the claim is REFUSED
(rc 4) with `verdict=sibling-held` on line 1. Same three-valued oracle contract as the row lease:
`claimer_live` then `owned_wait`, and **only rc 1 (proven not-live) releases the lease** — an
abstention leaves the incumbent alone rather than minting a second worker.

*Placement deviates from the item's literal "fix belongs at the dispatcher", deliberately.* The item
is right about the **layer** — dedupe must happen at dispatch, not at `add` — but the mechanism
belongs to the actuator. `cc-dispatch`'s own step 5a says it: *"THE ACTUATOR IS THE ARBITER … this
caller must not re-implement."* A sibling check inside `cc-dispatch` would read the ledger and then
claim, and a concurrent pass can slip between the read and the append. `claim` already holds the
fold one step before the append, so the predicate is atomic there and nowhere else. (memory:
`make-the-actuator-the-arbiter`.)

Cost is gated by position, like guard (5): the sibling scan is unreachable for an item with no
condition, which is 1238 of 1257 rows today.

**P3 — `cc-dispatch` journals it as a DEFERRAL, not a failure.** `verdict=sibling-held` is
discriminated positively, exactly as `verdict=done-latched` is, and recorded `skipped`. A refused
claim appends nothing, so the item stays `open` and re-attempts next tick — the same shape as an
at-ceiling deferral, and it feeds no thrash record for a correct refusal. Counting it `failed` would
make healthy contention read as breakage *and* feed `thrash_map` fault records that eventually
`block` the item.

**P4 — `cc-backlog dups`, the detector.** P1+P2 are armed but never loaded unless something surfaces
the candidates — which is the inertness generator this item's own `dodRef` documents. `dups` reports
groups of ≥2 live (open/claimed) items sharing a `project`+`dodRef` and not already sharing a
condition. It **gates nothing**, so measurement (b)'s 98% false-positive rate costs nothing here: as
a report it is exactly the review queue where the duplicate is visible, and `link` is the one-line
answer. The signal that was too weak to be a gate is strong enough to be a hint.

## Considered and rejected: filtering sibling-held rows at the PULL

A sibling-held row is admitted, wave-planned, and only then refused at the claim, so it consumes one
admission slot per pass for as long as the sibling runs — and unlike `done-latched` (transient, the
item goes terminal) that can be hours. Moving the check to step 1b's pull filter would recover the
slot, and it would not violate the actuator-is-arbiter rule: cc-dispatch already pairs a cheap pull
filter with an authoritative claim-time latch for `wasDone`.

It is rejected anyway, because **neither version of it is affordable and correct at once**:

- The *correct* filter needs to know whether the sibling is **live**, which means `claimer_live` +
  `owned_wait` per candidate row at pull time. Those are per-item forks (`kill -0`, `lsof`), run
  today only when a claim is about to displace a holder. Paying them for every open item on every
  tick is a real cost regression on the hot path.
- The *cheap* filter — "a sibling is `claimed`", without asking liveness — is strictly **wrong**: it
  defers rows whose sibling is dead-but-not-yet-reaped, which the claim-time lease correctly allows.
  A filter that strands work the arbiter would have released is worse than the slot it saves.

So the admission slot is the correct price for asking the expensive question exactly once, at the
only moment the answer can be acted on. Revisit only with a measurement showing sibling-held
deferrals actually starving a wave — the population is empty today (0 linked pairs), so any sizing
now would be invented.

## Verification

`tests/cc-backlog-condition-lease.bats`, with the controls that keep it from passing vacuously:

- **CONTROL (the live defect, reproduced):** two rows, *not* linked → both claims SUCCEED. Without
  this pair a stub lease that refused nothing, or one that refused everything, passes green.
- **CONTROL (the lease must not stick):** a linked sibling whose claimer is *provably dead* and whose
  worktree is absent → the claim PROCEEDS. A lease that cannot be released is a permanent strand.
- Linked pair, live sibling → rc 4, `verdict=sibling-held`, refusal names the sibling id.
- `--force` overrides; a sibling in a different project does not lease; the digit guard refuses.
