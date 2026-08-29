#!/bin/bash
# session-beat.sh — the WRITE side of the session presence beat (SESSION_REGISTRY_V2 §4.1).
#
# Wired to UserPromptSubmit and Stop. Writes ONE small durable attestation per turn boundary:
#   ${CC_BEAT_DIR:-$HOME/.claude/cc-beats}/<sid>.json
#   {sid, pane, pid, lstart, t, kind, who, operatorT, seq, cont, turnSeq}
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
# ── `cont` / `turnSeq` — THE CONTINUATION AXIS (backlog b60eb29e97dd, 2026-08-29) ─────────────────
# `seq` counts BOUNDARIES, and a boundary is not a turn's worth of new information. Our own Stop
# blockers (session-continue's 🔧 / ship / wake floors, completion-assert, an unmet /goal) re-prompt
# the model with a `Stop hook feedback:` user turn, so ONE idle episode emits an unbounded
# stop/prompt/stop/prompt chain — every link of it a fresh `seq`, none of it news.
#
# That distinction had exactly one consumer and it could not make it: `cc-await-ping --idle-scoped`
# baselines `seq` at arm and stands down when it moves, so the ARMING TURN'S OWN COMPLETION cancelled
# it — measured 2/2 on live sessions (banners `seq > 3` and `seq > 6`, both stood down at once). The
# arm is instructed BY a Stop-hook block, so the arming turn is itself a link in such a chain and its
# stop is very likely blocked again; the watcher died before the idle it was scoped to began, and the
# wake floor — bounded at CC_WAKE_FLOOR_MAX attempts — spent its whole budget instructing an arm that
# deterministically no-ops, then let the session go idle DEAF. The design doc predicted this and
# called it self-correcting ("converging one bounce later", goal-safe-2way-comms-2026-08-13 §4);
# it does not converge, because each re-arm meets the same blocker on the same turn.
#
#   cont     true iff this is a PROMPT beat whose text is our own boundary self-drive
#            (CC_BEAT_CONT_RX, default `^Stop hook feedback:` plus our ⟳/⚑/⚠ advisory glyphs).
#            Deliberately NARROWER than the auto-traffic regex `who` uses: `<task-notification>`,
#            `[Request interrupted` and `<local-command-stdout>` are all who=auto yet all carry
#            genuine news (a background task finished, the operator interrupted, the operator ran a
#            slash command), so they must still move `turnSeq`. Stop beats are never `cont`.
#   turnSeq  carried forward from the previous beat; +1 ONLY on a non-`cont` prompt beat. So it
#            counts NEW-INFORMATION turns, is monotone, and — because a Stop beat carries the
#            current value rather than resetting it — a reader that samples only the latest beat can
#            compare it against a baseline with no sampling hole: an unobserved turn still shows up
#            as a raised `turnSeq` on the next boundary of any kind.
#
# An empty/unreadable prompt is NOT counted as a continuation (it moves `turnSeq`), keeping the
# documented safe direction: erring toward standing a watcher down costs one bounce turn; erring the
# other way costs the goal.
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

  local sid cwd pane kind who prompt rx dir tmp prev prevOp now seq cpid lstart walk c i
  local cont contrx turnSeq
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
  cont=false
  if [ "$kind" = prompt ]; then
    prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
    rx="${CC_CLASSIFY_AUTO_RX:-^<task-notification>|^<local-command-stdout>|^Stop hook feedback:|^\\[Request interrupted|^⟳|^⚑|^⚠}"
    if [ -n "$prompt" ] && ! printf '%s' "$prompt" | jq -Rs --arg rx "$rx" -e 'test($rx)' >/dev/null 2>&1; then
      who=operator
    fi
    # ── the `cont` decision, made on the same prompt, in the same pass ──
    # A SEPARATE regex from the one above on purpose (see the header): who=auto answers "is the
    # operator present", cont answers "is this turn news". Every continuation is auto traffic; not
    # every piece of auto traffic is a continuation.
    contrx="${CC_BEAT_CONT_RX:-^Stop hook feedback:|^⟳|^⚑|^⚠}"
    if [ -n "$prompt" ] && printf '%s' "$prompt" | jq -Rs --arg rx "$contrx" -e 'test($rx)' >/dev/null 2>&1; then
      cont=true
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

  # Carry the sticky operator high-water mark and both sequences forward from the previous beat.
  prevOp=""; seq=0; turnSeq=0
  if [ -f "$dir/$sid.json" ]; then
    prev=$(jq -r '[(.operatorT // ""), (.seq // 0), (.turnSeq // 0)] | @tsv' "$dir/$sid.json" 2>/dev/null)
    prevOp=$(printf '%s' "$prev" | cut -f1)
    seq=$(printf '%s' "$prev" | cut -f2)
    turnSeq=$(printf '%s' "$prev" | cut -f3)
  fi
  case "$seq"     in ''|*[!0-9]*) seq=0 ;; esac
  case "$turnSeq" in ''|*[!0-9]*) turnSeq=0 ;; esac
  case "$prevOp" in *[!0-9]*) prevOp="" ;; esac
  seq=$((seq + 1))
  # A boundary always moves `seq`; only a turn that carries NEWS moves `turnSeq`. A beat file
  # written by a pre-b60eb29e97dd producer has no turnSeq, reads 0 above, and starts counting here —
  # so an upgrade in place degrades to "one extra stand-down", never to a wrong ordering.
  [ "$kind" = prompt ] && [ "$cont" = false ] && turnSeq=$((turnSeq + 1))
  [ "$who" = operator ] && prevOp="$now"

  tmp="$dir/.$sid.$$.tmp"
  if jq -n --arg sid "$sid" --arg pane "$pane" --arg cwd "$cwd" --arg kind "$kind" \
          --arg who "$who" --arg lstart "$lstart" --arg opT "$prevOp" \
          --argjson pid "$cpid" --argjson t "$now" --argjson seq "$seq" \
          --argjson cont "$cont" --argjson turnSeq "$turnSeq" \
        '{sid:$sid, pane:$pane, cwd:$cwd, pid:$pid, lstart:$lstart, t:$t, kind:$kind, who:$who,
          operatorT:(if $opT=="" then null else ($opT|tonumber) end), seq:$seq,
          cont:$cont, turnSeq:$turnSeq}' \
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
