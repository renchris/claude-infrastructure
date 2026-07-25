#!/usr/bin/env bash
# check09_subagent.sh — #9 Research subagents (a fire-and-forget subagent returns).
# ─────────────────────────────────────────────────────────────────────────────
# Research subagents (Agent tool, no team_name) are the fan-out workhorse. The gate proves one
# spawns and RETURNS under the candidate — self-evidencing via a unique marker (SUBAGENT_OK) that can
# only appear if the subagent actually ran, with modelUsage still carrying the model (no demotion).
# EXPENSIVE (spawns a subagent) → honors GATE_SPAWN; retries the flaky classifier up to GATE_RETRIES.
# shellcheck shell=bash

# One probe attempt; rc 0 iff SUBAGENT_OK is in the result AND modelUsage carries $GATE_MODEL.
# shellcheck disable=SC2317  # invoked by name through `retry`, not statically
_gate_subagent_probe() {
  local cfg="$1" out_file="$2" out=""
  out="$(gate_headless "$cfg" "$GATE_MODEL" \
    "Use the Agent tool (NO team_name — a fire-and-forget subagent) to spawn one subagent that returns exactly the string SUBAGENT_OK. Then reply with only what it returned." \
    --permission-mode auto)"
  printf '%s' "$out" >"$out_file"
  printf '%s' "$out" | grep -q 'SUBAGENT_OK' || return 1
  printf '%s' "$out" | json_has_model "$GATE_MODEL"
}

check_09() {
  if [ "${GATE_SPAWN:-1}" != 1 ]; then
    emit_result 09 subagent-run SKIP "GATE_SPAWN=0 (deferred to lead baseline)" ""
    return 0
  fi

  local acct cfg out_file=""
  acct="$(gate_primary_account)"
  cfg="$(gate_cfg_for "$acct")"
  if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
    emit_result 09 subagent-run SKIP "no config dir for account '$acct' ($cfg)" ""
    return 0
  fi

  out_file="$(mktemp)"
  if retry "${GATE_RETRIES:-3}" _gate_subagent_probe "$cfg" "$out_file"; then
    emit_result 09 subagent-run PASS \
      "subagent ran + returned (SUBAGENT_OK in result) + modelUsage carries $GATE_MODEL (no demotion)" \
      "modelUsage=$(json_get modelUsage <"$out_file")"
  else
    emit_result 09 subagent-run FAIL \
      "no SUBAGENT_OK in result, or model demoted/errored, after ${GATE_RETRIES:-3} tries" \
      "is_error=$(json_get is_error <"$out_file") result=$(json_get result <"$out_file" | head -c 200)"
  fi
  rm -f "$out_file"
  return 0
}
