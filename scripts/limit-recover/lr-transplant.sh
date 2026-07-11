#!/bin/bash
# lr-transplant.sh — move a Claude Code session to another account's config dir
# (same session uuid, so --resume and Workflow resumeFromRunId journals keep working).
#
# Usage: lr-transplant.sh --sid SID --from CFGDIR --to CFGDIR
#                         [--task-list ID] [--keep-source] [--force]
#
# Copies: <slug>/<sid>.jsonl + <slug>/<sid>/ (subagents, workflows, journals)
#         + tasks/<task-list>/ when given.
# Safety: split-brain lock at ~/.reso/limit-recover/locks/<sid>.lock, tombstone
#         JSON next to the source transcript, source transcript renamed to
#         *.jsonl.handed-off (skipped for the LIVE session or --keep-source).
# Output: one JSON object on stdout. Exit 0 ok, 2 refused/error.
set -euo pipefail

SID="" FROM="" TO="" TASK_LIST="" KEEP_SOURCE=0 FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sid) SID="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    --to) TO="$2"; shift 2 ;;
    --task-list) TASK_LIST="$2"; shift 2 ;;
    --keep-source) KEEP_SOURCE=1; shift ;;
    --force) FORCE=1; shift ;;
    *) echo "lr-transplant: unknown arg $1" >&2; exit 2 ;;
  esac
done
[[ -n "$SID" && -n "$FROM" && -n "$TO" ]] || { echo "lr-transplant: --sid/--from/--to required" >&2; exit 2; }

FROM=$(cd "${FROM/#\~/$HOME}" && pwd)
TO=$(cd "${TO/#\~/$HOME}" && pwd)
FROM_PROJ_REAL=$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$FROM/projects")
TO_PROJ_REAL=$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$TO/projects")
if [[ "$FROM_PROJ_REAL" == "$TO_PROJ_REAL" ]]; then
  echo "lr-transplant: REFUSED — source and target share the same projects/ store ($FROM_PROJ_REAL); nothing to transplant (same account)" >&2
  exit 2
fi

# Locate the source transcript (exactly one real file). (macOS ships bash 3.2 — no mapfile.)
HITS=()
while IFS= read -r line; do [[ -n "$line" ]] && HITS+=("$line"); done \
  < <(ls "$FROM"/projects/*/"$SID".jsonl 2>/dev/null || true)
if [[ ${#HITS[@]} -eq 0 ]]; then
  echo "lr-transplant: no transcript $SID under $FROM/projects" >&2; exit 2
elif [[ ${#HITS[@]} -gt 1 ]]; then
  echo "lr-transplant: REFUSED — multiple copies of $SID under $FROM/projects; disambiguate manually:" >&2
  printf '  %s\n' "${HITS[@]}" >&2; exit 2
fi
SRC="${HITS[0]}"
SRC_DIR=$(dirname "$SRC")
SLUG=$(basename "$SRC_DIR")
DST_DIR="$TO/projects/$SLUG"
DST="$DST_DIR/$SID.jsonl"

if [[ -e "$DST" && $FORCE -ne 1 ]]; then
  echo "lr-transplant: REFUSED — $DST already exists (use --force to overwrite)" >&2; exit 2
fi

# Split-brain lock (one transplant owner per session uuid).
LOCK_DIR="$HOME/.reso/limit-recover/locks"
mkdir -p "$LOCK_DIR"
LOCK="$LOCK_DIR/$SID.lock"
if [[ -e "$LOCK" && $FORCE -ne 1 ]]; then
  echo "lr-transplant: REFUSED — lock exists ($LOCK):" >&2
  cat "$LOCK" >&2; exit 2
fi
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"sid":"%s","from":"%s","to":"%s","ts":"%s","pid":%d,"host":"%s"}\n' \
  "$SID" "$FROM" "$TO" "$NOW" "$$" "$(hostname -s)" > "$LOCK"

mkdir -p "$DST_DIR"
cp -p "$SRC" "$DST"
SESSION_DIR_COPIED=0
if [[ -d "$SRC_DIR/$SID" ]]; then
  rsync -a "$SRC_DIR/$SID/" "$DST_DIR/$SID/"
  SESSION_DIR_COPIED=1
fi
TASKS_COPIED=0
if [[ -n "$TASK_LIST" && -d "$FROM/tasks/$TASK_LIST" ]]; then
  mkdir -p "$TO/tasks/$TASK_LIST"
  rsync -a "$FROM/tasks/$TASK_LIST/" "$TO/tasks/$TASK_LIST/"
  TASKS_COPIED=1
fi

SHA_SRC=$(shasum -a 256 "$SRC" | cut -d' ' -f1)
SHA_DST=$(shasum -a 256 "$DST" | cut -d' ' -f1)
if [[ "$SHA_SRC" != "$SHA_DST" ]]; then
  echo "lr-transplant: FATAL — sha mismatch after copy (src=$SHA_SRC dst=$SHA_DST)" >&2; exit 2
fi

# Tombstone + source retirement (never rename the LIVE session's transcript —
# the running harness still appends to it by path).
TOMBSTONE="$SRC_DIR/$SID.HANDOFF.json"
printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"%s","lock":"%s"}\n' \
  "$TO" "$DST" "$NOW" "$LOCK" > "$TOMBSTONE"
SOURCE_RETIRED=0
if [[ $KEEP_SOURCE -ne 1 && "${CLAUDE_CODE_SESSION_ID:-}" != "$SID" ]]; then
  mv "$SRC" "$SRC.handed-off"
  SOURCE_RETIRED=1
fi

printf '{"ok":true,"sid":"%s","slug":"%s","target_transcript":"%s","sha256":"%s","session_dir_copied":%s,"tasks_copied":%s,"source_retired":%s,"lock":"%s","tombstone":"%s"}\n' \
  "$SID" "$SLUG" "$DST" "$SHA_DST" "$SESSION_DIR_COPIED" "$TASKS_COPIED" "$SOURCE_RETIRED" "$LOCK" "$TOMBSTONE"
