#!/usr/bin/env bats
# kitty-pane-menu-route — WHERE A PICKED ROW ACTUALLY SENDS THE PANE.
#
# THE DEFECT (operator report 2026-10-01): "would click 'one window right' and it would not be the
# window to the right". The label was right; the ROUTE was not. The menu moved the pane with
# `detach-window --target-tab id:<a window id in the destination>`, believing kitty resolves that
# to the window's owning tab. kitty's match_tabs tries `id:N` against TAB ids first and falls back
# to windows only when no tab matched — and tab ids and window ids are separate counters, so a
# window id equal to a live tab id sends the pane to THAT tab's os-window. Every saved tree from
# 2026-09-30/10-01 (9-10 os-windows) had exactly one such row: os-window 30's row went to 24.
#
# These cases run the whole main() with `kitty` and `osascript` stubbed on PATH, so the assertion
# is on the argv kitty would have received — the route itself, not a helper's return value.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MENU="${KPM_MENU:-$REPO/bin/kitty-pane-menu}"
  [ -f "$MENU" ]
  HOME="$BATS_TEST_TMPDIR/home"; export HOME
  mkdir -p "$HOME/.claude/cc-registry"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export KPM_LOG="$BATS_TEST_TMPDIR/kitty.argv" KPM_TREE="$BATS_TEST_TMPDIR/tree.json"
  : >"$KPM_LOG"
  cat >"$STUBS/kitty" <<'SH'
#!/bin/sh
echo "$*" >>"$KPM_LOG"
case " $* " in *" ls "*|*" ls") [ -n "$KPM_LS_FAIL" ] && { echo "$KPM_LS_FAIL" >&2; exit 1; }
  cat "$KPM_TREE" ;; esac
exit 0
SH
  cat >"$STUBS/osascript" <<'SH'
#!/bin/sh
case "$*" in *"choose from list"*) printf '%s\n' "$KPM_PICK" ;; esac
case "$*" in *"display alert"*) echo "$*" >>"$KPM_LOG.alert" ;; esac
exit 0
SH
  chmod +x "$STUBS/kitty" "$STUBS/osascript"
  # The probe binary is a build artifact beside the deployed copy only; run a copy of the menu from
  # a directory without one, so the centered-dialog path (the osascript stub) is the one taken.
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"; cp "$MENU" "$BIN/kitty-pane-menu"
  export PATH="$STUBS:$PATH" KITTY_LISTEN_ON="unix:$BATS_TEST_TMPDIR/sock"
}

# os-window 1 holds the clicked pane (window 50, focused). os-window 24 holds tab 24. os-window 30
# holds tab 30, whose only pane is window 24 — the live collision, reduced to its two facts.
cat_tree() {
  cat >"$KPM_TREE" <<'JSON'
[{"id": 1, "platform_window_id": 101, "is_active": true,
  "tabs": [{"id": 1, "is_active": true, "is_focused": true,
            "windows": [{"id": 50, "is_active": true, "is_focused": true, "title": "where I clicked", "cwd": "/tmp/a"}]}]},
 {"id": 24, "platform_window_id": 124,
  "tabs": [{"id": 24, "is_active": true, "is_focused": false,
            "windows": [{"id": 40, "is_active": true, "is_focused": false, "title": "the wrong window", "cwd": "/tmp/b"}]}]},
 {"id": 30, "platform_window_id": 130,
  "tabs": [{"id": 30, "is_active": true, "is_focused": false,
            "windows": [{"id": 24, "is_active": true, "is_focused": false, "title": "the window I picked", "cwd": "/tmp/c"}]}]}]
JSON
}

@test "1 a window id that collides with a tab id routes to the PICKED window's tab" {
  cat_tree
  KPM_PICK="the window I picked — 1 pane" run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 0 ]
  run grep -c '^@ detach-window --match id:50 --target-tab id:30 --to ' "$KPM_LOG"
  [ "$output" = "1" ]
  # The pre-fix argv, named so a regression reads as the defect and not as a mystery.
  run grep -c 'target-tab id:24 ' "$KPM_LOG"
  [ "$output" = "0" ]
}

@test "2 the non-colliding row routes to its own tab too" {
  cat_tree
  KPM_PICK="the wrong window — 1 pane" run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 0 ]
  run grep -c '^@ detach-window --match id:50 --target-tab id:24 --to ' "$KPM_LOG"
  [ "$output" = "1" ]
}

@test "3 kitty not answering puts an alert on screen instead of doing nothing" {
  cat_tree
  KPM_LS_FAIL="Error: Failed to connect to unix:/tmp/kitty-610 with error: connection refused" \
    run python3 "$BIN/kitty-pane-menu"
  [ "$status" -eq 3 ]
  [ -f "$KPM_LOG.alert" ]
  run grep -c 'connection refused' "$KPM_LOG.alert"
  [ "$output" = "1" ]
}

@test "4 --check reports the refusal and pops nothing" {
  cat_tree
  KPM_LS_FAIL="Error: connection refused" run python3 "$BIN/kitty-pane-menu" --check
  [ "$status" -eq 3 ]
  [ ! -f "$KPM_LOG.alert" ]
}
