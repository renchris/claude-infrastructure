#!/bin/bash
# watch-getAppState-fix.sh — daily poll for upstream Claude Code fixes.
#
# Tracks TWO regression clusters we've locally patched:
#   1. TL / getAppState crash (GH #49253) — bytes 12194998 in 2.1.112 cli.js
#   2. Plan-accept "use auto mode" silent fallback (GH #49502/#49653/#49687)
#      — bytes 12184944 in 2.1.112 cli.js
#
# Signals: member comments on any watched issue, issue close-as-completed,
# new non-skip npm version, merged PRs matching regression keywords, release
# notes matching keywords. Notifies via macOS notification + `say`.
#
# Invoked by launchd daily at 09:07 local
# (~/Library/LaunchAgents/com.chrisren.watch-getAppState-fix.plist).
#
# Manual invoke: ~/.claude/scripts/watch-getAppState-fix.sh

set -euo pipefail

readonly ISSUES=(49253 49502 49653 49687 49804 49889 49812)
readonly PRIMARY_ISSUE=49253
readonly REPO="anthropics/claude-code"
readonly LOG_FILE="$HOME/.claude/logs/getAppState-fix-watch.log"
readonly STATE_FILE="$HOME/.claude/logs/getAppState-fix-watch.state.json"
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

# Signal 1+2: Anthropic member comments + state change across ALL watched issues.
# Aggregate totals so one persistent state file tracks the whole cluster.
total_member_comments=0
closed_count=0
status_details=""
for issue in "${ISSUES[@]}"; do
  mc=$(gh api "repos/$REPO/issues/$issue/comments" --jq \
    '[.[] | select(.author_association == "MEMBER" or .author_association == "OWNER" or .author_association == "COLLABORATOR")] | length' 2>/dev/null || echo "0")
  total_member_comments=$((total_member_comments + mc))
  is=$(gh api "repos/$REPO/issues/$issue" --jq '.state // "open"' 2>/dev/null || echo "open")
  sr=$(gh api "repos/$REPO/issues/$issue" --jq '.state_reason // ""' 2>/dev/null || echo "")
  [[ "$is" == "closed" ]] && closed_count=$((closed_count + 1))
  status_details="$status_details #$issue:$is/mc=$mc"
done

# Back-compat: keep scalar names for `member_comments` and `issue_state`
# (primary issue is treated as the representative signal for alert framing).
member_comments=$total_member_comments
issue_state=$(gh api "repos/$REPO/issues/$PRIMARY_ISSUE" --jq '.state // "open"' 2>/dev/null || echo "open")
state_reason=$(gh api "repos/$REPO/issues/$PRIMARY_ISSUE" --jq '.state_reason // ""' 2>/dev/null || echo "")

prev_member=$(echo "$state" | jq -r '.member_comments // 0')
if [[ "$member_comments" -gt "$prev_member" ]]; then
  notify "GH cluster: Anthropic responded" "Total member comments: $member_comments (was $prev_member).${status_details}"
fi

prev_state=$(echo "$state" | jq -r '.issue_state // "open"')
if [[ "$issue_state" != "$prev_state" ]]; then
  notify "GH #$PRIMARY_ISSUE: state=$issue_state" "Was $prev_state. state_reason=$state_reason"
fi

prev_closed=$(echo "$state" | jq -r '.closed_count // 0')
if [[ "$closed_count" -gt "$prev_closed" ]]; then
  notify "GH cluster: issues closed" "Closed $closed_count / ${#ISSUES[@]} issues (was $prev_closed)."
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
  notify "Claude Code $npm_latest available" "New version — not on MANIFEST skip list. Consider smoke-testing."
fi

# Signal 4: Merged PRs with keywords from either regression cluster
merged_pr_count=$(gh api "repos/$REPO/pulls" -X GET -f state=closed -f per_page=30 --jq \
  '[.[] | select(.merged_at != null) | select(.title + " " + (.body // "") | test("(?i)getAppState|toolUseContext|autoMode|auto.mode|plan.accept|49253|49502|49653|49687|49804|49889"))] | length' 2>/dev/null || echo "0")

prev_prs=$(echo "$state" | jq -r '.merged_prs // 0')
if [[ "$merged_pr_count" -gt "$prev_prs" ]]; then
  notify "Merged PR mentions watched cluster" "PR count with keywords: $merged_pr_count (was $prev_prs)"
fi

# Signal 5: Release notes mentioning fix
release_match=$(gh api "repos/$REPO/releases?per_page=5" --jq \
  '[.[] | select(.body | test("(?i)getAppState|toolUseContext|autoMode|auto.mode|plan.accept|permission.?prompt|49253|49502|49653|49687"))] | length' 2>/dev/null || echo "0")

prev_releases=$(echo "$state" | jq -r '.release_match // 0')
if [[ "$release_match" -gt "$prev_releases" ]]; then
  notify "Release notes mention fix" "Release entries matching keywords: $release_match (was $prev_releases)"
fi

# Save new state
new_state=$(jq -n \
  --argjson mc "$member_comments" \
  --arg is "$issue_state" \
  --arg npm "${npm_latest:-}" \
  --argjson pr "$merged_pr_count" \
  --argjson rm "$release_match" \
  --argjson cc "$closed_count" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{member_comments: $mc, issue_state: $is, npm_latest: $npm, merged_prs: $pr, release_match: $rm, closed_count: $cc, last_check: $ts}')
save_state "$new_state"

log "poll complete: member_comments=$member_comments issue_state=$issue_state npm=$npm_latest merged_prs=$merged_pr_count release_match=$release_match closed=$closed_count/${#ISSUES[@]}"
