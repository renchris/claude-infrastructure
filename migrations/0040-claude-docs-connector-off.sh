#!/bin/bash
# migration-class: c10
# migration-step: turn off the claude.ai "Claude Docs" connector in Claude Code for ALL accounts: add {"serverName":"claude.ai Claude Docs"} to deniedMcpServers and "anthropic-skills:docs":"off" to skillOverrides in the ONE shared ~/.claude/settings.json every account links to since 0037. Only that connector is removed (exact-name match); Google Drive, Gmail, Google Calendar and uidotsh stay connected. The anthropic-skills:docs skill needs this connector, so it is switched off with it and Claude Docs is no longer usable from Claude Code (claude.ai itself is unchanged). It refuses unless cc-settings-parity reports every account linked. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0040-claude-docs-connector-off.sh --confirm settings.json
# migration-verify: "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1 && jq -e '((.deniedMcpServers // []) | any(.[]; .serverName? == "claude.ai Claude Docs")) and ((.skillOverrides // {})["anthropic-skills:docs"] == "off")' "$HOME/.claude/settings.json" >/dev/null
#
# The verifier is config-dir-INVARIANT (as 0036-0039): one shared file, one answer from every dir.
#
# ══ 0040 — the unused Claude Docs connector off (token-efficiency rank 25, wave 3) ════════════════
# The connector had 0 calls in the 14.96-day baseline but put ~629 tool tokens and ~1,895 chars of
# server instructions into 50-90% of new contexts (OPPORTUNITIES.md rank 25). The operator approved
# turning it off on 2026-09-24, with one constraint: ENABLE_CLAUDEAI_MCP_SERVERS and
# disableClaudeAiConnectors are NOT acceptable, because they drop every claude.ai connector.
#
# WHY deniedMcpServers (docs/research/token-efficiency-2026-09-23/eval/wave3/r25-connector.md). On
# 2.1.280, measured headless with the setting passed per run: the server is dropped before it connects
# (absent from the init event's mcp_servers), its 8 tools and its instructions are gone, and
# "claude.ai uidotsh" stays connected. The binary matches entries by exact serverName, merges the key
# from every settings source ("users can deny servers for themselves"), and concatenates arrays. A
# server-level permissions.deny removes only the tools and leaves the instructions; `/mcp disable`
# persists per project only. skillOverrides turns off the one skill whose body calls this connector.
#
# SIDE EFFECTS, stated so they are not a surprise: every start prints "claude.ai MCP server blocked by
# enterprise policy: claude.ai Claude Docs" to stderr (the binary words any deny that way), and if
# Anthropic renames the connector the exact-name deny stops matching and it comes back.
#
# SAFETY. Edits the REAL file once (README rule 7), backs it up, verifies BY CONTENT that only the two
# keys changed as intended, and reads the effect back. Idempotent. Takes effect in NEW sessions.
# Revert: remove the deniedMcpServers entry and the skillOverrides key, or restore the printed backup.
#
# Usage: bash migrations/0040-claude-docs-connector-off.sh --dry-run
#        bash migrations/0040-claude-docs-connector-off.sh --confirm settings.json
# bash 3.2-safe.
set -uo pipefail

NAME='claude.ai Claude Docs'
SKILL='anthropic-skills:docs'
f="$HOME/.claude/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
command -v jq >/dev/null 2>&1 || { printf '0040: jq required — nothing written\n' >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '0040: --confirm must name its target: --confirm settings.json\n' >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '0040: unknown argument %s (use --dry-run or --confirm settings.json)\n' "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '0040: pass --dry-run to preview or --confirm settings.json to apply\n' >&2; exit 2; }

[ -f "$f" ] || { printf '0040: %s not found — nothing written\n' "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '0040: %s is not valid JSON — nothing written\n' "$real" >&2; exit 1; }

# shellcheck disable=SC2016  # a jq program: $n and $s are jq variables bound by --arg
applied='((.deniedMcpServers // []) | any(.[]; .serverName? == $n)) and ((.skillOverrides // {})[$s] == "off")'
if jq -e --arg n "$NAME" --arg s "$SKILL" "$applied" "$real" >/dev/null 2>&1; then
  printf '0040: already applied — %s denies %s and has %s off\n' "$real" "$NAME" "$SKILL"; exit 0
fi
"$parity" check >/dev/null 2>&1 || {
  printf '0040: REFUSED — accounts do not all share %s (%s check failed); the deny would reach some accounts and not others. Converge with 0037 first.\n' "$f" "$parity" >&2
  exit 1
}
jq -e '((.deniedMcpServers // []) | type == "array") and ((.skillOverrides // {}) | type == "object")' "$real" >/dev/null 2>&1 || {
  printf '0040: %s — deniedMcpServers is not an array or skillOverrides is not an object; left unchanged\n' "$real" >&2; exit 1
}

# shellcheck disable=SC2016  # a jq program: $n and $s are jq variables bound by --arg
EDIT='(if ((.deniedMcpServers // []) | any(.[]; .serverName? == $n)) then . else .deniedMcpServers = ((.deniedMcpServers // []) + [{serverName: $n}]) end)
      | .skillOverrides = ((.skillOverrides // {}) + {($s): "off"})'
printf '0040: will set in %s: deniedMcpServers += {"serverName":"%s"}, skillOverrides["%s"] = "off"\n' "$real" "$NAME" "$SKILL"
[ "$mode" = dry ] && { printf '0040: DRY RUN — nothing written\n'; exit 0; }

bdir="$HOME/.claude/backups/claude-docs-off-0040-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '0040: backup FAILED — nothing written\n' >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-0040-$$"
if ! jq --arg n "$NAME" --arg s "$SKILL" "$EDIT" "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0040: jq edit FAILED — nothing written\n' >&2; exit 1
fi
# BY CONTENT: every other key is unchanged, the prior deny entries and skill overrides all survive,
# and the result carries both changes.
same_rest=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" \
  '($a[0] | del(.deniedMcpServers, .skillOverrides)) == ($b[0] | del(.deniedMcpServers, .skillOverrides))')
kept=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" --arg s "$SKILL" \
  '(($a[0].deniedMcpServers // []) - $b[0].deniedMcpServers) == [] and (($a[0].skillOverrides // {}) | del(.[$s])) == ($b[0].skillOverrides | del(.[$s]))')
if [ "$same_rest" != true ] || [ "$kept" != true ] || ! jq -e --arg n "$NAME" --arg s "$SKILL" "$applied" "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0040: edit did not verify by content — nothing written\n' >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '0040: write FAILED — nothing written\n' >&2; exit 1; }
printf '0040: Claude Docs connector off for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$bdir"
"$parity" check >/dev/null 2>&1 || printf '0040: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$bdir" "$real" >&2
jq -e --arg n "$NAME" --arg s "$SKILL" "$applied" "$f" >/dev/null && printf '0040: verified — %s carries the deny and the skill override.\n' "$f"
