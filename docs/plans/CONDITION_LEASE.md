---
status: complete
created: 2026-08-07
closed: 2026-08-13
---

# CONDITION LEASE — one condition, one worker

**Item:** backlog `0bded74c6fa2` (claude-infrastructure) · created 2026-08-07

**CLOSED 2026-08-13 (backlog `01edea637633`).** P1–P6 are built, and every one of them is now
reachable by something that runs: `link` and the claim-time lease by the actuator, `dups` by
`backlog-consolidation-trigger.sh --fold` (dry-then-apply, from the autonomy sweep), and `backfill`
by the sweep arm P6 added — the last zero-caller in the set. Suites:
`tests/cc-backlog-condition-lease.bats` (21) · `tests/cc-backlog-dups-family.bats` (22) ·
`tests/autonomy-sweep.bats` P6 (3, red-proofed against a pristine tree).

**Deliberately NOT in this plan, and still open elsewhere.** (a) `backfill` proposes and does not
write — the flip to `--apply` is a measurement the P6 arm now produces rather than a step this plan
withheld; see P6 for the criterion. (b) The **mint side** of `b0b83b6c5845` — teaching
`postland-verify.sh` to file with `--condition` — belongs to M-landgate-2 and is what would make the
normalised-title key load-bearing again.

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

### P5 — the key was a field most rows do not carry (2026-08-11, backlog `7ff1b6f5ddbb`)

P1–P4 all work, and between them they still could not reach the population they were built for,
because **both halves keyed on something optional**. Measured over the live ledger on 2026-08-11:

- **`dups` was blind to 77% of live work.** 206 of 269 live rows carry no `dodRef` at all, so the
  P4 detector's grouping key does not exist on them. The family this was filed about —
  `memory-index-over-budget` — is entirely inside that blind spot.
- **`link` fires only when a human notices.** SEVEN link records exist in the ledger's whole
  history, six written inside eleven seconds on 2026-08-08T04:14 by one hand-driven sweep. Nothing
  backfills, so a row filed before its family had a condition never joins it. `2b6cc6a5116a` was
  dispatched 2026-08-08T04:08 — two days after the condition key landed — and joined by hand six
  minutes later. That same family still had two live orphans nobody had linked (`cf6eb3e47b12`,
  `152e9cacc8aa`), which is what this item found.

`dups` therefore gained two more keys for the dodRef-less population, and `backfill` turns the
second into the `link` it implies. **P4's conclusion is unchanged and is why `backfill` still asks:**
it dry-runs by default and writes only under `--apply`, because a wrong join is strictly worse than
a missed one — `link` feeds the P2 lease, so a false join REFUSES a live worker onto work that is
not duplicated, and nothing downstream reports the move.

**What the measurement changed about the design.** The obvious implementation — group dodRef-less
rows by title similarity — was built and REJECTED against its own numbers. Two natural formulations
both put the two *known* true positives at the corpus median:

| signal | true positives | corpus p50 / p90 |
|---|---|---|
| IDF-weighted containment over all title words | 0.325 / 0.305 | 0.239 / 0.333 |
| containment of the condition slug's own vocabulary | 0.442 / 0.442 | 0.424 / 0.591 |
| **IDF-weighted containment over IDENTIFIERS only** | **0.659 / 0.456** | **0.080 / 0.264** |

(The first two rows are the rejected prototypes; the third is what the shipped scorer prints, with
its smoothed `log((N+1)/(df+0.5))` — the unsmoothed form returns 0 for a token every row carries,
which is a rounding detail on the live ledger and a zeroed denominator on a 3-row fixture.)

This ledger is one voice writing about one machine, so prose is shared by everything and cannot
discriminate; what a row is *about* — `memory.md`, `cc-backlog`, `postland-verify.sh` — can. Two
floors ship together (`shared >= 3`, `frac >= 0.40`) because the fraction alone is a
small-denominator trap: three live rows scored a perfect 1.0 on ONE shared identifier each. Both
floors together select, out of 182 live orphans, exactly the two true positives and nothing else.
Both are flags, because these are thresholds over a living corpus (memory:
`published-figure-decays-with-its-source`).

**The second key reports zero live groups, and that is deliberate rather than inert.** Normalised-
title identity targets the post-land scanner's `… @ <sha>` rows — 57 open on 2026-08-09 per sibling
item `b0b83b6c5845`, down to 5 unrelated rows two days later. The population aged out between the
filing and the fix (memory: `scan-revision-predates-the-fix`), so its ability to group is pinned on
a fixture replaying that incident sha for sha, not on the live store. **The mint side of
`b0b83b6c5845` — teaching `postland-verify.sh` to file with `--condition` — is NOT done here;** it
belongs to M-landgate-2 and is what would make that key load-bearing again.

### P6 — the remedy for "nothing backfills" was itself backfilled by nothing (2026-08-13, backlog `01edea637633`)

P5 diagnosed the reachability failure exactly right and then reproduced it one layer up. Its finding
was *"`link` fires only when a human notices"* — seven link records in the ledger's whole history,
six of them written inside eleven seconds by one hand-driven sweep. Its remedy was `cc-backlog
backfill`, which proposes the joins that sweep would have made. Measured on trunk 2026-08-13:

```
callers of `cc-backlog backfill` anywhere in the repo: 0
```

Not in `scripts/autonomy-sweep.sh`, not in a plist, not in any script. The only two mentions are a
comparison in `backlog-consolidation-trigger.sh`'s header and a line in `commands/compact-memory.md`.
So the family key reached the lease exactly as often as before the fix — when a human happened to
look — and P5's own measurement is what says how often that is. Its two named live orphans
(`cf6eb3e47b12`, `152e9cacc8aa`) were still unjoined when P5 shipped, and nothing since could have
joined them. (memory: `feature-durability-mechanism-not-memory`.)

Every sibling key in this subsystem already had a caller: the mechanical fold runs dry-then-apply
from `autonomy-sweep.sh` §2b-i, the semantic grouping sweep from §2b-ii. This one did not, which
makes it the fifth zero-caller in the same subsystem — the shape the sweep's own comments call
"this wave's own defect".

**What is built:** the caller, at `autonomy-sweep.sh` §2b-i-b, journalling `backfill_rc`,
`backfill_note`, `backfill_proposed`, `backfill_ambiguous` into the `backlog-health` IDL record
beside the fold's fields.

**It is a DRY RUN, and the fold's flip criterion deliberately does not transfer.** The fold writes
unattended because it asserts CONSERVATION per run — a machine-checkable statement that its key did
not merge across a distinction. `backfill` has no such assertion and cannot have one: its key is a
scorer over a living corpus, and P5 above already fixed the position this caller must not quietly
overturn — *2 hits in 182 orphans on ONE day's ledger is evidence for a review queue, not for an
unattended writer*. The asymmetry is what prices it: a missed join costs one duplicate dispatch; a
wrong join feeds claim guard (6) and REFUSES a live worker onto work that is not duplicated, with
nothing downstream reporting the move. **The flip is a measurement this arm now produces** — when
`backfill_proposed` is small and stable across a run of sweeps and its named proposals have been
spot-checked, add `--apply`. `backfill_note` must never read `no-verdict` on the sweep that flips.

**It runs every sweep, and that is measured rather than assumed.** One `fold | jq` pass, no per-item
forks: **0.43 s over a 2400-record / 600-item ledger** (0.21 s at 600 records), against the currency
pass beside it that costs 106 s and had to buy a 6-hour interval gate. Sized on a store the size of
the real one (memory: `bound-must-fit-the-band-not-the-bench`).

**The verdict is parsed, never inferred from rc.** `backfill` exits 0 both on a clean store and on
one it could not read past the bound, so the exit code cannot separate "nothing to join" from "no
answer" — the exact conflation the fold arm next to it spent 10 of 10 runs paying for. A count that
does not parse is `no-verdict`, which is its own state (memory: `claimed-outcome-vs-checked-outcome`).

Verification lives in `tests/autonomy-sweep.bats`, three cases, all three red against a pristine
`git archive HEAD scripts/` tree: the arm fires and journals a depth · **CONTROL — it joins nothing**
(the orphan is still un-conditioned and zero `link` records exist, with a positive control proving
the same fixture *does* join under `--apply`, so the case cannot pass because the key found nothing)
· an unreadable answer is `no-verdict` and never a healthy zero. The control also asserts
`backfill_note` is `ok`, without which it would pass vacuously on a tree that has no caller at all —
which is the state it exists to prevent returning to.

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

`tests/cc-backlog-dups-family.bats` owns P5's two added keys and `backfill`; `tests/autonomy-sweep.bats`
owns P6's caller. The controls that keep each from passing vacuously are named in their own headers —
`--mode dodref` must find NOTHING over a dodRef-less fixture, both family floors are pinned in both
directions, and the P6 dry-run case asserts the arm RAN before asserting it wrote nothing.
