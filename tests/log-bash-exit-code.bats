#!/usr/bin/env bats
# log-bash-exit-code — the audit line must carry a REAL exit code, on BOTH post-tool events.
#
# WHAT THIS EXISTS TO PIN. hooks/log-bash.sh line 2 promises "REAL exit code". Measured across the
# whole live log 2026-09-04: 37,319 `Exit:` fields spanning 2026-08-26 → 09-04, every one `0`.
# Not one non-zero exit had ever been recorded. Two independent causes:
#   (a) the REAL PostToolUse payload carries no `exitCode` at all — captured from 2.1.220,
#       tool_response = {stdout, stderr, interrupted, isImage, noOutputExpected} — so `// 0` won;
#   (b) a failing tool never reaches PostToolUse: the harness dispatches PostToolUseFailure
#       INSTEAD (positive control in one run — `echo ok` → PostToolUse, `false` →
#       PostToolUseFailure and NO PostToolUse), and that payload carries `.error`, no tool_response.
#
# 🚨 WHY THIS SUITE IS NOT THE WHOLE STORY, and the reason it is written this way. The first
# attempt at this fix DELETED the `.tool_response.exitCode` read and was auto-reverted on trunk,
# because tests/bash-audit-attrib.bats feeds a fixture that SYNTHESISES that field. That fixture
# matches no payload the harness sends — which is precisely how the bug survived: a green sibling
# suite certified exit-code recording while every logged line said 0. The lesson is not "the old
# test was wrong to exist"; it is that a suite proving a script works on a payload nobody sends
# proves nothing about production. So this suite pins the MEASURED shapes, the sibling keeps
# pinning the hypothetical one, and the subject satisfies both — precedence is asserted below.
#
# Hermetic: HOME is redirected into BATS_TEST_TMPDIR, so this writes to a scratch
# bash-execution.log and never touches ~/.claude/logs.

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/log-bash.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  LOG="$HOME/.claude/logs/bash-execution.log"
}

last_exit_field() { sed -E 's/.*\| Exit: //' "$LOG" | tail -1; }

# ---- the shapes the harness ACTUALLY sends (captured verbatim from a 2.1.220 run) --------------
real_success() {
  cat <<'JSON'
{"session_id":"sid-ok","cwd":"/tmp","hook_event_name":"PostToolUse","tool_name":"Bash",
 "tool_input":{"command":"echo control-ok"},
 "tool_response":{"stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false,"stdout":"control-ok"},
 "tool_use_id":"toolu_ok","duration_ms":851}
JSON
}
real_failure() {   # $1 = the .error string
  local err="${1:-Exit code 1}"
  cat <<JSON
{"session_id":"sid-fail","cwd":"/tmp","hook_event_name":"PostToolUseFailure","tool_name":"Bash",
 "tool_input":{"command":"false"},"tool_use_id":"toolu_fail","error":"${err}",
 "is_interrupt":false,"duration_ms":22}
JSON
}

@test "real success payload (no exitCode field anywhere) logs Exit: 0" {
  real_success | bash "$HOOK"
  [ "$(last_exit_field)" = "0" ]
  grep -q 'sid-ok' "$LOG"
}

@test "real FAILURE payload logs the real code, not 0 — the whole point" {
  real_failure 'Exit code 1' | bash "$HOOK"
  [ "$(last_exit_field)" = "1" ]
}

@test "a non-1 exit code survives verbatim (127 must not be coerced)" {
  real_failure 'Exit code 127' | bash "$HOOK"
  [ "$(last_exit_field)" = "127" ]
}

@test "a non-exit-code failure keeps its text — 'Interrupted' is information, not a 1" {
  real_failure 'Interrupted by user' | bash "$HOOK"
  [ "$(last_exit_field)" = "Interrupted by user" ]
}

@test "a failure with an EMPTY error is never laundered into 0" {
  printf '%s' '{"session_id":"s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"x"}}' | bash "$HOOK"
  [ "$(last_exit_field)" = "fail" ]
}

# ---- coexistence with the sibling suite's hypothetical shape -----------------------------------
@test "PRECEDENCE: an explicit tool_response.exitCode is honoured when present" {
  # This is tests/bash-audit-attrib.bats's fixture shape. It is not what 2.1.220 sends, but if any
  # binary ever does send it, the explicit value must win over the event-derived default.
  printf '%s' '{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"grep -q nope /etc/hosts"},"tool_response":{"stdout":"","stderr":"","exitCode":1}}' | bash "$HOOK"
  [ "$(last_exit_field)" = "1" ]
}

@test "PRECEDENCE: an explicit exitCode of 0 is not mistaken for 'absent'" {
  # `// empty` rather than `// 0` is what makes this distinguishable; with `// 0` both paths
  # collapse and the regression is invisible.
  printf '%s' '{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"true"},"tool_response":{"exitCode":0}}' | bash "$HOOK"
  [ "$(last_exit_field)" = "0" ]
}

@test "the audit line stays single-line even when .error contains a newline" {
  before=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  printf '%s' '{"session_id":"s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"x"},"error":"line one\nline two"}' | bash "$HOOK"
  [ "$(( $(wc -l < "$LOG") - before ))" -eq 1 ]
}

@test "the hook always exits 0 — an observer on the hottest path, never a gate" {
  run bash -c "printf '%s' '{\"hook_event_name\":\"PostToolUseFailure\",\"error\":\"Exit code 1\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "printf 'not json at all' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "CONTROL pre_fix_is_red: the pre-fix expression scores the REAL failure payload as 0" {
  # Replays only the pre-fix derivation (`.tool_response.exitCode // 0`) against the real failure
  # payload. It must give the WRONG answer — if it ever stops doing so, the payload shape moved and
  # every assertion above has quietly stopped testing the defect it was written for.
  pre_fix=$(real_failure 'Exit code 1' | jq -r '.tool_response.exitCode // 0')
  [ "$pre_fix" = "0" ]
  real_failure 'Exit code 1' | bash "$HOOK"
  [ "$(last_exit_field)" != "$pre_fix" ]
}
