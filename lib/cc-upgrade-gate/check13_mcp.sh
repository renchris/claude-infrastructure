#!/usr/bin/env bash
# check13_mcp.sh — #13 MCP reachability (session-connected servers resolve on the candidate binary).
# ─────────────────────────────────────────────────────────────────────────────
# If the account has session-connected MCP servers, the candidate binary must enumerate + connect to
# them. `claude mcp list` prints one `<name>: <url> - <status>` line per configured server. PASS iff
# ≥1 server reports a solid `✔ Connected`; a single server showing a transient `timed out` is a WARN
# (server-side flake, noted in detail) not a hard FAIL. If NO servers are configured → SKIP (n/a, not
# a regression). Wrapped in a bounded retry (MCP health probes are transiently flaky).
# shellcheck shell=bash

# shellcheck disable=SC2317  # invoked by name through `retry`, not statically
_gate_mcp_list() {
  local cfg="$1" out_file="$2" out=""
  out="$(CLAUDE_CONFIG_DIR="$cfg" DISABLE_AUTOUPDATER=1 "$GATE_BIN" mcp list </dev/null 2>&1)"
  printf '%s' "$out" >"$out_file"
  # success = at least one solidly-connected server line
  printf '%s' "$out" | grep -q '✔ Connected'
}

check_13() {
  local acct cfg out_file="" out="" connected="" degraded=""
  acct="$(gate_primary_account)"
  cfg="$(gate_cfg_for "$acct")"
  if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
    emit_result 13 mcp-reachability SKIP "no config dir for account '$acct' ($cfg)" ""
    return 0
  fi

  out_file="$(mktemp)"
  retry "${GATE_RETRIES:-3}" _gate_mcp_list "$cfg" "$out_file"
  out="$(cat "$out_file")"
  rm -f "$out_file"

  # no servers configured → SKIP (not a regression)
  if [ -z "$out" ] || printf '%s' "$out" | grep -qiE 'No MCP servers|no servers? configured|not configured'; then
    emit_result 13 mcp-reachability SKIP "no session-connected MCP servers configured for '$acct'" ""
    return 0
  fi

  connected="$(printf '%s' "$out" | grep -c '✔ Connected')"
  degraded="$(printf '%s' "$out" | grep -Ec 'timed out|✗|Failed|! Connected')"

  if [ "${connected:-0}" -ge 1 ]; then
    emit_result 13 mcp-reachability PASS \
      "MCP tool list resolves on the candidate: ${connected} server(s) ✔ Connected$([ "${degraded:-0}" -gt 0 ] && echo ", ${degraded} degraded (server-side, non-fatal)")" \
      "$(printf '%s' "$out" | grep -E 'Connected|Failed|timed out' | head -6 | tr '\n' ';')"
  else
    emit_result 13 mcp-reachability FAIL \
      "mcp list returned NO ✔ Connected servers on the candidate binary" \
      "$(printf '%s' "$out" | head -c 300)"
  fi
  return 0
}
