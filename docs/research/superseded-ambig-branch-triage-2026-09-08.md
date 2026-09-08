# Triaging the SUPERSEDED-AMBIG local branches — 2026-09-08

Closes cc-backlog `806277b4eb8b` ("triage the 61 non-backup SUPERSEDED-AMBIG local branches —
paths since rewritten on main usually means landed-in-reworked-form but can hide a dropped hunk;
needs a per-branch adjudication wave"), filed 2026-08-16 from `fire-r2-recovery T5`.

## The answer

**No dropped hunk exists in this population.** All 160 branches adjudicate to landed-in-reworked
form, in-flight, or benign — the item's own hypothesis, now measured rather than assumed. One
branch briefly read as a genuine recovery and was refuted by a fact no content test can see: a
live worktree is standing on it.

The durable output is not this verdict, which rots. It is `scripts/branch-adjudicate.py`, which
re-derives it in one command, plus the two controls that make it falsifiable.

## Why the item existed

`scripts/branch-prune-landed.sh` proves landedness by PATCH EQUIVALENCE and refuses everything
else, calling it "real stranded work" (`:13-17`). That refusal is right about ancestry and wrong
about rework: a branch whose work landed RE-DERIVED — rewritten by hand on trunk rather than
cherry-picked — has no patch-equivalent commit, so the pruner holds it forever. The class is
therefore a permanent accumulator, and nothing adjudicated it.

It grew while it sat. The item said 61; on 2026-09-08 the same class measured **160**, a 2.6×
increase over 23 days.

## Population (2026-09-08, 2,429 local branches)

| class | n | meaning |
|---|---|---|
| backup-named | 2,020 | excluded by name — a snapshot is not evidence of loss |
| non-backup, unique commits | 251 | the pruner's refusal set |
| └ **SUPERSEDED-AMBIG** | **160** | every touched path since rewritten on trunk — **this item** |
| └ MIXED | 68 | some paths untouched |
| └ UNTOUCHED-STRANDED | 23 | trunk never touched their paths |
| ancestor- or patch-landed | 158 | already provable by the existing pruner |

## The instrument, and the two it replaced

Two weaker spellings were built first and **both were refuted by their own controls**. That
sequence is the reason the shipped test is shaped the way it is, so it is recorded rather than
tidied away:

| | test | refuted by |
|---|---|---|
| v1 | is this added line in the trunk tree today | **12 of 66** known-patch-landed branches read ABSENT. It cannot separate "never landed" from "landed, then trunk edited past it". |
| v2 | did this added line EVER exist on trunk | Both controls passed — and it still convicted `cloud-g5-create` at ratio 0.04 while **every deliverable that branch names is on trunk** (`scripts/lib/cloud-create.sh`, `tests/cloud-create-lib.bats`). A re-derived land keeps no line. |
| v3 | is the SYMBOL this branch introduces anywhere on trunk | positive control 66/66 clean, negative 21/23 convicted. Shipped. |

v3's unit is what survives a rework: the file a change adds, the function it defines, the flag it
spells. `cloud-g5-create`'s `cc_create_normalise` landed as `cc_cloud_normalise` — the rename is
visible, the capability is not lost.

**v3 narrows; it does not settle.** 160 branches → 45 carrying absent symbols → **38 distinct
missing-symbol signatures**, each named so a human verdict costs one grep instead of a diff read.
All 38 were then adjudicated against trunk by hand.

## Verdicts — all 38 signatures

Every one resolved SUPERSEDED or NOISE against a trunk citation. The representative cases:

| what the branch built | where it lives on trunk now |
|---|---|
| memory index 200-LINE cap enforcement (`BREACH_B`, `TOTAL_L`) | `hooks/memory-nudge.sh:382-388`, richer than the branch form |
| cloud create lane (`cc_create_*`, 8 functions) | `scripts/lib/cloud-create.sh` as `cc_cloud_*`, 1:1 |
| postland CUT-vs-verdict abstain (`stamp_is_cut`) | `scripts/postland-verify.sh:34-39`, HUNG/CUT split + `CUT_MAX` cool-off |
| await-ping arming-turn stand-down (`BEAT_SETTLE_*`) | trunk commit `0ce20c393`, same defect, different mechanism |
| marginal-load sampler (`CC_MARG*`, 5 signatures) | `scripts/capacity-marginal-run.sh` + `capacity-marginal.bats`, whole family landed |
| land-gate admission (`GATE_SLOTS`) | superseded by LOAD admission — `postland-verify.sh:190`, exit 75 |
| cc-value attribution join | trunk commit `a4504a914`, the identical finding |
| first-failing-line reporting | inlined as `grep … \| head -1` at `postland-verify.sh:1143,1187,1198` |
| `--tail-h` window flag | renamed `--window-h`, `bin/claude-accounts:81` |
| per-caller timeout resolution | folded into the shared `_resolve_timeout` seam, `bin/it2-kitty:194` |

Two branches are self-declared: `superseded/cc-notify-prefix-DO-NOT-LAND` and
`superseded/infra-green-narrow-DO-NOT-LAND`.

## The one that looked like loss, and why it is not

`drain/lane-infra` (`5edcc5d15`) makes `scripts/deploy-live.sh` **repair** a checkout flipped to
`core.bare=true` instead of paging. Trunk detects and classifies the state
(`deploy-live.sh:574-579`) and files the remedy as a string (`:653`) — and **nothing on trunk
executes it**. That is the detector-with-no-owner shape, over an incident that froze the fleet's
live layer until a human ran one `git config --unset`. It looked like the recovery this scan
existed to find.

It is not. The branch tip is **nine hours old** and a **live worktree is standing on it**
(`/Users/chrisren/Development/.worktrees/drain/lane-infra`). Cherry-picking it would have
duplicated a peer's open work — a worse outcome than the loss being hunted, and one no
content-presence test can see, because content is not ownership.

**17 of the 160 are worktree-held.** `HELD-WORKTREE` is now a first-class refusal in the tool
(`branch-adjudicate.py`), checked before any content test runs.

## What ships

- **`scripts/branch-adjudicate.py`** — classifies every local branch against a trunk.
  `--self-check` runs both controls on a SYNTHETIC repo (never the live population, which churns
  under a control and cannot fail the same way twice) and exits 1 when either is refuted.
- **`tests/branch-adjudicate.bats`** — 12 cases. Cases 7 and 8 are the load-bearing ones: they
  MUTATE the classifier and require the self-check to go red. Case 7's mutant is v1 itself, so
  the suite fails if the instrument ever regresses to the spelling that was already refuted.
  Without those two, every other case would pass against a script that said LANDED-REWORKED
  unconditionally.

Live run, 409 non-backup local branches: 118 HELD-WORKTREE · 87 LANDED-REWORKED · 60 PATCH-LANDED
· 47 ABSENT-FILE · 35 NO-SYMBOLS · 35 ABSENT-SYMBOLS · 15 ANCESTOR-LANDED · 12 MOSTLY-LANDED.

## What this cannot see

A change introducing **no new symbol** — a reordering, a bound moved from 30 to 300, a fixed
comparison, a deleted line — is invisible to the unit and reads LANDED-REWORKED on a branch that
holds it. A verdict here bounds SYMBOL-shaped loss and nothing else. `--self-check` proves the
instrument discriminates; it never proves a branch is safe to delete, and **nothing here deletes
a branch**.

The 47 `ABSENT-FILE` branches outside this item's class need no new action: they are exactly what
`branch-prune-landed.sh` already refuses to prune, so they are being held in the safe direction.

## Method note

Every trunk read in this triage went to `origin/main` blobs, never to a working tree, so a dirty
or stale checkout cannot move a verdict. The census, both refuted instruments, and their control
runs are reproducible from the shipped script.
