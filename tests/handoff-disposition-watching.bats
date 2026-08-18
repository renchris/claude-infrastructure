#!/usr/bin/env bats
# 08c746312188 — the disposition helper cannot see the watcher the wake floor actually arms.
#
# scripts/handoff-disposition.sh answers await_ping_running by matching the session uuid in a process's
# ARGV: pgrep -f "cc-await-ping.*$uuid". hooks/session-continue.sh:595 arms the wake floor with NO id in
# argv, deliberately — the NO-ARG decision of 2026-07-31, so cc-await-ping derives ${ITERM_SESSION_ID##*:}
# itself and covers that key's whole set, making reader ⊇ writer by construction instead of by two hooks
# agreeing on a key. Both watcher forms run in this fleet simultaneously and one of them is invisible to
# the probe. await_ping_running goes false, one of seven stay-OPEN reasons goes with it, and a pane parked
# awaiting a peer is told it is close-eligible (docs/plans/LIVENESS_DETECTOR_FAILNEG.md row 3).
#
# The durable oracle is the one cc-await-ping itself maintains and session-continue.sh:594 already relies
# on: a <key>.watching marker rewritten under EVERY key of the set on every poll, and removed in the
# watcher's EXIT trap. It does not depend on how the watcher was invoked, which is the whole defect.
#
# It is not sufficient on its own either, and the DEAD-PID case below is why: a watcher killed with a
# signal that skips its EXIT trap strands the marker (session-continue.sh:298). A marker trusted blind
# would then hold a pane open forever — trading a pane that closes too early for one that never closes.
# So the marker counts only while the pid it names is alive, and the argv probe stays for the watcher
# forms that DO carry an id (the --sid idle-scoped arm under a live goal).
#
# Every assertion reads the FIELD, never the exit code alone: exit 1 is the OR of seven reasons, so an
# assertion on exit status could pass on a dirty tree while the signal under test stayed false.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HD="$REPO/scripts/handoff-disposition.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # never the operator's live ~/
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_TASKS_DIR="$BATS_TEST_TMPDIR/tasks"
  export CC_SESSIONS_BIN=/nonexistent
  mkdir -p "$CC_MAILBOX_DIR" "$CC_TASKS_DIR"
  CLEAN="$BATS_TEST_TMPDIR/clean"; mkdir -p "$CLEAN"
  U="UUID-WATCH"
}

# a pid that is certainly dead: spawn, reap, reuse the number.
dead_pid() { local p; ( : ) & p=$!; wait "$p" 2>/dev/null; echo "$p"; }

@test "the NO-ARG watcher is visible through its marker: armed -> await_ping_running true, stay OPEN" {
  # exactly what hooks/session-continue.sh:595 arms — nothing in argv names this session.
  printf 'pid=%s\n' "$$" > "$CC_MAILBOX_DIR/$U.watching"
  run bash "$HD" --cwd "$CLEAN" --session "$U"
  [ "$(echo "$output" | head -n1 | jq -r '.await_ping_running')" = "true" ]
  [ "$status" -eq 1 ]
}

@test "REMOVE HALF: no marker and no matching argv -> false (the signal is not a blanket true)" {
  run bash "$HD" --cwd "$CLEAN" --session "$U"
  [ "$(echo "$output" | head -n1 | jq -r '.await_ping_running')" = "false" ]
  [ "$status" -eq 0 ]
}

@test "REMOVE HALF: a STRANDED marker (watcher killed past its EXIT trap) does NOT hold the pane open" {
  # the failure mode a blindly-trusted marker would introduce: a pane that can never close.
  printf 'pid=%s\n' "$(dead_pid)" > "$CC_MAILBOX_DIR/$U.watching"
  run bash "$HD" --cwd "$CLEAN" --session "$U"
  [ "$(echo "$output" | head -n1 | jq -r '.await_ping_running')" = "false" ]
  [ "$status" -eq 0 ]
}

@test "REMOVE HALF: the marker is read PER SESSION — a sibling's watcher cannot hold this pane open" {
  # the mirror of the argv probe's own scoping comment: a global match would let any other session's
  # watcher pin this one open forever.
  printf 'pid=%s\n' "$$" > "$CC_MAILBOX_DIR/SOME-OTHER-UUID.watching"
  run bash "$HD" --cwd "$CLEAN" --session "$U"
  [ "$(echo "$output" | head -n1 | jq -r '.await_ping_running')" = "false" ]
  [ "$status" -eq 0 ]
}

@test "a malformed marker is not a verdict: no readable pid -> false, never a crash" {
  printf 'garbage\n' > "$CC_MAILBOX_DIR/$U.watching"
  run bash "$HD" --cwd "$CLEAN" --session "$U"
  [ "$(echo "$output" | head -n1 | jq -r '.await_ping_running')" = "false" ]
  [ "$status" -eq 0 ]
}
