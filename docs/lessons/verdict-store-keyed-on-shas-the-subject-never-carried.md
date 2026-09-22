# A verdict store can be keyed on objects the subject never carried

**Measured 2026-09-21/22, claude-infrastructure.** `cc-blockers` reported two LAND-PIPELINE
alarms — `trunk-red PERSISTENT-NOT-GREEN` ("newest 5: 4 red 1 nonverdict, 0 green") and
`deploy-wedged NO-GREEN-AHEAD` ("green `c08dc78ae590` sits 375 behind live HEAD"). Both are
computed from `~/.claude/autonomy/postland/stamps/*.json`, one file per sha.

**0 of the 12 newest stamps name a sha that is an ancestor of `origin/main`**, going back to
2026-09-20 03:38:

```bash
for f in $(ls -t ~/.claude/autonomy/postland/stamps/*.json | head -12); do
  s=$(basename "$f" .json)
  git merge-base --is-ancestor "$s" origin/main && echo "$s ANCESTOR" || echo "$s not-on-trunk"
done
```

The verifier stamps the sha it *tested*, which is a pre-rebase branch tip; `ship-land` rebases
before pushing, so the object that lands is a different one. Every verdict is therefore attached to
an object trunk does not carry, and an alarm folding those verdicts speaks about **branch tips**
while its wording — "trunk-red", "behind live HEAD" — asserts something about trunk. The distance
`375` is measured from one of those same non-ancestor objects, so the number is suspect even where
the wedge is real.

## Two independent defects, and the second is the one that hides

**1. The aggregate buried the discriminator.** The alarm's own RECOVER command folds *every* stamp
ever written: 238 red, and a top-15 led by `tests/kitty-conf-bindings.bats` (37) and
`tests/operator-readout.bats` (35). None of those appears in a current red. Reading only the newest
five shows a **constant term** — `tests/lr-handoff-launcher-quoting.bats` fails in **all four**
reds while `cc-fleet`, `jev-predict-land` and `jev-promote` rotate. A rotating tail over a constant
term names a deterministic floor, not a flake (companion:
[[flake-model-hides-the-deterministic-floor]]).

**2. The constant term is green.** Run at trunk tip in the shared checkout,
`tests/lr-handoff-launcher-quoting.bats` returns `1..30`, all ok. So the suite the alarm's evidence
convicts passes today — which is exactly what you would expect if the verdicts describe objects
that are not trunk.

Consequence, and it is not small: `deploy-live` has been taking its degraded door since at least
2026-09-20, logging *"no GREEN stamp among the newest 200 commits of `origin/main`; taking the
newest NOT-RED commit instead"* — a correct refusal over evidence that may never have been about
`origin/main` at all.

## The rule

**Before believing any aggregate a verdict store computes, check that its KEY names an object the
subject actually carries.** A store keyed on a mutable identity — a pre-rebase sha, a pid, a port,
a session id, a branch tip — accumulates true records about objects the subject later replaced, and
nothing in the fold can tell you so. The fold is arithmetic over the rows it has; it cannot notice
that the rows describe a different population.

Two properties make this near-undetectable:

- **It fails in the safe-looking direction.** A red that belongs to an object trunk never took
  reads as caution. Nobody escalates a gate that is refusing.
- **The alarm's wording launders the population.** "trunk-red" is a claim about trunk; the data is
  a claim about branch tips. The name is written once, by hand, and is never re-derived — so it
  survives every change to what the store is actually keyed on.

Ask, in this order: does the key resolve **in the subject** (`git merge-base --is-ancestor`, or the
equivalent membership test)? Does the newest **window** agree with the all-time aggregate? Does the
named culprit still fail **when you run it yourself**? Three cheap checks; the first one alone would
have reframed both alarms.

Companions: [[cited-sha-may-not-survive-the-land]] (the same rebase, seen from the citing side —
there it makes a true landing read as never-landed; here it makes a stale verdict read as current),
[[aggregate-correlation-refutes-the-obvious-cause]], [[a-pre-existing-red-is-a-claim-not-a-measurement]],
[[police-the-denominator]].
