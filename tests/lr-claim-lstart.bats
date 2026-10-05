#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# scripts/limit-recover/lr-lib.sh — a run claim's holder is (pid, lstart), not a pid (F1, 2026-10-04).
#
# THE DEFECT: lr_claim_take judged a holder with `kill -0 <pid>` alone. This box forks ~1,162 pids/s,
# so the pid space wraps about every 86 s; a dead driver's pid is soon an unrelated live process, and
# the claim then read `held-live` for as long as that stranger ran. Nothing could recover the session.
#
# Every [RED] case fails on the pre-fix lr-lib.sh; each has an LR_CLAIM_LSTART=off control that
# replays the pre-fix judgment and shows the old outcome.
#
# Hermetic: the claim root is a fixture dir, the "holder" is this test's own `sleep`, nothing is typed.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/limit-recover/lr-lib.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  ROOT="$BATS_TEST_TMPDIR/by-sid"; mkdir -p "$ROOT"
  SID="aaaaaaaa-0000-4000-8000-000000000001"
  export LR_CLAIM_ORPHAN_GRACE_S=0
  # fd 3 closed: bats waits on every process still holding it, so a background sleep would hang the run.
  sleep 300 3>&- & HOLDER=$!
}
teardown() { kill "$HOLDER" 2>/dev/null || true; }

holder() { # $1=pid $2=lstart field, or "" for a legacy holder with no lstart
  mkdir -p "$ROOT/$SID.active"
  if [ -n "$2" ]; then
    printf '{"sid":"%s","pane":"-","pid":%d,"ts":"2026-10-04T00:00:00Z","by":"t","lstart":"%s"}\n' "$SID" "$1" "$2" > "$ROOT/$SID.active/holder"
  else
    printf '{"sid":"%s","pane":"-","pid":%d,"ts":"2026-10-04T00:00:00Z","by":"t"}\n' "$SID" "$1" > "$ROOT/$SID.active/holder"
  fi
}
take() { run bash -c 'source "$1"; lr_claim_take "$2" "$3" test - "$$"' _ "$LIB" "$ROOT" "$SID"; }

@test "[RED] a live pid recorded under a DIFFERENT lstart is a reused pid: the claim is stolen" {
  holder "$HOLDER" "Thu Jan 1 00:00:00 1970"
  take
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=stolen-pid-reused"* ]] || false
  [ "$(sed -n 's/.*"pid":\([0-9]*\).*/\1/p' "$ROOT/$SID.active/holder")" != "$HOLDER" ]
}

@test "control: LR_CLAIM_LSTART=off replays the pid-only judgment and the reused pid HOLDS the claim" {
  holder "$HOLDER" "Thu Jan 1 00:00:00 1970"
  export LR_CLAIM_LSTART=off
  take
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=held-live"* ]]
}

@test "the same pid under its own lstart is the holder, alive: held" {
  ls="$(bash -c 'source "$1"; lr_pid_lstart "$2"' _ "$LIB" "$HOLDER")"
  [ -n "$ls" ]
  holder "$HOLDER" "$ls"
  take
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=held-live"* ]]
}

@test "a legacy holder (no lstart) with a live pid keeps the pid-only judgment: held" {
  # Not stolen: a drain that stamped its own pid before this deployed is not in lr_claim_drivers'
  # census, and stealing its claim would start a second typer in its pane.
  holder "$HOLDER" ""
  take
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=held-live"* ]]
}

@test "a legacy holder whose pid is dead is stolen" {
  kill "$HOLDER"; wait "$HOLDER" 2>/dev/null || true
  holder "$HOLDER" ""
  take
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=stolen-dead-holder"* ]]
}

@test "a dead holder is stolen as before, whatever its lstart" {
  kill "$HOLDER"; wait "$HOLDER" 2>/dev/null || true
  holder "$HOLDER" "Thu Jan 1 00:00:00 1970"
  take
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=stolen-dead-holder"* ]]
}

@test "[RED] the stamp records the stamped pid's lstart in the holder, in store.py's field" {
  run bash -c 'source "$1"; lr_claim_take "$2" "$3" test - "$4" >/dev/null; lr_claim_holder_lstart "$2/$3.active"' _ "$LIB" "$ROOT" "$SID" "$HOLDER"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" = "$(TZ=UTC LC_ALL=C ps -o lstart= -p "$HOLDER" | tr -s ' ' | sed -e 's/^ //' -e 's/ $//')" ]
  grep -q "\"pid\":$HOLDER," "$ROOT/$SID.active/holder"
}

@test "[RED] a pid lock whose pid is alive under a different lstart is dead; the same lstart is alive" {
  L="$BATS_TEST_TMPDIR/x.lock"; mkdir -p "$L"
  bash -c 'source "$1"; lr_pidlock_stamp "$2" "$3"' _ "$LIB" "$L" "$HOLDER"
  run bash -c 'source "$1"; lr_pidlock_live "$2"' _ "$LIB" "$L"
  [ "$status" -eq 0 ]
  echo "Thu Jan 1 00:00:00 1970" > "$L/lstart"
  run bash -c 'source "$1"; lr_pidlock_live "$2"' _ "$LIB" "$L"
  [ "$status" -eq 1 ]
  run bash -c 'source "$1"; LR_CLAIM_LSTART=off lr_pidlock_live "$2"' _ "$LIB" "$L"
  [ "$status" -eq 0 ]
}

@test "a pid lock with no lstart file keeps the pid-only judgment" {
  L="$BATS_TEST_TMPDIR/y.lock"; mkdir -p "$L"; echo "$HOLDER" > "$L/pid"
  run bash -c 'source "$1"; lr_pidlock_live "$2"' _ "$LIB" "$L"
  [ "$status" -eq 0 ]
}
