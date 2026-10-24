#!/bin/bash
# subagent-long-bash-shadow.sh — COUNT-ONLY rule: a subagent's foreground Bash with timeout > 270 s.
#
# Plan: docs/plans/USAGE_LEVERS.md § W3. Research: docs/research/usage-levers-2026-10-23/round2/
# REPORT.md decision 3. It LOGS, it never denies, and it prints nothing.
#
# WHY. A subagent's prompt cache lives 5 minutes. A foreground Bash that runs past ~300 s lets it
# expire, and the subagent's next request re-writes its whole context: 250 rebuilds (46.3M tokens)
# in round 2 followed a foreground Bash whose timeout parameter was over 270 s. Slices of 270 s or
# less are safe (3 rebuilds in 302 gaps of 270-300 s). But a BLANKET deny on timeout > 270 s would
# have hit 6,385 calls, 5,941 of which finished in 270 s or less (median 10 s) — 24 harmless denies
# per rebuild avoided. So the rule is narrowed, and run count-only for a week before any deny:
#   broad   every subagent foreground Bash with tool_input.timeout > 270000 ms (logged, for the base)
#   narrow  the subset whose COMMAND says it will wait: a poll loop (while/until/for … sleep), a
#           sleep of 270 s or more, a waiter (cc-await-ping, cc-wait, gh run watch, --watch,
#           tail -f, bare wait, timeout ≥ 270), or a known long runner (bats, ship-land, deploy-live,
#           pytest, test/build scripts, cargo, xcodebuild, make, ffmpeg, render). `why` names the class.
# W6 (decision re-research 2026-10-24): `would_deny_class` splits the narrow rows into the three
# classes a deny would be judged by — poll-loop, long-runner, waiter (a long sleep is a waiter) —
# and a command whose every inner `timeout N` is under 300 s is EXEMPT from the count: it bounds
# itself under the cache's life (765 such calls, 6 followed by a rebuild). An exempt row keeps its
# `why` and `inner_timeout_s` and is logged with narrow:false and would_deny_class:null.
# bin/cc-idle-cache-readout joins each row to the call's real runtime and the next request's cache
# write (from the subagent transcript), prices wrongly denied calls against rebuilds avoided per
# class, and reports the one acceptance number: wrong-deny cost under 0.2% of weekly usage.
#
# HOSTED by hooks/validate-bash.sh, which is already registered on PreToolUse(Bash) for every account
# and already parses agent_id and run_in_background: it pipes the payload here only for a subagent's
# foreground call that carries a timeout, so the main thread pays nothing. Kill switch:
# CC_SUBAGENT_LONG_BASH=off. Log: ~/.claude/logs/subagent-long-bash.jsonl (command head + sha256,
# never the whole command). Fail-open on every path. bash 3.2-safe.
set -uo pipefail
trap 'exit 0' EXIT

[ "${CC_SUBAGENT_LONG_BASH:-shadow}" != off ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

IFS= read -r -d '' _in || true
[ -n "$_in" ] || exit 0

# Line 1: the scalars, tab-separated; everything after the first newline: the command verbatim.
_p="$(printf '%s' "$_in" | jq -r '
  def cell: (if . == null then "" else . end) | tostring | gsub("[\\t\\r\\n]"; " ") | if . == "" then "-" else . end;
  ([(.agent_id|cell), (.agent_type|cell), (.session_id|cell), (.tool_use_id|cell),
    (.tool_input.timeout|cell), (.tool_input.run_in_background|cell), (.transcript_path|cell)] | join("\t")),
  (.tool_input.command // "")' 2>/dev/null)" || exit 0
_meta="${_p%%$'\n'*}"
_cmd=""; [[ "$_p" == *$'\n'* ]] && _cmd="${_p#*$'\n'}"
IFS=$'\t' read -r _aid _atype _sid _tuid _to _bg _tp <<<"$_meta"

[ "${_aid:--}" != "-" ] || exit 0                 # main thread / pane teammate: not this rule
[ "${_bg:-}" != "true" ] || exit 0                # backgrounded: the subagent does not block on it
case "$_to" in ''|*[!0-9.]*) exit 0 ;; esac
_to="${_to%%.*}"
[ "${_to:-0}" -gt 270000 ] 2>/dev/null || exit 0

# ── narrow: does the command itself say it will wait? ───────────────────────────────────────────
_why=""
# a quote or paren may open the loop too: `bash -c 'until …; do sleep …'` is the same poll loop (W6)
_rx_loop="(^|[;&|[:space:]'\"(])(while|until|for)[[:space:]].*sleep[[:space:]]"
_rx_sleep='(^|[;&|[:space:]])sleep[[:space:]]+([0-9]+)'
_rx_wait='cc-await-ping|cc-wait([[:space:]]|$)|gh[[:space:]]+run[[:space:]]+watch|--watch([[:space:]]|$)|tail[[:space:]]+-[A-Za-z]*[fF]|(^|[;&|][[:space:]]*)wait([[:space:]]*($|[;&|]))'
_rx_timeout='(^|[;&|[:space:]])g?timeout[[:space:]]+(-[^[:space:]]+[[:space:]]+)*([0-9]+)([sm]?)[[:space:]]'
_rx_long='(^|[/[:space:];&|])(cc-bats|bats|ship-land(\.sh)?|deploy-live(\.sh)?|pytest|xcodebuild|ffmpeg)([[:space:]]|$)|(pnpm|npm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(test|build|e2e)|cargo[[:space:]]+(build|test)|(^|[;&|[:space:]])make([[:space:]]|$)|[[:space:]]render([[:space:]]|$)'
if [[ $_cmd =~ $_rx_loop ]]; then
  _why="poll-loop"
elif [[ $_cmd =~ $_rx_sleep ]] && [ "${BASH_REMATCH[2]}" -ge 270 ] 2>/dev/null; then
  _why="long-sleep"
elif [[ $_cmd =~ $_rx_wait ]]; then
  _why="waiter"
elif [[ $_cmd =~ $_rx_timeout ]] && {
       _tn="${BASH_REMATCH[3]}"; [ "${BASH_REMATCH[4]}" = m ] && _tn=$(( _tn * 60 )); [ "$_tn" -ge 270 ]; } 2>/dev/null; then
  _why="waiter"
elif [[ $_cmd =~ $_rx_long ]]; then
  _why="long-runner"
fi

# ── exemption: the largest inner `timeout N` (s); every one under 300 ⇒ the call bounds itself ─────
_inner=-1; _rest="$_cmd"; _k=0
while [ "$_k" -lt 20 ] && [[ $_rest =~ $_rx_timeout ]]; do
  _tn=$(( 10#${BASH_REMATCH[3]} )); [ "${BASH_REMATCH[4]}" = m ] && _tn=$(( _tn * 60 ))
  [ "$_tn" -gt "$_inner" ] && _inner="$_tn"
  _rest="${_rest#*"${BASH_REMATCH[0]}"}"; _k=$(( _k + 1 ))
done
_class=""; _exempt=""
case "$_why" in
  poll-loop|long-runner|waiter) _class="$_why" ;;
  long-sleep) _class="waiter" ;;
esac
if [ -n "$_class" ] && [ "$_inner" -ge 0 ] && [ "$_inner" -lt 300 ]; then _class=""; _exempt="inner-timeout"; fi

_log="${CC_SUBAGENT_LONG_BASH_LOG:-$HOME/.claude/logs/subagent-long-bash.jsonl}"
mkdir -p "${_log%/*}" 2>/dev/null || exit 0
# The direct binary, never `shasum` (a #! perl script: hooks/lib/shasum-direct.sh).
_sha256=/sbin/sha256sum; [ -x "$_sha256" ] || _sha256=sha256sum
_sha="$(printf '%s' "$_cmd" | "$_sha256" 2>/dev/null)"; _sha="${_sha%% *}"
_acct="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _acct="${_acct%/}"; _acct="${_acct##*/}"
jq -nc --arg ts "$(date -u +%FT%TZ)" --arg acct "$_acct" --arg sid "$_sid" --arg aid "$_aid" \
  --arg atype "$_atype" --arg tuid "$_tuid" --argjson to "$_to" --arg why "$_why" \
  --arg head "${_cmd:0:160}" --arg sha "$_sha" --arg tp "$_tp" \
  --arg cls "$_class" --arg ex "$_exempt" --argjson inner "$_inner" \
  'def nul: if . == "" then null else . end;
   {kind:"subagent_bash",v:2,ts:$ts,acct:$acct,sid:$sid,agent_id:$aid,agent_type:$atype,
    tool_use_id:$tuid,timeout_ms:$to,broad:true,narrow:($cls != ""),why:($why|nul),
    would_deny_class:($cls|nul),exempt:($ex|nul),inner_timeout_s:(if $inner < 0 then null else $inner end),
    would:"count",cmd_head:$head,cmd_sha256:$sha,transcript_path:$tp}' >> "$_log" 2>/dev/null
exit 0
