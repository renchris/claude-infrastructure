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
worker() { # [claim: yes|no]   WORKER_BASH names the interpreter (default: PATH bash)
  "${WORKER_BASH:-bash}" "$LRD/lr-move-worker.sh" w1 "$SID" > "$BATS_TEST_TMPDIR/worker.out" 2>&1 3>&- &
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

@test "7 [RED] no free slot: the session waits ALIVE, then NOTMOVED slot-wait (never 'capacity'); the actuator is never invoked" {
  # one slot (the plan's width), held by a live process
  MVF_SLOTS=1 mvf_plan w1 move "$PANE:$SID"
  mkdir -p "$LR_STATE_DIR/locks/swap-slots/slot-1"
  bash -c '. "$1/lr-lib.sh"; lr_pidlock_stamp "$2" "$3"' _ "$LRD" "$LR_STATE_DIR/locks/swap-slots/slot-1" "$MVF_PID"
  export LR_MOVE_SLOT_WAIT_S=1
  worker
  [ "$(res verdict)" = NOTMOVED ]
  # A queue timeout on a fixed width is not a memory refusal and must not read as one: until
  # 2026-10-06 both said `capacity:`, which is how "recovery is throttled by memory" got its evidence.
  [[ "$(res reason)" == "slot-wait: no move slot freed in 1s (width 1, a fixed count, not a memory limit)"* ]] || { res reason; false; }
  [[ "$(res reason)" != capacity:* ]] || false
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

# ── A SESSION THAT HIT ITS LIMIT AFTER THE PLAN WAS WRITTEN (2026-10-06) ─────────────────────────
# The plan holds a limit-blocked session (`hold:limited`), but it reads the transcript once. A row
# that waits for idle, or queues for a slot, can hit its limit in between; the census the wait loop
# reads calls an api-error tail "at rest", so the row was promoted and restarted with no prompt:
# reported MOVED, sitting on the target with its limit error unanswered.
limit_tail() { # the last assistant record becomes a usage-limit error, as the client writes it
  printf '%s\n' '{"type":"assistant","timestamp":"2026-10-06T06:20:00.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 7:50pm"}]}}' \
    >> "$SRC/projects/-x/$SID.jsonl"
}

@test "15 [RED] a wait row that hit its limit while waiting is NOTMOVED became-limited, never restarted without a prompt" {
  MVF_UNTIL=20 mvf_plan w1 wait "$PANE:$SID"
  limit_tail
  # the census, as it reads such a session: at rest, composer empty → `move`, twice
  printf '%s\t%s\tnext4\t%s\t/x\t1\tmove\n' "$PANE" "$SID" "$SRC" > "$BDIR/snap.tsv"; echo 1 > "$BDIR/snap.ts"
  bash "$LRD/lr-move-worker.sh" w1 "$SID" > "$BATS_TEST_TMPDIR/worker.out" 2>&1 3>&- &
  WPID=$!
  mkdir -p "$CLAIMS/$SID.active"
  bash -c '. "$1/lr-lib.sh"; lr_claim_stamp "$2" "$3" "$4" lr-move-worker "$5"' _ "$LRD" "$CLAIMS/$SID.active" "$SID" "$WPID" "$PANE"
  sleep 1; echo 2 > "$BDIR/snap.ts"
  WRC=0; wait "$WPID" || WRC=$?
  # RED before the fix: MOVED, and the actuator was invoked.
  [ "$(res verdict)" = NOTMOVED ] || { res verdict; res reason; false; }
  [[ "$(res reason)" == became-limited:* ]] || { res reason; false; }
  ! invoked || false
  [ -f "$SRC/projects/-x/$SID.jsonl" ]
  [ ! -d "$CLAIMS/$SID.active" ]
}

@test "16 an idle move row whose session hit its limit after the plan was written is NOTMOVED became-limited" {
  limit_tail
  worker
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == became-limited:*"cc-lr recover ${SID:0:8}"* ]] || { res reason; false; }
  ! invoked || false
  [ -z "$(ls -A "$LR_STATE_DIR/locks/swap-slots" 2>/dev/null)" ]
}

# ── THE MEMORY READ, WITH THE GATE ON (replay of batch 20261006T060534Z-next3-next2-64630) ───────
# Every other case here runs with LR_MOVE_KERNEL_CHECK=off (the fixture), so before 2026-10-06 the
# move lane's memory read had no test at all: deleting it turned nothing red. These two turn it on
# and pin the readings. The first uses what the record holds for that batch's seven workers
# (~/.claude/autonomy/idl.jsonl, caller lr-move-worker: reclaimable 32.98-34.75 GB against the 4 GB
# floor, compressor segments 4.33-4.50% against the 90% swap ceiling; 8 of 8 admitted). The second
# is the positive arm: a reading past the ceiling refuses before anything is touched.
kernel_on() { # <reclaimable GB> <segments %>
  unset CC_ADMIT_GATE
  export LR_MOVE_KERNEL_CHECK=on CC_ADMIT_HEADROOM_OVERRIDE="$1" CC_ADMIT_SEGMENT_OVERRIDE="$2"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl" CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit-state" CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"
}

@test "17 replay 20261006T060534Z: with the memory read ON at the recorded readings (32.98 GB, 4.50%) the move is admitted" {
  kernel_on 32.98 4.50
  worker
  [ "$(res verdict)" = MOVED ] || { res verdict; res reason; cat "$BDIR/$SID.capacity.log"; false; }
  # the read really ran: one admit row for this caller, on the two memory terms only
  [ "$(jq -r 'select(.caller == "lr-move-worker") | .verdict' "$CC_ADMIT_IDL" | sort -u)" = admit ] || { cat "$CC_ADMIT_IDL"; false; }
  jq -e 'select(.caller == "lr-move-worker") | .terms | test("headroom") and test("segments") and (test("active") | not) and (test("load") | not)' "$CC_ADMIT_IDL" >/dev/null \
    || { cat "$CC_ADMIT_IDL"; false; }
}

@test "18 the memory read can refuse: segments at 95% is NOTMOVED capacity, the actuator is never invoked, the slot is released" {
  kernel_on 32.98 95
  worker
  [ "$(res verdict)" = NOTMOVED ] || { res verdict; res reason; false; }
  [[ "$(res reason)" == capacity:*segments* ]] || { res reason; false; }
  ! invoked || false
  kill -0 "$MVF_PID"
  [ -z "$(ls -A "$LR_STATE_DIR/locks/swap-slots" 2>/dev/null)" ]
  # control for this case: the same session at the recorded reading moves (case 17)
}

@test "19 a real plan carries no .slots, and the worker then uses the default width of 4 (stated in its slot-wait event)" {
  # mvf_plan always writes .slots; `cc-lr move` writes it only under --slots, and the recorded
  # batch's plan has none, so the default was the one width no case observed.
  jq -c 'del(.slots)' "$BDIR/plan.json" > "$BDIR/plan.json.t" && mv "$BDIR/plan.json.t" "$BDIR/plan.json"
  unset LR_MOVE_SLOTS
  worker
  [ "$(res verdict)" = MOVED ]
  grep -q '"stage":"slot-wait".*"detail":"width 4"' "$BDIR/$SID.events.jsonl" || { cat "$BDIR/$SID.events.jsonl"; false; }
}

# The poller's PATH is /usr/bin:/bin:/usr/sbin:/sbin and the batch runner starts each worker with
# /bin/bash, so in production this file runs under bash 3.2. Every case above runs it under PATH
# bash (5.x), which is how the batch runner's roll-up defect stayed green for its whole life.
@test "20 the worker under /bin/bash (the interpreter launchd gives it): an idle session is MOVED" {
  [ -x /bin/bash ] || skip "/bin/bash absent"
  WORKER_BASH=/bin/bash worker
  [ "$WRC" -eq 0 ] || { cat "$BATS_TEST_TMPDIR/worker.out"; false; }
  [ "$(res verdict)" = MOVED ] || { res reason; false; }
  ! grep -qi 'syntax error\|bad substitution\|command not found' "$BATS_TEST_TMPDIR/worker.out" || { cat "$BATS_TEST_TMPDIR/worker.out"; false; }
}
