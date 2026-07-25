#!/usr/bin/env bash
# check11_permission.sh — #11 Permission-mode non-blocking (benign).
# ─────────────────────────────────────────────────────────────────────────────
# Distinct from #3 (which proves auto-mode DRIVES a turn): this proves auto-mode
# does NOT hard-block a BENIGN command. CC 216/219 moved the dangerous cases
# (rm -rf, backgrounding `&`, suspicious paths) onto the classifier — but a plainly
# benign `echo` must still auto-pass with no denial. Self-evidencing on the turn's
# artifact:
#   • is_error         == false
#   • permission_denials == []          (benign command was NOT blocked)
#   • result            contains BENIGN_OK
# Classifier is transiently flaky → wrapped in `retry $GATE_RETRIES`.
# shellcheck shell=bash

# _check11_probe <cfg> <outfile> : run the benign auto-mode turn, record raw JSON
# to <outfile>, return 0 iff it ran with no denial and echoed BENIGN_OK.
_check11_probe() {
  local cfg="$1" outfile="$2" out is_error denials result
  out="$(gate_headless "$cfg" "$GATE_MODEL" \
        "Use the Bash tool to run exactly: echo BENIGN_OK — then reply with only its stdout." \
        --permission-mode auto)"
  printf '%s' "$out" >"$outfile"
  is_error="$(printf '%s' "$out" | json_get is_error)"
  case "$is_error" in False|false) ;; *) return 1 ;; esac
  denials="$(printf '%s' "$out" | json_get permission_denials)"
  [ "$denials" = "[]" ] || return 1
  result="$(printf '%s' "$out" | json_get result)"
  case "$result" in *BENIGN_OK*) ;; *) return 1 ;; esac
  return 0
}

check_11() {
  local acct cfg tmp out
  acct="$(gate_primary_account)"
  cfg="$(gate_cfg_for "$acct")"

  if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
    emit_result 11 permission-nonblock SKIP "no config dir for account '$acct' ($cfg)" ""
    return 0
  fi

  tmp="$(mktemp)"
  if retry "$GATE_RETRIES" _check11_probe "$cfg" "$tmp"; then
    out="$(cat "$tmp")"; rm -f "$tmp"
    emit_result 11 permission-nonblock PASS \
      "auto-mode did NOT block a benign command: is_error=false, permission_denials=[], result~BENIGN_OK" \
      "result=$(printf '%s' "$out" | json_get result) permission_denials=$(printf '%s' "$out" | json_get permission_denials)"
  else
    out="$(cat "$tmp")"; rm -f "$tmp"
    emit_result 11 permission-nonblock FAIL \
      "auto-mode blocked/failed a BENIGN command (is_error, denial, or missing BENIGN_OK)" \
      "is_error=$(printf '%s' "$out" | json_get is_error) permission_denials=$(printf '%s' "$out" | json_get permission_denials) result=$(printf '%s' "$out" | json_get result)"
  fi
  return 0
}
