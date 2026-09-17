#!/usr/bin/env bats
# THE DRAGGABLE PANE TITLE IS ON BY DEFAULT — an OPERATOR RULING, pinned mechanically.
#
# WHY A TEST AND NOT A COMMENT. This exact regression reached the operator three times
# (2026-09-14, and twice on 2026-09-16), and each time the config already carried prose
# explaining it. Prose lost, because the overlay is genuinely prettier and every session
# that re-introduced it re-derived the trade from scratch. His ruling: "all other features
# come secondary to being draggable if its a technical impossibility for all/both."
#
# WHY THIS IS NOT THE SAME AS tests/kitty-conf-bindings.bats's ⌘⇧B guard. That one asserts
# a CHORD can reach real bars. A chord you must remember to press is exactly how the feature
# kept going missing — the operator does not press it, sees no draggable title, and reports
# it broken. This pins the RESTING STATE: real, hit-tested, draggable bars with nothing
# pressed at all.
#
# kitty's own docs for the option: 0 = never show, 1 = always show, N = show at N+ windows.
# Asserted through kitty's real parser, never a grep of the file, because a grep proves a
# line was typed and not that the terminal will act on it.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CONF="$REPO/config/kitty.conf"
  KITTY="$(command -v kitty 2>/dev/null || true)"
  [ -n "$KITTY" ] || KITTY=/Applications/kitty.app/Contents/MacOS/kitty
  [ -x "$KITTY" ] || skip "kitty is not installed — this asserts against its real config parser"
}

min_windows() {
  CC_TEST_CONF="$1" "$KITTY" +runpy '
def main():
    import os
    from kitty.config import load_config
    o = load_config(os.environ["CC_TEST_CONF"])
    print("min_windows=%s" % o.window_title_bar_min_windows)
main()
' 2>/dev/null
}

@test "real draggable title bars are ON in the resting config (operator ruling)" {
  run min_windows "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local v; v="${output#min_windows=}"
  case "$v" in ''|*[!0-9]*) echo "unparseable: $output"; false ;; esac
  [ "$v" -ge 1 ] || {
    echo "window_title_bar_min_windows is $v — 0 means NEVER SHOW, so there is no real"
    echo "title bar to grab and drag-to-reorder is gone with nothing pressed."
    echo "This is the operator's ruling and is not a trade to re-open: a draggable pane"
    echo "title outranks zero row shift, custom fonts, and the graphics overlay."
    echo "The overlay draws a PICTURE of a bar; kitty's drag machinery hangs off real"
    echo "title-bar render data, so a picture can never be dragged however it is drawn."
    false; }
}

@test "MUTANT CONTROL: flipping it back to 0 is caught — the guard above is not decorative" {
  local mut="$BATS_TEST_TMPDIR/mutant.conf"
  sed 's/^window_title_bar_min_windows 1$/window_title_bar_min_windows 0/' "$CONF" > "$mut"
  # the mutation must actually have applied, or this control proves nothing
  grep -q '^window_title_bar_min_windows 0$' "$mut" || {
    echo "mutant did not apply — the setting's spelling changed and this control is vacuous"; false; }
  run min_windows "$mut"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local v; v="${output#min_windows=}"
  [ "$v" = "0" ] || { echo "expected the mutant to parse as 0, got: $output"; false; }
}
