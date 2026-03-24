#!/bin/bash
# Sweep daemon — catches sessions missed by SessionEnd hook.
# Scans ~/.claude/projects/ for new or changed .jsonl transcripts,
# extracts context + enriched data, and upserts into the index.
# Designed to run every 60s via launchd with low priority I/O.
# Performance target: <500ms when no changes detected.
set -euo pipefail

# Resolve helpers — follow symlink to repo
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$SCRIPT_DIR/lib/session-index-helpers.sh"
if [ ! -f "$HELPERS" ]; then
    HELPERS="$HOME/.claude/hooks/lib/session-index-helpers.sh"
fi
[ -f "$HELPERS" ] || exit 0
source "$HELPERS"

# Fast exit if no DB
[ -f "$SESSION_INDEX_DB" ] || exit 0

# Init DB + tracking tables (idempotent)
session_index_init_db
session_index_init_tracking

# Non-blocking lock — skip if backfill/tagger/another sweep is running
if ! session_index_trylock; then
    exit 0
fi

UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
WORK_DONE=0

# ─── Scan all project directories ────────────────────────
for project_dir in "$CLAUDE_PROJECTS_DIR"/*/; do
    [ -d "$project_dir" ] || continue

    dir_name=$(basename "$project_dir")
    proj_path=$(echo "$dir_name" | sed 's/^-/\//' | sed 's/-/\//g')
    proj_name=$(session_index_project_name "$proj_path")

    # ─── Flat layout: {project_dir}/{session_id}.jsonl ────
    for transcript in "$project_dir"*.jsonl; do
        [ -f "$transcript" ] || continue

        sid=$(basename "$transcript" .jsonl)
        # Skip non-UUID files (sessions-index.json produces .jsonl too)
        [[ "$sid" =~ $UUID_RE ]] || continue

        # Stat file: mtime + size (macOS stat)
        file_mtime=$(stat -f "%m" "$transcript" 2>/dev/null || echo 0)
        file_size=$(stat -f "%z" "$transcript" 2>/dev/null || echo 0)

        # Check tracking table for changes
        tracked=$(session_index_sql "SELECT last_mtime, last_size FROM file_tracking WHERE file_path = '$(echo "$transcript" | sed "s/'/''/g")' LIMIT 1;" 2>/dev/null || echo "")

        if [ -n "$tracked" ]; then
            IFS='|' read -r tracked_mtime tracked_size <<< "$tracked"
            # No change — skip
            if [ "$file_mtime" = "$tracked_mtime" ] && [ "$file_size" = "$tracked_size" ]; then
                continue
            fi
        fi

        # ─── New or changed file: extract and upsert ──────
        # Extract context text from transcript (first 5 user messages)
        context_text=$(session_index_extract_context "$transcript" 5 2>/dev/null || echo "")

        # Extract enriched data (assistant text, file paths, commands)
        enriched_data=$(session_index_extract_enriched "$transcript" 2>/dev/null || printf '\t\t')
        IFS=$'\t' read -r assistant_text files_changed commands_run <<< "$enriched_data"

        # Extract message count
        msg_count=$(session_index_extract_transcript_meta "$transcript" 2>/dev/null || echo "0")

        # Build first_prompt from context_text (fallback for stub rows)
        first_prompt=""
        if [ -n "$context_text" ]; then
            first_prompt=$(printf '%s' "$context_text" | head -c 500)
        fi

        # Extract keywords
        keywords=$(session_index_extract_keywords "$first_prompt $context_text" 2>/dev/null || echo "")

        # File mtime as ISO8601 for created_at/modified_at
        file_mtime_iso=$(date -r "$file_mtime" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "$NOW")

        # Upsert session — 'sweep' source is lower priority than 'sessions-index'
        session_index_upsert_with_fts \
            "$sid" \
            "$proj_path" \
            "$proj_name" \
            "" \
            "$first_prompt" \
            "" \
            "$file_mtime_iso" \
            "$file_mtime_iso" \
            "${msg_count:-0}" \
            "" \
            "$keywords" \
            "session-sweep" \
            "$context_text" \
            "$assistant_text" \
            "$files_changed" \
            "$commands_run" \
            ""

        # Update sweep columns on sessions
        sid_escaped=$(echo "$sid" | sed "s/'/''/g")
        session_index_sql "UPDATE sessions SET sweep_mtime = $file_mtime, sweep_size = $file_size WHERE session_id = '$sid_escaped';"

        # Upsert file_tracking
        transcript_escaped=$(echo "$transcript" | sed "s/'/''/g")
        proj_dir_escaped=$(echo "$project_dir" | sed "s/'/''/g")
        session_index_sql <<SQL
INSERT INTO file_tracking (file_path, session_id, project_dir, last_mtime, last_size, last_swept_at, sweep_count, is_active)
VALUES ('$transcript_escaped', '$sid_escaped', '$proj_dir_escaped', $file_mtime, $file_size, '$NOW', 1, 1)
ON CONFLICT(file_path) DO UPDATE SET
    last_mtime = $file_mtime,
    last_size = $file_size,
    last_swept_at = '$NOW',
    sweep_count = file_tracking.sweep_count + 1;
SQL

        WORK_DONE=$((WORK_DONE + 1))
    done

    # ─── Subdirectory layout: {project_dir}/{session_id}/transcript.jsonl ──
    for subdir in "$project_dir"*/; do
        [ -d "$subdir" ] || continue

        sid=$(basename "$subdir")
        [[ "$sid" =~ $UUID_RE ]] || continue

        transcript="$subdir/transcript.jsonl"
        [ -f "$transcript" ] || continue

        # Skip if flat file exists (prefer flat — same content)
        [ -f "$project_dir${sid}.jsonl" ] && continue

        # Stat file
        file_mtime=$(stat -f "%m" "$transcript" 2>/dev/null || echo 0)
        file_size=$(stat -f "%z" "$transcript" 2>/dev/null || echo 0)

        # Check tracking table
        tracked=$(session_index_sql "SELECT last_mtime, last_size FROM file_tracking WHERE file_path = '$(echo "$transcript" | sed "s/'/''/g")' LIMIT 1;" 2>/dev/null || echo "")

        if [ -n "$tracked" ]; then
            IFS='|' read -r tracked_mtime tracked_size <<< "$tracked"
            if [ "$file_mtime" = "$tracked_mtime" ] && [ "$file_size" = "$tracked_size" ]; then
                continue
            fi
        fi

        # Extract and upsert (same pattern as flat layout)
        context_text=$(session_index_extract_context "$transcript" 5 2>/dev/null || echo "")
        enriched_data=$(session_index_extract_enriched "$transcript" 2>/dev/null || printf '\t\t')
        IFS=$'\t' read -r assistant_text files_changed commands_run <<< "$enriched_data"
        msg_count=$(session_index_extract_transcript_meta "$transcript" 2>/dev/null || echo "0")

        first_prompt=""
        if [ -n "$context_text" ]; then
            first_prompt=$(printf '%s' "$context_text" | head -c 500)
        fi

        keywords=$(session_index_extract_keywords "$first_prompt $context_text" 2>/dev/null || echo "")
        file_mtime_iso=$(date -r "$file_mtime" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "$NOW")

        session_index_upsert_with_fts \
            "$sid" \
            "$proj_path" \
            "$proj_name" \
            "" \
            "$first_prompt" \
            "" \
            "$file_mtime_iso" \
            "$file_mtime_iso" \
            "${msg_count:-0}" \
            "" \
            "$keywords" \
            "session-sweep" \
            "$context_text" \
            "$assistant_text" \
            "$files_changed" \
            "$commands_run" \
            ""

        sid_escaped=$(echo "$sid" | sed "s/'/''/g")
        session_index_sql "UPDATE sessions SET sweep_mtime = $file_mtime, sweep_size = $file_size WHERE session_id = '$sid_escaped';"

        transcript_escaped=$(echo "$transcript" | sed "s/'/''/g")
        proj_dir_escaped=$(echo "$project_dir" | sed "s/'/''/g")
        session_index_sql <<SQL
INSERT INTO file_tracking (file_path, session_id, project_dir, last_mtime, last_size, last_swept_at, sweep_count, is_active)
VALUES ('$transcript_escaped', '$sid_escaped', '$proj_dir_escaped', $file_mtime, $file_size, '$NOW', 1, 1)
ON CONFLICT(file_path) DO UPDATE SET
    last_mtime = $file_mtime,
    last_size = $file_size,
    last_swept_at = '$NOW',
    sweep_count = file_tracking.sweep_count + 1;
SQL

        WORK_DONE=$((WORK_DONE + 1))
    done
done

# ─── Log only when work was done ──────────────────────────
if [ "$WORK_DONE" -gt 0 ]; then
    session_index_log "Sweep: indexed $WORK_DONE new/changed transcripts"
fi

exit 0
