#!/bin/bash
# async-hook-lint.sh — an ASYNC hook must never print systemMessage (read-only lint).
#
# WHY. Claude Code routes an async hook's response to the MODEL as an isMeta attachment, not to the
# terminal: `case"async_hook_response"` pushes only systemMessage and additionalContext, and its
# stderr is never rendered (docs/research/startup-hooks-2026-10-18/A5-silent-drops.md F8, A6 §6). So
# an async hook that "warns" through systemMessage bills the model for a line the operator never
# sees, and one that warns through stderr warns nobody. The rule: an async hook reports through the
# IDL (hooks/lib/async-span.sh) and never through systemMessage or stderr.
#
# Usage: scripts/async-hook-lint.sh [settings.json ...]
#   default: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json. Each async command's script is read
#   from THIS checkout's hooks/ when it lives there (the version about to land), else at its path.
# Exit: 0 clean · 1 a violation (each named on stdout) · 2 no readable settings / no jq.
set -uo pipefail

REPO="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "async-hook-lint: jq not found" >&2; exit 2; }
[ "$#" -gt 0 ] || set -- "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

bad=0 seen=0
for settings in "$@"; do
  [ -r "$settings" ] || { echo "async-hook-lint: cannot read $settings" >&2; exit 2; }
  while IFS=$'\t' read -r ev cmd; do
    [ -n "$cmd" ] || continue
    script="${cmd%% *}"; script="${script/#\~/$HOME}"
    [ -f "$REPO/hooks/${script##*/}" ] && script="$REPO/hooks/${script##*/}"
    [ -f "$script" ] || { echo "SKIP  $ev  $cmd (script not found)"; continue; }
    seen=$((seen + 1))
    if grep -n 'systemMessage' "$script" | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then
      echo "FAIL  $ev  ${script##*/} is async and prints systemMessage — route the report through the IDL"
      bad=1
    fi
  # Every non-last cell is padded at the emitter: tab is IFS-whitespace, so an empty cell would shift
  # the command into the event column (scripts/tsv-pad-lint.sh).
  done < <(jq -r 'def cell(ph): (if . == null then "" else . end) | tostring
                    | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;
                  .hooks // {} | to_entries[] | .key as $e | .value[]? | .hooks[]?
                  | select(.async == true) | [($e | cell("-")), (.command // "")] | @tsv' "$settings" 2>/dev/null)
done
[ "$bad" = 0 ] && echo "async-hook-lint: ok — $seen async hook script(s), none prints systemMessage"
exit "$bad"
