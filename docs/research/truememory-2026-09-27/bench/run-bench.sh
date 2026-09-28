#!/usr/bin/env bash
# run-bench.sh <arm 1|2|3> <task-id> <rep> — ONE headless run of the #35 delivery benchmark
# (docs/research/truememory-2026-09-27.md §5.16 pre-registration; results in §5.17).
#
# Modelled on ../ab-harness/run-ab.sh. Per run, under $RUNROOT/<task>/a<arm>-r<rep>/:
#   origin.git + fx/  a clone of a one-commit snapshot of the repo at the arm's sha (arms 1-2:
#                     BENCH_A2_SHA, default abaf1e990; arm 3: BENCH_A3_SHA, required)
#   home/.claude/projects/<infra key>/memory/   the frozen store COPY (autoMemoryDirectory); mem -> it
#   out/              result.json, rc, time, meta.json, settings.json, mem.{before,after}.sha256, fx.status
#
# Arm differences, and nothing else differs:
#   1  stock: no hooks of ours, no rules or instruction text (fixture .claude/rules/ and
#      CLAUDE.global*.md deleted), only the sandbox guard.
#   2/3 the memory hooks the arm's tree registers (settings template + bash-output-offload, which a
#      migration registers), run from an exported copy of that tree; the fixture's .claude/CLAUDE.md
#      and rules plus the tree's CLAUDE.global.slim.md (what account next loads) through --add-dir;
#      the tree's bin/ on PATH.
# `--setting-sources ''` loads NO user or project instructions in any arm (probed 2026-09-28), so the
# arm-2/3 text arrives only through --add-dir with CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1. The
# `project` source was rejected: its ancestor walk from a fixture under ~/.claude pulls in
# ~/.claude/CLAUDE.md and ~/.claude/rules in every arm.
#
# Isolation: claude itself keeps the real HOME (a redirected HOME is "Not logged in"); every hook of
# ours is launched as `env HOME=$RUN/home CLAUDE_CONFIG_DIR=$RUN/home/.claude …`, so their logs, state,
# backups and `~/` pointers land in the run. The transcript lands in $BENCH_CONFIG_DIR/projects/.
set -u
[ $# -eq 3 ] || { echo "usage: run-bench.sh <arm 1|2|3> <task-id> <rep>" >&2; exit 2; }
ARM=$1; TASK=$2; REP=$3
H=$(cd "$(dirname "$0")" && pwd)
REPO=${BENCH_REPO:-$(git -C "$H" rev-parse --show-toplevel)}
RUNROOT=${BENCH_ROOT:-$HOME/.claude/autonomy/memory-eval/bench-runs}
SRC=${BENCH_STORE:-$HOME/.claude/autonomy/memory-eval/storecopy-infra-2026-09-28}
CCD=${BENCH_CONFIG_DIR:-$HOME/.claude-next}
CLAUDE_BIN=${CLAUDE_BIN:-/opt/homebrew/bin/claude}
GUARD=${BENCH_GUARD:-$HOME/Development/claude-infrastructure/docs/research/token-efficiency-2026-09-23/eval/harness/f3/sandbox-guard.sh}
KEY=-Users-chrisren-Development-claude-infrastructure

case "$ARM" in
  1|2) SHA=${BENCH_A2_SHA:-abaf1e990} ;;
  3) SHA=${BENCH_A3_SHA:-}; [ -n "$SHA" ] || { echo "arm 3 needs BENCH_A3_SHA" >&2; exit 2; } ;;
  *) echo "bad arm: $ARM" >&2; exit 2 ;;
esac
SHA=$(git -C "$REPO" rev-parse --verify -q "$SHA^{commit}") || { echo "unknown sha" >&2; exit 2; }
ROW=$(awk -F'\t' -v t="$TASK" 'NR>1 && $1==t' "$H/tasks.tsv")
[ -n "$ROW" ] || { echo "no task: $TASK" >&2; exit 2; }
SETUP=$(printf '%s' "$ROW" | cut -f4); PROMPT=$(printf '%s' "$ROW" | cut -f5)
case "$RUNROOT" in /tmp/*|/private/tmp/*|'') echo "refusing RUNROOT $RUNROOT (X8)" >&2; exit 2 ;; esac
[ -d "$SRC" ] && [ -f "$GUARD" ] && [ -d "$CCD" ] || { echo "missing store, guard or config dir" >&2; exit 2; }

# One snapshot repo and one exported tree per sha, shared by every run (built under a mkdir lock).
SNAP="$RUNROOT/_snap/$SHA.git"; TREE="$RUNROOT/_trees/$SHA"
mkdir -p "$RUNROOT/_snap" "$RUNROOT/_trees"
until mkdir "$RUNROOT/_snap/.lock" 2>/dev/null; do sleep 1; done
if [ ! -d "$SNAP" ] || [ ! -d "$TREE" ]; then
  B="$RUNROOT/_snap/.build-$$"; rm -rf "$B" "$TREE"; mkdir -p "$B/w" "$TREE"
  git -C "$REPO" archive "$SHA" | tar -x -C "$B/w" && git -C "$REPO" archive "$SHA" | tar -x -C "$TREE" \
    && git -C "$B/w" init -q -b main && git -C "$B/w" add -A \
    && git -C "$B/w" -c user.name=Bench -c user.email=bench@example.invalid commit -q -m "snapshot $SHA" \
    && git clone -q --bare "$B/w" "$SNAP"
  st=$?; rm -rf "$B"
  [ "$st" -eq 0 ] || { rmdir "$RUNROOT/_snap/.lock"; echo "snapshot failed" >&2; exit 3; }
fi
rmdir "$RUNROOT/_snap/.lock"

RUN="$RUNROOT/$TASK/a$ARM-r$REP"
rm -rf "${RUN:?}"; mkdir -p "$RUN/out" "$RUN/tmp" "$RUN/home/.claude/state" "$RUN/home/.claude/logs" "$RUN/home/.claude/autonomy"
FX="$RUN/fx"
git clone -q --bare --local "$SNAP" "$RUN/origin.git" && git clone -q --local "$RUN/origin.git" "$FX" \
  || { echo "fixture clone failed" >&2; exit 3; }
git -C "$FX" config user.name "Bench Run"; git -C "$FX" config user.email "bench@example.invalid"

MEMREAL="$RUN/home/.claude/projects/$KEY/memory"
mkdir -p "$(dirname "$MEMREAL")" && cp -R "$SRC" "$MEMREAL" && ln -s "$MEMREAL" "$RUN/mem"
FXSLUG=$(python3 -c 'import os,re,sys; print(re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(sys.argv[1])))' "$FX")
mkdir -p "$RUN/home/.claude/projects/$FXSLUG" && ln -s "$MEMREAL" "$RUN/home/.claude/projects/$FXSLUG/memory"

bash "$H/setup.sh" "$SETUP" "$FX" "$RUN" || { echo "setup failed: $SETUP" >&2; exit 3; }
if [ "$ARM" = 1 ]; then
  rm -rf "$FX/.claude/rules" "$FX"/CLAUDE.global*.md
  git -C "$FX" add -A && git -C "$FX" commit -q -m "strip rules" && git -C "$FX" push -q origin HEAD:main
fi
( cd "$MEMREAL" && find . -type f | sort | xargs shasum -a 256 ) > "$RUN/out/mem.before.sha256"

ADD=(); ENVX=(); PATHX=""
if [ "$ARM" != 1 ]; then
  mkdir -p "$RUN/instr" && cp "$TREE/CLAUDE.global.slim.md" "$RUN/instr/CLAUDE.md"
  ADD=(--add-dir "$FX" "$RUN/instr"); ENVX=(CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1); PATHX="$TREE/bin:"
fi
SETTINGS=$(python3 "$H/settings.py" "$ARM" "$RUN" "$TREE" "$GUARD" "$RUN/out/hooks.txt") || exit 3
printf '%s\n' "$SETTINGS" > "$RUN/out/settings.json"
python3 -c 'import json,sys; a=sys.argv; print(json.dumps({"arm": a[1], "task": a[2], "rep": a[3], "sha": a[4], "fx": a[5]}))' \
  "$ARM" "$TASK" "$REP" "$SHA" "$FX" > "$RUN/out/meta.json"
printf '%s' "$PROMPT" > "$RUN/out/prompt.txt"

cd "$FX" || exit 2
START=$(date +%s)
env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON -u KITTY_PID -u TERM_SESSION_ID \
  -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_TASK_LIST_ID \
  -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_PID -u CLAUDECODE \
  -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_EFFORT -u CLAUDE_PROJECT_DIR \
  -u CC_SPAWN_ROOT -u CC_SPAWN_GEN -u CC_PANE_RUNNER -u CC_ACCOUNT_PINNED \
  CLAUDE_CONFIG_DIR="$CCD" TMPDIR="$RUN/tmp/" PATH="$PATHX$PATH" ${ENVX[@]+"${ENVX[@]}"} \
  timeout 1500 "$CLAUDE_BIN" -p --output-format json \
  --model claude-opus-5-5 --effort high --permission-mode auto \
  --strict-mcp-config --mcp-config '{"mcpServers":{}}' --setting-sources '' --settings "$SETTINGS" \
  ${ADD[@]+"${ADD[@]}"} < "$RUN/out/prompt.txt" > "$RUN/out/result.json" 2> "$RUN/out/stderr.txt"
echo $? > "$RUN/out/rc"; echo "$START $(date +%s)" > "$RUN/out/time"
( cd "$MEMREAL" && find . -type f | sort | xargs shasum -a 256 ) > "$RUN/out/mem.after.sha256"
git -C "$FX" status --porcelain > "$RUN/out/fx.status" 2>&1
