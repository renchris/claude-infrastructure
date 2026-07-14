#!/bin/bash
# session-register.sh — SessionStart hook for the cross-session comms feature.
#
# Records this iTerm2 pane in an account-agnostic registry so ANY session (any
# account / config-dir) can resolve a friendly name → iTerm2 pane UUID and ping
# it with `cc-notify` (the it2 keystroke transport). Paired with
# session-deregister.sh (SessionEnd) and the `cc-sessions` lister.
#
# Registry dir: $HOME/.claude/cc-registry/<paneUUID>.json  — FIXED $HOME/.claude,
#   NOT $CLAUDE_CONFIG_DIR: the whole point is CROSS-account addressing (a next2
#   session must resolve a next session's name), and per-account config dirs are
#   isolated. Deliberately NOT ~/.claude/sessions/ — that dir is Claude Code's
#   OWN per-account <pid>.json session registry plus this repo's <sid>.plan pins
#   (hooks/plan-pin-session.sh); layering a third schema there would be fragile.
#   See docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md.
#
# Entry: {paneUUID, name, cwd, account, pid, startedAt}. Name defaults to
#   <cwd-basename>-<short-uuid>; override with CC_SESSION_NAME.
#
# Fail-safe: never blocks the session (always exit 0). Needs jq + a valid
#   $ITERM_SESSION_ID (an iTerm2 pane). bash 3.2-safe.
set -uo pipefail

input=$(cat 2>/dev/null)

# --- FAIL-OPEN CONTRACT (P8-GO condition 1) ----------------------------------------------------
# This runs on EVERY session start, on every account. A registration spine that can block, delay,
# or kill a startup inverts its own purpose — so ALL work happens inside register(), under a HARD
# timeout, and this hook ALWAYS exits 0 no matter what happens inside. Registration is best-effort
# BY CONSTRUCTION: a missing row degrades the board (one session we cannot see); it must never cost
# a session. Typical cost is <100ms (2 jq + a few ps); the cap only bites if something hangs.
P8_TIMEOUT="${P8_REGISTER_TIMEOUT:-3}"

register() {
command -v jq >/dev/null 2>&1 || return 0

# Pane UUID from $ITERM_SESSION_ID (strip the "wNtNpN:" prefix → bare UUID the
# it2 shim addresses). No pane / not a UUID → nothing to register.
pane="${ITERM_SESSION_ID:-}"; pane="${pane##*:}"
case "$pane" in
  ''|*[!0-9A-Fa-f-]*) return 0 ;;
esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

# session_id — THE JOIN KEY (P8). Telemetry is keyed by session_id; the registry was keyed only by
# paneUUID, so the two could not be joined and cc-board had no way to notice a registered session
# that NEVER produced telemetry. That join is the whole spawn-death detector: registry row + no
# telemetry ever = a pane that came up and never rendered (D8 trigger 1), which the telemetry-spined
# board renders as ABSENCE — and absence is silent.
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

acct=$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" | sed 's/^\.//')
short="${pane%%-*}"
name="${CC_SESSION_NAME:-$(basename "$cwd")-$short}"

# Durable claude-ancestor PID (NOT the /bin/sh hook shim — the teammate-lifecycle
# $PPID lesson). Gives cc-sessions a cross-account `kill -0` liveness signal.
walk="$PPID"; cpid=""; i=0
while [ -n "$walk" ] && [ "$walk" -gt 1 ] 2>/dev/null && [ "$i" -lt 12 ]; do
  c=$(ps -o comm= -p "$walk" 2>/dev/null); c="${c##*/}"
  case "$c" in claude|claude.exe|claude-*) cpid="$walk"; break ;; esac
  walk=$(ps -o ppid= -p "$walk" 2>/dev/null | tr -d ' ')
  i=$((i + 1))
done
[ -z "$cpid" ] && cpid="$PPID"

started=$(( $(date +%s) * 1000 ))
reg_dir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
mkdir -p "$reg_dir" 2>/dev/null || return 0

# Atomic write (tmp + mv) so a concurrent cc-sessions read never sees a partial file.
tmp="$reg_dir/.$pane.$$.tmp"
if jq -n --arg paneUUID "$pane" --arg name "$name" --arg cwd "$cwd" \
        --arg account "$acct" --arg sessionId "$sid" \
        --argjson pid "$cpid" --argjson startedAt "$started" \
      '{paneUUID:$paneUUID, name:$name, cwd:$cwd, account:$account, pid:$pid,
        startedAt:$startedAt, session_id:(if $sessionId=="" then null else $sessionId end)}' \
      > "$tmp" 2>/dev/null; then
  mv -f "$tmp" "$reg_dir/$pane.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
else
  rm -f "$tmp" 2>/dev/null
fi
return 0
}

# Hard timeout + unconditional exit 0. `wait` on a killed worker returns non-zero; we swallow it.
register >/dev/null 2>&1 &
_w=$!
( sleep "$P8_TIMEOUT"; kill -9 "$_w" 2>/dev/null ) >/dev/null 2>&1 &
_k=$!
wait "$_w" >/dev/null 2>&1
kill -9 "$_k" >/dev/null 2>&1
wait "$_k" >/dev/null 2>&1
exit 0
