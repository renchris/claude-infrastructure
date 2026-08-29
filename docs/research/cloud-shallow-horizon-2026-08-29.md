# Every cloud worker reads trunk through a 50-commit horizon, and the horizon moves

**2026-08-29 · measured in the dispatched container for backlog `f85fce7c26f5`
("the cloud return/land arm died 2026-08-17T09:12:05Z"), 9th dispatch.**

**In one line:** a cloud VM's checkout arrives **shallow at depth 50**, `git` answers "I cannot see
that far" and "no" with the *same* exit code, and every landedness read a dispatched worker makes is
therefore wrong in exactly one direction — *landed work reads as never landed*, which is this item's
headline, re-manufactured from scratch on every dispatch.

---

## 1 · The measurement, and its control

`.git/shallow` present on arrival; `git rev-parse --is-shallow-repository` → `true`. The same
container, same commands, before and after `git fetch --unshallow`:

| read | depth 50 | unshallowed |
|---|---|---|
| `git rev-list --count origin/main` | **50** | **3832** |
| `git merge-base --is-ancestor a42f107a origin/main` | rc **1** (not on trunk) | rc **0** (on trunk) |
| `git cherry` census, branches tipped 2026-08-22 | **0 %** landed | **67 %** landed |
| `git cherry` census, branches tipped 2026-08-19 | **0 %** landed | **24 %** landed |
| `git cherry` census, all 305 `origin/claude/fire-*` | **0** landed | **45** landed / 371 own commits |
| own commits attributed to the 2 branches tipped 08-11 | **5 119** | **3** |

`a42f107a` is not an arbitrary sha. It is *the cure for this very item*, and the dispatch brief's
first instruction is to check it against trunk. **On the checkout the harness hands the worker, that
check returns FALSE for a commit that has been an ancestor of `origin/main` since 2026-08-25.**

The last row is the shape of the error rather than its size: with the fork point below the horizon,
the range `merge-base..branch` is unbounded in practice, so a two-branch day is credited with 5 119
"own commits". Every day from 08-11 to 08-27 scores 0 % landed. Days **inside** the horizon
(08-28, 08-29) score identically on both clones — 4 % and 34 % — which is what makes the effect
attributable to the horizon and not to the instrument.

## 2 · Why this item in particular keeps coming back

The horizon is always *the last ~50 trunk commits*, so it **moves with the fetch**. A worker
dispatched today measures a collapse a few days back; a worker dispatched next week measures one a
few days back from there. Every dispatch independently "confirms" a step in the landing rate, and
the step it confirms is its own right edge. That is a self-renewing false positive, and it sits
directly underneath the sentence nine dispatches have now re-derived.

**The failure is silent in both directions, which is the part that matters.**
`git merge-base --is-ancestor` exits 1 for *"no"* and 1 for *"that commit is below my horizon"*.
`git log <sha>..origin/main -- <path>` prints nothing for *"nothing changed since"* and nothing for
*"I cannot reach that sha"*. Neither prints a warning. A worker that reads a landed cure as absent
re-derives it, and the diff it then writes **reverts trunk** — the hazard this repo already filed as
`6110fc45141e`, reached here by a route nobody had named.

## 3 · What this does NOT claim

- **It is not the whole of `f85fce7c26f5`.** `d84434cd` (on trunk) measured the lane on instruments
  the pruning confound cannot reach and found the rail **intermittent** — 89 % of branches fired
  08-10…08-17 on trunk, 35 % for 08-18…08-25 — and placed the defect **on the operator's box**,
  operator-gated on one read (`launchctl print` + `zsh -lc` + `idl.jsonl`,
  `docs/research/cloud-land-arm-step-2026-08-25.md` §3). Nothing here moves that. This names a
  *second* generator of the same wrong sentence: the one that has been corrupting the diagnoses.
- **It does not touch the desk's verdict machinery.** `landed()` in `bin/cc-cloud` reads
  `git ls-tree <trunk> -- <path>`, a read of the tip *tree*, which a shallow clone answers
  correctly; and `fill-paths` runs desk-side on a full clone. What is corrupted is the **worker's
  own** reads.
- **`git cherry` is a weak instrument even at full depth.** `d84434cd`'s instrument note is right:
  landing re-authors, so patch-equivalence decays with branch age, and the 08-11…08-17 rows above
  read 0 % on both clones where subject-equality scores that era at 89 %. The table is a
  *shallow-vs-full* comparison on one instrument, not a landing-rate estimate.
- **Unmeasured, deliberately:** whether `ship-land.sh`'s rebase onto trunk survives a fork point
  below the horizon. The cure is the same either way and costs one fetch.

## 4 · The cure

`scripts/cloud-venue-provision.sh` gains a **history horizon** arm — the first cell in its verdict,
ahead of the hard lock, with the token `TRUNCATED-HISTORY` and a `git fetch --unshallow` in the
provision path. Precedence is the point: the other cells decide whether a diff can *land*, this one
decides whether the diff is *right*, and a red gate is a smaller failure than a green land of a
revert.

`--deepen` is not offered as a fallback. A deeper wrong horizon is still a wrong horizon, and a
partial cure would restore the silent failure with a green line above it.

Two seams worth naming:

- **`CC_VENUE_HISTORY` is bidirectional**, unlike the file's one-directional `CC_VENUE_ABSENT`. This
  operand's optimistic value is `full`, so a seam that could only force `shallow` could not drive
  the positive control on a box whose own clone is shallow. It is printed as `FORCED … not a
  measurement` wherever it is used, and the provision path **refuses to fetch** while it is set.
- **`n-a` is a measurement, not an abstention.** A directory that is not a work tree has no trunk to
  read and no horizon to be wrong about. The first spelling of the probe answered `unknown` there
  and turned a clean `NOT-APPLICABLE` into "no verdict about this venue" — caught by the suite's
  pre-existing suite-less cell, not by review.

The suite's fixture is a real `git clone --depth 1`, with the same clone **after `--unshallow`** as
the positive control, and the file under test copied in — a clone carries the committed HEAD, so
without that copy every cell would have exercised the previously landed script and passed against a
subject containing none of this arm.

## 5 · Honest limits

- One container, one clone, one day. That the harness *always* clones at depth 50 is inferred from
  this instance plus the horizon matching `rev-list --count` exactly; it is not measured across
  fires. The guard is correct either way — it reports what the checkout in front of it actually is.
- The `git cherry` census is reproducible from the commands inline, but see §3 on what it can and
  cannot support.
- Nothing here was gated by the operator's box. `shellcheck` 0.11.0 and `bats` 1.10.0 were installed
  by `cloud-venue-provision.sh` itself; the suite and the gate ran in this venue.
