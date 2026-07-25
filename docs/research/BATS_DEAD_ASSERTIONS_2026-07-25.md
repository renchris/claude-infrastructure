---
status: open
found-by: relogin-build session, 2026-07-25 (surfaced by tm/relogin-browser, verified by lead)
scope: FINDING + REPRODUCTION ONLY — deliberately NOT swept in this session (see "Why not fixed here")
---

# 212 bats assertions in this repo are structurally dead

## The defect — TWO classes, not one

An assertion inside a bats `@test` is a **silent no-op unless it is the last statement of
the test**, if it takes either of these two forms. The assertion runs, evaluates false,
and the test passes anyway.

| Form | Why it is exempt | Non-final behaviour |
|---|---|---|
| `! cmd` | POSIX exempts a `!`-inverted pipeline from `errexit` | **DEAD** |
| `[[ ... ]]` | bash keyword — the `ERR` trap bats relies on is skipped | **DEAD** |
| `[ ... ]` | ordinary command | correctly fails ✓ |
| plain command | ordinary command | correctly fails ✓ |

**The `[[ ]]` class is the more dangerous of the two** — it is the idiomatic bash
conditional, so it is far more common than `!`, and unlike `!` there is no shellcheck rule
that flags it. shellcheck flags only the `!` form, as **SC2314** (error severity).

> The `[[ ]]` class was found by `tm/relogin-sched` while fixing the `!` class, and is why
> the count in this document more than doubled. Finding one silent-assertion class is a
> reason to go looking for its siblings, not a reason to declare victory.

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

And the second class, isolated against two controls:

```bash
@test "non-final [[ ]] false — should fail"          { [[ 1 -eq 2 ]]; [ 1 -eq 1 ]; }
@test "non-final [ ] false — should fail"            { [ 1 -eq 2 ];   [ 1 -eq 1 ]; }
@test "non-final plain command false — should fail"  { false;         [ 1 -eq 1 ]; }
```

```
ok 1     non-final [[ ]] false — should fail          <-- DEAD
not ok 2 non-final [ ] false — should fail            <-- correct
not ok 3 non-final plain command false — should fail  <-- correct
```

> A synthetic probe in *final* position **refutes** the bug — it fails correctly. That is
> why this survived: the only way to expose it is a non-final position, or by breaking the
> implementation under test and watching the suite stay green.

## Exposure, measured

| form | total in `@test` blocks | **non-final ⇒ DEAD** |
|---|---|---|
| `! cmd` | 186 | **89** |
| `[[ ... ]]` | 213 | **123** |
| **combined** | **399** | **212, across 51 files** |

51 of 119 test files — **43% of the suite** — contain at least one assertion that can
never fail.

Worst offenders:

| count | file |
|---|---|
| 31 | `tests/cc-reaper.bats` |
| 19 | `tests/handoff-teardown-marker.bats` |
| 17 | `tests/cc-notify.bats` |
| 16 | `tests/claude-kimi.bats` |
| 12 | `tests/lr-select.bats` |
| 9 | `tests/claude-accounts-core.bats` |
| 8 | `tests/teammate-auto-shutdown.bats` |
| 6 | `tests/handoff-fire-account-sweep.bats`, `handoff-selfclose.bats`, `team-orphan-reaper.bats` |

**`cc-reaper.bats` carries 31, and cc-reaper kills panes.** Its negative assertions
("does NOT reap when …") are precisely the shape that dies silently — so the guard rails
on an autonomous destructive actor may be materially less tested than the green suite
implies. `teammate-auto-shutdown` and `team-orphan-reaper` are the same story. Start there.

## The fix

Two rules:

1. **Never use `[[ ]]` as a bats assertion — use `[ ]`.** It is a drop-in for nearly every
   comparison in these suites and it is actually enforced. (`[[ ]]` remains fine in
   non-assertion contexts, e.g. inside an `if`.)
2. **For negations, use `run` + an explicit status check**, never a bare `!`:

```bash
refute() { run "$@"; [ "$status" -ne 0 ]; }
```

Portable, no bats-version floor, and `run` captures status explicitly instead of relying
on errexit. (`refute_output` / `assert_failure` from `bats-assert` would also work but add
a dependency this repo does not currently take.)

⚠️ **shellcheck will NOT catch the `[[ ]]` class** — SC2314 covers only the `!` form. A
lint-only gate is therefore insufficient; the block-position analyzer below is the real
detector.

**Verification discipline that actually proves the fix:** converting the assertion is not
enough — break the implementation under test once and confirm the test goes RED. A suite
that stays green against a deliberately broken implementation is proving nothing. That is
how this was found: `tm/relogin-browser` neutered its own `--headless` handling, the test
still passed, and that was the tell.

## Why not fixed here

The Follow-On Gate fails on **boundedness**: 212 assertions across 51 files — 43% of the
suite — and this repo currently has many concurrent writer sessions holding those same
test files in their own worktrees. A 51-file sweep from this session would collide with
in-flight work and drag unrelated files into a landing whose scope is the relogin build.
The measurement is cheap and collision-free; the sweep is neither.

The relogin build's own five suites are clean — the two classes were found *because* a
teammate broke its own implementation and watched the suite stay green, then went looking
for the sibling class.

## Root cause — the gate has never linted a single `.bats` file

Found by `tm/relogin-exec`, verified by lead. `scripts/ship-land.sh:85`:

```bash
is_shell_file() {  # *.sh/*.bash OR a shell shebang
  case "$1" in *.sh|*.bash) return 0 ;; esac
  [[ -f "$1" ]] || return 1
  head -1 "$1" 2>/dev/null | grep -qiE '^#!.*(bash|zsh|ksh|dash|(/| )sh)'
}
```

A bats file's shebang is `#!/usr/bin/env bats`, which matches **neither** that regex
**nor** the `*.sh|*.bash` case. So the `/ship` gate's `shellcheck` pass has **never run on
any test file in this repo** — which is exactly why 212 dead assertions accumulated across
51 files with a permanently green suite. This is the mechanism, not just an exposure.

**But fixing `is_shell_file()` alone is NOT sufficient**, and this is the trap: SC2314
covers only the bare-`!` class (89). It does not flag non-final `[[ ]]` at all (123 — the
majority). Wiring bats into the existing shellcheck pass would fix 42% of the problem
while reporting a confidently green gate. The lint is necessary; the analyzer below is
what actually closes the class.

## Detection

`shellcheck -S error tests/*.bats | grep -c SC2314` catches **only the `!` class** and
will report a falsely reassuring number. Use the block-position analyzer, which finds
both — it parses `@test` blocks by brace depth and flags any `!` or `[[` that is not the
last meaningful statement:

```python
import re, glob
for f in sorted(glob.glob('tests/*.bats')):
    lines = open(f, encoding='utf-8', errors='replace').read().split('\n')
    i, n = 0, len(lines)
    while i < n:
        if re.match(r'\s*@test\b', lines[i]):
            depth = lines[i].count('{') - lines[i].count('}'); body = []; j = i + 1
            while j < n and depth > 0:
                depth += lines[j].count('{') - lines[j].count('}')
                if depth > 0: body.append((j, lines[j]))
                j += 1
            mean = [k for k, (ln, t) in enumerate(body)
                    if t.strip() and not t.strip().startswith('#')]
            last = mean[-1] if mean else -1
            for k, (ln, t) in enumerate(body):
                s = t.strip()
                if (re.match(r'!\s+\S', s) or s.startswith('[[')) and k != last:
                    print(f"{f}:{ln+1}: DEAD  {s[:70]}")
            i = j
        else:
            i += 1
```

## Suggested sequencing

1. `tests/cc-reaper.bats` first (31, safety-critical destructive actor), then
   `teammate-auto-shutdown` and `team-orphan-reaper` — the same "does NOT reap" shape.
2. Then the handoff cluster (`handoff-teardown-marker` 19, `handoff-selfclose`,
   `handoff-fire-account-sweep`) — these gate pane closure.
3. Then the rest, **one file per commit** so a conversion that turns a test red is
   bisectable. Expect real failures: some of these assertions were never true, and the
   only reason the suite was green is that they never ran.
4. Gate against regression with the analyzer above (not shellcheck alone — it misses the
   `[[ ]]` class entirely).
