#!/bin/bash
# recycle-failed-inject.sh — SessionStart child (run by session-start-dispatch.sh). The second
# channel for a failed recycle's recovery packet (docs/plans/RECYCLE_KEYSTROKELESS_DELIVERY.md §D4).
#
# WHY. On 2026-10-09 a self-recycle died after its /exit, and the original was resumed with NO prompt:
# it came back idle, never learned the recycle had failed, and nothing re-fired it. The first channel
# is bin/reso-resume-one, which submits the packet's <sid>.prompt.md as a launch argument. This hook
# covers every resume that does not go through it — an operator's manual `claude --resume`, another
# resumer — by putting the packet in front of the model as additionalContext, EXACTLY ONCE.
#
# THE PACKET (written by handoff-fire's rcy_recovery_packet):
#   ${CC_RECYCLE_FAILED_DIR:-~/.claude/autonomy/recycle-failed}/<session_id>.json  + <session_id>.prompt.md
# Injected only when the packet is undelivered (no delivered_at) and not yet injected (no
# injected_at); injected_at is stamped by temp + mv AFTER the context is printed, so a second
# SessionStart (a /clear, a compact, a re-resume) finds it and stays quiet. Print-then-stamp is the
# order that cannot lose the packet: the dispatcher kills a slow child at its bound, and a kill between
# a stamp and its print used to mark the packet injected while nothing reached the model. A kill or an
# unwritable stamp after the print costs at worst one repeat on the next start, never the order itself.
# A packet with no token, or one jq cannot parse, is treated as ABSENT: reso-resume-one and the
# delivery proofs key on the token, so a tokenless order could never be acknowledged.
#
# NOT injected when CC_RECYCLE_ATTACHED_TOKEN equals the packet's token: reso-resume-one exports that
# when it has already submitted this packet as the session's first prompt, and the hook inherits it
# through claude's environment. Two copies of the same order would read as two failures.
#
# FAIL-OPEN: no jq, no session id or no packet prints nothing and exits 0.
# bash 3.2 (hooks run under /bin/bash).
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
DIR="${CC_RECYCLE_FAILED_DIR:-$HOME/.claude/autonomy/recycle-failed}"

payload="$(cat 2>/dev/null)" || payload=""
sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)" || sid=""
# The sid names a file in DIR: refuse anything that could leave it.
case "$sid" in ''|.*|*[!A-Za-z0-9._-]*) exit 0 ;; esac
pkt="$DIR/$sid.json"; prompt="$DIR/$sid.prompt.md"
[ -f "$pkt" ] && [ -s "$prompt" ] || exit 0

# One read for every field the decision needs; a malformed packet is treated as absent.
fields="$(jq -r '[(.delivered_at // ""), (.injected_at // ""), (.token // "")] | @tsv' "$pkt" 2>/dev/null)" || exit 0
delivered="${fields%%	*}"; rest="${fields#*	}"
injected="${rest%%	*}"; token="${rest#*	}"
[ -n "$token" ] || exit 0
[ -z "$delivered" ] && [ -z "$injected" ] || exit 0
[ "${CC_RECYCLE_ATTACHED_TOKEN:-}" = "$token" ] && exit 0

# Print FIRST, stamp after (see the header): a lost stamp repeats the order, a lost print loses it.
ctx="RECYCLE FAILED — this session's self-recycle did not complete, and it was resumed without the recovery prompt. Delivered once by SessionStart (hooks/recycle-failed-inject.sh; packet $pkt). Act on it before anything else:

$(cat "$prompt")"
jq -nc --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}' || exit 0

tmp="$pkt.tmp.$$"
if { jq --arg v "$(date -u +%FT%TZ)" '.injected_at = $v' "$pkt" > "$tmp"; } 2>/dev/null; then
  mv -f "$tmp" "$pkt" 2>/dev/null || rm -f "$tmp" 2>/dev/null
else
  rm -f "$tmp" 2>/dev/null
fi
exit 0
