#!/usr/bin/env bats
# comms-safety — F3 payload-lint: a successor-fire payload missing the BACK-CHANNEL BLOCK (cc-notify line +
# desk full-uuid) lints RED — the W5 incident root; a terminal-announce via SendMessage lints RED (serves
# F2/a). The tool's --selftest RED-proves discrimination; these bats add CLI-level regression on the exit
# codes (0=GREEN, 1=RED, 2=LOUD).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  L="$REPO/scripts/payload-lint.sh"
  DESK='99261468-A46A-498A-AE9B-F39473E5E7AE'
  P="$BATS_TEST_TMPDIR/p.txt"
}

@test "selftest passes 4/4 (a zero-check suite must not 'pass')" {
  run "$L" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"4/4"* ]]
}

@test "block-less payload → RED (exit 1) — the W5 drop" {
  printf 'SUCCESSOR FIRE — continue the build. Ship at a green boundary.\n' > "$P"
  run "$L" "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BACK-CHANNEL BLOCK missing"* ]]
}

@test "well-formed payload (cc-notify + desk uuid + prohibition) → GREEN (exit 0)" {
  { printf 'SUCCESSOR FIRE.\n'
    printf 'BACK-CHANNEL: announce to the desk via cc-notify %s VERIFIED.\n' "$DESK"
    printf 'NEVER SendMessage — the desk is NOT a teammate.\n'; } > "$P"
  run "$L" "$P"
  [ "$status" -eq 0 ]
}

@test "missing cc-notify line (uuid only) → RED" {
  printf 'FIRE. the desk is %s. carry on.\n' "$DESK" > "$P"
  run "$L" "$P"
  [ "$status" -eq 1 ]
}

@test "missing desk uuid (cc-notify only) → RED" {
  printf 'FIRE. announce via cc-notify to the desk. carry on.\n' > "$P"
  run "$L" "$P"
  [ "$status" -eq 1 ]
}

@test "terminal-announce via SendMessage (F3/a) → RED even with the block present" {
  { printf 'FIRE. cc-notify %s is the desk.\n' "$DESK"
    printf 'On ship, announce the ship-witness to the desk via SendMessage.\n'; } > "$P"
  run "$L" "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"F3/a"* ]]
}

@test "a PROHIBITION of SendMessage is tolerated (prescriptive vs proscriptive) — not false-RED" {
  { printf 'FIRE. cc-notify %s is the desk.\n' "$DESK"
    printf 'NEVER use SendMessage for the desk — it silently degrades to disk-truth.\n'; } > "$P"
  run "$L" "$P"
  [ "$status" -eq 0 ]
}

@test "missing file → LOUD (exit 2), never a silent pass" {
  run "$L" "$BATS_TEST_TMPDIR/does-not-exist.txt"
  [ "$status" -eq 2 ]
}
