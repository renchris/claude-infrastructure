#!/bin/bash
# lead-crash-watchdog.sh — SessionStart hook that spawns a detached watchdog
# daemon per claude session. If the lead process dies while it has an active
# team, the watchdog:
#   1. Appends a shutdown_request envelope to each teammate inbox
#   2. Writes a CRASH_REPORT.md in the team dir
#   3. Fires a macOS notification + terminal bell
#
# This prevents the routines-v1 scenario from repeating: lead died mid-session,
# 3 teammates blocked on permission prompts, no recovery signal.
#
# Kill switch: export LEAD_CRASH_WATCHDOG_DISABLED=1
#
# Exit: always 0 (hook must never block session startup).

set -euo pipefail

if [[ "${LEAD_CRASH_WATCHDOG_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

readonly WATCHDOG_DIR="$HOME/.claude/watchdog"
readonly LOG_FILE="$HOME/.claude/logs/lead-crash-watchdog.log"

mkdir -p "$WATCHDOG_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# Parse hook JSON stdin
INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo '')
LEAD_PID="${PPID:-$$}"

if [[ -z "$SESSION_ID" ]]; then
  log "no session_id from hook input — using PID $LEAD_PID as key"
  SESSION_ID="pid-$LEAD_PID"
fi

# Record session→PID mapping for orphan-reaper to consult
echo "$LEAD_PID" > "$WATCHDOG_DIR/$SESSION_ID.pid"
echo "$SESSION_ID" > "$WATCHDOG_DIR/$SESSION_ID.id"
log "registered session=$SESSION_ID pid=$LEAD_PID"

# Spawn detached watchdog daemon. Uses setsid + nohup + disown to survive
# the hook process exit; daemon itself polls via kill -0 every 30s.
(
  # Self-contained daemon. Exits cleanly when:
  #   (a) lead PID gone AND any owned team handled, or
  #   (b) the pid file is removed (session ended cleanly)

  exec </dev/null >>"$LOG_FILE" 2>&1
  trap '' HUP

  local_watchdog() {
    local pid="$1" sid="$2"
    local pid_file="$WATCHDOG_DIR/$sid.pid"

    while :; do
      # pid file gone = clean shutdown elsewhere
      [[ -f "$pid_file" ]] || { echo "[watchdog $sid] pid file gone — exit"; return 0; }
      # lead process gone = crash detected
      if ! kill -0 "$pid" 2>/dev/null; then
        echo "[watchdog $sid] LEAD CRASH detected pid=$pid"
        handle_crash "$pid" "$sid"
        return 0
      fi
      sleep 30
    done
  }

  handle_crash() {
    local pid="$1" sid="$2"
    local affected_team_dirs=()

    # Which teams had this session as lead? Scan BOTH team roots — CC writes
    # $CLAUDE_CONFIG_DIR/teams/<team>/, so *2-launcher leads (claude-next2 /
    # claude-fable2) keep their team state only under ~/.claude-secondary/teams
    # (memory: teammate-shutdown-secondary-config-dir-2026-06-09). The dir each
    # config was FOUND in is carried through — never re-derived from a root.
    for team_config in "$HOME/.claude/teams"/*/config.json "$HOME/.claude-secondary/teams"/*/config.json; do
      [[ -f "$team_config" ]] || continue
      local team_dir
      team_dir=$(dirname "$team_config")
      local team_name
      team_name=$(basename "$team_dir")
      [[ "$team_name" == "_archive" ]] && continue
      local lead_sid
      lead_sid=$(jq -r '.leadSessionId // empty' "$team_config" 2>/dev/null)
      if [[ "$lead_sid" == "$sid" ]]; then
        affected_team_dirs+=("$team_dir")
      fi
    done

    if [[ ${#affected_team_dirs[@]} -eq 0 ]]; then
      echo "[watchdog $sid] crash — no teams affected (lead had no active team)"
      rm -f "$WATCHDOG_DIR/$sid.pid" "$WATCHDOG_DIR/$sid.id"
      return 0
    fi

    echo "[watchdog $sid] crash affects ${#affected_team_dirs[@]} team(s): ${affected_team_dirs[*]}"

    for team_dir in "${affected_team_dirs[@]}"; do
      write_crash_report "$team_dir" "$pid" "$sid"
      send_shutdown_requests "$team_dir" "$sid"
    done

    osascript -e "display notification \"Lead crashed. ${#affected_team_dirs[@]} team(s) affected. See CRASH_REPORT.md\" with title \"Claude Code Watchdog\" sound name \"Basso\"" 2>/dev/null || true
    printf '\a' >/dev/tty 2>/dev/null || true

    rm -f "$WATCHDOG_DIR/$sid.pid" "$WATCHDOG_DIR/$sid.id"
  }

  write_crash_report() {
    local team_dir="$1" pid="$2" sid="$3"
    local team_name
    team_name=$(basename "$team_dir")
    local team_root
    team_root=$(dirname "$team_dir")
    local report="$team_dir/CRASH_REPORT.md"

    {
      echo "# Lead Crash Report"
      echo ""
      echo "- **Team**: $team_name"
      echo "- **Lead PID**: $pid (dead at $(date '+%Y-%m-%d %H:%M:%S'))"
      echo "- **Lead session**: $sid"
      echo ""
      echo "## Members"
      jq -r '.members[] | "- \(.name) (agentId=\(.agentId), cwd=\(.cwd // "?"))"' \
        "$team_dir/config.json" 2>/dev/null || echo "- (unable to parse config.json)"
      echo ""
      echo "## Last 5 inbox messages per member"
      for inbox in "$team_dir/inboxes"/*.json; do
        [[ -f "$inbox" ]] || continue
        local member
        member=$(basename "$inbox" .json)
        [[ "$member" == "team-lead" ]] && continue
        echo ""
        echo "### $member"
        jq -r '.[-5:] | .[] | "- [\(.timestamp // "?")] from=\(.from // "?"): \(.summary // (.text | tostring | .[0:200]))"' \
          "$inbox" 2>/dev/null || echo "(unable to parse)"
      done
      echo ""
      echo "## Recovery"
      echo ""
      echo "1. Start a new claude session. Do NOT \`claude --resume\`."
      echo "2. Archive this team dir: \`mv $team_dir $team_root/_archive/$team_name-\$(date +%s)\`"
      echo "3. Run \`scripts/team/respawn-team.sh $team_name\` (if team-briefs/$team_name/ exists) to get the paste block."
      echo "4. Check teammate worktrees for uncommitted work: \`git reflog refs/checkpoints/<member>/\` (if teammate-checkpoint.sh was active)."
      echo ""
    } > "$report"

    echo "[watchdog] wrote $report"
  }

  send_shutdown_requests() {
    local team_dir="$1" sid="$2"

    for inbox in "$team_dir/inboxes"/*.json; do
      [[ -f "$inbox" ]] || continue
      local member
      member=$(basename "$inbox" .json)
      [[ "$member" == "team-lead" ]] && continue

      local envelope
      envelope=$(jq -n \
        --arg from "watchdog" \
        --arg text "{\"type\":\"shutdown_request\",\"reason\":\"lead crashed — see CRASH_REPORT.md\"}" \
        --arg summary "LEAD CRASH — shutting down" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
        '{from:$from, text:$text, summary:$summary, timestamp:$ts, read:false}')

      # Append to inbox array — use jq to avoid races
      local tmp
      tmp=$(mktemp)
      if jq --argjson env "$envelope" '. += [$env]' "$inbox" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$inbox"
        echo "[watchdog] shutdown_request → $member"
      else
        rm -f "$tmp"
        echo "[watchdog] WARN: failed to inject shutdown_request for $member"
      fi
    done
  }

  local_watchdog "$LEAD_PID" "$SESSION_ID"
) </dev/null >/dev/null 2>&1 &
disown

log "spawned watchdog daemon for session=$SESSION_ID pid=$LEAD_PID"
exit 0
