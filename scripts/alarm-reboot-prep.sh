#!/usr/bin/env bash
# alarm-reboot-prep.sh — the agent half of the safe reboot order, run whenever the capacity alarm's
# kalloc rung fires (host-memory.2 of the 2026-09-30 backlog master plan).
#
# WHY A STANDING PROCEDURE. data.kalloc.1024 is a kernel zone only a reboot resets. It read
# 14.78 GB after 13.8 days on the 2026-09-16 boot (1.05 GB/day measured) and panic #5 died at
# 9.89 GB, so a reboot buys roughly 5 days to the 6 GB alarm and 9 to the panic level until the
# driver is fixed (docs/research/kalloc-ratchet-2026-10.md). The first reboot, on 2026-09-30, went
# in a safe order; this script is that order, so every later one repeats it instead of improvising:
#
#   1. record the start epoch        ~/.claude/autonomy/reboot-<date>.start
#   2. record the live-session roster ~/.claude/autonomy/reboot-<date>.roster.json  (cc-sessions --json;
#      the resume path relaunches from it after login)
#   3. refuse while a land is in flight (a ship-land.sh PROCESS) — a reboot mid-push strands the land
#   4. record the kalloc reading the reboot is about to erase ~/.claude/autonomy/reboot-<date>.kalloc
#      (its OWN file: appended to .start as a second line, it made boot-resume.sh skip every roster
#      this script wrote, because the reader took the whole file as the epoch — W3 P3a-i, 2026-10-04)
#   5. print the operator's steps: long-running leads write a handoff first; if a root zone capture
#      is staged (~/.claude/autonomy/kalloc-root-capture.cmd, written by the ratchet analysis when
#      it could not name a driver), run it BEFORE rebooting, because the reboot erases the evidence;
#      then reboot within 24 h of the alarm. If ~/.claude/autonomy/kitty-restart-pending exists,
#      this reboot is also the kitty restart (plan W3) and the script says so.
#
#   6. THE ARRANGEMENT (2026-10-13): take a restore heartbeat now (scripts/lib/restore-heartbeat.sh
#      hb_tick, stamped with step 1's epoch), so the record boot-resume.sh restores from holds kitty's
#      tree as it is at this moment: OS windows, tabs, split geometry, which session sits in which
#      pane, and the non-Claude panes with their cwd. cc-resume-layout.sh --restore already replays
#      such a tree; what was missing is one taken at the reboot instead of up to a tick before it, and
#      a check on it. The check: the tree was read in this run (up to CC_REBOOT_PREP_TRIES=3 tries,
#      15 s each: kitty's remote control times out under load) and every session pane is in it.
#      A tree that fails is marked <heartbeat dir>/hb.layout-degraded, and the restore then uses its
#      plain row layout for that kitty, never half of an arrangement.
#   7. THE DRAFTS (2026-10-13): save the text sitting unsent in each pane's prompt box to
#      ~/.claude/autonomy/reboot-<date>.drafts/<session id>/ (directory 700, files 600; a draft may
#      hold a secret). boot-resume.sh types each one back, unsent, into the pane its session came
#      back in and deletes it. Reading is `kitty @ get-text` only (scripts/lib/reboot-drafts.sh): this
#      script sends no key to any pane, clears no box and submits nothing. A box it cannot read (a
#      dialog over it) is counted and left alone. Draft directories older than 7 days are removed.
#
# --dry-run: steps 6 and 7 against the live machine, writing no reboot record: the heartbeat goes to
# <dir>/reboot-prep-dryrun/, the tree is printed pane by pane, drafts are counted and not stored, and
# the cc-resume-layout.sh command that prints the restore plan for that capture is named.
#
# It never reboots, never kills a session and never runs sudo: those are the operator's.
# Exit: 0 READY · 3 NOT-READY (a land is in flight; re-run when it finishes) · 2 usage.
# Env:  CC_REBOOT_PREP_DIR (default ~/.claude/autonomy) · CC_REBOOT_PREP_DATE (default today, local)
#       CC_REBOOT_PREP_PS (default /bin/ps; stub for tests) · CC_REBOOT_PREP_SESSIONS (default cc-sessions)
#       CC_REBOOT_PREP_ZPRINT (default /usr/bin/zprint) · CC_REBOOT_PREP_TRIES (3) ·
#       CC_HEARTBEAT_DIR (default <dir>/heartbeat) and the heartbeat library's own seams
set -uo pipefail

DRY=0
case "${1:-}" in
  -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d'; exit 0 ;;
  --dry-run) DRY=1 ;;
  '') ;;
  *) echo "usage: $0 [--dry-run] [--help]" >&2; exit 2 ;;
esac

DIR="${CC_REBOOT_PREP_DIR:-$HOME/.claude/autonomy}"
DAY="${CC_REBOOT_PREP_DATE:-$(date +%Y-%m-%d)}"
PS="${CC_REBOOT_PREP_PS:-/bin/ps}"
SESSIONS="${CC_REBOOT_PREP_SESSIONS:-cc-sessions}"
ZPRINT="${CC_REBOOT_PREP_ZPRINT:-/usr/bin/zprint}"
CAPTURE_CMD="$DIR/kalloc-root-capture.cmd"
mkdir -p "$DIR" || { echo "alarm-reboot-prep: cannot create $DIR" >&2; exit 2; }

now="$(date +%s)"
roster="$DIR/reboot-$DAY.roster.json"
n=""
if [ "$DRY" = 0 ]; then
  printf '%s\n' "$now" > "$DIR/reboot-$DAY.start"
  if "$SESSIONS" --json > "$roster.tmp" 2>/dev/null && [ -s "$roster.tmp" ]; then
    mv -f "$roster.tmp" "$roster"
    n="$(grep -o '"paneUUID"' "$roster" 2>/dev/null | wc -l | tr -d ' ')"   # occurrences, not lines
  else
    rm -f "$roster.tmp"; n="unknown (cc-sessions failed — record the panes by hand)"
  fi
fi

# ── 6. the arrangement, 7. the drafts (see the header). Both libraries resolve beside this file,
#    then in the live layer; missing is loud, never fatal: the roster above still restores the fleet.
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
for _lib in restore-heartbeat.sh reboot-drafts.sh; do
  for _c in "$HERE/lib/$_lib" "$HOME/.claude/scripts/lib/$_lib"; do
    # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
    [ -f "$_c" ] && . "$_c" 2>/dev/null && break
  done
done
unset _lib _c

SNAP_ROOT="${CC_HEARTBEAT_DIR:-$DIR/heartbeat}"
if [ "$DRY" = 1 ]; then
  rm -rf "${DIR:?}/reboot-prep-dryrun"
  ( umask 077; mkdir -p "$DIR/reboot-prep-dryrun" ) 2>/dev/null
  SNAP_ROOT="$DIR/reboot-prep-dryrun/heartbeat"
fi
export CC_HEARTBEAT_DIR="$SNAP_ROOT" CC_HB_NOW="$now" CC_HB_LS_TIMEOUT="${CC_HB_LS_TIMEOUT:-15}"
# The heartbeat reads the same cc-sessions this script was pointed at (a path; a bare name is its own default).
[ -n "${CC_REBOOT_PREP_SESSIONS:-}" ] && [ -z "${CC_HB_SESSIONS_BIN:-}" ] && export CC_HB_SESSIONS_BIN="$CC_REBOOT_PREP_SESSIONS"
TRIES="${CC_REBOOT_PREP_TRIES:-3}"

snap_check() { # <heartbeat kitty dir> → nothing when its tree is whole, else one line saying why not
  local d="$1" tree m miss
  tree="$d/hb.kitty-ls.json"
  [ -f "$tree" ] || { echo "kitty did not answer the tree read"; return 0; }
  # Read in THIS run: a failed read leaves the last good file in place (the heartbeat's rule), and
  # that one describes an earlier moment.
  m="$(/usr/bin/stat -f %m "$tree" 2>/dev/null || stat -c %Y "$tree" 2>/dev/null)"
  case "$m" in ''|*[!0-9]*) m=0 ;; esac
  [ "$m" -ge "$now" ] || { echo "kitty did not answer the tree read (the tree on disk is from $(date -r "$m" '+%H:%M:%S' 2>/dev/null || echo "$m"))"; return 0; }
  miss="$(jq -r --slurpfile r "$d/hb.roster.json" '
      [ .[]?.tabs[]?.windows[]?.id | tostring ] as $ids
      | [ $r[0][]? | select(type == "object" and (.session_id // "") != "") | ((.paneUUID // "") | tostring)
          | select(. == "" or (. as $p | $ids | index($p) | not)) ] | length' "$tree" 2>/dev/null)"
  case "$miss" in ''|*[!0-9]*) echo "the tree could not be read back"; return 0 ;; esac
  [ "$miss" = 0 ] || echo "$miss session pane(s) are not in the tree"
  return 0
}

SNAP_DIRS=""; n_kitty=0; n_degraded=0; hb_rc=127; layout_v=none
if command -v hb_tick >/dev/null 2>&1; then
  uuid="$(_hb_bootuuid)"; [ -n "$uuid" ] || uuid=nouuid
  try=0
  while :; do
    try=$((try + 1))
    hb_tick >/dev/null 2>&1; hb_rc=$?
    SNAP_DIRS=""; n_kitty=0; n_degraded=0
    for d in "$SNAP_ROOT/$uuid"/*; do
      [ -d "$d" ] || continue
      case "${d##*/}" in 0|*[!0-9]*) continue ;; esac          # 0 = the sessions outside any kitty
      [ "$(_hb_start_of "$d")" = "$now" ] || continue          # this run's tick only
      n_kitty=$((n_kitty + 1)); SNAP_DIRS="${SNAP_DIRS}${d}
"
      [ -z "$(snap_check "$d")" ] || n_degraded=$((n_degraded + 1))
    done
    { [ "$n_degraded" -gt 0 ] || [ "$hb_rc" = 2 ]; } && [ "$try" -lt "$TRIES" ] || break
  done
fi

ARR=""      # the lines to print, one per kitty
while IFS= read -r d; do
  [ -n "$d" ] || continue
  why="$(snap_check "$d")"
  if [ -n "$why" ]; then
    printf '%s\n' "$why" > "$d/hb.layout-degraded"
    ARR="${ARR}  arrangement        kitty ${d##*/}: DEGRADED after ${try} tries — ${why}. The restore will use its plain
                     row layout for this kitty, NOT the arrangement on screen now.
"
    continue
  fi
  rm -f "$d/hb.layout-degraded"
  counts="$(jq -r --slurpfile r "$d/hb.roster.json" '
      [ $r[0][]? | select(type == "object" and (.session_id // "") != "") | ((.paneUUID // "") | tostring) ] as $s
      | [ .[]?.tabs[]?.windows[]? ] as $w
      | "\(length) OS window(s), \([.[]?.tabs | length] | add // 0) tab(s), \($w | length) pane(s): \([$w[] | select((.id | tostring) as $i | $s | index($i))] | length) session(s), \([$w[] | select((.id | tostring) as $i | $s | index($i) | not)] | length) other"' \
      "$d/hb.kitty-ls.json" 2>/dev/null)"
  ARR="${ARR}  arrangement        kitty ${d##*/}: ${counts:-recorded} → $d/hb.kitty-ls.json
"
  if [ "$DRY" = 1 ]; then
    ARR="${ARR}$(jq -r --slurpfile r "$d/hb.roster.json" '
      ($r[0] | map(select(type == "object" and (.session_id // "") != "")
                   | {key: ((.paneUUID // "") | tostring), value: (.session_id[0:8] + "  " + ((.name // "") | tostring))})
             | from_entries) as $m
      | .[]? | "      OS window \(.id): \(.tabs | length) tab(s)",
          (.tabs | to_entries[] | "        tab \(.key + 1) [\(.value.layout // "?")]",
             (.value.windows[]? | "          pane \(.id)  " + (if $m[(.id | tostring)] then "session " + $m[(.id | tostring)]
                                                                else "shell in " + ((.cwd // "?") | tostring) end)))' \
      "$d/hb.kitty-ls.json" 2>/dev/null)
      restore plan:  $HERE/../bin/cc-resume-layout.sh --desktops --restore --dry-run --tree $d/hb.kitty-ls.json </dev/null
"
  fi
done <<EOF
$SNAP_DIRS
EOF
if [ "$n_kitty" -gt 0 ]; then
  layout_v=ok; [ "$n_degraded" -gt 0 ] && layout_v=degraded
elif [ "$hb_rc" = 127 ]; then
  layout_v=failed
  ARR="  arrangement        NOT RECORDED — scripts/lib/restore-heartbeat.sh did not load. The restore will use its plain row layout.
"
elif [ "$hb_rc" = 2 ]; then
  layout_v=failed
  ARR="  arrangement        NOT RECORDED after ${try} tries — the heartbeat could not be taken (cc-sessions failed). The restore
                     will use its plain row layout.
"
else
  ARR="  arrangement        none to record (no session runs in a kitty pane)
"
fi

# The drafts, from the sessions the heartbeat just listed (else the roster above).
DRAFTS="$DIR/reboot-$DAY.drafts"
droster="$DIR/.reboot-prep-roster.$$"
d_sum=""; d_line=""
if [ -n "$SNAP_DIRS" ]; then
  while IFS= read -r d; do [ -n "$d" ] && cat "$d/hb.roster.json" 2>/dev/null; done <<EOF | jq -s 'add // []' > "$droster" 2>/dev/null
$SNAP_DIRS
EOF
elif [ "$DRY" = 0 ] && [ -s "$roster" ]; then
  cp "$roster" "$droster" 2>/dev/null
fi
if [ "$DRY" = 0 ]; then
  # Today's earlier capture is replaced (what is in the boxes NOW is the truth), old ones expire.
  rm -rf "${DRAFTS:?}"
  for d in "$DIR"/reboot-*.drafts; do
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    st="$(head -n 1 "${d%.drafts}.start" 2>/dev/null | awk '{ print $1 }')"
    case "$st" in ''|*[!0-9]*) st="$(/usr/bin/stat -f %m "$d" 2>/dev/null || stat -c %Y "$d" 2>/dev/null)" ;; esac
    case "$st" in ''|*[!0-9]*) continue ;; esac
    [ $((now - st)) -gt 604800 ] && rm -rf "${DIR:?}/${d##*/}"
  done
fi
if ! command -v rd_capture >/dev/null 2>&1; then
  d_line="NOT CAPTURED — scripts/lib/reboot-drafts.sh did not load"
elif [ ! -s "$droster" ]; then
  d_line="none to capture (no session list)"
else
  if [ "$DRY" = 1 ]; then d_sum="$(rd_capture "$droster" "" 2>/dev/null)"; else d_sum="$(rd_capture "$droster" "$DRAFTS" 2>/dev/null)"; fi
  if [ -z "$d_sum" ]; then
    d_line="NOT CAPTURED — the prompt-box reader did not load"
  else
    dv() { printf '%s\n' "$d_sum" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -n 1; }
    d_line="$(dv saved) non-empty"
    if [ "$DRY" = 1 ]; then d_line="${d_line} (counted, not stored: dry run)"; else d_line="${d_line}, saved"; fi
    [ "$(dv partial)" -gt 0 ] 2>/dev/null && d_line="${d_line} ($(dv partial) hold a pasted block that exists only in the session's memory and cannot be saved)"
    d_line="${d_line}; $(dv empty) empty"
    [ "$(dv unreadable)" -gt 0 ] 2>/dev/null && d_line="${d_line}; $(dv unreadable) unreadable (a dialog over the box, or no answer) and left alone"
    [ "$(dv unread)" -gt 0 ] 2>/dev/null && d_line="${d_line}; $(dv unread) NOT READ (kitty stopped answering inside the ${CC_REBOOT_DRAFT_BUDGET:-120}s budget)"
    [ "$DRY" = 0 ] && [ -d "$DRAFTS" ] && d_line="${d_line} → $DRAFTS"
  fi
fi
rm -f "$droster"

if [ "$DRY" = 1 ]; then
  echo "alarm-reboot-prep --dry-run — $(date '+%Y-%m-%d %H:%M %z') (no reboot record written)"
  printf '%s' "$ARR"
  echo "  unsent drafts      $d_line"
  echo "capture layout=$layout_v kitty=$n_kitty degraded=$n_degraded ${d_sum:-drafts=none}"
  echo "verdict=DRY-RUN"
  exit 0
fi

kalloc="$("$ZPRINT" data.kalloc.1024 2>/dev/null \
          | awk '$1 == "data.kalloc.1024" && $7 ~ /^[0-9]+$/ { printf "%.2f", $2 * $7 / 1073741824; exit }')"
printf '%s kalloc1024_gb=%s\n' "$now" "${kalloc:-unreadable}" > "$DIR/reboot-$DAY.kalloc"

# A land in flight is a process whose PROGRAM is ship-land.sh (argv[0], or argv[1] under a shell) —
# never `pgrep -f ship-land.sh`, which also matches every agent session whose brief merely MENTIONS
# the name (measured 2026-09-30: 6 of 6 matches were claude sessions, 0 were lands).
lands="$("$PS" -axo pid=,args= 2>/dev/null | awk '
  { a0 = $2; a1 = $3 }
  a0 ~ /(^|\/)ship-land\.sh$/ { print $1; next }
  a0 ~ /(^|\/)(ba|z|da)?sh$/ && a1 ~ /(^|\/)ship-land\.sh$/ { print $1 }' | tr '\n' ' ')"

echo "alarm-reboot-prep — $(date '+%Y-%m-%d %H:%M %z')"
echo "  start epoch        $now  → $DIR/reboot-$DAY.start"
echo "  live sessions      $n  → $roster"
printf '%s' "$ARR"
echo "  unsent drafts      $d_line"
echo "capture layout=$layout_v kitty=$n_kitty degraded=$n_degraded ${d_sum:-drafts=none}"
echo "  data.kalloc.1024   ${kalloc:-unreadable} GB (the reading this reboot erases) → $DIR/reboot-$DAY.kalloc"
if [ -n "${lands// /}" ]; then
  echo "  lands in flight    pids ${lands% } — NOT READY: re-run when ship-land.sh has exited"
  echo "verdict=NOT-READY reason=land-in-flight"
  exit 3
fi
echo "  lands in flight    none"
echo
echo "Operator steps, in order:"
echo "  1. Long-running leads write a handoff first (the FLEET_V2 lead included); every other"
echo "     session resumes from its own handoff or from the roster above."
if [ -s "$CAPTURE_CMD" ]; then
  echo "  2. A root zone capture is STAGED. Run it before rebooting — the reboot erases the evidence:"
  echo "       bash $CAPTURE_CMD"
  echo "  3. Reboot within 24 h of the alarm."
else
  echo "  2. Reboot within 24 h of the alarm. (No root capture is staged: the ratchet analysis named"
  echo "     a driver, or has not asked for one.)"
fi
# The kitty restart rides the next alarm reboot after the operator's kitty build choice (plan W3):
# whoever stages the build drops this marker with one line saying what the restart installs.
if [ -s "$DIR/kitty-restart-pending" ]; then
  echo "  This reboot is ALSO the kitty restart: $(head -1 "$DIR/kitty-restart-pending")"
  echo "     (remove $DIR/kitty-restart-pending once kitty is back on the new build)"
fi
echo "  After login, resume sessions with the resume-sessions skill; the next capacity-alarm tick"
echo "  should read data.kalloc.1024 under 3 GB."
echo "verdict=READY"
exit 0
