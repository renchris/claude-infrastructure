#!/usr/bin/env bats
# cc-backlog KEY 4 (`dups --mode mechanical`) + the `needs` MINT BRAKE — READINESS R6/R7.
#
# WHAT THESE PIN, AND WHY THE REFUSALS OUTNUMBER THE ACCEPTANCES. This is the first duplicate key in
# the file with a WRITER on the end of it: the trigger's `--fold` turns a group into `link` records,
# and `link` feeds claim guard (6), so a wrong group REFUSES dispatch on work that is not duplicated
# and nothing downstream reports the move. The premise R6 was written on — "rows differing only by
# an embedded sha fold with no judgment" — is false in exactly the population it was measured in:
# on 2026-08-11 the consolidation trigger's largest cluster was 14 rows that its `<sha>`
# normalisation had merged out of NINE different stranded worktrees. So the acceptance cases below
# are the easy half, and every refusal is a case the obvious key gets wrong.
#
# THE BRAKE IS THE SAME KEY ASKED ONE STEP EARLIER. 172 live `needs` rows on the day it landed, 46
# of them recurrences in 18 groups — so it is measured, not hypothesised, and a case that mints must
# be pinned beside every case that folds (memory: control-must-replay-the-real-artifact).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  # Verbatim from the live ledger: six re-land rows for ONE worktree, differing only inside the
  # failed-land ref's timestamp.
  # `@@` is substituted, not printf-formatted: a variable used AS a format string is SC2059, and
  # the finding is not pedantic here — a `%` pasted into a fixture title from a real ledger row
  # would be eaten silently and the fixture would stop being the shape it claims to replay.
  RL='re-land mcp-w-no-inherit (/Users/x/.worktrees/mcp-w-no-inherit): ship-land exited 6 (exit) and its author pane may be gone — head pinned at refs/land/failed/20260811T08@@02Z-53391a94-mcp-w-no-inherit'
}

n_items()  { bash "$CB" list --all --json | jq 'length'; }
n_mech()   { bash "$CB" dups --mode mechanical --json | jq '.mechanical|length'; }
refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

# ── KEY 4 ──────────────────────────────────────────────────────────────────────────────────────

@test "mechanical: rows differing only INSIDE a digit run of one identifier are ONE group" {
  for t in 1507 1742 2007; do
    bash "$CB" add --project P --source needs --title "${RL/@@/$t}" >/dev/null
  done
  [ "$(n_items)" -eq 3 ]
  [ "$(n_mech)" -eq 1 ]
  run bash "$CB" dups --mode mechanical
  printf '%s' "$output" | grep -q "mechanical: 1 group"
}

@test "mechanical REFUSES two subjects whose identifiers differ in a LETTER" {
  # wt-7ff1b6f5ddbb vs wt-4ce34a4f703c: the detector's `[0-9a-f]{7,40}` erases both to <sha> and
  # calls them one cluster. Masking digit runs keeps #ff#b#f#ddbb apart from #ce#a#f#c.
  for w in 7ff1b6f5ddbb 4ce34a4f703c; do
    bash "$CB" add --project P --source needs \
      --title "re-land wt-$w (/Users/x/.worktrees/wt-$w): ship-land exited 6 (exit)" >/dev/null
  done
  [ "$(n_items)" -eq 2 ]
  [ "$(n_mech)" -eq 0 ]
}

@test "mechanical REFUSES a group with no identifier at all — a bare number is not a subject" {
  bash "$CB" add --project P --source needs --title "restart the pane and wait 3 seconds" >/dev/null
  bash "$CB" add --project P --source needs --title "restart the pane and wait 7 seconds" >/dev/null
  [ "$(n_items)" -eq 2 ]
  [ "$(n_mech)" -eq 0 ]
}

@test "mechanical REFUSES a near-wordless title — the floor that stops every untitled row collapsing" {
  # Two surviving prose tokens ("go", "x"): below the floor, so these abstain even though their
  # subject identifier (x/y#) matches exactly. Keying on a normalised title unconditionally is what
  # collapsed every untitled row into one cluster the first time.
  bash "$CB" add --project P --source needs --title "go x/y1 2" >/dev/null
  bash "$CB" add --project P --source needs --title "go x/y1 3" >/dev/null
  [ "$(n_items)" -eq 2 ]
  [ "$(n_mech)" -eq 0 ]
}

@test "mechanical spans BLOCKED rows — key 2 cannot see them, and every live recurrence is one" {
  for t in 1507 1742; do
    CC_BACKLOG_NEEDS_BRAKE=off bash "$CB" needs "${RL/@@/$t}" --project P >/dev/null
  done
  [ "$(bash "$CB" list --all --json | jq '[.[]|select(.status=="blocked")]|length')" -eq 2 ]
  [ "$(bash "$CB" dups --mode title --json | jq '.title|length')" -eq 0 ]
  [ "$(n_mech)" -eq 1 ]
}

@test "mechanical ignores DONE rows — a closed step is not a live duplicate" {
  a=$(bash "$CB" add --project P --source needs --title "${RL/@@/1507}")
  bash "$CB" add --project P --source needs --title "${RL/@@/1742}" >/dev/null
  [ "$(n_mech)" -eq 1 ]
  bash "$CB" "done" "$a" --evidence landed >/dev/null
  [ "$(n_mech)" -eq 0 ]
}

# ── THE MINT BRAKE ─────────────────────────────────────────────────────────────────────────────

@test "brake: a recurring operator step re-files onto the existing row instead of minting" {
  first=$(bash "$CB" needs "${RL/@@/1507}" --project P)
  again=$(bash "$CB" needs "${RL/@@/1742}" --project P)
  [ "$first" = "$again" ]
  [ "$(n_items)" -eq 1 ]
  # and it is still the operator's step: blocked, carrying the LATEST wording.
  [ "$(bash "$CB" list --all --json | jq -r '.[0].status')" = blocked ]
  bash "$CB" list --all --json | jq -e '.[0].needs|test("1742")' >/dev/null
}

@test "brake CONTROL: a different subject still mints, or the brake is just a swallow" {
  a=$(bash "$CB" needs "re-land wt-7ff1b6f5ddbb (/Users/x/.worktrees/wt-7ff1b6f5ddbb): ship-land exited 6 (exit)" --project P)
  b=$(bash "$CB" needs "re-land wt-4ce34a4f703c (/Users/x/.worktrees/wt-4ce34a4f703c): ship-land exited 6 (exit)" --project P)
  [ "$a" != "$b" ]
  [ "$(n_items)" -eq 2 ]
}

@test "brake CONTROL: the same subject with a different step still mints" {
  a=$(bash "$CB" needs "re-land wt-abcdefab (/Users/x/.worktrees/wt-abcdefab): ship-land exited 6 (exit)" --project P)
  b=$(bash "$CB" needs "delete the stale worktree wt-abcdefab (/Users/x/.worktrees/wt-abcdefab) after 2 days" --project P)
  [ "$a" != "$b" ]
  [ "$(n_items)" -eq 2 ]
}

@test "brake: a recurrence of a DONE step MINTS — swallowing it would drop the operator's work" {
  a=$(bash "$CB" needs "${RL/@@/1507}" --project P)
  bash "$CB" "done" "$a" --evidence landed >/dev/null
  b=$(bash "$CB" needs "${RL/@@/1742}" --project P)
  [ "$a" != "$b" ]
  [ "$(n_items)" -eq 2 ]
}

@test "brake: CC_BACKLOG_NEEDS_BRAKE=off restores the mint, and says nothing about it" {
  a=$(bash "$CB" needs "${RL/@@/1507}" --project P)
  b=$(CC_BACKLOG_NEEDS_BRAKE=off bash "$CB" needs "${RL/@@/1742}" --project P)
  [ "$a" != "$b" ]
  [ "$(n_items)" -eq 2 ]
}

@test "brake ANNOUNCES itself on stderr — a silent swallow is indistinguishable from a lost row" {
  bash "$CB" needs "${RL/@@/1507}" --project P >/dev/null
  run bash "$CB" needs "${RL/@@/1742}" --project P
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "RECURRENCE"
  printf '%s' "$output" | grep -q "CC_BACKLOG_NEEDS_BRAKE=off"
}

@test "brake is append-only: the recurrence adds a record, never rewrites one" {
  bash "$CB" needs "${RL/@@/1507}" --project P >/dev/null
  before="$(grep -c . "$CC_BACKLOG_FILE")"
  bash "$CB" needs "${RL/@@/1742}" --project P >/dev/null
  [ "$(grep -c . "$CC_BACKLOG_FILE")" -gt "$before" ]
  [ "$(jq -r 'select(.event=="add")|.id' "$CC_BACKLOG_FILE" | sort -u | wc -l | tr -d ' ')" -eq 1 ]
}

@test "an unknown --mode is refused, and the message names the new key" {
  run bash "$CB" dups --mode nonsense
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q "mechanical"
}
