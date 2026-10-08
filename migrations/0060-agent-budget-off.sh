#!/bin/bash
# migration-class: c10
# migration-step: switch off the per-agent token budget before the server turns it on: add "CLAUDE_CODE_RIPPLING_TULIP": "0" to env in the ONE shared ~/.claude/settings.json (decision D6, docs/research/haiku55-upgrade-2026-10-07/decisions/D6-agent-budget-switch.md). It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0060-agent-budget-off.sh --confirm settings.json
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0060-agent-budget-off.sh" --verify
# migration-conflict: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0060-agent-budget-off.sh" --conflict
#
# ══ 0060 — CLAUDE_CODE_RIPPLING_TULIP=0 (decision D6, Haiku 5.5 upgrade 2026-10-08, binary 2.1.293) ══
# Claude Code 2.1.293 can give every agent it launches a token budget: the parent's Agent tool
# description gains "Each fresh agent you launch has a budget of N tokens", and the sub-agent sees a
# countdown. The client enforces nothing, but the model does: forced on, Opus 5.5 sub-agents finished
# an eight-file task in 0 of 9 runs against 6 of 6 with it off (Fisher p = 0.0002), and none of them
# errored. So the failure, if the vendor turns the server flag on, is partial work with no error to
# catch. `=0` removed the budget and the parent sentence in every run, and a settings env value beat a
# shell value. `CLAUDE_CODE_TOTAL_TOKENS_REMINDER=infinite` is NOT the switch: it rewrites the
# sub-agent's countdown to "Infinite tokens left", a change we have not evaluated.
#
# NOTHING CHANGES TODAY. On 2026-10-08 neither server flag (tengu_rippling_tulip,
# tengu_streamed_bumblebee) is cached on any account (`cc-agent-budget-flags`), so the control arm and
# the `=0` arm are indistinguishable. This is insurance against a server-side change, staged now so it
# is in place before the change rather than after the first partial result.
#
# WHAT WATCHES IT. `cc-agent-budget-flags` reads the flag caches; the SessionStart hook
# config-mirror-assert.sh warns in an account whose cache holds a flag ON while this key is absent;
# `cc-token-ledger --haiku` prints the same line; gate check16 re-proves on every binary move that
# `=0` still removes a forced budget (a rename would make this line inert, not harmful).
#
# BLAST RADIUS: adds ONE key to env. Nothing else changes; backed up first, verified by content. A
# DIFFERENT value already at that key is somebody's decision (a real budget, set on purpose), so it is
# REFUSED rc 3, never overwritten. Rollback: the printed `cp -p` line. Takes effect in NEW sessions.
#
# Usage: bash migrations/0060-agent-budget-off.sh --dry-run | --check | --verify | --conflict
#        bash migrations/0060-agent-budget-off.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure (nothing written) · 2 usage ·
#       3 REFUSED: an account settings.json is forked (run 0037 first) or a different value is set
# shellcheck disable=SC2016  # every single-quoted string below is a jq program; $k/$v are jq variables
set -uo pipefail

N=0060
KEY=CLAUDE_CODE_RIPPLING_TULIP
VAL=0
f="$HOME/.claude/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
command -v jq >/dev/null 2>&1 || { printf '%s: jq required — nothing written\n' "$N" >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --check) mode=check ;;
  --verify) mode=verify ;;
  --conflict) mode=conflict ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '%s: --confirm must name its target: --confirm settings.json\n' "$N" >&2; exit 2; }
             [ -z "${3:-}" ] || { printf '%s: unknown argument %s after --confirm settings.json\n' "$N" "$3" >&2; exit 2; }
             mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '%s: unknown argument %s (use --dry-run, --check, --verify, --conflict or --confirm settings.json)\n' "$N" "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '%s: pass --dry-run, --check, --verify, --conflict or --confirm settings.json\n' "$N" >&2; exit 2; }

# The value is compared as a string: settings env values are strings, and a JSON number 0 typed by
# hand reaches the binary as "0" too, so both read as applied.
is_set() { jq -e --arg k "$KEY" --arg v "$VAL" '((.env // {})[$k] | tostring) == $v' "$1" >/dev/null 2>&1; }
other_value() { jq -r --arg k "$KEY" --arg v "$VAL" '(.env // {})[$k] // empty | tostring | select(. != $v)' "$1" 2>/dev/null; }

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }
other="$(other_value "$real")"

case "$mode" in
  verify)
    is_set "$f" && { printf '%s: live — %s carries env.%s=%s\n' "$N" "$f" "$KEY" "$VAL"; exit 0; }
    printf '%s: NOT live — %s lacks env.%s=%s\n' "$N" "$f" "$KEY" "$VAL" >&2; exit 1 ;;
  conflict)
    [ -n "$other" ] && { printf '%s: overridden — env.%s is %s, not %s\n' "$N" "$KEY" "$other" "$VAL"; exit 0; }
    exit 1 ;;
esac

jq -e '(.env // {}) | type == "object"' "$real" >/dev/null 2>&1 \
  || { printf '%s: env is not an object — left unchanged\n' "$N" >&2; exit 1; }
"$parity" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}

if is_set "$real"; then
  printf '%s: already applied — %s carries env.%s=%s\n' "$N" "$real" "$KEY" "$VAL"
  exit 0
fi
if [ -n "$other" ]; then
  printf '%s: REFUSED — env.%s is already %s. A non-zero value is a budget someone set on purpose; nothing written. To take the switch, set it to %s by hand.\n' "$N" "$KEY" "$other" "$VAL" >&2
  exit 3
fi
printf '%s: will add env.%s=%s to %s\n' "$N" "$KEY" "$VAL" "$real"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: preflight ok — accounts share one file, the edit is well-formed; nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/agent-budget-off-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
EDIT='.env = ((.env // {}) + {($k): $v})'
if ! jq --arg k "$KEY" --arg v "$VAL" "$EDIT" "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# Two comparisons, not one `del(.env[$k])` on each side: a file with NO env object gains `env: {}`
# once the key is removed again, which is not equal to "no env" and would refuse a correct edit.
same_rest=$(jq -n --arg k "$KEY" --slurpfile a "$real" --slurpfile b "$tmp" '(($a[0] | del(.env)) == ($b[0] | del(.env))) and ((($a[0].env // {}) | del(.[$k])) == ($b[0].env | del(.[$k])))')
if [ "$same_rest" != true ] || ! is_set "$tmp"; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: env.%s=%s set. Backup: %s/settings.json (restore: cp -p %s/settings.json %s)\n' "$N" "$KEY" "$VAL" "$bdir" "$bdir" "$real"
"$parity" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with the line above\n' "$N" >&2
is_set "$f" || { printf '%s: did NOT verify through %s\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s carries env.%s=%s. New sessions pick it up.\n' "$N" "$f" "$KEY" "$VAL"
exit 0
