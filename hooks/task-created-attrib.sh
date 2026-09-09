#!/bin/bash
# task-created-attrib.sh — TaskCreated → write the creator's session id beside the task.
#
# WHY THIS EXISTS. A task file carries no creator. `TaskCreate`'s body sets `owner: void 0`
# (binary 2.1.260 @164041206) and `owner` is the Agent-Teams ASSIGNEE (`lead`, `channels-s4`),
# never the session that opened the item. Measured 2026-09-08: 10 of 293 open items (3.4%) carry
# `metadata.owner_session`, and all ten were written BY HAND through Bash. The model CAN
# self-attribute — `TaskCreate` accepts a `metadata` argument — but that channel is discretionary
# and FAILS OPEN: an unattributed task is invisible to any session-scoped reader, i.e. the
# mechanism goes silent in exactly the state it exists to catch.
#
# The deterministic channel is this event. The `TaskCreated` payload carries `session_id` AND
# `task_id` in one object (schema @157890649) — the join no field on disk provides. We write it to
# a sidecar we own, never into the task JSON the binary owns.
#
#   $CLAUDE_CONFIG_DIR/tasks/<listId>/.owners/<taskId>   →  "<session_id>\t<iso ts>\t<cwd>"
#
# 🚨 EXIT 0 UNCONDITIONALLY, AND EMIT NOTHING ON STDOUT. `TaskCreated` is one of the four events
# that get ` hook feedback:\n` treatment (`ovn=["Stop","TeammateIdle","TaskCreated","TaskCompleted"]`
# @157431448), and `TaskCreate`'s own body does `if(D.length>0) throw await p9t(xE(),C,…)` — a
# BLOCKING TaskCreated hook DELETES the task it just created and throws. So every failure mode in
# this file is a silent no-op: no `set -e`, every write `|| true`, the exit status a literal 0.
# Losing a sidecar costs one unattributed task; a non-zero exit costs the operator's task.
#
# THE SIDECAR IS SAFE FROM THE BINARY AND FROM OUR OWN HELPERS (checked, not assumed): the list
# reader `aC` filters `u.endsWith(".json")`, the reset path `yXn` filters `!f.startsWith(".")`, and
# `hooks/lib/task-helpers.sh` globs `[0-9]*.json` / `*.json`. A `.owners/` directory is invisible to
# all four.
#
# LIST-ID RESOLUTION MIRRORS THE BINARY'S `xE()` — env var, then team name, then session id — but it
# is VERIFIED rather than trusted: the task file was created microseconds ago, so the right list is
# the candidate that actually holds `<taskId>.json`. Three stats, and a wrong guess self-corrects
# instead of writing a sidecar into a directory nobody will read.
#
# Env seams (tests): CLAUDE_CONFIG_DIR · CLAUDE_CODE_TASK_LIST_ID · TASK_ATTRIB_TASKS_DIR
set -uo pipefail

TASKS_DIR="${TASK_ATTRIB_TASKS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/tasks}"

# jq absent ⇒ no-op. Fail-open is the only posture available on a blocking event.
command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD="$(cat 2>/dev/null)" || PAYLOAD=""
[ -n "$PAYLOAD" ] || exit 0

# One jq pass; a malformed payload exits non-zero here and we stop, having written nothing.
#
# `@sh` + `eval`, NOT `@tsv` piped into a tab-split `read`. Tab is IFS WHITESPACE, so a reader
# splitting on it strips leading empty cells and collapses runs of them: a payload with no
# `session_id` — exactly the malformed case this hook must survive — delivered `task_id` into `$SID`
# and `cwd` into `$TASK_ID`, and the hook then wrote a sidecar naming a session that does not exist.
# Measured by case 5 of tests/task-created-attrib.bats, which was red on the tab-split form (memory:
# ifs-whitespace-collapses-empty-fields; the class ratchet is scripts/tsv-pad-lint.sh, and this
# comment deliberately carries no contiguous copy of that spelling, exactly as the lint's own source
# does at :98-108 — a detector that matches prose about a surface reports the explanation as the
# breach). `@sh` quotes every field including the empty ones, so the arity is positional and fixed,
# and jq's own escaping is what makes the eval safe.
FIELDS="$(printf '%s' "$PAYLOAD" | jq -r '
  [ (.session_id // ""), (.task_id // ""), (.cwd // ""), (.team_name // "") ] | @sh
' 2>/dev/null)" || exit 0
[ -n "$FIELDS" ] || exit 0

eval "set -- $FIELDS" 2>/dev/null || exit 0
SID="${1:-}"; TASK_ID="${2:-}"; CWD="${3:-}"; TEAM="${4:-}"

# Both halves of the join must be present. Either missing ⇒ nothing worth writing.
[ -n "${SID:-}" ] && [ -n "${TASK_ID:-}" ] || exit 0

# `HE(e)=e.replace(/[^a-zA-Z0-9_-]/g,"-")` — the binary sanitizes BOTH the list id and the task id
# before joining them into a path, so a sidecar named any other way could never be matched back.
_sanitize() { printf '%s' "$1" | sed 's/[^a-zA-Z0-9_-]/-/g'; }

TASK_FILE="$(_sanitize "$TASK_ID")"
[ -n "$TASK_FILE" ] || exit 0

LIST=""
for cand in "${CLAUDE_CODE_TASK_LIST_ID:-}" "${TEAM:-}" "$SID"; do
  [ -n "$cand" ] || continue
  s="$(_sanitize "$cand")"
  [ -n "$s" ] || continue
  [ -n "$LIST" ] || LIST="$s"            # first non-empty candidate = the fallback
  if [ -f "$TASKS_DIR/$s/$TASK_FILE.json" ]; then LIST="$s"; break; fi
done
[ -n "$LIST" ] || exit 0

OWNERS="$TASKS_DIR/$LIST/.owners"
mkdir -p "$OWNERS" 2>/dev/null || exit 0

# PAD AT THE EMITTER (scripts/tsv-pad-lint.sh's rule, applied to our own producer). This row is
# read back by tab-splitting, so an empty NON-LAST cell would not read back empty — it would shift
# every later column left, silently. Cell 1 is structurally non-empty (the guard above returns
# unless `$SID` is set) and cell 3 is last, so the timestamp is the only cell that can be blank:
# `date` is not on the critical path of anything and this hook must not fail, so it gets a
# placeholder rather than an exit.
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || TS=""
[ -n "$TS" ] || TS="-"
printf '%s\t%s\t%s\n' "$SID" "$TS" "${CWD:-}" > "$OWNERS/$TASK_FILE" 2>/dev/null || true

exit 0
