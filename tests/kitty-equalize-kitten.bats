#!/usr/bin/env bats
# ⌘⇧E equalizes in EVERY layout. `layout_action equalize` is Splits-only, so in the one-row
# `horizontal` resume layout the bare chord only beeped (incident 2026-10-01: 6 of 8 live tabs in
# horizontal, ⌘⇧E "does nothing"). scripts/kitty-equalize.py dispatches on the tab's layout.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CONF="$REPO/config/kitty.conf"
  KITTEN="$REPO/scripts/kitty-equalize.py"
  KITTY="$(command -v kitty 2>/dev/null || true)"
  [ -n "$KITTY" ] || KITTY=/Applications/kitty.app/Contents/MacOS/kitty
  [ -x "$KITTY" ] || skip "kitty is not installed — these tests run the kitten under kitty's own python"
}

# Runs handle_result from the kitten file $1 against fake tabs, printing one verdict line per case.
drive() {
  CC_KITTEN="$1" "$KITTY" +runpy '
def main():
    import os, importlib.util
    spec = importlib.util.spec_from_file_location("k", os.environ["CC_KITTEN"])
    k = importlib.util.module_from_spec(spec); spec.loader.exec_module(k)
    class L:
        def __init__(s, name): s.name = name
    class T:
        def __init__(s, tid, layout): s.id, s.current_layout, s.calls = tid, L(layout), []
        def layout_action(s, name, args): s.calls.append("layout_action:" + name)
        def reset_window_sizes(s): s.calls.append("reset_window_sizes")
    class W:
        def __init__(s, tab_id): s.tab_id = tab_id
    class B:
        def __init__(s, tabs, windows, active): s.tabs, s.window_id_map, s.active_tab = tabs, windows, active
        def tab_for_id(s, tid): return s.tabs.get(tid)
    for layout in ("splits", "horizontal", "vertical", "stack"):
        t = T(1, layout); b = B({1: t}, {7: W(1)}, t)
        k.handle_result([], "", 7, b)
        print("%s=%s" % (layout, ",".join(t.calls)))
    # The INVOKING window picks the tab, not focus: --self from a script must hit its own tab.
    focused, mine = T(1, "horizontal"), T(2, "horizontal")
    k.handle_result([], "", 9, B({1: focused, 2: mine}, {9: W(2)}, focused))
    print("target_tab=%s focused_tab=%s" % (",".join(mine.calls), ",".join(focused.calls)))
    # An unknown window falls back to the active tab rather than raising.
    t = T(1, "horizontal")
    k.handle_result([], "", 404, B({1: t}, {}, t))
    print("fallback=%s" % ",".join(t.calls))
main()
' 2>&1
}

@test "the chord resolves to the kitten, not the splits-only bare action" {
  run env CC_TEST_CONF="$CONF" "$KITTY" +runpy '
def main():
    import os
    from kitty.config import load_config
    km = load_config(os.environ["CC_TEST_CONF"]).keyboard_modes[""].keymap
    for k, v in km.items():
        if getattr(k, "mods", None) == 9 and getattr(k, "key", None) == 101:   # cmd+shift, e
            print("cmd_shift_e_last=%s" % getattr(v[-1], "definition", ""))
main()
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qxF 'cmd_shift_e_last=kitten ${HOME}/.claude/scripts/kitty-equalize.py' || { echo "$output"; false; }
}

@test "the premise: kitty's horizontal layout has no equalize (returns None, so the bare chord only beeps)" {
  run "$KITTY" +runpy '
from kitty.layout.vertical import Horizontal
from kitty.layout.splits import Splits
print("horizontal_overrides=%d" % ("layout_action" in Horizontal.__dict__ or "layout_action" in Horizontal.__mro__[1].__dict__))
print("splits_overrides=%d" % ("layout_action" in Splits.__dict__))
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qx 'horizontal_overrides=0' || { echo "$output"; false; }
  echo "$output" | grep -qx 'splits_overrides=1' || { echo "$output"; false; }
}

@test "splits keeps count-weighted equalize; every other layout resets its biases" {
  run drive "$KITTEN"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qx 'splits=layout_action:equalize' || { echo "$output"; false; }
  echo "$output" | grep -qx 'horizontal=reset_window_sizes' || { echo "$output"; false; }
  echo "$output" | grep -qx 'vertical=reset_window_sizes' || { echo "$output"; false; }
  echo "$output" | grep -qx 'stack=reset_window_sizes' || { echo "$output"; false; }
  echo "$output" | grep -qx 'target_tab=reset_window_sizes focused_tab=' || { echo "$output"; false; }
  echo "$output" | grep -qx 'fallback=reset_window_sizes' || { echo "$output"; false; }
}

@test "MUTANT CONTROL: a kitten that always sends the bare action is caught in horizontal" {
  MUT="$BATS_TEST_TMPDIR/mut.py"
  sed 's/if tab.current_layout.name == "splits":/if True:/' "$KITTEN" > "$MUT"
  ! cmp -s "$KITTEN" "$MUT" || { echo "mutation did not apply"; false; }
  run drive "$MUT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qx 'horizontal=layout_action:equalize' || { echo "$output"; false; }
}
