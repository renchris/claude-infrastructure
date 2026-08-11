#!/usr/bin/env bats
# lr-fire-resume.sh — a transplant tombstone must GUARD the resume path, not merely record it.
#
# THE DEFECT (24c9955d6c4f). lr-transplant.sh writes a per-session tombstone naming the account a
# session moved TO, and takes a split-brain lock — but only the TRANSPLANT path ever read it. On
# 2026-08-10 17:36Z the operator ran /limit-recover in the three ORIGINAL panes the morning after an
# overnight transplant. The recovery OPENED the tombstone directory — it wrote its own audit files
# into it — and resumed anyway. Two sessions went live in two accounts at once; one diverged and
# landed independently.
#
# THE SHAPE OF THE CURE. "Refuse whenever a tombstone exists" would break the primary path, because
# resuming ON the transplant target is the entire point of a transplant. The discriminator is where
# the resume is LANDING: the target is the successor and is always allowed; any other account is a
# second live copy.
#
# AND THE GUARD MUST NOT STRAND A REAL RECOVERY, which would be worse than the bug. The tempting
# allow-test is "the successor has been idle for N hours" and it is rejected on precedent in this
# repo: stamp-age as a liveness proxy goes false during exactly the long quiet runs that matter, so
# it would hand back a false all-clear over a live session. What is provable from disk is ABSENCE.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$LR_STATE_DIR/locks"

  eval "$(sed -n '/^lr_tombstone_verdict() {/,/^}/p' "$FIRE")"
  command -v lr_tombstone_verdict >/dev/null \
    || { echo "extraction of lr_tombstone_verdict from $FIRE failed" >&2; return 1; }
  # Supplied by the generated account map in production; stubbed here so the verdict text is tested,
  # not the operator's account roster.
  cc_acct_name_for_dir_basename() { case "$1" in .claude-quaternary) echo next4 ;; *) echo "" ;; esac; }

  SID="21fe99e4-6a71-482a-9337-1c660413a0f6"
  SRC="$BATS_TEST_TMPDIR/.claude-tertiary"
  DST="$BATS_TEST_TMPDIR/.claude-quaternary"
  SLUG="-Users-chrisren-Development-claude-infrastructure"
  mkdir -p "$SRC/projects/$SLUG" "$DST/projects/$SLUG"
}

# The exact record lr-transplant.sh writes (scripts/limit-recover/lr-transplant.sh printf).
mk_tombstone() {
  printf '{"sid":"%s","from":"%s","to":"%s","ts":"2026-08-10T10:46:25Z","pid":41434,"host":"h"}\n' \
    "$SID" "$SRC" "${1:-$DST}" > "$LR_STATE_DIR/locks/$SID.lock"
}
mk_successor() { : > "$DST/projects/$SLUG/$SID.jsonl"; }

@test "CONTROL (a): a sid with NO tombstone resumes unchanged" {
  run lr_tombstone_verdict "$SID" "$SRC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no tombstone"* ]] || { echo "$output"; false; }
}

@test "THE INCIDENT: resuming a transplanted sid on the account it came FROM is refused" {
  mk_tombstone; mk_successor
  run lr_tombstone_verdict "$SID" "$SRC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"REFUSED"* ]] || { echo "$output"; false; }
}

@test "the refusal names where the session actually went, and its last activity" {
  # A refusal the operator cannot act on is a wall. It has to answer "then where is it?" in the
  # same breath — target account, successor transcript, when it last moved.
  mk_tombstone; mk_successor
  run lr_tombstone_verdict "$SID" "$SRC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"next4"* ]]                       || { echo "no target account: $output"; false; }
  [[ "$output" == *"$DST/projects/$SLUG/$SID.jsonl"* ]] || { echo "no successor path: $output"; false; }
  [[ "$output" == *"last activity"* ]]               || { echo "no last activity: $output"; false; }
}

@test "the transplant TARGET resuming itself is allowed — the primary path is not broken" {
  # The discriminating control. A guard that keys on "a tombstone exists" instead of "where is this
  # landing" passes every test above and breaks every transplant.
  mk_tombstone; mk_successor
  run lr_tombstone_verdict "$SID" "$DST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"transplant target"* ]] || { echo "$output"; false; }
}

@test "CONTROL (b): a tombstone whose successor is GONE must not block recovery" {
  mk_tombstone            # no mk_successor — the target holds no transcript for this sid
  run lr_tombstone_verdict "$SID" "$SRC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"successor is gone"* ]] || { echo "$output"; false; }
}

@test "a tombstone that names no target FAILS CLOSED rather than reading as clear" {
  # "Cannot say where it went" is not "it went nowhere". This is the one case where refusing is the
  # safe answer, and it is the case a naive `grep -q` guard gets backwards.
  printf '{"sid":"%s","garbage":true}\n' "$SID" > "$LR_STATE_DIR/locks/$SID.lock"
  run lr_tombstone_verdict "$SID" "$SRC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"names no target"* ]] || { echo "$output"; false; }
}

# ── the WIRING — every test above stays green if the guard is never CALLED ────────────────────────
# The discriminator is the script's exit taxonomy. The guard runs after the config-dir check and
# before the worktree is recreated, so with a missing worktree and no --branch:
#   exit 3 + "REFUSED"        ⇒ the guard ran and refused
#   exit 2 + "worktree … missing" ⇒ it got past the guard

@test "WIRING: the script itself refuses, before it creates a worktree or spawns anything" {
  mk_tombstone; mk_successor
  run env LR_STATE_DIR="$LR_STATE_DIR" bash "$FIRE" "$SRC" "$BATS_TEST_TMPDIR/nowt" "$SID" \
      --model claude-opus-5 --effort high
  [ "$status" -eq 3 ]
  [[ "$output" == *"REFUSED"* ]]      || { echo "$output"; false; }
  [[ "$output" == *"--force-split"* ]] || { echo "the refusal names no way forward: $output"; false; }
  [ ! -d "$BATS_TEST_TMPDIR/nowt" ] || { echo "it created a worktree before refusing"; false; }
}

@test "WIRING: --force-split is the deliberate override, and it gets PAST the guard" {
  mk_tombstone; mk_successor
  run env LR_STATE_DIR="$LR_STATE_DIR" bash "$FIRE" "$SRC" "$BATS_TEST_TMPDIR/nowt" "$SID" \
      --model claude-opus-5 --effort high --force-split
  [ "$status" -eq 2 ]
  [[ "$output" == *"worktree"* ]] || { echo "did not reach the worktree check: $output"; false; }
}

@test "WIRING CONTROL: with no tombstone the script reaches the same later failure" {
  # Without this, the refusal test above could be passing on a script that exits 3 for any reason.
  run env LR_STATE_DIR="$LR_STATE_DIR" bash "$FIRE" "$SRC" "$BATS_TEST_TMPDIR/nowt" "$SID" \
      --model claude-opus-5 --effort high
  [ "$status" -eq 2 ]
  [[ "$output" != *"REFUSED"* ]] || { echo "$output"; false; }
}
