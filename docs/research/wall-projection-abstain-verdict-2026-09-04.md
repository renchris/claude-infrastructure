# VERDICT — `wall_projection()`'s abstain window was already widened; backlog `70ed289c10fb` is cured

**Date:** 2026-09-04 · **Row:** `70ed289c10fb` — *"wall_projection() assumes LINEAR weekly burn —
mid-week projection errs by a mean 46pp; widen its abstain window"* · **DoD ref:**
`docs/research/weekly-reset-utilization-2026-08-25.md` · **Verdict:** **ALREADY CURED ON TRUNK.**
No code change was made or needed. This artifact is the evidence that the row can be closed.

## The cure

**`0eb64b73cb4f9b4f26c00ac1171f418cea12f388`** — *"fix(accounts): wall_projection's abstain floor
was guarding the arithmetic, not the model"*, 2026-09-01.

Asserted an ancestor of trunk, not merely resolvable in this checkout:

```
$ git merge-base --is-ancestor 0eb64b73 origin/main   # exit 0
```

It moves `MIN_ELAPSED_FRAC` in `bin/claude-accounts` from `0.05` (~8.4 h elapsed — a guard sized for
the *arithmetic* blowing up near zero elapsed) to `6.0 / 7.0` (the day-6 mark, ~24 h left), which is
exactly the remedy the DoD doc prescribes in §6: *"widen the abstain rule so the projection stays
silent mid-week … and speaks only in the last ~2 days where linear and empirical converge."*
The doc's own §6 already carries a `✅ SHIPPED 2026-09-01` callout naming this backlog id. The row
was never closed; the work was done.

⚠️ **This checkout arrived SHALLOW at depth 50.** Before any trunk read it was deepened
(`git fetch --unshallow`). Without that, `git log -S'MIN_ELAPSED_FRAC = 6.0 / 7.0'` returns empty and
`git merge-base --is-ancestor` exits 1 — both indistinguishable from "never landed" — and the cure
would have been re-derived. `git rev-list --count HEAD..origin/main` read **0**: this tree *is* trunk.

## What was actually run, and what it proves

The DoD doc's §6 makes three falsifiable claims about the shipped fix. All three were executed
against trunk content, not read off the prose.

**1. The floor is where the doc says.** `bin/claude-accounts:2333` reads
`MIN_ELAPSED_FRAC = 6.0 / 7.0`.

**2. The suite binds it — 11/11 green.** `bats tests/claude-accounts-burn-ratio.bats`:

```
1..11   (ok 1 … ok 11 — no failures)
```

Including the four day-3 backtest rows from the DoD doc's §3 table, now sited as *silence* fixtures
(case 3, "ABSTAINS across the whole mid-week regime — the 46pp error class"), the day-5 case
(case 4, the residual 35 pp), and the boundary pair pinning the floor at 25 h silent / 24 h speaking
(case 5).

**3. Both mutants red, and they red on the right cases** — so the suite is not passing vacuously:

| mutant | reds | which |
|---|---:|---|
| `MIN_ELAPSED_FRAC = 0.05` (restore the old floor) | **3** | cases 3, 4, 5 — exactly the three abstain cases the widening added |
| `MIN_ELAPSED_FRAC = 1.01` (never speaks) | **5** | cases 2, 6, 7, 8 — the four in-range cases — **plus** case 5, the boundary pair |

The doc says a never-speaks floor *"reds exactly the four in-range ones"*. Measured, it reds those
four **and** the boundary case, because case 5 asserts both sides of the floor (`25 h → NONE`,
`24 h → not NONE`) and a never-speaks floor breaks its second half. The doc counts that case under
its separate *"a boundary pair pins the floor"* clause; the two statements are consistent, but the
"exactly four" phrasing under-counts the mutant by one. Noted for accuracy, not as a defect.

**4. The abstain propagates to every consumer, not just the return value.** The DoD doc claims
`burn_ratio`, `proj_end_pct`, `wall_risk` and the pace-line `⚠ WALL` flag all go silent with it.
Verified by reading both call sites: `bin/claude-accounts:2224` gates all three derived fields
behind `if ratio is not None:`, and the pace-line branch at `:2517` guards its `⚠ WALL` render with
`if ratio is not None and proj >= 100.0`. Below the floor the fields are **absent**, not stale — so
no downstream consumer can read a mid-week projection the function declined to make.

## Sibling suites: 92 pass, 7 fail — all environmental, none attributable here

`tests/claude-accounts-core.bats` + `tests/claude-accounts-strand.bats` fail 7 cases on this box:
`--relogin-info` (30), `--login-status` (59, 60, 61), and `read_creds` (86, 87, 88). Every one
exercises the macOS keychain/login path — `read_creds` raises `FileNotFoundError` from
`subprocess.run` because the macOS `security` binary does not exist on this Linux VM. They are
unrelated to `wall_projection`, they are red for the environment rather than for the code, and this
session's diff is documentation only. Attributed, not driven.

## Dispatcher vintage

The brief that fired this session was composed by `bin/cc-dispatch` blob
`646b8a652e71dd5e5e506dffe23725437accea6b`; trunk carries
`98ab38f51f7ac82a043e522d3a9601ff9f460528`. **DIFFERENT — the firing dispatcher is BEHIND trunk.**
That is a convergence fact about the deploy layer (landed ≠ live), not a defect in the fix read
above. It has no bearing on this verdict: the cure was asserted against `origin/main` directly.

## Disposition

The row is **cured, not open**. Nothing to implement; the correct close is to mark
`70ed289c10fb` done with `0eb64b73` as its evidence. Re-dispatching it would produce a diff that
re-lands work already on trunk.

The one piece of genuinely open work in this area is untouched and stays open: the DoD doc's §5.2 —
the empirical curve rests on **4 windows**, which refute the linear model but cannot calibrate a
replacement. Its §6 records why the shape-corrected divisor was rejected (leave-one-out MAE 54.1 vs
linear's 39.5; the shape is a fossil of the operator's own end-of-window rush, so an estimator
fitted to it fails toward complacency). Re-derive after ≥2 more full cycles — that is a scheduled
re-measurement, not a defect, and it is not this row.
