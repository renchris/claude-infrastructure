#!/bin/bash
# worktree-gc-wake.sh — the event-driven half of the worktree janitor: evaluate only the worktrees
# an event has named, once their grace has run out. DESIGN docs/research/load-root-cause-2026-10-17/
# DESIGN.md §3.4 ("How a wake run evaluates"), WP-15.
#
# Run by `worktree-gc-infra-run.sh --auto|--wake`, which launchd starts on a WatchPaths touch of
# ~/.claude/state/worktree-gc.wake and on a 600 s tick. The tick is why the idle path must be O(1):
# no new event bytes and no due queue row ⇒ exit 0 with no git fork and no log row.
#
# THE QUEUE. Producers (hooks/live-session-registry.sh on SessionEnd, cc-reaper on pane teardown, …)
# append `{"ev","path","sid","repo","ts"}` rows to $WT_EVENTS_FILE through wt_emit_event. This run
# reads the bytes past its cursor and folds them into ~/.claude/state/wt-queue.tsv, one row per path:
#   path <TAB> not_before <TAB> ev <TAB> sid
# not_before = event time + grace (CC_WTGC_GRACE_S, 24 h); a newer event for the path resets it.
# The events file is the source of truth and the wake file only a hint, so a lost touch costs at
# most one tick.
#
# EVALUATION, per due row: drop what is neither a linked worktree nor parked; apply the repo-scope
# table (scripts/lib/wtgc-scope.sh) FIRST — reso-management-app is never touched, a foreign repo is
# observe-only until the operator promotes it, and nothing acts unless the mode switch says `act`;
# then ONE `worktree-gc.sh --park-first --path …` per repo, with --dry-run unless that repo's scope
# is act. Never --prune-branches, never --dispose-landed-dirt, never a fetch: a stale trunk can only
# turn a PARK into a KEEP. Each path's decision line is logged to ~/.claude/logs/worktree-gc-wake.log
# (not the backstop's log) and decides whether the row is dequeued or requeued (table below).
#
# Seams (production defaults; the bats suite points every one into a throwaway HOME):
#   CC_WTGC_INFRA_REPO  home repo (/Users/chrisren/Development/claude-infrastructure)
#   CC_WTGC_INFRA_GC    the janitor (<home repo>/scripts/worktree-gc.sh, as worktree-gc-infra-run.sh)
#   CC_WTGC_WAKE_LOG    this run's log      CC_WTGC_GRACE_S  grace after an event (86400)
#   CC_WTGC_WAKE_DEBOUNCE_S  minimum gap between run starts (60)     WT_NOW  lab clock (epoch)
#   WT_EVENTS_FILE      the event queue     CC_WT_TOMBSTONE_LIB  the park-index library
#   plus wtgc-scope.sh's own (WTGC_EVENTS, CC_WTGC_EVENTS_MODE_FILE, CC_WTGC_PROMOTED_FILE, …).
# bash 3.2-safe (launchd runs /bin/bash): no associative arrays, no mapfile.

# CRITICAL — PATH, identical to worktree-gc-infra-run.sh:18. lsof lives in /usr/sbin; without it
# every liveness gate in worktree-gc.sh reads empty and a LIVE worktree looks dead.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
set -uo pipefail

case "${BASH_SOURCE[0]}" in */*) HERE="${BASH_SOURCE[0]%/*}" ;; *) HERE="." ;; esac
HOME_REPO="${CC_WTGC_INFRA_REPO:-/Users/chrisren/Development/claude-infrastructure}"
HOME_REPO="${HOME_REPO%/}"
GC_SH="${CC_WTGC_INFRA_GC:-$HOME_REPO/scripts/worktree-gc.sh}"
STATE="$HOME/.claude/state"
EVENTS="${WT_EVENTS_FILE:-$STATE/wt-events.jsonl}"
QUEUE="$STATE/wt-queue.tsv"
CURSOR="$STATE/wt-queue.cursor"
STAMP="$STATE/worktree-gc-wake.started"
LOCK="$STATE/worktree-gc-wake.lock"
INFRA_LOCK="$STATE/worktree-gc-infra.lock"     # the 04:15 backstop's own lock (worktree-gc-infra-run.sh:29)
LOG="${CC_WTGC_WAKE_LOG:-$HOME/.claude/logs/worktree-gc-wake.log}"
TOMB_LIB="${CC_WT_TOMBSTONE_LIB:-$HERE/lib/wt-tombstone.sh}"
GRACE="${CC_WTGC_GRACE_S:-86400}"
DEBOUNCE="${CC_WTGC_WAKE_DEBOUNCE_S:-60}"
case "$GRACE" in ''|*[!0-9]*) GRACE=86400 ;; esac
case "$DEBOUNCE" in ''|*[!0-9]*) DEBOUNCE=60 ;; esac
# A row with no verdict at all (the janitor's own mutex was held, or it crashed) is retried after an
# hour rather than a full grace: nothing was decided, so nothing should wait a day for it.
RETRY_S=3600
TAB="$(printf '\t')"

NOW="${WT_NOW:-$(date +%s)}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log() { mkdir -p "${LOG%/*}" 2>/dev/null; printf '%s %s\n' "$TS" "$*" >> "$LOG" 2>/dev/null; }

# ── Debounce: a burst of wake touches (a teammate wave closing) starts one run, not twenty. The
#    stamp holds the epoch the previous run STARTED, read with `read`, so this costs no fork. A
#    stamp from the future (clock step) is ignored rather than trusted to silence every run.
if read -r _last _ < "$STAMP" 2>/dev/null; then
  case "$_last" in
    ''|*[!0-9]*) ;;
    *) if [ "$NOW" -ge "$_last" ] && [ $((NOW - _last)) -lt "$DEBOUNCE" ]; then exit 0; fi ;;
  esac
fi

# ── Singleton. mkdir is the atomic test-and-set; a holder that is provably gone (dead pid, or no
#    pid written and the lock older than 10 min) is cleared once and the mkdir retried.
mkdir -p "$STATE" 2>/dev/null
if ! mkdir "$LOCK" 2>/dev/null; then
  _hp=""; read -r _hp _ < "$LOCK/pid" 2>/dev/null
  case "$_hp" in ''|*[!0-9]*) _hp="" ;; esac
  if { [ -n "$_hp" ] && ! kill -0 "$_hp" 2>/dev/null; } \
     || { [ -z "$_hp" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ]; }; then
    rm -f "$LOCK/pid" 2>/dev/null; rmdir "$LOCK" 2>/dev/null
  fi
  mkdir "$LOCK" 2>/dev/null || exit 0       # a live run holds it: it will see our events
fi
printf '%s\n' "$$" > "$LOCK/pid" 2>/dev/null
trap 'rm -f "$LOCK/pid" 2>/dev/null; rmdir "$LOCK" 2>/dev/null' EXIT INT TERM
printf '%s\n' "$NOW" > "$STAMP" 2>/dev/null

# ── Ingest: fold the event bytes past the cursor into the queue. Only COMPLETE lines are consumed;
#    a row a producer is still appending stays past the cursor for the next run. An events file
#    shorter than the cursor was truncated or rotated, so it is reread from 0. jq's `fromjson?`
#    skips malformed lines, and the event's own ts (not ingest time) starts the grace.
ingest() {
  local LC_ALL=C size cur=0 chunk tail_part fold
  [ -f "$EVENTS" ] || return 0
  size="$(stat -f %z "$EVENTS" 2>/dev/null)"
  case "$size" in ''|*[!0-9]*) return 0 ;; esac
  read -r cur _ < "$CURSOR" 2>/dev/null
  case "$cur" in ''|*[!0-9]*) cur=0 ;; esac
  [ "$size" -lt "$cur" ] && cur=0
  [ "$size" -gt "$cur" ] || return 0
  command -v jq >/dev/null 2>&1 || { log "verdict=error reason=no-jq events-not-ingested"; return 0; }
  # The x sentinel keeps a trailing newline, which $( ) would strip, so a partial tail is visible.
  chunk="$(tail -c +$((cur + 1)) "$EVENTS" 2>/dev/null | head -c $((size - cur)); printf x)"
  chunk="${chunk%x}"
  case "$chunk" in
    *"
") tail_part="" ;;
    *"
"*) tail_part="${chunk##*
}" ;;
    *) tail_part="$chunk" ;;
  esac
  chunk="${chunk%"$tail_part"}"
  cur=$((cur + ${#chunk}))
  if [ -n "$chunk" ]; then
    # An empty ev or sid is written as "-": a TAB is IFS whitespace to `read`, so an empty middle
    # field would collapse and shift every field after it.
    fold="$(printf '%s' "$chunk" | jq -Rr --argjson now "$NOW" --argjson g "$GRACE" '
      def f: (. // "" | tostring) | if . == "" then "-" else . end;
      fromjson? | select(type == "object" and (.path | type) == "string" and (.path | length) > 0)
      | ((.ts // "") | try (strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) catch $now) as $t
      | [.path, ($t + $g | tostring), (.ev | f), (.sid | f)] | @tsv' 2>/dev/null)"
    if [ -n "$fold" ]; then
      # Later rows win: the queue first, then the events in file order, keyed on the path.
      { [ -f "$QUEUE" ] && cat "$QUEUE"; printf '%s\n' "$fold"; } \
        | awk -F'\t' 'NF >= 2 && $1 != "" { if (!($1 in row)) ord[n++] = $1; row[$1] = $0 }
                      END { for (i = 0; i < n; i++) print row[ord[i]] }' > "$QUEUE.tmp.$$" \
        && mv -f "$QUEUE.tmp.$$" "$QUEUE"
      rm -f "$QUEUE.tmp.$$" 2>/dev/null
    fi
  fi
  printf '%s\n' "$cur" > "$CURSOR.tmp.$$" && mv -f "$CURSOR.tmp.$$" "$CURSOR"
}
ingest

# ── Due rows. A pure-bash read: the idle tick forks nothing past this point.
DUE=""; KEEPQ=""; N_DUE=0
if [ -s "$QUEUE" ]; then
  while IFS="$TAB" read -r p nb ev sid || [ -n "$p" ]; do
    [ -n "$p" ] || continue
    case "$nb" in ''|*[!0-9]*) nb=0 ;; esac
    if [ "$nb" -le "$NOW" ]; then
      DUE="${DUE}${p}${TAB}${ev}${TAB}${sid}
"; N_DUE=$((N_DUE + 1))
    else
      KEEPQ="${KEEPQ}${p}${TAB}${nb}${TAB}${ev}${TAB}${sid}
"
    fi
  done < "$QUEUE"
fi
[ "$N_DUE" -gt 0 ] || exit 0

# The backstop sweeps everything; running beside it would only contend for worktree-gc's mutex.
# Checked after the due test so an idle tick stays silent while the backstop runs.
if [ -d "$INFRA_LOCK" ]; then
  _bp=""; read -r _bp _ < "$INFRA_LOCK/pid" 2>/dev/null
  case "$_bp" in ''|*[!0-9]*) _bp="" ;; esac
  if [ -n "$_bp" ] && kill -0 "$_bp" 2>/dev/null; then
    log "verdict=skipped reason=backstop-running due=$N_DUE"
    exit 0
  fi
fi

# shellcheck source=/dev/null
. "$HERE/lib/wtgc-scope.sh"
MODE="$(wtgc_events_mode)"
# git names a repo by its physical path, so the home repo is compared in that form (/var vs /private/var).
[ -d "$HOME_REPO" ] && HOME_REPO="$(cd -P -- "$HOME_REPO" 2>/dev/null && pwd -P)"
TOMB_OK=0
# shellcheck source=/dev/null
[ -f "$TOMB_LIB" ] && . "$TOMB_LIB" 2>/dev/null && [ "$(type -t wt_parked_lookup 2>/dev/null)" = function ] && TOMB_OK=1

# wk_canon <path> → physical path; for a gone path, its parent canonicalized (a parked or detached
# tree's path no longer exists, and /var vs /private/var must still compare equal).
wk_canon() {
  local p="${1%/}" d
  if [ -d "$p" ]; then (cd -P -- "$p" 2>/dev/null && pwd -P) || printf '%s\n' "$p"; return 0; fi
  d="${p%/*}"
  if [ -n "$d" ] && [ -d "$d" ]; then printf '%s/%s\n' "$(cd -P -- "$d" 2>/dev/null && pwd -P)" "${p##*/}"
  else printf '%s\n' "$p"; fi
}

REQ=""; N_EVAL=0; N_DEQ=0; N_REQ=0
requeue() { REQ="${REQ}$1${TAB}$2${TAB}$3${TAB}$4
"; N_REQ=$((N_REQ + 1)); }
row() { # <mode> <repo> <decision> <path> <reason>
  log "mode=$1 repo=${2##*/} decision=$3 path=$4 reason=$5"
}

# Resolve, scope and group. WK_ROWS: "<repo> TAB <scope> TAB <trunk> TAB <path> TAB <canon> TAB <ev> TAB <sid>".
WK_ROWS=""
while IFS="$TAB" read -r p ev sid; do
  [ -n "$p" ] || continue
  repo=""
  if [ -f "$p/.git" ]; then
    repo="$(wtgc_repo_of "$p")" || repo=""
  elif [ "$TOMB_OK" = 1 ] && _lk="$(wt_parked_lookup "$p" 2>/dev/null)"; then
    repo="${_lk%%"$TAB"*}"
  fi
  if [ -z "$repo" ]; then
    row "$MODE" "-" dropped "$p" "not a linked worktree and not parked"; N_DEQ=$((N_DEQ + 1)); continue
  fi
  scope="$(wtgc_scope "$repo" "$HOME_REPO")"
  if [ "$scope" = excluded ]; then
    row observe "$repo" dropped "$p" "scope=excluded (its own janitor owns it)"; N_DEQ=$((N_DEQ + 1)); continue
  fi
  if [ "${repo%/}" = "$HOME_REPO" ]; then trunk="origin/main"
  elif ! trunk="$(wtgc_trunk_of "$repo")"; then
    row observe "$repo" dropped "$p" "scope=no-trunk (no refs/remotes/origin/HEAD)"; N_DEQ=$((N_DEQ + 1)); continue
  fi
  WK_ROWS="${WK_ROWS}${repo}${TAB}${scope}${TAB}${trunk}${TAB}${p}${TAB}$(wk_canon "$p")${TAB}${ev}${TAB}${sid}
"
done <<EOF
$DUE
EOF

# ── KEEP-reason classification. A KEEP waiting on a CLOCK (a grace, a floor, a recent write) is
#    requeued — nothing else will name the tree again when that clock runs out. A KEEP on STATE is
#    terminal: a live or pinned session ends with its own SessionEnd event, a lock or a marker is
#    lifted by whoever set it, and the 04:15 backstop sweeps everything regardless. A KEEP that
#    reached NO verdict (a library or trunk missing, a refused git step) is retried like a clock.
#    Exception, per DESIGN §3.4: arm (ii)'s 7 d floors ("dirty-and-young": an unlanded, dirty or
#    detached tree whose tip, transcript, files or git activity is < 7 d old) are TERMINAL, not
#    clocks. Requeueing them would re-run the janitor daily for a week per tree; the 04:15 backstop
#    finds them once the floor has passed. The non-park "abandon horizon" KEEP is the same case.
#    The patterns are worktree-gc.sh's own wording (park_record, parked_record, process_record).
keep_class() { # <reason> → time | retry | terminal
  case "$1" in
    *"arm-ii floor:"*"unreadable"*)                                                   echo retry ;;
    *"arm-ii floor:"*|*"abandon horizon"*)                                            echo terminal ;;
    *"idle floor)"*|*"inside the PARK grace"*)                                        echo time ;;
    *"ACTIVE — an untracked file here was written within"*)                          echo time ;;
    *"LIVE at act time"*)                                                             echo terminal ;;
    *"unavailable"*|*"unresolvable"*|*"unreadable"*|*"unprovable"*)                   echo retry ;;
    *"refused"*|*"REFUSED"*|*"failed"*|*"CHANGED after classification"*)              echo retry ;;
    *)                                                                                echo terminal ;;
  esac
}

# decision_of <line> → sets D_KIND D_PATH D_REASON for one janitor stdout line; rc 1 if not one.
decision_of() {
  local l="$1" rest
  D_KIND=""; D_PATH=""; D_REASON=""
  case "$l" in
    "KEEP "*)           D_KIND=keep;          rest="${l#KEEP }" ;;
    "would park "*)     D_KIND=would_park;    rest="${l#would park }" ;;
    "park "*)           D_KIND=parked;        rest="${l#park }" ;;
    "would detach "*|"would archive "*) D_KIND=would_detach; rest="${l#would * }" ;;
    "detach "*|"archive "*)             D_KIND=detached;     rest="${l#* }" ;;
    "would remove "*|"would dispose "*) D_KIND=would_remove; rest="${l#would * }" ;;
    "remove "*|"dispose "*)             D_KIND=removed;      rest="${l#* }" ;;
    "worktree-gc: --path "*" — not a worktree"*)
      D_KIND=dropped; rest="${l#worktree-gc: --path }"; D_PATH="${rest%% — not a worktree*}"
      D_REASON="worktree-gc: not a worktree of any repository, and not parked"; return 0 ;;
    *) return 1 ;;
  esac
  while :; do case "$rest" in " "*) rest="${rest# }" ;; *) break ;; esac; done
  D_PATH="${rest%% \[*}"
  case "$rest" in *" — "*) D_REASON="${rest#* — }" ;; *) D_REASON="" ;; esac
  return 0
}

# ── One janitor run per repo, serially (each takes worktree-gc's own mutex in act mode).
REPOS="$(printf '%s' "$WK_ROWS" | cut -f1 | sed '/^$/d' | sort -u)"
ERRF="$STATE/.worktree-gc-wake.err.$$"
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  scope=""; trunk=""; args=(--park-first)
  while IFS="$TAB" read -r r s t p c ev sid; do
    [ "$r" = "$repo" ] || continue
    scope="$s"; trunk="$t"; args+=(--path "$p"); N_EVAL=$((N_EVAL + 1))
  done <<EOF
$WK_ROWS
EOF
  rmode=observe
  if [ "$scope" = act ]; then rmode=act; else args+=(--dry-run); fi
  out="$(CC_WTGC_REPO="$repo" CC_WTGC_TRUNK="$trunk" \
         CC_WTGC_EXCLUDE="$HOME_REPO:$HOME/.claude/autonomy/postland" \
         bash "$GC_SH" "${args[@]}" 2>"$ERRF" </dev/null)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    log "mode=$rmode repo=${repo##*/} verdict=gc-error rc=$rc stderr=$(head -1 "$ERRF" 2>/dev/null)"
  fi
  rm -f "$ERRF" 2>/dev/null

  # Match each queued path to its decision line: by the janitor's path, canonicalized, or — for a
  # parked tree, whose KEEP line names the parked dir — by the "PARKED from <path>" in its reason.
  while IFS="$TAB" read -r r s t p c ev sid; do
    [ "$r" = "$repo" ] || continue
    kind=""; why=""
    while IFS= read -r line; do
      decision_of "$line" || continue
      lp="$D_PATH"; hit=0
      if [ "$lp" = "$p" ] || [ "$lp" = "$c" ]; then hit=1
      else
        case "$D_REASON" in
          "PARKED from $p "*|"PARKED from $p;"*|"PARKED from $p"|"PARKED from $c "*|"PARKED from $c;"*|"PARKED from $c") hit=1 ;;
        esac
        [ "$hit" = 1 ] || { [ -n "$lp" ] && [ "$(wk_canon "$lp")" = "$c" ] && hit=1; }
      fi
      [ "$hit" = 1 ] || continue
      kind="$D_KIND"; why="$D_REASON"; break
    done <<EOF
$out
EOF
    case "$kind" in
      "")
        row "$rmode" "$repo" none "$p" "no decision line from worktree-gc (rc=$rc); retry in ${RETRY_S}s"
        requeue "$p" $((NOW + RETRY_S)) "$ev" "$sid" ;;
      keep)
        d=kept; [ "$rmode" = observe ] && d=would_keep
        cls="$(keep_class "$why")"
        row "$rmode" "$repo" "$d" "$p" "$why (keep=$cls)"
        if [ "$cls" = terminal ]; then N_DEQ=$((N_DEQ + 1)); else requeue "$p" $((NOW + GRACE)) "$ev" "$sid"; fi ;;
      *)
        # PARK, DETACH, ARCHIVE, a removal or a janitor-side drop: terminal. In observe mode the
        # would_* verdicts are dequeued too, so an observe soak does not re-evaluate every tick.
        row "$rmode" "$repo" "$kind" "$p" "$why"; N_DEQ=$((N_DEQ + 1)) ;;
    esac
  done <<EOF
$WK_ROWS
EOF
done <<EOF
$REPOS
EOF

# ── Rewrite the queue: rows that were not due, plus the requeued, plus anything a producer appended
#    after ingest (that stays in the events file past the cursor, so nothing is lost here).
printf '%s%s' "$KEEPQ" "$REQ" | sed '/^$/d' > "$QUEUE.tmp.$$" && mv -f "$QUEUE.tmp.$$" "$QUEUE"
rm -f "$QUEUE.tmp.$$" 2>/dev/null

log "verdict=ok due=$N_DUE evaluated=$N_EVAL dequeued=$N_DEQ requeued=$N_REQ mode=$MODE"
exit 0
