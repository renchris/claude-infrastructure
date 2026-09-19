# W6a — the ranker's recovery lane

**Branch** `lr100p/w6a` · **worktree** `/Users/chrisren/Development/.worktrees/wt-lr-w6a` ·
**base** `601807233` · **commits** `db89f212b` (code + tests), this report last.

**One line.** `bin/claude-accounts` gains a `--recovery` modifier under which a target must
SURVIVE the recovered session: three survival floors in eligibility, read from the SSOT, classed
POLICY, killable with `CC_ROUTE_RECOVERY=off`, and byte-identical to today when the modifier is
absent.

---

## 1. What changed, by file:function

### `accounts.json` `.router`

| key | value | what it does |
|---|---|---|
| `_recovery` | prose | the rationale, in the file the operator tunes (U13 §4a, extended with the S_CUT-ordering argument and the ULP arithmetic) |
| `RECOVERY_W_FLOOR` | `0.10` | weekly headroom floor — weekly ≥ 90 is excluded |
| `RECOVERY_S_CEIL` | `0.60` | projected-5h ceiling — reuses `DESK_5H_FLOOR`'s already-argued value |
| `RECOVERY_F_FLOOR` | `0.05` | `f_eff` floor for the fable lane — fable ≥ 90 at coupling 0.5 |

### `bin/claude-accounts`

| anchor | change |
|---|---|
| after `urgency_exp` | `RECOVERY_{W_FLOOR,S_CEIL,F_FLOOR}_DEFAULT` + **`recovery_floors(R)`** — env override > SSOT > code default; `CC_ROUTE_RECOVERY=off` returns the neutral triple |
| `ROUTER_OPTIONAL_RANGES` | the three keys, each `(0.0, 1.0)` — optional presence, range-checked when present (catches `60` written for `0.60`) |
| `_validate_router` | **`RECOVERY_S_CEIL < S_CUT` asserted at load**, with the reason in the message |
| `_excluded(r, R, cliff=True, k_of=None, recovery=False)` | new kwarg; under it, after the shared `5h-cutoff`: `recovery-5h-thin` (projected 5h ≥ ceiling) · `no-weekly-data` (absence is not headroom) · `recovery-weekly-thin` (`w_rem < floor`) |
| `score_general(…, recovery=False)` | threads the kwarg into `_excluded` |
| `score_fable(…, recovery=False)` | threads it, and raises the fable floor to `max(FABLE_FLOOR, recovery_floors(R)[2])`, reporting `recovery-fable-thin` only when `FABLE_FLOOR` itself would have admitted (an exhausted bucket keeps `fable-exhausted`) |
| `_rank_pass(…, recovery=False)` / `ranked(…, recovery=False)` | threaded through both cliff passes; the docstring states why the floors are **never yielded** the way the cliff is |
| `main()` `--rank`/`--route` | `recovery = "--recovery" in args`, passed to `ranked` |
| `route-meta` | gains `recovery=1|0` |

**Not touched:** `score_interactive`, `desk_keys`, the desk floors, `DATA_UNAVAILABLE`,
`lr-fleet.sh` (W6b), `handoff-fire.sh`.

### The three reasons and their exit codes

`recovery-weekly-thin` / `recovery-5h-thin` / `recovery-fable-thin` are **not** in
`DATA_UNAVAILABLE`, so `reason_class` returns `policy` and an all-thin fleet exits **2** with the
reasons on stderr and `none` on stdout — never a silent empty rank. `no-weekly-data` is already in
that set and stays **data** (exit 3): we could not SEE the headroom, which is a different fact from
policy refusing.

---

## 2. The incident, reproduced against the real scorer

The fixture in case 2 is U13 §0's 17:00 Z snapshot. Measured in this worktree:

```
dispatch next  (weekly 98 / fable 7 / reset 11.0h, k_work 4) -> 9.070294784580507e-05
dispatch next3 (weekly 11 / fable 0 / reset 67.0h, k_work 2) -> 8.479846232121657e-05
recovery next                                                -> (None, 'recovery-weekly-thin')
recovery next3                                               -> 8.479846232121657e-05
```

`next` is still rank[0] for **dispatch** — that is the correct dispatch answer and this wave does
not relitigate it — and is refused for **recovery** by the weekly floor. The survivor still scores,
so no recovery is parked for want of a target.

---

## 3. RED before, GREEN after

`bats tests/account-recovery-lane.bats` — **15 cases, 12 RED pre-fix, 15 GREEN post-fix.**

### RED tail (before the fix, at `601807233` + the new suite only)

```
1..15
not ok 1 floors are DERIVED from the repo SSOT, never hand-copied, and range-validated there
#   AssertionError: RECOVERY_W_FLOOR
not ok 2 THE INCIDENT: weekly 98 / fable 7 / reset 11h is rank[0] for DISPATCH and recovery-weekly-thin for RECOVERY
#   TypeError: score_fable() got an unexpected keyword argument 'recovery'
not ok 3 the float ULP at weekly 98 cannot admit a thin account any more
#   TypeError: _excluded() got an unexpected keyword argument 'recovery'
not ok 4 the 5h ceiling is TIGHTER than S_CUT, in the direction the guard needs
#   KeyError: 'RECOVERY_S_CEIL'
not ok 5 the 5h ceiling boundary is INCLUSIVE, at exactly the SSOT value
#   KeyError: 'RECOVERY_S_CEIL'
not ok 6 the ceiling reads the PROJECTED 5h, not the measured one: a burning account is refused early
#   KeyError: 'RECOVERY_S_CEIL'
not ok 7 fable-lane floor bites at fable 91 while weekly is fat
#   TypeError: score_fable() got an unexpected keyword argument 'recovery'
not ok 8 an account with NO weekly data is EXCLUDED as no-weekly-data — never admitted on absence
#   TypeError: _excluded() got an unexpected keyword argument 'recovery'
ok 9 the three recovery reasons are POLICY, so an all-thin fleet refuses instead of degrading
not ok 10 KILL SWITCH: CC_ROUTE_RECOVERY=off makes --recovery identical to pre-U13, at the module
#   AttributeError: module 'ca' has no attribute 'recovery_floors'
ok 11 KILL SWITCH: CC_ROUTE_RECOVERY=off is BYTE-IDENTICAL through the CLI on weekly 0/50/98/99
not ok 12 an ALL-THIN fleet exits 2 with the reasons on stderr and 'none' on stdout — never a silent empty rank
#   status=0 out=a98 0.000053
#   a99 0.000026
not ok 13 route-meta carries recovery=1 under the modifier and recovery=0 without it
#   route-meta: acct=fat cliff_band=none … repick_ratio=4      (no recovery= field)
ok 14 NON-REGRESSION: --rank fable WITHOUT --recovery still ranks the thin account
not ok 15 NON-REGRESSION: every existing caller's signature is unchanged — recovery defaults to False
#   AssertionError: _excluded
```

Case 12's pre-fix line is the incident in miniature: the all-thin fleet **exited 0 and named
`a98`**.

### Three cases are GREEN in both arms — they are EQUIVALENCE GUARDS, not red-proofs

Stated rather than counted, per `green-in-both-arms-is-an-equivalence-guard-not-a-red-proof`:

| case | what it guards | the mutant no pre/post arm can exercise |
|---|---|---|
| 9 | the three reasons stay POLICY | a future `DATA_UNAVAILABLE.add("recovery-weekly-thin")` — which would silently turn a refusal into "degrade to a proxy" |
| 11 | `CC_ROUTE_RECOVERY=off` is byte-identical through the CLI | pre-fix the flag was simply unknown, so identity was free; post-fix it is a claim about `recovery_floors`' neutral triple |
| 14 | `--rank fable` without `--recovery` is untouched | `recovery=True` as the default kwarg anywhere in the chain |

### GREEN tail (after the fix)

```
1..15
ok 1 floors are DERIVED from the repo SSOT, never hand-copied, and range-validated there
ok 2 THE INCIDENT: weekly 98 / fable 7 / reset 11h is rank[0] for DISPATCH and recovery-weekly-thin for RECOVERY
ok 3 the float ULP at weekly 98 cannot admit a thin account any more
ok 4 the 5h ceiling is TIGHTER than S_CUT, in the direction the guard needs
ok 5 the 5h ceiling boundary is INCLUSIVE, at exactly the SSOT value
ok 6 the ceiling reads the PROJECTED 5h, not the measured one: a burning account is refused early
ok 7 fable-lane floor bites at fable 91 while weekly is fat
ok 8 an account with NO weekly data is EXCLUDED as no-weekly-data — never admitted on absence
ok 9 the three recovery reasons are POLICY, so an all-thin fleet refuses instead of degrading
ok 10 KILL SWITCH: CC_ROUTE_RECOVERY=off makes --recovery identical to pre-U13, at the module
ok 11 KILL SWITCH: CC_ROUTE_RECOVERY=off is BYTE-IDENTICAL through the CLI on weekly 0/50/98/99
ok 12 an ALL-THIN fleet exits 2 with the reasons on stderr and 'none' on stdout — never a silent empty rank
ok 13 route-meta carries recovery=1 under the modifier and recovery=0 without it
ok 14 NON-REGRESSION: --rank fable WITHOUT --recovery still ranks the thin account
ok 15 NON-REGRESSION: every existing caller's signature is unchanged — recovery defaults to False
```

### Siblings that share this code (run, not assumed)

`bats tests/claude-accounts-core.bats tests/account-cliff-routing.bats
tests/claude-accounts-schema-drift.bats` → **115 ok, 0 not ok.** These are the suites that exercise
`_excluded` / `score_general` / `score_fable` / `_validate_router` / the `.router` block, i.e. every
surface this diff touches. The FULL suite was NOT run (wave rule 4 — the box is contended).

---

## 4. The mutation arms — applied by hand, run, reverted

`/tmp/w6a-mutate.sh` applies one mutant, runs the suite, `git checkout --` reverts, next. The
worktree was verified clean afterwards (`git status --short` empty, `RECOVERY_S_CEIL` back at 0.60).

| mutant | cases turned red | verdict |
|---|---|---|
| **M1** `_excluded`: `_su_projected(r, R) >= s_ceil` → `>` | **exactly 1** — case 5, *the 5h ceiling boundary is INCLUSIVE, at exactly the SSOT value* | killed |
| **M2** `score_fable`: `_excluded(r, R, cliff, recovery=recovery)` → `_excluded(r, R, cliff)` | **exactly 1** — case 2, *THE INCIDENT* | killed |
| **M3** `accounts.json`: `RECOVERY_S_CEIL` `0.60` → `0.90` | **6** — cases 4, 5, 11, 12, 13, 14 | killed, but see below |
| **M3b** `RECOVERY_S_CEIL` `0.60` → `0.80` (loadable) | **exactly 1** — case 4, *the 5h ceiling is TIGHTER than S_CUT* | killed |

**Why M3 is not a one-case kill, and why that is the right outcome.** `0.90` is the value U13 §3b
warns is a *loosening* — `S_CUT` is already 0.85, so a 5h "guard" at 0.90 excludes strictly nothing.
The load-time assertion added to `_validate_router` **refuses that config outright**, so the four
CLI cases (11-14) die at `load_cfg` with

```
claude-accounts: invalid router constants in …/accounts.json: RECOVERY_S_CEIL (0.9) must be
< S_CUT (0.85): a recovery 5h ceiling at/above the shared cutoff excludes nothing
```

rather than reaching the scorer at all. M3b isolates the semantic half: `0.80` is a genuine
loosening that the validator permits, and it kills **exactly one** case — case 4, the assertion
whose whole job is the ordering. Both arms are recorded because the interesting fact is that the
mutant U13 named is now *unshippable*, not merely *detected*.

Case 3 (the ULP) is killed by none of the three named mutants; it is a red-proof of the feature
(pre-fix `TypeError`) and a standing guard on the arithmetic, and that is stated rather than
implied.

---

## 5. Lint

| tool | target | result |
|---|---|---|
| `python3 -m py_compile` | `bin/claude-accounts` | clean |
| `ruff check --isolated --select F` (ruff 0.15.9) | `bin/claude-accounts` | `All checks passed!` |
| `python3 -c 'json.load(...)'` | `accounts.json` | parses; the three keys read `0.1 0.6 0.05` |

`shellcheck` and `bash -n` do **not** apply here: `bin/claude-accounts` is `#!/usr/bin/env python3`
(the wave brief anticipated this — "the file is python or bash, use the right linter"), and
`pyflakes` is not installed on this box, so ruff's `F` ruleset stands in for it. `bash -n` on a
`.bats` file is not a valid check either — `@test "…" {` is bats syntax, not bash; the existing
`tests/account-cliff-routing.bats` fails `bash -n` identically. The suite was verified by RUNNING it.

---

## 6. Deviations from the spec, and why

1. **`--recovery` with `--rank interactive` is REFUSED, not ignored.** The spec scopes the modifier
   to `general|fable` but does not say what the third lane does with it. Silently accepting it would
   be a flag that reads as applied while doing nothing — the exact failure shape of this wave. It
   exits 1 with `--recovery is not defined for --rank interactive (the desk lane hosts no
   transplanted session)`. `score_interactive`'s signature is deliberately left without the kwarg,
   and case 15 asserts that.
2. **The kill switch's neutral ceiling is `float("inf")`, not U13's `1.0`.** A projected 5h of
   exactly `1.0` is reachable, so `>= 1.0` would let a DISABLED guard exclude a row. `inf` makes the
   neutral triple unreachable by construction. `w_floor` and `f_floor` neutrals stay `0.0` as
   specified.
3. **`RECOVERY_S_CEIL < S_CUT` is enforced in `_validate_router`, not only asserted in a test.** The
   spec says "assert … at load time"; this is that, sited where every consumer of the tool pays it.
   Consequence: M3 is unshippable rather than merely detected (§4).
4. **The recovery weekly floor does not apply the credits target (`0.98`).** `score_general` uses
   `wtgt = 0.98 if credits_on`; `_excluded` uses a flat `1.00`, following U13's sketch. 2 pp of
   reserve is noise against a 10 pp floor and the extra branch is not. Stated in a comment at the
   site.
5. **One extra case beyond U13's eight** — case 6, *the ceiling reads the PROJECTED 5h*. U13
   specifies the projection but no case exercised it, so a `_su_projected` → `session_pct` swap
   would have been invisible. It also forced `CC_UTIL_LOG` into the fixture, without which the
   assertion reads the operator's live burn series.
6. **The all-thin CLI case uses `--rank general`, not `fable`.** Deliberate, so that M2 (a
   `score_fable`-only mutant) turns exactly one case red instead of two. The fable lane's refusal
   path is covered at the module by case 7.

## 7. Blocked / not done

Nothing blocked. Out of scope by the wave brief and left for **W6b**: `lr_pick_target`'s
`--recovery` ask, keeping the router's stderr instead of `2>/dev/null`, the `--assign` phantom
charge, and `handoff-fire.sh:9296`'s `[ "$RECYCLE" = 0 ]` guard. No file outside `accounts.json`,
`bin/claude-accounts` and the new suite was modified.

**Residual, named rather than hidden** (U13 §6, unchanged by this wave): `RECOVERY_W_FLOOR = 0.10`
rests on ONE 2.43 h burn window over 4 accounts on 2026-09-19; the `k_src` work→panes instrument
flip (cap 8 → 40) still changes the concurrency gradient 5× exactly when a fleet recovery runs; and
whether a transplanted session's FIRST hour burns faster than the 0.39 pp/h fleet median is
unmeasured — if it does, this floor should rise.
