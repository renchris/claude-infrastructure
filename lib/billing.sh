#!/bin/bash
# lib/billing.sh — shell face of the three-key attribution API (scripts/lib/billing.py; wave W2 of
# docs/plans/ZERO_HITL_ROTATION.md). Source it; every function prints one value and returns 0.
#
#   cc_billing_on                      exit 0 when the CC_BILLING switch is on (env, then switch file)
#   cc_billing_of  <sid> [at] [home]   the account sid bills at `at` (default now), or `unknown`
#   cc_home_of     <sid> [home]        the store account (registry, transcript, ledger), or `unknown`
#   cc_identity_of <sid> [at] [home]   home | billing | unknown
#   cc_billing_json <sid> [at] [home]  every key as one JSON object
#
# `at` is epoch seconds, epoch ms or ISO-8601 ("" = now); `home` is the caller's own store (an
# account name or config dir, e.g. "$CLAUDE_CONFIG_DIR"), which skips the lookup. The fast path
# answers without python when the caller names its home and the switch is off, the ledger is
# absent, or the ledger never mentions the sid; that is the same answer billing.py gives there
# (tests/attribution-keys.bats holds the parity). Bash 3.2 safe: launchd jobs source this.

_CC_BILLING_LIB="${BASH_SOURCE[0]%/*}"
_CC_BILLING_PY="$_CC_BILLING_LIB/../scripts/lib/billing.py"
# shellcheck source=lib/account-map.generated.sh disable=SC1091  # sibling file, resolved at runtime
. "$_CC_BILLING_LIB/account-map.generated.sh"

cc_billing_on() {
  local v
  v=$(printf '%s' "${CC_BILLING:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  case "$v" in
    1|on|true|yes) return 0 ;;
    0|off|false|no) return 1 ;;
  esac
  [ -e "${CC_LANES_DIR:-$HOME/.reso/lanes}/billing.on" ]
}

# An account name, alias, launcher or config dir -> the canonical name; empty when unknown.
_cc_billing_norm() {
  local x="${1:-}" n
  case "$x" in
    "~"*) x="$HOME${x#\~}" ;;
  esac
  case "$x" in
    */*) x="${x%/}"; x="${x##*/}" ;;
  esac
  [ "$x" = ".claude" ] && x="claude"
  n=$(cc_acct_name_for_dir_basename "$x")
  if [ -z "$n" ] && cc_acct_dir_for_name "$x"; then
    n=$(cc_acct_name_for_dir_basename "${CC_ACCT_DIR##*/}")
  fi
  printf '%s' "$n"
}

# Exit 0 when the ledger can say nothing about sid, so billing is home with no python.
_cc_billing_ledger_silent() {
  local led="${CC_BILLING_LEDGER:-${CC_LANES_DIR:-$HOME/.reso/lanes}/ledger.jsonl}"
  cc_billing_on || return 0
  [ -f "$led" ] || return 0
  ! grep -qF -- "$1" "$led" 2>/dev/null
}

_cc_billing_py() {
  local sid="$1" at="$2" home="$3"; shift 3
  set -- --sid "$sid" "$@"
  [ -n "$at" ] && set -- "$@" --at "$at"
  [ -n "$home" ] && set -- "$@" --home "$home"
  python3 -I "$_CC_BILLING_PY" "$@"
}

cc_billing_of() {
  local sid="${1:-}" at="${2:-}" home="${3:-}" n=""
  [ -n "$sid" ] || { printf 'unknown\n'; return 0; }
  [ -n "$home" ] && n=$(_cc_billing_norm "$home")
  if [ -n "$n" ] && _cc_billing_ledger_silent "$sid"; then
    printf '%s\n' "$n"
    return 0
  fi
  _cc_billing_py "$sid" "$at" "$home" --field billing 2>/dev/null || printf 'unknown\n'
}

cc_home_of() {
  local sid="${1:-}" home="${2:-}" n=""
  [ -n "$home" ] && n=$(_cc_billing_norm "$home")
  if [ -n "$n" ]; then
    printf '%s\n' "$n"
    return 0
  fi
  [ -n "$sid" ] || { printf 'unknown\n'; return 0; }
  _cc_billing_py "$sid" "" "" --field home 2>/dev/null || printf 'unknown\n'
}

cc_identity_of() {
  local sid="${1:-}" at="${2:-}" home="${3:-}" n=""
  [ -n "$sid" ] || { printf 'unknown\n'; return 0; }
  [ -n "$home" ] && n=$(_cc_billing_norm "$home")
  if [ -n "$n" ] && _cc_billing_ledger_silent "$sid"; then
    printf 'home\n'
    return 0
  fi
  _cc_billing_py "$sid" "$at" "$home" --field identity 2>/dev/null || printf 'unknown\n'
}

cc_billing_json() {
  local sid="${1:-}" at="${2:-}" home="${3:-}"
  [ -n "$sid" ] || return 0
  _cc_billing_py "$sid" "$at" "$home" --json
}
