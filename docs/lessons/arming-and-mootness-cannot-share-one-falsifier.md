# A falsifier field holds ONE question, and "not needed" and "now possible" are opposite ones

**Found:** 2026-09-17, driving cc-backlog `2a65b9bf722d` ("ProposeGoal (`tengu_propose_goal`) is
default-off upstream — adopt when the flag flips"). **Live for nine days.** No incident fired,
because the defect's whole shape is that it discharges silently at the one moment anybody would
have cared.

## The rule

A work item's `--falsifier` answers exactly one question — **is this row still needed?** — and its
consumer acts on exit 0 by **closing the row**. A `not-yet-true` row is watching a *precondition*,
and a probe that detects the precondition ARRIVING answers the opposite question: **is this row now
possible?** Wire the second into the first field and the row deletes itself at the instant it
becomes actionable.

**Before storing a probe as a falsifier, say its exit 0 out loud as a sentence about the ROW.** If
it reads *"…so there is nothing to do"* it belongs in the field. If it reads *"…so go do it"* it
does not, and it needs a different owner — one that PAGES.

## What was actually wired

Three facts, each individually correct, composing into the inversion:

1. `bin/cc-premise:1370,1402` — `run_falsifier` reads exit 0 as *"the condition this item was filed
   for is GONE"*, verdict `falsified`, and prints *"Close it citing this run"*.
2. `scripts/autonomy-sweep.sh` §2b-iii runs `cc-premise sweep --record --close-falsified 25` every
   6 h. `_close_falsified` calls `cc-backlog done`. It skips `done`, missing and `claimed` rows —
   **and nothing else. A `blocked` row is NOT skipped**, so parking a row does not protect it.
3. The row stored `propose-goal-flag-watch.sh --falsify`, which exits **0 when the flag flips true**.

So the row titled *adopt when the flag flips* was wired to auto-close **when the flag flipped**, with
evidence reading "falsifier passed — the condition is GONE".

## The proof, because reading the code is not the measurement

One fixture — a cache carrying `cachedGrowthBookFeaturesAt` fresh and
`{"tengu_propose_goal":true}` — run through the real `cc-premise`:

```
$ PGW_CONFIG_PATHS=<flipped>  cc-premise check 2a65b9bf722d     # pre-fix store
  FALSIFIER PASSED — ... the condition it was filed for is GONE.
  Close it citing this run (cc-backlog done 2a65b9bf722d --evidence "falsifier passed: ...")
  verdict=falsified
$ cc-premise check 2a65b9bf722d                                  # live control, same moment
  verdict=clear
```

The control matters: it proves the flipped fixture — not the tree, not the box — produced the close.

## The fix, and why it is two halves

**Half one, the store.** The field now holds `--moot`: exit 0 **only** when `ProposeGoal` is absent
from a subject that passes its own tripwire (`--binary` rc 3) — adopting a removed feature is not
work. A flip lands on rc 1. Same fixture, post-fix: `verdict=clear`.

**Half two, the owner — and shipping half one alone would have made things WORSE.** `--moot` is
correct and *silent about the flip*, so removing `--falsify` from the store without replacing it
leaves the arming event owned by nothing: strictly less observable than the defect. The flip got its
own arm in `scripts/autonomy-sweep.sh` §2b-iii-b, which **pages the desk and touches no store**.
This repo's own §2f names the flagship version of that failure — a detector built, selftest green,
and never called. *The caller lands in the same diff as the tool.*

## How to check your own store

```sh
cc-backlog list --open --json | jq -r '.[] | select((.whyNotNow//"")|startswith("not-yet-true"))
                                            | "\(.id)\t\(.falsifier // "(none)")"'
```

Measured that day: 9 open `not-yet-true` rows. Six were correctly polarised (a re-land row's
`land-content-verify.sh` exit 0 = *the content IS on trunk* = moot ✓). Two carried prose that
cannot execute and fail open (rc 127, rc 2) — harmless, and worth knowing they are inert rather
than passing. **One — this one — was the live inversion.** So this is a trap the field invites, not
a class defect: check the sentence, per row.

## The companion lesson

The house rule that produced it reads *"`not-yet-true` (an external precondition has not happened —
pair it with a `--falsifier`)"* and, two clauses later, *"ideally as a `--falsifier` **so it
self-retracts**"*. Both halves are reasonable and together they invite exactly this: the natural
probe for "has the precondition happened" is the arming probe, and the field it is being offered
retires the row. **A field that means one thing, offered for a class whose natural probe means the
other, will be filled wrong — and the wrongness is invisible until the day it fires.**

Related: `detector-with-no-owner-is-not-an-actuator`, `probe-that-acts-on-absence-must-confirm-presence`,
`falsifier-polarity-inverted-under-no-run`, `a-falsifier-resting-on-a-frozen-pointer-is-inert`.
