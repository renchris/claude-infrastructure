#!/usr/bin/env bats
# hooks/session-end.sh — the pane-close retry queue gets a SECOND clock (husk panes fix F-b).
#
# scripts/pane-close-retry.sh's only scheduled trigger was the end of a 600 s launchd job that
# launchd will not restart while its previous instance lives; measured 2026-10-01 one instance held
# it for 4h52m, so durable rows sat with no retry at all. Every SessionEnd that finds a queue row now
# kicks the drainer, detached and rate-limited by a machine-wide stamp. The drainer here is a stub.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export CC_PANE_CLOSE_QUEUE_DIR="$BATS_TEST_TMPDIR/q"; mkdir -p "$CC_PANE_CLOSE_QUEUE_DIR"
  export SE_DETACH_LIB="$REPO/scripts/lib/detach.sh" SE_PCQ_LOG="$BATS_TEST_TMPDIR/drain.log"
  export SE_PCQ_BIN="$BATS_TEST_TMPDIR/drainer"
  printf '#!/bin/bash\necho ran >> %s/drainer.ran\n' "$BATS_TEST_TMPDIR" > "$SE_PCQ_BIN"; chmod +x "$SE_PCQ_BIN"
  export CC_TEAMMATE_ORPHAN_CLOSE=off CC_TMP_SWEEP_DIRS="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$CC_TMP_SWEEP_DIRS"
  unset CC_PCQ_SESSIONEND_DRAIN CC_PCQ_SESSIONEND_MIN_S CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
}

end_hook() { echo '{"session_id":"s1","reason":"other"}' | bash "$REPO/hooks/session-end.sh" >/dev/null 2>&1 || true; }
runs() { local i=0; while [ ! -s "$BATS_TEST_TMPDIR/drainer.ran" ] && [ "$i" -lt "${1:-30}" ]; do sleep 0.1; i=$((i + 1)); done
         [ -f "$BATS_TEST_TMPDIR/drainer.ran" ] && wc -l < "$BATS_TEST_TMPDIR/drainer.ran" | tr -d ' ' || echo 0; }
row() { printf '{"kind":"teammate","pane":"57"}\n' > "$CC_PANE_CLOSE_QUEUE_DIR/teammate-57.json"; }

@test "a queue row present and no recent stamp: SessionEnd kicks the drainer" {
  row
  end_hook
  [ "$(runs)" = 1 ]
  [ -f "$CC_PANE_CLOSE_QUEUE_DIR/.sessionend-drain" ]
}

@test "a second SessionEnd inside the window does not kick it again (machine-wide stamp)" {
  row
  end_hook; [ "$(runs)" = 1 ]
  end_hook; sleep 0.5
  [ "$(runs 1)" = 1 ]
}

@test "an empty queue kicks nothing" {
  end_hook; sleep 0.5
  [ "$(runs 1)" = 0 ]
}

@test "the kill switch keeps SessionEnd off the queue" {
  row
  CC_PCQ_SESSIONEND_DRAIN=off end_hook; sleep 0.5
  [ "$(runs 1)" = 0 ]
}
