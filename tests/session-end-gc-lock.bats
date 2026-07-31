#!/usr/bin/env bats
# session-end.sh — the version-GC lock must reclaim a DEAD holder and never steal from a live one.
#
# THE DEFECT (a15/D6). The GC took its mutex with a bare `mkdir "$lock_dir" || exit 0`, wrote a pid
# nothing ever read, and released it only via an `rm -rf` at the bottom of the block with no trap. A
# SIGKILL/OOM/reboot between the two orphans the dir permanently, and every later SessionEnd GC then
# does `mkdir → fail → exit 0`: a silent, permanent skip. The asymmetry is what makes it a defect
# rather than a preference — the dir is SHARED with claude-latest:96 (both are
# $HOME/.claude-versions/.cleanup_lock) and claude-latest reclaims it by pid-liveness, so one holder
# of the same mutex self-heals while the other wedges.
#
# WHY A pid+lstart TOKEN, AND WHOSE pid. `kill -0` alone convicts nothing when the OS recycles a dead
# holder's pid (the land-lock flake of 2026-07-25), so identity is pid+start-time. And the token must
# name THIS GC: the body runs in a backgrounded, disowned `( … ) &`, where bash 3.2's `$$` is the
# PARENT hook shell — which exits milliseconds later. Recording `$$` would publish an
# almost-immediately-dead pid and invite a peer to steal the lock from a live GC. Test 5 pins that.
#
# Hermetic: $HOME is fixtured (VERSIONS_DIR and the lock are both $HOME-derived) and `pgrep` is
# stubbed on PATH, so no real ~/.claude-versions is touched and no real process is probed.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-end.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  VD="$HOME/.claude-versions"
  LOCK="$VD/.cleanup_lock"
  mkdir -p "$VD" "$HOME/.claude/watchdog" "$HOME/.claude/logs"
  export CC_TMP_SWEEP_DIRS="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$CC_TMP_SWEEP_DIRS"

  # KEEP_COUNT=2 ⇒ GC_THRESHOLD=4, so seed 6 version dirs to make the GC do real work.
  for v in 1.0.1 1.0.2 1.0.3 1.0.4 1.0.5 1.0.6; do mkdir -p "$VD/$v"; done
  ln -sfn "$VD/1.0.6" "$VD/current"

  # pgrep stub: the GC calls `pgrep -f claude-versions/<v>` to skip in-use versions. Real pgrep would
  # scan the operator's live process table (and could match a real claude), so stub it to "no match".
  # PGREP_SLEEP holds the critical section open for the mid-run observations in tests 3 and 5.
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  cat > "$BIN/pgrep" <<'SH'
#!/bin/bash
[ -n "${PGREP_SLEEP:-}" ] && sleep "$PGREP_SLEEP"
exit 1
SH
  chmod +x "$BIN/pgrep"
  export PATH="$BIN:$PATH"
}

fire() { echo '{"session_id":"ZZZ"}' | bash "$HOOK"; }

# The GC is backgrounded+disowned, so the hook returns before it finishes. Wait on its OBSERVABLE
# product (version dirs pruned to KEEP_COUNT+current) rather than a fixed sleep.
wait_for_gc() { # $1=max deciseconds
  local i=0 n
  while [ "$i" -lt "${1:-100}" ]; do
    n=$(find "$VD" -maxdepth 1 -mindepth 1 -type d ! -name current ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -le 3 ] && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}

version_count() { find "$VD" -maxdepth 1 -mindepth 1 -type d ! -name current ! -name '.*' 2>/dev/null | wc -l | tr -d ' '; }

# The fixture's dead holder. The `kill` is GUARDED because the child may already be gone: under load
# this shell can be descheduled past the whole 1s lifetime, and once bash has REAPED the child a
# signal to it returns 1/ESRCH — an UNREAPED zombie still returns 0, so the window opens only after
# the reap, not merely after the exit. Unguarded, that non-final failure aborted the helper under
# bats' errexit and left `deadpid > "$LOCK/pid"` truncated EMPTY, so test 1 failed ~1-in-3 at
# loadavg 13 and never once in isolation — the fast path, child still alive, returns 0. Test 0 pins
# it. Killing a child that already died is a no-op for this helper's contract: it wants a dead pid.
deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; echo "$p"; }

@test "0: the deadpid fixture survives its child pre-deceasing the kill — the load flake" {
  # Replay the REAL helper text out of this very file. A hand-copied approximation would keep
  # passing after the line above drifted, which is the classic vacuous control.
  local real; real="$(grep -m1 '^deadpid()' "$BATS_TEST_FILENAME")"
  [ -n "$real" ] || { echo "could not extract the deadpid helper from $BATS_TEST_FILENAME"; false; }

  # Force the descheduled ordering deterministically instead of waiting for load to supply it: hold
  # the kill until the child is genuinely REAPED (kill -0 still succeeds on a zombie, so this spins
  # past the exit to the reap), then perform the REAL kill and report its REAL status.
  local shadow='kill() { local i=0; while builtin kill -0 "$1" 2>/dev/null; do sleep 0.05; i=$((i+1)); [ "$i" -lt 200 ] || { echo "harness: child never reaped" >&2; return 99; }; done; builtin kill "$@"; }'

  local out rc
  out="$(/bin/bash -c "set -e; $shadow
$real
deadpid" 2>&1)" && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || { echo "deadpid aborted (rc=$rc) once its child pre-deceased the kill: '$out'"; false; }
  [[ "$out" =~ ^[0-9]+$ ]] || { echo "deadpid emitted no pid under the forced race: '$out'"; false; }

  # POSITIVE CONTROL. Strip the guard back out and the SAME harness must convict — otherwise the
  # assertions above prove only that nothing was ever forced.
  local unguarded="${real/ || true; wait/; wait}"
  [ "$unguarded" != "$real" ] || { echo "control derivation failed — the guard is not where expected"; false; }
  local crc
  /bin/bash -c "set -e; $shadow
$unguarded
deadpid" >/dev/null 2>&1 && crc=0 || crc=$?
  [ "$crc" -ne 0 ] || { echo "POSITIVE CONTROL PASSED — the harness cannot see the defect it guards"; false; }
}

@test "1: a stale lock from a DEAD holder is reclaimed — the GC is not wedged forever" {
  mkdir -p "$LOCK"
  deadpid > "$LOCK/pid"                     # holder that no longer exists
  local before; before="$(version_count)"
  [ "$before" -eq 6 ] || { echo "fixture wrong: $before version dirs"; false; }
  fire
  wait_for_gc 100 || { echo "GC never ran — the dead holder's lock still wedges it (pre-fix behaviour)"; false; }
  [ "$(version_count)" -le 3 ] || { echo "GC ran but pruned nothing: $(version_count) left"; false; }
}

@test "2: a LIVE holder's lock is respected — the GC skips, never steals" {
  sleep 5 & local holder=$!
  mkdir -p "$LOCK"
  echo "$holder" > "$LOCK/pid"
  ps -o lstart= -p "$holder" > "$LOCK/lstart" 2>/dev/null || true
  fire
  sleep 1                                    # give the GC every chance to misbehave
  [ "$(version_count)" -eq 6 ] || { echo "GC pruned while a LIVE holder held the lock — the lock is not honoured"; kill "$holder" 2>/dev/null; false; }
  [ -d "$LOCK" ] || { echo "the live holder's lock dir was deleted"; kill "$holder" 2>/dev/null; false; }
  kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
}

@test "3: the lock is released on exit — no orphan left after a normal run" {
  fire
  wait_for_gc 100 || { echo "GC did not complete"; false; }
  # the trap releases on subshell exit; allow a beat for it to fire after the last prune
  local i=0
  while [ -d "$LOCK" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  [ ! -d "$LOCK" ] || { echo "lock dir orphaned after a clean run — no trap released it"; false; }
}

@test "4: a RECYCLED pid (live pid, lstart mismatch) is reclaimed, not treated as a live holder" {
  sleep 5 & local live=$!
  mkdir -p "$LOCK"
  echo "$live" > "$LOCK/pid"                 # pid IS alive...
  echo "Thu Jan  1 00:00:00 1970" > "$LOCK/lstart"   # ...but is not the process we recorded
  fire
  wait_for_gc 100 || { echo "a recycled-pid lock was mistaken for a live holder and wedged the GC"; kill "$live" 2>/dev/null; false; }
  [ "$(version_count)" -le 3 ] || { echo "GC did not prune"; kill "$live" 2>/dev/null; false; }
  kill "$live" 2>/dev/null || true; wait "$live" 2>/dev/null || true
}

@test "5: the recorded pid is the LIVE GC subshell, not the parent hook shell that already exited" {
  # THE SUBTLE ONE. On bash 3.2 `$$` in a `( … ) &` is the parent's pid and BASHPID does not exist.
  # The parent hook exits immediately, so a `$$` token would name a dead process for nearly the whole
  # critical section — and test 1's reclaim would then fire against a LIVE GC. Hold the section open
  # with a slow pgrep and assert the recorded holder is genuinely alive.
  export PGREP_SLEEP=1
  fire
  # wait for the lock to appear (the GC reaches it after the version-count check)
  local i=0
  while [ ! -f "$LOCK/pid" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  [ -f "$LOCK/pid" ] || { echo "lock pid file never appeared"; false; }
  local rec; rec="$(cat "$LOCK/pid" 2>/dev/null)"
  [[ "$rec" =~ ^[0-9]+$ ]] || { echo "recorded pid is not an integer: '$rec'"; false; }
  kill -0 "$rec" 2>/dev/null || {
    echo "recorded holder pid $rec is NOT alive while the critical section runs —"
    echo "a peer's stale-reap would steal this lock from a live GC (the \$\$-in-subshell trap)"
    false
  }
  wait_for_gc 200 || { echo "GC did not finish"; false; }
}

@test "6: release is owner-verified — our trap does not delete a lock that is no longer ours" {
  # Steal-then-double-release: if our lock is reclaimed and a peer takes its own, an unconditional
  # `rm -rf` on the way out would delete the PEER's live lock and admit a third holder. The trap
  # compares the recorded pid to ours first, so a foreign token survives our exit.
  export PGREP_SLEEP=1
  fire
  local i=0
  while [ ! -f "$LOCK/pid" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  [ -f "$LOCK/pid" ] || { echo "lock pid file never appeared"; false; }
  sleep 9 & local peer=$!
  echo "$peer" > "$LOCK/pid"                 # simulate a peer now owning the same dir
  ps -o lstart= -p "$peer" > "$LOCK/lstart" 2>/dev/null || true
  # Wait for the GC to actually FINISH (its observable product), then settle — never a fixed sleep.
  # A fixed `sleep 3` here made this test pass vacuously against the pre-fix control, which deletes
  # the peer's lock at ~4s: the assertion simply ran before the release did. Waiting on the product
  # and then giving the trap a settle window is what makes the RED real (verified: with the
  # unconditional `rm -rf` restored, the lock is GONE at t=4s and this test fails).
  wait_for_gc 200 || { echo "GC did not complete"; kill "$peer" 2>/dev/null; false; }
  sleep 2                                     # let the exiting subshell's release path run
  [ -d "$LOCK" ] || { echo "our trap deleted a lock owned by another pid — double-release hole open"; kill "$peer" 2>/dev/null; false; }
  [ "$(cat "$LOCK/pid" 2>/dev/null)" = "$peer" ] || { echo "peer token was clobbered"; kill "$peer" 2>/dev/null; false; }
  kill "$peer" 2>/dev/null || true; wait "$peer" 2>/dev/null || true
}
