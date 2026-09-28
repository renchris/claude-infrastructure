#!/bin/bash
# replay-after.sh — the #18 replay's AFTER state, without waiting for the live backfill.
# Once #18a (index workflow result files, aff1d904e) and its all-roots sweep (7eb75b912) are live, the
# launchd sweep reaches the other account roots at SESSION_INDEX_SWEEP_MAX_FILES per tick, so on
# 2026-09-28 the #106 gold (two wf_*.json files under ~/.claude-quaternary) was hours from the live
# index. This script builds what the live index will hold for those files: it `.backup`s the live
# index into a mktemp HOME, copies ONLY the gold workflow files into a scratch projects root under
# their real project/session dirs, runs THIS tree's hooks/session-index-sweep.sh against the copy
# (retention, history union and read ledger disabled, so the copy is only added to), then runs
# replay.sh on the copy. The live index, live state and every account root are only read.
# Usage: bash replay-after.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$here/../../../.." && pwd)
T=$(mktemp -d)
mkdir -p "$T/.claude/state" "$T/.claude/autonomy" "$T/projects"
sqlite3 "$HOME/.claude/session-index.db" ".backup '$T/.claude/session-index.db'" \
  || { echo "COPY-FAIL"; exit 2; }
n=0
for f in \
  "$HOME/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-pool-7/5e498dc5-b58d-4f17-8f12-0b868021b84c/workflows/wf_850036ea-183.json" \
  "$HOME/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-pool-7/d83af9ce-0678-4154-b7d9-3f6afcade3d6/workflows/wf_05868c2b-dcd.json"; do
  [ -f "$f" ] || { echo "GOLD-MISSING: $f"; continue; }
  rel=${f#"$HOME/.claude-quaternary/projects/"}
  mkdir -p "$T/projects/${rel%/*}" && cp "$f" "$T/projects/$rel" && n=$((n + 1))
done
echo "gold workflow files copied: $n"
HOME="$T" SESSION_INDEX_DB="$T/.claude/session-index.db" SESSION_INDEX_PROJECT_ROOTS="$T/projects" \
  CLAUDE_PROJECTS_DIR="$T/projects" CC_IDL="$T/.claude/autonomy/idl.jsonl" \
  SESSION_INDEX_RETENTION_DAYS=0 CC_HISTORY_UNION_MINUTES=0 CC_READ_LEDGER_MINUTES=0 \
  bash "$REPO/hooks/session-index-sweep.sh" >/dev/null 2>&1
echo "wf rows in the copy: $(sqlite3 "$T/.claude/session-index.db" \
  "select group_concat(session_id, ' ') from sessions where session_id in ('wf_850036ea-183','wf_05868c2b-dcd')")"
bash "$here/replay.sh" "$T/.claude/session-index.db"
# Control: is the gold findable at all once indexed? The same ask's nouns, spelled correctly (the
# prompt reads "Dyanmic" and "Pierre Jouet" for Perrier-Jouët; the gold never says "pinterest").
PY=$(readlink -f "$HOME/.claude/bin/session-search.py" 2>/dev/null || echo "$HOME/.claude/bin/session-search.py")
for q in 'dynamic workflow perrier jouet' 'perrier jouet' 'bottle reference sourcing'; do
  top=$(HOME="$T" python3 "$PY" --format json --limit 5 "$q" 2>/dev/null \
        | jq -r '[.[] | (.session_id // .id // "") | .[0:15]] | join(",")' 2>/dev/null)
  printf 'control %-30s top5=%s\n' "'$q'" "$top"
done
