#!/usr/bin/env bats
# scripts/handoff-alarm-polarity.sh — RED when no handoff alarm in the window reached a reader
# (RECYCLE_KEYSTROKELESS_DELIVERY §D3: all 24 verdicts ever recorded were refused-rc3 and nothing
# noticed). Hermetic: a sandboxed HOME and alarm dir; records are backdated with touch -t.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/handoff-alarm-polarity.sh"
  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/alarms"; mkdir -p "$CC_HANDOFF_ALARM_DIR"
  unset CC_HANDOFF_ALARM_POLARITY_WINDOW_D CC_HANDOFF_ALARM_POLARITY_MIN
  N=0
}

record() { # $1=verdict token, or "" for a record with no sidecar · $2=optional touch -t stamp
  N=$((N + 1))
  local f="$CC_HANDOFF_ALARM_DIR/alarm-20261009T05032${N}Z-1-$N.json"
  printf '{"kind":"handoff-alarm","class":"recycle-dead"}\n' > "$f"
  if [ -n "$1" ]; then printf '%s\n' "$1" > "$f.verdict"; fi
  if [ -n "${2:-}" ]; then touch -t "$2" "$f"; fi
}
records_n() { # $1=count $2=verdict token
  local k=0
  while [ "$k" -lt "$1" ]; do record "$2"; k=$((k + 1)); done
}

@test "5 of 5 refused ⇒ RED (exit 1) — the 2026-10-09 state" {
  records_n 5 refused-rc3
  run bash "$S"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=red total=5 heard=0 refused=5"* ]] || { echo "$output"; false; }
}

@test "4 refused + 1 reached ⇒ GREEN (exit 0): one heard alarm proves the channel is alive" {
  records_n 4 refused-rc3
  record reached
  run bash "$S"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=green total=5 heard=1"* ]] || { echo "$output"; false; }
}

@test "a record with NO sidecar counts as not heard (fail-closed), so 4 refused + 1 missing is still RED" {
  records_n 4 refused-rc3
  record ""
  run bash "$S"
  [ "$status" -eq 1 ] && [[ "$output" == *"no_verdict=1"* ]] || { echo "$output"; false; }
}

@test "below the floor ⇒ ABSTAIN (exit 3), never green: 4 refusals are not yet a pattern" {
  records_n 4 refused-rc3
  run bash "$S"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=abstain"* ]] || { echo "$output"; false; }
  CC_HANDOFF_ALARM_POLARITY_MIN=4 run bash "$S"
  [ "$status" -eq 1 ] || { echo "$output"; false; }       # the floor is an env knob
}

@test "the window: a heard record OLDER than the window does not rescue a dead week" {
  records_n 5 refused-rc3
  record reached 202001010000                            # years old: outside the default 7 d
  run bash "$S" --json
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  echo "$output" | jq -e '.verdict == "red" and .total == 5 and .window_d == 7' >/dev/null || { echo "$output"; false; }
}

@test "no alarm dir at all ⇒ ABSTAIN, not an error and not green" {
  CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/none" run bash "$S"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
}

@test "runs under /bin/bash 3.2 (a scheduler's interpreter) with the same verdict" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  records_n 5 refused-rc3
  run /bin/bash "$S"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}
