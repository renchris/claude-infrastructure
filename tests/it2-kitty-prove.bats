#!/usr/bin/env bats
# bin/it2-kitty prove_target: ONE window by `ls --match id:N`, plus the kitty-pid proof (W2c).
#
# `kitty @ send-text` exits 0 for a window that does not exist, so prove_target asks kitty first.
# It used to ask for the WHOLE fleet (`kt ls`) and could not tell a vanished window from a failed
# ls. It now asks for one id and reads the GONE triple identity_ok already documents (rc 1, empty
# stdout, "No matching windows"). And because a kitty window id is a per-process counter that
# restarts at 1 with every kitty, a recorded id can name a live window in a DIFFERENT instance: a
# caller that recorded the kitty pid passes CC_TERM_KITTY_PID, and a window whose env.KITTY_PID
# differs (or is absent) is refused. Unset, nothing about delivery changes.
#
# Behavioural: the shipped bin/it2-kitty runs against a stub `kitty` whose `ls` stdout, stderr and
# rc are scripted per test; every argv it receives is logged, so "nothing sent" is observable.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SHIM="$REPO/bin/it2-kitty"
  [ -x "$SHIM" ] || skip "bin/it2-kitty not found or not executable at $SHIM"

  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export KITTY_ARGV="$BATS_TEST_TMPDIR/kitty-argv.log"
  export LS_OUT="$BATS_TEST_TMPDIR/ls-out.json"
  export LS_ERR="$BATS_TEST_TMPDIR/ls-err.txt"
  export LS_RC=0
  : > "$LS_ERR"; : > "$KITTY_ARGV"
  # One window, id 300, living in kitty pid 4242.
  cat > "$LS_OUT" <<'JSON'
[{"id":1,"tabs":[{"id":1,"windows":[{"id":300,"columns":100,"in_alternate_screen":false,"pid":1,"cwd":"/tmp","env":{"KITTY_PID":"4242"}}]}]}]
JSON

  cat > "$BIN/kitty" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KITTY_ARGV"
for a in "$@"; do
  if [ "$a" = "ls" ]; then
    cat "$LS_OUT"
    cat "$LS_ERR" >&2
    exit "${LS_RC:-0}"
  fi
done
exit 0
SH
  chmod +x "$BIN/kitty"
  export CC_TERM_KITTY="$BIN/kitty"
  export PATH="$BIN:$PATH"
  export KITTY_WINDOW_ID=300
  export CC_KITTY_ARGV_SPAWN=0
  export CC_TERM=kitty
  export KITTY_LISTEN_ON="unix:$BATS_TEST_TMPDIR/kitty-sock"
  unset CC_TERM_KITTY_TO CC_TERM_KITTY_PID
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
}

sent() { grep -c 'send-text' "$KITTY_ARGV" 2>/dev/null || true; }

@test "1 present window: ls asks for --match id:300 (not the fleet), and the text is delivered" {
  run "$SHIM" session send -s 300 "hello"
  [ "$status" -eq 0 ]
  grep -q 'ls --match id:300' "$KITTY_ARGV" || { cat "$KITTY_ARGV"; false; }
  run grep -Eq ' ls$' "$KITTY_ARGV"; [ "$status" -ne 0 ]
  grep -q 'send-text --match id:300' "$KITTY_ARGV"
}

@test "2 absent window (GONE triple: rc 1, empty stdout, No matching windows) -> refused, nothing sent" {
  : > "$LS_OUT"; echo "No matching windows" > "$LS_ERR"; export LS_RC=1
  run "$SHIM" session send -s 300 "hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in kitty's window list"* ]] || false
  [ "$(sent)" = 0 ]
}

@test "3 unreadable ls (rc 1, empty stdout, unrelated stderr) -> delivered anyway (could-not-tell)" {
  : > "$LS_OUT"; echo "Failed to connect to socket" > "$LS_ERR"; export LS_RC=1
  run "$SHIM" session send -s 300 "hello"
  [ "$status" -eq 0 ]
  [ "$(sent)" = 1 ]
}

@test "4 CC_TERM_KITTY_PID differs from the window's env.KITTY_PID -> refused naming both pids" {
  CC_TERM_KITTY_PID=9999 run "$SHIM" session send -s 300 "hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"4242"* && "$output" == *"9999"* ]] || false
  [ "$(sent)" = 0 ]
}

@test "4b CC_TERM_KITTY_PID set but the window carries no env.KITTY_PID -> refused (unproven)" {
  sed -i '' 's/"env":{"KITTY_PID":"4242"}/"env":{}/' "$LS_OUT"
  CC_TERM_KITTY_PID=4242 run "$SHIM" session send -s 300 "hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"<absent>"* ]] || false
  [ "$(sent)" = 0 ]
}

@test "5 CC_TERM_KITTY_PID matches -> delivered" {
  CC_TERM_KITTY_PID=4242 run "$SHIM" session send -s 300 "hello"
  [ "$status" -eq 0 ]
  [ "$(sent)" = 1 ]
}

@test "6 CC_TERM_KITTY_PID unset -> env.KITTY_PID is never consulted" {
  sed -i '' 's/"env":{"KITTY_PID":"4242"}/"env":{"KITTY_PID":"1"}/' "$LS_OUT"
  run "$SHIM" session send -s 300 "hello"
  [ "$status" -eq 0 ]
  [ "$(sent)" = 1 ]
}

@test "7 socket named for kitty 111 with CC_TERM_KITTY_PID=222 -> refused before ANY kitty call" {
  CC_TERM_KITTY_TO="unix:/tmp/kitty-111" CC_TERM_KITTY_PID=222 run "$SHIM" session send -s 300 "hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"111"* && "$output" == *"222"* ]] || false
  [ ! -s "$KITTY_ARGV" ] || { echo "kitty was called:"; cat "$KITTY_ARGV"; false; }
}

@test "7b the socket pid matching CC_TERM_KITTY_PID passes the pre-check and delivers" {
  CC_TERM_KITTY_TO="unix:/tmp/kitty-4242" CC_TERM_KITTY_PID=4242 run "$SHIM" session send -s 300 "hello"
  [ "$status" -eq 0 ]
  [ "$(sent)" = 1 ]
}
