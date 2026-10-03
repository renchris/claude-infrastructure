#!/bin/bash
# migration-class: c10
# migration-step: allow agents to run bin/cc-wake (wake an IDLE peer session through its messaging socket so it reads its inbox): add Bash(cc-wake:*), Bash(~/.claude/bin/cc-wake:*) and Bash($HOME/.claude/bin/cc-wake:*) to permissions.allow in the ONE shared ~/.claude/settings.json. cc-wake types nothing into any pane; it refuses unless the target is idle, the same process, and has unread mail. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0052-cc-wake-allow.sh --confirm settings.json
# migration-subject: ~/.claude/bin/cc-wake
# migration-verify: jq -e '(.permissions.allow // []) | index("Bash(cc-wake:*)") != null' "$HOME/.claude/settings.json" >/dev/null
#
# ══ 0052 — cc-wake on the allow list (docs/plans/AGENT_PEER_WAKE.md, Permissions) ══════════════════
# The operator, 2026-10-03: "you need to have the permissions and allowlist of commands so you have the
# ability to do this yourself." cc-notify already calls cc-wake internally (Bash(cc-notify:*) is
# allowed), so the automatic path needs nothing here. This rule covers the DIRECT call an agent makes
# to wake a peer and wait for its receipt (`cc-wake <pane> --wait 240`). Without it, auto mode's
# classifier judges each call afresh, and acting on another live session is a class it has denied before.
# Three spellings, because an allow rule matches by PREFIX and agents reach the bin by all three.
#
# BLAST RADIUS: it only ADDS three strings to permissions.allow. Nothing is removed or reordered.
# The file is backed up first, and the edit is verified by content (everything except
# permissions.allow is unchanged, and every pre-existing allow entry survives) before it replaces the
# live file. Rollback: the printed `cp -p` line.
# shellcheck disable=SC2016  # every single-quoted string below is a jq program; $a/$r1 are jq variables
set -uo pipefail

f="$HOME/.claude/settings.json"
command -v jq >/dev/null 2>&1 || { printf '0052: jq required — nothing written\n' >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '0052: --confirm must name its target: --confirm settings.json\n' >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '0052: unknown argument %s (use --dry-run or --confirm settings.json)\n' "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '0052: pass --dry-run to preview or --confirm settings.json to apply\n' >&2; exit 2; }

[ -x "$HOME/.claude/bin/cc-wake" ] || { printf '0052: %s is not on the live layer yet — converge first; nothing written\n' "$HOME/.claude/bin/cc-wake" >&2; exit 1; }
[ -f "$f" ] || { printf '0052: %s not found — nothing written\n' "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '0052: %s is not valid JSON — nothing written\n' "$real" >&2; exit 1; }
jq -e '(.permissions // {}) | (.allow // []) | type == "array"' "$real" >/dev/null 2>&1 \
  || { printf '0052: permissions.allow is not an array — left unchanged\n' >&2; exit 1; }

# shellcheck disable=SC2088  # the tilde is literal: it is a permission-rule string, not a path to expand
R1='Bash(cc-wake:*)'; R2='Bash(~/.claude/bin/cc-wake:*)'; R3="Bash($HOME/.claude/bin/cc-wake:*)"
applied='(.permissions.allow // []) as $a | ($a | index($r1)) != null and ($a | index($r2)) != null and ($a | index($r3)) != null'
if jq -e --arg r1 "$R1" --arg r2 "$R2" --arg r3 "$R3" "$applied" "$real" >/dev/null 2>&1; then
  printf '0052: already applied — %s allows cc-wake\n' "$real"; exit 0
fi
printf '0052: will add to permissions.allow in %s: %s  %s  %s\n' "$real" "$R1" "$R2" "$R3"
[ "$mode" = dry ] && { printf '0052: DRY RUN — nothing written\n'; exit 0; }

bdir="$HOME/.claude/backups/cc-wake-allow-0052-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '0052: backup FAILED — nothing written\n' >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-0052-$$"
EDIT='.permissions = ((.permissions // {}) | .allow = ((.allow // []) + ([$r1, $r2, $r3] - (.allow // []))))'
if ! jq --arg r1 "$R1" --arg r2 "$R2" --arg r3 "$R3" "$EDIT" "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0052: jq edit FAILED — nothing written\n' >&2; exit 1
fi
same_rest=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" '($a[0] | del(.permissions.allow)) == ($b[0] | del(.permissions.allow))')
kept=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" '(($a[0].permissions.allow // []) - $b[0].permissions.allow) == []')
if [ "$same_rest" != true ] || [ "$kept" != true ] || ! jq -e --arg r1 "$R1" --arg r2 "$R2" --arg r3 "$R3" "$applied" "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0052: edit did not verify by content — nothing written\n' >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '0052: write FAILED — nothing written\n' >&2; exit 1; }
printf '0052: cc-wake allowed. Backup: %s/settings.json (restore: cp -p %s/settings.json %s)\n' "$bdir" "$bdir" "$real"
jq -e --arg r1 "$R1" --arg r2 "$R2" --arg r3 "$R3" "$applied" "$f" >/dev/null && printf '0052: verified — %s carries all three rules.\n' "$f"
