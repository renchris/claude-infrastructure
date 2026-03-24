#!/bin/bash
# Shared functions for session search indexing.
# Source: . "$(dirname "$0")/lib/session-index-helpers.sh"
# Or:    . "$REPO_DIR/hooks/lib/session-index-helpers.sh"

SESSION_INDEX_DB="$HOME/.claude/session-index.db"
SESSION_INDEX_LOG="$HOME/.claude/logs/session-index.log"
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
CLAUDE_HISTORY="$HOME/.claude/history.jsonl"

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

session_index_lock() {
    mkdir -p "$(dirname "$SESSION_INDEX_LOCKFILE")"
    exec 9>"$SESSION_INDEX_LOCKFILE"
    _SESSION_INDEX_LOCK_FD=9
    if ! flock -x 9 2>/dev/null; then
        # flock not available on some macOS — fall back to mkdir lock
        local _attempts=0
        while ! mkdir "$SESSION_INDEX_LOCKFILE.d" 2>/dev/null; do
            _attempts=$((_attempts + 1))
            if [ "$_attempts" -ge 300 ]; then
                session_index_log "Lock timeout after 300s, proceeding anyway"
                return 0
            fi
            sleep 1
        done
        _SESSION_INDEX_LOCK_FD="mkdir"
    fi
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
    # flock unavailable or lock held
    if mkdir "$SESSION_INDEX_LOCKFILE.d" 2>/dev/null; then
        _SESSION_INDEX_LOCK_FD="mkdir"
        trap 'session_index_unlock' EXIT
        return 0
    fi
    return 1
}

session_index_unlock() {
    if [ "$_SESSION_INDEX_LOCK_FD" = "mkdir" ]; then
        rmdir "$SESSION_INDEX_LOCKFILE.d" 2>/dev/null || true
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

session_index_lookup_sessions_index() {
    local project_dir="$1"
    local session_id="$2"
    local index_file="$project_dir/sessions-index.json"

    if [ ! -f "$index_file" ]; then
        return 1
    fi

    jq -r --arg sid "$session_id" '
        .entries[] | select(.sessionId == $sid) |
        [.summary // "", .firstPrompt // "", .gitBranch // "",
         .created // "", .modified // "", (.messageCount // 0 | tostring)] |
        join("\t")
    ' "$index_file" 2>/dev/null
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

session_index_extract_enriched() {
    local transcript_path="$1"
    local max_assistant_chars="${2:-3000}"
    local max_files="${3:-100}"
    [ -f "$transcript_path" ] || { printf '\t\t'; return; }

    # Skip very large transcripts (>50MB) to prevent OOM
    local file_size
    file_size=$(stat -f%z "$transcript_path" 2>/dev/null || stat -c%s "$transcript_path" 2>/dev/null || echo 0)
    if [ "$file_size" -gt 52428800 ]; then
        session_index_log "Skipping large transcript ($file_size bytes): $transcript_path"
        printf '\t\t'
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
    sys.stdout.write(at + '\t' + fc + '\t' + cr)
except MemoryError:
    sys.stdout.write('\t\t')
    sys.exit(0)
" 2>/dev/null || printf '\t\t'
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

    jq -r '.[] | .term as $term | .category as $cat | .expansions[] | [$term, ., $cat] | @tsv' "$synonyms_file" | \
    while IFS=$'\t' read -r term expansion category; do
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
