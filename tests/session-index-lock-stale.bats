#!/usr/bin/env bats
# hooks/lib/session-index-helpers.sh — the mkdir lock must reclaim a dead holder (a15/D1) and must
# not report success without holding anything (a15/D3).
#
# THIS IS NOT A HYPOTHETICAL. `flock` is absent on macOS, so the mkdir fallback is the ONLY path
# taken, and it had no stale recovery at all — no TTL, no owner check, nothing in the repo removing
# the dir, and release only from an EXIT trap that SIGKILL skips. ~/.claude/session-index.lock.d was
# created 2026-04-09 23:47:50 and never removed. Split the live log at that instant:
#   "Indexed session"  1033 before → 0 after
#   "Sweep: indexed"   2889 before → 1 after
#   "lock held ..."     383 before → 8096 after
# Full session indexing was dead for 111 days while session-index-start.sh — the one writer that
# takes no lock — kept adding stub rows, so the DB mtime and its session count both looked healthy.
# Test 1 replays exactly that dir (empty, ancient) and proves it now self-heals.
#
# Hermetic: $HOME is fixtured, so SESSION_INDEX_LOCKFILE and the log are both under the test tmpdir.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  # shellcheck source=/dev/null
  source "$REPO/hooks/lib/session-index-helpers.sh"
  LOCKD="$HOME/.claude/session-index.lock.d"
  export SESSION_INDEX_LOCK_STALE_S=2      # keep the no-pid grace window testable
}

    # exit-safe: every step tolerated, so a already-reaped child cannot fail the calling test under
    # bats' errexit (a failure inside a helper is reported against the test in a confusing way).
deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; printf '%s\n' "$p"; }
age_dir() { touch -t "$(date -u -v-"${2}"S +%Y%m%d%H%M.%S)" "$1" 2>/dev/null || true; }

@test "1: the REAL April wedge — an empty, ancient lock dir is reclaimed, not honoured forever" {
  mkdir -p "$LOCKD"                      # exactly the live artifact: no pid file, no lstart
  age_dir "$LOCKD" 9600000               # ~111 days old
  # Called DIRECTLY, not via `run`: `run` executes in a subshell, so the lock state this test needs
  # to inspect (_SESSION_INDEX_LOCK_FD) would be discarded with that subshell.
  session_index_trylock || {
    echo "trylock REFUSED over 111-day-old debris — this is the 8096-skip outage, unfixed"
    false
  }
  [ "$_SESSION_INDEX_LOCK_FD" = "mkdir" ] || { echo "acquired but FD not marked mkdir: '$_SESSION_INDEX_LOCK_FD'"; false; }
  [ "$(cat "$LOCKD/pid")" = "$$" ] || { echo "acquirer did not record its own pid"; false; }
  session_index_unlock
}

@test "2: a lock held by a LIVE, identity-confirmed holder is never stolen" {
  sleep 5 & local holder=$!
  mkdir -p "$LOCKD"
  echo "$holder" > "$LOCKD/pid"
  ps -o lstart= -p "$holder" > "$LOCKD/lstart" 2>/dev/null || true
  run session_index_trylock
  [ "$status" -eq 1 ] || { echo "STOLE the lock from a live holder"; kill "$holder" 2>/dev/null; false; }
  [ "$(cat "$LOCKD/pid")" = "$holder" ] || { echo "live holder's token was clobbered"; kill "$holder" 2>/dev/null; false; }
  kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
}

@test "3: a DEAD holder's lock is reclaimed immediately — no TTL wait needed" {
  mkdir -p "$LOCKD"
  local dead; dead="$(deadpid)"
  printf '%s\n' "$dead" > "$LOCKD/pid"
  # fresh dir: only the pid-liveness check can justify reclaiming this, not age
  session_index_trylock || { echo "a dead holder's lock still blocked acquisition"; false; }
  session_index_unlock
}

@test "4: a RECYCLED pid (alive, lstart mismatch) is reclaimed — kill -0 alone is not identity" {
  sleep 5 & local live=$!
  mkdir -p "$LOCKD"
  echo "$live" > "$LOCKD/pid"
  echo "Thu Jan  1 00:00:00 1970" > "$LOCKD/lstart"
  run session_index_trylock
  [ "$status" -eq 0 ] || { echo "a recycled pid was mistaken for the original holder"; kill "$live" 2>/dev/null; false; }
  kill "$live" 2>/dev/null || true; wait "$live" 2>/dev/null || true
  session_index_unlock
}

@test "5: a FRESH no-pid dir is respected — a holder mid-acquire is never robbed" {
  mkdir -p "$LOCKD"                      # just created, token not yet written
  run session_index_trylock
  [ "$status" -eq 1 ] || { echo "robbed a peer that was milliseconds from writing its pid"; false; }
}

@test "6: release removes the dir AND its token (rm -rf, not rmdir — the dir is non-empty now)" {
  session_index_trylock
  [ -f "$LOCKD/pid" ] || { echo "no token written"; false; }
  session_index_unlock
  [ ! -d "$LOCKD" ] || {
    echo "lock dir survived release — `rmdir` cannot remove a dir containing our token, so the"
    echo "fix would have become the wedge it removes"
    false
  }
}

@test "7: release is owner-verified — a foreign token is not deleted" {
  session_index_trylock
  sleep 5 & local peer=$!
  echo "$peer" > "$LOCKD/pid"             # peer reclaimed and now owns this dir
  session_index_unlock
  [ -d "$LOCKD" ] || { echo "deleted a lock owned by another pid — double-release hole"; kill "$peer" 2>/dev/null; false; }
  kill "$peer" 2>/dev/null || true; wait "$peer" 2>/dev/null || true
}

@test "8: D3 — blocking lock TIMEOUT returns FAILURE, never 'proceeding anyway'" {
  # The old code returned 0 after 300 attempts while holding nothing, and returned BEFORE arming its
  # trap, so two callers could both believe they held the lock and write the DB concurrently.
  sleep 30 & local holder=$!
  mkdir -p "$LOCKD"
  echo "$holder" > "$LOCKD/pid"
  ps -o lstart= -p "$holder" > "$LOCKD/lstart" 2>/dev/null || true
  # Drive the real function with a patched attempt ceiling: 2 attempts exercises the timeout branch
  # without a 300-second test. STALE_S is pushed far out so the holder reads live, not reclaimable —
  # otherwise the reclaim would fire and we would never reach the timeout at all (a vacuous pass).
  local libcopy="$BATS_TEST_TMPDIR/lib.sh"
  sed 's/-ge 300 \]/-ge 2 ]/' "$REPO/hooks/lib/session-index-helpers.sh" > "$libcopy"
  run env HOME="$HOME" SESSION_INDEX_LOCK_STALE_S=99999 bash -c "
    source '$libcopy'
    session_index_lock
  "
  [ "$status" -eq 1 ] || {
    echo "blocking lock returned $status on timeout — a false 'I hold the lock' (pre-fix returned 0)"
    kill "$holder" 2>/dev/null; false
  }
  [ "$(cat "$LOCKD/pid")" = "$holder" ] || { echo "timeout path clobbered the live holder's token"; kill "$holder" 2>/dev/null; false; }
  kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
}

@test "9: acquiring, releasing and re-acquiring in sequence works (no self-wedge)" {
  session_index_trylock || { echo "first acquire failed"; false; }
  session_index_unlock
  session_index_trylock || { echo "re-acquire after a clean release failed — release is incomplete"; false; }
  session_index_unlock
  [ ! -d "$LOCKD" ]
}
