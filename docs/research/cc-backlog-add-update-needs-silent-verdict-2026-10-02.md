# Verdict — post-land RED `cc-backlog-add-update.bats` test 13 is already cured on trunk (2026-10-02)

**cc-backlog item:** `71a4aa9fdc55` — post-land RED: `tests/cc-backlog-add-update.bats::CONTROL — the
needs path stays silent: its stdout IS the id, read off a merged stream` @ `49d1535966e4`.

**Verdict: CURED by `b80c251761a6`, which is on trunk.** No code change. This file is the evidence.

## Cause and cure

- `49d1535966e4` made an unclassed `cc-backlog needs` print a WARN line on stderr. Test 13 ran a bare
  `needs` under bats `run`, which folds stderr into `$output`, so `[[ "$output" =~ ^[0-9a-f]{12}$ ]]`
  failed (line 190).
- `b80c251761a6` (`fix(test): cc-backlog-add-update's needs-path control files the classed form …`)
  passes `--class needs-human`, the form callers are taught. The test's subject (no coverage warning on
  the needs path) is unchanged. Its sibling half, `cc-backlog-needs.bats`, was fixed by `ad5ef734e`.

## What was run (cloud VM, off-box)

| check | result |
|---|---|
| `git rev-parse --is-shallow-repository` → `git fetch --unshallow` | was `true`; unshallowed |
| `git rev-list --count HEAD..origin/main` | `0`, so this tree is trunk (`b80c251761a6`) |
| `git merge-base --is-ancestor 49d1535966e4 origin/main` | rc 0 |
| `git merge-base --is-ancestor b80c2517 origin/main` | rc 0, so the **cure is on trunk** |
| `git log --oneline 49d1535966e4..origin/main -- tests/cc-backlog-add-update.bats bin/cc-backlog` | only `b80c2517` |
| `npx bats@1 tests/cc-backlog-add-update.bats` at trunk | plan `1..33`, 33/33 `ok`, test 13 `ok` |
| same test (`-f 'needs path stays silent'`) at `b80c2517^` | plan `1..1`, `not ok 1`, line 190 regex failed: **red reproduces without the cure** |

So the test fails on the pre-cure parent and passes on the cure.

## Dispatcher vintage

`git rev-parse origin/main:bin/cc-dispatch` = `03e82d02b1fc534d11df9cd4939541225bdb6829`. That **EQUALS** the
blob that composed the brief, so the dispatcher that fired this session is trunk. The row was dispatched
after the cure landed. That likely means the post-land RED row (filed against `49d1535966e4`) was never
tied to the fix-forward commit, because `b80c2517`'s message cites `b9363a1b78b2` and `ab8080a2c4b9`, not
`71a4aa9fdc55`. Close this row with `b80c251761a6` as evidence.
