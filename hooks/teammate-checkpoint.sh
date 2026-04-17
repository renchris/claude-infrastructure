#!/bin/bash
# shellcheck disable=SC2329,SC1083
# teammate-checkpoint.sh — PostToolUse + Stop hook.
#
# Creates a lightweight checkpoint every N tool uses so a teammate's
# in-progress work survives a lead crash. Uses `git stash create` which
# produces a stash object without committing and without modifying the
# working tree — zero impact on normal flow.
#
# Only fires when $CLAUDE_CWD resembles a teammate worktree
# (/tmp/worktree-*). On the lead, this hook exits 0 immediately.
#
# Kill switch: export TEAMMATE_CHECKPOINT_DISABLED=1
# Tuning:      export TEAMMATE_CHECKPOINT_EVERY=<N>  (default 10)

set -uo pipefail

if [[ "${TEAMMATE_CHECKPOINT_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

readonly EVERY="${TEAMMATE_CHECKPOINT_EVERY:-10}"
readonly WATCHDOG_DIR="$HOME/.claude/watchdog"
readonly LOG_FILE="$HOME/.claude/logs/teammate-checkpoint.log"

mkdir -p "$WATCHDOG_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# Parse hook JSON stdin
INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo 'unknown')
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "?"' 2>/dev/null || echo '?')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo '')
[[ -z "$CWD" ]] && CWD="$PWD"

# Only act in a teammate worktree
case "$CWD" in
  /tmp/worktree-*) ;;
  *) exit 0 ;;
esac

# Skip mid-rebase/merge
if [[ -d "$CWD/.git/rebase-merge" || -d "$CWD/.git/rebase-apply" || -f "$CWD/.git/MERGE_HEAD" ]]; then
  log "skip $CWD: rebase/merge in progress"
  exit 0
fi

# Per-session counter (avoid collisions across parallel teammates)
COUNTER_FILE="$WATCHDOG_DIR/cp-$SESSION_ID.count"
COUNT=0
[[ -f "$COUNTER_FILE" ]] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)

# Always checkpoint on Stop; otherwise every EVERY tool uses
SHOULD_SNAPSHOT=false
if [[ "$EVENT" == "Stop" ]]; then
  SHOULD_SNAPSHOT=true
else
  COUNT=$((COUNT + 1))
  echo "$COUNT" > "$COUNTER_FILE"
  if (( COUNT % EVERY == 0 )); then
    SHOULD_SNAPSHOT=true
  fi
fi

$SHOULD_SNAPSHOT || exit 0

# Only snapshot if there's something to snapshot
if ! git -C "$CWD" status --porcelain 2>/dev/null | grep -q .; then
  exit 0
fi

# Derive member name from worktree path convention /tmp/worktree-<team>-<member>
# Fallback: last path segment
MEMBER=$(basename "$CWD" | sed 's/^worktree-[^-]*-//')
[[ -z "$MEMBER" ]] && MEMBER=$(basename "$CWD")

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
MSG="checkpoint: ${EVENT} count=${COUNT} ts=${TIMESTAMP}"

# Snapshot BOTH tracked modifications AND untracked files (respecting .gitignore)
# via a temp index — zero impact on the teammate's working tree or real index.
# (git stash create alone misses untracked files; new files a teammate writes
# would be lost on a crash, defeating the point.)
HEAD_SHA=$(git -C "$CWD" rev-parse HEAD 2>/dev/null || echo "")
if [[ -z "$HEAD_SHA" ]]; then
  log "no HEAD for $CWD — skipping checkpoint"
  exit 0
fi

TMP_INDEX=$(mktemp)
# If anything fails, drop the temp index — we never touch the real one
cleanup_index() { rm -f "$TMP_INDEX"; }
trap cleanup_index EXIT

CHECKPOINT_SHA=$(
  GIT_INDEX_FILE="$TMP_INDEX" git -C "$CWD" read-tree HEAD 2>/dev/null &&
  GIT_INDEX_FILE="$TMP_INDEX" git -C "$CWD" add -A 2>/dev/null &&
  TREE=$(GIT_INDEX_FILE="$TMP_INDEX" git -C "$CWD" write-tree 2>/dev/null) &&
  [[ -n "$TREE" && "$TREE" != "$(git -C "$CWD" rev-parse HEAD^{tree} 2>/dev/null)" ]] &&
  git -C "$CWD" commit-tree "$TREE" -p "$HEAD_SHA" -m "$MSG" 2>/dev/null
) || CHECKPOINT_SHA=""

if [[ -z "$CHECKPOINT_SHA" ]]; then
  log "no checkpoint needed for $CWD — tree matches HEAD"
  exit 0
fi

# Record under refs/checkpoints/<member>/<timestamp> so `git reflog` can list them
REF="refs/checkpoints/$MEMBER/$TIMESTAMP"
if git -C "$CWD" update-ref "$REF" "$CHECKPOINT_SHA" 2>/dev/null; then
  log "checkpoint $CWD $MEMBER $EVENT count=$COUNT sha=$CHECKPOINT_SHA ref=$REF"
else
  log "WARN: update-ref failed for $REF"
fi

exit 0
