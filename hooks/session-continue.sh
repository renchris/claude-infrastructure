#!/usr/bin/env bash
# session-continue.sh — 🔧 loose-ends continuation loop (agent-set sentinel + Stop-hook actuator).
#
# WHY: a Stop hook fired on its own is SCOPE-BLIND — a shell script can't tell an
# in-scope loose end from an intentional pause or out-of-scope dirt, so a standalone
# one loops on the wrong things (that's why the Session Close Protocol banned it).
# This design keeps scope-judgment with the AGENT: the agent (which classifies each
# close as 🔧 / ✅ / 📦 / ⛔ / 📤) ARMS a sentinel ONLY on 🔧, and this script is a
# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
# loop cap so a stuck gate can never run away.
#
# Agent interface (run from the session's worktree):
#   session-continue.sh set "<the ONE next step>"   # arm — ONLY on the 🔧 state
#   session-continue.sh clear                        # disarm — on ✅/📦/⛔/📤, read-only, or "...and stop"
#   session-continue.sh status                       # inspect
#
# Claude Code calls it with NO args + the Stop JSON on stdin → actuation mode.
#
# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
# keyed by config-dir + cwd hash, so it never gets committed and concurrent sessions —
# including different accounts (each with its own CLAUDE_CONFIG_DIR) — don't collide.
#
# NOTE: deliberately NO `set -e` — a Stop hook that exits 2 *blocks the stop*, so an
# accidental non-zero exit could force a false continuation. Every path ends `exit 0`.

state_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state"
mkdir -p "$state_dir" 2>/dev/null

# Sentinel path for a given working dir (stable hash → one file per worktree).
sentinel_for() {
  local h
  h=$(printf '%s|%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "$1" | shasum 2>/dev/null | cut -c1-16)
  printf '%s/continue-%s' "$state_dir" "$h"
}

# ---- Agent CLI mode -------------------------------------------------------------
case "${1:-}" in
  set)
    f=$(sentinel_for "$PWD")
    printf '%s' "${2:-Continue the in-scope work.}" > "$f"
    rm -f "${f}.count" 2>/dev/null   # fresh chain → reset the loop counter
    echo "armed → $f"
    exit 0 ;;
  clear)
    f=$(sentinel_for "$PWD")
    rm -f "$f" "${f}.count" 2>/dev/null
    echo "cleared"
    exit 0 ;;
  status)
    f=$(sentinel_for "$PWD")
    if [ -f "$f" ]; then echo "ARMED ($(cat "${f}.count" 2>/dev/null || echo 0) continuations): $(cat "$f")"; else echo "inactive"; fi
    exit 0 ;;
esac

# ---- Stop-hook actuation mode (no recognized arg; JSON on stdin) ----------------
input=$(cat 2>/dev/null || printf '{}')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd="$PWD"
f=$(sentinel_for "$cwd")

# No sentinel → the agent did NOT request continuation → allow the stop.
if [ ! -f "$f" ]; then
  rm -f "${f}.count" 2>/dev/null
  exit 0
fi

# Hard loop cap (guards a stuck gate / non-progressing agent).
MAX="${CLAUDE_CONTINUE_MAX:-8}"
n=$(cat "${f}.count" 2>/dev/null); [ -n "$n" ] || n=0
if [ "$n" -ge "$MAX" ]; then
  rm -f "$f" "${f}.count" 2>/dev/null
  printf 'session-continue: hit cap (%s continuations) — allowing stop, sentinel cleared.\n' "$MAX" >&2
  exit 0   # non-2 exit → does NOT block; just surfaces the note
fi
printf '%s' $((n + 1)) > "${f}.count"

step=$(cat "$f")
reason="🔧 Loose ends remain — do NOT stop yet. Next: ${step}

When this is done (state ✅/📦), blocked on the user (⛔), or out of context (📤), run \`~/.claude/hooks/session-continue.sh clear\` so the session can close. (continuation ${n}/${MAX} of $((n + 1)))"

# decision:block blocks the stop; reason is fed back to the model as the next turn.
jq -n --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
