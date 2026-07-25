#!/bin/bash
# Shared functions for session search indexing.
# Source: . "$(dirname "$0")/lib/session-index-helpers.sh"
# Or:    . "$REPO_DIR/hooks/lib/session-index-helpers.sh"

# shellcheck disable=SC2034
#   Library globals. CLAUDE_PROJECTS_DIR is read by session-index-sweep.sh and
#   session-index-end.sh *after* sourcing this file, which shellcheck cannot follow.
# shellcheck disable=SC2001
#   The `echo "$v" | sed "s/'/''/g"` SQL single-quote doubling is deliberate and applied
#   uniformly to every column of the INSERT statements below. ${v//\'/\'\'} is equivalent,
#   but rewriting 20 call sites in the index write path is not a lint pass's business.
#
# Env seams (same defaults as before). Needed so a retention/sweep run can be REHEARSED
# against a copy of the index over the real transcript tree before anything destructive
# touches the live DB — and so a test can point at a fixture without moving $HOME.
SESSION_INDEX_DB="${SESSION_INDEX_DB:-$HOME/.claude/session-index.db}"
SESSION_INDEX_LOG="${SESSION_INDEX_LOG:-$HOME/.claude/logs/session-index.log}"
CLAUDE_PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
CLAUDE_HISTORY="${CLAUDE_HISTORY:-$HOME/.claude/history.jsonl}"

# Resolve repo root (follows symlink if helpers are symlinked from ~/.claude/hooks/)
_helpers_real=$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")
if [[ "$_helpers_real" == /* ]]; then
    SESSION_SEARCH_REPO="$(cd "$(dirname "$(dirname "$(dirname "$_helpers_real")")")" && pwd)"
else
    SESSION_SEARCH_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
SESSION_SEARCH_PYTHON_DEPS="$SESSION_SEARCH_REPO/.python-deps"
export SESSION_SEARCH_PYTHON_DEPS

# ─── Logging ───────────────────────────────────────────────

session_index_log() {
    local msg="$1"
    mkdir -p "$(dirname "$SESSION_INDEX_LOG")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$SESSION_INDEX_LOG"
}

# ─── Safe SQLite Wrapper ──────────────────────────────────
# Every sqlite3 CLI invocation MUST use this wrapper to ensure busy_timeout
# is set. Raw `sqlite3 "$SESSION_INDEX_DB"` spawns a fresh process with 0ms
# timeout, causing SQLITE_BUSY crashes under concurrent access.
#
# Usage:
#   session_index_sql "SELECT COUNT(*) FROM sessions;"
#   session_index_sql <<'SQL'
#   INSERT INTO sessions (...) VALUES (...);
#   SQL

SESSION_INDEX_BUSY_TIMEOUT="${SESSION_INDEX_BUSY_TIMEOUT:-5000}"

session_index_sql() {
    if [ $# -gt 0 ]; then
        sqlite3 "$SESSION_INDEX_DB" ".timeout $SESSION_INDEX_BUSY_TIMEOUT" "$1"
    else
        # Read SQL from stdin (heredoc)
        local sql
        sql=$(cat)
        sqlite3 "$SESSION_INDEX_DB" ".timeout $SESSION_INDEX_BUSY_TIMEOUT" "$sql"
    fi
}

# ─── Script-Level Lock ────────────────────────────────────
# Prevents concurrent heavy writers (backfill, tagger) from conflicting.
# Hooks use non-blocking mode and skip if locked.
#
# Usage:
#   session_index_lock         # blocking — waits for lock (backfill/tagger)
#   session_index_trylock      # non-blocking — returns 1 if locked (hooks)
#   session_index_unlock       # release (called automatically on EXIT)

SESSION_INDEX_LOCKFILE="$HOME/.claude/session-index.lock"
_SESSION_INDEX_LOCK_FD=""
# ─── Stale-holder recovery for the mkdir lock (a15/D1) ────────────────────────────────
# WHY THIS EXISTS, measured rather than predicted. `flock` is ABSENT on macOS (verified:
# `command -v flock` → nothing), so every path below falls through to the mkdir fallback, and that
# fallback had NO stale recovery of any kind: no TTL, no owner check, and nothing in hooks/bin/
# scripts/launchd ever removed the dir. `unlock` released it only from a clean EXIT trap, which does
# not run on SIGKILL — and the holder is `com.claude.session-search-sweep`, the most OOM-exposed
# process in the repo (it guards itself by skipping >50 MB transcripts).
#
# THE PREDICTED FAILURE ALREADY HAPPENED AND RAN FOR 111 DAYS. ~/.claude/session-index.lock.d was
# created 2026-04-09 23:47:50 and never removed. From ~/.claude/logs/session-index.log, split at that
# instant: "Indexed session" 1033 before / 0 after · "Sweep: indexed" 2889 before / 1 after · "lock
# held by another process" 383 before / 8096 after. The last successful index was 23:45:03 and the
# last sweep 23:47:27 — seconds before the orphan appeared. Full session indexing has been dead ever
# since, while session-index-start.sh (the one writer that takes no lock) kept adding stub rows, so
# the DB's mtime and its "5802 sessions" count both looked healthy. A liveness proxy that reads the
# output of a DIFFERENT writer cannot see this.
#
# THE RULE — never steal from a holder that might be alive; always reclaim one that provably is not:
#   • pid alive AND lstart matches (or no lstart recorded) → a real holder → do not touch.
#   • pid dead, or alive with a MISMATCHED lstart (the OS recycled a dead holder's pid onto a new
#     process — `kill -0` alone cannot see that; the land-lock flake of 2026-07-25) → reclaim.
#   • NO pid recorded at all → either a holder 2 ms from writing its token, or pre-fix debris like
#     the April dir. Grace-then-age: reclaim only once the dir is older than the stale window, so a
#     mid-acquire peer is never robbed but 111-day debris cannot outlive one sweep interval.
# Env seam (tests): SESSION_INDEX_LOCK_STALE_S.
_session_index_lock_is_stale() {  # 0 = reclaimable, 1 = a live holder
    local d="$SESSION_INDEX_LOCKFILE.d" pid rec cur age stale
    stale="${SESSION_INDEX_LOCK_STALE_S:-900}"
    pid="$(cat "$d/pid" 2>/dev/null || echo "")"
    case "$pid" in
        ''|*[!0-9]*)
            age=$(( $(date +%s) - $(stat -f %m "$d" 2>/dev/null || echo 0) ))
            [ "$age" -ge "$stale" ] && return 0
            return 1 ;;
    esac
    kill -0 "$pid" 2>/dev/null || return 0          # holder is gone → reclaim
    rec="$(cat "$d/lstart" 2>/dev/null || echo "")"
    cur="$(ps -o lstart= -p "$pid" 2>/dev/null || echo "")"
    [ -n "$rec" ] && [ "$rec" != "$cur" ] && return 0   # pid recycled → original holder dead
    return 1                                        # live, identity confirmed → never steal
}

# Record ownership INSIDE the lock dir, so a later acquirer can judge us. Note this is why release
# can no longer be a bare `rmdir` (see session_index_unlock).
_session_index_lock_own() {
    printf '%s\n' "$$" > "$SESSION_INDEX_LOCKFILE.d/pid" 2>/dev/null || true
    ps -o lstart= -p "$$" 2>/dev/null > "$SESSION_INDEX_LOCKFILE.d/lstart" || true
}

# mkdir, with one owner-verified reclaim attempt. 0 = acquired, 1 = genuinely held by someone live.
_session_index_mkdir_lock() {
    mkdir "$SESSION_INDEX_LOCKFILE.d" 2>/dev/null && { _session_index_lock_own; return 0; }
    _session_index_lock_is_stale || return 1
    session_index_log "Reclaiming stale index lock (holder gone; dir $(( $(date +%s) - $(stat -f %m "$SESSION_INDEX_LOCKFILE.d" 2>/dev/null || echo 0) ))s old)"
    rm -rf "$SESSION_INDEX_LOCKFILE.d" 2>/dev/null || return 1
    mkdir "$SESSION_INDEX_LOCKFILE.d" 2>/dev/null && { _session_index_lock_own; return 0; }
    return 1                                        # a peer won the reclaim race — correctly held
}

session_index_lock() {
    mkdir -p "$(dirname "$SESSION_INDEX_LOCKFILE")"
    exec 9>"$SESSION_INDEX_LOCKFILE"
    # Do NOT set the FD before flock succeeds (a15/D3): with flock absent the old code left
    # _FD="9" while holding a MKDIR lock, so unlock took the flock branch (`flock -u 9`, a no-op)
    # and never removed the dir — a second way to orphan it. The FD is now set only by the branch
    # that actually acquired.
    if flock -x 9 2>/dev/null; then
        _SESSION_INDEX_LOCK_FD=9
        trap 'session_index_unlock' EXIT
        return 0
    fi
    # flock not available on some macOS — fall back to mkdir lock
    local _attempts=0
    while ! _session_index_mkdir_lock; do
        _attempts=$((_attempts + 1))
        if [ "$_attempts" -ge 300 ]; then
            # RETURN 1, never "proceeding anyway" (a15/D3). The old code returned SUCCESS on timeout
            # without holding anything and — because it returned before the trap below — without
            # arming release either. Two callers could both "hold" the lock and write the DB
            # concurrently. Failing honestly lets the caller skip, which is what every caller of this
            # family already does correctly.
            session_index_log "Lock timeout after ${_attempts}s — NOT proceeding (lock is held)"
            exec 9>&- 2>/dev/null || true
            return 1
        fi
        sleep 1
    done
    _SESSION_INDEX_LOCK_FD="mkdir"
    trap 'session_index_unlock' EXIT
}

session_index_trylock() {
    mkdir -p "$(dirname "$SESSION_INDEX_LOCKFILE")"
    exec 9>"$SESSION_INDEX_LOCKFILE"
    if flock -n -x 9 2>/dev/null; then
        _SESSION_INDEX_LOCK_FD=9
        trap 'session_index_unlock' EXIT
        return 0
    fi
    # flock unavailable or lock held — mkdir path, now with owner-verified stale reclaim
    if _session_index_mkdir_lock; then
        _SESSION_INDEX_LOCK_FD="mkdir"
        trap 'session_index_unlock' EXIT
        return 0
    fi
    exec 9>&- 2>/dev/null || true
    return 1
}

session_index_unlock() {
    if [ "$_SESSION_INDEX_LOCK_FD" = "mkdir" ]; then
        # OWNER-VERIFIED, and `rm -rf` not `rmdir` — the dir now CONTAINS our pid/lstart token, so
        # `rmdir` would fail on a non-empty directory and silently never release (turning the fix
        # into the very wedge it removes). Verifying the token first is what keeps release safe: if
        # our lock was reclaimed as stale and a peer now holds its own, the pid file is theirs and an
        # unconditional delete here would drop a LIVE holder's lock and admit a third (a15/D4).
        if [ "$(cat "$SESSION_INDEX_LOCKFILE.d/pid" 2>/dev/null || echo)" = "$$" ]; then
            rm -rf "$SESSION_INDEX_LOCKFILE.d" 2>/dev/null || true
        fi
    elif [ -n "$_SESSION_INDEX_LOCK_FD" ]; then
        flock -u "$_SESSION_INDEX_LOCK_FD" 2>/dev/null || true
        exec 9>&- 2>/dev/null || true
    fi
    _SESSION_INDEX_LOCK_FD=""
}

# ─── Database Init ─────────────────────────────────────────
# Uses standalone FTS5 (no content= sync) to avoid SQLite trigger restrictions.
# FTS is rebuilt after bulk operations and kept in sync manually on single upserts.

session_index_init_db() {
    mkdir -p "$(dirname "$SESSION_INDEX_DB")"

    # Migrate: add context_text column if missing
    if [ -f "$SESSION_INDEX_DB" ]; then
        local has_col
        has_col=$(sqlite3 "$SESSION_INDEX_DB" "PRAGMA table_info(sessions);" 2>/dev/null | grep -c 'context_text' || true)
        if [ "$has_col" = "0" ]; then
            sqlite3 "$SESSION_INDEX_DB" >/dev/null 2>&1 <<'MIGRATE'
ALTER TABLE sessions ADD COLUMN context_text TEXT NOT NULL DEFAULT '';
DROP TABLE IF EXISTS sessions_fts;
MIGRATE
            session_index_log "Migrated: added context_text column, FTS will be recreated"
        fi
    fi

    # Migrate: add enrichment columns if missing
    if [ -f "$SESSION_INDEX_DB" ]; then
        local has_assistant
        has_assistant=$(sqlite3 "$SESSION_INDEX_DB" "PRAGMA table_info(sessions);" 2>/dev/null | grep -c 'assistant_text' || true)
        if [ "$has_assistant" = "0" ]; then
            sqlite3 "$SESSION_INDEX_DB" >/dev/null 2>&1 <<'MIGRATE2'
ALTER TABLE sessions ADD COLUMN assistant_text TEXT NOT NULL DEFAULT '';
ALTER TABLE sessions ADD COLUMN files_changed TEXT NOT NULL DEFAULT '';
ALTER TABLE sessions ADD COLUMN commands_run TEXT NOT NULL DEFAULT '';
DROP TABLE IF EXISTS sessions_fts;
MIGRATE2
            session_index_log "Migrated: added assistant_text, files_changed, commands_run columns, FTS will be recreated"
        fi
    fi

    # Migrate: add search_aliases column if missing
    if [ -f "$SESSION_INDEX_DB" ]; then
        local has_aliases
        has_aliases=$(sqlite3 "$SESSION_INDEX_DB" "PRAGMA table_info(sessions);" 2>/dev/null | grep -c 'search_aliases' || true)
        if [ "$has_aliases" = "0" ]; then
            sqlite3 "$SESSION_INDEX_DB" >/dev/null 2>&1 <<'MIGRATE3'
ALTER TABLE sessions ADD COLUMN search_aliases TEXT NOT NULL DEFAULT '';
DROP TABLE IF EXISTS sessions_fts;
MIGRATE3
            session_index_log "Migrated: added search_aliases column, FTS will be recreated"
        fi
    fi

    sqlite3 "$SESSION_INDEX_DB" >/dev/null <<'SCHEMA'
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA busy_timeout=1000;

CREATE TABLE IF NOT EXISTS sessions (
    session_id    TEXT PRIMARY KEY,
    project_path  TEXT NOT NULL,
    project_name  TEXT NOT NULL,
    summary       TEXT NOT NULL DEFAULT '',
    first_prompt  TEXT NOT NULL DEFAULT '',
    context_text  TEXT NOT NULL DEFAULT '',
    assistant_text TEXT NOT NULL DEFAULT '',
    files_changed  TEXT NOT NULL DEFAULT '',
    commands_run   TEXT NOT NULL DEFAULT '',
    search_aliases TEXT NOT NULL DEFAULT '',
    git_branch    TEXT NOT NULL DEFAULT '',
    created_at    TEXT NOT NULL,
    modified_at   TEXT NOT NULL,
    message_count INTEGER NOT NULL DEFAULT 0,
    tags          TEXT NOT NULL DEFAULT '',
    keywords      TEXT NOT NULL DEFAULT '',
    source        TEXT NOT NULL DEFAULT 'unknown',
    indexed_at    TEXT NOT NULL,
    tagged_at     TEXT DEFAULT NULL
);

CREATE VIRTUAL TABLE IF NOT EXISTS sessions_fts USING fts5(
    session_id, summary, first_prompt, tags, keywords, project_name, context_text,
    assistant_text, files_changed, commands_run, search_aliases,
    tokenize='porter unicode61 remove_diacritics 1',
    prefix='2 3'
);

CREATE TABLE IF NOT EXISTS synonyms (
    term      TEXT NOT NULL,
    expansion TEXT NOT NULL,
    category  TEXT,
    PRIMARY KEY (term, expansion)
);

CREATE TABLE IF NOT EXISTS search_log (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    query         TEXT,
    result_count  INTEGER,
    selected_id   TEXT,
    selected_rank INTEGER,
    pipeline_ms   INTEGER,
    created_at    TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS session_chunks (
    chunk_id      TEXT PRIMARY KEY,
    session_id    TEXT NOT NULL,
    chunk_index   INTEGER NOT NULL,
    start_turn    INTEGER NOT NULL,
    end_turn      INTEGER NOT NULL,
    user_text     TEXT NOT NULL DEFAULT '',
    assistant_text TEXT NOT NULL DEFAULT '',
    files_mentioned TEXT NOT NULL DEFAULT '',
    commands_mentioned TEXT NOT NULL DEFAULT '',
    UNIQUE(session_id, chunk_index)
);
CREATE INDEX IF NOT EXISTS idx_chunks_session ON session_chunks(session_id);

CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
    chunk_id, session_id, user_text, assistant_text, files_mentioned, commands_mentioned,
    tokenize='porter unicode61 remove_diacritics 1',
    prefix='2 3'
);
SCHEMA
}

# ─── Upsert Session ───────────────────────────────────────

session_index_upsert() {
    local session_id="$1"
    local project_path="$2"
    local project_name="$3"
    local summary="$4"
    local first_prompt="$5"
    local git_branch="$6"
    local created_at="$7"
    local modified_at="$8"
    local message_count="$9"
    local tags="${10}"
    local keywords="${11}"
    local source="${12}"
    local context_text="${13:-}"
    local assistant_text="${14:-}"
    local files_changed="${15:-}"
    local commands_run="${16:-}"
    local search_aliases="${17:-}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    session_index_sql <<SQL
INSERT INTO sessions (session_id, project_path, project_name, summary, first_prompt,
    context_text, assistant_text, files_changed, commands_run, search_aliases,
    git_branch, created_at, modified_at, message_count, tags, keywords, source, indexed_at)
VALUES (
    '$(echo "$session_id" | sed "s/'/''/g")',
    '$(echo "$project_path" | sed "s/'/''/g")',
    '$(echo "$project_name" | sed "s/'/''/g")',
    '$(echo "$summary" | sed "s/'/''/g")',
    '$(echo "$first_prompt" | sed "s/'/''/g")',
    '$(echo "$context_text" | sed "s/'/''/g")',
    '$(echo "$assistant_text" | sed "s/'/''/g")',
    '$(echo "$files_changed" | sed "s/'/''/g")',
    '$(echo "$commands_run" | sed "s/'/''/g")',
    '$(echo "$search_aliases" | sed "s/'/''/g")',
    '$(echo "$git_branch" | sed "s/'/''/g")',
    '$(echo "$created_at" | sed "s/'/''/g")',
    '$(echo "$modified_at" | sed "s/'/''/g")',
    $message_count,
    '$(echo "$tags" | sed "s/'/''/g")',
    '$(echo "$keywords" | sed "s/'/''/g")',
    '$(echo "$source" | sed "s/'/''/g")',
    '$now'
)
ON CONFLICT(session_id) DO UPDATE SET
    project_path  = CASE WHEN excluded.source >= sessions.source THEN excluded.project_path  ELSE sessions.project_path  END,
    project_name  = CASE WHEN excluded.source >= sessions.source THEN excluded.project_name  ELSE sessions.project_name  END,
    summary       = CASE WHEN excluded.summary != '' AND (excluded.source >= sessions.source OR sessions.summary = '') THEN excluded.summary ELSE sessions.summary END,
    first_prompt  = CASE WHEN excluded.first_prompt != '' AND (excluded.source >= sessions.source OR sessions.first_prompt = '') THEN excluded.first_prompt ELSE sessions.first_prompt END,
    context_text  = CASE WHEN excluded.context_text != '' AND (excluded.source >= sessions.source OR sessions.context_text = '') THEN excluded.context_text ELSE sessions.context_text END,
    assistant_text = CASE WHEN excluded.assistant_text != '' AND (excluded.source >= sessions.source OR sessions.assistant_text = '') THEN excluded.assistant_text ELSE sessions.assistant_text END,
    files_changed  = CASE WHEN excluded.files_changed != '' AND (excluded.source >= sessions.source OR sessions.files_changed = '') THEN excluded.files_changed ELSE sessions.files_changed END,
    commands_run   = CASE WHEN excluded.commands_run != '' AND (excluded.source >= sessions.source OR sessions.commands_run = '') THEN excluded.commands_run ELSE sessions.commands_run END,
    search_aliases = CASE WHEN excluded.search_aliases != '' AND (excluded.source >= sessions.source OR sessions.search_aliases = '') THEN excluded.search_aliases ELSE sessions.search_aliases END,
    git_branch    = CASE WHEN excluded.git_branch != '' THEN excluded.git_branch ELSE sessions.git_branch END,
    modified_at   = CASE WHEN excluded.modified_at > sessions.modified_at THEN excluded.modified_at ELSE sessions.modified_at END,
    message_count = CASE WHEN excluded.message_count > sessions.message_count THEN excluded.message_count ELSE sessions.message_count END,
    tags          = CASE WHEN excluded.tags != '' THEN excluded.tags ELSE sessions.tags END,
    keywords      = CASE WHEN excluded.keywords != '' THEN excluded.keywords ELSE sessions.keywords END,
    source        = CASE WHEN excluded.source >= sessions.source THEN excluded.source ELSE sessions.source END,
    indexed_at    = '$now';
SQL
}

# ─── Upsert + FTS sync (for single-row operations like hooks) ───

session_index_upsert_with_fts() {
    session_index_upsert "$@"
    local session_id="$1"
    local sid_escaped
    sid_escaped=$(echo "$session_id" | sed "s/'/''/g")

    # Remove old FTS entry, insert new one
    session_index_sql <<SQL
DELETE FROM sessions_fts WHERE session_id = '$sid_escaped';
INSERT INTO sessions_fts (session_id, summary, first_prompt, tags, keywords, project_name, context_text, assistant_text, files_changed, commands_run, search_aliases)
    SELECT session_id, summary, first_prompt, tags, keywords, project_name, context_text, assistant_text, files_changed, commands_run, search_aliases
    FROM sessions WHERE session_id = '$sid_escaped';
SQL
}

# ─── Keyword Extraction ───────────────────────────────────

session_index_extract_keywords() {
    local text="$1"
    # Extract: kebab-case, dotted names, file extensions, underscored names
    # Note: grep -oE returns exit 1 on no match; || true prevents pipefail abort
    local regex_keywords
    regex_keywords=$(echo "$text" | tr '[:upper:]' '[:lower:]' | \
        (grep -oE '[a-z]+[-][a-z]+[-a-z]*|[a-z]+\.[a-z]+(\.[a-z]+)*|[a-z_]+\.(ts|tsx|js|jsx|py|sh|sql|json|md)|[a-z]+_[a-z_]+' || true) | \
        sort -u | tr '\n' ',' | sed 's/,$//')

    # YAKE key phrase extraction (optional — silently skipped if not installed)
    local yake_keywords
    yake_keywords=$(python3 -c "
import sys, os
deps = os.environ.get('SESSION_SEARCH_PYTHON_DEPS', '')
if deps and os.path.isdir(deps):
    sys.path.insert(0, deps)
try:
    import yake
    extractor = yake.KeywordExtractor(top=10, stopwords='en', dedupLim=0.7)
    text = sys.argv[1][:5000]
    keyphrases = extractor.extract_keywords(text)
    phrases = [kw[0].lower().replace(' ', '-') for kw in keyphrases if kw[1] < 0.1]
    print(','.join(phrases))
except ImportError:
    pass
except Exception:
    pass
" "$text" 2>/dev/null || true)

    # Merge and deduplicate
    local merged
    if [ -n "$regex_keywords" ] && [ -n "$yake_keywords" ]; then
        merged="$regex_keywords,$yake_keywords"
    elif [ -n "$regex_keywords" ]; then
        merged="$regex_keywords"
    else
        merged="$yake_keywords"
    fi

    # Deduplicate comma-separated list, output space-separated
    echo "$merged" | tr ',' '\n' | sort -u | tr '\n' ' '
}

# ─── Project Name from Path ───────────────────────────────

session_index_project_name() {
    local project_path="$1"
    basename "$project_path"
}

# ─── Lookup sessions-index.json ───────────────────────────
# TSV field-collapse guard — docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md. The caller reads this
# with `IFS=$'\t' read`, and tab is IFS-*whitespace*: `read` collapses a RUN of tabs, so ANY empty
# cell shifts every later field one position LEFT — silently, with a zero exit status. EVERY column
# here defaults to "" and several are routinely empty on real entries (`.gitBranch` for any session
# outside a repo, `.summary` before one is written), so the row was landing gitBranch in CREATED_AT
# and messageCount in MODIFIED_AT — corrupting the session-search index that claude-search reads.
# `//` is what produces the "" — it substitutes for null, so it cannot also be the fix. Each cell is
# padded to $'\037' at the emitter and un-padded by the caller, which needs the real ""
# (`[ -z "$SUMMARY" ]` is its transcript-fallback predicate). SESSION_INDEX_TSV_PAD is the SSOT.
SESSION_INDEX_TSV_PAD=$'\037'

session_index_lookup_sessions_index() {
    local project_dir="$1"
    local session_id="$2"
    local index_file="$project_dir/sessions-index.json"

    if [ ! -f "$index_file" ]; then
        return 1
    fi

    jq -r --arg sid "$session_id" --arg pad "$SESSION_INDEX_TSV_PAD" '
        def cell: (if . == null then "" else . end) | tostring
                  | gsub("[\\t\\r\\n]"; " ") | if . == "" then $pad else . end;
        .entries[] | select(.sessionId == $sid) |
        [(.summary | cell), (.firstPrompt | cell), (.gitBranch | cell),
         (.created | cell), (.modified | cell), ((.messageCount // 0) | cell)] |
        join("\t")
    ' "$index_file" 2>/dev/null
}

# session_index_unpad <value> → the value, or "" if it is the empty-cell sentinel.
session_index_unpad() {
    [ "$1" = "$SESSION_INDEX_TSV_PAD" ] && return 0
    printf '%s' "$1"
}

# ─── Extract Context Text from Transcript ─────────────────

session_index_extract_context() {
    local transcript_path="$1"
    local max_messages="${2:-10}"
    [ -f "$transcript_path" ] || return
    python3 -c "
import json, sys, re
msgs = []
total_user = 0
with open('$transcript_path') as f:
    for line in f:
        try:
            d = json.loads(line)
            if d.get('type') != 'user': continue
            total_user += 1
            content = d.get('message', {}).get('content', '')
            if isinstance(content, list):
                text = ' '.join(c.get('text','') for c in content if isinstance(c, dict) and c.get('type')=='text')
            else:
                text = str(content)
            text = text.strip()
            # Skip system/command/XML messages and single-word responses
            if not text or text.startswith('<') or text.startswith('<!--'): continue
            if len(text) < 10: continue
            # Skip plan preambles (## Context, ## Phase, markdown headers at start)
            # but keep the substantive parts
            lines = text.split('\n')
            substantive = []
            for ln in lines:
                ln = ln.strip()
                if not ln: continue
                # Skip markdown structure: headers, horizontal rules, code fences
                if re.match(r'^#{1,4}\s', ln) or ln.startswith('---') or ln.startswith('\`\`\`'): continue
                # Skip bullet points that are just labels
                if re.match(r'^[-*]\s\*\*\w+\*\*:', ln): continue
                substantive.append(ln)
            text = ' '.join(substantive)[:400]
            if len(text) < 10: continue
            msgs.append(text)
            if len(msgs) >= $max_messages: break
        except: pass
# Output: context text, then message count on a separate line
print(' '.join(msgs)[:2500])
print(total_user, file=sys.stderr)
" 2>/dev/null || echo ""
}

# Extract both context_text and message_count from a transcript
session_index_extract_transcript_meta() {
    local transcript_path="$1"
    [ -f "$transcript_path" ] || return
    python3 -c "
import json, os
path = '$transcript_path'
user_count = 0
with open(path) as f:
    for line in f:
        try:
            d = json.loads(line)
            if d.get('type') == 'user':
                user_count += 1
        except: pass
print(user_count)
" 2>/dev/null || echo "0"
}

# ─── Extract Enriched Data from Transcript ─────────────────
# Extracts assistant text, file paths, and commands from transcript JSONL.
# Output: tab-separated assistant_text\tfiles_changed\tcommands_run
#
# TSV field-collapse guard — docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md. Every caller reads this
# with `IFS=$'\t' read`, and tab is IFS-*whitespace*: `read` collapses a RUN of tabs, so ANY empty
# cell shifts every later field one position LEFT. A transcript with no qualifying assistant text but
# real tool calls (an all-tool_use session) emitted "\t<files>\t<cmds>" and the reader stored the FILE
# LIST as assistant_text and the COMMANDS as files_changed — corrupting the search index silently.
# Each cell is padded to a single SPACE, deliberately NOT the $'\037' sentinel used elsewhere: a
# space is not in IFS here so it holds the column open, and it is inert if a caller does not un-pad
# it (" " indexes as nothing). That matters because one caller — hooks/session-index-sweep.sh — is
# being rewritten on the in-flight fix/infra-perfection wave and must not be edited from here.

session_index_extract_enriched() {
    local transcript_path="$1"
    local max_assistant_chars="${2:-3000}"
    local max_files="${3:-100}"
    [ -f "$transcript_path" ] || { printf ' \t \t '; return; }

    # Skip very large transcripts (>50MB) to prevent OOM
    local file_size
    file_size=$(stat -f%z "$transcript_path" 2>/dev/null || stat -c%s "$transcript_path" 2>/dev/null || echo 0)
    if [ "$file_size" -gt 52428800 ]; then
        session_index_log "Skipping large transcript ($file_size bytes): $transcript_path"
        printf ' \t \t '
        return 0
    fi

    python3 -c "
import json, sys
try:
    assistant_texts = []
    files = set()
    commands = []
    line_count = 0
    max_lines = 10000
    with open('$transcript_path') as f:
        for line in f:
            line_count += 1
            if line_count > max_lines:
                break
            try:
                obj = json.loads(line)
                if obj.get('type') == 'assistant':
                    for block in obj.get('message', {}).get('content', []):
                        if block.get('type') == 'text':
                            text = block.get('text', '').strip()
                            if len(text) > 30 and not text.startswith('<'):
                                assistant_texts.append(text[:500])
                        elif block.get('type') == 'tool_use':
                            name = block.get('name', '')
                            inp = block.get('input', {})
                            if name in ('Read', 'Write', 'Edit'):
                                fp = inp.get('file_path', '')
                                if fp:
                                    files.add(fp)
                            elif name in ('Glob', 'Grep'):
                                path = inp.get('path', '')
                                pattern = inp.get('pattern', '')
                                if path: files.add(path)
                                if pattern: files.add(pattern)
                            elif name == 'Bash':
                                cmd = inp.get('command', '')
                                if cmd and len(cmd) < 500:
                                    commands.append(cmd)
                elif obj.get('type') == 'file-history-snapshot':
                    backups = obj.get('snapshot', {}).get('trackedFileBackups', {})
                    files.update(backups.keys())
            except:
                pass
    at = ' '.join(assistant_texts)[:$max_assistant_chars].replace('\t', ' ').replace('\n', ' ').replace('\r', ' ')
    fc = ' '.join(sorted(files)[:$max_files]).replace('\t', ' ').replace('\n', ' ')
    cr = ' '.join(commands[:50]).replace('\t', ' ').replace('\n', ' ').replace('\r', ' ')
    # Hold every column open — an empty cell would shift the later ones left in the caller's
    # \`IFS=\$'\t' read\` (see the header note). A space is inert wherever it is not un-padded.
    sys.stdout.write((at or ' ') + '\t' + (fc or ' ') + '\t' + (cr or ' '))
except MemoryError:
    sys.stdout.write(' \t \t ')
    sys.exit(0)
" 2>/dev/null || printf ' \t \t '
}

# ─── Batched change detection (the sweep's hot path) ───────
# Emits ONE tab-separated row per NEW-or-CHANGED transcript: <path>\t<mtime>\t<size>.
#
# Replaces the per-file cost that made the sweep a 59 s-per-60 s-tick scanner once
# unblocked (audit 06 §3/§5.3): 2× `stat` AND one `sqlite3` process **per transcript**
# — ~4,900 processes for 1,631 files. This is 3 processes total, whatever the count:
#   1. one `find … -exec stat +`  — batched stat, so also the single-pass replacement
#                                   for the old mtime+size stat pair
#   2. one `sqlite3`              — the whole file_tracking table, once
#   3. one `awk`                  — the join, in-memory
# maxdepth 3 preserves the two layouts the sweep has always handled: flat
# `<project>/<sid>.jsonl` and nested `<project>/<sid>/transcript.jsonl`.
session_index_changed_files() {
    local projects_dir="${1:-$CLAUDE_PROJECTS_DIR}"
    [ -d "$projects_dir" ] || return 0
    local tracking
    tracking=$(session_index_sql \
        "SELECT file_path || char(9) || last_mtime || char(9) || last_size FROM file_tracking;" \
        2>/dev/null || true)
    # %m mtime, %z size, %N path — path LAST so a path containing spaces still parses.
    find "$projects_dir" -maxdepth 3 -type f -name '*.jsonl' -exec stat -f '%m%t%z%t%N' {} + 2>/dev/null \
      | awk -F'\t' -v tracking="$tracking" '
          BEGIN {
              n = split(tracking, rows, "\n")
              for (i = 1; i <= n; i++) {
                  if (rows[i] == "") continue
                  split(rows[i], c, "\t")
                  seen[c[1]] = c[2] SUBSEP c[3]
              }
          }
          {
              path = $3
              if ((path in seen) && seen[path] == ($1 SUBSEP $2)) next
              print path "\t" $1 "\t" $2
          }'
}

# ─── One-pass transcript extraction ────────────────────────
# ONE python3 process per changed transcript, emitting every field the sweep needs:
#   context_text \t assistant_text \t files_changed \t commands_run \t message_count
#
# The sweep used to call session_index_extract_context + _extract_enriched +
# _extract_transcript_meta, i.e. **three full-file JSON parses of the same file** — on a
# 60 s tick that re-read every active session's growing transcript three times a minute
# (audit 06 §5.3). Semantics are preserved field-for-field; the three single-purpose
# functions above are kept for their other callers.
session_index_extract_all() {
    local transcript_path="$1"
    local max_messages="${2:-5}"
    local max_assistant_chars="${3:-3000}"
    local max_files="${4:-100}"
    [ -f "$transcript_path" ] || { printf '\t\t\t\t0'; return 0; }

    # Same >50MB OOM guard the enriched extractor has always had.
    local file_size
    file_size=$(stat -f%z "$transcript_path" 2>/dev/null || stat -c%s "$transcript_path" 2>/dev/null || echo 0)
    if [ "$file_size" -gt 52428800 ]; then
        session_index_log "Skipping large transcript ($file_size bytes): $transcript_path"
        printf '\t\t\t\t0'
        return 0
    fi

    TRANSCRIPT_PATH="$transcript_path" \
    MAX_MESSAGES="$max_messages" \
    MAX_ASSISTANT_CHARS="$max_assistant_chars" \
    MAX_FILES="$max_files" \
    python3 -c "
import json, os, re, sys
# Path/limits arrive through the ENVIRONMENT, not string interpolation: a transcript path
# is attacker-adjacent data and the older extractors spliced it straight into the program
# text, where a quote would break the parse (or worse).
path = os.environ['TRANSCRIPT_PATH']
max_messages = int(os.environ['MAX_MESSAGES'])
max_assistant_chars = int(os.environ['MAX_ASSISTANT_CHARS'])
max_files = int(os.environ['MAX_FILES'])

msgs, assistant_texts, commands = [], [], []
files = set()
user_count = 0
line_count = 0
MAX_LINES = 10000
try:
    with open(path) as f:
        for line in f:
            line_count += 1
            try:
                d = json.loads(line)
            except Exception:
                continue
            t = d.get('type')
            if t == 'user':
                # ── context_text: identical rules to session_index_extract_context ──
                user_count += 1
                if len(msgs) < max_messages:
                    content = d.get('message', {}).get('content', '')
                    if isinstance(content, list):
                        text = ' '.join(c.get('text','') for c in content
                                        if isinstance(c, dict) and c.get('type') == 'text')
                    else:
                        text = str(content)
                    text = text.strip()
                    if text and not text.startswith('<') and len(text) >= 10:
                        substantive = []
                        for ln in text.split('\n'):
                            ln = ln.strip()
                            if not ln: continue
                            if re.match(r'^#{1,4}\s', ln) or ln.startswith('---') or ln.startswith('\`\`\`'):
                                continue
                            if re.match(r'^[-*]\s\*\*\w+\*\*:', ln): continue
                            substantive.append(ln)
                        text = ' '.join(substantive)[:400]
                        if len(text) >= 10:
                            msgs.append(text)
            elif line_count <= MAX_LINES:
                # ── enriched: identical rules to session_index_extract_enriched, which
                #    stops at 10,000 lines. user_count above must NOT stop there — the old
                #    _extract_transcript_meta counted the whole file.
                if t == 'assistant':
                    for block in d.get('message', {}).get('content', []):
                        if not isinstance(block, dict): continue
                        if block.get('type') == 'text':
                            text = block.get('text', '').strip()
                            if len(text) > 30 and not text.startswith('<'):
                                assistant_texts.append(text[:500])
                        elif block.get('type') == 'tool_use':
                            name = block.get('name', '')
                            inp = block.get('input', {})
                            if name in ('Read', 'Write', 'Edit'):
                                fp = inp.get('file_path', '')
                                if fp: files.add(fp)
                            elif name in ('Glob', 'Grep'):
                                p = inp.get('path', ''); pat = inp.get('pattern', '')
                                if p: files.add(p)
                                if pat: files.add(pat)
                            elif name == 'Bash':
                                cmd = inp.get('command', '')
                                if cmd and len(cmd) < 500: commands.append(cmd)
                elif t == 'file-history-snapshot':
                    files.update(d.get('snapshot', {}).get('trackedFileBackups', {}).keys())
except MemoryError:
    sys.stdout.write('\t\t\t\t0'); sys.exit(0)
except Exception:
    sys.stdout.write('\t\t\t\t0'); sys.exit(0)

def flat(s):
    return s.replace('\t', ' ').replace('\n', ' ').replace('\r', ' ')

ctx = flat(' '.join(msgs)[:2500])
at  = flat(' '.join(assistant_texts)[:max_assistant_chars])
fc  = flat(' '.join(sorted(files)[:max_files]))
cr  = flat(' '.join(commands[:50]))
sys.stdout.write(ctx + '\t' + at + '\t' + fc + '\t' + cr + '\t' + str(user_count))
" 2>/dev/null || printf '\t\t\t\t0'
}

# ─── Retention: drop rows whose transcript no longer exists ────────────────────
# The index outlives its subject ~4× (audit 03 §1c): 5,453 session rows for ~1,600
# transcripts, because CC's cleanupPeriodDays deletes transcripts at 30 d and NOTHING
# ever deleted the corresponding index rows — no retention, no VACUUM, 717 free pages.
# Searching a session whose transcript is gone returns a result you cannot open.
#
# The predicate is deliberately narrow: a row is dropped ONLY when we positively
# resolved a path for it and that path is absent. A row whose path cannot be resolved
# at all is KEPT — "I could not find it" must never be read as "it does not exist".
#
# TWO predicates, both "positively resolved absent":
#   P1  a file_tracking row whose recorded file_path no longer exists.
#   P2  a sessions row whose session_id matches NO transcript on disk. P2 is the one that
#       matters — file_tracking has only ~498 rows for 5,453 sessions (it stopped being
#       written when the sweep wedged in April), so P1 alone can judge <10% of the index.
#
# FAIL-CLOSED: if the on-disk scan finds ZERO transcripts, the projects dir is missing or
# unreadable, not empty — deleting the whole index on that reading is the catastrophic
# failure mode. Nothing is deleted and the caller is told.
session_index_retention() { # [--apply]  → prints "<before> <after> <deleted>"
    local apply=0
    [ "${1:-}" = "--apply" ] && apply=1
    [ -f "$SESSION_INDEX_DB" ] || { echo "0 0 0"; return 0; }

    local before
    before=$(session_index_sql "SELECT COUNT(*) FROM sessions;" 2>/dev/null || echo 0)

    # The on-disk universe: every session UUID that still has a transcript, across EVERY
    # config dir — not just this one. MEASURED 2026-07-25: 1,087 of 5,494 indexed sessions
    # have their transcript under ~/.claude-{secondary,tertiary,quaternary}/projects. A
    # predicate that searched only $CLAUDE_PROJECTS_DIR would have called all 1,087 "gone"
    # and deleted live, openable sessions. Absence is only absence after looking everywhere.
    # maxdepth 3 is the right bound and was verified, not assumed: 0 UUID-named transcripts
    # exist deeper than that (the 1,295 deeper files are `agent-<hash>.jsonl` subagent
    # transcripts, which this index never contained).
    local roots ondisk n_ondisk r
    roots="${SESSION_INDEX_PROJECT_ROOTS:-$CLAUDE_PROJECTS_DIR $HOME/.claude-secondary/projects $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects}"
    ondisk=""
    # shellcheck disable=SC2086  # roots is an intentional space-separated list
    for r in $roots; do
        [ -d "$r" ] || continue
        ondisk="$ondisk
$(find "$r" -maxdepth 3 -type f -name '*.jsonl' 2>/dev/null \
        | while IFS= read -r f; do
              b=$(basename "$f" .jsonl)
              [ "$b" = "transcript" ] && b=$(basename "$(dirname "$f")")
              printf '%s\n' "$b"
          done)"
    done
    ondisk=$(printf '%s\n' "$ondisk" | grep . | sort -u)
    n_ondisk=$(printf '%s\n' "$ondisk" | grep -c . || true)
    if [ "${n_ondisk:-0}" -lt 1 ]; then
        session_index_log "Retention REFUSED: 0 transcripts found under [$roots] (unreadable, not empty)"
        echo "$before $before 0"
        return 0
    fi

    # Victims = indexed sessions absent from the on-disk universe (P2), plus tracked files
    # whose path is gone (P1). `comm` needs both sides sorted.
    local indexed victims dead
    indexed=$(session_index_sql "SELECT session_id FROM sessions;" 2>/dev/null | sort -u)
    victims=$(comm -23 <(printf '%s\n' "$indexed" | grep .) <(printf '%s\n' "$ondisk" | grep .))
    while IFS=$'\t' read -r sid path; do
        [ -n "$sid" ] && [ -n "$path" ] || continue
        [ -e "$path" ] && continue
        victims="$victims
$sid"
    done < <(session_index_sql \
        "SELECT session_id || char(9) || file_path FROM file_tracking;" 2>/dev/null || true)
    victims=$(printf '%s\n' "$victims" | grep . | sort -u)
    dead=$(printf '%s\n' "$victims" | grep -c . || true)

    if [ "$apply" -eq 1 ] && [ "${dead:-0}" -gt 0 ]; then
        # CHUNKED, deliberately. The obvious "one big transaction" builds ~1.8 MB of SQL for
        # 5,128 victims and session_index_sql passes it as a single argv string — which blows
        # past ARG_MAX, so sqlite3 never runs and `|| true` reports success while deleting
        # nothing. (Observed exactly that in rehearsal: deletable=5128, after=before.) Batching
        # keeps every invocation small, and each batch's status is CHECKED, not swallowed.
        local chunk="" n=0 failed=0 quoted
        _flush_chunk() {
            [ -n "$chunk" ] || return 0
            session_index_sql "BEGIN;
DELETE FROM session_chunks WHERE session_id IN ($chunk);
DELETE FROM chunks_fts    WHERE session_id IN ($chunk);
DELETE FROM sessions_fts  WHERE session_id IN ($chunk);
DELETE FROM sessions      WHERE session_id IN ($chunk);
DELETE FROM file_tracking WHERE session_id IN ($chunk);
COMMIT;" >/dev/null 2>&1 || failed=$((failed + 1))
            chunk=""; n=0
        }
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            quoted="'$(printf '%s' "$s" | sed "s/'/''/g")'"
            if [ -z "$chunk" ]; then chunk="$quoted"; else chunk="$chunk,$quoted"; fi
            n=$((n + 1))
            [ "$n" -ge 400 ] && _flush_chunk
        done <<< "$victims"
        _flush_chunk
        unset -f _flush_chunk
        if [ "$failed" -gt 0 ]; then
            session_index_log "Retention: $failed delete batch(es) FAILED — index partially pruned"
        fi
        session_index_sql "VACUUM;" >/dev/null 2>&1 || true
        session_index_log "Retention: removed $dead session(s) with no transcript on disk; VACUUM done"
    fi

    local after
    after=$(session_index_sql "SELECT COUNT(*) FROM sessions;" 2>/dev/null || echo 0)
    echo "$before $after ${dead:-0}"
}

# ─── Stats ─────────────────────────────────────────────────

session_index_stats() {
    if [ ! -f "$SESSION_INDEX_DB" ]; then
        echo "No index database found."
        return 1
    fi
    local total tagged projects last_indexed
    total=$(session_index_sql "SELECT COUNT(*) FROM sessions;" 2>/dev/null)
    tagged=$(session_index_sql "SELECT COUNT(*) FROM sessions WHERE tagged_at IS NOT NULL;" 2>/dev/null)
    projects=$(session_index_sql "SELECT COUNT(DISTINCT project_name) FROM sessions;" 2>/dev/null)
    last_indexed=$(session_index_sql "SELECT MAX(indexed_at) FROM sessions;" 2>/dev/null)
    echo "Sessions: $total | Tagged: $tagged | Projects: $projects | Last indexed: $last_indexed"
}

# ─── Rebuild FTS (for bulk operations) ─────────────────────

session_index_rebuild_fts() {
    session_index_sql <<'SQL'
DELETE FROM sessions_fts;
INSERT INTO sessions_fts (session_id, summary, first_prompt, tags, keywords, project_name, context_text, assistant_text, files_changed, commands_run, search_aliases)
    SELECT session_id, summary, first_prompt, tags, keywords, project_name, context_text, assistant_text, files_changed, commands_run, search_aliases FROM sessions;
SQL
}

session_index_rebuild_chunks_fts() {
    session_index_sql <<'SQL'
DELETE FROM chunks_fts;
INSERT INTO chunks_fts (chunk_id, session_id, user_text, assistant_text, files_mentioned, commands_mentioned)
    SELECT chunk_id, session_id, user_text, assistant_text, files_mentioned, commands_mentioned FROM session_chunks;
SQL
}

# ─── Load Synonyms from JSON ──────────────────────────────

session_index_load_synonyms() {
    local synonyms_file="$1"
    if [ ! -f "$synonyms_file" ]; then
        session_index_log "Synonyms file not found: $synonyms_file"
        return 1
    fi

    # TSV field-collapse guard (docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md): a synonyms entry
    # with no `.category` — or an empty `.term`/expansion — emitted an empty cell, which
    # `IFS=$'\t' read` collapses into the surrounding tab run, shifting the later fields LEFT and
    # inserting the EXPANSION under the term column. Padded at the emitter, un-padded here.
    jq -r --arg pad "$SESSION_INDEX_TSV_PAD" '
        def cell: (if . == null then "" else . end) | tostring
                  | gsub("[\\t\\r\\n]"; " ") | if . == "" then $pad else . end;
        .[] | .term as $term | .category as $cat | .expansions[]
        | [($term | cell), (. | cell), ($cat | cell)] | @tsv' "$synonyms_file" | \
    while IFS=$'\t' read -r term expansion category; do
        term=$(session_index_unpad "$term")
        expansion=$(session_index_unpad "$expansion")
        category=$(session_index_unpad "$category")
        session_index_sql "INSERT OR IGNORE INTO synonyms (term, expansion, category) VALUES ('$(echo "$term" | sed "s/'/''/g")', '$(echo "$expansion" | sed "s/'/''/g")', '$(echo "$category" | sed "s/'/''/g")');"
    done
}

# ─── File Tracking for Sweep Daemon ──────────────────────
# Creates file_tracking table and adds sweep columns to sessions.
# Idempotent — safe to call multiple times.

session_index_init_tracking() {
    [ -f "$SESSION_INDEX_DB" ] || return 0

    session_index_sql <<'SQL'
CREATE TABLE IF NOT EXISTS file_tracking (
    file_path     TEXT PRIMARY KEY,
    session_id    TEXT NOT NULL,
    project_dir   TEXT NOT NULL,
    last_mtime    INTEGER NOT NULL,
    last_size     INTEGER NOT NULL,
    last_swept_at TEXT NOT NULL,
    sweep_count   INTEGER DEFAULT 1,
    is_active     INTEGER DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_tracking_session ON file_tracking(session_id);
SQL

    # Add sweep_mtime and sweep_size to sessions if missing
    local has_sweep_mtime
    has_sweep_mtime=$(session_index_sql "PRAGMA table_info(sessions);" 2>/dev/null | grep -c 'sweep_mtime' || true)
    if [ "$has_sweep_mtime" = "0" ]; then
        session_index_sql "ALTER TABLE sessions ADD COLUMN sweep_mtime INTEGER DEFAULT NULL;"
        session_index_sql "ALTER TABLE sessions ADD COLUMN sweep_size INTEGER DEFAULT NULL;"
        session_index_log "Migrated: added sweep_mtime, sweep_size columns to sessions"
    fi
}
