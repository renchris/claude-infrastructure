#!/usr/bin/env bats
# land-lock.sh — repo-keyed landing serializer.
# Isolated via LAND_LOCK_DIR + LAND_LOG (both under BATS_TEST_TMPDIR); no real
# /tmp/land-lock-* or ~/.claude/land.log is touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LL="$REPO/scripts/land-lock.sh"
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export LAND_LOG="$BATS_TEST_TMPDIR/land.log"
  LOCK="$LAND_LOCK_DIR/lock.d"
}

teardown() {
  # kill any live sleep we parked in the lock
  if [ -f "$LOCK/pid" ]; then
    p="$(cat "$LOCK/pid" 2>/dev/null || true)"
    [ -n "$p" ] && kill "$p" 2>/dev/null || true
  fi
}

@test "propagates wrapped exit code 0" {
  run bash "$LL" -- bash -c 'exit 0'
  [ "$status" -eq 0 ]
}

@test "propagates wrapped exit code 7" {
  run bash "$LL" -- bash -c 'exit 7'
  [ "$status" -eq 7 ]
}

@test "runs the wrapped command (side effect observed)" {
  marker="$BATS_TEST_TMPDIR/ran"
  run bash "$LL" -- bash -c "touch '$marker'"
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
}

@test "LAND_SERIALIZE=off bypass: runs command, lock dir NOT created" {
  marker="$BATS_TEST_TMPDIR/ran-off"
  run env LAND_SERIALIZE=off bash "$LL" -- bash -c "touch '$marker'"
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
  [ ! -d "$LOCK" ]
}

@test "LIVE holder respected past TTL (never reaped) — exits 75, pid unchanged" {
  mkdir -p "$LOCK"
  sleep 30 & live=$!
  echo "$live" > "$LOCK/pid"
  run env LAND_LOCK_TTL=0 LAND_LOCK_WAIT=1 bash "$LL" -- bash -c 'exit 0'
  [ "$status" -eq 75 ]
  [ "$(cat "$LOCK/pid")" = "$live" ]
  kill "$live" 2>/dev/null || true
}

@test "DEAD holder reaped — acquires" {
  mkdir -p "$LOCK"
  # A crashed holder wrote pid+lstart then died. Capture lstart WHILE it is alive, then kill
  # it. Under load its pid may be recycled to a live process (kill -0 sees "alive"), but the
  # recorded lstart won't match the impostor → land-lock still identifies the ORIGINAL holder
  # as dead and reaps. The prior bare-pid fixture flaked exactly here (2026-07-25 land: not ok
  # 1081/1102 — recycled pid read as a live holder, gate wedged RED).
  sleep 5 & dead=$!
  lstart="$(ps -o lstart= -p "$dead" 2>/dev/null)"
  kill "$dead" 2>/dev/null || true; wait "$dead" 2>/dev/null || true
  echo "$dead" > "$LOCK/pid"
  printf '%s\n' "$lstart" > "$LOCK/lstart"
  run env LAND_LOCK_WAIT=5 bash "$LL" -- bash -c 'exit 0'
  [ "$status" -eq 0 ]
}

@test "recycled-pid holder reaped — lstart mismatch, deterministic (no load needed)" {
  mkdir -p "$LOCK"
  # Positive control for the pid-reuse fix, made DETERMINISTIC: the holder pid is genuinely
  # ALIVE (a live sleep), but the recorded lstart does NOT match it — exactly the state a
  # recycled pid produces. land-lock must treat the original holder as dead (lstart mismatch)
  # and reap + acquire, WITHOUT relying on the OS actually recycling a pid under load.
  sleep 30 & live=$!
  echo "$live" > "$LOCK/pid"
  printf '%s\n' "Thu Jan  1 00:00:00 2020" > "$LOCK/lstart"   # stale, non-matching lstart
  run env LAND_LOCK_WAIT=5 bash "$LL" -- bash -c 'exit 0'
  kill "$live" 2>/dev/null || true
  [ "$status" -eq 0 ]
}

@test "empty-pid stale reaped (old mtime) — acquires" {
  mkdir -p "$LOCK"
  touch -t 202001010000 "$LOCK"
  run env LAND_LOCK_WAIT=5 bash "$LL" -- bash -c 'exit 0'
  [ "$status" -eq 0 ]
}

# --- keying (G-P9-1): the lock must serialize ACROSS worktrees of one repo. This test
# deliberately does NOT override LAND_LOCK_DIR, so it exercises the real repo-keying that
# the other tests bypass. RED against `--show-toplevel` keying (two worktrees → two dirs).
@test "keying: two worktrees of one repo resolve the SAME lock dir (no LAND_LOCK_DIR override)" {
  unset LAND_LOCK_DIR

  scratch="$BATS_TEST_TMPDIR/scratch"
  git init -q "$scratch"
  git -C "$scratch" config user.email t@e.com
  git -C "$scratch" config user.name t
  echo base > "$scratch/base.txt"
  git -C "$scratch" add base.txt
  git -C "$scratch" commit -q -m base
  git -C "$scratch" worktree add -q "$BATS_TEST_TMPDIR/wtA" -b wtA
  git -C "$scratch" worktree add -q "$BATS_TEST_TMPDIR/wtB" -b wtB

  a="$(cd "$BATS_TEST_TMPDIR/wtA" && bash "$LL" --print-lock-dir)"
  b="$(cd "$BATS_TEST_TMPDIR/wtB" && bash "$LL" --print-lock-dir)"
  m="$(cd "$scratch" && bash "$LL" --print-lock-dir)"

  [ -n "$a" ]
  [ "$a" = "$b" ]     # two worktrees collide on ONE mutex (the fix)
  [ "$a" = "$m" ]     # the main checkout maps to the same mutex too
}

@test "keying: --print-lock-dir is a pure read (creates no lock dir)" {
  unset LAND_LOCK_DIR
  # Fresh scratch repo → its /tmp/land-lock-<hash> cannot pre-exist from a real land.
  scratch="$BATS_TEST_TMPDIR/pureread"
  git init -q "$scratch"
  git -C "$scratch" config user.email t@e.com
  git -C "$scratch" config user.name t
  echo base > "$scratch/base.txt"
  git -C "$scratch" add base.txt
  git -C "$scratch" commit -q -m base

  d="$(cd "$scratch" && bash "$LL" --print-lock-dir)"
  [ -n "$d" ]
  [ ! -d "$d" ]       # introspection must not litter /tmp
}
