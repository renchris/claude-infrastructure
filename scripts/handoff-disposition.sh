#!/bin/bash
# handoff-disposition.sh — un-fakeable reads of the MECHANICAL reasons a
# post-handoff session must stay OPEN. The model adds only R-USER/R-DECIDE
# judgment on top; this script never guesses.
#
# Usage:
#   handoff-disposition.sh [--session <uuid>] [--cwd <path>] [--tasklist <id>] [--ack] [slug ...]
#
# Output:
#   stdout — ONE compact JSON object:
#     {"dirty":<n>,"mailbox_pending":["<uuid>",...],"await_ping_running":<bool>,
#      "fired_peers_alive":["<name>",...],"open_tasks":<n or null>}
#   stderr — ONE human summary line.
#
# Exit codes:
#   0 = no mechanical reason (close-eligible pending R-USER/R-DECIDE judgment)
#   1 = ≥1 mechanical reason exists
#   2 = usage error
#
# A mechanical reason EXISTS (exit 1) iff: dirty>0 OR mailbox_pending non-empty
# OR await_ping_running OR fired_peers_alive non-empty OR open_tasks>0.
#
# Field semantics:
#   dirty              count of `git -C <cwd> status --porcelain` lines (0 if not a repo).
#   mailbox_pending    own uuid (--session, else $ITERM_SESSION_ID stripped of "wXtYpZ:")
#                      has more lines in its mailbox file than its .seen cursor records.
#   await_ping_running true iff a cc-await-ping process for THIS session is live:
#                      `pgrep -f "cc-await-ping.*<uuid>"` when a uuid is resolvable
#                      (launch watchers as `cc-await-ping <uuid>` so they attribute);
#                      bare `pgrep -f cc-await-ping` only when no uuid resolves —
#                      scoped, else another session's watcher would hold THIS one open.
#   fired_peers_alive  live cc-sessions --names that contain a passed slug as substring.
#   open_tasks         (--tasklist only) .pending + .in_progress from the task _summary.json.
#
# Env overrides (tests):
#   CC_MAILBOX_DIR  (default ~/.claude/mailbox)
#   CC_SESSIONS_BIN (default ~/.claude/bin/cc-sessions)
#   CC_TASKS_DIR    (default ~/.claude/tasks)
set -uo pipefail

MAILBOX_DIR="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
SESSIONS_BIN="${CC_SESSIONS_BIN:-$HOME/.claude/bin/cc-sessions}"
TASKS_DIR="${CC_TASKS_DIR:-$HOME/.claude/tasks}"

usage() { sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'; }

SESSION=""
CWD="$PWD"
TASKLIST=""
ACK=0
SLUGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --session)  SESSION="${2:?--session needs a value}"; shift 2 ;;
    --cwd)      CWD="${2:?--cwd needs a value}"; shift 2 ;;
    --tasklist) TASKLIST="${2:?--tasklist needs a value}"; shift 2 ;;
    --ack)      ACK=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    --*)        echo "handoff-disposition: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    *)          SLUGS+=("$1"); shift ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "handoff-disposition: jq required" >&2; exit 2; }

notes=""
note() { notes="${notes:+$notes; }$1"; }

# --- dirty: working-tree changes ------------------------------------------
dirty=0
if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  dirty=$(git -C "$CWD" status --porcelain 2>/dev/null | grep -c '' )
  dirty=${dirty:-0}
else
  note "cwd not a git repo (dirty=0)"
fi

# --- mailbox_pending: own uuid has unread mail ----------------------------
uuid="$SESSION"
if [ -z "$uuid" ]; then
  _it="${ITERM_SESSION_ID:-}"; uuid="${_it##*:}"
fi

mailbox_json='[]'
if [ -z "$uuid" ]; then
  note "no session uuid resolvable (mailbox_pending=[])"
else
  mbox="$MAILBOX_DIR/$uuid.md"
  seen="$MAILBOX_DIR/$uuid.seen"
  cur=0
  [ -f "$mbox" ] && cur=$(grep -c '' "$mbox" 2>/dev/null)
  cur=${cur:-0}
  if [ "$ACK" -eq 1 ]; then
    mkdir -p "$MAILBOX_DIR" 2>/dev/null
    printf '%s\n' "$cur" > "$seen"
  fi
  prev=0
  [ -f "$seen" ] && prev=$(head -n1 "$seen" 2>/dev/null | tr -dc '0-9')
  prev=${prev:-0}
  if [ "$cur" -gt "$prev" ]; then
    mailbox_json=$(jq -n --arg u "$uuid" '[$u]')
  fi
fi

# --- await_ping_running: a cc-await-ping loop for THIS session is live -----
# Scoped to the session uuid when resolvable — a global match would let any
# OTHER session's watcher hold this one mechanically open forever.
await_ping=false
if [ -n "$uuid" ]; then
  pgrep -f "cc-await-ping.*$uuid" >/dev/null 2>&1 && await_ping=true
else
  pgrep -f cc-await-ping >/dev/null 2>&1 && await_ping=true
fi

# --- fired_peers_alive: live session names matching passed slugs ----------
peers_json='[]'
if [ "${#SLUGS[@]}" -gt 0 ]; then
  names=""
  if names=$("$SESSIONS_BIN" --names 2>/dev/null); then
    matched=""
    while IFS= read -r nm; do
      [ -n "$nm" ] || continue
      for s in "${SLUGS[@]}"; do
        case "$nm" in
          *"$s"*) matched="${matched}${nm}"$'\n'; break ;;
        esac
      done
    done <<EOF
$names
EOF
    if [ -n "$matched" ]; then
      peers_json=$(printf '%s' "$matched" | jq -R . | jq -s 'map(select(length>0))')
    fi
  else
    note "cc-sessions unavailable (fired_peers_alive=[])"
  fi
fi

# --- open_tasks: pending + in_progress from a task summary ----------------
open_tasks=null
if [ -n "$TASKLIST" ]; then
  summary="$TASKS_DIR/$TASKLIST/_summary.json"
  if [ -f "$summary" ]; then
    ot=$(jq -r '((.pending // 0) + (.in_progress // 0))' "$summary" 2>/dev/null)
    case "$ot" in
      ''|*[!0-9]*) note "task summary unparseable (open_tasks=null)" ;;
      *)           open_tasks="$ot" ;;
    esac
  else
    note "task summary absent (open_tasks=null)"
  fi
fi

# --- assemble JSON --------------------------------------------------------
out=$(jq -cn \
  --argjson dirty "$dirty" \
  --argjson mailbox "$mailbox_json" \
  --argjson await "$await_ping" \
  --argjson peers "$peers_json" \
  --argjson tasks "$open_tasks" \
  '{dirty:$dirty, mailbox_pending:$mailbox, await_ping_running:$await, fired_peers_alive:$peers, open_tasks:$tasks}')
printf '%s\n' "$out"

# --- verdict --------------------------------------------------------------
mb_n=$(printf '%s' "$mailbox_json" | jq 'length')
peers_n=$(printf '%s' "$peers_json" | jq 'length')
tasks_open=0
[ "$open_tasks" != null ] && [ "$open_tasks" -gt 0 ] 2>/dev/null && tasks_open=1

reason=0
{ [ "$dirty" -gt 0 ] || [ "$mb_n" -gt 0 ] || [ "$await_ping" = true ] \
  || [ "$peers_n" -gt 0 ] || [ "$tasks_open" -eq 1 ]; } && reason=1

# human summary fields
mb_disp=$mb_n
ap_disp=no; [ "$await_ping" = true ] && ap_disp=yes
peers_disp=$(printf '%s' "$peers_json" | jq -r 'join(",")'); [ -z "$peers_disp" ] && peers_disp=none
tasks_disp=$open_tasks

if [ "$reason" -eq 1 ]; then
  echo "handoff-disposition: dirty=$dirty mailbox=$mb_disp await-ping=$ap_disp peers=$peers_disp tasks=$tasks_disp${notes:+ ($notes)} -> mechanical reasons EXIST (exit 1)" >&2
  exit 1
else
  echo "handoff-disposition: no mechanical reason${notes:+ ($notes)} -> close-eligible pending R-USER/R-DECIDE judgment (exit 0)" >&2
  exit 0
fi
