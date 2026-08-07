#!/usr/bin/env bats
# boot-resume-launch.sh — the TTY-coupled resume seam (T-P16-2). The GUI drive (iTerm2) is not
# unit-testable, but --dry-run makes the command-construction (shell-quoting a spacey cwd, the
# osascript assembly, the reso-resume-one arg order) fully verifiable without a display.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LAUNCH="$REPO/scripts/boot-resume-launch.sh"
  export CC_RESUME_ONE_BIN="/Users/x/.reso/bin/reso-resume-one"
  # PIN THE TERMINAL. Since 2026-07-31 the script has a kitty arm, so every assertion below is
  # about the iTerm2 arm SPECIFICALLY — and this suite is now routinely run from inside kitty,
  # where an inherited KITTY_WINDOW_ID would otherwise decide the verdict. The kitty arm has its
  # own suite (tests/kitty-recovery-launch.bats).
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
}

@test "--help exits 0" {
  run bash "$LAUNCH" --help
  [ "$status" -eq 0 ]
}

@test "missing args → usage exit 2" {
  run bash "$LAUNCH"
  [ "$status" -eq 2 ]
}

@test "dry-run builds a reso-resume-one command with account, cwd, sid" {
  run bash "$LAUNCH" --dry-run next4 /Users/x/Development/.worktrees/wt-zeta sid-123
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "reso-resume-one"
  echo "$output" | grep -q "next4"
  echo "$output" | grep -q "/Users/x/Development/.worktrees/wt-zeta"
  echo "$output" | grep -q "sid-123"
  echo "$output" | grep -q "create window with default profile"
  echo "$output" | grep -q "write text"
}

@test "dry-run: a cwd with spaces stays single-quoted (survives the write-text shell)" {
  run bash "$LAUNCH" --dry-run next2 "/Users/x/My Worktrees/wt a" sid-x branchy
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "'/Users/x/My Worktrees/wt a'"
  echo "$output" | grep -q "branchy"      # optional branch arg carried through
}

@test "CC_LAUNCH_DRYRUN=1 env also triggers dry-run" {
  CC_LAUNCH_DRYRUN=1 run bash "$LAUNCH" next /tmp/wt sid9
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CMD:"
}

# ── DAEMON-CONTEXT DISPATCH (2026-08-07). Under launchd there is no terminal env at all, and
# until this date the fall-through was the iTerm2 arm + `open -a iTerm` — which RESURRECTED
# iTerm2 behind a kitty-fleet operator (03:51:18 that morning, 6 sessions fired into it while
# kitty held 153 panes). These tests pin both halves of the fix hermetically: the live-socket
# resolver (bin/cc-kitty-socket, fixtured via CC_KITTY_SOCKET_DIR/_PS) decides the absent-env
# case, and the iTerm2 arm REFUSES rather than launches.

@test "daemon context (no terminal env) + live kitty socket -> kitty arm" {
  unset IT2_WRAPPER_NO_KITTY KITTY_WINDOW_ID CC_TERM_KITTY_TO KITTY_LISTEN_ON
  mkdir -p "$BATS_TEST_TMPDIR/sock"
  python3 - "$BATS_TEST_TMPDIR/sock/kitty-42" <<'PY'
import socket, sys
socket.socket(socket.AF_UNIX).bind(sys.argv[1])
PY
  cat > "$BATS_TEST_TMPDIR/ps" <<'EOF'
#!/bin/bash
pid=""; col=""
while [ $# -gt 0 ]; do case "$1" in -p) pid="$2"; shift 2 ;; -o) col="$2"; shift 2 ;; *) shift ;; esac; done
[ "$pid" = "42" ] || exit 1
case "$col" in ucomm=) echo kitty ;; etime=) echo 05:00 ;; esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/ps"
  export CC_KITTY_SOCKET_DIR="$BATS_TEST_TMPDIR/sock" CC_KITTY_SOCKET_PS="$BATS_TEST_TMPDIR/ps"
  run bash "$LAUNCH" --dry-run next4 /tmp sid-dc1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^KITTY: '                  # dispatch chose kitty with no env at all
}

@test "daemon context + NO kitty anywhere + iTerm2 not running -> rc 3 refusal, app NEVER launched" {
  unset IT2_WRAPPER_NO_KITTY KITTY_WINDOW_ID CC_TERM_KITTY_TO KITTY_LISTEN_ON
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  export CC_KITTY_SOCKET_DIR="$BATS_TEST_TMPDIR/empty"
  # non-dry-run reaches the executable check on reso-resume-one BEFORE the terminal arm (its own
  # exit 3) — the suite's default CC_RESUME_ONE_BIN names a path that never exists, so give it a
  # real stub or this test asserts the WRONG exit-3.
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/rro"; chmod +x "$BATS_TEST_TMPDIR/rro"
  export CC_RESUME_ONE_BIN="$BATS_TEST_TMPDIR/rro"
  # the capacity gate sits ahead of the terminal arms — pin it ADMIT so this test reaches the
  # arm under any host load (it runs on the very box the load-781 incident melted)
  export CC_ADMIT_LOADAVG_OVERRIDE=1 CC_ADMIT_HEADROOM_OVERRIDE=64
  # osascript stub: the is-running probe answers NOTHING (iTerm2 down); every invocation is
  # recorded — reaching the window-creating payload would BE the defect being pinned.
  cat > "$BATS_TEST_TMPDIR/osa" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/osa.calls"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/osa"
  export CC_OSASCRIPT_BIN="$BATS_TEST_TMPDIR/osa"
  run bash "$LAUNCH" next4 /tmp sid-dc2
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'refusing to launch'
  [ -f "$BATS_TEST_TMPDIR/osa.calls" ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/osa.calls" | tr -d ' ')" -eq 1 ]   # the probe, and ONLY the probe
  grep -q 'is running' "$BATS_TEST_TMPDIR/osa.calls"                 # ...and it WAS the probe
}
