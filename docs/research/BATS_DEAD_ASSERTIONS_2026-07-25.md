---
status: open
found-by: relogin-build session, 2026-07-25 (surfaced by tm/relogin-browser, verified by lead)
scope: FINDING + REPRODUCTION ONLY — deliberately NOT swept in this session (see "Why not fixed here")
---

# 89 bats assertions in this repo are structurally dead

## The defect

A bare `! cmd` assertion inside a bats `@test` is a **silent no-op unless it is the last
statement of the test.** POSIX exempts a pipeline prefixed with `!` from `errexit`, so
bats' `set -e` never trips on it. The assertion runs, evaluates false, and the test passes
anyway.

shellcheck flags exactly this as **SC2314** (error severity).

## Reproduction (verified on bats 1.13.0, this machine, 2026-07-25)

```bash
@test "non-final bare ! — should fail, does not" {
  ! true          # FALSE. Should fail the test here.
  [ 1 -eq 1 ]     # any assertion after it
}
@test "final-position bare ! — correctly fails" {
  [ 1 -eq 1 ]
  ! true
}
```

```
1..2
ok 1 non-final bare ! should FAIL but may silently pass     <-- DEAD
not ok 2 final-position bare ! correctly fails
```

> A synthetic `! true` probe in *final* position **refutes** the bug — it fails correctly.
> That is why this survived: the only way to expose it is a non-final position, or by
> breaking the implementation under test and watching the suite stay green.

## Exposure, measured

| | |
|---|---|
| bare-`!` assertions inside `@test` blocks | 186 |
| **non-final ⇒ structurally dead** | **89** |
| files affected | 28 |

Worst offenders:

| count | file |
|---|---|
| 31 | `tests/cc-reaper.bats` |
| 6 | `tests/handoff-fire-account-sweep.bats` |
| 6 | `tests/team-orphan-reaper.bats` |
| 4 | `tests/cc-backlog.bats`, `cc-digest.bats`, `comms-drain-activate.bats`, `notify-back.bats`, `operator-readout.bats` |
| 3 | `tests/cc-close-attrib.bats`, `cc-decide.bats` |
| 2 | `tests/boot-resume.bats`, `cc-inbox-guard.bats` |

**`cc-reaper.bats` carries a third of them, and cc-reaper kills panes.** Its negative
assertions ("does NOT reap when …") are precisely the shape that dies silently — so the
guard rails on an autonomous destructive actor may be less tested than the green suite
implies. That file is the highest-value place to start.

## The fix

```bash
refute() { run "$@"; [ "$status" -ne 0 ]; }
```

Portable, no bats-version floor, and `run` captures status explicitly instead of relying
on errexit. (`refute_output` / `assert_failure` from `bats-assert` would also work but add
a dependency this repo does not currently take.)

**Verification discipline that actually proves the fix:** converting the assertion is not
enough — break the implementation under test once and confirm the test goes RED. A suite
that stays green against a deliberately broken implementation is proving nothing. That is
how this was found: `tm/relogin-browser` neutered its own `--headless` handling, the test
still passed, and that was the tell.

## Why not fixed here

The Follow-On Gate fails on **boundedness**: 89 assertions across 28 files, and this repo
currently has many concurrent writer sessions with their own worktrees on those same test
files. A 28-file sweep from this session would collide with in-flight work and drag
unrelated files into a landing whose scope is the relogin build. The measurement is cheap
and collision-free; the sweep is neither.

Detection one-liner for whoever picks it up (counts non-final hits per file):

```bash
shellcheck -S error tests/*.bats 2>&1 | grep -c SC2314
```

## Suggested sequencing

1. `tests/cc-reaper.bats` first (31, safety-critical destructive actor).
2. Then the reaper/handoff cluster (`team-orphan-reaper`, `handoff-fire-account-sweep`).
3. Then the rest, one file per commit so a red conversion is bisectable.
4. Consider adding `shellcheck -S error tests/*.bats` to the `/ship` gate to prevent
   regression — SC2314 catches this class at commit time.
