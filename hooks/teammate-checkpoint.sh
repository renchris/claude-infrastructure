#!/bin/bash
# shellcheck disable=SC2329,SC1083,SC2155
# teammate-checkpoint.sh — PostToolUse + Stop + TeammateIdle hook.
#
# Creates a lightweight checkpoint of teammate work using git plumbing
# (read-tree + add -A + write-tree + commit-tree) — zero impact on the
# working tree or real index, and bypasses pre-commit hooks entirely
# (never invokes `git commit`). Captures tracked modifications AND
# untracked files (honoring .gitignore).
#
# Fires on:
#   - PostToolUse: every N tool uses (default 10)
#   - Stop:        always (end of turn)
#   - TeammateIdle: always (on idle transition — invoked synchronously by
#                   teammate-auto-shutdown.sh before it reaps the worktree)
#
# Worktree conventions supported:
#   - /tmp/worktree-<team>-<member>   (legacy, from 15-agent research)
#   - /tmp/wt-<team>-<member>         (newer, per ui-sh-100p-v2 plan)
#   - /tmp/worktree-<member>          (single-segment fallback)
#
# Output refs (per worktree):
#   - refs/checkpoints/<member>/<YYYYMMDDTHHMMSSZ>   — timestamped, append-only
#   - refs/wip/<member>/LAST                         — fast-forward alias to latest
#
# Kill switch: export TEAMMATE_CHECKPOINT_DISABLED=1
# Tuning:      export TEAMMATE_CHECKPOINT_EVERY=<N>  (default 5 — tightened
#              from 10 on 2026-04-18 after Wave 2 context-exhaustion incident:
#              teammates can crash before hitting 10 PostToolUse events, so
#              the safety-net trigger needs to fire sooner. Per-fixture commit
#              cadence in the brief template remains the primary defense.)

set -uo pipefail

if [[ "${TEAMMATE_CHECKPOINT_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

readonly EVERY="${TEAMMATE_CHECKPOINT_EVERY:-5}"
readonly WATCHDOG_DIR="$HOME/.claude/watchdog"
readonly LOG_FILE="$HOME/.claude/logs/teammate-checkpoint.log"

mkdir -p "$WATCHDOG_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# Parse hook JSON stdin
INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo 'unknown')
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "?"' 2>/dev/null || echo '?')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo '')
[[ -z "$CWD" ]] && CWD="$PWD"
# Prefer names from payload — Claude Code provides these for TeammateIdle;
# teammate-auto-shutdown.sh also populates them in its synthetic payload.
PAYLOAD_TEAM=$(echo "$INPUT" | jq -r '.team_name // empty' 2>/dev/null || echo '')
PAYLOAD_MEMBER=$(echo "$INPUT" | jq -r '.teammate_name // empty' 2>/dev/null || echo '')

# Normalize /private/tmp → /tmp (macOS realpath quirk)
CWD="${CWD#/private}"

# Only act in a worktree or repo we manage. Gate on git-common-dir (discovery
# §4 #4) so the checkpoint covers the repo ROOT + ~/Development/.worktrees, not
# just /tmp/wt-* — otherwise solo-root and Track-R worktree sessions are a
# permanent recovery blind spot. The clean-tree skip below prevents over-firing.
case "$CWD" in
  /tmp/worktree-*|/tmp/wt-*) ;;                 # legacy + current teammate paths
  "$HOME"/Development/.worktrees/*) ;;          # Track R worktrees (branch-named)
  *)
    # Any other dir: act only if it is inside a git working tree (root or
    # linked worktree). --git-common-dir resolves for both; fails elsewhere.
    git -C "$CWD" rev-parse --git-common-dir >/dev/null 2>&1 || exit 0
    ;;
esac

# Skip mid-rebase/merge — avoid corrupting in-flight git operations
if [[ -d "$CWD/.git/rebase-merge" || -d "$CWD/.git/rebase-apply" || -f "$CWD/.git/MERGE_HEAD" ]]; then
  log "skip $CWD: rebase/merge in progress"
  exit 0
fi

# Per-session counter (avoid collisions across parallel teammates)
COUNTER_FILE="$WATCHDOG_DIR/cp-$SESSION_ID.count"
COUNT=0
[[ -f "$COUNTER_FILE" ]] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)

# Always checkpoint on Stop + TeammateIdle; otherwise every EVERY tool uses
SHOULD_SNAPSHOT=false
case "$EVENT" in
  Stop|TeammateIdle)
    SHOULD_SNAPSHOT=true
    ;;
  *)
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$COUNTER_FILE"
    if (( COUNT % EVERY == 0 )); then
      SHOULD_SNAPSHOT=true
    fi
    ;;
esac

$SHOULD_SNAPSHOT || exit 0

# Only snapshot if there's something to snapshot
if ! git -C "$CWD" status --porcelain 2>/dev/null | grep -q .; then
  log "no checkpoint needed for $CWD — tree clean"
  exit 0
fi

# Derive member name. Preference order:
#   1. PAYLOAD_MEMBER from hook JSON (Claude Code native events + our synthetic payload)
#   2. Strip PAYLOAD_TEAM prefix from the basename ("wt-<team>-<member>" → "<member>")
#   3. Parse from basename using convention
#
# Conventions for step 3:
#   /tmp/worktree-<team>-<member>  — legacy ("worktree-" prefix, team slug)
#   /tmp/wt-<team>-<member>        — newer ("wt-" prefix, team slug like "ui-sh-v2")
#   /tmp/worktree-<member>         — single-segment (no team prefix)
BASENAME=$(basename "$CWD")
if [[ -n "$PAYLOAD_MEMBER" ]]; then
  MEMBER="$PAYLOAD_MEMBER"
elif [[ -n "$PAYLOAD_TEAM" ]]; then
  # Strip either "wt-<team>-" or "worktree-<team>-" prefix
  MEMBER="$BASENAME"
  MEMBER="${MEMBER#wt-$PAYLOAD_TEAM-}"
  MEMBER="${MEMBER#worktree-$PAYLOAD_TEAM-}"
else
  # Last-resort fallback: strip prefix + assume single-segment member.
  # For multi-segment conventions, the caller should pass PAYLOAD_TEAM.
  case "$BASENAME" in
    wt-*) MEMBER="${BASENAME#wt-}" ;;
    worktree-*) MEMBER="${BASENAME#worktree-}" ;;
    *) MEMBER="$BASENAME" ;;
  esac
fi
[[ -z "$MEMBER" ]] && MEMBER="$BASENAME"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
MSG="checkpoint: ${EVENT} count=${COUNT} ts=${TIMESTAMP}"

# Snapshot BOTH tracked modifications AND untracked files (respecting .gitignore)
# via a temp index — zero impact on the teammate's working tree or real index.
# (git stash create alone misses untracked files; new files a teammate writes
# would be lost on a crash, defeating the point.)
HEAD_SHA=$(git -C "$CWD" rev-parse HEAD 2>/dev/null || echo "")
if [[ -z "$HEAD_SHA" ]]; then
  log "no HEAD for $CWD — skipping checkpoint"
  exit 0
fi

TMP_INDEX=$(mktemp)
# If anything fails, drop the temp index — we never touch the real one
cleanup_index() { rm -f "$TMP_INDEX"; }
trap cleanup_index EXIT

CHECKPOINT_SHA=$(
  GIT_INDEX_FILE="$TMP_INDEX" git -C "$CWD" read-tree HEAD 2>/dev/null &&
  GIT_INDEX_FILE="$TMP_INDEX" git -C "$CWD" add -A 2>/dev/null &&
  TREE=$(GIT_INDEX_FILE="$TMP_INDEX" git -C "$CWD" write-tree 2>/dev/null) &&
  [[ -n "$TREE" && "$TREE" != "$(git -C "$CWD" rev-parse HEAD^{tree} 2>/dev/null)" ]] &&
  git -C "$CWD" commit-tree "$TREE" -p "$HEAD_SHA" -m "$MSG" 2>/dev/null
) || CHECKPOINT_SHA=""

if [[ -z "$CHECKPOINT_SHA" ]]; then
  log "no checkpoint needed for $CWD — tree matches HEAD"
  exit 0
fi

# Record under refs/checkpoints/<member>/<timestamp> so `git reflog` can list them
TS_REF="refs/checkpoints/$MEMBER/$TIMESTAMP"
LAST_REF="refs/wip/$MEMBER/LAST"

if git -C "$CWD" update-ref "$TS_REF" "$CHECKPOINT_SHA" 2>/dev/null; then
  log "checkpoint $CWD $MEMBER $EVENT count=$COUNT sha=$CHECKPOINT_SHA ref=$TS_REF"
  # Fast-forward the LAST alias too (O(1) "give me the latest" for respawn)
  git -C "$CWD" update-ref "$LAST_REF" "$CHECKPOINT_SHA" 2>/dev/null \
    && log "  → fast-forwarded $LAST_REF"
else
  log "WARN: update-ref failed for $TS_REF"
fi

exit 0
