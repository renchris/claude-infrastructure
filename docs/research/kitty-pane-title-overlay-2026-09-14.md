# A pane title that does not move the content — what is actually possible in kitty 0.48.2

**Operator goal (2026-09-14):** make `cmd+shift+b` show/hide a per-pane semantic header with **no
content layout shift** to the pane underneath. Explicitly disqualified as answers: "always on" and
"never on" title bars.

**Status: INVESTIGATION, one axis still open.** Five mechanisms measured in isolated kitty
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
| C | graphics protocol, `z >= 0` | expected yes | **YES, by spec** | **OPEN — the linchpin** |
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
