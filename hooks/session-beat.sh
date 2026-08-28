#!/bin/bash
# session-beat.sh — the WRITE side of the session presence beat (SESSION_REGISTRY_V2 §4.1).
#
# Wired to UserPromptSubmit and Stop. Writes ONE small durable attestation per turn boundary:
#   ${CC_BEAT_DIR:-$HOME/.claude/cc-beats}/<sid>.json
#   {sid, pane, pid, lstart, t, kind, who, operatorT, seq, wakeSeq}
#
# TWO COUNTERS, because "a boundary happened" and "this session was woken" are different questions
# and only one of them can be answered by counting boundaries. `seq` is every prompt AND every stop.
# `wakeSeq` counts only prompt beats that came from OUTSIDE this session, so it is flat across a
# stop beat and flat across this session's own Stop-hook self-drive re-prompts. See the WAKE
# decision in beat() for why that distinction is load-bearing (backlog b60eb29e97dd).
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
# purpose, so ALL work happens inside beat(), under a HARD timeout, and this hook ALWAYS exits 0.
# A missing beat degrades the reap decision toward REFUSE (the safe direction, R3) — it must never
# cost a session. Kill switch: CC_BEAT=off.
#
# Env seams: CC_BEAT_DIR · CC_BEAT_TIMEOUT · CC_CLASSIFY_AUTO_RX (the presence predicate) ·
# CC_BEAT_SELFDRIVE_RX (the wake predicate).
#
# bash 3.2-safe. jq required (absent ⇒ silent no-op, same as session-register.sh).
set -uo pipefail

input=$(cat 2>/dev/null)

P8_TIMEOUT="${CC_BEAT_TIMEOUT:-3}"

beat() {
  [ "${CC_BEAT:-on}" = off ] && return 0
  command -v jq >/dev/null 2>&1 || return 0

  local sid cwd pane kind who prompt rx srx dir tmp prev prevOp now seq wake prevWake cpid lstart walk c i
  sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
  [ -n "$sid" ] || return 0
  # sid is the IDENTITY key, deliberately NOT the pane: tmux panes inherit the server's
  # ITERM_SESSION_ID, so a pane-keyed beat would have N sessions overwrite one row.
  case "$sid" in *[!0-9A-Za-z_-]*) return 0 ;; esac   # path-safety: sid becomes a filename

  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
  [ -z "$cwd" ] && cwd="$PWD"
  pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; pane="${pane##*:}"

  # kind: explicit arg wins (Stop passes `stop`); default is a prompt beat.
  kind="${1:-prompt}"

  # ── the `who` decision, made here, once ──
  who=auto
  wake=0
  if [ "$kind" = prompt ]; then
    prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
    rx="${CC_CLASSIFY_AUTO_RX:-^<task-notification>|^<local-command-stdout>|^Stop hook feedback:|^\\[Request interrupted|^⟳|^⚑|^⚠}"
    if [ -n "$prompt" ] && ! printf '%s' "$prompt" | jq -Rs --arg rx "$rx" -e 'test($rx)' >/dev/null 2>&1; then
      who=operator
    fi
    # ── the WAKE decision — a SECOND predicate over the same prompt, and deliberately NOT `who` ──
    # `who` answers "is a human present" (presence, for the reaper). This answers a different
    # question, for `cc-await-ping --idle-scoped`: "did something OUTSIDE this session hand it new
    # information?" The two disagree on exactly the traffic that matters. A `<task-notification>`
    # (a fired peer reported, a background task finished) and a `[Request interrupted` are who=auto
    # yet ARE wakes — the session was driven from outside. This session's OWN Stop-hook feedback is
    # not: it is the auto-drive continuation of a turn that has not ended, and counting it as a wake
    # is precisely the defect this field exists to close (backlog b60eb29e97dd — the wake floor
    # blocks a Stop to DEMAND the idle-scoped arm, the model arms, and the very next self-drive
    # round then stood the watcher down, making the floor's arm a deterministic no-op).
    #
    # SEPARATE REGEX, NOT A SLICE OF $rx, because the sets are not nested the same way and a shared
    # one would silently re-couple two decisions that must be free to diverge. Fail-open direction:
    # an unreadable prompt counts as a WAKE (stand down early = one bounce turn; the other way costs
    # the goal — the same asymmetry the awaiter's own allowance comment already argues from).
    srx="${CC_BEAT_SELFDRIVE_RX:-^Stop hook feedback:|^⟳|^⚑|^⚠}"
    if [ -n "$prompt" ] && printf '%s' "$prompt" | jq -Rs --arg rx "$srx" -e 'test($rx)' >/dev/null 2>&1; then
      wake=0
    else
      wake=1
    fi
  fi

  now=$(date +%s)

  # Durable claude-ancestor PID + its lstart — identity is (pid,lstart), never pid alone: a
  # RECYCLED pid must not masquerade as this session (the reaper's a17 S-4 pin, now the beat's too).
  walk="$PPID"; cpid=""; i=0
  while [ -n "$walk" ] && [ "$walk" -gt 1 ] 2>/dev/null && [ "$i" -lt 12 ]; do
    c=$(ps -o comm= -p "$walk" 2>/dev/null); c="${c##*/}"
    case "$c" in claude|claude.exe|claude-*) cpid="$walk"; break ;; esac
    walk=$(ps -o ppid= -p "$walk" 2>/dev/null | tr -d ' ')
    i=$((i + 1))
  done
  [ -z "$cpid" ] && cpid="$PPID"
  lstart=$(ps -o lstart= -p "$cpid" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')

  dir="${CC_BEAT_DIR:-$HOME/.claude/cc-beats}"
  mkdir -p "$dir" 2>/dev/null || return 0

  # Carry the sticky operator high-water mark and both counters forward from the previous beat.
  # `seq` counts BOUNDARIES (every prompt and every stop); `wakeSeq` counts WAKES only, so it is
  # flat across a stop beat and across a self-drive re-prompt, and strictly monotone otherwise.
  prevOp=""; seq=0; prevWake=0
  if [ -f "$dir/$sid.json" ]; then
    prev=$(jq -r '[(.operatorT // ""), (.seq // 0), (.wakeSeq // 0)] | @tsv' "$dir/$sid.json" 2>/dev/null)
    prevOp=$(printf '%s' "$prev" | cut -f1)
    seq=$(printf '%s' "$prev" | cut -f2)
    prevWake=$(printf '%s' "$prev" | cut -f3)
  fi
  case "$seq"     in ''|*[!0-9]*) seq=0 ;; esac
  case "$prevOp"  in *[!0-9]*) prevOp="" ;; esac
  case "$prevWake" in ''|*[!0-9]*) prevWake=0 ;; esac
  seq=$((seq + 1))
  wake=$((prevWake + wake))
  [ "$who" = operator ] && prevOp="$now"

  tmp="$dir/.$sid.$$.tmp"
  if jq -n --arg sid "$sid" --arg pane "$pane" --arg cwd "$cwd" --arg kind "$kind" \
          --arg who "$who" --arg lstart "$lstart" --arg opT "$prevOp" \
          --argjson pid "$cpid" --argjson t "$now" --argjson seq "$seq" --argjson wake "$wake" \
        '{sid:$sid, pane:$pane, cwd:$cwd, pid:$pid, lstart:$lstart, t:$t, kind:$kind, who:$who,
          operatorT:(if $opT=="" then null else ($opT|tonumber) end), seq:$seq, wakeSeq:$wake}' \
        > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$dir/$sid.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

beat "${1:-prompt}" >/dev/null 2>&1 &
_w=$!
( sleep "$P8_TIMEOUT"; kill -9 "$_w" 2>/dev/null ) >/dev/null 2>&1 &
_k=$!
wait "$_w" >/dev/null 2>&1
kill -9 "$_k" >/dev/null 2>&1
wait "$_k" >/dev/null 2>&1
exit 0
