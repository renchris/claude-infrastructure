#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# scripts/limit-recover/lr-move-lib.sh lr_move_verdict — the outcome of one account move, re-derived
# from disk and ps (design-swap-v3 §4.6, 2026-10-04).
#
# THE DEFECT IT REPLACES: the old lane read SWITCHED / NOTMOVED out of the subject's reply and a
# transcript mtime. On 2026-10-04 it reported SWITCHED for 762a6daa, whose target store still held a
# tombstone naming the store it had just left, so the prompt guard blocked every prompt there; the
# proposed "process alive + env + READY" proof passes on that session too.
#
# EVERY CONJUNCT IS MUTATED ALONE: each case starts from the fully MOVED fixture (case 1), breaks
# exactly one fact, and asserts the verdict names exactly that conjunct. So removing any one check
# from lr_move_verdict turns exactly its case red, and case 1 is the control that the fixture is
# otherwise whole. Before lr-move-lib.sh existed none of these cases could run.
#
# Hermetic: see tests/helpers/lr-move-fixture.sh. No pane is read, nothing is written by the subject.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_GATE=off
  export CC_FIRE_CAPACITY_GATE=off
  # shellcheck source=/dev/null
  . "$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/helpers/lr-move-fixture.sh"
  mvf_setup
  SID="aaaa1111-0000-4000-8000-000000000001"; PANE=31
  mvf_session "$PANE" "$SID"
  mvf_plan b1 move "$PANE:$SID"
  printf '{"admitted":true,"target":"next3","target_auth":"ok"}\n' > "$BDIR/admit.json"
}
teardown() { mvf_teardown; }

verdict() { # [from cfg] [to cfg] [batch dir or ""]
  run bash -c '. "$1/lr-lib.sh"; . "$1/lr-move-lib.sh"; lr_move_verdict "$2" "$3" "$4" "$5" "$6"' _ \
    "$LRD" "$SID" "$PANE" "${1:-$SRC}" "${2:-$DST}" "${3-$BDIR}"
  V="$(printf '%s' "$output" | cut -f1)"; WHY="$(printf '%s' "$output" | cut -f2)"; FLAGS="$(printf '%s' "$output" | cut -f4)"
}

@test "1 MOVED: the row, the process environment, the one transcript, no tombstone, one holder, admission, debt" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  verdict
  [ "$status" -eq 0 ]
  [ "$V" = MOVED ]
  [ "$FLAGS" = 1111111 ]
}

@test "2 NOTMOVED: before any move the session is live in its pane on the source, one copy" {
  verdict
  [ "$V" = NOTMOVED ]
}

@test "3 P2 alone: the row says target but the process runs under the SOURCE config dir ⇒ FAILED P2" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  printf '%s' "$SRC" > "$LR_MOVE_ENV_DIR/$MVF_PID"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P2 environment:"* ]]
}

@test "4 P3 alone: a second live transcript left under the source ⇒ FAILED P3 (two copies)" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  cp "$DST/projects/-x/$SID.jsonl" "$SRC/projects/-x/$SID.jsonl"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P3 transcript:"* ]]
}

@test "5 P4 alone: a tombstone in the target naming another account (the 8e18da3f / 762a6daa shape) ⇒ FAILED P4" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  printf '{"handed_off_to":"%s","ts":"2026-10-03T02:28:00Z"}\n' "$SRC" > "$DST/projects/-x/$SID.HANDOFF.json"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P4 tombstone:"* ]] || false
  [[ "$WHY" == *"cc-lr repair-markers --sid $SID"* ]]
}

@test "5b a tombstone in the target naming the target's OWN account is not foreign: still MOVED" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  printf '{"handed_off_to":"%s","ts":"2026-10-03T02:28:00Z"}\n' "$DST" > "$DST/projects/-x/$SID.HANDOFF.json"
  verdict
  [ "$V" = MOVED ]
}

@test "6 P5 alone: a second live process holding the session ⇒ FAILED P5" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  first="$MVF_PID"
  sleep 900 3>&- &
  other=$!; MVF_PIDS="$MVF_PIDS $other"
  printf '{"paneUUID":"77","pid":%d,"session_id":"%s","account":"claude-tertiary","cwd":"/x"}\n' "$other" "$SID" > "$CC_REGISTRY_DIR/77.json"
  printf '%s' "$DST" > "$LR_MOVE_ENV_DIR/$other"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P5 holders:"* ]] || false
  [ "$first" != "$other" ]
}

@test "7 P6 alone: the batch recorded no ranked target ⇒ FAILED P6; without a batch dir P6 is not asked" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  printf '{"admitted":true,"target":"next3","target_auth":"unverified"}\n' > "$BDIR/admit.json"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P6 admission:"* ]] || false
  printf '{"admitted":true,"target":"next3","target_auth":"unverified-accepted"}\n' > "$BDIR/admit.json"
  verdict
  [ "$V" = MOVED ]
  printf '{"admitted":false,"target":"next3","target_auth":"ok"}\n' > "$BDIR/admit.json"
  verdict
  [ "$V" = FAILED ]
  verdict "$SRC" "$DST" ""
  [ "$V" = MOVED ]
}

@test "8 P7 alone: an open resume debt ⇒ FAILED P7; a proven one passes" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  printf '{"state":"open"}\n' > "$CC_RESUME_DEBT_DIR/meta/$SID.json"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P7 resume debt:"* ]] || false
  printf '{"state":"proven"}\n' > "$CC_RESUME_DEBT_DIR/meta/$SID.json"
  verdict
  [ "$V" = MOVED ]
}

@test "9 STRANDED: no live process holds the session" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  kill "$MVF_PID"; wait "$MVF_PID" 2>/dev/null || true
  verdict
  [ "$V" = STRANDED ]
}

@test "10 MOVED-NEW-PANE: the live row is on the target but in another pane" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  jq -c '.paneUUID = "88"' "$CC_REGISTRY_DIR/$PANE.json" > "$CC_REGISTRY_DIR/88.json"; rm -f "$CC_REGISTRY_DIR/$PANE.json"
  verdict
  [ "$V" = MOVED-NEW-PANE ]
}

@test "11 MOVED-UNREGISTERED: the registry row was lost, and one --resume process holds the session under the target" {
  # session-register.sh has a 5 s timeout and loses rows at load 30-50; a lost row is not a failed move.
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  rm -f "$CC_REGISTRY_DIR/$PANE.json"
  /usr/bin/perl -e 'sleep 900' -- --resume "$SID" 3>&- &
  rp=$!; MVF_PIDS="$MVF_PIDS $rp"
  printf '%s' "$DST" > "$LR_MOVE_ENV_DIR/$rp"
  sleep 0.3
  verdict
  [ "$V" = MOVED-UNREGISTERED ]
  # the same process under the SOURCE config dir is not a move
  printf '%s' "$SRC" > "$LR_MOVE_ENV_DIR/$rp"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P2 environment:"* ]]
}

@test "11b no registry row and no --resume process: nothing names a holder ⇒ STRANDED" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  rm -f "$CC_REGISTRY_DIR/$PANE.json"
  verdict
  [ "$V" = STRANDED ]
}

@test "12 the next account: a move ONTO next is MOVED when the row says claude and the store is the mirror" {
  # ~/.claude and ~/.claude-next are one account: the relaunch runs under ~/.claude-next, the
  # registry writes `claude-next` or `claude`, and ~/.claude-next/projects is a symlink to
  # ~/.claude/projects. A raw compare of names or directories fails every such move.
  mkdir -p "$HOME/.claude/projects/-x" "$HOME/.claude-next"
  ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"
  mv "$SRC/projects/-x/$SID.jsonl" "$HOME/.claude/projects/-x/$SID.jsonl"
  jq -c '.account = "claude"' "$CC_REGISTRY_DIR/$PANE.json" > "$CC_REGISTRY_DIR/$PANE.json.t"; mv "$CC_REGISTRY_DIR/$PANE.json.t" "$CC_REGISTRY_DIR/$PANE.json"
  printf '%s' "$HOME/.claude-next" > "$LR_MOVE_ENV_DIR/$MVF_PID"
  verdict "$SRC" "$HOME/.claude-next"
  [ "$V" = MOVED ]
  # P2 stays byte-exact: the same process under ~/.claude (another Keychain item) is not the target
  printf '%s' "$HOME/.claude" > "$LR_MOVE_ENV_DIR/$MVF_PID"
  verdict "$SRC" "$HOME/.claude-next"
  [ "$V" = FAILED ]
  [[ "$WHY" == "P2 environment:"* ]]
}

@test "13 the next account: a session still on next reads NOTMOVED for a move OFF next" {
  mkdir -p "$HOME/.claude/projects/-x" "$HOME/.claude-next"
  ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"
  mv "$SRC/projects/-x/$SID.jsonl" "$HOME/.claude/projects/-x/$SID.jsonl"
  jq -c '.account = "claude-next"' "$CC_REGISTRY_DIR/$PANE.json" > "$CC_REGISTRY_DIR/$PANE.json.t"; mv "$CC_REGISTRY_DIR/$PANE.json.t" "$CC_REGISTRY_DIR/$PANE.json"
  verdict "$HOME/.claude-next" "$DST"
  [ "$V" = NOTMOVED ]
}

@test "14 the verdict writes nothing: the fixture tree is byte-identical after a read" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  before="$(cd "$BATS_TEST_TMPDIR" && find home reg penv debt -type f -exec shasum {} + | sort | shasum)"
  verdict
  after="$(cd "$BATS_TEST_TMPDIR" && find home reg penv debt -type f -exec shasum {} + | sort | shasum)"
  [ "$before" = "$after" ]
}
