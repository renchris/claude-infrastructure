#!/bin/bash
# migration-class: c10
# migration-step: allow agents to run bin/cc-husk-sweep (list panes left at a bare shell over a dead Claude session, and resume them on the right account): add Bash(cc-husk-sweep:*), Bash(~/.claude/bin/cc-husk-sweep:*) and Bash($HOME/.claude/bin/cc-husk-sweep:*) to permissions.allow in the ONE shared ~/.claude/settings.json. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0074-husk-sweep-allow.sh --confirm settings.json
# migration-subject: ~/.claude/bin/cc-husk-sweep
# migration-verify: jq -e '(.permissions.allow // []) | index("Bash(cc-husk-sweep:*)") != null' "$HOME/.claude/settings.json" >/dev/null
#
# ══ 0074 — cc-husk-sweep on the allow list (docs/research/husk-mass-sigterm-2026-10-21.md) ══════════
# The operator, 2026-10-21, after recovering 8 killed sessions by typing `cc-husk-sweep --resume --yes`
# by hand: "Update our allowlist/permissions such that you can run these commands as needed without
# human manual command entry." The sweep only ever types into a pane it has itself proved is a HUSK
# (a bare shell over a DEAD session whose transcript it resolved to an account); it never touches a
# live session, refuses a transplanted session's source pane, and resumes nothing whose work is
# collected by a custody holder. Without this rule, auto mode's classifier judges each `--resume`
# afresh, and acting on another session's pane is a class it has denied before.
# Three spellings, because an allow rule matches by PREFIX and agents reach the bin by all three.
#
# BLAST RADIUS: it only ADDS three strings to permissions.allow. Nothing is removed or reordered.
# The file is backed up first, and the edit is verified by content (everything except
# permissions.allow is unchanged, and every pre-existing allow entry survives) before it replaces the
# live file. Rollback: the printed `cp -p` line.
# shellcheck disable=SC2016  # every single-quoted string below is a jq program; $a/$r1 are jq variables
set -uo pipefail

f="$HOME/.claude/settings.json"
command -v jq >/dev/null 2>&1 || { printf '0074: jq required — nothing written\n' >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '0074: --confirm must name its target: --confirm settings.json\n' >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '0074: unknown argument %s (use --dry-run or --confirm settings.json)\n' "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '0074: pass --dry-run to preview or --confirm settings.json to apply\n' >&2; exit 2; }

[ -x "$HOME/.claude/bin/cc-husk-sweep" ] || { printf '0074: %s is not on the live layer yet — converge first; nothing written\n' "$HOME/.claude/bin/cc-husk-sweep" >&2; exit 1; }
[ -f "$f" ] || { printf '0074: %s not found — nothing written\n' "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '0074: %s is not valid JSON — nothing written\n' "$real" >&2; exit 1; }
jq -e '(.permissions // {}) | (.allow // []) | type == "array"' "$real" >/dev/null 2>&1 \
  || { printf '0074: permissions.allow is not an array — left unchanged\n' >&2; exit 1; }

# shellcheck disable=SC2088  # the tilde is literal: it is a permission-rule string, not a path to expand
R1='Bash(cc-husk-sweep:*)'; R2='Bash(~/.claude/bin/cc-husk-sweep:*)'; R3="Bash($HOME/.claude/bin/cc-husk-sweep:*)"
applied='(.permissions.allow // []) as $a | ($a | index($r1)) != null and ($a | index($r2)) != null and ($a | index($r3)) != null'
if jq -e --arg r1 "$R1" --arg r2 "$R2" --arg r3 "$R3" "$applied" "$real" >/dev/null 2>&1; then
  printf '0074: already applied — %s allows cc-husk-sweep\n' "$real"; exit 0
fi
printf '0074: will add to permissions.allow in %s: %s  %s  %s\n' "$real" "$R1" "$R2" "$R3"
[ "$mode" = dry ] && { printf '0074: DRY RUN — nothing written\n'; exit 0; }

bdir="$HOME/.claude/backups/husk-sweep-allow-0074-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '0074: backup FAILED — nothing written\n' >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-0074-$$"
EDIT='.permissions = ((.permissions // {}) | .allow = ((.allow // []) + ([$r1, $r2, $r3] - (.allow // []))))'
if ! jq --arg r1 "$R1" --arg r2 "$R2" --arg r3 "$R3" "$EDIT" "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0074: jq edit FAILED — nothing written\n' >&2; exit 1
fi
same_rest=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" '($a[0] | del(.permissions.allow)) == ($b[0] | del(.permissions.allow))')
kept=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" '(($a[0].permissions.allow // []) - $b[0].permissions.allow) == []')
if [ "$same_rest" != true ] || [ "$kept" != true ] || ! jq -e --arg r1 "$R1" --arg r2 "$R2" --arg r3 "$R3" "$applied" "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0074: edit did not verify by content — nothing written\n' >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '0074: write FAILED — nothing written\n' >&2; exit 1; }
printf '0074: cc-husk-sweep allowed. Backup: %s/settings.json (restore: cp -p %s/settings.json %s)\n' "$bdir" "$bdir" "$real"
jq -e --arg r1 "$R1" --arg r2 "$R2" --arg r3 "$R3" "$applied" "$f" >/dev/null && printf '0074: verified — %s carries all three rules.\n' "$f"
