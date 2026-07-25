#!/usr/bin/env bash
# check07_teams.sh — #7 Agent-Teams spawn (a teammate ACTUALLY runs, no demotion).
# ─────────────────────────────────────────────────────────────────────────────
# Agent Teams are the DEFAULT for all implementation work, so the gate must prove a real teammate
# spawns AND executes under the candidate — not that the tool merely exists. Self-evidencing: the
# teammate echoes a unique marker (TEAMMATE_OK) that can only appear if it truly ran; we assert the
# marker is in the session result AND modelUsage still carries the model under test (no silent
# demotion to a fallback). EXPENSIVE (spawns a teammate) → honors GATE_SPAWN; retries the flaky
# auto-mode classifier up to GATE_RETRIES.
# shellcheck shell=bash

# One probe attempt; rc 0 iff TEAMMATE_OK is in the result AND modelUsage carries $GATE_MODEL.
# shellcheck disable=SC2317  # invoked by name through `retry`, not statically
_gate_teams_probe() {
  local cfg="$1" out_file="$2" out=""
  out="$(gate_headless "$cfg" "$GATE_MODEL" \
    "Use the Agent tool to spawn ONE teammate (team_name gate-probe, model opus) that runs the Bash command: echo TEAMMATE_OK — and returns only that. Then stop." \
    --permission-mode auto)"
  printf '%s' "$out" >"$out_file"
  printf '%s' "$out" | grep -q 'TEAMMATE_OK' || return 1
  printf '%s' "$out" | json_has_model "$GATE_MODEL"
}

check_07() {
  if [ "${GATE_SPAWN:-1}" != 1 ]; then
    emit_result 07 teams-spawn SKIP "GATE_SPAWN=0 (deferred to lead baseline)" ""
    return 0
  fi

  local acct cfg out_file=""
  acct="$(gate_primary_account)"
  cfg="$(gate_cfg_for "$acct")"
  if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
    emit_result 07 teams-spawn SKIP "no config dir for account '$acct' ($cfg)" ""
    return 0
  fi

  out_file="$(mktemp)"
  if retry "${GATE_RETRIES:-3}" _gate_teams_probe "$cfg" "$out_file"; then
    emit_result 07 teams-spawn PASS \
      "teammate ran (TEAMMATE_OK in result) + modelUsage carries $GATE_MODEL (no demotion)" \
      "modelUsage=$(json_get modelUsage <"$out_file")"
  else
    emit_result 07 teams-spawn FAIL \
      "no TEAMMATE_OK in result, or model demoted/errored, after ${GATE_RETRIES:-3} tries" \
      "is_error=$(json_get is_error <"$out_file") result=$(json_get result <"$out_file" | head -c 200)"
  fi
  rm -f "$out_file"
  return 0
}
