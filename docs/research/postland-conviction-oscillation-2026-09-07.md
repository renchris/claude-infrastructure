# The verifier's disjoint REDs are a period-2 oscillation, not a rerolling population

*2026-09-07 · backlog item `56b39811eddc` · fix C29c in `scripts/postland-verify.sh`*

## Conclusion

`postland-verify.sh` spent a convicted suite's corroboration row **at the same verdict site that
convicted it**, so a chronically failing suite could never hold two consecutive windows of evidence.
It reds on one sweep, restarts from zero on the next, and reds again on the one after — a period-2
oscillation. The RED set therefore alternates between two halves of ONE stable population, which is
what made consecutive REDs look disjoint and made per-suite fixes look like chasing samples.

The population was never unstable. The **reporting** alternated.

## The measurement that settles it

Parsed from `~/.claude/autonomy/postland/runner.log`, all C29 dispositions since the mechanism
landed (`7e10f13ad`, 2026-08-08). `C` = corroborated (counts toward the RED), `P` = pending (dropped
from `FAILING`):

```
tests/compressor-sentinel.bats            PCPCPCPPPCPCPC   n=35  consecutive-CC=0
tests/handoff-fire-completion-push.bats   CPCPCPCPPCPCPC   n=30  consecutive-CC=0
tests/cc-dispatch-venue-only.bats         PCPCPCPCPCPCPC   n=27  consecutive-CC=0
tests/idle-slope-sweep.bats               CPCPCPCPPPCPCP   n=23  consecutive-CC=0
tests/claude-accounts-core.bats           CPCPCPCPCPPPPC   n=20  consecutive-CC=0
tests/cc-reaper.bats                      PCPCPCPPCPCPCP   n=20  consecutive-CC=0
tests/boundary-handoff.bats               PCPCPCPPPCPPCP   n=19  consecutive-CC=0
tests/goal-inert-watch.bats               CPPCPCPCPCPCPCP  n=17  consecutive-CC=0

396 observations · 344 adjacent pairs · both-CORROBORATED: 0
```

**Zero of 344.** No ladder-convicted suite has ever been RED in two consecutive windows. The `PCPC`
signature is the mechanism printing itself.

The stamp-level view agrees. Over 21 consecutive RED pairs (2026-09-04 → 09-08):

| lag | overlap |
|---|---|
| **lag-1 (consecutive)** | shared=0, Jaccard **0.00 — in all 21 pairs** |
| **lag-2** | Jaccard up to **1.00** (09-05T13:37 vs 20:55 identical; 09-05T10:23 vs 17:46 at 0.90) |

The three runs the backlog item cited are three consecutive samples of that alternation:
20:55Z set A, 01:13Z set B, 04:30Z set A again. A and B are halves of one population, in antiphase.

## Mechanism

`conviction_observe` appends a row for every file it adjudicates. `conviction_clear` takes the files
to **preserve** and spends every other row. The RED and HUNG sites passed `CONVICT_PENDED` alone:

```sh
cut_clear; conviction_clear "${CONVICT_PENDED[@]+...}"      # convicted files' rows: DELETED
```

So on a RED, each corroborated file's row — including the one written seconds earlier by the very
loop that produced the verdict — was deleted. Next sweep the file has no prior, so it PENDS; the
sweep after, it corroborates again.

C29b (2026-08-22) had already found and fixed exactly this shape for the *pending* half, and its own
comment states the governing rule — *"A RED exonerates nothing"* — but applied it only to file B. It
covers file A with equal force: a RED does not exonerate A, it **confirms** A.

Confirming state on disk at the time of writing: the store held 4 rows, which were precisely the 4
files the last run PENDED. The 2 it CORROBORATED were absent.

## Why the backlog item's falsifier could never fire

The item proposed: *"if two consecutive REDs ever share >50% of their failing set, the population is
stable and per-suite work is justified again."*

That test was **unsatisfiable by construction**. A ladder-convicted file red at sweep N had its row
spent at sweep N, so it was structurally barred from being red at N+1 — however broken it was. The
falsifier could only ever return "population unstable", which is the answer it in fact returned, and
it would have returned it against a perfectly stable population. Measured: 0/344.

*Generalisable shape:* a falsifier evaluated on a signal the subject itself suppresses can only
confirm the hypothesis it was written to test. Check that the proposed evidence is **reachable**
before trusting its absence.

## The fix (C29c)

Both non-green verdict sites now preserve the convicted names alongside the pended ones:

```sh
cut_clear; conviction_clear "${CONVICT_PENDED[@]+...}" "${CONVICT_CORROBORATED[@]+...}"
```

The GREEN path is untouched — a green ran the whole corpus and everything passed, so every candidate
row really is stale, and the unscoped wipe there stays byte-identical.

### Why this does not re-open the stale-row trap

Spending the *convicted* row was never what closed that trap; the **"not in the keep list ⇒ spent"**
property is, and it is untouched. A file that gets fixed stops failing, so it is neither pended nor
corroborated at the next verdict and its rows are spent at that very site exactly as before. The only
rows preserved belong to files the run **observed failing seconds earlier** — the opposite of stale.
A convicted file now carries precisely the exposure a pended file has carried since C29b (no new
class), and `CONVICT_TTL` still bounds every row at 24h.

## Corrects a landed claim

Commit `9221fe208` ("three idle-slope-sweep tests inherited the box's load") fixed three real tests —
that measurement stands (pre-fix 3 not-ok at load1 19.2, post-fix 16/16 at load1 38.2). But the suite
reappeared in a later RED on a tree containing the fix, and the commit message read as though the
suite's redness was resolved. It was a cause, not the cause: `idle-slope-sweep` shows `CPCPCPCP…`
like every other chronic suite, so its reappearance was the oscillation, not a failure of that fix.

## Red-proof coverage

`tests/postland-verify.bats`:

- **`C29c: a chronic suite reds in CONSECUTIVE sweeps`** — the item's falsifier as an assertion. One
  always-failing suite must red twice running. Pre-fix the second verdict is `cut`.
- **`C29b: a RED does not spend a file it never adjudicated`** — its `alwaysbad` row assertion was
  inverted (it read `= 0`, which *pinned* the defect) and the guard it was really buying moved to its
  correct subject: a third fixture suite that fails in window 1 only, whose row must still be spent.
- The call-site census gained an arm asserting both non-green sites pass the corroborated array, so a
  later edit cannot silently drop it while the 3/2/1 counts still read green.
