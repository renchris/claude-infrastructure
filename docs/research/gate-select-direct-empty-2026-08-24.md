# `gate-select --direct` returns empty at rc 0 — REFUTED as a gate defect (row f1a9146c7f2f)

**Date:** 2026-08-24 · **Verdict:** the observation is real and reproducible; the defect it was
attributed to does not exist. The instrument was lying, not the gate. Landed fix: `297f1bcc7`.

## The row, and what it claimed

> `gate-select --direct` returns an EMPTY suite set at rc 0 for a range `--explain` says has 3
> suites, so a land gated on `--direct` is gated on nothing.

Filed after ten independent observations across the drain chain. Two remedies were prescribed:
**(A)** add a durable ship-land log, because "there is NO ship-land log" and every past observation
was therefore unauditable; **(B)** make the empty set at rc 0 a distinguishable *abstention*, and
make `ship-land.sh` treat abstain as REFUSE-TO-LAND rather than as a lint-only land.

Both premises are false. Neither remedy was implemented, deliberately.

## Premise (A) is false — the log exists and has for two weeks

`~/.claude/land.log` — 6,176 rows, of which **1,772** are `tool:"ship-land"`, `stage:"land"`. Every
one carries `base`, `head`, `tree`, `gate_scope`, `selected_n`, and `smoke`. The smoke field has
been written since **2026-08-11T09:38:48Z**.

The `:1974` stderr line the row cites as ephemeral is a *duplicate* of a field already persisted.
Its state is `smoke:"none-nodirect"`, and it is one of seven distinct `none-` tokens ship-land
already emits (`none-unreached`, `none-nosuites`, `none-locked`, `none-precheck`,
`none-noselector`, `none-undecided`, `none-nodirect`) — a split introduced precisely so that
"83% of lands execute no test" could be broken down by cause.

Every one of the ten observations was auditable the whole time, by one query. That query is below.

## Premise (B) is false — empty is a VERDICT, and the abstention already has its own spelling

`--direct`'s empty set at rc 0 is not an abstention. This selector abstains by printing the literal
token **`FULL`** — every `fail_closed` door and every internal error takes that path. ship-land
already reads the two differently: `FULL` ⇒ `none-undecided`, empty ⇒ `none-nodirect`. The gate
that "cannot tell nothing-to-run from I-could-not-tell" is already told.

### The census that settles it

For every `none-nodirect` land row, resolve `base..head` and classify the changed files:

```
none-nodirect rows: 262   (resolved 262, unresolved 0)
  prose-only ranges (empty direct is CORRECT):   250
  ranges containing any non-prose file:           12
```

The 250 are `docs(drain): recycle #N` commits and their kin. Their only edges are `prose-cited` —
a suite that *mentions* the doc in a comment. `cited_only` exists to demote exactly those, because
a DIRECT edge is the claim *"a failure here is caused by your diff"* and a comment is not evidence
of that. Demoting them is the whole point of `--direct`, and it is measured: 90 of 542 clause-(a)
edges were comment-only and exactly one was a real dependency.

Of the 12 remaining, 11 are assets, research scratch (`docs/research/**/*.py`, `*.tsv`),
`docs/activation/pending-activation/*.sh`, and a `skills/**/SKILL.md` — none of which any suite
covers. **Exactly one is a source file: `scripts/branch-prune-landed.sh`, which has no suite in
the tree at all.** That is a real but narrow coverage hole, and a different class from this row —
filed separately.

## So why did ten observers see a bug?

Because `--direct --explain` narrated the edges it had just discarded. Pre-fix, a demoted edge
printed in the **same shape** as a selecting one:

```
tests/cc-dispatch-firegate.bats <- prose-cited:docs/plans/BACKLOG_DRAIN_24_7.md
tests/land-content-verify.bats <- prose-cited:docs/plans/BACKLOG_DRAIN_24_7.md
tests/postland-verify-bisect-bound.bats <- prose-cited:docs/plans/BACKLOG_DRAIN_24_7.md
```

…over an empty stdout. `--explain`'s own documented contract is *"one stderr line per decision"* —
and under `--direct` the decision taken at that line is to **DROP** the suite. Nothing said so, so
the trace read as three selected suites the gate then failed to return. Ten times.

**The generalisable shape:** an instrument whose verbose mode describes a *different* selection
from the one it returns manufactures a defect report on every use. The cost is not one wrong
conclusion — it is a *per-observation* cost that never amortises, because each observer re-derives
the same wrong inference from the same self-contradicting output. Compare
`wrong-cause-corroborated-by-true-metric`: here the corroborating evidence is emitted by the
subject itself, which is why it survived ten reviews.

## What landed (`297f1bcc7`)

Reporting only — selection is byte-identical to the pre-fix artifact across 28 comparisons
(14 commits × {plain, `--direct`}); selftest and map lint green.

1. A demoted edge is marked: `tests/X.bats <- NOT-DIRECT prose-cited:docs/…`
2. A closing summary states the counts **and names the abstention token**:
   *"An empty direct set is a VERDICT — nothing this diff executes — NOT an abstention; this
   selector abstains by printing the literal token FULL."*
3. The header documents empty-vs-`FULL` and points at ship-land's two land.log tokens.

Two tests, both proven controls: the demotion test goes RED against the real pre-fix
`scripts/gate-select.sh` from git; the selection-untouched pin goes RED against a planted mutant
that makes `--explain` suppress the selection.

## What was NOT done, and the fact that would change that

**`ship-land.sh` still lands on a genuine abstention.** `none-undecided` (90 rows) and
`none-noselector` both proceed with zero behavioural gate, exactly like `none-nodirect`. Making
those refuse is what remedy (B) asked for, and it is *not* obviously right: it reverses a
deliberate, documented, measured decision — R6, *"a non-verdict must never block a land"* — taken
after fail-closed-toward-more-proof was identified as the amplifier in the
kill→RED→re-block→retry runaway (`f8e40b4c577d`). Fail-closed there is the behaviour that jammed
the pipeline for days.

**The named fact that would settle it:** whether any `none-undecided` land was followed by a
post-land verifier RED attributable to that same diff. If abstention-then-land has never shipped a
regression the verifier caught, R6 stands as measured and the current behaviour is correct. If it
has, that is the counter-evidence that earns the reversal. Both halves are answerable from
`land.log` joined against the verifier's own store — neither is answerable from this row.

## The query, so observation 11 is free

```bash
python3 - <<'PY'
import json, subprocess, collections
rows = [json.loads(l) for l in open('/Users/chrisren/.claude/land.log') if l.strip()]
land = [o for o in rows if o.get('tool') == 'ship-land' and o.get('stage') == 'land']
print(collections.Counter(r.get('smoke') for r in land).most_common())
def prose(p):
    return p in ("README.md", "CLAUDE.md") or (p.startswith("docs/") and p.endswith(".md"))
for r in land:
    if r.get('smoke') != 'none-nodirect':
        continue
    f = subprocess.run(['git', 'diff', '--name-only', r['base'], r['head']],
                       capture_output=True, text=True).stdout.split()
    if any(not prose(p) for p in f):
        print(r['ts'], r['head'][:9], [p for p in f if not prose(p)])
PY
```

And at the point of observation, the selector now answers for itself:

```bash
scripts/gate-select.sh --direct --explain <base>..<head> 2>&1 >/dev/null | tail -1
```
