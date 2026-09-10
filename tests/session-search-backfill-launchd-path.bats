#!/usr/bin/env bats
# The weekly session-search backfill invokes its script through a SYMLINK, and the script derives
# its own repo root from $0 — so the invocation path is load-bearing, not cosmetic.
#
# WHY THIS SUITE EXISTS (measured 2026-09-09, not hypothetical). `~/.claude/bin/session-index-backfill.sh`
# is a symlink into another checkout. The script's line 10 is
#     SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# which does NOT resolve a symlink, so invoked by its link name SCRIPT_DIR became ~/.claude/bin and
# line 13's `source "$SCRIPT_DIR/lib/progress-ui.sh"` resolved to a path that does not exist. Every
# scheduled run since the job was registered died there; ~/.claude/logs/backfill-scheduled.log held
# that one error repeated and nothing else.
#
# It survived for months because of the SECOND defect, which is the one worth guarding: the old
# command ended `... 2>&1 | head -50 >> log`, so the pipeline's exit status was head's. A job that
# had never once succeeded reported exit 0 to launchd on every run — a dead rung reporting OK,
# which is worse than no rung (MEMORY.md alarm-polarity-and-attention-budget, claimed-vs-checked).
#
# Harness laws: L1 the command under test is EXTRACTED from the shipped plist, never restated here
# (a copy drifts and passes while production is broken); L2 both directions are asserted — reaching
# the script AND propagating a red — so neither "never runs" nor "always reports ok" can pass;
# L3 each pre-fix control replays the old invocation shape against the same fixture, so the suite
# shows the defect rather than only asserting its absence.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/logs" "$HOME/realrepo/scripts/lib"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PLIST="$REPO/launchd/com.claude.session-search-backfill.plist"
  LOG="$HOME/.claude/logs/backfill-scheduled.log"
}

# The literal command the job will run, taken from the plist itself.
plist_cmd() {
  /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$PLIST" 2>/dev/null
}

# The pre-fix invocation shape, replayed. One line, so inlining it is faithful and cannot rot.
# The tilde is DATA here, not a path this file dereferences: the string is handed to `bash -c`,
# which performs tilde expansion itself — exactly as /bin/bash -c did for the real plist. Cases
# 4 and 6 prove it empirically: both depend on it resolving to the test's own $HOME, and both
# pass. Rewriting it to $HOME would stop replaying the artifact, which is the point of the arm.
# shellcheck disable=SC2088  # replayed pre-fix artifact; expanded by `bash -c`, not by this file
old_cmd='~/.claude/bin/session-index-backfill.sh --quiet 2>&1 | head -50 >> ~/.claude/logs/backfill-scheduled.log'

# A stand-in for the real script: derives SCRIPT_DIR from $0 exactly as the subject does, sources a
# sibling that exists ONLY next to the real file, and exits with $FIXTURE_RC.
make_fixture() {
  local rc="${1:-0}"
  printf '%s\n' 'echo "progress-ui loaded"' > "$HOME/realrepo/scripts/lib/progress-ui.sh"
  cat > "$HOME/realrepo/scripts/session-index-backfill.sh" <<EOF
#!/bin/bash
# Mirrors the subject's line 8 and line 10 exactly. \`set -e\` is not decoration here: it is what
# makes the failed \`source\` FATAL, which is the whole behaviour under test. Measured on the real
# log — all 24 lines are that one error and nothing after it.
set -euo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
source "\$SCRIPT_DIR/lib/progress-ui.sh"
echo "BACKFILL-RAN"
exit $rc
EOF
  chmod +x "$HOME/realrepo/scripts/session-index-backfill.sh"
  ln -sf "$HOME/realrepo/scripts/session-index-backfill.sh" "$HOME/.claude/bin/session-index-backfill.sh"
}

@test "the plist exposes a parseable command" {
  run plist_cmd
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "the shipped plist is valid and its command is syntactically a shell program" {
  run plutil -lint "$PLIST"
  [ "$status" -eq 0 ]
  run bash -n -c "$(plist_cmd)"
  [ "$status" -eq 0 ]
}

@test "the command reaches the real script through the ~/.claude/bin symlink" {
  make_fixture 0
  run bash -c "$(plist_cmd)"
  [ "$status" -eq 0 ]
  grep -q 'BACKFILL-RAN' "$LOG"
}

@test "PRE-FIX CONTROL: the unresolved invocation never reaches the script at all" {
  make_fixture 0
  run bash -c "$old_cmd"
  # The script body never executed — SCRIPT_DIR resolved under ~/.claude/bin and the source died
  # under `set -e`. Asserted directly: a second `run` here would clobber the status being read.
  ! grep -q 'BACKFILL-RAN' "$LOG" || false
  # ...and the log DID capture the cause, so this is "never reached", not "produced no output".
  grep -q 'progress-ui' "$LOG"
}

@test "a failing job propagates its exit code, so launchd can see a red" {
  make_fixture 7
  run bash -c "$(plist_cmd)"
  [ "$status" -eq 7 ]
}

@test "PRE-FIX CONTROL: the old pipeline reported success over a job that failed" {
  make_fixture 7
  run bash -c "$old_cmd"
  [ "$status" -eq 0 ]
}

@test "the log carries a parseable verdict= token in both directions" {
  make_fixture 0
  run bash -c "$(plist_cmd)"
  grep -q 'verdict=ok ' "$LOG"
  make_fixture 7
  run bash -c "$(plist_cmd)"
  grep -q 'verdict=FAILED ' "$LOG"
}

# The subject is a symlink into a SEPARATE checkout, so "the other repo moved" is a real state, not
# a hypothetical — and the whole lesson of this defect is that a cross-repo break must be LOUD.
@test "a vanished cross-repo target fails loudly rather than silently" {
  make_fixture 0
  rm -f "$HOME/.claude/bin/session-index-backfill.sh"
  run bash -c "$(plist_cmd)"
  [ "$status" -ne 0 ]
  grep -q 'verdict=FAILED' "$LOG"
}

@test "a DANGLING cross-repo symlink also fails loudly" {
  make_fixture 0
  ln -sf "$HOME/gone/scripts/session-index-backfill.sh" "$HOME/.claude/bin/session-index-backfill.sh"
  run bash -c "$(plist_cmd)"
  [ "$status" -ne 0 ]
  grep -q 'verdict=FAILED' "$LOG"
}

@test "readlink -f is available and resolves a symlink on this platform" {
  make_fixture 0
  # Compare resolved-to-resolved: on Darwin /var is itself a symlink to private/var, so a literal
  # compare against $HOME/... fails on the instrument rather than on the subject.
  run readlink -f "$HOME/.claude/bin/session-index-backfill.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "$(readlink -f "$HOME/realrepo/scripts/session-index-backfill.sh")" ]
  [ -n "$output" ]
}
