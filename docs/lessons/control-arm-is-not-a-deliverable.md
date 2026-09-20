# A control-arm branch is not a deliverable — its finding is already in the log, and its bytes must never land

2026-09-19, cc-backlog `d1a914ca8fa1` — *"re-land control/gate-ab: ship-land could not complete and
its author's pane may be gone"*.

## The row is machine-minted, and it inherits none of the branch's intent

`scripts/ship-land.sh` files a re-land row on **every** land that fails after it has started — it
pins the head at `refs/land/failed/<ts>-<sid>-<branch>` and writes the row with a boilerplate title.
Nothing in that path asks what the branch is FOR, so an experiment scaffold gets the same row, the
same falsifier and the same dispatch slot as a stranded feature. The falsifier
(`land-content-verify.sh`) is honest and unhelpful in exactly the way
[[superseded-stranded-and-the-falsifier-cannot-tell-them-apart]] describes: it measured **2 of 2
paths hold content origin/main lacks — NOT landed**, which is true, and says nothing about whether
those bytes should ever be on trunk.

## What `control/gate-ab` actually is

Two commits (`d07e7b5fd`, `2be9d91ab`) off `307f9749d`, appending one line each:

```
hooks/anti-deference-nudge.sh       + "# control-arm probe: comment-only, no semantic change (ship-land gate A/B)"
tests/fixtures/jev-mock-gateway.mjs + "// control-arm probe: comment-only, no semantic change (ship-land gate A/B)"
```

The shell line sits **after `exit 0`**; both are comments. It is a control arm for the question
decision packet `73329c873224` puts to the operator: `tests/operator-surface-scope.bats` test 21
(*"LINT: the discriminator exists in exactly ONE place"*) has been RED on trunk since `3cdaa2552`
landed a second copy of the three-flag argv conjunction in `hooks/teammate-auto-shutdown.sh:320`,
and ship-land's gate then convicts **any** lander whose diff reaches a hook that suite exercises —
attribution by reachability, not causation (`gate-attributes-by-reachability-not-causation`).

## The A/B, re-run at a later trunk sha

The receipt (`~/.claude/autonomy/decisions/oss-lint-regression-receipt.md`, session `cb29ae36`) ran
its control at `origin/main` = `7985e60d9`. Re-run 2026-09-20T03:5xZ at `origin/main` = `ba466660a`,
two commits later, one variable — a detached worktree at trunk vs. a detached worktree at
`control/gate-ab`:

| arm | plan | ok | not ok |
|---|---|---|---|
| trunk `ba466660a` | `1..21` | 20 | **1** — test 21, `discriminator re-implemented in: hooks/teammate-auto-shutdown.sh` |
| `control/gate-ab` | `1..21` | 20 | **1** — identical |

Both arms print the plan line, so neither is a shed non-verdict
([[a-gate-refusal-is-not-a-gate-result]]). **The red replicates at a new trunk sha and the
comment-only diff causes nothing.**

## The finding was delivered before the row was filed — by the failure itself

The bats A/B can only show trunk is red. The control arm was built to show something stronger: that
the **gate** issues its false conviction over a provably semantically-null diff. It did, and the
proof is durable in `~/.claude/land.log` without any of its bytes reaching trunk:

```
03:04:05Z control/gate-ab exit 6 red=smoke:tests/operator-surface-scope.bats  selected_n=6
03:10:01Z control/gate-ab exit 6 red=smoke:tests/operator-surface-scope.bats  selected_n=7
```

So landing the branch would add nothing to the record and would put two meaningless probe comments
on trunk permanently, in a hook and a test fixture, for every future reader to decode.

## The blast radius, which the packet does not carry

Over all 6,202 `tool:"ship-land"` rows in `land.log`, **7** name this suite in their `red` field.
**6 of the 7 fall inside one 4h07m window** on 2026-09-19/20, across **4 distinct branches** —
`lesson/imported-threshold-range`, `wt-f0d14af080aa` (×2), `control/gate-ab` (×2),
`feat/kitty-equalize-chords`. Each refusal auto-mints its own re-land row, so one open decision is
converting itself into dispatch traffic. That is a fact about urgency, not a new defect, and it
belongs on the packet rather than in a new row.

## The rule

**Read the branch's PURPOSE before landing its bytes.** A re-land row is minted by a failure path,
not by anyone deciding the work should ship; `git log` on the branch and the branch NAME are the
cheapest discriminators there are. When the branch is an instrument — a control arm, a bisect
probe, a fixture spike — the deliverable is the measurement, which is already written wherever the
instrument ran. Close the row with the finding and say where it lives; do not re-derive it, and do
not land the scaffold.

Companion: [[superseded-stranded-and-the-falsifier-cannot-tell-them-apart]] (a falsifier measures
BYTES, so NOT-REFUTED never means the work is owed) and
[[the-blocking-gate-was-stricter-than-the-repo-s-own-verifier]].
