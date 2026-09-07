# The post-land conviction that named `e39aa0be1546` is false at its own tree

**2026-09-07.** Adjudication of backlog `35d1f6ded206`
("post-land AUTO-REVERT FAILED(step=revert rc=90): tests/autonomy-sweep.bats @ e39aa0be1546").

## Verdict: the premise is refuted by execution

`tests/autonomy-sweep.bats` passes at the exact tree the verifier stamped RED.

| where | plan | rc | `not ok` |
|---|---|---|---|
| `e7a10f4fa5a4` — the tree stamped `verdict:"red"`, `failing:[…autonomy-sweep…]` | `1..67` | 0 | 0 |
| `a4674b4c1` — trunk today | `1..67` | 0 | 0 |

Run in a disposable detached worktree on a quiet box, `bats tests/autonomy-sweep.bats`.
`e39aa0be1546` did not break the suite, and no later commit cured it — there was nothing to cure.

The other three suites convicted in the same run are green on trunk as well:
`goal-inert-watch` `1..28`, `handoff-fire-completion-push` `1..11`, `idle-slope-sweep` `1..16`,
each rc 0 / 0 `not ok`. Four of four convicted files pass.

**The `rc=90` in the item's title is the good news, not the defect.** `revert=none`, `land_exit=90`
in `~/.claude/autonomy/postland/reverts/e39aa0be…` means the revert *conflicted and applied
nothing*. A culprit whose lines happened not to have moved would have reverted cleanly and the land
lane would have pushed a revert of a correct commit to trunk — the `f323b427` shape (2026-08-06),
reached again on 2026-09-04 and repaired by `1f5385f9b` ("re-land the cloud-return stratifiers the
auto-revert took on a CUT"). On 2026-09-05 a merge conflict is the only thing that stood between a
false conviction and a reverted-innocent trunk.

## Why the stored falsifier could not say so

`postland-verify.sh --falsify-red` exits 0 only when a full-corpus green **contains** the accused
commit. `last-green` is `24c598bac1c7` — **257 commits behind `origin/main`**, and `e39aa0be1546`
is not its ancestor. So the probe returns 1, "still live", correctly and uninformatively: it is a
fact about the absence of a green stamp, never a fact about the file. While the corpus does not
certify, no item in this class can ever retract, whatever the suite actually does.

## The convicted population is two stable sets alternating

`56b39811eddc` (open) already records that consecutive REDs are disjoint. The stamps say *why*, and
the shape is not a reroll — it is a clean A/B/A/B:

```
2026-09-05 10:23Z  RED  n=10  {bats-assert-liveness, cc-offload, cc-reaper, compressor-sentinel, …}   A
2026-09-05 13:37Z  RED  n=4   {autonomy-sweep, goal-inert-watch, handoff-fire-completion-push, …}     B
2026-09-05 17:46Z  RED  n=9   A                                                                        A
2026-09-05 20:55Z  RED  n=4   B   ← the run that convicted e39aa0be1546
2026-09-06 01:13Z  RED  n=8   A
2026-09-06 04:30Z  RED  n=3   B
```

Consecutive overlap is zero; alternate-run overlap is total. The mechanism is C29 meeting *A VERDICT
SPENDS THE CANDIDATES* (`scripts/postland-verify.sh:3211`) on a box where the ladder convicts both
sets on every sweep:

1. Set B is ladder-convicted at run *n* → one window only → `C29 PENDING`.
2. Set A is ladder-convicted at run *n* for the second window → `CORROBORATED` → the run stamps RED
   on set A, and that verdict spends set A's candidate rows.
3. At run *n+1* set B reaches its second window → RED on set B; set A restarts from window 1.

So under sustained saturation C29 does not suppress load-attributable convictions — it **halves
their rate and makes them alternate**, and each one still arms `git bisect` and AUTO-REVERT. The
gate is separation *in time*, which the clock always satisfies (`postland-verify.sh:660`); time
separation decorrelates nothing when the box is loaded for days.

Corpus-wide, over the 578 stamps on disk (176 red, 86 green): **53 of 175 consecutive red pairs are
disjoint — 30.3%.** C29's own pre-ship measurement was 7/34 (20.6%) before C24 and 7/47 (14.9%)
after. The fingerprint has grown since C29 shipped, not shrunk.

## What is deliberately *not* prescribed here

The obvious remedy — refuse to convict while the box is loaded — is forbidden by a shipped guard.
`postland-verify.sh:3707` asserts by statement position that no `if`/`while`/`until` branches on the
recorded load, because a quiet-box wait recreates the `gate_admit` deadlock (R1,
`LOAD_INSENSITIVE_VERIFY_V2.md`: "any design whose success requires load to fall is already
failed"). Load is recorded as evidence and never tested. A remedy therefore has to trade against
either that invariant or candidate-spending's own documented rationale, and which one to give up is
a judgment about how aggressively trunk may be auto-mutated — not a defect with one right answer.

`56b39811eddc` owns the population question and asks for exactly the characterisation above; its
falsifier ("two consecutive REDs sharing >50% of their failing set") remains unmet at 30.3%
disjoint. The auto-revert exposure is filed separately.

## Addendum — set A's `lead-crash-watchdog` conviction was TRUE, and cured before this doc

**2026-09-07.** Adjudication of backlog `d90a582dfd5d`
("post-land RED: tests/lead-crash-watchdog.bats::deliberate recycle via DISPOSITION: CLOSE
phrase → RECYCLE"), the set-A row filed on the 10:23Z run above and re-titled on each of the
next three convictions.

The verdict here is the **opposite** of the set-B adjudication at the top of this file, and the
difference matters for `56b39811eddc`: the alternating population is not uniformly false.

| where | `ok` | `not ok` |
|---|---|---|
| `678728f015a0` — first convicted tree | 29 | **6** |
| `f535c6eaec1a` — last convicted tree | 29 | **6** |
| `e4193e24a` — trunk today | 35 | 0 |

Run from `git archive <sha>` into a disposable directory, `bats tests/lead-crash-watchdog.bats`,
box at load 12.6 — i.e. reproduced *deterministically*, and reproduced under exactly the load the
alternation hypothesis blames.

The failure is a real `set -u` defect, and it printed its own diagnosis on every red test:

```
hooks/lead-crash-watchdog.sh: line 363: pane: unbound variable
```

`classify_death()` declared `local reg_hit pane` — a declaration, not an assignment — and arm 1.6
opens by reading `[[ -z "$pane" ]]` on precisely the path where the registry lookup never assigned
it. Cured by **`a29ecb5275b5b13b88091814ecb31bacd0ab8b18`** ("initialise `pane`, which set -u made
fatal on the common path", 2026-09-06T12:34Z), which changed the declaration to
`local reg_hit="" pane=""`.

**Every one of the four convicted shas is an ancestor of that fix**, and the last conviction
(11:14:43Z) precedes it by 80 minutes. So the row is not a false positive being re-derived — it is
a true positive whose cure landed while the row was still open, and no arm of the ledger noticed:
`--falsify-red` cannot retract while `last-green` trails trunk (§ "Why the stored falsifier could
not say so" above applies unchanged), and a condition-keyed row carries no re-check of its own.

**Consequence for the remedy question.** The obvious remedy this file declines to prescribe —
suppress convictions while the box is loaded — would have suppressed *this* conviction, which was
correct, reproducible on a loaded box, and named the right suite four times running. Alternation
is evidence about the *scheduler*, not about the truth of any member. Set membership is not a
verdict; the only thing that settles a member is executing it at its own tree.
