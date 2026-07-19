#!/usr/bin/env bats
# handoff-fire.sh prompt-file validation — the FM-D empty-payload guard (Fable panel 2026-07-19).
# An empty prompt file passed the [ -f ] existence check and fired `claude ""` → a task-less-idle
# successor. The [ -s ] guard rejects it BEFORE any side effect, for every fire mode.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
}

@test "FM-D: an EMPTY prompt file is rejected before any side effect" {
  local pf="$BATS_TEST_TMPDIR/empty.txt"; : > "$pf"
  run bash "$HF" --recycle --prompt-file "$pf" --session-id "fake:UUID"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "empty prompt file"
  echo "$output" | grep -qi "FM-D"
}

@test "a MISSING prompt file is still rejected (the pre-existing [ -f ] guard)" {
  run bash "$HF" --recycle --prompt-file "$BATS_TEST_TMPDIR/does-not-exist.txt" --session-id "fake:UUID"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "missing prompt file"
}

@test "a NON-empty prompt file passes both validation guards (fails later, not on [ -s ])" {
  local pf="$BATS_TEST_TMPDIR/ok.txt"; echo "resume the desk" > "$pf"
  run bash "$HF" --recycle --prompt-file "$pf" --session-id "fake:UUID"
  # It will fail downstream (no real iTerm/account in the test env) — but NOT on the empty/missing guards.
  ! echo "$output" | grep -qi "empty prompt file"
  ! echo "$output" | grep -qi "missing prompt file"
}
