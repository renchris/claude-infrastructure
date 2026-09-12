#!/usr/bin/env bats
# handoff-claim-assert.sh — the Stop hook that verifies the hand-off claim.
# Every case is FAIL-SAFE-shaped: the hook blocks on exactly one condition and is silent on every
# other, errors included. Silence is the correct output almost always.
#
# HARNESS NOTE: the payloads carry backticks and newlines, so they are written to FILES and piped.
# Interpolating them through `bash -c` mangles them and produced three false REDs on first write —
# a test that fails for the wrong reason is worse than no test.

setup() {
  H="${BATS_TEST_DIRNAME}/../hooks/handoff-claim-assert.sh"
  T="$BATS_TEST_TMPDIR"
  export HANDOFF_CLAIM_STATE_DIR="$T/state"
}

# write_msg <file-with-the-assistant-text> → builds the transcript + stdin payload at $T/in.json
write_msg() {
  python3 - "$T" "$1" <<'PY'
import json,sys
T,src=sys.argv[1],sys.argv[2]
m=open(src).read()
open(f"{T}/t.jsonl","w").write(json.dumps({"type":"assistant","message":{"content":[{"type":"text","text":m}]}})+"\n")
open(f"{T}/in.json","w").write(json.dumps({"session_id":"s1","transcript_path":f"{T}/t.jsonl","cwd":"/tmp"}))
PY
}

@test "BLOCKS on a refutable command under the marker" {
  printf '%s\n' '▶ Run this:' '' '`cc-blockers`' > "$T/m.txt"; write_msg "$T/m.txt"
  run bash -c "bash '$H' < '$T/in.json'"
  [ "$status" -eq 0 ]                                   # a Stop hook ALWAYS exits 0
  printf '%s' "$output" | grep -q '"decision":"block"'
  printf '%s' "$output" | grep -q 'read-only'
}

@test "SILENT on a genuinely human command — an affirmation is not news" {
  printf '%s\n' '▶ Run this:' '' '`sudo killall fseventsd`' > "$T/m.txt"; write_msg "$T/m.txt"
  run bash -c "bash '$H' < '$T/in.json'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "SILENT inside a fence — the rendered OPERATOR block is a mandated verbatim relay" {
  # Convicting inside a fence would punish exactly the closes that obey the relay rule.
  printf '%s\n' '```' '▶ Run this:' '' 'cc-blockers' '```' > "$T/m.txt"; write_msg "$T/m.txt"
  run bash -c "bash '$H' < '$T/in.json'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "SILENT on a mid-sentence mention — position is the discriminator, not styling" {
  printf '%s\n' 'All landed. Read it back with `cc-blockers` whenever you like.' > "$T/m.txt"; write_msg "$T/m.txt"
  run bash -c "bash '$H' < '$T/in.json'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "LATCHED — the same close never blocks twice (the infinite-loop anti-pattern)" {
  printf '%s\n' '▶ Run this:' '' '`cc-decide list --open`' > "$T/m.txt"; write_msg "$T/m.txt"
  run bash -c "bash '$H' < '$T/in.json'"; printf '%s' "$output" | grep -q '"decision":"block"'
  run bash -c "bash '$H' < '$T/in.json'"; [ -z "$output" ]
}

@test "FAIL-SAFE — missing transcript, junk stdin, and the kill switch are all silent at rc 0" {
  run bash -c "printf '{\"transcript_path\":\"/nope/x.jsonl\"}' | bash '$H'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash -c "printf 'not json at all' | bash '$H'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  printf '%s\n' '▶ Run this:' '' '`cc-blockers`' > "$T/m.txt"; write_msg "$T/m.txt"
  run bash -c "HANDOFF_CLAIM_DISABLED=1 bash '$H' < '$T/in.json'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
