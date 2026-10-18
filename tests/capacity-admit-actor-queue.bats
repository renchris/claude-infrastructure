#!/usr/bin/env bats
# scripts/lib/capacity-admit.sh — the budget key carries the ACTOR, and a QUEUED request is bounded
# by the clock (lr-wake incident 2026-10-18, REPORT §4 Wave B step 4).
#
# THE DEFECTS. (1) `lr-fire-resume.direct-<sid>.refusals` was one counter for every process that
# resumed that sid, so a rescue agent's three refusals of 5232121f released the POLLER's spawn of the
# same sid into a box still at 9 mid-turn (c2 Correction 1). (2) The only release was the count, which
# only re-running can reach, and the refusal text said so ("the next evaluation ADMITS") — an agent
# quoted it back as its reason to fire again. A request waiting in the durable queue now carries
# CC_ADMIT_QUEUED_SINCE: it charges nothing and admits once LR_CAPACITY_QUEUE_MAX_S has passed.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/capacity-admit.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ADMIT_NOTIFY_BIN="$BATS_TEST_TMPDIR/notify"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/pages.txt"\n' "$BATS_TEST_TMPDIR" > "$CC_ADMIT_NOTIFY_BIN"
  chmod +x "$CC_ADMIT_NOTIFY_BIN"
  # 50 on 10 cores is over every load ceiling, so the load term refuses; the other terms are quiet
  export CC_ADMIT_LOADAVG_OVERRIDE=50 CC_ADMIT_HEADROOM_OVERRIDE=64 CC_ADMIT_SEGMENT_OVERRIDE=1
  export CC_ADMIT_ACTIVE_TERM=off CC_ADMIT_RESERVE_TERM=off CC_ADMIT_BUDGET=3
  export CC_ADMIT_SYSCTL="$BATS_TEST_TMPDIR/sysctl"
  printf '#!/usr/bin/env bash\ncase "$*" in *hw.ncpu*) echo 10 ;; *vm.loadavg*) echo "{ 1.00 1.00 1.00 }" ;; *) echo 0 ;; esac\n' > "$CC_ADMIT_SYSCTL"
  chmod +x "$CC_ADMIT_SYSCTL"
  unset CC_ADMIT_ACTOR CC_ADMIT_QUEUED_SINCE LR_CAPACITY_QUEUE_MAX_S CC_ADMIT_GATE
  SID="5232121f-0000-4000-8000-000000000001"
  # shellcheck disable=SC1090  # the subject under test, resolved from $REPO at run time
  . "$LIB"
}

# the in-pane call, exactly as lr-fire-resume.sh makes it on the direct path
pane_admit() { CC_ADMIT_BUDGET_KEY="direct-$SID" cc_capacity_admit lr-fire-resume "resume $SID on next2"; }

@test "the rescue's three refusals do NOT release the poller's spawn of the same sid" {
  for _ in 1 2 3; do run pane_admit; [ "$status" -eq 9 ]; done    # the hand-fired rescue, no actor
  CC_ADMIT_ACTOR=poller run pane_admit
  [ "$status" -eq 9 ]
  [[ "$output" != *ADMIT* ]] || false
  grep -q 'refusal 1 of budget 3' <(tail -n 1 "$CC_ADMIT_IDL") || { tail -n 1 "$CC_ADMIT_IDL"; false; }
  [ "$(cat "$CC_ADMIT_STATE_DIR/lr-fire-resume.direct-$SID.by-poller.refusals")" = 1 ]
  ! grep -q budget-expired "$CC_ADMIT_IDL"
}

@test "CONTROL — the same actor's fourth evaluation is still released by its own count" {
  for _ in 1 2 3; do CC_ADMIT_ACTOR=poller run pane_admit; [ "$status" -eq 9 ]; done
  CC_ADMIT_ACTOR=poller run pane_admit
  [ "$status" -eq 0 ]
  [ "$(jq -r .basis <(tail -n 1 "$CC_ADMIT_IDL"))" = budget-expired ]
}

@test "no actor ⇒ the key is byte-identical to before (the direct and fleet paths are unchanged)" {
  run pane_admit
  [ "$status" -eq 9 ]
  [ -f "$CC_ADMIT_STATE_DIR/lr-fire-resume.direct-$SID.refusals" ]
  CC_ADMIT_ACTOR='bad/actor' run pane_admit                         # unusable ⇒ dropped, never a path
  [ "$(cat "$CC_ADMIT_STATE_DIR/lr-fire-resume.direct-$SID.refusals")" = 2 ]
}

@test "the refusal text no longer invites a re-run" {
  pane_admit || true
  pane_admit || true
  [[ "$(cc_capacity_admit_reason)" == *"(refusal 2 of 3)" ]] || { cc_capacity_admit_reason; false; }
  [[ "$(cc_capacity_admit_reason)" != *ADMITS* ]] || false
  [ "$(cc_capacity_admit_refused_term)" = load ]
}

@test "a QUEUED request charges nothing and is never released by re-runs inside its bound" {
  export CC_ADMIT_QUEUED_SINCE="$(( $(date +%s) - 60 ))" LR_CAPACITY_QUEUE_MAX_S=2700
  for _ in 1 2 3 4 5; do run pane_admit; [ "$status" -eq 9 ]; done
  [ ! -s "$CC_ADMIT_STATE_DIR/lr-fire-resume.direct-$SID.refusals" ]
  [ "$(jq -r .basis <(tail -n 1 "$CC_ADMIT_IDL"))" = queued ]
  pane_admit || true
  [[ "$(cc_capacity_admit_reason)" == *"queued "*"s of 2700s; the queue retries it, nothing to re-run)" ]] || { cc_capacity_admit_reason; false; }
  [ ! -f "$BATS_TEST_TMPDIR/pages.txt" ]
}

@test "a QUEUED request past LR_CAPACITY_QUEUE_MAX_S admits and pages once; a probe says the same and pages nothing" {
  export CC_ADMIT_QUEUED_SINCE="$(( $(date +%s) - 3000 ))" LR_CAPACITY_QUEUE_MAX_S=2700
  run cc_capacity_probe lr-reset-poller "resume $SID"
  [ "$status" -eq 0 ]
  [ "$(jq -r .basis <(tail -n 1 "$CC_ADMIT_IDL"))" = queue-expired ]
  [ ! -f "$BATS_TEST_TMPDIR/pages.txt" ]
  run pane_admit
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/pages.txt")" = 1 ]
  [ ! -s "$CC_ADMIT_STATE_DIR/lr-fire-resume.direct-$SID.refusals" ]
}

@test "an unusable CC_ADMIT_QUEUED_SINCE falls back to the count bound (bounded either way)" {
  export CC_ADMIT_QUEUED_SINCE=yesterday
  for _ in 1 2 3; do run pane_admit; [ "$status" -eq 9 ]; done
  run pane_admit
  [ "$status" -eq 0 ]
  [ "$(jq -r .basis <(tail -n 1 "$CC_ADMIT_IDL"))" = budget-expired ]
}
