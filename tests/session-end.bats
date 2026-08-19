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

# ── attribution on the sessions.log line (row b521cb445465) ───────────────────
# The line used to be a bare "[ts] Session ended": no sid, no reason, on a log
# where ~86% of such lines are PHANTOMS emitted by `claude mcp list` during
# SessionStart (reason=other, fresh random sid). That made a real session end
# indistinguishable from the phantom AND unattributable to a session — which is
# why an abrupt-death investigation could not name what closed the pane.
# ANTI-VACUITY: each case first asserts the log line exists at all, so a refactor
# that stopped writing it can never make these pass over nothing.

@test "session end line carries the sid that ended" {
  end_for AAA
  line=$(grep -F 'Session ended' "$HOME/.claude/logs/sessions.log" | tail -1)
  [ -n "$line" ] || false                       # anti-vacuity: the line was written
  case "$line" in *"sid=AAA"*) ;; *) false ;; esac
}

@test "session end line carries the reason, so the mcp-list phantom is separable" {
  echo '{"session_id":"PHANTOM1","reason":"other"}' | bash "$HOOK"
  line=$(grep -F 'Session ended' "$HOME/.claude/logs/sessions.log" | tail -1)
  [ -n "$line" ] || false                       # anti-vacuity
  case "$line" in *"reason=other"*) ;; *) false ;; esac
  case "$line" in *"sid=PHANTOM1"*) ;; *) false ;; esac
}

@test "missing sid/reason render as '-' so the fields are always parseable" {
  echo '{}' | bash "$HOOK"
  line=$(grep -F 'Session ended' "$HOME/.claude/logs/sessions.log" | tail -1)
  [ -n "$line" ] || false                       # anti-vacuity
  case "$line" in *"sid=-"*) ;; *) false ;; esac
  case "$line" in *"reason=-"*) ;; *) false ;; esac
}

@test "a newline in the sid cannot forge an extra log record" {
  # The property is RECORD integrity, not text absence: sanitation strips the
  # newline (and '=' and spaces) but legitimately keeps the letters, so the
  # forged words survive INSIDE the one legitimate record. What must never
  # happen is a second record, or a record whose line begins with the payload.
  log="$HOME/.claude/logs/sessions.log"
  : > "$log"                                    # anti-vacuity: known-empty baseline
  before=$(wc -l < "$log")
  printf '{"session_id":"EVIL\\nFORGED Session ended sid=victim"}' | bash "$HOOK"
  after=$(wc -l < "$log")
  [ "$((after - before))" -eq 1 ] || false      # exactly ONE record appended
  run grep -c '^FORGED' "$log"
  [ "$output" -eq 0 ] || false                  # payload never starts a record
  run grep -c '^\[' "$log"
  [ "$output" -eq 1 ] || false                  # exactly one timestamped record
}

@test "reason=clear still logs an attributed line (the process survives, the sid does not)" {
  seed_session AAA
  echo '{"session_id":"AAA","reason":"clear"}' | bash "$HOOK"
  line=$(grep -F 'Session ended' "$HOME/.claude/logs/sessions.log" | tail -1)
  [ -n "$line" ] || false                       # anti-vacuity
  case "$line" in *"sid=AAA"*) ;; *) false ;; esac
  case "$line" in *"reason=clear"*) ;; *) false ;; esac
  [ -e "$WD/AAA.pid" ] || false                 # and the pidfile is still kept
}

@test "stdin is consumed once — the sid still reaches the removal logic" {
  # Regression guard for the reordering: reading stdin at the top for the log line
  # must not starve the charset-guarded rm below. An empty second read EXITS 0, so
  # the `|| echo '{}'` fallback would NOT fire and the sid would silently blank.
  seed_session AAA
  run end_for AAA
  [ "$status" -eq 0 ]
  [ ! -e "$WD/AAA.pid" ] || false
  [ ! -e "$WD/AAA.id" ] || false
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
  [ -e "$WD/LIVE.pid" ] && [ -e "$WD/LIVE.id" ] && [ -e "$WD/cp-LIVE.count" ] || false # live kept
  [ ! -e "$WD/DEAD.pid" ] && [ ! -e "$WD/DEAD.id" ] && [ ! -e "$WD/cp-DEAD.count" ] || false # dead reaped
  [ ! -e "$WD/cp-OLDORPHAN.count" ]                 # aged reaped
  [ -e "$WD/cp-FRESH.count" ]                       # fresh kept
  [ ! -e "$CC_TMP_SWEEP_DIRS/handoff-selfclose-x.log" ]      # aged tmp reaped
  [ -e "$CC_TMP_SWEEP_DIRS/handoff-selfclose-fresh.log" ]    # fresh tmp kept
}
