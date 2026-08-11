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

@test "concurrent reap: 6 acquirers vs ONE dead lock ⇒ never two holders at once" {
  # THE MUTEX'S OWN FAILURE MODE, and the one no other test in this file can see: every test above
  # reaps with a SINGLE acquirer, so all of them pass against a reap that is not atomic. Pre-fix
  # (`rm -rf "$LOCK"; mkdir "$LOCK"`) six acquirers all judge the dead lock stale, all remove it and
  # several recreate it — 3 simultaneous holders measured — i.e. the serializer stops serializing in
  # exactly the crash-recovery case it exists for, and two lands run concurrently.
  #
  # The assertion is DIRECT mutual exclusion, not a timing proxy: the wrapped body claims a second,
  # independent directory and records a VIOLATION if that claim fails, so a second holder is
  # observed by construction rather than inferred. The acquisition tally is the non-vacuity control
  # — a run where nobody ever got the lock would trivially record zero violations too.
  #
  # TWO INSTRUMENTS MAKE IT DETERMINISTIC, because the defect is real but NARROW and a plain
  # 6-way launch does NOT reproduce it (measured: 1/1 spurious green against the pre-fix reap —
  # each acquirer's own git/shasum startup jitters arrivals by more than the window is wide, so
  # they serialize by luck). A test that only sometimes reproduces is not a control:
  #   · a SPIN BARRIER releases all six into land-lock within microseconds of each other, and
  #   · a slow `stat` shim widens the judge→reap window (the pre-fix code's `stat -f %m` sits
  #     between "this holder is dead" and `rm -rf`) from ~microseconds to ~200ms.
  # Neither instrument weakens the claim: the fix must hold for a window of ANY width, and under
  # the shim the FIXED path pays the same widening four times over (generation + staleness, twice)
  # — so this is the fix being tested at its most exposed, not at its most convenient.
  mkdir -p "$LOCK"
  echo 99998 > "$LOCK/pid"                       # dead holder (see the DEAD-holder test for why
  printf '%s\n' "$SENTINEL_LSTART" > "$LOCK/lstart"  # both branches of the rule reap it)

  excl="$BATS_TEST_TMPDIR/exclusive.d"
  viol="$BATS_TEST_TMPDIR/violations"
  acq="$BATS_TEST_TMPDIR/acquired"
  : > "$viol"; : > "$acq"

  body="$BATS_TEST_TMPDIR/body.sh"
  cat > "$body" <<BODY
#!/usr/bin/env bash
mkdir "$excl" 2>/dev/null || { echo VIOLATION >> "$viol"; exit 0; }
echo held >> "$acq"
sleep 0.3
rmdir "$excl"
BODY
  chmod +x "$body"

  # Window widener. Scoped to the acquirers' own PATH (set inside the runner), so bats' and git's
  # stat calls are untouched. Forwards verbatim to the real binary — an approximation here would
  # make the whole fixture vacuous.
  shimdir="$BATS_TEST_TMPDIR/shims"
  mkdir -p "$shimdir"
  cat > "$shimdir/stat" <<'SHIM'
#!/bin/bash
sleep 0.2
exec /usr/bin/stat "$@"
SHIM
  chmod +x "$shimdir/stat"

  # All job control lives in a CHILD shell, never in the bats body: a backgrounded job in a bats
  # test has twice produced a spurious `not ok` alongside the real `ok` (see the DEAD-holder test).
  go="$BATS_TEST_TMPDIR/go"
  runner="$BATS_TEST_TMPDIR/runner.sh"
  cat > "$runner" <<RUN
#!/usr/bin/env bash
export PATH="$shimdir:\$PATH"
for i in 1 2 3 4 5 6; do
  (
    while [ ! -f "$go" ]; do :; done      # spin, not sleep — a poll re-serializes the arrivals
    exec env LAND_LOCK_DIR="$LAND_LOCK_DIR" LAND_LOG="$LAND_LOG" LAND_LOCK_WAIT=90 \
      bash "$LL" -- bash "$body" >/dev/null 2>&1
  ) &
done
sleep 1                                    # let all six reach the barrier
: > "$go"
wait
RUN
  chmod +x "$runner"

  run bash "$runner"
  [ "$status" -eq 0 ]
  [ ! -s "$viol" ]                               # pre-fix: several VIOLATION lines
  [ "$(grep -c . "$acq")" -eq 6 ]                # …and all six still get their turn
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

# ── P4 defect 6: the verb allowlist (land-architecture-100p §5 P4 / §2.F) ────────────────────────
# MEASURED: 23 ledger rows are `exit 127` — agents guessing `land-lock.sh status`, which was not a
# verb and was therefore treated as PAYLOAD: the machine-wide mutex was TAKEN for the whole wait
# and only then did the exec fail. One such guess waited 2,777 s to run a command that does not
# exist, and every other lander on the box paid for that wait.

@test "verb guard: a guessed verb is REFUSED (64) and the mutex is never taken" {
  run bash "$LL" status
  [ "$status" -eq 64 ]
  [ ! -d "$LOCK" ]                                   # the whole point: no lock, not even briefly
  echo "$output" | grep -q "REFUSING before the lock is taken"
}

@test "verb guard: the refusal does NOT queue behind a live holder (the 2777s pathology)" {
  # THE DISCRIMINATOR. Refusing at all is cheap to fake; refusing WITHOUT WAITING is the fix. With
  # the lock held by a live process the pre-guard code path queued for LAND_LOCK_WAIT and then
  # exited 75 (or 127 on acquire) — here it must come back immediately with EX_USAGE.
  mkdir -p "$LOCK"
  sleep 30 & live=$!
  echo "$live" > "$LOCK/pid"
  ps -o lstart= -p "$live" > "$LOCK/lstart"
  start="$(date +%s)"
  run env LAND_LOCK_WAIT=30 bash "$LL" status
  elapsed="$(( $(date +%s) - start ))"
  [ "$status" -eq 64 ]
  [ "$elapsed" -lt 5 ]
  [ "$(cat "$LOCK/pid")" = "$live" ]                 # and it touched nothing
  kill "$live" 2>/dev/null || true
}

@test "verb guard: a real command is NEVER second-guessed (the guard cannot eat a payload)" {
  # The too-strong half. A guard keyed on a denylist of guessed words would be out-run by the next
  # guess; a guard keyed on resolvability could instead swallow a legitimate command. Both shapes
  # every real caller uses — a bare resolvable name and an absolute path — must still run.
  run bash "$LL" -- true
  [ "$status" -eq 0 ]
  run bash "$LL" -- /bin/echo hello
  [ "$status" -eq 0 ]
  echo "$output" | grep -q hello
}

# ── P4 defect 4: waiters are VISIBLE while they wait ─────────────────────────────────────────────
# MEASURED: land-lock logged only at timeout or the release EXIT trap, so a queued waiter wrote
# NOTHING until its wait resolved — three live waiters were observed with zero rows and all four
# rows then appeared at once on release. Waits of 98 / 665 / 2,362 / 5,536 s were invisible for
# exactly the interval in which someone would have wanted to know.

@test "waiters: a QUEUED waiter registers and gets a ledger row AT ACQUIRE-START, not at release" {
  mkdir -p "$LOCK"
  sleep 30 & live=$!
  echo "$live" > "$LOCK/pid"
  ps -o lstart= -p "$live" > "$LOCK/lstart"
  printf 'held-branch\n' > "$LOCK/branch"

  env LAND_LOCK_WAIT=8 bash "$LL" -- bash -c 'exit 0' >/dev/null 2>&1 &
  w=$!
  # Assert WHILE IT IS STILL WAITING — this is the whole defect. Poll rather than sleep-and-hope so
  # the test cannot pass on a slow box for the wrong reason.
  seen=0
  for _ in 1 2 3 4 5 6; do
    if grep -q '"event":"queued"' "$LAND_LOG" 2>/dev/null; then seen=1; break; fi
    sleep 1
  done
  [ "$seen" -eq 1 ]
  [ "$(env LAND_LOCK_WAIT=1 bash "$LL" --waiters | grep -c .)" -ge 1 ]
  # …and the holder is still holding, i.e. nothing about this resolved the wait.
  [ -d "$LOCK" ]

  wait "$w" 2>/dev/null || true
  kill "$live" 2>/dev/null || true
}

@test "waiters: an UNCONTENDED land registers nothing and adds no queue row (signal, not volume)" {
  # The negative control. A row per land would drown the signal this adds; only a lander that
  # actually had to WAIT may write one.
  run bash "$LL" -- bash -c 'exit 0'
  [ "$status" -eq 0 ]
  # (plain `if`, not `run !`: the latter needs bats_require_minimum_version 1.5.0, which would
  # change `run`'s semantics for the other 19 tests in this file to silence one warning.)
  if grep -q '"event":"queued"' "$LAND_LOG" 2>/dev/null; then false; fi
  [ ! -e "$LAND_LOCK_DIR/waiters" ] || [ -z "$(ls -A "$LAND_LOCK_DIR/waiters" 2>/dev/null)" ]
}

# ── P4 defect 5: an over-budget LIVE holder PAGES (H2 stands — it is never reaped) ───────────────
# MEASURED: holder pid 82031 held the mutex with ppid 1 (its owning session dead) and NOTHING
# anywhere raised a word, while the lands behind it waited 2,362 s and 5,536 s. H2 (never reap a
# live holder) is correct and unchanged; what was missing is its other half — if the machine will
# never take the lock back, a human has to be told.

@test "land-holder alarm: a LIVE holder past its budget emits a page — and is still NOT reaped" {
  mkdir -p "$LOCK"
  sleep 30 & live=$!
  echo "$live" > "$LOCK/pid"
  ps -o lstart= -p "$live" > "$LOCK/lstart"
  touch -t 202001010000 "$LOCK"          # deterministically past ANY budget; no sleep, no flake

  run env LAND_LOCK_SCAN="$LAND_LOCK_DIR" bash "$LL" --alarms
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"kind":"land-lock-hung"'
  echo "$output" | grep -q "\"recover_cmd\":\"ps -o pid,ppid,lstart,command -p $live\""
  # H2 UNWEAKENED, asserted rather than assumed: paging must not have become reaping.
  [ -d "$LOCK" ]
  [ "$(cat "$LOCK/pid")" = "$live" ]
  kill "$live" 2>/dev/null || true
}

@test "land-holder alarm: a live holder INSIDE its budget is SILENT (the alarm can not-fire)" {
  # An alarm that always fires carries the same zero bits as one that cannot fire. A backgrounded
  # land is the NORMAL shape on this box and is reparented to pid 1 exactly like a derelict one, so
  # the trigger is over-budget, not orphanhood — this control is what pins that.
  mkdir -p "$LOCK"
  sleep 30 & live=$!
  echo "$live" > "$LOCK/pid"
  ps -o lstart= -p "$live" > "$LOCK/lstart"

  run env LAND_LOCK_SCAN="$LAND_LOCK_DIR" bash "$LL" --alarms
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  kill "$live" 2>/dev/null || true
}

@test "land-holder alarm: a DEAD holder is not paged either — it is the reaper's business" {
  mkdir -p "$LOCK"
  echo 999999 > "$LOCK/pid"                       # a pid nothing can be
  printf '%s\n' "$SENTINEL_LSTART" > "$LOCK/lstart"
  touch -t 202001010000 "$LOCK"

  run env LAND_LOCK_SCAN="$LAND_LOCK_DIR" bash "$LL" --alarms
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
