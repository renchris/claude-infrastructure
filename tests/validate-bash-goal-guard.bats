#!/usr/bin/env bats
# validate-bash goal guard — the CHOKEPOINT that stops a session disabling its own /goal.
#
# Subject: hooks/validate-bash.sh, LIVE-/goal guard. Mechanism: CC deletes the /goal Stop hook at
# any Stop where the task registry holds a non-terminal local_bash task
# (docs/research/goal-in-handoff-2026-08-08.md § RESOLVED) — and CLAUDE.md § Agent Teams instructs
# every wave lead to arm exactly such a task (`cc-await-ping`, Bash run_in_background). The guard
# denies that one arm, only under a live goal (MEMORY.md enforcement-must-live-at-the-chokepoint:
# gate the act's own tool call, and let the gate teach the alternative).
#
# The discriminators are the suite: foreground cc-await-ping (cc-wait's use) passes, a goal-less
# session passes, a met goal passes, an unreadable transcript passes (fail-open). Only the exact
# self-sabotage shape is refused.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  D="$BATS_TEST_TMPDIR"
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

live_goal_tx() {
  printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"resolve the goal-inertness conflict"}}\n' > "$D/t.jsonl"
  printf '%s' "$D/t.jsonl"
}
met_goal_tx() {
  { printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"x"}}\n'
    printf '{"type":"attachment","attachment":{"type":"goal_status","met":true,"condition":"x","iterations":1}}\n'
  } > "$D/t.jsonl"
  printf '%s' "$D/t.jsonl"
}

probe() { # <command> <run_in_background:true|false> <transcript>
  run bash -c 'jq -nc --arg c "$1" --argjson b "$2" --arg t "$3" \
    "{tool_input:{command:\$c, run_in_background:\$b}, transcript_path:\$t}" | "$0"' \
    "$HOOK" "$1" "$2" "$3"
}
denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

@test "DENIES: background cc-await-ping under a LIVE goal — and the reason teaches the mechanism" {
  probe "$HOME/.claude/bin/cc-await-ping --timeout 14400 --interval 15" true "$(live_goal_tx)"
  [ "$status" -eq 0 ]
  denied "$output"
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q 'skips /goal evaluation' || false
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q 'session-continue.sh set' || false
}

@test "PASSES: the same arm with NO goal in the transcript (the ordinary wave-lead case)" {
  printf '{"type":"user","message":{"content":"hello"}}\n' > "$D/t.jsonl"
  probe "cc-await-ping --timeout 14400" true "$D/t.jsonl"
  [ "$status" -eq 0 ]
  ! denied "$output" || false
}

@test "PASSES: a MET goal is no goal (last record wins)" {
  probe "cc-await-ping --timeout 14400" true "$(met_goal_tx)"
  ! denied "$output" || false
}

@test "PASSES: FOREGROUND cc-await-ping under a live goal (cc-wait's use — terminal by Stop time)" {
  probe "cc-await-ping --timeout 60" false "$(live_goal_tx)"
  ! denied "$output" || false
}

@test "PASSES: an unreadable transcript fails OPEN (never strand a wake path on a read failure)" {
  probe "cc-await-ping --timeout 14400" true "$D/absent.jsonl"
  ! denied "$output" || false
}

@test "DISCRIMINATOR: a background SEARCH that merely mentions cc-await-ping is NOT denied" {
  probe "rg -n 'cc-await-ping' docs/" true "$(live_goal_tx)"
  [ "$status" -eq 0 ]
  ! denied "$output" || false
}

@test "DENIES the path spelling too (\$HOME/.claude/bin/cc-await-ping — the nags' exact string)" {
  probe "/some/home/.claude/bin/cc-await-ping --timeout 14400 --interval 15" true "$(live_goal_tx)"
  denied "$output"
}
