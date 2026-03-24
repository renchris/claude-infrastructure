#!/bin/bash
# Daily backup pruning — called from SessionStart hook (background, non-blocking)
# macOS-compatible (bash 3.2, no associative arrays, no flock)
#
# Rules:
#   - Keep last 10 backups per basename (3 for .sh files)
#   - Delete ALL backups older than 30 days
#   - Delete orphaned .path files
#   - Skip files modified <5min ago (active session protection)

set -uo pipefail

BACKUP_DIR="$HOME/.claude/backups"
LOG_FILE="$HOME/.claude/logs/backup-cleanup.log"

[ ! -d "$BACKUP_DIR" ] && exit 0
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# === CONCURRENT EXECUTION GUARD (macOS-compatible) ===
LOCK_DIR="$BACKUP_DIR/.prune-lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [ -d "$LOCK_DIR" ] && [ "$(find "$LOCK_DIR" -maxdepth 0 -mmin +5 2>/dev/null)" ]; then
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

DELETED=0

{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup prune started"

  # === PHASE 1: Delete >30 days old ===
  while IFS= read -r old_bak; do
    [ -z "$old_bak" ] && continue
    rm -f "$old_bak" "${old_bak%.bak}.path" 2>/dev/null
    DELETED=$((DELETED + 1))
  done < <(find "$BACKUP_DIR" -maxdepth 1 -name "*.bak" -type f -mtime +30 2>/dev/null)

  # === PHASE 2: Per-basename count pruning ===
  # Get unique basenames (everything before __)
  find "$BACKUP_DIR" -maxdepth 1 -name "*__*.bak" -type f 2>/dev/null \
    | sed 's/.*\///' | sed 's/__.*//' | sort -u \
    | while IFS= read -r base; do
        [ -z "$base" ] && continue

        # Determine keep count
        KEEP=10
        case "$base" in *.sh) KEEP=3 ;; esac

        COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name "${base}__*.bak" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ "$COUNT" -gt "$KEEP" ]; then
          find "$BACKUP_DIR" -maxdepth 1 -name "${base}__*.bak" -type f -print0 2>/dev/null \
            | xargs -0 ls -t 2>/dev/null \
            | tail -n +"$((KEEP + 1))" \
            | while IFS= read -r old_bak; do
                # Skip files <5min old (active session)
                if [ "$(find "$old_bak" -mmin +5 2>/dev/null)" ]; then
                  rm -f "$old_bak" "${old_bak%.bak}.path" 2>/dev/null
                  DELETED=$((DELETED + 1))
                fi
              done
        fi
      done

  # === PHASE 3: Orphaned .path cleanup ===
  for path_file in "$BACKUP_DIR"/*.path; do
    [ -f "$path_file" ] || continue
    [ ! -f "${path_file%.path}.bak" ] && rm -f "$path_file"
  done

  SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
  FILES=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.bak" -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Prune complete. Deleted: $DELETED. Remaining: $FILES files ($SIZE)"

} >> "$LOG_FILE" 2>&1

exit 0
