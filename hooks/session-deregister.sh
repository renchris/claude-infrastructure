#!/bin/bash
# session-deregister.sh — SessionEnd hook; removes this pane's cc-registry entry.
#
# Pairs with session-register.sh (see it for the registry rationale). Fail-safe:
# always exit 0. Skips reason=clear — a cleared session keeps the SAME pane and
# re-registers on the immediately-following SessionStart, so removing here would
# only briefly drop a live pane from the registry (matches session-save-id.sh).
# A session that dies WITHOUT SessionEnd self-heals: cc-sessions sweeps the stale
# entry (pane gone per `it2 session list`, or owning pid dead per `kill -0`).
# bash 3.2-safe.
set -uo pipefail

input=$(cat 2>/dev/null)
command -v jq >/dev/null 2>&1 || exit 0

reason=$(printf '%s' "$input" | jq -r '.reason // empty' 2>/dev/null)
[ "$reason" = "clear" ] && exit 0

pane="${ITERM_SESSION_ID:-}"; pane="${pane##*:}"
case "$pane" in
  ''|*[!0-9A-Fa-f-]*) exit 0 ;;
esac

reg_dir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
rm -f "$reg_dir/$pane.json" 2>/dev/null
exit 0
