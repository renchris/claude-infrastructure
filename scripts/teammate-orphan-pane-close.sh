#!/bin/bash
# teammate-orphan-pane-close.sh — close an Agent-Team member's pane when its member approved a
# shutdown and its LEAD cannot close it. Detached by hooks/session-end.sh in the member's own
# SessionEnd; never run inside a turn.
#
# WHY (measured 2026-09-23, pane 545). Claude Code closes a pane member's pane from the LEAD: the
# member writes `shutdown_approved {paneId, backendType}` to the lead's inbox and exits, and the
# lead's InboxPoller kills that pane — but only when the approval's paneId equals the tmuxPaneId in
# the lead's IN-MEMORY roster, and only while its poller runs at all. A RESUMED lead (cc-lr upgrade,
# /limit-recover, a crash + --resume) rebuilds that roster with itself alone, so its poller never
# runs and the approval sits unread forever: the member's process is gone and its pane stays open
# at a bare shell. Lead 513 sent refute-reversals a shutdown_request after its in-place upgrade; the
# member approved at 08:20:37Z and exited rc 0; pane 545 stayed. The member is the one party that
# knows it approved and where its pane is, so the close comes from its side.
#
# ACTS ONLY when every one of these holds after the grace (the lead gets first claim):
#   1. the lead's inbox holds a shutdown_approved FROM this member, stamped within TOPC_WINDOW_S;
#   2. that approval is still UNREAD — read means the lead processed it and owns the close;
#   3. the member is really gone: its pane's registered pid is not a live claude, and no claude runs
#      in the vendor spawn form `--agent-id ID` (identity, never argv text — see check 3);
#   4. the approval names an iterm2-backend pane (this box's it2 shim; tmux is not driven here)
#      and that pane is still listed by `it2 session list`.
# Anything else logs one line and closes nothing.
#
# Usage: teammate-orphan-pane-close.sh --cfg DIR --team T --name N --agent-id ID
# Seams: TOPC_GRACE_S (20) · TOPC_WINDOW_S (300) · TOPC_NOW (epoch) · TOPC_IT2 · TOPC_REG_DIR · TOPC_PS_SNAPSHOT
#        (file of `ps -axww -o args=` lines) · TOPC_LOG. Kill switch: CC_TEAMMATE_ORPHAN_CLOSE=off.
# bash 3.2 (a detached child of a hook runs /bin/bash semantics): no arrays of maps, no ${x,,}.
set -uo pipefail
export PATH="$PATH:$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin"

CFG="" TEAM="" NAME="" AID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cfg)      [ $# -ge 2 ] || exit 3; CFG="$2"; shift 2 ;;
    --team)     [ $# -ge 2 ] || exit 3; TEAM="$2"; shift 2 ;;
    --name)     [ $# -ge 2 ] || exit 3; NAME="$2"; shift 2 ;;
    --agent-id) [ $# -ge 2 ] || exit 3; AID="$2"; shift 2 ;;
    *) echo "teammate-orphan-pane-close: unknown arg $1" >&2; exit 3 ;;
  esac
done
LOG="${TOPC_LOG:-$HOME/.claude/logs/teammate-lifecycle.log}"
say() { printf '[%s] orphan-pane-close %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${NAME:-?}" "$*" >> "$LOG" 2>/dev/null || true; }

[ "${CC_TEAMMATE_ORPHAN_CLOSE:-on}" = off ] && { say "off (CC_TEAMMATE_ORPHAN_CLOSE=off)"; exit 0; }
[ -n "$CFG" ] && [ -n "$TEAM" ] && [ -n "$NAME" ] && [ -n "$AID" ] || { say "usage: missing --cfg/--team/--name/--agent-id"; exit 3; }
command -v jq >/dev/null 2>&1 || { say "jq unreachable - nothing closed"; exit 0; }

sleep "${TOPC_GRACE_S:-20}"

INBOX="${CFG%/}/teams/$TEAM/inboxes/team-lead.json"
[ -f "$INBOX" ] || { say "no lead inbox at $INBOX - nothing closed"; exit 0; }
now="${TOPC_NOW:-$(date +%s)}"
# The member's newest approval: `{read, paneId, backendType, age}`. A text that is not JSON is not
# an approval; a timestamp that does not parse cannot be dated, so it cannot qualify.
appr="$(TOPC_N="$NAME" TOPC_T="$now" jq -c '
  [ .[]? | select(.from == env.TOPC_N)
    | . as $m | ((.text // "") | (try fromjson catch null)) as $f
    | select($f != null and ($f | type) == "object" and $f.type == "shutdown_approved")
    | { read: ($m.read // false), paneId: ($f.paneId // ""), backendType: ($f.backendType // ""),
        age: ((env.TOPC_T | tonumber) - ((($f.timestamp // $m.timestamp // "") | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch -1e12))) } ]
  | last // empty' "$INBOX" 2>/dev/null)"
[ -n "$appr" ] || { say "no shutdown_approved from $NAME in $INBOX - nothing closed"; exit 0; }
age="$(printf '%s' "$appr" | jq -r '.age | floor')"
if [ "$age" -lt 0 ] || [ "$age" -gt "${TOPC_WINDOW_S:-300}" ]; then say "approval is ${age}s old (window ${TOPC_WINDOW_S:-300}s) - not this exit's; nothing closed"; exit 0; fi
[ "$(printf '%s' "$appr" | jq -r '.read')" = true ] && { say "the lead READ the approval - the close is the lead's; nothing closed"; exit 0; }
pane="$(printf '%s' "$appr" | jq -r '.paneId')"; backend="$(printf '%s' "$appr" | jq -r '.backendType')"
case "$pane" in ''|*[!A-Za-z0-9_:%.-]*) say "approval names no usable pane ('$pane') - nothing closed"; exit 0 ;; esac
[ "$backend" = iterm2 ] || { say "backend '$backend' for pane $pane is not driven here - nothing closed"; exit 0; }

# 3. The member is gone — decided by IDENTITY, never by argv text. A `--agent-id ID` substring is
#    forgeable by any session whose brief QUOTES it (measured: the session that wrote this file
#    carried the id in its own argv and read as the live member). Two arms, either proves ALIVE:
#    (a) the pane's own registry row names a pid that is alive and is a claude — a relaunch
#        re-registers the pane, so this also catches a member brought back in place;
#    (b) the vendor spawn form: argv[0] is claude and argv[1..2] are exactly `--agent-id ID`.
reg="${TOPC_REG_DIR:-$HOME/.claude/cc-registry}/$pane.json"
rpid="$(jq -r '.pid // empty' "$reg" 2>/dev/null || true)"
case "$rpid" in ''|*[!0-9]*) rpid="" ;; esac
if [ -n "$rpid" ] && kill -0 "$rpid" 2>/dev/null; then
  case "$(ps -o args= -p "$rpid" 2>/dev/null | awk '{ print $1 }')" in
    */claude|*/claude.exe|claude|claude.exe) say "pane $pane's registered pid $rpid is a live claude - nothing closed"; exit 0 ;;
  esac
fi
if [ -n "${TOPC_PS_SNAPSHOT:-}" ]; then procs="$(cat "$TOPC_PS_SNAPSHOT" 2>/dev/null)"; else procs="$(ps -axww -o args= 2>/dev/null)"; fi
if printf '%s\n' "$procs" | TOPC_ID="$AID" awk '$1 ~ /(^|\/)claude(\.exe)?$/ && $2 == "--agent-id" && $3 == ENVIRON["TOPC_ID"] { f = 1 } END { exit !f }'; then
  say "a claude spawned as --agent-id $AID is alive - nothing closed"; exit 0
fi

IT2="${TOPC_IT2:-$HOME/.claude/bin/it2}"
[ -x "$IT2" ] || { say "it2 unreachable at $IT2 - pane $pane left open"; exit 0; }
listing="$("$IT2" session list 2>/dev/null)" || { say "it2 session list failed - pane $pane left open (unknown is not absent)"; exit 0; }
case $'\n'"$listing"$'\n' in *$'\n'"$pane"$'\n'*) ;; *) say "pane $pane is already gone - nothing to close"; exit 0 ;; esac

if err="$("$IT2" session close -f -s "$pane" 2>&1)"; then
  say "✓ closed pane $pane: $NAME approved a shutdown the lead never read (a resumed lead cannot close its members' panes)"
else
  say "✗ close of pane $pane FAILED: $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-240)"
fi
exit 0
