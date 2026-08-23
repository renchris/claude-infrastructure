#!/usr/bin/env bats
# THE CLOUD→LEDGER HAND-BACK: a verdict recorded at a venue that cannot write the ledger, folded in
# at the venue that can.
#
# The defect it closes is measured, not hypothesised: backlog `354c73ebd400` had its cure landed on
# 2026-08-16/17 and was dispatched to a cloud worker again on 08-19 and again on 08-23. Each pass
# re-derived the same already-landed answer and each ended the same way — `cc-backlog done` returns
# `unknown id` off-box, so the row could not be closed, so the next wave dispatched it again. Three
# worker slots, one cure.
#
# WHAT THESE TESTS PIN, in order of how much they would cost if they broke:
#   1. THE CEILING. A record is data from another venue. It may advance a row the box already knows
#      and NOTHING else: it can never create one, it carries two verbs only, and no field of it ever
#      reaches a shell. Those are the tests that matter if this transport is ever pointed at.
#   2. THE LATCH. `apply` must set `wasDone` — that is the field cc-dispatch reads to keep a
#      finished row out of the wave, i.e. the thing that actually stops the loop. A `done` that
#      changed `status` but not the latch would close the row and re-dispatch it anyway.
#   3. "CANNOT FOLD" ≠ "NOTHING PENDING". `cc-backlog list --all --json` prints `[]` rc 0 against a
#      MISSING ledger, so the off-box venue must probe the ledger FILE. Reading `[]` as an answer
#      would make every record report UNKNOWN at exactly the venue that wrote it.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HB="$REPO/scripts/backlog-handback.sh"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_HANDBACK_DIR="$BATS_TEST_TMPDIR/store"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_PROJECT_WARN=off
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
}

file_a_row() {  # <title> → the id
  "$CB" add --title "$1" --project claude-infrastructure 2>/dev/null
}

# ── the ceiling ──────────────────────────────────────────────────────────────────────────────────

@test "record carries done and block, and refuses every other verb" {
  run bash "$HB" record aaaaaaaaaaaa --verb done --evidence sha
  [ "$status" -eq 0 ]
  run bash "$HB" record aaaaaaaaaaaa --verb block --needs "operator must rotate the key"
  [ "$status" -eq 0 ]
  for v in reopen claim add venue unblock; do
    run bash "$HB" record aaaaaaaaaaaa --verb "$v" --evidence sha
    [ "$status" -eq 64 ]
  done
}

@test "record refuses an id that is not a backlog id" {
  run bash "$HB" record 'aaaa; rm -rf /' --verb done --evidence sha
  [ "$status" -eq 64 ]
  run bash "$HB" record '../../etc/passwd' --verb done --evidence sha
  [ "$status" -eq 64 ]
  run bash "$HB" record 'AAAAAAAAAAAA' --verb done --evidence sha   # hex is lowercase
  [ "$status" -eq 64 ]
}

@test "apply NEVER creates a row the ledger does not already have" {
  file_a_row "an unrelated row" >/dev/null
  bash "$HB" record bbbbbbbbbbbb --verb done --evidence sha >/dev/null
  CONFIRM=1 run bash "$HB" apply
  [ "$status" -eq 0 ]
  run grep -c bbbbbbbbbbbb "$CC_BACKLOG_FILE"
  [ "$status" -ne 0 ]                      # not one record mentions it
  bash "$HB" list > "$BATS_TEST_TMPDIR/out"
  grep -q '^UNKNOWN.*bbbbbbbbbbbb' "$BATS_TEST_TMPDIR/out"
}

@test "a payload edited into the record after the fact is refused, never executed" {
  # The file is a git artifact: a later commit can edit it without passing through `record`, so the
  # validation on the way OUT is the one that has to hold.
  mkdir -p "$CC_HANDBACK_DIR"
  printf '{"id":"$(touch %s/pwned)","verb":"done","evidence":"x"}\n' "$BATS_TEST_TMPDIR" \
    > "$CC_HANDBACK_DIR/00000001-evil.json"
  printf '{"id":"cccccccccccc","verb":"done; touch %s/pwned2","evidence":"x"}\n' "$BATS_TEST_TMPDIR" \
    > "$CC_HANDBACK_DIR/00000002-evil.json"
  file_a_row "a row so the ledger exists" >/dev/null
  CONFIRM=1 run bash "$HB" apply
  [ "$status" -eq 66 ]                     # malformed reported, never silently skipped
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned2" ]
}

@test "apply refuses without CONFIRM" {
  file_a_row "row" >/dev/null
  run bash "$HB" apply
  [ "$status" -eq 65 ]
}

# ── the latch: what actually stops the re-dispatch ───────────────────────────────────────────────

@test "apply folds a done verdict and sets the wasDone latch" {
  id="$(file_a_row "a row a cloud worker finished")"
  [ -n "$id" ]
  bash "$HB" record "$id" --verb done --evidence "abc123 + def456" >/dev/null
  bash "$HB" list > "$BATS_TEST_TMPDIR/before"
  grep -q "^PENDING	$id	done" "$BATS_TEST_TMPDIR/before"

  CONFIRM=1 run bash "$HB" apply
  [ "$status" -eq 0 ]

  "$CB" list --all --json > "$BATS_TEST_TMPDIR/led"
  run jq -r --arg i "$id" 'map(select(.id==$i))[0] | "\(.status) \(.wasDone) \(.evidence)"' "$BATS_TEST_TMPDIR/led"
  [ "$output" = "done true abc123 + def456" ]

  bash "$HB" list > "$BATS_TEST_TMPDIR/after"
  grep -q "^APPLIED	$id	done" "$BATS_TEST_TMPDIR/after"
}

@test "apply folds a block verdict with the operator step intact" {
  id="$(file_a_row "a row only the operator can finish")"
  bash "$HB" record "$id" --verb block --needs "launchctl bootout the stale agent" >/dev/null
  CONFIRM=1 bash "$HB" apply
  "$CB" list --blocked --json > "$BATS_TEST_TMPDIR/led"
  run jq -r --arg i "$id" 'map(select(.id==$i))[0].needs' "$BATS_TEST_TMPDIR/led"
  [ "$output" = "launchctl bootout the stale agent" ]
}

@test "apply is idempotent and record is idempotent" {
  id="$(file_a_row "a row")"
  bash "$HB" record "$id" --verb done --evidence sha >/dev/null
  bash "$HB" record "$id" --verb done --evidence sha >/dev/null
  [ "$(ls -1 "$CC_HANDBACK_DIR" | wc -l | tr -d ' ')" -eq 1 ]
  CONFIRM=1 bash "$HB" apply
  CONFIRM=1 run bash "$HB" apply
  [ "$status" -eq 0 ]
  [ "$(grep -c '"event":"done"' "$CC_BACKLOG_FILE" || true)" -le 2 ]
}

# ── "cannot fold" is never "nothing pending" ─────────────────────────────────────────────────────

@test "no ledger: list says CANNOT FOLD, apply refuses, render offers nothing" {
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/does-not-exist.jsonl"
  bash "$HB" record 354c73ebd400 --verb done --evidence sha >/dev/null
  bash "$HB" list > "$BATS_TEST_TMPDIR/out"
  grep -q 'CANNOT FOLD' "$BATS_TEST_TMPDIR/out"
  grep -q '^NO-LEDGER' "$BATS_TEST_TMPDIR/out"
  # THE CONTROL: it must not report a count of pending records it cannot possibly know.
  ! grep -q '0 pending' "$BATS_TEST_TMPDIR/out" || false
  CONFIRM=1 run bash "$HB" apply
  [ "$status" -eq 65 ]
  run bash "$HB" render
  [ -z "$output" ]
}

@test "render is silent with nothing pending and offers exactly one command when there is" {
  id="$(file_a_row "a row")"
  run bash "$HB" render
  [ -z "$output" ]
  bash "$HB" record "$id" --verb done --evidence sha >/dev/null
  bash "$HB" render > "$BATS_TEST_TMPDIR/r"
  grep -q '▶ Run this:' "$BATS_TEST_TMPDIR/r"
  [ "$(grep -c 'CONFIRM=1' "$BATS_TEST_TMPDIR/r")" -eq 1 ]
  CONFIRM=1 bash "$HB" apply
  run bash "$HB" render
  [ -z "$output" ]
}

@test "a malformed record is reported and does not stop the good ones" {
  id="$(file_a_row "a good row")"
  bash "$HB" record "$id" --verb done --evidence sha >/dev/null
  printf 'not json\n' > "$CC_HANDBACK_DIR/00000003-bad.json"
  CONFIRM=1 run bash "$HB" apply
  [ "$status" -eq 66 ]
  "$CB" list --all --json > "$BATS_TEST_TMPDIR/led"
  run jq -r --arg i "$id" 'map(select(.id==$i))[0].status' "$BATS_TEST_TMPDIR/led"
  [ "$output" = "done" ]
}

@test "the script's own selftest passes" {
  run bash "$HB" --selftest
  [ "$status" -eq 0 ]
}

# ── the wiring ratchet ───────────────────────────────────────────────────────────────────────────

@test "cloud-reconcile still surfaces pending hand-backs at every verb" {
  # A STRUCTURAL check, and it is honest about being one: it does not prove the report renders, only
  # that the call sites still exist. It is here because the whole failure mode this transport fixes
  # is a conclusion that never reaches its enforcing store — an unwired renderer would be the same
  # defect wearing a fix's clothes, and it would be invisible to every behavioural test above.
  run grep -c 'handback_report' "$REPO/scripts/cloud-reconcile.sh"
  [ "$output" -ge 4 ]     # the definition + --list + --land + --all
}
