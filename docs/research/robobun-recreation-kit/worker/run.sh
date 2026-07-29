#!/usr/bin/env bash
# One work item, start to finish. RECONSTRUCTED.
set -euo pipefail
: "${RUN_TOKEN:?}" "${SLUG:?}" "${REPO:?}" "${BOT_TOKEN:?}"
BRANCH="farm/${RUN_TOKEN}/${SLUG}"   # robobun's grammar; the model names the slug freehand
WT="/workspace/wt/${RUN_TOKEN}-${SLUG}"

# Persistent bare mirror -> worktrees are cheap and the build cache stays warm.
git -C /workspace/mirror fetch --prune origin
git -C /workspace/mirror worktree add -B "$BRANCH" "$WT" origin/main
cd "$WT"; mkdir -p .gate
git rev-parse HEAD > .gate/base-sha          # the gate replays THIS tree
printf 0 > .gate/iteration; printf 0 > .gate/passed; printf 0 > .gate/rejected

# UNKNOWN: robobun's model/effort. Bun's only public model pin is claude-opus-4-6[1m] on its
# triage CI jobs, which is NOT the farm. Substitute your own choice here.
claude -p "$(envsubst < /workspace/prompts/task.md)" \
  --output-format stream-json \
  --permission-mode acceptEdits \
  --add-dir "$WT" \
  2>&1 | tee "/workspace/logs/${RUN_TOKEN}-${SLUG}.jsonl"
