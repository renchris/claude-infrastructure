#!/bin/bash
# reset-hard-activate.sh — OPERATOR-run wiring for the reset-hard-shadow-allow PreToolUse hook (C10).
# Agents cannot self-edit settings.json (it governs their own permissions), so this is the human
# hand-step. It is IDEMPOTENT, backs up every file it touches, and validates JSON before writing
# (temp → jq-check → mv), so a re-run or a partial run can never corrupt a settings file.
#
#   Dry-run (default): ./docs/activation/reset-hard-activate.sh
#   Apply:             ./docs/activation/reset-hard-activate.sh --apply
#   Rollback:          restore the printed *.bak-<ts> files (commands printed at the end).
#
# WHAT THIS DOES (per config dir):
#   1. symlink  $REPO/hooks/reset-hard-shadow-allow.sh → ~/.claude/hooks/  (all 5 settings reference
#      the single ~/.claude/hooks/ path).
#   2. register {type:command, command:~/.claude/hooks/reset-hard-shadow-allow.sh, timeout:5} into the
#      PreToolUse "Bash" matcher's hooks array — appended (runs alongside the existing guards).
#
# WIRING ONLY STARTS THE SHADOW SOAK — IT DOES NOT AUTO-ALLOW ANYTHING.
#   The hook ships in SHADOW mode: once wired it LOGS a would-allow for each `git reset --hard
#   origin/main|@{u}` that occurs on a clean tree in a linked worktree, but emits NO decision — the
#   `Bash(git reset --hard:*)` ask prompt STILL fires (every real reset is still human/desk-approved).
#   AUTO-ALLOW turns on only after you review a clean soak and ARM deliberately — a separate step
#   this script never performs (Part B §B.5: wire in shadow → arm after clean soak):
#       ~/.claude/hooks/reset-hard-shadow-allow.sh status        # inspect the soak
#       ~/.claude/hooks/reset-hard-shadow-allow.sh arm --confirm  # arm (auto-allow live)
#       ~/.claude/hooks/reset-hard-shadow-allow.sh shadow         # revert to log-only
#   The static Bash(git reset --hard:*) ask rule is LEFT in place; a PreToolUse allow (once armed)
#   overrides it ONLY for the proven reflog-reversible shape, while every other reset still prompts.

set -uo pipefail
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SRC="$REPO/hooks/reset-hard-shadow-allow.sh"
# shellcheck disable=SC2088  # the literal ~ is INTENTIONAL — this string is stored in settings.json, which expands it
HOOK_CMD='~/.claude/hooks/reset-hard-shadow-allow.sh'          # the string stored in settings.json
HOOK_DEST="$HOME/.claude/hooks/reset-hard-shadow-allow.sh"     # tilde resolved for the fs ops
TS="$(date -u +%Y%m%dT%H%M%SZ)"
CONFIG_DIRS=( "$HOME/.claude" "$HOME/.claude-secondary" "$HOME/.claude-next" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary" )
BAKS=()

say(){ printf '%s\n' "$*"; }
[ -f "$HOOK_SRC" ] || { say "FATAL: hook source missing: $HOOK_SRC"; exit 1; }
command -v jq >/dev/null || { say "FATAL: jq required"; exit 1; }

say "reset-hard-activate ($([ $APPLY = 1 ] && echo APPLY || echo DRY-RUN)) — repo=$REPO"
say "(this wires the SHADOW hook only; arming is a separate step — see the header)"
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

# ── 2. register the hook in each settings.json PreToolUse Bash matcher (idempotent, structural) ─
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
  say "DONE — hook wired in SHADOW. It now LOGS would-allow events; it does NOT auto-allow yet."
  say "Soak:  ~/.claude/hooks/reset-hard-shadow-allow.sh status"
  say "Arm:   ~/.claude/hooks/reset-hard-shadow-allow.sh arm --confirm   (only after a clean soak)"
  if [ ${#BAKS[@]} -gt 0 ]; then
    say "Rollback (undo everything this run wrote):"
    for b in "${BAKS[@]}"; do say "  mv '$b' '${b%".bak-$TS"}'"; done
  fi
else
  say "DRY-RUN only — no files changed. Re-run with --apply to write."
fi
