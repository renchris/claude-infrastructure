#!/usr/bin/env bats
# C1 — no-focus-steal autonomous handoff-fire (2026-07-19, the ttys018 mis-inject).
# --follow gates the raise: WITHOUT it a fire is AUTONOMOUS and the default surface is a BACKGROUND tab
# (never a split of the operator's active pane, never `session focus`/order_window_front=True); WITH it
# the ⌘D split-right preference + the raise return for a manual /handoff. These assert the surface-
# resolution POLICY via --dry-run (pure bash, no iTerm2) + that the embedded it2py python compiles.
# The live focus-preservation (create → restore active-session + frontmost-app → assert unchanged)
# runs against a real iTerm2, so it cannot execute headless; it is verified manually + recorded in the
# landing commit. Design: docs/research/desk-anti-hitl-2026-07-19.md Part C.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  PF="$BATS_TEST_TMPDIR/fire.txt"; echo "resume the desk work" > "$PF"
}

# A dry-run with a fake anchor + explicit launcher/account (account-probe is a no-op in --dry-run).
dry() { bash "$HF" --prompt-file "$PF" --session-id "w1t0p0:FAKE-UUID" --account next --launcher claude-next "$@" --dry-run; }

@test "--follow is a known flag (not 'unknown arg')" {
  run dry --follow
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qi "unknown arg"
}

@test "AUTONOMOUS default (no surface flag) resolves to a background tab, no raise" {
  run dry
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE "surface: +bg-tab"
  echo "$output" | grep -qiE "follow: +no"
}

@test "--follow keeps the split-right (⌘D) preference and raises" {
  run dry --follow
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE "surface: +split-right"
  echo "$output" | grep -qiE "follow: +YES"
}

@test "explicit --tab WITHOUT --follow is normalized to a background tab" {
  run dry --tab
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE "surface: +bg-tab"
  echo "$output" | grep -qiE "follow: +no"
}

@test "explicit --split-right WITHOUT --follow stays a split but is autonomous (restore + assert)" {
  run dry --split-right
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE "surface: +split-right"
  echo "$output" | grep -qiE "follow: +no"
}

@test "--tab --follow is a raised tab" {
  run dry --tab --follow
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE "surface: +tab"
  echo "$output" | grep -qiE "follow: +YES"
}

@test "the fire summary records the background/raised disposition" {
  # Not a dry-run assertion — the summary line is only printed on a real fire, but the dry-run 'follow:'
  # line carries the same policy; assert the autonomous default advertises operator-focus preservation.
  run dry
  echo "$output" | grep -qi "operator focus"
}

@test "the embedded it2py python is syntactically valid (py_compile)" {
  # Extract the it2py() heredoc body (skips the earlier detach() PY block via the it2py() anchor) and
  # compile it — a guard against a future edit breaking the focus-safe driver. py_compile never imports
  # iterm2, so it runs fine with no iTerm2 / no iterm2 module installed.
  command -v python3 >/dev/null || skip "python3 not on PATH"
  local body="$BATS_TEST_TMPDIR/it2py.py"
  awk '
    /^it2py\(\) \{/ { inf = 1; next }
    inf && /<<.PY.$/ { cap = 1; next }
    cap && /^PY$/ { exit }
    cap { print }
  ' "$HF" > "$body"
  [ -s "$body" ]
  python3 -m py_compile "$body"
}
