#!/bin/bash
# SessionEnd Hook — Skill-Harvest Candidate Logger
#
# Appends a one-line candidate record for substantive sessions so the human can
# later run /harvest-skill to synthesize a draft SKILL.md. NO model interaction,
# NO autonomous skill write — the synthesis (the expensive, judgment-heavy part)
# stays human-gated and on-demand.
#
# Adapted from hermes-agent skill_manage / background_review, minus the autonomous
# fork (which writes skills unattended — out of scope by our human-in-the-loop policy).
#
# Runs AFTER session-index-end.sh in the SessionEnd chain, so the DB row is fresh.
set -euo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
[ -z "$SID" ] && exit 0
case "$SID" in *[!a-zA-Z0-9_-]*) exit 0 ;; esac

DB="$HOME/.claude/session-index.db"
[ -f "$DB" ] || exit 0

ROW=$(sqlite3 "$DB" "SELECT message_count || '|' || commands_run || '|' || files_changed FROM sessions WHERE session_id='$SID' LIMIT 1;" 2>/dev/null || echo "")
[ -z "$ROW" ] && exit 0

MSGS=$(printf '%s' "$ROW" | cut -d'|' -f1)
CMDS=$(printf '%s' "$ROW" | cut -d'|' -f2)
FILES=$(printf '%s' "$ROW" | cut -d'|' -f3)

# Gate: skip trivial sessions (need real back-and-forth + tool activity)
[ "${MSGS:-0}" -ge 12 ] 2>/dev/null || exit 0
[ -n "$CMDS" ] || exit 0

STAGE_DIR="$HOME/.claude/skills-pending"
mkdir -p "$STAGE_DIR" 2>/dev/null || true
STAGE="$STAGE_DIR/_candidates.jsonl"

jq -cn \
  --arg sid "$SID" \
  --arg msgs "$MSGS" \
  --arg cmds "$CMDS" \
  --arg files "$FILES" \
  '{ts: (now|todate), session_id: $sid, message_count: ($msgs|tonumber? // 0), commands_run: $cmds, files_changed: $files, status: "unreviewed"}' \
  >> "$STAGE" 2>/dev/null || true

exit 0
