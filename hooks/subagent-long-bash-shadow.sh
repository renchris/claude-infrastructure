#!/bin/bash
# subagent-long-bash-shadow.sh — lever D4: a subagent's foreground Bash with timeout > 270 s.
#
# Plan: docs/plans/USAGE_LEVERS.md § W3 and § W7+ §2 D4. Research: docs/research/usage-levers-2026-10-23/
# round2/REPORT.md decision 3. It LOGS. It prints nothing, except the one D4-DENY line of a treated
# poll loop (S11, below), which only an agent in the treat arm at a pct above 0 can reach.
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
# W7+ S3 (plan § W7+ §2 D4 "Arm"/"First", §3 "Telemetry rows") bumps the row to v:3, still log-only:
#   arm      lever D4's arm for this agent_id (hooks/lib/lever-flags.sh lf_arm, salt_D4), the full
#            lf_arm_json object; arms are per agent, never per account. pct 0 means every unit is
#            ctrl or the forced arm, and nothing here reads the arm to decide anything.
#   acct     the account running the hook; tp_acct the account root the transcript lives under. A
#            cross-account copy is owned by the EARLIEST file (the cc-token-ledger rule), resolved
#            by the scorer: the hook only records both, since a live call cannot see later copies.
#   wider    the wider pattern (`select(undef`, `time.sleep(`), a SEPARATE match class: it never
#            sets narrow or would_deny_class. wider_would_deny is the population it would add (a
#            match no narrow class took, not bounded by an inner timeout under 300 s).
#   kind=d4_follow  what the agent did next. A would-deny (narrow or wider) leaves a marker per
#            agent_id; hooks/validate-bash.sh pipes that agent's next Bash call here whatever its
#            timeout, and this writes one follow row linking it (follows_tool_use_id) and clears the
#            marker. The follow call may also get its own subagent_bash row: consumers filter kind.
# W7+ S11 (plan § W7+ §2 D4; decisions-2026-10-24 REPORT.md row 3b) adds the TREATMENT verdict. Only
#   the poll-loop class is deny-eligible (long-runner, waiter and the wider pattern stay count-only),
#   and every row carries treat_verdict: null (not eligible), "would_deny" (eligible, but this
#   agent's arm is not treat at a pct above 0 — every eligible row at pct 0), or "deny". Only on
#   "deny", and only after its row is written, does this print one line on stdout,
#   `D4-DENY<TAB><the fixed message>`, which validate-bash.sh turns into its deny(). The message is
#   the lever's tunable (§3 hillclimb "D4: the message"): a non-wait branch, `echo rc=$?`, and repeat
#   the slice on 124; never run_in_background (it trips the /goal gate in validate-bash.sh).
# Every row is one write() of at most 2 KB (cmd_head and transcript_path shed first), in UTC Z.
# Markers live in $CC_SUBAGENT_LONG_BASH_PENDING, else beside a redirected log (so a replay through
# CC_SUBAGENT_LONG_BASH_LOG never touches live state), else ~/.claude/state/levers/d4-pending.
#
# HOSTED by hooks/validate-bash.sh, which is already registered on PreToolUse(Bash) for every account
# and already parses agent_id and run_in_background: it pipes the payload here only for a subagent's
# foreground call that carries a timeout, so the main thread pays nothing. Kill switches:
# CC_SUBAGENT_LONG_BASH=off (nothing runs), CC_LEVER_D4 / CC_LEVER_ALL = off|control (arm ctrl, so
# never "deny"). Log: ~/.claude/logs/subagent-long-bash.jsonl (command head ≤ 200 chars + sha256,
# never the whole command). Fail-open on every path: any failure prints nothing. bash 3.2-safe.
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

_log="${CC_SUBAGENT_LONG_BASH_LOG:-$HOME/.claude/logs/subagent-long-bash.jsonl}"
if [ -n "${CC_SUBAGENT_LONG_BASH_PENDING:-}" ]; then _pend="$CC_SUBAGENT_LONG_BASH_PENDING"
elif [ -n "${CC_SUBAGENT_LONG_BASH_LOG:-}" ]; then _pend="$_log.pending"
else _pend="${CC_LEVER_STATE_DIR:-$HOME/.claude/state/levers}/d4-pending"; fi
# The direct binary, never `shasum` (a #! perl script: hooks/lib/shasum-direct.sh).
_sha256=/sbin/sha256sum; [ -x "$_sha256" ] || _sha256=sha256sum
_acct="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _acct="${_acct%/}"; _acct="${_acct##*/}"
_tp_acct=""; [[ $_tp =~ /(\.claude[A-Za-z0-9_-]*)/ ]] && _tp_acct="${BASH_REMATCH[1]}"
_aid_ok=""; case "$_aid" in *[!A-Za-z0-9._-]*|.*) ;; *) [ ${#_aid} -le 128 ] && _aid_ok=1 ;; esac
_cmdsha() { _sha="$(printf '%s' "$_cmd" | "$_sha256" 2>/dev/null)"; _sha="${_sha%% *}"; }

# Clock and D4 arm per agent_id, computed only for a call that will be logged: a call the gates
# below drop pays no extra fork. The arm is one jq + one sha256sum (lever-flags.sh); a missing lib
# or an unsafe id logs null.
_armj=""
_prep() {
  [ -z "$_armj" ] || return 0
  _now="$(date -u '+%s %FT%TZ')"; _epoch="${_now%% *}"; _ts="${_now#* }"
  _armj=null
  local lf="${BASH_SOURCE[0]%/*}/lib/lever-flags.sh"
  if [ -n "$_aid_ok" ] && [ -r "$lf" ]; then
    # shellcheck source=lib/lever-flags.sh
    # shellcheck disable=SC1091  # resolved at RUNTIME from BASH_SOURCE
    . "$lf" && lf_arm D4 "$_aid" && _armj="$(lf_arm_json)"
  fi
  return 0
}

# One row, one write(), at most 2 KB: shed cmd_head and transcript_path first, else write nothing.
_emit() { # <jq object program> [jq args…] — the row is built by the program from its --arg values
  local prog="$1" line; shift
  line="$(jq -nr "$@" --argjson arm "$_armj" "($prog) as \$r
    | if (\$r | tojson | utf8bytelength) < 2048 then \$r
      else \$r + {cmd_head: ((\$r.cmd_head // \"\")[0:40]), transcript_path: null, trunc: true} end
    | tojson | if utf8bytelength < 2048 then . else empty end" 2>/dev/null)" || return 0
  [ -n "$line" ] || return 1
  mkdir -p "${_log%/*}" 2>/dev/null || return 1
  printf '%s\n' "$line" >> "$_log" 2>/dev/null
}

# ── d4_follow: this agent's previous Bash call was a would-deny; record what it did next ──────────
if [ -n "$_aid_ok" ] && [ -e "$_pend/$_aid" ]; then
  # claim the marker atomically: a parallel follow call that loses the rename logs nothing
  if mv "$_pend/$_aid" "$_pend/.claim.$_aid.$$" 2>/dev/null; then
    IFS=$'\t' read -r _f_tuid _f_cls _f_wider _f_sha _f_epoch _f_tv < "$_pend/.claim.$_aid.$$" || true
    rm -f "$_pend/.claim.$_aid.$$" 2>/dev/null
    _prep; _cmdsha
    case "$_f_epoch" in ''|*[!0-9]*) _gap=-1 ;; *) _gap=$(( _epoch - _f_epoch )) ;; esac
    _rc=false; [[ $_cmd == *'rc=$?'* ]] && _rc=true
    _toj=null; case "$_to" in ''|*[!0-9.]*) ;; *) _toj="${_to%%.*}" ;; esac
    # shellcheck disable=SC2016  # a jq program: its $vars are jq's
    _emit '{kind:"d4_follow",v:3,ts:$ts,acct:$acct,sid:$sid[0:128],agent_id:$aid[0:128],
            agent_type:$atype[0:128],tool_use_id:$tuid[0:128],
            follows_tool_use_id:$ftuid[0:128],follows_class:(if $fcls == "-" then null else $fcls end),
            follows_wider:(if $fw == "-" then null else $fw end),
            follows_verdict:(if $ftv == "-" then null else $ftv end),
            gap_s:(if $gap < 0 then null else $gap end),same_cmd:($sha == $fsha),echo_rc:$rc,
            timeout_ms:$to,run_in_background:($bg == "true"),cmd_head:$head,cmd_sha256:$sha,arm:$arm}' \
      --arg ts "$_ts" --arg acct "$_acct" --arg sid "$_sid" --arg aid "$_aid" --arg atype "$_atype" \
      --arg tuid "$_tuid" --arg ftuid "${_f_tuid:--}" --arg fcls "${_f_cls:--}" --arg fw "${_f_wider:--}" \
      --arg ftv "${_f_tv:--}" --argjson gap "$_gap" --arg sha "$_sha" --arg fsha "${_f_sha:-}" \
      --argjson rc "$_rc" --argjson to "$_toj" --arg bg "$_bg" --arg head "${_cmd:0:200}"
  fi
fi

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

# ── wider pattern (shadow only, its own class): perl's select(undef,…) and python's time.sleep( ───
_wider=""; _wider_wd=false
_rx_select='select[[:space:]]*[(][[:space:]]*undef'
_rx_tsleep='time[.]sleep[[:space:]]*[(]'
if [[ $_cmd =~ $_rx_select ]]; then _wider="select-undef"
elif [[ $_cmd =~ $_rx_tsleep ]]; then _wider="time-sleep"; fi
if [ -n "$_wider" ] && [ -z "$_class" ] && [ -z "$_exempt" ] && ! { [ "$_inner" -ge 0 ] && [ "$_inner" -lt 300 ]; }; then
  _wider_wd=true
fi

_prep; _cmdsha

# ── treatment verdict (S11): poll-loop only; "deny" needs this agent's arm = treat at pct_eff > 0 ───
# The arm already folds every lower-only control (hook kill, CC_LEVER_EXCLUDE, CC_LEVER_ALL/D4,
# mode, trip, dead-man): treat is reachable only at pct_eff > 0. Both are re-checked here anyway, so
# a partial lib load (LF_ARM unset) can only read would_deny.
_tv=""
if [ "$_class" = poll-loop ]; then
  _tv=would_deny
  if [ "${LF_ARM:-}" = treat ] && [ "${LF_PCT_EFF:-0}" -gt 0 ] 2>/dev/null; then _tv=deny; fi
fi

# shellcheck disable=SC2016  # a jq program: its $vars are jq's
_emit 'def nul: if . == "" then null else . end;
   {kind:"subagent_bash",v:3,ts:$ts,acct:$acct,tp_acct:($tpa|nul),sid:$sid[0:128],agent_id:$aid[0:128],
    agent_type:$atype[0:128],tool_use_id:$tuid[0:128],timeout_ms:$to,broad:true,narrow:($cls != ""),
    why:($why|nul),would_deny_class:($cls|nul),exempt:($ex|nul),
    inner_timeout_s:(if $inner < 0 then null else $inner end),wider:($wider|nul),wider_would_deny:$wwd,
    would:"count",treat_verdict:($tv|nul),arm:$arm,cmd_head:$head,cmd_sha256:$sha,transcript_path:$tp[0:300]}' \
  --arg ts "$_ts" --arg acct "$_acct" --arg tpa "$_tp_acct" --arg sid "$_sid" --arg aid "$_aid" \
  --arg atype "$_atype" --arg tuid "$_tuid" --argjson to "$_to" --arg why "$_why" \
  --arg head "${_cmd:0:200}" --arg sha "$_sha" --arg tp "$_tp" \
  --arg cls "$_class" --arg ex "$_exempt" --argjson inner "$_inner" \
  --arg wider "$_wider" --argjson wwd "$_wider_wd" --arg tv "$_tv" || { [ "$_tv" != deny ] || _tv=would_deny; }   # no row, no deny

# a would-deny (narrow or wider) arms the follow pipe for this agent's next Bash call
if [ -n "$_aid_ok" ] && { [ -n "$_class" ] || [ "$_wider_wd" = true ]; } && mkdir -p "$_pend" 2>/dev/null; then
  find "$_pend" -type f -mmin +1440 -delete 2>/dev/null   # an agent that never called again
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$_tuid" "${_class:--}" "${_wider:--}" "$_sha" "$_epoch" "${_tv:--}" > "$_pend/$_aid" 2>/dev/null
fi

if [ "$_tv" = deny ]; then
  printf 'D4-DENY\t%s\n' "Denied by usage lever D4 (3df527edd333): this foreground poll loop can outlive the subagent's 5-minute prompt cache, and the next request then re-writes your whole context. If you are not waiting on something outside this agent, do not poll: do the next piece of work now and check once later. If you must wait, wait in slices: re-issue it as \`timeout 260 bash -c '<the loop>'; echo rc=\$?\` with a Bash tool timeout of 270000 or less, and repeat that same slice while it prints rc=124. Do not use run_in_background for it."
fi
exit 0
