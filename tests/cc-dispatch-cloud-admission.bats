#!/usr/bin/env bats
# THE CLOUD ADMISSION GATE — the arm that stops the off-box lane refilling faster than it drains.
#
# WHY IT EXISTS. Measured 2026-09-04 (docs/research/backlog-zero-2026-09-04/cloud-lane.md): 29.9
# cloud sessions fired/day against 1.3 branches returned/day, a pending pile of 543 growing
# +23.5/day, and 17 backlog ids owning 379 of 665 declarations — one id fired 37 times, another
# carrying 24 declarations while being closed twice. `git log -S pending_unlanded` and
# `-S CC_DISPATCH_CLOUD_PENDING_MAX` both returned nothing: no admission gate existed at all, and
# the dispatcher never read the decl store's `item=` link although it is the dispatcher that writes
# it.
#
# TWO GATES OVER ONE WALK, and the tests below keep them apart because they measure different
# things: ALREADY-DECLARED de-duplicates per item, THE PILE CAP refuses the lane. De-duplication
# alone does not change the arithmetic — 500 distinct items each add a row to a queue returning
# 1.3/day.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/bin/cc-dispatch"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_DISPATCH_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_DISPATCH_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export CC_DISPATCH_PROJECT="p"
  export CC_DISPATCH_CLOUD_DECL_DIR="$BATS_TEST_TMPDIR/cloud"
  mkdir -p "$CC_DISPATCH_CLOUD_DECL_DIR"
  : > "$CC_BACKLOG_FILE"; : > "$CC_DISPATCH_IDL"
}

# row <id> <venuePlan|-> — an open, dispatchable item in project p
row() {
  local vp=""
  [ "${2:--}" != "-" ] && vp=", \"venuePlan\":\"$2\""
  printf '{"id":"%s","ts":"2026-08-01T00:00:00Z","event":"add","project":"p","title":"t %s"%s}\n' \
    "$1" "$1" "$vp" >> "$CC_BACKLOG_FILE"
}

# decl <session> <item|-> — a declaration in the store, in the real shape bin/cc-cloud writes
decl() {
  local it=""
  [ "${2:--}" != "-" ] && it="$2"
  printf 'id=%s\nbranch=claude/fire-%s\nremote=origin\npaths=\nitem=%s\ndeclared_at=1788000000\n' \
    "$1" "$1" "$it" > "$CC_DISPATCH_CLOUD_DECL_DIR/$1.decl"
}

@test "NEITHER gate binds: an empty store fires the cloud queue exactly as before" {
  # The incumbent path, and the denominator for everything below. Without it a gate that refused
  # EVERYTHING would satisfy every other arm in this file (memory: positive-control-the-denominator).
  row aaaa cloud; row bbbb cloud
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  ! grep -q 'already-declared' "$CC_DISPATCH_IDL" || false
  ! grep -q 'cloud-pending-cap' "$CC_DISPATCH_IDL" || false
  [ "$(jq -r 'select(.verdict=="admit")|.id' "$CC_DISPATCH_IDL" | sort | tr '\n' ' ')" = "aaaa bbbb " ]
}

@test "A PENDING DECLARATION holds its item — the second fire is skipped, naming the session" {
  row aaaa cloud; row bbbb cloud
  decl session_HOLD aaaa
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  # the SESSION is named, not merely the fact: a skip that does not say which session owes the
  # result is a dead end for whoever reads it.
  grep -q 'aaaa: already-declared session_HOLD' "$CC_DISPATCH_IDL"
  # …and the item that has no declaration is untouched.
  [ "$(jq -r 'select(.verdict=="admit")|.id' "$CC_DISPATCH_IDL" | sort | tr '\n' ' ')" = "bbbb " ]
}

@test "the count is journalled beside the per-item rows, with the pile it was measured against" {
  row aaaa cloud; row bbbb cloud
  decl session_1 aaaa
  decl session_2 bbbb
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  grep -q 'cloud-already-declared: 2 of 2 cloud item(s)' "$CC_DISPATCH_IDL"
  grep -q 'pending_unlanded=2 of 50' "$CC_DISPATCH_IDL"
}

@test "THE PILE CAP refuses ALL cloud fires and PRINTS the count" {
  row aaaa cloud; row bbbb cloud
  local i
  for i in 1 2 3; do decl "session_$i" "other$i"; done
  run env CC_DISPATCH_VENUE_ONLY=cloud CC_DISPATCH_CLOUD_PENDING_MAX=2 "$SUT" --decide
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'refusing ALL cloud fires'
  printf '%s' "$output" | grep -q '3 unlanded cloud declaration(s) against a cap of 2'
  # EVERY cloud item is refused, including the ones with no declaration of their own: the cap is a
  # statement about the LANE, not about an item.
  grep -q 'aaaa: cloud-pending-cap' "$CC_DISPATCH_IDL"
  grep -q 'bbbb: cloud-pending-cap' "$CC_DISPATCH_IDL"
  ! grep -q '"verdict":"admit"' "$CC_DISPATCH_IDL" || false
}

@test "the cap is LANE-WIDE and touches nothing else — local dispatch is unaffected" {
  # The whole point of pausing this lane is that the other one closes 65 rows to cloud's 3. A cap
  # that also stopped local work would be a total outage wearing a throttle's clothes.
  row aaaa cloud; row bbbb local
  decl session_1 other1
  decl session_2 other2
  run env CC_DISPATCH_CLOUD_PENDING_MAX=1 "$SUT" --decide
  [ "$status" -eq 0 ]
  grep -q 'aaaa: cloud-pending-cap' "$CC_DISPATCH_IDL"
  [ "$(jq -r 'select(.verdict=="admit")|.id' "$CC_DISPATCH_IDL" | sort | tr '\n' ' ')" = "bbbb " ]
}

@test "a RETURNED declaration no longer holds its item — the store is what clears the gate" {
  # There is no TTL and no sweeper here on purpose. A gate that expired on a clock rather than on
  # the store would be a fourth immortal label (memory: filed-blocker-is-never-revalidated).
  row aaaa cloud
  decl session_DONE aaaa
  : > "$CC_DISPATCH_CLOUD_DECL_DIR/session_DONE.returned"
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  ! grep -q 'already-declared' "$CC_DISPATCH_IDL" || false
  grep -q '"id":"aaaa","verdict":"admit"' "$CC_DISPATCH_IDL"
}

@test "a RETIRED declaration no longer holds its item — this is what the retire pass buys" {
  row aaaa cloud
  decl session_OLD aaaa
  : > "$CC_DISPATCH_CLOUD_DECL_DIR/session_OLD.retired"
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  ! grep -q 'already-declared' "$CC_DISPATCH_IDL" || false
  grep -q '"id":"aaaa","verdict":"admit"' "$CC_DISPATCH_IDL"
}

@test "a declaration carrying NO item still counts against the pile — the widest reading, on purpose" {
  # A declaration this dispatcher cannot attribute is still a result the lane owes. Counting it
  # AGAINST firing means a store it cannot understand throttles the lane rather than opening it.
  row aaaa cloud
  decl session_ANON -
  decl session_ANON2 -
  run env CC_DISPATCH_VENUE_ONLY=cloud CC_DISPATCH_CLOUD_PENDING_MAX=1 "$SUT" --decide
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '2 unlanded cloud declaration(s) against a cap of 1'
}

@test "an ABSENT declaration store is not a cleared gate for the cap, and not a held one either" {
  # 'The store does not exist' is 'nothing has been declared', which is a real zero — every fire
  # this dispatcher makes writes one. It must not read as a full pile (a permanent outage on a
  # fresh box) and it must not error.
  rm -rf "$CC_DISPATCH_CLOUD_DECL_DIR"
  row aaaa cloud
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  ! grep -q 'cloud-pending-cap' "$CC_DISPATCH_IDL" || false
  grep -q '"id":"aaaa","verdict":"admit"' "$CC_DISPATCH_IDL"
}

@test "CC_DISPATCH_CLOUD_PENDING_MAX must be a non-negative integer" {
  row aaaa cloud
  run env CC_DISPATCH_CLOUD_PENDING_MAX=lots "$SUT" --decide
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q 'CC_DISPATCH_CLOUD_PENDING_MAX'
}
