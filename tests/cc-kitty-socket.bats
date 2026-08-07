#!/usr/bin/env bats
# cc-kitty-socket — the daemon-context LIVE kitty detector behind terminal dispatch
# (boot-resume-launch.sh, lr-handoff.sh). Env inheritance is a sampling detector — launchd
# jobs carry no KITTY_WINDOW_ID — so this resolver is what stops autonomous spawns falling
# through to the iTerm2 arm while the fleet lives in kitty (the 2026-08-07 03:51 iTerm2
# resurrection). Hermetic: CC_KITTY_SOCKET_DIR replaces /tmp, CC_KITTY_SOCKET_PS replaces
# /bin/ps — the suite never reads the live process table and never touches a real socket.

setup() {
  # Terminal pinning (the #124 class): the SUBJECT branches on KITTY_LISTEN_ON, so the suite
  # must not inherit the developer's — a fast-path hit on a live socket would decide every test
  # by which terminal the developer is sitting in.
  unset KITTY_LISTEN_ON KITTY_WINDOW_ID CC_TERM_KITTY_TO
  # Fixture $HOME (hermeticity ratchet): the subject reads nothing under ~, but a suite that
  # inherits the live $HOME is one refactor away from doing so silently.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BIN="$REPO/bin/cc-kitty-socket"
  T="$BATS_TEST_TMPDIR"
  mkdir -p "$T/sock"
  # fake ps: answers `-p <pid> -o ucomm=` / `-o etime=` from a table of "<pid> <ucomm> <etime>"
  cat > "$T/ps" <<'EOF'
#!/bin/bash
pid=""; col=""
while [ $# -gt 0 ]; do case "$1" in -p) pid="$2"; shift 2 ;; -o) col="$2"; shift 2 ;; *) shift ;; esac; done
row="$(grep "^$pid " "$PS_TABLE" 2>/dev/null | head -1)"
[ -n "$row" ] || exit 1
case "$col" in
  ucomm=) printf '%s\n' "$row" | awk '{print $2}' ;;
  etime=) printf '%s\n' "$row" | awk '{print $3}' ;;
esac
EOF
  chmod +x "$T/ps"
  export CC_KITTY_SOCKET_DIR="$T/sock" CC_KITTY_SOCKET_PS="$T/ps" PS_TABLE="$T/table"
  : > "$PS_TABLE"
}

mksock() { # bind a real unix socket at $1 (a plain file must NOT count as a socket)
  python3 - "$1" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
PY
}

@test "no sockets at all -> rc 4, no output" {
  run "$BIN"
  [ "$status" -eq 4 ]
  [ -z "$output" ]
}

@test "one live kitty socket resolves to unix:<path>" {
  mksock "$T/sock/kitty-123"
  echo "123 kitty 05:00" > "$PS_TABLE"
  run "$BIN"
  [ "$status" -eq 0 ]
  [ "$output" = "unix:$T/sock/kitty-123" ]
}

@test "recycled pid (comm no longer kitty) marks a STALE socket file, not a terminal" {
  mksock "$T/sock/kitty-124"
  echo "124 zsh 05:00" > "$PS_TABLE"
  run "$BIN"
  [ "$status" -eq 4 ]
}

@test "dead pid (ps knows nothing) is skipped" {
  mksock "$T/sock/kitty-125"
  run "$BIN"
  [ "$status" -eq 4 ]
}

@test "a plain FILE named like a socket is not a socket" {
  touch "$T/sock/kitty-126"
  echo "126 kitty 05:00" > "$PS_TABLE"
  run "$BIN"
  [ "$status" -eq 4 ]
}

@test "non-numeric suffix is ignored" {
  mksock "$T/sock/kitty-abc"
  run "$BIN"
  [ "$status" -eq 4 ]
}

@test "two live instances: the OLDEST wins (the operator's login kitty, not a test instance)" {
  mksock "$T/sock/kitty-1"
  mksock "$T/sock/kitty-2"
  printf '1 kitty 2-01:00:00\n2 kitty 10:00\n' > "$PS_TABLE"
  run "$BIN"
  [ "$status" -eq 0 ]
  [ "$output" = "unix:$T/sock/kitty-1" ]
}

@test "KITTY_LISTEN_ON fast path wins when its socket is live" {
  mksock "$T/sock/inherited"
  KITTY_LISTEN_ON="unix:$T/sock/inherited" run "$BIN"
  [ "$status" -eq 0 ]
  [ "$output" = "unix:$T/sock/inherited" ]
}

@test "stale KITTY_LISTEN_ON (socket gone) falls through to the glob" {
  mksock "$T/sock/kitty-77"
  echo "77 kitty 03:00" > "$PS_TABLE"
  KITTY_LISTEN_ON="unix:$T/sock/gone" run "$BIN"
  [ "$status" -eq 0 ]
  [ "$output" = "unix:$T/sock/kitty-77" ]
}
