#!/usr/bin/env bats
# cc-teardown — the actuator. Its --selftest RED-proves the full flow (mock panes/pids + temp git,
# no real session); these bats add CLI-level regression that needs no mock rig.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$REPO/bin/cc-teardown"
  export CC_TEARDOWN_RECORDS_DIR="$BATS_TEST_TMPDIR/rec"
  export CC_TEARDOWN_SELF_UUID="none"   # deterministic self-guard in a headless test
}

@test "selftest passes and runs all 15 checks (a zero-check suite must not 'pass')" {
  run "$T" --selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 15 ]
}

@test "identity-pin: --expect-pid mismatch (pane recycled) → REFUSE (exit 2), records identity-pin (a17 S-4)" {
  # a live registry row whose pid differs from cc-reaper's classify-time pin → recycle → REFUSE, never kill.
  printf '#!/bin/bash\necho "[{\\"paneUUID\\":\\"U9\\",\\"name\\":\\"t\\",\\"pid\\":'"$$"',\\"cwd\\":\\"/tmp\\",\\"session_id\\":\\"s\\"}]"\n' > "$BATS_TEST_TMPDIR/cc-sessions"
  printf '#!/bin/bash\n[ "$1" = session ] && [ "$2" = list ] && { echo "[{\\"id\\":\\"U9\\"},{\\"id\\":\\"DESK\\"}]"; exit 0; }\nexit 0\n' > "$BATS_TEST_TMPDIR/it2"
  printf '#!/bin/bash\necho "{\\"decision\\":\\"OK\\",\\"git_state\\":\\"clean\\"}"; exit 0\n' > "$BATS_TEST_TMPDIR/gate"
  chmod +x "$BATS_TEST_TMPDIR/cc-sessions" "$BATS_TEST_TMPDIR/it2" "$BATS_TEST_TMPDIR/gate"
  CC_TEARDOWN_SESSIONS_BIN="$BATS_TEST_TMPDIR/cc-sessions" IT2_BIN="$BATS_TEST_TMPDIR/it2" \
  CC_TEARDOWN_GATE_BIN="$BATS_TEST_TMPDIR/gate" CC_TEARDOWN_SELF_UUID="none" \
  run "$T" U9 --done-evidence "x" --expect-pid 4000000
  [ "$status" -eq 2 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' 2>/dev/null | head -1)"
  [ -n "$rec" ]
  [ "$(jq -r '.decision' "$rec")" = "REFUSE" ]
  [ "$(jq -r '.reason_kind' "$rec")" = "identity-pin" ]
}

@test "no target → usage (exit 0), no teardown attempted" {
  run "$T"
  [ "$status" -eq 0 ]
}

@test "--self literal → REFUSE (exit 2) and writes a record (no silent refuse)" {
  run "$T" --self --done-evidence "x"
  [ "$status" -eq 2 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' 2>/dev/null | head -1)"
  [ -n "$rec" ]
  [ "$(jq -r '.decision' "$rec")" = "REFUSE" ]
}

@test "unknown target (empty registry) → REFUSE (exit 2)" {
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/cc-sessions"; chmod +x "$BATS_TEST_TMPDIR/cc-sessions"
  CC_TEARDOWN_SESSIONS_BIN="$BATS_TEST_TMPDIR/cc-sessions" run "$T" NOPE-0000 --done-evidence "x"
  [ "$status" -eq 2 ]
}
