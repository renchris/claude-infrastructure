#!/bin/bash
# UserPromptSubmit Hook — Memory Crystallization Nudge
#
# Periodic in-session reminder (every MEMORY_NUDGE_INTERVAL prompts, default 12)
# to persist DURABLE knowledge to MEMORY.md / a topic file, with the hermes-agent
# anti-capture list embedded. Fires while context is LIVE — UserPromptSubmit is
# the only event whose additionalContext reaches the model mid-session (Stop
# cannot inject; GH anthropics/claude-code#37559).
#
# Adapted from hermes-agent agent/background_review.py (nudge_interval=10), minus
# the autonomous write: this NUDGES, the model decides + the human reviews.
set -euo pipefail

INTERVAL="${MEMORY_NUDGE_INTERVAL:-12}"
[ "$INTERVAL" -gt 0 ] 2>/dev/null || exit 0

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
[ -z "$SID" ] && exit 0
# Defensive: session_id is a harness UUID; refuse anything with path/shell chars
case "$SID" in *[!a-zA-Z0-9_-]*) exit 0 ;; esac

STATE_DIR="$HOME/.claude/state"
mkdir -p "$STATE_DIR" 2>/dev/null || true
# Prune stale per-session counters (>1 day). -mtime +1 is BSD-safe (unlike -mmin).
find "$STATE_DIR" -name 'nudge-*.count' -mtime +1 -delete 2>/dev/null || true

CF="$STATE_DIR/nudge-${SID}.count"
COUNT=$(cat "$CF" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
printf '%s' "$COUNT" > "$CF"

# Fire only on each Nth prompt
[ $((COUNT % INTERVAL)) -eq 0 ] || exit 0

cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "MEMORY CHECK (periodic): if this session surfaced a DURABLE, generalizable rule, a decision (+ its why), a confirmed constraint, or user feedback that is NOT already in MEMORY.md, persist it now — append one <=200-char index line to MEMORY.md and create the topic file with frontmatter. SKIP (do not encode as a permanent rule): transient errors, environment/worktree-specific one-offs, lucky paths, negative tool-claims (verify before encoding), anything already indexed. If MEMORY.md is past its load warning, run /compact-memory first. Nothing durable this session? Ignore this."
  }
}
EOF
exit 0
