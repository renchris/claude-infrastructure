#!/usr/bin/env bats
# kitty socket discovery for callers with NO terminal environment (2026-10-08).
#
# The defect: scripts/limit-recover/lr-upgrade.sh runs under launchd (com.reso.lr-reset-poller) and
# asks `cc-resume-debt surface --pane N` before typing into an idle session. With no KITTY_* in the
# environment, cc-pane's `list` took the it2 shim's iTerm2 arm (exit 2 on a kitty box), surface read
# that as rc 3 "unknown", and the drain skipped every idle session: 149 skips against 10 upgrades in
# ~/.reso/limit-recover/upgrade-drain.log, 12 sessions stuck on an old Claude Code. The socket path
# embeds kitty's pid (unix:/tmp/kitty-<pid>), so it cannot be configured ahead of time.
#
# The fix: bin/cc-kitty-socket --unique (exactly one live kitty, else refuse), consulted by
# bin/cc-pane for its read verbs and by bin/it2-kitty when a CC_TERM=kitty caller names no socket.
#
# Every test runs the REAL chain — cc-resume-debt → cc-pane → it2-wrapper → it2-kitty →
# cc-kitty-socket — with only kitty, the iTerm2 CLI and ps faked. The socket is a real unix socket
# bound in the test tmpdir (CC_KITTY_SOCKET_DIR); the live /tmp is never globbed.
#
# RED-proof: on the pre-fix tree (44b261af4) "one live kitty, no terminal env: surface rc 0" fails
# with status 3, and "it2-kitty with CC_TERM=kitty and no socket discovers it" fails with status 4.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$BATS_TEST_TMPDIR"
  # The launchd shape: no terminal identity of any kind, and no switch or seam inherited from the
  # developer's pane (an agent running this from kitty carries all of these).
  unset KITTY_LISTEN_ON KITTY_WINDOW_ID KITTY_PID CC_TERM CC_TERM_KITTY_TO ITERM_SESSION_ID
  unset IT2_WRAPPER_NO_KITTY CC_PANE_KITTY_DISCOVER CC_KITTY_SOCKET_BIN CC_PANE_DRIVER CC_PANE_ID
  unset CC_RESUME_DEBT_PANE_BIN

  # The shim as deployed: ~/.claude/bin/it2 is a COPY of it2-wrapper that resolves its kitty
  # siblings next to itself.
  D="$T/bin"; mkdir -p "$D"
  cp "$REPO/bin/it2-wrapper" "$D/it2"
  for f in it2-kitty cc-in-kitty cc-kitty-socket; do cp "$REPO/bin/$f" "$D/$f"; done
  chmod +x "$D"/*
  export CC_PANE_IT2="$D/it2"

  # iTerm2's CLI on a kitty box: nothing to talk to.
  ITERM_LOG="$T/iterm-was-driven"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 2\n' "$ITERM_LOG" > "$T/fake-it2"
  chmod +x "$T/fake-it2"
  export IT2_WRAPPER_REAL="$T/fake-it2"

  # kitty: records every call (with its --to address) and answers `ls` with windows 2 and 5.
  KITTY_LOG="$T/kitty-was-driven"
  cat > "$T/fake-kitty" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$KITTY_LOG"
case "\$*" in
  *" ls"*) printf '[{"id":1,"is_focused":true,"tabs":[{"id":1,"is_focused":true,"windows":[{"id":2,"title":"a","is_focused":true,"cwd":"/","pid":11,"foreground_processes":[]},{"id":5,"title":"b","is_focused":false,"cwd":"/","pid":12,"foreground_processes":[]}]}]}]\n' ;;
esac
exit 0
EOF
  chmod +x "$T/fake-kitty"
  export CC_TERM_KITTY="$T/fake-kitty"

  # cc-kitty-socket's own seams: a private socket dir and a ps answering from a table.
  mkdir -p "$T/sock"
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

  RD="$REPO/bin/cc-resume-debt"
  export CC_RESUME_DEBT_DIR="$T/rd"
}

# A real unix socket, bound relative to its dir (Darwin's 104-byte sun_path cap applies to the
# string handed to bind(2); see tests/cc-kitty-socket.bats).
live_kitty() { # $1=pid
  /usr/bin/python3 -c 'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)' "$T/sock/kitty-$1"
  printf '%s kitty 1-00:00:00\n' "$1" >> "$PS_TABLE"
}

@test "one live kitty, no terminal env: surface of a listed pane is rc 0, addressed at that socket" {
  live_kitty 4242
  run "$RD" surface --pane 2
  [ "$status" -eq 0 ] || { echo "status=$status $output"; cat "$KITTY_LOG" 2>/dev/null; false; }
  grep -q -- "--to unix:$T/sock/kitty-4242 ls" "$KITTY_LOG"
}

@test "one live kitty: a pane kitty does not list is rc 1 (absent), not unknown" {
  live_kitty 4242
  run "$RD" surface --pane 99
  [ "$status" -eq 1 ]
}

@test "no live kitty: surface stays unknown (rc 3) and kitty is never driven" {
  run "$RD" surface --pane 2
  [ "$status" -eq 3 ]
  [ ! -s "$KITTY_LOG" ] || { cat "$KITTY_LOG"; false; }
}

@test "two live kitties: ambiguous stays unknown (rc 3) and neither is driven" {
  live_kitty 4242
  live_kitty 4343
  run "$RD" surface --pane 2
  [ "$status" -eq 3 ]
  [ ! -s "$KITTY_LOG" ] || { cat "$KITTY_LOG"; false; }
}

@test "a genuine iTerm2 pane (UUID session id) is never diverted to a discovered kitty" {
  live_kitty 4242
  ITERM_SESSION_ID="w0t0p0:8A2F1C3E-1111-4222-8333-444455556666" run "$RD" surface --pane 2
  [ "$status" -eq 3 ]
  [ ! -s "$KITTY_LOG" ] || { cat "$KITTY_LOG"; false; }
  [ -s "$ITERM_LOG" ]
}

@test "kitty-setup's synthetic numeric ITERM_SESSION_ID is not an iTerm2 identity" {
  live_kitty 4242
  ITERM_SESSION_ID="w0t0p0:50" run "$RD" surface --pane 2
  [ "$status" -eq 0 ]
}

@test "CC_PANE_KITTY_DISCOVER=off restores the old unknown" {
  live_kitty 4242
  CC_PANE_KITTY_DISCOVER=off run "$RD" surface --pane 2
  [ "$status" -eq 3 ]
  [ ! -s "$KITTY_LOG" ] || { cat "$KITTY_LOG"; false; }
}

@test "an ACTING verb discovers nothing: env-less cc-pane send never reaches kitty" {
  live_kitty 4242
  run "$REPO/bin/cc-pane" send 2 "hello"
  [ "$status" -ne 0 ]
  [ ! -s "$KITTY_LOG" ] || { cat "$KITTY_LOG"; false; }
}

@test "it2-kitty with CC_TERM=kitty and no socket discovers the one live kitty" {
  live_kitty 4242
  CC_TERM=kitty run "$D/it2-kitty" session list
  [ "$status" -eq 0 ] || { echo "status=$status $output"; false; }
  grep -q -- "--to unix:$T/sock/kitty-4242 ls" "$KITTY_LOG"
}

@test "it2-kitty with CC_TERM=kitty and two live kitties refuses (rc 4) without driving either" {
  live_kitty 4242
  live_kitty 4343
  CC_TERM=kitty run "$D/it2-kitty" session list
  [ "$status" -eq 4 ]
  [ ! -s "$KITTY_LOG" ] || { cat "$KITTY_LOG"; false; }
}
