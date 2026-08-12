#!/usr/bin/env bats
# cc-backlog `add` on a KNOWN id — THE UPDATE ARM (backlog ce1e9d1adab8 · W2).
#
# THE DEFECT THIS PINS. `cmd_add` resolves the id, hits `has_id`, echoes it and returns rc 0 having
# written nothing. That is the idempotency contract, and it also made a whole class of caller a
# permanent no-op: a generator that RE-FILES a condition-keyed row to refresh its wording is not
# adding an item, it is reporting a new measurement of a standing state — and the store kept the
# FIRST wording forever. `scripts/backlog-consolidation-trigger.sh --file` runs on every autonomy
# sweep for exactly that purpose ("repeated runs update rather than mint", its own header), and its
# row 5df742fb3894 sat frozen at its pre-R6 wording from 2026-08-11 while the sweep re-filed it every
# few minutes, each pass a silent rc-0 no-op.
#
# EVERY POSITIVE HERE IS PAIRED WITH THE NEGATIVE IT MUST NOT BREAK. The update arm sits inside the
# idempotency path, so the tests that matter most are the ones asserting what did NOT change: no new
# item, no re-open, no ledger growth on an unchanged re-file (memory:
# control-must-replay-the-real-artifact).

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  # Verbatim shapes from the live row this arm was built for: one condition, two measurements.
  T1="backlog consolidation: 3 cluster(s) at/above threshold 5 — 14 rows in the largest"
  T2="backlog consolidation: 1 cluster(s) at/above threshold 5 — 6 rows in the largest"
}

refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

fld() { bash "$CB" list --all --json | jq -r --arg i "$1" --arg f "$2" '.[]|select(.id==$i)|(.[$f] // "")'; }
n_items() { bash "$CB" list --all --json | jq 'length'; }
n_lines() { grep -c '' "$CC_BACKLOG_FILE"; }

@test "a condition-keyed re-file with a NEW title UPDATES the row (the frozen-row defect)" {
  a=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig)
  b=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T2" --source trig)
  [ "$a" = "$b" ]
  [ "$(n_items)" -eq 1 ]
  [ "$(fld "$a" title)" = "$T2" ]
}

@test "CONTROL — the row is still ONE item and still open; an update is not an add or a reopen" {
  a=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig)
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T2" --source trig
  [ "$(n_items)" -eq 1 ]
  [ "$(grep -c '"event":"add"' "$CC_BACKLOG_FILE")" -eq 1 ]
  [ "$(fld "$a" status)" = "open" ]
  refute_match "$(cat "$CC_BACKLOG_FILE")" '"event":"reopen"'
}

@test "CONTROL — an UNCHANGED re-file appends NOTHING (an idempotent caller cannot grow the ledger)" {
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig
  before=$(n_lines)
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig
  [ "$(n_lines)" -eq "$before" ]
}

@test "--dod-ref and --source update too, and the update record carries ONLY what changed" {
  a=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig --dod-ref old/path.md)
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig --dod-ref "origin/main:docs/plans/NEW.md"
  [ "$(fld "$a" dodRef)" = "origin/main:docs/plans/NEW.md" ]
  [ "$(fld "$a" title)" = "$T1" ]
  # The appended record must not carry the unchanged title — a whole-row rewrite would make every
  # re-file a diff against itself and defeat the unchanged-is-silent rule above.
  upd="$(grep '"event":"update"' "$CC_BACKLOG_FILE" | tail -1)"
  [ "$(printf '%s' "$upd" | jq -r 'has("dodRef")')" = "true" ]
  [ "$(printf '%s' "$upd" | jq -r 'has("title")')" = "false" ]
}

@test "a DONE row is never re-worded — its title is what its evidence refers to" {
  a=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig)
  bash "$CB" "done" "$a" --evidence "landed abc1234"
  # stdout ONLY. The done-guard writes a multi-line WARNING to stderr, and bats' `run` folds the two
  # streams together — so comparing $output against the id fails on the warning, not on the contract.
  echoed="$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T2" --source trig 2>/dev/null)"
  [ "$echoed" = "$a" ]                     # idempotency contract survives
  [ "$(fld "$a" title)" = "$T1" ]          # …and the history is intact
  [ "$(fld "$a" status)" = "done" ]
  refute_match "$(cat "$CC_BACKLOG_FILE")" '"event":"update"'
}

@test "--falsifier on a known id stays a NO-OP: only \`falsify\` may store a probe (it runs it first)" {
  a=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig)
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig --falsifier "true"
  [ -z "$(fld "$a" falsifier)" ]
  refute_match "$(cat "$CC_BACKLOG_FILE")" '"event":"update"'
}

@test "the update event lands in the CARRY-FORWARD arm of the status fold, not in a default" {
  a=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig)
  bash "$CB" block "$a" --needs "waiting on a decision"
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T2" --source trig
  # An `update` carries NO status field, so a blocked row must still read blocked afterwards. A new
  # event member that reset status (or landed in a fail-closed default) is this repo's recurring
  # defect (memory: new-enum-member-falls-into-fail-closed-default).
  [ "$(fld "$a" status)" = "blocked" ]
  [ "$(fld "$a" title)" = "$T2" ]
  [ "$(fld "$a" needs)" = "waiting on a decision" ]
}

@test "the trigger's own --file path can now move its row's wording (the live caller)" {
  # THE REAL ARTIFACT, not a paraphrase: the escalation row is minted by
  # backlog-consolidation-trigger.sh --file, which is why the freeze mattered. Two --file runs over
  # two different stores must leave the row wearing the SECOND measurement.
  trig="$REPO/scripts/backlog-consolidation-trigger.sh"
  seed() { # <n-rows> — one cluster whose size decides the escalated wording
    : > "$CC_BACKLOG_FILE"
    for i in $(seq 1 "$1"); do
      bash "$CB" add --project P --title "autonomy sweep suite FAILED at sha deadbee$i (run $i)" --source postland >/dev/null
    done
  }
  seed 7
  run bash "$trig" --file --threshold 5
  [ "$status" -eq 0 ]
  id="$(bash "$CB" list --all --json | jq -r '.[]|select(.condition!=null and (.condition|startswith("backlog-duplicate")))|.id' | head -1)"
  [ -n "$id" ]
  first="$(fld "$id" title)"
  # A second, LARGER cluster in the same store must re-word the same row rather than mint a sibling.
  bash "$CB" add --project P --title "autonomy sweep suite FAILED at sha deadbee8 (run 8)" --source postland >/dev/null
  bash "$CB" add --project P --title "autonomy sweep suite FAILED at sha deadbee9 (run 9)" --source postland >/dev/null
  run bash "$trig" --file --threshold 5
  [ "$status" -eq 0 ]
  second="$(fld "$id" title)"
  [ "$first" != "$second" ]
  [ "$(bash "$CB" list --all --json | jq '[.[]|select(.condition!=null and (.condition|startswith("backlog-duplicate")))]|length')" -eq 1 ]
}
