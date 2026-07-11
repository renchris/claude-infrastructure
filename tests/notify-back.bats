#!/usr/bin/env bats
# Phase 3 — handoff-fire.sh --notify-back: the back-channel trailer.
#
# Exercised through `handoff-fire.sh --dry-run` with an explicit --launcher (which
# skips account ranking / claude-accounts / git / iTerm2 — fully side-effect-free).
# TMPDIR is pointed at the bats temp dir so the materialized prompt COPIES auto-clean.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  PF="$BATS_TEST_TMPDIR/prompt.md"
  printf 'ORIGINAL PROMPT BODY\nline two\n' > "$PF"
  export TMPDIR="$BATS_TEST_TMPDIR"
}

# extract the "copy: <path>)" the dry-run prints on its notify-back line
copy_of() { printf '%s\n' "$1" | sed -n 's/.*copy: \([^)]*\)).*/\1/p'; }

@test "--notify-back <uuid>: trailer copy carries the cc-notify ping recipe with that UUID" {
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-000000000001" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test \
    --notify-back 1234ABCD-5678-90EF-1234-567890ABCDEF --dry-run
  [ "$status" -eq 0 ]
  copy="$(copy_of "$output")"
  [ -n "$copy" ]; [ -f "$copy" ]
  grep -q 'cc-notify 1234ABCD-5678-90EF-1234-567890ABCDEF "HANDOFF-PING' "$copy"
  grep -q 'ORIGINAL PROMPT BODY' "$copy"        # the copy preserves the original body first
}

@test "--notify-back NEVER mutates the caller's prompt file" {
  before="$(shasum "$PF" | awk '{print $1}')"
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-000000000001" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test \
    --notify-back 1234ABCD-5678-90EF-1234-567890ABCDEF --dry-run
  [ "$status" -eq 0 ]
  after="$(shasum "$PF" | awk '{print $1}')"
  [ "$before" = "$after" ]
  copy="$(copy_of "$output")"
  [ "$copy" != "$PF" ]                          # trailer went to a distinct copy
}

@test "--notify-back (bare) defaults to the firing pane UUID from \$ITERM_SESSION_ID" {
  run env ITERM_SESSION_ID="w3t0p1:CAFEBABE-0000-0000-0000-000000000009" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --notify-back --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'originator CAFEBABE-0000-0000-0000-000000000009'
  copy="$(copy_of "$output")"
  grep -q 'cc-notify CAFEBABE-0000-0000-0000-000000000009' "$copy"
}

@test "--notify-back (bare) honors --session-id over \$ITERM_SESSION_ID" {
  run env ITERM_SESSION_ID="w3t0p1:AAAAAAAA-0000-0000-0000-000000000001" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test \
    --session-id BBBBBBBB-0000-0000-0000-000000000002 --notify-back --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'originator BBBBBBBB-0000-0000-0000-000000000002'
}

@test "--notify-back (bare) with no \$ITERM_SESSION_ID and no UUID errors (exit 1)" {
  run env -u ITERM_SESSION_ID \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --notify-back --dry-run
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'ITERM_SESSION_ID and no UUID'
}

@test "trailer documents the \\r-not-\\n submit invariant" {
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-000000000003" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --notify-back --dry-run
  [ "$status" -eq 0 ]
  copy="$(copy_of "$output")"
  grep -q 'r submit, not' "$copy"               # "(\r submit, not \n)"
}

@test "without --notify-back: no trailer, original prompt used as-is" {
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-000000000004" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --dry-run
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -q 'notify-back:'
  printf '%s\n' "$output" | grep -qF "cat $PF"  # command reads the original prompt directly
}
