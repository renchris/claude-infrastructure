#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# scripts/limit-recover/lr-move-worker.sh — the worker owns its retries and does not churn a
# transplant it cannot finish (docs/plans/LIMIT_RECOVER_SELF_INPLACE.md § W0 R6, R7; § W1).
#
# WHAT THESE CASES PIN:
#   · R6: a CLEAN HELD:unreachable (rc 6, `lr-transplant --phase abort rc 0` withdrew the admit) is
#     re-driven by the worker itself, under the same claim; every other hold is final (2026-10-18:
#     one attempt, NOTMOVED, and the only retry left was a mail that put two actuators on a session);
#   · R7 → A2: the worker never waits for load nor finishes HELD:load itself; a staged move is not
#     load-gated, and a typed one is held by handoff-fire's own hold (lr-sustained-load REPORT §4 A2);
#   · the claim is released the moment the verdict file exists, not after the summary/mail step.
#
# Hermetic: lr-handoff is a stub wrapping tests/helpers/lr-move-fixture.sh's; the load is the
# HF_LOAD_PER_CORE seam, and setup() pins CC_FIRE_CAPACITY_GATE=off so no case reads the machine's.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_GATE=off
  export CC_FIRE_CAPACITY_GATE=off
  export CC_LR_MOVE_MAIL=off CC_NOTIFY_BIN=/usr/bin/false
  export LR_MOVE_UNREACHABLE_BACKOFF_S=0
  # shellcheck source=/dev/null
  . "$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/helpers/lr-move-fixture.sh"
  mvf_setup
  mvf_handoff_stub
  SID="bbbb2222-0000-4000-8000-000000000001"; PANE=41
  mvf_session "$PANE" "$SID"
  mvf_plan w1 move "$PANE:$SID"
  # The batch runner's admission record, as tests/lr-move-worker.bats writes it: the verdict's P6 conjunct
  # needs it, so without it every MOVED case here ended FAILED "P6 admission" (also on 69ed4dae1 itself).
  printf '{"admitted":true,"target":"next3","target_auth":"ok"}\n' > "$BDIR/admit.json"
  CLAIMS="$LR_STATE_DIR/runs/by-sid"
  retry_stub
}
teardown() { mvf_teardown; }

# The first STUB_FAIL_N calls hold with STUB_HELD (default HELD:unreachable), carrying lr-handoff's
# clean-abort line unless STUB_NO_ABORT is set; later calls are the fixture's moving stub. Each call
# records its number, its attempt env and the claim holder's pid at that moment.
retry_stub() {
  mv "$LR_MOVE_HANDOFF_BIN" "$STUBS/lr-handoff-move"
  export STUBS STUB_CLAIM="$CLAIMS/$SID.active" LR_MOVE_HANDOFF_BIN="$STUBS/lr-handoff-retry"
  cat > "$LR_MOVE_HANDOFF_BIN" <<'STUB'
#!/bin/bash
n=$(( $(cat "$STUB_LOG/calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_LOG/calls"
printf '%s %s %s\n' "$n" "${LR_ATTEMPT:-}" "${HF_RECYCLE_ATTEMPT:-}" >> "$STUB_LOG/attempts.log"
sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "$STUB_CLAIM/holder" 2>/dev/null | sed -n '1p' >> "$STUB_LOG/holders.log"
if [ "$n" -le "${STUB_FAIL_N:-1}" ]; then
  tail="; lr-transplant --phase abort rc 0 withdrew the admit"; [ -z "${STUB_NO_ABORT:-}" ] || tail=""
  echo "lr-handoff: verdict: ${STUB_HELD:-HELD:unreachable} — the recycle stood down before any confirm (handoff-fire rc=6)$tail" >&2
  exit 6
fi
exec "$STUBS/lr-handoff-move" "$@"
STUB
  chmod +x "$LR_MOVE_HANDOFF_BIN"
}

worker_bg() {
  bash "$LRD/lr-move-worker.sh" w1 "$SID" > "$BATS_TEST_TMPDIR/worker.out" 2>&1 3>&- &
  WPID=$!
  mkdir -p "$CLAIMS/$SID.active"
  bash -c '. "$1/lr-lib.sh"; lr_claim_stamp "$2" "$3" "$4" lr-move-worker "$5"' _ "$LRD" "$CLAIMS/$SID.active" "$SID" "$WPID" "$PANE"
}
worker() { worker_bg; wait "$WPID" || true; }
res() { jq -r ".$1" "$BDIR/$SID.json"; }
calls() { cat "$STUB_LOG/calls" 2>/dev/null || echo 0; }

# ── R6: retry a clean HELD:unreachable ───────────────────────────────────────────────────────────
@test "R6-1 [RED] a clean HELD:unreachable is re-driven: second attempt MOVED, one claim holder throughout" {
  worker
  [ "$(res verdict)" = MOVED ] || { res verdict; res reason; cat "$BATS_TEST_TMPDIR/worker.out"; false; }
  [ "$(calls)" = 2 ]
  # a fresh attempt number per actuation, under the same record id
  [ "$(sed -n 1p "$STUB_LOG/attempts.log")" = "1 1 move-w1-bbbb2222:1" ]
  [ "$(sed -n 2p "$STUB_LOG/attempts.log")" = "2 2 move-w1-bbbb2222:2" ]
  grep -q -- "--attempt 2 " "$STUB_LOG/argv.log"
  # the claim named this worker at both actuations: nothing was released between them
  [ "$(sort -u "$STUB_LOG/holders.log")" = "$WPID" ] || { cat "$STUB_LOG/holders.log"; false; }
  grep -q '"stage":"retry","t_ms":[0-9]*,"detail":"attempt 2 after HELD:unreachable"' "$BDIR/$SID.events.jsonl"
  # attempt 1's log is kept; attempt 2 wrote its own
  grep -q 'HELD:unreachable' "$BDIR/$SID.handoff.log"
  [ -f "$BDIR/$SID.handoff.2.log" ]
  [ ! -d "$CLAIMS/$SID.active" ]
}

@test "R6-2 CONTROL: rc 6 HELD:busy is never retried — one call, NOTMOVED HELD:busy" {
  export STUB_HELD=HELD:busy
  worker
  [ "$(calls)" = 1 ]
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == "HELD:busy"* ]] || { res reason; false; }
}

@test "R6-3 CONTROL: HELD:unreachable WITHOUT the clean-abort line is never retried" {
  export STUB_NO_ABORT=1
  worker
  [ "$(calls)" = 1 ]
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == "HELD:unreachable"* ]] || { res reason; false; }
}

@test "R6-4 CONTROL: retries exhausted — 1+N calls, then NOTMOVED HELD:unreachable" {
  export STUB_FAIL_N=99 LR_MOVE_UNREACHABLE_RETRIES=2
  worker
  [ "$(calls)" = 3 ]
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == "HELD:unreachable"* ]] || { res reason; false; }
  grep -q '"stage":"retry-exhausted"' "$BDIR/$SID.events.jsonl"
}

@test "R6-5 KILL SWITCH: LR_MOVE_UNREACHABLE_RETRIES=0 is one attempt, as before" {
  export LR_MOVE_UNREACHABLE_RETRIES=0
  worker
  [ "$(calls)" = 1 ]
  [ "$(res verdict)" = NOTMOVED ]
}

# ── R7 → A2: the load is recorded, never waited on (lr-sustained-load 2026-10-20 REPORT §4 A2) ──
# LR_MOVE_LOAD_WAIT_S=0 is exported in the [RED] cases only so the pre-fix worker reaches its final
# HELD:load at once instead of after 600 s; the fixed worker reads no such knob.
load_on() { unset CC_FIRE_CAPACITY_GATE; export HF_LOAD_PER_CORE="$1" STUB_FAIL_N=0 LR_MOVE_LOAD_WAIT_S=0; }

@test "R7-1 [RED] load 40/core, staged relaunch: the actuator runs and the move lands, no HELD:load" {
  load_on 40
  worker
  [ "$(calls)" = 1 ]
  [ "$(res verdict)" = MOVED ] || { res verdict; res reason; cat "$BATS_TEST_TMPDIR/worker.out"; false; }
  grep -q '"stage":"load","t_ms":[0-9]*,"detail":"40/core; the relaunch is staged' "$BDIR/$SID.events.jsonl"
  ! grep -q '"stage":"load-wait"' "$BDIR/$SID.events.jsonl" || false
}

@test "R7-2 [RED] load 40/core, typed relaunch (CC_PANE_SUCCESSOR=off): the worker does not hold, handoff-fire decides" {
  load_on 40; export CC_PANE_SUCCESSOR=off
  worker
  [ "$(calls)" = 1 ]
  [ "$(res verdict)" = MOVED ] || { res verdict; res reason; false; }
  grep -q "\"detail\":\"40/core; the relaunch is typed, so handoff-fire's own load hold decides\"" "$BDIR/$SID.events.jsonl"
}

@test "R7-3 [RED] load 22/core, between the old precheck (20) and commit (24) bounds, actuates" {
  load_on 22
  worker
  [ "$(calls)" = 1 ]
  [ "$(res verdict)" = MOVED ] || { res reason; false; }
}

@test "R7-4 CONTROL: a typed move that handoff-fire holds on load ends with ITS HELD:load, one call" {
  # The hold that guards a typed relaunch (F1, pane 44) is handoff-fire's; the worker passes it on
  # as before (rc 6 holds other than a clean HELD:unreachable are final) and never mints its own.
  load_on 40; export CC_PANE_SUCCESSOR=off STUB_FAIL_N=1 STUB_HELD=HELD:load
  worker
  [ "$(calls)" = 1 ]
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == "HELD:load"* ]] || { res reason; false; }
  ! grep -q 'stayed above the' "$BDIR/$SID.json" || false
}

@test "R7-5 CONTROL: load 1/core actuates and moves" {
  load_on 1
  worker
  [ "$(calls)" = 1 ]
  [ "$(res verdict)" = MOVED ] || { res reason; false; }
}

# ── the claim goes with the verdict ──────────────────────────────────────────────────────────────
@test "C-1 [RED] the claim is gone as soon as <sid>.json exists, while the summary step still spins" {
  export STUB_FAIL_N=0
  # A closed batch (summary.json) whose summary lock is held: lr_move_summary_late spins ~10 s on it.
  printf '{"status":"done"}\n' > "$BDIR/summary.json"; mkdir "$BDIR/summary.lock"
  worker_bg
  for _ in $(seq 1 300); do [ -f "$BDIR/$SID.json" ] && break; sleep 0.2; done
  [ -f "$BDIR/$SID.json" ]
  sleep 0.5
  kill -0 "$WPID"                       # still inside the summary step
  [ ! -d "$CLAIMS/$SID.active" ] || { rmdir "$BDIR/summary.lock"; wait "$WPID"; false; }
  rmdir "$BDIR/summary.lock"
  wait "$WPID" || true
  [ "$(res verdict)" = MOVED ]
}
