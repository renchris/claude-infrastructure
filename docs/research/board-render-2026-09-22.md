# What a SessionStart `systemMessage` can actually render — measured, 2026-09-22

**Question.** The operator, looking at the startup accounts board: *"Is it possible to improve the
readability and formatting of our /accounts startup hook output such that it renders in the table?
its relatively unreadable currently."*

**Answer, in one line.** The channel was never monochrome. The harness paints the block flat #999
grey and **any SGR the payload carries survives and overrides it** — truecolor foreground, truecolor
background, bold, and box/block glyphs all render. Nothing had ever asked it for colour.

## Method

`docs/research/R5b-sessionstart-render-probe.py`, re-run against the LIVE binary
(`~/.claude-260/node_modules/.bin/claude`, CC 2.1.260) with an SGR-bearing payload instead of the
original plain-token one. A real `pty.fork()`, `TIOCSWINSZ` to a chosen geometry, the raw escape
stream captured to disk and read back byte-for-byte — not a screenshot, not a model's report of
what it saw.

Two traps cost a run each and are worth recording, because both produce a CLEAN NEGATIVE that
looks like a finding:

1. **The workspace-trust dialog blocks startup**, so the hook never fires and every token reads
   ABSENT. A fresh directory is untrusted; the probe must answer the dialog (Down, Enter).
2. **Matching the dialog's own text fails.** The TUI emits column-positioned output —
   `Yes,^[[9GI^[[11Gtrust^[[17Gthis^[[22Gfolder` — so the literal substring `trust this folder`
   never appears in the stream. Anchor on a single word that survives (`safety`).

Both are instances of the repo's standing lesson that a negative measured once is a claim about
the instrument until the instrument has a positive control.

## Findings

| # | Claim | Evidence in the capture |
|---|---|---|
| 1 | The harness paints the whole block **flat #999 grey**, NOT the dim attribute | every rendered row is preceded by `\x1b[38;2;153;153;153m`; no `\x1b[2m` anywhere |
| 2 | Payload **truecolor fg survives and overrides** it | `\x1b[38;2;235;122;90mZZCOLORZZ` present verbatim |
| 3 | Payload **bold survives** | `\x1b[1mZZBOLDZZ` present |
| 4 | Payload **truecolor background survives** | `48;2;40;44;52` present |
| 5 | **Box-drawing and block glyphs render** | `┌ ┬ ├ └ ▏▎▍▌▋▊▉█ ░▒▓ ▁▃▅▇` all present |
| 6 | Usable width is **pane − 5** | at an 80-col pane, a 74-cell row fits and an 80-cell row wraps; the continuation indent is `\r\x1b[5C` (5 columns) |
| 7 | **Line 1 alone** additionally carries the harness prefix `⎿ SessionStart:startup says: ` (~31 columns) | the prefix appears once, at the head of the first rendered row only |

Finding 6 vindicates the existing `NARROW_W = 76` budget at the 80-column floor and says it is
~19 columns conservative at the 100-column pane the operator actually runs. Finding 7 is the one
that had a live defect behind it: the old 46-character header line, plus a 31-column prefix, is 77
cells — it wrapped at an 80-column pane, and a wrapped line 1 costs the reader the AGE of every
number below it.

## What shipped on the back of this

`bin/claude-accounts` `readout_lines(narrow=True)`:

- its own palette (`bc()`, gated on `CC_BOARD_COLOR` / `NO_COLOR`, ON by default) — separate from
  `COLOR` because the board is written to a FILE by a launchd producer whose stdout is never a tty,
  so `_color_on()` is False in exactly the one caller that must emit colour;
- every cell padded as PLAIN text and coloured afterwards (`_cell`), since `f"{coloured:<8}"`
  counts escape bytes as columns;
- `_disp_w` made SGR-blind, or the wrap/clip budget would shred the rows it exists to protect;
- a weekly usage bar, a `strand` column fed by the same `wk_strand_pp` the prose block used, and
  the four-line drain block collapsed to one legend line plus any genuine `⚠` alarm;
- a short line 1, for finding 7.

Board length: **19 rows → 15**, zero width breaches, `tests/accounts-board.bats` 25/25.

## Re-derive

```
bash /tmp/board-probe/probe.py        # the SGR payload run (rebuild the hook stub from § Method)
python3 docs/research/R5b-sessionstart-render-probe.py <a trusted dir>
```

Re-measure on every CC version bump: all seven findings are properties of the harness's renderer,
not of the protocol, and #1 in particular is a colour constant somebody may change.
