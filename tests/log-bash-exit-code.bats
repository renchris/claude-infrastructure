#!/usr/bin/env bats
# log-bash-exit-code — the audit line must carry a REAL exit code, on BOTH post-tool events.
#
# WHAT THIS EXISTS TO PIN. hooks/log-bash.sh line 2 promises "REAL exit code". Measured
# 2026-09-04 on the live log: 37,319 `Exit:` fields across 9 days (2026-08-26 → 2026-09-04),
# every single one of them `0`. Not one non-zero exit had EVER been recorded. Two independent
# causes, both needed for the promise to be false, and the earlier D-3 fix addressed neither:
#
#   (a) WRONG FIELD, STILL. D-3 renamed `.tool_result.exitCode` → `.tool_response.exitCode`, but
#       `tool_response` has no `exitCode` either — the real success payload is
#       {stdout, stderr, interrupted, isImage, noOutputExpected}. So `// 0` kept winning. The
#       rename made the expression *look* corrected while leaving it vacuous: this is the
#       "fixed instrument lies" shape — correcting one blindness delivers you into the next.
#
#   (b) THE FAILING CALL NEVER ARRIVES. A tool that fails does not reach PostToolUse at all; the
#       harness dispatches PostToolUseFailure INSTEAD of it. Measured with a positive control in
#       ONE headless run on 2.1.220: `echo control-ok` → PreToolUse + PostToolUse;
#       `false` → PreToolUse + PostToolUseFailure and NO PostToolUse. So even a perfect exit-code
#       expression on PostToolUse could only ever observe successes — a success-only census that
#       reads like a complete one. `~/.claude/logs/bash-execution.log` is the corpus
#       docs/plans/HOOK_CHAIN_COST.md derives its rate arithmetic from.
#
# WHY THE MUTANT MATTERS HERE. The pre-fix script passes any test that only checks a SUCCESS
# payload — it emits `Exit: 0` for the right answer by the wrong route. So the load-bearing case
# is the FAILURE payload, and `pre_fix_is_red` below replays the exact pre-fix expression to prove
# this suite can go red at all. A control that cannot fail certifies nothing.
#
# Hermetic: HOME is redirected into BATS_TEST_TMPDIR, so the suite writes to a scratch
# bash-execution.log and never touches ~/.claude/logs.

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/log-bash.sh"
  [ -x "$HOOK" ] || chmod +x "$HOOK"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  LOG="$HOME/.claude/logs/bash-execution.log"
}

# The two payload shapes, captured verbatim from a real 2.1.220 headless run.
success_payload() {
  cat <<'JSON'
{"session_id":"sid-success","cwd":"/tmp","hook_event_name":"PostToolUse","tool_name":"Bash",
 "tool_input":{"command":"echo control-ok","description":"Echo control-ok"},
 "tool_response":{"stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false,"stdout":"control-ok"},
 "tool_use_id":"toolu_ok","duration_ms":851}
JSON
}

failure_payload() {   # $1 = the .error string the harness sends
  local err="${1:-Exit code 1}"
  cat <<JSON
{"session_id":"sid-failure","cwd":"/tmp","hook_event_name":"PostToolUseFailure","tool_name":"Bash",
 "tool_input":{"command":"false","description":"Run false"},
 "tool_use_id":"toolu_fail","error":"${err}","is_interrupt":false,"duration_ms":22}
JSON
}

last_exit_field() { sed -E 's/.*\| Exit: //' "$LOG" | tail -1; }

@test "success payload logs Exit: 0 (regression guard — this half already worked)" {
  success_payload | bash "$HOOK"
  [ "$(last_exit_field)" = "0" ]
  grep -q 'sid-success' "$LOG"
  grep -q 'echo control-ok' "$LOG"
}

@test "failure payload logs the REAL exit code, not 0 — the whole point" {
  failure_payload 'Exit code 1' | bash "$HOOK"
  run bash -c "sed -E 's/.*\\| Exit: //' '$LOG' | tail -1"
  [ "$output" = "1" ]
  [ "$output" != "0" ]
}

@test "a non-1 exit code survives verbatim (127 must not be coerced)" {
  failure_payload 'Exit code 127' | bash "$HOOK"
  [ "$(last_exit_field)" = "127" ]
}

@test "a non-exit-code failure keeps its text — 'Interrupted' is information, not a 1" {
  failure_payload 'Interrupted by user' | bash "$HOOK"
  [ "$(last_exit_field)" = "Interrupted by user" ]
}

@test "a failure with an EMPTY error is never laundered into 0" {
  printf '%s' '{"session_id":"s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"x"}}' | bash "$HOOK"
  [ "$(last_exit_field)" != "0" ]
  [ "$(last_exit_field)" = "fail" ]
}

@test "the audit line stays single-line even when .error contains a newline" {
  before=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  printf '%s' '{"session_id":"s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"x"},"error":"line one\nline two"}' | bash "$HOOK"
  after=$(wc -l < "$LOG")
  [ "$((after - before))" -eq 1 ]
}

@test "the hook always exits 0 — it is an observer on the hottest path, never a gate" {
  run bash -c "printf '%s' '{\"hook_event_name\":\"PostToolUseFailure\",\"error\":\"Exit code 1\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "printf 'not json at all' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "CONTROL pre_fix_is_red: the pre-fix expression scores the failure payload as 0" {
  # Replays ONLY the pre-fix exit derivation (hooks/log-bash.sh:18 before this change) against the
  # same failure payload the suite asserts on. It must produce the WRONG answer — if this ever
  # yields anything but 0, the payload shape has moved and the tests above are no longer testing
  # the defect they were written for.
  pre_fix=$(failure_payload 'Exit code 1' | jq -r '.tool_response.exitCode // 0')
  [ "$pre_fix" = "0" ]
  # ...and the fixed hook must disagree with it on that identical input.
  failure_payload 'Exit code 1' | bash "$HOOK"
  [ "$(last_exit_field)" != "$pre_fix" ]
}
