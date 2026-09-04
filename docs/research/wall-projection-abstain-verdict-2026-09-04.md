# VERDICT — `wall_projection()`'s abstain window was ALREADY WIDENED; backlog `70ed289c10fb` is cured

**Date:** 2026-09-04 · **Session:** dispatched cloud worker · **Row:** cc-backlog `70ed289c10fb`
*"`wall_projection()` assumes LINEAR weekly burn — mid-week projection errs by a mean 46 pp; widen
its abstain window."* · **DoD ref:** `docs/research/weekly-reset-utilization-2026-08-25.md`

## Verdict

**CURED, three days before this row was dispatched.** No code change was warranted and none was
made. The cure is `0eb64b73cb4f9b4f26c00ac1171f418cea12f388` — *"fix(accounts): wall_projection's
abstain floor was guarding the arithmetic, not the model"*, Tue 2026-09-01 07:11:51 +0000 — and it
is an ancestor of trunk:

```
$ git merge-base --is-ancestor 0eb64b73cb4f9b4f26c00ac1171f418cea12f388 origin/main; echo $?
0
```

That commit is the row's own remedy, not a near-miss: its message names the 46 pp figure, the
2.3× end-of-window acceleration, and the widening this row asks for, and it carries the row id
`70ed289c10fb` forward into both cited documents.

## What landed

`MIN_ELAPSED_FRAC` in `bin/claude-accounts` goes `0.05` → `6.0 / 7.0` (0.857 — the day-6 mark,
~24 h left), across 6 files: the constant and `wall_projection`'s ABSTAIN docstring, the three
bats suites that pin it, and the two cited docs.

The reasoning, preserved because this verdict is the only thing a future re-dispatch of this row
will read: the old 5% floor guarded the **arithmetic** near zero elapsed (at 1 h in, a 1% reading
projects to 168%). It never tested whether the **linear divisor above it** is true, and it is not.
Over 11,287 adjacent pairs across 12 window instances with phase decorrelated from calendar
(r = +0.030), phase 0.0–0.7 runs at 10.9 pp/day and phase 0.7–1.0 at 25.2 pp/day. Backtested at
day 3 the function scores a mean absolute error of 46 pp — against a constant predictor of ~94
scoring 5.3 pp, i.e. mid-week it is 8.7× worse than a number that ignores its input. The floor now
sits where linear and empirical converge (day 6: −17 pp; day 7: −2 pp).

**Widened rather than shape-corrected**, and the reason should survive any future attempt to
"improve" this: the fitted-shape divisor was built and backtested leave-one-out and *loses*
(MAE 54.1 vs linear's 39.5), because between-window shape variance dominates the mean shape — and
the shape is a fossil of the operator's own end-of-window rush, so an estimator fitted to it fails
toward complacency exactly when the planner reading it succeeds.

## What I actually ran

`bats` is not installed on this cloud VM, so I executed the suite's assertions directly against
the module — same loader, same inputs, same expectations as
`tests/claude-accounts-burn-ratio.bats`:

```
PASS  barely-started 1%/167h        -> NONE
PASS  control 10%/20h               -> 0.1135 11.35      (past the floor: the abstain is a floor, not a stub)
PASS  day-3 12%/96h                 -> NONE              ┐
PASS  day-3 17%/96h                 -> NONE              │ the four backtested day-3 windows,
PASS  day-3 25%/96h                 -> NONE              │ mean absolute error 46 pp — all silent
PASS  day-3 51%/96h                 -> NONE              ┘ (this one raised the false ⚠ WALL)
PASS  day-5 47%/48h                 -> NONE              (35 pp — the floor sits ABOVE day 5)
PASS  day-6 boundary                -> 25h NONE / 24h 0.70
MIN_ELAPSED_FRAC = 0.8571428571428571
ALL GREEN
```

The boundary pair is the case that fixes *where* the floor is rather than merely that one exists —
the old 0.05 floor passes every other case in the file while speaking through all of mid-week.

**Consumers verified abstain-clean.** Every read of the projection routes through
`wall_projection()` (`bin/claude-accounts:2224` stamps the row; `:2517` calls it again rather than
reading the stamp, deliberately, so a renderer cannot render nothing when `apply_burn` has not
run). Both call sites have an explicit `ratio is None` arm — `:2534` falls to the bare
`on pace to fill the window` line, which is the M3a strand nowcast speaking, a different
instrument. Repo-wide, nothing outside `bin/claude-accounts` reads `burn_ratio` / `proj_end_pct` /
`wall_risk` at runtime; the only other hits are the bats suite and docs. So there is no second path
that re-derives a mid-week projection around the widened floor.

## Record consistency

Both cited documents already carry the outcome:
`weekly-reset-utilization-2026-08-25.md:197` (✅ SHIPPED 2026-09-01, with what the widening costs
stated) and `USAGE_TELEMETRY_100P.md:524` (M3 row amendment) and `:1474` (§4 supersession note).

One drift corrected in this commit: the M3 row's evidence cell still read *"8 bats, RED-proved
8/8"* — the original 2026-08-16 landing count — while `:1474` and the file on disk both say 11.
`grep -c '^@test' tests/claude-accounts-burn-ratio.bats` returns **11**. Corrected to 11, with the
3 added cases named. Docs-only; no behaviour touched.

## Dispatcher vintage

`git rev-parse origin/main:bin/cc-dispatch` = `646b8a652e71dd5e5e506dffe23725437accea6b`, **equal**
to the blob that composed this brief. The dispatcher that fired me *is* trunk, so this row's
dispatch was not a stale-bytes artifact — it was an open row that its cure never closed.

## Why the row was still open

Nothing in the cure closed the backlog store. `0eb64b73` landed the fix and updated both docs on
2026-09-01 but the row stayed open, so the dispatcher correctly re-issued it on 2026-09-04. That is
a store-closure gap, not a defect in the fix. **Landed is not closed** — the same shape as
*landed is not live*.

⚠️ **Not asserted from here:** whether the cure is *live* on the operator box. `bin/claude-accounts`
reaches `~/.claude` by symlink from the checkout, so a trunk fast-forward there converges it — but
this VM cannot read that box, and this verdict makes no claim about it either way.

## Disposition

Close `70ed289c10fb` against `0eb64b73cb4f9b4f26c00ac1171f418cea12f388`. No follow-on.
