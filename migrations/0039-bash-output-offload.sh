#!/bin/bash
# migration-class: c10
# migration-step: register hooks/bash-output-offload.sh as a PostToolUse hook (its own "^Bash$" entry) in ~/.claude/settings.json, which every account links to since 0037 — so ALL accounts at once. A Bash result over 8,000 chars from a command that is not a deliberate read (cat/sed/grep/git show…) is saved to a file and the model gets its head, tail, the failure-looking lines from the hidden middle, and the path. It refuses unless cc-settings-parity reports every account linked and the LIVE hook file exists. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0039-bash-output-offload.sh --confirm settings.json
# migration-subject: hooks/bash-output-offload.sh
# migration-verify: "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1 && jq -e '[.hooks.PostToolUse[]? | select(.matcher == "^Bash$") | .hooks[]?.command] | any(. == "~/.claude/hooks/bash-output-offload.sh")' "$HOME/.claude/settings.json" >/dev/null
#
# The verifier is config-dir-INVARIANT (as 0036-0038): one shared file, one answer from every dir.
#
# ══ 0039 — large non-read Bash output goes to a file (token-efficiency rank 12, wave 2) ══════════
# Tool output is 18% of list-weighted spend and is re-read on every later turn of its context; the pass
# put the non-read subset over 8k chars at <= $453 per 14.96 days (OPPORTUNITIES.md rank 12) and
# filed it as "no user-space mechanism". Claude Code 2.1.280 has one: a PostToolUse hook's
# hookSpecificOutput.updatedToolOutput replaces the tool output before the model sees it (for Bash it
# must be the tool_response object; probed 2026-09-24). Offline gate (docs/research/
# token-efficiency-2026-09-23/eval/wave2/r12-offload.md): success 12/12 both arms, the hook fired 3
# times, and the runs whose needed fact sat in the hidden middle still answered correctly.
#
# WHY ITS OWN "^Bash$" ENTRY. The "Bash" entry is the collapsible audit chain that
# config/hook-chains.d/posttooluse-bash mirrors (tests/hook-chain-live-parity.bats compares the two).
# This hook REWRITES the result, and rewriting hooks run in parallel with last-write-wins semantics,
# so it stays outside that chain on purpose; "^Bash$" matches exactly the Bash tool.
#
# SAFETY. Edits the REAL file once (README rule 7), backs it up, verifies BY CONTENT that the only
# change is the one appended entry, and reads the effect back through the verifier. Idempotent.
# Revert: delete the "^Bash$" entry, or set CC_BASH_OFFLOAD=0 in the environment (the hook then does
# nothing), or restore the printed backup. Takes effect in NEW sessions.
#
# Usage: bash migrations/0039-bash-output-offload.sh --dry-run
#        bash migrations/0039-bash-output-offload.sh --confirm settings.json
# bash 3.2-safe.
set -uo pipefail

# shellcheck disable=SC2088  # the literal "~/" is what settings.json stores; Claude Code expands it
CMD='~/.claude/hooks/bash-output-offload.sh'
f="$HOME/.claude/settings.json"
hook="$HOME/.claude/hooks/bash-output-offload.sh"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
command -v jq >/dev/null 2>&1 || { printf '0039: jq required — nothing written\n' >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '0039: --confirm must name its target: --confirm settings.json\n' >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '0039: unknown argument %s (use --dry-run or --confirm settings.json)\n' "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '0039: pass --dry-run to preview or --confirm settings.json to apply\n' >&2; exit 2; }

[ -f "$f" ] || { printf '0039: %s not found — nothing written\n' "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '0039: %s is not valid JSON — nothing written\n' "$real" >&2; exit 1; }

if jq -e --arg c "$CMD" '[.hooks.PostToolUse[]? | select(.matcher == "^Bash$") | .hooks[]?.command] | any(. == $c)' "$real" >/dev/null 2>&1; then
  printf '0039: already applied — %s is registered in %s\n' "$CMD" "$real"; exit 0
fi
"$parity" check >/dev/null 2>&1 || {
  printf '0039: REFUSED — accounts do not all share %s (%s check failed); the hook would reach some accounts and not others. Converge with 0037 first.\n' "$f" "$parity" >&2
  exit 1
}
[ -f "$hook" ] || {
  printf '0039: REFUSED — the live hook %s does not exist yet. Converge first: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' "$hook" >&2
  exit 1
}

printf '0039: will append to %s .hooks.PostToolUse: {"matcher":"^Bash$","hooks":[{"type":"command","command":"%s","timeout":10}]}\n' "$real" "$CMD"
[ "$mode" = dry ] && { printf '0039: DRY RUN — nothing written\n'; exit 0; }

bdir="$HOME/.claude/backups/bash-output-offload-0039-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '0039: backup FAILED — nothing written\n' >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-0039-$$"
ENTRY=$(jq -nc --arg c "$CMD" '{matcher:"^Bash$",hooks:[{type:"command",command:$c,timeout:10}]}')
if ! jq --argjson e "$ENTRY" '.hooks.PostToolUse = ((.hooks.PostToolUse // []) + [$e])' "$real" > "$tmp" 2>/dev/null \
   || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0039: jq edit FAILED — nothing written\n' >&2; exit 1
fi
# BY CONTENT: everything but .hooks.PostToolUse is the same document, and PostToolUse gained exactly
# the one entry at its end.
same_rest=$( [ "$(jq -S 'del(.hooks.PostToolUse)' "$real")" = "$(jq -S 'del(.hooks.PostToolUse)' "$tmp")" ] && echo y )
want=$(jq -c --argjson e "$ENTRY" '(.hooks.PostToolUse // []) + [$e]' "$real")
got=$(jq -c '.hooks.PostToolUse' "$tmp")
if [ "$same_rest" != y ] || [ "$want" != "$got" ]; then
  rm -f "$tmp"; printf '0039: edit did not verify by content — nothing written\n' >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '0039: write FAILED — nothing written\n' >&2; exit 1; }
printf '0039: registered for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$bdir"
"$parity" check >/dev/null 2>&1 || printf '0039: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$bdir" "$real" >&2
jq -e --arg c "$CMD" '[.hooks.PostToolUse[]? | select(.matcher == "^Bash$") | .hooks[]?.command] | any(. == $c)' "$f" >/dev/null \
  && printf '0039: verified — %s carries the hook.\n' "$f"
