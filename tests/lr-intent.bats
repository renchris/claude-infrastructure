#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# scripts/limit-recover/lr-intent.sh — the operator-intent file that admits a driver-direct move of
# a healthy pane (design-swap-v3 D1/F11, 2026-10-04).
#
# THE CONTRACT UNDER TEST: lr_intent_check <file> <sid> <pane> <from> <to> is valid only when every
# check holds. Each case below takes the VALID fixture and breaks exactly one thing, and asserts the
# token of exactly that check, so deleting any single check from lr_intent_check turns its case red
# (one mutant per site). Before this file existed nothing admitted a healthy peer at all.
#
# Hermetic: the state dir is a fixture under $BATS_TEST_TMPDIR; nothing here reads a live session.

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/limit-recover/lr-intent.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_STATE_DIR="$HOME/.reso/limit-recover"
  SID="0000aaaa-0000-4000-8000-00000000cafe"
  D="$LR_STATE_DIR/move/b1/intent"; mkdir -p "$D"
  F="$D/$SID.json"
  jq -nc --arg sid "$SID" --argjson exp "$(( $(date +%s) + 600 ))" \
    '{kind:"cc-lr-move",batch:"b1",sid:$sid,pane:"31",from:"next4",to:"next3",requested_by:"t",ts:0,expires_epoch:$exp,plan_row_sha:"x"}' > "$F"
  chmod 600 "$F"
}
check() { run bash -c 'source "$1"; shift; lr_intent_check "$@"; rc=$?; printf "%s" "$LR_INTENT_WHY"; exit $rc' _ "$LIB" "$@"; }
edit() { jq -c "$1" "$F" > "$F.t"; mv "$F.t" "$F"; chmod 600 "$F"; }

@test "the valid fixture is admitted, with no reason" {
  check "$F" "$SID" 31 next4 next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "not-regular: a symlink to a valid intent, and a missing file, are refused" {
  mv "$F" "$F.real"; ln -s "$F.real" "$F"
  check "$F" "$SID" 31 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == not-regular:* ]] || false
  check "$D/absent.json" "$SID" 31 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == not-regular:* ]]
}

@test "bad-mode: a group- or world-readable intent is refused" {
  chmod 644 "$F"
  check "$F" "$SID" 31 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == bad-mode:* ]]
}

@test "bad-path: the same file outside <state>/move/<batch>/intent/ is refused" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"; cp -p "$F" "$BATS_TEST_TMPDIR/elsewhere/$SID.json"
  check "$BATS_TEST_TMPDIR/elsewhere/$SID.json" "$SID" 31 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == bad-path:* ]]
}

@test "bad-path: a file one level too deep, or not named <sid>.json, is refused" {
  mkdir -p "$LR_STATE_DIR/move/b1/x/intent"; cp -p "$F" "$LR_STATE_DIR/move/b1/x/intent/$SID.json"
  check "$LR_STATE_DIR/move/b1/x/intent/$SID.json" "$SID" 31 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == bad-path:* ]] || false
  cp -p "$F" "$D/other.json"
  check "$D/other.json" "$SID" 31 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == bad-path:* ]]
}

@test "unreadable: a file that is not a JSON object is refused" {
  printf 'not json\n' > "$F"
  check "$F" "$SID" 31 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == unreadable:* ]]
}

@test "bad-kind: another kind is refused" {
  edit '.kind = "cc-lr-switch"'
  check "$F" "$SID" 31 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == bad-kind:* ]]
}

@test "sid-mismatch: an intent whose body names another session is refused" {
  edit '.sid = "ffffffff-0000-4000-8000-000000000000"'
  check "$F" "$SID" 31 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == sid-mismatch:* ]]
}

@test "pane-mismatch: an intent for another pane is refused" {
  check "$F" "$SID" 32 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == pane-mismatch:* ]]
}

@test "from-mismatch: a session that is not on the intent's source account is refused" {
  check "$F" "$SID" 31 next2 next3
  [ "$status" -eq 1 ]
  [[ "$output" == from-mismatch:* ]]
}

@test "to-mismatch: a move to another target than the intent's is refused" {
  check "$F" "$SID" 31 next4 next2
  [ "$status" -eq 1 ]
  [[ "$output" == to-mismatch:* ]]
}

@test "expired: a past or non-integer expires_epoch is refused" {
  edit '.expires_epoch = 1'
  check "$F" "$SID" 31 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == expired:* ]] || false
  edit '.expires_epoch = "soon"'
  check "$F" "$SID" 31 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == expired:* ]]
}

@test "switched-off: LR_OPERATOR_INTENT=off refuses the valid fixture" {
  export LR_OPERATOR_INTENT=off
  check "$F" "$SID" 31 next4 next3
  [ "$status" -eq 1 ]
  [[ "$output" == switched-off:* ]]
}

@test "an empty from or to never matches (an unmapped account admits nothing)" {
  check "$F" "$SID" 31 "" next3
  [ "$status" -eq 1 ]
  [[ "$output" == from-mismatch:* ]]
}
