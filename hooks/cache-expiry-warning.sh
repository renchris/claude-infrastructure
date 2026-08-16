#!/bin/bash
# UserPromptSubmit Hook — Cache Expiry Warning
# Fires when the idle gap since the last interaction exceeds the prompt-cache TTL, so
# the next turn pays cache_creation on the whole context instead of a free cache_read.
#
# ⚠️ CORRECTED 2026-08-16 (USAGE_TELEMETRY_100P §2.4). This hook was wrong twice over:
#
#  1. THE TTL WAS 300s AND THE REAL TTL IS ~3600s. Anthropic documents that "on a Claude
#     subscription, Claude Code requests the one-hour TTL automatically"; ENABLE_PROMPT_CACHING_1H
#     only matters when drawing on usage credits, and credits_on is false on 5,017/5,017 rows of
#     ~/.claude/logs/account-utilization.jsonl, so the downgrade path has never fired. Measured
#     independently in our own corpus: the cache-miss breakpoint is at 65 min (3600-3900s band
#     33.5% miss, 3900-4200s 90.8%), while the 300-900s band this hook policed sits at 7.1% —
#     indistinguishable from the 1.3% baseline. At 300s, 184 of 238 fires were FALSE (77.3%),
#     measured over 13,622 user-prompt gaps in 200 sessions.
#
#  2. ITS ADVICE INCREASED QUOTA SPEND. It recommended /clear or /compact "to reduce token cost".
#     Against the weekly limit, cache_read is charged at ~nothing while cache_creation is 42-48%
#     of the bill — so discarding a warm cache converts a FREE operation into a PAID one. It also
#     traded session state for tokens, which the operator's standing rule forbids outright
#     ("never cut quality even for a disproportionate amount of token savings").
#
# It now reports the fact and names the only quality-neutral use of it: an expiry is the cheapest
# moment for a recycle you had ALREADY decided to make. It never recommends one.

set -euo pipefail

LAST_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.last-interaction"
# Overridable so a future re-measurement changes one env var, not this file.
CACHE_TTL="${CC_PROMPT_CACHE_TTL_S:-3600}"  # 1 hour — the subscription default

# No tracking file = first message in session, skip
if [[ ! -f "$LAST_FILE" ]]; then
  exit 0
fi

LAST_EPOCH=$(cat "$LAST_FILE" 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)
ELAPSED=$((NOW_EPOCH - LAST_EPOCH))

if [[ $ELAPSED -gt $CACHE_TTL ]]; then
  MINUTES=$((ELAPSED / 60))
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "PROMPT CACHE EXPIRED: ${MINUTES}m idle vs a $((CACHE_TTL / 60))m TTL, so this turn re-creates the cache — cache_creation is a charged class against the weekly limit, unlike cache_read. No action is required and shrinking the context does NOT save quota. Relevant only if you had already decided to recycle: a boundary here wastes the least."
  }
}
EOF
fi

exit 0
