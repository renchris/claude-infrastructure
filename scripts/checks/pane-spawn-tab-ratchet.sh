#!/usr/bin/env bash
# pane-spawn-tab-ratchet.sh — the no-tabs ratchet over ~/.claude/logs/pane-spawns.jsonl.
#
# WHY. The operator rule is NO kitty tabs, ever: every OS window fullscreen on its own Space, at
# most 4 vertical split panes. Between 01:00Z and 15:00Z on 2026-10-18 the spawn log recorded 22
# rows with surface `bg-tab`, every one from an agent's `handoff-fire … --tab`, and 13 of those tabs
# ended as dead shells hidden behind the one visible tab (docs/research/lr-wake-incident-2026-10-18/
# REPORT.md RC3, b-tabs.md). Wave D removed every agent path to a tab; this check is how a
# regression gets SEEN: the count of tab rows in the window must be 0. Against that night it reads 22
# (tests/pane-spawn-tab-ratchet.bats replays it).
#
# A tab row is surface `tab` or `bg-tab`. Two callers are exempt by design, because they replay a
# RECORDED layout with CC_ALLOW_TAB=1: cc-resume-layout.sh and restore-tree-live-verify.
#
# usage: pane-spawn-tab-ratchet.sh [--log <file>] [--since <ISO-8601 UTC> | --all]
#   --log    default ~/.claude/logs/pane-spawns.jsonl (CC_SPAWN_LOG_FILE when set)
#   --since  only rows at or after this time; default: the last 24 hours
# Prints one verdict line, then one line per offending row.
# exit 0 = no tab rows · 1 = tab rows (RED) · 2 = no verdict (unreadable log, jq absent, bad usage)
set -uo pipefail

LOG="${CC_SPAWN_LOG_FILE:-${HOME:-}/.claude/logs/pane-spawns.jsonl}"
SINCE=""
ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --log)   LOG="${2:-}"; shift 2 ;;
    --since) SINCE="${2:-}"; shift 2 ;;
    --all)   ALL=1; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "pane-spawn-tab-ratchet: unknown argument: $1" >&2; exit 2 ;;
  esac
done

nv() { echo "pane-spawn-tab-ratchet: verdict=no-verdict reason=$1 log=$LOG"; exit 2; }
command -v jq >/dev/null 2>&1 || nv jq-absent
[ -r "$LOG" ] || nv log-unreadable
if [ "$ALL" = 1 ]; then SINCE="0000"
elif [ -z "$SINCE" ]; then
  SINCE="$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || nv no-clock
fi
case "$SINCE" in [0-9][0-9][0-9][0-9]*) ;; *) nv "bad-since:$SINCE" ;; esac

# One pass. A row jq cannot parse is skipped (fromjson? on each raw line) rather than ending the
# read, and counted, so a torn line never hides the rows after it.
out="$(jq -R -r --arg since "$SINCE" '
  (fromjson? // "BAD") as $r
  | if $r == "BAD" then "BAD"
    elif (($r.surface // "") as $s | ($s == "tab" or $s == "bg-tab"))
         and (($r.ts // "") >= $since)
         and ((($r.caller // "") | test("^(cc-resume-layout(\\.sh)?|restore-tree-live-verify(\\.py)?)$")) | not)
    then "TAB\t\($r.ts)\t\($r.surface)\tpane:\($r.pane // "?")\t\($r.caller // "?")\t\($r.detail // "")"
    else empty end' "$LOG" 2>/dev/null)" || nv jq-failed
n="$(printf '%s\n' "$out" | grep -c '^TAB' || true)"
bad="$(printf '%s\n' "$out" | grep -c '^BAD$' || true)"
if [ "${n:-0}" -eq 0 ]; then
  echo "pane-spawn-tab-ratchet: verdict=ok tab_rows=0 since=$SINCE unparsed=$bad log=$LOG"
  exit 0
fi
echo "pane-spawn-tab-ratchet: verdict=RED tab_rows=$n since=$SINCE unparsed=$bad log=$LOG"
printf '%s\n' "$out" | grep '^TAB' | cut -f2-
exit 1
