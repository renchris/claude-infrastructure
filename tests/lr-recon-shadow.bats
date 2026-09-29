#!/usr/bin/env bats
# tests/rig/shadow_lib.py — the W5b shadow gate (plan § W5 "Shadow"): the observe-mode reconciler's
# plan for a limit cohort against what the legacy hook lane did. One fixture cohort, one case per gate
# arm, each red when its arm is broken.
#
# HERMETIC: HOME and the limit-recover tree live in BATS_TEST_TMPDIR; nothing live is read.

SIDA="aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"
SIDB="bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"
SIDC="cccccccc-3333-4333-8333-cccccccccccc"
CID="next2-5h-1790663400"

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  L="$REPO/tests/rig/shadow_lib.py"
  export HOME="$BATS_TEST_TMPDIR/home"
  LR="$BATS_TEST_TMPDIR/lr"
  mkdir -p "$HOME/.claude/logs" "$HOME/.claude/autonomy/stop-failure" "$LR/recon/cohorts" \
    "$LR/recon/sessions" "$LR/recon/facts" "$LR/results" "$LR/fleet/one-x"
  printf '{"cid":"%s","acct":"next2","scope":"5h","resets_at":1790663400,"opened_at":1790654300,"members":["%s","%s"]}' \
    "$CID" "$SIDA" "$SIDB" > "$LR/recon/cohorts/$CID.json"
  rec "$SIDA" next4 ENGAGED ENGAGED
  rec "$SIDB" next4 ENGAGED ENGAGED
  # the only fact: the source's own 5h cap
  printf '{"acct":"next2","scope":"5h","status":"rejected","window":"five_hour","resets_at":1790663400,"observed_at":1790654300,"src":"hook"}' \
    > "$LR/recon/facts/next2.5h.json"
  req "$SIDA"; req "$SIDB"
  legacy "$SIDA" next4 RECOVERED 2026-09-29T04:18:06Z
  legacy "$SIDB" next4 RECOVERED 2026-09-29T04:17:59Z
  engaged "$SIDA" 2026-09-29T04:18:33Z
  engaged "$SIDB" 2026-09-29T04:19:01Z
}

rec() { # sid target phase via
  printf '{"sid":"%s","cohort_id":"%s","source_acct":"next2","target_acct":"%s","lane":"general","phase":"%s","timeline":{"planned":1790654400},"close":{"via":"%s"}}' \
    "$1" "$CID" "$2" "$3" "$4" > "$LR/recon/sessions/$1.json"
}
req() { printf '{"sid":"%s","account":"next2","reset_at_epoch":"1790663400","rate_limit_type":"five_hour"}' "$1" > "$LR/results/$1.retired.json"; }
legacy() { printf '%s\t841\t841\tnext2\t%s\trecycle-in-place/%s\t-\t%s\n' "$1" "$2" "$3" "$4" >> "$LR/fleet/one-x/results.tsv"; }
engaged() { printf '{"ts":"%s","class":"recycle-engaged","engaged":true,"prev_sid":"%s"}\n' "$2" "$1" >> "$HOME/.claude/logs/handoffs.jsonl"; }
archive() { /usr/bin/python3 "$L" watch "$LR" --once >/dev/null; }

@test "statics: py_compile under the box's /usr/bin/python3" {
  /usr/bin/python3 -m py_compile "$L"
}

@test "a cohort the daemon planned feasibly, found whole, and judged as legacy did ⇒ PASS" {
  archive
  run /usr/bin/python3 "$L" compare "$LR" "$CID" --home "$HOME"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"census misses 0"* ]] || { echo "$output"; false; }
  [[ "$output" == *"placements feasible 2/2"* ]] || { echo "$output"; false; }
  [[ "$output" == *"phase agree 2/2"* ]] || { echo "$output"; false; }
  [ -s "$LR/shadow-archive/$CID/compare.json" ]
}

@test "a limited pane legacy found and the census did not ⇒ census miss, FAIL" {
  req "$SIDC"
  archive
  run /usr/bin/python3 "$L" compare "$LR" "$CID" --home "$HOME"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"census misses 1 (cccccccc)"* ]] || { echo "$output"; false; }
}

@test "a placement onto an account a fact blocked at plan time ⇒ INFEASIBLE, FAIL" {
  printf '{"acct":"next4","scope":"5h","status":"rejected","window":"five_hour","resets_at":1790670000,"observed_at":1790654000,"src":"hook"}' \
    > "$LR/recon/facts/next4.5h.json"
  archive
  run /usr/bin/python3 "$L" compare "$LR" "$CID" --home "$HOME"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"blocked by next4.5h"* ]] || { echo "$output"; false; }
}

@test "legacy RECOVERED with no engaged watcher row is a false-RECOVERED, and the daemon agreeing with the WATCHER passes" {
  : > "$HOME/.claude/logs/handoffs.jsonl"
  engaged "$SIDA" 2026-09-29T04:18:33Z
  rec "$SIDB" next4 EXITING ""
  archive
  run /usr/bin/python3 "$L" compare "$LR" "$CID" --home "$HOME"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"false-RECOVERED resolved 1"* ]] || { echo "$output"; false; }
  # CONTROL: the daemon claiming ENGAGED against the watcher's truth disagrees
  rec "$SIDB" next4 ENGAGED ENGAGED
  run /usr/bin/python3 "$L" compare "$LR" "$CID" --home "$HOME"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"DISAGREE"* ]] || { echo "$output"; false; }
}

@test "the archive keeps a fact the daemon later reaped" {
  archive
  rm -f "$LR/recon/facts/next2.5h.json"
  archive
  run grep -c '"next2"' "$LR/shadow-archive/$CID/facts.jsonl"
  [ "$output" -eq 1 ]
}
