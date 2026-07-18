#!/bin/bash
# handoff-disposition.sh — un-fakeable reads of the MECHANICAL reasons a
# post-handoff session must stay OPEN. The model adds only R-USER/R-DECIDE
# judgment on top; this script never guesses.
#
# Usage:
#   handoff-disposition.sh [--session <uuid>] [--cwd <path>] [--tasklist <id>]
#                          [--deliverable <path> ...] [--payload <file>] [--ack] [slug ...]
#
# Output:
#   stdout — ONE compact JSON object:
#     {"dirty":<n>,"mailbox_pending":["<uuid>",...],"await_ping_running":<bool>,
#      "fired_peers_alive":["<name>",...],"open_tasks":<n or null>,
#      "registry_indeterminate":<bool>,"deliverables_missing":["<path>",...]}
#   stderr — ONE human summary line.
#
# Exit codes:
#   0 = no mechanical reason (close-eligible pending R-USER/R-DECIDE judgment)
#   1 = ≥1 mechanical reason exists
#   2 = usage error
#
# A mechanical reason EXISTS (exit 1) iff: dirty>0 OR mailbox_pending non-empty
# OR await_ping_running OR fired_peers_alive non-empty OR open_tasks>0
# OR registry_indeterminate (R-REGISTRY-INDETERMINATE) OR deliverables_missing non-empty.
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
#   fired_peers_alive  live cc-sessions --names word-boundary-matching a passed slug (grep -Fw:
#                      "ship" hits "ship-hardening", never "relationship-tracker").
#   open_tasks         (--tasklist only) .pending + .in_progress from the task _summary.json.
#   registry_indeterminate  true iff cc-sessions was present but ERRORED (rc≠0/malformed) — the
#                      registry is unreadable, so peers are UNKNOWN: fail-CLOSED to OPEN rather
#                      than mistaking an unreadable registry for "no peers". rc 127 (absent) and
#                      rc 0 with empty output are NOT indeterminate.
#   deliverables_missing  declared `DELIVERABLE: <path>` (via --deliverable or extracted from
#                      --payload) that is absent OR zero-length — the completeness axis (a19 §4).
#                      Relative paths resolve against --cwd.
#
# Env overrides (tests):
#   CC_MAILBOX_DIR  (default ~/.claude/mailbox)
#   CC_SESSIONS_BIN (default ~/.claude/bin/cc-sessions)
#   CC_TASKS_DIR    (default ~/.claude/tasks)
set -uo pipefail

MAILBOX_DIR="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
SESSIONS_BIN="${CC_SESSIONS_BIN:-$HOME/.claude/bin/cc-sessions}"
TASKS_DIR="${CC_TASKS_DIR:-$HOME/.claude/tasks}"

usage() { sed -n '2,49p' "$0" | sed 's/^# \{0,1\}//'; }

SESSION=""
CWD="$PWD"
TASKLIST=""
ACK=0
SLUGS=()
DELIVERABLES=()
PAYLOAD=""

while [ $# -gt 0 ]; do
  case "$1" in
    --session)     SESSION="${2:?--session needs a value}"; shift 2 ;;
    --cwd)         CWD="${2:?--cwd needs a value}"; shift 2 ;;
    --tasklist)    TASKLIST="${2:?--tasklist needs a value}"; shift 2 ;;
    --deliverable) DELIVERABLES+=("${2:?--deliverable needs a value}"); shift 2 ;;
    --payload)     PAYLOAD="${2:?--payload needs a value}"; shift 2 ;;
    --ack)         ACK=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    --*)           echo "handoff-disposition: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    *)             SLUGS+=("$1"); shift ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "handoff-disposition: jq required" >&2; exit 2; }

# A payload can DECLARE its outputs with `DELIVERABLE: <path>` lines — extract them so the
# completeness axis (below) can check the delegated work actually landed (a19 §4).
if [ -n "$PAYLOAD" ] && [ -f "$PAYLOAD" ]; then
  while IFS= read -r dl; do
    [ -n "$dl" ] && DELIVERABLES+=("$dl")
  done < <(grep -oE 'DELIVERABLE:[[:space:]]*[^[:space:]]+' "$PAYLOAD" 2>/dev/null | sed -E 's/^DELIVERABLE:[[:space:]]*//')
fi

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
# Three cc-sessions outcomes, kept distinct so an UNREADABLE registry can never read as "no peers"
# (G-P1-7 — a desk self-closing while its wave is still alive):
#   rc 127 (binary absent)   → feature unavailable → [] (machines without the comms stack stay usable)
#   rc≠0   (present, errored) → registry INDETERMINATE → fail-CLOSED to OPEN (R-REGISTRY-INDETERMINATE)
#   rc 0   (incl. empty out)  → a GENUINE read → [] means no matching live peer (real close-eligible)
peers_json='[]'
registry_indeterminate=false
if [ "${#SLUGS[@]}" -gt 0 ]; then
  names=$("$SESSIONS_BIN" --names 2>/dev/null); rc=$?
  if [ "$rc" -eq 127 ]; then
    note "cc-sessions unavailable (fired_peers_alive=[])"
  elif [ "$rc" -ne 0 ]; then
    registry_indeterminate=true
    note "cc-sessions errored rc=$rc (R-REGISTRY-INDETERMINATE — fail-closed to OPEN)"
  else
    matched=""
    while IFS= read -r nm; do
      [ -n "$nm" ] || continue
      for s in "${SLUGS[@]}"; do
        # WORD-BOUNDARY match (grep -Fw): a slug matches a hyphen/underscore-delimited token, never a
        # bare substring — "ship" hits "ship-hardening" but NOT "relationship-tracker" (false OPEN).
        if printf '%s\n' "$nm" | grep -Fqw -- "$s"; then
          matched="${matched}${nm}"$'\n'; break
        fi
      done
    done <<EOF
$names
EOF
    if [ -n "$matched" ]; then
      peers_json=$(printf '%s' "$matched" | jq -R . | jq -s 'map(select(length>0))')
    fi
  fi
fi

# --- deliverables_missing: declared DELIVERABLE paths that are absent/empty ------------------
# Completeness axis (a19 §4): a fired peer that returns a PARTIAL deliverable then dies leaves
# fired_peers_alive=[] → the mechanical read would green-light a close over incomplete work.
# A declared DELIVERABLE that is absent OR zero-length is itself a stay-OPEN reason.
deliverables_missing='[]'
if [ "${#DELIVERABLES[@]}" -gt 0 ]; then
  miss=""
  for d in "${DELIVERABLES[@]}"; do
    case "$d" in /*) p="$d" ;; *) p="$CWD/$d" ;; esac
    [ -s "$p" ] || miss="${miss}${d}"$'\n'
  done
  [ -n "$miss" ] && deliverables_missing=$(printf '%s' "$miss" | jq -R . | jq -s 'map(select(length>0))')
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
  --argjson regind "$registry_indeterminate" \
  --argjson delivmiss "$deliverables_missing" \
  '{dirty:$dirty, mailbox_pending:$mailbox, await_ping_running:$await, fired_peers_alive:$peers, open_tasks:$tasks, registry_indeterminate:$regind, deliverables_missing:$delivmiss}')
printf '%s\n' "$out"

# --- verdict --------------------------------------------------------------
mb_n=$(printf '%s' "$mailbox_json" | jq 'length')
peers_n=$(printf '%s' "$peers_json" | jq 'length')
deliv_n=$(printf '%s' "$deliverables_missing" | jq 'length')
tasks_open=0
[ "$open_tasks" != null ] && [ "$open_tasks" -gt 0 ] 2>/dev/null && tasks_open=1

reason=0
{ [ "$dirty" -gt 0 ] || [ "$mb_n" -gt 0 ] || [ "$await_ping" = true ] \
  || [ "$peers_n" -gt 0 ] || [ "$tasks_open" -eq 1 ] \
  || [ "$registry_indeterminate" = true ] || [ "$deliv_n" -gt 0 ]; } && reason=1

# human summary fields
mb_disp=$mb_n
ap_disp=no; [ "$await_ping" = true ] && ap_disp=yes
peers_disp=$(printf '%s' "$peers_json" | jq -r 'join(",")'); [ -z "$peers_disp" ] && peers_disp=none
tasks_disp=$open_tasks
reg_disp=ok; [ "$registry_indeterminate" = true ] && reg_disp=INDETERMINATE
deliv_disp=$(printf '%s' "$deliverables_missing" | jq -r 'join(",")'); [ -z "$deliv_disp" ] && deliv_disp=none

if [ "$reason" -eq 1 ]; then
  echo "handoff-disposition: dirty=$dirty mailbox=$mb_disp await-ping=$ap_disp peers=$peers_disp tasks=$tasks_disp registry=$reg_disp deliverables-missing=$deliv_disp${notes:+ ($notes)} -> mechanical reasons EXIST (exit 1)" >&2
  exit 1
else
  echo "handoff-disposition: no mechanical reason${notes:+ ($notes)} -> close-eligible pending R-USER/R-DECIDE judgment (exit 0)" >&2
  exit 0
fi
