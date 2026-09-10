#!/usr/bin/env bats
# unit-gate.sh — PreToolUse matcher "*": the brake, the HALTED stamp, the unit ledger.
# Spec: docs/research/oversight-at-scale-2026-08-19.md §5.2-§5.3. Backlog ad37b0296a56.
#
# A PreToolUse hook signals a block through JSON `permissionDecision:"deny"`, NOT an exit code —
# every path here exits 0, so allow/deny is asserted on the emitted JSON, never on $status.
#
# 🚨 THE FIRST CASE IS THE ONE THAT GIVES THE REST THEIR POWER. A hook that denied unconditionally
# would pass every deny case below and read as a healthy brake. `silent when nothing is set` is the
# arm that can refute that, and it is why the suite is not one-armed
# (MEMORY: one-armed-adjudication-only-convicts, alarm-polarity-and-attention-budget).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/unit-gate.sh"
  MIG="$REPO/migrations/0024-unit-gate-registration.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
  unset CC_UNIT_GATE_EXEMPT
}

# $1 session_id · $2 agent_id ('' = none) · $3 tool_name · $4 raw tool_input JSON (default {})
payload() {
  local sid="$1" aid="$2" tool="$3" ti="${4:-\{\}}"
  if [ -n "$aid" ]; then
    printf '{"session_id":"%s","agent_id":"%s","agent_type":"workflow-subagent","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' \
      "$sid" "$aid" "$tool" "$ti"
  else
    printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' \
      "$sid" "$tool" "$ti"
  fi
}
fire() { payload "$@" | bash "$HOOK"; }
set_halt() { mkdir -p "$(dirname "$1")"; printf 'ts=2026-09-09T00:00:00Z\nscope=%s\n' "${2:-test}" > "$1"; }

# ── the control arm ─────────────────────────────────────────────────────────────────────────────
@test "silent when nothing is set — the arm that refutes an unconditional deny" {
  run fire s-1 '' Bash
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── the three scopes (§5.2 Check) ───────────────────────────────────────────────────────────────
@test "fleet HALT brakes any unit" {
  set_halt "$CLAUDE_CONFIG_DIR/HALT" fleet
  run fire s-1 a-1 Read
  [[ "$output" == *'"permissionDecision":"deny"'* ]] || false
  [[ "$output" == *'HALT fleet'* ]]
}

@test "session HALT brakes that session only" {
  set_halt "$CLAUDE_CONFIG_DIR/HALT.d/s-1" session
  run fire s-1 '' Bash
  [[ "$output" == *'"deny"'* ]] || false
  run fire s-2 '' Bash
  [ -z "$output" ]
}

@test "unit HALT brakes that agent only" {
  set_halt "$CLAUDE_CONFIG_DIR/HALT.d/a-1" unit
  run fire s-1 a-1 Grep
  [[ "$output" == *'"deny"'* ]] || false
  run fire s-1 a-2 Grep
  [ -z "$output" ]
}

@test "reaches the classes that traverse no hook today — Read, Grep, Task, Workflow" {
  set_halt "$CLAUDE_CONFIG_DIR/HALT" fleet
  for t in Read Grep Glob Task Workflow WebFetch; do
    run fire s-1 a-1 "$t"
    [[ "$output" == *'"deny"'* ]] || { echo "not braked on $t"; return 1; }
  done
}

# ── the stamp (§5.2 Stamp) ──────────────────────────────────────────────────────────────────────
@test "every deny stamps units/<unit_id>.halted — without it a braked run renders completed" {
  set_halt "$CLAUDE_CONFIG_DIR/HALT" fleet
  run fire s-1 a-1 Bash
  [ -s "$CLAUDE_CONFIG_DIR/units/a-1.halted" ]
  run grep -c fleet "$CLAUDE_CONFIG_DIR/units/a-1.halted"
  [ "$output" -eq 1 ]
}

@test "a main session with no agent_id stamps under its session id" {
  set_halt "$CLAUDE_CONFIG_DIR/HALT" fleet
  run fire s-9 '' Bash
  [ -s "$CLAUDE_CONFIG_DIR/units/s-9.halted" ]
}

@test "the stamp accumulates one line per denied call" {
  set_halt "$CLAUDE_CONFIG_DIR/HALT" fleet
  fire s-1 a-1 Bash >/dev/null; fire s-1 a-1 Read >/dev/null; fire s-1 a-1 Grep >/dev/null
  run wc -l < "$CLAUDE_CONFIG_DIR/units/a-1.halted"
  [ "${output// /}" -eq 3 ]
}

# ── the ledger (§5.2 Register / §5.3 the namespace) ─────────────────────────────────────────────
@test "first tool call carrying agent_id writes one ledger row, and it is valid JSON" {
  run fire s-1 a-7 Bash
  [ -s "$CLAUDE_CONFIG_DIR/logs/units.jsonl" ]
  run jq -e -r '.unit_id' "$CLAUDE_CONFIG_DIR/logs/units.jsonl"
  [ "$output" = "a-7" ]
  run jq -e -r '.agent_type' "$CLAUDE_CONFIG_DIR/logs/units.jsonl"
  [ "$output" = "workflow-subagent" ]
}

@test "the ledger row is written once per unit, not once per tool call" {
  fire s-1 a-7 Bash >/dev/null; fire s-1 a-7 Read >/dev/null; fire s-1 a-7 Grep >/dev/null
  run wc -l < "$CLAUDE_CONFIG_DIR/logs/units.jsonl"
  [ "${output// /}" -eq 1 ]
}

@test "the ledger registers on the ALLOW path — an unbraked unit is the one most needing a name" {
  run fire s-1 a-7 Bash
  [ -z "$output" ]
  [ -s "$CLAUDE_CONFIG_DIR/logs/units.jsonl" ]
}

@test "a call with no agent_id writes no ledger row" {
  run fire s-1 '' Bash
  [ ! -e "$CLAUDE_CONFIG_DIR/logs/units.jsonl" ]
}

@test "two units append two distinct rows" {
  fire s-1 a-1 Bash >/dev/null; fire s-1 a-2 Bash >/dev/null
  run jq -s -r '[.[].unit_id] | join(",")' "$CLAUDE_CONFIG_DIR/logs/units.jsonl"
  [ "$output" = "a-1,a-2" ]
}

# ── the exemption (§5.2 "the cure must not be blocked by the flag") ─────────────────────────────
@test "CC_UNIT_GATE_EXEMPT matching the session id allows through a fleet HALT" {
  set_halt "$CLAUDE_CONFIG_DIR/HALT" fleet
  run env CC_UNIT_GATE_EXEMPT=s-1 bash -c "$(declare -f payload); payload s-1 '' Bash | bash '$HOOK'"
  [ -z "$output" ]
}

@test "the exemption is EQUALITY, not truthiness — a bare value exempts nobody" {
  set_halt "$CLAUDE_CONFIG_DIR/HALT" fleet
  run env CC_UNIT_GATE_EXEMPT=1 bash -c "$(declare -f payload); payload s-1 '' Bash | bash '$HOOK'"
  [[ "$output" == *'"deny"'* ]]
}

@test "the session that SET the brake is not braked by it — the setter can always clear" {
  mkdir -p "$CLAUDE_CONFIG_DIR"
  printf 'ts=2026-09-09T00:00:00Z\nscope=fleet\nexempt_session=s-desk\n' > "$CLAUDE_CONFIG_DIR/HALT"
  run fire s-desk '' Bash
  [ -z "$output" ]
  run fire s-other '' Bash
  [[ "$output" == *'"deny"'* ]]
}

@test "cc-halt --selftest is an oracle that can go RED, not a fail-safe that always looks calm" {
  run bash "$REPO/bin/cc-halt" --selftest
  [ "$status" -eq 0 ]
  # ...and it convicts a gate that denies unconditionally. Without this the selftest could be
  # `exit 0` and nothing would notice (MEMORY: fail-safe-default-mimics-the-healthy-state).
  mkdir -p "$BATS_TEST_TMPDIR/mut/hooks" "$BATS_TEST_TMPDIR/mut/bin"
  printf '#!/bin/bash\nprintf %s\n' \
    "'{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\"}}'" \
    > "$BATS_TEST_TMPDIR/mut/hooks/unit-gate.sh"
  chmod +x "$BATS_TEST_TMPDIR/mut/hooks/unit-gate.sh"
  cp "$REPO/bin/cc-halt" "$BATS_TEST_TMPDIR/mut/bin/cc-halt"
  run bash "$BATS_TEST_TMPDIR/mut/bin/cc-halt" --selftest
  [ "$status" -ne 0 ]
}

# ── the identity reads, and the two ways they could be poisoned ─────────────────────────────────
@test "an agent_id INSIDE tool_input is not read as the caller's identity" {
  # tool_input carries whole briefs and arbitrary tool parameters; a regex over the full payload
  # would read one of them as the unit's address and brake — or mis-attribute — an innocent session
  # (MEMORY: pgrep-f-matches-agent-briefs · fixture-identifier-shape-collapses-two-spaces).
  #
  # 🚨 THE FIXTURE SHAPE IS THE WHOLE TEST. The first version of this case put the poison in a
  # STRING (`"command":"echo \"agent_id\": \"a-evil\""`) and was green with the guard REMOVED —
  # an equivalence guard, not a red-proof. JSON escapes a string's inner quotes, so `\"agent_id\"`
  # can never match a regex anchored on `"agent_id"`; the fixture had made the axis inexpressible.
  # The reachable poison is a NESTED OBJECT, where the quotes are real — and it is not exotic: an
  # Agent-tool call or an MCP tool taking an agent id parameter has exactly this shape.
  set_halt "$CLAUDE_CONFIG_DIR/HALT.d/a-evil" unit
  run fire s-1 '' Bash '{"agent_id":"a-evil","agent_type":"impostor"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$CLAUDE_CONFIG_DIR/logs/units.jsonl" ]
}

@test "a dot-dot session id cannot brake through HALT.d/.., and does not error either" {
  # `..` passes any sane charset and names a DIRECTORY, which [ -e ] reports present — a brake
  # nobody set, on every session at once.
  #
  # `[ "$status" -eq 0 ]` is not decoration: without the guard the hook resolves HALT.d/.. to the
  # config dir, then tries to READ that directory as the halt file and exits 1 with no output. On a
  # `*` matcher that is a non-blocking error on every single tool call the fleet makes. Asserting
  # only on $output cannot tell that apart from correct silence — measured, the case was green
  # against the mutant until this line was added.
  mkdir -p "$CLAUDE_CONFIG_DIR/HALT.d"
  run fire .. '' Bash
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── fail-open, asserted rather than assumed ─────────────────────────────────────────────────────
@test "an unparseable payload cannot manufacture a brake — nothing set, nothing said" {
  # This hook sees every tool call of every class, so a fail-CLOSED bug here denies the whole
  # machine and the only cure (editing settings.json) is itself a tool call.
  run bash -c "printf '' | bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash -c "printf 'not json at all' | bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "an unparseable payload cannot DISSOLVE one either — garbage is not a brake bypass" {
  # The other half, and the half an early `[ -n "$PAYLOAD" ] || exit 0` silently gave away: the
  # fleet check needs no identity, so a payload the hook cannot read is still a tool call the
  # operator has told to stop. Allow-on-unknown is right for what the hook must INFER and wrong for
  # what the operator has already DECLARED.
  set_halt "$CLAUDE_CONFIG_DIR/HALT" fleet
  run bash -c "printf 'not json at all' | bash '$HOOK'"
  [[ "$output" == *'"deny"'* ]] || false
  run bash -c "printf '' | bash '$HOOK'"
  [[ "$output" == *'"deny"'* ]]
}

@test "the deny says BRAKE, not stop, and names the clearing command" {
  set_halt "$CLAUDE_CONFIG_DIR/HALT" fleet
  run fire s-1 a-1 Bash
  [[ "$output" == *"BRAKE"* ]] || false
  [[ "$output" == *"cc-halt clear"* ]] || false
  run jq -e -r '.hookSpecificOutput.permissionDecision' <<<"$output"
  [ "$output" = "deny" ]
}

# ── cc-halt round trip ──────────────────────────────────────────────────────────────────────────
@test "cc-halt sets and clears each scope, and the hook agrees with it" {
  run bash "$REPO/bin/cc-halt" --fleet
  [ "$status" -eq 0 ]
  run fire s-1 '' Bash
  [[ "$output" == *'"deny"'* ]] || false
  run bash "$REPO/bin/cc-halt" clear fleet
  [ "$status" -eq 0 ]
  run fire s-1 '' Bash
  [ -z "$output" ]
}

@test "cc-halt refuses an unusable id rather than writing a path it cannot mean" {
  run bash "$REPO/bin/cc-halt" ".."
  [ "$status" -eq 2 ]
  run bash "$REPO/bin/cc-halt" "a/b"
  [ "$status" -eq 2 ]
}

# ── the migration's verifier: POSITION, not presence ─────────────────────────────────────────────
@test "0024 --verify goes RED when the entry is merely present but not FIRST" {
  local s="$CLAUDE_CONFIG_DIR/settings.json"
  jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"x"}]}],
                 PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"b"}]},
                             {matcher:"*",hooks:[{type:"command",command:"~/.claude/hooks/unit-gate.sh"}]}]}}' > "$s"
  run env CC_CLAUDE_DIR="$CLAUDE_CONFIG_DIR" bash "$MIG" --verify
  [ "$status" -ne 0 ]
  jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"x"}]}],
                 PreToolUse:[{matcher:"*",hooks:[{type:"command",command:"~/.claude/hooks/unit-gate.sh"}]},
                             {matcher:"Bash",hooks:[{type:"command",command:"b"}]}]}}' > "$s"
  run env CC_CLAUDE_DIR="$CLAUDE_CONFIG_DIR" bash "$MIG" --verify
  [ "$status" -eq 0 ]
}

@test "0024 --conflict reports a FOREIGN command squatting the * matcher" {
  local s="$CLAUDE_CONFIG_DIR/settings.json"
  jq -n '{hooks:{PreToolUse:[{matcher:"*",hooks:[{type:"command",command:"~/.claude/hooks/other.sh"}]}]}}' > "$s"
  run env CC_CLAUDE_DIR="$CLAUDE_CONFIG_DIR" bash "$MIG" --conflict
  [ "$status" -eq 0 ]
  jq -n '{hooks:{PreToolUse:[{matcher:"*",hooks:[{type:"command",command:"~/.claude/hooks/unit-gate.sh"}]}]}}' > "$s"
  run env CC_CLAUDE_DIR="$CLAUDE_CONFIG_DIR" bash "$MIG" --conflict
  [ "$status" -ne 0 ]
}
