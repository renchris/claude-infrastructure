#!/usr/bin/env bats
# lr-lib.sh lr_sid_file + lr_tier_from_transcript, and lr-transplant.sh's lrt_at: the session's own
# slug before the `projects/*/<sid>` glob (B4 review F10, 2026-10-20). Each glob stats every project
# dir in a store (~18,400 here, 1.2-2.4 s at load1 241-247), so the move path reads the slug it
# already knows first and globs only on a miss.
#
# THE DECOY is what makes these cases able to fail: a second copy at a slug that SORTS FIRST, so the
# glob alone returns the decoy and only a slug-first read returns the session's own copy.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR/locks"
  export LR_LIB_DIR="$REPO/scripts/limit-recover"
  unset LR_SID_SLUG LR_MOVE_LOCATION_FAST
  CFG="$BATS_TEST_TMPDIR/cfg-a"
  SID="aaaa1111-0000-4000-8000-000000000001"
  OWN="-Users-z-own"; DECOY="-Users-a-decoy"
  mkdir -p "$CFG/projects/$OWN" "$CFG/projects/$DECOY"
  # shellcheck disable=SC1091  # the subject under test, resolved from $REPO at run time
  . "$REPO/scripts/limit-recover/lr-lib.sh"
}
turn() { # $1=file $2=ts $3=model
  printf '{"type":"assistant","timestamp":"%s","effort":"high","message":{"role":"assistant","model":"%s","content":[{"type":"text","text":"work"}]}}\n' "$2" "$3" >> "$1"
}

@test "lr_slug: Claude Code's encoder, every non-alphanumeric byte becomes -" {
  [ "$(lr_slug /Users/x/.worktrees/wt_1)" = "-Users-x--worktrees-wt-1" ]
  [ -z "$(lr_slug '')" ]
}

@test "lr_sid_file: the hinted slug answers even when another copy sorts first" {
  : > "$CFG/projects/$OWN/$SID.jsonl"; : > "$CFG/projects/$DECOY/$SID.jsonl"
  run lr_sid_file "$CFG" "$SID" .jsonl
  [ "$status" -eq 0 ]; [ "$output" = "$CFG/projects/$DECOY/$SID.jsonl" ]    # control: the glob's pick
  LR_SID_SLUG="$OWN" run lr_sid_file "$CFG" "$SID" .jsonl
  [ "$status" -eq 0 ]; [ "$output" = "$CFG/projects/$OWN/$SID.jsonl" ]
}

@test "lr_sid_file: a hint that misses globs, exactly as with no hint" {
  : > "$CFG/projects/$DECOY/$SID.jsonl.handed-off"
  LR_SID_SLUG="$OWN" run lr_sid_file "$CFG" "$SID" .jsonl.handed-off
  [ "$status" -eq 0 ]; [ "$output" = "$CFG/projects/$DECOY/$SID.jsonl.handed-off" ]
  LR_SID_SLUG="$OWN" run lr_sid_file "$CFG" "$SID" .HANDOFF.json
  [ "$status" -eq 1 ]; [ -z "$output" ]
}

@test "lr_sid_file: LR_MOVE_LOCATION_FAST=off globs always" {
  : > "$CFG/projects/$OWN/$SID.jsonl"; : > "$CFG/projects/$DECOY/$SID.jsonl"
  LR_SID_SLUG="$OWN" LR_MOVE_LOCATION_FAST=off run lr_sid_file "$CFG" "$SID" .jsonl
  [ "$output" = "$CFG/projects/$DECOY/$SID.jsonl" ]
}

@test "lr_sid_file: a hint that is not a slug is never joined into a path" {
  mkdir -p "$CFG/projects/sub/dir"; : > "$CFG/projects/sub/dir/$SID.jsonl"
  LR_SID_SLUG="sub/dir" run lr_sid_file "$CFG" "$SID" .jsonl
  [ "$status" -eq 1 ]; [ -z "$output" ]
}

@test "lr_sid_file: the test operator is the caller's (-e sees what -f refuses)" {
  mkdir -p "$CFG/projects/$OWN/$SID.jsonl.handed-off"
  LR_SID_SLUG="$OWN" run lr_sid_file "$CFG" "$SID" .jsonl.handed-off
  [ "$status" -eq 1 ]
  LR_SID_SLUG="$OWN" run lr_sid_file "$CFG" "$SID" .jsonl.handed-off -e
  [ "$status" -eq 0 ]; [ "$output" = "$CFG/projects/$OWN/$SID.jsonl.handed-off" ]
}

@test "tier: the hinted copy is read first; with no turn in it the globs run as before" {
  turn "$CFG/projects/$OWN/$SID.jsonl" 2026-10-20T10:00:00.000Z claude-fable-5-1
  turn "$CFG/projects/$DECOY/$SID.jsonl" 2026-10-20T10:00:00.000Z claude-opus-5-5
  run lr_tier_from_transcript "$CFG" "$SID"
  [ "$output" = "claude-opus-5-5 high" ]                                     # control: the glob's pick
  LR_SID_SLUG="$OWN" run lr_tier_from_transcript "$CFG" "$SID"
  [ "$status" -eq 0 ]; [ "$output" = "claude-fable-5-1 high" ]
  : > "$CFG/projects/$OWN/$SID.jsonl"
  LR_SID_SLUG="$OWN" run lr_tier_from_transcript "$CFG" "$SID"
  [ "$status" -eq 0 ]; [ "$output" = "claude-opus-5-5 high" ]
}

@test "lr-transplant: a stale LR_SID_SLUG only misses — the admit still locates the source by glob" {
  TO="$BATS_TEST_TMPDIR/cfg-b"; mkdir -p "$TO/projects"
  turn "$CFG/projects/$DECOY/$SID.jsonl" 2026-10-20T10:00:00.000Z claude-opus-5-5
  LR_SID_SLUG="$OWN" LR_HOLDER_PID=$$ run /bin/bash "$REPO/scripts/limit-recover/lr-transplant.sh" \
    --sid "$SID" --from "$CFG" --to "$TO" --phase admit
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"slug\":\"$DECOY\""* ]]
  cmp -s "$CFG/projects/$DECOY/$SID.jsonl" "$TO/projects/$DECOY/$SID.jsonl"
}

@test "lr-transplant: abort reads the tombstone at the hinted slug, not the one that sorts first" {
  TO="$BATS_TEST_TMPDIR/cfg-b"; mkdir -p "$TO/projects/$OWN"
  printf '{"handed_off_to":"%s"}\n' "$BATS_TEST_TMPDIR/elsewhere" > "$CFG/projects/$DECOY/$SID.HANDOFF.json"
  printf '{"handed_off_to":"%s"}\n' "$TO" > "$CFG/projects/$OWN/$SID.HANDOFF.json"
  : > "$CFG/projects/$OWN/$SID.jsonl"
  LR_SID_SLUG="$OWN" LR_HOLDER_PID=$$ run /bin/bash "$REPO/scripts/limit-recover/lr-transplant.sh" \
    --sid "$SID" --from "$CFG" --to "$TO" --phase abort
  [ "$status" -eq 0 ]; [[ "$output" == *'"phase":"abort"'* ]]
  # control: the glob's pick is the decoy, whose tombstone names another store ⇒ refused
  LR_HOLDER_PID=$$ run /bin/bash "$REPO/scripts/limit-recover/lr-transplant.sh" \
    --sid "$SID" --from "$CFG" --to "$TO" --phase abort
  [ "$status" -ne 0 ]; [[ "$output" == *"does not name"* ]]
}
