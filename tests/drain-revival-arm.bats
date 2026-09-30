#!/usr/bin/env bats
# drain-revival-arm.sh — the actuator that revives a DEAD drain chain (backlog c109e9e850fb).
#
# The load-bearing property is the NEGATIVE one: the fire binary runs in exactly one case (mode on,
# verdict dead, a parseable link number, no live cooldown, a claimed stamp) and in no other. So every
# case asserts whether the fire stub was called, not only the decision string — a decision that reads
# right over a fire that happened anyway is the failure this suite exists to catch.
# Both the detector and the fire path are stubs; HOME is fixtured so nothing reaches the live store.

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"; mkdir -p "$HOME"
  SUBJECT="${BATS_TEST_DIRNAME}/../scripts/drain-revival-arm.sh"
  export CC_DRAIN_ARM_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  FIRE_LOG="${BATS_TEST_TMPDIR}/fire.log"
  ASSERT_LOG="${BATS_TEST_TMPDIR}/assert.log"
  export CC_DRAIN_FIRE_BIN="${BATS_TEST_TMPDIR}/fire-stub.sh"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$FIRE_LOG" > "$CC_DRAIN_FIRE_BIN"
  export CC_DRAIN_ASSERT_BIN="${BATS_TEST_TMPDIR}/assert-stub.sh"
  unset CC_DRAIN_AUTOFIRE
}

# <verdict> [brief-basename] [rc] — the detector stub prints a verdict object shaped like the real one.
detector() {
  local v="$1" b="${2:-fire-drain-infra-recycle336.txt}" rc="${3:-0}"
  printf '#!/bin/bash\necho x >> "%s"\necho '"'"'{"verdict":"%s","why":"no-brief-no-lease","brief":"/x/%s"}'"'"'\nexit %s\n' \
    "$ASSERT_LOG" "$v" "$b" "$rc" > "$CC_DRAIN_ASSERT_BIN"
}

decision() { printf '%s' "$output" | jq -r '.decision'; }
fires() { [ -f "$FIRE_LOG" ] && wc -l < "$FIRE_LOG" | tr -d ' ' || echo 0; }

@test "dead + on: fires once, with the next link number and --first" {
  detector dead
  CC_DRAIN_AUTOFIRE=on run bash "$SUBJECT" --tick
  [ "$status" -eq 0 ]
  [ "$(decision)" = fired ]
  [ "$(fires)" = 1 ]
  grep -q -- '--num 337' "$FIRE_LOG"
  grep -q -- '--first' "$FIRE_LOG"
  [ "$(printf '%s' "$output" | jq -r '.fire_rc')" = 0 ]
  [ -s "$CC_DRAIN_ARM_STATE_DIR/fire.stamp" ]
}

@test "alive + on: never fires" {
  detector alive
  CC_DRAIN_AUTOFIRE=on run bash "$SUBJECT" --tick
  [ "$(decision)" = alive ]
  [ "$(fires)" = 0 ]
}

@test "dead + on + fresh stamp: cooldown holds the fire" {
  detector dead
  mkdir -p "$CC_DRAIN_ARM_STATE_DIR"; date +%s > "$CC_DRAIN_ARM_STATE_DIR/fire.stamp"
  CC_DRAIN_AUTOFIRE=on run bash "$SUBJECT" --tick
  [ "$(decision)" = cooldown-held ]
  [ "$(fires)" = 0 ]
}

@test "dead + on, second tick inside the cooldown: exactly one fire in total" {
  detector dead
  CC_DRAIN_AUTOFIRE=on run bash "$SUBJECT" --tick
  [ "$(decision)" = fired ]
  CC_DRAIN_AUTOFIRE=on run bash "$SUBJECT" --tick
  [ "$(decision)" = cooldown-held ]
  [ "$(fires)" = 1 ]
}

@test "kill switch off: neither the detector nor the fire runs" {
  detector dead
  CC_DRAIN_AUTOFIRE=off run bash "$SUBJECT" --tick
  [ "$(decision)" = off ]
  [ "$(fires)" = 0 ]
  [ ! -f "$ASSERT_LOG" ]
}

@test "unset mode defaults to would-fire: logs the command, fires nothing, keeps its own stamp" {
  detector dead
  run bash "$SUBJECT" --tick
  [ "$(printf '%s' "$output" | jq -r '.mode')" = would-fire ]
  [ "$(decision)" = would-fire ]
  [ "$(fires)" = 0 ]
  printf '%s' "$output" | jq -r '.cmd' | grep -q -- '--num 337'
  [ -s "$CC_DRAIN_ARM_STATE_DIR/would-fire.stamp" ]
  [ ! -f "$CC_DRAIN_ARM_STATE_DIR/fire.stamp" ]
}

@test "would-fire respects the same hourly cap" {
  detector dead
  run bash "$SUBJECT" --tick
  [ "$(decision)" = would-fire ]
  run bash "$SUBJECT" --tick
  [ "$(decision)" = cooldown-held ]
}

@test "bogus mode fails closed" {
  detector dead
  CC_DRAIN_AUTOFIRE=yes run bash "$SUBJECT" --tick
  [ "$(decision)" = bad-mode ]
  [ "$(fires)" = 0 ]
}

@test "detector exits non-zero: no verdict, no fire" {
  detector dead fire-drain-infra-recycle336.txt 1
  CC_DRAIN_AUTOFIRE=on run bash "$SUBJECT" --tick
  [ "$(decision)" = no-verdict ]
  [ "$(fires)" = 0 ]
}

@test "detector prints garbage: no verdict, no fire" {
  printf '#!/bin/bash\necho not-json\n' > "$CC_DRAIN_ASSERT_BIN"
  CC_DRAIN_AUTOFIRE=on run bash "$SUBJECT" --tick
  [ "$(decision)" = no-verdict ]
  [ "$(fires)" = 0 ]
}

@test "unparseable brief name: no link number, no fire" {
  detector dead some-other-file.txt
  CC_DRAIN_AUTOFIRE=on run bash "$SUBJECT" --tick
  [ "$(decision)" = no-num ]
  [ "$(fires)" = 0 ]
}

@test "unwritable state dir: claim fails closed, no fire" {
  detector dead
  export CC_DRAIN_ARM_STATE_DIR="${BATS_TEST_TMPDIR}/ro/state"
  mkdir -p "${BATS_TEST_TMPDIR}/ro"; chmod 555 "${BATS_TEST_TMPDIR}/ro"
  CC_DRAIN_AUTOFIRE=on run bash "$SUBJECT" --tick
  chmod 755 "${BATS_TEST_TMPDIR}/ro"
  [ "$(decision)" = claim-failed ]
  [ "$(fires)" = 0 ]
}

@test "unknown argument exits 2" {
  run bash "$SUBJECT" --fire
  [ "$status" -eq 2 ]
}
