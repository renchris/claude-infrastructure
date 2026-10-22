#!/usr/bin/env bats
# it2-kitty split — a launch whose ANSWER was lost must not orphan the pane kitty went on to open.
#
# THE DEFECT (2026-10-22, session kte-w3, load ~450). kt wraps `kitty @ launch` in `timeout`, which
# kills the CLIENT; the request had already reached kitty, which finished it seconds later. 9 teammate
# splits each failed "kitty launch failed (rc=124)" while kitty opened all 9 panes — no id recorded,
# so no command was ever delivered to them and nothing ever closed them.
#
# The fix tags every launch with a unique `cc_spawn` user var and, on a lost answer, reconciles
# against `kitty @ ls`: the one window carrying the EXACT tag is adopted. The pairs below hold both
# halves — a late window IS adopted, and a window without the exact tag is never touched.
#
# Hermetic: kitty is a cc_stub that records argv, keeps the launch's tag in $STATE, and answers `ls`
# with an operator window plus (per LS_MODE) the late window.

load helpers/cc-stub

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  K="$REPO/bin/it2-kitty"
  S="$BATS_TEST_TMPDIR/stub"
  export STATE="$BATS_TEST_TMPDIR/state"; mkdir -p "$STATE"
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  export CC_TERM_KITTY="$S/kitty"
  export CC_PANE_CMD_DIR="$BATS_TEST_TMPDIR/cmd"
  export CC_PANE_RUNNER_BIN="$REPO/bin/cc-pane-runner"
  export KLOG="$BATS_TEST_TMPDIR/kitty.log"
  export IT2_KITTY_RECONCILE_S=3
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_WAIT_S CC_PANE_RUNNER LAUNCH_MODE LS_MODE APPEAR_AFTER
  cc_stub "$S" kitty - <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
tag="" prev="" verb=""
for a in "$@"; do
  [ "$prev" = --var ] && case "$a" in cc_spawn=*) tag="${a#cc_spawn=}" ;; esac
  prev="$a"
done
for a in "$@"; do case "$a" in @|--to|unix:*) continue ;; *) verb="$a"; break ;; esac; done
case "$verb" in
  launch)
    printf '%s' "$tag" > "$STATE/tag"
    case "${LAUNCH_MODE:-ok}" in
      ok)      echo 42 ;;
      rc124)   exit 124 ;;
      hang)    sleep 5; echo 42 ;;
      garbled) echo "Error: no response" ;;
      refused) echo "Error: connection refused" >&2; exit 1 ;;
    esac ;;
  ls)
    n=$(( $(cat "$STATE/ls-n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STATE/ls-n"
    t="$(cat "$STATE/tag" 2>/dev/null)"
    late=""
    if [ "$n" -ge "${APPEAR_AFTER:-1}" ]; then
      case "${LS_MODE:-tagged}" in
        tagged) late=",{\"id\":57,\"user_vars\":{\"cc_spawn\":\"$t\"}}" ;;
        prefix) late=",{\"id\":57,\"user_vars\":{\"cc_spawn\":\"${t}9\"}}" ;;
        none)   late="" ;;
      esac
    fi
    printf '[{"id":1,"tabs":[{"id":1,"windows":[{"id":7,"user_vars":{}}%s]}]}]\n' "$late" ;;
esac
exit 0
SH
}

@test "every split carries a unique cc_spawn tag" {
  run "$K" session split -v -s 7
  [ "$status" -eq 0 ]
  [ "$output" = "Created new pane: 42" ]
  grep -q -- '--var cc_spawn=cc' "$KLOG" || false
  [ -s "$STATE/tag" ]
  # a clean launch never pays for a reconcile
  ! grep -q '^@.* ls ' "$KLOG" || false
}

@test "a launch that timed out (rc 124) adopts the late window carrying its tag — and arms it" {
  LAUNCH_MODE=rc124 run "$K" session split -v -s 7
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"Created new pane: 57"* ]] || { echo "$output"; false; }
  [[ "$output" == *"adopting it"* ]] || false
  [ -f "$CC_PANE_CMD_DIR/57.armed" ]
  grep -q -- "var:cc_spawn=^$(cat "$STATE/tag")\\$" "$KLOG" || false
}

@test "a REAL client timeout (kitty answers after IT2_KITTY_TIMEOUT_S) is reconciled the same way" {
  LAUNCH_MODE=hang IT2_KITTY_TIMEOUT_S=1 run "$K" session split -v -s 7
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"Created new pane: 57"* ]] || { echo "$output"; false; }
}

@test "a window that appears only on a later poll is still adopted" {
  APPEAR_AFTER=2 LAUNCH_MODE=rc124 run "$K" session split -v -s 7
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"Created new pane: 57"* ]] || false
  [ "$(cat "$STATE/ls-n")" -ge 2 ]
}

@test "a non-id answer (rc 0, garbled) is reconciled too" {
  LAUNCH_MODE=garbled run "$K" session split -v -s 7
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"Created new pane: 57"* ]] || false
}

@test "no window with the EXACT tag ⇒ fails as before, bounded, and touches no window" {
  LS_MODE=prefix LAUNCH_MODE=rc124 IT2_KITTY_RECONCILE_S=2 run "$K" session split -v -s 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"kitty launch failed (rc=124)"* ]] || false
  [[ "$output" != *"Created new pane"* ]] || false
  [ ! -f "$CC_PANE_CMD_DIR/57.armed" ]
  ! grep -q 'close-window' "$KLOG" || false
  [ "$(cat "$STATE/ls-n")" -le 4 ]
}

@test "a refused launch (rc 1) fails fast — no reconcile" {
  LAUNCH_MODE=refused run "$K" session split -v -s 7
  [ "$status" -eq 1 ]
  [ ! -e "$STATE/ls-n" ]
}

@test "IT2_KITTY_RECONCILE_S=0 turns the reconcile off" {
  IT2_KITTY_RECONCILE_S=0 LAUNCH_MODE=rc124 run "$K" session split -v -s 7
  [ "$status" -eq 1 ]
  [ ! -e "$STATE/ls-n" ]
}
