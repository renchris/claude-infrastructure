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
  # A recorded lstart NO live process can ever match (nothing on a booted box started in 2020
  # to the second). Shared by every dead/recycled-holder fixture so the two cannot drift.
  SENTINEL_LSTART='Thu Jan  1 00:00:00 2020'
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
  # NOTE: writes pid but NO lstart — so this covers the "nothing recorded ⇒ never stale"
  # branch. The lstart-MATCHES branch is covered by the producer round-trip test below.
  sleep 30 & live=$!
  echo "$live" > "$LOCK/pid"
  run env LAND_LOCK_TTL=0 LAND_LOCK_WAIT=1 bash "$LL" -- bash -c 'exit 0'
  [ "$status" -eq 75 ]
  [ "$(cat "$LOCK/pid")" = "$live" ]
  kill "$live" 2>/dev/null || true
}

@test "DEAD holder reaped — acquires" {
  mkdir -p "$LOCK"
  # A crashed holder wrote pid+lstart then died. The fixture forks NOTHING, kills nothing and
  # waits on nothing — every recorded flake of this test has been the fixture's own job
  # control, never land-lock:
  #   · `kill` returning 1 on a sleep that had already exited under load          (debc016f)
  #   · a backgrounded `sleep` making bats emit a spurious `not ok` ALONGSIDE the `ok` for a
  #     body that ran ONCE and passed (proven with a body-execution counter: 12 bodies, 12
  #     runs). Measured 5/12 when the `kill` follows the `&` immediately, 0/12 fork-free. The
  #     older shape scored 0/15 only because an intervening `ps` fork happened to space the
  #     `&` and the `kill` apart — timing nothing guarantees, and it still flaked the
  #     2026-07-25 land at load 21-26 (not ok 1081/1102).
  #     That spurious line alone refuses the push: the gate's verdict is `grep -c '^not ok'`
  #     (scripts/ship-land.sh), so ONE of them is a RED regardless of the retry passing.
  # Correctness does NOT depend on this pid being dead, which is why no live process is needed:
  #   pid dead (the usual case) → kill -0 fails                  → reaped
  #   pid happens to be live    → lstart is the SENTINEL, so it cannot match → reaped
  # Both branches reap, so there is no race left to lose.
  dead=99998
  echo "$dead" > "$LOCK/pid"
  printf '%s\n' "$SENTINEL_LSTART" > "$LOCK/lstart"
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
  printf '%s\n' "$SENTINEL_LSTART" > "$LOCK/lstart"           # stale, non-matching lstart
  run env LAND_LOCK_WAIT=5 bash "$LL" -- bash -c 'exit 0'
  kill "$live" 2>/dev/null || true
  [ "$status" -eq 0 ]
}

@test "LIVE holder with its REAL producer-written lstart is never reaped — exits 75" {
  # The CATASTROPHIC direction, and the only test where lstart is written by the real producer
  # (write_owner) instead of a fixture. If the recorded and the re-read lstart ever stop
  # comparing equal — a whitespace/format change on one side only, `$(cat)` swapped for `read`,
  # a `tr -s` added to one branch — land-lock would REAP A LIVE HOLDER and two lands would run
  # concurrently: precisely what the mutex exists to prevent. Every other test writes lstart by
  # hand or leaves it empty, so not one of them can catch that regression.
  #
  # NESTED rather than backgrounded (same reason as the DEAD-holder test above): the holder is
  # the OUTER land-lock, which is genuinely alive and blocked waiting on this probe, so the
  # fixture needs no `&`, no `kill` and no polling — nothing whose timing can flake.
  probe="$BATS_TEST_TMPDIR/probe.sh"
  cat > "$probe" <<'PROBE'
#!/usr/bin/env bash
# Runs while the OUTER land-lock holds the mutex, pid+lstart written by the real producer.
[ -s "$LOCK/pid" ]    || { echo "PRECOND-FAIL: producer wrote no pid";    exit 90; }
[ -s "$LOCK/lstart" ] || { echo "PRECOND-FAIL: producer wrote no lstart"; exit 91; }
env LAND_LOCK_WAIT=1 bash "$LL" -- bash -c 'exit 0'
echo "inner=$?"
PROBE
  export LOCK LL
  run bash "$LL" -- bash "$probe"
  [ "$status" -eq 0 ]                        # preconditions held; outer ran the probe
  [[ "$output" == *"inner=75"* ]] || false   # live holder respected ⇒ lstart round-tripped EQUAL
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
