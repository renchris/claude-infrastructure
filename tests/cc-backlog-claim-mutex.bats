#!/usr/bin/env bats
# cc-backlog claim: ONE grant per item, even when two claims land in the same second (5207d553dce2).
#
# THE DEFECT. The lease guard is healthy on the slow path — a claimer arriving minutes after a live
# incumbent is correctly refused rc 4 — but it is NOT ATOMIC: cmd_transition folds the trail to read
# the incumbent and then appends the claim, and those are two steps. Measured 2026-08-07 on item
# 149789b69fc4: pids 67287 and 82639 both emitted a claim record at 22:57:45Z, both stayed live, both
# wrote the same shared worktree, and the fold names only the last — so the displaced worker received
# no refusal and had no way to learn it had lost.
#
# WHY THE RED-PROOF IS THE HELD LOCK AND NOT A RACE. Racing two real claims reproduces the bug only
# when the interleaving lands inside a sub-second window, so a race test is probabilistic and cannot
# be the thing that goes red. Test 1 asserts the PROPERTY the fix installs — a claim that cannot take
# the item's mutex refuses and appends nothing — which is deterministic and is exactly what no
# pre-fix build can do: with no mutex, holding the lock dir is inert and the claim is granted.
# Tests 2-4 are the false-positive controls in the other direction: an uncontended claim must still
# be granted, a DEAD holder must never wedge an item, and the mutex must be PER ITEM.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  # $HOME is fixtured even though CC_BACKLOG_FILE redirects the ledger: cc-backlog resolves other
  # paths under $HOME, and the hermeticity ratchet's unit is the FILE, not the individual read.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_CLAIM_LOCK_DIR="$BATS_TEST_TMPDIR/claim.lock.d"
  export CC_BACKLOG_CLAIM_LOCK_WAIT_S=0     # no wait: contention is decided, not slept on
  export CC_BACKLOG_KICK=off
  HOLDER=""
}

teardown() { [ -n "$HOLDER" ] && { kill "$HOLDER" 2>/dev/null || true; }; return 0; }

mkitem() { "$CB" add --project p --title "$1" --source t 2>/dev/null | tail -1; }
claims() { grep -c '"event":"claim"' "$CC_BACKLOG_FILE" 2>/dev/null || true; }

# hold <id> with a LIVE owner pid, the way a peer mid-claim holds it
hold_live() {
  local ld="$CC_BACKLOG_CLAIM_LOCK_DIR/$1"
  mkdir -p "$ld"
  sleep 60 & HOLDER=$!
  printf '%s\n' "$HOLDER" > "$ld/owner"
}

@test "1: a claim whose item is inside ANOTHER process's claim is REFUSED and appends nothing" {
  id="$(mkitem raced)"
  [ -n "$id" ]
  before="$(claims)"
  hold_live "$id"

  run "$CB" claim "$id" --by "$(hostname -s)-$$" --venue local
  [ "$status" -eq 4 ]
  [[ "$output" == *"verdict=claim-contended"* ]] || false
  # LINE 1, because cc-dispatch only ever sees this refusal through a head-biased excerpt.
  [[ "$(printf '%s\n' "$output" | head -1)" == *"verdict=claim-contended"* ]] || false
  # and the abstention is real: no record was appended, so the item is untouched.
  [ "$(claims)" = "$before" ]
  run "$CB" list --all --json
  [[ "$(printf '%s' "$output" | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = "open" ]]
}

@test "2: control — an UNCONTENDED claim is still granted, and the mutex is released after it" {
  id="$(mkitem plain)"
  run "$CB" claim "$id" --by "$(hostname -s)-$$" --venue local
  [ "$status" -eq 0 ]
  [ ! -d "$CC_BACKLOG_CLAIM_LOCK_DIR/$id" ]
  run "$CB" list --all --json
  [[ "$(printf '%s' "$output" | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = "claimed" ]]
}

@test "3: a mutex held by a DEAD owner is reclaimed, so a crashed claimer never wedges an item" {
  id="$(mkitem crashed)"
  ld="$CC_BACKLOG_CLAIM_LOCK_DIR/$id"; mkdir -p "$ld"
  # `wait` on a killed child returns 143, which bats' `set -e` would read as the TEST failing —
  # the reap is the fixture, not the assertion.
  sleep 60 & dead=$!; kill "$dead" 2>/dev/null || true; wait "$dead" 2>/dev/null || true
  printf '%s\n' "$dead" > "$ld/owner"
  run "$CB" claim "$id" --by "$(hostname -s)-$$" --venue local
  [ "$status" -eq 0 ]
  [[ "$output" != *"claim-contended"* ]]
}

@test "4: the mutex is PER ITEM — a lock on one id does not refuse a claim on another" {
  a="$(mkitem itema)"; b="$(mkitem itemb)"
  hold_live "$a"
  run "$CB" claim "$b" --by "$(hostname -s)-$$" --venue local
  [ "$status" -eq 0 ]
  [[ "$output" != *"claim-contended"* ]]
}
