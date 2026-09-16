#!/usr/bin/env bats
# kitty-title-zero-shift — the ⌘⇧B title-bar pair that neither shifts content nor loses a row.
#
# WHAT THIS GUARDS, and why a grep is not enough. The feature is an ARITHMETIC IDENTITY spread
# across three files, and every term of it is a number somebody could reasonably "tidy":
#
#   kitty.conf          window_padding_width  22.5 5 0 5   <- one cell of TOP reservoir
#   kitty-title-on.conf window_padding_width  0 5 0 5      <- hands exactly that cell to the bar
#                       window_title_bar_min_windows 1     <- and holds the bars up by CONFIG
#
# The identity is: top_OFF - top_ON == one cell, and bottom_OFF == bottom_ON. The first keeps the
# ROW COUNT constant (no PTY resize, no SIGWINCH, no reflow); the second keeps the grid's top edge
# on the same PIXEL. Break either and nothing errors — the shift simply comes back. That silence
# is the whole reason this suite exists.
#
# 🚨 THE RESERVOIR IS A FUNCTION OF THE FONT. 22.5pt is `font_size 18` x `modify_font cell_height
# 94%` = a 45px cell at 2x. It must EQUAL the cell in pixels, not merely exceed it: 23pt rounds to
# 46px and leaves a measured 1px creep in the content on every toggle. So this suite pins the
# TRIPLE — font size, cell-height percentage, reservoir — as one unit. It deliberately does not
# re-derive 22.5 from font metrics (that needs a live window); it detects DRIFT, which is the
# failure that actually happens. If you change the font, re-measure and update all three here.
#
# Measurements behind the numbers (isolated kitty 0.48.2, 2-pane split, WINCH-trapping children):
#   TODAY `10 5` 30,30 · OFF `22.5 5 0 5` 30,30 · ON `0 5 0 5`+mw1 30,30 over 6 swaps, SIGWINCH 0
#   control: a forced row change gives 27,27 and moves the counter 1 -> 2, so the zero is real
#   pixels: content row 1 at y 465..644 in BOTH states; only changed band y 420..464 = 45px
#   no-op drag: today 29,29 -> 30,30 (title vanishes) · this pair 30,30 -> 30,30 x3 (stays up)

setup() {
  # Fixture $HOME. The subject defaults its state file to $HOME/.claude/autonomy/kitty-title-state
  # and mkdir -p's that directory, so an inherited $HOME would have this suite writing into the
  # operator's live autonomy store — and case 9 invokes the script for real.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  OFF="$REPO/config/kitty.conf"
  ON="$REPO/config/kitty-title-on.conf"
  TOGGLE="$REPO/scripts/kitty-pane-title-toggle.sh"
  # Kept though a49280bd9 removed the reservoir: case 4 still pins the FONT that derived it,
  # because font_size 18.0 x cell_height 94% = 22.5pt is what any future one-cell band must use.
  RESERVOIR_PT="22.5"   # one cell, at font_size 18 x cell_height 94%
}

# value of the LAST occurrence of a directive — kitty takes the last one, so a grep that reads the
# first would pass over a later line that actually decides the behaviour.
last_directive() { grep -E "^[[:space:]]*$2([[:space:]]|$)" "$1" | tail -1 | sed -E "s/^[[:space:]]*$2[[:space:]]+//"; }

# REFUTED IN PLACE 2026-09-16 by a49280bd9, kept as the record of what was believed.
# This case demanded top == 22.5 (one cell), the reservoir the ON-half config swap handed back.
# The operator asked for that band to go ("Is there a way to remove the top margin?"): it cost
# 45px of dead space at the top of every pane, all day, to make a chord pressed a few times a
# week zero-shift. a49280bd9 removed it, so BOTH halves now read `0 5 0 5` and the assertion
# below is the shipped design, not the old one. a49280bd9 ran kitty-conf-bindings and
# cc-kitty-reload but NOT this suite, which is why these four cases sat red on trunk.
@test "kitty.conf reserves NO top padding — the reservoir was removed (a49280bd9)" {
  run last_directive "$OFF" window_padding_width
  [ "$status" -eq 0 ] || false
  # four values = top right bottom left (CSS order)
  # The split IS the point: $output is one line of padding values and we want
  # them as separate positionals, so quoting would defeat the assertion.
  # shellcheck disable=SC2086
  set -- $output
  [ "$#" -eq 4 ] || false
  [ "$1" = "0" ] || false
  [ "$3" = "0" ] || false
}

@test "the ON half hands the whole reservoir back: top 0, bottom unchanged at 0" {
  run last_directive "$ON" window_padding_width
  [ "$status" -eq 0 ] || false
  # The split IS the point: $output is one line of padding values and we want
  # them as separate positionals, so quoting would defeat the assertion.
  # shellcheck disable=SC2086
  set -- $output
  [ "$#" -eq 4 ] || false
  [ "$1" = "0" ] || false
  [ "$3" = "0" ] || false
}

# REFUTED IN PLACE 2026-09-16 by a49280bd9. The identity used to be top_OFF - top_ON == one
# cell; the commit states the consequence itself — "config/kitty-title-on.conf is now identical
# to kitty.conf on both paired values, so the ⌘⌥B swap compensates nothing and its real bars
# take one row while they are up. Accepted trade." So the surviving invariant is EQUALITY, and
# a non-zero delta now means the reservoir crept back in unnoticed.
@test "the pairing identity holds: top_OFF == top_ON, bottoms equal (swap compensates nothing)" {
  local ot on_ ob nb
  ot="$(last_directive "$OFF" window_padding_width | awk '{print $1}')"
  ob="$(last_directive "$OFF" window_padding_width | awk '{print $3}')"
  on_="$(last_directive "$ON" window_padding_width | awk '{print $1}')"
  nb="$(last_directive "$ON" window_padding_width | awk '{print $3}')"
  # the row-count half
  run awk -v a="$ot" -v b="$on_" 'BEGIN{exit !((a-b)==0)}'
  [ "$status" -eq 0 ] || false
  # the pixel half: if the bottoms ever differ the grid's top edge can move
  [ "$ob" = "$nb" ] || false
}

@test "the reservoir is pinned to the font that derives it" {
  # Change either of these and 22.5 is the wrong number — silently.
  run grep -qE '^font_size[[:space:]]+18\.0[[:space:]]*$' "$OFF"
  [ "$status" -eq 0 ] || false
  run grep -qE '^modify_font[[:space:]]+cell_height[[:space:]]+94%[[:space:]]*$' "$OFF"
  [ "$status" -eq 0 ] || false
}

@test "placement_strategy top — the design depends on it, and the kitty default is center" {
  # `top` pins the grid to the top of the padded area and parks all sub-cell leftover at the
  # BOTTOM. Under the `center` default the leftover is split, so changing the padding would move
  # the grid's top edge and the toggle would creep by half a cell.
  run grep -qE '^placement_strategy[[:space:]]+top[[:space:]]*$' "$OFF"
  [ "$status" -eq 0 ] || false
}

@test "bars are OFF by default and held up ONLY by the ON half" {
  run last_directive "$OFF" window_title_bar_min_windows
  [ "$status" -eq 0 ] || false
  [ "$output" = "0" ] || false
  run last_directive "$ON" window_title_bar_min_windows
  [ "$status" -eq 0 ] || false
  [ "$output" = "1" ] || false
}

@test "the ON half includes the main config, so it cannot drift from it" {
  run grep -qE '^include[[:space:]]+kitty\.conf[[:space:]]*$' "$ON"
  [ "$status" -eq 0 ] || false
}

@test "cmd+shift+b runs the toggle script and NOT the bare built-in action" {
  local line
  line="$(grep -E '^map[[:space:]]+cmd\+shift\+b([[:space:]]|$)' "$OFF" | tail -1)"
  [ -n "$line" ] || false
  case "$line" in *kitty-pane-title-toggle.sh*) ;; *) false ;; esac
  # `toggle_window_title_bars` is the one-row shift this feature exists to remove, and with
  # min_windows >= 1 it is inert anyway — so it must not be what the chord ends in.
  case "$line" in *toggle_window_title_bars*) false ;; *) ;; esac
}

# RE-KEYED 2026-09-16: a49280bd9 swapped the chords — ⌘⇧B now carries the GRAPHICS OVERLAY and
# ⌘⌥B the real bars. The clear-before-draw ordering this case guards therefore lives on ⌘⇧B now.
# The invariant is unchanged and is still the double-title trap: clear the real bars BEFORE the
# overlay paints, or a strip is drawn under a bar that is about to be raised over it.
@test "cmd+shift+b clears the REAL bars before drawing the overlay" {
  # The bars now PERSIST, so the reverse order is a standing double-title trap rather than the
  # accident it used to be. ⌘⇧B already guards the other direction; this is its mirror.
  local line
  line="$(grep -E '^map[[:space:]]+cmd\+shift\+b([[:space:]]|$)' "$OFF" | tail -1)"
  [ -n "$line" ] || false
  case "$line" in *kitty-pane-title-toggle.sh\ off*) ;; *) false ;; esac
  # ORDER matters, so assert on the prefix that precedes the overlay call rather than on the
  # whole line: clearing AFTER the toggle would wipe a strip the overlay's hold loop just drew.
  [ "${line%%kitty-pane-title-overlay.py*}" != "$line" ] || false
  local before_overlay="${line%%kitty-pane-title-overlay.py*}"
  case "$before_overlay" in *kitty-pane-title-toggle.sh\ off*) ;; *) false ;; esac
}

@test "the toggle script exists, is executable, and rejects an unknown argument" {
  [ -x "$TOGGLE" ] || false
  run env KITTY_TITLE_STATE="$BATS_TEST_TMPDIR/state" "$TOGGLE" nonsense
  [ "$status" -eq 2 ] || false
}

@test "both halves parse through kitty's OWN loader with the intended values" {
  # A grep cannot see a later line shadowing ours, a typo kitty silently drops, or a bad float.
  # kitty's parser can. Skipped rather than faked where kitty is absent (CI, a bare container).
  command -v kitty >/dev/null 2>&1 || skip "kitty not installed"
  run kitty +runpy "
from kitty.config import load_config
o  = load_config('$OFF')
on = load_config('$ON')
print('OFF', o.window_padding_width.top, o.window_padding_width.bottom,
      o.window_title_bar_min_windows, o.placement_strategy)
print('ON ', on.window_padding_width.top, on.window_padding_width.bottom,
      on.window_title_bar_min_windows)
"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -qE "^OFF 0(\.0)? 0(\.0)? 0 top$" || false
  echo "$output" | grep -qE "^ON  0 0 1$" || false
}
