#!/usr/bin/env bats
# kitty-upstream-defects — the source-level falsifier for two upstream kitty defects.
#
# WHY THIS SUITE EXISTS. Backlog rows 7e067b9377ff (fonts_data NULL dereference) and a205ef0a3659
# (tick_lock check-then-use) used to carry a version-string falsifier, `!= 0.48.2`, which an upgrade to
# 0.49.x would have flipped while both defects were still in the code. The replacement reads the
# source structurally, and its consumer CLOSES the row on exit 0, so the dangerous direction is a
# false FIXED. Three cases here pin exactly that: a missing file, a renamed function and an unknown
# defect name must each ABSTAIN (exit 2), never report fixed.
#
# HERMETICITY. Every case passes --src at a fixture: redacted excerpts of v0.49.1 and the same
# excerpts with the drafted fixes. No network, no kitty, no $HOME.

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/checks/kitty-upstream-defects.sh"
FIX="${BATS_TEST_DIRNAME}/fixtures/kitty-upstream-defects"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}

copy_fixture() {  # copy_fixture <name> -> echoes the copy's path
  local dst="${BATS_TEST_TMPDIR}/$1"
  mkdir -p "$dst"
  cp -R "$FIX/$1/." "$dst/"
  printf '%s' "$dst"
}

@test "v0.49.1 excerpt: both defects present, exit 1" {
  run bash "$SCRIPT" --src "$FIX/v0.49.1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"defect=fonts_data state=present site=viewport_for_window,cell_size_for_window,dpi_for_os_window"* ]] || false
  [[ "$output" == *"defect=tick_lock state=present"* ]] || false
  [[ "$output" == *"verdict=PRESENT"* ]]
}

@test "patched excerpt: both defects fixed, exit 0" {
  run bash "$SCRIPT" --src "$FIX/patched"
  [ "$status" -eq 0 ]
  [[ "$output" == *"defect=fonts_data state=fixed"* ]] || false
  [[ "$output" == *"defect=tick_lock state=fixed"* ]] || false
  [[ "$output" == *"verdict=FIXED"* ]]
}

@test "each defect alone: present on v0.49.1, fixed on patched" {
  for d in fonts_data tick_lock; do
    run bash "$SCRIPT" --src "$FIX/v0.49.1" --defect "$d"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"defect=$d state=present"* ]] || return 1
    run bash "$SCRIPT" --src "$FIX/patched" --defect "$d"
    [ "$status" -eq 0 ] || return 1
    [[ "$output" != *"state=present"* ]] || return 1
  done
}

@test "one guard is not enough: a single unguarded site keeps fonts_data present" {
  dir="$(copy_fixture patched)"
  cp "$FIX/v0.49.1/kitty/state.c" "$dir/kitty/state.c"
  run bash "$SCRIPT" --src "$dir" --defect fonts_data
  [ "$status" -eq 1 ]
  [[ "$output" == *"state=present"* ]]
}

@test "a missing source file abstains (exit 2), never reports fixed" {
  dir="$(copy_fixture patched)"
  mv "$dir/glfw/cocoa_init.m" "$dir/glfw/cocoa_init.m.gone"
  run bash "$SCRIPT" --src "$dir" --defect tick_lock
  [ "$status" -eq 2 ]
  [[ "$output" == *"verdict=UNKNOWN"* ]]
}

@test "a renamed function abstains (exit 2), never reports fixed" {
  dir="$(copy_fixture patched)"
  awk '{ gsub(/cell_size_for_window/, "cell_dims_for_window"); print }' "$FIX/patched/kitty/state.c" > "$dir/kitty/state.c"
  run bash "$SCRIPT" --src "$dir" --defect fonts_data
  [ "$status" -eq 2 ]
  [[ "$output" == *"cell_size_for_window-missing"* ]]
}

@test "an unknown defect name is a usage error (exit 2)" {
  run bash "$SCRIPT" --src "$FIX/patched" --defect nonsense
  [ "$status" -eq 2 ]
}
