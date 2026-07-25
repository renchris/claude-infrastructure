#!/usr/bin/env bash
# check03_automode.sh — #3 Auto-mode resolution (THE CRUX).
# ─────────────────────────────────────────────────────────────────────────────
# The load-bearing claim: `--permission-mode auto` lets the model actually DRIVE
# a tool turn headlessly — auto-approving a benign Bash call — WITHOUT demotion or
# error. This overturns the old "auto-mode is human-only, can't be live-tested"
# belief. Self-evidencing: the model is told to `echo GATE_OK` via the Bash tool
# and reply with its stdout; the probe asserts on the ARTIFACT of that turn:
#   • is_error         == false        (the run completed)
#   • modelUsage        carries model   (no silent demotion)
#   • permission_denials == []          (the tool was auto-approved, not blocked)
#   • result            contains GATE_OK (a turn was genuinely driven)
# The classifier is transiently flaky → wrapped in `retry $GATE_RETRIES`.
# shellcheck shell=bash

# _check03_probe <cfg> <outfile> : run the auto-mode tool-use turn, record the raw
# JSON to <outfile> (for evidence), return 0 iff the turn was cleanly driven.
_check03_probe() {
  local cfg="$1" outfile="$2" out is_error denials result
  out="$(gate_headless "$cfg" "$GATE_MODEL" \
        "Use the Bash tool to run exactly: echo GATE_OK — then reply with only its stdout." \
        --permission-mode auto)"
  printf '%s' "$out" >"$outfile"
  printf '%s' "$out" | json_has_model "$GATE_MODEL" || return 1
  is_error="$(printf '%s' "$out" | json_get is_error)"
  case "$is_error" in False|false) ;; *) return 1 ;; esac
  denials="$(printf '%s' "$out" | json_get permission_denials)"
  [ "$denials" = "[]" ] || return 1
  result="$(printf '%s' "$out" | json_get result)"
  case "$result" in *GATE_OK*) ;; *) return 1 ;; esac
  return 0
}

check_03() {
  local acct cfg tmp out
  acct="$(gate_primary_account)"
  cfg="$(gate_cfg_for "$acct")"

  if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
    emit_result 03 automode-resolution SKIP "no config dir for account '$acct' ($cfg)" ""
    return 0
  fi

  tmp="$(mktemp)"
  if retry "$GATE_RETRIES" _check03_probe "$cfg" "$tmp"; then
    out="$(cat "$tmp")"; rm -f "$tmp"
    emit_result 03 automode-resolution PASS \
      "auto-mode drove a tool turn on $GATE_MODEL: is_error=false, no demotion, permission_denials=[], result~GATE_OK" \
      "result=$(printf '%s' "$out" | json_get result) num_turns=$(printf '%s' "$out" | json_get num_turns)"
  else
    out="$(cat "$tmp")"; rm -f "$tmp"
    emit_result 03 automode-resolution FAIL \
      "auto-mode did NOT cleanly drive a turn (demotion / denial / error / missing GATE_OK)" \
      "is_error=$(printf '%s' "$out" | json_get is_error) permission_denials=$(printf '%s' "$out" | json_get permission_denials) modelUsage=$(printf '%s' "$out" | json_get modelUsage) result=$(printf '%s' "$out" | json_get result)"
  fi
  return 0
}
