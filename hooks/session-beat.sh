#!/bin/bash
# session-beat.sh — the WRITE side of the session presence beat (SESSION_REGISTRY_V2 §4.1).
#
# Wired to UserPromptSubmit and Stop. Writes ONE small durable attestation per turn boundary:
#   ${CC_BEAT_DIR:-$HOME/.claude/cc-beats}/<sid>.json
#   {sid, pane, pid, lstart, t, kind, who, src, operatorT, seq}
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
# bash 3.2-safe. jq required (absent ⇒ silent no-op, same as session-register.sh).
set -uo pipefail

input=$(cat 2>/dev/null)

P8_TIMEOUT="${CC_BEAT_TIMEOUT:-3}"

beat() {
  [ "${CC_BEAT:-on}" = off ] && return 0
  command -v jq >/dev/null 2>&1 || return 0

  local sid cwd pane kind who src prompt rx dir tmp prev prevOp now seq cpid lstart walk c i
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
  if [ "$kind" = prompt ]; then
    prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
    rx="${CC_CLASSIFY_AUTO_RX:-^<task-notification>|^<local-command-stdout>|^Stop hook feedback:|^\\[Request interrupted|^⟳|^⚑|^⚠}"
    if [ -n "$prompt" ] && ! printf '%s' "$prompt" | jq -Rs --arg rx "$rx" -e 'test($rx)' >/dev/null 2>&1; then
      who=operator
    fi
  fi

  # ── `src` — WHICH auto-traffic, not merely THAT it was auto (backlog b60eb29e97dd) ──────────────
  # `who` answers presence, and for presence every non-operator prompt is the same answer. One
  # consumer needs the distinction `who` collapses: `cc-await-ping --idle-scoped` stands itself down
  # on "a new turn of my own session", and a session's own CLOSE CASCADE is made of turns — a Stop
  # hook blocks, its `Stop hook feedback:` re-prompt is a UserPromptSubmit, and the beat seq moves.
  # The watcher is ARMED inside exactly that cascade (the wake floor blocks to demand it), so a
  # `who`-blind stand-down killed every idle-scoped watcher on the turn that armed it — measured
  # 2/2, thresholds `seq>3` and `seq>6`, i.e. the arm turn's own completion. That made the wake
  # floor's block an instruction to run a deterministic no-op and the session went idle DEAF anyway.
  #
  # The discriminator has to live HERE because only this hook ever sees the prompt text; by the time
  # the watcher reads the beat, the prompt is gone. So the classification is attested with the beat,
  # once, on the prompt already in hand — the same economics that put `who` here.
  #
  # SUBORDINATE TO `who`, never a second opinion on it: `who=operator` ⇒ `src=operator`, so the
  # CC_CLASSIFY_AUTO_RX seam still governs the operator/auto split and the two fields cannot
  # disagree. The sub-classification below only ever partitions the auto side.
  # ADDITIVE: every existing consumer reads `who`/`operatorT`/`kind`/`seq` and is untouched; a beat
  # written before this field existed reads `src` empty, which every reader must treat as UNKNOWN
  # (cc-await-ping does — unknown falls through to the pre-existing stand-down, the safe direction).
  if [ "$kind" != prompt ]; then
    src=stop
  elif [ "$who" = operator ]; then
    src=operator
  else
    case "$prompt" in
      'Stop hook feedback:'*)   src=stopfeedback ;;   # THIS session's own auto-drive — not a wake
      '⟳'*|'⚑'*|'⚠'*)           src=advisory ;;       # our own ⟳/⚑/⚠ nudges — also not a wake
      '<task-notification>'*)   src=tasknote ;;
      '<local-command-stdout>'*) src=localcmd ;;
      '[Request interrupted'*)  src=interrupt ;;
      *)                        src=auto ;;
    esac
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

  # Carry the sticky operator high-water mark and the sequence forward from the previous beat.
  prevOp=""; seq=0
  if [ -f "$dir/$sid.json" ]; then
    prev=$(jq -r '[(.operatorT // ""), (.seq // 0)] | @tsv' "$dir/$sid.json" 2>/dev/null)
    prevOp=$(printf '%s' "$prev" | cut -f1)
    seq=$(printf '%s' "$prev" | cut -f2)
  fi
  case "$seq"   in ''|*[!0-9]*) seq=0 ;; esac
  case "$prevOp" in *[!0-9]*) prevOp="" ;; esac
  seq=$((seq + 1))
  [ "$who" = operator ] && prevOp="$now"

  tmp="$dir/.$sid.$$.tmp"
  if jq -n --arg sid "$sid" --arg pane "$pane" --arg cwd "$cwd" --arg kind "$kind" \
          --arg who "$who" --arg src "$src" --arg lstart "$lstart" --arg opT "$prevOp" \
          --argjson pid "$cpid" --argjson t "$now" --argjson seq "$seq" \
        '{sid:$sid, pane:$pane, cwd:$cwd, pid:$pid, lstart:$lstart, t:$t, kind:$kind, who:$who,
          src:$src, operatorT:(if $opT=="" then null else ($opT|tonumber) end), seq:$seq}' \
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
