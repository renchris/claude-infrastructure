#!/usr/bin/env bash
# check02_entitlement.sh — #2 Entitlement + budget per account.
# ─────────────────────────────────────────────────────────────────────────────
# The model can register on the binary (check #1) yet an individual account still
# lack the entitlement/budget to actually run it. This walks EVERY account in
# $GATE_ACCOUNTS: an absent config dir (logged-out / not-provisioned) is a SKIP
# for that account (not a regression); a present account must come back with
# modelUsage carrying $GATE_MODEL and is_error=false, or the gate fails closed.
#
# One aggregate result: PASS iff every PRESENT account is entitled (evidence lists
# the entitled + any skipped); FAIL if any present account is not entitled; SKIP
# only in the degenerate case where no account is present at all.
# shellcheck shell=bash

check_02() {
  local acct cfg out entitled="" failed="" skipped=""

  # shellcheck disable=SC2086  # deliberate word-split of the space-separated account list
  set -- $GATE_ACCOUNTS
  for acct in "$@"; do
    cfg="$(gate_cfg_for "$acct")"
    if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
      skipped="$skipped $acct"
      info "#02 entitlement — $acct: no config dir ($cfg) — skipped"
      continue
    fi
    if out="$(gate_headless "$cfg" "$GATE_MODEL" "Reply with exactly: ok")" \
       && printf '%s' "$out" | json_has_model "$GATE_MODEL"; then
      entitled="$entitled $acct"
      info "#02 entitlement — $acct: entitled for $GATE_MODEL"
    else
      failed="$failed $acct"
      info "#02 entitlement — $acct: NOT entitled (is_error=$(printf '%s' "$out" | json_get is_error))"
    fi
  done

  entitled="${entitled# }"; failed="${failed# }"; skipped="${skipped# }"

  if [ -n "$failed" ]; then
    emit_result 02 entitlement FAIL \
      "account(s) NOT entitled for $GATE_MODEL: $failed" \
      "entitled=[$entitled] failed=[$failed] skipped=[$skipped]"
  elif [ -n "$entitled" ]; then
    emit_result 02 entitlement PASS \
      "every present account entitled for $GATE_MODEL: $entitled${skipped:+ (skipped: $skipped)}" \
      "entitled=[$entitled] skipped=[$skipped]"
  else
    emit_result 02 entitlement SKIP \
      "no present account to test (all absent/logged-out): $skipped" \
      "skipped=[$skipped]"
  fi
  return 0
}
