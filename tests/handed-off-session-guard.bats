#!/usr/bin/env bats
# handed-off-session-guard — RED-proves the enforcing half of the transplant tombstone.
#
# Before this hook landed, `lr-transplant.sh` wrote `<sid>.HANDOFF.json` and a split-brain lock and
# NOTHING on a running session's path read either, so a source pane that survived the transplant
# resumed the moment its quota refilled and forked the session (incident 2026-08-16, `ede6a811`:
# 40 assistant turns in the retired store against 218 in the live one).
#
# The two ways this guard rots are asserted first and hardest, because both are worse than the bug:
#   (a) it convicts the SUCCESSOR — same session id, so identity is the whole question; and
#   (b) it convicts a next-account successor over the `.claude` / `.claude-next` MIRROR, which is
#       two directories for one account.
# The fixtures use the tombstone verbatim as lr-transplant.sh prints it — a guard tested against a
# hand-simplified shape is a guard tested against a file that does not exist.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/handed-off-session-guard.sh"
  # The subject falls back to $HOME/.claude when CLAUDE_CONFIG_DIR is unset, so an unfixtured
  # $HOME makes every verdict a function of the operator's live tree.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SID="ede6a811-fdb5-42e6-8c61-37d325878020"
  SRC_CFG="$BATS_TEST_TMPDIR/.claude-tertiary"
  DST_CFG="$BATS_TEST_TMPDIR/.claude-next"
  MIRROR_CFG="$BATS_TEST_TMPDIR/.claude"
  SLUG="-Users-chrisren-Development-personal"
  SRC_DIR="$SRC_CFG/projects/$SLUG"
  DST_DIR="$DST_CFG/projects/$SLUG"
  MIRROR_DIR="$MIRROR_CFG/projects/$SLUG"
  mkdir -p "$SRC_DIR" "$DST_DIR" "$MIRROR_DIR"
  SRC_TP="$SRC_DIR/$SID.jsonl"
  DST_TP="$DST_DIR/$SID.jsonl"
  MIRROR_TP="$MIRROR_DIR/$SID.jsonl"
  : >"$SRC_TP"; : >"$DST_TP"; : >"$MIRROR_TP"
  PAYLOAD_SRC="{\"session_id\":\"$SID\",\"transcript_path\":\"$SRC_TP\",\"cwd\":\"/tmp\",\"prompt\":\"hi\"}"
  PAYLOAD_DST="{\"session_id\":\"$SID\",\"transcript_path\":\"$DST_TP\",\"cwd\":\"/tmp\",\"prompt\":\"hi\"}"
  PAYLOAD_MIRROR="{\"session_id\":\"$SID\",\"transcript_path\":\"$MIRROR_TP\",\"cwd\":\"/tmp\",\"prompt\":\"hi\"}"
}

# Verbatim shape from lr-transplant.sh's tombstone printf.
write_tombstone() { # $1=dir  $2=handed_off_to  $3=target_transcript
  printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"2026-08-16T23:44:43Z","lock":"/tmp/l.lock"}\n' \
    "$2" "$3" >"$1/$SID.HANDOFF.json"
}

# ── The load-bearing invariant: an ORDINARY session is untouched ────────────────────────────────
@test "no tombstone → exit 0, emits NOTHING (the 99.9% path is unchanged)" {
  run env CLAUDE_CONFIG_DIR="$SRC_CFG" "$HOOK" <<<"$PAYLOAD_SRC"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── The bug itself ──────────────────────────────────────────────────────────────────────────────
@test "SOURCE pane after a transplant → exit 2 (the husk cannot take the prompt)" {
  write_tombstone "$SRC_DIR" "$DST_CFG" "$DST_TP"
  run env CLAUDE_CONFIG_DIR="$SRC_CFG" "$HOOK" <<<"$PAYLOAD_SRC"
  [ "$status" -eq 2 ]
  [[ "$output" == *"RETIRED SOURCE"* ]] || false
  [[ "$output" == *"${SID:0:8}"* ]]
}

@test "…and the SAME fixture exits 0 under the kill switch (proves the fixture, not the hook, is the subject)" {
  write_tombstone "$SRC_DIR" "$DST_CFG" "$DST_TP"
  run env CLAUDE_CONFIG_DIR="$SRC_CFG" CC_HANDED_OFF_GUARD_DISABLED=1 "$HOOK" <<<"$PAYLOAD_SRC"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── False positive (a): the SUCCESSOR must never be convicted ───────────────────────────────────
@test "TARGET pane (same sid, tombstone copied alongside) → exit 0" {
  write_tombstone "$DST_DIR" "$DST_CFG" "$DST_TP"
  run env CLAUDE_CONFIG_DIR="$DST_CFG" "$HOOK" <<<"$PAYLOAD_DST"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── False positive (b): the .claude / .claude-next mirror is ONE account ────────────────────────
@test "successor running in ~/.claude with a tombstone naming ~/.claude-next → exit 0 (mirror)" {
  write_tombstone "$MIRROR_DIR" "$DST_CFG" "$DST_TP"
  run env CLAUDE_CONFIG_DIR="$MIRROR_CFG" "$HOOK" <<<"$PAYLOAD_MIRROR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "…and the mirror acquittal is NOT a blanket acquittal (tertiary source still blocks)" {
  write_tombstone "$SRC_DIR" "$MIRROR_CFG" "$MIRROR_TP"
  run env CLAUDE_CONFIG_DIR="$SRC_CFG" "$HOOK" <<<"$PAYLOAD_SRC"
  [ "$status" -eq 2 ]
}

# ── Fail-open on every unknown ──────────────────────────────────────────────────────────────────
@test "tombstone without handed_off_to → exit 0 (fail-open, never convict on a parse gap)" {
  printf '{"ts":"2026-08-16T23:44:43Z"}\n' >"$SRC_DIR/$SID.HANDOFF.json"
  run env CLAUDE_CONFIG_DIR="$SRC_CFG" "$HOOK" <<<"$PAYLOAD_SRC"
  [ "$status" -eq 0 ]
}

@test "unparseable tombstone → exit 0" {
  printf 'not json at all\n' >"$SRC_DIR/$SID.HANDOFF.json"
  run env CLAUDE_CONFIG_DIR="$SRC_CFG" "$HOOK" <<<"$PAYLOAD_SRC"
  [ "$status" -eq 0 ]
}

@test "empty stdin → exit 0" {
  run env CLAUDE_CONFIG_DIR="$SRC_CFG" "$HOOK" </dev/null
  [ "$status" -eq 0 ]
}

@test "payload without transcript_path → exit 0" {
  write_tombstone "$SRC_DIR" "$DST_CFG" "$DST_TP"
  run env CLAUDE_CONFIG_DIR="$SRC_CFG" "$HOOK" <<<"{\"session_id\":\"$SID\"}"
  [ "$status" -eq 0 ]
}

# ── Key anchoring: a LONGER key must not answer for the one we asked about ──────────────────────
@test "parent_session_id in the payload does not hijack session_id extraction" {
  write_tombstone "$SRC_DIR" "$DST_CFG" "$DST_TP"
  run env CLAUDE_CONFIG_DIR="$SRC_CFG" "$HOOK" \
    <<<"{\"parent_session_id\":\"00000000-dead-dead-dead-000000000000\",\"session_id\":\"$SID\",\"transcript_path\":\"$SRC_TP\"}"
  [ "$status" -eq 2 ]
}

@test "a tombstone belonging to a DIFFERENT sid in the same dir does not convict this session" {
  printf '{"handed_off_to":"%s","target_transcript":"x","ts":"t","lock":"l"}\n' "$DST_CFG" \
    >"$SRC_DIR/00000000-dead-dead-dead-000000000000.HANDOFF.json"
  run env CLAUDE_CONFIG_DIR="$SRC_CFG" "$HOOK" <<<"$PAYLOAD_SRC"
  [ "$status" -eq 0 ]
}

# ── The wiring is part of the fix: an unwired guard is prose ────────────────────────────────────
@test "the hook is wired into the settings template's UserPromptSubmit chain" {
  run grep -c 'handed-off-session-guard.sh' "$REPO/settings-templates/settings.example.json"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# ── The $HOME fallback branch, which the hermeticity ratchet correctly flagged as untested ──────
@test "CLAUDE_CONFIG_DIR unset → identity falls back to \$HOME/.claude, and still acquits the mirror" {
  mkdir -p "$HOME/.claude/projects/$SLUG"
  HOME_TP="$HOME/.claude/projects/$SLUG/$SID.jsonl"; : >"$HOME_TP"
  write_tombstone "$HOME/.claude/projects/$SLUG" "$DST_CFG" "$DST_TP"
  run env -u CLAUDE_CONFIG_DIR "$HOOK" <<<"{\"session_id\":\"$SID\",\"transcript_path\":\"$HOME_TP\"}"
  [ "$status" -eq 0 ]
}

@test "CLAUDE_CONFIG_DIR unset + tombstone naming a DIFFERENT account → exit 2 (fallback still convicts)" {
  mkdir -p "$HOME/.claude/projects/$SLUG"
  HOME_TP="$HOME/.claude/projects/$SLUG/$SID.jsonl"; : >"$HOME_TP"
  write_tombstone "$HOME/.claude/projects/$SLUG" "$BATS_TEST_TMPDIR/.claude-quaternary" "$BATS_TEST_TMPDIR/.claude-quaternary/x.jsonl"
  run env -u CLAUDE_CONFIG_DIR "$HOOK" <<<"{\"session_id\":\"$SID\",\"transcript_path\":\"$HOME_TP\"}"
  [ "$status" -eq 2 ]
}
