# The Claude Code mascot, extracted from the shipping binary

Reference material for `docs/plans/README_HERO_BANNER.md` rejection **R4** — *"the Claude Code
orange mascot character"*, meaning the pixel-art creature rendered at session start, **not** the
radiating asterisk `✻ ✽ ✳`.

The creature is not a description to approximate. It ships as literal data inside the Claude Code
binary, and this is that data, read out rather than redrawn from memory.

**Source:** `~/.claude-219/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (v2.1.219,
build `7006c4c3`, 2026-07-24). The JS bundle is plaintext inside the executable; the art is stored
as `\uXXXX` escapes, which is why a byte-grep for block characters (`\xe2\x96…`) returns **zero
hits** and reads as "the art isn't in here". Grep the escapes, not the glyphs.

## Its name and its colour

```js
clawd_body:       "rgb(215,119,87)"   // #D77757
clawd_background: "rgb(0,0,0)"
```

The mascot is called **clawd** internally. `#D77757` is the exact body orange — note it is *not*
the `orange_FOR_SUBAGENTS_ONLY` swatch `rgb(217,119,87)` sitting two keys away in the same table,
and not the `#D97757` that a search will also surface. Use `#D77757`.

## The session-start creature (11 × 4 cells)

Drawn `color: clawd_body` throughout, except row 2, which additionally carries
`backgroundColor: clawd_background` — that is what makes the two `▄` read as **eyes**: the glyph
fills the lower half with orange and leaves the upper half black.

```text
 █████████
██▄█████▄██
 █████████
 █ █   █ █
```

Row 4 (the legs) is emitted at a **+1 column offset** from the body block, so the legs sit under
body columns 1, 3, 7, 9.

Because `▄` is a half-block, the true resolution is **11 × 8 square pixels**, not 11 × 4:

```text
x:     0 1 2 3 4 5 6 7 8 9 10
y=0      █ █ █ █ █ █ █ █ █
y=1      █ █ █ █ █ █ █ █ █
y=2    █ █ · █ █ █ █ █ · █ █     ← · = eye (background shows through)
y=3    █ █ █ █ █ █ █ █ █ █ █
y=4      █ █ █ █ █ █ █ █ █
y=5      █ █ █ █ █ █ █ █ █
y=6      █   █       █   █
y=7      █   █       █   █
```

That 11 × 8 grid is the authoritative geometry for any vector reproduction.

## The full session-start scene

The creature does not appear alone — it stands in a landscape, on a dotted ground line, under soft
`░` hills, beside `▒` vegetation. Reconstructed in row order from the bundle:

```text
..........................................................

            ░░░░░░
    ░░░   ░░░░░░░░░░
   ░░░░░░░░░░░░░░░░░░░

                           ░░░░                     ██
                         ░░░░░░░░░░               ██▒▒██
                                            ▒▒      ██   ▒
       █████████                          ▒▒░░▒▒      ▒ ▒▒
      ██▄█████▄██                           ▒▒         ▒▒
       █████████                           ░          ▒
.......█ █   █ █..........................░..........▒....
```

The `░` rows render `dimColor`; the `█▒` rows are default-coloured; only the creature is orange.
A second, **night** variant exists in the same bundle — `*` stars, a `░▓▓███▓▓░` tree canopy over a
`███▓░` trunk — so the scene is themed, not fixed.

**The aesthetic to honour is here, not invented:** one saturated orange subject, everything else
dim monochrome texture, a hard dotted horizon, and a lot of empty space.

## The idle poses — an authentic motion vocabulary

A second, smaller clawd (used in-session, not at startup) ships with a **pose table**. This matters
for the banner: the creature's idle motion does not have to be invented, it can be quoted.

```js
Sdf = {
  "default":    { r1L:" ▐", r1E:"▛███▜", r1R:"▌", r2L:"▝▜", r2R:"▛▘" },
  "look-left":  { r1L:" ▐", r1E:"▟███▟", r1R:"▌", r2L:"▝▜", r2R:"▛▘" },
  "look-right": { r1L:" ▐", r1E:"▙███▙", r1R:"▌", r2L:"▝▜", r2R:"▛▘" },
  "arms-up":    { r1L:"▗▟", r1E:"▛███▜", r1R:"▙▖", r2L:" ▜", r2R:"▛ " },
}
Tdf = {  // the feet row
  "default":" ▗   ▖ ", "look-left":" ▘   ▘ ", "look-right":" ▝   ▝ ", "arms-up":" ▗   ▖ ",
}
```

Four poses: **default · look-left · look-right · arms-up**, with the feet shifting under each. The
eye segment is the only part that changes between the three looking poses — the body never moves.
`arms-up` is the one whole-body pose.

## Method note

Byte-grepping a 257 MB compiled binary for the glyphs finds nothing and looks conclusive. Two
things make it work:

1. `strings -a` the executable once into a scratch file (0.6 s, 38 MB) and search *that* — the
   bundle is plaintext, just not line-oriented.
2. Search for the **escape form** (`█`), then `.encode().decode('unicode_escape')` to render.

An all-negative sweep on art that demonstrably ships is a broken harness, not a finding.
