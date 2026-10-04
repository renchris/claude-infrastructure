#!/usr/bin/env bats
# PLAN GUARD is sent once per (session_id, agent_id, plan file), not on every plan Edit.
#
# The defect (claude-api audit 2026-10-04, hooks-a-09): hooks/backup-before-write.sh re-injected the
# same ~870-char PLAN GUARD + PLAN UPDATE RULES on every Edit of a plan file — 598 fires and ~190K
# tokens in 7 days, 57% of them repeats inside one context. The fix keys a marker on
# (session_id|agent_id, file) under CC_PLAN_GUARD_STATE_DIR. agent_id is in the key because an
# in-process subagent shares its lead's session_id but not its context. No session id ⇒ always emit.
# Write (OVERWRITE GUARD) stays per call. Evidence: docs/research/claude-api-audit-2026-10-04/.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/backup-before-write.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_PLAN_GUARD_STATE_DIR="$BATS_TEST_TMPDIR/plan-guard"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/proj/docs/plans"
  PLAN="$BATS_TEST_TMPDIR/proj/docs/plans/ALPHA_PLAN.md"
  PLAN2="$BATS_TEST_TMPDIR/proj/docs/plans/BETA_PLAN.md"
  printf '# Alpha\n\nline\n' > "$PLAN"
  printf '# Beta\n' > "$PLAN2"
}

# errexit-live helpers (a bare `[[ ]]` mid-body is exempt from errexit and would pass vacuously)
has()  { printf '%s' "$1" | grep -qF -- "$2" || { printf 'expected [%s] in:\n%s\n' "$2" "$1" >&2; return 1; }; }
none() { [ -z "$1" ] || { printf 'expected no output, got:\n%s\n' "$1" >&2; return 1; }; }

call() { # call <tool> <file> <session_id> [agent_id] → hook stdout
  jq -nc --arg t "$1" --arg f "$2" --arg s "$3" --arg a "${4:-}" \
    '{tool_name:$t, session_id:$s, tool_input:{file_path:$f, content:"body", old_string:"a", new_string:"b"}}
     + (if $a == "" then {} else {agent_id:$a} end)' \
    | bash "$HOOK"
}

@test "same session, agent and plan file: the second Edit emits nothing" {
  out="$(call Edit "$PLAN" s1)"
  has "$out" "PLAN GUARD: Editing plan file 'ALPHA_PLAN.md'"
  has "$out" "PLAN UPDATE RULES"
  out="$(call Edit "$PLAN" s1)"
  none "$out"
  out="$(call Edit "$PLAN" s1 agentA)"
  has "$out" "PLAN GUARD"
  out="$(call Edit "$PLAN" s1 agentA)"
  none "$out"
}

@test "a new agent_id, a new session or a new plan file each emits again" {
  has "$(call Edit "$PLAN" s1)" "PLAN GUARD"
  has "$(call Edit "$PLAN" s1 agentB)" "PLAN GUARD"
  has "$(call Edit "$PLAN" s2)" "PLAN GUARD"
  has "$(call Edit "$PLAN2" s1)" "PLAN GUARD: Editing plan file 'BETA_PLAN.md'"
}

@test "an empty session_id always emits" {
  has "$(call Edit "$PLAN" "")" "PLAN GUARD"
  has "$(call Edit "$PLAN" "")" "PLAN GUARD"
  has "$(call Edit "$PLAN" "" agentA)" "PLAN GUARD"
}

@test "Write keeps OVERWRITE GUARD and the plan rules on every call" {
  has "$(call Edit "$PLAN" s1)" "PLAN GUARD"
  out="$(call Write "$PLAN" s1)"
  has "$out" "OVERWRITE GUARD"
  has "$out" "PLAN UPDATE RULES"
  has "$(call Write "$PLAN" s1)" "OVERWRITE GUARD"
}

@test "a marker older than 7 days is collected and the guard emits again" {
  has "$(call Edit "$PLAN" s1)" "PLAN GUARD"
  markers=("$CC_PLAN_GUARD_STATE_DIR"/*)
  [ "${#markers[@]}" -eq 1 ] && [ -f "${markers[0]}" ] || false
  touch -t 202001010000 "${markers[0]}"
  has "$(call Edit "$PLAN" s1)" "PLAN GUARD"
  # re-minted fresh, not left stale: the same key, with a current mtime
  [ -f "${markers[0]}" ]
  [ -z "$(find "$CC_PLAN_GUARD_STATE_DIR" -type f -mtime +7)" ]
}
