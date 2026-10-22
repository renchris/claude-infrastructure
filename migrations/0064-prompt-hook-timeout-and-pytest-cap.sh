#!/bin/bash
# migration-class: c10
# migration-step: give the UserPromptSubmit hook handed-off-session-guard.sh a 5 s timeout and cap `pytest -n auto` at 3 workers per run (env PYTEST_XDIST_AUTO_NUM_WORKERS=3) in the ONE shared ~/.claude/settings.json (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md O1). It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0064-prompt-hook-timeout-and-pytest-cap.sh --confirm settings.json
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0064-prompt-hook-timeout-and-pytest-cap.sh" --verify
# migration-conflict: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0064-prompt-hook-timeout-and-pytest-cap.sh" --conflict
#
# ══ 0064 — prompt-hook timeout + pytest worker cap (load plan O1, 2026-10-12) ══
# 1. `"timeout": 5` on the UserPromptSubmit hook whose command ends in handed-off-session-guard.sh.
#    UserPromptSubmit hooks run in parallel and the prompt waits on the SLOWEST of them, so one hook
#    with no ceiling bounds every prompt by nothing. WP6 (de69938a4) made the guard cheap; the
#    timeout is the backstop for the day something it calls hangs. Every sibling in that event
#    already carries 5 or 10. Background: docs/research/load-hook-timeouts-2026-10-11/DESIGN.md "O1".
# 2. env `PYTEST_XDIST_AUTO_NUM_WORKERS=3`: pytest-xdist reads it as the value of `-n auto`, which
#    otherwise spawns one worker per core — measured ~46 workers machine-wide across concurrent
#    sessions, ~12-18 with the cap. An explicit `-n N` still wins.
#
# NOT COVERED: keychain-guard.sh and waiting-recycle.sh also carry no timeout (migrations/0009
# `wire()` notes the same three). Whether they should is an undecided operator call; when it is
# made, scripts/settings-hook-timeouts.sh --set-timeout is the tool for it.
#
# BLAST RADIUS: one key on one hook entry, one key in env. Nothing else changes; backed up first,
# verified by content. A DIFFERENT value already at either key is somebody's decision, so it is
# REFUSED rc 3, never overwritten. Rollback: the printed `cp -p` line. Takes effect in NEW sessions.
#
# Usage: bash migrations/0064-prompt-hook-timeout-and-pytest-cap.sh --dry-run | --check | --verify | --conflict
#        bash migrations/0064-prompt-hook-timeout-and-pytest-cap.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure (nothing written) · 2 usage ·
#       3 REFUSED: an account settings.json is forked (run 0037 first) or a different value is set
# shellcheck disable=SC2016  # every single-quoted string below is a jq program; $k/$v/$re/$t are jq variables
set -uo pipefail

N=0064
KEY=PYTEST_XDIST_AUTO_NUM_WORKERS
VAL=3
HOOK_RE='handed-off-session-guard\.sh$'
TMO=5
f="$HOME/.claude/settings.json"
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
  --conflict) mode=conflict ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '%s: --confirm must name its target: --confirm settings.json\n' "$N" >&2; exit 2; }
             [ -z "${3:-}" ] || { printf '%s: unknown argument %s after --confirm settings.json\n' "$N" "$3" >&2; exit 2; }
             mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '%s: unknown argument %s (use --dry-run, --check, --verify, --conflict or --confirm settings.json)\n' "$N" "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '%s: pass --dry-run, --check, --verify, --conflict or --confirm settings.json\n' "$N" >&2; exit 2; }

# The guard's hook objects, wherever they sit under UserPromptSubmit.
GUARDS='[.hooks.UserPromptSubmit[]?.hooks[]? | select((.command // "") | test($re))]'
guard_count() { jq -r --arg re "$HOOK_RE" "$GUARDS | length" "$1" 2>/dev/null || echo 0; }
# Applied = at least one guard entry, and every guard entry carries exactly this timeout.
tmo_set() { jq -e --arg re "$HOOK_RE" --argjson t "$TMO" "$GUARDS as \$g | (\$g | length) > 0 and all(\$g[]; .timeout == \$t)" "$1" >/dev/null 2>&1; }
tmo_other() { jq -r --arg re "$HOOK_RE" --argjson t "$TMO" "$GUARDS | map(.timeout // empty | select(. != \$t)) | first // empty | tostring" "$1" 2>/dev/null; }
# Env values are compared as strings: settings env values are strings, and a JSON number 3 typed by
# hand reaches the process as "3" too, so both read as applied.
env_set() { jq -e --arg k "$KEY" --arg v "$VAL" '((.env // {})[$k] | tostring) == $v' "$1" >/dev/null 2>&1; }
env_other() { jq -r --arg k "$KEY" --arg v "$VAL" '(.env // {})[$k] // empty | tostring | select(. != $v)' "$1" 2>/dev/null; }

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }
o_tmo="$(tmo_other "$real")"
o_env="$(env_other "$real")"

case "$mode" in
  verify)
    tmo_set "$f" && env_set "$f" && { printf '%s: live — %s carries timeout %s on handed-off-session-guard.sh and env.%s=%s\n' "$N" "$f" "$TMO" "$KEY" "$VAL"; exit 0; }
    tmo_set "$f" || printf '%s: NOT live — handed-off-session-guard.sh in %s lacks "timeout": %s\n' "$N" "$f" "$TMO" >&2
    env_set "$f" || printf '%s: NOT live — %s lacks env.%s=%s\n' "$N" "$f" "$KEY" "$VAL" >&2
    exit 1 ;;
  conflict)
    rc=1
    [ -n "$o_tmo" ] && { printf '%s: overridden — handed-off-session-guard.sh timeout is %s, not %s\n' "$N" "$o_tmo" "$TMO"; rc=0; }
    [ -n "$o_env" ] && { printf '%s: overridden — env.%s is %s, not %s\n' "$N" "$KEY" "$o_env" "$VAL"; rc=0; }
    exit "$rc" ;;
esac

jq -e '(.env // {}) | type == "object"' "$real" >/dev/null 2>&1 \
  || { printf '%s: env is not an object — left unchanged\n' "$N" >&2; exit 1; }
[ "$(guard_count "$real")" -gt 0 ] 2>/dev/null \
  || { printf '%s: no UserPromptSubmit hook ends in handed-off-session-guard.sh in %s — nothing to time out; nothing written\n' "$N" "$real" >&2; exit 1; }
"${parity_cmd[@]}" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}

if tmo_set "$real" && env_set "$real"; then
  printf '%s: already applied — %s carries timeout %s on handed-off-session-guard.sh and env.%s=%s\n' "$N" "$real" "$TMO" "$KEY" "$VAL"
  exit 0
fi
if [ -n "$o_tmo" ] || [ -n "$o_env" ]; then
  [ -n "$o_tmo" ] && printf '%s: REFUSED — handed-off-session-guard.sh already has timeout %s; somebody chose it, nothing written.\n' "$N" "$o_tmo" >&2
  [ -n "$o_env" ] && printf '%s: REFUSED — env.%s is already %s; somebody chose it, nothing written.\n' "$N" "$KEY" "$o_env" >&2
  exit 3
fi
tmo_set "$real" || printf '%s: will add "timeout": %s to handed-off-session-guard.sh under UserPromptSubmit in %s\n' "$N" "$TMO" "$real"
env_set "$real" || printf '%s: will add env.%s=%s to %s\n' "$N" "$KEY" "$VAL" "$real"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: preflight ok — accounts share one file, the edit is well-formed; nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/prompt-hook-timeout-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
EDIT='.hooks.UserPromptSubmit |= map(if (.hooks | type) == "array" then .hooks |= map(if ((.command // "") | test($re)) then .timeout = $t else . end) else . end)
      | .env = ((.env // {}) + {($k): $v})'
if ! jq --arg re "$HOOK_RE" --argjson t "$TMO" --arg k "$KEY" --arg v "$VAL" "$EDIT" "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# Both sides are normalized the same way (guard timeouts dropped, the env key dropped, env defaulted
# to {}) before comparing, so a file with NO env object is not refused for gaining one.
NORM='def norm: (if (.hooks.UserPromptSubmit | type) == "array" then .hooks.UserPromptSubmit |= map(if (.hooks | type) == "array" then .hooks |= map(if ((.command // "") | test($re)) then del(.timeout) else . end) else . end) else . end) | .env = ((.env // {}) | del(.[$k]));
      ($a[0] | norm) == ($b[0] | norm)'
same_rest=$(jq -n --arg re "$HOOK_RE" --arg k "$KEY" --slurpfile a "$real" --slurpfile b "$tmp" "$NORM")
if [ "$same_rest" != true ] || ! tmo_set "$tmp" || ! env_set "$tmp"; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: timeout and env set. Backup: %s/settings.json (restore: cp -p %s/settings.json %s)\n' "$N" "$bdir" "$bdir" "$real"
"${parity_cmd[@]}" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with the line above\n' "$N" >&2
{ tmo_set "$f" && env_set "$f"; } || { printf '%s: did NOT verify through %s\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s carries timeout %s on handed-off-session-guard.sh and env.%s=%s. New sessions pick it up.\n' "$N" "$f" "$TMO" "$KEY" "$VAL"
exit 0
