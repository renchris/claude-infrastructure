#!/usr/bin/env bats
# session-end.sh — clean-exit cleanup of THIS session's watchdog + checkpoint state.
# On a clean SessionEnd the hook removes ~/.claude/watchdog/<sid>.{pid,id} and
# cp-<sid>.count so (1) the lead-crash-watchdog daemon takes its "pid file gone =>
# clean shutdown" branch instead of logging a false "LEAD CRASH" (previously 93% of
# ends), and (2) those per-session files stop accumulating unbounded — no reaper
# GCs that directory. A genuine crash skips SessionEnd, so its pid file survives and
# the crash is still detected + classified.
#
# Coverage: removes this sid's 3 files · leaves OTHER sessions' files · empty sid is a
# safe no-op · path-traversal sid is refused by the charset guard · logs "Session ended".

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-end.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  WD="$HOME/.claude/watchdog"
  mkdir -p "$WD" "$HOME/.claude/logs"
  export CC_TMP_SWEEP_DIRS="$BATS_TEST_TMPDIR/tmp"   # hermetic tmp sweep — never the real /tmp
  mkdir -p "$CC_TMP_SWEEP_DIRS"
}

end_for() { echo "{\"session_id\":\"$1\"}" | bash "$HOOK"; }

seed_session() { # $1=sid — LIVE pid so the background straggler sweep keeps it; only the ENDING
                 # session's own files are removed synchronously (by sid, regardless of liveness)
  echo $$     > "$WD/$1.pid"
  echo "$1"   > "$WD/$1.id"
  echo 3      > "$WD/cp-$1.count"
}

@test "clean exit removes this session's pid/id/cp-count" {
  seed_session AAA
  run end_for AAA
  [ "$status" -eq 0 ]
  [ ! -e "$WD/AAA.pid" ]
  [ ! -e "$WD/AAA.id" ]
  [ ! -e "$WD/cp-AAA.count" ]
}

@test "other sessions' files are untouched" {
  seed_session AAA
  seed_session BBB
  end_for AAA
  [ ! -e "$WD/AAA.pid" ]
  [ -e "$WD/BBB.pid" ]
  [ -e "$WD/BBB.id" ]
  [ -e "$WD/cp-BBB.count" ]
}

@test "empty session_id is a safe no-op (removes nothing)" {
  seed_session AAA
  echo '{}' | bash "$HOOK"
  [ -e "$WD/AAA.pid" ]
}

@test "path-traversal session_id is refused by the charset guard" {
  echo v > "$HOME/.claude/victim.pid"   # what '../victim' would resolve to from $WD
  echo '{"session_id":"../victim"}' | bash "$HOOK"
  [ -e "$HOME/.claude/victim.pid" ]     # guard refused the traversal -> survives
}

@test "still logs 'Session ended'" {
  end_for AAA
  grep -q 'Session ended' "$HOME/.claude/logs/sessions.log"
}

@test "reason=clear keeps the pidfile (process survives /clear — no team-archive regression)" {
  seed_session AAA
  echo '{"session_id":"AAA","reason":"clear"}' | bash "$HOOK"
  [ -e "$WD/AAA.pid" ]   # kept — /clear ends the sid but the process/pane live on
  [ -e "$WD/AAA.id" ]
}

@test "straggler sweep reaps dead-pid pairs + aged cp, keeps live + fresh" {
  echo $$     > "$WD/LIVE.pid"; echo LIVE > "$WD/LIVE.id"; echo 1 > "$WD/cp-LIVE.count"
  echo 999999 > "$WD/DEAD.pid"; echo DEAD > "$WD/DEAD.id"; echo 1 > "$WD/cp-DEAD.count"
  touch -t 202601010000 "$WD/cp-OLDORPHAN.count"   # aged orphan (no pid), > 2 days
  echo 1 > "$WD/cp-FRESH.count"                     # fresh orphan (no pid)
  : > "$CC_TMP_SWEEP_DIRS/handoff-selfclose-x.log"; touch -t 202601010000 "$CC_TMP_SWEEP_DIRS/handoff-selfclose-x.log"
  : > "$CC_TMP_SWEEP_DIRS/handoff-selfclose-fresh.log"
  end_for ZZZ
  sleep 1                                           # let the backgrounded sweep finish
  [ -e "$WD/LIVE.pid" ] && [ -e "$WD/LIVE.id" ] && [ -e "$WD/cp-LIVE.count" ]   # live kept
  [ ! -e "$WD/DEAD.pid" ] && [ ! -e "$WD/DEAD.id" ] && [ ! -e "$WD/cp-DEAD.count" ]  # dead reaped
  [ ! -e "$WD/cp-OLDORPHAN.count" ]                 # aged reaped
  [ -e "$WD/cp-FRESH.count" ]                       # fresh kept
  [ ! -e "$CC_TMP_SWEEP_DIRS/handoff-selfclose-x.log" ]      # aged tmp reaped
  [ -e "$CC_TMP_SWEEP_DIRS/handoff-selfclose-fresh.log" ]    # fresh tmp kept
}
