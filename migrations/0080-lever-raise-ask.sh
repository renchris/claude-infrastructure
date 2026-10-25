#!/bin/bash
# migration-class: c10
# migration-step: migration 0080 — add permissions.ask rules to ~/.claude/settings.json (which every account links to) for the four cc-lever verbs that raise a usage lever or release its trip: stage, candidate, promote and ack. Any session that runs one then stops for your yes, on top of cc-lever's own --confirm and ADVANCE gates, so only you can turn a lever up. Lowering (cc-lever off, the guard's trip) is not asked. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0080-lever-raise-ask.sh --confirm settings.json
# migration-subject: bin/cc-lever
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0080-lever-raise-ask.sh" --verify
#
# ══ 0080 — only the operator raises a lever (docs/plans/USAGE_LEVERS.md § W7+ §2 "Only the operator raises
# a stage", §5.1 and §5.3) ══
# cc-lever refuses a raise without --confirm, the latest ADVANCE, a fresh guard heartbeat and no open
# trip — but an agent can type --confirm. An ask rule puts the operator's yes in front of the call
# itself. Rules are prefix matches, so each verb is asked in the three spellings a session uses: the
# bare name on PATH, ~/.claude/bin/cc-lever and the absolute $HOME path (MEMORY allow-rule-prefix-
# misses-bash-wrapper). Residual, stated: an interpreter-prefixed form (`python3 …/cc-lever stage`) is
# not matched by a prefix rule; cc-lever's own gates still hold there.
#
# SAFETY. Edits the ONE shared ~/.claude/settings.json every account links to (0037), backs it up to
# ~/.claude/backups/lever-raise-ask-0080-<ts>/ in the layout `bash scripts/c10-batch.sh --rollback
# <dir>` restores, and verifies BY CONTENT that the only change is the appended ask entries. Idempotent
# (a rule already present is not added twice). Revert: the rollback above, or delete the entries.
# Takes effect in NEW sessions.
#
# Usage: bash migrations/0080-lever-raise-ask.sh --dry-run | --check | --verify
#        bash migrations/0080-lever-raise-ask.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage (no --confirm:
#       nothing written) · 3 REFUSED, an account settings.json is still forked (run 0037 first) ·
#       4 REFUSED, the live layer lacks bin/cc-lever (converge first)
# Seams (tests): CC_SETTINGS_PARITY_BIN. bash 3.2-safe.
set -uo pipefail

N=0080
f="$HOME/.claude/settings.json"
cli="$HOME/.claude/bin/cc-lever"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
# Through its interpreter, never by path: a #! exec keeps ~1.1 KiB of kernel memory on macOS 15.8.1
# (docs/research/kalloc-longterm-2026-10-21/REPORT.md). Read from its own #! line, so a stub still runs.
_pl=""; IFS= read -r _pl < "$parity" 2>/dev/null || true
case "$_pl" in *python3*) parity_cmd=(/usr/bin/env python3 "$parity") ;; *) parity_cmd=("$parity") ;; esac
command -v jq >/dev/null 2>&1 || { printf '%s: jq required — nothing written\n' "$N" >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --check) mode=check ;;
  --verify) mode=verify ;;
  --confirm)
    case "${2:-settings.json}" in
      settings.json) mode=apply ;;
      *) printf '%s: --confirm names its target: --confirm settings.json (got %s)\n' "$N" "$2" >&2; exit 2 ;;
    esac ;;
  '') printf '%s: refused — pass --dry-run, --check, --verify or --confirm settings.json; nothing written\n' "$N" >&2; exit 2 ;;
  *) printf '%s: unknown argument %s (use --dry-run, --check, --verify or --confirm settings.json)\n' "$N" "$1" >&2; exit 2 ;;
esac

RULES="$(for v in stage candidate promote ack; do
  # shellcheck disable=SC2088  # the literal "~/" is the spelling a session types; the rule stores it as is
  printf 'Bash(cc-lever %s:*)\nBash(~/.claude/bin/cc-lever %s:*)\nBash(%s/.claude/bin/cc-lever %s:*)\n' "$v" "$v" "$HOME" "$v"
done | jq -R . | jq -sc .)"

missing() { # <settings> → the rules not yet in .permissions.ask, as a JSON array
  jq -c --argjson r "$RULES" '(.permissions.ask // []) as $a | [$r[] | select(. as $x | $a | index($x) | not)]' "$1"
}

real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi

if [ "$mode" = verify ]; then
  [ -f "$real" ] && [ "$(missing "$real" 2>/dev/null)" = "[]" ]; exit $?
fi

[ -f "$real" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }

add="$(missing "$real")"
if [ "$add" = "[]" ]; then
  printf '%s: already applied — every cc-lever raise verb is asked in %s\n' "$N" "$real"; exit 0
fi
"${parity_cmd[@]}" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed); the rules would reach some accounts and not others. Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}
[ -f "$cli" ] || {
  printf '%s: REFUSED — the live layer lacks %s. Converge first: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' "$N" "$cli" >&2
  exit 4
}

printf '%s: will append to %s .permissions.ask: %s\n' "$N" "$real" "$add"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/lever-raise-ask-$N-$(date +%Y%m%d%H%M%S)"
if ! mkdir -p "$bdir" || ! : > "$bdir/MANIFEST" || ! cp -p "$real" "$bdir/shared.settings.json" \
   || ! cp -p "$real" "$bdir/settings.json"; then
  printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1
fi
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
if ! jq --argjson e "$add" '.permissions.ask = ((.permissions.ask // []) + $e)' "$real" > "$tmp" 2>/dev/null \
   || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# BY CONTENT: everything but .permissions.ask is the same document, and ask gained exactly the
# missing rules at its end.
same_rest=$( [ "$(jq -S 'del(.permissions.ask)' "$real")" = "$(jq -S 'del(.permissions.ask)' "$tmp")" ] && echo y )
want=$(jq -c --argjson e "$add" '(.permissions.ask // []) + $e' "$real")
got=$(jq -c '.permissions.ask' "$tmp")
if [ "$same_rest" != y ] || [ "$want" != "$got" ]; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: asked for every account. Backup: %s (undo: bash ~/Development/claude-infrastructure/scripts/c10-batch.sh --rollback %s). Takes effect in NEW sessions.\n' "$N" "$bdir" "$bdir"
"${parity_cmd[@]}" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
[ "$(missing "$f")" = "[]" ] || { printf '%s: did NOT verify — %s lacks a rule\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s asks before every cc-lever raise verb.\n' "$N" "$f"
