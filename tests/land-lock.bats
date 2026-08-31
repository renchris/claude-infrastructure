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

# ── {pid,lstart} IDENTITY IS LOCALE- AND TZ-PINNED (the C31/C33 class) ──────────────────────────
# `ps -o lstart=` renders through LC_TIME and TZ, so the SAME live pid reads as two different
# strings to two different readers, and an unequal string means "pid recycled ⇒ reap" — on the
# LANDING mutex. Every case below drives a STUBBED `ps`, never /bin/ps: the real binary shows the
# skew only on a non-C-locale box, so a real-ps test silently no-ops on a C-locale machine and
# certifies nothing. The stub is the whole instrument, so the fixtures are written THROUGH it.
stub_locale_ps() { # <mode: skew|blind|stranger> — install a $PATH `ps` emulating the hazard
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  cat > "$STUB/ps" <<PS
#!/bin/bash
q=
for a in "\$@"; do [ "\$a" = "lstart=" ] && q=1; done
[ -n "\$q" ] || exec /bin/ps "\$@"          # every other ps query (ppid=, …) is the real one
case "$1" in
  blind)    exit 0 ;;                        # the instrument cannot be read at all
  stranger) printf 'Thu Jan  1 00:00:00 2020    \n' ;;   # a genuinely different start instant,
                                             # rendered identically in BOTH locales
  *) if [ "\${LC_ALL:-}" = "C" ]; then printf 'Fri Aug 21 13:45:22 2026    \n'
     else                              printf 'Fri 21 Aug 06:45:22 2026    \n'; fi ;;
esac
PS
  chmod +x "$STUB/ps"
}

@test "C31: a LIVE holder recorded in a DIFFERENT locale is NEVER reaped (H2 over the land mutex)" {
  # The bug: a holder records `Fri Aug 21 …` (C — launchd, or any of the 5 scripts that
  # `export LC_ALL=C`); a session reads `Fri 21 Aug …`; the strings differ; the reader concludes
  # the pid was recycled by a stranger, reaps the LANDING mutex, and two lands run at once — the
  # rebase-drop incident .claude/CLAUDE.md opens with.
  mkdir -p "$LOCK"
  sleep 30 & live=$!
  echo "$live" > "$LOCK/pid"
  stub_locale_ps skew
  # The record is written THROUGH the stub, so the fixture cannot drift from the instrument.
  LC_ALL=C "$STUB/ps" -o lstart= -p "$live" > "$LOCK/lstart"
  [ -s "$LOCK/lstart" ]                                    # armed, not silently empty
  # …and read back by a session-shaped environment, which renders the same instant day-first.
  # UNSET rather than set-empty: `LC_ALL= cmd` is SC1007 and the gate is right to call it a typo.
  run env -u LC_ALL -u LC_TIME LANG=en_CA.UTF-8 PATH="$STUB:$PATH" \
      LAND_LOCK_TTL=0 LAND_LOCK_WAIT=1 bash "$LL" -- bash -c 'exit 0'
  [ "$status" -eq 75 ]                                     # queued behind the live holder
  [ "$(cat "$LOCK/pid")" = "$live" ]                       # …and did NOT steal the lock
  kill "$live" 2>/dev/null || true
}

@test "C33: an UNREADABLE lstart instrument does not convict a LIVE holder, at ANY age" {
  # `ps` returning nothing for a pid `kill -0` has just proved alive is a FAILED PROBE, not a
  # stranger. Pre-fix the empty reading fell through `rec != cur` straight into the reap branch, so
  # the one condition under which NOTHING is known was the one that produced two live landers.
  # H2 DIVERGES from postland-verify's twin here deliberately: that one bounds the honour by TTL,
  # this one never reaps a live holder at any age — a wedged land costs a wait, a dropped commit
  # costs the commit. lock_alarm_rows is what reaches a human instead (asserted below).
  mkdir -p "$LOCK"
  sleep 30 & live=$!
  echo "$live" > "$LOCK/pid"
  printf 'Fri Aug 21 13:45:22 2026\n' > "$LOCK/lstart"
  stub_locale_ps blind
  run env PATH="$STUB:$PATH" LAND_LOCK_TTL=0 LAND_LOCK_WAIT=1 bash "$LL" -- bash -c 'exit 0'
  [ "$status" -eq 75 ]
  [ "$(cat "$LOCK/pid")" = "$live" ]
  kill "$live" 2>/dev/null || true
}

@test "C31: --alarms can still SEE a cross-locale live holder (the page is not silenced)" {
  # The second consumer, and the one whose failure is silent: lock_alarm_rows does
  # `holder_live "$d" || continue`, so a holder misjudged as not-live is SKIPPED — the over-budget
  # page that is H2's other half never fires, and the wedge reaches nobody.
  mkdir -p "$LOCK"
  sleep 30 & live=$!
  echo "$live" > "$LOCK/pid"
  stub_locale_ps skew
  LC_ALL=C "$STUB/ps" -o lstart= -p "$live" > "$LOCK/lstart"
  touch -t 202001010000 "$LOCK"                            # past budget
  run env -u LC_ALL -u LC_TIME LANG=en_CA.UTF-8 PATH="$STUB:$PATH" \
      LAND_LOCK_SCAN="$LAND_LOCK_DIR" bash "$LL" --alarms
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"kind":"land-lock-hung"'
  # H2 UNWEAKENED, asserted rather than assumed: paging must not have become reaping.
  [ "$(cat "$LOCK/pid")" = "$live" ]
  kill "$live" 2>/dev/null || true
}

@test "C31 control: a GENUINE stranger is still reaped — the fix left survivors" {
  # DISCRIMINATING arm, green on BOTH sides of the fix by design. Its job is not to red: it is to
  # prove the cure was not "honour everything", which is the way this class is usually over-fixed.
  # The stub renders a different start INSTANT identically in both locales, so the mismatch is real
  # and neither the canonical compare nor the ambient fallback can launder it.
  mkdir -p "$LOCK"
  sleep 30 & live=$!
  echo "$live" > "$LOCK/pid"
  stub_locale_ps stranger
  printf '%s\n' "$SENTINEL_LSTART" > /dev/null              # the sentinel's shape, rendered by the stub
  printf 'Fri Aug 21 13:45:22 2026\n' > "$LOCK/lstart"      # ≠ what the stub reports for this pid
  marker="$BATS_TEST_TMPDIR/stranger-ran"
  run env PATH="$STUB:$PATH" LAND_LOCK_TTL=0 LAND_LOCK_WAIT=1 bash "$LL" -- bash -c "touch '$marker'"
  [ "$status" -eq 0 ]                                       # reaped and acquired
  [ -f "$marker" ]
  [ "$(cat "$LOCK/pid")" != "$live" ]
  kill "$live" 2>/dev/null || true
}

@test "C31 migration: a PRE-FIX record (ambient rendering) is honoured by the canonical reader" {
  # Load-bearing, not defensive. A lock already on disk carries the OLD ambient rendering, which
  # does NOT equal the new canonical one (measured on this box: `Fri 21 Aug 06:46:23 2026` vs
  # `Fri Aug 21 13:46:23 2026`). A canonical-ONLY reader would reap exactly one live holder on the
  # way in — the fix committing the bug it removes. Deleting the ambient fallback in
  # lstart_matches turns THIS case red while every other case above stays green, which is what
  # makes it a per-site assertion rather than a restatement of the locale case.
  mkdir -p "$LOCK"
  sleep 30 & live=$!
  echo "$live" > "$LOCK/pid"
  stub_locale_ps skew
  env -u LC_ALL "$STUB/ps" -o lstart= -p "$live" > "$LOCK/lstart"   # the PRE-FIX writer's dialect
  grep -q 'Fri 21 Aug' "$LOCK/lstart"                       # the fixture really is the old shape
  run env -u LC_ALL -u LC_TIME LANG=en_CA.UTF-8 PATH="$STUB:$PATH" \
      LAND_LOCK_TTL=0 LAND_LOCK_WAIT=1 bash "$LL" -- bash -c 'exit 0'
  [ "$status" -eq 75 ]
  [ "$(cat "$LOCK/pid")" = "$live" ]
  kill "$live" 2>/dev/null || true
}

# ── PORTABLE stat — BOTH PLATFORM DIRECTIONS, DRIVEN ─────────────────────────────────────────────
# scripts/land-lock.sh § PORTABLE stat. The file read every mtime through a bare BSD `stat -f %m`
# with a `|| echo <default>` fallback that CANNOT fire on Linux: GNU's `-f` is --file-system, so it
# prints a filesystem report on stdout and exits 1, and `|| echo` does not replace stdout already
# written. Four of the five sites feed that capture to arithmetic, where `set -u` makes the report's
# first bare word fatal. MEASURED 2026-08-31 (Ubuntu, GNU coreutils 9.4): the real script, outside
# any harness, over a lock dir holding a dead pid — `line 305: File: unbound variable`, rc 1. The
# machine-wide landing mutex could not be acquired AT ALL on Linux once the lock directory existed.
#
# These cases STUB `stat` rather than trusting the box, so each platform's direction is exercised on
# BOTH platforms — the whole defect was one platform's behaviour being invisible from the other.
# `_real_mtime` resolves the box's own answer without assuming which stat this box ships.
_real_mtime() {  # <path> → epoch seconds, whichever stat this box has
  local m
  m="$(/usr/bin/stat -c %Y "$1" 2>/dev/null || true)"
  case "$m" in ''|*[!0-9]*) m="$(/usr/bin/stat -f %m "$1" 2>/dev/null || true)" ;; esac
  case "$m" in ''|*[!0-9]*) m=0 ;; esac
  printf '%s' "$m"
}

# stat_stub <gnu|bsd> — a $PATH `stat` with exactly one platform's flag semantics.
stat_stub() {
  SSTUB="$BATS_TEST_TMPDIR/statstub.$1"; mkdir -p "$SSTUB"
  if [ "$1" = gnu ]; then
    cat > "$SSTUB/stat" <<'GNU'
#!/bin/bash
# GNU: -c is the format flag; -f is --file-system and prints a REPORT on stdout, then exits 1.
case "${1:-}" in
  -c) case "$2" in %Y) exec /usr/bin/stat -c %Y "$3" ;; %i) exec /usr/bin/stat -c %i "$3" ;; esac ;;
  -f) printf '  File: "%s"\n    ID: 0 Namelen: 255 Type: ext2/ext3\nInodes: Total: 1 Free: 1\n' "${3:-}"
      printf 'stat: cannot read file system information\n' >&2; exit 1 ;;
esac
exec /usr/bin/stat "$@"
GNU
  else
    cat > "$SSTUB/stat" <<'BSD'
#!/bin/bash
# BSD/macOS: there is no -c at all; -f takes a format.
case "${1:-}" in
  -c|-c*) printf 'stat: illegal option -- c\n' >&2; exit 1 ;;
  -f) case "$2" in
        %m) v="$(/usr/bin/stat -c %Y "$3" 2>/dev/null)" ;;
        %i) v="$(/usr/bin/stat -c %i "$3" 2>/dev/null)" ;;
        *)  printf 'stat: bad format\n' >&2; exit 1 ;;
      esac
      [ -n "$v" ] || exit 1; printf '%s\n' "$v"; exit 0 ;;
esac
exec /usr/bin/stat "$@"
BSD
  fi
  chmod +x "$SSTUB/stat"
}

@test "portable stat: the GNU direction — a DEAD holder is reaped, not a fatal unbound variable" {
  stat_stub gnu
  # the stub really is GNU-shaped: -c answers, -f writes to STDOUT and fails
  run env PATH="$SSTUB:$PATH" stat -c %Y "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = "$(_real_mtime "$BATS_TEST_TMPDIR")" ]
  run env PATH="$SSTUB:$PATH" stat -f %m "$BATS_TEST_TMPDIR"
  [ "$status" -ne 0 ]
  [ -n "$output" ]

  mkdir -p "$LOCK"
  echo 999999 > "$LOCK/pid"                       # a pid no live process holds
  echo "$SENTINEL_LSTART" > "$LOCK/lstart"
  run env PATH="$SSTUB:$PATH" LAND_LOCK_WAIT=1 bash "$LL" -- bash -c 'exit 0'
  [ "$status" -eq 0 ]
  # the pre-fix shape is what this case exists to keep out, so name it rather than only the rc
  run bash -c "printf '%s' \"\$1\" | grep -c 'unbound variable'" _ "$output"
  [ "$output" = "0" ]
}

@test "portable stat: the BSD direction is unbroken — the fleet's platform still reaps" {
  stat_stub bsd
  # the stub really is BSD-shaped: -c is refused, -f answers
  run env PATH="$SSTUB:$PATH" stat -c %Y "$BATS_TEST_TMPDIR"
  [ "$status" -ne 0 ]
  run env PATH="$SSTUB:$PATH" stat -f %m "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = "$(_real_mtime "$BATS_TEST_TMPDIR")" ]

  mkdir -p "$LOCK"
  echo 999999 > "$LOCK/pid"
  echo "$SENTINEL_LSTART" > "$LOCK/lstart"
  run env PATH="$SSTUB:$PATH" LAND_LOCK_WAIT=1 bash "$LL" -- bash -c 'exit 0'
  [ "$status" -eq 0 ]
}

@test "portable stat: NEITHER form answers ⇒ each site's own default, still no fatal" {
  # The fail-open direction. `ll_mtime` prints NOTHING when unknowable — which is the half that
  # makes every call site's `|| echo <default>` mean what it has always claimed to mean. A stub
  # that answers nothing must therefore leave the script alive, never kill it in arithmetic.
  SSTUB="$BATS_TEST_TMPDIR/statstub.none"; mkdir -p "$SSTUB"
  printf '#!/bin/bash\nprintf "  File: junk\\n"\nexit 1\n' > "$SSTUB/stat"; chmod +x "$SSTUB/stat"
  mkdir -p "$LOCK"
  echo 999999 > "$LOCK/pid"
  echo "$SENTINEL_LSTART" > "$LOCK/lstart"
  run env PATH="$SSTUB:$PATH" LAND_LOCK_WAIT=1 bash "$LL" -- bash -c 'exit 0'
  run bash -c "printf '%s' \"\$1\" | grep -c 'unbound variable'" _ "$output"
  [ "$output" = "0" ]
}

@test "RATCHET: no bare BSD-first stat survives in land-lock.sh outside the two helpers" {
  # The durable half. Order reversal is invisible at a glance and a future edit re-reaches for the
  # idiom the rest of this fleet still uses, so the shape is pinned rather than only its effect.
  #
  # EXECUTABLE lines only. The file's own § PORTABLE stat comment quotes the broken idiom twice, by
  # design — that is the record of what was wrong — and a ratchet that cannot tell a citation from a
  # call site convicts the documentation for describing the bug it cures. (Same distinction
  # scripts/gate-select.sh draws with `cited_only`.) The negative control is below: strip the guard
  # and the count is 2, both of them comments.
  run bash -c "grep -vE '^[[:space:]]*#' '$REPO/scripts/land-lock.sh' | grep 'stat -f' | grep -vc 'stat -c'"
  [ "$output" = "0" ]
  # …and the helpers really are the only stat call sites, so the grep above cannot pass by deletion:
  # exactly two survive, each pairing -c FIRST with -f second.
  run bash -c "grep -vE '^[[:space:]]*#' '$REPO/scripts/land-lock.sh' | grep -c 'stat -c %Y\|stat -c %i'"
  [ "$output" = "2" ]
  run bash -c "grep -vE '^[[:space:]]*#' '$REPO/scripts/land-lock.sh' | grep -c 'stat -c %Y \"\$1\" 2>/dev/null || stat -f %m'"
  [ "$output" = "1" ]
}
