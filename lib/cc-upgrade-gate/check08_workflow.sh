#!/usr/bin/env bash
# check08_workflow.sh — #8 Dynamic Workflows (an agent actually runs; journal result non-null).
# ─────────────────────────────────────────────────────────────────────────────
# We run trivial-but-real workflows; the gate must prove a 1-agent workflow executes under the
# candidate and returns a non-null result — not that the tool merely exists. Self-evidencing: the
# workflow's agent returns a unique marker (WF_OK) that can only appear if the agent truly ran, and
# modelUsage must still carry the model under test (no silent demotion). EXPENSIVE (runs a workflow)
# → honors GATE_SPAWN; retries the flaky auto-mode classifier up to GATE_RETRIES.
# shellcheck shell=bash

# One probe attempt; rc 0 iff WF_OK is in the result AND modelUsage carries $GATE_MODEL.
# shellcheck disable=SC2317  # invoked by name through `retry`, not statically
_gate_workflow_probe() {
  local cfg="$1" out_file="$2" out=""
  out="$(gate_headless "$cfg" "$GATE_MODEL" \
    "Use the Workflow tool to run a ONE-agent workflow whose single agent returns exactly the string WF_OK. Then reply with only the workflow's result." \
    --permission-mode auto)"
  printf '%s' "$out" >"$out_file"
  printf '%s' "$out" | grep -q 'WF_OK' || return 1
  printf '%s' "$out" | json_has_model "$GATE_MODEL"
}

check_08() {
  if [ "${GATE_SPAWN:-1}" != 1 ]; then
    emit_result 08 workflow-run SKIP "GATE_SPAWN=0 (deferred to lead baseline)" ""
    return 0
  fi

  local acct cfg out_file=""
  acct="$(gate_primary_account)"
  cfg="$(gate_cfg_for "$acct")"
  if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
    emit_result 08 workflow-run SKIP "no config dir for account '$acct' ($cfg)" ""
    return 0
  fi

  out_file="$(mktemp)"
  if retry "${GATE_RETRIES:-3}" _gate_workflow_probe "$cfg" "$out_file"; then
    emit_result 08 workflow-run PASS \
      "workflow agent ran (WF_OK in result) + modelUsage carries $GATE_MODEL (non-null journal result)" \
      "modelUsage=$(json_get modelUsage <"$out_file")"
  else
    emit_result 08 workflow-run FAIL \
      "no WF_OK in result, or model demoted/errored, after ${GATE_RETRIES:-3} tries" \
      "is_error=$(json_get is_error <"$out_file") result=$(json_get result <"$out_file" | head -c 200)"
  fi
  rm -f "$out_file"
  return 0
}
