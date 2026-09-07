# VERDICT — `backlog-pipeline-unwedge.bats::D3 CONTROL` was already cured on trunk

Backlog row: `6da4339bd9d0` — *post-land RED: tests/backlog-pipeline-unwedge.bats::D3 CONTROL:
retire is NOT called before the work is verified on trunk @ 7d72371caa2d*.
Verdict: **ALREADY CURED. No code change made.** Cure sha `28ec92a8e315115e9a2d68df015ff6d8f17029ac`
(`fix(backlog-pipeline-unwedge test): the D3 control tested a proxy, and the proxy indicted a sound
guard`, 2026-09-07 11:02:59 -0500), asserted an ancestor of trunk with
`git merge-base --is-ancestor 28ec92a8 origin/main` → exit 0.

## What was actually run, off-box, on a VM whose checkout is trunk

`git rev-list --count HEAD..origin/main` = 0 at `a7e5a609`, after `git fetch --unshallow` (the
dispatched checkout arrived shallow at depth 50; every trunk read below would otherwise have
answered from inside that horizon). `bats` is not present on the image, so bats-core was cloned into
the scratchpad and the suite run from there.

| Tree | Result |
|---|---|
| `7d72371caa2d` (`git archive` → clean extract) | **15/16 — `not ok 12 D3 CONTROL`**, failing at `tests/backlog-pipeline-unwedge.bats:156` |
| `origin/main` @ `a7e5a609` | **16/16 ok**, D3 CONTROL among them |

The RED reproduces faithfully at the cited sha and is gone at trunk. Isolating the assertion from
bats and running the old proxy body against `scripts/cloud-return.sh` @ `7d72371caa2d` prints
`UNGUARDED at 540` — the exact false indictment the cure commit names.

## Why the RED was a defect in the instrument, not in the subject

All three `retire --id` call sites in `scripts/cloud-return.sh` are, and were at `7d72371caa2d`,
genuinely guarded:

- **`:540`** sits inside `if item_is_done "$item"; then` — the row was closed by someone else, so
  this session has no work to verify and none to strand; custody is abandoned and the branch is left
  on origin.
- **`:1037`** and **`:1059`** sit under `[ "$landed_ok" -eq 0 ]` branches — content-verified on trunk.

The old assertion asked whether the string `landed_ok" -eq 0` appeared *anywhere earlier in the
file*. `landed_ok` is first assigned at `:859`, so `:540` failed purely for being earlier in the file
than an unrelated assignment. Weak and strict in the wrong places at once, as the cure commit says.

## Honest limit of the cure — recorded, not fixed

The replacement bounds the search to a 40-line window above each call. Mutation-tested here:

| Mutation | Caught? |
|---|---|
| unguarded `retire --id` injected at line 200 | ✅ `UNGUARDED at 200` |
| `item_is_done` guard stripped from the `:540` branch | ✅ `UNGUARDED at 540` |
| unguarded `retire --id` injected at line 950 | ❌ **passes** |

The third escapes because line 917 (`if [ "$landed_ok" -eq 0 ] && [ -n "$BACKLOG_BIN" ]`) is 33 lines
above it and satisfies the window by proximity alone. The cure commit's comment claims "a retire
dropped in without a guard still goes red"; that holds for the file's genuinely unguarded regions but
is not universal — a fixed text window cannot distinguish an enclosing branch from a neighbouring
one. This is a residual property of a structural test, not a regression and not this row's RED, so it
is recorded here rather than changed. Closing it would mean parsing the enclosing branch (or moving
the property to a behavioural test), which is new work and outside this row's frozen scope.

## Dispatcher vintage

`git rev-parse origin/main:bin/cc-dispatch` = `98ab38f51f7ac82a043e522d3a9601ff9f460528`, **equal** to
the blob that composed this brief. The dispatcher that fired this session is trunk, so nothing here
turns on a landed-but-not-live gap in the dispatch layer.
