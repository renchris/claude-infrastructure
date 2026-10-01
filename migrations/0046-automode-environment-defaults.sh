#!/bin/bash
# migration-class: c10
# migration-step: put the literal "$defaults" first in autoMode.environment in ~/.claude/settings.json, which every account links to since 0037 — so ALL accounts at once. Our 7 reso entries REPLACED the classifier's shipped environment list (21 entries on 2.1.284), dropping "Trusted repo" and the definitions the shipped soft_deny rules lean on; "$defaults" inherits them and keeps our 7 after it. It refuses unless cc-settings-parity reports every account linked. It writes the auto-mode classifier's trust configuration, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0046-automode-environment-defaults.sh --confirm settings.json
# migration-verify: "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1 && jq -e '(.autoMode.environment // []) | index("$defaults") != null' "$HOME/.claude/settings.json" >/dev/null
#
# The verifier is config-dir-INVARIANT (as 0036-0041): one shared file, one answer from every dir.
#
# ══ 0046 — restore the auto-mode classifier's shipped environment (backlog d26bf99b6e9a) ══════════
# Claude Code's schema: "Include the literal string \"$defaults\" to inherit the built-in entries at
# that position." Our autoMode.environment carries 7 reso-only entries (Amplify, Fly, *.reso.gl,
# Turso, Replicache) and no "$defaults", so the shipped list — 21 entries on 2.1.284, among them
# **Trusted repo** ("the git repository the agent started in and its configured remotes") — is gone.
# A claude-infrastructure session runs with a trust block that never names its own repo.
#
# This VERSIONS ~/.claude/scripts/automode-restore-defaults.sh, a live-only file written 2026-08-23
# that looped `os.replace` over FIVE paths — on a linked fleet that replaces four symlinks with real
# files and re-forks every account (README rule 7). This writes the one real file once.
#
# NOT soft_deny. "$defaults" there was measured and ruled NO (docs/research/c10-staged-residuals-
# 2026-10.md § soft_deny): it would add the 44 shipped rules beside our 35, an estimated +7 to +14
# classifier blocks a day, ~80% from "Interfere With Workloads" on routine kill/pkill. The narrower
# named-rule set is 0048, held behind its own operator decision.
#
# SAFETY. Edits the REAL shared file once, backs it up, verifies BY CONTENT that the only change is
# "$defaults" prepended to autoMode.environment, and reads the effect back. Idempotent: a list that
# already carries "$defaults" anywhere is left alone. Revert: restore the printed backup, or delete
# the "$defaults" element. Auto-mode config is read at session start, so it takes effect in NEW
# sessions.
#
# Usage: bash migrations/0046-automode-environment-defaults.sh --dry-run
#        bash migrations/0046-automode-environment-defaults.sh --check    # preflight, writes nothing
#        bash migrations/0046-automode-environment-defaults.sh --verify   # is the effect live?
#        bash migrations/0046-automode-environment-defaults.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first)
# bash 3.2-safe.
set -uo pipefail

N=0046
# shellcheck disable=SC2016  # the literal JSON string Claude Code looks for, never an expansion
DEF='"$defaults"'
f="$HOME/.claude/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
command -v jq >/dev/null 2>&1 || { printf '%s: jq required — nothing written\n' "$N" >&2; exit 1; }

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

# shellcheck disable=SC2016  # "$defaults" is the literal JSON string Claude Code looks for
has_defaults() { jq -e '(.autoMode.environment // []) | index("$defaults") != null' "$1" >/dev/null 2>&1; }

if [ "$mode" = verify ]; then
  "$parity" check >/dev/null 2>&1 && has_defaults "$f"; exit $?
fi

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }

if has_defaults "$real"; then
  printf '%s: already applied — autoMode.environment in %s carries %s\n' "$N" "$real" "$DEF"; exit 0
fi
"$parity" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed); the change would reach some accounts and not others. Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}

n_before=$(jq '(.autoMode.environment // []) | length' "$real")
printf '%s: will prepend %s to %s .autoMode.environment (%s entries kept after it)\n' "$N" "$DEF" "$real" "$n_before"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/automode-environment-defaults-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
# shellcheck disable=SC2016
if ! jq '.autoMode.environment = (["$defaults"] + (.autoMode.environment // []))' "$real" > "$tmp" 2>/dev/null \
   || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# BY CONTENT: everything but autoMode.environment is the same document, and environment is the old
# list with "$defaults" in front.
same_rest=$( [ "$(jq -S 'del(.autoMode.environment)' "$real")" = "$(jq -S 'del(.autoMode.environment)' "$tmp")" ] && echo y )
# shellcheck disable=SC2016
want=$(jq -c '["$defaults"] + (.autoMode.environment // [])' "$real")
got=$(jq -c '.autoMode.environment' "$tmp")
if [ "$same_rest" != y ] || [ "$want" != "$got" ]; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: applied for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$N" "$bdir"
"$parity" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
has_defaults "$f" || { printf '%s: did NOT verify — %s lacks %s\n' "$N" "$f" "$DEF" >&2; exit 1; }
printf '%s: verified — autoMode.environment in %s starts with %s.\n' "$N" "$f" "$DEF"
