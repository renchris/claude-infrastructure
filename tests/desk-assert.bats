#!/usr/bin/env bats
# bin/desk-assert — the FM2 grounding triad made executable (read-transcript-before-asserting-why).
# Fixtures: a <sid>.jsonl under DESK_ASSERT_PROJECTS, a stubbed cc-sessions --json, and a git repo
# whose --witnessed-ref sits one commit behind HEAD. DESK_ASSERT_NOW pins "now" for a deterministic
# last_turn age.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DA="$REPO/bin/desk-assert"
  SID="11111111-2222-3333-4444-555555555555"
  PANE="PANE-AAAA-BBBB-CCCC-000000000001"

  PROJ="$BATS_TEST_TMPDIR/projects"; mkdir -p "$PROJ/enc"
  printf '{"type":"mode","sessionId":"%s"}\n{"type":"assistant","timestamp":"2026-07-10T06:36:13.805Z","message":{"role":"assistant"}}\n' \
    "$SID" > "$PROJ/enc/$SID.jsonl"
  export DESK_ASSERT_PROJECTS="$PROJ"
  EP="$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "2026-07-10T06:36:13" +%s)"
  export DESK_ASSERT_NOW=$(( EP + 42 ))

  STUB="$BATS_TEST_TMPDIR/cc-sessions"
  cat > "$STUB" <<EOF
#!/bin/bash
printf '%s\n' '[{"session_id":"$SID","paneUUID":"$PANE"},{"session_id":"other","paneUUID":"P2"}]'
EOF
  chmod +x "$STUB"
  export CC_SESSIONS_BIN="$STUB"

  GR="$BATS_TEST_TMPDIR/repo"; mkdir -p "$GR"
  git -C "$GR" init -q
  git -C "$GR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  REF="$(git -C "$GR" rev-parse HEAD)"
  git -C "$GR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m next
}

@test "GROUNDED: all three legs + witnessed-ref -> exit 0 with pane, last_turn, head_delta" {
  run bash "$DA" "$SID" --witnessed-ref "$REF" --cwd "$GR"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q "GROUNDED sid=$SID pane=$PANE"
  printf '%s\n' "$output" | grep -q 'last_turn=42s ago'
  printf '%s\n' "$output" | grep -q 'head_delta=1'
}

@test "GROUNDED: no --witnessed-ref -> legs 1+2 ground, head_delta=n/a" {
  run bash "$DA" "$SID"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q "GROUNDED sid=$SID pane=$PANE"
  printf '%s\n' "$output" | grep -q 'head_delta=n/a'
}

@test "UNGROUNDED: no transcript for the sid (transcript leg)" {
  run bash "$DA" "unknown-sid-0000"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^UNGROUNDED:'
  printf '%s\n' "$output" | grep -q 'transcript'
}

@test "UNGROUNDED: cc-sessions has no row for the sid (pane leg)" {
  cat > "$CC_SESSIONS_BIN" <<'EOF'
#!/bin/bash
printf '%s\n' '[{"session_id":"someone-else","paneUUID":"PX"}]'
EOF
  run bash "$DA" "$SID"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'pane('
}

@test "UNGROUNDED: --witnessed-ref not resolvable (head leg)" {
  run bash "$DA" "$SID" --witnessed-ref deadbeefref --cwd "$GR"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'head('
}

@test "UNGROUNDED: an assistant-less transcript (only metadata) fails the transcript leg" {
  printf '{"type":"mode","sessionId":"%s"}\n{"type":"user","message":{"role":"user","content":"hi"}}\n' \
    "$SID" > "$PROJ/enc/$SID.jsonl"
  run bash "$DA" "$SID"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'transcript'
}

@test "missing <sid> -> usage error exit 2" {
  run bash "$DA"
  [ "$status" -eq 2 ]
}
