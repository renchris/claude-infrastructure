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
# PER-RUN OPERATOR STORES (BACKLOG_MASTER W0 ledger-admission.1). The 09-24/25 gate set none of these,
# so every run's cc-backlog / cc-decide / cc-notify filing landed in the REAL ~/.claude stores: 73
# project=fx rows plus ~88 project=null lines. They are ALWAYS pointed into $RUN/out (a caller's value
# is overridden, never inherited), and the run refuses to start if any of them resolves inside the
# real autonomy store or mailbox. GATE_GUARD stays a separate, explicit arm: denying cc-backlog would
# change the filing behaviour T03, T07, T08 and T12 grade; a private ledger isolates without that.
export CC_BACKLOG_FILE="$RUN/out/backlog.jsonl" CC_BACKLOG_IDL="$RUN/out/idl.jsonl" \
       CC_BACKLOG_VALIDATED="$RUN/out/backlog-validated.json" CC_BACKLOG_GATE_LOG="$RUN/out/backlog-gate.jsonl" \
       CC_DECISIONS_DIR="$RUN/out/decisions" CC_IDL="$RUN/out/decide-idl.jsonl" \
       CC_MAILBOX_DIR="$RUN/out/mailbox" CC_COMMS_ALARM_DIR="$RUN/out/comms-alarm"
# _canon <path> → the path with symlinks resolved through its deepest EXISTING ancestor (creates nothing).
_canon() {
  local p="$1" tail=""
  while [ ! -d "$p" ] && [ "$p" != / ] && [ -n "$p" ]; do tail="/${p##*/}$tail"; p="${p%/*}"; [ -n "$p" ] || p=/; done
  printf '%s%s' "$(cd "$p" 2>/dev/null && pwd -P)" "$tail"
}
for _store in "$HOME/.claude/autonomy" "$HOME/.claude/mailbox"; do
  [ -d "$_store" ] || continue
  _rs="$(_canon "$_store")"
  for _p in "$CC_BACKLOG_FILE" "$CC_BACKLOG_IDL" "$CC_BACKLOG_VALIDATED" "$CC_BACKLOG_GATE_LOG" \
            "$CC_DECISIONS_DIR" "$CC_IDL" "$CC_MAILBOX_DIR" "$CC_COMMS_ALARM_DIR"; do
    case "$(_canon "$_p")" in
      "$_rs"|"$_rs"/*)
        echo "refusing to start: store override $_p resolves inside the real store $_rs" >&2; exit 2 ;;
    esac
  done
done
rm -rf "${RUN:?}"; mkdir -p "$RUN/out" "$RUN/tmp" "$CC_DECISIONS_DIR" "$CC_MAILBOX_DIR"
FX="$RUN/fx"
"$T/fixture.sh" "$FX" "$RUN/origin.git" > "$RUN/out/fixture.log" 2>&1 || { echo "fixture build failed: $TASK" >&2; exit 3; }

mkdir -p "$FX/.claude/rules"
cp "$G/arms/$ARM/CLAUDE.md" "$FX/.claude/CLAUDE.md"
cp "$G/arms/$ARM/rules/"*.md "$FX/.claude/rules/"
if [ -d "$FX/.git" ]; then
  mkdir -p "$FX/.git/info"
  grep -qxF '.claude/' "$FX/.git/info/exclude" 2>/dev/null || echo '.claude/' >> "$FX/.git/info/exclude"
fi

# The account's and ~/.claude's own memory files, built from what is on disk now (gate-excludes.py):
# a hard-coded list missed ~/.claude/rules/10-session-close.md, which then loaded into both arms.
SETTINGS=$(python3 -B "$H/gate-excludes.py" "$CCD") || { echo "gate-excludes.py failed for $CCD" >&2; exit 2; }
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
