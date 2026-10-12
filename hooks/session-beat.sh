#!/bin/bash
# session-beat.sh — the WRITE side of the session presence beat (SESSION_REGISTRY_V2 §4.1).
#
# Wired to UserPromptSubmit and Stop. Writes ONE small durable attestation per turn boundary:
#   ${CC_BEAT_DIR:-$HOME/.claude/cc-beats}/<sid>.json
#   {sid, pane, pid, lstart, t, kind, who, operatorT, seq}
#
# WHY THIS EXISTS. "Who drove the last turn" is the one signal a done-decision cannot fake —
# idle+clean+landed is every live conversation's steady state between prompts (2026-07-24: two live
# operator conversations reaped 12-14 min after their last typed prompt). v1 answered it by
# re-deriving it from the transcript inside every sweep. This hook answers it ONCE, here, at the
# moment the prompt arrives, on the prompt already in hand — no scan, no transcript, no cost that
# grows with history. The reap path then reads it in O(1) and can therefore re-take the reading
# IMMEDIATELY before a close, which is what makes the ≤60s freshness contract structural.
#
# THE `who` PREDICATE — kept semantically identical to hooks/lib/cc-interactive.sh so the write-time
# and read-time answers agree (acceptance A2). At UserPromptSubmit the tool_result / isMeta cases of
# that predicate cannot arise (this event fires only for a submitted prompt), so the predicate
# reduces to its remaining leg: the AUTO-TRAFFIC regex. That exclusion is load-bearing, not
# cosmetic — our own auto-drive re-prompts (session-continue's Stop-hook feedback, task
# notifications, our ⟳/⚑/⚠ advisories) arrive through this same event, and a presence signal that
# counted its own auto-drive would hold every self-driving session open forever and deadlock every
# recycle. Operator slash-commands DO count: the operator is present.
#
# `operatorT` is a STICKY high-water mark: a later who=auto beat never lowers it. Presence, once
# demonstrated, decays only by the clock — otherwise a Stop beat landing after an operator prompt
# would erase the very evidence that protects the pane.
#
# FAIL-OPEN CONTRACT (inherited verbatim from hooks/session-register.sh:26-32). This runs on EVERY
# prompt of EVERY session. A presence spine that can block, delay or kill a turn inverts its own
# purpose, so ALL slow work happens inside beat(), under a HARD timeout, and this hook ALWAYS exits 0.
# A missing beat degrades the reap decision toward REFUSE (the safe direction, R3) — it must never
# cost a session. Kill switch: CC_BEAT=off.
#
# OFF THE PROMPT PATH (docs/research/load-hook-timeouts-2026-10-11 item 7). The hook pays exactly ONE
# jq start in the foreground — the payload parse, the `who` regex is bash's own `[[ =~ ]]` — and then
# DETACHES beat() and exits. The ancestry walk (two `ps` per hop), the previous-beat read and the
# write all run after the turn has its prompt back. Before, a prompt beat held its turn for six jq
# starts plus up to 24 `ps` (counted from the code), for as long as the machine took to run them, up
# to the 3 s cap. The detach is done in
# bash, NOT with scripts/lib/detach.sh: that helper starts /usr/bin/python3 to call setsid, which
# would put back on every prompt the interpreter start this change exists to remove. `set -m` gives
# the worker its own process GROUP — the property detach.sh's header names, immunity to a group
# SIGKILL of the hook — stdin is /dev/null, output goes to a log, and once this hook exits the worker
# is reparented to launchd, out of any parent-tree walk. `async: true` in settings.json was the other
# way off the path and was rejected: it has no enforced timeout, so slow runs pile up. The worker
# keeps its own HARD timeout instead (P8_TIMEOUT, below, 20 s). The ≤60 s freshness contract still
# holds: the write lands within that bound of the prompt, not at its instant.
#
# bash 3.2-safe. jq required (absent ⇒ silent no-op, same as session-register.sh).
set -uo pipefail

input=$(cat 2>/dev/null)

# The worker's HARD timeout. 3 s while it ran in the foreground, where every second of it was the
# turn's; detached, the bound only has to keep workers from piling up and land the beat inside the
# reader's 60 s freshness window. 20 s does both. A 3 s cap was measured too tight once detached:
# at load ~600 (2026-10-12) tests/session-beat.bats, whose walk climbs a deep bats ancestry, saw 7
# of its detached beats never written within 20 s under the 3 s cap.
P8_TIMEOUT="${CC_BEAT_TIMEOUT:-20}"

[ "${CC_BEAT:-on}" = off ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# kind: explicit arg wins (Stop passes `stop`); default is a prompt beat.
kind="${1:-prompt}"

# ONE jq start for every payload field. Line 1 is "<sid> TAB <cwd>" as @tsv; everything after the
# first newline is the RAW prompt, so the `who` regex sees exactly the text the old per-field
# `jq -r '.prompt'` produced (an @tsv field would arrive with its \t \n \\ escaped).
_parsed=$(printf '%s' "$input" | jq -r '
  ([(.session_id // "" | tostring), (.cwd // "" | tostring)] | @tsv), (.prompt // "" | tostring)' 2>/dev/null)
_head="${_parsed%%$'\n'*}"
prompt=""
case "$_parsed" in *$'\n'*) prompt="${_parsed#*$'\n'}" ;; esac
sid="${_head%%$'\t'*}"
cwd=""
case "$_head" in *$'\t'*) cwd="${_head#*$'\t'}" ;; esac
[ -n "$sid" ] || exit 0
# sid is the IDENTITY key, deliberately NOT the pane: tmux panes inherit the server's
# ITERM_SESSION_ID, so a pane-keyed beat would have N sessions overwrite one row.
case "$sid" in *[!0-9A-Za-z_-]*) exit 0 ;; esac   # path-safety: sid becomes a filename
# Undo @tsv's escaping of the cwd (\\ \t \n \r); 0x02 holds an escaped backslash meanwhile (not
# 0x01, bash's internal CTLESC byte, which mangles inside ${//}).
cwd="${cwd//\\\\/$'\002'}"; cwd="${cwd//\\t/$'\t'}"; cwd="${cwd//\\n/$'\n'}"; cwd="${cwd//\\r/$'\r'}"
cwd="${cwd//$'\002'/\\}"
[ -z "$cwd" ] && cwd="$PWD"

# ── the `who` decision, made here, once ──
# `[[ =~ ]]` (POSIX ERE) agrees with the reader's jq `test` (hooks/lib/cc-interactive.sh) on this
# regex: every alternative is ^-anchored at the string's start, and neither engine treats ^ as a
# line anchor here (measured both on multi-line prompts, 2026-10-11).
who=auto
if [ "$kind" = prompt ]; then
  rx="${CC_CLASSIFY_AUTO_RX:-^<task-notification>|^<local-command-stdout>|^Stop hook feedback:|^\\[Request interrupted|^⟳|^⚑|^⚠|^⛔}"
  if [ -n "$prompt" ] && ! [[ $prompt =~ $rx ]]; then
    who=operator
  fi
fi

beat() {
  local pane dir tmp prev prevOp now seq cpid lstart walk c i lock
  # KITTY_WINDOW_ID last, for the same measured no-address class session-register.sh:127 carries:
  # without it a kitty-hosted session's beat records pane "" while its stop-failure marker records
  # a real pane, and a reader comparing the two sees a disagreement that is purely this gap.
  pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-${KITTY_WINDOW_ID:-}}}"; pane="${pane##*:}"

  now=$(date +%s)

  # Durable claude-ancestor PID + its lstart — identity is (pid,lstart), never pid alone: a
  # RECYCLED pid must not masquerade as this session (the reaper's a17 S-4 pin, now the beat's too).
  #
  # TZ=UTC IS PART OF THE IDENTITY, NOT A FORMATTING PREFERENCE. `ps -o lstart=` renders in the
  # AMBIENT zone, so the stored string is only comparable to a reader that happened to be running in
  # the same zone — and it stops being comparable to its own past self at the next DST flip, which
  # makes every beat on disk read as a DIFFERENT process while the sessions are still alive (memory
  # process-start-time-renders-in-ambient-timezone). Measured 2026-09-08 on 51 live beats: 0 matched
  # a `TZ=UTC` reader and 22 matched an ambient one, i.e. the census was already keyed on a
  # coincidence between two unpinned renderings. Pinning HERE is what makes the field mean the same
  # thing to every reader, in every zone, on both sides of a DST boundary; the reader
  # (scripts/lib/spawn-presence.sh) pins its own sample the same way. `bin/cc-await-ping`'s
  # _pid_ident is the idiom being copied.
  walk="$PPID"; cpid=""; i=0
  while [ -n "$walk" ] && [ "$walk" -gt 1 ] 2>/dev/null && [ "$i" -lt 12 ]; do
    c=$(ps -o comm= -p "$walk" 2>/dev/null); c="${c##*/}"
    case "$c" in claude|claude.exe|claude-*) cpid="$walk"; break ;; esac
    walk=$(ps -o ppid= -p "$walk" 2>/dev/null | tr -d ' ')
    i=$((i + 1))
  done
  [ -z "$cpid" ] && cpid="$PPID"
  lstart=$(TZ=UTC ps -o lstart= -p "$cpid" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')

  dir="${CC_BEAT_DIR:-$HOME/.claude/cc-beats}"
  mkdir -p "$dir" 2>/dev/null || return 0

  # ONE WRITER PER SID AT A TIME. In the foreground the turn itself serialized a session's beats (the
  # prompt beat finished before the turn could reach Stop); detached, a slow prompt worker can still
  # be walking `ps` when the Stop worker starts, and two unserialized read-modify-writes would let the
  # later one write back a STALE operatorT — erasing the presence this file exists to keep. The walk
  # above stays outside the lock; only the short read-modify-write below is inside it. Bounded and
  # self-healing: past 1-2 s the worker proceeds anyway and removes the lock when done, so a worker
  # killed by the HARD timeout while holding it costs its successors one wait, never a beat.
  # The wait is bounded by the CLOCK, not by a try count: at load ~600 each `sleep` fork can take a
  # second; with a 20-try bound the suite's stale-lock beat never landed in 45 s (2026-10-12).
  lock="$dir/.$sid.lock"; i=$SECONDS
  until mkdir "$lock" 2>/dev/null; do
    [ $((SECONDS - i)) -ge 2 ] && break
    sleep 0.1
  done

  # Carry the sticky operator high-water mark and the sequence forward from the previous beat.
  prevOp=""; seq=0
  if [ -f "$dir/$sid.json" ]; then
    prev=$(jq -r '[(.operatorT // ""), (.seq // 0)] | @tsv' "$dir/$sid.json" 2>/dev/null)
    prevOp="${prev%%$'\t'*}"
    seq="${prev#*$'\t'}"
  fi
  case "$seq"   in ''|*[!0-9]*) seq=0 ;; esac
  case "$prevOp" in *[!0-9]*) prevOp="" ;; esac
  seq=$((seq + 1))
  # A high-water mark in fact as well as in name: a worker that took its clock reading before a
  # sibling's later one must not lower the mark that sibling wrote.
  if [ "$who" = operator ] && { [ -z "$prevOp" ] || [ "$now" -gt "$prevOp" ]; }; then prevOp="$now"; fi

  tmp="$dir/.$sid.$$.tmp"
  if jq -n --arg sid "$sid" --arg pane "$pane" --arg cwd "$cwd" --arg kind "$kind" \
          --arg who "$who" --arg lstart "$lstart" --arg opT "$prevOp" \
          --argjson pid "$cpid" --argjson t "$now" --argjson seq "$seq" \
        '{sid:$sid, pane:$pane, cwd:$cwd, pid:$pid, lstart:$lstart, t:$t, kind:$kind, who:$who,
          operatorT:(if $opT=="" then null else ($opT|tonumber) end), seq:$seq}' \
        > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$dir/$sid.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  rmdir "$lock" 2>/dev/null
  return 0
}

# The worker: beat() under its HARD timeout, in its own process group, stdin /dev/null, output to a
# log (see OFF THE PROMPT PATH above). The hook returns as soon as the worker is forked; nothing the
# worker does can hold this hook's stdout pipe open, so the harness reads EOF at once.
_log="${CC_BEAT_LOG:-$HOME/.claude/logs/session-beat.log}"
[ -d "${_log%/*}" ] || mkdir -p "${_log%/*}" 2>/dev/null || _log=/dev/null
set -m
(
  set +m
  beat >/dev/null 2>&1 &
  _w=$!
  ( sleep "$P8_TIMEOUT"; kill -9 "$_w" 2>/dev/null ) >/dev/null 2>&1 &
  _k=$!
  wait "$_w" >/dev/null 2>&1
  kill -9 "$_k" >/dev/null 2>&1
  wait "$_k" >/dev/null 2>&1
) </dev/null >>"$_log" 2>&1 &
exit 0
