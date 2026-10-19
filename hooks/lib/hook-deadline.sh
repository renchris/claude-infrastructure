#!/usr/bin/env bash
# hook-deadline.sh — a deadline for Stop-chain RENDERERS: speak before the harness kills you, and
# deliver the late result at the session's next boundary instead of losing it.
#
# WHY (docs/research/startup-hooks-2026-10-18/README.md §2 row #27; A9-beyond-startup.md R6 as
# amended by A9-F6): operator-readout (Stop, 10 s) and teammate-auto-shutdown (TeammateIdle, 5 s)
# are each cancelled on ~46% of runs under load, ~650-770 kills per 48 h. A cancelled renderer is
# SIGKILLed mid-work and its output is discarded: the close block never shows, and a teammate reap
# can die between its checkpoint and its pane close. Nothing records that it was lost.
#
# WHAT it does. A hook sources this lib and calls `hd_wrap <name> <deadline-s> <notice> "$@"` before
# it reads stdin. The wrapper reads the payload, re-runs the hook's own file as the BODY in a job of
# its own process group (set -m, the session-beat.sh worker idiom), and waits on a process-
# substitution pipe with bash 3.2's integer `read -t` — no sleep loop, no fork per tick.
#   in time   the body's stdout, stderr and exit code are relayed BYTE-IDENTICALLY. Cost: one bash
#             start for the wrapper, two subshells and one `rm` (measured in tests/hook-deadline.bats).
#   late      the wrapper exits 0 at the deadline, so the harness has nothing to kill. With notice=on
#             it prints one systemMessage saying the block is deferred (an operator line, never
#             additionalContext — that would force a turn). The body keeps running in its own process
#             group under a hard bound (CC_HD_HARD_S, default 120 s) and, when it finishes, files its
#             systemMessage as a per-session PENDING file. The next boundary prints it exactly once:
#               · the next UserPromptSubmit — session-beat.sh's synchronous front (hd_take_pending);
#               · or, when no prompt comes first, this hook's own next run: a fresh non-empty render
#                 supersedes the pending one (newer truth); an empty fresh render (the body's damping
#                 latch, which the late run already advanced) or another late run prints the pending.
#             A body with no systemMessage (teammate-auto-shutdown's `{"continue": false}`) files
#             nothing: its late result is the side effect it was allowed to finish — DESIGN.md:230
#             admits detached bodies for side-effect hooks with their own deadline, which this is.
#   busy      a previous late body for the same (hook, session) is still running ⇒ exit 0 without
#             starting another: single-flight, so detached bodies cannot pile up.
#
# The atomic arbiter is ONE noclobber create (`set -C`) of the run's claim file — a builtin. The body
# writes `done <rc>` when it finishes, the wrapper writes `late` at its deadline; whoever creates the
# file first decides. A body that wins `done` but finds its wrapper already dead (the harness killed it
# before the deadline, e.g. spawn lag under load) files its result as pending too.
#
# NOT for verdict gates: a gate's late verdict is stale, and DESIGN.md:230 refuses detached gates.
#
# Env: CC_HOOK_DEADLINE=on|off (default on; default OFF when BATS_TEST_FILENAME is set, so a suite
#        that is not about deadlines never becomes a timing test under load — tests/hook-deadline.bats
#        sets it on) · CC_HOOK_DEADLINE_DIR (default $HOME/.claude/state/hook-deadline) ·
#        CC_HD_HARD_S (default 120) · CC_IDL (rows: hook "hook-deadline", only on non-healthy paths).
# bash 3.2-safe: no $BASHPID, no ${var,,}, no fractional read -t. Healthy paths write no IDL row.

hd_excl() { # <file> <content> → rc 0 iff THIS call created <file> (noclobber; builtin, atomic)
  local was=0 rc
  case "$-" in *C*) was=1 ;; esac
  set -C
  { printf '%s\n' "$2" > "$1"; } 2>/dev/null
  rc=$?
  [ "$was" = 1 ] || set +C
  return "$rc"
}

hd_json_esc() { # <string> → HD_J, a JSON-string-safe body
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"; s="${s//$'\033'/\\u001b}"
  HD_J="$s"
}

hd_idl() { # <sid> <disposition> <reason> [extra-json] — unhealthy paths only (forks jq + date)
  local _hl="${BASH_SOURCE[0]%/*}/idl-log.sh"
  # shellcheck source=idl-log.sh disable=SC1091  # runtime-resolved beside this file
  [ -f "$_hl" ] && . "$_hl" 2>/dev/null || return 0
  # shellcheck disable=SC2034  # read by idl-log.sh through the variable NAME passed below
  HD_SID="$1"
  idl_init "${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}" "hook-deadline" HD_SID
  log_idl "$2" "$3" "${4:-}"
}

# hd_take_pending <pending-dir> <sid> → HD_SYS = every pending late result of <sid>, claimed (moved)
# first so a second reader can never print it again. Called only after a glob proved one exists.
hd_take_pending() {
  local d="$1" sid="$2" f t m="" from
  HD_SYS=""
  for f in "$d/$sid".*.msg; do
    [ -e "$f" ] || continue
    t="$f.taking.$$"
    mv "$f" "$t" 2>/dev/null || continue
    m=""
    IFS= read -r -d '' m < "$t" || :
    rm -f "$t"
    [ -n "$m" ] || continue
    HD_SYS="${HD_SYS:+$HD_SYS$'\n'}$m"
    from="${f##*/}"; from="${from#"$sid".}"; from="${from%.msg}"
    hd_idl "$sid" delivered "late-result:prompt" "{\"from\":\"$from\"}"
  done
  return 0
}

# _hd_body — the detached job: run the hook's own file as the body, then settle the claim.
_hd_body() { # <name> <sid> <run-prefix> <pending-dir> <wrapper-pid> <self> <args…>
  local name="$1" sid="$2" r="$3" pdir="$4" wpid="$5" self="$6" rc ipid tag="done" msg="" hdr
  shift 6
  SECONDS=0
  CC_HD_INNER="$name" CC_HD_PIDFILE="$r.pid" "${BASH:-/bin/bash}" "$self" "$@" \
    < "$r.in" > "$r.out" 2> "$r.err" &
  ipid=$!
  wait "$ipid"; rc=$?
  if hd_excl "$r.claim" "done $rc"; then
    # In time, and the wrapper is alive to relay it: the wrapper cleans up.
    kill -0 "$wpid" 2>/dev/null && return 0
    tag=orphaned   # the wrapper died before reading it (killed by the harness) — file it anyway
  else
    tag=late
  fi
  if [ "$sid" != nosid ] && [ -s "$r.out" ] && command -v jq >/dev/null 2>&1; then
    msg="$(jq -r '.systemMessage // empty' < "$r.out" 2>/dev/null)"
  fi
  if [ -n "$msg" ]; then
    hdr="↻ $name finished late (${SECONDS}s) — its result from the last stop:"
    printf '%s\n%s' "$hdr" "$msg" > "$pdir/$sid.$name.msg.tmp.$ipid" 2>/dev/null \
      && mv -f "$pdir/$sid.$name.msg.tmp.$ipid" "$pdir/$sid.$name.msg" 2>/dev/null
  fi
  hd_idl "$sid" "late-done" "$name:$tag" \
    "{\"rc\":$rc,\"secs\":$SECONDS,\"pending\":$([ -n "$msg" ] && echo true || echo false)}"
  rm -f "$r.in" "$r.out" "$r.err" "$r.claim" "$r.pid"
  return 0
}

# hd_wrap <name> <deadline-s> <notice:on|off> [hook args…]
# Returns 0 ONLY when the caller should run its body inline (it IS the body, or the wrapper is off);
# otherwise it relays the body's result and EXITS the hook.
hd_wrap() {
  if [ "${CC_HD_INNER:-}" = "$1" ]; then
    [ -n "${CC_HD_PIDFILE:-}" ] && { printf '%s\n' "$$" > "$CC_HD_PIDFILE"; } 2>/dev/null
    unset CC_HD_INNER CC_HD_PIDFILE
    return 0
  fi
  local mode="${CC_HOOK_DEADLINE:-}"
  if [ -z "$mode" ]; then mode=on; [ -n "${BATS_TEST_FILENAME:-}" ] && mode=off; fi
  [ "$mode" = on ] || return 0
  local name="$1" dl="$2" notice="$3"
  case "$dl" in ''|0|*[!0-9]*) return 0 ;; esac
  case "$name" in ''|*[!A-Za-z0-9_-]*) return 0 ;; esac
  shift 3
  local base="${CC_HOOK_DEADLINE_DIR:-$HOME/.claude/state/hook-deadline}"
  local run="$base/run" pdir="$base/pending"
  { [ -d "$run" ] && [ -d "$pdir" ]; } || mkdir -p "$run" "$pdir" 2>/dev/null || return 0

  # ── from here stdin is consumed: never return to the caller ──
  local in="" sid f p
  IFS= read -r -d '' in || :
  sid="${in#*\"session_id\"}"
  if [ "$sid" = "$in" ]; then sid=""; else sid="${sid#*\"}"; sid="${sid%%\"*}"; fi
  case "$sid" in ''|*[!0-9A-Za-z_-]*) sid=nosid ;; esac

  # single-flight: a previous late body of this (hook, session) still running ⇒ start nothing.
  for f in "$run/$name.$sid".*.pid; do
    [ -e "$f" ] || continue
    p=""; read -r p < "$f" 2>/dev/null
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
      hd_idl "$sid" busy "$name:single-flight" "{\"pid\":$p}"
      [ "$notice" = on ] && printf '{"systemMessage":"%s still rendering the previous stop under load — it will show at your next prompt"}\n' "$name"
      exit 0
    fi
  done

  local r="$run/$name.$sid.$$" tag="" rc=0 out="" err="" pend="$pdir/$sid.$name.msg"
  printf '%s' "$in" > "$r.in" 2>/dev/null || { CC_HD_INNER="$name" "${BASH:-/bin/bash}" "$0" "$@" <<< "$in"; exit $?; }
  exec 7< <(
    exec 2>/dev/null
    set -m
    ( set +m; _hd_body "$name" "$sid" "$r" "$pdir" "$$" "$0" "$@" ) </dev/null >/dev/null 2>&1 &
    wait "$!"
    printf 'x\n'
  )
  IFS= read -r -t "$dl" -u 7 _ || :   # a wake-up, or the deadline; the claim below decides
  exec 7<&-

  if hd_excl "$r.claim" late; then
    # ── LATE: the body keeps running in its own process group; bound it, say so, leave. ──
    p=""; read -r p < "$r.pid" 2>/dev/null
    case "$p" in ''|*[!0-9]*) : ;; *)
      set -m
      ( set +m; sleep "${CC_HD_HARD_S:-120}"
        q=""; read -r q < "$r.pid" 2>/dev/null; [ "$q" = "$p" ] && kill -TERM "$p" ) </dev/null >/dev/null 2>&1 &
      set +m ;;
    esac
    hd_idl "$sid" deferred "$name:deadline" "{\"deadline_s\":$dl}"
    if [ "$notice" = on ]; then
      local m="$name deferred under load (${dl}s) — its result will show at your next prompt"
      if [ -e "$pend" ] && mv "$pend" "$pend.taking.$$" 2>/dev/null; then
        IFS= read -r -d '' out < "$pend.taking.$$" || :
        rm -f "$pend.taking.$$"
        [ -n "$out" ] && { m="$out"$'\n'"$m"; hd_idl "$sid" delivered "late-result:stop" "{\"from\":\"$name\"}"; }
      fi
      hd_json_esc "$m"; printf '{"systemMessage":"%s"}\n' "$HD_J"
    fi
    exit 0
  fi

  # ── IN TIME: relay the body byte-identically. ──
  read -r tag rc < "$r.claim" 2>/dev/null
  case "$rc" in ''|*[!0-9]*) rc=0 ;; esac
  IFS= read -r -d '' out < "$r.out" || :
  IFS= read -r -d '' err < "$r.err" || :
  rm -f "$r.in" "$r.out" "$r.err" "$r.claim" "$r.pid"
  # A late result still pending meets this hook's own next run (no prompt came in between).
  if [ -e "$pend" ] && mv "$pend" "$pend.taking.$$" 2>/dev/null; then
    if [ -n "$out" ]; then
      hd_idl "$sid" superseded "late-result:$name"   # a fresh render is the newer truth
    else
      local m=""; IFS= read -r -d '' m < "$pend.taking.$$" || :
      [ -n "$m" ] && { hd_json_esc "$m"; out="{\"systemMessage\":\"$HD_J\"}"$'\n'
        hd_idl "$sid" delivered "late-result:stop" "{\"from\":\"$name\"}"; }
    fi
    rm -f "$pend.taking.$$"
  fi
  [ -n "$err" ] && printf '%s' "$err" >&2
  printf '%s' "$out"
  exit "$rc"
}
