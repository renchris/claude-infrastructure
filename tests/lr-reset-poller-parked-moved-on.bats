#!/usr/bin/env bats
# lr-reset-poller.sh § 2 — A SUCCESSOR THAT RAN ON THE TARGET AND EXITED RETIRES ITS PARKED RECORD
# (decision e276a5e2fb63, option (g), 2026-10-11). Leg (1) waits for RECOVERED, which lr-handoff
# never writes; leg (2) needs the successor alive during a tick; so such records stayed parked
# forever (24 of 27 live on 2026-10-11). Leg (3) retires on a non-error assistant turn on the
# TARGET after the confirm tombstone's ts, with no registry row naming the sid and never on an
# admit tombstone. ONE TICK FOR THE FILE (setup_file), four independent sids: the off-box bound is
# 300 s per suite and a tick took ~4 min at load 400.

load lr-reset-poller-parked-helpers

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"; mkdir -p "$HOME"
  parked_env
  ENGAGED=e276a5e2-0000-4000-8000-0000000000d1   # the successor took a turn after the move
  BEFORE=e276a5e2-0000-4000-8000-0000000000d2    # a turn on the target, but from BEFORE the move
  HUSKROW=e276a5e2-0000-4000-8000-0000000000d3   # engaged, but a source pane still holds the sid
  ADMIT=e276a5e2-0000-4000-8000-0000000000d4     # engaged, but the tombstone is an ADMIT one
  export ENGAGED BEFORE HUSKROW ADMIT
  for s in "$ENGAGED" "$BEFORE" "$HUSKROW" "$ADMIT"; do husk_disk "$s"; park_past "$s"; done
  turn_on_target "$ENGAGED" 2026-10-10T05:00:00.123Z
  turn_on_target "$BEFORE" 2026-10-10T04:10:00Z
  turn_on_target "$HUSKROW" 2026-10-10T05:00:00Z
  holder "$HUSKROW" 99168 "$$" claude-secondary "$SRC"
  turn_on_target "$ADMIT" 2026-10-10T05:00:00Z
  printf '{"handed_off_to":"%s","target_transcript":"%s/projects/-p/%s.jsonl","ts":"2026-10-10T04:18:07Z","phase":"admit"}\n' \
    "$TGT" "$TGT" "$ADMIT" > "$SRC/projects/-p/$ADMIT.HANDOFF.json"
  tick > "$BATS_FILE_TMPDIR/tick.out" 2>&1; echo "$?" > "$BATS_FILE_TMPDIR/tick.rc"
}
setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
}

@test "the tick exits 0" {
  [ "$(cat "$BATS_FILE_TMPDIR/tick.rc")" -eq 0 ] || { cat "$BATS_FILE_TMPDIR/tick.out"; plog; false; }
}

@test "[RED] (g) the successor took a turn on the target after the move and no pane holds the sid: retired TRANSPLANTED" {
  grep -q "TRANSPLANTED $ENGAGED .*engaged-on-target after 2026-10-10T04:18:07Z" "$STATE/poller.log" || { plog; false; }
  [ -f "$STATE/resumed/$ENGAGED.json" ] || { plog; false; }
  [ ! -e "$STATE/parked/$ENGAGED.json" ]
  [ ! -e "$STATE/parked/$ENGAGED.husk-noted" ]
  ! grep -q -- "$ENGAGED" "$FLEET_LOG" || { cat "$FLEET_LOG"; false; }
}

@test "(g) GUARD: a turn on the target from BEFORE the tombstone's ts is not the successor: left parked" {
  [ -f "$STATE/parked/$BEFORE.json" ] || { plog; false; }
  [ ! -e "$STATE/resumed/$BEFORE.json" ] || { plog; false; }
}

@test "(g) GUARD: a live registry row on the source (a husk pane) keeps the record for the husk lane" {
  [ -f "$STATE/parked/$HUSKROW.json" ] || { plog; false; }
  [ ! -e "$STATE/resumed/$HUSKROW.json" ] || { plog; false; }
}

@test "(g) GUARD: an ADMIT-phase tombstone (the source was never retired) is never read as a carried session" {
  [ -f "$STATE/parked/$ADMIT.json" ] || { plog; false; }
  [ ! -e "$STATE/resumed/$ADMIT.json" ] || { plog; false; }
}
