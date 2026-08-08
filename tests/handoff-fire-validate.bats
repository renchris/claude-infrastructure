#!/usr/bin/env bats
# handoff-fire.sh prompt-file validation — the FM-D empty-payload guard (Fable panel 2026-07-19).
# An empty prompt file passed the [ -f ] existence check and fired `claude ""` → a task-less-idle
# successor. The [ -s ] guard rejects it BEFORE any side effect, for every fire mode.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
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
  ! echo "$output" | grep -qi "empty prompt file" || false
  ! echo "$output" | grep -qi "missing prompt file"
}
