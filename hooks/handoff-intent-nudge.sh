#!/bin/bash
# UserPromptSubmit: typed/verbal parity for handoff & session-succession mechanics.
#
# Why: a typed /handoff injects the full command spec; a VERBAL or relayed intent ("hand off",
# "you may self-close", "relieve", "recycle the session") leaves the model executing a
# safety-critical multi-step chain from memory. All three 2026-07-13 "the handoff closed our
# session without opening the new one" incidents arrived via verbal intent (two: pre-setsid
# watcher bug; one: an undeclared/invisible succession). This hook makes the sanctioned paths
# deterministic context whenever the intent appears in ANY user-channel message — typed by the
# human OR injected by a peer session via cc-notify (those also arrive as user prompts).
#
# Cheap (grep on the prompt), precise (skips the typed /handoff command itself — the full spec
# is being injected already), and advisory-only (additionalContext; never blocks).
set -u
INPUT="$(cat)"
PROMPT="$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("prompt",""))
except Exception: pass' 2>/dev/null)" || exit 0
[ -n "$PROMPT" ] || exit 0

# The typed command injects the full spec — no nudge needed on top of it.
case "$PROMPT" in "/handoff"*) exit 0 ;; esac

# A background team assignee owns no pane, has no session-registry row, and cannot run
# handoff-fire.sh — so ~1.2 KB of pane-succession spec is unusable context for it. It matters here
# because a LEAD's brief arrives on the assignee's user channel: a brief that merely says "hand
# off" or "recycle the session" injects the whole block into a teammate. Advisory-only hook, so the
# guard is purely a context saving — and it fails OPEN (no lib ⇒ nudge as today).
_hi_lib="${AGENT_IDENTITY_LIB:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/agent-identity.sh}"
[ -f "$_hi_lib" ] || _hi_lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/agent-identity.sh"
[ -f "$_hi_lib" ] || _hi_lib="$HOME/.claude/hooks/lib/agent-identity.sh"
if [ -f "$_hi_lib" ]; then
  # shellcheck source=lib/agent-identity.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  if . "$_hi_lib" 2>/dev/null; then
    agent_is_assignee >/dev/null 2>&1 && exit 0
  fi
fi

if printf '%s' "$PROMPT" | grep -qiE 'hand[- ]?off|self[- ]?close|\brelieve|\brelieved\b|recycle (this|the|your|our) (session|pane)|succession'; then
  # A BACKGROUND JOB gets the rails that work for it (hooks/lib/session-kind.sh): the pane block below
  # names --split-right and a pane uuid, neither of which a job has (job 032aa97f, 2026-10-03).
  _hi_sk="$(cd "$(dirname "$(readlink "$0" 2>/dev/null || echo "$0")")" 2>/dev/null && pwd)/lib/session-kind.sh"
  [ -f "$_hi_sk" ] || _hi_sk="$HOME/.claude/hooks/lib/session-kind.sh"
  _hi_job=""
  # shellcheck source=lib/session-kind.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  if [ -f "$_hi_sk" ] && . "$_hi_sk" 2>/dev/null; then _hi_job="$(cc_bgjob_short 2>/dev/null || true)"; fi
  if [ -n "$_hi_job" ] && command -v jq >/dev/null 2>&1; then
    jq -cn --arg c "HANDOFF-INTENT PARITY (deterministic hook — verbal intent must land on the same rails as a typed /handoff): $(cc_bgjob_succession_step "$_hi_job") To retire this job with nothing continuing, run handoff-fire.sh self-close --terminal (or --successor <job short>); it stops the job the same way. Never improvise teardown by hand." \
      '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
    exit 0
  fi
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"HANDOFF-INTENT PARITY (deterministic hook — verbal intent must land on the same rails as a typed /handoff): execute handoff/succession mechanics ONLY through the sanctioned paths. (1) Continuation bridge + fire: invoke Skill(handoff) and follow the CURRENT spec — never improvise the chain from memory. (2) In-place continuation of THIS pane: handoff-fire.sh --recycle. (3) Retiring a pane: handoff-fire.sh self-close --successor <pane-uuid> (verified alive, announced into the survivor via cc-notify, focused after close) or --terminal when truly nothing continues — bare self-close is refused (exit 2). (4) NEVER hand-type /exit, use raw osascript, or raw it2 session close for teardown. A pane the operator watches must never vanish without its continuation being visible (memory: handoff-succession-legibility)."}}
JSON
fi
exit 0
