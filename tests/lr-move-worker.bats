#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# scripts/limit-recover/lr-move-worker.sh — one session moved to another account in its own pane,
# with no model turn (design-swap-v3 §4.3, 2026-10-04).
#
# WHAT THESE CASES PIN, each against a named failure of the lane it replaces:
#   · every hold happens BEFORE the actuator runs (claim, fence, abort, slot, idle wait): a worker
#     that cannot move a session never starts the /exit. The rejected designs took their boot slot
#     after /exit, where a queued pane waits at a bare shell;
#   · the actuator is called with the operator's intent, --no-prompt, --no-replace and
#     LR_ADMIT_MODE=swap, so nothing can refuse after /exit and no prompt is typed;
#   · the result is lr_move_verdict's, read off disk: a recycle that returned rc 0 but left a
#     tombstone in the target is FAILED, not SWITCHED (762a6daa).
# Each `not invoked` assertion is the control for its hold: the stub records every call.
#
# Hermetic: lr-handoff is a stub (tests/helpers/lr-move-fixture.sh); sessions are `sleep`s.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_GATE=off
  export CC_FIRE_CAPACITY_GATE=off
  # shellcheck source=/dev/null
  . "$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/helpers/lr-move-fixture.sh"
  mvf_setup
  mvf_handoff_stub
  SID="bbbb2222-0000-4000-8000-000000000001"; PANE=41
  mvf_session "$PANE" "$SID"
  mvf_plan w1 move "$PANE:$SID"
  printf '{"admitted":true,"target":"next3","target_auth":"ok"}\n' > "$BDIR/admit.json"
  CLAIMS="$LR_STATE_DIR/runs/by-sid"
}
teardown() { mvf_teardown; }

# The batch runner's two steps, in its order: spawn the worker, then re-stamp the claim to its pid.
worker() { # [claim: yes|no]
  bash "$LRD/lr-move-worker.sh" w1 "$SID" > "$BATS_TEST_TMPDIR/worker.out" 2>&1 3>&- &
  WPID=$!
  if [ "${1:-yes}" = yes ]; then
    mkdir -p "$CLAIMS/$SID.active"
    bash -c '. "$1/lr-lib.sh"; lr_claim_stamp "$2" "$3" "$4" lr-move-worker "$5"' _ "$LRD" "$CLAIMS/$SID.active" "$SID" "$WPID" "$PANE"
  fi
  WRC=0; wait "$WPID" || WRC=$?
}
res() { jq -r ".$1" "$BDIR/$SID.json"; }
invoked() { [ -s "$STUB_LOG/typers.log" ]; }

@test "1 [RED] an idle session is moved: MOVED from disk, claim and slot released, every stage timestamped" {
  worker
  [ "$WRC" -eq 0 ]
  [ "$(res verdict)" = MOVED ]
  [ "$(res conjuncts)" = 1111111 ]
  [ ! -d "$CLAIMS/$SID.active" ]
  [ -z "$(ls -A "$LR_STATE_DIR/locks/swap-slots" 2>/dev/null)" ]
  for st in spawned claimed fenced slot actuate proof-first result; do
    grep -q "\"stage\":\"$st\"" "$BDIR/$SID.events.jsonl"
  done
}

@test "2 [RED] the actuator gets the operator intent, no prompt, no replace, and swap admission" {
  worker
  grep -q -- "--voluntary --operator-intent $BDIR/intent/$SID.json --no-prompt --no-replace" "$STUB_LOG/argv.log"
  grep -q -- "--in-place --source-pane $PANE " "$STUB_LOG/argv.log"
  grep -q "^$SID admit=swap placed=cc-lr-move bgwork=stop-if-watcher rec=move-w1-bbbb2222$" "$STUB_LOG/env.log"
}

@test "3 the slot was held while the actuator ran (taken BEFORE the /exit)" {
  worker
  [ "$(cat "$STUB_LOG/slots.log")" = 1 ]
}

@test "4 a hold from the actuator (rc 6) is NOTMOVED with its reason, and the session is still on the source" {
  export STUB_MODE=hold
  worker
  [ "$WRC" -eq 3 ]
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == "HELD:busy"* ]] || false
  [ -f "$SRC/projects/-x/$SID.jsonl" ]
  [ ! -d "$CLAIMS/$SID.active" ]
}

@test "5 a claim that does not name this worker: NOTMOVED claim-lost, the actuator is never invoked" {
  export LR_MOVE_CLAIM_WAIT_N=2
  worker no
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == claim-lost:* ]] || false
  ! invoked
}

@test "6 an aborted batch: NOTMOVED before the move, the actuator is never invoked" {
  : > "$BDIR/abort"
  worker
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == aborted* ]] || false
  ! invoked
}

@test "7 [RED] no free slot: the session waits ALIVE, then NOTMOVED capacity; the actuator is never invoked" {
  # one slot (the plan's width), held by a live process
  MVF_SLOTS=1 mvf_plan w1 move "$PANE:$SID"
  mkdir -p "$LR_STATE_DIR/locks/swap-slots/slot-1"
  bash -c '. "$1/lr-lib.sh"; lr_pidlock_stamp "$2" "$3"' _ "$LRD" "$LR_STATE_DIR/locks/swap-slots/slot-1" "$MVF_PID"
  export LR_MOVE_SLOT_WAIT_S=1
  worker
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == capacity:* ]] || false
  ! invoked || false
  kill -0 "$MVF_PID"
  [ -f "$SRC/projects/-x/$SID.jsonl" ]
}

@test "8 a slot whose holder is DEAD (or whose pid was reused) is taken over, and the move proceeds" {
  MVF_SLOTS=1 mvf_plan w1 move "$PANE:$SID"
  mkdir -p "$LR_STATE_DIR/locks/swap-slots/slot-1"
  echo "$MVF_PID" > "$LR_STATE_DIR/locks/swap-slots/slot-1/pid"
  echo "Thu Jan 1 00:00:00 1970" > "$LR_STATE_DIR/locks/swap-slots/slot-1/lstart"
  worker
  [ "$(res verdict)" = MOVED ]
}

@test "9 the session dies during the move: STRANDED, named from disk" {
  export STUB_MODE=strand LR_MOVE_PROVE_S=2
  worker
  [ "$WRC" -eq 1 ]
  [ "$(res verdict)" = STRANDED ]
}

@test "10 [RED] a move that leaves a foreign tombstone in the target is FAILED on P4, never MOVED" {
  export STUB_MODE=tomb LR_MOVE_PROVE_S=2
  worker
  [ "$(res verdict)" = FAILED ]
  [[ "$(res reason)" == "P4 tombstone:"* ]]
}

@test "11 a wait row moves only after the shared census says move on two snapshots" {
  MVF_UNTIL=20 mvf_plan w1 wait "$PANE:$SID"
  snap() { printf '%s\t%s\tnext4\t%s\t/x\t1\t%s\n' "$PANE" "$SID" "$SRC" "$1" > "$BDIR/snap.tsv"; date +%s%N > "$BDIR/snap.ts"; }
  snap mid-turn
  bash "$LRD/lr-move-worker.sh" w1 "$SID" > "$BATS_TEST_TMPDIR/worker.out" 2>&1 3>&- &
  WPID=$!
  mkdir -p "$CLAIMS/$SID.active"
  bash -c '. "$1/lr-lib.sh"; lr_claim_stamp "$2" "$3" "$4" lr-move-worker "$5"' _ "$LRD" "$CLAIMS/$SID.active" "$SID" "$WPID" "$PANE"
  sleep 1.5
  ! invoked || false
  [ -e "$BDIR/$SID.waiting" ]
  snap move; sleep 1; snap move
  WRC=0; wait "$WPID" || WRC=$?
  [ "$(res verdict)" = MOVED ]
  [ ! -e "$BDIR/$SID.waiting" ]
}

@test "12 a wait row that stays busy past its budget: NOTMOVED still-busy, never invoked" {
  MVF_UNTIL=2 mvf_plan w1 wait "$PANE:$SID"
  printf '%s\t%s\tnext4\t%s\t/x\t1\tmid-turn\n' "$PANE" "$SID" "$SRC" > "$BDIR/snap.tsv"; echo 1 > "$BDIR/snap.ts"
  worker
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == still-busy:mid-turn* ]] || false
  ! invoked
}

@test "13 KILL SWITCH: LR_MOVE_LANE=off — NOTMOVED, nothing claimed, nothing invoked" {
  export LR_MOVE_LANE=off
  worker
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == "LR_MOVE_LANE=off"* ]] || false
  ! invoked
}

@test "14 the worker never types a prompt and never mails: no cc_tui_submit, no cc-notify in the lane's worker" {
  ! grep -q 'cc_tui_submit\|cc-notify\|cc_tui_type' "$LRD/lr-move-worker.sh"
}
