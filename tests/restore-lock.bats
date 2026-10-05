#!/usr/bin/env bats
# scripts/lib/restore-lock.sh — one restore at a time (W3 P2, 2026-10-04).
#
# Contract under test: restore_lock_take takes a global mkdir lock and claims events/<id>.inprogress,
# both stamped with pid, lstart and boot uuid; a live holder refuses a second taker (rc 1); a holder
# from another boot, a dead pid or a reused pid (same pid, other lstart) is reclaimed; a holder file
# that never appeared is a taker mid-write until the grace runs out; release refuses a lock it does
# not hold; `release done` turns the claim into events/<id>.done and a done event is never retaken;
# restore_refuse_under_bats refuses under a harness and only there. Every case runs the library under
# /bin/bash, the 3.2 that launchd gives the restore.
#
# Hermetic: HOME, RESTORE_STATE_DIR and RESTORE_LOCK_BOOT_UUID point into the case dir; the only real
# processes are the case's own `sleep`s, which teardown kills.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LIB="$REPO/scripts/lib/restore-lock.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export RESTORE_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export RESTORE_LOCK_BOOT_UUID="boot-A"
  LOCK="$RESTORE_STATE_DIR/restore.lock"
  EV="$RESTORE_STATE_DIR/events"
  SLEEPERS=""
}

teardown() {
  local p; for p in $SLEEPERS; do kill "$p" 2>/dev/null || true; done
}

rl() { # <shell body> — run it under /bin/bash with the library sourced
  run /bin/bash -c ". \"$LIB\"; $1"
}

lstart_of() { TZ=UTC LC_ALL=C ps -o lstart= -p "$1" | tr -s ' ' | sed -e 's/^ //' -e 's/ $//'; }

# A lock held by a LIVE process other than the test's: a background sleep, stamped by hand with its
# own pid and lstart (or the overrides given).
hold_with() { # <pid> <lstart> <boot>
  mkdir -p "$LOCK" "$EV"
  printf '{"event":"e0","pid":%s,"lstart":"%s","boot":"%s","at":1}\n' "$1" "$2" "$3" > "$LOCK/holder"
}
live_sleeper() { sleep 300 & SLEEPERS="$SLEEPERS $!"; LIVE=$!; }

@test "take: lock and claim both carry pid, lstart and boot uuid" {
  rl 'restore_lock_take ev-1; echo "rc=$? pid=$$"; cat "$RESTORE_STATE_DIR/restore.lock/holder"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=0"* ]] || false
  pid="$(printf '%s\n' "$output" | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -1)"
  grep -q "\"pid\":$pid," "$LOCK/holder"
  grep -q '"boot":"boot-A"' "$LOCK/holder"
  grep -q '"lstart":"[A-Z][a-z][a-z] ' "$LOCK/holder"
  grep -q '"event":"ev-1"' "$EV/ev-1.inprogress"
  cmp -s "$LOCK/holder" "$EV/ev-1.inprogress"
}

@test "take: a lock held by a live restore refuses the second taker with rc 1 and leaves it alone" {
  live_sleeper; hold_with "$LIVE" "$(lstart_of "$LIVE")" boot-A
  before="$(cat "$LOCK/holder")"
  rl 'restore_lock_take ev-2; echo "rc=$?"'
  [ "$output" = "rc=1" ]
  [ "$(cat "$LOCK/holder")" = "$before" ]
  [ ! -e "$EV/ev-2.inprogress" ]
}

@test "stale: a dead holder pid is reclaimed" {
  sleep 0 & dead=$!; wait "$dead"
  hold_with "$dead" "Mon Jan 1 00:00:00 2026" boot-A
  rl 'restore_lock_take ev-3; echo "rc=$?"'
  [ "$output" = "rc=0" ]
  grep -q '"event":"ev-3"' "$LOCK/holder"
}

@test "stale: a live pid with another start time is a reused pid, and is reclaimed" {
  live_sleeper; hold_with "$LIVE" "Mon Jan 1 00:00:00 2001" boot-A
  rl 'restore_lock_take ev-4; echo "rc=$?"'
  [ "$output" = "rc=0" ]
  grep -q '"event":"ev-4"' "$LOCK/holder"
}

@test "stale: a holder from another boot is reclaimed even though its pid and lstart match a live process" {
  live_sleeper; hold_with "$LIVE" "$(lstart_of "$LIVE")" boot-OLD
  rl 'restore_lock_take ev-5; echo "rc=$?"'
  [ "$output" = "rc=0" ]
  grep -q '"boot":"boot-A"' "$LOCK/holder"
}

@test "stale: a lock dir with no holder file is held inside the grace and reclaimed after it" {
  mkdir -p "$LOCK" "$EV"
  rl 'restore_lock_take ev-6; echo "rc=$?"'
  [ "$output" = "rc=1" ]
  touch -t 202601010000 "$LOCK"
  rl 'restore_lock_take ev-6; echo "rc=$?"'
  [ "$output" = "rc=0" ]
}

@test "release: plain release removes lock and claim; release done turns the claim into .done, never retaken" {
  rl 'restore_lock_take ev-7; restore_lock_release; echo "rc=$?"'
  [ "$output" = "rc=0" ]
  [ ! -e "$LOCK" ]; [ ! -e "$EV/ev-7.inprogress" ]; [ ! -e "$EV/ev-7.done" ]
  rl 'restore_lock_take ev-8; restore_lock_release done; echo "rc=$?"'
  [ "$output" = "rc=0" ]
  [ ! -e "$LOCK" ]; [ ! -e "$EV/ev-8.inprogress" ]; [ -f "$EV/ev-8.done" ]
  rl 'restore_lock_take ev-8; echo "rc=$?"'
  [ "$output" = "rc=3" ]
  [ ! -e "$LOCK" ]
}

@test "release: a lock this process does not hold is refused and left in place" {
  live_sleeper; hold_with "$LIVE" "$(lstart_of "$LIVE")" boot-A
  rl 'restore_lock_release; echo "rc=$?"'
  [ "$output" = "rc=1" ]
  [ -f "$LOCK/holder" ]
}

@test "take: an event id that could escape the events dir is refused with rc 2" {
  for bad in "" "../x" ".hidden" "a/b" "a b"; do
    rl "restore_lock_take '$bad'; echo \"rc=\$?\""
    [ "$output" = "rc=2" ]
  done
  [ ! -e "$LOCK" ]
}

@test "restore_refuse_under_bats refuses under a harness and lets a real run through" {
  rl 'restore_refuse_under_bats "TERM kitty"; echo "rc=$?"'
  [[ "$output" == *"REFUSED under a bats harness: TERM kitty"* ]] || false
  [[ "$output" == *"rc=0" ]] || false
  run env -u BATS_TEST_FILENAME -u BATS_TEST_TMPDIR -u BATS_VERSION \
    /bin/bash -c ". \"$LIB\"; restore_refuse_under_bats x; echo \"rc=\$?\""
  [ "$output" = "rc=1" ]
}
