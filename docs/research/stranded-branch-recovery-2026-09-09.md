# Stranded-branch recovery, final pass — 2026-09-09

Closes cc-backlog `c9d5053a92c0` ("RECOVER 46 stranded cloud commits across 41 `claude/fire-*`
branches"). Manifest of record: `docs/research/branch-prune-manifest-2026-08-19.tsv`.

## The filed premise is REFUTED, and its refutation is dated 2026-09-08

The row's title asserts that `scripts/backlog-flow-assert.sh` (268 lines) and
`tests/backlog-flow-assert.bats` (327 lines) "are ABSENT from main". Both are on trunk today, at
exactly those line counts, landed by `5000db426` — a commit that cites this backlog id in its own
body. The spot-check that justified the row is discharged.

What was NOT discharged is the row's payload. `5000db426` triaged all 41 branches and left **6
RECOVER-PENDING**; `aff3eb889` (recycle #326) re-measured five of those and cleared one. Five rows
were still live when this pass started. *An item's payload is its EFFECT; a dead cause does not
close it* — so the five were measured independently rather than closed on the refuted premise.

## The instrument the two prior passes used cannot answer the question

Both earlier passes measured **"how many of a branch's added code lines appear on main"**. That
statistic reports a reworded, reformatted or independently-reimplemented land as *stranded*, and
`5000db426`'s own HONEST LIMIT says so ("a modification landed with any reformatting still reads as
stranded, so the six are an upper bound"). It was never wrong about the branches; it was answering a
question about **text** while the decision turns on **capability**.

Re-measured by capability — *does main establish the property this commit establishes, by whatever
mechanism* — the five rows split 2 / 3:

| branch (tip) | prior reading | measured 2026-09-09 |
|---|---|---|
| `6eb74d040` | 9 of 13 lines absent | **CURED** — fixture `HOME` at `tests/autonomy-sweep.bats:23`, `CC_BACKLOG_KICK=off` at `:131`, and the suite is out of `test-hermeticity-lint.sh`'s allowlist |
| `6e7bdd2e8` | 35 of 39 lines absent | **CURED** — the deployed-copy guard is exact on main at `scripts/autonomy-sweep.sh:636`, same cure, different form |
| `44de2d805` | 23 of 36 lines absent | **PARTIAL** — the fd-3 leak is real and unfixed at source |
| `265e59b4e` | 8 of 9 lines absent | **PARTIAL** — and live on main in an *amplified* form |
| `649ecc23b` | 79 of 220 lines present | **PARTIAL** — structural half landed as `1fc55c9c5`, two nudge properties did not |

Two of five were cured and would have been re-derived by anyone trusting the line count. Three
carried genuine residue, and in one case the line count *understated* how bad main was.

## The three residues, and why each was fixed where it was

**1. `44de2d805` — the dispatch kick's spawn held fd 3.** `dispatch_kick` redirects 0/1/2 and
`</dev/null`, so the spawn looks detached; fd 3 it did not, and under bats fd 3 is the TAP channel,
which bats reads to EOF. A reader gets no EOF while any process holds the write end, so bats blocked
until the whole `cc-dispatch --decide` pass exited — 150 s on `tests/autonomy-sweep.bats`, and under
`postland-verify`'s per-file bound a HUNG naming a *file* rather than a red naming a test.

Fixed at the **seam** (`3>&-` in `bin/cc-backlog`), not as the stranded commit's per-suite stub.
Counted today: **44** suites set `CC_BACKLOG_KICK`, **82** reach `cc-backlog` without it, and the
spawn's output already goes to `/dev/null`, so a suite that starts wedging gives no tell pointing
here. The stranded commit's own body argues for exactly this — *"THE REMEDY IS THE SEAM"* — and then
fixed one file, because one file was what had wedged.

Two-arm control on the real subject: trunk's blob returns in **5 s**, the fix in **1 s**, with the
kick marker present in *both* arms so neither is vacuous.

**2. `265e59b4e` — the bound ladder was inverted, not merely un-nested.** The suite exported neither
inner bound, so the subject ran at its production defaults (**180 s**, **1500 s**) underneath a
**30 s** harness wrap: inverted 6× and 50×. Every wedged arm was cut by the harness first, so
`fold_rc:"124"` and `premise_pass_note:"bound-exceeded"` — the subject's own instrument, and the only
form of the event a test can assert on — were **structurally unreachable from this file**, and no
test in it ever mentioned them. Both bounds existed, both fired, and only the ORDER was wrong, which
is invisible to every other gate here.

Now 20 / 25 under 30, with the nesting **asserted** rather than trusted. The sizing argument is that
this is not a materially tighter constraint: any throttling that pushes an arm past 20 s pushes the
whole sweep past 30 s too, so the outer would have cut it anyway. What changes is *which rung fires*
— a journalled verdict instead of a silent whole-file cut.

**3. `649ecc23b` — the char cap masked the line cap.** Its structural half landed independently as
`1fc55c9c5`, a superset that also corrected bytes → UTF-16 units. Two properties did not land, both
in `hooks/memory-nudge.sh`, both live defects in the advisory an operator sizes a compaction pass
from: the dropped-entry count was byte-only (so a **line**-cut index reported 0 dropped — a silent
tail with the sensor announcing nothing), and a dual breach fell into the char arm's bare `if`, so
it was never told it was over both caps and could be handed *"hook LENGTH is the binding lever"*, a
lever that provably cannot free a line.

The override for the second is deliberately **narrow** — only the two levers that claim shortening
suffices are replaced. The char arm's third lever already selects cardinality on its own arithmetic;
overriding it too would make that branch unreachable for any index dense enough to breach both caps,
i.e. exactly the population it was written for, and the suite would lose the coverage while still
reading green. The existing 600-entry case going red is what caught it.

## What was NOT done, and why

**The 41 branches are not deleted.** All five pending branches still exist on origin, as do 427
`claude/fire-*` refs. "Abandon with a reason" is satisfied by recording the verdict; deleting 41
remote refs is a destructive push, was not asked for, and the branches are the only remaining copy
of the abandoned content. The cost argument for pruning does not hold either — a full
`git for-each-ref` over this repo's refs runs in 0.01–0.02 s.

**`ABANDON-suite-red` (`8c9250ccd`) stands.** `tests/handoff-prompt-file-join.bats` is red 2/9
against main and the repair is inside `scripts/handoff-fire.sh` — a change to the subject, not a
recovery of the stranded commit. Unchanged from `5000db426`'s verdict.

## The reusable lesson

*A measurement taken in service of a triage outlives the triage, and gets re-read as if it answered
the question.* The "added code lines present on main" figure was recorded honestly, with its limit
stated in the same commit body, and was then carried into two later passes as though it were a
verdict about recoverability. It made two cured branches look stranded and — the direction nobody
checks — made one branch look *better* than it was: `265e59b4e` read "8 of 9 lines absent", a
tidy-sounding residue, while the property it guards was inverted on main by 6× and 50×.

When a triage statistic is a **proxy**, re-derive the decision from the thing itself before acting on
the proxy a second time; and when re-measuring, ask whether the proxy can err in *both* directions,
because the direction that flatters the tree is the one no one re-opens.
