#!/usr/bin/env bash
# cc-unattended-ask-guard.sh — PreToolUse(AskUserQuestion): the deterministic backstop
# for the unattended-escalation doctrine (P15 §1, G-P15-5 / T-P15-7). On the 24×7 desk a
# limit event — or any STOP-ASK — fires exactly when no human is watching; a blocking
# AskUserQuestion there is the P15 idle-strand: the turn halts on a click nobody makes.
#
# Knowledge layers (commands/limit-recover.md § Unattended mode, the anti-deference rule)
# STEER the agent to route the fork to a durable cc-decide packet instead of eliciting.
# This gate catches the one failure knowledge can't: the agent asking anyway. It is the
# executable half of what was, until now, prose-only — the same "steer-then-backstop"
# design as frontier-spawn-gate.sh.
#
# Behavior (the block/allow decision hinges ONLY on the env var, never on stdin — so a
# malformed payload can never flip an interactive session into a block, nor let a strand
# through under CC_UNATTENDED):
#   CC_UNATTENDED unset / empty / 0 / false / no / off  → exit 0  (INTERACTIVE — UNCHANGED;
#       the ask still elicits; this is the load-bearing invariant of T-P15-7).
#   CC_UNATTENDED = 1 / true / yes / on (case-insensitive) → exit 2 with a reason that
#       routes the fork to a class-B decision packet + standing-value default. The blocked
#       question text (best-effort from stdin) rides the reason so the agent has the fork.
#   Any tool other than AskUserQuestion (matcher broadened later) → exit 0 (defensive scope).
#
# Kill switch: CC_UNATTENDED_ASK_GUARD_DISABLED=1 (operability — disable a misfire without
# touching live settings.json). Fail-OPEN on every unexpected path.
set -uo pipefail

[ "${CC_UNATTENDED_ASK_GUARD_DISABLED:-0}" = "1" ] && exit 0

# ── Enabled ONLY on an explicit truthy CC_UNATTENDED. Everything else (unset, empty, 0,
#    false, no, off, or any stray value) is INTERACTIVE → silent allow. Reading the env
#    directly — not stdin — is what makes the interactive path unfalsifiable. ──
val="$(printf '%s' "${CC_UNATTENDED:-}" | tr '[:upper:]' '[:lower:]')"
case "$val" in
  1|true|yes|on) ;;            # unattended — fall through to the guard
  *) exit 0 ;;                 # interactive — unchanged, no matter the payload
esac

input="$(cat 2>/dev/null || true)"

# Defensive scope: only guard AskUserQuestion. The settings matcher already scopes us to it,
# but if a future edit broadens the matcher, a non-AskUserQuestion tool must pass untouched.
# Absent/unparseable tool_name → assume AskUserQuestion (the matcher's guarantee) and proceed.
if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
else
  tool="$(printf '%s' "$input" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi
[ -n "${tool:-}" ] && [ "$tool" != "AskUserQuestion" ] && exit 0

# Best-effort: surface the first blocked question so the agent can name the fork in the
# packet. Enrichment only — a missing question NEVER changes the block decision.
if command -v jq >/dev/null 2>&1; then
  q="$(printf '%s' "$input" | jq -r '.tool_input.questions[0].question // empty' 2>/dev/null)"
fi
q="${q:-<the pending question>}"

veto="${CC_UNATTENDED_VETO_HOURS:-1}"

cat >&2 <<EOF
cc-unattended-ask-guard: CC_UNATTENDED is set — a blocking AskUserQuestion has no human to
answer it (the P15 idle-strand). Do NOT retry the elicitation. Route the ONE fork to a
durable decision packet + standing-value default instead, then keep moving:
  1. scripts/gate-classify.sh "<the fork text>"   (wait-vs-switch AND monthly-spend both → B)
  2. cc-decide open --class B --what "<the fork>" \\
       --recommendation "<the standing-value pick>" \\
       --default "<default-if-no-veto>" --deadline "<now + ${veto}h>"
  3. PROCEED on that default NOW — the deadline is the operator's async early-veto window,
     not a synchronous approval gate.
Blocked question: "${q}"
Interactive sessions (CC_UNATTENDED unset) are UNCHANGED — the ask still elicits.
Doctrine: commands/limit-recover.md § Unattended mode. Kill switch: CC_UNATTENDED_ASK_GUARD_DISABLED=1.
EOF
exit 2
