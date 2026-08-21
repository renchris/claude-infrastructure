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
#
# ── THE BOUND (2026-08-08) ───────────────────────────────────────────────────────────────────────────
# "NON-FATAL" above was enforced for a non-zero EXIT and for nothing else: an unbounded push has no arm a
# HANG can reach, and a --terminal close (pid 68958) sat 15+ min in completion-push → cc-announce, never
# retired its pane, and read as idle-not-done. The bound is the enforcement the contract always specified.
#
# 🚨 THE PRE-EXISTING TESTS IN THIS FILE CANNOT CATCH THAT, AND THAT IS WHY IT SHIPPED. They wrap the
# subject in `timeout 6 bash "$HF" … || true` — a bound in the HARNESS. Under it a hang and a clean close
# are the same observation, so the suite stayed green across the whole defect. The bound tests below
# therefore never bound the subject from outside as the pass condition: they set the SEAM
# (HANDOFF_COMPLETION_PUSH_TIMEOUT_S) and require the subject to return on its OWN, with the outer
# `timeout` present only as a backstop whose firing is a FAILURE (the mutation control inverts exactly
# this, and is the only test here that may legitimately hit it).

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
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

  # ORIGIN GATE (2026-07-26): self-close is available ONLY to a session FIRED BY an originator.
  # Completion-push IS the fired-peer path by definition — a peer finishing its assignment and
  # pushing completion back to whoever fired it — so stamp every pane id this suite drives.
  # Without this the origin gate refuses first (exit 2) and no push side effect is ever reached.
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  # HERMETICITY (measured leak, 2026-08-07): this suite drives the REAL self-close paths, whose
  # alarm sites call the live $HOME/.claude/bin/cc-notify — which honours these env seams. Without
  # them this suite wrote its fake-pane husk alarms into the OPERATOR'S live stores: 370 of 395
  # HANDOFF-HUSK-PANE lines in ~/.claude/mailbox (93.7% of all husk traffic) were this suite's
  # litter, drowning the 25 real alarms. Same law as the cc-notify.bats CC_COMMS_ALARM_DIR leak
  # (backlog 817faf3a4968): the seam belongs in setup(), per-test does not count.
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/comms-alarms"
  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/handoff-alarms"
  for _p in fake:AAAA-1111 fake:BBBB-2222 fake:CCCC-3333 fake:DDDD-4444 fake:EEEE-5555 fake:FFFF-5150; do
    # cwd is THIS PANE's cwd, not a hardcoded "/tmp": the origin gate tenancy-binds the stamp on cwd
    # (item aba6bcbff6de), and a placeholder path would make every pane here a stale tenant.
    printf '{"paneUUID":"%s","cwd":"%s","firedBy":"ORIGINATOR","firedAt":"2026-07-26T18:00:00Z","selfRetire":true}\n' \
      "$_p" "$PWD" > "$CC_FIRED_DIR/$_p.json"
  done
}

@test "--terminal --dry-run → shows the completion-push PLAN, fires nothing (stub not called)" {
  run env CC_COMPLETION_PUSH_BIN="$STUB" bash "$HF" self-close --terminal --session-id "fake:AAAA-1111" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"completion:"* ]] || false
  [[ "$output" == *"F5 / T-P2-1"* ]] || false
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
  [[ "$output" == *"did NOT verify"* ]] || false
  [[ "$output" == *"proceeding with the close"* ]] || false
  grep -q 'CALLED' "$MARK"     # the push WAS attempted (recorded LOUD, never silent)
}

@test "--successor <dead pane> → aborts at the liveness gate (exit 3) BEFORE any completion push" {
  run env CC_COMPLETION_PUSH_BIN="$STUB" bash "$HF" self-close --successor "NOPANE-4444" --session-id "fake:DDDD-4444"
  [ "$status" -eq 3 ]
  [ ! -f "$MARK" ]     # a successor close is NOT terminal — no push
}

@test "--successor liveness gate is load-robust: a failing tty query does NOT leak a raw osascript exit (T-P2-1)" {
  # RED-provable guard for the concurrent-load flake that reds the shared ship-land gate. Under iTerm2
  # AppleScript-bridge contention as_tty's osascript errors NON-ZERO; a bare `SUC_TTY="$(as_tty …)"` under
  # `set -e` then LEAKED that code (status 1/128+sig), NOT the gate's intended `exit 3` — the same CLASS as
  # cc-run 846380c6308f. The seam HANDOFF_TTY_FAIL_FILE fails EVERY query (count 4 > RETRIES 3), so the run
  # never touches real iTerm2 — the only way to reach a CLASSIFIED exit is the fixed as_tty retrying past
  # the failures and then reporting what it actually knows. A naive as_tty (no retry / no set-e guard)
  # leaks status 1 here instead. RETRY_SLEEP_S=0 keeps it instant.
  #
  # RE-KEYED 3 → 7 (item 87a515ed087e). This case's SUBJECT is unchanged — "a failing tty query does not
  # leak a raw osascript code" — and 7 discriminates from the leak (1 / 128+sig) exactly as 3 did. What
  # changed is the subject's honesty: every query here FAILED, so the resolver never answered, and the
  # old comment on this very line said the gate reached 3 by "classifying the unresolved pane as absent"
  # — naming the misclassification as the intent. Exit 3 is now reserved for a resolver that ANSWERED and
  # said the pane is not there; a resolver that never answered exits 7 and says so. The suite that pins
  # the split itself is tests/handoff-selfclose.bats § RESOLVER CANNOT TELL.
  local failf="$BATS_TEST_TMPDIR/ttyfail"; printf '4\n' > "$failf"
  run env CC_COMPLETION_PUSH_BIN="$STUB" \
      HANDOFF_TTY_FAIL_FILE="$failf" HANDOFF_TTY_RETRIES=3 HANDOFF_TTY_RETRY_SLEEP_S=0 \
      bash "$HF" self-close --successor "NOPANE-5150" --session-id "fake:FFFF-5150"
  [ "$status" -eq 7 ]                       # NOT a leaked osascript code — the flake this fixes
  [ ! -f "$MARK" ]                          # still aborts BEFORE any completion push
  [ "$(cat "$failf")" -eq 1 ]              # seam consumed on all 3 retries (4→1) — proves the query was retried
}

@test "real completion-push (default bin resolution) → a completion-push RECORD, verdict verified" {
  local roles="$BATS_TEST_TMPDIR/roles" recs="$BATS_TEST_TMPDIR/records"
  mkdir -p "$roles"; printf 'DESK-UUID-1\n' > "$roles/desk"
  local ccn="$BATS_TEST_TMPDIR/ccn.sh"
  { printf '#!/bin/bash\n'; printf 'echo "cc-notify: delivered to inbox [T] (live session, wake-path armed — its cc-await-ping watcher wakes it within a poll)" >&2\nexit 0\n'; } > "$ccn"
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

# ── the bound: a HANG must not suspend the close ─────────────────────────────────────────────────────
# Stubs live here rather than in setup() so the tests above keep their exact fixture.
#   hang_stub  — never returns on its own (the wedge: cc-announce blocked in a capture that never EOFs)
#   ignterm_stub — additionally IGNORES SIGTERM, so `timeout -k 3` must escalate to SIGKILL
mk_hang_stub() { printf '#!/bin/bash\nsleep 30\n' > "$1"; chmod +x "$1"; }
mk_ignterm_stub() { printf '#!/bin/bash\ntrap "" TERM\nwhile :; do sleep 1; done\n' > "$1"; chmod +x "$1"; }

@test "BOUND: a HANGING completion-push expires → LOUD 'TIMED OUT', and the close is NOT suspended" {
  local hang="$BATS_TEST_TMPDIR/hang.sh"; mk_hang_stub "$hang"
  local t0 t1
  t0="$(date +%s)"
  # `timeout 20` is a BACKSTOP, not the mechanism: status 124 here would mean the subject never
  # returned, which is the defect. The pass condition is that handoff-fire ends on its own.
  run bash -c "cd '$WORK' && CC_COMPLETION_PUSH_BIN='$hang' HANDOFF_COMPLETION_PUSH_TIMEOUT_S=2 \
      timeout 20 bash '$HF' self-close --terminal --session-id 'fake:BBBB-2222' 2>&1"
  t1="$(date +%s)"
  [ "$status" -ne 124 ]                                   # the subject returned; the backstop did NOT fire
  [[ "$output" == *"TIMED OUT (bound 2s"* ]] || false
  [[ "$output" == *"the pane must retire"* ]] || false
  [[ "$output" == *"rc=124"* ]] || false                  # names WHICH expiry code, not a bare failure
  # NOT the exit-5 wording: a bound that fired knows only that no verdict arrived, and the push may
  # well have landed (capture-before-notify wrote the record first). Claiming "did NOT verify" here
  # would assert a delivery FACT this path cannot possibly hold.
  [[ "$output" != *"did NOT verify"* ]] || false
  [ $(( t1 - t0 )) -lt 15 ]                               # bounded at 2s, nowhere near the stub's 30s
}

@test "BOUND mutation control: with the seam DISABLED the same hang DOES suspend the close" {
  # The red-on-mutation half. Without it every assertion above could pass on a build where the stub
  # merely exited early for some unrelated reason — this proves the BOUND is what cures the hang.
  # Here, and only here, the outer timeout firing (124) is the EXPECTED observation.
  local hang="$BATS_TEST_TMPDIR/hang.sh"; mk_hang_stub "$hang"
  run bash -c "cd '$WORK' && CC_COMPLETION_PUSH_BIN='$hang' HANDOFF_COMPLETION_PUSH_TIMEOUT_S=0 \
      timeout 5 bash '$HF' self-close --terminal --session-id 'fake:BBBB-2222' 2>&1"
  [ "$status" -eq 124 ]                                   # suspended — the outer backstop had to kill it
  [[ "$output" != *"TIMED OUT"* ]] || false                # and no expiry was ever reported
}

@test "BOUND: a TERM-ignoring push needs the -k SIGKILL → rc 137 is ALSO reported as TIMED OUT" {
  # MEASURED, not assumed (GNU coreutils 9.1, this box): `timeout -k` yields 124 when the callee dies
  # on SIGTERM and 137 when it must be SIGKILLed. A `= 124` test would file this — the likelier shape,
  # since cc-notify installs its own TERM trap — under the WRONG label: a channel that reported
  # failure rather than one that never answered.
  local ign="$BATS_TEST_TMPDIR/ignterm.sh"; mk_ignterm_stub "$ign"
  run bash -c "cd '$WORK' && CC_COMPLETION_PUSH_BIN='$ign' HANDOFF_COMPLETION_PUSH_TIMEOUT_S=2 \
      timeout 20 bash '$HF' self-close --terminal --session-id 'fake:BBBB-2222' 2>&1"
  [ "$status" -ne 124 ]
  [[ "$output" == *"TIMED OUT (bound 2s"* ]] || false
  [[ "$output" == *"rc=137"* ]] || false
  [[ "$output" != *"did NOT verify"* ]] || false
}

@test "BOUND false-positive control: a SLOW but healthy push under the bound still reads VERIFIED" {
  # The bound must separate wedged from merely slow. Without this arm, shrinking the bound to 0s would
  # pass every test above while converting each healthy push into a false LOUD — corrupting exactly the
  # verified/degraded truthfulness the F5 chain exists for (memory: threshold-must-separate-fatal-from-
  # survived — pin the false positive as a control, not just the fatal case).
  local slow="$BATS_TEST_TMPDIR/slow.sh"
  { printf '#!/bin/bash\n'; printf 'sleep 2\n'
    printf 'printf "%%s\\n" "CALLED $*" >> "%s"\n' "$MARK"; printf 'exit 0\n'; } > "$slow"
  chmod +x "$slow"
  run bash -c "cd '$WORK' && CC_COMPLETION_PUSH_BIN='$slow' HANDOFF_COMPLETION_PUSH_TIMEOUT_S=15 \
      timeout 20 bash '$HF' self-close --terminal --session-id 'fake:BBBB-2222' 2>&1"
  [[ "$output" == *"terminal completion pushed to the 'desk' role"* ]] || false
  [[ "$output" != *"TIMED OUT"* ]] || false
  grep -q 'CALLED fire --role desk' "$MARK"               # it really ran to completion, not skipped
}

@test "BOUND is stated in the --dry-run PLAN, and renders 'unbounded' when the seam disables it" {
  # "Can this close hang?" is a question --dry-run is read to answer; before the bound existed it could
  # only be answered by grepping the source. The disabled render is pinned because `${x:-unbounded}`
  # alone prints "≤ 0s" for the 0 case — a plan asserting a bound the run does not apply.
  run env CC_COMPLETION_PUSH_BIN="$STUB" HANDOFF_COMPLETION_PUSH_TIMEOUT_S=45 \
      bash "$HF" self-close --terminal --session-id "fake:AAAA-1111" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"bound:"* ]] || false
  [[ "$output" == *"≤ 45s"* ]] || false

  run env CC_COMPLETION_PUSH_BIN="$STUB" HANDOFF_COMPLETION_PUSH_TIMEOUT_S=0 \
      bash "$HF" self-close --terminal --session-id "fake:AAAA-1111" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"unbounded"* ]] || false
  [[ "$output" != *"≤ 0s"* ]] || false
}
