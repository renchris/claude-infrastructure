#!/usr/bin/env bats
# scripts/drain-recycle-fire.sh — the chokepoint that makes §4.1's goal and its closure floor
# mechanical instead of retyped.
#
# WHAT IS BEING PINNED, and it is not "does the script print a goal". The subject replaces a rule
# that decayed: §4.1's fire command has carried `--goal` since it was written, and the live chain
# fired **183 recycle-intent rows with `goal_requested:false` against 46 true** — every one of the
# last forty false. So the properties that matter are (a) the goal cannot be omitted by a caller who
# forgets it, (b) it is a SHAPE handoff-fire will actually arm rather than refuse, and (c) the floor
# it carries can read both MET and UNMET, because a check that can only say one of them is not a
# check (memory `fail-safe-default-mimics-the-healthy-state`).
#
# THE FIXTURE LEDGER IS WRITTEN BY THE REAL bin/cc-backlog, never hand-rolled: the subject folds the
# ledger, so a hand-written one would pin this suite's idea of the events rather than cc-backlog's
# (memory `sibling-auditors-must-share-the-state-model`).

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJECT="${CC_DRAIN_FIRE_SUBJECT:-$REPO/scripts/drain-recycle-fire.sh}"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  # This suite never reaches the real handoff-fire (CC_DRAIN_FIRE_BIN below is a recorder), but the
  # hermeticity ratchet reads the file, not the wiring — and it is right to: a later case that DID
  # reach it would go red-by-load on a box that lives above 2.0/core, not red by its subject.
  export CC_FIRE_CAPACITY_GATE=off

  # The fire path, replaced by a recorder. Firing for real would spawn a pane; what this suite has
  # to prove is what the subject HANDS the fire path, which is exactly its argv.
  export CC_DRAIN_FIRE_BIN="$BATS_TEST_TMPDIR/fake-fire.sh"
  ARGV="$BATS_TEST_TMPDIR/argv.txt"
  cat > "$CC_DRAIN_FIRE_BIN" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGV"
EOF
  chmod +x "$CC_DRAIN_FIRE_BIN"

  POINTER="$BATS_TEST_TMPDIR/fire-pointer-280.txt"
  printf 'read the brief in full\n' > "$POINTER"
}

add()   { bash "$CB" add --project claude-infrastructure --title "$1" --source fx; }
goal()  { bash "$SUBJECT" --num "${1:-280}" --print-goal; }
# The condition as the fire path received it: the value of the argument AFTER --goal.
armed_goal() { grep -A1 -x -- '--goal' "$ARGV" | tail -1; }

# ── (a) the goal cannot be omitted ───────────────────────────────────────────────────────────────
#
# THE POSITIVE CONTROL FOR THE WHOLE FILE. The measured pre-state is a fire with no `--goal` at all;
# this asserts the flag AND a non-empty condition reach the fire path from a caller that never
# mentioned a goal.
@test "a plain fire hands handoff-fire a --recycle and a non-empty --goal" {
  run bash "$SUBJECT" --num 280 --prompt-file "$POINTER"
  [ "$status" -eq 0 ]
  [ "$(grep -c -x -- '--recycle' "$ARGV")" -eq 1 ]
  [ "$(grep -c -x -- '--goal' "$ARGV")" -eq 1 ]
  [ -n "$(armed_goal)" ]
}

@test "extra arguments pass through to handoff-fire untouched, beside the goal" {
  run bash "$SUBJECT" --num 280 --prompt-file "$POINTER" --account auto --split-right
  [ "$status" -eq 0 ]
  [ "$(grep -c -x -- '--account' "$ARGV")" -eq 1 ]
  [ "$(grep -c -x -- 'auto' "$ARGV")" -eq 1 ]
  [ "$(grep -c -x -- '--split-right' "$ARGV")" -eq 1 ]
  [ "$(grep -c -x -- '--goal' "$ARGV")" -eq 1 ]
}

# NEVER FIRE A LINK WITH NO BRIEF. The one failure the chain cannot survive is a successor that
# comes up with nothing to do, so an unreadable pointer is refused BEFORE the fire, not after it.
@test "an unreadable prompt-file refuses rather than firing a brief-less link" {
  run bash "$SUBJECT" --num 280 --prompt-file "$BATS_TEST_TMPDIR/no-such-pointer.txt"
  [ "$status" -eq 2 ]
  [ ! -f "$ARGV" ]
}

@test "the recycle number must be a number, and a missing one refuses" {
  run bash "$SUBJECT" --num "two-eighty" --prompt-file "$POINTER"
  [ "$status" -eq 2 ]
  run bash "$SUBJECT" --prompt-file "$POINTER"
  [ "$status" -eq 2 ]
}

# ── (b) the condition is a SHAPE handoff-fire will arm ──────────────────────────────────────────
#
# All three are refused by scripts/handoff-fire.sh's check_goal_arm, and a refusal there costs the
# chain a link. Pinned against the SUBJECT's own output rather than against the fire path, so this
# stays true if the wrapper's wording is ever rewritten.
@test "the condition is ONE line — a newline strands the rest in the composer" {
  [ "$(goal | wc -l | tr -d ' ')" -eq 1 ]
}

@test "the condition does not start with a slash — it would read as another command" {
  case "$(goal)" in /*) return 1 ;; esac
}

@test "the condition is inside the harness's 4000-char cap" {
  n="$(goal | tr -d '\n' | wc -c | tr -d ' ')"
  [ "$n" -lt 4000 ]
  # …and not vacuously short. A one-word condition would pass the cap and say nothing.
  [ "$n" -gt 200 ]
}

# THE CLOSURE FLOOR IS IN THE CONDITION, AND SO IS THE COMMAND THAT PROVES IT. The goal evaluator is
# tool-less and sees only what the session surfaces, so a condition naming state nobody prints can
# never clear (§4.1's own #124 finding, one layer up).
@test "the condition names the floor AND the command that prints it" {
  g="$(goal 280)"
  [ "$(printf '%s' "$g" | grep -c 'floor=MET')" -eq 1 ]
  [ "$(printf '%s' "$g" | grep -c -- '--closure-report')" -eq 1 ]
  [ "$(printf '%s' "$g" | grep -c 'closed >= 1 AND closed >= filed')" -eq 1 ]
}

# INVARIANT 6 IS SUBORDINATED BY POSITION, NOT BY PROSE. §4.1 measured that a duty with no position
# ahead of the fire is unreachable the moment the session takes the goal at its word (#124's missing
# ping). So the floor must appear BEFORE the fire clause in the one string the evaluator reads.
@test "the floor is stated before the fire clause, so the fire cannot outrank it" {
  g="$(goal 280)"
  floor_at=$(awk '{print index($0, "floor=MET")}' <<<"$g")
  fire_at=$(awk '{print index($0, "is FIRED")}' <<<"$g")
  [ "$floor_at" -gt 0 ]
  [ "$fire_at" -gt 0 ]
  [ "$floor_at" -lt "$fire_at" ]
}

@test "the condition names THIS link and the successor it must fire" {
  g="$(goal 280)"
  [ "$(printf '%s' "$g" | grep -c 'recycle #280')" -eq 1 ]
  [ "$(printf '%s' "$g" | grep -c 'recycle #281')" -eq 1 ]
}

# ── (c) the floor can read BOTH ways ────────────────────────────────────────────────────────────

@test "a recycle that closes nothing is UNMET, and the report exits 1" {
  add "a row this recycle filed" >/dev/null
  run bash "$SUBJECT" --closure-report 2020-01-01T00:00:00Z
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'floor=UNMET')" -eq 1 ]
}

# THE CONTROL THAT MAKES THE CASE ABOVE MEAN SOMETHING. An alarm that can only say UNMET is
# indistinguishable from one that cannot compute.
@test "a recycle that closes more than it filed is MET, and the report exits 0" {
  id=$(add "a row filed earlier")
  # The ledger stamps to the SECOND, and the window predicate is `ts >= since` — so a cut taken in
  # the same second as the add would count that add as inside the window. Sleep BEFORE the cut.
  sleep 1
  cut="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sleep 1
  bash "$CB" "done" "$id" --evidence "landed abc1234" >/dev/null 2>&1
  run bash "$SUBJECT" --closure-report "$cut"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'floor=MET')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'closed=1 filed=0')" -eq 1 ]
}

# EQUALITY IS MET, NOT UNMET: §4.1 invariant 4 is "close >= file", and a boundary read the other way
# would convict a link that broke even.
@test "closing exactly as many as were filed MEETS the floor" {
  a=$(add "row a")
  b=$(add "row b")
  sleep 1
  cut="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sleep 1
  c=$(add "row c")
  bash "$CB" "done" "$a" --evidence "landed abc1234" >/dev/null 2>&1
  run bash "$SUBJECT" --closure-report "$cut"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'closed=1 filed=1 ')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'floor=MET')" -eq 1 ]
  [ -n "$b" ]
  [ -n "$c" ]
}

# COUNT DISTINCT IDS, NOT EVENTS. cc-backlog re-emits `add` for a known id on a title refresh, so an
# event fold would read a refresh as a fresh filing and convict a link for keeping a title current.
@test "a title refresh is not a new filing" {
  id=$(add "a row with a title that will be refreshed")
  sleep 1
  cut="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sleep 1
  bash "$CB" add --project claude-infrastructure --source fx \
      --title "a row with a title that will be refreshed — now with a fresh measurement" >/dev/null 2>&1
  bash "$CB" "done" "$id" --evidence "landed abc1234" >/dev/null 2>&1
  run bash "$SUBJECT" --closure-report "$cut"
  [ "$(printf '%s' "$output" | grep -c 'closed=1')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'floor=MET')" -eq 1 ]
}

# THE BLOCKED TAIL IS REPORTED, NOT HIDDEN. A zero without its blocked tail is the exact defect that
# produced this plan (BACKLOG_DRAIN_24_7 §1.1), and routing rows to the operator must never be a way
# to make the floor look met.
@test "rows routed to the operator are counted and shown, and do not count as closures" {
  id=$(add "a row the operator must unblock")
  cut="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sleep 1
  bash "$CB" block "$id" --needs "the operator must rotate a key" >/dev/null 2>&1
  run bash "$SUBJECT" --closure-report "$cut"
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'blocked=1')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'floor=UNMET')" -eq 1 ]
}

@test "the report prints its own predicate and the ledger it read" {
  add "a row" >/dev/null
  run bash "$SUBJECT" --closure-report 2020-01-01T00:00:00Z
  [ "$(printf '%s' "$output" | grep -c '^predicate:')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c "^ledger:.*$CC_BACKLOG_FILE")" -eq 1 ]
}

@test "a malformed timestamp refuses rather than folding the whole ledger" {
  add "a row" >/dev/null
  run bash "$SUBJECT" --closure-report "yesterday"
  [ "$status" -eq 2 ]
}

# THE WINDOW DEFAULTS TO NOW, so a link measures the rows IT discharged. Inheriting its
# predecessor's window is how a chain certifies itself on somebody else's work.
@test "the goal's window is stamped at fire time, not inherited" {
  g1="$(goal 280)"
  sleep 1
  g2="$(goal 280)"
  [ "$g1" != "$g2" ]
  [ "$(printf '%s' "$g1" | grep -cE '\-\-closure-report [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z')" -eq 1 ]
}

@test "an explicit --since pins the window for a session that started earlier" {
  g="$(bash "$SUBJECT" --num 280 --since 2026-09-01T00:00:00Z --print-goal)"
  [ "$(printf '%s' "$g" | grep -c -- '--closure-report 2026-09-01T00:00:00Z')" -eq 1 ]
}

@test "--print-goal has no side effect: nothing is fired" {
  run bash "$SUBJECT" --num 280 --print-goal
  [ "$status" -eq 0 ]
  [ ! -f "$ARGV" ]
}
