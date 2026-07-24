#!/usr/bin/env bats
# effort-parity-assert.sh — asserts resolved effort matches the SSOT effort_defaults floor.
#
# Guards the drift the script was built for: model-config.yaml claimed a xhigh settings floor
# "symlinked into every CLAUDE_CONFIG_DIR", but the five settings.json are FIVE INDEPENDENT REAL files
# that had drifted to ~/.claude=high, four accounts=low — every non-wrapped surface silently resolved
# below the floor and no existing gate (claude-lint-models / settings-drift-assert) caught it.
#
# HERMETIC: each case builds a fake SSOT + config dirs + zshrc + ps fixture in BATS_TEST_TMPDIR and
# drives the script via CC_EFFORT_SSOT / CC_EFFORT_DIRS / CC_EFFORT_ZSHRC / CC_EFFORT_PS. The final case
# runs the script against the REAL live host (no fixtures) to prove the live path is assertable.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export ASSERT="$REPO_ROOT/scripts/effort-parity-assert.sh"

  # a minimal SSOT carrying the effort_defaults keys the script reads
  export CC_EFFORT_SSOT="$BATS_TEST_TMPDIR/model-config.yaml"
  cat > "$CC_EFFORT_SSOT" <<'YAML'
effort_defaults:
  default: max
  settings_floor: xhigh
frontier_access:
  active: true
YAML

  export CC_EFFORT_ZSHRC="$BATS_TEST_TMPDIR/zshrc"
  printf 'alias claude="claude --effort ${CLAUDE_DEFAULT_EFFORT:-max}"\n' > "$CC_EFFORT_ZSHRC"

  export CC_EFFORT_PS="$BATS_TEST_TMPDIR/ps.txt"
  printf 'claude --effort max\nnode server.js\n' > "$CC_EFFORT_PS"   # no below-floor live session

  export D="$BATS_TEST_TMPDIR/dirs"
  mkdir -p "$D"/one "$D"/two "$D"/three "$D"/four "$D"/five
  export CC_EFFORT_DIRS="$D/one $D/two $D/three $D/four $D/five"
}

set_all() {  # $1 = effortLevel written to every fake dir's settings.json
  local d
  for d in "$D"/one "$D"/two "$D"/three "$D"/four "$D"/five; do
    printf '{"effortLevel":"%s"}\n' "$1" > "$d/settings.json"
  done
}

@test "parity: every dir at the SSOT floor (xhigh) + zshrc max ⇒ exit 0" {
  set_all xhigh
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"parity"* ]]
}

@test "the live-state shape (one dir high, four low) ⇒ DRIFT, exit 1 (the 2026-07-24 regression)" {
  printf '{"effortLevel":"high"}\n' > "$D/one/settings.json"
  local d
  for d in two three four five; do printf '{"effortLevel":"low"}\n' > "$D/$d/settings.json"; done
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BELOW"* ]]
  [[ "$output" == *"high < floor xhigh"* ]]
  [[ "$output" == *"low < floor xhigh"* ]]
}

@test "zshrc launcher --effort default drifted below SSOT (high, not max) ⇒ exit 1" {
  set_all xhigh
  printf 'alias claude="claude --effort ${CLAUDE_DEFAULT_EFFORT:-high}"\n' > "$CC_EFFORT_ZSHRC"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"zshrc launcher"* ]]
}

@test "a below-floor LIVE session is REPORT-ONLY by default (⚠, does NOT gate)" {
  set_all xhigh
  printf 'claude --effort low\n' > "$CC_EFFORT_PS"
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PS-WARN"* ]]
}

@test "a below-floor LIVE session GATES under CC_EFFORT_PS_STRICT=1" {
  set_all xhigh
  printf 'claude --effort low\n' > "$CC_EFFORT_PS"
  CC_EFFORT_PS_STRICT=1 run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PS-WARN"* ]]
}

@test "missing effortLevel key ⇒ NOFLOOR drift (binary default, not the floor)" {
  set_all xhigh
  printf '{"model":"claude-opus-4-8"}\n' > "$D/one/settings.json"   # no effortLevel key
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOFLOOR"* ]]
}

@test "SSOT unreadable ⇒ exit 3 (missing prerequisite), never a false parity" {
  set_all xhigh
  CC_EFFORT_SSOT="$BATS_TEST_TMPDIR/nope.yaml" run "$ASSERT"
  [ "$status" -eq 3 ]
}

@test "the REAL live host is assertable — script runs to a 0/1 verdict, never a crash (exit 3)" {
  run env -u CC_EFFORT_SSOT -u CC_EFFORT_DIRS -u CC_EFFORT_ZSHRC -u CC_EFFORT_PS "$ASSERT"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]     # a real verdict, not a missing-prereq crash
  [[ "$output" == *"SSOT floor="* ]]
}
