#!/bin/bash
# migration-class: c10
# migration-step: allow agents to move and recover sessions between accounts with no prompt and no auto-mode denial: add Bash(cc-lr:*), Bash(~/.claude/bin/cc-lr:*), Bash($HOME/.claude/bin/cc-lr:*), Bash(~/.claude/scripts/limit-recover/lr-handoff.sh:*), Bash($HOME/.claude/scripts/limit-recover/lr-handoff.sh:*), Bash($HOME/.claude/scripts/handoff-fire.sh:*) and Bash(~/.claude/hooks/session-continue.sh clear:*) to permissions.allow in the ONE shared ~/.claude/settings.json. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0084-cc-lr-move-allow.sh --confirm settings.json
# migration-subject: ~/.claude/bin/cc-lr
# migration-verify: jq -e '(.permissions.allow // []) as $a | (["Bash(cc-lr:*)", "Bash(~/.claude/bin/cc-lr:*)", "Bash(~/.claude/scripts/limit-recover/lr-handoff.sh:*)", "Bash(~/.claude/hooks/session-continue.sh clear:*)"] - $a) == []' "$HOME/.claude/settings.json" >/dev/null
#
# ══ 0084 — cc-lr moves on the allow list (docs/plans/ZERO_HITL_ROTATION.md wave Z1) ═════════════════
# Evidence: ~/.reso/zero-hitl-2026-10-25/survey-permission-surface.md (rows 1-6, 10) and
# verify-auto-mode.md (claims a, d). Only `~/.claude/bin/cc-lr switch` was allowed; every other
# cc-lr verb and spelling fell through to the auto-mode classifier, which has denied `cc-lr switch`
# and `cc-lr recover` as [Self-Modification], and which refuses EVERY unmatched command during a
# "Classifier unavailable" outage (156 such denials since 2026-09-25). In 2.1.293 a rule allow
# returns before any classifier code and is never re-routed by the server-side hold, so a single
# rule-matched command ran 22/22 during outages. cc-lr is the rail: it refuses teammates, ambiguous
# refs and non-limited sessions, and never types, kills or touches git.
# Spellings: bare, `~/` and absolute, because an allow rule matches by PREFIX and agents reach these
# tools all three ways. handoff-fire.sh's `~/` form is already allowed; only its absolute form is new.
# NOT added, on purpose: lr-fire-resume.sh, lr-move-worker.sh, lr-move-batch.sh and lr-fleet.sh are
# launchd-only daemon internals, and a rule for them would bypass cc-lr's refusals. `kitty @` stays
# out. No `autoMode.environment` prose: the classifier re-judges it on every call, so it gives no
# outage protection (verify-auto-mode.md, "Mechanisms that cannot give the guarantee").
# The hook gates on lr-handoff.sh and handoff-fire.sh (duplicate-worker lease, spawn-generation cap)
# deny regardless of any allow rule, and keep doing so.
#
# BLAST RADIUS: it only ADDS the rules not already present to permissions.allow. Nothing is removed or
# reordered. The file is backed up first, and the edit is verified by content (everything except
# permissions.allow is unchanged, and every pre-existing allow entry survives) before it replaces the
# live file. Rollback: the printed `cp -p` line.
# shellcheck disable=SC2016  # every single-quoted string below is a jq program; $a/$r/$m are jq variables
set -uo pipefail

f="$HOME/.claude/settings.json"
command -v jq >/dev/null 2>&1 || { printf '0084: jq required — nothing written\n' >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '0084: --confirm must name its target: --confirm settings.json\n' >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '0084: unknown argument %s (use --dry-run or --confirm settings.json)\n' "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '0084: pass --dry-run to preview or --confirm settings.json to apply\n' >&2; exit 2; }

[ -x "$HOME/.claude/bin/cc-lr" ] || { printf '0084: %s is not on the live layer yet — converge first; nothing written\n' "$HOME/.claude/bin/cc-lr" >&2; exit 1; }
[ -f "$f" ] || { printf '0084: %s not found — nothing written\n' "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '0084: %s is not valid JSON — nothing written\n' "$real" >&2; exit 1; }
jq -e '(.permissions // {}) | (.allow // []) | type == "array"' "$real" >/dev/null 2>&1 \
  || { printf '0084: permissions.allow is not an array — left unchanged\n' >&2; exit 1; }

# The tildes are literal: these are permission-rule strings, not paths to expand. The absolute
# spellings carry $HOME expanded, as 0074's R3 does (a literal `$HOME` in a rule is unverified).
RULES=$(jq -nc --arg h "$HOME" '[
  "Bash(cc-lr:*)",
  "Bash(~/.claude/bin/cc-lr:*)",
  "Bash(\($h)/.claude/bin/cc-lr:*)",
  "Bash(~/.claude/scripts/limit-recover/lr-handoff.sh:*)",
  "Bash(\($h)/.claude/scripts/limit-recover/lr-handoff.sh:*)",
  "Bash(\($h)/.claude/scripts/handoff-fire.sh:*)",
  "Bash(~/.claude/hooks/session-continue.sh clear:*)"
]')
applied='((.permissions.allow // []) as $a | ($r - $a)) == []'
missing=$(jq -c --argjson r "$RULES" '$r - (.permissions.allow // [])' "$real") \
  || { printf '0084: could not read permissions.allow — nothing written\n' >&2; exit 1; }
if [ "$missing" = "[]" ]; then
  printf '0084: already applied — %s allows cc-lr, lr-handoff.sh, handoff-fire.sh and session-continue.sh clear\n' "$real"; exit 0
fi
printf '0084: will add to permissions.allow in %s (rules already present are skipped):\n' "$real"
jq -r '.[] | "  + " + .' <<<"$missing"
[ "$mode" = dry ] && { printf '0084: DRY RUN — nothing written\n'; exit 0; }

bdir="$HOME/.claude/backups/cc-lr-move-allow-0084-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '0084: backup FAILED — nothing written\n' >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-0084-$$"
EDIT='.permissions = ((.permissions // {}) | .allow = ((.allow // []) + $m))'
if ! jq --argjson m "$missing" "$EDIT" "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0084: jq edit FAILED — nothing written\n' >&2; exit 1
fi
same_rest=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" '($a[0] | del(.permissions.allow)) == ($b[0] | del(.permissions.allow))')
kept=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" '(($a[0].permissions.allow // []) - $b[0].permissions.allow) == []')
if [ "$same_rest" != true ] || [ "$kept" != true ] || ! jq -e --argjson r "$RULES" "$applied" "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0084: edit did not verify by content — nothing written\n' >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '0084: write FAILED — nothing written\n' >&2; exit 1; }
printf '0084: cc-lr moves allowed. Backup: %s/settings.json (restore: cp -p %s/settings.json %s)\n' "$bdir" "$bdir" "$real"
jq -e --argjson r "$RULES" "$applied" "$f" >/dev/null && printf '0084: verified — %s carries all seven rules.\n' "$f"
