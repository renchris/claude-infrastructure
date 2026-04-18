#!/bin/bash
# ~/.claude/scripts/current-session-plan.sh — canonical oracle for "what plan
# does THIS Claude Code session own?". Single source of truth; any skill,
# hook, or slash command can call it and never reimplement the lookup.
#
# Usage:
#   current-session-plan.sh [--verbose]
#
# Exit codes:
#   0 — absolute plan file path printed to stdout
#   2 — REQUIRES_USER: no plan found; caller should AskUserQuestion
#   1 — tooling failure (jq missing, etc.)
#
# Layered resolution (first hit wins):
#   L1  sidecar  ~/.claude/sessions/<sid>.plan — O(1), written by
#                plan-pin-session.sh PostToolUse hook on ExitPlanMode.
#   L2  transcript — most-recent Edit/Write/MultiEdit tool_input.file_path
#                matching a plan pattern, from THIS session's .jsonl.
#   L3  exit 2 — caller owns the prompt.
#
# Deterministic: no mtime heuristics. PID walk from $$ to the enclosing
# `claude` process establishes session identity; session file on disk
# maps PID → sessionId → cwd → transcript.

set -uo pipefail

VERBOSE=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1
log() { [[ $VERBOSE -eq 1 ]] && echo "[current-session-plan] $*" >&2 || true; }

command -v jq >/dev/null || { echo "ERROR: jq required" >&2; exit 1; }

# ---------------------------------------------------------------------
# Preflight — find this session's PID by walking ancestors until we hit
# the `claude` node binary. Avoids false matches on shell snapshots +
# hook scripts whose path strings contain "claude".
# ---------------------------------------------------------------------
CLAUDE_PID=""
CURRENT=$$
DEPTH=0
while [ -n "$CURRENT" ] && [ "$CURRENT" != "1" ] && [ $DEPTH -lt 20 ]; do
  CMD=$(ps -p "$CURRENT" -o command= 2>/dev/null || echo "")
  # Match executable basename `claude` (optionally with args), not paths
  # that merely contain "claude" as a substring (shell-snapshots, hooks).
  case "$CMD" in
    */claude|*/claude\ *|claude|claude\ *)
      CLAUDE_PID="$CURRENT"
      break
      ;;
  esac
  PPID_OF=$(ps -o ppid= -p "$CURRENT" 2>/dev/null | tr -d ' ')
  [ -z "$PPID_OF" ] && break
  CURRENT="$PPID_OF"
  DEPTH=$((DEPTH+1))
done

if [ -z "$CLAUDE_PID" ]; then
  log "no claude ancestor PID in process tree"
  echo "REQUIRES_USER: not running inside an active claude session" >&2
  exit 2
fi

SESSION_FILE="$HOME/.claude/sessions/$CLAUDE_PID.json"
if [ ! -f "$SESSION_FILE" ]; then
  log "session file missing: $SESSION_FILE"
  echo "REQUIRES_USER: session metadata not found for PID $CLAUDE_PID" >&2
  exit 2
fi

SESS=$(jq -r '.sessionId // empty' "$SESSION_FILE")
CWD=$(jq -r '.cwd // empty' "$SESSION_FILE")
if [ -z "$SESS" ] || [ -z "$CWD" ]; then
  log "malformed session file"
  echo "REQUIRES_USER: $SESSION_FILE missing sessionId or cwd" >&2
  exit 2
fi
log "pid=$CLAUDE_PID session=$SESS cwd=$CWD"

# ---------------------------------------------------------------------
# L1 — sidecar pin written by plan-pin-session.sh hook on ExitPlanMode
# ---------------------------------------------------------------------
SIDECAR="$HOME/.claude/sessions/$SESS.plan"
if [ -f "$SIDECAR" ]; then
  PINNED=$(head -n 1 "$SIDECAR" | tr -d '\r\n')
  if [ -n "$PINNED" ] && [ -f "$PINNED" ]; then
    log "L1 sidecar hit: $PINNED"
    echo "$PINNED"
    exit 0
  fi
  log "L1 sidecar stale: $PINNED (target missing)"
fi

# ---------------------------------------------------------------------
# L2 — transcript scan: most recent Edit/Write/MultiEdit to a plan path
# ---------------------------------------------------------------------
SLUG=$(echo "$CWD" | sed 's|/|-|g')
TRANSCRIPT="$HOME/.claude/projects/$SLUG/$SESS.jsonl"
if [ ! -f "$TRANSCRIPT" ]; then
  log "transcript missing: $TRANSCRIPT"
  echo "REQUIRES_USER: session transcript not found at $TRANSCRIPT" >&2
  exit 2
fi

# Extract every file_path targeted by Edit/Write/MultiEdit, filter to plan
# patterns, take the last (most recent turn). This survives plan-file
# edits post-ExitPlanMode — unlike content-hash approaches.
LAST_PLAN_PATH=$(
  jq -r '
    .message?.content?                                       // empty
    | if type == "array" then
        .[]
        | select(.type == "tool_use"
                 and (.name == "Edit" or .name == "Write" or .name == "MultiEdit"))
        | .input.file_path // empty
      else empty end
  ' "$TRANSCRIPT" 2>/dev/null \
    | grep -E '(/\.claude/plans/|/\.claude-plans/|/docs/plans/)[^/]+\.md$' \
    | tail -1
)

if [ -n "$LAST_PLAN_PATH" ] && [ -f "$LAST_PLAN_PATH" ]; then
  log "L2 transcript-edit hit: $LAST_PLAN_PATH"
  echo "$LAST_PLAN_PATH"
  exit 0
fi
log "L2 no plan-file edit found in transcript"

# ---------------------------------------------------------------------
# L3 — surface to user
# ---------------------------------------------------------------------
echo "REQUIRES_USER: session plan could not be resolved. L1 (sidecar) miss; L2 (transcript Edit scan) no hit. Ask explicitly." >&2
exit 2
