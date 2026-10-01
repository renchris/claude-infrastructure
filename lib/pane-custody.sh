# shellcheck shell=bash
# pane-custody.sh — did this pane's originator collect its work? Sourced; bash 3.2 / zsh portable.
#
# WHY THIS EXISTS (docs/research/husk-triage-2026-10-01.md § Gaps, items 2 and 3). A lead killed in
# its pane (55, c82dd5b9, SIGTERMed 02:26Z) had its work taken over by its orchestrator, which wrote
# `cc-custody abandon … "lead collected its work"` at 03:59Z. Two surfaces still told the operator to
# resume it, which would re-arm a live /goal over finished work: the watchdog's CRASH banner
# (hooks/lead-crash-watchdog.sh) and cc-husk-sweep's UNKNOWN verdict (bin/cc-husk-sweep). Neither
# read custody. This file is the ONE reader both use, so they cannot disagree about "collected".
# It never writes the store; bin/cc-custody owns it.
#
# KEYED ON targetPane, NEVER cwd. A custody row's cwd is the ORIGINATOR's (bin/cc-custody header),
# so the dead session's cwd names nothing. The discharge rule is cc-custody's own: an open row is
# discharged by a later return/abandon with its marker, falling back to slug+targetPane; the latest
# row per key is the verdict.
#
# PANE IDS ARE REUSED. kitty hands id 55 to a new window once the old one closes, so a row targeting
# 55 from an earlier tenant must not speak for today's session. Callers pass the session's start
# epoch (cc_transcript_start_epoch below) and only open rows at or after it count. custody opens
# AFTER the fire proves engagement (scripts/handoff-fire.sh engage_rc_consequence), so a row for this
# session is never older than its first record — measured on c82dd5b9: first record 00:35:33Z, open
# 00:35:50Z. A caller that cannot date the session passes 0 and accepts the weaker match.
#
# ABSENCE IS NOT "COLLECTED". No row, no jq, an unreadable store or file: rc 1, no output, and the
# caller keeps its old behaviour. Only a row that was actually discharged reads as collected
# (memory: lookup-miss-is-not-absence).

cc_transcript_start_epoch() { # $1=transcript path → epoch (whole seconds) of its first dated record, or 0
  local _f="${1:-}" _e=""
  if [ -n "$_f" ] && [ -r "$_f" ] && command -v jq >/dev/null 2>&1; then
    # head of a FILE, not a pipe into head: nothing upstream is cut off, so pipefail callers stay sound.
    _e="$(head -n 200 -- "$_f" 2>/dev/null | jq -R -n -r '
      [inputs | fromjson? | objects | .timestamp? | strings] | first // empty
      | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch empty) | floor' 2>/dev/null)"
  fi
  case "$_e" in ''|*[!0-9]*) _e=0 ;; esac
  printf '%s\n' "$_e"
}

cc_pane_custody() { # $1=pane $2=since-epoch → `<state>\t<slug>\t<kind>\t<ts>\t<originatorPane>`, rc 0; rc 1 = no custody fact
  # state: collected (the newest open row targeting the pane since $2 was discharged; kind = return|abandon,
  # ts = the discharge's) · open (it was not; kind = open, ts = the open's).
  local _p="${1:-}" _since="${2:-0}" _dir _rows _out
  [ -n "$_p" ] || return 1
  case "$_since" in ''|*[!0-9]*) _since=0 ;; esac
  command -v jq >/dev/null 2>&1 || return 1
  _dir="${CC_CUSTODY_DIR:-${HOME:-}/.claude/autonomy/custody}"
  [ -d "$_dir" ] || return 1
  set -- "$_dir"/*.jsonl
  [ -f "$1" ] || return 1
  # Every file, because cc-custody keys files by the ORIGINATOR's cwd and the pane's row may be in any
  # of them. One unreadable file fails the whole read: a store missing the file that holds the
  # discharge would report "open" over collected work.
  _rows="$(cat -- "$@" 2>/dev/null)" || return 1
  # shellcheck disable=SC2016  # $p, $since, $all, $o, $v are jq variables
  _out="$(printf '%s\n' "$_rows" | jq -R -n -r --arg p "$_p" --argjson since "$_since" '
    [inputs | fromjson? | objects] | to_entries
    | map(.value + {i: .key,
                    k: (if (.value.marker // "") != "" then ("m:" + .value.marker)
                        else ("s:" + (.value.slug // "") + "|" + ((.value.targetPane // "") | tostring)) end),
                    e: ((.value.ts // "") | tostring | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch null))})
    | . as $all
    | [.[] | select(.kind == "open" and ((.targetPane // "") | tostring) == $p and .e != null and .e >= $since)]
    | sort_by([.e, .i]) | last
    | if . == null then empty else
        . as $o
        | [$all[] | select(.k == $o.k and .e != null and (.kind == "open" or .kind == "return" or .kind == "abandon"))]
        | sort_by([.e, .i]) | last as $v
        | [(if $v.kind == "open" then "open" else "collected" end),
           ($o.slug // "-"), $v.kind, ($v.ts // "-"), (($o.originatorPane // "-") | tostring)]
        | @tsv
      end' 2>/dev/null)" || return 1
  [ -n "$_out" ] || return 1
  printf '%s\n' "$_out"
}
