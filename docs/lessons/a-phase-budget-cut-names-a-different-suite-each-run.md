# A phase-budget cut names a different suite each run — and that variance is the discriminator

**2026-09-19 · scripts/ship-land.sh smoke phase · measured over two consecutive land attempts**

## The rule

When a gate bounds a whole PHASE rather than each suite, the suite it kills is simply whichever one
was mid-run when the clock expired. Its summary arm may still report that kill as a failure
attributed to your diff. **Re-run it: if the named suite CHANGES, the verdict is a budget artifact,
not a finding about your tree.** If the same suite is named twice, you have a real suspect.

## The incident

Two consecutive `ship-land.sh` runs on the same commit, no edits between them:

| run | suite named | `not ok` lines in the whole log |
|---|---|---|
| 4 | `tests/it2-kitty-composer-guard.bats` | **0** |
| 5 | `tests/host-identity-flip.bats` | **0** |

Both were reported identically:

```
⛔ gate: GATE-KILLED: tests/<suite>.bats — cut by the smoke budget (exit 124, ZERO 'not ok')
   … It is NOT a red and NOT evidence about your tree.
⏱ gate: smoke budget 900s exhausted — remaining suite(s) not started, land PROCEEDS
✗ gate: smoke RED — 1 of 12 direct suite(s) named a failure (1 mapped to YOUR diff).
  This is a VERDICT about your diff (O(diff), reproducible): fix it, do not retry unchanged.
```

The gate says both things at once: line 1 says the cut is *not* evidence about the tree, line 3
calls it a reproducible verdict about the diff and forbids retrying unchanged. Line 3 is the one a
reader acts on, and it is the wrong one.

## Why the attribution is wrong in three independent ways

1. **Kill ≠ failure.** `exit 124` is the timeout, and there were ZERO `not ok` lines anywhere in
   either run. Nothing asserted and failed. (Companion: *Killed pipe = no verdict*, *Gate refusal
   ≠ gate result*.)
2. **Reachable ≠ caused.** "Mapped to YOUR diff" means the suite is *reachable* from a file the
   diff touches. The diff touched `bin/it2-kitty`; `it2-kitty-composer-guard.bats` tests the
   `close` subcommand, while the change was in the `session split` branch — not reachable at
   runtime at all. `host-identity-flip.bats` is unrelated to every file in the diff.
3. **The cost was not the suite's.** Run standalone on the same branch,
   `it2-kitty-composer-guard.bats` is **green, 47/47, in 23 seconds.** It cannot consume a 900s
   budget; it was merely the one holding the clock when the phase ran out.

## The cheap discriminator, in order

1. `grep -c '^not ok'` the WHOLE log. Zero ⇒ nothing failed, whatever the summary says.
2. Re-run unchanged. A **different** suite named ⇒ budget artifact. The **same** suite ⇒ suspect.
3. Run the named suite ALONE and read its own seconds. A suite that finishes in 23s did not spend
   a 900s budget.
4. Only then ask whether your diff is reachable from it *at runtime*, not merely by file.

## Method warnings this cost

- **Do not `tail` a gate log inside the command that produces it.** `bash ship-land.sh 2>&1 | tail -25`
  discards the per-suite progress that names what actually consumed the budget — and that is
  precisely what you need when the summary is untrustworthy. Capture the whole log; tail it when
  reading.
- **A budget raise is the sanctioned cure here, and it is not laundering** — the gate itself names
  `SHIP_LAND_SMOKE_BUDGET_S`. But ground the new value in a measurement (the standalone seconds,
  and how many suites never started), never in a guess, and say in the close which arm you
  overrode and why.
- Budget exhaustion ALONE does not block: the gate attests `smoke:"partial"` and proceeds. What
  blocks is only the summary counting the cut as a named failure.

## The third instance — same advice, and this time the suite really was red

A later pass of the same land raised the budget to 2700s, which took the gate from 12 direct suites
to **46** and surfaced a genuine failure: `tests/deploy-link-parity.bats` → *"every forward-walked
directory is either stray-swept or declared NOT-STRAY-SWEPT"*, 2 real `not ok` lines. The summary
was identical in shape — `smoke RED — 1 of 46 direct suite(s) named a failure (1 mapped to YOUR
diff). … fix it, do not retry unchanged.`

It was still not the lander's. That test derives all three of its sets from
`scripts/deploy-link-parity.sh`, a file the diff never touched; the unclaimed directory was
`scripts/jev`, added to the forward-walk by a **sibling session's** commit made during the same
hour, whose matching `sweep_strays` entry landed one commit later. The branch sat on the base
between the two.

**So "do not retry unchanged" was exactly inverted**: the input that changed was TRUNK, and the cure
was a rebase. Obeying the instruction would have meant hand-patching another session's file to fix a
bug they had already fixed.

⇒ Generalise the discriminator past the budget case: **when a gate attributes a failure to your
diff, ask what the failing assertion actually READS.** If its inputs are files you did not touch,
the verdict is about the tree you are sitting on, not about your work — `git fetch` and compare
trunk before you change a line. The three instances here (two budget cuts, one sibling red) share
one root: the gate maps by *reachability from changed files* and reports that mapping in the
vocabulary of *causation*.
