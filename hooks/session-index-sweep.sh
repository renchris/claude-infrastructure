#!/bin/bash
# Sweep daemon — catches sessions missed by SessionEnd hook.
# Scans ~/.claude/projects/ for new or changed .jsonl transcripts,
# extracts context + enriched data, and upserts into the index.
# Designed to run every 60s via launchd with low priority I/O.
# Performance target: <500ms when no changes detected.
#
# Also the entry point for index RETENTION: `session-index-sweep.sh --retention[-apply]`.
set -euo pipefail

# Resolve helpers — follow symlink to repo
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$SCRIPT_DIR/lib/session-index-helpers.sh"
if [ ! -f "$HELPERS" ]; then
    HELPERS="$HOME/.claude/hooks/lib/session-index-helpers.sh"
fi
[ -f "$HELPERS" ] || exit 0
# shellcheck source=hooks/lib/session-index-helpers.sh
source "$HELPERS"

# Fast exit if no DB
[ -f "$SESSION_INDEX_DB" ] || exit 0

# ─── Retention verb ───────────────────────────────────────
# `--retention` reports (reads only); `--retention-apply` deletes + VACUUMs. The index
# outlives its subject ~4× — 5,453 session rows against ~1,600 transcripts, because CC's
# cleanupPeriodDays removes transcripts at 30 d and nothing ever removed the matching
# rows (audit 03 §1c: no retention, no VACUUM, 717 free pages). A hit whose transcript is
# gone is a search result you cannot open.
case "${1:-}" in
  --retention|--retention-apply)
    session_index_init_db
    session_index_init_tracking
    session_index_trylock || { echo "session-index-retention: index is locked, skipping"; exit 0; }
    if [ "$1" = "--retention-apply" ]; then
        read -r _b _a _d <<< "$(session_index_retention --apply)"
    else
        read -r _b _a _d <<< "$(session_index_retention)"
    fi
    echo "session-index-retention: sessions before=$_b after=$_a deletable=$_d db=$(du -h "$SESSION_INDEX_DB" 2>/dev/null | cut -f1)"
    exit 0
    ;;
esac

# ─── Cadence knob ─────────────────────────────────────────
# The plist stays at StartInterval 60. That is deliberate: with the batched change
# detection below, a tick with nothing to do is 3 processes and a few ms, so 60 s
# costs almost nothing and keeps index lag at 60 s instead of 300 s. This knob exists
# for the operator who wants to trade lag for load WITHOUT editing (and reloading) the
# plist: set SESSION_INDEX_SWEEP_MIN_INTERVAL_S=300 in the environment and every tick
# inside that window exits before touching the DB. Default 0 = run every tick.
SESSION_INDEX_SWEEP_MIN_INTERVAL_S="${SESSION_INDEX_SWEEP_MIN_INTERVAL_S:-0}"
SWEEP_STAMP="${SESSION_INDEX_SWEEP_STAMP:-$HOME/.claude/state/session-index-sweep.last}"
if [ "$SESSION_INDEX_SWEEP_MIN_INTERVAL_S" -gt 0 ] 2>/dev/null; then
    if [ -f "$SWEEP_STAMP" ]; then
        _last=$(cat "$SWEEP_STAMP" 2>/dev/null || echo 0)
        _now=$(date +%s)
        if [ $((_now - _last)) -lt "$SESSION_INDEX_SWEEP_MIN_INTERVAL_S" ] 2>/dev/null; then
            exit 0
        fi
    fi
fi

# Init DB + tracking tables (idempotent)
session_index_init_db
session_index_init_tracking

# Non-blocking lock — skip if backfill/tagger/another sweep is running.
# The trylock is now staleness-aware: an abandoned mkdir-lock (dead owner, or unstamped
# and older than 30 min) is taken over instead of wedging the sweep forever. One such
# orphan silently stopped session indexing for 107 days (audit 06 §4.1).
if ! session_index_trylock; then
    exit 0
fi

mkdir -p "$(dirname "$SWEEP_STAMP")" 2>/dev/null || true
date +%s > "$SWEEP_STAMP" 2>/dev/null || true

UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
WORK_DONE=0
SKIPPED_BY_CAP=0

# Per-tick work cap. The first unblocked sweep after the 107-day wedge has ~1,100
# never-indexed transcripts to parse; without a cap that single tick runs for minutes
# while launchd fires the next one (which then trylock-skips). The cap turns the
# catch-up into a handful of bounded ticks. NOT silent — a capped tick logs what it
# left behind, because a truncation nobody can see reads as "fully indexed".
SESSION_INDEX_SWEEP_MAX_FILES="${SESSION_INDEX_SWEEP_MAX_FILES:-200}"

# ─── ONE batched change-detection pass ────────────────────
# Was: for every transcript, 2× `stat` + 1× `sqlite3` SELECT, then 3 full-file python3
# parses of the same file — ~4,900 processes for 1,631 transcripts, and every active
# session's growing transcript re-parsed three times a minute (audit 06 §3, §5.3).
# Now: 3 processes for the whole scan (find+stat / sqlite3 / awk), then ONE python3 pass
# per *changed* file.
while IFS=$'\t' read -r transcript file_mtime file_size; do
    [ -n "$transcript" ] || continue
    [ -f "$transcript" ] || continue

    if [ "$WORK_DONE" -ge "$SESSION_INDEX_SWEEP_MAX_FILES" ]; then
        SKIPPED_BY_CAP=$((SKIPPED_BY_CAP + 1))
        continue
    fi

    base=$(basename "$transcript")
    if [ "$base" = "transcript.jsonl" ]; then
        # Nested layout: {project_dir}/{session_id}/transcript.jsonl
        sid=$(basename "$(dirname "$transcript")")
        project_dir="$(dirname "$(dirname "$transcript")")/"
        # Prefer the flat file when both exist (same content) — unchanged behaviour.
        [ -f "$project_dir${sid}.jsonl" ] && continue
    else
        # Flat layout: {project_dir}/{session_id}.jsonl
        sid="${base%.jsonl}"
        project_dir="$(dirname "$transcript")/"
    fi

    # Skip non-UUID files (sessions-index.json and friends also end in .jsonl)
    [[ "$sid" =~ $UUID_RE ]] || continue

    dir_name=$(basename "$project_dir")
    proj_path=$(echo "$dir_name" | sed 's/^-/\//' | sed 's/-/\//g')
    proj_name=$(session_index_project_name "$proj_path")

    # ─── ONE parse: context, assistant text, files, commands, message count ───
    extracted=$(session_index_extract_all "$transcript" 5 2>/dev/null || printf '\t\t\t\t0')
    IFS=$'\t' read -r context_text assistant_text files_changed commands_run msg_count <<< "$extracted"

    # Build first_prompt from context_text (fallback for stub rows)
    first_prompt=""
    if [ -n "$context_text" ]; then
        first_prompt=$(printf '%s' "$context_text" | head -c 500)
    fi

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

    sid_escaped=$(echo "$sid" | sed "s/'/''/g")
    transcript_escaped=$(echo "$transcript" | sed "s/'/''/g")
    proj_dir_escaped=$(echo "$project_dir" | sed "s/'/''/g")

    # Both writes in ONE sqlite3 process (was two).
    session_index_sql <<SQL
UPDATE sessions SET sweep_mtime = $file_mtime, sweep_size = $file_size WHERE session_id = '$sid_escaped';
INSERT INTO file_tracking (file_path, session_id, project_dir, last_mtime, last_size, last_swept_at, sweep_count, is_active)
VALUES ('$transcript_escaped', '$sid_escaped', '$proj_dir_escaped', $file_mtime, $file_size, '$NOW', 1, 1)
ON CONFLICT(file_path) DO UPDATE SET
    last_mtime = $file_mtime,
    last_size = $file_size,
    last_swept_at = '$NOW',
    sweep_count = file_tracking.sweep_count + 1;
SQL

    WORK_DONE=$((WORK_DONE + 1))
done < <(session_index_changed_files "$CLAUDE_PROJECTS_DIR")

# ─── Weekly retention (self-damped; no new launchd job) ───
# Wired here rather than into the weekly backfill plist because that plist invokes
# `~/.claude/bin/session-index-backfill.sh`, which is a symlink into the SEPARATE
# claude-session-search repo — appending to it would put half of this feature in a repo
# this branch cannot atomically commit. This sweep is already loaded, already holds the
# lock, and already owns the index, so it carries the cadence itself: a marker file, one
# `find -mmin` test per tick, and the pass runs at most once every 7 days.
# SESSION_INDEX_RETENTION_DAYS=0 disables it.
SESSION_INDEX_RETENTION_DAYS="${SESSION_INDEX_RETENTION_DAYS:-7}"
RETENTION_STAMP="${SESSION_INDEX_RETENTION_STAMP:-$HOME/.claude/state/session-index-retention.last}"
if [ "$SESSION_INDEX_RETENTION_DAYS" -gt 0 ] 2>/dev/null; then
    _due=0
    if [ ! -f "$RETENTION_STAMP" ]; then
        _due=1
    elif [ -n "$(find "$RETENTION_STAMP" -maxdepth 0 -mtime +"$((SESSION_INDEX_RETENTION_DAYS - 1))" 2>/dev/null)" ]; then
        _due=1
    fi
    if [ "$_due" -eq 1 ]; then
        mkdir -p "$(dirname "$RETENTION_STAMP")" 2>/dev/null || true
        date -u +"%Y-%m-%dT%H:%M:%SZ" > "$RETENTION_STAMP" 2>/dev/null || true
        read -r _rb _ra _rd <<< "$(session_index_retention --apply)"
        [ "${_rd:-0}" -gt 0 ] && session_index_log "Weekly retention: $_rb -> $_ra sessions ($_rd removed)"
    fi
fi

# ─── Log only when work was done ──────────────────────────
if [ "$WORK_DONE" -gt 0 ]; then
    if [ "$SKIPPED_BY_CAP" -gt 0 ]; then
        session_index_log "Sweep: indexed $WORK_DONE new/changed transcripts; DEFERRED $SKIPPED_BY_CAP to the next tick (cap=$SESSION_INDEX_SWEEP_MAX_FILES)"
    else
        session_index_log "Sweep: indexed $WORK_DONE new/changed transcripts"
    fi
fi

exit 0
