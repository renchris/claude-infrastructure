#!/bin/bash
# run-ab.sh <line|noline> <task-id> <rep> <account-config-dir> — ONE headless run of the gap-3 A/B:
# "does a resident instruction line naming `cc-memory-search` raise memory-pull invocation?"
#
# NOT RUN BY ITS AUTHOR. Operator-run only: it needs a real account config dir (keychain OAuth; no
# ANTHROPIC_API_KEY exists in this environment), and every run writes a transcript and session state
# under that dir and fires that account's user hooks — which the research brief forbids its workers.
#
# Derived from docs/research/token-efficiency-2026-09-23/eval/harness/f3/run-f3.sh (same frozen fixture
# clone, same sandbox-guard PreToolUse hook, no MCP, scrubbed pane env). Differences:
#   * the memory store is a frozen COPY at $RUN/mem, loaded as the project's auto-memory through
#     --settings {"autoMemoryDirectory": ...} (flagSettings is honoured: CC 2.1.278 vK() reads
#     ["policySettings","flagSettings",…,"userSettings"], /tmp/tm-research/_cc_strings.txt). All writes
#     land in the copy, never in a live store.
#   * the prototype `cc-memory-search` is on PATH in BOTH arms (CCMS_STORE=$RUN/mem, CCMS_LOG=$RUN/out/ccms.jsonl).
#   * the arms differ ONLY by one line planted in the fixture's resident rules file
#     .claude/rules/agent-operating-lessons.md, directly after its line 33 (the existing pull pointer):
#       line   → "$LINE" below
#       noline → nothing
#   * write-kind tasks delete the NEWER twin of a known duplicate pair (and its index line) from the
#     copy, so the older twin is the only prior copy of the rule.
set -u
[ $# -eq 4 ] || { echo "usage: run-ab.sh <line|noline> <task-id> <rep> <config-dir>" >&2; exit 2; }
ARM=$1; TASK=$2; REP=$3; CCD=$4
H=$(cd "$(dirname "$0")" && pwd)
F3=${F3_HARNESS:-/Users/chrisren/Development/claude-infrastructure/docs/research/token-efficiency-2026-09-23/eval/harness/f3}
G=${GATE_ROOT:-/tmp/tm-research/gap3/ab-runs}
SNAP=${SNAP:-/tmp/tokeff-f3/snap.git}
CLAUDE_BIN=${CLAUDE_BIN:-$HOME/.claude-280/node_modules/.bin/claude}
# shellcheck disable=SC2016  # the backticks are literal prompt text for the model, not an expansion
LINE='Before diagnosing any failure, and before writing a new memory or lesson file, run `cc-memory-search <3-6 symptom or topic words>` first: it ranks this project'"'"'s memory store, its cold archive and docs/lessons by relevance and prints pointer lines (falls back to grep MEMORY.md).'
case "$ARM" in line|noline) ;; *) echo "bad arm: $ARM" >&2; exit 2;; esac
ROW=$(awk -F'\t' -v t="$TASK" '$1==t' "$H/tasks.tsv")
[ -n "$ROW" ] || { echo "no task: $TASK" >&2; exit 2; }
KIND=$(printf '%s' "$ROW" | cut -f2); STORE=$(printf '%s' "$ROW" | cut -f3)
PROMPT=$(printf '%s' "$ROW" | cut -f4); REMOVE=$(printf '%s' "$ROW" | cut -f6)
case "$STORE" in
  infra) SRC=${SRC_INFRA:-/tmp/tm-research/gap3/ab/storecopy} ;;
  reso)  SRC=${SRC_RESO:-/tmp/tm-research/gap3/ab/storecopy-reso} ;;
  *) echo "bad store: $STORE" >&2; exit 2 ;;
esac
[ -d "$SRC" ] && [ -d "$SNAP" ] && [ -d "$CCD" ] || { echo "missing SRC/SNAP/CCD" >&2; exit 2; }

RUN="$G/$TASK/$ARM-r$REP"
case "$RUN" in /tmp/*|/private/tmp/*) ;; *) echo "refusing run dir $RUN" >&2; exit 2;; esac
rm -rf "${RUN:?}"; mkdir -p "$RUN/out" "$RUN/tmp" "$RUN/bin"
FX="$RUN/fx"
git clone -q --bare --local "$SNAP" "$RUN/origin.git" && git clone -q --local "$RUN/origin.git" "$FX" \
  || { echo "fixture clone failed" >&2; exit 3; }
git -C "$FX" config user.name "AB Run"; git -C "$FX" config user.email "ab@example.invalid"

# frozen store copy (read from a /tmp snapshot, never from a live store)
cp -R "$SRC" "$RUN/mem"
if [ "$KIND" = write ] && [ -n "$REMOVE" ]; then
  rm -f "$RUN/mem/$REMOVE"
  grep -vF "($REMOVE)" "$RUN/mem/MEMORY.md" > "$RUN/mem/MEMORY.md.n" && mv "$RUN/mem/MEMORY.md.n" "$RUN/mem/MEMORY.md"
fi
( cd "$RUN/mem" && find . -type f | sort | xargs shasum -a 256 ) > "$RUN/out/mem.before.sha256"

# the only arm difference
if [ "$ARM" = line ]; then
  R="$FX/.claude/rules/agent-operating-lessons.md"
  awk -v l="$LINE" '{print} NR==33{print ""; print l}' "$R" > "$R.n" && mv "$R.n" "$R"
fi
git -C "$FX" diff --stat > "$RUN/out/arm.diff"

cp "$H/cc-memory-search" "$RUN/bin/"; chmod +x "$RUN/bin/cc-memory-search"
SETTINGS=$(python3 - "$F3/sandbox-guard.sh" "$RUN" <<'PY'
import json, sys
guard, run = sys.argv[1:3]
print(json.dumps({"autoMemoryDirectory": f"{run}/mem",
  "hooks": {"PreToolUse": [{"matcher": "Bash|Edit|Write|MultiEdit|NotebookEdit",
    "hooks": [{"type": "command", "command": f"bash {guard} {run}"}]}]}}))
PY
)
printf '%s\n' "$SETTINGS" > "$RUN/out/settings.json"; printf '%s\n' "$ARM" > "$RUN/out/arm"

cd "$FX" || exit 2
START=$(date +%s)
CLAUDE_CONFIG_DIR="$CCD" TMPDIR="$RUN/tmp/" PATH="$RUN/bin:$PATH" CCMS_STORE="$RUN/mem" CCMS_LOG="$RUN/out/ccms.jsonl" \
  env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON -u KITTY_PID -u TERM_SESSION_ID \
  -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_TASK_LIST_ID \
  -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_PID -u CLAUDECODE \
  -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_EFFORT \
  -u CC_SPAWN_ROOT -u CC_SPAWN_GEN -u CC_PANE_RUNNER -u CC_ACCOUNT_PINNED \
  timeout 1500 "$CLAUDE_BIN" -p --output-format json \
  --model claude-opus-5-5 --effort high --permission-mode auto \
  --strict-mcp-config --mcp-config '{"mcpServers":{}}' --settings "$SETTINGS" \
  "$PROMPT" > "$RUN/out/result.json" 2> "$RUN/out/stderr.txt"
echo $? > "$RUN/out/rc"; echo "$START $(date +%s)" > "$RUN/out/time"
( cd "$RUN/mem" && find . -type f | sort | xargs shasum -a 256 ) > "$RUN/out/mem.after.sha256"
