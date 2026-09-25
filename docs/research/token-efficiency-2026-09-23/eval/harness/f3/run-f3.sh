#!/bin/bash
# run-f3.sh <exclude|control> <task-id> <rep> <account-config-dir> — one headless F3 run.
#
# The fixture is a fresh clone of claude-infrastructure at ONE frozen sha ($GATE_ROOT/snap.git, sha in
# $GATE_ROOT/FROZEN_SHA) with its own private bare origin, plus the task's planted commit (script +
# bats test, or nothing). The session runs IN the clone, so the repo's own .claude/CLAUDE.md and
# .claude/rules/*.md load as project memory, and the account's user memory loads too (it is not
# excluded: that is the realistic setting). The two arms differ ONLY in --settings:
#   exclude  {"claudeMdExcludes": ["**/.claude/rules/agent-operating-lessons-situational.md"], <guard>}
#   control  {<guard>}
# where <guard> is the same sandbox-guard.sh PreToolUse hook in both arms (it keeps the run off the
# shared checkout, the live layer and the operator's stores). Private TMPDIR; pane and session
# identity scrubbed from the environment; no MCP servers (--strict-mcp-config with an empty set), so a
# run cannot create a real mail draft for a board row.
set -u
[ $# -eq 4 ] || { echo "usage: run-f3.sh <exclude|control> <task-id> <rep> <config-dir>" >&2; exit 2; }
ARM=$1; TASK=$2; REP=$3; CCD=$4
H=$(cd "$(dirname "$0")" && pwd)
G=${GATE_ROOT:-/tmp/tokeff-f3}
CLAUDE_BIN=${CLAUDE_BIN:-$HOME/.claude-280/node_modules/.bin/claude}
GLOB='**/.claude/rules/agent-operating-lessons-situational.md'
case "$ARM" in exclude|control) ;; *) echo "bad arm: $ARM" >&2; exit 2;; esac
T="$H/tasks/$TASK"
[ -f "$T/prompt.txt" ] || { echo "no task: $TASK" >&2; exit 2; }
[ -d "$CCD" ] || { echo "no config dir: $CCD" >&2; exit 2; }
[ -d "$G/snap.git" ] || { echo "no snapshot: $G/snap.git" >&2; exit 2; }

RUN="$G/runs/$TASK/r$REP"
case "$RUN" in "$G"/runs/*/r*) ;; *) echo "refusing run dir $RUN" >&2; exit 2;; esac
rm -rf "${RUN:?}"; mkdir -p "$RUN/out" "$RUN/tmp"
FX="$RUN/fx"
{
  git clone -q --bare --local "$G/snap.git" "$RUN/origin.git" &&
  git clone -q --local "$RUN/origin.git" "$FX" &&
  git -C "$FX" config user.name "Chris Ren" &&
  git -C "$FX" config user.email "dev@example.invalid"
} > "$RUN/out/fixture.log" 2>&1 || { echo "fixture clone failed: $TASK" >&2; exit 3; }
if [ -d "$T/files" ]; then
  ( cd "$T/files" && find . -type f -name '*.plant' ) | while IFS= read -r f; do
    dst="$FX/${f#./}"; dst=${dst%.plant}
    mkdir -p "$(dirname "$dst")"; cp "$T/files/${f#./}" "$dst"
    case "$dst" in "$FX"/scripts/*) chmod +x "$dst" ;; esac
  done
  GIT_AUTHOR_DATE="2026-09-24T15:00:00Z" GIT_COMMITTER_DATE="2026-09-24T15:00:00Z" \
    git -C "$FX" add -A >> "$RUN/out/fixture.log" 2>&1 &&
  GIT_AUTHOR_DATE="2026-09-24T15:00:00Z" GIT_COMMITTER_DATE="2026-09-24T15:00:00Z" \
    git -C "$FX" commit -q -F "$T/commit-msg.txt" >> "$RUN/out/fixture.log" 2>&1 &&
  git -C "$FX" push -q origin main >> "$RUN/out/fixture.log" 2>&1 || { echo "plant failed: $TASK" >&2; exit 3; }
fi
git -C "$FX" rev-parse HEAD > "$RUN/out/plant.sha"

SETTINGS=$(python3 - "$ARM" "$GLOB" "$H/sandbox-guard.sh" "$RUN" <<'PY'
import json, sys
arm, glob, guard, run = sys.argv[1:5]
s = {"hooks": {"PreToolUse": [{"matcher": "Bash|Edit|Write|MultiEdit|NotebookEdit",
     "hooks": [{"type": "command", "command": f"bash {guard} {run}"}]}]}}
if arm == "exclude":
    s = {"claudeMdExcludes": [glob], **s}
print(json.dumps(s))
PY
)
printf '%s\n' "$SETTINGS" > "$RUN/out/settings.json"
printf '%s\n' "$ARM" > "$RUN/out/arm"
printf '%s\n' "$CCD" > "$RUN/out/config_dir"
touch "$RUN/out/start.stamp"

cd "$FX" || exit 2
START=$(date +%s)
CLAUDE_CONFIG_DIR="$CCD" TMPDIR="$RUN/tmp/" env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON \
  -u KITTY_PID -u TERM_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN \
  -u CLAUDE_CODE_TASK_LIST_ID -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_PID \
  -u CLAUDECODE -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_EFFORT \
  -u CC_SPAWN_ROOT -u CC_SPAWN_GEN -u CC_PANE_RUNNER -u CC_ACCOUNT_PINNED \
  timeout 1500 "$CLAUDE_BIN" -p --output-format json \
  --model claude-opus-5-5 --effort high --permission-mode auto \
  --strict-mcp-config --mcp-config '{"mcpServers":{}}' --settings "$SETTINGS" \
  "$(cat "$T/prompt.txt")" > "$RUN/out/result.json" 2> "$RUN/out/stderr.txt"
RC=$?
END=$(date +%s)
echo "$RC" > "$RUN/out/rc"
echo "$START $END" > "$RUN/out/time"
exit "$RC"
