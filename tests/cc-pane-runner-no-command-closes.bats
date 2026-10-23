#!/usr/bin/env bats
# bin/cc-pane-runner — an ARMED agent pane that never receives its command closes at the deadline.
#
# THE DEFECT (2026-10-22, session kte-w3). A split whose answer was lost to a client timeout left
# kitty's late pane with nobody holding its id; the runner waited CC_PANE_CMD_WAIT_S and then exec'd
# a login shell — 9 ownerless shells that nothing would ever close. The deadline now closes the pane
# through the same gates as every other runner close (recycle check, fullscreen guard in refuse mode,
# CC_PANE_CLOSE_ON_EXIT=0); the OTHER fallbacks (no state dir, not kitty) keep the shell — those are
# a human's pane. Shape: tests/cc-pane-runner-exit75-closes.bats.

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RUNNER="$REPO/bin/cc-pane-runner"
  T="$BATS_TEST_TMPDIR"
  S="$T/stub"
  mkdir -p "$T/home" "$T/locks" "$T/cmd"
  export HOME="$T/home" LR_LOCKS_DIR="$T/locks" GLOG="$T/guard-log" SHELL_RAN="$T/shell-ran"
  export KITTY_WINDOW_ID=42 CC_PANE_WEDGE_WATCH=0 CC_PANE_CMD_DIR="$T/cmd" CC_PANE_CMD_WAIT_S=0
  unset KITTY_LISTEN_ON CC_TERM_KITTY_TO CC_PANE_CLOSE_ON_EXIT CC_PANE_CMD_INTERACTIVE CC_PANE_CMD
  unset CC_PANE_RUNNER_OWNS_CLOSE KITTY_PID LR_RUN_DIR CC_PANE_STARTED_FILE CC_PANE_EXIT_OWED
  export PATH="$S:/usr/bin:/bin"
  cc_stub "$S" fsguard '#!/bin/bash
printf "%s\n" "$*" >> "$GLOG"
[ -n "${GUARD_ERR:-}" ] && printf "%s\n" "$GUARD_ERR" >&2
exit "${GUARD_RC:-0}"'
  export CC_KITTY_FS_GUARD="$S/fsguard"
  cc_stub "$S" fakeshell '#!/bin/bash
: > "$SHELL_RAN"
exit 7'
  export SHELL="$S/fakeshell"
}

@test "no command by the deadline closes the armed pane — through the guard, refuse mode, pane scope" {
  : > "$CC_PANE_CMD_DIR/42.armed"
  run "$RUNNER"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$SHELL_RAN" ]
  [ "$(cat "$GLOG")" = "--window 42 --mode refuse --scope pane --tool cc-pane-runner" ]
  [ ! -e "$CC_PANE_CMD_DIR/42.armed" ]
}

@test "it closes even with no .armed marker — the orphan case, where it2-kitty never wrote one" {
  run "$RUNNER"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$SHELL_RAN" ]
  [ -s "$GLOG" ]
}

@test "the guard refusing (last pane of a fullscreen window) keeps the shell — never a raw close" {
  GUARD_RC=3 run "$RUNNER"
  [ "$status" -eq 7 ]
  [ -e "$SHELL_RAN" ]
}

@test "CC_PANE_CLOSE_ON_EXIT=0 keeps the shell and never asks the guard" {
  CC_PANE_CLOSE_ON_EXIT=0 run "$RUNNER"
  [ "$status" -eq 7 ]
  [ -e "$SHELL_RAN" ]
  [ ! -e "$GLOG" ]
}

@test "a human's pane (no CC_PANE_CMD_DIR) still becomes a shell" {
  run env -u CC_PANE_CMD_DIR "$RUNNER"
  [ "$status" -eq 7 ]
  [ -e "$SHELL_RAN" ]
  [ ! -e "$GLOG" ]
}

@test "a command that arrives in time still runs" {
  printf '%s' ": > $T/ran" > "$CC_PANE_CMD_DIR/42.cmd"
  CC_PANE_CMD_WAIT_S=5 run "$RUNNER"
  [ -e "$T/ran" ]
}

@test "an UNREADABLE guard read says kitty didn't answer — never 'last pane of a fullscreen window', never the guard's raw line" {
  # husk-panes-2026-10-22 F4, pane 42: a kitten-failed read in a 3-pane window was painted as the
  # last pane of a fullscreen window, with the guard's placeholder state line under it. RED before
  # the fix: both forbidden strings reached the pane.
  GUARD_RC=3 GUARD_ERR='kitty-fullscreen-guard: refused (kitten-failed) could not read kitty window 42: timed out' run "$RUNNER"
  [ "$status" -eq 7 ]
  [[ "$output" == *"kitty didn't answer"* ]] || { echo "$output"; false; }
  [[ "$output" != *"last pane of a fullscreen window"* ]] || { echo "$output"; false; }
  [[ "$output" != *"kitty-fullscreen-guard: refused"* ]] || { echo "$output"; false; }
}

@test "a refused-fs guard verdict says last pane of a fullscreen window and names ⌘W, without the guard's raw line" {
  GUARD_RC=3 GUARD_ERR='kitty-fullscreen-guard: refused (refused-fs) kitty window 42 scope=pane mode=refuse: state=FS types=[4] onscreen=True' run "$RUNNER"
  [ "$status" -eq 7 ]
  [[ "$output" == *"last pane of a fullscreen window"*"⌘W closes it"* ]] || { echo "$output"; false; }
  [[ "$output" != *"kitty-fullscreen-guard: refused"* ]] || { echo "$output"; false; }
}

@test "no command and the guard cannot read kitty: an exit record (never launched) AND a husk row are left" {
  # husk-panes-2026-10-22 F3, pane 101: _no_command wrote no exit record, so cc-pane-close's
  # never-launched arm refused the pane forever, and nothing retried. RED before the fix.
  export CC_PANE_EXIT_DIR="$T/pane-exit" CC_PANE_CLOSE_QUEUE_DIR="$T/q"
  GUARD_RC=3 GUARD_ERR='kitty-fullscreen-guard: refused (kitten-failed) could not read kitty window 42: x' run "$RUNNER"
  [ "$status" -eq 7 ]
  [ "$(jq -r .claude_started "$T/pane-exit/42.json")" = false ]
  [ "$(jq -r .rc "$T/pane-exit/42.json")" = 124 ]
  [ "$(jq -r .reason "$T/q/husk-42.json")" = guard-unreadable ]
  [ "$(jq -r .what "$T/q/husk-42.json")" = "this armed agent pane" ]
}

@test "F5: with a tty, the kept no-command pane is painted by cc-pane-verdict (NOTHING RAN) and the runner adds no line" {
  # RED before F5: the runner printed its own two lines (the guard's and "pane is an ordinary shell").
  export CC_PANE_RUNNER_TTY="$T/ttys042" CC_PANE_EXIT_DIR="$T/pane-exit" CC_PANE_CLOSE_QUEUE_DIR="$T/q"
  export CC_PANE_VERDICT_DIR="$T/pv" CC_PANE_VERDICT_KITTY_BIN="$T/no-kitty" CC_SAY_LOG="$T/say.jsonl"
  : > "$CC_PANE_RUNNER_TTY"
  GUARD_RC=3 GUARD_ERR='kitty-fullscreen-guard: refused (kitten-failed) could not read kitty window 42: x' run "$RUNNER"
  [ "$status" -eq 7 ]
  grep -qF '✗ no session started in this pane' "$CC_PANE_RUNNER_TTY" || { cat -v "$CC_PANE_RUNNER_TTY"; false; }
  grep -qF "kitty didn't answer · closes when it does" "$CC_PANE_RUNNER_TTY"
  [[ "$output" != *"pane is an ordinary shell"* ]] || { echo "$output"; false; }
  [[ "$output" != *"kitty didn't answer"* ]] || { echo "$output"; false; }
}
