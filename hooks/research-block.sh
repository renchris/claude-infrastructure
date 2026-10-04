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
# One jq parse yields the cwd and the session id, \x1f-separated: a non-whitespace IFS keeps an
# empty cwd from shifting the fields. A session id that is neither a string nor absent prints
# sidt=other, which never takes the fast exit below.
fields="$(printf '%s' "$input" | jq -r '[(.cwd // "" | tostring),
  (.session_id | if type == "string" then "s" elif . == null then "n" else "o" end),
  (.session_id | if type == "string" then . else "" end)] | join("\u001f")' 2>/dev/null)" && parsed=1 || parsed=0
IFS=$'\x1f' read -r cwd sidt sid <<EOF
$fields
EOF
slug=""
if [ -n "$cwd" ]; then
  res="$(rp_resolve_cwd "$cwd" 2>/dev/null)"
  slug="${res%% *}"
fi
# FAST EXIT (docs/research/concurrency-scale-2026-10-04 fix row 4). router.py `tool` allows, with
# no output, whenever the cwd resolves to no program AND the session has no route record — and
# that is every tool call of every session outside a program's roots, on a machine whose registry
# exists. Deciding it here saves the python start. The route record's name is router.py
# route_path(): sid with [^A-Za-z0-9_.-] → _, cut at 128 chars, "unknown" when empty. Rather than
# re-implement that sanitizer, the fast exit is taken only for a sid the sanitizer leaves
# UNCHANGED (or an empty/absent one), so the two cannot drift; any other sid, a payload jq could
# not parse, or a multi-line field goes to the router as before.
_rb_no_route() { # $1=sid → rc 0 iff the sid is sanitizer-stable and has no route record
  local LC_ALL=C s="${1:-unknown}"   # byte ranges: a locale must not widen A-Z past ASCII
  case "$s" in *[!A-Za-z0-9_.-]*) return 1 ;; esac
  [ "${#s}" -le 128 ] || return 1
  [ ! -e "${CC_RESEARCH_HOME:-$HOME/.claude/autonomy/research}/route-state/$s.json" ]
}
if [ "$parsed" = 1 ] && [ -z "$slug" ] && [ "$sidt" != o ] && [ "${fields#*$'\n'}" = "$fields" ] \
  && _rb_no_route "$sid"; then
  exit 0
fi
printf '%s' "$input" | /usr/bin/env python3 "$RR_ROUTER" tool --program "$slug" 2>/dev/null
exit 0
