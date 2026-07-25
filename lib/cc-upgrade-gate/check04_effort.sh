#!/usr/bin/env bash
# check04_effort.sh — #4 Effort ladder.
# ─────────────────────────────────────────────────────────────────────────────
# The binary must ACCEPT Opus 5's effort ladder — high (its own default), xhigh,
# and max. A rejected effort flag surfaces as is_error=true / no JSON at all, so
# "accepted" is asserted on the artifact: JSON came back with is_error=false. The
# default rung (high) is held to the stronger bar — the model must actually
# register in modelUsage (no silent demotion). Prompts are trivial to bound cost.
# shellcheck shell=bash

# _effort_ok <cfg> <effort> : 0 iff the binary ACCEPTED the flag (returned JSON,
# is_error=false). Transport failure (no JSON) → gate_headless rc≠0 → 1.
_effort_ok() {
  local out ie
  out="$(gate_headless "$1" "$GATE_MODEL" "Reply with exactly: ok" --effort "$2")" || return 1
  ie="$(printf '%s' "$out" | json_get is_error)"
  case "$ie" in False|false) return 0 ;; *) return 1 ;; esac
}

check_04() {
  local acct cfg out_high failed="" lvl
  acct="$(gate_primary_account)"
  cfg="$(gate_cfg_for "$acct")"

  if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
    emit_result 04 effort-ladder SKIP "no config dir for account '$acct' ($cfg)" ""
    return 0
  fi

  # high = Opus 5's own default rung: strongest bar, the model must register.
  out_high="$(gate_headless "$cfg" "$GATE_MODEL" "Reply with exactly: ok" --effort high)"
  if ! printf '%s' "$out_high" | json_has_model "$GATE_MODEL"; then
    emit_result 04 effort-ladder FAIL \
      "--effort high rejected or demoted (default rung must run on $GATE_MODEL)" \
      "is_error=$(printf '%s' "$out_high" | json_get is_error) modelUsage=$(printf '%s' "$out_high" | json_get modelUsage)"
    return 0
  fi

  # xhigh + max: the binary must ACCEPT each flag (JSON returned, is_error=false).
  for lvl in xhigh max; do
    _effort_ok "$cfg" "$lvl" || failed="$failed $lvl"
  done
  failed="${failed# }"

  if [ -n "$failed" ]; then
    emit_result 04 effort-ladder FAIL \
      "effort ladder rung(s) rejected: $failed" \
      "high=accepted(model registered) rejected=[$failed]"
  else
    emit_result 04 effort-ladder PASS \
      "effort ladder accepted on $GATE_MODEL: high(default,+model) xhigh max" \
      "modelUsage=$(printf '%s' "$out_high" | json_get modelUsage)"
  fi
  return 0
}
