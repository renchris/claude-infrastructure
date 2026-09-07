#!/bin/bash
# instructions-loaded.sh — InstructionsLoaded observer: one greppable line per memory file a
# session actually LOADED. Nothing else we own reports this; today it is inferred, never observed.
#
# WHAT THE HARNESS SENDS (measured 2026-09-05 on 2.1.114 AND 2.1.220, 16 rows across
# /tmp/hs/log/{census,census114,display-run*}.tsv, and confirmed against the binary's own hook
# metadata registry, which is the authority for the fields the probe never exercised):
#   {session_id, transcript_path, cwd, hook_event_name:"InstructionsLoaded",
#    file_path, memory_type, load_reason}
#   + optional: globs (the `paths:` frontmatter patterns that matched),
#               trigger_file_path (the file Claude touched that caused the load),
#               parent_file_path (the file that @-included this one)
# `memory_type` ∈ {User, Project, Local, Managed}. Note there is NO `prompt_id` at session_start —
# no prompt exists yet — so a reader must not key on it.
#
# The binary states the contract for this event in one line: "This hook is observability-only and
# does not support blocking." So there is no decision to make here and no output to return; the
# only correct behaviour is to record and exit 0.
#
# ══ THE MATCHER, CHOSEN DELIBERATELY ══════════════════════════════════════════════════════════
#
# This event's `matcher` is NOT a tool name. The binary's metadata says so explicitly:
#
#     matcherMetadata:{fieldToMatch:"load_reason",
#                      values:["session_start","nested_traversal","path_glob_match","include","compact"]}
#
# The matcher therefore SELECTS WHICH LOADS YOU OBSERVE. It is not inert, and a wrong one does not
# fail loudly — it just points the log at a different population.
#
# 🚨 THE PLAN'S LIST OF THESE FIVE VALUES IS WRONG, and this is the corrected one. HOOK_SURFACE_100P
# § 3 (the `InstructionsLoaded consider → WIRE` note) gives them as `session_start`,
# `nested_traversal`, `at_mention`, `skill_load`, `slash_command`. Three of those five do not appear
# in the event's matcherMetadata at all; the real remaining three are `path_glob_match`, `include`
# and `compact`. Read off the binary's own contiguous metadata literal, which is a bounded
# instrument — the array's brackets end it, so a sixth value would be visible. Recorded in § 2 of
# the plan rather than corrected in place, because § 3's ledger rows are not this wave's to edit.
#
# RECOMMENDED MATCHER: `session_start`. It is the one that answers the question this event was
# adopted to answer — which memory files a session loaded — and it is BOUNDED at 2–4 rows per
# session (all 16 measured rows are `session_start`, 2 on a bare /tmp cwd, 4 in a repo with both a
# project CLAUDE.md and a .claude/CLAUDE.md).
#
# Why each of the other four is rejected, since "not chosen" is not a reason:
#   · path_glob_match — fires when Claude TOUCHES a file matching a rule's `paths:` frontmatter.
#     That is per-tool-call and unbounded within a session, so it is the value that drowns the
#     signal the plan warns about. It also answers a different question (which rule a file touch
#     pulled in), not the session's load census.
#   · nested_traversal — the walk into subdirectory CLAUDE.md files. Real, and part of the same
#     census, but its volume tracks tree depth rather than the session, so folding it in makes the
#     count uninterpretable without also recording the tree.
#   · include    — @-include expansion. Its parent is already derivable from `parent_file_path` on
#     the row that included it, so it is redundant against a `session_start` census plus the file.
#   · compact    — the post-compaction reload. Fleet-measured, compaction is rare and always manual
#     (CLAUDE.md § Context Stewardship: 39/39 manual, 0 auto), so a matcher here observes almost
#     nothing and cannot carry the census.
#
# ⚠️ ONE MATCHER = ONE REASON. Dispatch buckets registrations by the exact `load_reason` value, so
# a `session_start` registration sees session_start loads and nothing else. Any per-session rate
# derived from this log is therefore a FLOOR over one reason, never a rate over all loads. This
# script records `load_reason` on every row precisely so that a later registration on a second
# value stays distinguishable in the same log instead of silently contaminating the first.
#
# FAILS OPEN, ALWAYS. Missing args, empty stdin, malformed JSON, an unwritable log — every path
# exits 0 with nothing on stdout.

set -u

LOG_DIR="${CC_INSTRUCTIONS_LOG_DIR:-$HOME/.claude/logs}"
LOG="$LOG_DIR/instructions-loaded.log"

# Builtin read, not `$(cat)` — no fork, no exec. See hooks/log-bash.sh for the measurement.
IFS= read -r -d '' INPUT || true
while [ "${INPUT%$'\n'}" != "${INPUT}" ]; do INPUT="${INPUT%$'\n'}"; done

[ -n "$INPUT" ] || exit 0

# `-e` so malformed JSON is detected rather than yielding a row of empty fields. `// "-"` on the
# optionals, never `// ""`: an absent trigger_file_path and an empty one must stay distinguishable
# in the log.
#
# 🚨 `@sh` + `eval`, NOT `@tsv` + `read`. A tab IS an IFS whitespace character, so `read` collapses
# runs of it and strips leading ones — an absent `file_path` makes the leading field vanish and
# shifts every later field LEFT, so the guard below would read `memory_type` as the filename and
# log a row naming a file called "User". Measured on the sibling hooks/file-changed.sh, which had
# exactly this defect until its suite's no-file_path arm caught it (memory:
# ifs-whitespace-collapses-empty-fields). `@sh` emits properly quoted assignments instead.
FIELDS=$(printf '%s' "$INPUT" | jq -er '@sh "FILE_PATH=\(.file_path // "") MEM_TYPE=\(.memory_type // "-") LOAD_REASON=\(.load_reason // "-") SID=\(.session_id // "-") TRIGGER=\(.trigger_file_path // "-") PARENT=\(.parent_file_path // "-")"' 2>/dev/null) || exit 0
eval "$FIELDS"

[ -n "${FILE_PATH:-}" ] || exit 0
[ -n "${MEM_TYPE:-}" ] || MEM_TYPE="-"
[ -n "${LOAD_REASON:-}" ] || LOAD_REASON="-"
[ -n "${SID:-}" ] || SID="-"
[ -n "${TRIGGER:-}" ] || TRIGGER="-"
[ -n "${PARENT:-}" ] || PARENT="-"

TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

if mkdir -p "$LOG_DIR" 2>/dev/null; then
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$TS" "$SID" "$LOAD_REASON" "$MEM_TYPE" "$FILE_PATH" "$TRIGGER" "$PARENT" >> "$LOG" 2>/dev/null || true
fi

exit 0
