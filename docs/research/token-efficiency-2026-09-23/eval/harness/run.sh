#!/bin/bash
# run.sh <arm full|slim> <task-id> <rep> <account-config-dir>
# One headless F1 run. Builds a fresh fixture (with its own bare origin) under
# $GATE_ROOT/runs/<task>/r<rep>, loads the arm's instruction files as PROJECT memory,
# excludes the account's user memory files, gives the run a private TMPDIR, and
# records result.json / stderr / rc / time. The two arms differ only in memory content.
set -u
[ $# -eq 4 ] || { echo "usage: run.sh <full|slim> <task-id> <rep> <config-dir>" >&2; exit 2; }
ARM=$1; TASK=$2; REP=$3; CCD=$4
H=$(cd "$(dirname "$0")" && pwd)
G=${GATE_ROOT:-/tmp/tokeff-gate}
CLAUDE_BIN=${CLAUDE_BIN:-$HOME/.claude-280/node_modules/.bin/claude}
# full|slim are the gate's arms; any other name must be a probe arm already built under $G/arms.
case "$ARM" in full|slim) ;; *[!a-z0-9-]*|'') echo "bad arm: $ARM" >&2; exit 2;; *) [ -d "$G/arms/$ARM" ] || { echo "bad arm: $ARM" >&2; exit 2; };; esac
# GATE_TASKS: a tasks dir other than harness/tasks (F4 uses one holding T01-T20 plus its T21).
T="${GATE_TASKS:-$H/tasks}/$TASK"
[ -f "$T/prompt.txt" ] && [ -x "$T/fixture.sh" ] || { echo "no task: $TASK" >&2; exit 2; }
[ -d "$CCD" ] || { echo "no config dir: $CCD" >&2; exit 2; }
[ -f "$G/arms/$ARM/CLAUDE.md" ] || { echo "arm files missing: $G/arms/$ARM (run build-arms.sh)" >&2; exit 2; }

RUN="$G/runs/$TASK/r$REP"
case "$RUN" in "$G"/runs/*/r*) ;; *) echo "refusing run dir $RUN" >&2; exit 2;; esac
rm -rf "${RUN:?}"; mkdir -p "$RUN/out" "$RUN/tmp"
FX="$RUN/fx"
"$T/fixture.sh" "$FX" "$RUN/origin.git" > "$RUN/out/fixture.log" 2>&1 || { echo "fixture build failed: $TASK" >&2; exit 3; }

mkdir -p "$FX/.claude/rules"
cp "$G/arms/$ARM/CLAUDE.md" "$FX/.claude/CLAUDE.md"
cp "$G/arms/$ARM/rules/"*.md "$FX/.claude/rules/"
if [ -d "$FX/.git" ]; then
  mkdir -p "$FX/.git/info"
  grep -qxF '.claude/' "$FX/.git/info/exclude" 2>/dev/null || echo '.claude/' >> "$FX/.git/info/exclude"
fi

SETTINGS=$(python3 -c 'import json,sys; print(json.dumps({"claudeMdExcludes": sys.argv[1:]}))' \
  "$CCD/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "$HOME/.claude/rules/00-mission-board.md" \
  "$HOME/.claude/rules/agent-operating-lessons.md")
# Rank 2's setup-breakpoint workaround (wave 3): an arm dir holding a SYSPROMPT marker keeps the same
# files in the fixture but excludes them as memory and appends their text, framed as the memory loader
# frames it, to the SYSTEM prompt (main and subagents), so it sits before the system cache breakpoint.
# Without the marker nothing below changes, which reproduces every earlier F1 round.
SYS=()
if [ -f "$G/arms/$ARM/SYSPROMPT" ]; then
  MEMFILE="$RUN/out/memory.md"
  for f in "$FX/.claude/CLAUDE.md" "$FX/.claude/rules/"*.md; do
    printf 'Contents of %s (project instructions, checked into the codebase):\n\n%s\n\n' "$f" "$(cat "$f")"
  done > "$MEMFILE"
  SETTINGS=$(python3 -c 'import json,sys; s=json.loads(sys.argv[1]); s["claudeMdExcludes"]+=sys.argv[2:]; print(json.dumps(s))' \
    "$SETTINGS" '**/.claude/CLAUDE.md' '**/.claude/rules/*.md')
  SYS=(--append-system-prompt-file "$MEMFILE" --append-subagent-system-prompt-file "$MEMFILE")
  export CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT=1
fi
# GATE_GUARD=<hook script>: add f3/sandbox-guard.sh as a PreToolUse hook (both arms alike), so a run
# cannot mutate the real mission board or operator stores. GATE_NO_MCP=1: start no MCP servers, so a
# run cannot create a real mail draft. Both default off, which reproduces the F1 rounds.
if [ -n "${GATE_GUARD:-}" ]; then
  SETTINGS=$(python3 -c 'import json,sys; s=json.loads(sys.argv[1]); s["hooks"]={"PreToolUse":[{"matcher":"Bash|Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"bash "+sys.argv[2]+" "+sys.argv[3]}]}]}; print(json.dumps(s))' \
    "$SETTINGS" "$GATE_GUARD" "$RUN")
fi
MCP=()
# (--mcp-config is variadic: these go BEFORE --settings, or it swallows the prompt as a config path.)
[ "${GATE_NO_MCP:-0}" = 1 ] && MCP=(--strict-mcp-config --mcp-config '{"mcpServers":{}}')
printf '%s\n' "$ARM" > "$RUN/out/arm"
printf '%s\n' "$CCD" > "$RUN/out/config_dir"
touch "$RUN/out/start.stamp"

cd "$FX" || exit 2
# The 2026-09-24 gate ran with the DRIVER's environment inherited, including the launching pane's
# identity (ITERM_SESSION_ID, KITTY_WINDOW_ID, CLAUDE_CODE_MESSAGING_SOCKET, the task-list id), so hooks
# treated every run as that pane (5 of the first ~65 runs armed an inbox watcher keyed to it). Both arms
# saw the same environment. GATE_SCRUB_PANE_ENV=1 drops those variables for a cleaner re-run; the
# default reproduces the conditions the recorded gate ran under.
SCRUB=()
if [ "${GATE_SCRUB_PANE_ENV:-0}" = 1 ]; then
  SCRUB=(env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u TERM_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET
         -u CLAUDE_CODE_TASK_LIST_ID -u CC_SPAWN_ROOT -u CC_SPAWN_GEN -u CC_PANE_RUNNER)
fi
START=$(date +%s)
CLAUDE_CONFIG_DIR="$CCD" TMPDIR="$RUN/tmp/" ${SCRUB[@]+"${SCRUB[@]}"} timeout 1500 "$CLAUDE_BIN" -p --output-format json \
  --model claude-opus-5-5 --effort high --permission-mode auto ${MCP[@]+"${MCP[@]}"} ${SYS[@]+"${SYS[@]}"} --settings "$SETTINGS" \
  "$(cat "$T/prompt.txt")" > "$RUN/out/result.json" 2> "$RUN/out/stderr.txt"
RC=$?
END=$(date +%s)
echo "$RC" > "$RUN/out/rc"
echo "$START $END" > "$RUN/out/time"

# /tmp literal-path leak sweep (T3 lesson): files this task's runs write straight to /tmp
# are moved into the run dir so the next rep cannot find them. Only files newer than the
# run's start AND matching this task's own pattern are touched.
if [ -f "$T/leak-pattern" ]; then
  mkdir -p "$RUN/out/tmp-leaked"
  find /tmp/ -maxdepth 1 -type f -newer "$RUN/out/start.stamp" 2>/dev/null | while IFS= read -r f; do
    grep -qE -f "$T/leak-pattern" "$f" 2>/dev/null && mv "$f" "$RUN/out/tmp-leaked/"
  done
fi
exit "$RC"
