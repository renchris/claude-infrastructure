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

## Addendum — the remedy this file declined to prescribe, found: probe the FLOOR, never the load

**2026-09-08.** Backlog `799ec26e3a74`. Shipped as **C30** in `scripts/postland-verify.sh`.

This file left the remedy open because both candidate levers were forbidden: suppressing convictions
while the box is loaded recreates `gate_admit` (R1), and the addendum above shows it would have
suppressed the `lead-crash-watchdog` conviction, which was *true*. The lever it did not consider is
the one its own last sentence names — *"the only thing that settles a member is executing it at its
own tree."* Generalised: execute it at a tree we already **certified**.

### The state the wedge had reached

The alternation did not stay at halved-and-alternating. By 2026-09-08 it was total: **20 consecutive
sweeps — 18 RED, 2 CUT, 0 GREEN**, `last-green` frozen at `24c598bac1c7` since 2026-09-03 and now
past `SCAN_N=200`, so `deploy-live --dry-run` reports `no GREEN stamp among the newest 200 commits`.
Not "trunk is broken" — the green it needs scrolled off the window. The A/B alternation of §3 with
its period intact, read off the C29 log lines:

```
11:22 handoff-fire CORROBORATED (RED) · idle-slope PENDING
14:44 backlog-pipeline, cc-pane, cc-reaper, goal-inert, idle-slope CORROBORATED (RED)
17:54 backlog-pipeline PENDING → CUT
21:03 compressor, handoff-fire CORROBORATED (RED) · cc-reaper, goal-inert, idle-slope PENDING
00:28 cc-reaper, idle-slope CORROBORATED (RED) · compressor, handoff-fire PENDING
```

`conviction_observe`'s awk matches **`$2==f` — the file alone**, no tree and no sha. So window 1 on
tree A corroborates window 2 on tree B, and `conviction_clear` preserving exactly the *pended* set
guarantees the next sweep inherits it in-TTL. Two windows, one experiment.

### The evidence was already being computed — 19 minutes too late

The same 00:28 run that stamped RED on `cc-reaper` logged, afterwards:

```
bisect FLOOR NOT GREEN: … tests/cc-reaper.bats is not green at 24c598bac1c7 either (runner rc=1)
```

`24c598bac1c7` is `last-green` — the commit whose tree **this verifier stamped GREEN**, i.e. one on
which every suite passed. A suite failing there *now* is proven non-deterministic by our own prior
verdict, so its failure says nothing about the tree under test. `bisect_floor_ok` knew and discarded
it as `undecidable, no culprit named`, because it runs after `write_stamp` and only ever needed to
name a culprit. C30 asks the same question one step earlier, where the answer can still change the
verdict.

### Why this is not the forbidden lever

It never reads load — the `if|while|until … (loadavg|load1)` guard at the C29 selftest passes
unchanged. It branches on a **test result at a different commit**, which is how it gets
load-insensitivity without a quiet box (R1: "any design whose success requires load to fall is
already failed"). And it is strictly weakening in one direction:

| floor probe | meaning | verdict |
|---|---|---|
| rc 1 | the failure predates the window | not differential ⇒ flake, recorded |
| rc 0 | the floor really is green | differential ⇒ **RED stands, unchanged** |
| 124 / >128 / 126 / 127 / unresolvable / unreachable / file absent at floor / cell not restored / renamed test | no verdict | **RED stands, unchanged** |

Absence of evidence never exonerates; only a positive reproduction does. So it settles the two cases
this file proved must be told apart, and settles them the right way round: set B (`autonomy-sweep` et
al., green on a quiet box) reproduces at the floor and is dropped; `lead-crash-watchdog` **passed**
at the floor — the `set -u` defect postdates it — so its conviction is differential and survives.
Bounded by `FLOOR_BUDGET` (6 probes/run, each under `FILE_TO` in the retry band); files past the
budget keep their conviction **unprobed**, so a run where the whole corpus is flaking cannot
exonerate its way to an unearned green.

Red-proof, run as a control rather than asserted: `CC_POSTLAND_FLOOR_EXONERATE=off` reproduces the
pre-fix RED on the identical fixture (`--selftest`, 66 passed / 0 failed).

**Still open:** `56b39811eddc` owns the population question, and C30 does not answer it — a suite
that is chronically load-flaky is still chronically load-flaky, now recorded as
`"outcome":"floor-not-differential"` in `flakes.jsonl` instead of blocking every deploy. That ledger
is the queue for fixing them.

## Addendum 2026-09-09 — the floor C30 probes against ROTS, and only a green can refresh it (C31)

The table above ends four of its rows in **RED stands, unchanged**: *file absent at floor*, *renamed
test*, *unresolvable*, *unreachable*. Those are correct as fail-closed outcomes and they are also a
**rate**, and nothing until now measured which way that rate moves. It moves the wrong way: `$LASTGREEN`
advances on exactly one event — a GREEN verdict — so during an outage the control drifts further from
trunk every sweep while the share of convictions it cannot reach rises. The exonerator's power is a
function of the outcome it exists to make reachable. A bootstrap circle
(memory `deployed-layer-bootstrap-circle`), and the reason it is not merely theoretical is that this
box has been inside it since 2026-09-03.

**Measured 2026-09-09**, live `$LASTGREEN` = `24c598bac1c7` (2026-09-03, **428 commits** down), against
the suites carrying the recent convictions — the count in brackets is appearances in the newest 60
stamps' `failing[]`:

| suite | at the floor | consequence for a C30 probe |
|---|---|---|
| `tests/drain-brief.bats` (5) | **does not exist** | `floor N/A … differential by construction` — a *false* label: a new file is UNMEASURED at the floor, not proven regressive |
| `tests/cc-reaper.bats` (10) | +22 test names since | the `-f` filter can match nothing ⇒ `tap_plan 0` ⇒ rc 126 ⇒ conviction stands |
| `tests/goal-inert-watch.bats` (7) | +14 test names since | as above |
| `tests/autonomy-sweep.bats` (5) | +10 test names since | as above |
| `tests/deploy-parity.bats` (2) | +9 test names since | as above |

Those five are precisely the chronic flakes C30 was built to exonerate. Verdict mix over the same
window: **29 red · 22 cut · 9 green**, and every one of the 9 greens is dated 2026-09-01…03 — none
since. Median load barely moved across the regime change (15–17 → 16–23), which is the second reason
this is not a load story.

### C31 — a PER-FILE floor, written by the sweeps that are already happening

A whole-tree green is a **stronger** claim than the probe uses. The probe asks one question about ONE
file — *was this suite ever observed to pass at a commit below the one under test?* — and every
plan-complete corpus run already answers it for the ~590 suites that did not fail, **red runs
included**. `passes_record` writes that complement to `$STATE/passes` (`<file>\t<epoch>\t<sha>`), and
`floor_exonerates` prefers the file's own row over `$LASTGREEN`, falling back when there is none. The
floor for a chronic flake becomes ~3.2 h old (the sweep period) instead of six days, and it refreshes
on the reds — which is the property that breaks the circle.

Nothing about the probe's meaning changes; only the control does, from *"a tree on which every suite
passed"* to *"a commit at which THIS suite was observed to pass"*. Because the per-file floor is
NEARER, the differential window it spans is SMALLER, so a genuine regression is convicted at least as
readily as today. Four guards make the write side the conservative one — a row is written only from a
run bats reported no shortfall for, that exited 0 or 1, that completed exactly the tests it planned,
and in which every `not ok` was attributable to a file; a file with ANY not-ok is excluded even when
the ladder later cleared it, so *passed* means passed outright, never passed-on-retry. One extra
ancestry check the whole-tree floor gets for free: a per-file floor must be an ancestor of the tree
under test, or it is not a floor.

**The bug worth recording**, because it makes the clause an elaborate no-op wearing C30's behaviour
and it survived a first implementation: dropping every CORPUS file's row and re-adding the passers is
not equivalent to dropping only the passers' rows. A chronic flake fails in the very sweep that
convicts it, so its prior floor is erased seconds before `floor_exonerates` reads it, and the probe
falls back to `$LASTGREEN` every single time. A file that failed KEEPS its last observed pass.

**Red-proof, run as controls rather than asserted** — `tests/postland-verify-passfloor.bats`:
`CC_POSTLAND_PASS_FLOOR=off` reproduces the pre-fix RED on the identical fixture, and a suite that
PASSES at its own per-file floor and fails at the tip still REDs. Kill switch `CC_POSTLAND_PASS_FLOOR`;
`CC_POSTLAND_PASS_TTL_S` (7 d) bounds staleness, `CC_POSTLAND_PASS_KEEP` bounds the store.

**Still open, and unchanged by this:** `56b39811eddc` still owns the population question. C31 makes the
gate reach a verdict about the tree in the presence of chronically load-flaky suites; it does not make
them less flaky, and `flakes.jsonl` remains the queue for fixing them.
