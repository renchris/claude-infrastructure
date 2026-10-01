#!/usr/bin/env bats
# ts7-peer-watch.sh — the watch that owns reso's TS 7 trigger (typescript-eslint admitting TS >= 7).
#
# The subject stays silent for months and then, once, says "the peer range admits 7". So the cases
# that matter are the PAGE case and the NON-VERDICT case, not the quiet "still capped" one that
# almost any wrong implementation also passes:
#
#   peer range admits 7.0.0                 → rc 0   PAGE
#   peer range still caps below 7           → rc 1   keep waiting
#   registry unreadable / range unparseable → rc 2   NON-VERDICT, never "still capped"
#
# Hermetic: every case reads a fixture through CC_TS7_PEER_JSON, except the unreachable-registry
# case, which points CC_TS7_REGISTRY_URL at a closed loopback port (no network leaves the box).
#
# RED-PROOF (R1): a mutant that drops the `||` alternative split must turn the disjunctive-range
# PAGE into "still capped", proving that assertion depends on the split and not on luck.

setup() {
  # The subject reads nothing under $HOME, but a fixtured HOME keeps it that way if it ever does.
  export HOME="${BATS_TEST_TMPDIR}/home"; mkdir -p "$HOME"
  SUBJECT="${BATS_TEST_DIRNAME}/../scripts/ts7-peer-watch.sh"
  FIX="${BATS_TEST_TMPDIR}/latest.json"
}

peer() { # <range> → writes a registry document carrying it
  printf '{"version":"9.9.9","peerDependencies":{"typescript":"%s"}}' "$1" > "$FIX"
}

@test "the 2026-09-30 range (>=4.8.4 <6.1.0) is still capped: rc 1" {
  peer '>=4.8.4 <6.1.0'
  CC_TS7_PEER_JSON="$FIX" run bash "$SUBJECT" --arm
  [ "$status" -eq 1 ]
}

@test "a spaced comparator (>= 4.8.4 < 6.1.0) is read the same way: rc 1" {
  peer '>= 4.8.4 < 6.1.0'
  CC_TS7_PEER_JSON="$FIX" run bash "$SUBJECT" --arm
  [ "$status" -eq 1 ]
}

@test "a range whose upper bound passes 7 PAGES: rc 0" {
  peer '>=4.8.4 <7.1.0'
  CC_TS7_PEER_JSON="$FIX" run bash "$SUBJECT" --arm
  [ "$status" -eq 0 ]
}

@test "a disjunctive range with a 7-admitting alternative PAGES: rc 0" {
  peer '^5 || >=7.0.0'
  CC_TS7_PEER_JSON="$FIX" run bash "$SUBJECT" --arm
  [ "$status" -eq 0 ]
}

@test "R1 red-proof: without the || split the disjunctive range no longer pages" {
  peer '^5 || >=7.0.0'
  mutant="${BATS_TEST_TMPDIR}/mutant.sh"
  sed 's/for alt in rng.split("||")/for alt in [rng]/' "$SUBJECT" > "$mutant"
  [ "$(grep -c 'for alt in \[rng\]' "$mutant")" -eq 1 ]
  bash -n "$mutant"
  CC_TS7_PEER_JSON="$FIX" run bash "$mutant" --arm
  [ "$status" -ne 0 ]
}

@test "a document with no typescript peer is a NON-VERDICT: rc 2" {
  printf '{"version":"9.9.9"}' > "$FIX"
  CC_TS7_PEER_JSON="$FIX" run bash "$SUBJECT" --arm
  [ "$status" -eq 2 ]
}

@test "an unparseable range is a NON-VERDICT, never 'still capped': rc 2" {
  peer 'garbage-range'
  CC_TS7_PEER_JSON="$FIX" run bash "$SUBJECT" --arm
  [ "$status" -eq 2 ]
}

@test "an unreachable registry is a NON-VERDICT: rc 2" {
  CC_TS7_REGISTRY_URL="http://127.0.0.1:9/typescript-eslint/latest" CC_TS7_FETCH_TIMEOUT_S=2 \
    run bash "$SUBJECT" --arm
  [ "$status" -eq 2 ]
}

@test "--report names the range when capped and the recipe when admitted" {
  peer '>=4.8.4 <6.1.0'
  CC_TS7_PEER_JSON="$FIX" run bash "$SUBJECT" --report
  [ "$status" -eq 1 ]
  [[ "$output" == *"still capped"*">=4.8.4 <6.1.0"* ]] || false
  peer '>=4.8.4 <8.0.0'
  CC_TS7_PEER_JSON="$FIX" run bash "$SUBJECT" --report
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADMITTED"* ]] || false
  [[ "$output" == *"@typescript/native"* ]] || false
}
