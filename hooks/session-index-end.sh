#!/bin/bash
# SessionEnd hook — indexes the just-completed session.
# Reads session metadata from stdin JSON, looks up rich data from sessions-index.json.
# Performance target: <200ms.
set -euo pipefail

# ONE IDL ROW PER INVOCATION, written from an EXIT trap (hook `session-index-end`), so a death
# under errexit still leaves a `failed` row instead of nothing — a hook that dies silently is
# indistinguishable from one that was never called (docs/research/truememory-2026-09-27.md §3.3,
# gap 5). The lib path is dereferenced so the checkout's lib is found through the live symlink.
_sie_self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
_sie_lib="$(dirname "$_sie_self")/lib/idl-log.sh"
[ -r "$_sie_lib" ] || _sie_lib="$(dirname "${BASH_SOURCE[0]}")/lib/idl-log.sh"
if [ -r "$_sie_lib" ]; then
    # shellcheck source=lib/idl-log.sh
    # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
    . "$_sie_lib"
    idl_init "${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}" "session-index-end" SESSION_ID
else
    # shellcheck disable=SC2329  # the no-op stand-in, called from the EXIT trap
    log_idl() { :; }
fi
SESSION_ID="" _SIE_REASON=started _SIE_LOCKED=0 MSG_SRC=none
# `lock-held` and `no-helpers` are BLIND reasons in scripts/idl-abstain-alarm.sh: the orphaned
# lock of 2026-04 skipped every index for 111 days and logged only a free-text line.
# shellcheck disable=SC2329  # invoked by the EXIT trap, which shellcheck does not follow
_sie_exit() {
    local rc=$?
    if [ "$_SIE_LOCKED" = 1 ]; then session_index_unlock; fi
    if [ "$rc" -ne 0 ]; then
        log_idl failed "errexit:$rc" "$(jq -cn --arg r "$_SIE_REASON" '{last:$r}' 2>/dev/null)"
    elif [ "$_SIE_REASON" = indexed ]; then
        log_idl fired indexed "$(jq -cn --arg m "$MSG_COUNT" --arg s "$MSG_SRC" '{msgs:($m|tonumber? // 0),msgs_src:$s}' 2>/dev/null)"
    else
        log_idl abstained "$_SIE_REASON"
    fi
}
trap _sie_exit EXIT

# Read stdin (hook provides JSON with session_id, transcript_path, cwd)
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

# Fast exit if no session ID
[ -z "$SESSION_ID" ] && { _SIE_REASON=no-session-id; exit 0; }

# Resolve helpers — follow symlink to repo
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$SCRIPT_DIR/lib/session-index-helpers.sh"
if [ ! -f "$HELPERS" ]; then
    # Fallback: try the repo location directly
    HELPERS="$HOME/.claude/hooks/lib/session-index-helpers.sh"
fi
[ -f "$HELPERS" ] || { _SIE_REASON=no-helpers; exit 0; }
# shellcheck source=/dev/null  # $HELPERS is resolved at runtime (repo checkout or ~/.claude fallback)
source "$HELPERS"

# Init DB (idempotent)
session_index_init_db

# Non-blocking lock — skip if backfill/tagger is running (hook must be <200ms)
if ! session_index_trylock; then
    session_index_log "Skipped indexing $SESSION_ID (lock held by another process)"
    _SIE_REASON=lock-held
    exit 0
fi
# trylock installed its own `trap session_index_unlock EXIT`, replacing ours; take it back and
# release the lock from _sie_exit instead.
_SIE_LOCKED=1
trap _sie_exit EXIT

# Derive project directory from transcript path or cwd
PROJECT_DIR=""
if [ -n "$TRANSCRIPT_PATH" ]; then
    PROJECT_DIR=$(dirname "$TRANSCRIPT_PATH")
elif [ -n "$CWD" ]; then
    # Encode cwd to project dir name: /Users/chrisren/Dev/foo → -Users-chrisren-Dev-foo
    encoded="${CWD//\//-}"
    PROJECT_DIR="$CLAUDE_PROJECTS_DIR/$encoded"
fi

# Derive project path from cwd or directory name
PROJECT_PATH="${CWD:-}"
if [ -z "$PROJECT_PATH" ] && [ -n "$PROJECT_DIR" ]; then
    dir_name=$(basename "$PROJECT_DIR")
    PROJECT_PATH=$(echo "$dir_name" | sed 's/^-/\//' | sed 's/-/\//g')
fi
PROJECT_NAME=$(session_index_project_name "${PROJECT_PATH:-unknown}")

# Try sessions-index.json first (richest source)
SUMMARY="" FIRST_PROMPT="" GIT_BRANCH="" CREATED_AT="" MODIFIED_AT="" MSG_COUNT=0
if [ -n "$PROJECT_DIR" ]; then
    ENTRY=$(session_index_lookup_sessions_index "$PROJECT_DIR" "$SESSION_ID" 2>/dev/null || echo "")
    if [ -n "$ENTRY" ]; then
        IFS=$'\t' read -r SUMMARY FIRST_PROMPT GIT_BRANCH CREATED_AT MODIFIED_AT MSG_COUNT <<< "$ENTRY"
        # Un-pad the empty-cell sentinel the emitter uses to stop `IFS=$'\t' read` collapsing a run
        # of tabs (docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md). The real "" matters below:
        # [ -z "$SUMMARY" ] is the transcript-fallback predicate, and the CREATED_AT/MODIFIED_AT/
        # MSG_COUNT defaults are all keyed on emptiness.
        SUMMARY=$(session_index_unpad "$SUMMARY")
        FIRST_PROMPT=$(session_index_unpad "$FIRST_PROMPT")
        GIT_BRANCH=$(session_index_unpad "$GIT_BRANCH")
        CREATED_AT=$(session_index_unpad "$CREATED_AT")
        MODIFIED_AT=$(session_index_unpad "$MODIFIED_AT")
        MSG_COUNT=$(session_index_unpad "$MSG_COUNT")
    fi
fi

# Fallback: first substantive user message from the transcript.
#
# The guard names FIRST_PROMPT, not SUMMARY. A predicate on one field guarding an assignment to
# another is how this blanked good data: the entry could carry a real firstPrompt and an empty
# summary, and the summary-keyed branch overwrote the firstPrompt anyway. The extra `-n` test keeps
# that true even if someone later widens the guard — the fallback may only ever ADD a value.
#
# Extraction delegates to session_index_extract_context, the one filter in this repo for
# "substantive user text". Re-implementing it locally in jq is what broke it: that copy matched
# `.type == "human"`, a type Claude Code transcripts do not emit (measured 2026-08-08: 0 `human`
# records across the newest live transcripts, 313/224/277 `user`), so it always yielded "" .
#
# Swapping the type alone would NOT have been the fix. `.message.content` is a block array on the
# large majority of user records (294/313 in one live transcript) and the first `type=="user"`
# record is usually machinery, not the human: measured over the 4 newest transcripts, a raw
# first-record read returns `[`, `<command-name>/goal</command-name>`, and `<local-command-caveat>`
# for 3 of them. That stores garbage in the search index and, being non-empty, walks straight past
# the `-n` test above — strictly worse than the empty string it replaced. The helper is what knows
# to join `type=="text"` blocks, drop `<`-leading machinery, and require ≥10 chars.
if [ -z "$FIRST_PROMPT" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Trimmed with parameter expansion rather than `… | head -1 | cut`: under this file's
    # `set -o pipefail`, a `head -1` that closes the pipe early SIGPIPEs the producer and the 141
    # propagates out of the command substitution into `set -e` (measured: a 200k-line producer
    # exits the caller 141; a one-line producer does not). The helper prints one line today, so
    # that trap is latent, not live — but expansion costs no subprocess and cannot arm it.
    transcript_first_prompt=$(session_index_extract_context "$TRANSCRIPT_PATH" 1)
    transcript_first_prompt="${transcript_first_prompt%%$'\n'*}"
    transcript_first_prompt="${transcript_first_prompt:0:500}"
    [ -n "$transcript_first_prompt" ] && FIRST_PROMPT="$transcript_first_prompt"
fi

# Defaults
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
[ -z "$CREATED_AT" ] && CREATED_AT="$NOW"
[ -z "$MODIFIED_AT" ] && MODIFIED_AT="$NOW"
[ -z "$MSG_COUNT" ] || [ "$MSG_COUNT" = "null" ] && MSG_COUNT=0

# MSG_COUNT AT THE SOURCE. The sessions-index entry is absent for almost every session now, so
# this read 0 in 11,666 of 11,670 "Indexed session" lines, and harvest-skill-end's 12-message gate
# (which read it back from the row) never opened. When the entry gives nothing, count the
# transcript's user + assistant records — the same count harvest-skill-end.sh makes. `fromjson?`
# skips a last line cut short by the session ending mid-write.
MSG_SRC=sessions-index
case "$MSG_COUNT" in ''|0|*[!0-9]*)
    MSG_SRC=none
    if [ -n "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
        _n=$(jq -Rn 'reduce (inputs | fromjson? | select(type == "object")
                             | select(.type == "user" or .type == "assistant")) as $_ (0; . + 1)' \
               < "$TRANSCRIPT_PATH" 2>/dev/null || echo "")
        case "$_n" in ''|*[!0-9]*) ;; *) MSG_COUNT="$_n"; MSG_SRC=transcript ;; esac
    fi
    case "$MSG_COUNT" in ''|*[!0-9]*) MSG_COUNT=0 ;; esac
    ;;
esac

# Extract context text from transcript (first 5 user messages)
CONTEXT_TEXT=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    CONTEXT_TEXT=$(session_index_extract_context "$TRANSCRIPT_PATH" 5)
fi

# Extract enriched data (assistant text, file paths, commands)
ASSISTANT_TEXT="" FILES_CHANGED="" COMMANDS_RUN=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    ENRICHED=$(session_index_extract_enriched "$TRANSCRIPT_PATH")
    IFS=$'\t' read -r ASSISTANT_TEXT FILES_CHANGED COMMANDS_RUN <<< "$ENRICHED"
fi

# Extract keywords
KEYWORDS=$(session_index_extract_keywords "$SUMMARY $FIRST_PROMPT $CONTEXT_TEXT")

# Upsert
session_index_upsert_with_fts \
    "$SESSION_ID" \
    "$PROJECT_PATH" \
    "$PROJECT_NAME" \
    "$SUMMARY" \
    "$FIRST_PROMPT" \
    "$GIT_BRANCH" \
    "$CREATED_AT" \
    "$MODIFIED_AT" \
    "$MSG_COUNT" \
    "" \
    "$KEYWORDS" \
    "sessions-index" \
    "$CONTEXT_TEXT" \
    "$ASSISTANT_TEXT" \
    "$FILES_CHANGED" \
    "$COMMANDS_RUN" \
    ""

session_index_log "Indexed session $SESSION_ID ($PROJECT_NAME, ${MSG_COUNT} msgs)"
_SIE_REASON=indexed
exit 0
