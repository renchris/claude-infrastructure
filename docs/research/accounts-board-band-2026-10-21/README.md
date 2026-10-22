# The SessionStart accounts board as a band above the prompt (2026-10-21)

Scope (frozen): when `mods/accounts-readout` is loaded, the SessionStart accounts board (the grid +
routing picks + pace/drain + "Quota read live at" lines that `claude-accounts` renders into
/tmp/claude-accounts-board.txt) is drawn by the mod as an `AbovePrompt` band at FULL pane width,
re-laid out at every width change (wider and narrower, 40–200 columns, zero wrapped grid rows), and
removed when the operator submits the first prompt; hooks/accounts-board.sh then omits that static
grid from its systemMessage. Without the mod (CC_MODS=off, `claude -p`, sessions started before
converge) behavior is byte-identical to today. Operator chose this design on 2026-10-21 ("Band
until 1st prompt") over a collapsible band and over prose-only reflow.

Why: the board was static text hard-wrapped at the width the pane had at startup (operator
screenshot: a pane that started at ~50 columns and later measured ~115 still showed a ~45-cell board).
CC 2.1.293 has no render component for a SessionStart hook message, so that copy cannot be redrawn
in place, and `AbovePrompt` is the only site a mod owns at session start.

## Answer

Measured on CC 2.1.293 in a real pty over the width-sweep fixture rows: start at 50 columns, resize
to 160, then to 40, then through 200 · 60 · 180 · 80 · 140 · 100 · 120 · 45 · 40, then submit one
prompt (`board-probe.py`). Each cell is the widest intact grid row in cells / wrapped grid rows.

| arm | 50 (start) | 160 | 40 | 200 | 120 | 80 | 60 | 45 | after the prompt |
|---|---|---|---|---|---|---|---|---|---|
| trunk (static systemMessage) | 45 / 0 | **45** / 0 | 33 / **18** | 45 / 0 | 45 / 0 | 45 / 0 | 45 / 0 | 37 / **13** | still on screen (19 wrapped) |
| band (this change) | 45 / 0 | **125** / 0 | 33 / **0** | 125 / 0 | 115 / 0 | 71 / 0 | 54 / 0 | 38 / 0 | **gone** |

125 cells is the fixture grid's natural widest layout; past it the band does not stretch.
`captures/out-{trunk,band}/` hold every screen and `verdict.json` (trunk: `green: false` on all four
checks after the start; band: `green: true`, all five checks).

## Findings

1. **The handshake is ordered by the engine, and was measured before building on it.** A plugin
   hooks the settings hook events as `classic.<Event>`, and the chain is [managed settings hooks,
   hooks modules, the other settings hooks]. So the mod's `classic.SessionStart` hook runs BEFORE
   accounts-board.sh and its `next(e)` resolves AFTER it. In `order-probe/` (a scratch mod and a
   settings hook, pty, nothing typed) the mod's stamp went down at t=…454 ms, the hook saw
   `stamp=present` at …621 and the mod's `next(e)` returned at …742, with the same `session_id` on
   both sides (`mod-log.txt`, `hook-log.txt`). That is better than the brief's argv-walk candidate:
   it proves "this mod, in this process, for this start", not "a mod directory is on argv".
2. **`classic.SessionStart` carries `source`; `session.start` does not.** `session.start` fires once
   per process and never on `/clear`, so it could not mirror the hook. The classic event fires
   wherever the settings hook does (startup, resume, clear, fork, compact), so the band follows the
   hook's own rule: every source but `compact`.
3. **Who decides is the hook, so it can never be both and never neither.** The mod blanks
   `<sid>.board-band.json` and stamps `<sid>.board-band.req` with the session id, runs the settings
   hooks, then consumes both. The hook leaves the grid out only when the stamp names its session and
   is under 30 s old, the board is on the FRESH path, `<board>.ladder.json` carries the board's own
   mtime (±60 s, the rule the `.w<N>` variants already use), and the `cp -p` + `mv` of the ladder to
   the snapshot succeeded. A stale, hard, empty, unreadable or missing board keeps its labelled static
   text: an unlabelled stale board never reaches the band. The one residual: the hook omitted the grid
   and the mod then fails to parse a file the producer wrote with `json.dump`; nothing is drawn.
4. **A band never scrolls away, so it needs no survive-one-split budget** (the 2026-10-19 study,
   finding 4, applied only to transcript copies). It draws the widest layout whose widest line fits
   `e.props.bodyColumns` (the band's cells, less the engine's `[-]` mark), and `truncate-end` on each
   grid row is the guard below the narrowest layout.
5. **A band can sit for hours before the first prompt, so it applies the hook's staleness bands
   itself**: the board alone while fresh, the hook's `⚠ STALE by …` lines past `CC_BOARD_STALE_S`, and
   the numbers withheld past `CC_BOARD_HARD_S`, with the age read from the snapshot's mtime (the board's)
   and the label re-evaluated every 30 s.
6. **The deadline banner and the startup-health line stay in the systemMessage.** With neither
   present, the hook prints nothing at all (as it already does on `compact`); the dispatcher reads an
   empty child as `ok`.
7. **Cost.** The producer's ladder is `pane_ladder` (161 renders, 81 distinct layouts, ~400 KB on the
   fixture) inside each board write: ~2 s of a keepwarm tick at load ~130, measured. The mod is the one
   already loaded on all four accounts, so it costs no extra RSS.

## What was built

| part | where |
|---|---|
| `<board>.ladder.json`: `pane_ladder` over the board's rows, written atomically with the board's mtime under the board's wlock, by both producers (keepwarm and the local re-render) | `bin/claude-accounts` `_board_ladder`, `write_board(ladder=)` |
| the handoff: stamp + fresh board + same-pass ladder ⇒ snapshot for the mod and no grid; anything else ⇒ today's bytes; `CC_BOARD_BAND=off` kill switch | `hooks/accounts-board.sh` `band_handoff` |
| the band: `classic.SessionStart` stamp/consume, `AbovePrompt` draw (yields to a survey), cleared on `prompt.submit`; `board` in `$.state` | `mods/accounts-readout/hooks/{register.tsx,ladder.ts}`, `types/index.d.ts` |
| tests: the hook against itself with the band block cut out at source (byte-identical on every non-band path), the producer's ladder end to end; the mod's handshake, widths, prompt, compact, survey and staleness bands | `tests/accounts-board.bats` 19d, 28-29e; `mods/accounts-readout/tests/` |

Sessions already running when this converged keep the static board; nothing changes for them.

## Reproduce

```
bash docs/research/accounts-responsive-mod-2026-10-19/setup-probe.sh .     # the fixture rows + config
/tmp/abb-probe/venv/bin/python docs/research/accounts-board-band-2026-10-21/board-probe.py trunk /tmp/abb-probe/out-trunk
/tmp/abb-probe/venv/bin/python docs/research/accounts-board-band-2026-10-21/board-probe.py band /tmp/abb-probe/out-band
```

The venv is `uv venv /tmp/abb-probe/venv && uv pip install --python /tmp/abb-probe/venv/bin/python pyte`.
Each run starts one Haiku session with `--setting-sources project` and its own `--settings`, so no
fleet hook runs and no shared settings file is touched; no slash command is typed. The trunk arm
needs a pre-band `TRUNK_REF` once this has landed. `order-probe/probe.py` expects its mod and hook at
/tmp/abb-order/.
