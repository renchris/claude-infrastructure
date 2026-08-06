#!/usr/bin/env bats
# cc-backlog `add --condition` — the CONDITION KEY (backlog 0b3a8b19d4d4).
#
# The event key is project+title+source, so a title carrying a live measurement re-keys itself every
# time it is measured: one standing condition ("this project's memory index is over its loader
# budget") minted 21 items between 2026-07-25 and 2026-08-06 instead of one, and the ledger's own
# done-guard never fired because a re-file only reads as a re-file when it lands on the same key.
# `--condition <slug>` keys the id on project+condition and drops title and source from the hash.
#
# THE CONTROL IS NOT INCIDENTAL. Every dedupe assertion below is paired with the SAME two adds run
# WITHOUT --condition, which must still mint two items. Without that pair a stub `--condition` that
# ignored its argument, or a mk_id that had silently stopped hashing the title, would pass the whole
# file green (memory: control-must-replay-the-real-artifact).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  # $HOME is fixtured FIRST, before the explicit seams below, and both are kept. cc-backlog defaults
  # the ledger, the IDL, the kick marker and the kick binary under $HOME, so an unfixtured suite
  # writes fixture rows into the operator's live autonomy state — this file's sibling
  # tests/cc-backlog.bats is one of the grandfathered suites that does exactly that. The explicit
  # CC_BACKLOG_* exports are not redundant with it: they say WHICH state each test means, so a
  # default that later moves out from under $HOME cannot silently un-fixture this suite
  # (memory: unfixtured-sensor-executes-the-deployed-subject).
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # The S5 dispatch kick spawns a detached cc-dispatch on every successful `add`. Off here: this
  # suite's adds are fixtures, and a real kick would reach the operator's live autonomy state.
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  # The two titles are verbatim-shaped after the live ledger — the same condition, measured twice.
  T1="compact MEMORY.md (claude-infrastructure) — 20.5KB vs the 24.4KB read limit"
  T2="compact claude-infrastructure MEMORY.md: 22.5KB vs 24.4KB read limit"
}

# `! cmd` is exempt from errexit in bash, so a negative written that way only fails as the LAST line
# of a body. These return non-zero directly and so fail anywhere (the audit that found 4 vacuous
# assertions in tests/cc-backlog.bats).
refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

n_items() { bash "$CB" list --all --json | jq 'length'; }

@test "one condition, two measurements, two sessions ⇒ ONE item" {
  a=$(bash "$CB" add --project P --condition memory-index-over-budget --title "$T1" --source sess-A)
  b=$(bash "$CB" add --project P --condition memory-index-over-budget --title "$T2" --source sess-B)
  [ "$a" = "$b" ]
  [ "$(n_items)" -eq 1 ]
  [ "$(grep -c '"event":"add"' "$CC_BACKLOG_FILE")" -eq 1 ]
}

@test "CONTROL — the same two adds WITHOUT --condition still mint TWO items (the live defect)" {
  a=$(bash "$CB" add --project P --title "$T1" --source sess-A)
  b=$(bash "$CB" add --project P --title "$T2" --source sess-B)
  [ "$a" != "$b" ]
  [ "$(n_items)" -eq 2 ]
}

@test "the condition key ignores --source: same condition from two dispatchers ⇒ ONE item" {
  a=$(bash "$CB" add --project P --condition memory-index-over-budget --title "$T1" --source memory-index-hook)
  b=$(bash "$CB" add --project P --condition memory-index-over-budget --title "$T1" --source wt-6024bd009717)
  [ "$a" = "$b" ]
  [ "$(n_items)" -eq 1 ]
}

@test "CONTROL — without --condition, the source alone re-keys the SAME title into a second item" {
  a=$(bash "$CB" add --project P --title "$T1" --source memory-index-hook)
  b=$(bash "$CB" add --project P --title "$T1" --source wt-6024bd009717)
  [ "$a" != "$b" ]
  [ "$(n_items)" -eq 2 ]
}

@test "the condition key stays PROJECT-scoped — two projects over budget are two items" {
  # The live ledger held both: 15 claude-infrastructure items and 6 reso-management-app ones for
  # this same condition. Collapsing across projects would strand one project's work behind the
  # other's close, which is the opposite failure and just as silent.
  a=$(bash "$CB" add --project claude-infrastructure --condition memory-index-over-budget --title "$T1")
  b=$(bash "$CB" add --project reso-management-app   --condition memory-index-over-budget --title "$T1")
  [ "$a" != "$b" ]
  [ "$(n_items)" -eq 2 ]
}

@test "the measurement survives in the TITLE — it stops being identity, it is not discarded" {
  bash "$CB" add --project P --condition memory-index-over-budget --title "$T1" >/dev/null
  run bash "$CB" list --open
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "20.5KB"
}

@test "the condition is recorded and surfaced in --json (the fold WHITELISTS fields)" {
  id=$(bash "$CB" add --project P --condition memory-index-over-budget --title "$T1")
  run bash "$CB" list --open --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r --arg i "$id" '.[]|select(.id==$i)|.condition')" = "memory-index-over-budget" ]
}

@test "an ordinary event-keyed item OMITS condition rather than carrying an empty one" {
  id=$(bash "$CB" add --project P --title "$T1" --source s)
  run bash "$CB" list --open --json
  [ "$(printf '%s' "$output" | jq -r --arg i "$id" '.[]|select(.id==$i)|has("condition")')" = "false" ]
}

@test "a slug carrying a MEASUREMENT is refused (rc 2) and appends NOTHING" {
  run bash "$CB" add --project P --condition memory-index-over-budget-20.5KB --title "$T1"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q "NO DIGITS"
  [ ! -s "$CC_BACKLOG_FILE" ]
}

@test "the digit ban covers the whole class — a count, a percentage, a date and a sha all refuse" {
  # Written as a loop over the FAMILY, not four spellings of one: the guard is a grammar, and a
  # denylist of examples is what it deliberately is not (memory:
  # denylist-enumerates-spellings-not-the-class).
  for slug in index-over-101-entries index-over-80-percent index-over-2026-08-06 red-at-8035ea63; do
    run bash "$CB" add --project P --condition "$slug" --title "$T1"
    [ "$status" -eq 2 ]
  done
  [ ! -s "$CC_BACKLOG_FILE" ]
}

@test "a malformed slug REFUSES rather than degrading to a title key" {
  # The dangerous failure is a silent fallback: the caller asked not to have a per-event id, and a
  # fallback would hand it exactly that, in the retry loop that mints one item per pass.
  run bash "$CB" add --project P --condition "BAD Slug" --title "$T1"
  [ "$status" -eq 2 ]
  [ "$(n_items)" -eq 0 ]
  refute_match "$output" "^[0-9a-f]\{12\}$"
}

@test "shape rules: leading, trailing and doubled hyphens refuse; a plain slug is accepted" {
  for slug in -leading trailing- doub--led; do
    run bash "$CB" add --project P --condition "$slug" --title "$T1"
    [ "$status" -eq 2 ]
  done
  run bash "$CB" add --project P --condition memory-index-over-budget --title "$T1"
  [ "$status" -eq 0 ]
  [ "$(n_items)" -eq 1 ]
}

@test "a 65-char slug refuses and a 64-char slug is accepted (the bound, both sides)" {
  long65="$(printf 'a%.0s' $(seq 1 65))"
  long64="$(printf 'a%.0s' $(seq 1 64))"
  run bash "$CB" add --project P --condition "$long65" --title "$T1"
  [ "$status" -eq 2 ]
  run bash "$CB" add --project P --condition "$long64" --title "$T1"
  [ "$status" -eq 0 ]
}

@test "recurrence after done WARNS as a condition, refuses to reopen, and still echoes the id" {
  # 004502cf59ab closed 21:28:01Z; its twin was CLAIMED 21:34:01Z. With one key the second observation
  # can no longer mint a worker — but it must not silently auto-reopen either, or the six-minute
  # thrash returns wearing one id.
  id=$(bash "$CB" add --project P --condition memory-index-over-budget --title "$T1")
  bash "$CB" "done" "$id" --evidence sha1 >/dev/null   # quoted: bare `done` reads as a keyword (SC1010)
  # stderr is DISCARDED, not merged: bats folds stderr into $output, and the whole point here is
  # that STDOUT is still exactly the id — the contract cc-discover parses in a loop.
  run bash -c "bash '$CB' add --project P --condition memory-index-over-budget --title '$T2' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$output" = "$id" ]
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = "done" ]
  [ "$(n_items)" -eq 1 ]
}

@test "that recurrence warning names the CONDITION path, not 'use a distinct title'" {
  # Telling a condition-keyed caller to vary its title is advice to re-create the 21-item defect.
  id=$(bash "$CB" add --project P --condition memory-index-over-budget --title "$T1")
  bash "$CB" "done" "$id" --evidence sha1 >/dev/null   # quoted: bare `done` reads as a keyword (SC1010)
  run bash -c "bash '$CB' add --project P --condition memory-index-over-budget --title '$T2' 2>&1 >/dev/null"
  echo "$output" | grep -q "RECURRED"
  echo "$output" | grep -q -- "--force"
  refute_match "$output" "distinct title"
}

@test "CONTROL — an event-keyed re-file still gets the ORIGINAL 'distinct title/source' warning" {
  id=$(bash "$CB" add --project P --title "$T1" --source s)
  bash "$CB" "done" "$id" --evidence sha1 >/dev/null   # quoted: bare `done` reads as a keyword (SC1010)
  run bash -c "bash '$CB' add --project P --title '$T1' --source s 2>&1 >/dev/null"
  echo "$output" | grep -q "distinct title"
  refute_match "$output" "RECURRED"
}

@test "a plain add is byte-identical to pre-flag behaviour — the id still hashes title+source" {
  # The flag must be inert when absent. This pins the id ITSELF against the documented formula, so a
  # refactor that made every add condition-keyed could not pass by merely still deduping.
  want=$(printf '%s\037%s\037%s' P "$T1" s | shasum -a 256 | cut -c1-12)
  got=$(bash "$CB" add --project P --title "$T1" --source s)
  [ "$got" = "$want" ]
}

@test "the condition id is domain-separated from any event key that could spell it" {
  # THIS ADD USED TO COLLIDE. mk_cond_id's first cut put the literal `condition` in mk_id's third
  # slot — which is the free-form --source, so the tag was a string a caller can simply type, and
  # these two hashed identically. The separation is the FIELD COUNT (4 vs 3), not the tag.
  a=$(bash "$CB" add --project P --condition memory-index-over-budget --title "$T1")
  b=$(bash "$CB" add --project P --title memory-index-over-budget --source condition)
  [ "$a" != "$b" ]
  [ "$(n_items)" -eq 2 ]
  # …and the same probe from the other side: the tag itself must not be steerable either.
  c=$(bash "$CB" add --project cc-backlog --title condition-v1 --source P)
  [ "$c" != "$a" ]
}

@test "an unknown arg is still rejected — --condition did not open the parser up" {
  run bash "$CB" add --project P --title "$T1" --conditon memory-index-over-budget
  [ "$status" -eq 2 ]
  [ ! -s "$CC_BACKLOG_FILE" ]
}

@test "a condition item claims, blocks and folds like any other (no second item class)" {
  id=$(bash "$CB" add --project P --condition memory-index-over-budget --title "$T1")
  bash "$CB" claim "$id" --by sess-X >/dev/null
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = "claimed" ]
  bash "$CB" block "$id" --needs "operator must approve the lossy diffs" >/dev/null
  run bash "$CB" list --blocked --json
  [ "$(printf '%s' "$output" | jq -r --arg i "$id" '.[]|select(.id==$i)|.needs')" = "operator must approve the lossy diffs" ]
  # The condition survives the fold across transitions — it is carried, not just written once.
  [ "$(printf '%s' "$output" | jq -r --arg i "$id" '.[]|select(.id==$i)|.condition')" = "memory-index-over-budget" ]
}
