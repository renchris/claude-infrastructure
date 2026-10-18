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
teardown() {
  # 11g/11h leave a worker inside a 900 s idle wait when they fail (or by design); end it here
  [ -z "${WAIT_WPID:-}" ] || kill "$WAIT_WPID" 2>/dev/null || true
  mvf_teardown
}

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
# wstart <sid> <pane> → that sid's worker running in the background (WPID), its claim stamped to it
wstart() {
  "${WORKER_BASH:-bash}" "$LRD/lr-move-worker.sh" w1 "$1" > "$BATS_TEST_TMPDIR/worker.$1.out" 2>&1 3>&- &
  WPID=$!
  mkdir -p "$CLAIMS/$1.active"
  bash -c '. "$1/lr-lib.sh"; lr_claim_stamp "$2" "$3" "$4" lr-move-worker "$5"' _ "$LRD" "$CLAIMS/$1.active" "$1" "$WPID" "$2"
}
# await_stage <sid> <stage> [bound s, default 120] → 0 once that worker has logged the stage. Waits
# on the worker's own event, never a fixed sleep: at load ~300 (2026-10-18) a worker took more than
# 1.5 s to reach its idle wait, and case 11's `sleep 1.5` convicted a correct worker.
await_stage() {
  local i=0 n=$(( ${3:-120} * 5 ))
  until grep -q "\"stage\":\"$2\"" "$BDIR/$1.events.jsonl" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt "$n" ] || { cat "$BDIR/$1.events.jsonl" 2>/dev/null; return 1; }
    sleep 0.2
  done
}
# ts_feed <worker pid> — a fresh census timestamp every 0.5 s while that worker lives, as the batch
# runner's census keeps writing them. A single short-lived snapshot is missed by a worker whose poll
# is slower than it.
ts_feed() {
  ( i=2; while kill -0 "$1" 2>/dev/null; do sleep 0.5; echo "feed-$i" > "$BDIR/snap.ts"; i=$((i + 1)); done ) 3>&- &
}

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

# Move batch 20261011T190215Z, pane 124: lr-handoff returned rc 0 unawaited, then its watcher held at
# the background-work dialog after the confirm. Once the watcher hands the source back (handoff-fire
# rcy_bgwork_unconfirm) the session is on the source, one copy: a hold, named from the row at once.
# Mutant: drop the watcher-row finish in the NOTMOVED arm (the worker waits out its bound instead).
@test "4b [RED] rc 0, then the watcher held after the confirm and unconfirmed: NOTMOVED HELD:bg-work, without waiting out the bound" {
  export STUB_MODE=watcher-hold LR_MOVE_PROVE_S=6
  worker
  [ "$(res verdict)" = NOTMOVED ] || { res verdict; res reason; false; }
  [[ "$(res reason)" == "HELD:bg-work"* ]] || { res reason; false; }
  [ -f "$SRC/projects/-x/$SID.jsonl" ]
  # A row whose unconfirm did NOT take is no such hold: the bound runs out and the reason says so.
  rm -f "$BDIR/$SID.json" "$HOME/.claude/logs/handoffs.jsonl"
  STUB_HOLD_DETAIL="background-work dialog at 30s cancelled with Esc; nothing typed; unconfirm rc 2; unconfirm=needed" worker
  [ "$(res verdict)" = NOTMOVED ] || { res verdict; res reason; false; }
  [[ "$(res reason)" != "HELD:"* ]] || { res reason; false; }
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
  MVF_UNTIL=60 mvf_plan w1 wait "$PANE:$SID"   # 20 s ran out at load ~270-390 (2026-10-18): still-busy:move
  snap() { printf '%s\t%s\tnext4\t%s\t/x\t1\t%s\n' "$PANE" "$SID" "$SRC" "$1" > "$BDIR/snap.tsv"; date +%s%N > "$BDIR/snap.ts"; }
  snap mid-turn
  wstart "$SID" "$PANE"
  await_stage "$SID" waiting; sleep 1
  ! invoked || false
  [ -e "$BDIR/$SID.waiting" ]
  snap move; ts_feed "$WPID"
  WRC=0; wait "$WPID" || WRC=$?
  [ "$(res verdict)" = MOVED ] || { res verdict; res reason; false; }
  [ ! -e "$BDIR/$SID.waiting" ]
}

@test "11g [RED] a wait row whose session left the census on two snapshots: NOTMOVED gone at once, not at the budget" {
  # raw/E R1 (2026-10-18): rows whose session had moved or died waited out 9-28 min of budget,
  # because only `move` ends the wait and a sid absent from snap.tsv reads as "not move yet".
  MVF_UNTIL=900 mvf_plan w1 wait "$PANE:$SID"
  printf '%s\t%s\tnext4\t%s\t/x\t1\tmid-turn\n' 99 "cccc3333-0000-4000-8000-000000000009" "$SRC" > "$BDIR/snap.tsv"
  echo feed-1 > "$BDIR/snap.ts"
  wstart "$SID" "$PANE"; WAIT_WPID="$WPID"
  ts_feed "$WPID"
  # a wall-clock bound on the result, a third of the 900 s budget: gone is two snapshots and a few
  # polls; at load ~120 (2026-10-18) the worker took 42 s just to reach its wait, and a poll COUNT
  # of sleeps stretched 4x, so the bound is in seconds, not iterations
  end=$(( $(date +%s) + 300 ))
  until [ -s "$BDIR/$SID.json" ] || [ "$(date +%s)" -ge "$end" ]; do sleep 0.2; done
  [ -s "$BDIR/$SID.json" ]
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == gone:* ]] || { res reason; false; }
  ! invoked || false
}

@test "11h a wait row absent from ONE snapshot and back in the next keeps waiting" {
  MVF_UNTIL=900 mvf_plan w1 wait "$PANE:$SID"
  : > "$BDIR/snap.tsv"; echo feed-1 > "$BDIR/snap.ts"
  wstart "$SID" "$PANE"; WAIT_WPID="$WPID"
  await_stage "$SID" waiting
  # the worker has read the absent snapshot once it logs `waiting` and polls; then the row returns
  i=0; until [ "$i" -ge 10 ]; do sleep 0.2; i=$((i + 1)); done
  printf '%s\t%s\tnext4\t%s\t/x\t1\tmid-turn\n' "$PANE" "$SID" "$SRC" > "$BDIR/snap.tsv"
  ts_feed "$WPID"
  i=0; until [ "$i" -ge 25 ]; do sleep 0.2; i=$((i + 1)); done
  [ ! -s "$BDIR/$SID.json" ] || { res verdict; res reason; false; }
  kill -0 "$WPID"
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
  MVF_UNTIL=60 mvf_plan w1 wait "$PANE:$SID"   # 20 s ran out at load ~270-390 (2026-10-18): still-busy:move
  limit_tail
  # the census, as it reads such a session: at rest, composer empty → `move`, twice
  printf '%s\t%s\tnext4\t%s\t/x\t1\tmove\n' "$PANE" "$SID" "$SRC" > "$BDIR/snap.tsv"; echo 1 > "$BDIR/snap.ts"
  wstart "$SID" "$PANE"
  ts_feed "$WPID"
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

# ── THE INTENT, RE-CHECKED WHILE THE WORKER WAITS (2026-10-18) ───────────────────────────────────
# Batch 69593's four rows held all 4 swap slots for 107-116 s, then lr-handoff refused each as
# intent-invalid (expired 902-904 s earlier); the worker had never looked. Each case below lets the
# intent lapse at one hold and is RED on a worker that leaves the check to lr-handoff. The cases
# run the worker under /bin/bash, the interpreter launchd gives it, and the polling ones set
# LR_MOVE_INTENT_RECHECK_S=0 so every poll re-reads (the production default is every 30 s).
expire_intent() { # <sid> <epoch> — the intent's act-by moved to <epoch>; still 0600, as the lane writes it
  local f="$BDIR/intent/$1.json"
  ( umask 077; jq -c --argjson e "$2" '.expires_epoch = $e' "$f" > "$f.t" ) && mv -f "$f.t" "$f"
}
hold_slot() { # <slot index> — a live `sleep` holds that swap slot
  mkdir -p "$LR_STATE_DIR/locks/swap-slots/slot-$1"
  bash -c '. "$1/lr-lib.sh"; lr_pidlock_stamp "$2" "$3"' _ "$LRD" "$LR_STATE_DIR/locks/swap-slots/slot-$1" "$MVF_PID"
}

@test "21 [RED] the intent lapses while the row waits for a slot: NOTMOVED intent-invalid in seconds, not at the slot timeout; never invoked" {
  [ -x /bin/bash ] || skip "/bin/bash absent"
  MVF_SLOTS=1 mvf_plan w1 move "$PANE:$SID"
  hold_slot 1
  export LR_MOVE_SLOT_WAIT_S=45 WORKER_BASH=/bin/bash LR_MOVE_INTENT_RECHECK_S=0
  wstart "$SID" "$PANE"
  await_stage "$SID" slot-wait
  expire_intent "$SID" "$(( $(date +%s) + 2 ))"
  WRC=0; wait "$WPID" || WRC=$?
  # RED before the fix: the worker sat out the 45 s slot wait and said `slot-wait:`. The reason is
  # the timing assertion: an intent-invalid verdict can only come from a re-check that beat the slot
  # deadline, where a wall-clock bound would only convict a slow box (bound-must-fit-the-band).
  [ "$(res verdict)" = NOTMOVED ] || { res verdict; res reason; false; }
  [[ "$(res reason)" == "intent-invalid: expired:"*"(re-checked by the worker before the move); nothing touched" ]] || { res reason; false; }
  ! invoked || false
  [ ! -d "$CLAIMS/$SID.active" ]
  # the worker holds no slot; the only one held is the `sleep`'s, untouched
  [ "$(ls "$LR_STATE_DIR/locks/swap-slots")" = slot-1 ]
  [ "$(cat "$LR_STATE_DIR/locks/swap-slots/slot-1/pid")" = "$MVF_PID" ]
  ! grep -qi 'syntax error\|bad substitution\|command not found' "$BATS_TEST_TMPDIR/worker.$SID.out" || { cat "$BATS_TEST_TMPDIR/worker.$SID.out"; false; }
}

@test "22 [RED] the intent lapses while a wait row waits for idle: NOTMOVED intent-invalid, never reaches the slot, never invoked" {
  [ -x /bin/bash ] || skip "/bin/bash absent"
  MVF_UNTIL=60 mvf_plan w1 wait "$PANE:$SID"
  printf '%s\t%s\tnext4\t%s\t/x\t1\tmid-turn\n' "$PANE" "$SID" "$SRC" > "$BDIR/snap.tsv"; echo 1 > "$BDIR/snap.ts"
  export WORKER_BASH=/bin/bash LR_MOVE_INTENT_RECHECK_S=0
  wstart "$SID" "$PANE"
  await_stage "$SID" waiting
  expire_intent "$SID" "$(( $(date +%s) - 1 ))"
  WRC=0; wait "$WPID" || WRC=$?
  # RED before the fix: still-busy:mid-turn after the whole 60 s budget.
  [ "$(res verdict)" = NOTMOVED ] || { res verdict; res reason; false; }
  [[ "$(res reason)" == "intent-invalid: expired:"* ]] || { res reason; false; }
  ! grep -q '"stage":"slot-wait"' "$BDIR/$SID.events.jsonl" || false
  ! invoked || false
  [ ! -e "$BDIR/$SID.waiting" ]
  [ ! -d "$CLAIMS/$SID.active" ]
}

@test "23 [RED] an intent already lapsed when the worker claims: NOTMOVED intent-invalid before the slot queue, never invoked" {
  [ -x /bin/bash ] || skip "/bin/bash absent"
  expire_intent "$SID" "$(( $(date +%s) - 900 ))"
  WORKER_BASH=/bin/bash worker
  # RED before the fix: the stub actuator (which checks nothing) ran, and the verdict was MOVED.
  [ "$WRC" -eq 3 ] || { res verdict; res reason; false; }
  [[ "$(res reason)" == "intent-invalid: expired: the intent expired "* ]] || { res reason; false; }
  grep -q '"stage":"claimed"' "$BDIR/$SID.events.jsonl"
  ! grep -q '"stage":"slot-wait"' "$BDIR/$SID.events.jsonl" || false
  ! invoked || false
  [ ! -d "$CLAIMS/$SID.active" ]
  [ -z "$(ls -A "$LR_STATE_DIR/locks/swap-slots" 2>/dev/null)" ]
}

# ── THE SLOT IN PLAN ORDER (2026-10-18) ──────────────────────────────────────────────────────────
# The plan lists its rows highest-activity first, but the slot was a free-for-all poll: whichever
# waiter's tick reached `mkdir` first after a release took it. Case 24 makes that race certain
# rather than likely: the rows ahead are frozen (SIGSTOP: alive, between two polls) at the instant
# the slot frees, so a free-for-all hands it to the last row on every run. Poll rates cannot set it
# up on a loaded box: at load ~390 an iteration's forks, not its sleep, set the pace, and a version
# that gave the later rows faster polls passed on the unfixed worker.
S1="bbbb2222-0000-4000-8000-000000000002"; S2="bbbb2222-0000-4000-8000-000000000003"
verdict_of() { jq -r .verdict "$BDIR/$1.json" 2>/dev/null; }
slot_free() { [ ! -d "$LR_STATE_DIR/locks/swap-slots/slot-1" ]; }

@test "24 [RED] one slot, three rows queued in reverse plan order: the actuator runs them in plan order" {
  [ -x /bin/bash ] || skip "/bin/bash absent"
  mvf_session 42 "$S1"; mvf_session 43 "$S2"
  MVF_SLOTS=1 mvf_plan w1 move "$PANE:$SID" "42:$S1" "43:$S2"
  hold_slot 1
  # the slot wait outlasts three worker starts and the frozen window on a loaded box
  export WORKER_BASH=/bin/bash LR_MOVE_SLOT_WAIT_S=600
  wstart "$S2" 43; P2=$WPID; await_stage "$S2" slot-wait
  wstart "$S1" 42; P1=$WPID; await_stage "$S1" slot-wait
  wstart "$SID" "$PANE"; P0=$WPID; await_stage "$SID" slot-wait
  # the holder lets go (as lr_swap_slot_release does) while the rows ahead are between polls
  kill -STOP "$P0" "$P1"
  rm -f "$LR_STATE_DIR/locks/swap-slots/slot-1/pid" "$LR_STATE_DIR/locks/swap-slots/slot-1/lstart"
  rmdir "$LR_STATE_DIR/locks/swap-slots/slot-1"
  # a free-for-all gives the last row the slot at its next poll; a yielding one leaves it free
  await_stage "$S2" slot 20 || true
  slot_ok=0; slot_free || slot_ok=1
  kill -CONT "$P0" "$P1"
  # RED before the fix: $S2 took the freed slot while the rows ahead of it were frozen.
  [ "$slot_ok" -eq 0 ] || { echo "the last row took the slot from the rows ahead"; cat "$BDIR/$S2.events.jsonl"; false; }
  grep -q '"stage":"slot-yield"' "$BDIR/$S2.events.jsonl"
  for p in "$P0" "$P1" "$P2"; do wait "$p" || true; done
  for s in "$SID" "$S1" "$S2"; do
    [ "$(verdict_of "$s")" = MOVED ] || { echo "$s: $(verdict_of "$s") $(jq -r .reason "$BDIR/$s.json" 2>/dev/null)"; false; }
  done
  [ "$(cut -d' ' -f1 "$STUB_LOG/typers.log" | tr '\n' ' ')" = "$SID $S1 $S2 " ] || { cat "$STUB_LOG/typers.log"; false; }
  # one at a time: every actuator ran holding the only slot
  [ "$(sort -u "$STUB_LOG/slots.log")" = 1 ]
  for s in "$SID" "$S1" "$S2"; do [ ! -e "$BDIR/$s.slotwait" ]; done
}

@test "25 [RED] a row ahead that died in the queue, its marker left behind, holds no one back; a live one does" {
  [ -x /bin/bash ] || skip "/bin/bash absent"
  mvf_session 42 "$S1"
  MVF_SLOTS=1 mvf_plan w1 move "$PANE:$SID" "42:$S1"
  export WORKER_BASH=/bin/bash LR_MOVE_SLOT_WAIT_S=3
  # control: the first row's worker is alive in the queue, so the second leaves the free slot to it
  printf '%s\n' "$MVF_PID" > "$BDIR/$SID.slotwait"
  wstart "$S1" 42; wait "$WPID" || true
  # RED before the fix: the second row took the free slot and was MOVED.
  [ "$(verdict_of "$S1")" = NOTMOVED ] || { verdict_of "$S1"; false; }
  [[ "$(jq -r .reason "$BDIR/$S1.json")" == "slot-wait:"*", and it yielded the free ones to rows ahead of it in the plan;"* ]] \
    || { jq -r .reason "$BDIR/$S1.json"; false; }
  grep -q '"stage":"slot-yield"' "$BDIR/$S1.events.jsonl"
  ! invoked || false
  # the same marker naming a dead worker (SIGKILL runs neither finish() nor the EXIT trap)
  sleep 0 3>&- & dead=$!; wait "$dead" || true
  printf '%s\n' "$dead" > "$BDIR/$SID.slotwait"
  rm -f "$BDIR/$S1.json" "$BDIR/$S1.events.jsonl"
  wstart "$S1" 42; wait "$WPID" || true
  [ "$(verdict_of "$S1")" = MOVED ] || { verdict_of "$S1"; jq -r .reason "$BDIR/$S1.json"; false; }
  ! grep -q '"stage":"slot-yield"' "$BDIR/$S1.events.jsonl" || false
}
