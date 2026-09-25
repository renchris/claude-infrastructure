#!/bin/bash
# migration-class: c10
# migration-step: set "bashOutputMaxChars": 16000 in the ONE shared ~/.claude/settings.json every account links to since 0037 — so ALL accounts at once. A Bash result over 16,000 chars (today 30,000) is saved to a file and the model gets a ~2 KB preview and the path. Replay over 14.96 days: +$309-424 net list-weighted, +0.3% turns, band re-read rate 25-35% (conviction 70%). It refuses unless cc-settings-parity reports every account linked, and leaves an operator-set value other than 16000 alone. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0041-bash-output-max-chars.sh --confirm settings.json
# migration-verify: "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1 && jq -e '.bashOutputMaxChars == 16000' "$HOME/.claude/settings.json" >/dev/null
#
# The verifier is config-dir-INVARIANT (as 0036-0040): one shared file, one answer from every dir.
#
# ══ 0041 — Bash output persisted above 16k chars (token-efficiency rank 16, wave 3) ═════════════════
# Claude Code 2.1.280 reads `bashOutputMaxChars` from the merged settings (binary: "How many characters
# of a successful Bash or PowerShell command's output Claude receives inline (default 30000; values
# clamp to 4000-128000)"); a longer result is persisted to a file and replaced by a preview. Tool output
# is re-read from cache on every later request of its context, so each result in the 16-30k band costs
# its size on ~41 later requests.
#
# MEASURED BEFORE STAGING (docs/research/token-efficiency-2026-09-23/eval/wave3/r16-bash-cap.md, replay
# of 6,914 transcripts): 1,944 band results, 40.7M chars. Saving $554 gross; cost of follow-up re-reads
# and their extra turns $130-276 on the central and brief-defined rates, so net +$259 to +$424 per
# 14.96 days with or without 0039 (0039's read regex exempts 87% of the band, so the two barely
# overlap); extra turns 0.3-0.4% of all turns. The no-baseline worst case (every source re-touch
# charged to persistence) nets -$14 to +$42 with a 64-72% re-read rate; that is why conviction is 70%.
#
# SAFETY. Edits the REAL file once (README rule 7), backs it up, verifies BY CONTENT that the only
# change is the one key, and reads the effect back. Idempotent. Takes effect in NEW sessions.
# Revert: delete the key (default 30000 returns), or restore the printed backup.
#
# Usage: bash migrations/0041-bash-output-max-chars.sh --dry-run
#        bash migrations/0041-bash-output-max-chars.sh --confirm settings.json
# bash 3.2-safe.
set -uo pipefail

VAL=16000
f="$HOME/.claude/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
command -v jq >/dev/null 2>&1 || { printf '0041: jq required — nothing written\n' >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '0041: --confirm must name its target: --confirm settings.json\n' >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '0041: unknown argument %s (use --dry-run or --confirm settings.json)\n' "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '0041: pass --dry-run to preview or --confirm settings.json to apply\n' >&2; exit 2; }

[ -f "$f" ] || { printf '0041: %s not found — nothing written\n' "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '0041: %s is not valid JSON — nothing written\n' "$real" >&2; exit 1; }

cur=$(jq -r '.bashOutputMaxChars // "unset"' "$real")
[ "$cur" = "$VAL" ] && { printf '0041: already applied — %s has bashOutputMaxChars %s\n' "$real" "$VAL"; exit 0; }
[ "$cur" = unset ] || { printf '0041: %s already sets bashOutputMaxChars to %s — an operator value, left unchanged\n' "$real" "$cur" >&2; exit 1; }
"$parity" check >/dev/null 2>&1 || {
  printf '0041: REFUSED — accounts do not all share %s (%s check failed); the cap would reach some accounts and not others. Converge with 0037 first.\n' "$f" "$parity" >&2
  exit 1
}

printf '0041: will set in %s: "bashOutputMaxChars": %s\n' "$real" "$VAL"
[ "$mode" = dry ] && { printf '0041: DRY RUN — nothing written\n'; exit 0; }

bdir="$HOME/.claude/backups/bash-output-max-chars-0041-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '0041: backup FAILED — nothing written\n' >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-0041-$$"
if ! jq --argjson v "$VAL" '.bashOutputMaxChars = $v' "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0041: jq edit FAILED — nothing written\n' >&2; exit 1
fi
same_rest=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" '($a[0] | del(.bashOutputMaxChars)) == ($b[0] | del(.bashOutputMaxChars))')
if [ "$same_rest" != true ] || ! jq -e --argjson v "$VAL" '.bashOutputMaxChars == $v' "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0041: edit did not verify by content — nothing written\n' >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '0041: write FAILED — nothing written\n' >&2; exit 1; }
printf '0041: bashOutputMaxChars %s for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$VAL" "$bdir"
"$parity" check >/dev/null 2>&1 || printf '0041: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$bdir" "$real" >&2
jq -e --argjson v "$VAL" '.bashOutputMaxChars == $v' "$f" >/dev/null && printf '0041: verified — %s carries bashOutputMaxChars %s.\n' "$f" "$VAL"
