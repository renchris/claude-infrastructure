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
  # THE BIND IS RELATIVE, AND THAT IS THE WHOLE POINT (item e1d43f93da19; this file is the 4th site
  # of that one defect, found 2026-08-09 by censusing the class instead of the file). Darwin caps
  # sun_path at 104 bytes against THE STRING HANDED TO bind(2), not the file's location, and $T here
  # is $BATS_TEST_TMPDIR — launchd's 49-byte TMPDIR plus postland's own 21-byte postland-run.XXXXXX
  # plus this suite's test names. Absolute, that overran the cap ONLY inside postland, so the suite
  # hand-checked green and still appeared in three postland reds. chdir + bind the basename spends
  # 10 bytes and lands the socket at the same absolute path.
  /usr/bin/python3 -c 'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)' "$1"
  [ -S "$1" ]
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

# ── --all (W2c): every live instance, for callers reconciling window ids across kitties ────────
# A window id restarts at 1 in every kitty, so a reconciler must address EVERY instance. Before
# W2c every argument was silently ignored: `--all` answered with one line and rc 0.

@test "--all lists two live instances, oldest first, rc 0" {
  mksock "$T/sock/kitty-2"
  mksock "$T/sock/kitty-1"
  printf '1 kitty 10:00\n2 kitty 2-01:00:00\n' > "$PS_TABLE"
  run "$BIN" --all
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'unix:%s\nunix:%s' "$T/sock/kitty-2" "$T/sock/kitty-1")" ]
}

@test "--all with no live instance -> rc 4, no output" {
  run "$BIN" --all
  [ "$status" -eq 4 ]
  [ -z "$output" ]
}

@test "--all skips a symlink, a plain file, and a pid whose comm is not kitty" {
  mksock "$T/sock/kitty-10"
  ln -s "$T/sock/kitty-10" "$T/sock/kitty-11"
  touch "$T/sock/kitty-12"
  mksock "$T/sock/kitty-13"
  printf '10 kitty 05:00\n11 kitty 06:00\n12 kitty 07:00\n13 zsh 08:00\n' > "$PS_TABLE"
  run "$BIN" --all
  [ "$status" -eq 0 ]
  [ "$output" = "unix:$T/sock/kitty-10" ]
}

@test "--all does NOT take the KITTY_LISTEN_ON fast path the glob does not see" {
  mksock "$T/sock/inherited"
  mksock "$T/sock/kitty-5"
  echo "5 kitty 05:00" > "$PS_TABLE"
  KITTY_LISTEN_ON="unix:$T/sock/inherited" run "$BIN" --all
  [ "$status" -eq 0 ]
  [ "$output" = "unix:$T/sock/kitty-5" ]
}

@test "an unknown argument is refused with rc 64 and names the argument" {
  mksock "$T/sock/kitty-6"
  echo "6 kitty 05:00" > "$PS_TABLE"
  run "$BIN" --bogus
  [ "$status" -eq 64 ]
  [[ "$output" == *"unknown argument --bogus"* ]]
}

@test "--help prints the usage header, rc 0" {
  run "$BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: cc-kitty-socket [--all"* ]]
}

# ── --unique (2026-10-08): discovery for callers with no terminal env must never pick one of two ──
# Window ids restart at 1 in every kitty, so "the oldest" of two live kitties is a guess about whose
# window N a caller means. bin/it2-kitty, bin/cc-pane and bin/cc-reaper ask --unique and treat any
# non-zero as "unknown" (nothing typed). Zero and one candidates share the default mode's rules.

@test "--unique with exactly one live kitty resolves it, rc 0" {
  mksock "$T/sock/kitty-30"
  echo "30 kitty 05:00" > "$PS_TABLE"
  run "$BIN" --unique
  [ "$status" -eq 0 ]
  [ "$output" = "unix:$T/sock/kitty-30" ]
}

@test "--unique with no live kitty -> rc 4, no output" {
  run "$BIN" --unique
  [ "$status" -eq 4 ]
  [ -z "$output" ]
}

@test "--unique with two live kitties refuses -> rc 5, no output (the default mode would pick one)" {
  mksock "$T/sock/kitty-31"
  mksock "$T/sock/kitty-32"
  printf '31 kitty 2-01:00:00\n32 kitty 10:00\n' > "$PS_TABLE"
  run "$BIN" --unique
  [ "$status" -eq 5 ]
  [ -z "$output" ]
}

@test "--unique counts a symlink to the live socket once, not as a second kitty" {
  mksock "$T/sock/kitty-33"
  ln -s "$T/sock/kitty-33" "$T/sock/kitty-34"
  printf '33 kitty 05:00\n34 kitty 05:00\n' > "$PS_TABLE"
  run "$BIN" --unique
  [ "$status" -eq 0 ]
  [ "$output" = "unix:$T/sock/kitty-33" ]
}

@test "--unique ignores the KITTY_LISTEN_ON fast path (its callers inherited nothing)" {
  mksock "$T/sock/inherited"
  mksock "$T/sock/kitty-35"
  mksock "$T/sock/kitty-36"
  printf '35 kitty 05:00\n36 kitty 06:00\n' > "$PS_TABLE"
  KITTY_LISTEN_ON="unix:$T/sock/inherited" run "$BIN" --unique
  [ "$status" -eq 5 ]
}
