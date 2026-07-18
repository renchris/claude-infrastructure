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

if printf '%s' "$PROMPT" | grep -qiE 'hand[- ]?off|self[- ]?close|\brelieve|\brelieved\b|recycle (this|the|your|our) (session|pane)|succession'; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"HANDOFF-INTENT PARITY (deterministic hook — verbal intent must land on the same rails as a typed /handoff): execute handoff/succession mechanics ONLY through the sanctioned paths. (1) Continuation bridge + fire: invoke Skill(handoff) and follow the CURRENT spec — never improvise the chain from memory. (2) In-place continuation of THIS pane: handoff-fire.sh --recycle. (3) Retiring a pane: handoff-fire.sh self-close --successor <pane-uuid> (verified alive, announced into the survivor via cc-notify, focused after close) or --terminal when truly nothing continues — bare self-close is refused (exit 2). (4) NEVER hand-type /exit, use raw osascript, or raw it2 session close for teardown. A pane the operator watches must never vanish without its continuation being visible (memory: handoff-succession-legibility)."}}
JSON
fi
exit 0
