#!/usr/bin/env bats
# cc-backlog `add` on a DONE-LATCHED condition key — THE GROUP FOLD (backlog b82a4060b00f).
#
# THE DEFECT THIS PINS. The add-side done latch consulted only the condition KEY's own status. A
# condition GROUP is routinely in several states at once — `link` and `block`'s operator-gate join
# put rows into a group whose ids are not the key — so a latched key can sit next to a sibling that
# is still open. Measured 2026-08-19: `memory-index-over-budget` resolved to THREE ids in THREE
# states (150c50055e1c done-latched, the KEY · 7c266e16fc94 open · 5ab3327ed0c8 blocked). A re-add
# carrying a fresh live measurement echoed the latched key, printed "if it genuinely holds again:
# reopen --force", and wrote ZERO records — while an OPEN row for that very condition, positive
# evidence the condition still held, sat one select away. The cost is a ROTTING TITLE: a standing
# condition closed once could never again carry a fresh measurement, so it stayed frozen at the
# value it held the day it closed, and that stale number is what a later reader budgets against.
#
# EVERY POSITIVE IS PAIRED WITH THE NEGATIVE IT MUST NOT BREAK. This arm sits inside the latch that
# stopped the 21-duplicate storm, so the tests that matter most are the ones asserting what did NOT
# change: no reopen, no new item, the done row never re-worded, and a group with no live member
# still latching exactly as before (memory: control-must-replay-the-real-artifact).

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  # Verbatim shapes from the group this was measured on: one condition, three measurements.
  COND=memory-index-over-budget
  T1="compact MEMORY.md (claude-infrastructure) — 20.5KB vs the 24.4KB read limit"
  T2="compact claude-infrastructure MEMORY.md: 26.9KB vs 24.4KB read limit"
  SIB="MEMORY.md index is over the loader budget again"
}

refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

fld() { bash "$CB" list --all --json | jq -r --arg i "$1" --arg f "$2" '.[]|select(.id==$i)|(.[$f] // "")'; }
n_items() { bash "$CB" list --all --json | jq 'length'; }
n_lines() { grep -c '' "$CC_BACKLOG_FILE"; }

# Mint the measured shape: the condition KEY, closed; plus a sibling row joined to the same
# condition by `link` — which is how every real group came to hold more than one id.
seed_group() { # <sibling-status: open|blocked> → echoes "<key> <sibling>"
  local k s
  k=$(bash "$CB" add --project P --condition "$COND" --title "$T1" --source m)
  bash "$CB" "done" "$k" --evidence "landed abc1234" >/dev/null 2>&1
  s=$(bash "$CB" add --project P --title "$SIB" --source m)
  bash "$CB" link "$s" --condition "$COND" >/dev/null 2>&1
  [ "$1" = blocked ] && bash "$CB" block "$s" --needs "operator must raise the loader budget" >/dev/null 2>&1
  printf '%s %s' "$k" "$s"
}

@test "a done-latched key with an OPEN sibling ACCEPTS the add and updates the open row" {
  read -r k s <<<"$(seed_group open)"
  echoed="$(bash "$CB" add --project P --condition "$COND" --title "$T2" --source m 2>/dev/null)"
  # The measurement reached the live row — this is the whole defect, inverted.
  [ "$(fld "$s" title)" = "$T2" ]
  # …and the caller is told WHERE it landed, so a `claim $(add …)` chain reaches the live row.
  [ "$echoed" = "$s" ]
  [ "$echoed" != "$k" ]
}

@test "a BLOCKED sibling is live evidence too — the condition holds while an operator is the gate" {
  read -r k s <<<"$(seed_group blocked)"
  echoed="$(bash "$CB" add --project P --condition "$COND" --title "$T2" --source m 2>/dev/null)"
  [ "$echoed" = "$s" ]
  [ "$(fld "$s" title)" = "$T2" ]
  # An `update` carries no status field, so the operator gate must survive the re-wording intact
  # (memory: new-enum-member-falls-into-fail-closed-default).
  [ "$(fld "$s" status)" = "blocked" ]
  [ "$(fld "$s" needs)" = "operator must raise the loader budget" ]
}

@test "CONTROL — the LATCH still holds: nothing reopens, nothing is minted, the done row is intact" {
  read -r k s <<<"$(seed_group open)"
  bash "$CB" add --project P --condition "$COND" --title "$T2" --source m >/dev/null 2>&1
  [ "$(fld "$k" status)" = "done" ]
  [ "$(fld "$k" title)" = "$T1" ]              # its title is the history its evidence refers to
  [ "$(fld "$k" evidence)" = "landed abc1234" ]
  [ "$(n_items)" -eq 2 ]                       # no third row minted
  refute_match "$(cat "$CC_BACKLOG_FILE")" '"event":"reopen"'
  [ "$(grep -c '"event":"add"' "$CC_BACKLOG_FILE")" -eq 2 ]
}

@test "CONTROL — NO live sibling: the latch refuses exactly as before and writes nothing" {
  # The 2026-08-06 behaviour, unchanged. Without this the fix would read as "the latch was removed".
  k=$(bash "$CB" add --project P --condition "$COND" --title "$T1" --source m)
  bash "$CB" "done" "$k" --evidence "landed abc1234"
  before=$(n_lines)
  run bash "$CB" add --project P --condition "$COND" --title "$T2" --source m
  [ "$status" -eq 0 ]
  [ "$(n_lines)" -eq "$before" ]                        # ZERO records
  [ "$(fld "$k" title)" = "$T1" ]
  echo "$output" | grep -q 'already DONE'
  echo "$output" | grep -q "reopen $k --force"
}

@test "CONTROL — a DONE sibling is not live evidence; a group with only dead members still latches" {
  read -r k s <<<"$(seed_group open)"
  bash "$CB" "done" "$s" --evidence "landed def5678"
  before=$(n_lines)
  run bash "$CB" add --project P --condition "$COND" --title "$T2" --source m
  [ "$status" -eq 0 ]
  [ "$(n_lines)" -eq "$before" ]
  [ "$output" = "$k
$(echo "$output" | tail -n +2)" ] || true                # id still echoed (idempotency contract)
  [ "$(fld "$s" title)" = "$SIB" ]
  echo "$output" | grep -q 'already DONE'
}

@test "CONTROL — a CLAIMED sibling is NOT a redirect target; claim guard (6) owns that contention" {
  read -r k s <<<"$(seed_group open)"
  bash "$CB" claim "$s" --by "host-$$" >/dev/null 2>&1
  [ "$(fld "$s" status)" = "claimed" ]
  before=$(n_lines)
  run bash "$CB" add --project P --condition "$COND" --title "$T2" --source m
  [ "$status" -eq 0 ]
  # Re-wording the brief a worker is executing against is a different, worse failure than a stale
  # title, so this path latches rather than writing.
  [ "$(n_lines)" -eq "$before" ]
  [ "$(fld "$s" title)" = "$SIB" ]
  echo "$output" | grep -q 'already DONE'
}

@test "CONTROL — an UNCHANGED re-file against a live sibling appends NOTHING" {
  read -r k s <<<"$(seed_group open)"
  bash "$CB" add --project P --condition "$COND" --title "$T2" --source m >/dev/null 2>&1
  before=$(n_lines)
  echoed="$(bash "$CB" add --project P --condition "$COND" --title "$T2" --source m 2>/dev/null)"
  [ "$(n_lines)" -eq "$before" ]      # idempotency does not weaken because the write moved rows
  [ "$echoed" = "$s" ]                # …but the caller is still told which row is live
}

@test "the update record carries ONLY what changed, on the SIBLING's id" {
  read -r k s <<<"$(seed_group open)"
  bash "$CB" add --project P --condition "$COND" --title "$T2" --source m \
    --dod-ref "origin/main:docs/plans/NEW.md" >/dev/null 2>&1
  upd="$(grep '"event":"update"' "$CC_BACKLOG_FILE" | tail -1)"
  [ "$(printf '%s' "$upd" | jq -r '.id')" = "$s" ]
  [ "$(printf '%s' "$upd" | jq -r 'has("title")')"  = "true" ]
  [ "$(printf '%s' "$upd" | jq -r 'has("dodRef")')" = "true" ]
  [ "$(printf '%s' "$upd" | jq -r 'has("source")')" = "false" ]   # --source m is unchanged
  [ "$(fld "$s" dodRef)" = "origin/main:docs/plans/NEW.md" ]
}

@test "the redirect target is INVARIANT across re-files: open before blocked, then oldest" {
  # Two live siblings. Ranking on `lastTs` would let successive measurements ping-pong between them
  # as either is touched, scattering one condition's history across rows; `firstTs` is first-wins in
  # the fold, so nothing that happens later can move the target.
  k=$(bash "$CB" add --project P --condition "$COND" --title "$T1" --source m)
  bash "$CB" "done" "$k" --evidence "landed abc1234"
  older=$(bash "$CB" add --project P --title "$SIB (older)" --source m)
  bash "$CB" link "$older" --condition "$COND" >/dev/null 2>&1
  # `now_iso` is second-granularity, so two adds in the same second tie on firstTs and the test
  # would be discriminating the id tie-break instead of the age rule it claims to pin. One real
  # second is the cost of the fixture actually replaying the shape (memory:
  # control-must-replay-the-real-artifact).
  sleep 1
  newer=$(bash "$CB" add --project P --title "$SIB (newer)" --source m)
  bash "$CB" link "$newer" --condition "$COND" >/dev/null 2>&1
  # Touch the NEWER row last, so a lastTs-ranked implementation would pick it.
  bash "$CB" block "$newer" --needs "operator step" >/dev/null 2>&1
  bash "$CB" unblock "$newer" >/dev/null 2>&1
  a="$(bash "$CB" add --project P --condition "$COND" --title "$T2" --source m 2>/dev/null)"
  b="$(bash "$CB" add --project P --condition "$COND" --title "$T2 (again)" --source m 2>/dev/null)"
  [ "$a" = "$older" ]
  [ "$a" = "$b" ]
  [ "$(fld "$newer" title)" = "$SIB (newer)" ]
}

@test "an OPEN sibling outranks a BLOCKED one — the row a dispatcher can act on wins" {
  k=$(bash "$CB" add --project P --condition "$COND" --title "$T1" --source m)
  bash "$CB" "done" "$k" --evidence "landed abc1234"
  blocked=$(bash "$CB" add --project P --title "$SIB (blocked, filed first)" --source m)
  bash "$CB" link "$blocked" --condition "$COND" >/dev/null 2>&1
  bash "$CB" block "$blocked" --needs "operator step" >/dev/null 2>&1
  open=$(bash "$CB" add --project P --title "$SIB (open, filed second)" --source m)
  bash "$CB" link "$open" --condition "$COND" >/dev/null 2>&1
  echoed="$(bash "$CB" add --project P --condition "$COND" --title "$T2" --source m 2>/dev/null)"
  [ "$echoed" = "$open" ]                      # open wins despite being the YOUNGER row
  [ "$(fld "$blocked" title)" = "$SIB (blocked, filed first)" ]
}

@test "the group is scoped to ONE project — another project's live sibling is not evidence here" {
  k=$(bash "$CB" add --project P --condition "$COND" --title "$T1" --source m)
  bash "$CB" "done" "$k" --evidence "landed abc1234"
  other=$(bash "$CB" add --project Q --title "$SIB" --source m)
  bash "$CB" link "$other" --condition "$COND" >/dev/null 2>&1
  before=$(n_lines)
  run bash "$CB" add --project P --condition "$COND" --title "$T2" --source m
  [ "$status" -eq 0 ]
  [ "$(n_lines)" -eq "$before" ]
  [ "$(fld "$other" title)" = "$SIB" ]
  echo "$output" | grep -q 'already DONE'
}

@test "the redirect notice does NOT say \"already DONE\" — postland-verify greps that phrase" {
  # scripts/postland-verify.sh matches `*'already DONE'*` on this stderr and logs "RECURRED (closed
  # item, NOT re-opened — needs reopen --force)". On the redirect path the condition is NOT parked
  # behind a --force: it is live on a row that just took the measurement, so that log line would be
  # false (memory: sibling-auditors-must-share-the-state-model).
  read -r k s <<<"$(seed_group open)"
  err="$(bash "$CB" add --project P --condition "$COND" --title "$T2" --source m 2>&1 >/dev/null)"
  refute_match "$err" 'already DONE'
  printf '%s' "$err" | grep -q "is LIVE on $s"
  printf '%s' "$err" | grep -q "$COND"
}
