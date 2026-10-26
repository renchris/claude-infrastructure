#!/usr/bin/env bats
# check18 (lane certification) contract, pinned against a STUB suite placed where the check resolves it
# (<root>/tests/probes/lane/run.py, root found through symlinks): the verdict mapping and its polarity
# knob, that the candidate binary reaches the suite, and that a suite with no verdict fails closed. The
# real suite starts throwaway Claude Code sessions; these cases never do.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
}

_g18_tree() {  # $1 = stub exit code → builds $BATS_TEST_TMPDIR/t with the real check + a stub suite
  local t="$BATS_TEST_TMPDIR/t"
  mkdir -p "$t/lib/cc-upgrade-gate" "$t/tests/probes/lane"
  cp "$REPO/lib/cc-upgrade-gate/check18_lanes.sh" "$t/lib/cc-upgrade-gate/"
  printf 'import sys\nopen("%s/suite-argv","w").write(" ".join(sys.argv[1:]))\nprint("PASS P-P1 — stub")\nprint("cert: /tmp/stub/2.9.9.json")\nsys.exit(%s)\n' \
    "$BATS_TEST_TMPDIR" "$1" > "$t/tests/probes/lane/run.py"
}

_g18_run() {  # $1 = path of the check file to source → prints "STATUS :: evidence :: detail"
  bash -c '
    export GATE_BIN=/cand/claude GATE_MODEL=claude-opus-5-5 GATE_ACCOUNTS=next GATE_SPAWN="${GATE_SPAWN:-1}"
    . "$2/lib/cc-upgrade-gate/common.sh"
    emit_result(){ echo "$3 :: $4 :: $5"; }
    . "$3"
    check_18
  ' _ "$BATS_TEST_TMPDIR" "$REPO" "$1"
}

@test "check18: CERTIFIED → PASS, and the candidate binary reaches the suite with --all" {
  _g18_tree 0
  run _g18_run "$BATS_TEST_TMPDIR/t/lib/cc-upgrade-gate/check18_lanes.sh"
  [[ "$output" == PASS* ]] || { echo "$output"; false; }
  [[ "$output" == *"cert=/tmp/stub/2.9.9.json"* ]] || { echo "$output"; false; }
  [ "$(cat "$BATS_TEST_TMPDIR/suite-argv")" = "--all --binary /cand/claude" ]
}

@test "check18: UNCERTIFIED is SKIP news while lanes are not live, FAIL once GATE_LANES_GATING=1 (red-proof)" {
  _g18_tree 1
  run _g18_run "$BATS_TEST_TMPDIR/t/lib/cc-upgrade-gate/check18_lanes.sh"
  [[ "$output" == SKIP*NEWS* ]] || { echo "$output"; false; }
  GATE_LANES_GATING=1 run _g18_run "$BATS_TEST_TMPDIR/t/lib/cc-upgrade-gate/check18_lanes.sh"
  [[ "$output" == FAIL*UNCERTIFIED* ]] || { echo "$output"; false; }
}

@test "check18: a suite with no verdict fails closed" {
  _g18_tree 2
  run _g18_run "$BATS_TEST_TMPDIR/t/lib/cc-upgrade-gate/check18_lanes.sh"
  [[ "$output" == FAIL*"no verdict (rc=2)"* ]] || { echo "$output"; false; }
}

@test "check18: sourced through a symlink it still finds the suite in the real tree" {
  _g18_tree 0
  mkdir -p "$BATS_TEST_TMPDIR/farm"
  ln -s "$BATS_TEST_TMPDIR/t/lib/cc-upgrade-gate/check18_lanes.sh" "$BATS_TEST_TMPDIR/farm/check18_lanes.sh"
  run _g18_run "$BATS_TEST_TMPDIR/farm/check18_lanes.sh"
  [[ "$output" == PASS* ]] || { echo "$output"; false; }
}

@test "check18: GATE_SPAWN=0 → SKIP; a missing suite → FAIL" {
  _g18_tree 0
  GATE_SPAWN=0 run _g18_run "$BATS_TEST_TMPDIR/t/lib/cc-upgrade-gate/check18_lanes.sh"
  [[ "$output" == SKIP*GATE_SPAWN=0* ]] || { echo "$output"; false; }
  mv "$BATS_TEST_TMPDIR/t/tests/probes/lane/run.py" "$BATS_TEST_TMPDIR/run.py.moved"
  run _g18_run "$BATS_TEST_TMPDIR/t/lib/cc-upgrade-gate/check18_lanes.sh"
  [[ "$output" == FAIL*"suite missing"* ]] || { echo "$output"; false; }
}

@test "lane suite: anchors are found by regex on the pinned binary when it is present" {
  bin="$HOME/.claude-293/node_modules/.bin/claude"
  [ -x "$bin" ] || skip "no 2.1.293 binary on this machine"
  run python3 -I "$REPO/tests/probes/lane/anchors.py" "$bin"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok": true'* ]] || { echo "$output" | head -40; false; }
}
