#!/usr/bin/env bats
# waiting-recycle.sh — PER-INVOCATION MEMO (docs/plans/HOOK_CHAIN_COST.md R-1).
#
# WHAT IS UNDER TEST — only the memo, not the 1100-line hook around it. The hook traced 20 external
# execs before abstaining on a non-desk session; `shasum`+`cut` ran twice for the SAME cwd and the
# role file was read THREE times. Those reads are now done once, in the parent, because every caller
# reaches them through a command substitution (`[ -f "$(arm_for "$CWD")" ]` → sentinel_for → key_cwd)
# and a `$( )` subshell discards anything it assigns — a self-populating memo could never hit.
# Measured interleaved A/B at load 14: 100.08 ms → 67.46 ms median (-32.6%), 20 → 13 external execs.
#
# WHY THIS SUITE EXISTS SEPARATELY: all 106 cases in waiting-recycle.bats pass identically before and
# after the memo, so none of them can distinguish a correct memo from a broken one. They DO cover the
# lazy-CMD move (mutation-proved: forcing CMD empty reds "guard: a handoff-fire --recycle command
# does not trigger a fresh advisory").
#
# WHAT EACH CASE HERE IS ACTUALLY WORTH — stated from mutation results, not from intent, because the
# first draft of this header claimed more than the cases deliver:
#
#   • Case 5 is the ONLY one that catches a real memo defect. Mutated so the cwd memo returns a
#     fixed wrong hash, case 5 reds and nothing else does. It works by keying an arm marker on a
#     hash the TEST computes independently, so memo-vs-uncached drift of even one byte is visible.
#
#   • Cases 1-3 are CONTRACT-PRESERVATION, named as such: an empty, whitespace-only, or absent role
#     file must never make a session the desk. They are worth keeping — that is a security-shaped
#     invariant on the arming path — but they do NOT prove the memo. Measured: mutating the
#     existence guard `[ -n "${_WR_ROLE_V+set}" ]` into a truthiness guard `[ -n "${_WR_ROLE_V:-}" ]`
#     reds ZERO cases, because the truthiness form merely falls through to a re-read that yields the
#     same empty value. So the existence guard is a PERFORMANCE choice (it avoids one fork when the
#     role file is legitimately empty), not a correctness one. Do not let a future reader infer a
#     correctness contract here that no test enforces.
#
#   • Case 4 is the positive control for cases 1-3: without it they would pass on a fixture where
#     nothing could ever arm, i.e. they would be measuring the fixture rather than the invariant.
#
# Harness laws: L1 fixtures are literal PostToolUse payloads; L2 assertions key on the IDL
# disposition + reason, which are failure-distinct ("not-armed" vs "desk-role"); L3 `[ ]` / `grep -q`
# only; L4 every behaviour has a must-arm and a must-NOT-arm fixture.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermeticity: never the live ~/
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/waiting-recycle.sh"
  export CC_WR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_WR_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  export CC_WR_COORD_DIR="$BATS_TEST_TMPDIR/coord"
  export CC_WR_UUID="MEMO-TEST-UUID"
  export CC_WR_COOLDOWN_S=0 CC_WR_MAX=9 CC_WR_T_NUDGE=101
  # Load-insensitivity (test-hermeticity-lint): handoff-fire's capacity_gate() refuses a net-new
  # fire above 2.0/core and this box lives well above that, so without this pin the suite would go
  # red-by-load rather than by its subject. Nothing here intends to exercise the gate.
  export CC_FIRE_CAPACITY_GATE=off
  mkdir -p "$CC_TELEMETRY_DIR" "$CC_WR_STATE_DIR" "$CC_WR_COORD_DIR/cc-roles" "$CLAUDE_CONFIG_DIR"
  # No-op pager so no case can pop a real notification.
  export CC_WR_NOTIFY="$BATS_TEST_TMPDIR/noop.sh"; printf '#!/bin/bash\nexit 0\n' > "$CC_WR_NOTIFY"; chmod +x "$CC_WR_NOTIFY"
  SID="memo-sid-1"
  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"
}

drive() { # <cwd> → run the hook with a benign Bash PostToolUse payload
  printf '{"session_id":"%s","transcript_path":"","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"echo hi"}}' \
    "$SID" "$1" | bash "$HOOK"
}
# The hook's own cwd-key spelling, recomputed independently here. If the memo ever returned a
# different hash than this, the arm marker written below would not be found and case 4 would red.
cwd_key() { printf '%s|%s' "${CLAUDE_CONFIG_DIR}" "$1" | shasum 2>/dev/null | cut -c1-16; }
disp() { grep -o '"disposition":"[^"]*"' "$CC_WR_IDL" 2>/dev/null | tail -1; }
reason() { grep -o '"reason":"[^"]*"' "$CC_WR_IDL" 2>/dev/null | tail -1; }

@test "empty role file does NOT make the session the desk" {
  : > "$CC_WR_COORD_DIR/cc-roles/desk"          # exists, but empty
  run drive "$WORK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  reason | grep -q "not-armed"
}

@test "whitespace-only role file does NOT make the session the desk" {
  printf '   \n\t\n' > "$CC_WR_COORD_DIR/cc-roles/desk"   # tr -d '[:space:]' must reduce this to ""
  run drive "$WORK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  reason | grep -q "not-armed"
}

@test "absent role file does NOT make the session the desk (memo left UNSET)" {
  [ ! -f "$CC_WR_COORD_DIR/cc-roles/desk" ]
  run drive "$WORK"
  [ "$status" -eq 0 ]
  reason | grep -q "not-armed"
}

@test "POSITIVE CONTROL: a role file naming this session IS the desk" {
  # Without this case, the three above would pass on a fixture where nothing can ever arm — i.e.
  # they would be measuring the fixture, not the memo. This proves the desk branch is reachable,
  # so "not-armed" above is a real verdict rather than a structural impossibility.
  printf '%s\n' "$SID" > "$CC_WR_COORD_DIR/cc-roles/desk"
  run drive "$WORK"
  [ "$status" -eq 0 ]
  reason | grep -qv "not-armed"
}

@test "memoized cwd key resolves an arm marker written with the independently computed hash" {
  # Pins memo == uncached for key_cwd. The marker is keyed by a hash this test computes itself; if
  # the memo drifted by even one byte the hook would not find it and would report "not-armed".
  printf '%s\n' "$SID" > "$CC_WR_COORD_DIR/cc-roles/desk"
  local k; k="$(cwd_key "$WORK")"
  printf '2026-01-01T00:00:00Z %s\n' "$WORK" > "$CC_WR_STATE_DIR/disarm-$k"
  run drive "$WORK"
  [ "$status" -eq 0 ]
  # A disarm marker found via the memoized key must suppress even a role-holding desk.
  reason | grep -q "disarmed"
}
