# The 62-row custody landing backlog, adjudicated — 2026-09-09

Closes cc-backlog `95cbba839b44` ("62 cloud custody rows hold REAL commits that are on no trunk").
Per-row verdicts: `docs/research/custody-landing-manifest-2026-09-09.tsv` (62 rows, zero
un-adjudicated). Predecessors of record: `docs/research/custody-integrity-2026-08-23.md` (the
reconciliation that produced the 62), `docs/research/branch-prune-manifest-2026-08-19.tsv` and
`docs/research/stranded-branch-recovery-2026-09-09.md` (which had already adjudicated 35 of them).

## The row's three classes, measured

The row filed three strata. One is refuted outright, one was discharged by other hands, and one was
real and is now driven.

| filed | measured 2026-09-09 |
|---|---|
| 36 rows: branch on origin + observed sha, commits not on trunk | 59 branches survive on origin; **12** are patch-equivalent on trunk outright, **14** more are landed by content |
| 23 rows: as above, plus a `.land-refused` artifact | the artifacts are real (25 of them; rc 70 conflict ×20, rc 65 fetch/divergence ×4) but the artifact says why the LAND failed, not whether the WORK is missing — those rows distribute across the same verdicts as the rest |
| 3 rows: branch deleted from origin, sha present locally, **NOT an ancestor of origin/main** | **REFUTED. All three landed.** `git cherry origin/main <sha>` answers `-` for every one, and their content is on trunk as `22e378ae3`, `2c5efa011`, `66857bc2e` |

**The third class is a pure instrument artifact, and this repo already knows why.**
`scripts/branch-prune-landed.sh`'s own header records the measurement: `git branch -r --merged`
reported 1 merged branch of 97 where `git cherry` reported 56, because ship-land rebases before it
pushes and rewrites every object. The reconciliation reached for ancestry anyway. Its own wording —
*"is NOT an ancestor of origin/main"* — is the tell. Repo memory: `cited-sha-may-not-survive-the-land`.

## "Closing them without a decision erases the only record that the work exists" — refuted, and the
## refutation is what makes the rest cheap

Three independent stores hold the record, and each was checked rather than assumed:

- **the branch on origin.** 59 of 62 still there. The pruner deletes only patch-equivalent branches
  and reports the rest `HOLD-stranded`; all 13 rows that still needed a verdict when this pass
  started are `HOLD-stranded` in the live manifests.
- **the declaration.** All 13 `.decl` files present, with their `.retired` markers.
  `cloud-retire-terminal.sh`'s header records that `id_for_item`/`ids_for_branch` keep serving
  retired declarations for exactly this reason.
- **the prune manifest**, dated, with each branch's sha, so any deletion is reversible by
  `git push origin <sha>:refs/heads/<branch>`.

Nothing was erased. What the row got right is that nothing had **decided**.

## What HAD happened, unnoticed by the row: a bulk discharge with the wrong predicate

On **2026-09-07**, 13 of these 62 custody rows were abandoned with the reason
`cloud declaration retired: superseded`. That verdict is `scripts/cloud-retire-terminal.sh`'s, and it
is defined as *the declaration's `item=` folds to `done` in the backlog* — the row was closed by a
sibling, so this branch is a second implementation of work already on trunk.

That inference is about the ITEM. It is not a measurement of the BRANCH, and the two can disagree:
an item closes when a sibling lands a cure, and a sibling can land the prose half of a commit and not
its executable half. Measured across the whole class rather than guessed at:

```
153  custody rows abandoned "…retired: superseded"   (all 153 branches still on origin)
152  of those carry >=1 commit not patch-equivalent on trunk   (232 commits)
140  carry >=1 commit with >=50% of its added CODE lines absent from trunk
```

**That 140 is an UPPER BOUND and must not be quoted as a finding.** The line-count instrument is the
one `stranded-branch-recovery-2026-09-09.md` § *"The instrument the two prior passes used cannot
answer the question"* already retired: it reports a reworded, reformatted or independently
reimplemented land as stranded. Its calibration is now measured twice:

| pass | flagged by line count | CURED / SUPERSEDED under capability | false-positive rate |
|---|---|---|---|
| trunk, 2026-09-09 (n=5) | 5 | 2 | 40% |
| **this pass (n=16)** | 16 | **13** | **81%** |

So the honest statement about the wider class is: *between 19% and 100% of those 140 hold real
residue, and only a per-branch capability read decides which.* This pass paid that cost for its own
16 and no further — the wider class belongs to `307fe7ab1e91`, not here.

## The 16 that needed a verdict, and the 3 that were real

Sixteen commits across 13 branches were uncovered by every prior pass. Each was adjudicated by
CAPABILITY — *does trunk establish this property, by whatever mechanism or wording* — never by line
overlap, and each verdict cites a trunk path, line or ancestor sha.

**Thirteen were correctly superseded.** Nine are one series of venue foreign-repo dispatch reports
whose recurring payload was *"the cause at `bin/cc-offload:84` is still unshipped, N days on"* — true
when written, false since `113d944c8` (2026-09-06) shipped `foreign_repo_refusal()` at
`bin/cc-offload:463`, in exactly the shape four of them predicted, and every one of their subject
items is closed. Two more are capacity work trunk replaced with a better instrument that has actually
run. Two are infrastructure cures trunk closed by a later, stronger route.

**Three were real, and all three are landed by this pass.**

1. **`70d4aad1e` → `770569a15`.** `ship-land`'s rebase guard fires on the ABSENCE of evidence
   (nothing unmerged, no markers) plus the PRESENCE of a rebase state directory, which does not
   distinguish a rerere replay from **a rebase that is not ours**. `git rebase` refuses over an
   existing state directory and changes nothing; that refusal is non-zero with nothing unmerged, so
   the loop adopted a stranger's rebase, `--continue`d it, and **returned 0 with `HEAD^` at the old
   `onto`**. Reproduced end to end on git 2.54 against trunk's own predicates. The state is not
   exotic: an exit 5 leaves the rebase in progress by design, so it is where every re-run of `/ship`
   on a failed land begins — and `main_outer`'s dirty-tree preflight cannot see it, because a
   conflict resolved to trunk's side leaves `index == HEAD` and `git status --porcelain` EMPTY.
   Directly relevant to this row's own subject: 46 of these 62 rows died on a land.
2. **`71658d676` → `f9c98cd1a`.** `cc-discover` minted every plan-open falsifier as
   `[ "$(scan --falsify)" = FALSIFIED ]`, which yields only 0 or 1, so 127/126/124/2 all reached
   `cc-premise` as a flat 1 and its could-not-ask band (`bin/cc-premise:266`) was **structurally
   unreachable for the entire class**. Every unaskable state rendered as a confident
   `NOT REFUTED (exit 1) … output: (silent)`. Measured consequence: a completed plan dispatched as
   live work one day after it closed.
3. **`c79af507d` → `b86cbb5d2`, test file only.** Its header hunk is CURED — trunk's version is a
   strict superset carrying `f944d6e3`'s *the INPUT is wrong, not the number*, written a day after
   this commit — but `tests/capacity-ceiling-derivation.bats` existed nowhere, so the gate's only
   defence against a blind raise of `CC_HW_DEFAULT_MAX_LOAD_PER_CORE` was a paragraph, on a constant
   with nineteen unlanded correction attempts behind it.

Two landing hazards found and deliberately NOT taken, recorded so nobody reaches for them:
`64eef549b` adds a file at `tests/capacity-marginal.bats` where **trunk already has a different
suite of that name** guarding a shipped measurement — a path clobber a cherry-pick would resolve as
an ordinary content conflict rather than announcing; and `981fe9b2c`'s `bin/cc-offload` hunk would
revert `1311ff038`'s `CC_PANE_ID` preference and silently downgrade every headless/kitty fire to
fire-and-forget.

## The generalisable finding

**A discharge predicate must be a measurement of the thing being discharged.**
`cloud-retire-terminal.sh` is a careful tool — its `gone` and `landed` verdicts each measure the
branch, and `landed` uses `git cherry` explicitly *because* ancestry is wrong here. `superseded`
is the one verdict that reasons about a DIFFERENT object (the backlog item) and infers the branch's
disposition from it. That inference is right most of the time and is wrong exactly when a sibling
landed part of a commit — which is the case that costs something, because the part left behind is
the part nobody wrote down. Two of this pass's three recoveries were in rows abandoned as
`superseded`, and both were live defects in the dispatch and landing machinery itself.

The remedy is not to disarm the arm: it retires ~153 rows that would otherwise be re-examined on
every cursor rotation, and its own header measures that cost. The remedy is that `superseded` should
carry the branch measurement it already computes for `landed` — `git cherry` is one call it is
making anyway — and say `superseded (branch patch-equivalent)` versus
`superseded (item closed; branch holds N unlanded commit(s))`, so the second class is separately
addressable instead of being indistinguishable from the first. Filed, not built here: the arm is on
a live launchd path and its blast radius is the whole cloud lane.

## What the store can and cannot carry

All 62 rows are now discharged, each with a reason naming the manifest: **44 `return`, 18
`abandon`**. Thirty were discharged by this pass; the other 32 were already discharged before it.

**The 13 rows abandoned on 2026-09-07 keep that reason in the store, and the manifest is their
correction of record.** `cc-custody` discharges a row ONCE — a second `return`/`abandon` against a
marker that is no longer open prints *"no OPEN row matches … nothing discharged"* and **exits 0**.
That is the right design for an append-only ledger (a discharge is a verdict, not a field to edit),
and it means the store cannot be made to point at this adjudication for those rows. For three of
them the store's reason is now actively wrong — their residue was real and is landed as `770569a15`,
`f9c98cd1a` and `b86cbb5d2` — so the manifest, which names each marker, its branch and its landed
sha, is the only place that correction exists. A reader going marker → store gets the 2026-09-07
reason; a reader going marker → manifest gets the verdict.

Recorded because it cost a false count in this pass: the discharge script read that exit 0 as
success and reported 13 corrective rows appended when **zero** were. Same shape as repo memory
`claimed-outcome-vs-checked-outcome` — a rc-0 no-op is indistinguishable from a rc-0 act unless the
STORE is read back. It was caught by re-counting the store's rows (1,152 → 1,182 = the 30, not 43),
which is the check that should have been in the script.

## Honest limits

- The wider-class figure (140 of 153) is a **bound from the retired instrument**, not a finding.
  Quoting it as "140 branches hold lost work" would repeat the error this document is about.
- The three `LANDED-REBASED` rows were verified by `git cherry` plus content presence of their added
  files on trunk, not by ancestry. That is the right test here, and it is still a patch-id test: a
  land that reformatted would read `+`. All three also matched by subject and by file content.
- `.land-refused` artifacts were read for their rc distribution only. Whether the rc 65/70 causes are
  still live is row `8636b8f829fe`'s question and was not re-measured.
- The 2026-09-07 bulk abandon was attributed to `cloud-retire-terminal.sh` from the reason string it
  is the sole producer of (`grep` over `bin scripts hooks` returns one other site, in
  `cloud-return.sh`, with different wording). No launchd log was read.
