# A pane title that does not move the content — what is actually possible in kitty 0.48.2

**Operator goal (2026-09-14):** make `cmd+shift+b` show/hide a per-pane semantic header with **no
content layout shift** to the pane underneath. Explicitly disqualified as answers: "always on" and
"never on" title bars.

**Status: SOLVED — see § G. The six over-painting routes all fail; the answer was to move the row, not the paint.** Five mechanisms measured in isolated kitty
instances plus one lead-run lane. Nothing has been changed in the operator's config by this work.

## The defect, stated once

`map cmd+shift+b toggle_window_title_bars` costs exactly one text ROW in every pane of the tab.
A row change is a PTY resize, so kitty SIGWINCHes every child on the show **and** again on the
hide: one peek = two full scrollback reflows per pane. Upstream says the row is reserved by
construction — PR #9450, which introduced the feature: *"`_apply_window_title_bars()` **shrinks
each visible window's geometry by one cell height** to make room for the title bar."*

The reflow itself cannot be suppressed: a row-count change IS a PTY resize and kitty must signal
the child. **So the only solution shape that can work is one where the header is PAINTED OVER the
content rather than allocated beside it.** Everything below is judged on that.

## The five mechanisms

| # | Mechanism | Zero-reflow? | Paints above text? | Verdict |
|---|---|---|---|---|
| A | `window_logo` / `kitty @ set-window-logo` | **YES** (22 set/clear ops, 0 SIGWINCH) | **NO** — above the cell background, below glyphs | PARTLY |
| B | overlay window (`launch --type=overlay`) | **YES** (7 lifecycles, 0 SIGWINCH) | n/a — replaces the pane entirely | DEAD |
| C | graphics protocol, `z >= 0` | **YES** (200 cycles in 0.98s, 0 SIGWINCH) | **YES** — measured, not just spec'd | DEAD — see below |
| F | header painted into top PADDING | n/a | n/a | DEAD — logo anchors to the CELL area |
| D | external macOS overlay (Hammerspoon) | YES (never touches the grid) | YES | VIABLE, EXPENSIVE |
| E | any native kitty option | — | — | DEAD, none exists |

### A — window logo: right layout, wrong layer
Measured zero SIGWINCH and zero grid change across 22 alternating set/clear operations, with a
positive control (a real hsplit) firing in the same probe, so the instrument is not blind. A
1540x48 PNG at `--position top-left` lands **exactly** at the pane's own top-left origin, unscaled
and clipped rather than stretched, and `none` clears it completely. It survives a repainting `top`.
**But it composites BELOW the glyphs:** 8,595 glyph-bright pixels punched through a band laid over
`top`'s header row, and the first cell rendered as the cursor block. Crisp only over empty cells.
Two further limits: `--alpha` is **inert at runtime on 0.48.2** (1.0/0.75/0.5/0.25/0.0 all produced
identical pixels; only `-o window_logo_alpha=` at config level moved it), and there is no `--scale`
at runtime, so the PNG must be regenerated on resize.

### B — overlay window: zero-reflow and useless
7 overlay lifecycles produced 0 SIGWINCH and no grid change; the base stayed live underneath and
kept focus with `--dont-take-focus`. But an overlay is necessarily the base's **full** cell grid —
`--bias`, `--location`, `--spacing` and `resize-window` are all documented or measured no-ops for
overlays — and it is opaque: the base's text measured **0 visible pixels** under it. The
transparency salvage fails too, because `set-background-opacity` is per-OS-window, not per-window,
and at 0.35 the pane goes transparent to the **desktop**, not to the base.

### C — the graphics protocol: the only layer with the right z-order
The shipped protocol doc is explicit: *"**Negative** z-index values mean that the images will be
drawn **under** the text. This allows rendering of text on top of images."* So `z >= 0` paints
**above** the glyphs — precisely the property A lacks. Delivery is also solved in principle: each
pane's slave tty is addressable (`kitty @ ls` -> pid -> `ps -o tty=`), and writing an escape
sequence to it is indistinguishable from the child writing to stdout. A lead-run injection of a
3-chunk `a=T,f=100,z=1,C=1` placement into a live pane returned without error.
**What is NOT yet settled, and decides the whole question:** whether a placement survives a TUI
that repaints continuously, and whether it stays pinned to the top row when the pane scrolls —
kitty deletes placements whose anchoring cells are cleared or scrolled away. Measurement in flight.

### D — external overlay: works, but it is a window manager
Corrects an earlier lead claim that `geometry: null` kills this axis. **Per-pane pixel geometry IS
obtainable**, three independent ways: `kitty @ ls` carries `platform_window_id` (= the CGWindowID,
joined 4/4 against CoreGraphics) and `tab.layout_state.pairs` (the full splits tree with biases);
and — the clean one — **`TIOCGWINSZ` on each pane's tty yields exact pane pixel size and exact cell
size with zero assumed constants.** Verified by the lead on all three panes of one window:
`77x47 -> 1694x2115 px -> cell 22x45`. Hammerspoon is present, running and TCC-trusted; an
`hs.canvas` probe drew **above** native-fullscreen kitty, stole neither focus nor clicks. The cost
is the objection: kitty publishes no layout change events, so this is a ~500-LOC polling daemon
with four silent invalidation paths, and it does **not** track across Spaces — off-Space kitty
windows report identical bounds to the active one. That is an overlay window manager, not a title
bar.

### E — nothing native exists
`window_title_bar` accepts exactly `top|bottom` — read out of the frozen binary's own option table
as `typing.Literal['top', 'bottom']`. No `overlay`, no `float`, no `hidden`. The only knob
governing the row's existence is `window_title_bar_min_windows`. 0.48.2 is the newest upstream
release, so upgrading is not an available move. The renderer DOES own a non-reserving above-text
layer — the `hints` kitten and `select-window` both paint text over panes with no resize, and
`progress_bar`/`scrollbar_*` are non-reserving per-window edge paints — but none is exposed as a
persistent per-window text overlay. The upstream primitive that would make this a five-line change
is **issue #7450** (overlay windows with custom size/position while the covered window keeps
rendering); it is OPEN.

## The binding half, which is settled either way
Whatever draws the header, the chord must stop calling `toggle_window_title_bars`. kitty ships the
mechanism: `map cmd+shift+b launch --type=background --allow-remote-control <script>` runs a script
on the chord, creates **no window** — so the trigger itself can never cause a shift — and hands the
script a private remote-control socket via `KITTY_LISTEN_ON`.

## Method notes worth keeping
* **An occluded or off-Space macOS window FREEZES its backing store**, so `screencapture -l` returns
  a stale frame with no error and `--start-as=hidden` returns a blank one. This invalidated one
  lead conclusion mid-investigation (a "logo is invisible" reading that was really a stale capture)
  and cost two agents a first instrument. Pixel measurement requires the probe window to be briefly
  focused, with the frontmost app recorded and restored.
* `kitty @ action -m id:<N>` **ignores the match** and fires on the active OS window — measured:
  `-m id:338` toggled a different OS window entirely.
* `-o` overrides passed to `kitty @ load-config` are **sticky** and survive later bare reloads; they
  must be reverted with an explicit `-o`. `modify_font` additionally **accumulates** per target, so
  resetting `cell_height` does not clear `cell_width`.


## C, settled: the right layer, destroyed without notice

`z >= 0` really does paint above the glyphs — confirmed visually, not merely quoted: a `z=1,c=40,r=1`
placement hid columns 1-40 of row 1 while the same line's tail past column 40 stayed visible. Cost
is nil: 200 rapid place/delete cycles in 0.98 s produced **0 SIGWINCH**, with a layout split as the
positive control firing 1. Delivery works too — `kitty @ send-text` is NOT a paint route (it writes
to the program's stdin; a marker escape landed in a `cat` capture file and never on screen), but
writing the escape to the pane's slave tty from an unrelated process paints with 0 bytes reaching
stdin.

**It dies on INVALIDATION.** The placement survives continuous cursor-home repainting (~45 frames),
cursor movement and an alt-screen round trip — but `ESC[2J` deletes it, any scroll carries it out of
the viewport with the text, and `vim :redraw!` alone wiped it with nothing else happening. Worse,
`ESC[2J` frees the image DATA, so a cheap re-place fails with `ENOENT: Put command refers to
non-existent image`. And the ACK channel is unusable: with `q=0` the terminal's reply is delivered
into the program's stdin, so `q=2` is mandatory and you therefore get no error reporting either.

The TUI owns the screen buffer, destroys the header on any clear, frees the bytes, and tells nobody.
What is left is a blind timed re-transmission of the full PNG against a surface that may have
discarded it — a polling loop with no invalidation signal. That is the opposite of the clean
implementation the goal asks for.

## F, tested and dead: the header cannot hide in the padding

The one idea none of the five axes covered. If the top `window_padding_width` were one cell tall and
the strip were drawn INTO that band, no glyph could ever overprint it — A's only defect would be
gone, at the price of one permanently reserved row of PADDING (not a title bar, so the toggle still
works, which is what the operator actually objected to losing).

**Measured false.** An isolated instance with `window_padding_width 23 7 10 7` (top = 46 device px =
one cell) and a 1200x46 strip at `--position top-left`: the band rendered **over row 1**, with the
shell's own first line printed on top of it. `--position top-left` anchors to the **cell area**
origin, not the window origin, so padding does not move the logo out of the glyph zone. Dead.

## VERDICT

**There is no clean implementation in kitty 0.48.2.** Six mechanisms, each failing on exactly one
property:

* native title bar — reserves the row by construction (upstream PR #9450)
* overlay window — zero-reflow, but covers the pane entirely and is opaque
* window logo — zero-reflow and pixel-exact, but paints under the glyphs
* graphics protocol — zero-reflow AND above the glyphs, but destroyed by any clear, with the image
  data freed and no invalidation signal
* padding band — the logo anchors to the cell area, not the window
* external macOS overlay — works, and is a ~500-LOC polling daemon that cannot follow Spaces

The renderer demonstrably HAS a non-reserving above-text layer: `hints` and `select-window` both
paint text over panes with no resize, and `progress_bar`/`scrollbar_*` are non-reserving per-window
paints. None is exposed as a persistent per-window TEXT overlay, and the graphics protocol — the one
public door into that layer — is cell-anchored and therefore at the mercy of the program that owns
the cells.

**The single upstream lever is issue #7450** — overlay windows with custom size and position while
the covered window keeps rendering. If that lands, this becomes a `launch --type=overlay` one-row
strip and the whole problem is a five-line config change. It is open and unmerged; 0.48.2 is the
newest release, so there is nothing to upgrade to.

**What that leaves today:** the current setting (`window_title_bar_min_windows 0`, chord live) is the
correct one. It costs two reflows per peek and keeps the control, which is the trade the operator
already chose when always-on removed the chord.

## G — SOLVED: pay the row once in padding, and hand it back when the bar wants it

Every route in the table above tries to draw the header somewhere that costs no row. That is the
wrong axis. The bar needs exactly one cell height of pixels; the only question is WHERE it takes
them from. Keep that much permanently in the TOP padding, and when the bar appears swap the whole
config in ONE relayout to a variant whose top padding is exactly one cell smaller. The cell area
gains precisely the row the bar consumes: the row count never changes, the PTY is never resized, no
child is signalled, and the first text row lands on the same absolute pixel because the bar fills
exactly the band the padding vacated.

**MEASURED, all in ONE run** — the pairing is the point, because every earlier attempt had one half
or the other and the two had never been observed together:

    two-pane split, WINCH-trapping shells in both, Monaco 18, 45 px cell
      OFF   rows [7,7]   SIGWINCH 0/0
      ON    rows [7,7]   SIGWINCH 0/0   + a capture showing the title bar VISIBLE in BOTH panes
      cursor block bottom edge: 626 px (ON) vs 625 px (OFF) — the content does not move

On the live fleet, five consecutive toggles: rows and PTY pixel height IDENTICAL in every state
(win341 rows=46 ypx=2070 in both ON and OFF). No resize means no signal means no reflow.

**ATOMICITY IS THE TRICK.** Two remote commands (`action toggle_window_title_bars` then
`set-spacing`) are two relayouts and measured 16 -> 15 -> 16, i.e. TWO signals — worse than the
defect being fixed. One `load-config` of a complete file is one relayout and gives none. `-o`
overrides were tried first and do NOT reproduce it reliably, which is why the ON half is a real conf
file that `include`s the main config rather than a list of overrides.

**Shipped as:** `window_padding_width 32.5 7 10 7` in the main config (the reservoir — 32.5pt = 65
device px = one 45 px cell above the ordinary 10pt), `config/kitty-title-on.conf` as the ON half,
`scripts/kitty-pane-title-toggle.sh` as the swap, and `map cmd+shift+b launch --type=background` as
the chord — background, so the trigger creates no window and cannot shift anything either.

**COST:** one row per pane, permanently (47 -> 46). That is the reservoir. It buys a header that
genuinely appears and disappears, which is exactly what "always on" took away, and it satisfies the
constraint the other six routes could not.

**CAVEAT worth keeping:** the numbers are tied to the cell height. 32.5pt is one 45 px cell above
10pt; if `modify_font cell_height` ever changes, re-derive both paddings or the toggle silently
starts costing a row again. And per-tab `toggle_window_title_bars` state is sticky and survives a
config reload, so a window whose bar was toggled by hand can disagree with the config until kitty
restarts.

### The six routes that failed, kept because they bound the design space

Prompted by the goal evaluator correctly objecting that an impossibility verdict is not an
implementation, one more shape was tried — the only one that attacks the CAUSE rather than the
symptom. The bar needs exactly one cell height of pixels. Keep that much permanently in the TOP
padding, and when the bar appears, shrink the top padding by exactly one cell **in the same
relayout**. The cell area's row capacity rises by one at the instant the bar consumes one, so the
PTY never resizes, no child is signalled, and the first text row lands on the same absolute pixel
because the bar occupies precisely the band the padding vacated.

Atomicity is the whole trick and it is expressible: two remote commands (`action
toggle_window_title_bars` then `set-spacing`) are two relayouts and measured 16 -> 15 -> 16, i.e.
TWO signals — worse than the defect. A single `kitty @ load-config` carrying BOTH overrides is one
relayout. `scripts/kitty-pane-title-toggle.sh` implements it.

**It is not verified, and the honest reading is that it may be vacuous.** In an isolated instance
three on/off cycles held rows at 7x7 with 0 SIGWINCH in both panes of a split, and a fresh OS window
on the live config held 39 rows across OFF -> ON -> OFF with 0 SIGWINCH. But a capture of that fresh
window shows **no pane title bar drawn at all** — so "nothing moved" is equally explained by
"nothing happened". Meanwhile the one window where bars were definitely visible is the one whose
rows DID move. Every zero-SIGWINCH run is therefore unfalsified rather than confirmed.

**Two things must be settled before this can be claimed.** (1) A capture proving the bar is VISIBLE
in the same run in which rows stay constant — the two facts have never been observed together.
(2) Whether `window_title_bar_min_windows` is even a reliable lever on a live fleet: per-tab
`toggle_window_title_bars` state is sticky, `kitty @ action -m` fires on the wrong OS window, and a
config reload does not clear it, so the operator's windows currently disagree with each other. Some
of that pollution is mine, from probing; a kitty restart clears it, which is why this was NOT left
wired up.

**Live config is therefore REVERTED to the known-good state** (`window_padding_width 10 7`,
`map cmd+shift+b toggle_window_title_bars`). The script is committed unwired, with its derivation,
so the next session can finish the two checks above rather than re-derive the idea.
