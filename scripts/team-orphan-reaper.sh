#!/bin/bash
# team-orphan-reaper.sh — Archive dead teams + auto-deny stale permission
# requests. Invoked by launchd every 10 minutes.
#
# A team is orphaned when:
#   - ~/.claude/teams/<name>/config.json exists
#   - leadSessionId has no live pid file in ~/.claude/watchdog/
#   - OR the recorded pid is dead
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

readonly TEAMS_DIR="$HOME/.claude/teams"
readonly WATCHDOG_DIR="$HOME/.claude/watchdog"
readonly ARCHIVE_DIR="$TEAMS_DIR/_archive"
readonly LOG_FILE="$HOME/.claude/logs/team-reaper.log"
readonly PERM_TIMEOUT_MIN="${TEAM_REAPER_PERM_TIMEOUT_MIN:-5}"

mkdir -p "$ARCHIVE_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

is_lead_alive() {
  local sid="$1"
  local pid_file="$WATCHDOG_DIR/$sid.pid"
  if [[ ! -f "$pid_file" ]]; then
    return 1  # no record — assume dead
  fi
  local pid
  pid=$(cat "$pid_file" 2>/dev/null || echo "")
  [[ -z "$pid" ]] && return 1
  kill -0 "$pid" 2>/dev/null
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

    if is_lead_alive "$lead_sid"; then
      scan_stale_permissions "$team_dir"
      live_count=$((live_count + 1))
    else
      # Optionally: verify no iTerm panes alive (osascript) — skip for v1, archive is idempotent
      archive_team "$team_dir"
      archived_count=$((archived_count + 1))
    fi
  done

  log "reaper sweep — done: $live_count live, $archived_count archived"
}

main "$@"
