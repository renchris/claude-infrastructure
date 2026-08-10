#!/usr/bin/env bats
# backlog-consolidation-trigger: notice the duplicate-cluster shape before a human has to.
#
# THE POSITIVE CONTROL LIVES HERE, DELIBERATELY. Measured on the live store 2026-08-10 (after the
# 161-item prune) there is not a single cluster at threshold 2 — the shape is real but currently
# absent. A detector verified only against that store would be indistinguishable from a broken one
# returning empty, which is the "a null from a blind instrument is not absence" failure. So the
# fixture below MANUFACTURES the exact shape that occurred: N rows differing only by an embedded sha.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/scripts/backlog-consolidation-trigger.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  : > "$CC_BACKLOG_FILE"
}

# row <id> <title> [event]
row() {
  printf '{"id":"%s","ts":"2026-08-01T00:00:00Z","event":"%s","project":"p","title":"%s"}\n' \
    "$1" "${3:-add}" "$2" >> "$CC_BACKLOG_FILE"
}

# The real shape: post-land RED for ONE suite, one row per culprit sha.
seed_sha_cluster() {
  local n="$1" i sha
  for i in $(seq 1 "$n"); do
    sha="$(printf 'deadbee%04d' "$i")"
    row "id$i$(printf '%08d' "$i")" "post-land RED: tests/deploy-parity.bats @ $sha"
  done
}

@test "POSITIVE CONTROL: N rows differing only by an embedded sha are ONE cluster" {
  seed_sha_cluster 6
  run "$SUT" --threshold 5
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "1 cluster"
  printf '%s' "$output" | grep -q "6x"
}

@test "below the threshold it is SILENT — an alarm that always fires carries no bits" {
  seed_sha_cluster 3
  run "$SUT" --threshold 5
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "no cluster at/above 5"
}

@test "genuinely distinct items are NOT collapsed" {
  row a1aaaaaaaaaa "fix the wake path so a session is not deaf by default"
  row b2bbbbbbbbbb "the memory index is over its loader cap and truncates silently"
  row c3cccccccccc "worktree population is over its janitor ceiling"
  row d4dddddddddd "deploy-live refuses because no green stamp is in the scan window"
  row e5eeeeeeeeee "cc-premise cannot re-run a falsifier at claim time"
  run "$SUT" --threshold 2
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "no cluster at/above 2"
}

@test "CLOSED rows leave the population — consolidating a cluster silences the trigger" {
  seed_sha_cluster 6
  run "$SUT" --threshold 5
  printf '%s' "$output" | grep -q "6x"
  # close five of the six, as a consolidation would. The event argument is QUOTED: a bare `done`
  # here is ambiguous with the loop keyword (SC1010) and reads as a terminator to a human too.
  for i in 1 2 3 4 5; do row "id$i$(printf '%08d' "$i")" "" "done"; done
  run "$SUT" --threshold 5
  printf '%s' "$output" | grep -q "no cluster at/above 5"
}

@test "--assert exits 1 when a cluster crosses, 0 when none does" {
  seed_sha_cluster 6
  run "$SUT" --assert --threshold 5
  [ "$status" -eq 1 ]
  : > "$CC_BACKLOG_FILE"
  seed_sha_cluster 2
  run "$SUT" --assert --threshold 5
  [ "$status" -eq 0 ]
}

@test "an empty store is a no-op, never a crash" {
  run "$SUT" --assert
  [ "$status" -eq 0 ]
}

@test "an unknown argument is refused rather than silently ignored" {
  run "$SUT" --nonsense
  [ "$status" -eq 2 ]
}
