#!/usr/bin/env bats
# agent-teams-enforce.sh — PreToolUse hook on the Agent tool: enforces Agent Teams for
# implementation and (G-P13-4) counts the teammate brief. The brief IS the `prompt`; an oversized
# brief burns the teammate context before any work and drives the GH #49593 /compact crash → wave
# stall (FM2). Graduated guard: >WARN(150) → allow + hard warning · >=DENY(250) → deny · else
# unchanged allow+pointer. These tests also anchor the pre-existing model-allowlist / research
# behavior so the brief-count insertion is proven not to have regressed it.
#
# A PreToolUse hook signals a block via JSON permissionDecision:"deny", NOT via exit code — every
# path here exits 0, so the allow/deny distinction is asserted on the emitted JSON, not $status.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/agent-teams-enforce.sh"
}

brief() { yes "brief content line" | head -n "$1"; }   # emit an N-line brief

run_hook() { # $1=team_name  $2=prompt  [$3=model]
  jq -n --arg tn "$1" --arg p "$2" --arg m "${3:-}" \
    '{tool_input:{team_name:$tn,prompt:$p,model:$m}}' | bash "$HOOK"
}
decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"'; }
has()      { printf '%s' "$1" | grep -q "$2"; }

# ── G-P13-4: brief-count guard ──────────────────────────────────────────────────
@test "small brief (10 lines) + team_name → allow, no over-cap warning" {
  run run_hook "wave-1" "$(brief 10)"
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = allow ]
  ! has "$output" "OVER CAP"
  printf '%s' "$output" | jq -e . >/dev/null          # well-formed JSON
}

@test "brief just over warn cap (160 lines) → allow + hard warning naming the count" {
  run run_hook "wave-1" "$(brief 160)"
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = allow ]
  has "$output" "OVER CAP"
  has "$output" "160 lines"
  printf '%s' "$output" | jq -e . >/dev/null
}

@test "brief at/over hard cap (250 lines) → DENY with split guidance" {
  run run_hook "wave-1" "$(brief 250)"
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = deny ]
  has "$output" "SPLIT into 2-3 teammates"
  has "$output" "250 lines"
  printf '%s' "$output" | jq -e . >/dev/null
}

@test "warn threshold is env-overridable (AGENT_TEAMS_BRIEF_WARN_LINES=20)" {
  export AGENT_TEAMS_BRIEF_WARN_LINES=20
  run run_hook "wave-1" "$(brief 25)"
  [ "$(decision "$output")" = allow ]
  has "$output" "OVER CAP"
}

@test "deny threshold is env-overridable (AGENT_TEAMS_BRIEF_DENY_LINES=30)" {
  export AGENT_TEAMS_BRIEF_DENY_LINES=30
  run run_hook "wave-1" "$(brief 35)"
  [ "$(decision "$output")" = deny ]
}

# ── regression anchors: brief-count insertion must not disturb these ─────────────
@test "off-allowlist model → deny (model gate runs before brief-count)" {
  run run_hook "wave-1" "$(brief 10)" "zzz-not-a-real-model"
  [ "$(decision "$output")" = deny ]
  has "$output" "allowlist"
}

@test "allowlisted model alias (opus) + small brief → allow" {
  run run_hook "wave-1" "$(brief 10)" "opus"
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = allow ]
}

@test "no team_name + research prompt → allow (exit 0)" {
  run run_hook "" "research and analyze the design space; read and inspect the files"
  [ "$status" -eq 0 ]
}
