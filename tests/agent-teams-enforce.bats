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
  # HERMETICITY (scripts/test-hermeticity-lint.sh RULE 1). The hook now carries a machine-capacity
  # admission term whose every evaluation appends a row to the IDL; unfixtured, this suite would
  # write test rows into the OPERATOR'S live decision ledger — the one §9.5.1 requires be
  # trustworthy enough to compute an admit/refuse ratio from.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # DETERMINISM: the capacity term reads the REAL box (it resolves its library script-relative, so
  # it is live here). Left on, every assertion below would depend on the load and free memory of
  # whatever machine runs the suite — a deny could come from capacity rather than from the policy
  # under test, and the case would still "pass" for the wrong reason. Capacity has its own suites
  # (capacity-admit.bats, capacity-admit-coverage.bats); this one pins the POLICY behaviour.
  export CC_ADMIT_GATE=off
  # Same hermeticity argument for the spawn-budget term: it keys a counter on .session_id under
  # $HOME/.claude/autonomy/spawn-budget. $HOME is already fixtured above, but the seam is pinned
  # explicitly so a case that sets its own HOME cannot silently charge the operator's real budget.
  export CC_SPAWN_STATE_DIR="$BATS_TEST_TMPDIR/spawn-budget"
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
  ! has "$output" "OVER CAP" || false
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

# ── SPAWN BUDGET + DEPTH CAP (master 66ef300dd0b4 — fleet footprint) ─────────────
# The cap is THE actuator term: one dispatch historically reached 224 spawns / 167 sessions with
# nothing counting them, and that horde is the measured ignition of the kernel watchdog panics.
# It sits ABOVE the read-only-type skip on purpose — a 224-wide fan-out is mostly Explore-class
# research subagents, so a cap below that skip would be blind to the only shape that caused harm.

# $1=session_id  $2=transcript_path  $3=subagent_type  [$4=prompt]
run_spawn() {
  jq -n --arg s "$1" --arg t "$2" --arg st "$3" --arg p "${4:-read and inspect the files}" \
    '{session_id:$s,transcript_path:$t,tool_input:{subagent_type:$st,prompt:$p}}' | bash "$HOOK"
}

@test "spawn budget: under cap → allow, and the counter advances" {
  CC_SPAWN_MAX_PER_SESSION=3 run run_spawn "sid-under" "/tmp/sid-under.jsonl" Explore
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" != deny ]
  [ "$(cat "$CC_SPAWN_STATE_DIR/sid-under.count")" = 1 ]
}

@test "spawn budget: the (cap+1)th attempt in one session is DENIED" {
  for _ in 1 2 3; do CC_SPAWN_MAX_PER_SESSION=3 run_spawn "sid-cap" "/tmp/sid-cap.jsonl" Explore >/dev/null; done
  CC_SPAWN_MAX_PER_SESSION=3 run run_spawn "sid-cap" "/tmp/sid-cap.jsonl" Explore
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = deny ]
  has "$output" "SPAWN BUDGET EXHAUSTED"
  printf '%s' "$output" | jq -e . >/dev/null
}

# The load-bearing property, and the reason the key is .session_id: a subagent does NOT get its
# own session id (measured 2026-08-09 — its transcript rows and PostToolUse audit lines both carry
# the LEAD's id), so lead + every descendant charge ONE account. Without this, a fan-out of N
# agents each spawning M more spends N*M budgets of 1 and the cap is decorative.
@test "spawn budget: descendants of one session share the lead's account" {
  CC_SPAWN_MAX_PER_SESSION=2 run_spawn "sid-share" "/tmp/sid-share.jsonl" Explore >/dev/null
  CC_SPAWN_MAX_PER_SESSION=2 run_spawn "sid-share" "/proj/sid-share/subagents/agent-aa.jsonl" Explore >/dev/null
  CC_SPAWN_MAX_PER_SESSION=2 run run_spawn "sid-share" "/proj/sid-share/subagents/agent-bb.jsonl" Explore
  [ "$(decision "$output")" = deny ]
  has "$output" "SPAWN BUDGET EXHAUSTED"
}

@test "spawn budget: a DENIED attempt is still charged (a retry storm reaches the wall faster)" {
  for _ in 1 2 3 4; do CC_SPAWN_MAX_PER_SESSION=2 run_spawn "sid-charge" "/tmp/x.jsonl" Explore >/dev/null; done
  [ "$(cat "$CC_SPAWN_STATE_DIR/sid-charge.count")" = 4 ]
}

@test "spawn budget: sessions do not spend each other's account" {
  for _ in 1 2 3; do CC_SPAWN_MAX_PER_SESSION=3 run_spawn "sid-a" "/tmp/a.jsonl" Explore >/dev/null; done
  CC_SPAWN_MAX_PER_SESSION=3 run run_spawn "sid-b" "/tmp/b.jsonl" Explore
  [ "$(decision "$output")" != deny ]
}

@test "spawn budget: the cap binds ABOVE the read-only-type skip (Explore is not exempt)" {
  for _ in 1 2; do CC_SPAWN_MAX_PER_SESSION=2 run_spawn "sid-ro" "/tmp/ro.jsonl" Explore >/dev/null; done
  CC_SPAWN_MAX_PER_SESSION=2 run run_spawn "sid-ro" "/tmp/ro.jsonl" Explore "READ-ONLY RESEARCH: explore and report"
  [ "$(decision "$output")" = deny ]
  has "$output" "SPAWN BUDGET EXHAUSTED"
}

@test "depth cap: a subagent transcript at/over the depth cap is DENIED" {
  meta="$BATS_TEST_TMPDIR/proj/subagents"; mkdir -p "$meta"
  printf '%s\n' '{"agentType":"Explore","spawnDepth":2}' > "$meta/agent-deep.meta.json"
  CC_SPAWN_MAX_DEPTH=2 run run_spawn "sid-deep" "$meta/agent-deep.jsonl" Explore
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = deny ]
  has "$output" "SPAWN DEPTH CAP"
  printf '%s' "$output" | jq -e . >/dev/null
}

@test "depth cap: depth is read from the harness's own meta, not inferred from the prompt" {
  meta="$BATS_TEST_TMPDIR/proj2/subagents"; mkdir -p "$meta"
  printf '%s\n' '{"agentType":"Explore","spawnDepth":1}' > "$meta/agent-ok.meta.json"
  CC_SPAWN_MAX_DEPTH=2 run run_spawn "sid-shallow" "$meta/agent-ok.jsonl" Explore
  [ "$(decision "$output")" != deny ]
  grep -q '"basis":"depth-read"' "$CC_ADMIT_IDL"
  grep -q '"depth":1' "$CC_ADMIT_IDL"
}

# A subagent transcript with NO readable meta still proves we are below the top level. The two
# states must stay distinguishable in the ledger — one value meaning both "answered no" and
# "could not ask" is what fabricated 80/156 findings elsewhere in this repo
# (memory: sensor-default-off-makes-blindness-the-shipping-path).
@test "depth cap: an unreadable meta INFERS depth 1 and says so, never reads as top level" {
  CC_SPAWN_MAX_DEPTH=2 run run_spawn "sid-nometa" "/nowhere/subagents/agent-zz.jsonl" Explore
  [ "$(decision "$output")" != deny ]
  grep -q '"basis":"depth-inferred"' "$CC_ADMIT_IDL"
  ! grep -q '"sid":"sid-nometa".*"basis":"depth-toplevel"' "$CC_ADMIT_IDL" || false
}

@test "instrumentation: every evaluation emits exactly one spawn-budget row (no silent branch)" {
  run_spawn "sid-row" "/tmp/row.jsonl" Explore >/dev/null
  [ "$(grep -c '"gate":"spawn-budget"' "$CC_ADMIT_IDL")" = 1 ]
  grep -q '"transcript":"/tmp/row.jsonl"' "$CC_ADMIT_IDL"
}

# Fail-OPEN on every unknown: a gate that cannot identify the session must not become a fleet-wide
# refusal (capacity-admit's convention). But it must be LOUD about it in the ledger.
@test "no session_id → admit, and the ledger records that the spawn went UNGATED" {
  CC_SPAWN_MAX_PER_SESSION=1 run_spawn "" "/tmp/n.jsonl" Explore >/dev/null
  CC_SPAWN_MAX_PER_SESSION=1 run run_spawn "" "/tmp/n.jsonl" Explore
  [ "$(decision "$output")" != deny ]
  grep -q 'UNGATED for budget' "$CC_ADMIT_IDL"
}

@test "CC_SPAWN_GATE=off disables the term entirely and records gate-off" {
  export CC_SPAWN_GATE=off
  for _ in 1 2 3; do CC_SPAWN_MAX_PER_SESSION=1 run_spawn "sid-off" "/tmp/o.jsonl" Explore >/dev/null; done
  CC_SPAWN_MAX_PER_SESSION=1 run run_spawn "sid-off" "/tmp/o.jsonl" Explore
  [ "$(decision "$output")" != deny ]
  grep -q '"detail":"gate-off"' "$CC_ADMIT_IDL"
  [ ! -f "$CC_SPAWN_STATE_DIR/sid-off.count" ]
}

# A malformed cap must ADMIT at the default, never refuse and never crash under set -u.
@test "malformed cap falls back to the default rather than refusing" {
  CC_SPAWN_MAX_PER_SESSION="not-a-number" run run_spawn "sid-bad" "/tmp/bad.jsonl" Explore
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" != deny ]
}
