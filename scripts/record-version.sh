#!/bin/bash
# record-version.sh — Append-only version registry.
#
# Records status decisions about Claude Code versions so smoke-test.sh can
# consult the registry before promotion and humans can review version history.
#
# Usage:
#   record-version.sh <version> <status> [notes...]
#
# Status:
#   candidate — installed but not yet tested
#   stable    — verified working, safe to promote
#   skip      — known-broken, refuse to promote
#
# Output: appends one NDJSON line to ~/.claude-versions/MANIFEST.jsonl

set -euo pipefail

readonly MANIFEST_FILE="$HOME/.claude-versions/MANIFEST.jsonl"

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <version> <status> [notes...]

Status values:
  candidate — installed but not yet tested
  stable    — verified working, safe to promote
  skip      — known-broken, refuse to promote

Example:
  $(basename "$0") 2.1.111 stable "last known good before getAppState regression"
  $(basename "$0") 2.1.112 skip "getAppState crash in auto-mode+teams init"
EOF
}

main() {
  if [[ $# -lt 2 ]]; then
    usage
    exit 2
  fi

  local version="$1"
  local status="$2"
  shift 2
  local notes="${*:-}"

  case "$status" in
    candidate|stable|skip) ;;
    *)
      echo "ERROR: invalid status '$status' (must be candidate|stable|skip)" >&2
      exit 2
      ;;
  esac

  mkdir -p "$(dirname "$MANIFEST_FILE")"

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Escape notes for JSON (basic — wraps in quotes, escapes \ and ")
  local escaped_notes
  escaped_notes=$(printf '%s' "$notes" | sed 's/\\/\\\\/g; s/"/\\"/g')

  printf '{"version":"%s","status":"%s","date_added":"%s","notes":"%s"}\n' \
    "$version" "$status" "$ts" "$escaped_notes" >> "$MANIFEST_FILE"

  echo "recorded: $version [$status] @ $ts"
  [[ -n "$notes" ]] && echo "  notes: $notes"
}

main "$@"
