#!/usr/bin/env bats
# The launchd wrapper OVERWRITES PATH, so every binary capacity-alarm.sh invokes must be reachable
# on the plist's own PATH string — not on an interactive shell's PATH.
#
# WHY THIS SUITE EXISTS (measured 2026-07-30, not hypothetical). The wrapper's PATH omitted
# /usr/sbin, where `sysctl` lives. launchd's own default PATH includes /usr/sbin, but the wrapper
# replaces it. Result: in every SCHEDULED run — never in a hand-run from a terminal, which is
# exactly why it survived review — three rungs failed open:
#     rung 1 swap · rung 3 kernel pressure · rung 5 compressor segments
# The 17:25:59Z scheduled row read pressure_level=null, seg_pct=null, swap_used_mb=0. That last one
# is the dangerous shape: `${SWAP_MB:-0}` renders an unreadable instrument as the HEALTHY value.
# A dead rung that reports OK is worse than no rung (memory feature-durability-mechanism-not-memory).
#
# This suite is the recurrence guard for the CLASS, not just for sysctl: it extracts the binaries
# the script actually calls and checks each against the plist's literal PATH.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PLIST="$REPO/launchd/com.claude.capacity-alarm.plist"
  SCRIPT="$REPO/scripts/capacity-alarm.sh"
}

# The literal PATH the job will run with, taken from the plist rather than restated here — a copy
# in the test could drift from the plist and pass while production is broken.
plist_path() {
  /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$PLIST" 2>/dev/null \
    | sed -n 's/.*export PATH="\([^"]*\)".*/\1/p'
}

@test "the plist exposes a parseable PATH override" {
  run plist_path
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "every binary capacity-alarm.sh invokes is reachable on the plist PATH" {
  local p; p="$(plist_path)"
  [ -n "$p" ] || { echo "could not parse PATH from plist"; false; }
  local missing=""
  # HOME is expanded by the wrapper's shell at runtime; expand it here the same way.
  p="${p//\$HOME/$HOME}"
  for bin in sysctl zprint vm_stat ps python3 top awk sed; do
    if ! env -i PATH="$p" HOME="$HOME" bash -c "command -v $bin" >/dev/null 2>&1; then
      missing="$missing $bin"
    fi
  done
  [ -z "$missing" ] || { echo "UNREACHABLE on the launchd PATH:$missing"; echo "PATH=$p"; false; }
}

@test "RED CONTROL: the pre-fix PATH (no /usr/sbin) really does hide sysctl" {
  # If this control ever passes, the environment changed and the suite above proves nothing —
  # a control that cannot fail is not a control.
  run env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" bash -c 'command -v sysctl'
  [ "$status" -ne 0 ]
}

@test "the three sysctl-backed rungs go SKIPPED, never healthy, when sysctl is unreachable" {
  # Prove the failure MODE, so a future PATH regression is loud rather than a silent green.
  # SEG_PCT must be empty (=> rung 5 skipped) rather than a fabricated 0.
  run env -i PATH="/usr/bin:/bin" HOME="$HOME" bash -c '
    '"$(sed -n '/^read_segments() {/,/^}/p' "$SCRIPT")"'
    read_segments && echo "RETURNED-A-VALUE" || echo "REFUSED"'
  [ "$output" = "REFUSED" ]
}

@test "sysctl is reachable on the CURRENT plist PATH (the actual fix)" {
  local p; p="$(plist_path)"; p="${p//\$HOME/$HOME}"
  run env -i PATH="$p" HOME="$HOME" bash -c 'command -v sysctl'
  [ "$status" -eq 0 ]
}
