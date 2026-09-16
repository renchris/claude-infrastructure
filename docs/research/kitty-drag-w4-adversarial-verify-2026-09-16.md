# W4 adversarial verification — the witness rule, re-derived not graded

Verifier: adversarial pass on wave W4, 2026-09-16. Lens: **the witness rule**
(`scripts/kitty-pane-graph.py` must test the pane SET before the pane ORDER).
Nothing below is the implementer's reported output; every line was re-run here.

## 1. The set test genuinely precedes AND short-circuits the order test

Not "both exist" — an early `return`. Read off the tracked file:

```
248:    # ----- STEP 1: THE SET TEST.  Runs first.  Returns. -------------------
249:    gone = sorted(set(b) - set(a), key=_idkey)
250:    new  = sorted(set(a) - set(b), key=_idkey)
251:    if gone or new:
252:        return {  'verdict': VERDICT_SET_CHANGED, ... }      <- RETURNS
266:    # ----- STEP 2: THE ORDER TEST.  Only reachable on a stable set. -------
268:    for key in sorted(b, key=_idkey):
```

STEP 2 iterates `sorted(b)` and indexes `a[key]` unguarded — it is only
total because STEP 1 has already returned on any set change. The order is
load-bearing in the code, not merely in the comment.

## 2. The control suite is a real result (S6), and the seam is live

```
$ /opt/homebrew/bin/bats tests/kitty-pane-graph.bats
bats rc=0 ; 1..14 ; ok:14 ; not ok:0
```

Plan line `1..14` present, so this is a verdict and not a cc-bats refusal.

The suite exposes `KITTY_PANE_GRAPH_BIN`. Positive-controlled before use, so a
mutant verdict through it is attributable:

```
$ KITTY_PANE_GRAPH_BIN=/tmp/kdv2-W4-0/NO_SUCH_FILE.py bats tests/kitty-pane-graph.bats
rc=1 ; ok:0 ; not ok:14
```

## 3. THE MUTANT — built here, run here, and it kills branch (b) only

Order test moved above the set test, iterating `set(b) & set(a)` (the faithful
pre-fix shape: it does not crash, it fabricates silently). Applied to a scratch
copy through the seam; the tracked file was never written by this verifier.

```
$ KITTY_PANE_GRAPH_BIN=/tmp/kdv2-W4-0/mutant.py bats tests/kitty-pane-graph.bats
bats rc=1 ; ok:11 ; not ok:3
not ok 3 (b) member closed: a pane close is NOT a reorder, it is SET-CHANGED
not ok 4 (b) member closed: names the gone pane and reports no moves
not ok 5 (b) member closed: --expect REORDERED must FAIL, rc 1
```

11 green / 3 red, and all three reds are branch (b). **The suite is not
decorative on the axis that matters.** The fabrication itself, A/B on one
fixture (3 panes -> 2, nobody dragged anything):

```
MUTANT :  VERDICT: REORDERED — the pane layout genuinely changed.
            why: the pane set is IDENTICAL on both sides ...
            panes before=3 after=2                      <- contradicts its own why
            moved: window 1 ... bottom=[2, 3] -> bottom=[3]
          verdict=REORDERED   rc=0
TRACKED:  VERDICT: SET-CHANGED — NOT a reorder; a pane was opened or closed.
            gone: 2
          verdict=SET-CHANGED rc=0
```

## 4. The `neighbors` schema re-measured independently

Own sandbox kitty, own KITTY_CONFIG_DIRECTORY, socket `/tmp/kdv2.sock`
(outside the `/tmp/kitty-*` glob), all three `KITTY_` vars dropped:

```
 id 1 {'bottom': [2, 3]}
 id 2 {'right': [3], 'top': [1]}
 id 3 {'left': [2], 'top': [1]}
```

A dict; absent keys mean no neighbour; values are lists that can hold >1 id.
Matches the header claim exactly.

## 5. 🚨 FINDING — REORDERED is a LAYOUT claim; the driver reads it as a CHORD claim

`scripts/kitty-drag-w4.sh:503` renders `REORDERED` as:

```
Q9  : YES -- the chord moved a pane. Route A works end to end
```

The graph cannot witness *cause*. Measured on the sandbox above — two
**keyboard** actions, no mouse, no human, both from a clean baseline:

```
$ kitten @ action move_window_forward   ->  verdict=REORDERED
$ kitten @ action next_layout           ->  verdict=REORDERED
$ kitten @ action move_window_backward  ->  verdict=NO-CHANGE   (reset; differ not trigger-happy)
```

Both are kitty defaults (`ctrl+shift+f`, `ctrl+shift+l`) and both are live in
the sandbox. So a stray keypress during the 120 s watch window produces
`REORDERED`, and the script then asserts **"Route A works end to end"** — a
false positive in the one direction W4 must not produce.

The differ is correct (a layout change did occur). The **driver's wording** is
the over-claim. Cheapest fix, no logic change: reword to *"a layout change was
observed during the window — if you pressed anything other than the chord,
re-run"*, or unbind the layout actions in the generated sandbox config.

## 6. Attacks that FAILED (re-derivations, not defects)

- **Dry-run selfcheck vacuous through a pipe?** No. `scripts/kitty-drag-w4.sh:78`
  sets `set -euo pipefail`; reproduced the exact pipe shape with a failing
  `--expect` and the outer rc is 1 with the post-pipe line unreached.
- **Driver rolls its own comparison?** No. Both the poll (`:477`) and the final
  verdict (`:498`) call `kitty-pane-graph.py`; there is no second differ.
- **`--dry-run` binding count / LEFT assertion fabricated?** No. 6 `mouse_map`
  lines, all `left`, and `:558-561` are real `die`s on the generated file, not
  printed conclusions. (My first `grep '^mouse_map'` returned 0 — the display
  indents via `sed 's/^/    /'`. The instrument was wrong, not the script.)
- **Implementer's empty-population residual.** Confirmed honest: the
  `/tmp/kitty-*` glob `die` precedes the live-socket loop, so that loop can
  never fire. Defence in depth, correctly declared as such.

## 7. 🚨 COLLISION HAZARD OBSERVED LIVE — mutants applied to the TRACKED file

At **16:18:5x** the tracked `scripts/kitty-pane-graph.py` was read as
sha `9738154e…`, 18300 B, with **STEP 2 (order) above STEP 1 (set)** and
`set(b) & set(a)` — i.e. the fabricating mutant, live in the tracked file.
Seconds later it was back to pristine `7be0a7bc…`, 18286 B, and stayed there
across 12 samples over 24 s, 14/14 green, SET-CHANGED on the pane-close fixture.

Transient, not shipped. But the window is real: a sibling applying a mutant by
**overwriting the tracked file** means any `git add` landing in that window
ships a differ that fabricates REORDERED. The suite already ships
`KITTY_PANE_GRAPH_BIN` precisely so a mutant never needs to touch the tracked
file — use the seam, not an in-place overwrite. Pristine bytes preserved at
`/tmp/kdv2-W4-0/PRISTINE-7be0a7bc.py` for one-command restore.
