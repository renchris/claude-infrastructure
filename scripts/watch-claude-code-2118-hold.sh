#!/bin/bash
# watch-claude-code-2118-hold.sh — daily poll for upstream fixes blocking 2.1.118 upgrade.
#
# We're holding at Claude Code 2.1.114 (2026-04-23) because three regressions in
# 2.1.116-2.1.118 break our workflow:
#   1. GH #52251 — subagent SendMessage/TaskCreate fail on tmux + Opus frontmatter
#   2. GH #52522 — Opus 4.7 auto-compact threshold raised → ~5x token burn on Max
#   3. GH #51798 — PreToolUse allow no longer suppresses Bash prompt w/ dangerouslyDisableSandbox
#
# Unblock criteria: #52251 AND #52522 closed upstream. #51798 preferred but
# tolerable (config workaround exists).
#
# Signals (same pattern as the prior getAppState watcher):
#   1. Member comments on any of the 3 watched issues (indicates Anthropic engaged)
#   2. Issue state change (open → closed-as-completed unblocks)
#   3. New non-skip npm version (e.g., 2.1.119+ that might carry fixes)
#   4. Merged PRs with regression-specific keywords
#   5. Release notes mentioning the issue numbers
#
# Notifies via macOS notification + `say`. State persisted to STATE_FILE.
#
# Manual invoke: ~/.claude/scripts/watch-claude-code-2118-hold.sh

set -euo pipefail

readonly ISSUES=(52251 52522 51798)
readonly PRIMARY_ISSUE=52251
readonly REPO="anthropics/claude-code"
readonly LOG_FILE="$HOME/.claude/logs/claude-code-2118-hold-watch.log"
readonly STATE_FILE="$HOME/.claude/logs/claude-code-2118-hold-watch.state.json"
readonly MANIFEST="$HOME/.claude-versions/MANIFEST.jsonl"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

notify() {
  local title="$1" message="$2"
  osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\"" 2>/dev/null || true
  say "$title" 2>/dev/null || true
  log "NOTIFY: $title — $message"
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
  else
    echo '{}'
  fi
}

save_state() {
  echo "$1" > "$STATE_FILE"
}

command -v gh >/dev/null 2>&1 || { log "gh CLI not installed — aborting"; exit 1; }

state=$(load_state)

# Signal 1+2: Anthropic member comments + state change across all watched issues
total_member_comments=0
closed_count=0
blocker_closed_count=0   # #52251 + #52522 only (unblock criteria)
status_details=""
for issue in "${ISSUES[@]}"; do
  mc=$(gh api "repos/$REPO/issues/$issue/comments" --jq \
    '[.[] | select(.author_association == "MEMBER" or .author_association == "OWNER" or .author_association == "COLLABORATOR")] | length' 2>/dev/null || echo "0")
  total_member_comments=$((total_member_comments + mc))
  is=$(gh api "repos/$REPO/issues/$issue" --jq '.state // "open"' 2>/dev/null || echo "open")
  sr=$(gh api "repos/$REPO/issues/$issue" --jq '.state_reason // ""' 2>/dev/null || echo "")
  if [[ "$is" == "closed" ]]; then
    closed_count=$((closed_count + 1))
    if [[ "$issue" == "52251" || "$issue" == "52522" ]]; then
      blocker_closed_count=$((blocker_closed_count + 1))
    fi
  fi
  status_details="$status_details #$issue:$is/mc=$mc"
done

member_comments=$total_member_comments
issue_state=$(gh api "repos/$REPO/issues/$PRIMARY_ISSUE" --jq '.state // "open"' 2>/dev/null || echo "open")

prev_member=$(echo "$state" | jq -r '.member_comments // 0')
if [[ "$member_comments" -gt "$prev_member" ]]; then
  notify "CC 2.1.118 hold: Anthropic responded" "Total member comments: $member_comments (was $prev_member).${status_details}"
fi

prev_state=$(echo "$state" | jq -r '.issue_state // "open"')
if [[ "$issue_state" != "$prev_state" ]]; then
  notify "GH #$PRIMARY_ISSUE: state=$issue_state" "Primary issue state changed from $prev_state."
fi

prev_closed=$(echo "$state" | jq -r '.closed_count // 0')
if [[ "$closed_count" -gt "$prev_closed" ]]; then
  notify "CC 2.1.118 hold: issues closing" "Closed $closed_count / ${#ISSUES[@]} issues (was $prev_closed)."
fi

# Unblock signal: both blockers (#52251 + #52522) closed
prev_blocker_closed=$(echo "$state" | jq -r '.blocker_closed_count // 0')
if [[ "$blocker_closed_count" == "2" && "$prev_blocker_closed" != "2" ]]; then
  notify "UNBLOCKED: Claude Code 2.1.118+ upgrade ready" "Both blockers closed (#52251 + #52522). Run smoke-test.sh on the latest version."
fi

# Signal 3: New non-skip npm version
npm_latest=$(timeout 5 npm view @anthropic-ai/claude-code version 2>/dev/null || echo "")
npm_skip="no"
if [[ -n "$npm_latest" && -f "$MANIFEST" ]]; then
  skip_check=$(grep -E "\"version\":\"${npm_latest//./\\.}\"" "$MANIFEST" 2>/dev/null | tail -1 \
    | sed -nE 's/.*"status":"([^"]+)".*/\1/p' || true)
  [[ "$skip_check" == "skip" ]] && npm_skip="yes"
fi

prev_npm=$(echo "$state" | jq -r '.npm_latest // ""')
if [[ -n "$npm_latest" && "$npm_latest" != "$prev_npm" && "$npm_skip" == "no" ]]; then
  notify "Claude Code $npm_latest available" "New version not on MANIFEST skip list. Smoke-test and verify #52251/#52522 closed before promoting."
fi

# Signal 4: Merged PRs with regression keywords
merged_pr_count=$(gh api "repos/$REPO/pulls" -X GET -f state=closed -f per_page=30 --jq \
  '[.[] | select(.merged_at != null) | select(.title + " " + (.body // "") | test("(?i)52251|52522|51798|subagent.{0,20}SendMessage|subagent.{0,20}TaskCreate|auto.?compact.{0,30}(threshold|limit)|PreToolUse.{0,30}allow|tmux.{0,30}Opus"))] | length' 2>/dev/null || echo "0")

prev_prs=$(echo "$state" | jq -r '.merged_prs // 0')
if [[ "$merged_pr_count" -gt "$prev_prs" ]]; then
  notify "Merged PR matches 2.1.118-hold cluster" "PR count with keywords: $merged_pr_count (was $prev_prs)"
fi

# Signal 5: Release notes mentioning fixes
release_match=$(gh api "repos/$REPO/releases?per_page=5" --jq \
  '[.[] | select(.body | test("(?i)52251|52522|51798|subagent.{0,20}SendMessage|auto.?compact.{0,30}(threshold|limit)|PreToolUse.{0,30}allow"))] | length' 2>/dev/null || echo "0")

prev_releases=$(echo "$state" | jq -r '.release_match // 0')
if [[ "$release_match" -gt "$prev_releases" ]]; then
  notify "Release notes mention 2.1.118-hold fix" "Release entries matching keywords: $release_match (was $prev_releases)"
fi

# Save new state
new_state=$(jq -n \
  --argjson mc "$member_comments" \
  --arg is "$issue_state" \
  --arg npm "${npm_latest:-}" \
  --argjson pr "$merged_pr_count" \
  --argjson rm "$release_match" \
  --argjson cc "$closed_count" \
  --argjson bcc "$blocker_closed_count" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{member_comments: $mc, issue_state: $is, npm_latest: $npm, merged_prs: $pr, release_match: $rm, closed_count: $cc, blocker_closed_count: $bcc, last_check: $ts}')
save_state "$new_state"

log "poll complete: member_comments=$member_comments primary_state=$issue_state npm=$npm_latest merged_prs=$merged_pr_count release_match=$release_match closed=$closed_count/${#ISSUES[@]} blockers_closed=$blocker_closed_count/2"
