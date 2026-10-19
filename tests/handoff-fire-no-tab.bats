#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2329
#   SC2030/2031: every @test body is its own subshell, so an export inside one is test-local.
#   SC2034/SC2329: the variables and stubs below are read or called by the eval-extracted spawn functions.
#
# handoff-fire's fire surfaces never open a kitty TAB (lr-wake incident 2026-10-18, REPORT §4 Wave E;
# RC3). Overnight, 22 agent `--tab` fires became `kitty @ launch --type=tab` — hidden tabs of plain
# shells — through one rewrite (`--tab` → bg-tab → it2py bgtab → kt_launch --type=tab). The operator
# rule: NO kitty tabs, ever; every OS window fullscreen on its own Space; at most 4 vertical panes.
#
# Every case reads what the fire SENT kitty: a recording stub whose `kitty @ ls` is MUTABLE (Wave D's
# tests/fixtures/pane-placement/fake-kitty.py), so a sequence of fires sees its own earlier panes. The
# subject is the REAL spawn path — spawn(), as_tab, it2py bgtab, spawn_frontmost, kt_launch and
# hf_place_pane extracted from scripts/handoff-fire.sh — placed by the REAL scripts/lib/pane-placement.sh.
#
# RED on origin/main before this wave: --tab and bg-tab launched `--type=tab` (the argv cases), kt_launch
# passed `--type=tab` through (the refusal case), a full named anchor got a fifth split (the room case),
# --window was not fullscreen, and the 16-fire replay made 16 tabs in one OS window.
#
# Hermetic: HOME, the spawn log and the kitty binary are per-test; nothing talks to a real kitty.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # Seams that do NOT resolve under $HOME (test-hermeticity-lint 5a/5b): absent paths, sensors fail open.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_SPAWN_LOG_FILE="$BATS_TEST_TMPDIR/spawns.jsonl"
  export KLOG="$BATS_TEST_TMPDIR/kitty.log" KSTATE="$BATS_TEST_TMPDIR/ls.json"
  : > "$KLOG"
  export CC_TERM_KITTY="$BATS_TEST_DIRNAME/fixtures/pane-placement/fake-kitty.py"
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  export CC_PLACE_LOAD_PER_CORE=0
  export CC_PANE_PLACEMENT_LIB="$REPO/scripts/lib/pane-placement.sh"
  unset CC_KITTY_BIN CC_PLACE_KITTY_BIN CC_PLACE_FOCUS CC_PLACE_REQUESTED CC_MAX_PANES_PER_SPACE IT2_WRAPPER_NO_KITTY
  export KITTY_WINDOW_ID=344

  hf_bounded() { "$@"; }
  hf_bounded_s() { shift; "$@"; }
  local f x
  for f in kt_launch hf_place_pane hf_anchor_room hf_adopt_split_pane as_tab it2_bgtab it2py spawn_frontmost spawn; do
    x="$(sed -n "/^$f() {/,/^}/p" "$HF")"
    [ -n "$x" ] || { echo "extraction of $f() is EMPTY — the subject is missing" >&2; return 1; }
    eval "$x"
  done
  # one-liners: a /,/^}/ range would swallow the next function
  eval "$(sed -n '/^in_kitty() {/p;/^kt() {/p' "$HF")"

  LAND="$BATS_TEST_TMPDIR/land"; : > "$LAND"
  SPLITS="$BATS_TEST_TMPDIR/splits"; : > "$SPLITS"
  it2_land() { echo "$1" >> "$LAND"; return 0; }
  it2_split() { echo "$1" >> "$SPLITS"; printf 901; }
  restore_focus_or_fail() { return 0; }
  FIRING_SID=344 ANCHOR_INTENT=1 FOLLOW=0 FIRE_SPAWN_UNKNOWN=0 SURFACE_REASON=""
  CMD="claude --fire-marker $BATS_TEST_NUMBER-$$"
  HF_ARGV=(--env "CC_PANE_CMD=$CMD" -- /bin/zsh -l)
  HF_ARGV_ACTIVE=1
}

# one OS window (id 18), one splits tab, panes <ids…>
one_window() {
  python3 -c '
import json, sys
ids = [int(x) for x in sys.argv[2:]]
json.dump([{"id": 18, "tabs": [{"id": 146, "layout": "splits",
           "windows": [{"id": i, "columns": 80, "user_vars": {}} for i in ids]}]}], open(sys.argv[1], "w"))' "$KSTATE" "$@"
}
# one line per OS window: `<id> tabs=<n> panes=<n>`
shape() {
  python3 -c '
import json, sys
for o in json.load(open(sys.argv[1])):
    print("%s tabs=%d panes=%d" % (o["id"], len(o["tabs"]), sum(len(t["windows"]) for t in o["tabs"])))' "$KSTATE"
}
no_tab_argv() { ! grep -q -- '--type=tab' "$KLOG"; }

@test "--tab (deprecated alias) from a FULL window is placed by the policy: a fullscreen OS window, never --type=tab" {
  one_window 344 345 346 347
  SURFACE=tab
  run spawn
  echo "$output"
  [ "$status" -eq 0 ]
  no_tab_argv || { cat "$KLOG"; false; }
  grep -qF -- '--type=os-window' "$KLOG"
  grep -qF -- '--os-window-state=fullscreen' "$KLOG"
  [ "$(cat "$LAND")" = 900 ]
}

@test "--tab from a window WITH room is a split beside the firing pane — still never a tab" {
  one_window 344 345
  SURFACE=tab
  run spawn
  [ "$status" -eq 0 ]
  no_tab_argv || { cat "$KLOG"; false; }
  grep -qF -- 'launch --type=window --location=vsplit --match window_id:344 --next-to id:344' "$KLOG"
  [ "$(shape)" = "18 tabs=1 panes=3" ]
}

@test "the bg-tab verb (it2py bgtab) places too: no --type=tab, the operator's focus kept" {
  one_window 344 345
  SURFACE=bg-tab
  run spawn
  [ "$status" -eq 0 ]
  no_tab_argv || { cat "$KLOG"; false; }
  grep -qF -- '--dont-take-focus' "$KLOG"
}

@test "REPLAY: 16 --tab fires from pane 344 give 4 fullscreen OS windows, each 1 tab and at most 4 panes" {
  # The overnight shape: pane 344's OS window already holds 4 panes, and 16 rescue fires name it.
  one_window 344 345 346 347
  SURFACE=tab
  local i
  for i in $(seq 16); do
    spawn >/dev/null 2>&1 || { echo "fire $i failed" >&2; false; }
  done
  no_tab_argv || { cat "$KLOG"; false; }
  [ "$(grep -c -- ' launch --type=os-window' "$KLOG")" -eq 4 ]
  [ "$(grep -c -- '--os-window-state=fullscreen' "$KLOG")" -eq 4 ]
  run shape
  echo "$output"
  [ "${#lines[@]}" -eq 5 ]
  for l in "${lines[@]}"; do
    [[ "$l" == *" tabs=1 panes=4" ]] || false
  done
  # and the pane-spawn log holds no tab row for the ratchet to count
  [ "$(jq -s '[.[] | select(.surface == "tab" or .surface == "bg-tab")] | length' "$CC_SPAWN_LOG_FILE")" -eq 0 ]
  [ "$(wc -l < "$LAND" | tr -d ' ')" -eq 16 ]
}

@test "--split-right from a FULL named anchor overflows through the policy — never a fifth pane, never the plain split" {
  one_window 344 345 346 347
  SURFACE=split-right
  run spawn
  echo "$output"
  [ "$status" -eq 0 ]
  [ ! -s "$SPLITS" ]                                 # the it2 split was NOT taken
  grep -qF -- '--os-window-state=fullscreen' "$KLOG"
  [[ "$output" == *"firing pane's OS window is full"* ]] || false
  run shape
  [ "${lines[0]}" = "18 tabs=1 panes=4" ]
}

@test "--split-right from a window holding TWO tabs is placed too (the room rule counts tabs)" {
  one_window 344 345
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
d[0]["tabs"].append({"id": 147, "layout": "splits", "windows": [{"id": 360, "columns": 80}]})
json.dump(d, open(sys.argv[1], "w"))' "$KSTATE"
  SURFACE=split-right
  run spawn
  [ "$status" -eq 0 ]
  [ ! -s "$SPLITS" ]
  no_tab_argv
}

@test "CONTROL: --split-right with room keeps the plain split, byte-identical (no placement launch)" {
  one_window 344 345
  SURFACE=split-right
  run spawn
  [ "$status" -eq 0 ]
  [ "$(cat "$SPLITS")" = 344 ]
  ! grep -q -- ' launch ' "$KLOG" || false
}

@test "kt_launch REFUSES --type=tab (both spellings): rc 1 and no kitty launch at all" {
  one_window 344
  run kt_launch --type=tab --match id:344
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSED --type=tab"* ]] || false
  run kt_launch --type tab --match id:344
  [ "$status" -eq 1 ]
  ! grep -q -- 'launch' "$KLOG" || false
}

@test "--window opens a FULLSCREEN OS window (its own Space)" {
  one_window 344
  run spawn_frontmost
  [ "$status" -eq 0 ]
  grep -qF -- 'launch --type=os-window --cwd=current --os-window-state=fullscreen --keep-focus' "$KLOG"
}

@test "the whole script: --tab warns DEPRECATED and is no longer rewritten to a background tab" {
  printf 'brief\n' > "$BATS_TEST_TMPDIR/p.txt"
  run bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/p.txt" --launcher claude-test --tab --dry-run
  echo "$output"
  [[ "$output" == *"--tab is DEPRECATED"* ]] || false
  ! printf '%s\n' "$output" | grep -qE 'surface: +bg-tab' || false
}
