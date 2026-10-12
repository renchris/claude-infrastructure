#!/usr/bin/env bats
# lr-reset-poller.sh § 2 — THE PARKED LOOP'S READ-ONLY GATES, CHEAPEST FIRST (decision e276a5e2fb63,
# option (c), 2026-10-11). A husk record that no registry row names must cost ONE `pgrep resume`
# per tick, not two, and its outcome must not change. The two projects/* globs the reorder also
# skips have no process to count; they are pinned by the comment beside them, not by a trace.
# Hermetic: fixture $HOME and stubs, as tests/lr-poller-stranded-husk.bats; a counting pgrep on PATH
# (the tests/lr-lib-registry-one-jq.bats:26-30 pattern) that then runs the real one.
# ONE TICK FOR THE FILE (setup_file), three independent sids in it: a poller tick took ~4 min at
# load 400 and the off-box admission bound is 300 s per suite. Option (g)'s cases are in
# tests/lr-reset-poller-parked-moved-on.bats for the same reason.

load lr-reset-poller-parked-helpers

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"; mkdir -p "$HOME"
  parked_env
  NOROW=e276a5e2-0000-4000-8000-0000000000c1   # no registry row anywhere
  SRCROW=e276a5e2-0000-4000-8000-0000000000c2  # a live row on the source: a husk pane
  TGTROW=e276a5e2-0000-4000-8000-0000000000c3  # a live row on the target: the successor runs
  export NOROW SRCROW TGTROW
  for s in "$NOROW" "$SRCROW" "$TGTROW"; do husk_disk "$s"; park_past "$s"; done
  holder "$SRCROW" 99168 "$$" claude-secondary "$SRC"
  holder "$TGTROW" 200 "$PPID" claude-quaternary "$TGT"
  tick > "$BATS_FILE_TMPDIR/tick.out" 2>&1; echo "$?" > "$BATS_FILE_TMPDIR/tick.rc"
}
setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
}

@test "the tick exits 0" {
  [ "$(cat "$BATS_FILE_TMPDIR/tick.rc")" -eq 0 ] || { cat "$BATS_FILE_TMPDIR/tick.out"; plog; false; }
}

@test "[RED] no registry row names the sid: ONE pgrep resume per tick (trunk: 2), and the record stays LEFT PARKED" {
  [ "$(resume_pgreps "$NOROW")" -eq 1 ] || { cat "$PGREP_LOG"; plog; false; }
  [ -f "$STATE/parked/$NOROW.json" ] || { plog; false; }
  [ -e "$STATE/parked/$NOROW.husk-noted" ]
  [ ! -e "$STATE/requests/$NOROW.json" ] || { plog; false; }
  [ ! -e "$STATE/resumed/$NOROW.json" ] || { plog; false; }
  ! grep -q -- "$NOROW" "$FLEET_LOG" || { cat "$FLEET_LOG"; false; }
}

@test "GUARD: a live source row still files the STRANDED-HUSK request and leaves the record parked" {
  [ "$(jq -r .requested_by "$STATE/requests/$SRCROW.json")" = stranded-husk ] || { plog; false; }
  [ "$(jq -r .source_pane "$STATE/requests/$SRCROW.json")" = 99168 ]
  grep -q "STRANDED-HUSK $SRCROW" "$STATE/poller.log" || { plog; false; }
  [ -f "$STATE/parked/$SRCROW.json" ] || { plog; false; }
  [ ! -e "$STATE/resumed/$SRCROW.json" ] || { plog; false; }
}

@test "GUARD: a live row on the TARGET still retires the record as TRANSPLANTED" {
  grep -q "TRANSPLANTED $TGTROW" "$STATE/poller.log" || { plog; false; }
  [ -f "$STATE/resumed/$TGTROW.json" ] || { plog; false; }
  [ ! -e "$STATE/parked/$TGTROW.json" ]
}
