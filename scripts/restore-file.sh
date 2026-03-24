#!/bin/bash
# Restore a file from the automatic backup created by backup-before-write.sh
#
# Usage:
#   restore-file.sh <original-path>          Restore latest backup of that file
#   restore-file.sh <original-path> --list   List all available backups
#   restore-file.sh <original-path> --diff   Show diff between current file and latest backup
#   restore-file.sh <original-path> --pick N Restore Nth most recent (1=latest)
#   restore-file.sh --recent                 Show 10 most recent backups across all files
#   restore-file.sh --recent N               Show N most recent backups

set -euo pipefail

BACKUP_DIR="$HOME/.claude/backups"

# === --recent: list recent backups across all files ===
if [ "${1:-}" = "--recent" ]; then
  COUNT="${2:-10}"
  if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
    echo "No backups found in $BACKUP_DIR"
    exit 0
  fi
  echo "=== ${COUNT} Most Recent Backups ==="
  echo ""
  find "$BACKUP_DIR" -maxdepth 1 -name "*.bak" -print0 \
    | xargs -0 ls -lt \
    | head -n "$COUNT" \
    | while IFS= read -r line; do
        bak_path=$(echo "$line" | awk '{print $NF}')
        bak_name=$(basename "$bak_path")
        path_file="${bak_path%.bak}.path"
        original="(unknown)"
        [ -f "$path_file" ] && original=$(cat "$path_file")
        size=$(echo "$line" | awk '{print $5}')
        date_str=$(echo "$line" | awk '{print $6, $7, $8}')
        echo "  ${date_str}  ${size}B  ${bak_name}"
        echo "    → ${original}"
        echo ""
      done
  exit 0
fi

# === Require file path for all other operations ===
if [ -z "${1:-}" ]; then
  echo "Usage:"
  echo "  restore-file.sh <path>           Restore latest backup"
  echo "  restore-file.sh <path> --list    List all backups"
  echo "  restore-file.sh <path> --diff    Diff current vs latest backup"
  echo "  restore-file.sh <path> --pick N  Restore Nth most recent"
  echo "  restore-file.sh --recent [N]     Show N most recent backups"
  exit 1
fi

FILE="$1"
ACTION="${2:-restore}"
PICK="${3:-1}"

# Resolve to absolute path (gracefully handle deleted parent dirs)
if [[ "$FILE" != /* ]]; then
  DIR=$(cd "$(dirname "$FILE")" 2>/dev/null && pwd)
  if [ -z "$DIR" ]; then
    # Parent directory doesn't exist — try from current working directory
    DIR="$(pwd)/$(dirname "$FILE")"
  fi
  FILE="${DIR}/$(basename "$FILE")"
fi

BASENAME=$(basename "$FILE")

# Find all backups for this basename, sorted newest first
BACKUPS=()
while IFS= read -r -d '' bak; do
  # Verify the .path sidecar points to the same original file
  path_file="${bak%.bak}.path"
  if [ -f "$path_file" ]; then
    stored_path=$(cat "$path_file")
    [ "$stored_path" = "$FILE" ] && BACKUPS+=("$bak")
  else
    # No sidecar — match by basename only (legacy backups)
    BACKUPS+=("$bak")
  fi
done < <(find "$BACKUP_DIR" -maxdepth 1 -name "${BASENAME}__*.bak" -print0 | xargs -0 ls -t 2>/dev/null | tr '\n' '\0')

if [ ${#BACKUPS[@]} -eq 0 ]; then
  echo "No backups found for: $FILE"
  echo "Basename searched: ${BASENAME}__*.bak in $BACKUP_DIR"
  exit 1
fi

case "$ACTION" in
  --list)
    echo "=== Backups for $(basename "$FILE") ==="
    echo "Original: $FILE"
    echo ""
    i=1
    for bak in "${BACKUPS[@]}"; do
      ts=$(basename "$bak" | sed "s/${BASENAME}__//; s/\.bak$//")
      size=$(wc -c < "$bak" | tr -d ' ')
      lines=$(wc -l < "$bak" | tr -d ' ')
      echo "  #${i}  ${ts}  ${lines} lines  ${size} bytes"
      echo "       ${bak}"
      i=$((i + 1))
    done
    echo ""
    echo "Restore: restore-file.sh $FILE --pick N"
    ;;

  --diff)
    LATEST="${BACKUPS[0]}"
    if [ ! -f "$FILE" ]; then
      echo "Current file doesn't exist. Latest backup:"
      echo "  ${LATEST}"
      echo ""
      echo "Restore with: restore-file.sh $FILE"
      exit 0
    fi
    echo "=== Diff: backup (old) vs current (new) ==="
    echo "Backup: $(basename "$LATEST")"
    echo ""
    diff --unified=3 "$LATEST" "$FILE" || true
    ;;

  --pick)
    IDX=$((PICK - 1))
    if [ "$IDX" -lt 0 ] || [ "$IDX" -ge ${#BACKUPS[@]} ]; then
      echo "Invalid pick: $PICK (${#BACKUPS[@]} backups available)"
      exit 1
    fi
    TARGET="${BACKUPS[$IDX]}"
    # Atomic restore: copy to temp, then mv (preserves permissions on interruption)
    TMPFILE=$(mktemp "${FILE}.restore.XXXXXX")
    cp -p "$TARGET" "$TMPFILE" && mv "$TMPFILE" "$FILE"
    echo "Restored $FILE from backup #${PICK}"
    echo "  Source: $(basename "$TARGET")"
    echo "  Lines: $(wc -l < "$FILE" | tr -d ' ')"
    ;;

  restore|*)
    # Default: restore latest
    LATEST="${BACKUPS[0]}"
    # Atomic restore: copy to temp, then mv (prevents corruption if interrupted)
    TMPFILE=$(mktemp "${FILE}.restore.XXXXXX")
    cp -p "$LATEST" "$TMPFILE" && mv "$TMPFILE" "$FILE"
    echo "Restored $FILE from latest backup"
    echo "  Source: $(basename "$LATEST")"
    echo "  Lines: $(wc -l < "$FILE" | tr -d ' ')"
    echo ""
    echo "Other backups available: ${#BACKUPS[@]} total"
    [ ${#BACKUPS[@]} -gt 1 ] && echo "  List all: restore-file.sh $FILE --list"
    ;;
esac
