#!/usr/bin/env bats
# cc-model-registered — the exit-code contract of the model-registration probe (cc-upgrade skill,
# registration phase): 0 present, 1 absent, 2 instrument broken, 64 usage.
#
# Fixtures are small byte files standing in for the Bun binary: NUL-separated, no newlines, the
# shape that makes a line-oriented count lie. Each case asserts the verdict token AND the exit code.
#
# RED-proof: replacing count_id's pattern with a plain substring count (drop the (?![-0-9])
# lookahead) turns "a prefix id is not counted inside its successor" red, and removing the
# control check turns "control absent" red (it exits 1 instead of 2); both measured 2026-09-28.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  P="$REPO/bin/cc-model-registered"
  F="$BATS_TEST_TMPDIR"
}

blob() {  # blob <file> <id>... : ids NUL-separated between filler, one "line" in total
  local out="$1"; shift
  printf 'filler\0' >"$out"
  for id in "$@"; do printf 'x%s\0' "$id" >>"$out"; done
}

@test "present: the id and the control are both in the binary -> exit 0" {
  blob "$F/bin" claude-opus-5 claude-sonnet-5-5 claude-sonnet-5-5
  run "$P" claude-sonnet-5-5 --bin "$F/bin"
  [ "$status" -eq 0 ]
  [[ "$output" == "verdict=present id=claude-sonnet-5-5 count=2 control=claude-opus-5 control_count=1 "* ]] || false
}

@test "absent: control present, id missing -> exit 1" {
  blob "$F/bin" claude-opus-5 claude-sonnet-5
  run "$P" claude-sonnet-5-5 --bin "$F/bin"
  [ "$status" -eq 1 ]
  [[ "$output" == "verdict=absent id=claude-sonnet-5-5 count=0 "* ]] || false
}

@test "control absent: a zero proves nothing -> exit 2, never 1" {
  blob "$F/bin" claude-haiku-4-5
  run "$P" claude-sonnet-5-5 --bin "$F/bin"
  [ "$status" -eq 2 ]
  [[ "$output" == "verdict=instrument-broken "* ]] || false
}

@test "a prefix id is not counted inside its successor (claude-sonnet-5 vs claude-sonnet-5-5)" {
  blob "$F/bin" claude-opus-5 claude-sonnet-5-5 claude-sonnet-5-5
  # The naive readings both say present: a substring count finds 2, a line count finds 1.
  [ "$(python3 -c 'import sys; print(open(sys.argv[1],"rb").read().count(b"claude-sonnet-5"))' "$F/bin")" -eq 2 ]
  run "$P" claude-sonnet-5 --bin "$F/bin"
  [ "$status" -eq 1 ]
  [[ "$output" == "verdict=absent id=claude-sonnet-5 count=0 "* ]] || false
  # ...and the control itself is not inflated by claude-opus-5-5.
  blob "$F/bin2" claude-opus-5-5
  run "$P" claude-opus-5-5 --bin "$F/bin2"
  [ "$status" -eq 2 ]
}

@test "without --bin it measures what bin/cc-claude-bin resolves" {
  blob "$F/bin" claude-opus-5 claude-sonnet-5-5
  chmod +x "$F/bin"
  run env CC_CLAUDE_BIN="$F/bin" "$P" claude-sonnet-5-5
  [ "$status" -eq 0 ]
  [[ "$output" == *" bin=$(cd "$F" && pwd -P)/bin" ]] || false
}

@test "an unreadable binary or a malformed id is not reported as absent" {
  run "$P" claude-sonnet-5-5 --bin "$F/nope"
  [ "$status" -eq 2 ]
  [[ "$output" == "verdict=instrument-broken reason=unreadable "* ]] || false
  run "$P" sonnet-5.5 --bin "$F/nope"
  [ "$status" -eq 64 ]
}
