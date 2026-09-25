#!/bin/bash
# r12-run.sh <arm on|off> <task-id> <rep> <config-dir> — one run of the rank-12 gate (wave 2, item 6).
# Same fixture discipline, arm files (`full`: live CLAUDE.md, mission board, lessons as project memory)
# and claude invocation as the F1 gate's run.sh. The arms differ ONLY in whether --settings also
# registers hooks/bash-output-offload.sh as a PostToolUse(Bash) hook. Afterwards the task's own
# verify.sh checks the outcome from the repo state and the final answer, and the offloads the hook
# made are counted from its private output dir.
set -u
[ $# -eq 4 ] || { echo "usage: r12-run.sh <on|off> <task-id> <rep> <config-dir>" >&2; exit 2; }
ARM=$1; TASK=$2; REP=$3; CCD=$4
H=$(cd "$(dirname "$0")" && pwd)
G=${R12_ROOT:-/private/tmp/tokeff-r12gate}
ARMS=${R12_ARMS:-/private/tmp/tokeff-dodprobe/arms}
HOOK=${R12_HOOK:-$H/../../../../../../hooks/bash-output-offload.sh}
CLAUDE_BIN=${CLAUDE_BIN:-$HOME/.claude-280/node_modules/.bin/claude}
case "$ARM" in on|off) ;; *) echo "bad arm: $ARM" >&2; exit 2 ;; esac
T="$H/r12tasks/$TASK"
[ -f "$T/prompt.txt" ] && [ -x "$T/fixture.sh" ] && [ -x "$T/verify.sh" ] || { echo "no task: $TASK" >&2; exit 2; }
[ -f "$ARMS/full/CLAUDE.md" ] || { echo "arm files missing under $ARMS/full" >&2; exit 2; }
[ -f "$HOOK" ] || { echo "hook missing: $HOOK" >&2; exit 2; }
RUN="$G/runs/$TASK/r$REP"
case "$RUN" in "$G"/runs/*/r*) ;; *) echo "refusing run dir $RUN" >&2; exit 2 ;; esac
rm -rf "${RUN:?}"; mkdir -p "$RUN/out" "$RUN/tmp" "$RUN/offload"
FX="$RUN/fx"
"$T/fixture.sh" "$FX" "$RUN/origin.git" > "$RUN/out/fixture.log" 2>&1 || { echo "fixture build failed: $TASK" >&2; exit 3; }
mkdir -p "$FX/.claude/rules" "$FX/.git/info"
cp "$ARMS/full/CLAUDE.md" "$FX/.claude/CLAUDE.md"
cp "$ARMS/full/rules/"*.md "$FX/.claude/rules/"
echo '.claude/' >> "$FX/.git/info/exclude"
SETTINGS=$(python3 -c '
import json, sys
arm, hook, excl = sys.argv[1], sys.argv[2], sys.argv[3:]
s = {"claudeMdExcludes": excl}
if arm == "on":
    s["hooks"] = {"PostToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash " + hook}]}]}
print(json.dumps(s))' "$ARM" "$HOOK" "$CCD/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "$HOME/.claude/rules/00-mission-board.md" \
  "$HOME/.claude/rules/agent-operating-lessons.md")
printf '%s\n' "$ARM" > "$RUN/out/arm"; printf '%s\n' "$CCD" > "$RUN/out/config_dir"
cd "$FX" || exit 2
START=$(date +%s)
CLAUDE_CONFIG_DIR="$CCD" TMPDIR="$RUN/tmp/" CC_BASH_OFFLOAD_DIR="$RUN/offload" \
  env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u TERM_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
  -u CLAUDE_CODE_TASK_LIST_ID -u CC_SPAWN_ROOT -u CC_SPAWN_GEN -u CC_PANE_RUNNER \
  timeout 1200 "$CLAUDE_BIN" -p --output-format json --model claude-opus-5-5 --effort high \
  --permission-mode auto --settings "$SETTINGS" "$(cat "$T/prompt.txt")" > "$RUN/out/result.json" 2> "$RUN/out/stderr.txt"
echo "$? $START $(date +%s)" > "$RUN/out/rc"
jq -r '.result // ""' "$RUN/out/result.json" > "$RUN/out/answer.txt" 2>/dev/null
( cd "$FX" && ORIGIN="$RUN/origin.git" bash "$T/verify.sh" "$RUN/out/answer.txt" ) > "$RUN/out/verify.txt" 2>&1
find "$RUN/offload" -type f | wc -l | tr -d ' ' > "$RUN/out/offloads"
printf '%s %s r%s %s offloads=%s\n' "$TASK" "$ARM" "$REP" "$(tail -1 "$RUN/out/verify.txt")" "$(cat "$RUN/out/offloads")"
