#!/usr/bin/env bash
# fired-peers.sh — "which sessions did THIS session fire?", ONE answer, sourced by every reader.
#
# THE QUESTION. A fired peer files its operator steps (backlog rows) and warnings under ITS OWN
# session id, so a reader keyed only on "rows whose .session is mine" cannot see work that a session
# delegated. Measured 2026-09-27 over 30 days: 83 of 688 operator steps (12%) were filed by fired
# sessions, and a firing session's close read ✅ over an operator step its own peer had filed.
# Two readers need the lineage: scripts/wrap-ledger.sh (the 👤 rung) and handoff-fire.sh's
# self-close orphan inventory. They share this file so the matching rule has exactly one author.
#
# THE STORE. ${CC_FIRED_DIR:-~/.claude/cc-fired}/<paneUUID>.json, written only by handoff-fire's
# mark_fired_peer. `firedBy` / `originator` hold the FIRING PANE, never a session id; `transcript`
# is the FIRED session's transcript, so its basename is the peer's session id. Since 2026-09-27 the
# writer also records `firedBySid`, the firing SESSION's id.
#
# THE RULE, per stamp:
#   · firedBySid present  ⇒ it is ours iff firedBySid == our session id. Nothing else is consulted:
#     a stamp naming another session is that session's, whatever pane it came from.
#   · firedBySid absent (a LEGACY stamp) ⇒ ours iff firedBy == our pane AND firedAt >= our session's
#     start. The time guard is not optional: pane numbers are reused, and without it a later session
#     in the same pane would inherit every peer an earlier session fired there. No start ⇒ no
#     legacy match at all.
#
# BOUNDED. Only stamps modified since the session started are read (a stamp is written at fire time
# and only touched later, so a stamp fired after the start always has an mtime after it). With no
# start the window is FIRED_PEER_WINDOW_MIN (14 days). Past FIRED_PEER_MAX_FILES candidates the
# function abstains (rc 3) rather than run an unbounded read inside a Stop hook.
#
# FAIL-OPEN. Every failure — no dir, no jq, an unreadable stamp — yields fewer peers, never more.
# A corrupt stamp is skipped individually; it does not blank the rest.

# fired_session_start_epoch <transcript> → epoch of the transcript's first timestamped record.
fired_session_start_epoch() {
  local tp="${1:-}" ts
  [ -n "$tp" ] && [ -f "$tp" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  ts="$(head -n 200 "$tp" 2>/dev/null | grep -o -m1 '"timestamp":"[^"]*"' | head -1 | cut -d'"' -f4)"
  [ -n "$ts" ] || return 1
  jq -rn --arg t "$ts" '$t | sub("\\.[0-9]+"; "") | (try fromdateiso8601 catch empty) | floor' 2>/dev/null \
    | grep -E '^[0-9]+$' || return 1
}

# The per-stamp predicate, shared by the batch read and its per-file fallback.
# shellcheck disable=SC2016  # a jq program, expanded by jq
_FIRED_PEER_JQ='
  def epoch: (. // "") | tostring | sub("\\.[0-9]+"; "") | (try fromdateiso8601 catch null);
  select(type == "object")
  | ((.firedBySid // "") | tostring) as $fs
  | select( ($sid != "" and $fs == $sid)
            or ( $fs == "" and $pane != "" and $start != ""
                 and (((.firedBy // "") | tostring) == $pane)
                 and (((.firedAt | epoch) // -1) >= ($start | tonumber)) ) )
  | ((.transcript // "") | tostring | split("/") | (last // "") | sub("\\.jsonl$"; "")) as $peer
  | select($peer != $sid or $peer == "")
  | [ ((.paneUUID // "") | tostring),
      (if $peer == "" then "-" else $peer end),
      (if $fs != "" then "sid" else "pane-time" end) ]
  | @tsv'

# fired_peer_stamps <dir> <our-sid> <our-pane> <start-epoch> → one TSV line per stamp this session
# fired: <paneUUID> <peer-sid|-> <sid|pane-time>. rc 0 answered (possibly empty) · 2 unusable
# inputs · 3 abstained over the file cap.
fired_peer_stamps() {
  local dir="${1:-}" sid="${2:-}" pane="${3:-}" start="${4:-}" now win files n f out
  [ -n "$dir" ] && [ -d "$dir" ] || return 2
  command -v jq >/dev/null 2>&1 || return 2
  case "$start" in *[!0-9]*) start="" ;; esac
  [ -n "$sid" ] || [ -n "$start" ] || return 2   # neither arm can match anything
  now="$(date +%s 2>/dev/null || echo 0)"
  if [ -n "$start" ] && [ "$now" -gt "$start" ] 2>/dev/null; then
    win=$(( (now - start) / 60 + 2 ))
  else
    win="${FIRED_PEER_WINDOW_MIN:-20160}"
  fi
  files="$(find "$dir" -maxdepth 1 -type f -name '*.json' -mmin "-$win" 2>/dev/null)"
  [ -n "$files" ] || return 0
  n="$(printf '%s\n' "$files" | grep -c .)"
  [ "$n" -le "${FIRED_PEER_MAX_FILES:-400}" ] || return 3
  # One jq over every candidate; jq stops at the first corrupt file, so on any failure re-read
  # each file alone and keep what parses.
  out=""
  if ! out="$(printf '%s\n' "$files" | tr '\n' '\0' \
              | xargs -0 jq -r --arg sid "$sid" --arg pane "$pane" --arg start "$start" \
                  "$_FIRED_PEER_JQ" 2>/dev/null)"; then
    out=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      out="$out$(jq -r --arg sid "$sid" --arg pane "$pane" --arg start "$start" \
                   "$_FIRED_PEER_JQ" "$f" 2>/dev/null || true)
"
    done <<EOF
$files
EOF
  fi
  printf '%s\n' "$out" | grep -v '^$' || true
  return 0
}

# fired_peer_sids <dir> <our-sid> <our-pane> <start-epoch> → the peers' session ids, one per line
# (stamps whose peer never engaged have no transcript, so no id, and are omitted). Same rc as above.
fired_peer_sids() {
  local rows rc=0
  rows="$(fired_peer_stamps "$@")" || rc=$?
  [ "$rc" = 0 ] || return "$rc"
  printf '%s\n' "$rows" | awk -F'\t' '$2 != "" && $2 != "-" { print $2 }' | sort -u
  return 0
}
