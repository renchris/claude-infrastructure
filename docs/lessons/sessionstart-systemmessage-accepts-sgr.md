# A SessionStart `systemMessage` accepts your colour — the flat grey is the harness's, not the channel's

**The rule.** A hook's top-level `systemMessage` is rendered by Claude Code inside a flat #999 grey
(`\x1b[38;2;153;153;153m`, *not* the dim attribute), and **any SGR the payload carries survives and
overrides it** — truecolor foreground, truecolor background, bold, and box/block glyphs all render.
So a startup banner that reads as an undifferentiated wall is a banner nobody ever coloured, never a
monochrome channel. Before accepting a surface's appearance as its limit, emit one probe payload
through it and read the bytes back.

## How this was missed for six weeks

`hooks/accounts-board.sh` shipped 2026-08-11 with a long, careful header comment about the CHANNEL
— which key renders, which is silently ignored, which bills tokens — all of it measured, all of it
correct. It says nothing about SGR, because the question was never asked: the probe that established
the channel used plain ASCII tokens (`ZZTOPLEVELZZ`), so it could only ever answer *does text
arrive*. The board then rendered eighteen rows of numbers, labels, prose and alarms at one single
weight until the operator said "relatively unreadable".

**The shape:** a probe answers the question it was built for and is then read as having
characterised the surface. Its silence on every other axis is not a finding.

## The measurements (CC 2.1.260, real pty, raw stream read back)

| # | Claim | Evidence |
|---|---|---|
| 1 | harness paints the block **flat #999**, not dim | `\x1b[38;2;153;153;153m` heads every row; no `\x1b[2m` |
| 2 | payload truecolor fg survives and overrides | `\x1b[38;2;235;122;90m` present verbatim |
| 3 | bold survives | `\x1b[1m` present |
| 4 | truecolor **background** survives | `48;2;40;44;52` present |
| 5 | box-drawing + block glyphs render | `┌ ┬ ├ └ ▏▎▍▌▋▊▉█ ░▒▓ ▁▃▅▇` |
| 6 | usable width = **pane − 5** | at 80 cols a 74-cell row fits, 80 wraps; indent is `\r\x1b[5C` |
| 7 | **line 1 only** also carries `⎿ SessionStart:startup says: ` (~31 cols) | the prefix appears once |

Finding 7 had a live defect behind it: a 46-character header plus a 31-column prefix is 77 cells, so
the board's own first line — the one carrying the AGE of every number below it — wrapped at an
80-column pane.

## Two traps in probing a TUI, both of which produce a clean false negative

1. **The workspace-trust dialog blocks startup**, so the hook never fires and every token reads
   ABSENT. A fresh directory is untrusted.
2. **Matching the dialog's own words fails.** The TUI emits column-positioned output —
   `Yes,^[[9GI^[[11Gtrust^[[17Gthis^[[22Gfolder` — so the literal `trust this folder` never appears
   in the stream. Anchor on one word that survives (`safety`).

Both cost a full run, and both return the same clean ABSENT a real negative would. This is
[[a-negative-measured-once-is-a-claim-about-the-instrument]] in its TUI form: a probe against a
terminal needs a positive control before its silence means anything.

## What it implies for any coloured payload

- **Pad as PLAIN text, then colour.** `f"{coloured:<8}"` counts escape bytes as columns, pads to
  nothing, and collapses every column to its right — while a width check only ever gets SHORTER and
  a colour-off run stays byte-identical to a correct one. Nothing else sees it.
- **Any display-width helper must strip SGR**, or the wrap/clip budget shreds the rows it protects.
- **Gate colour separately from a tty check.** A board written to a FILE by a launchd producer has
  no tty, so an `isatty()` gate is False in exactly the one caller that must emit colour.
- **Keep a kill switch.** The one failure worse than flat grey is a harness that starts ESCAPING
  the sequences instead of rendering them.

Record: `docs/research/board-render-2026-09-22.md`. Shipped in `75246cbf6`.
Re-measure on every CC version bump — all seven findings are properties of the renderer.
