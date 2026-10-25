#!/bin/bash
# session-start-dispatch.sh — ONE SessionStart registration for the nine non-gating hooks that print
# context or an operator banner (fix row 17, docs/research/concurrency-scale-2026-10-04/README.md).
#
# WHY. Every session start, /clear and compact fired 18 SessionStart hooks, each its own harness spawn,
# JSON parse and attachment; the multi-hook startup span measured p50 2.9 s, p95 10.1 s, max 35.5 s
# (j-startup-hang.md). Migration 0056 regroups them by what each one owes the session:
#   · 5 pure side-effect hooks (nothing Claude reads) become "async": true, off the critical path.
#   · these 9 fold into this one process, which runs them in PARALLEL (as the harness did) and merges
#     their outputs into one additionalContext and one systemMessage, so turn-1 delivery is kept.
#   · 4 stay separate and sync: dod-persist, desk-brief-inject and mailbox-drain are gating and large
#     (merged, they would share and blow the harness's 10,000-character per-hook context cap), and
#     mailbox-wake-arm is already asyncRewake.
# The banner hooks may NOT go async: an async hook's systemMessage reaches the model as context and the
# terminal hides it, the reverse of the channel they chose (accounts-board.sh's channel proof).
#
# V2: PRINT BY A DEADLINE, LET LATE CHILDREN FINISH, FAIL LOUD, MEASURE (README rows #2 #11 #14 #19,
# docs/research/startup-hooks-2026-10-18/; spec A3-dispatcher.md §4 as its skeptic corrected it).
# v1 killed an overdue child 9 s after SPAWN and printed only once every child was gone, so a slow
# dispatcher could lose its WHOLE output to the harness timeout (4 of 7 runs over 12 s) and a killed
# child vanished without a word (~80 kills in 2 days, every one silent).
#   · DEADLINE. A watchdog sends SIGUSR1 at CC_SSD_EMIT_S (9 s) from PROCESS start, read once from
#     `ps -o etime=` so a slow exec counts against it. A trapped signal makes a blocking `wait` return
#     (bash 3.2 included, its man page :2256); the parent merges whatever finished and prints. 9 s is
#     v1's de-facto bound made honest: 7 s would make 7.4% of healthy runs partial (skeptic R4).
#   · LATE. An overdue child is no longer killed at the deadline. It runs on with every fd off the
#     harness pipe, and the watchdog becomes its collector: TERM to its group at CC_SSD_LATE_S (60 s
#     from process start), KILL 2 s later, then one late ledger row per child and a late outbox.
#   · LOUD. Each path that used to exit silently prints a static systemMessage naming the check
#     (loud). The merge (hooks/lib/ssd-merge.jq, which holds the child table) names each late, killed,
#     cut, absent or malformed child FIRST in the systemMessage, with its recovery command, and gives
#     the model one line only for a missing MODEL-FACING child. A healthy run prints v1's exact bytes.
#   · MEASURED. One ledger row per run (CC_SSD_LEDGER): per child ms from one `stat` of the rc files'
#     ns mtimes (bash 3.2 has no EPOCHREALTIME), rc and state.
#
# FILES, all under CC_SSD_SPOOL (not $TMPDIR, and not inside $T, which the EXIT trap deletes):
#   run.XXXXXX/            $T, the work dir; handed to the late collector when any child is late
#   outbox/<sid>.<src>.json the exact printed line, written BEFORE the print, because a harness cancel
#                          drops stdout (the TERM trap writes a partial one); a later unit re-prints it
#   late/<sid>.json        what late children said, for the same re-print
#
# CHILD CONTRACT, unchanged. Each child gets the same stdin payload. `$PPID` would now name this
# dispatcher, so CC_HOOK_PARENT_PID carries the claude pid; the two children that read their parent
# (session-start.sh, accounts-board.sh) prefer it. Stdout that is a JSON object contributes its
# hookSpecificOutput.additionalContext and systemMessage; any other stdout is plain context, which is how
# the harness reads a plain-text SessionStart hook. Children's stderr is kept out of the output, as the
# harness did for an exit-0 hook.
#
# Env seams (tests): CC_SSD_HOOK_DIR · CC_SSD_CHILDREN (space-separated) · CC_SSD_EMIT_S · CC_SSD_LATE_S
# · CC_SSD_CAP · CC_SSD_SMCAP · CC_SSD_LEDGER · CC_SSD_SPOOL
set -uo pipefail
set -m        # job control: each background child leads its own process group, so the backstop can kill it whole
exec 2>/dev/null   # with job control on, bash reports killed jobs on stderr; the harness needs none of it

HERE="${BASH_SOURCE[0]%/*}"; [ "$HERE" = "${BASH_SOURCE[0]}" ] && HERE=.
DIR="${CC_SSD_HOOK_DIR:-$HERE}"
MERGE="$HERE/lib/ssd-merge.jq"
# recycle-failed-inject.sh (RECYCLE_KEYSTROKELESS_DELIVERY §D4) is a TENTH child, added after
# migration 0056, so it needed no settings.json edit. It is FIRST, and tier 0 in the merge's table:
# a failed recycle's recovery packet must never be the context that gets cut. lever-arm-start.sh (the
# usage levers' session stamp, USAGE_LEVERS.md § W7+ §3) is an ELEVENTH, likewise with no settings
# edit; it prints nothing, so it is tier 3 and last.
CHILDREN="${CC_SSD_CHILDREN:-recycle-failed-inject.sh session-start.sh setup-plan-symlinks.sh setup-task-symlinks.sh activation-watch.sh escalation-watch.sh accounts-board.sh session-index-start.sh config-mirror-assert.sh frontier-status.sh lever-arm-start.sh}"
EMIT="${CC_SSD_EMIT_S:-9}"
LATE="${CC_SSD_LATE_S:-60}"
CAP="${CC_SSD_CAP:-9500}"
SMCAP="${CC_SSD_SMCAP:-9000}"   # under the harness's 10,000-char preview threshold for systemMessage
LEDGER="${CC_SSD_LEDGER:-$HOME/.claude/logs/session-start-dispatch.jsonl}"
SPOOL="${CC_SSD_SPOOL:-$HOME/.claude/state/ssd}"
case "$EMIT" in ''|*[!0-9]*|0) EMIT=9 ;; esac
case "$LATE" in ''|*[!0-9]*) LATE=60 ;; esac
[ "$LATE" -lt "$EMIT" ] && LATE=$EMIT          # the backstop never fires before the deadline
case "$CAP" in ''|*[!0-9]*) CAP=9500 ;; esac
case "$SMCAP" in ''|*[!0-9]*) SMCAP=9000 ;; esac

# Whole seconds this process has already lived (a slow exec under load) come off the deadline: one fork.
lag=$(ps -o etime= -p $$ 2>/dev/null); lag=${lag//[[:space:]]/}
case "$lag" in
  [0-9][0-9]:[0-9][0-9]) lag=$((10#${lag%%:*} * 60 + 10#${lag#*:})) ;;
  *-*|*:*:*) lag=$EMIT ;;                      # over an hour old: emit at once
  *) lag=0 ;;
esac

SID=""; SRC=""; T=""; all=""; map=""; wd=""; L1=""
ledger_raw() { { [ -d "${LEDGER%/*}" ] || mkdir -p "${LEDGER%/*}"; printf '%s\n' "$1" >> "$LEDGER"; } 2>/dev/null; }

# The jq-free fail path (A3 §4.3 F3): static, valid JSON naming the check, then exit 0. The text is
# fixed ASCII plus paths, and quotes, backslashes and control characters are replaced so a path
# cannot break the JSON.
loud() { # <code> <message>
  local m="${2//[\"\\]/_}"; m="${m//[[:cntrl:]]/_}"
  command -v ss_owed >/dev/null 2>&1 && ss_owed $(( ${#m} + 48 ))
  printf '{"systemMessage":"⚠ session-start-dispatch: %s"}\n' "$m"
  ledger_raw "{\"v\":1,\"kind\":\"loud\",\"sid\":\"$SID\",\"src\":\"$SRC\",\"pid\":$$,\"why\":\"$1\"}"
  exit 0
}

# ── STARTUP HEALTH (README §5 units 3.1 and 3.6). The dispatcher's board is the outbox below; the
# startup-health reader (hooks/lib/startup-health.sh, bin/cc-startup-health) finds it through a link
# in the session's sentinel dir, and the two places a start loses output after the print decision —
# the TERM trap and the late collector — leave a line in the rolling idle-pane alert file
# (hooks/lib/startup-alert.sh), which README #13a's FileChanged push reads once the operator applies it.
SH_R="${CC_STARTUP_HEALTH_DIR:-$HOME/.claude/state/startup-health}"
ssd_outbox_link() { # <outbox file> — point "$SH_R/<sid>/outbox.txt" at this start's board
  case "$SID" in ''|*[!0-9A-Za-z-]*) return 0 ;; esac
  [ -d "$SH_R/$SID" ] && [ -f "$1" ] && ln -sf "$1" "$SH_R/$SID/outbox.txt" 2>/dev/null
  return 0
}
ssd_alert_hook() { # <harness-term|late> <sid> <child names>
  case "${2:-}" in ''|*[!0-9A-Za-z-]*) return 0 ;; esac
  [ -f "$HERE/lib/startup-alert.sh" ] || return 0
  # shellcheck source=lib/startup-alert.sh disable=SC1091  # runtime-resolved beside this file
  . "$HERE/lib/startup-alert.sh" 2>/dev/null || return 0
  case "$1" in
    harness-term)
      ssd_outbox_link "$SPOOL/outbox/$2.${SRC:-nosrc}.json"
      sa_alert "$2" "⚠ startup: session-start-dispatch may not have delivered (cancelled by Claude Code; still running: ${3:-none}) — confirming" ;;
    late)
      [ -n "${3:-}" ] && sa_alert "$2" "⚠ startup: session-start-dispatch children finished late (${3}) — their output missed the startup board · cc-startup-health $2" ;;
  esac
  return 0
}

[ -d "$SPOOL" ] || mkdir -p "$SPOOL" 2>/dev/null
T="$(mktemp -d "$SPOOL/run.XXXXXX" 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/ssd.XXXXXX" 2>/dev/null)" \
  || loud mktemp "could not create a work dir under $SPOOL or ${TMPDIR:-/tmp}, so every startup hook was SKIPPED this start (board, notices, Plans/Tasks/MCP lines). Check: df -h ~ ; ls -ld $SPOOL"
# shellcheck disable=SC2329  # both run from a trap
cleanup() { # a late child ⇒ the collector owns $T and removes it
  local rc=$?
  [ -e "$T/late" ] || rm -rf "$T"
  command -v ss_end >/dev/null 2>&1 && ss_end "$rc"
}
trap cleanup EXIT

# The harness cancels a hook at its timeout. Leave a harness-term ledger row and a partial outbox
# (unless the real one is already written), and hand any still-running child to the collector.
# shellcheck disable=SC2329
term_now() {
  trap '' TERM USR1
  : > "$T/emit"                                # stops the watchdog signalling a pid that is about to go
  local e n r p c fin="" pend="" pn="" late="" printed=false
  [ -n "$L1" ] && printed=true
  for e in $all; do
    n=${e%%:*}; r=${e#*:}; p=${r%%:*}; c=${r#*:}; c=${c//[\"\\[:cntrl:]]/_}
    [ "$p" = - ] && continue
    if [ -e "$T/r$n" ]; then fin="$fin,\"$c\""; else pend="$pend,\"$c\""; pn="$pn $c"; late="$late$e"$'\n'; fi
  done
  ledger_raw "{\"v\":1,\"kind\":\"harness-term\",\"sid\":\"$SID\",\"src\":\"$SRC\",\"pid\":$$,\"at_s\":$((SECONDS)),\"printed\":$printed,\"finished\":[${fin#,}],\"pending\":[${pend#,}]}"
  if [ -z "$L1" ]; then
    [ -d "$SPOOL/outbox" ] || mkdir -p "$SPOOL/outbox"
    printf '{"systemMessage":"⚠ session-start-dispatch: cancelled by Claude Code at %ss before printing; the merged startup output was lost this start. Still running: %s"}\n' \
      "$SECONDS" "${pn# }" > "$SPOOL/outbox/${SID:-nosid}.${SRC:-nosrc}.json"
  fi
  if [ -n "$late" ] && [ -n "$wd" ]; then printf '%s' "$late" > "$T/late"; else [ -z "$wd" ] || kill -TERM -- "-$wd"; fi
  ssd_alert_hook harness-term "$SID" "${pn# }"
  command -v ss_end >/dev/null 2>&1 && ss_end 143   # this trap exits 0; the sentinel records the TERM
  exit 0
}
trap term_now TERM

: > "$T/t0"                                    # its mtime is t0 for every child's ms
if [ -e /dev/fd/0 ]; then cat > "$T/payload" 2>/dev/null || :; else : > "$T/payload"; fi
PL=""; IFS= read -r -d '' PL < "$T/payload" || :
re='"session_id"[[:space:]]*:[[:space:]]*"([^"]*)"'; [[ $PL =~ $re ]] && SID=${BASH_REMATCH[1]}
re='"source"[[:space:]]*:[[:space:]]*"([^"]*)"'; [[ $PL =~ $re ]] && SRC=${BASH_REMATCH[1]}
SID=${SID//[!A-Za-z0-9._-]/_}; SRC=${SRC//[!A-Za-z0-9._-]/_}
# Start/done markers (hooks/lib/startup-sentinel.sh, README §5 unit 3.1). --no-trap: cleanup and
# term_now above own EXIT and TERM, and call ss_end themselves. 12000 ms = the registration timeout
# (migration 0068 raises it to 20 s; CC_SSD_REG_TIMEOUT_MS follows it).
TPATH=""; re='"transcript_path"[[:space:]]*:[[:space:]]*"([^"]*)"'; [[ $PL =~ $re ]] && TPATH=${BASH_REMATCH[1]}
if [ -f "$HERE/lib/startup-sentinel.sh" ]; then
  # shellcheck source=lib/startup-sentinel.sh disable=SC1091  # runtime-resolved beside this file
  . "$HERE/lib/startup-sentinel.sh" 2>/dev/null \
    && ss_begin --no-trap session-start-dispatch "${CC_SSD_REG_TIMEOUT_MS:-12000}" "$SID" "$TPATH"
fi

export CC_HOOK_PARENT_PID="${CC_HOOK_PARENT_PID:-$PPID}"

# One wrapper per child: the rc file's mtime is the child's end time, and all three fds leave the
# harness pipe, so a late child can never hold the dispatcher's stdout open. Each child runs through
# its own #! interpreter, not by path: ten by-path #! execs per session start each keep ~1.1 KiB of
# kernel memory on macOS 15.8.1 (KALLOC_TRIGGER_ELIMINATION W4, scripts/lib/cc-run.sh; fail-open).
# shellcheck source=../scripts/lib/cc-run.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if [ -f "$HERE/../scripts/lib/cc-run.sh" ]; then . "$HERE/../scripts/lib/cc-run.sh"; else cc_run() { "$@"; }; fi
i=0; n=""
for c in $CHILDREN; do
  i=$((i + 1)); printf -v n '%02d' "$i"
  if [ ! -x "$DIR/$c" ]; then all="$all $n:-:$c"; continue; fi
  ( cc_run "$DIR/$c" < "$T/payload" > "$T/o$n" 2> "$T/e$n"; echo $? > "$T/r$n" ) </dev/null >/dev/null 2>&1 &
  all="$all $n:$!:$c"; map="$map $n:$!:$c"
done
[ -n "$map" ] || loud none "none of the startup hooks in this dispatcher is installed and executable in $DIR, so the board, notices and Plans/Tasks/MCP lines are missing. Re-run: bash ~/Development/claude-infrastructure/install.sh"

# The watchdog: phase 1 is the deadline, phase 2 the late collector. It inherits $T, $map and $lag.
watchdog() { # <budget-s>
  local t e n p c rc a left="" out rows names=""; local -a ra
  sleep "$1"; [ -e "$T/emit" ] || kill -USR1 $$
  t=$((lag + $1))
  while :; do
    [ -d "$T" ] || exit 0                      # the parent finished with nothing late and cleaned up
    # Re-signal until the parent has left its wait loop: a USR1 landing between its DEADLINE test
    # and its next `wait` would otherwise be absorbed with the wait still blocking.
    [ -e "$T/emit" ] || kill -USR1 $$
    a=1; for e in $map; do n=${e%%:*}; [ -e "$T/r$n" ] || { a=0; break; }; done
    if [ "$a" = 1 ]; then kill -0 $$ || break; fi
    [ "$t" -ge "$LATE" ] && break
    sleep 1; t=$((t + 1))
  done
  for e in $map; do
    n=${e%%:*}; p=${e#*:}; p=${p%%:*}
    [ -e "$T/r$n" ] && continue
    kill -TERM -- "-$p"; left="$left $p"
  done
  if [ -n "$left" ]; then sleep 2; for p in $left; do kill -KILL -- "-$p"; done; fi
  t=0; while kill -0 $$ && [ "$t" -lt 10 ]; do sleep 1; t=$((t + 1)); done
  [ -e "$T/late" ] || exit 0
  ra=(); : > "$T/lstatus"
  while IFS=: read -r n p c; do
    [ -n "$n" ] || continue
    if [ -e "$T/r$n" ]; then rc=""; read -r rc < "$T/r$n"; printf '%s\t%s\tdone\t%s\n' "$n" "$c" "${rc:--}"
    else printf '%s\t%s\tkilled\t-\n' "$n" "$c"; fi
    names="$names $c"
    [ -e "$T/o$n" ] && ra+=(--rawfile "o$n" "$T/o$n")
  done < "$T/late" >> "$T/lstatus"
  stat -f '%Fm %N' "$T/t0" "$T"/r[0-9]* > "$T/times"
  if command -v jq >/dev/null && [ -f "$MERGE" ]; then
    out="$(merge late "$T/lstatus" ${ra[@]+"${ra[@]}"})"
    rows=${out#*$'\n'}; [ "$rows" = "$out" ] && rows=""
    [ -n "$rows" ] && ledger_raw "$rows"
    if [ -n "$out" ] && [ "${out%%$'\n'*}" != null ]; then
      [ -d "$SPOOL/late" ] || mkdir -p "$SPOOL/late"
      printf '%s\n' "${out%%$'\n'*}" > "$SPOOL/late/${SID:-nosid}.json"
    fi
  fi
  ssd_alert_hook late "$SID" "${names# }"
  rm -rf "$T"
}

merge() { # <main|late> <status file> [--rawfile oNN file]...
  local mode=$1 st=$2; shift 2
  jq -nc -f "$MERGE" --arg mode "$mode" --arg sid "$SID" --arg src "$SRC" \
    --arg cfg "$CFG" --arg ledger "$LEDGER" --arg home "$HOME" --arg dir "$DIR" \
    --argjson cap "$CAP" --argjson smcap "$SMCAP" --argjson emit "$EMIT" --argjson late "$LATE" \
    --argjson lag "$lag" --argjson pid $$ --argjson ppid "$PP" \
    --rawfile status "$st" --rawfile times "$T/times" "$@"
}
PP="$CC_HOOK_PARENT_PID"; case "$PP" in ''|*[!0-9]*) PP=0 ;; esac
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; CFG="${CFG%/}"; CFG="${CFG##*/}"

DEADLINE=0; trap 'DEADLINE=1' USR1
budget=$((EMIT - lag)); [ "$budget" -lt 1 ] && budget=1
watchdog "$budget" </dev/null >/dev/null 2>&1 &
wd=$!
for e in $map; do
  [ "$DEADLINE" = 1 ] && break
  p=${e#*:}; p=${p%%:*}
  wait "$p"
done
: > "$T/emit"

# Registration order, absent children included. Only a finished child's stdout reaches the merge.
late=""; args=()
for e in $all; do
  n=${e%%:*}; r=${e#*:}; p=${r%%:*}; c=${r#*:}
  if [ "$p" = - ]; then printf '%s\t%s\tabsent\t-\n' "$n" "$c"
  elif [ -e "$T/r$n" ]; then
    rc=""; read -r rc < "$T/r$n"; printf '%s\t%s\tdone\t%s\n' "$n" "$c" "${rc:--}"
    args+=(--rawfile "o$n" "$T/o$n")
  else printf '%s\t%s\tlate\t-\n' "$n" "$c"; late="$late$e"$'\n'
  fi
done > "$T/status"
if [ -z "$late" ]; then kill -TERM -- "-$wd"; else printf '%s' "$late" > "$T/late"; fi

command -v jq >/dev/null 2>&1 || loud nojq "jq is not on PATH, so the merged startup output (board, notices, Plans/Tasks/MCP lines) was DROPPED this start; the hooks themselves ran. Fix: brew install jq"
[ -f "$MERGE" ] || loud nomerge "the merge program $MERGE is missing, so the merged startup output was DROPPED this start; the hooks themselves ran. Re-run: bash ~/Development/claude-infrastructure/install.sh"
stat -f '%Fm %N' "$T/t0" "$T"/r[0-9]* > "$T/times"
OUT="$(merge main "$T/status" ${args[@]+"${args[@]}"})" || OUT=""
[ -n "$OUT" ] || loud jqfail "the jq merge (hooks/lib/ssd-merge.jq) failed, so the merged startup output was DROPPED this start; the hooks themselves ran. Log: $LEDGER"
L1=${OUT%%$'\n'*}; ROW=${OUT#*$'\n'}; [ "$ROW" = "$OUT" ] && ROW=""

# Outbox, then ledger, then print: a harness that cancels us mid-print still leaves both behind.
OB="$SPOOL/outbox/${SID:-nosid}.${SRC:-nosrc}.json"
if [ "$L1" != null ]; then
  [ -d "$SPOOL/outbox" ] || mkdir -p "$SPOOL/outbox"
  printf '%s\n' "$L1" > "$OB.$$" && mv -f "$OB.$$" "$OB"
  ssd_outbox_link "$OB"
else
  rm -f "$OB"; L1=""
fi
[ -n "$ROW" ] && ledger_raw "$ROW"
if [ -n "$L1" ]; then
  command -v ss_owed >/dev/null 2>&1 && ss_owed $(( ${#L1} + 1 ))
  printf '%s\n' "$L1"
fi
exit 0
