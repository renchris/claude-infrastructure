#!/usr/bin/env bash
# check01_binary.sh — #1 Binary registers the model (the LOUD-fail floor).
# ─────────────────────────────────────────────────────────────────────────────
# `--model X --print` must exit 0 AND come back with modelUsage carrying X (no demotion, no error).
# This is the check that fails LOUDLY when the binary predates the model — the exact reason CC 2.1.215
# could not run claude-opus-5. It is also the check the known-bad baseline case must trip.
#
# Reference probe: this file is the CONTRACT EXEMPLAR for teammates — one `check_NN`, self-evidencing
# (asserts on modelUsage, not a claim), emits exactly once, returns 0.
# shellcheck shell=bash

check_01() {
  local acct cfg out
  acct="$(gate_primary_account)"
  cfg="$(gate_cfg_for "$acct")"

  if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
    emit_result 01 binary-registers SKIP "no config dir for account '$acct' ($cfg)" ""
    return 0
  fi

  if ! out="$(gate_headless "$cfg" "$GATE_MODEL" "Reply with exactly: ok")"; then
    emit_result 01 binary-registers FAIL \
      "binary returned NO json for --model $GATE_MODEL (predates the model / hard error)" \
      "$(printf '%s' "$out" | head -c 400)"
    return 0
  fi

  if printf '%s' "$out" | json_has_model "$GATE_MODEL"; then
    emit_result 01 binary-registers PASS \
      "modelUsage carries $GATE_MODEL, is_error=false (registered, no demotion)" \
      "modelUsage=$(printf '%s' "$out" | json_get modelUsage)"
  else
    emit_result 01 binary-registers FAIL \
      "binary did NOT register $GATE_MODEL (empty/other modelUsage, demoted, or is_error)" \
      "is_error=$(printf '%s' "$out" | json_get is_error) modelUsage=$(printf '%s' "$out" | json_get modelUsage)"
  fi
  return 0
}
