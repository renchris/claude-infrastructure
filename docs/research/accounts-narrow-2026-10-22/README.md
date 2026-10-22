# Accounts board at narrow widths, in real Claude Code (2026-10-22)

Scope (frozen): at every pane width down to ~20 columns both the band and the /accounts readout show the picks and every account 5h/weekly used + reset, nothing cut to an ellipsis; below the floor whole words wrap.

The change under test is the uncommitted narrow-layout diff in this worktree: `bin/claude-accounts`
gets a ladder down to 12 cells, and `mods/accounts-readout/hooks/register.tsx` makes band rows
wrap instead of truncating at the end. The probe is `narrow-probe.py` and the table comes from
`summarize.py`, which writes `verdict.json` here.

Committed: this README, the probe and sheet scripts, `verdict.json`, and the judged sheets in
`captures/r7-sheets/` and `captures/r8-sheets/`. The raw per-round captures (226 MB: screen dumps,
ladders, `raw.bin` streams, earlier sheets) are not committed; the `probe-*.sh` drivers regenerate
them, and the paths below that name them are the run's working record.

## Verdict

- **The layouts are right.** With the band arm at every width from 17 to 80 columns, the band
  Claude Code drew matches the producer's chosen layout row for row. Scrolling through the band
  and stitching the views back together gives exactly the ladder variant. No value sits behind an
  ellipsis, and no row is cut at the right edge. Trunk at 27 and 20 columns is red, with 35-38
  ellipsis rows and no 5h or weekly value readable anywhere.
- **The scope is not met on the first screen, because Claude Code caps the band's height.** The
  band window is about half the pane height minus 5 rows, counting its own `↓ N more` cue:
  10 rows at 30 rows tall, 17 at 45 and 30 at 70. This holds even when the transcript above it is
  empty. The narrow forms use 3 rows per account, so on a 45-row pane:
  - with live-shaped rows, the desk pick's own account (next2) is below the fold from 27 columns
    down;
  - from 17 columns down, no account's values are on the first screen;
  - the fixture rows overflow from 40 columns down.

  Every value can still be reached by scrolling the band with the mouse wheel over it, or with
  ctrl+x tab and then the arrow keys. On a 70-row pane the live-shaped band fits whole at 27 and
  20 columns.
- **Below the floor, words break mid-word.** At 12-16 columns, Claude Code hands the band 7-11
  cells, because 5 columns are reserved for the `[-]` collapse mark. That is under the ladder's
  12-cell floor, so Ink hard-wraps the 12-cell layout by character:
  - `gener|al`, `confi|rmed`, `Anthr|opic'|s`;
  - the countdowns break across rows: `4h|43m`, `1h|11m`.

  At 15 columns the values survive but names and prose break (`quaternary|-`).
- **The /accounts readout passes with live-shaped rows from 20 to 40 columns**: all four accounts
  are whole on the screen. At 17 columns and below, or with the tall fixture rows, the readout is
  taller than the screen and the earlier accounts sit above it in the transcript, which scrolls
  as normal. Nothing in the readout is cut.
- The prompt input echoed typed text at every width, and the band was gone after the first prompt
  in every run.

## Measured (45-row pane unless stated; band cells = pane − 5)

The "rows shown" column counts band rows from the first `➤` line down to Claude Code's cue. At
20 columns and below, the fixture run's board had aged past 300 s under machine load, so a
7-row `⚠ STALE` head sat above the picks as well. Where a cell says "scroll incomplete", the
stitch stopped at its 80-step budget. In those cases the cue, not the stitch, shows that more
rows exist.

| run | pane | band cells → layout (lines) | rows shown before cue | accounts whole on first screen | all values reachable by scroll | ellipsis rows | split tokens |
|---|---|---|---|---|---|---|---|
| band-live | 80 | 75 → 72 (15) | 16 | all 4 | yes | 0 | — |
| band-live | 40 | 35 → 35 (22) | 16 + ↓ 6 | all 4 | yes | 0 | — |
| band-live | 34 | 29 → 29 (22) | 16 + ↓ 6 | all 4 | yes | 0 | — |
| band-live | 30 | 25 → 24 (19) | 16 + ↓ 3 | all 4 | yes | 0 | — |
| band-live | 27 | 22 → 22 (23) | 16 + ↓ 7 | 3 of 4 (next2 below) | yes | 0 | — |
| band-live | 22 | 17 → 17 (26) | 16 + ↓ 10 | 3 of 4 (next2 below) | yes | 0 | — |
| band-live | 20 | 15 → 16 (29) | 16 + ↓ 13 | 2 of 4 | yes | 0 | — |
| band-live-floor | 17 | 12 → 12 (43) | 16 + ↓ 27 | 0 of 4 | yes | 0 | — |
| band-live-floor | 15 | 10 → 12 (43) | 16 + ↓ 31 | 0 of 4 | yes | 0 | — |
| band-live-floor | 12 | 7 → 12 (43) | 16 + ↓ 63 | 0 of 4 | NO: `4h`/`43m` split | 0 | `➤ general`, `4h 43m` |
| band-live-rows70 | 27×70 | 22 → 22 (23) | 24 | all 4 | yes | 0 | — |
| band-live-rows70 | 20×70 | 15 → 16 (29) | 30 | all 4 | yes | 0 | — |
| band-fx | 80 | 75 → 75 (27) | 16 + ↓ 11 | 3 of 4 (long name `next-quatern…`) | values yes | 1 (name) | — |
| band-fx | 40 | 35 → 35 (48) | 16 + ↓ 32 | 2 of 4 | yes | 0 | — |
| band-fx | 27 | 22 → 22 (53) | 16 + ↓ 37 | 2 of 4 | yes | 0 | — |
| band-fx | 22 | 17 → 17 (63) | 16 + ↓ 47 | 1 of 4 | yes | 0 | — |
| band-fx | 20 | 15 → 15 (73) | 8 + ↓ 65 (stale head) | 0 of 4 | yes | 0 | — |
| band-fx-floor | 17 | 12 → 12 (102) | 16 + ↓ 86 | 0 of 4 | yes | 0 | — |
| band-fx-floor | 15 | 10 → 12 (102) | 16 + ↓ 106 | 0 of 4 | values yes | 0 | `quaternary-`, `Anthropic's` |
| band-fx-floor | 12 | 7 → 12 (102) | 16 + ↓ 172 | 0 of 4 | NO: `1h`/`11m` split | 0 | `general`, `confirmed`, names |
| band-fx-rows30 | 27×30 | 22 → 22 (53) | 9 + ↓ 44 | 0 of 4 | yes | 0 | — |
| band-fx-rows70 | 27×70 | 22 → 22 (53) | 29 + ↓ 24 | all 4 | yes | 0 | — |
| trunk-live | 27 | 22 → 35 (22) | 16 + ↓ 6 | 0 of 4 | NO | 17 | every value `…` |
| trunk-live | 20 | 15 → 35 (22) | 16 + ↓ 6 | 0 of 4 | NO | 18 | every value `…` |
| trunk-fx | 27 | 22 → 35 (44) | 16 + ↓ 28 | 0 of 4 | NO | 35 | every value `…` |
| trunk-fx | 20 | 15 → 35 (44) | 16 + ↓ 28 | 0 of 4 | NO | 38 | every value `…` |

The full table, with the readout rows, is `python3 summarize.py`.

## Method

`narrow-probe.py <band|trunk> <fx|live> <out> [--rows N] [--widths …] [--readout]` runs a real
`pty.fork` of Claude Code 2.1.293 with `--setting-sources project` and its own `--settings`, so
no shared settings file is touched and no slash command is typed. The trunk arm uses `git show` /
`git archive` copies of `origin/main`'s `bin/claude-accounts` and `mods/accounts-readout`; the
hooks are byte-identical to trunk. The producer renders fresh over the rows into scratch under
`/tmp/narrow-verify/probe/`.

The terminal is a single pyte screen, resized at the same moment as the pty. Each step does four
things:
1. It dumps the screen with colors and snaps it to a PNG.
2. It scrolls the band to its end with the mouse wheel and stitches the views together, giving
   `*-band-whole.*`.
3. It scrolls back to the top.
4. It types `zq` into the prompt, reads it back, and deletes it.

Expected values are read from the producer's widest grid by its own header columns. A value
counts only when it sits whole in one row of its account's block, in the order 5h used, 5h reset,
weekly used, weekly reset. The readout's expected values come from its own ladder, which renders
minutes later.

Caveats from this machine (load averages 400-550 during the runs):
- Claude Code's startup blocked for minutes inside a keychain read (`SecItemCopyMatching`,
  sampled). The probe now refuses to give a verdict when no board is drawn.
- `readout-00-80` is a pyte artifact of Claude Code's scroll-region writes after a turn; the
  repaint at the next resize is clean.
- Claude Code cuts its own overflow cue at 17 columns and below (`↑ 10 more · ↓ …`), so the probe
  stops scrolling on three unchanged steps rather than on the cue.

## Round 2: the dense family and the 8-cell floor (renderer, 2026-10-22)

`bin/claude-accounts` now writes two families into every ladder: the full layouts, and a `dense`
one (`"dense": true`, listed first, each family narrowest first) laid out for the band's height:
the picks with agreeing lanes on one row, every account's name and its four values, alerts, and
the read clock, with no live counts, desk clause, drain line, `--fresh` hint or blank rows. The
full family's floor moved from 12 cells to 8. Rows of the dense variant on the live-shaped rows
(4 accounts, lanes agree), as rendered, at the band widths the mod's `pickFit` would hand it:

| band cells | 8-9 | 10-11 | 12-18 | 19 | 20-21 | 22-27 | 28+ |
|---|---|---|---|---|---|---|---|
| dense rows | 27 | 25-26 | 16 | 15 | 11 | 8 | 8 |
| form | five rows an account | same | name, 5h, weekly | same | name+5h, weekly | cards side by side | one row an account |

With the lanes split (desk ≠ general/fable) each width costs up to two rows more: 9 rows from 22
cells, 16-18 at 12-20. Screens judged: `/tmp/narrow-fix/renderer/final/sheet-*.png`.

`captures/band-live-floor8/` is this probe re-run with the round-2 producer and the UNCHANGED mod
(so the band still draws the full family; picking dense is the mod's change), live rows, 45 rows
tall, at 80, 17, 15, 14, 13, 12, 80 columns. At 13 columns Claude Code hands the band 8 cells and
draws the 8-cell floor form row for row: every name and value whole, no word broken by Ink
(`band-04-13*`). At 12 columns (7 cells, under the floor) the mod falls back to the first
variant and Ink wraps it at spaces, still without splitting a token (`band-05-12-band-whole.txt`).
The probe's own `reach_whole` reads false at every floor step for a reason in the probe, not the
screen: its expected values come from the wide grid (`4h 43m`), and the floor forms print each
countdown as one token (`4h43m`). The first attempt drew no board (the keychain stall above, load
~330) and was re-run.

## Round 3: the mod picks by height too (mods/accounts-readout, 2026-10-22)

`pickFit(ladder, cells, maxRows, headRows)` now reads the band's `maxRows`. Among the layouts
whose widest line fits the cells, it takes the full family's widest that leaves the `↓ N more` row
free (`lines + head <= maxRows - 1`). If no full layout fits, it takes the dense family's widest.
If nothing fits the height, it takes the layout with the fewest rows, and on a tie the widest.
Ranking both families on width alone flipped families as a tall band widened (full at 17 cells,
dense at 20 for one cell of width, full again at 22), so the full family wins wherever it fits
whole. `pickVariant` (the transcript `/accounts` readout, no height cap) draws only the full
family. A ladder with no `dense` flag picks as before.

The stale and hard heads now count against the same rows, and they arrive pre-wrapped at word
boundaries, so Ink never breaks `claude-accounts` mid-word. A word wider than the row breaks after
its `-`, as in `claude-` / `accounts`. `bandLayout` picks the head form from fullest to leanest:
1. the hook's own sentence, with its blank row;
2. the same sentence without the blank row;
3. `⚠ stale 6m · live: claude-accounts` on one row, where it fits;
4. `⚠ stale 6m` / `live: claude-accounts`;
5. `⚠ stale 6m` alone.

The full sentence is offered only from 25 cells. `bandLayout` keeps the fullest head that still
leaves the best layout whole. On a 30-row pane, that means `⚠ stale 6m` alone over the 8-row
cards, because the 2-row short head would push them one row past the band. Past the hard band
the head is `numbers withheld (2h old)` / `run claude-accounts`.

`captures/band-live-mod-rows30/` is this probe with the round-2 producer and the round-3 mod: live
rows, 30 rows tall (`maxRows` 10). At 80, 40, 30 and 27 columns the band draws the dense layout,
8 rows, with the picks and all four accounts' 5h and weekly use and reset whole on the first
screen and no cue (`band-00-80.png`, `band-02-30.png`, `band-03-27.png`). Width alone (the
previous `pickFit`, run over the same ladder, not re-probed) takes the 16-row full grid at 80
columns, which a 10-row band would scroll. At 22 and 17 columns (17 and
12 cells) the narrowest dense forms are 16 rows, which still scroll (`↓ 7 more`). At 13
columns the 8-cell floor is 27 rows. Those row counts are the renderer's (Round 2's open issue),
and the mod already picks the fewest-row layout there. The probe's per-account verdict reads
"bad" on every dense frame for the reason given in Round 2 (its oracle expects the wide grid's
`4h 43m` and its picks rows), so these frames were judged by eye.

`captures/band-live-mod-rows45/` is the same at 45 rows (`maxRows` 17), at 80, 40, 22, 13 and 80
columns:
- At 80 columns the band draws the 16-row full grid whole, with no cue. The band spans 16 rows,
  which is `maxRows - 1` exactly, so a tree that leaves the cue row free does show whole. Whether
  a 17-row tree would also show whole, as the type docs say ("a tree of at most `maxRows` rows
  shows whole"), was not tested. The mod keeps the cue row free regardless.
- At 40 columns the band draws the 8-row dense table.
- At 22 columns (17 cells) the band draws the 16-row dense form whole, with all four accounts on
  the first screen. Round 1 had next2 below the fold at this width (`band-02-22.png`).
- At 13 columns the band draws the 27-row floor, which scrolls (`↓ 11 more`).

Two runs drew no board within 150 s at load ~250 (the keychain stall). `NARROW_START_S` now
widens the probe's startup bound; the runs here used 420 s and 900 s.

## Round 4: the full sweep, measured against the bar (probe-1, 2026-10-22)

The bar has two parts:
- Live-shaped rows: the picks and every account's 5h used/reset and weekly used/reset sit whole
  on the band's first screen at every pane of 30+ rows and 17+ columns.
- Fixture rows: every account value sits on the first screen at 45+ rows and 27+ columns. The
  alerts may scroll.

Test setup:
- Real Claude Code 2.1.293 in a pty, with the worktree's producer, mod and hook as they stood at
  07:25. The probe snapshots the producer and mod at the start of each run, and
  `verdict.json` → `round4.runs.*.provenance_sha256_16` records their hashes.
- Pane heights 30, 45 and 70 rows. Widths 80, 40, 34, 30, 27, 22, 20, 17, 16, 15, 13 and 12, then
  80 again.
- `NARROW_STALE_S=86400` keeps the board fresh for the whole sweep (aged and stale runs are below).
- Every capture was snapped and judged by eye. The side-by-side sheets are in
  `captures/r4-sheets/`.

**Verdict:**
- **Fixture: met.** 12 of 12 cells pass (`round4.bar` in `verdict.json`).
- **Live: not met on a 30-row pane at 22, 20 and 17 columns.** The band draws the 16-row dense
  form (name / 5h / wk rows) into a 10-row window. next and next4 show; next3 and next2 (the
  desk's own pick) sit under `↓ 7 more` (`r4-sheets/live-rows30-a.png`). Every other live cell
  at 17+ columns passes.

Across every capture, fresh or aged:
- no ellipsis anywhere;
- the prompt echoed typed input at every width;
- the band was gone after the first prompt.

### Measured: first screen, per pane height × width (fresh board)

A cell reads `✓|✗ <d=dense|f=full><cells>/<rows> [↓N more] [↩N]`:
- ✓ means the picks and all four accounts' names and values are whole on the first screen.
- `↓N` is Claude Code's own fold cue.
- `↩N` counts the producer's own mid-word hard breaks across the whole band.
- `Ink-wrap` means no ladder variant fits (7 cells is under the 8-cell floor), so Ink wraps the
  narrowest variant.

| data × pane rows (maxRows) | 80 | 40 | 34 | 30 | 27 | 22 | 20 | 17 | 16 | 15 | 13 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| live × 30 (10) | ✓ d30/8 | ✓ d30/8 | ✓ d30/8 | ✓ d24/8 | ✓ d22/8 | ✗ d15/16 ↓7 | ✗ d15/16 ↓7 | ✗ d12/16 ↓7 | ✗ d11/25 ↓16 | ✗ d10/26 ↓17 | ✗ d9/27 ↓18 | ✗ Ink-wrap ↓36 |
| live × 45 (17) | ✓ f72/15 | ✓ d30/8 | ✓ d30/8 | ✓ d24/8 | ✓ d22/8 | ✓ d15/16 | ✓ d15/16 | ✓ d12/16 | ✗ d11/25 ↓9 | ✗ d10/26 ↓10 | ✗ d9/27 ↓11 | ✗ Ink-wrap ↓29 |
| live × 70 (30) | ✓ f72/15 | ✓ f35/22 | ✓ f29/22 | ✓ f24/19 | ✓ f22/23 | ✓ f17/25 | ✓ f16/28 | ✓ d12/16 | ✓ d11/25 | ✓ d10/26 | ✓ d9/27 | ✗ Ink-wrap ↓16 |
| fx × 30 (10) | ✗ d69/19 ↓10 | ✗ d34/26 ↓17 | ✗ d29/33 ↓24 | ✗ d25/37 ↓28 | ✗ d22/42 ↓33 | ✗ d17/54 ↓45 | ✗ d15/60 ↓51 | ✗ d11/85 ↓76 ↩4 | ✗ d11/85 ↓76 ↩4 | ✗ d10/92 ↓83 ↩7 | ✗ d8/102 ↓93 ↩10 | ✗ Ink-wrap ↓138 ↩7 |
| fx × 45 (17) | ✓ d69/19 ↓3 | ✓ d34/26 ↓10 | ✓ d29/33 ↓17 | ✓ d25/37 ↓21 | ✓ d22/42 ↓26 | ✗ d17/54 ↓38 | ✗ d15/60 ↓44 | ✗ d11/85 ↓69 ↩4 | ✗ d11/85 ↓69 ↩4 | ✗ d10/92 ↓76 ↩7 | ✗ d8/102 ↓86 ↩10 | ✗ Ink-wrap ↓131 ↩7 |
| fx × 70 (30) | ✓ f75/28 | ✓ d34/26 | ✓ d29/33 ↓4 | ✓ d25/37 ↓8 | ✓ d22/42 ↓13 | ✓ d17/54 ↓25 | ✓ d15/60 ↓31 | ✗ d11/85 ↓56 ↩4 | ✗ d11/85 ↓56 ↩4 | ✗ d10/92 ↓63 ↩7 | ✗ d8/102 ↓73 ↩10 | ✗ Ink-wrap ↓118 ↩7 |

Notes on the table:
- In every matched cell, the drawn variant is the one the snapshot mod's own `bandLayout`
  predicts (`mod-prediction.json`).
- A ✓ cell with a fold cue on fixture data means only alerts and footers are below the fold.
- The first 80×70 fixture frame reads "no variant matches" in `verdict.json`. The cause is
  Claude Code's transient `◐ medium · /effort` hint row under the band. Its board is
  byte-identical to the final 80-column frame.

### The reason for each value is in the window

Judged by eye, per form:
- The dense table (29+ cells) labels its windows with a `5-hour ── weekly ──` header over
  `used reset used reset`.
- The cards (22-24 cells) label every row `5h` or `wk`; the second account in each pair reads
  by its name column.
- The name / 5h / wk form (12-19 cells) labels every row.
- The floor (8-11 cells) puts each reset on its own row, straight under its labeled `5h` or
  `wk` percent.

None of these forms leaves a value's window ambiguous.

The Ink-wrapped 7-cell band (12 columns) keeps the order but splits every label from its value
and adds blank rows (`5h` / `0%` / blank / `4h43m`; `r4-sheets/live-rows30-b.png`).

### What the extra runs showed

- **A tree of exactly `maxRows` rows shows whole** (`captures/r4x-live-rows45-roomfull/`). In a
  scratch copy of the mod, room was set to `maxRows` instead of `maxRows - 1` (`NARROW_ROOM_FULL=1`).
  On a 45-row pane at 50-57 columns, the 17-row full grid then drew in full with no cue
  (`band-03-55.png`). So the row the mod keeps free for the cue is wasted whenever the band fits;
  on a 30-row pane the band has 10 rows, not 9.
- **The mod's own stale head**, with the board aged past 300 s inside the session
  (`NARROW_IDLE_S=330`, `r4-sheets/aged.png`):
  - With live rows on a 30-row pane, `⚠ stale 6m` takes one row over the 8-row dense board and
    everything stays whole at 27-80 columns.
  - With fixture rows at 27×45 that row pushes `next`'s weekly row below the fold. The fixture
    bar fails once a band has sat for 5 minutes.
- **A board already stale when the session starts** (`NARROW_STALE_S=1`,
  `captures/r4-live-rows30-stale/`) never reaches the band. The hook's stale path prints the
  static grid as a SessionStart message, and Claude Code re-wraps it at 27 columns
  (`band-01-27.png`):
  - the grid's columns scatter across rows;
  - `28d 13h` splits across two rows;
  - `claude-accounts --re|adout` breaks mid-word.
- **/accounts readout:**
  - Live rows at 40 and 20 columns on a 45-row pane, and fixture rows at 40 and 20 columns on a
    100-row pane (`r4-sheets/readout-*.png`): every name and value whole, no ellipsis, no ↩
    break.
  - At 20 columns the narrow variant leaves out the `➤`/`➤ᵍ` marks in front of account names
    and the fixture's `▲ next3 — 5h at 102%` alert. That alert repeats the `✖ next3` alert.
- **The renderer's own `↩` breaks** (fixture rows, 8-12 cells, 13-17 columns,
  `r4-sheets/fx-floor-whole.png`) split words mid-word in alert prose and the 61-character name:
  `Anthropi↩c's`, `confir↩med`, `quaternar↩y`. At 8 cells the break also reaches the name
  heading: `quatern↩ary-`.
- **The picks abbreviate `general` to `gen`** at 20-30 columns (`desk·gen·fable`).

### Method changes in round 4

`narrow-probe.py`:
- snapshots the producer and mod into its scratch arm, records their hashes, and runs the mod's
  `bandLayout` over the ladder through `predict.ts`;
- `NARROW_STALE_S` / `NARROW_HARD_S` set the staleness bands, `NARROW_IDLE_S` ages the band
  inside the session, and `NARROW_ROOM_FULL` is the scratch-only room experiment;
- `--readout-widths` sets the readout's widths separately;
- the band's top is now found by its `[-]` mark, so a head row counts;
- the per-account oracle accepts `4h43m` as well as `4h 43m`.

`summarize.py --r4` judges each screen against the ladder variant it reproduces, and checks the
first screen by token multiset. That fixes the old oracle, which read the card form (two accounts
per row) as missing.

`sheet.py` lays captures side by side for review.

The probe's transcript stitch (`*-transcript-whole.*`) is not reliable on Claude Code's fullscreen
renderer. Wheel scrolling leaves logo fragments in pyte and stitch gaps (23 on the fixture
readout), so the fixture readout was re-measured on a 100-row pane, where it fits on one screen.

## Round 5: the reviewers' findings fixed, measured again (fixer-1, 2026-10-22)

Run: `probe-r5.sh` (captures `r5-*`), judged by `summarize.py --r4 --prefix r5`.

### What changed

The renderer (`bin/claude-accounts`):
- The dense family puts the picks first (desk, general, fable, then config order). When a band is
  cut, it cuts an unpicked account, not the desk's own pick.
- The read clock appears in a dense variant only when the quota was already 5 minutes old when
  the board was written. The band shows its own age.
- New column form (`dy`): two rows per account, each limit's percent over its reset. It covers
  15-19 cells, where the old form needed three rows per account.
- Agreeing lanes fit one row at 11-18 cells (`➤ use next2`), and `general` is spelled out.
- The side-by-side cards carry a `used reset` legend.
- The floor is 7 cells, so a 12-column pane gets a laid-out form instead of Ink re-wrap.
- The wrap no longer cuts a word that fits a row, and a cut stays in its piece. Arrows and
  leading glyphs keep their word.
- Grid columns only appear as the pane widens, and the grid no longer overflows on short or
  wide (CJK) names.

The mod (`ladder.ts`):
- No row is held back for the cue: `room = maxRows`. Round 4 measured that a tree of exactly
  `maxRows` rows shows whole.
- When no layout fits whole, the mod prefers the one whose account rows fit above the cue. The
  ladder carries each variant's `values` row count for this.

### Measured: first screen, fresh board (real pty, Claude Code 2.1.293)

| data × pane rows (maxRows) | 80 | 40 | 34 | 30 | 27 | 22 | 20 | 17 | 16 | 15 | 13 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| live × 30 (10) | ✓ d29/7 | ✓ d29/7 | ✓ d29/7 | ✓ d24/8 | ✓ d22/8 | ✓ d17/10 | ✓ d15/10 | ✗ d12/14 ↓5 | ✗ d11/23 | ✗ d9/25 | ✗ d9/25 | ✗ d7/25 |
| live × 45 (17) | ✓ f72/15 | ✓ d29/7 | ✓ d29/7 | ✓ d24/8 | ✓ d22/8 | ✓ d17/10 | ✓ d15/10 | ✓ d12/14 | ✗ d11/23 ↓7 | ✗ d9/25 | ✗ d9/25 | ✗ d7/25 |
| fx × 45 (17) | ✓ f75/28 | ✓ d34/25 | ✓ d29/32 | ✓ d25/35 | ✓ d22/41 | ✓ d17/48 | ✗ d15/56 | ✗ d12/84 | ✗ d11/84 | ✗ d10/91 | ✗ d8/101 | ✗ d7/106 |

- Two bar cells that failed in round 4 now pass: 22×30 and 20×30. On those panes a 10-row tree
  fills the 10-row band with no cue (`band-05-22.png`, `band-06-20.png`).
- The fixture now passes from 22 columns. Round 4 needed 27.
- 12 columns gets the 7-cell layout instead of Ink re-wrap. No ellipsis anywhere.

The fixture's ✓ cells still show a fold cue. Only its alerts sit below the fold.

### What still fails, and why

- **17×30, live rows.** At 12 cells a 5-character name, a 3-cell percent and a 5-cell countdown
  cannot share a row. So the floor is 3 rows per account: name, then 5h, then weekly. With the
  legend and the picks that is 14 rows against 10. No layout of all 16 values fits. Picks first
  puts the desk pick at the top, so its values show, and the band scrolls to the rest.
- **Split lanes at 30 rows under 27 columns.** This is the renderer model; the live cache had
  agreeing lanes during the probe. Two lane rows, the header and 8 account rows make 11 rows
  against 10. At 27 columns and up the cards fit in 9 rows.
- **A stale head at 30 rows under 27 columns.** The stale head takes one row, so the same layouts
  come to 11 rows. Picks first keeps the cut on an unpicked account. Covered by the mod tests and
  the renderer harness only, not by the probe (see P3 below).
- **Fixture at 27×45 once the band is stale.** The renderer model gives 16 account rows plus the
  head against 17, one over: the 61-character name takes 4 rows at 22 cells. The fresh band
  passes.

**P3 is still open: a board that is already stale when the session starts never reaches the
band.** This lives in `hooks/accounts-board.sh`, outside this round's files. Both aged reruns hit
it under load (~60-120): the session started after the board was 300 s old. The hook printed its
static stale message, and Claude Code re-wrapped it at 27 columns (`captures/r5-p3/`). The
captures show the scattered grid columns and `claude-accounts --re|adout` broken mid-word.

The fix is to hand a stale board to the band as well. The mod already draws stale heads.

### Method changes in round 5

- `summarize.py --r4 --prefix r5` judges a later round's runs.
- `NARROW_ROOM_FULL` now patches only a mod from before round 5, which kept the cue row free.

## Round 6: the full grid, every height × width × dataset (probe-2, 2026-10-22)

Run: `probe-r6.sh` (captures `r6-*`), judged by `summarize.py --r4 --prefix r6 --write`, which
writes `round6` into `verdict.json` beside the earlier rounds. The code under test is the worktree
at 09:24. Its hashes (`bin/claude-accounts` `6c32bf57…`, `ladder.ts` `a25c891e…`,
`register.tsx` `12be97e3…`) equal round 5's, so this round re-measures round 5's code. It also
covers the cells round 5 did not run: live × 70, fixture × 30, fixture × 70, and both readouts.

Setup:
- real Claude Code 2.1.293 in a pty;
- pane heights 30, 45 and 70; widths 80 40 34 30 27 22 20 17 16 15 13 12, then 80 again;
- `NARROW_STALE_S=86400`, so every band is fresh;
- the /accounts readout at 40 and 20 columns: live rows on a 45-row pane, fixture rows on a
  100-row pane, so the whole readout is on one screen.

Every capture was snapped to a PNG and judged by eye. The side-by-side sheets are in
`captures/r6-sheets/`.

### Verdict against the bar

- **Live rows, every width of 17+ columns on panes of 30+ rows: 26 of 27 cells pass.** The one
  failure is **17×30**, as in round 5. At 12 cells the dense form is 14 rows (picks, legend, then
  name / 5h / wk for each account) against a 10-row band. next4's values and all of next3 sit
  under `↓ 5 more` (`r6-sheets/live-rows30-b.png`, tile `band-07-17`).
- **Fixture rows, every width of 27+ columns on panes of 45+ rows: 12 of 12 pass.** The fixture
  also passes at 22×45, and at 20 and 22 on a 70-row pane. Only alerts sit below the fold.
- Across all 79 band frames:
  - no ellipsis;
  - Ink never re-wrapped a layout (every frame reproduces a ladder variant);
  - the input echoed at every width;
  - the band was gone after the first prompt in all seven runs;
  - the picks' targets were whole on the first screen in every frame (the new `picks_check`).
- The renderer's own `↩` mid-word breaks appear only for fixture rows at 15 columns and under:
  4, 8 and 11-12 rows, all in the 61-character name and the alert prose.

### Measured: first screen, per pane height × width (fresh board)

The cell format is the same as round 4, `✓|✗ <d|f><cells>/<lines> [↓N] [↩N]`:
- ✓ means the picks' targets, every account name, and all four values of every account are whole
  on the band's first screen.
- `↓N` is Claude Code's own fold cue.
- `↩N` counts the renderer's mid-word breaks in the whole band.

| data × pane rows (maxRows) | 80 | 40 | 34 | 30 | 27 | 22 | 20 | 17 | 16 | 15 | 13 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| live × 30 (10) | ✓ d29/7 | ✓ d29/7 | ✓ d29/7 | ✓ d24/8 | ✓ d22/8 | ✓ d17/10 | ✓ d15/10 | ✗ d12/14 ↓5 | ✗ d11/23 ↓14 | ✗ d9/25 ↓16 | ✗ d9/25 ↓16 | ✗ d7/25 ↓16 |
| live × 45 (17) | ✓ f72/15 | ✓ d29/7 | ✓ d29/7 | ✓ d24/8 | ✓ d22/8 | ✓ d17/10 | ✓ d15/10 | ✓ d12/14 | ✗ d11/23 ↓7 | ✗ d9/25 ↓9 | ✗ d9/25 ↓9 | ✗ d7/25 ↓9 |
| live × 70 (30) | ✓ f74/15 | ✓ f35/22 | ✓ f29/22 | ✓ f24/19 | ✓ f22/23 | ✓ f17/25 | ✓ f15/28 | ✓ d12/14 | ✓ d11/23 | ✓ d9/25 | ✓ d9/25 | ✓ d7/25 |
| fx × 30 (10) | ✗ d69/18 ↓9 | ✗ d34/25 ↓16 | ✗ d29/32 ↓23 | ✗ d25/35 ↓26 | ✗ d22/41 ↓32 | ✗ d17/48 ↓39 | ✗ d15/56 ↓47 | ✗ d12/84 ↓75 | ✗ d11/84 ↓75 | ✗ d10/91 ↓82 ↩4 | ✗ d8/101 ↓92 ↩8 | ✗ d7/106 ↓97 ↩11 |
| fx × 45 (17) | ✓ f75/28 ↓12 | ✓ d34/25 ↓9 | ✓ d29/32 ↓16 | ✓ d25/35 ↓19 | ✓ d22/41 ↓25 | ✓ d17/48 ↓32 | ✗ d15/56 ↓40 | ✗ d12/84 ↓68 | ✗ d11/84 ↓68 | ✗ d10/91 ↓75 ↩4 | ✗ d8/101 ↓85 ↩8 | ✗ d7/106 ↓90 ↩11 |
| fx × 70 (30) | ✓ f75/28 | ✓ d34/25 | ✓ f29/45 ↓16 | ✓ f25/47 ↓18 | ✓ f22/53 ↓24 | ✓ f17/62 ↓33 | ✓ f15/72 ↓43 | ✗ d12/84 ↓55 | ✗ d11/84 ↓55 | ✗ d10/91 ↓62 ↩4 | ✗ d8/101 ↓72 ↩8 | ✗ d7/106 ↓77 ↩12 |

Band rows used against `maxRows`: a band that fits uses its own line count and draws no cue. A
band that overflows shows `maxRows - 1` rows plus the cue: 9 + 1, 16 + 1, or 29 + 1. That matches
round 1's measured caps exactly. The full per-frame table, including the drawn variant, the head
rows and the readouts, is `python3 summarize.py --r4 --prefix r6`.

### Which window each value belongs to (judged by eye)

No value's window is ambiguous on any screen. Each form labels its values this way:
- **Dense table (29+ cells):** `5-hour ── weekly ──` over `used reset used reset`.
- **Cards (22-24 cells):** every row starts with `5h` or `wk`.
- **Column form (15-17 cells):** `used 5h wk` heads the percent columns, and each countdown sits
  straight under its percent.
- **Floor forms (7-12 cells):** each row is labeled `5h` or `wk`, with its reset on the row below.

Two weaker spots:
1. The cards at 30 columns carry the legend `used reset used reset`, one pair for each card. At
   34 columns the same text means 5h used/reset followed by weekly used/reset. The `5h`/`wk` row
   labels settle it, but the legend's meaning changes between two adjacent widths.
2. In the column form the reset row has no label of its own. The legend says only `used`. The
   values read as countdowns from their shape.

### The /accounts readout

| data | pane | rows | every name + value whole | ellipsis | `↩` |
|---|---|---|---|---|---|
| live | 40×45 | 23 | yes | 0 | 0 |
| live | 20×45 | 25 | yes | 0 | 0 |
| fx | 40×100 | 49 | yes | 0 | 0 |
| fx | 20×100 | 91 | yes | 0 | 0 |

`r6-sheets/readout-live45.png` and `readout-fx100.png`. At 20 columns the account rows drop the
`➤` and `➤ᵍ` pick marks. The picks rows above them still name every target, as in round 4. The
61-character name wraps at its hyphens without a mid-word break.

### What round 6 adds to the open list

1. **17×30 with live rows is the only bar cell still red, and the current form cannot pass it.**
   At 12 cells, `next2 16% 3h33m` is 15 cells, so each account needs 3 rows: 4 × 3 + picks +
   legend = 14 rows against 10.

   A candidate, not yet rendered or judged: a 2-row column form with the `%` moved into the
   legend (`   5h% wk%` / `next2 16  37` / `3h33m 2d20h`). That is 11 cells a row, and with picks
   and legend it comes to 10 rows. When both percents have three digits (`100 100`) it falls
   back to the 3-row form.
2. **Fixture rows at 80×30 lose next3 because the picks take 3 rows.** The dense 69-cell variant
   keeps desk, general and fable one per row even at 75 cells. Its `values` is 10, but an
   overflowing band shows only 9. On one row, `➤ desk → next2 · ➤ᵍ general → next · ➤ fable →
   none` is 51 cells and would bring `values` to 8, so all four accounts would fit on
   80×30. The mod's `room - 1` check is right; nothing in the ladder qualifies. This sits outside
   the bar (the fixture bar starts at 45 rows).
3. **The dense family shortens `general` to `gen` at 22 columns (17 cells).** The aligned picks
   column (`➤  desk    → next2`) is what costs the cell. The full family at the same width (on a
   70-row pane) spells out `➤ general → next`.
4. **The renderer breaks the fixture name mid-word at 15 columns (10 cells) where it doesn't
   have to.** It prints `quaternar↩` / `y-`, but `quaternary` is 10 cells and fits whole if the
   break comes before the `-`. At 13 and 12 columns the word is wider than the row, so the break
   is forced.
5. **Not re-tested: P3** (a board already stale at session start reaches only the static
   SessionStart message). Every round-6 run used a fresh board.

A probe artifact, not a band defect: one frame (12×70, live) shows the picks block twice. The
upper copy sits above the band's real top: rows left over from the 13-column frame, which pyte
does not reflow. The other 38 live frames have exactly one `[-]`. The same frame's `head 5` in
the summary table is that leftover.

### Method changes in round 6

- `summarize.py`:
  - `pick_targets` reads the targets of the widest variant's `➤ … → X` rows;
  - `picks_check` requires each target whole after a `→` or `use` on the first screen;
  - `--write` merges a `round<N>` key into `verdict.json` and leaves the other keys as they were.
- `probe-r6.sh` runs the seven arms in parallel, each with its own `NARROW_TAG` scratch (load was
  55-70).

## Round 7: every label said, the floor holds, a stale board reaches the band (fix3, 2026-10-22)

### What changed

The renderer (`bin/claude-accounts`):
- **Used and reset, said in every dense form, in one vocabulary.** The column form (15-21 cells on
  live rows) labels each reset row `reset`, in the name column, wherever the word and a space fit
  beside the countdown (17 cells up on live rows). Under that the key takes a second row, `reset`
  under `used`, and a `terse` sibling without it ships at the same width (below). The side-by-side
  cards carry ONE `used reset` legend at every width; one per card read `used reset used reset`,
  which the one-row table prints one column wider to mean the 5-hour pair, then the weekly one.
  The three-row and floor forms say `used`/`reset`, where they said `resets`. The full family keeps
  `resets`, the chat grid's word.
- **The terse sibling** (`"terse": true`, additive like `dense`). Where a dense layout spends rows on
  its labels, `pane_ladder` also ships the layout without them, right after it, only if it is
  shorter. On the band's own data (the board's ladder, no self mark) that happens at 15-16 cells
  only: 11 rows labelled, 10 terse.
- **The 7-cell floor holds for every value the renderer prints.** A percent too wide to sit beside
  its label (`≥99%*`, `100%*`: `5h ≥99%*` was 8 cells) goes under it, right-aligned on the same
  edge, one row more for that limit only.
- **`← you`, never a bare `←`.** The lanes take the first form that fits WITH `← you` when the session
  runs on the desk pick (`➤ use next2 ← you` at 17-24 cells, `➤ all lanes → next2 ← you` from 25);
  elsewhere the account's name says `← you` itself. The band never shows a self mark today (keepwarm
  deliberately skips `mark_self`, so the board's ladder has none); this is for `--readout --ladder`
  and any future band that has one.
- **Lanes.** Split lanes share ONE row where it fits (`➤ desk → next2 · ➤ᵍ general → next · ➤ fable →
  none`, 51 cells), which takes the fixture's account rows on an 80×30 pane from 10 (one past the
  cue) to 8. `general` stays a word wherever its one-row lane fits: an unaligned row is tried before
  the aligned `gen` (17 cells now reads `➤ᵍ general → next`). `gen` is left to 7-9 and 16 cells,
  where the whole word costs the lane a row.
- **A word a row holds is never cut.** A name part that fits the row but not with its hyphen breaks
  BEFORE the hyphen (`quaternary` / `-extremely` at 10 cells, where it printed `quaternar↩` / `y-`),
  in names and in prose. A name that fits the full row but not beside the mark gutter goes to the
  margin whole, without its mark (a 36-cell name at 36 cells, `アカウント一二三四五六` at 22).

The mod (`mods/accounts-readout/hooks/ladder.ts`): any labelled layout outranks any terse one
wherever it fits the height (or keeps its accounts above the cue), whatever their widths, since
the labelled layout for a width can be an earlier variant the ladder deduplicated into. The terse
one is drawn only where no labelled one fits, and wins on rows alone.

**The cue row, settled by measurement (C).** Round 4 measured that a tree of exactly `maxRows`
rows shows whole, and round 6 that an overflowing tree shows `maxRows - 1` rows plus the cue
(9 + 1, 16 + 1, 29 + 1). So the rule is two-sided and both sides stay: a layout fits when
`head + lines <= maxRows`; a layout that is cut keeps every account only when
`head + values <= maxRows - 1`. `bandLayout`'s own `room - 1` was untested; it is now pinned by a
test that fails on both mutants (`room` and `room - 2`).

The hook (`hooks/accounts-board.sh`, P3): a board at or past `CC_BOARD_STALE_S` and under
`CC_BOARD_HARD_S` now goes to the band like a fresh one. The mod labels it from the snapshot's
mtime with its own `⚠ STALE` head; the systemMessage keeps only the producer's launchd diagnosis,
which the band cannot know (`accounts board is stale: its producer … is RUNNING but …`). Hard,
empty, unreadable and missing boards keep their static text. The chat readout and the 76-cell
board are byte-identical to `origin/main` (five fixtures, clock and cache age masked).

### Measured

The dense family's rows per band width, live-shaped rows with no self mark (the band's own data),
from the ladder (`--readout --ladder`):

| band cells | 7-10 | 11 | 12-14 | 15-16 | 17-21 | 22-27 | 28+ |
|---|---|---|---|---|---|---|---|
| round 6 | 25 | 23 | 14 | 10 | 10 | 8 | 7 (from 29) |
| round 7, labelled | 25 | 23 | 14 | 11 | 10 | 8 | 7 |
| round 7, terse sibling | | | | 10 | | | |

The mod's own `bandLayout` over that ladder (`pred-r7.ts`, the probe's
`predict.ts` per pane), fresh board, `✓` when every account's values are on the first screen,
`d`/`t`/`f` = dense / terse / full, `cells/rows`:

| pane rows (maxRows) | 80 | 40 | 34 | 30 | 27 | 22 | 21 | 20 | 17 | 16 | 15 | 13 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| live × 30 (10) | ✓ d29/7 | ✓ d29/7 | ✓ d29/7 | ✓ d24/8 | ✓ d22/8 | ✓ d17/10 | ✓ t16/10 | ✓ t15/10 | ✗ d12/14 | ✗ d11/23 | ✗ d9/25 | ✗ d9/25 | ✗ d7/25 |
| live × 45 (17) | ✓ f72/15 | ✓ d29/7 | ✓ d29/7 | ✓ d24/8 | ✓ d22/8 | ✓ d17/10 | ✓ d16/11 | ✓ d15/11 | ✓ d12/14 | ✗ d11/23 | ✗ d9/25 | ✗ d9/25 | ✗ d7/25 |
| live × 70 (30) | ✓ f72/15 | ✓ f35/22 | ✓ f29/22 | ✓ f24/19 | ✓ f22/23 | ✓ f17/25 | ✓ f15/28 | ✓ f15/28 | ✓ d12/14 | ✓ d11/23 | ✓ d9/25 | ✓ d9/25 | ✓ d7/25 |
| fx × 30 (10) | ✓ d69/16 | ✗ d34/25 | ✗ d29/32 | ✗ d25/35 | ✗ d22/41 | ✗ d17/48 | ✗ d16/53 | ✗ t15/57 | ✗ d12/84 | ✗ d11/84 | ✗ d10/88 | ✗ d8/101 | ✗ d7/103 |
| fx × 45 (17) | ✓ d69/16 | ✓ d34/25 | ✓ d29/32 | ✓ d25/35 | ✓ d22/41 | ✓ d17/48 | ✗ d16/53 | ✗ t15/57 | ✗ d12/84 | ✗ d11/84 | ✗ d10/88 | ✗ d8/101 | ✗ d7/103 |

Against round 6: every live cell keeps its verdict (20×30 and 21×30 hold on the terse sibling, and
20-21 on a 45-row pane now draw the labelled form), and fixture 80×30 turns ✓ (the lanes on one
row). Every bar cell of round 6 still passes.

CORRECTED (2026-10-22, round 8): the `live × 30` ✓ at 20-22 columns held only while every lane
pointed at one account. The live fixture has every lane on next2. The operator's own board at
11:14 had `desk·fable → next2` and `general → next`, and on that board the same cells drew 13, 12
and 11 rows against 10, with next3 under the cue. Round 8 measures it and fixes it.

**Real Claude Code 2.1.293 in a pty** (`probe-r7.sh`, `captures/r7-*`; the probe's `provenance_sha256_16`
equals the files as they stand: `bin/claude-accounts` `245236fc…`, `ladder.ts` `ae8c542c…`,
`hooks/accounts-board.sh` `8262829d…`). Judged by each band's own rows and by eye, as rounds 4-6:
the probe's built-in per-account oracle predates the dense forms. A cell reads
`✓|✗ <d|t|f> <rows drawn> [cue]`:

| arm | 80 | 40 | 30 | 27 | 22 | 21 | 20 | 17 |
|---|---|---|---|---|---|---|---|---|
| live × 30 | ✓ d 7 | | ✓ d 8 | ✓ d 8 | ✓ d 10, `reset` rows | ✓ t 10 | ✓ t 10 | ✗ d 14, ↓ 5 more |
| live × 45 | ✓ f 15 | | | | ✓ d 10 | ✓ d 11, `used`/`reset` key | ✓ d 11, key | ✓ d 14 |
| fixture × 30 | ✓ d 16, lanes on one row, ↓ 7 (alerts only) | ✗ ↓ 16 | | ✗ ↓ 32 | | | | |
| live × 30, stale at start | ✓ hook's sentence + table | | | ✓ `⚠ stale` + cards, 10 | ✗ head + 10, ↓ 2 more | | | |

- The stale-at-start arm is P3 closed: the band draws the board under its own head (`⚠ stale 6s`
  / `live: claude-accounts` at 27 columns; the hook's full sentence at 80) and the SessionStart
  message carries only the producer's diagnosis, wrapped at words.
- 20-21 columns on a 30-row pane draw the terse sibling with all four accounts; the same widths
  on a 45-row pane draw the labelled form whole. 22 columns on 30 rows draw the labelled form, every
  reset row saying `reset`.
- Fixture rows at 80×30: every account's values above the cue, where round 6 lost next3.
- In every frame of every arm: no ellipsis, the prompt echoed typed input, and the band was gone
  after the first prompt.

### Known physical limits

- **17×30, live rows (12 cells): 14 rows against 10.** `next2 16% 3h33m` is 15 cells, so each
  account takes three rows. No layout of all 16 values fits. Picks first keeps the desk pick's
  values on the first screen.
- **The labelled column form at 15-16 cells is 11 rows.** `reset` and a space need 6 cells beside
  a 5-cell countdown and the row has 4-5, so the key takes a row. A 10-row band (20-21 columns on a
  30-row pane) draws the terse sibling, whose reset rows are labelled only by their shape and the
  `used` legend.
- **A stale head at 30 rows under 27 columns**: one row over (11 against 10). Picks first keeps the
  cut on an unpicked account.
- **Fixture rows at 30 rows under 80 columns**: alerts and the 61-character name take the rows.
- **The 7-cell floor with 5-cell percents** costs one row per such limit.
- **The stale band's static diagnosis** names the launchd label and the `kickstart` target, tokens
  wider than a 22-cell row; the hook never splits a token (broken, it would no longer paste), so
  Claude Code wraps those two at the edge.
- **A word bound to its arrow**: `→ next3@example.com` is 19 cells and a 17-cell row cuts it
  (`next3@exampl↩`): the arrow never ends a row, so the word cannot start one alone.

### Wording, chosen and why

- `used` and `reset`, singular, in every dense legend and label: `reset` fits over a 5-cell
  countdown, and one word at every width is the consistency G asked for. The full family keeps
  `resets`, the chat grid's word.
- `reset` sits in the name column of each reset row, in label grey, so a name never reads as a
  label; `used` heads that column on the legend row. Under 17 cells the two stack as a key.
- `← you` beside the desk pick (`➤ use next2 ← you`) wins over `➤ all lanes → next2` with a bare
  `←` below: saying whose session it is outranks saying all three lanes agree, which `use` implies.
- One `used reset` over the first card; the others align under it.
- A name continued after a whole word leads with its hyphen (`-extremely`), as plain a
  continuation mark as a trailing one, where the cut alternative was `quaternar↩`.
- The stale band's static line is `accounts board is stale: its producer …`: the band's head says
  how old; this says why.

### Method

- `probe-r7.sh` runs four arms (`captures/r7-*`): live × 30 and × 45 through 20-22 columns, fixture
  × 30 at 80, and a board stale at session start (`NARROW_STALE_S=1`).
- Offline, in `/tmp/narrow-fix3/`: `gen.sh` builds ladders over twelve fixtures plus a starred one
  (`≥99%*`, `100%*`, `—`, a `?` live count); `pred-r7.ts` (here) runs the mod's `bandLayout` per pane
  height and width; `compose.py` lays variants side by side for snap.py. Sheets judged, in
  `captures/r7-sheets/`: `sheetA.png` (column form, cards, table), `sheetB.png` (7-cell floor),
  `sheetE.png` (`← you`), `sheetF1.png`/`sheetF2.png` (lanes, names), `pty1.png` (two pty frames).
- Tests: the sweep's LADDER_CHECK requires `used` and `reset` in every labelled dense variant's
  account rows, a `reset` key wherever a reset row has no label, a terse sibling only where it saves
  a row, and no cut of a word a row holds; test 16 adds the starred fixture; test 12 caps the rows a
  band that tall draws, terse sibling included; the mod tests pin the cue term and the terse rank.

## Final round: the full grid on the round-7 code (probe3, 2026-10-22)

Run: `probe-final-p3.sh` (captures `fin-*`), judged by `summarize.py --r4 --prefix fin --write`.
That writes the `round_final_probe3` key into `verdict.json` beside the earlier rounds. The code
under test is the worktree as round 7 left it. In every arm, the probe's `provenance_sha256_16`
equals round 7's: `bin/claude-accounts` `245236fc…`, `ladder.ts` `ae8c542c…`,
`hooks/accounts-board.sh` `8262829d…`.

Setup:
- real Claude Code 2.1.293 in a pty;
- pane heights 30, 45 and 70; widths 80 40 34 30 27 22 20 17 15 13 12, then 80 again;
- live-shaped and fixture rows;
- a fresh board (`NARROW_STALE_S=86400`), and a board already stale at session start
  (`NARROW_STALE_S=1`): live × 30/45/70 and fixture × 45;
- the /accounts readout on live × 45 at 40 27 20 15 12.

That is 10 arms and 130 band frames, plus 5 readout frames. Every frame was snapped to a PNG; the
PNGs of every narrow and failing cell were read by eye.

### Verdict against the bar

- **Fresh board: the bar holds where round 7 said it would.**
  - Live rows, every width of 17+ columns on panes of 30+ rows: 26 of 27 cells pass. The one
    failure is 17×30, unchanged since round 5.
  - Fixture rows, 27+ columns on panes of 45+ rows: 12 of 12 pass.
  - The 20-column live cell on a 30-row pane draws the terse sibling (10 rows); on 45 rows it
    draws the labelled 11-row form.
- **Stale at start: the band now reaches the stale board in every arm (round 7's hook change), but
  the head costs a row the bar has no room for.**
  - Live × 30 fails at 22, 20 and 17 columns: next3 sits under `↓ 2 more`.
  - Fixture × 45 fails at 27 columns, a fixture-bar cell: next3's weekly row (`40% 99d+`) is under
    the cue.
  - Live × 45 and × 70 pass at every bar width.
- **In every one of the 130 band frames:**
  - no ellipsis;
  - no Ink re-wrap (each frame reproduces a ladder variant);
  - the prompt echoed typed input;
  - every pick target was whole after its `→` or `use`.
- **After the first prompt:** the band was gone in all 10 arms.
- **The readout (live × 45):** every name and value is whole at 40, 27, 20, 15 and 12 columns, with
  no ellipsis and no renderer break. It uses the full family's `used resets`.
- **The renderer's `↩` breaks:** only fixture rows at 15 columns and under show them (1, 8 and
  8-9 rows): the 61-character name and the alert prose. At 15 columns the one break is
  `Anthropic↩`; `Anthropic's` is 11 cells against a 10-cell row.

### Measured: first screen, per pane height × width

The cell format is `✓|✗ <d|t|f><cells>/<lines> [h<head rows>] [↓N]`:
- `d`/`t`/`f` is dense, terse or full.
- `✓` means the picks' targets, every account name, and all four values of every account are whole
  on the band's first screen.
- `*` marks a frame where pyte kept a leftover copy of the band top above the real one, so its
  head count is inflated. Five frames are affected; see the probe artifacts below.

| data × pane rows (maxRows) | 80 | 40 | 34 | 30 | 27 | 22 | 20 | 17 | 15 | 13 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| live × 30 (10) | ✓ d29/7 | ✓ d29/7 | ✓ d29/7 | ✓ d24/8 | ✓ d22/8 | ✓ d17/10 | ✓ t15/10 | ✗ d12/14 ↓ 5 | ✗ d9/25 ↓ 16 | ✗ d9/25 ↓ 16 | ✗ d7/25 ↓ 16 |
| live × 45 (17) | ✓ f72/15 | ✓ d29/7 | ✓ d29/7 | ✓ d24/8 | ✓ d22/8 | ✓ d17/10 | ✓ d15/11 | ✓ d12/14 | ✗ d9/25 ↓ 9 | ✗ d9/25 ↓ 9 | ✗ d7/25 ↓ 9 |
| live × 70 (30) | ✓ f72/15 | ✓ f35/22 | ✓ f29/22 | ✓ f24/19 | ✓ f22/23 | ✓ f17/25 | ✓ f15/28 | ✓ d12/14 | ✓ d9/25 | ✓ d9/25 | ✓ d7/25 h5* |
| fx × 30 (10) | ✓ d69/16 ↓ 7 | ✗ d34/25 ↓ 16 | ✗ d29/32 ↓ 23 | ✗ d25/35 ↓ 26 | ✗ d22/41 ↓ 32 | ✗ d17/48 ↓ 39 | ✗ t15/57 ↓ 48 | ✗ d12/84 ↓ 75 | ✗ d10/88 ↓ 79 | ✗ d8/101 ↓ 92 | ✗ d7/103 ↓ 94 |
| fx × 45 (17) | ✓ d69/16 | ✓ d34/25 ↓ 9 | ✓ d29/32 ↓ 16 | ✓ d25/35 ↓ 19 | ✓ d22/41 ↓ 25 | ✓ d17/48 ↓ 32 | ✗ t15/57 ↓ 41 | ✗ d12/84 ↓ 68 | ✗ d10/88 ↓ 72 | ✗ d8/101 ↓ 85 | ✗ d7/103 ↓ 87 |
| fx × 70 (30) | ✓ f75/28 | ✓ d34/25 | ✓ f29/45 ↓ 16 | ✓ f25/47 ↓ 18 | ✓ f22/53 ↓ 24 | ✓ f17/62 ↓ 33 | ✓ f15/72 ↓ 43 | ✗ d12/84 ↓ 55 | ✗ d10/88 ↓ 59 | ✗ d8/101 ↓ 72 | ✗ d7/103 ↓ 74 |
| live stale × 30 (10) | ✓ d29/7 h3 | ✓ d29/7 h3 | ✓ d29/7 h3* | ✓ d24/8 h2 | ✓ d22/8 h2 | ✗ d17/10 h1 ↓ 2 | ✗ t15/10 h1 ↓ 2 | ✗ d12/14 h1 ↓ 6 | ✗ d9/25 h1 ↓ 17 | ✗ d9/25 h2 ↓ 18 | ✗ d7/25 h2 ↓ 18 |
| live stale × 45 (17) | ✓ f72/15 h2 | ✓ d29/7 h4 | ✓ d29/7 h5 | ✓ d24/8 h6 | ✓ d22/8 h2 | ✓ d17/10 h3 | ✓ d15/11 h6* | ✓ d12/14 h3* | ✗ d9/25 h2 ↓ 11 | ✗ d9/25 h2 ↓ 11 | ✗ d7/25 h2 ↓ 11 |
| live stale × 70 (30) | ✓ f72/15 h3 | ✓ f35/22 h4 | ✓ f29/22 h5 | ✓ f24/19 h6 | ✓ f22/23 h2 | ✓ f17/25 h3 | ✓ f15/28 h1 | ✓ d12/14 h4 | ✓ d9/25 | ✓ d9/25 h5 | ✓ d7/25 h5* |
| fx stale × 45 (17) | ✓ d69/16 h1 | ✓ d34/25 h4 ↓ 13 | ✓ d29/32 h1 ↓ 17 | ✓ d25/35 h1 ↓ 20 | ✗ d22/41 h1 ↓ 26 | ✗ d17/48 h1 ↓ 33 | ✗ t15/57 h1 ↓ 42 | ✗ d12/84 h1 ↓ 69 | ✗ d10/88 h1 ↓ 73 | ✗ d8/101 h2 ↓ 87 | ✗ d7/103 h2 ↓ 89 |

Band rows used against `maxRows`: a band that fits draws its own line count (plus its head) with
no cue. A band that overflows shows `maxRows - 1` rows plus the cue: 9 + 1, 16 + 1 or 29 + 1,
as in rounds 1 and 6. The mod's own `bandLayout` (`pred-r7.ts` over `fin-*/board.ladder.json`,
age 10 s for a fresh board and 400 s for a stale one) predicts every ✓/✗ above, stale heads
included.

### What the final round finds (the open list)

1. **At 12-15 columns the picks take three rows, and that pushes the desk pick's own weekly reset
   under the fold on a 30-row pane.** It happens fresh and stale: `2d3h` is absent from the first
   screen at 15, 13 and 12 columns (`fin-live-rows30/band-08-15.png`, `band-10-12.png`).
   - The lane forms in `_dense_lanes` (`bin/claude-accounts`, the `forms` list near line 10514)
     stop at `➤ use next2` (11 cells), then fall back to `_lane_lines`
     (`➤ all` / `lanes` / `→ next2`).
   - `use next2` (9 cells) and `➤ next2` (7 cells) would hold the lane on one row at every width
     down to the 7-cell floor. That saves two rows, which brings all four of the desk pick's values
     onto the first screen at 12-15×30.
2. **The stale head costs a whole row, and that fails bar cells.** It fails live × 30 at 22, 20 and
   17 columns, and fixture × 45 at 27 columns (`fin-fx-rows45-stale/band-04-27.png`).
   - Round 7 lists the live case as a physical limit, but a shared row would fit. At 27 columns
     (22 cells), `⚠ stale 2m` (10 cells) fits on the legend row: that row's first 12 cells are
     blank, and the `[-]` mark lives in Claude Code's gutter, not in the band's cells.
   - At 22 columns (17 cells), `➤ use next2 ⚠ 47s` is exactly 17 cells.
3. **The SessionStart diagnosis above a stale band breaks mid-token at 30 columns and under**
   (`com.claude.a`/`ccounts-keepwarm`, `~/.claude/logs/accou`/`nts-keepwarm.out.log`). It is on
   the same first screen as the band (`fin-live-rows30-stale/band-05-22.png`, `band-04-27.png`).
   - The hook pre-wraps the message with a two-space hanging indent. Claude Code then re-wraps it,
     so the continuation lines land at uneven indents (`  (launchd) is`, `  refreshing the`).
   - Round 7 noted the split as a separate change. The goal ("nothing split mid-token") covers
     this screen.
4. **The terse sibling's reset rows carry no label at 15-16 cells, though a short one fits.** For
   example, `rst 3h33m  2d3h` and `rst 4h43m 2d20h` are each 15 cells (`fin-live-rows30/band-06-20.png`).
   - Round 7 says `reset` and a space need 6 cells beside the countdowns and the row has 4. That
     holds for the word, not for a label.
   - Whether a 3-cell label reads plainly enough is a wording call. If one does, the labelled form
     drops to 10 rows and the terse sibling is no longer needed.
5. **17×30 (live) is a physical limit only for the three-rows-an-account form.** Round 6's candidate,
   a two-row column form with the `%` in the legend (`   5h% wk%` / `next2 16  37` /
   `3h33m 2d20h`, 11 cells), comes to 10 rows. It is still neither rendered nor judged, and it
   raises the same labelling question as item 4.

Status after round 8 (below): items 1, 2 and 3 are fixed. Item 2 still fails for split lanes at
20-24 columns, where it is a measured physical limit. Items 4 and 5 are open.

Unchanged from round 7 and confirmed here:
- live 15-12 columns on 30 and 45 rows (25 rows of values);
- fixture rows under 80 columns on 30 rows, and under 22 columns on 45 rows;
- the readout's picks rows at 20 columns and under, which drop the `➤` marks but name every
  target.

### Probe artifacts (not band defects)

- **Startup.** Ten sessions started together all blocked for over 10 minutes in the same keychain
  read: a `sample` of one showed `SecItemCopyMatching` waiting on securityd, at load about 250 on
  10 cores. `probe-final-p3.sh` therefore starts each arm only after the previous one has drawn its
  first frame. The first start then took 420 s, and the later ones 20-280 s.
- **Leftover rows.** In 5 of 130 frames (the `*` cells), the band top appears twice: rows from the
  previous width that pyte does not reflow. Round 6 saw the same thing at 12×70. One stale frame,
  `fin-live-rows70-stale/band-08-15.png`, also shows residue on the head row (`⚠ stale.out[-]g`).
  None of this has been checked in a real terminal.
- **Readout stitching.** The stitched `readout-*-transcript-whole` files repeat the transcript;
  the single-screen readout PNGs are the ones judged.

### Gates (run during this round, same code)

- `bats tests/accounts-width-sweep.bats`: 1..18, 18 ok, 0 not ok.
- `bats tests/claude-accounts-core.bats`: 1..129, 129 ok, 0 not ok.
- `bats tests/accounts-board.bats`: 1..42. Two tests failed at load about 270: 19b and 19c, the
  wall-clock deadline tests (`took=19.0` and `took=10.5` against a bound of 10). Neither is touched
  by the diff, and both pass when re-run alone at load about 190 (1..2, 2 ok).
- `claude plugin validate .`: passed. `claude plugin test .`: 26 pass, 0 fail.

## Round 8: split lanes, the stale tag shares a row, whole words at the floor (fix3b, 2026-10-22)

This round fixes five review findings, all rated medium. Each fix has a test and a rendered check
(sheets in `captures/r8-sheets/`), and each was measured with round 7's `pred-r7.ts` over ladders
the worktree renderer wrote (full output in `captures/r8-sheets/pred-r8.txt`). The findings:

1. The operator's real board, with split lanes, lost an account at 20-26 columns on a 30-row pane.
   Round 7 had marked those cells ✓, measured on a fixture whose lanes all agree.
2. At the 7-cell floor the band's head split words: `account` / `s` and `withhel` / `d`.
3. At 12-15 columns the picks took three rows, which pushed the desk pick's weekly reset under the
   fold (final round, item 1).
4. A stale head on a row of its own failed bar cells (final round, item 2).
5. The SessionStart diagnosis above a stale band broke tokens mid-word and landed at uneven
   indents (final round, item 3).

### What changed

The renderer (`bin/claude-accounts`):
- **Split lanes take one row in the terse sibling.** On the real board (`desk·fable → next2`,
  `general → next`), the labelled lanes take 2-4 rows at 15-21 cells. The terse sibling now writes
  each group as its mark and its pick, `➤ next2 ➤ᵍ next`, and leaves the lane names to the marks:
  - the desk's group keeps the bare `➤`, which says every lane in it follows the desk;
  - any other group carries `➤` plus the superscript of each of its lanes, so `➤ᵍᶠ next` says
    fable goes with general, and `➤ᶠ none` says fable has no pick.

  A layout whose terse lanes are shorter ships the sibling (`costly`). The labelled layout keeps
  the words, and the band draws it wherever its height allows.
- **The terse lanes take the fewest rows, and then the narrowest form**: `➤ next2` rather than
  `➤ use next2`. This leaves room for the stale tag beside them (below).
- **Agreeing lanes stay on one row down to the floor.** Under 11 cells, `➤ next2` (7 cells) replaces
  `➤ all` / `lanes` / `→ next2`. I also tried `use next2` at 9-10 cells and judged it on screen: it
  was the one width band whose pick lost its `➤`, so I dropped it.
- **`lanes`** is a new additive ladder field on every dense variant: the display cells of each
  lane row. The band uses it to place its stale tag, so the mod never measures a name.
- **`← you` in a one-row lane form** now goes right after the desk pick, not at the row's end. The
  space-joined form needs this, and the old ` · ` form puts it in the same place as before.

The mod (`mods/accounts-readout/hooks/ladder.ts`):
- **The stale tag shares a row.** Where no head on its own row keeps every account above the
  cue, `⚠ stale 6m` (else `⚠ 6m`) joins a dense layout. It goes at the end of the first lane row
  with room for it. Failing that, and only for the full tag, it goes into the blank lead of the
  legend row under the lanes, two cells clear of its first word. A bare `⚠ 6m` in that position,
  judged on screen at 20 cells, read as one of the legend's labels. The merged candidate is ranked
  with the head forms and wins only on a better tier or a fuller layout. Where both tie, the head
  keeps its own row and its words.
- **No head cuts a word at the row edge.** A form whose wrap must cut a word is not offered.
  A break after a `-` (`claude-` / `accounts`) still counts as a word break. At 7 cells:
  - stale: `⚠ stale` / `6m`;
  - hard: a new form, `numbers` / `hidden` / `(2h` / `old)`, because `withheld` is 8 cells.

  If every form needed a cut, the shortest would still be kept, so a band never loses its head.
- **A terse layout ranks under every labelled one that keeps its accounts above the cue**, in
  `pickFit` and `bandLayout` alike. Round 7 states this rule, but `pickFit` ranked any layout that
  fit whole first. That did not matter until split lanes gave the fixture terse siblings at 29-40
  cells. A 70-row band at 34 columns then took a 30-row terse layout over the full one whose cut
  fell only in its alerts. It draws `f29/45` again.

The hook (`hooks/accounts-board.sh`), on the band path only:
- The stale diagnosis is now one unwrapped sentence, which Claude Code wraps at its words at
  whatever width the pane has by then. The sentence names the producer as "the keepwarm launchd
  job", and the command to run sits alone on the next line.
- fit() passes such lines through unwrapped (they are marked `FIT_RAW`, a US byte that emit()
  strips).
- The static path, used when no mod is running, keeps `producer_state`'s words byte for byte,
  including the hanging indent (test 29f checks it against the pre-band control).

### Measured

From `pred-r7.ts` over the new ladders. The cell format is the final round's, `✓|✗
<d|t|f><cells>/<lines> [h<head rows>]`. A cell marked `tag` drew no head row: the stale tag
shares a lane row or the legend.

| data × pane rows (maxRows) | 80 | 40 | 34 | 30 | 27 | 22 | 21 | 20 | 17 | 15 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| split × 30, round-7 code | ✓ d40/7 | ✓ d30/8 | ✓ d29/8 | ✓ d24/9 | ✓ d22/9 | ✗ d17/12 | ✗ t16/13 | ✗ t15/13 | ✗ d12/17 | ✗ d10/27 | ✗ d7/27 |
| split × 30, fresh | ✓ d40/7 | ✓ d30/8 | ✓ d29/8 | ✓ d24/9 | ✓ d22/9 | ✓ t17/10 | ✓ t16/10 | ✓ t15/10 | ✗ t12/15 | ✗ t8/24 | ✗ t7/24 |
| split × 30, stale | ✓ d40/10 h3 | ✓ d30/9 h1 | ✓ d29/10 h2 | ✓ d24/10 h1 | ✓ d22/10 h1 | ✗ t17/11 h1 | ✗ t16/11 h1 | ✗ t15/11 h1 | ✗ t12/15 | ✗ t8/25 h1 | ✗ t7/26 h2 |
| live × 30, stale (final round: 22 ✗, 20 ✗) | ✓ d29/10 h3 | ✓ d29/10 h3 | ✓ d29/9 h2 | ✓ d24/10 h2 | ✓ d22/10 h2 | ✓ d17/10 tag | ✓ t16/10 tag | ✓ t15/10 tag | ✗ d12/15 h1 | ✗ d8/24 h1 | ✗ d7/25 h2 |
| fixture × 45, stale (final round: 27 ✗) | ✓ d69/17 h1 | ✓ d34/29 h4 | ✓ d29/33 h1 | ✓ d25/36 h1 | ✓ d22/41 tag | ✗ d17/49 h1 | ✗ d16/54 h1 | ✗ t15/56 | ✗ t12/81 | ✗ t10/86 h1 | ✗ t7/102 h2 |
| fixture × 30, fresh (final round: 40 ✗) | ✓ d69/16 | ✓ t34/23 | ✗ t29/30 | ✗ t25/33 | ✗ d22/41 | ✗ d17/48 | ✗ d16/53 | ✗ t15/56 | ✗ t12/81 | ✗ t10/85 | ✗ t7/100 |

- **Split lanes, fresh:** 20-26 columns on a 30-row pane now fit 10 rows, every account whole. On
  45- and 70-row panes the labelled lanes keep their words: `d17/12` and `f17/25` at 22 columns.
- **Stale bar cells the final round failed now pass:** live × 30 at 22, 21 and 20 columns, and the
  fixture × 45 at 27 columns. At 22 columns (17 cells) the band draws `➤ use next2 ⚠ 6m`. At 21
  and 20 columns (terse) it draws `➤ next2 ⚠ 6m`. In the fixture at 27 columns, the legend row
  reads `⚠ stale 6m  used reset` and next3's weekly row is the last above the cue
  (`captures/r8-sheets/fx-r17-stale.png`).
- **The fixture on a 30-row pane at 40 columns** turns ✓. Its terse sibling's one lane row,
  `➤ next2 ➤ᵍ next ➤ᶠ none`, lifts every account above the cue; only the alerts are cut.
- **The floor, live × 30 at 12-15 columns:** the lanes take one row (`➤ next2`), and all four of the
  desk pick's values (`16%`, `3h35m`, `37%`, `2d3h`) sit above the cue in 23 rows. These cells stay
  ✗ because the other accounts are under the fold, but the picks now come first
  (`captures/r8-sheets/live-r10-floor.png`).
- **Every cell the final round passed still passes.** `pred-r8.txt` holds the full grid for split,
  live and fixture rows, at 30, 45 and 70 rows, fresh and stale.
- **The chat readout and the 76-cell board are byte-identical to `origin/main`.** That was checked
  on six fixtures (sweep, live, star, login, maxed and split), chat and narrow, with the clock masked.
- **The diagnosis** is the hook's real output from an 80-column start, re-wrapped the way the
  final-round capture shows Claude Code doing it: word wrap, an over-wide token cut at the edge,
  continuation rows unindented (`ccwrap-r8.py`). The sentence flows at its words with no stray
  indent. The only splits fall inside the log path or the `launchctl` command, each on its own line
  (`captures/r8-sheets/diag-modelled.png`). This part is modelled, not measured in a pty.

### Known physical limits (added)

- **Split lanes with a stale band at 20-24 columns on a 30-row pane (15-19 cells): 11 rows against
  10.**
  - The one-row lanes `➤ next2 ➤ᵍ next` take 15 cells, so neither tag fits beside them:
    `⚠ 6m` needs 5 more.
  - The column form's legend starts with `used` at the margin, so it has no blank lead.
  - Dropping `used` would fit the tag, but it would also drop the label the operator asked for.

  Picks first, so the cut falls on next3. From 25 columns (20 cells) the tag fits beside the lanes.
- **The fixture's stale head at 22 columns on a 45-row pane (17 cells)** has no room on any lane
  row (`➤ desk → next2` is 14 cells; `⚠ 6m` needs 5 more) and no blank lead. This is outside the
  fixture bar (27+ columns).
- **The diagnosis's longest tokens are 36-57 characters**: `gui/501/com.claude.accounts-keepwarm`,
  the 40-character log path, and the 57-character plist path. Claude Code still splits one when
  the pane is narrower than the token plus its 5-column gutter (41-62 columns). Each now sits on
  the command's own line, so the split never falls inside the sentence.

### Wording, chosen and why

- `➤ next2 ➤ᵍ next`: the lane names give way to the marks, which the grid's rows also carry
  wherever they have room (18+ cells). It reads as two picks. Fable's lane is implied by the rule
  "a lane with no mark of its own follows the desk", which is the grid's own de-dup rule. When
  fable follows general instead, the mark says `➤ᵍᶠ`.
- `⚠ 6m` appears only at the end of a lane row, right after a pick. In the legend's lead only
  `⚠ stale 6m` appears.
- `numbers hidden (2h old)` at 7 cells: `withheld` is 8 cells. The `run claude-accounts` hint is
  dropped there, because `accounts` cannot sit whole on a 7-cell row.
- "its producer, the keepwarm launchd job, …": the label `com.claude.accounts-keepwarm` is 28
  characters and broke inside the sentence at 30 columns. It still appears whole in the
  `launchctl` command line.

### Method

- Ladders came from the worktree renderer over the bats fixtures, plus a split-lane fixture built
  from the real board's 11:14 numbers. That fixture is now `SPLIT_FIXTURE` in the width sweep.
  Generated under `/tmp/narrow-fix3/fix3b/`.
- `pred-r7.ts` (unchanged) gives the band's verdict per pane. `sheet-r8.ts` lays the band's first
  screen (head, lines, cue at `maxRows`) side by side for snap.py. `ccwrap-r8.py` models Claude
  Code's re-wrap of a SessionStart message.
- Mutants, each run against the mod's tests in a fresh copy (all killed):
  - no cut filter on the heads;
  - the short tag allowed in the lead;
  - a merged layout ranked on the tag's width;
  - no merge at all;
  - round 7's `pickFit` rank;
  - round 7's `bandLayout` tier.
- Tests:
  - sweep 19 (split lanes: 15-21 cells within 10 rows, one terse lane row, `lanes` equals each lane
    row's cells, the labelled lanes keep their words);
  - sweep 20 (one lane row at 7-11 cells, the desk pick's values in the first 9 rows);
  - sweep 14 now accepts a pick led by its mark alone, but only inside a dense layout's lane rows;
  - board 29f (the band-path diagnosis in four launchd states, and the static path unchanged);
  - mod tests: 7-cell heads, the head loop from 7, the merge (lane end, legend lead, full-tag-only
    lead, ties keep their own row, colours kept), and the terse rank.
  - Sweep tests 19 and 20 fail on round 7's ladders for the reasons they pin: 13 rows, three lane
    rows, and `2d3h` below row 9.
- Not re-probed in a real Claude Code pty this round. Load stayed at 250-400 throughout, and the
  final round's starts took up to 420 s at that load. In the final round, the predictor matched
  every pty cell, stale heads included.

### Gates (on the final code, load 300-480)

- `bats tests/accounts-width-sweep.bats`: 1..20, 20 ok, 0 not ok.
  - An earlier filtered run of the round's first draft failed test 14. The terse lanes had no `→`,
    which is fixed above.
  - The same run also failed test 12, on the live fixture, in every width and every account at
    once. Replayed in isolation, the same commands pass, and the full run above passes it. The
    fixture's resets are relative to the clock (`_t(216)`), so a minute boundary crossed between
    the variants of one ladder shifts every countdown at once. That is an open flake, not this diff.
- `bats tests/accounts-board.bats`: 1..43, 43 ok, 0 not ok. A first run failed 29f on a leftover
  snapshot; the test now removes it, as 29d does.
- `bats tests/claude-accounts-core.bats`: 1..129, 129 ok, 0 not ok (after 39 deferrals for a slot).
- `claude plugin validate .`: passed. `claude plugin test .`: 29 pass, 0 fail.
- `shellcheck hooks/accounts-board.sh` (bare, as the land gate runs it): clean. `/bin/bash -n`
  (bash 3.2): clean. `producer_note` gives the same bytes under /bin/bash 3.2 and Homebrew bash 5
  in all four launchd states.
