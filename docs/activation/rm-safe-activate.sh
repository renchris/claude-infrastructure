#!/bin/bash
# rm-safe-activate.sh — OPERATOR-run wiring for the rm-safe-allowlist PreToolUse hook (C10).
# Agents cannot self-edit settings.json (it governs their own permissions), so this is the
# human hand-step. It is IDEMPOTENT, backs up every file it touches, and validates JSON before
# writing (temp → jq-check → mv), so a re-run or a partial run can never corrupt a settings file.
#
#   Dry-run (default): ./docs/activation/rm-safe-activate.sh
#   Apply:             ./docs/activation/rm-safe-activate.sh --apply
#   Rollback:          restore the printed *.bak-<ts> files (command printed at the end).
#
# What it does, per config dir:
#   1. symlink  $REPO/hooks/rm-safe-allowlist.sh → ~/.claude/hooks/  (all 5 settings reference the
#      single ~/.claude/hooks/ path; install.sh normally does this, we assert it here too).
#   2. register {type:command, command:~/.claude/hooks/rm-safe-allowlist.sh, timeout:5} into the
#      PreToolUse "Bash" matcher's hooks array — appended (runs alongside the existing guards).
# The static Bash(rm:*) ask rule is LEFT in place: a PreToolUse allow overrides it for safe targets,
# while every unsafe rm still falls through to the prompt.

set -uo pipefail
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SRC="$REPO/hooks/rm-safe-allowlist.sh"
# shellcheck disable=SC2088  # the literal ~ is INTENTIONAL — this string is stored in settings.json, which expands it
HOOK_CMD='~/.claude/hooks/rm-safe-allowlist.sh'          # the string stored in settings.json
HOOK_DEST="$HOME/.claude/hooks/rm-safe-allowlist.sh"     # tilde resolved for the fs ops
TS="$(date -u +%Y%m%dT%H%M%SZ)"
CONFIG_DIRS=( "$HOME/.claude" "$HOME/.claude-secondary" "$HOME/.claude-next" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary" )
BAKS=()

say(){ printf '%s\n' "$*"; }
[ -f "$HOOK_SRC" ] || { say "FATAL: hook source missing: $HOOK_SRC"; exit 1; }
command -v jq >/dev/null || { say "FATAL: jq required"; exit 1; }

say "rm-safe-activate ($([ $APPLY = 1 ] && echo APPLY || echo DRY-RUN)) — repo=$REPO"
say ""

# ── 1. hook script: executable + symlinked into ~/.claude/hooks (single source of truth) ──────
chmod +x "$HOOK_SRC" 2>/dev/null || true
if [ "$(readlink "$HOOK_DEST" 2>/dev/null)" = "$HOOK_SRC" ]; then
  say "hook symlink: already → $HOOK_SRC  (ok)"
else
  if [ $APPLY = 1 ]; then
    mkdir -p "$HOME/.claude/hooks"
    [ -e "$HOOK_DEST" ] && [ ! -L "$HOOK_DEST" ] && { cp -p "$HOOK_DEST" "$HOOK_DEST.bak-$TS"; BAKS+=("$HOOK_DEST.bak-$TS"); }
    ln -sf "$HOOK_SRC" "$HOOK_DEST" && say "hook symlink: linked → $HOOK_SRC"
  else
    say "hook symlink: WOULD link $HOOK_DEST → $HOOK_SRC"
  fi
fi
say ""

# ── 2. register the hook in each settings.json PreToolUse Bash matcher (idempotent) ───────────
# shellcheck disable=SC2016  # $cmd/$c are JQ variables (passed via --arg), NOT shell — single quotes are correct
JQ_PROG='
  ($cmd) as $c |
  .hooks             = (.hooks // {}) |
  .hooks.PreToolUse  = (.hooks.PreToolUse // []) |
  .hooks.PreToolUse |= (
    if any(.[]?; .matcher=="Bash")
    then map(if .matcher=="Bash"
             then .hooks = (
                    if any((.hooks // [])[]?; .command==$c) then (.hooks // [])
                    else ((.hooks // []) + [{"type":"command","command":$c,"timeout":5}]) end)
             else . end)
    else (. + [{"matcher":"Bash","hooks":[{"type":"command","command":$c,"timeout":5}]}])
    end)
'
for dir in "${CONFIG_DIRS[@]}"; do
  f="$dir/settings.json"
  if [ ! -f "$f" ]; then say "skip (no settings.json): $f"; continue; fi
  if jq -e --arg c "$HOOK_CMD" '[.hooks.PreToolUse[]?|select(.matcher=="Bash").hooks[]?|.command] | index($c) != null' "$f" >/dev/null 2>&1; then
    say "already registered: $f"
    continue
  fi
  if [ $APPLY = 1 ]; then
    cp -p "$f" "$f.bak-$TS"; BAKS+=("$f.bak-$TS")
    tmp="$f.tmp-$TS"
    if jq --arg cmd "$HOOK_CMD" "$JQ_PROG" "$f" > "$tmp" 2>/dev/null && jq -e . "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f"; say "registered:        $f  (backup: $f.bak-$TS)"
    else
      rm -f "$tmp"; say "FAILED (left intact): $f — jq transform did not validate"
    fi
  else
    tmp="$(mktemp)"
    if jq --arg cmd "$HOOK_CMD" "$JQ_PROG" "$f" > "$tmp" 2>/dev/null && jq -e . "$tmp" >/dev/null 2>&1; then
      say "WOULD register:    $f  (transform validates ✓)"
    else
      say "WOULD FAIL:        $f — transform did not validate (inspect manually)"
    fi
    rm -f "$tmp"
  fi
done

say ""
if [ $APPLY = 1 ]; then
  say "DONE. Verify: printf '{\"tool_input\":{\"command\":\"rm -rf artifacts\"}}' | $HOOK_CMD  # → permissionDecision:allow"
  if [ ${#BAKS[@]} -gt 0 ]; then
    say "Rollback (undo everything this run wrote):"
    for b in "${BAKS[@]}"; do say "  mv '$b' '${b%".bak-$TS"}'"; done
  fi
else
  say "DRY-RUN only — no files changed. Re-run with --apply to write."
fi
