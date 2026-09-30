#!/usr/bin/env bash
# hooks/lib/deadline-capture.sh — C2 / C2b of the deadline store (personal/deadlines/DESIGN-2026-09-29.md §3).
#
# Sourced at the top of the ALREADY-REGISTERED Stop hook dispatch-assert.sh, so no settings.json
# registration exists or is needed. One entry point, dl_capture_stop <stop-input-json>: it prints a
# {decision:"block"} object when C2b fires and NOTHING otherwise, and always returns 0. The caller
# runs it inside $( ) so nothing here can exit, or fail, the host hook.
#
# C2 — QUEUE. Every hit in THIS turn's main-agent text goes to $DL_DIR/.state/capture-queue.jsonl
#   (session id, cwd, arm, snippet) at zero model cost and without extending the turn. A hit is
#   (a) a date token within 80 chars of a cue, or (b) an undated deferral ("once it's time",
#   "bring this up", "revisit", "park this"). The regexes live in ONE place, `dl capture-scan`,
#   which the nightly `dl harvest` also uses, so the hook and the leak metric cannot drift apart.
#   Deduped per (session, snippet), because a Stop fires more than once per turn.
#
# C2b — NARROW BLOCK, AT MOST ONCE PER SESSION. Blocks only when
#     (a) carries a date inside the next 60 days, or (b) holds in a personal cwd or beside life
#     vocabulary,
#   AND no `dl add|skip|park` event in log.jsonl carries THIS session's id since the turn began.
#   THE DISCHARGE IS SESSION-SCOPED ON PURPOSE. dispatch-assert's discharged_since accepts any
#   backlog event from any session (measured at 166 a day), so a gate built on it is discharged by
#   strangers. Here an event from another session, or any cc-backlog event, discharges nothing.
#   Own latch and own cap (one block per session), separate from NAME_TELL's, so a capture block
#   never spends dispatch-assert's budget and vice versa. dispatch-assert's NAME_TELL path is
#   untouched: when this arm blocks, the host exits on that Stop and NAME_TELL runs at the next one.
#
# EXEMPT: headless runs (CLAUDE_CODE_ENTRYPOINT set and not `cli`, or a transcript whose last
#   `entrypoint` is not `cli`: no human reads the block, and the sweep's own `claude -p` would queue
#   its own output; a synthetic hook-suite payload carries no entrypoint and is skipped too), team assignees (agent_is_assignee), and
#   fired peers (oi_origin_class, evaluated only on the would-block path because it can grep a
#   transcript). Kill switch: CC_DEADLINE_CAPTURE=off.
#
# Seams: DL_DIR · DL_BIN · DL_PERSONAL_ROOT · DL_CAPTURE_STATE_DIR · CC_PANE_ID · CC_FIRED_DIR
# shellcheck shell=bash

# Cheap prefilter so the common Stop spawns no Python. A superset of what capture-scan accepts.
_DLC_PRE='[0-9]{4}-[0-9]{2}-[0-9]{2}|(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.? [0-9]{1,2}|it'"'"'?s time|bring (this|it) up|revisit|come back to|park(ed)? (this|it)'

_dlc_dir() { printf '%s' "${DL_DIR:-$HOME/Development/personal/deadlines}"; }

_dlc_resolve() { # $1=relative path from the repo root (e.g. bin/dl) → an existing path, or nothing
  local here t
  t="${BASH_SOURCE[0]}"; [ -L "$t" ] && t="$(readlink "$t")"
  here="$(cd "$(dirname "$t")" 2>/dev/null && pwd)"
  for c in "$here/../../$1" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/$1" "$HOME/.claude/$1"; do
    [ -e "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

_dlc_exempt() { # $1=cwd $2=transcript → rc 0 when this session may not be blocked
  local lib aid pane
  if lib="$(_dlc_resolve hooks/lib/agent-identity.sh)"; then
    # shellcheck disable=SC1090,SC1091
    if . "$lib" 2>/dev/null; then
      aid="$(agent_is_assignee 2>/dev/null || true)"
      [ -n "$aid" ] && return 0
    fi
  fi
  if lib="$(_dlc_resolve hooks/lib/origin-identity.sh)"; then
    # shellcheck disable=SC1090,SC1091
    if . "$lib" 2>/dev/null; then
      pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; pane="${pane##*:}"
      [ "$(oi_origin_class "$pane" "$1" "$2" 2>/dev/null)" = fired-peer ] && return 0
    fi
  fi
  return 1
}

_dlc_personal() { # $1=cwd → rc 0 when it sits under the personal repo
  local root="${DL_PERSONAL_ROOT:-$HOME/Development/personal}"
  case "$1/" in "$root"/*) return 0 ;; esac
  return 1
}

dl_capture_stop() {
  [ "${CC_DEADLINE_CAPTURE:-on}" = off ] && return 0
  case "${CLAUDE_CODE_ENTRYPOINT:-cli}" in cli) ;; *) return 0 ;; esac
  command -v jq >/dev/null 2>&1 || return 0
  local input="$1" sid tp cwd tturn t19 text dlbin scan dir q key sdir latch seen snip arm
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  tp="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -n "$sid" ] && [ -f "$tp" ] || return 0
  # Interactive only, by the transcript's own last `entrypoint` (a synthetic payload has none).
  [ "$(tail -c 262144 "$tp" 2>/dev/null | grep -o '"entrypoint":"[a-z-]*"' | tail -1)" = '"entrypoint":"cli"' ] || return 0

  # THIS turn: from the last genuine user message (same definition as dispatch-assert).
  tturn="$(jq -r 'select(.type=="user" and (.isSidechain != true))
                  | select(((.message.content|type)=="string")
                           or ([.message.content[]?|select(.type=="text")]|length > 0))
                  | .timestamp // empty' "$tp" 2>/dev/null | tail -1)"
  [ -n "$tturn" ] || return 0
  t19="$(printf '%s' "$tturn" | cut -c1-19)"
  text="$(jq -r --arg t "$t19" \
    'select(.type=="assistant" and (.isSidechain != true) and (((.timestamp // "")[0:19]) >= $t))
     | [.message.content[]? | select(.type=="text") | .text] | join("\n")
     | select(. != "")' "$tp" 2>/dev/null)"
  [ -n "$text" ] || return 0
  printf '%s' "$text" | grep -qiE "$_DLC_PRE" || return 0

  dlbin="${DL_BIN:-}"
  [ -n "$dlbin" ] || dlbin="$(_dlc_resolve bin/dl)" || return 0
  scan="$(printf '%s' "$text" | python3 "$dlbin" capture-scan 2>/dev/null)"
  [ "$(printf '%s' "$scan" | jq -r '.hit' 2>/dev/null)" = true ] || return 0

  dir="$(_dlc_dir)"
  sdir="${DL_CAPTURE_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/deadline-capture}"
  mkdir -p "$sdir" "$dir/.state" 2>/dev/null || return 0
  find "$sdir" -type f -mtime +7 -delete 2>/dev/null || true
  key="$(printf '%s' "$sid" | shasum 2>/dev/null | cut -c1-16)"
  [ -n "$key" ] || return 0
  latch="$sdir/$key.blocked"; seen="$sdir/$key.seen"

  # ── C2: queue each arm's hit once per session ──
  for arm in a b; do
    snip="$(printf '%s' "$scan" | jq -r --arg k "$arm" '.[$k].snippet // empty' 2>/dev/null)"
    [ -n "$snip" ] || continue
    q="$(printf '%s' "$snip" | shasum 2>/dev/null | cut -c1-16)"
    grep -qxF "$q" "$seen" 2>/dev/null && continue
    printf '%s\n' "$q" >> "$seen" 2>/dev/null || true
    printf '%s' "$scan" | jq -c --arg k "$arm" --arg sid "$sid" --arg cwd "$cwd" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{ts:$ts, session_id:$sid, cwd:$cwd, arm:$k, snippet:.[$k].snippet, date:(.[$k].date // null)}' \
      >> "$dir/.state/capture-queue.jsonl" 2>/dev/null || true
  done

  # ── C2b: at most one block per session ──
  [ -f "$latch" ] && return 0
  if [ "$(printf '%s' "$scan" | jq -r '.a.soon // false' 2>/dev/null)" = true ]; then
    snip="$(printf '%s' "$scan" | jq -r '.a.snippet' 2>/dev/null)"
  elif [ "$(printf '%s' "$scan" | jq -r '.b != null' 2>/dev/null)" = true ] \
       && { _dlc_personal "$cwd" || [ "$(printf '%s' "$scan" | jq -r '.life' 2>/dev/null)" = true ]; }; then
    snip="$(printf '%s' "$scan" | jq -r '.b.snippet' 2>/dev/null)"
  else
    return 0
  fi
  # Discharge: a dl add/skip/park event stamped with THIS session's id, at or after the turn start.
  if [ -f "$dir/log.jsonl" ] && jq -e --arg s "$sid" --arg t "$t19" \
       'select(.session_id == $s and (.event == "add" or .event == "skip" or .event == "park")
               and ((.ts // "")[0:19]) >= $t)' "$dir/log.jsonl" >/dev/null 2>&1; then
    return 0
  fi
  _dlc_exempt "$cwd" "$tp" && return 0

  printf '%s\n' "$t19" > "$latch" 2>/dev/null || true
  jq -nc --arg s "$(printf '%s' "$snip" | cut -c1-220)" '{decision:"block", reason:("You deferred “" + $s + "”. If that is a real-world date the operator must act on, record it now: `dl add \"<verb-first title>\" --kind hard|window|soft --lost <YYYY-MM-DD> --class <class> --text \"<the loss>\"`; an undated deferral needs a date to come back to: `dl park --resurface <YYYY-MM-DD> --snippet \"…\"`. If it is not one, `dl skip --why \"…\"`. Then close. (deadline capture, once per session; CC_DEADLINE_CAPTURE=off disables)")}'
  return 0
}
