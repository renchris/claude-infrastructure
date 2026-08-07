#!/usr/bin/env bats
# thrash-block-recover.sh — the one-time repair of items reap's rule B blocked on a DISPATCHER
# SELF-RELEASE (see SELF-RELEASE in bin/cc-backlog and the script's own header).
#
# 🚨 THE HOLD ARM IS THE REASON THIS FILE EXISTS. Run against the live ledger the day it was written
# the script reported 233 RECOVER · 0 HOLD — every historical fast pair in the whole store was a
# self-release, so the arm that PROTECTS a genuinely-thrashing item never executed. A branch that
# ships without ever running is indistinguishable from a branch that does not work (memory:
# sensor-default-off-makes-blindness-the-shipping-path), and this one guards against handing a real
# thrash back to the dispatcher. Every RECOVER assertion below is therefore paired with a HOLD one
# built from the same fixture with a single field changed.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/scripts/thrash-block-recover.sh"
  CB="$REPO/bin/cc-backlog"
  # HOME is fixtured FIRST and unconditionally. Pinning CC_BACKLOG_FILE/IDL/BIN below covers the
  # seams this suite knows about, but the subject shells out to cc-backlog, which reads its own
  # $HOME-rooted paths (registry, roles, autonomy dirs) that no seam here names — so "I pinned the
  # ones I use" is precisely the reasoning that leaks. $HOME is the one lever that covers the seams
  # you have not enumerated.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_BIN="$CB"
  : > "$CC_BACKLOG_FILE"
}

rec() { printf '%s\n' "$1" >> "$CC_BACKLOG_FILE"; }
status_of() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.status'; }
BLOCKMSG='persistent thrash — 2 fast claim→reopen cycle(s) (spawn-fail / land-conflict rebase-exit-5); the worker cannot land.'

# A rule-B-blocked item. $1 = id, $2/$3 = the `by` on each of the two reopens ("" ⇒ omit the field).
seed_ruleb() {
  local id="$1" r1="$2" r2="$3"
  rec "$(jq -nc --arg i "$id" '{id:$i,ts:"2026-01-01T00:00:00Z",event:"add",project:"/r",title:"seeded"}')"
  rec "$(jq -nc --arg i "$id" '{id:$i,ts:"2026-01-01T00:00:10Z",event:"claim",by:"d-1"}')"
  rec "$(jq -nc --arg i "$id" --arg b "$r1" '{id:$i,ts:"2026-01-01T00:00:14Z",event:"reopen"} + (if $b!="" then {by:$b} else {} end)')"
  rec "$(jq -nc --arg i "$id" '{id:$i,ts:"2026-01-01T00:00:20Z",event:"claim",by:"d-2"}')"
  rec "$(jq -nc --arg i "$id" --arg b "$r2" '{id:$i,ts:"2026-01-01T00:00:24Z",event:"reopen"} + (if $b!="" then {by:$b} else {} end)')"
  rec "$(jq -nc --arg i "$id" --arg n "$BLOCKMSG" '{id:$i,ts:"2026-01-01T00:00:30Z",event:"block",by:"cc-backlog-reap",needs:$n}')"
}

@test "RECOVER: same-author pairs (the dispatcher self-releasing) → recovered, and --apply unblocks" {
  seed_ruleb sameauth0001 d-1 d-2          # each reopen names the identity that claimed
  [ "$(status_of sameauth0001)" = blocked ]
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sameauth0001"*"RECOVER"* ]] || false
  [[ "$output" == *"1 RECOVER · 0 HOLD"* ]] || false
  [ "$(status_of sameauth0001)" = blocked ]        # dry run wrote NOTHING
  run bash "$SUT" --apply
  [ "$status" -eq 0 ]
  [ "$(status_of sameauth0001)" = open ]
}

@test "HOLD: one worker-attributable reopen protects the item — the arm live data never exercises" {
  # IDENTICAL fixture to the RECOVER case except the second reopen names a DIFFERENT, non-empty
  # identity: a real actor closing somebody else's claim, which is the shape rule B exists to catch.
  seed_ruleb workerpair01 d-1 w-99
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workerpair01"*"HOLD"* ]] || false
  [[ "$output" == *"0 RECOVER · 1 HOLD"* ]] || false
  run bash "$SUT" --apply
  [ "$status" -eq 0 ]
  [ "$(status_of workerpair01)" = blocked ]        # --apply must NOT touch a HOLD
}

@test "RECOVER: an anonymous reopen counts as a self-release (the pre---by dispatcher)" {
  seed_ruleb anonymous001 '' ''
  run bash "$SUT"
  [[ "$output" == *"anonymous001"*"RECOVER"* ]] || false
}

@test "RECOVER: a flag-carrying reopen counts too — the (a) arm, once new records exist" {
  rec '{"id":"flagged00001","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"flagged"}'
  rec '{"id":"flagged00001","ts":"2026-01-01T00:00:10Z","event":"claim","by":"d-1"}'
  rec '{"id":"flagged00001","ts":"2026-01-01T00:00:14Z","event":"reopen","by":"d-1","selfRelease":true,"releaseReason":"spawn-fail"}'
  rec '{"id":"flagged00001","ts":"2026-01-01T00:00:20Z","event":"claim","by":"d-2"}'
  rec '{"id":"flagged00001","ts":"2026-01-01T00:00:24Z","event":"reopen","by":"d-2","selfRelease":true,"releaseReason":"compose-fail"}'
  rec "$(jq -nc --arg n "$BLOCKMSG" '{id:"flagged00001",ts:"2026-01-01T00:00:30Z",event:"block",by:"cc-backlog-reap",needs:$n}')"
  run bash "$SUT"
  [[ "$output" == *"flagged00001"*"RECOVER"* ]] || false
}

@test "out of reach: a HUMAN block, and a reap block that is NOT rule B, are both untouched" {
  # The filter is the LAST RECORD, not a text search — so neither of these is reachable however the
  # prose reads. A human block is the operator's decision; a wedged-worker block is a different reap
  # rule with its own evidence, and releasing it would fire a second peer at live work.
  seed_ruleb humanblock01 d-1 d-2
  rec '{"id":"humanblock01","ts":"2026-01-01T01:00:00Z","event":"block","needs":"MINT the token — needs a real TTY"}'
  seed_ruleb wedgedblk001 d-1 d-2
  rec '{"id":"wedgedblk001","ts":"2026-01-01T01:00:00Z","event":"block","by":"cc-backlog-reap","needs":"wedged live worker past the 21600s ceiling"}'
  run bash "$SUT" --apply
  [ "$status" -eq 0 ]
  [[ "$output" != *"humanblock01"* ]] || false
  [[ "$output" != *"wedgedblk001"* ]] || false
  [ "$(status_of humanblock01)" = blocked ]
  [ "$(status_of wedgedblk001)" = blocked ]
}

@test "out of reach: a DONE item is never resurrected, even with a rule-B block in its trail" {
  seed_ruleb donelater001 d-1 d-2
  rec '{"id":"donelater001","ts":"2026-01-01T01:00:00Z","event":"done","evidence":"abc1234"}'
  run bash "$SUT" --apply
  [ "$status" -eq 0 ]
  [[ "$output" != *"donelater001"* ]] || false
  [ "$(status_of donelater001)" = "done" ]
}

@test "--max REFUSES rather than truncating, and refuses before writing anything" {
  seed_ruleb maxbound0001 d-1 d-2
  seed_ruleb maxbound0002 d-1 d-2
  run bash "$SUT" --apply --max 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"REFUSED"* ]] || false
  # A partial release is the failure mode this bound exists to prevent: neither item may have moved.
  [ "$(status_of maxbound0001)" = blocked ]
  [ "$(status_of maxbound0002)" = blocked ]
  run bash "$SUT" --apply --max 2
  [ "$status" -eq 0 ]
  [ "$(status_of maxbound0001)" = open ]
  [ "$(status_of maxbound0002)" = open ]
}

@test "an empty / rule-B-free ledger exits 0 and says so — never a silent success" {
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"absent or empty"* ]] || false
  bash "$CB" add --project /r --title 'ordinary open item' >/dev/null
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no rule-B thrash blocks"* ]] || false
}
