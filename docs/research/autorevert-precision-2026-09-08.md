# post-land AUTO-REVERT is ~62% precise, and its errors are silent in the wrong direction

**2026-09-08.** Adjudication of backlog `32d4d093f78a` ("AUTO-REVERT is armed by a conviction
population that is measurably unstable"). The row asked one question: **disarm, or keep armed?**

## Verdict: keep it armed, and fix the silence

Disarming was the wrong call and this document exists partly to record why the first analysis
reached it. The arm catches real regressions. What it does badly is tell anyone when it is wrong.

## The measurement

Whole `runner.log` history: **`landed 8 · FAILED(rc=90) 16 · skipped 34`**. Of the 24 attempts that
cleared every guard in `auto_revert()`, **16 landed nothing because the revert did not APPLY** — a
merge conflict, not a guard, is what stopped two thirds of them.

For each of the 8 that DID land, the convicted suite was executed at the culprit's own tree and at
the culprit's **parent**. Green-at-parent + red-at-culprit attributes the failure; the same verdict
at both exonerates.

| culprit | suite | at culprit | at parent | verdict |
|---|---|---|---|---|
| `2c6b8cdfa777` | autonomy-sweep | **63/0 pass** | — | **FALSE** |
| `b3f728858a6f` | capacity-alarm-segments | **10/0 pass** | — | **FALSE** (docs-only diff) |
| `e80c85aa2e47` | handoff-fire-kitty-daemon | **30/0 pass** | — | **FALSE** |
| `438883e365ec` | cc-fleet | 1 not-ok | **green** | TRUE |
| `a53632ae102d` | bash-audit-attrib | 3 not-ok | **green** | TRUE |
| `e6de2e15a444` | capacity-alarm-launchd-path | 1 not-ok | **green** | TRUE |
| `ee05adc63737` | cc-close-attrib | 1 not-ok | **green** | TRUE |
| `ee2e3a0d6a84` | capacity-admit-coverage | 1 not-ok | **green** | TRUE |

**5 true, 3 false — 62.5% precision.** `2c6b8cdfa777` is corroborated independently: the runner
itself later logged `already-reverted … its revert LANDED and it is convicted again — the surviving
red has another cause`, and `docs/research/postland-c29-alternation-2026-09-07.md` had already found
that suite green at the exact tree stamped red.

There is no cheap discriminator between the two groups. `2c6b8cdfa777` was **bisect-named over 7
steps** at load 12.64, so "only trust a bisected culprit" would not have excluded it.

## THE CORRECTION THAT MATTERS, recorded because the shape recurs

The first pass of this analysis concluded **"zero confirmed true positives — disarm"**, and it was
wrong. It ran only the culprit arm: suite at the culprit's tree, no parent control. Three suites
passed and five failed, and the five failures were read as *"can't tell, probably environmental"*
on the way to a conclusion the other three already supported.

Adding the parent arm inverted them: **all five parents are green.** The five were exactly the
evidence the recommendation had assumed away.

The generalisable rule: **a one-armed test cannot attribute, and its silence is not neutral — it
gets read in the direction the analysis is already leaning.** The control is not optional polish;
it was the whole result. (Same family as `control-must-replay-the-real-artifact` and
`positive-control-the-denominator`.)

## The actual defect: the alarm is inverted

`postland-verify.sh` pages when the revert **fails** and — until this diff — wrote nothing when it
**succeeds**. Checked across all 8 landed reverts: **zero pages**. The only other announcement is
`"$NOTIFY_BIN" "$sid"` to the *landing session's* inbox; an async corpus finishes ~3 h after the
land, by which time that session is gone, so it drains on a next turn that never comes. The
`file_linked` backlog row survives, but renders as a **count** in the standing pile, never named.

So the failure mode runs backwards:

| | announcement |
|---|---|
| revert wrong **and blocked** (rc 90) | a page, a desktop notify, a standing remedy |
| revert wrong **and applied** | *nothing the operator will see* |

The case where an innocent commit is gone from trunk is the quietest event in the system. That —
not the reverting — is what made the arm look indefensible.

## What landed

`C37`: the success arm now writes `$PAGES/postland-reverted-<c12>.page` and fires the same desktop
notify the failure arm does. The page names the commit it removed, its subject, the suite that
convicted it, and carries **the A/B above as a runnable check** plus the one-line re-land if the
verdict comes back FALSE.

It is deliberately **outside** the `postland-revert-*.page` glob: that namespace belongs to the
FAILED page, `rev_pages_n` counts it, and a green **retracts** it. A landed revert does not stop
being true when trunk goes green — trunk goes green *because* of it — so this page keeps its own
name and is acked by the sweep's ordinary seen-marker.

Red-proof: `tests/postland-verify.bats` `C37`, executed against the pre-fix script (fails: no page)
and post-fix (passes).

## What is NOT fixed here, and is still open

The conviction population remains unstable — `32d4d093f78a`'s falsifier re-run on 2026-09-08
returned **exit 1 (not refuted)**, i.e. consecutive red pairs still mostly disjoint, even after
`fc61fa948` and `d4b07a9ea` landed that day. This diff makes a wrong revert *visible*; it does not
make convictions *right*. The precision figure above should be re-derived, not inherited, once the
population stabilises — and if it drops materially below 62%, disarming becomes the correct call
after all.
