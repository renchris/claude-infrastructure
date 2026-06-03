#!/bin/bash
# concurrent-writer-guard.sh — PreToolUse fail-closed concurrency guard (#3).
#
# Fires on Write|Edit|MultiEdit (and git/shell-write Bash, paired with
# validate-bash.sh #9). In the PRIMARY worktree of the reso repo, if this
# session is NOT the writer-lock holder AND another LIVE writer holds it:
# CHECKPOINT the dirty tree to refs/wip/root-<session>/LAST FIRST (S1), then
# DENY (or, during soak, LOG the would-deny). The lock HOLDER is never denied
# (single-denier — no mutual freeze). No-op in a linked worktree (already
# isolated). Discovery §4 DETECT-CONCURRENCY; plan #3.
#
# Modes (CLAUDE_ISOLATION_MODE): "deny" (enforcing — set explicitly to block) |
#   "log" (soak — never blocks; this is the default). Kill switch: CLAUDE_ISOLATION_SKIP=1.
# Default is "log" (checkpoint-only, never blocks). Soak verdict 2026-06-03: hard-deny blocked
# more real work than the recoverable index-sweep it prevented; worktree isolation + refs/wip
# checkpoints already cover that. Set CLAUDE_ISOLATION_MODE=deny to re-enable blocking.
# Scope: only the repo whose toplevel basename == $RESO_GUARD_REPO_NAME
#   (default reso-management-app) — avoids global side-effects.

set -uo pipefail

[[ "${CLAUDE_ISOLATION_SKIP:-0}" == "1" ]] && exit 0

MODE="${CLAUDE_ISOLATION_MODE:-log}"
REPO_NAME="${RESO_GUARD_REPO_NAME:-reso-management-app}"
LOCK_HELPER="$HOME/.claude/hooks/reso-writer-lock.py"
RUN_DIR="$HOME/.claude/run"
LOG_FILE="$HOME/.claude/logs/concurrent-writer-guard.log"
CACHE_TTL=60

mkdir -p "$RUN_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true; }

INPUT=$(cat 2>/dev/null || echo '{}')
SESSION=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo unknown)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo '')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "?"' 2>/dev/null || echo '?')
[[ -z "$CWD" ]] && CWD="$PWD"
CWD="${CWD#/private}"

# For Bash, only guard git/shell-WRITE commands — read-only bash (status, log,
# diff, ls) never mutates the index/refs, so let it through (discovery §4:
# "Bash matching git-writes/shell-writes"). Write|Edit|MultiEdit always proceed.
if [[ "$TOOL" == "Bash" ]]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo '')
  case "$CMD" in
    *"git commit"*|*"git push"*|*"git merge"*|*"git rebase"*|*"git add"*|*"git reset"*|\
    *"git checkout"*|*"git restore"*|*"git stash"*|*"git cherry-pick"*|*"git apply"*|\
    *"git am"*|*"git mv"*|*"git rm"*|*"git branch -f"*|*"git branch -D"*|*"git branch -d"*|\
    *"git update-ref"*|*"git fetch . "*|*"pnpm generate"*) ;;   # index/ref write → guard
    *) exit 0 ;;                                                # read-only bash → allow
  esac
fi

# --- Scope gate: only the reso primary worktree -----------------------------
TOPLEVEL=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo '')
[[ -z "$TOPLEVEL" ]] && exit 0                                  # not a git repo
[[ "$(basename "$TOPLEVEL")" == "$REPO_NAME" ]] || exit 0       # not our repo
# Linked worktree → .git is a FILE → already isolated → allow.
[[ -f "$TOPLEVEL/.git" ]] && exit 0
# (.git is a directory → primary worktree → guard applies.)

COMMON_DIR=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$TOPLEVEL/.git")
LOCK="$COMMON_DIR/reso-writer.lock"
STATE="$RUN_DIR/reso-writer-$SESSION.holder"   # daemon pid (we are the holder)
CACHE="$RUN_DIR/reso-writer-$SESSION.cache"    # mtime = last allow (60s amortize)

allow_cached() { : > "$CACHE" 2>/dev/null || true; exit 0; }

# --- Fast paths (amortize I/O under Agent-Team write bursts) -----------------
# 60s cache: once allowed as holder, skip all checks for CACHE_TTL seconds.
if [[ -f "$CACHE" ]]; then
  now=$(date +%s); mt=$(stat -f %m "$CACHE" 2>/dev/null || echo 0)
  (( now - mt < CACHE_TTL )) && exit 0
fi
# Holder fast path: our daemon is alive → we hold the lock → allow.
if [[ -f "$STATE" ]]; then
  hpid=$(cat "$STATE" 2>/dev/null || echo '')
  if [[ -n "$hpid" ]] && kill -0 "$hpid" 2>/dev/null; then allow_cached; fi
fi

[[ -x "$(command -v python3)" ]] || { log "$SESSION python3 missing — fail-open"; exit 0; }

# Walk the process tree to the long-lived claude process to watch.
find_claude_pid() {
  local pid=$PPID hops=0 cmd
  while [[ "${pid:-0}" -gt 1 && "$hops" -lt 12 ]]; do
    cmd=$(ps -o command= -p "$pid" 2>/dev/null || echo '')
    case "$cmd" in *claude*) echo "$pid"; return 0 ;; esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    hops=$((hops + 1))
  done
  echo "$PPID"
}

STATE_OUT=$(python3 "$LOCK_HELPER" check "$LOCK" "$SESSION" 2>/dev/null || echo 'error')
case "$STATE_OUT" in
  self*) allow_cached ;;                                 # we hold it
  free*)
    # First writer on root → become holder so a 2nd writer is detectable.
    cpid=$(find_claude_pid)
    nohup python3 "$LOCK_HELPER" hold "$LOCK" "$SESSION" --watch-pid "$cpid" </dev/null >/dev/null 2>&1 &
    echo "$!" > "$STATE"
    sleep 0.3
    re=$(python3 "$LOCK_HELPER" check "$LOCK" "$SESSION" 2>/dev/null || echo 'error')
    case "$re" in
      self*) log "$SESSION acquired writer-lock (holder=$(cat "$STATE"), watch=$cpid) $TOPLEVEL"; allow_cached ;;
      *) rm -f "$STATE" 2>/dev/null || true ;;          # lost the race → deny path
    esac
    ;;
  error*) log "$SESSION lock check error — fail-open"; exit 0 ;;
esac

# Reaching here ⇒ another LIVE writer holds the lock (or we lost the acquire race).
# (S1) CHECKPOINT the dirty tree BEFORE denying so nothing is orphaned.
if git -C "$CWD" status --porcelain 2>/dev/null | grep -q .; then
  head=$(git -C "$CWD" rev-parse HEAD 2>/dev/null || echo '')
  if [[ -n "$head" ]]; then
    tmpidx=$(mktemp)
    cp=$(
      GIT_INDEX_FILE="$tmpidx" git -C "$CWD" read-tree HEAD 2>/dev/null &&
      GIT_INDEX_FILE="$tmpidx" git -C "$CWD" add -A 2>/dev/null &&
      tree=$(GIT_INDEX_FILE="$tmpidx" git -C "$CWD" write-tree 2>/dev/null) &&
      [[ -n "$tree" ]] &&
      git -C "$CWD" commit-tree "$tree" -p "$head" -m "checkpoint-before-deny: root session $SESSION" 2>/dev/null
    ) || cp=""
    rm -f "$tmpidx"
    [[ -n "$cp" ]] && git -C "$CWD" update-ref "refs/wip/root-$SESSION/LAST" "$cp" 2>/dev/null \
      && log "$SESSION checkpoint-before-deny → refs/wip/root-$SESSION/LAST ($cp)"
  fi
fi

holder=$(echo "$STATE_OUT" | awk '{print $2}')
if [[ "$MODE" == "deny" ]]; then
  log "$SESSION DENY 2nd-writer (holder=$holder) tool=$TOOL $TOPLEVEL"
  reason="A second concurrent writer holds this repo's writer-lock. Your uncommitted work was checkpointed to refs/wip/root-$SESSION/LAST (recover: git diff refs/wip/root-$SESSION/LAST, or cherry-pick it). Isolate this session: scripts/new-worktree.sh <name> (or claude -w <name>). Override: CLAUDE_ISOLATION_SKIP=1 (not recommended)."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(printf '%s' "$reason" | jq -Rs .)"
  exit 0
fi
log "$SESSION WOULD-DENY (mode=log, soak) 2nd-writer (holder=$holder) tool=$TOOL $TOPLEVEL — allowed"
exit 0
