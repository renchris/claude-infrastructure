#!/bin/bash
# inflight.sh — is work of THIS session still running while its lead looks idle?
#   inflight_waves    <transcript>  workflow runs with a fresh agent transcript (a count)
#   inflight_bg_tasks <transcript>  background Bash tasks and background Agent subagents that were
#                                   started and never reported finished, and are still writing
#
# Readers: hooks/session-continue.sh's scope floor (docs/research/lead-keeps-working-2026-10-24.md
# §3.3), which sources this through INFLIGHT_LIB and treats `?` or an unresolvable lib as unknown.
# boundary-handoff.sh keeps its own `bh_live_waves`; inflight_waves is a COPY of it, not a move, so
# that hook and its suite stay out of this change and its free-win guard gains no fail-open path
# (§3.3). tests/inflight.bats runs both on one fixture so the copies cannot drift (S22).
#
# WHAT COUNTS AS IN FLIGHT — deliberately narrow, because the reader SKIPS a block on "in flight"
# and a false "in flight" silences the floor at exactly the idle close it exists for:
#   · a task counts only while fresh: its output file / agent transcript was written within
#     CC_BH_WAVE_WARM_S (the waves' freshness rule), so an orphaned id cannot hold the floor down;
#   · a Bash task whose command is cc-await-ping is a WATCHER, not work, and never counts.
#
# Pure function definitions only; safe to source under `set -u` and under /bin/bash 3.2.

# EVIDENCE, and it is deliberately file-based. Workflow agents share the session's pid, so there is no
# process to count. A run is LIVE when its journal has more `started` than `result` rows AND some
# agent transcript under it was written within CC_BH_WAVE_WARM_S. The freshness leg is what keeps an
# abandoned run from holding the arm down forever.
CC_BH_WAVE_WARM_S="${CC_BH_WAVE_WARM_S:-1800}"
inflight_waves() { # <transcript> → count of in-flight workflow runs for THIS session (0 when unknowable)
  local tp="$1"
  # The run dirs live BESIDE the transcript, in a directory named after it WITHOUT the extension:
  # <projects>/<slug>/<sid>.jsonl  ->  <projects>/<slug>/<sid>/subagents/workflows/<runId>/.
  # `${tp%/*}` (the transcript's PARENT) is the slug dir and holds every session's tree, so it
  # counts nothing and reads as a clean "no waves" — measured 0 against three live runs before this
  # line was corrected. A detector's own path is the first thing to falsify.
  local _wdir="${tp%.jsonl}/subagents/workflows" _n=0 _j _st _rs _fresh _now
  [ -d "$_wdir" ] || { printf '0'; return 0; }
  _now="$(date +%s)"
  for _j in "$_wdir"/*/journal.jsonl; do
    [ -f "$_j" ] || continue
    # `grep -c` PRINTS its count and EXITS 1 when that count is zero, so `grep -c … || printf '0'`
    # emits BOTH — the substitution becomes "0\n0", `[ 1 -gt "0 0" ]` ERRORS, and `2>/dev/null ||
    # continue` reads that error as a clean false. Measured: the guard counted 0 live waves against
    # three, i.e. it silently disabled itself in the one direction nobody checks.
    _st="$(grep -c '"type":"started"' "$_j" 2>/dev/null | tr -d ' ' || true)"
    _rs="$(grep -c '"type":"result"'  "$_j" 2>/dev/null | tr -d ' ' || true)"
    case "$_st" in ''|*[!0-9]*) _st=0 ;; esac
    case "$_rs" in ''|*[!0-9]*) _rs=0 ;; esac
    [ "$_st" -gt "$_rs" ] || continue
    # freshest agent transcript in this run, in seconds of age
    _fresh="$(find "${_j%/*}" -name 'agent-*.jsonl' -type f -print0 2>/dev/null \
              | xargs -0 stat -f '%m' 2>/dev/null | sort -rn | head -1)"
    [ -n "$_fresh" ] || continue
    [ $(( _now - _fresh )) -le "$CC_BH_WAVE_WARM_S" ] 2>/dev/null || continue
    _n=$(( _n + 1 ))
  done
  printf '%s' "$_n"
}

# _inflight_mtime <path> → epoch seconds, empty when the file is missing. `-c` first: GNU `stat -f`
# SUCCEEDS at something else (a filesystem report), so the BSD-first order never reaches its
# fallback on Linux (hooks/lib/mailbox-pending.sh, `_mbx_mtime`).
_inflight_mtime() {
  local m
  m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)" || m=''
  case "$m" in ''|*[!0-9]*) m='' ;; esac
  printf '%s' "$m"
}

# _inflight_fresh <path> <now> → rc 0 iff the file exists and was written within CC_BH_WAVE_WARM_S.
_inflight_fresh() {
  local m
  m="$(_inflight_mtime "$1")"
  [ -n "$m" ] || return 1
  [ $(( $2 - m )) -le "${CC_BH_WAVE_WARM_S:-1800}" ] 2>/dev/null
}

# _inflight_is_watcher <command> → rc 0 iff the command's first real word is cc-await-ping. Skips
# `VAR=value`, `env` and `timeout <n>` / `gtimeout <n>`, then compares the BASENAME: watchers are
# launched by absolute path (73 × `/…/.claude/bin/cc-await-ping`, 0 bare, §9.3 M20), so a literal
# first-word match would count every one of them as work.
_inflight_is_watcher() {
  local w skip=0
  local -a words
  read -r -a words <<<"$1" || true
  for w in ${words[@]+"${words[@]}"}; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$w" in
      [A-Za-z_]*=*) case "${w%%=*}" in *[!A-Za-z0-9_]*) ;; *) continue ;; esac ;;
      env) continue ;;
      timeout|gtimeout) skip=1; continue ;;
    esac
    [ "${w##*/}" = cc-await-ping ]
    return
  done
  return 1
}

# inflight_bg_tasks <transcript> → `<n>` or `<n> <kinds>` (kinds ⊆ `bg,agent`, those present among
# the live ones), or `?` when the transcript is unreadable or a tool errors.
#   started   every `Command running in background with ID: <id>` (a Bash tool result; also the
#             `moved to the background (ID: <id>)` form a timed-out foreground command takes), and
#             every `agentId: <id>` in an `Async agent launched` tool result (Agent with
#             run_in_background, §9.3 M19)
#   finished  every `<task-id><id></task-id>` in ANY record kind. Notifications arrive as user
#             records, but mid-turn as `queued_command` attachments and `queue-operation` records too;
#             reading user records alone left 7 "live" tasks at three idle closes (§9.3 M14), so the
#             raw lines are grepped and every kind is covered.
# Cost: three `grep -oE` passes over the transcript, plus one jq only when a live Bash id survives.
inflight_bg_tasks() {
  local tp="$1" now started finished agents id path rc n=0 kb=0 ka=0 kinds='' line
  local -a bg_ids bg_paths
  [ -f "$tp" ] && [ -r "$tp" ] || { printf '?'; return 0; }
  now="$(date +%s)"

  # grep -o rc: 0 match · 1 none (a clean empty) · 2 error (unknown)
  started="$(grep -oE '(Command running in background with ID: |moved to the background \(ID: )[A-Za-z0-9_-]+[).]*( Output is being written to: [^ "\\]+)?' "$tp")"; rc=$?
  [ "$rc" -le 1 ] || { printf '?'; return 0; }
  agents="$(grep -oE 'Async agent launched[^"]*agentId: [A-Za-z0-9_-]+' "$tp")"; rc=$?
  [ "$rc" -le 1 ] || { printf '?'; return 0; }
  finished="$(grep -oE '<task-id>[A-Za-z0-9_-]+</task-id>' "$tp")"; rc=$?
  [ "$rc" -le 1 ] || { printf '?'; return 0; }
  finished=" $(printf '%s\n' "$finished" | sed -e 's/<task-id>//' -e 's#</task-id>##' | tr '\n' ' ')"

  # Live, fresh Bash tasks: id + output path (a record may carry the phrase twice; first wins).
  bg_ids=(); bg_paths=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="${line#*ID: }"; id="${id%%[!A-Za-z0-9_-]*}"
    [ -n "$id" ] || continue
    case "$finished" in *" $id "*) continue ;; esac
    case " ${bg_ids[*]+${bg_ids[*]}} " in *" $id "*) continue ;; esac
    path=''
    case "$line" in *'Output is being written to: '*) path="${line#*Output is being written to: }"; path="${path%.}" ;; esac
    [ -n "$path" ] && _inflight_fresh "$path" "$now" || continue
    bg_ids+=("$id"); bg_paths+=("$path")
  done <<<"$started"

  # Drop watchers: one jq maps each live id to the command of the tool_use its result answers.
  if [ "${#bg_ids[@]}" -gt 0 ]; then
    local cmds
    cmds="$(jq -nrR --arg ids "${bg_ids[*]}" '
      ($ids | split(" ")) as $want
      | reduce (inputs | fromjson? | objects) as $r ({cmd: {}, res: {}};
          if $r.type == "assistant" then
            reduce ($r.message.content? | arrays | .[] | objects
                    | select(.type == "tool_use" and .name == "Bash")) as $u
              (.; .cmd[$u.id] = ($u.input.command // ""))
          elif $r.type == "user" then
            reduce ($r.message.content? | arrays | .[] | objects | select(.type == "tool_result")) as $t (.;
              ($t.content | if type == "string" then .
                            elif type == "array" then (map(.text? // "") | join("\n"))
                            else "" end) as $c
              | reduce ($want[] | select(. as $w
                  | ($c | test("ID: " + $w + "([^A-Za-z0-9_-]|$)"))
                    or (($r.toolUseResult? | objects | .backgroundTaskId?) == $w))) as $w
                  (.; .res[$w] = $t.tool_use_id))
          else . end)
      | . as $s | $want[] | [., ($s.cmd[$s.res[.] // ""] // "")] | @tsv' "$tp")" \
      || { printf '?'; return 0; }
    while IFS=$'\t' read -r id line; do
      [ -n "$id" ] || continue
      # @tsv escapes a newline as `\n`; the first word never spans one.
      _inflight_is_watcher "${line%%\\n*}" && continue
      kb=$(( kb + 1 ))
    done <<<"$cmds"
  fi

  # Live, fresh background agents: their transcript sits beside ours (§3.3, measured layout).
  local seen=' '
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="${line##*agentId: }"
    case "$finished" in *" $id "*) continue ;; esac
    case "$seen" in *" $id "*) continue ;; esac
    seen="$seen$id "
    _inflight_fresh "${tp%.jsonl}/subagents/agent-$id.jsonl" "$now" || continue
    ka=$(( ka + 1 ))
  done <<<"$agents"

  n=$(( kb + ka ))
  [ "$kb" -gt 0 ] && kinds='bg'
  [ "$ka" -gt 0 ] && kinds="${kinds:+$kinds,}agent"
  if [ "$n" -gt 0 ]; then printf '%s %s' "$n" "$kinds"; else printf '0'; fi
}
