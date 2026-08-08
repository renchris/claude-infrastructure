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

# Same default + env override as hooks/lib/session-index-helpers.sh, so a fixtured
# suite can point this hook at a throwaway DB instead of the operator's live index.
DB="${SESSION_INDEX_DB:-$HOME/.claude/session-index.db}"
[ -f "$DB" ] || exit 0

# PER-COLUMN extraction. The previous form joined the three columns with '|' and split
# them back with `cut -d'|'` — but `commands_run` is RAW SHELL TEXT and routinely holds
# pipes (one probed row carried 127), so -f2 was a fragment of the first command and -f3
# the next fragment, never the file list. The corruption is visible in every record the
# hook has ever written: _candidates.jsonl line 1 stores a ` head -30 && echo …` fragment
# in files_changed. There is no delimiter that is safe against arbitrary shell text, so
# the join is removed rather than re-delimited — same class as
# docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md, at a call site that sweep never reached.
# `.timeout` because a raw sqlite3 spawns with a 0 ms busy timeout and dies under the
# concurrent SessionEnd writers this hook runs alongside (session-index-helpers.sh:43).
ROW=$(sqlite3 -json "$DB" ".timeout ${SESSION_INDEX_BUSY_TIMEOUT:-5000}" \
  "SELECT message_count AS m, commands_run AS c, files_changed AS f FROM sessions WHERE session_id='$SID' LIMIT 1;" \
  2>/dev/null || echo "")
# No row is '[]', not the empty string — a bare -z test would fall through to jq.
case "$ROW" in ''|'[]') exit 0 ;; esac

MSGS=$(printf '%s' "$ROW" | jq -r '.[0].m // 0' 2>/dev/null || echo 0)
CMDS=$(printf '%s' "$ROW" | jq -r '.[0].c // ""' 2>/dev/null || echo "")
FILES=$(printf '%s' "$ROW" | jq -r '.[0].f // ""' 2>/dev/null || echo "")

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
