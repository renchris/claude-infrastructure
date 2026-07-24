#!/bin/bash
# team-orphan-reaper.sh — Archive dead teams + auto-deny stale permission
# requests. Invoked by launchd every 10 minutes.
#
# A team is ARCHIVED only on POSITIVE evidence of death:
#   - ~/.claude/teams/<name>/config.json exists with a leadSessionId, AND
#   - that lead has an EXISTING watchdog pid file whose pid fails `kill -0` (dead), AND
#   - no live session (cc-sessions registry) occupies a member worktree or matches a member/lead name.
# A MISSING or empty watchdog pid file is UNKNOWN, not dead — the watchdog may not have written it yet,
# or an in-place /handoff of a named team left a stale leadSessionId whose pid file is gone while a
# SUCCESSOR actively drives the team. Such teams are SURFACED (logged + best-effort operator page),
# never archived: archiving a LIVE team erases cc-classify's owned-wait / coordination-hold signals and
# cascades toward the pane reaper. Absence of a pid file is not evidence of death.
#
# Also: for LIVE teams, scan inboxes for permission_request envelopes older
# than PERM_TIMEOUT_MIN (default 5); append a permission_response deny envelope
# so the teammate unblocks.
#
# Kill switch: export TEAM_ORPHAN_REAPER_DISABLED=1 (or launchctl unload)

set -uo pipefail

if [[ "${TEAM_ORPHAN_REAPER_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

readonly TEAMS_DIR="${TEAM_REAPER_TEAMS_DIR:-$HOME/.claude/teams}"
readonly WATCHDOG_DIR="${TEAM_REAPER_WATCHDOG_DIR:-$HOME/.claude/watchdog}"
readonly ARCHIVE_DIR="$TEAMS_DIR/_archive"
readonly LOG_FILE="${TEAM_REAPER_LOG_FILE:-$HOME/.claude/logs/team-reaper.log}"
readonly PERM_TIMEOUT_MIN="${TEAM_REAPER_PERM_TIMEOUT_MIN:-5}"

# Helper CLIs for the archive-safety gate: cc-sessions (live-session registry cross-check) and
# cc-notify (operator page for an UNKNOWN-liveness team). Resolve PATH-first so a test PATH-shim wins,
# then fall back to the standard install path; empty ⇒ unavailable, and the caller degrades gracefully
# (a missing registry only forfeits its extra KEEP evidence — it never fails the sweep).
_reaper_bin() { command -v "$1" 2>/dev/null || { [ -x "$HOME/.claude/bin/$1" ] && printf '%s\n' "$HOME/.claude/bin/$1"; }; }
readonly CC_SESSIONS_BIN="${CC_SESSIONS_BIN:-$(_reaper_bin cc-sessions)}"
readonly CC_NOTIFY_BIN="${CC_NOTIFY_BIN:-$(_reaper_bin cc-notify)}"

mkdir -p "$ARCHIVE_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# Three-state liveness of the recorded lead:
#   0 = ALIVE   (pid file present, pid answers kill -0 — keep existing semantics: ANY live pid ⇒ alive,
#                including a recycled non-claude pid; we do NOT add pid-identity checking here)
#   1 = DEAD    (pid file present, pid fails kill -0 — POSITIVE evidence of death; may proceed to archive)
#   2 = UNKNOWN (no pid file, or an empty one — absence of evidence, NOT evidence of death; surface it)
lead_liveness() {
  local sid="$1"
  local pid_file="$WATCHDOG_DIR/$sid.pid"
  [[ -f "$pid_file" ]] || return 2          # no watchdog record — UNKNOWN (was wrongly "assume dead")
  local pid
  pid=$(cat "$pid_file" 2>/dev/null || echo "")
  [[ -z "$pid" ]] && return 2               # empty pid file — no pid to test ⇒ UNKNOWN, not dead
  kill -0 "$pid" 2>/dev/null && return 0     # a live pid ⇒ alive (existing semantics preserved)
  return 1                                   # pid file present + pid dead ⇒ DEAD (positive evidence)
}

# Best-effort operator page (never fails the sweep). Addresses the operator ROLE so a recycled desk is
# followed automatically; a missing role / unavailable cc-notify is a silent no-op.
cc_notify_page() { # $1=message
  [[ -n "$CC_NOTIFY_BIN" ]] || return 0
  "$CC_NOTIFY_BIN" --role operator "$1" >/dev/null 2>&1 || true
}

# Registry cross-check before archiving a DEAD-lead team: a dead lead pid is not a dead TEAM. An
# in-place /handoff or a crash-respawn mints a successor session that drives the team from a member
# worktree (its cwd sits inside one) or under a member/lead name. Return 0 (KEEP) iff cc-sessions
# reports a live session matching either signal; 1 otherwise. cc-sessions unavailable / unreadable ⇒ 1
# (no extra KEEP evidence — the sweep falls back to the pid-death verdict it already has).
team_has_live_session() { # $1=team_dir
  local cfg="$1/config.json" rows
  [[ -f "$cfg" ]] || return 1
  [[ -n "$CC_SESSIONS_BIN" ]] || { log "registry cross-check skipped ($1): cc-sessions unavailable"; return 1; }
  rows="$("$CC_SESSIONS_BIN" --json 2>/dev/null)" || return 1
  case "$rows" in '['*) ;; *) return 1 ;; esac          # not a JSON array ⇒ ignore, no false KEEP
  # One jq pass: a live session KEEPs the team if its .name is a member/lead name OR its .cwd is inside
  # a member worktree (.worktree or .cwd). --slurpfile tolerates a malformed config (parse error ⇒ empty
  # stream ⇒ jq -e exits non-zero ⇒ no false KEEP). Member names include "team-lead", so the lead is covered.
  printf '%s' "$rows" | jq -e --slurpfile cfg "$cfg" '
    ($cfg[0] // {}) as $c
    | ([ ($c.members // [])[]? | (.worktree, .cwd) | select(type == "string" and . != "") ]) as $wts
    | ([ ($c.members // [])[]? | .name              | select(type == "string" and . != "") ]) as $names
    | any(.[]?;
        ((.name // "") as $n | $n != "" and ($names | index($n) != null))
        or
        ((.cwd  // "") as $d | $d != "" and (any($wts[]; . as $w | $d == $w or ($d | startswith($w + "/")))))
      )
  ' >/dev/null 2>&1
}

archive_team() {
  local team_dir="$1"
  local team_name
  team_name=$(basename "$team_dir")
  local ts
  ts=$(date +%s)
  local dest="$ARCHIVE_DIR/${team_name}-${ts}"

  if mv "$team_dir" "$dest" 2>/dev/null; then
    log "archived orphan team: $team_name → $dest"

    # Clean up associated watchdog files
    local lead_sid
    lead_sid=$(jq -r '.leadSessionId // empty' "$dest/config.json" 2>/dev/null)
    if [[ -n "$lead_sid" ]]; then
      rm -f "$WATCHDOG_DIR/$lead_sid.pid" "$WATCHDOG_DIR/$lead_sid.id" "$WATCHDOG_DIR/cp-$lead_sid.count"
    fi
  else
    log "FAIL: could not archive $team_dir"
  fi
}

scan_stale_permissions() {
  local team_dir="$1"
  local team_name
  team_name=$(basename "$team_dir")
  local cutoff_epoch
  cutoff_epoch=$(( $(date +%s) - PERM_TIMEOUT_MIN * 60 ))

  for inbox in "$team_dir/inboxes"/*.json; do
    [[ -f "$inbox" ]] || continue
    local member
    member=$(basename "$inbox" .json)
    [[ "$member" == "team-lead" ]] && continue

    # Find unread permission_requests older than cutoff
    local stale
    stale=$(jq -c --arg cutoff "$cutoff_epoch" '
      [.[] | select(.read == false)
           | select((.text | fromjson?).type == "permission_request")
           | select((.timestamp | sub("\\.[0-9]+Z"; "Z") | fromdateiso8601) < ($cutoff | tonumber))]
    ' "$inbox" 2>/dev/null || echo '[]')

    local count
    count=$(echo "$stale" | jq 'length' 2>/dev/null || echo 0)
    [[ "$count" == "0" ]] && continue

    log "auto-deny $count stale permission_request(s) for $team_name/$member"

    # Append one deny envelope per stale request — UNDER A MUTEX. The crash-watchdog
    # (lead-crash-watchdog.sh) appends shutdown/deny envelopes to this SAME inbox; two read-modify-write
    # cycles with last-mv-wins would silently drop one side's envelope. An inline mkdir lock (portable —
    # macOS has no flock) whose dir name is SHARED VERBATIM with the watchdog ("$inbox.lock.d") makes the
    # two exclude each other. Acquire ≤2s (0.1s steps), self-break a stale lock (holder died) >10s old,
    # and on give-up proceed lock-free — dup-biased: a duplicate deny is harmless, a hung reaper is not.
    local lockd="$inbox.lock.d" waited=0 lmt lnow lage
    while ! mkdir "$lockd" 2>/dev/null; do
      lmt=$(stat -f %m "$lockd" 2>/dev/null || stat -c %Y "$lockd" 2>/dev/null || echo 0)
      lnow=$(date +%s 2>/dev/null || echo 0)
      lage=$(( lnow - lmt ))
      if [[ "$lage" -ge 10 ]]; then rm -rf "$lockd" 2>/dev/null; continue; fi   # stale → holder died, break it
      [[ "$waited" -ge 2000 ]] && break                                          # gave up → proceed lock-free
      sleep 0.1 2>/dev/null || sleep 1; waited=$(( waited + 100 ))
    done
    local tmp
    tmp=$(mktemp)
    # shellcheck disable=SC2015  # deliberate A&&B||C: tmp is rm'd on either jq-or-mv failure; a successful mv cannot reach the rm
    jq --argjson stale "$stale" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" '
      . + ($stale | map({
        from: "reaper",
        text: ("{\"type\":\"permission_response\",\"request_id\":\"" + ((.text | fromjson).request_id // "unknown") + "\",\"decision\":\"deny\",\"reason\":\"lead unresponsive >5min — try alternative or report blocker\"}"),
        summary: "stale permission request auto-denied",
        timestamp: $ts,
        read: false
      }))
    ' "$inbox" > "$tmp" && mv "$tmp" "$inbox" || rm -f "$tmp"
    rmdir "$lockd" 2>/dev/null || true
  done
}

main() {
  log "reaper sweep — start"

  local live_count=0
  local archived_count=0
  local unknown_count=0

  for team_dir in "$TEAMS_DIR"/*/; do
    team_dir=${team_dir%/}
    [[ -d "$team_dir" ]] || continue
    local team_name
    team_name=$(basename "$team_dir")
    [[ "$team_name" == "_archive" ]] && continue
    [[ -f "$team_dir/config.json" ]] || continue

    local lead_sid
    lead_sid=$(jq -r '.leadSessionId // empty' "$team_dir/config.json" 2>/dev/null)
    if [[ -z "$lead_sid" ]]; then
      log "skip $team_name: no leadSessionId"
      continue
    fi

    local liveness
    lead_liveness "$lead_sid"; liveness=$?
    if [[ "$liveness" -eq 0 ]]; then
      scan_stale_permissions "$team_dir"
      live_count=$((live_count + 1))
    elif [[ "$liveness" -eq 2 ]]; then
      # UNKNOWN — no/empty watchdog pid file. NOT death (watchdog not yet written, or an in-place
      # /handoff left a stale leadSessionId whose pid file is gone while a successor drives the team).
      # Surface it and move on — archiving a live team erases cc-classify's hold signals.
      log "unknown-liveness $team_name (no watchdog pid file) — surfacing"
      cc_notify_page "team-orphan-reaper: unknown-liveness for '$team_name' (lead $lead_sid has no live watchdog pid file) — NOT archiving; if the team is truly dead, clean up $TEAMS_DIR/$team_name"
      unknown_count=$((unknown_count + 1))
    else
      # DEAD by positive evidence (pid file present, pid fails kill -0). Cross-check the live-session
      # registry first: a successor may drive the team from a member worktree/name (KEEP), else archive.
      if team_has_live_session "$team_dir"; then
        log "keep $team_name: lead pid dead but a live session matches a member worktree/name (successor-driven)"
        live_count=$((live_count + 1))
      else
        archive_team "$team_dir"
        archived_count=$((archived_count + 1))
      fi
    fi
  done

  log "reaper sweep — done: $live_count live, $archived_count archived, $unknown_count unknown"
}

main "$@"
