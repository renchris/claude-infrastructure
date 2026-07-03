#!/bin/bash
# live-session-registry.sh — durable per-worktree liveness registry for worktree-gc.
#
# WHY: the reaper's cwd/lsof liveness scan is flaky — live `claude` procs routinely
# report cwd=/ (verified 2026-06-19), so a single bad pass made a LIVE session's
# worktree look dead and it was reaped (project-worktree-gc-event-driven-2026-06-18).
# This records a POSITIVE, durable signal: the session's `claude`-ancestor PID. The
# reaper keeps any worktree whose registry PID is alive (`kill -0`) — deterministic,
# independent of cwd/lsof timing. Crash-safe: a dead PID is swept by kill -0, so a
# session that dies without SessionEnd self-heals (entry goes stale → ignored/removed).
#
# Wired on SessionStart (register) + SessionEnd (unregister) in ~/.claude/settings.json.
# Scope: only ~/Development/.worktrees/* (the reaper's reapable domain). Global (not
# project) so it is live for EVERY session immediately — no per-worktree-checkout lag.
# Fail-safe: never blocks the session (always exit 0). bash 3.2-safe.
REG_DIR="$HOME/.reso/live-sessions"
input=$(cat 2>/dev/null)
command -v jq >/dev/null 2>&1 || exit 0

ev=$(printf '%s' "$input"  | jq -r '.hook_event_name // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty'            2>/dev/null)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty'     2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

# Only sessions sitting in a reapable worktree matter.
case "$cwd" in
  "$HOME/Development/.worktrees/"*) ;;
  *) exit 0 ;;
esac
base=$(basename "$cwd")
mkdir -p "$REG_DIR" 2>/dev/null

if [ "$ev" = "SessionEnd" ]; then
  # Only remove if it's ours (basename is unique per worktree, but match sid to be safe).
  if [ -f "$REG_DIR/$base" ]; then
    have=$(cut -f2 "$REG_DIR/$base" 2>/dev/null)
    { [ -z "$sid" ] || [ "$have" = "$sid" ]; } && rm -f "$REG_DIR/$base" 2>/dev/null
  fi
  exit 0
fi

# Register (SessionStart / Resume / Clear — anything non-End): walk up to the durable
# `claude` ancestor PID (NOT the /bin/sh hook shim — the teammate-lifecycle $PPID lesson).
pid="$PPID"; cpid=""; i=0
while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null && [ "$i" -lt 12 ]; do
  c=$(ps -o comm= -p "$pid" 2>/dev/null); c="${c##*/}"
  case "$c" in
    claude|claude.exe|claude-*) cpid="$pid"; break ;;
  esac
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  i=$((i + 1))
done
[ -z "$cpid" ] && cpid="$PPID"   # fallback: still a live descendant anchor

printf '%s\t%s\t%s\n' "$cpid" "$sid" "$cwd" > "$REG_DIR/$base" 2>/dev/null
exit 0
