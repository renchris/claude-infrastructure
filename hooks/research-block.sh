#!/bin/bash
# PreToolUse (every tool, Workflow included) — the research block, REPORT.md §4.2 and §8 item 6,
# wave B1 of docs/plans/RESEARCH_PROGRAM_BUILD.md. Registered by migrations/0050 (operator-run c10).
#
# In a session of a research program whose registry state is `certifying` or `certified` (§10 open
# item 1: on from the freeze, so the relay trials run with it on), it denies by default the calls
# that buy research — Agent, Workflow, handoff-fire.sh, the vendor CLIs, `claude -p`, the kit's
# round.sh/courier.sh and the cc-research buying verbs — unless the turn's prompt was positively
# labeled a work order or a new idea by the re-ask router (hooks/research-precognition-nudge.sh).
# On a completeness or pushback turn it denies EVERY tool except the one certificate read. The
# decision table and the labels live in scripts/research-kit/router.py (`tool`); this wrapper only
# takes the fast exits, so a machine with no research program pays one jq parse per tool call.
#
# Fail direction: a missing router, resolver or registry is "no program" and allows — this hook
# can only ever add denies to a session that is provably inside an active program.
# Kill switch (operator, at launch): CC_RESEARCH_BLOCK=0.
set -uo pipefail
[ "${CC_RESEARCH_BLOCK:-1}" = 0 ] && exit 0
[ -n "${CC_RESEARCH_ROUTER_INNER:-}" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
_here="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_rl="$_here/lib/research-router.sh"
[ -f "$_rl" ] || { _t="$0"; [ -L "$_t" ] && _t="$(readlink "$_t")"; _rl="$(cd "$(dirname "$_t")" 2>/dev/null && pwd)/lib/research-router.sh"; }
[ -f "$_rl" ] || _rl="$HOME/.claude/hooks/lib/research-router.sh"
# shellcheck source=lib/research-router.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
. "$_rl" 2>/dev/null || exit 0
rr_registry_present || exit 0
rr_init "$0" || exit 0
input="$(cat)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
slug=""
if [ -n "$cwd" ]; then
  res="$(rp_resolve_cwd "$cwd" 2>/dev/null)"
  slug="${res%% *}"
fi
printf '%s' "$input" | /usr/bin/env python3 "$RR_ROUTER" tool --program "$slug" 2>/dev/null
exit 0
