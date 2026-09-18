#!/usr/bin/env bats
# hooks/net-recover-arm.sh — D4 of docs/plans/NONLIMIT_RESUME_LADDER.md (T6/W2-C).
#
# The done-when from the plan's W2-C row, verbatim: "fires exactly once on
# [api-error ∧ turn_duration ∧ 2 greens], never on IN-FLIGHT, never twice on one uuid".
# Every one of those four is a case below, each with the control arm that proves it is not passing
# for a trivial reason — plus the gate the plan could NOT have specified, because it was measured
# after the plan was written: `turn_duration` is absent from BOTH arms of the W2-0 probe INCLUDING
# the control, so requiring it would make the wake unreachable in any transcript that emits none.
# That fail-open branch is cases 8 and 9, and mutant 17 is what proves the branch is load-bearing.
#
# NO API-ERROR RECORD IS SYNTHESIZED FROM IMAGINATION. The envelope below is the one lr_last_api_error
# gates on (`type:"assistant"` + `isApiErrorMessage:true`, lr-lib.sh:124) and the shape quoted in this
# plan's § Finding 2.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/net-recover-arm.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_NET_RECOVER_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_NET_RECOVER_TIMEOUT=3          # the watch must END inside a test
  export CC_NET_RECOVER_INTERVAL=1
  export CC_NET_RECOVER_LIB="$REPO/scripts/limit-recover/lr-lib.sh"
  # A streaming argv, so the headless guard ARMS. Cases 2-4 override it.
  export CC_NET_RECOVER_HARNESS_ARGV="node claude --input-format stream-json --output-format stream-json"
  TP="$BATS_TEST_TMPDIR/transcript.jsonl"
  SID="cccc0000-1111-2222-3333-444444444444"
  probe_green   # most cases want the control satisfied; case 11 flips it
}

probe_green() {
  export CC_NET_RECOVER_PROBE="$BATS_TEST_TMPDIR/probe-green.sh"
  printf '#!/bin/bash\nexit 0\n' > "$CC_NET_RECOVER_PROBE"; chmod +x "$CC_NET_RECOVER_PROBE"
}
probe_red() {
  export CC_NET_RECOVER_PROBE="$BATS_TEST_TMPDIR/probe-red.sh"
  printf '#!/bin/bash\nexit 1\n' > "$CC_NET_RECOVER_PROBE"; chmod +x "$CC_NET_RECOVER_PROBE"
}

payload() { printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"SessionStart"}' "$SID" "${1-$TP}"; }
fire() { payload "$@" | bash "$HOOK"; }

# ── transcript builders ────────────────────────────────────────────────────────────────────────
normal_turn() {
  printf '{"type":"user","timestamp":"2026-09-17T14:00:00.000Z","message":{"role":"user","content":"go"}}\n' >> "$TP"
  printf '{"type":"assistant","timestamp":"2026-09-17T14:00:05.000Z","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}\n' >> "$TP"
}
api_error() { # [$1=uuid] [$2=timestamp]
  printf '{"type":"assistant","uuid":"%s","timestamp":"%s","isApiErrorMessage":true,"error":"ENOTFOUND","message":{"role":"assistant","content":[{"type":"text","text":"API Error: getaddrinfo ENOTFOUND api.anthropic.com"}]}}\n' \
    "${1:-err-uuid-1}" "${2:-2026-09-17T14:01:00.000Z}" >> "$TP"
}
turn_end() { # [$1=timestamp]
  printf '{"type":"system","subtype":"turn_duration","timestamp":"%s","durationMs":4200}\n' \
    "${1:-2026-09-17T14:01:30.000Z}" >> "$TP"
}

# ── the guards: this hook must never cost a session birth ───────────────────────────────────────
@test "1 the kill switch is a total no-op" {
  CC_NET_RECOVER_ARM=0 run fire
  [ "$status" -eq 0 ]
  [ ! -d "$CC_NET_RECOVER_STATE_DIR" ] || false
}

@test "2 a plain headless one-shot does NOT arm — asyncRewake is dispatched SYNC there" {
  export CC_NET_RECOVER_HARNESS_ARGV="node claude -p 'hello'"
  normal_turn
  run fire
  [ "$status" -eq 0 ]
}

@test "3 an UNRESOLVABLE harness argv fails SAFE (skip, never arm)" {
  export CC_NET_RECOVER_HARNESS_ARGV=""
  normal_turn
  run fire
  [ "$status" -eq 0 ]
}

@test "4 a missing transcript_path is a silent no-op" {
  run bash -c "printf '{\"session_id\":\"$SID\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "5 garbage stdin is a silent no-op" {
  run bash -c "printf 'not json' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "6 a lib with no lr_last_api_error is silent — never a false wake on a packaging slip" {
  export CC_NET_RECOVER_LIB="$BATS_TEST_TMPDIR/old-lib.sh"
  printf '#!/bin/bash\n: # an older lr-lib without the predicate\n' > "$CC_NET_RECOVER_LIB"
  api_error; turn_end
  run fire
  [ "$status" -eq 0 ]
}

# ── the wake ───────────────────────────────────────────────────────────────────────────────────
@test "7 FIRES on [api-error AND turn_duration AND green] — exit 2, and the body is on STDERR" {
  normal_turn; api_error; turn_end
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$HOOK' 2>&1 1>/dev/null"
  [ "$status" -eq 2 ]
  [[ "$output" == *"reachable again"* ]] || false
  [[ "$output" == *"/recover"* ]] || false
  # It must tell the model NOT to reconcile from context — that is the defect D3/D4 exist for,
  # not a nicety: a plausible pre-death narrative is what makes a session satisfice.
  [[ "$output" == *"Do NOT reconcile"* ]] || false
}

@test "8 FAIL-OPEN: no turn_duration ANYWHERE still fires — the record is shape-dependent" {
  normal_turn; api_error          # deliberately no turn_end
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$HOOK' >/dev/null 2>&1"
  [ "$status" -eq 2 ]
}

@test "9 CONTROL for 8: the fail-open branch is reached because NO turn_duration exists" {
  normal_turn; api_error
  run grep -c turn_duration "$TP"
  [ "$output" = "0" ]
}

# ── never on IN-FLIGHT ─────────────────────────────────────────────────────────────────────────
@test "10 IN-FLIGHT: turn_duration exists but only BEFORE the error ⇒ no wake" {
  normal_turn
  turn_end "2026-09-17T14:00:10.000Z"     # the PRIOR turn ended
  api_error "err-uuid-1" "2026-09-17T14:01:00.000Z"
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$HOOK' >/dev/null 2>&1"
  [ "$status" -eq 0 ]
}

# ── the control must be NECESSARY ──────────────────────────────────────────────────────────────
@test "11 a RED probe suppresses the wake — reachability is a precondition, not a formality" {
  probe_red
  normal_turn; api_error; turn_end
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$HOOK' >/dev/null 2>&1"
  [ "$status" -eq 0 ]
}

@test "12 a healthy session with no api error never wakes" {
  normal_turn
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$HOOK' >/dev/null 2>&1"
  [ "$status" -eq 0 ]
}

# ── never twice on one uuid ────────────────────────────────────────────────────────────────────
@test "13 the SECOND arm over the same death record is silent — one wake per uuid" {
  normal_turn; api_error; turn_end
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$HOOK' >/dev/null 2>&1"
  [ "$status" -eq 2 ]
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$HOOK' >/dev/null 2>&1"
  [ "$status" -eq 0 ]
}

@test "14 a LATER, DIFFERENT death still wakes — the latch is per record, not per session" {
  normal_turn; api_error "err-uuid-1"; turn_end
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$HOOK' >/dev/null 2>&1"
  [ "$status" -eq 2 ]
  api_error "err-uuid-2" "2026-09-17T14:05:00.000Z"; turn_end "2026-09-17T14:05:30.000Z"
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$HOOK' >/dev/null 2>&1"
  [ "$status" -eq 2 ]
}

# ── the claim guard ────────────────────────────────────────────────────────────────────────────
@test "15 a LIVE sibling watcher makes this arm a no-op — the Stop re-arm cannot stack" {
  mkdir -p "$CC_NET_RECOVER_STATE_DIR/$SID.claim"
  printf '%s' "$$" > "$CC_NET_RECOVER_STATE_DIR/$SID.claim/pid"   # $$ is alive by construction
  normal_turn; api_error; turn_end
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$HOOK' >/dev/null 2>&1"
  [ "$status" -eq 0 ]
}

@test "16 a TOMBSTONE claim (dead pid) is adopted, not obeyed — a killed watcher must not lock out its successor" {
  mkdir -p "$CC_NET_RECOVER_STATE_DIR/$SID.claim"
  printf '%s' "999999" > "$CC_NET_RECOVER_STATE_DIR/$SID.claim/pid"
  normal_turn; api_error; turn_end
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$HOOK' >/dev/null 2>&1"
  [ "$status" -eq 2 ]
}

# ── mutants: one per load-bearing predicate ────────────────────────────────────────────────────
mutate() { local m="$BATS_TEST_TMPDIR/mutant.sh"; sed "$1" "$HOOK" > "$m"; chmod +x "$m"; printf '%s' "$m"; }

@test "17 MUTANT — a fail-CLOSED turn-end gate makes the wake unreachable where the record is absent" {
  M="$(mutate 's|^sys.exit(1 if seen else 0).*|sys.exit(1)|')"
  ! cmp -s "$M" "$HOOK" || false
  normal_turn; api_error                      # no turn_duration — case 8's shape
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$M' >/dev/null 2>&1"
  [ "$status" -eq 0 ]                         # silently never fires — case 8 is what kills it
}

@test "18 MUTANT — dropping the probe gate wakes into a network that is still down" {
  M="$(mutate 's|if "\$_probe" >/dev/null 2>&1; then|if :; then|')"
  ! cmp -s "$M" "$HOOK" || false
  probe_red
  normal_turn; api_error; turn_end
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$M' >/dev/null 2>&1"
  [ "$status" -eq 2 ]                         # case 11 is what kills it
}

@test "19 MUTANT — a per-SESSION latch instead of per-uuid goes silent on every later death" {
  M="$(mutate 's|\$_state/\$_sid.woke.\$_uuid|$_state/$_sid.woke|g')"
  ! cmp -s "$M" "$HOOK" || false
  normal_turn; api_error "err-uuid-1"; turn_end
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$M' >/dev/null 2>&1"
  [ "$status" -eq 2 ]
  api_error "err-uuid-2" "2026-09-17T14:05:00.000Z"; turn_end "2026-09-17T14:05:30.000Z"
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$M' >/dev/null 2>&1"
  [ "$status" -eq 0 ]                         # the second death is swallowed — case 14 kills it
}

@test "20 MUTANT — obeying a tombstone claim locks a session out for the rest of its life" {
  M="$(mutate 's|if kill -0 "\$_old" 2>/dev/null; then exit 0; fi|exit 0|')"
  ! cmp -s "$M" "$HOOK" || false
  mkdir -p "$CC_NET_RECOVER_STATE_DIR/$SID.claim"
  printf '%s' "999999" > "$CC_NET_RECOVER_STATE_DIR/$SID.claim/pid"
  normal_turn; api_error; turn_end
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$M' >/dev/null 2>&1"
  [ "$status" -eq 0 ]                         # case 16 is what kills it
}

@test "21 MUTANT — arming in a headless one-shot would block every probe's session birth" {
  M="$(mutate "s|\\*' -p '\\*|*'NEVERMATCHES'*|")"
  ! cmp -s "$M" "$HOOK" || false
  export CC_NET_RECOVER_HARNESS_ARGV="node claude -p 'hello'"
  normal_turn; api_error; turn_end
  run bash -c "$(declare -f payload); TP='$TP' SID='$SID' payload | bash '$M' >/dev/null 2>&1"
  [ "$status" -eq 2 ]                         # case 2 is what kills it
}
