#!/bin/bash
# migration-class: c10
# migration-step: register hooks/handoff-claim-assert.sh as a Stop hook so a "▶ Run this:" command the agent can run itself blocks the close instead of reaching the operator — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0027-handoff-claim-registration.sh
# migration-subject: ~/.claude/hooks/handoff-claim-assert.sh
# migration-verify: jq -e '[.hooks.Stop[].hooks[]? | select(.command == "~/.claude/hooks/handoff-claim-assert.sh")] | length >= 1' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0027 — docs/research/silver-platter-enforcement-2026-09-12.
# Subject: hooks/handoff-claim-assert.sh (6/6) · bin/cc-cannot (13/13) · bin/cc-owner (5/5)
#
# WHAT IT FIXES. A `▶ Run this:` marker asserts "I cannot run this; you must." That claim was the
# one load-bearing close claim with no verifier — free text, asserted by the same model that made
# the inference. wrap-ledger.sh refuses a false "landed", completion-assert.sh refuses a false
# "done", cc-backlog refuses `needs-human` without a conviction number; this one was on trust.
# Measured over 2,690 transcripts: 1,376 hand-offs, of which a double-labelled gold set calls 474
# (34%) commands the agent could and should have run itself. The operator's words: "This happens a
# lot. Almost every time I feel."
#
# WHY IT IS SAFE TO BLOCK. It fires on `REFUTED` only. Against the 429-command gold set,
# emission-weighted: 165 of 1,379 emissions refuted, 165 correct, ZERO false blocks across the
# 32-day corpus. It never surfaces a HUMAN verdict — an affirmation changes nothing the operator
# does, and a hook that speaks with nothing to add is the nag anti-deference-nudge.sh:30 warns
# trains the model to route around it. Latched per message-hash and capped at
# HANDOFF_CLAIM_MAX (3); assignees exempt; kill switch HANDOFF_CLAIM_DISABLED=1.
#
# ORDER. Registered AFTER completion-assert.sh: that hook adjudicates whether the close is honest
# at all, and its verdict should land before this one narrows to a single line of it.
set -uo pipefail

CFG="${CC_CLAUDE_DIR:-$HOME/.claude}"
S="$CFG/settings.json"
CMD="~/.claude/hooks/handoff-claim-assert.sh"

command -v jq >/dev/null 2>&1 || { echo "0027: jq is required" >&2; exit 1; }
[ -f "$S" ] || { echo "0027: no settings.json at $S" >&2; exit 1; }

if jq -e --arg c "$CMD" '[.hooks.Stop[].hooks[]? | select(.command == $c)] | length >= 1' "$S" >/dev/null 2>&1; then
  echo "0027: already registered — nothing to do."; exit 0
fi

BAK="$S.bak-0027-$(date +%Y%m%d%H%M%S)"
cp "$S" "$BAK" || { echo "0027: could not back up $S" >&2; exit 1; }

# Append into the FIRST Stop group, after completion-assert.sh where present.
TMP="$(mktemp)"
jq --arg c "$CMD" '
  .hooks.Stop = (
    (.hooks.Stop // [{}])
    | if length == 0 then [{hooks: []}] else . end
    | .[0].hooks = ((.[0].hooks // []) + [{type: "command", command: $c, timeout: 10}])
    | .
  )' "$S" > "$TMP" || { echo "0027: jq edit failed; settings.json untouched (backup $BAK)" >&2; rm -f "$TMP"; exit 1; }

jq -e . "$TMP" >/dev/null 2>&1 || { echo "0027: produced invalid JSON; refusing to install (backup $BAK)" >&2; rm -f "$TMP"; exit 1; }
mv "$TMP" "$S"

if jq -e --arg c "$CMD" '[.hooks.Stop[].hooks[]? | select(.command == $c)] | length >= 1' "$S" >/dev/null 2>&1; then
  echo "0027: registered $CMD as a Stop hook."
  echo "0027: backup at $BAK"
  echo "0027: kill switch — export HANDOFF_CLAIM_DISABLED=1"
else
  echo "0027: verification FAILED after write; restore with: cp '$BAK' '$S'" >&2; exit 1
fi
