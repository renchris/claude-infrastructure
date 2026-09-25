#!/bin/bash
# r15-probe.sh <arm without|with> <rep> <config-dir> — rank 15 mechanism probe (wave 2, item 4).
# A headless main session delegates one brief to a subagent defined inline with --agents. The two
# arms differ ONLY in whether the subagent's prompt carries the "background long commands, wait in
# <=270 s slices" lines that agents/*.md now ship. The brief runs a benchmark that takes ~7 minutes,
# the shape behind 92% of agent cache misses after a 5-60 min gap (docs/research/.../eval/r15/).
# Outcome, read from the SUBAGENT transcript by r15-agg.py: gaps > 300 s between its API requests
# (each one a 5-minute-TTL cache rewrite), request count, and whether it reported the right result.
set -u
[ $# -eq 3 ] || { echo "usage: r15-probe.sh <without|with> <rep> <config-dir>" >&2; exit 2; }
ARM=$1; REP=$2; CCD=$3
H=$(cd "$(dirname "$0")" && pwd)
G=${R15_ROOT:-/private/tmp/tokeff-w2/r15probe}
CLAUDE_BIN=${CLAUDE_BIN:-$HOME/.claude-280/node_modules/.bin/claude}
RUN="$G/runs/$ARM-r$REP"
rm -rf "$RUN"; mkdir -p "$RUN/work" "$RUN/tmp"
N=$(( (REP * 7919 + ${#ARM} * 104729) % 100000 ))
# shellcheck disable=SC2016  # the $(seq …) and $i are bench.sh's own, written literally
printf '#!/bin/bash\n# bench.sh — a slow benchmark: ~7 minutes, then one RESULT line.\nfor i in $(seq 1 42); do sleep 10; echo "step $i/42"; done\necho "RESULT=%s"\n' "$N" > "$RUN/work/bench.sh"
chmod +x "$RUN/work/bench.sh"
printf '%s\n' "$N" > "$RUN/expected"

BASE='You are a worker agent. The delegation prompt is your whole brief. Do exactly what it asks and return the answer it asks for.'
LINES=$(sed -n '/^Tool behaviour:/,/^$/p' "$H/../../../../../agents/workflow-lean.md")
case "$ARM" in
  without) PROMPT="$BASE" ;;
  with) PROMPT="$BASE

$LINES" ;;
  *) echo "bad arm: $ARM" >&2; exit 2 ;;
esac
[ "$ARM" = without ] || [ -n "$LINES" ] || { echo "no Tool behaviour block found in agents/workflow-lean.md" >&2; exit 2; }
AGENTS=$(python3 -c 'import json,sys; print(json.dumps({"bench-worker": {"description": "Runs a benchmark and reports its result", "prompt": sys.argv[1], "tools": ["Bash", "Read"]}}))' "$PROMPT")
printf '%s\n' "$PROMPT" > "$RUN/agent-prompt.txt"

cd "$RUN/work" || exit 2
START=$(date +%s)
CLAUDE_CONFIG_DIR="$CCD" TMPDIR="$RUN/tmp/" env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
  -u CLAUDE_CODE_TASK_LIST_ID timeout 1800 "$CLAUDE_BIN" -p --output-format json \
  --model claude-opus-5-5 --effort high --permission-mode auto --agents "$AGENTS" \
  "Use the Agent tool with subagent_type \"bench-worker\" and exactly this brief: \"Run ./bench.sh in $RUN/work (a benchmark that takes about 7 minutes) and report the number on its RESULT= line.\" Then reply with only the number the worker reported." \
  > "$RUN/result.json" 2> "$RUN/stderr.txt"
echo "$? $START $(date +%s)" > "$RUN/rc"
