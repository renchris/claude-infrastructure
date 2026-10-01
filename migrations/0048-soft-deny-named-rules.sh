#!/bin/bash
# migration-class: c10
# migration-step: add 17 named shipped safety rules (Secret-Store Writes, Credential Materialization, Instruction Poisoning, Auto-Mode Bypass, Session Transcript Tampering, Tmux Self Drive, Unverifiable Deletion Target, Public Data-Sharing Upload, External Ingress Tunnel, Traffic Redirection, Sensitive-Source Provenance, Code That Leaks When Run, and the 5 Browser exfil rules) to autoMode.soft_deny in ~/.claude/settings.json, replacing our Memory Poisoning with Instruction Poisoning — ALL accounts at once. Measured cost about 1 to 2 extra classifier blocks a day. HELD until the operator rules yes on its decision packet. It writes the auto-mode classifier's rules, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0048-soft-deny-named-rules.sh --confirm settings.json
# migration-batch-hold: decision 0048-soft-deny-named-rules
# migration-verify: "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1 && bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0048-soft-deny-named-rules.sh" --verify
#
# ══ 0048 — the shipped soft_deny rules worth having, by name (backlog b19974f7ba82, follow-on) ═════
# "$defaults" in autoMode.soft_deny was measured and ruled NO (0046's header; docs/research/
# c10-staged-residuals-2026-10.md § soft_deny). The same 14-day replay (249,076 real tool calls,
# 2026-09-17..30) found 17 shipped rules that guard real risks on this machine and almost never fire:
# together about 1 to 2 extra blocks a day against today's 16.4. They are copied VERBATIM from
# `claude auto-mode defaults` on 2.1.284 into migrations/data/0048-soft-deny-named-rules.json, so the
# list stays fixed instead of taking on whatever each release adds (65 rules in August, 70 now).
# Memory Poisoning is replaced by Instruction Poisoning, whose shipped text covers it.
#
# WHY HELD. It trades fewer prompts (the operator's stated goal) for safety at a measured but
# unreplayed cost — the block rates are text-match estimates, no classifier was re-run — so the
# conviction is 75% and the call is the operator's. The batch (scripts/c10-batch.sh) skips it until
# the packet named on the migration-batch-hold line is actioned.
#
# SAFETY. Edits the REAL shared file once, backs it up, verifies BY CONTENT that only
# autoMode.soft_deny changed and that it equals the old list minus Memory Poisoning plus the 17 rules,
# and reads the effect back. Idempotent: a rule already present (by title) is not added twice.
# Revert: restore the printed backup. Takes effect in NEW sessions.
#
# Usage: bash migrations/0048-soft-deny-named-rules.sh --dry-run | --check | --verify
#        bash migrations/0048-soft-deny-named-rules.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first)
# bash 3.2-safe.
set -uo pipefail

N=0048
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
data="$here/data/0048-soft-deny-named-rules.json"
f="$HOME/.claude/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
command -v jq >/dev/null 2>&1 || { printf '%s: jq required — nothing written\n' "$N" >&2; exit 1; }
[ -f "$data" ] || { printf '%s: rule data %s missing — nothing written\n' "$N" "$data" >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --check) mode=check ;;
  --verify) mode=verify ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '%s: --confirm must name its target: --confirm settings.json\n' "$N" >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '%s: unknown argument %s (use --dry-run, --check, --verify or --confirm settings.json)\n' "$N" "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '%s: pass --dry-run, --check, --verify or --confirm settings.json\n' "$N" >&2; exit 2; }

# A rule's title is its text up to the first " [" or ":" — the same split the research used.
# shellcheck disable=SC2016
TITLE='def title: (split(" [")[0] | split(":")[0] | gsub("^\\s+|\\s+$"; ""));'
# The target list: the current one minus every replaced title and every title the data carries,
# then the data's rules appended in their file order. Pure function of (settings, data).
# shellcheck disable=SC2016
TARGET="$TITLE"'
  ($d[0].rules | map(title)) as $new | ($d[0].replaces) as $gone
  | ((.autoMode.soft_deny // []) | map(select((title as $t | ($new + $gone) | index($t)) == null)))
    + $d[0].rules'

target_list() { jq -c --slurpfile d "$data" "$TARGET" "$1"; }
applied() { [ "$(jq -c '.autoMode.soft_deny // []' "$1" 2>/dev/null)" = "$(target_list "$1" 2>/dev/null)" ]; }

if [ "$mode" = verify ]; then applied "$f"; exit $?; fi

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }

if applied "$real"; then
  printf '%s: already applied — autoMode.soft_deny in %s carries the named rules\n' "$N" "$real"; exit 0
fi
"$parity" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}

printf '%s: autoMode.soft_deny %s -> %s entries in %s\n' "$N" \
  "$(jq '(.autoMode.soft_deny // []) | length' "$real")" "$(target_list "$real" | jq length)" "$real"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/soft-deny-named-rules-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
want="$(target_list "$real")"
if ! jq --argjson l "$want" '.autoMode.soft_deny = $l' "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
same_rest=$( [ "$(jq -S 'del(.autoMode.soft_deny)' "$real")" = "$(jq -S 'del(.autoMode.soft_deny)' "$tmp")" ] && echo y )
if [ "$same_rest" != y ] || [ "$want" != "$(jq -c '.autoMode.soft_deny' "$tmp")" ]; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: applied for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$N" "$bdir"
"$parity" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
applied "$f" || { printf '%s: did NOT verify\n' "$N" >&2; exit 1; }
printf '%s: verified.\n' "$N"
