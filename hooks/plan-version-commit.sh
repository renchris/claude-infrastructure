#!/bin/bash
# PostToolUse hook — auto-version plan files to ~/.claude/plan-history/ git repo
# Fires after successful Write/Edit/MultiEdit on plan files.
# Non-blocking: background commit, graceful failure. Never blocks Claude Code.
#
# Architecture (from 15-agent research, Mar 19 2026):
#   Layer 1: MANIFEST.jsonl — append-only metadata log (timestamp, session, lines, hash)
#   Layer 2: plan-history git repo — full version snapshots with git log/diff/show
#   Zero race conditions — separate .git, no main repo interference.

set -uo pipefail

# === JQ CHECK ===
command -v jq &>/dev/null || exit 0

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_result.filePath // empty')

# Fast exit: no file or file doesn't exist
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# === PLAN FILE DETECTION (same 5-pattern as backup-before-write.sh) ===
IS_PLAN=false
case "$FILE" in
  "$HOME/.claude/plans/"*.md)                    IS_PLAN=true ;;
  *"/.claude-plans/"*.md)                        IS_PLAN=true ;;
  *"/docs/plans/"*.md)                           IS_PLAN=true ;;
  docs/plans/*.md)                               IS_PLAN=true ;;
  *"/AGENT_TEAM_IMPLEMENTATION_PLAN"*.md)        IS_PLAN=true ;;
esac

[ "$IS_PLAN" = false ] && exit 0

# === METADATA ===
BASENAME=$(basename "$FILE")
PLAN_NAME="${BASENAME%.md}"
LINES=$(wc -l < "$FILE" | tr -d ' ')
HASH=$(shasum -a 256 "$FILE" | awk '{print $1}')
SIZE=$(wc -c < "$FILE" | tr -d ' ')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

# === LAYER 1: MANIFEST (append-only metadata log) ===
MANIFEST_DIR="$HOME/.claude/plan-versions"
mkdir -p "$MANIFEST_DIR" 2>/dev/null || true

jq -nc \
  --arg ts "$TIMESTAMP" \
  --arg sess "$SESSION_ID" \
  --arg tool "$TOOL" \
  --arg path "$FILE" \
  --arg name "$PLAN_NAME" \
  --arg lines "$LINES" \
  --arg size "$SIZE" \
  --arg hash "$HASH" \
  '{ts: $ts, session: $sess, tool: $tool, path: $path, name: $name, lines: ($lines|tonumber), size: ($size|tonumber), sha256: $hash}' \
  >> "$MANIFEST_DIR/MANIFEST.jsonl" 2>/dev/null || true

# === LAYER 2: GIT REPO (background, non-blocking) ===
(
  PLAN_REPO="$HOME/.claude/plan-history"
  [ ! -d "$PLAN_REPO/.git" ] && exit 0

  cd "$PLAN_REPO"

  # Copy plan file (follow symlinks with -L)
  cp -L "$FILE" "plans/$BASENAME" 2>/dev/null || exit 0

  # Skip if content unchanged (dedup via git status)
  if git diff --quiet -- "plans/$BASENAME" 2>/dev/null && \
     ! git ls-files --others --exclude-standard -- "plans/$BASENAME" | grep -q .; then
    exit 0  # No changes
  fi

  git add "plans/$BASENAME" 2>/dev/null || exit 0
  git commit -m "auto: $BASENAME ($LINES lines, $TOOL)" \
    --author="Claude Hook <claude-hook@localhost>" 2>/dev/null || true
) &

exit 0
