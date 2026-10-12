#!/usr/bin/env bats
# lr-reset-poller.sh § 2a — THE REROUTE CAP CLEARS WHEN THE SESSION RECOVERS BY ANY PATH (decision 1dc45a0d583c).
#
# A cap that only a fleet RECOVERED could clear would latch forever: sessions also heal by RESUMED,
# TRANSPLANTED, REQUEST-RETIRED or a reconciler close (46bc0436 and 8e18da3f came back as RESUMED
# autofire, 58d3640a as CLOSED:IN-PLACE). Each such path clears the sid's cap here, so the next limit
# episode starts at zero and pages afresh. The cap itself is in lr-reset-poller-reroute-cap.bats.
# One tick for the file; fixture and the off-box reasoning: lr-reset-poller-reroute-cap-helpers.bash.

load lr-reset-poller-reroute-cap-helpers

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"; mkdir -p "$HOME"
  cap_env
  export RECOVD=1dc45a04-0000-4000-8000-000000000004   # gave up, then another lane's run RECOVERED
  export ORPHAN=1dc45a05-0000-4000-8000-000000000005   # cap state whose parked record retired
  export RECON=1dc45a06-0000-4000-8000-000000000006    # gave up, then the reconciler closed it
  export RETIRED=1dc45a08-0000-4000-8000-000000000008  # gave up, and its hook request retires
  for s in "$RECOVD" "$RECON" "$RETIRED"; do park_rec "$s"; done
  for s in "$RECOVD" "$ORPHAN" "$RECON" "$RETIRED"; do
    seed "$s" 3 "$R_FAIL"; printf '%s\n' "$R_FAIL" > "$STATE/reroute/$s.paged"
  done
  last_run "$RECOVD" "$V_OK"
  last_run "$RECON" "$V_FAIL"
  touch -t 202601010000 "$STATE/reroute/$RECON.tries"
  echo '{"phase":"ENGAGED","terminal":{"kind":"CLOSED:IN-PLACE"}}' > "$STATE/recon/sessions/$RECON.json"
  # RETIRED is parked too, so the sweep cannot be what clears it: without rq_retire's clear, § 2a
  # reads n=3 with its .paged marker and neither reroutes nor pages it.
  printf '{"sid":"%s","requested_by":"stop-failure-marker","account":"next4"}\n' "$RETIRED" > "$STATE/requests/$RETIRED.json"
  run_tick
}
setup() { export HOME="$BATS_FILE_TMPDIR/home"; }
teardown_file() { cap_teardown; }

@test "the tick exits 0 under /bin/bash" {
  [ "$(cat "$BATS_FILE_TMPDIR/tick.rc")" -eq 0 ] || { cat "$BATS_FILE_TMPDIR/tick.out"; plog; false; }
}

@test "[RED] 1dc45a0d583c: a RECOVERED last run clears the cap and the session is rerouted afresh" {
  [ ! -e "$STATE/reroute/$RECOVD.tries" ] || { ls "$STATE/reroute"; false; }
  [ ! -e "$STATE/reroute/$RECOVD.paged" ] || { ls "$STATE/reroute"; false; }
  [ "$(dispatched "$RECOVD")" -eq 1 ] || { cat "$FLEET_LOG"; plog; false; }
}

@test "[RED] 1dc45a0d583c: cap state whose parked record retired (RESUMED, TRANSPLANTED…) is swept" {
  [ ! -e "$STATE/reroute/$ORPHAN.tries" ] || { ls "$STATE/reroute"; false; }
  [ ! -e "$STATE/reroute/$ORPHAN.paged" ] || { ls "$STATE/reroute"; false; }
  grep -q "REROUTE-CAP-CLEAR $ORPHAN — its parked record retired" "$STATE/poller.log" || { plog; false; }
}

@test "[RED] 1dc45a0d583c: a reconciler close newer than the cap clears it, and the session is rerouted" {
  grep -q "REROUTE-CAP-CLEAR $RECON — the reconciler closed its record" "$STATE/poller.log" || { plog; false; }
  [ "$(dispatched "$RECON")" -eq 1 ] || { cat "$FLEET_LOG"; plog; false; }
}

@test "[RED] 1dc45a0d583c: a retired request clears the sid's cap, so the session is rerouted afresh" {
  grep -q "REQUEST-RETIRED $RETIRED" "$STATE/poller.log" || { plog; false; }
  [ ! -e "$STATE/reroute/$RETIRED.paged" ] || { ls "$STATE/reroute"; plog; false; }
  [ "$(dispatched "$RETIRED")" -eq 1 ] || { cat "$FLEET_LOG"; plog; false; }
}
