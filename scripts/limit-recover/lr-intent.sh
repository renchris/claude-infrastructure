#!/bin/bash
# lr-intent.sh — the operator-intent file that admits a driver-direct move of a HEALTHY pane.
# Sourced by lr-handoff.sh, handoff-fire.sh's --probe-recycle-preconditions, and the cc-lr move lane.
#
# WHY IT EXISTS (design-swap-v3 D1, operator ruling 2026-10-04; reverses VOLUNTARY_ACCOUNT_SWITCH
# DEC-2's SELF-only rule). A --voluntary move of another pane was admitted only on a quota fact
# (--account-evidence) or a limit; a healthy idle peer had to be ASKED to move itself. That subject
# turn cost a median 376K input-equivalent tokens per move, was paid even when the move was then
# refused, and was not bounded to the command (one subject ran 24 tool calls over 619 s). The
# operator's `cc-lr move` writes one of these files per session instead, and the launchd-owned batch
# runner restarts the pane directly, with no model turn.
#
# THE FILE IS THE AUTHORITY, so it is checked the way a credential is: it must be a regular file the
# user owns, readable by nobody else, sitting where only the lane writes (<state>/move/<batch>/
# intent/<sid>.json), and it must bind THIS move: the session, the pane, the source account and the
# target account, inside its expiry. Same trust boundary as typing into the pane: anyone who can
# write that file as the user can already type /exit there.
#
#   {"kind":"cc-lr-move","batch":B,"sid":S,"pane":P,"from":A,"to":T,"requested_by":R,"ts":N,
#    "expires_epoch":N,"plan_row_sha":H}
#
# Every check has its own token, first in LR_INTENT_WHY, and tests/lr-intent.bats breaks a valid
# fixture one check at a time, so removing any single check turns exactly its case red.
# Kill switch LR_OPERATOR_INTENT=off: no intent file admits anything (token `switched-off`).

# shellcheck disable=SC2034  # LR_INTENT_WHY is this library's out-parameter, read by every caller
LR_INTENT_WHY=""
lr_intent_mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1" 2>/dev/null; }
lr_intent_check() { # $1=file $2=sid $3=pane $4=from account name $5=to account name → 0 valid · 1 invalid (LR_INTENT_WHY)
  local f="${1:-}" sid="${2:-}" pane="${3:-}" from="${4:-}" to="${5:-}" state root dir mode got now exp
  LR_INTENT_WHY=""
  if [ "${LR_OPERATOR_INTENT:-on}" = off ]; then LR_INTENT_WHY="switched-off: LR_OPERATOR_INTENT=off, so no operator-intent file admits a move"; return 1; fi
  if [ -z "$f" ] || [ -L "$f" ] || [ ! -f "$f" ]; then LR_INTENT_WHY="not-regular: ${f:-<none>} is not a regular file (a symlink or a missing file is never an intent)"; return 1; fi
  if [ ! -O "$f" ]; then LR_INTENT_WHY="not-owned: $f is not owned by this user"; return 1; fi
  mode="$(lr_intent_mode "$f")"
  case "$mode" in
    [0-7]00) ;;
    *) LR_INTENT_WHY="bad-mode: $f is mode ${mode:-unreadable}; an intent is readable by its owner only (0600)"; return 1 ;;
  esac
  state="${LR_STATE_DIR:-$HOME/.reso/limit-recover}"
  root="$(cd "$state/move" 2>/dev/null && pwd -P)" || root=""
  dir="$(cd "$(dirname "$f")" 2>/dev/null && pwd -P)" || dir=""
  case "${dir#"$root"/}" in
    */*/*|"$dir") dir="" ;;
    */intent) ;;
    *) dir="" ;;
  esac
  if [ -z "$root" ] || [ -z "$dir" ] || [ "${f##*/}" != "$sid.json" ]; then
    LR_INTENT_WHY="bad-path: $f is not $state/move/<batch>/intent/$sid.json"; return 1
  fi
  if ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then LR_INTENT_WHY="unreadable: $f is not a JSON object"; return 1; fi
  got="$(jq -r '.kind // empty' "$f" 2>/dev/null)"
  if [ "$got" != cc-lr-move ]; then LR_INTENT_WHY="bad-kind: kind is '${got:-absent}', not cc-lr-move"; return 1; fi
  got="$(jq -r '.sid // empty' "$f" 2>/dev/null)"
  if [ -z "$sid" ] || [ "$got" != "$sid" ]; then LR_INTENT_WHY="sid-mismatch: the intent names session '${got:-none}', this move is ${sid:-none}"; return 1; fi
  got="$(jq -r '.pane // empty | tostring' "$f" 2>/dev/null)"
  if [ -z "$pane" ] || [ "$got" != "$pane" ]; then LR_INTENT_WHY="pane-mismatch: the intent names pane '${got:-none}', this move is pane ${pane:-none}"; return 1; fi
  got="$(jq -r '.from // empty' "$f" 2>/dev/null)"
  if [ -z "$from" ] || [ "$got" != "$from" ]; then LR_INTENT_WHY="from-mismatch: the intent moves it off '${got:-none}', the session is on '${from:-unknown}'"; return 1; fi
  got="$(jq -r '.to // empty' "$f" 2>/dev/null)"
  if [ -z "$to" ] || [ "$got" != "$to" ]; then LR_INTENT_WHY="to-mismatch: the intent names target '${got:-none}', this move targets '${to:-none}'"; return 1; fi
  exp="$(jq -r '.expires_epoch // empty | tostring' "$f" 2>/dev/null)"
  now="$(date +%s)"
  case "$exp" in
    ''|*[!0-9]*) LR_INTENT_WHY="expired: expires_epoch is '${exp:-absent}', not an integer"; return 1 ;;
  esac
  if [ "$exp" -le "$now" ]; then LR_INTENT_WHY="expired: the intent expired $(( now - exp ))s ago; re-run cc-lr move"; return 1; fi
  return 0
}
