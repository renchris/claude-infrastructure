#!/bin/bash
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Session ended" >> ~/.claude/logs/sessions.log

# Secondary GC trigger: clean stale Claude versions on session end (background, non-blocking)
# Primary trigger is in claude-latest (threshold-based). This catches any accumulation
# that slipped below threshold or when updates happened outside claude-latest.
(
  VERSIONS_DIR="$HOME/.claude-versions"
  CURRENT_LINK="$VERSIONS_DIR/current"
  KEEP_COUNT="${CLAUDE_VERSIONS_KEEP:-2}"
  GC_THRESHOLD=$(( KEEP_COUNT + 2 ))

  # Count versions (fast — single ls + wc)
  version_count=$(find "$VERSIONS_DIR" -maxdepth 1 -mindepth 1 -type d ! -name current ! -name '.*' 2>/dev/null | wc -l)
  [[ "$version_count" -le "$GC_THRESHOLD" ]] && exit 0

  # Acquire lock (skip if another cleanup is running)
  lock_dir="$VERSIONS_DIR/.cleanup_lock"
  mkdir "$lock_dir" 2>/dev/null || exit 0
  echo $$ > "$lock_dir/pid"

  current_target=$(readlink "$CURRENT_LINK" 2>/dev/null | xargs basename 2>/dev/null || echo "")

  # Sort versions, build keep set
  versions=()
  for dir in "$VERSIONS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    v=$(basename "$dir")
    [[ "$v" == "current" || "$v" == .* ]] && continue
    versions+=("$v")
  done
  IFS=$'\n' sorted=($(printf '%s\n' "${versions[@]}" | sort -t. -k1,1rn -k2,2rn -k3,3rn))
  unset IFS

  declare -A keep_set
  keep_set["$current_target"]=1
  kept=0
  for v in "${sorted[@]}"; do
    [[ "$v" == "$current_target" ]] && continue
    if [[ $kept -lt $KEEP_COUNT ]]; then
      keep_set["$v"]=1
      kept=$((kept + 1))
    fi
  done

  for v in "${sorted[@]}"; do
    [[ -n "${keep_set[$v]:-}" ]] && continue
    pgrep -f "claude-versions/$v" >/dev/null 2>&1 && continue
    rm -rf "$VERSIONS_DIR/$v" 2>/dev/null && \
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] SessionEnd GC: removed $v" >> "$HOME/.claude/.update-versions.log"
  done

  rm -rf "$lock_dir"
) &
disown 2>/dev/null || true

exit 0
