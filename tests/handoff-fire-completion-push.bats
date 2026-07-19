#!/usr/bin/env bats
# T-P2-1 — handoff-fire.sh self-close --terminal wires F5 completion-push (the terminal caller). A
# --terminal close is a PROGRAM-TERMINAL completion (nothing continues) → it pushes to the desk role via
# completion-push (F5 → cc-announce F1), so the terminal claim reaches the desk and is NEVER silent (the
# W5 shape: a ship reached the desk 50 min late). Until this caller completion-push was DEAD (p02 §2c).
# NON-FATAL: a push failure is recorded LOUD (exit 5) but never aborts the close. NOT on --successor
# (work continues) and NOT on --dry-run (no real side effect).
#
# The real-fire path runs osascript/detach after the push; the push fires FIRST (capture-before-notify),
# so a timeout-bounded run still captures the push side effect. self-close operates in $PWD, so tests cd
# to a non-git tmpdir (the dirty-tree guard is then skipped) and stub CC_COMPLETION_PUSH_BIN.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"
  MARK="$BATS_TEST_TMPDIR/pushed.log"
  # stub completion-push: records its argv, exits 0 (verified) unless STUB_RC overrides.
  STUB="$BATS_TEST_TMPDIR/cp-stub.sh"
  { printf '#!/bin/bash\n'
    printf 'printf "%%s\\n" "CALLED $*" >> "%s"\n' "$MARK"
    printf 'exit "${STUB_RC:-0}"\n'; } > "$STUB"
  chmod +x "$STUB"
  cd "$WORK"   # self-close operates in $PWD — a non-git dir skips the dirty-tree guard (the worktree is dirty during dev)
}

@test "--terminal --dry-run → shows the completion-push PLAN, fires nothing (stub not called)" {
  run env CC_COMPLETION_PUSH_BIN="$STUB" bash "$HF" self-close --terminal --session-id "fake:AAAA-1111" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"completion:"* ]]
  [[ "$output" == *"F5 / T-P2-1"* ]]
  [ ! -f "$MARK" ]     # dry-run must not fire a real push
}

@test "--terminal (real) → completion-push CALLED with --role desk and the terminal event" {
  ( cd "$WORK" && CC_COMPLETION_PUSH_BIN="$STUB" timeout 6 bash "$HF" self-close --terminal --session-id "fake:BBBB-2222" ) >/dev/null 2>&1 || true
  grep -q 'CALLED fire --role desk' "$MARK"
  grep -q -- '--from handoff-fire' "$MARK"
  grep -q -- 'self-closed (--terminal' "$MARK"
}

@test "--terminal + push FAILS (exit 5) → LOUD 'did NOT verify', close is NOT aborted by it" {
  run bash -c "cd '$WORK' && CC_COMPLETION_PUSH_BIN='$STUB' STUB_RC=5 timeout 6 bash '$HF' self-close --terminal --session-id 'fake:CCCC-3333' 2>&1"
  [[ "$output" == *"did NOT verify"* ]]
  [[ "$output" == *"proceeding with the close"* ]]
  grep -q 'CALLED' "$MARK"     # the push WAS attempted (recorded LOUD, never silent)
}

@test "--successor <dead pane> → aborts at the liveness gate (exit 3) BEFORE any completion push" {
  run env CC_COMPLETION_PUSH_BIN="$STUB" bash "$HF" self-close --successor "NOPANE-4444" --session-id "fake:DDDD-4444"
  [ "$status" -eq 3 ]
  [ ! -f "$MARK" ]     # a successor close is NOT terminal — no push
}

@test "--successor liveness gate is load-robust: a failing tty query does NOT leak a non-3 exit (T-P2-1)" {
  # RED-provable guard for the concurrent-load flake that reds the shared ship-land gate. Under iTerm2
  # AppleScript-bridge contention as_tty's osascript errors NON-ZERO; a bare `SUC_TTY="$(as_tty …)"` under
  # `set -e` then LEAKED that code (status 1/128+sig), NOT the gate's intended `exit 3` — the same CLASS as
  # cc-run 846380c6308f. The seam HANDOFF_TTY_FAIL_FILE fails EVERY query (count 4 > RETRIES 3), so the run
  # never touches real iTerm2 — the only way to reach exit 3 is the fixed as_tty retrying past the failures
  # then classifying the unresolved pane as absent. A naive as_tty (no retry / no set-e guard) leaks status
  # 1 here instead. RETRY_SLEEP_S=0 keeps it instant.
  local failf="$BATS_TEST_TMPDIR/ttyfail"; printf '4\n' > "$failf"
  run env CC_COMPLETION_PUSH_BIN="$STUB" \
      HANDOFF_TTY_FAIL_FILE="$failf" HANDOFF_TTY_RETRIES=3 HANDOFF_TTY_RETRY_SLEEP_S=0 \
      bash "$HF" self-close --successor "NOPANE-5150" --session-id "fake:FFFF-5150"
  [ "$status" -eq 3 ]                       # NOT a leaked osascript code — the flake this fixes
  [ ! -f "$MARK" ]                          # still aborts BEFORE any completion push
  [ "$(cat "$failf")" -eq 1 ]              # seam consumed on all 3 retries (4→1) — proves the query was retried
}

@test "real completion-push (default bin resolution) → a completion-push RECORD, verdict verified" {
  local roles="$BATS_TEST_TMPDIR/roles" recs="$BATS_TEST_TMPDIR/records"
  mkdir -p "$roles"; printf 'DESK-UUID-1\n' > "$roles/desk"
  local ccn="$BATS_TEST_TMPDIR/ccn.sh"
  { printf '#!/bin/bash\n'; printf 'echo "cc-notify: delivered to T (composer + mailbox; submit VERIFIED)" >&2\nexit 0\n'; } > "$ccn"
  chmod +x "$ccn"
  ( cd "$WORK" && \
    CC_NOTIFY_BIN="$ccn" CC_ROLES_DIR="$roles" CC_COMPLETION_RECORDS_DIR="$recs" \
    CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/al" CC_ANNOUNCE_RETRY_SLEEP=0 \
    timeout 6 bash "$HF" self-close --terminal --session-id "fake:EEEE-5555" ) >/dev/null 2>&1 || true
  local rec; rec="$(find "$recs" -name 'push-*.json' 2>/dev/null | head -1)"
  [ -n "$rec" ]
  [ "$(jq -r '.verdict' "$rec")" = "verified" ]
  [ "$(jq -r '.role' "$rec")" = "desk" ]
}
