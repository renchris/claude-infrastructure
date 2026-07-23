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
}

end_for() { echo "{\"session_id\":\"$1\"}" | bash "$HOOK"; }

seed_session() { # $1=sid
  echo 12345 > "$WD/$1.pid"
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
