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
  # HERMETIC $HOME, the idiom of tests/handoff-recycle-durable-cwd.bats: the fixture $HOME symlinks
  # the read-only config the subject resolves (~/.claude) and owns everything else.
  local real_home="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  [ -e "$real_home/.claude" ] && ln -s "$real_home/.claude" "$HOME/.claude"
  # That symlink makes every ~/.claude/state and ~/.claude/logs default the LIVE one, so each writer
  # a held recycle reaches is pinned here: the pane-close queue (the row this suite once left at
  # ~/.claude/state/pane-close-queue/recycle-fake_UUID.json) and the handoffs.jsonl refusal log.
  export CC_PANE_CLOSE_QUEUE_DIR="$BATS_TEST_TMPDIR/pcq"
  export CC_FIRE_REFUSAL_LOG=0
  # Never the pane's own terminal. Unset, a test run inside kitty probed /tmp/kitty-<live pid>.
  # CC_TERM=kitty with CC_TERM_KITTY_TO on a socket that cannot exist stops the recycle at its
  # up-front probe (handoff-fire.sh hf_recycle_kitty_precheck), before any pane is touched;
  # CC_FIRE_KITTY_PROBE=off stops the headless discovery from finding the live socket.
  unset KITTY_WINDOW_ID KITTY_PID KITTY_LISTEN_ON CC_TERM ITERM_SESSION_ID CC_PANE_EXIT_OWED CC_PANE_STARTED_FILE
  export CC_TERM=kitty CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/no-kitty.sock" CC_FIRE_KITTY_PROBE=off
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

# The arm above once wrote ~/.claude/state/pane-close-queue/recycle-fake_UUID.json and probed the live
# kitty (/tmp/kitty-1881): it ran with the real HOME, no queue dir and the pane's own KITTY_* env.
# The setup now pins both, so the held recycle's row lands in this suite's queue and names the
# stub socket the probe was pointed at.
@test "a held recycle writes its row to the suite's own queue and probes only the stub socket" {
  local pf="$BATS_TEST_TMPDIR/ok.txt"; echo "resume the desk" > "$pf"
  run bash "$HF" --recycle --prompt-file "$pf" --session-id "fake:UUID"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "recycle HELD"
  local row="$BATS_TEST_TMPDIR/pcq/recycle-fake_UUID.json"
  [ -f "$row" ]
  run jq -r .kitty_sock "$row"
  [ "$output" = "$BATS_TEST_TMPDIR/no-kitty.sock" ]
}
