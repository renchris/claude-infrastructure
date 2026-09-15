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

---

## H — the two ceilings that were never ceilings (2026-09-14, after C shipped)

C shipped and the operator refused it three more times, on the same two axes both times:
**"too small"** and **"still too subtle"**. Each round restyled inside a 45px cell and each round
lost, because both complaints were about limits that had been ASSUMED rather than measured.

### H1. A placement is sized in PIXELS. One cell was never the ceiling.

Every version through `8778b4ff6` rendered a strip exactly one cell tall, because row 1 is what the
placement anchors to. That is not what the protocol says and not what kitty does: an image occupies
`ceil(h / cell_h)` rows and is drawn at its full pixel height. Measured against the live terminal —
a 90px strip on a 45px cell rendered **90px**, ink-measured off the capture at rows 22..111.

This is the whole of the size complaint, and it is arithmetic rather than taste:

```
$ scripts/kitty-pane-title-overlay.py measure
cell            45 device px   band 90 px (2 cells)
BODY   Monaco   em 36   cap 28 px
TITLE  SF Semibold  em 58   cap 41 px   = 1.46x BODY   asc+desc 70 <= band 90
  CEILING at one cell: em 37 (the largest that fits 45px) -> cap 27 px = 0.96x BODY
```

**At one cell the best attainable header is 0.96x the body's cap height.** Not the shipped 0.86x —
the *ceiling*, at the largest em that fits, in any face. So no restyling inside a cell could ever
have produced a header, and three rounds were spent looking for one. The band is now `BAND_CELLS =
2` and the label is 1.46x the body. The cost is honest and bounded: while the toggle is up, two rows
are covered instead of one. Nothing moves — pane `lines` measured identical with titles on and off
across all 8 panes.

`measure` is a subcommand of the script itself, using the script's own renderer, so it cannot drift
from what is drawn; two bats tests assert the verdict and the one-cell ceiling, both mutation-checked.

### H2. SF Pro has no ✳ ◐ ◑ ✻ ✶ — and every pane title starts with one.

Read out of the real cmaps: those five are absent from `SFNS.ttf` and present in `Menlo.ttc`. PIL
does not raise on a missing glyph, it draws `.notdef` — a striped box — so this survived two
restyles and was only visible once a strip was rendered at 1:1 and looked at. **Neither of the two
obvious coverage tests works**: `getmask` returns ink for `.notdef`, and `getlength` returns an
ordinary advance. The test that does work needs no `fontTools`: render `U+E000` (private use, which
no font carries), keep its bitmap, and compare. Characters that match it are drawn from Menlo
instead, cap-height-matched and set on a shared baseline (`anchor="ls"`).

### H3. Vibrancy is a FOCUS budget, not a brightness knob.

Four idle candidates were rendered beside the live band before choosing. Seven loud bands say
nothing, so the chroma is spent on the one pane that is live: `#2f62d8` is kitty's own
`active_border_color` hue at full chroma, so the focused strip and the focused border are the same
blue. Idle is `#3f5590` — blue rather than grey, 2.30:1 over the ground, and it loses to the live
band on both brightness and saturation.

### H4. The 0.5s chord was startup, so the fix is a daemon — not a faster path.

Measured, per press: interpreter ~20ms, re-exec into a Pillow-capable python ~20ms, PIL import
~40ms, `kitty @ ls` ~30ms, the first `ps` ~95ms, then ~11ms of PIL per pane. **The tty write is
1.5ms for eight panes.** There was nothing to shave; the work was already free and the startup was
the whole bill.

So a daemon holds the pane list and the rendered strips warm, and the chord becomes a unix-socket
message plus that 1.5ms write. Measured on this machine:

| | before | after |
|---|---|---|
| client process, warm daemon | — | **p50 33.7 ms**, p90 36.3, max 38.4 (n=24) |
| end to end, stamped by the launched process | ~500 ms | **p50 46.7 ms**, max 63.5 (n=10) |

The end-to-end figure still includes a `/bin/sh` the real binding does not spawn, and excludes only
the 27.8ms `kitty @` remote-control CLI, which a keypress genuinely never pays (kitty's own internal
fork/exec measured ~3ms, as `launch background /usr/bin/true` minus `ls`).

Three design points are load-bearing:

* **No pidfile.** A dead daemon leaves its socket FILE behind and `connect()` to it fails instantly
  with `ECONNREFUSED`, so staleness is self-detecting. The alternative — validate a pid's start time
  with `ps` — costs 95ms, more than the entire budget it was meant to protect.
* **The refresh runs on its own thread.** Putting it on the accept loop only MOVES the cost:
  measured, one press in five landed mid-refresh and took **293ms** against 40ms for the rest.
* **The tty cache is keyed by `(pane_id, pid)` and pruned to the panes kitty just listed.** This
  code writes raw escape sequences into a device file and pids are reused within minutes; a stale
  mapping does not degrade, it paints into a stranger's terminal. A reused pid alone cannot re-mint
  a `(pane_id, pid)` pair, and pruning forces a returning pid to be re-resolved.

### H5. Method — the stale-frame trap fired again, and it fired on the SUCCESS this time

`screencapture -l <window>` on a window macOS is not compositing returns a **frozen frame and exit
0**. It cost two rounds earlier in this work; here it nearly produced a false *negative* — three
captures after an `off` showed the strips still up, byte-identical to the capture taken before it,
and the honest reading was "off is broken". They were the same frozen frame. A live capture taken
while kitty was genuinely frontmost showed **zero band pixels**.

**Never trust a single capture. Pair it with a liveness control** — two captures separated in time
that MUST differ (a spinner, a clock, a deliberate change) — and treat identical bytes as *no
information*, never as *no change*.

### H6. CORRECTION to H1: the height was the dial, and two cells overshot it

H1 above is right about the MECHANISM and wrong about the conclusion it drew. A placement
genuinely is sized in pixels and genuinely is not clipped to one cell — that measurement stands.
But "therefore make it two cells" was my inference, not the operator's ask, and shipped it drew
**"way too big"** on sight.

Rendering four points at 1:1 against real body text settles which dial was carrying the complaint:

| | band | type | cap vs body | verdict |
|---|---|---|---|---|
| A | 2 cells | em 58 | 1.46x | the slab dominates the pane |
| B | 2 cells | em 41 | 1.04x | **worse than either extreme** — text rattling inside a slab |
| C | 1 cell | em 36 | 0.89x | reads as a header, costs one row |
| D | 1 cell | em 32 | 0.82x | the version originally called "too small" |

**B is the finding.** If the complaint had been about type size, shrinking the type inside the tall
band would have improved it; it does the opposite. The band is what dominates, so the band is what
was wrong, and the shipped value is C: one cell, with the type at that cell's ceiling (em 36 against
a ceiling of 37 — one em of headroom).

**So size was never the free dial it looked like, and three rounds of "too small" were answered on
the wrong axis.** At one cell the type has a hard ceiling that sits just *under* body size (0.96x at
em 37), which means a one-cell header can never win on size and must win on REGISTER and COLOUR
instead — a proportional semibold against a monospace body, on a band that carries focus. That is
the rule; the numbers are downstream of it.

`measure` was rewritten to assert that rule rather than the old one. It no longer claims "LARGER
THAN BODY" — unreachable at one cell, and asserting an unreachable property is how a test starts
lying — it asserts that the em is AT the band's ceiling (nothing left on the table), that it fits,
and that the face is not the body's. Two bats tests pin it, both mutation-checked in both
directions: shrinking TYPE_RATIO below the ceiling and restoring BAND_CELLS to 2 each turn them red.

---

## I — 2026-09-15: the header grew a unit, and the gutter range in § H was a MODEL, not a reading

Three operator asks closed this session. Two of them corrected a figure that had already
landed, and in both cases the correction came from measuring the RENDER rather than
re-reading the derivation that produced it.

### I1 · The band and the type each went up a unit — and the suite had pinned the defect

The ask: *"one unit larger, the band and the text together, so the text doesn't look
oversized to its boundary container."* The second clause is the whole brief. § H had
pinned the type to the cell's **ink ceiling**, which put the accented worst case at 43px
inside a 45px band — ink-to-band **0.93**, one pixel of air on each edge. That is what
"oversized to its boundary container" is describing, and it was arrived at deliberately:
the previous round read a ceiling as a target. **A ceiling is where type stops being safe.
It is not where a header should sit.**

Seven candidates rendered at 1:1 over real Monaco body before choosing (the grid script is
in the session scratchpad; `measure` prints the same numbers from the shipped renderer):

| cand | band | em | ink (accented worst) | ink/band | cap vs body |
|---|---|---|---|---|---|
| 1:38 | 1 cell / 45px | 38 | 42px | **0.93** | 0.96x |
| 2:42 | 2 cells / 90px | 42 | 46px | 0.51 | 1.04x |
| **2:46** | **2 cells / 90px** | **46** | **51px** | **0.57** | **1.14x** |
| 2:50 | 2 cells / 90px | 50 | 57px | 0.63 | 1.29x |
| 2:58 | 2 cells / 90px | 58 | 66px | 0.73 | 1.46x — *"way too big"* |

Two cells is the only step that exists. A placement covers `ceil(h/cell)` rows, so a
fractional band leaves its last row half covered and clips the glyph tops of live content
under it. The refused extreme was never the band on its own — it was two cells **at em
58**, four steps above what shipped.

**Why this was not tried eight commits ago.** The comparison that sent the band back to
one cell was *"a two-cell band with SMALLER type"*. That finding is real and still holds —
the slab does dominate when the label is small inside it. A two-cell band with **modestly
larger** type was never in that comparison; it was excluded on my taste, and taste here is
the operator's. Recorded because the shape recurs: *a rendered A/B rules on the pair it
rendered, and the pair is chosen before the render.*

**The suite demanded the state the cure had to delete.** `measure` asserted
`headroom <= 1` and a bats case asserted `BAND_CELLS == 1`: between them they pinned
ink-to-band 0.93 as the contract, so the suite would have blocked its own fix. Both are
inverted **in place**, old reasoning kept — the clause is the record of what was believed.
What is pinned now is the proportion in **both** directions (the label must outrank the
body, and must not touch its band), because those are the two ways this has actually gone
wrong: three rounds in one direction, one in the other. Mutants: `TYPE_RATIO` back to
0.845 reddens the breathing case, `BAND_CELLS = 3` reddens the whole-cells case.

One side effect worth naming on its own: the label's inset was `band * 0.21`, which is the
same 9px at one cell and silently **18px** at two — a horizontal margin doubling because a
vertical dimension changed, walking the label out of alignment with the body under it. It
divides by `BAND_CELLS` first now. *A constant derived from one dimension will be applied
to the other by whoever changes that dimension next.*

### I2 · § H's "26-34px" was the model speaking, and the render says 28-42px

§ H predicted that horizontal padding 7 -> 5 would land the gutters *"at 26-34px across
every split count instead of 34-53px"*. That number came from the arithmetic
(`gutter = 2*padding + 2*border + LEFTOVER`), which is sound and reproduces kitty's own
column counts — but a model's output is not a reading. Measured from rendered PNGs at the
operator's real window width (3456 device px), every pane flooded with a solid block so a
gutter is the only place the block colour is absent:

| padding_h | N=2 | N=3 | N=4 | N=5 | N=6 | range |
|---|---|---|---|---|---|---|
| 3 | 34 | 31,28 | 31,32,36 | 31,32,27,18 | 31,32,27,19,20 | 18-36 |
| 4 | 34 | 31,28 | 31,32,36 | 31,32,38,40 | 31,32,38,30,20 | 20-40 |
| **5** | **34** | **31,28** | **31,32,36** | **31,32,38,40** | **31,32,38,41,42** | **28-42** |
| 6 | 34 | 31,28 | 31,32,36 | 31,32,38,40 | 31,32,38,41,42 | 28-42 |
| 7 *(was)* | 34 | 42,50 | 42,43,36 | 42,43,38,40 | 42,43,38,41,42 | 34-50 |
| 8 | 56 | 53,50 | 53,43,36 | 53,43,38,40 | 53,43,38,41,42 | 36-56 |
| 9 | 56 | 53,50 | 53,54,58 | 53,54,49,40 | 53,54,49,41,42 | 40-58 |
| 10 | 56 | 53,50 | 53,54,58 | 53,54,60,62 | 53,54,60,63,64 | 50-64 |

**5 is still the right value and the reasoning behind it still holds** — its overall range
(14px) is the tightest in the family, and it removes the step the operator actually
reported: at padding 7 the window goes 34px at two panes to 42/50px at three, a 16px jump
that is exactly *"two panes look right and three or more do not"*; at padding 5 it goes 34
to 31/28, a 6px settle. Confirmed on his own live windows, before and after: the
three-column window measured **54,54 -> 32,31**, and the second window **-> 45,46**.

**What is NOT true is "uniform".** At N=5 and N=6 the gutters still run 31,32,38,41,42 —
an 11px spread that no padding value removes, because the leftover is sub-cell waste paid
per column and shrinking the padding only re-accumulates it further along the row. The
whole family was swept to establish that rather than assumed: padding 3 has a *smaller*
worst-case gutter (36px) but a worse within-layout spread (an 18px gutter beside a 32px
one), and padding 7 has the tightest within-layout spread of all while carrying the 2-vs-3
step that prompted the report. There is no value that is best on both axes. **The honest
claim is a tighter band and no step, not uniformity.**

Two instrument notes, both of which produced a wrong answer first:

- **A probe window of the wrong width answers a different question.** The first sweep ran
  at 1400 logical px and reported padding 5, 6, 7 and 8 as *byte-distinct frames with
  identical gutters* — which is true at that width and says nothing about the operator's.
  The leftover term is a function of the window width, so a gutter measurement is only
  valid at the width it was taken at. The positive control that saved it: padding 40 moved
  the gutter to 168px, proving the config was applied and the instrument was sensitive,
  which is what turned "the fix does nothing" into "this window cannot see it".
- **Kitty's active-pane border is bright enough to count as ink.** The first analyser
  keyed on `sum(rgb) > 300`, which also matches `#6194f3`; the border sits *inside* the
  gutter, so every gutter beside the focused pane split into two ~10px runs and the pane
  count came out N+2. `min(r,g,b) > 180` separates a near-neutral block glyph from a
  saturated border. The tell was free and should have been read immediately: **the
  detected pane count did not equal the pane count kitty reported.**

### I3 · "now the titles are too large. is there no in between?" — there is, and I had conflated two numbers

§ I1 above shipped a two-cell band and was rejected within the hour. The reply that matters
is the question: *is there no in between?* § I1 says there is not, and gives the reason —
*"a placement covers `ceil(h/cell)` rows, so a fractional band leaves row 2 half covered and
clips the glyph tops of live content. Integer cells."* Every clause of that is true. The
conclusion does not follow, because the sentence is about **two different numbers wearing
one name**:

- **COVERAGE** — how many rows the placement spans. Quantised, genuinely: a placement
  shorter than its rows paints the *top* of the last row, which is exactly where that row's
  glyphs are, so live content under it reads as clipped.
- **THE BAND** — how much of that placement is painted the band colour. Nothing constrains
  this at all.

Cover two whole cells and paint the band for only the first `BAND_FILL_CELLS` of them,
filling the remainder with the terminal's own `background`. No row is part-painted, nothing
clips, and the covered-but-unbanded row reads as **a blank line under the header** — which
is what a header wants under it anyway. The band height is now continuous from one cell to
two, and the next move in either direction is a one-line change rather than another
architecture:

| band | em | ink (worst) | ink/band | air/side | cap vs body | |
|---|---|---|---|---|---|---|
| 45px | 38 | 42px | 0.93 | **1px** | 0.96x | *"oversized to its boundary container"* |
| 54px | 40 | 44px | 0.81 | 5px | 1.00x | |
| **58px** | **41** | **46px** | **0.79** | **6px** | **1.04x** | **is** |
| 62px | 42 | 46px | 0.74 | 8px | 1.04x | |
| 68px | 44 | 48px | 0.71 | 10px | 1.11x | |
| 90px | 46 | 51px | 0.57 | 19px | 1.14x | *"too large"* |

**The acceptance test moved twice, and the second move is the instructive one.** § I1
replaced a ceiling (`headroom <= 1`) with a **ratio** (`0.45 <= ink/band <= 0.68`). A ratio
cannot express the choice that is actually on the table: the *same* 0.79 is 6px of air at a
58px band and 19px at a 90px band, and the 90px band was rejected on sight. What the
operator named both times is **the gap** — "the text doesn't look oversized to its boundary
container" — so the gap in **device pixels** is what is asserted now (`air >= 4`, against
the 1px this shipped with). *When a rule keeps needing new constants, check that it is
measuring the quantity the complaint is about.*

And the suite had to be corrected a second time in three commits: the case that demanded
`BAND_CELLS` be a whole integer read that number as **the band's height**, which is what
made one cell and two the only two headers available. It now pins the pair — the placement
lands on whole cells, the band fits inside it, and the rows below the band are the ground
colour rather than band colour. Three mutants, each killing: `TYPE_RATIO` back to 0.845
(the reported crowding), the placement collapsed onto the band (a part-painted last row),
and the unbanded rows painted band colour instead of ground.

### I4 · The uneven gutters were never the padding — they are unequal COLUMNS, and ⌘⇧E already cures them

§ H diagnosed the wide gaps as sub-cell leftover and shipped `window_padding_width 10 7 ->
10 5` against it. § I2 corrected its predicted range and kept the diagnosis. Both are
wrong, and the instrument that produced them is the reason.

**The probe was building a geometry the operator does not have.** `launch
--location=vsplit` splits the CURRENT pane, so six launches give columns
**77,38,18,8,3,3** — a halving cascade — and every gutter figure in § I2 describes that.
Re-run with kitty's `horizontal` layout, which is what "N vertical splits" means on screen:

| padding | N=2 | N=3 | N=4 | N=5 | N=6 | spread |
|---|---|---|---|---|---|---|
| 10 7 | 32 | 32,32 | 32,32,32 | 32,32,32,32 | 32,32,32,32,32 | **0** |
| 10 5 | 24 | 24,24 | 24,24,24 | 24,24,24,24 | 24,24,24,24,24 | **0** |

**On equal columns the gutters were always uniform, at every split count, at either
padding.** Kitty absorbs the remainder by handing whole extra COLUMNS to panes
(50,50,52 · 29,29,29,29,33), not by leaving pixels in the gutter, which is what the
leftover model assumed.

Measured on the operator's own live windows with an exact ruler — the overlay's title
strips are solid blocks exactly one pane wide, so a band run IS a pane's content and a gap
IS a gutter, which is immune to the text-sparsity that made the first live reading
(54,54 -> 32,31) unreliable:

```
3 panes · content 1078,1078,1078 · GUTTERS 42,42 · spread 0 · margins 21/21
```

…and **identical at padding 7 and at padding 5**, one variable, frames verified distinct.
The 8 device px the change frees per pane is less than one 22px cell, so no pane gains a
column and the leftover absorbs all of it. **The landed padding change is a no-op on his
actual windows.** (It is kept: after equalising it gives 26px gutters against 32px, and one
more column per pane in some regimes. It is simply not the fix it was landed as.)

**Where the complaint does reproduce, and what actually cures it:**

```
cascade (repeated ⌘D)        columns 77,38,18,8,3,3   gutters 31,32,38,41,42   spread 11
layout_action equalize       columns 25,25,25,25,25,25 gutters 26,26,26,26,26   spread  0
```

`map cmd+shift+e layout_action equalize` has been in `config/kitty.conf` since before any
of this. The uneven gaps are unequal column widths, they are what repeated ⌘D produces by
construction, and ⌘⇧E removes them completely. Nothing needed building.

**Two levers swept and refuted along the way**, both at his real window width with a
distinctness control per arm: `placement_strategy top-left` moves each pane's leftover from
both sides to one and makes the cascade spread **worse** (14 against 11) — the render
agreeing with § H's arithmetic; `window_border_width 0` buys nothing to N=4 and is worse at
N=6 (18). `draw_minimal_borders yes` is a wash costing a pixel everywhere.

**The lesson is the one this file keeps relearning in a new costume.** A model that
reproduces a *correlated* observable — here kitty's column counts, 77/50/29, exactly — reads
as validated, and its actual prediction was never checked against a render. When it finally
was, the number was wrong (§ I2). When the *geometry* was finally checked, the mechanism was
wrong too. **Reproduce the user's own geometry before measuring anything in it**: the probe
and the operator's screen differed in the one axis that decides the answer, and nothing in
either reading announced that.

### I5 · The no-layout-shift invariant re-proved at two-cell coverage, and two residues

The band now sits inside a **two-cell** placement (§ I3), so the property the whole mechanism
exists for had to be re-measured rather than inherited from the one-cell era. Rows, columns
and pixel size read from each pane's own `TIOCGWINSZ`, across `off -> on -> off`:

```
pane   titles OFF             titles ON              OFF again
129    (44, 49, 1078, 1980)   (44, 49, 1078, 1980)   (44, 49, 1078, 1980)
265    (45, 49, 1078, 2025)   (45, 49, 1078, 2025)   (45, 49, 1078, 2025)
276    (22, 49, 1078,  990)   (22, 49, 1078,  990)   (22, 49, 1078,  990)
312    (22, 49, 1078,  990)   (22, 49, 1078,  990)   (22, 49, 1078,  990)
315    (44, 49, 1078, 1980)   (44, 49, 1078, 1980)   (44, 49, 1078, 1980)
341    (45, 49, 1078, 2025)   (45, 49, 1078, 2025)   (45, 49, 1078, 2025)
384    (44, 49, 1078, 1980)   (44, 49, 1078, 1980)   (44, 49, 1078, 1980)
```

7 of 7 identical. No PTY resize, no SIGWINCH, no row reserved — the placement paints above
the cell grid whether it is one cell tall or two, and covering a second row costs nothing
permanent because the strips are a toggle.

**Residue 1 — the daemon is running from a worktree, on purpose, and it expires.** The
`~/.claude/scripts/…` symlink points into the deploy checkout, which holds inside its
converge budget (lag 5 / 1h41m against 25 / 6h) and so still carries the one-cell band. The
daemon was restarted from the worktree copy so the operator could see the change the hour he
asked for it, with nothing hand-placed under `~/.claude` or `~/.config` — trap 2 forbids
that and the converger would revert it anyway. The failure mode to know: if that daemon
dies, the client respawns one from the DEPLOYED path and the band silently reverts to 45px
until the converger advances. It self-heals; it does not announce itself.

**Residue 2 — the padding is live via the runtime API, not a file.** `kitty @ set-spacing
--all --configured` applies to the running instance and to new windows, but not across a
kitty restart. `config/kitty.conf` on trunk already reads `10 5`, so a restart after the
converger advances lands in the same place. Per § I4 this is a no-op on his current windows
either way.

**One consideration for the open ⌘D decision** (`cc-decide acfef5ea0753`), recorded because
it is the argument against and it is easy to miss: the conf raises `window_drag_tolerance`
to 6 specifically so dividers are grabbable, i.e. deliberate manual resizing is a workflow
this setup was tuned for. Auto-equalising on every split would silently undo it. That is why
this is a 45% call and not an implementation.

### I6 · Closing (iii): within one window, equal columns give a uniform gutter at every N

§ I4 established the mechanism and cure. This closes the measurement, at **his** window
widths, in **his** layout, both paddings, every arm with a distinctness control.

**`horizontal` layout — equal columns by construction:**

| window | padding | N=2 | N=3 | N=4 | N=5 | N=6 |
|---|---|---|---|---|---|---|
| 3360 device | 10 7 | 32 | 32,32 | 32,32,32 | 32,32,32,32 | 32,32,32,32,32 |
| 3360 device | 10 5 | 24 | 24,24 | 24,24,24 | 24,24,24,24 | 24,24,24,24,24 |
| 3456 device | 10 7 | 32 | 32,32 | 32,32,32 | 32,32,32,32 | 32,32,32,32,32 |
| 3456 device | 10 5 | 24 | 24,24 | 24,24,24 | 24,24,24,24 | 24,24,24,24,24 |

Spread 0 in every row, and the *same value* across N: in this layout the gutter does not
depend on the split count at all, and padding 5 is a uniform 8px tighter than padding 7.

**`splits` layout — his — with `layout_action equalize` after each split:** spread 0 at
every split count as well, but the absolute width moves with N (42 · 48 · 34 · 32 at
padding 7). The two layouts differ in where the remainder goes: `horizontal` hands the
leftover cells to one pane as extra COLUMNS (49,49,51), `splits` leaves it distributed,
which is why his live 3-pane window reads 42px where the horizontal probe reads 24px at the
same width. Both are uniform; only `splits` pays for the remainder in gutter width.

**So the answer to "are the gutters uniform across 2..6 panes" is yes, conditional on one
thing, and the condition is the finding:** *equal columns*. Within any single window, once
the columns are equal, every gutter in it is the same width at every split count from two
to six, at either padding, at either of his window sizes. The uneven case is unequal
columns — what repeated ⌘D produces by construction — and ⌘⇧E removes it in one keystroke.
What remains is that the *absolute* width differs between split counts in the `splits`
layout (32-48px), which is sub-cell remainder and is only visible comparing two different
windows side by side, not within one.

**Instrument note, the third geometry error in this section and the same shape each time.**
Measuring `splits` instead of `horizontal` is not a detail: the two divide the remainder
differently and answer differently at the same width, by 18px. § I2 measured a cascade and
called it N splits; § I4 measured `horizontal` and called it his layout. **Each reading was
internally consistent, carried a liveness control, and described a window the operator does
not have.** A liveness control proves the instrument is *awake*; nothing in it proves the
instrument is pointed at the right thing.

### I7 · The drag: four aimed attempts, a passing control, and a specific reason it may still be untestable from here

The previous record left this as *"a synthetic CGEvent drag never did, in any layout, but
that instrument probably cannot start a macOS drag session — treat the negative as
untrusted."* That is a negative claim about a tool, which is the shape this corpus keeps
being wrong about, and the cause identified since (the ⌘⌥B binding had not reached the
running kitty, so **no bars were drawn** and every press landed on ordinary cell grid) is
now fixed. So it was re-run properly, in an ISOLATED instance so the operator's own panes
are never reordered, with the verdict read from `kitty @ ls` window ORDER — objective, no
screenshot, no liveness problem.

Two things had to be got right before the negative meant anything:

1. **Aim.** `hide_window_decorations` is not set, so macOS draws its own title bar at the
   top of the window and `WY + 14` presses *that*, dragging the OS window. The pane title
   bars are found by their exact configured colours (`#2f62d8` / `#3f5590`) in a capture and
   converted back to screen points — png row 88, scale 2x, screen y 96.
2. **A positive control**, in the same run, on the same binary: kitty resizes a split by
   dragging the BORDER between panes. If that works, synthetic drags reach kitty's drag
   handling and a title-bar negative is about the FEATURE; if it does not, the negative is
   about the INSTRUMENT and says nothing.

```
CONTROL  border drag      cols 41 41 41  ->  51 36 36          ← the instrument CAN drag
TEST     pane 3 body           60 steps  [1 2 3] -> [1 2 3]    no reorder
TEST     pane 3 title bar      60 steps  [1 2 3] -> [1 2 3]    no reorder
TEST     pane 2 title bar      60 steps  [1 2 3] -> [1 2 3]    no reorder
TEST     pane 2 title bar slow 400 steps [1 2 3] -> [1 2 3]    no reorder
```

**The control passes and all four variants fail** — distance, whether the drop lands on a
pane's body or on another title bar, and speed (a hand drag takes about a second; 60
synthetic steps take milliseconds, which could miss a drag threshold, so 400 was tried too).

**And there is a specific reason this may still not settle it.** The symbol set is AppKit
drag-and-drop, not plain mouse handling: `start_drag_with_data`, `on_drag_source_finished`,
`change_drag_thumbnail`, `GLFW_DRAG_OPERATION_MOVE/COPY/GENERIC`, alongside
`set_window_being_dragged` and `set_window_drag_overlay`. A border drag is GLFW mouse
motion and a CGEvent stream drives it fine; an **NSDraggingSession** is begun by AppKit from
a real event and a synthesised stream may be unable to start one at all. That is a
mechanism, not a shrug: it predicts exactly this result — control passes, feature does not —
and it is why a hand drag remains the decisive test.

What HAS been eliminated: the bars not being drawn, the binding not reaching the running
kitty, a mis-aimed press landing on macOS chrome, the drop target, the drag speed, and the
instrument being unable to drag at all.

**And if the drag turns out to be dead, nothing is lost** — the conf already binds every
reorder this feature would give, without a pointer: `cmd+shift+left/right/up/down`
(`move_window`), `cmd+opt+shift+<arrow>` (`move_to_screen_edge`, the only route for a pane
with no neighbour to swap with), `cmd+shift+r` (`rotate`), and `cmd+shift+o` /
`cmd+opt+o` (`detach_window`) for moving one to another tab or OS window.

### I8 · Upstream settles what the feature IS; the action was armed; the answer is unchanged

Two things were still unknown after § I7: whether kitty 0.48.2 even *has* drag-to-reorder
for windows inside a tab (the symbol set could equally have served tab dragging or
detaching), and whether making the bars visible by CONFIG is the same state as invoking the
action. Both are now answered, and neither rescues the synthetic test.

**Upstream documents the feature as exactly the operator's ask** — `toggle_window_title_bars`:

> *"Temporarily show window title bars to allow **drag-to-reorder**. When window title bars
> are hidden (because `window_title_bar_min_windows` is not met), this action forces them
> temporarily visible so that they can be dragged to reorder windows. After any drag
> operation completes, the bars are automatically hidden again. Press again to cancel before
> dragging. Map an action to this, then press it before dragging a window title bar."*

Introduced in **0.46.0**, alongside *"Allow dragging tabs in the tab bar to re-order, move to
another OS Window or detach"* and *"Allow dragging window borders to resize kitty windows in
all the different layouts, controlled by `window_drag_tolerance`"*. So ⌘⌥B is bound to the
right thing, the build has it, and the intended gesture is: **press once, then drag a title
bar — the bars hide themselves when the drag finishes.**

**The action is a MODE, and that was a real hypothesis, now tested.** § I7's probe made the
bars visible with `window_title_bar_min_windows 1` and never invoked the action; the doc's
wording ("forces them temporarily visible *so that they can be dragged*") allows that the
action arms something config alone does not. Re-run with `min_windows 0` and
`kitty @ action --self toggle_window_title_bars` before each attempt — the bars were
confirmed drawn by the same colour-keyed capture (png row 88), which is itself proof the
action fired:

```
CONTROL  border drag            cols 41 41 41 -> 51 36 36
TEST     pane 3 body, pane 3 title bar, pane 2 title bar, pane 2 title bar slow
         all four:  [1 2 3] -> [1 2 3]    no reorder
```

Identical to the unarmed run. **So the mode hypothesis is refuted and the AppKit one stands**:
a border drag is GLFW mouse motion and a CGEvent stream drives it; the reorder path is an
NSDraggingSession (`start_drag_with_data`, `on_drag_source_finished`,
`change_drag_thumbnail`, `GLFW_DRAG_OPERATION_MOVE`), which AppKit begins from a real event
and a synthesised stream appears unable to start.

**This is now a genuinely operator-only step, and the record says why**: every alternative
explanation has been eliminated by measurement — bars not drawn, binding not loaded, action
not armed, press landing on macOS chrome, wrong drop target, drag too fast, instrument
unable to drag at all — and the feature is documented to exist in this exact version. What
is left is one hand movement, and nothing on this machine can synthesise it.
