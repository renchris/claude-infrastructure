#!/bin/bash
# r2-exp.sh <arm base|sys> <rep> <config-dir> — rank 2 workaround experiment (wave 2, item 5).
# One headless main session in a scratch repo spawns three general-purpose subagents in parallel.
#   base  memory files load the normal way: in the FIRST USER MESSAGE, after the only cache breakpoint
#         on the system block, so every new context (main or subagent) re-writes them.
#   sys   the same memory files are excluded (claudeMdExcludes) and appended to the SYSTEM prompt
#         instead: --append-system-prompt-file for the main, and CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT=1
#         + --append-subagent-system-prompt-file for subagents, so they sit before the breakpoint.
# The memory text is byte-identical across arms (MEMFILE, built once per rep from the live files).
# Outcome, read from the transcripts by r2-agg.py: cache_read / cache_creation of each context's first
# request, and the whole tree's cost via cc-token-ledger --task.
set -u
[ $# -eq 3 ] || { echo "usage: r2-exp.sh <base|sys> <rep> <config-dir>" >&2; exit 2; }
ARM=$1; REP=$2; CCD=$3
G=${R2_ROOT:-/private/tmp/tokeff-w2/r2exp}
CLAUDE_BIN=${CLAUDE_BIN:-$HOME/.claude-280/node_modules/.bin/claude}
RUN="$G/runs/wf-$ARM-r$REP"
rm -rf "$RUN"; mkdir -p "$RUN/tmp"
REPO="$G/repo"   # shared by every run on purpose: same cwd, same system block
if [ ! -d "$REPO/.git" ]; then
  mkdir -p "$REPO"; git -C "$REPO" init -q -b main; seq 1 37 > "$REPO/data.txt"; seq 1 11 > "$REPO/small.txt"
  git -C "$REPO" add -A; git -C "$REPO" -c user.name=x -c user.email=x@example.invalid commit -q -m init
fi
MEMS=("$HOME/.claude/CLAUDE.md" "$HOME/.claude/rules/00-mission-board.md" "$HOME/.claude/rules/agent-operating-lessons.md")
MEMFILE="$RUN/memory.md"
for f in "${MEMS[@]}"; do [ -f "$f" ] && printf 'Contents of %s (user instructions for all projects):\n\n%s\n\n' "$f" "$(cat "$f")"; done > "$MEMFILE"
# Workflow variant: three default-type workflow agent() slots with different briefs.
PROMPT="Call the Workflow tool once with exactly this script and nothing else, then reply with its returned value only: export const meta = {name: 'r2-probe', description: 'three read-only slots'}; const r = await parallel([() => agent('Run wc -l on data.txt in the current directory and reply with the number only.'), () => agent('Run wc -l on small.txt in the current directory and reply with the number only.'), () => agent('Run head -1 data.txt in the current directory and reply with that line only.')]); return r"
cd "$REPO" || exit 2
EXTRA=()
if [ "$ARM" = sys ]; then
  EXCL=$(python3 -c 'import json,sys; print(json.dumps({"claudeMdExcludes": sys.argv[1:]}))' "$CCD/CLAUDE.md" "${MEMS[@]}")
  EXTRA=(--settings "$EXCL" --append-system-prompt-file "$MEMFILE" --append-subagent-system-prompt-file "$MEMFILE")
  export CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT=1
fi
START=$(date +%s)
CLAUDE_CONFIG_DIR="$CCD" TMPDIR="$RUN/tmp/" env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
  -u CLAUDE_CODE_TASK_LIST_ID timeout 900 "$CLAUDE_BIN" -p --output-format json \
  --model claude-opus-5-5 --effort high --permission-mode auto ${EXTRA[@]+"${EXTRA[@]}"} "$PROMPT" \
  > "$RUN/result.json" 2> "$RUN/stderr.txt"
echo "$? $START $(date +%s)" > "$RUN/rc"
