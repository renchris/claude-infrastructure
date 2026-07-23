#!/bin/bash
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Session ended" >> ~/.claude/logs/sessions.log

# ── clean-exit watchdog + checkpoint cleanup ───────────────────────────────────
# Remove THIS session's watchdog pid/id + teammate-checkpoint counter on a clean
# SessionEnd so that:
#   1. the lead-crash-watchdog daemon takes its "pid file gone => clean shutdown"
#      branch instead of logging a FALSE "LEAD CRASH" — every clean /exit, ⌘W,
#      handoff and recycle previously left the pid file in place, so the daemon's
#      "lead pid dead + pid file present => crash" branch fired on 93% of all
#      session ends (3011/3244). The signal is only meaningful once clean exits
#      stop tripping it.
#   2. the per-session files under ~/.claude/watchdog/ (<sid>.pid, <sid>.id, and
#      cp-<sid>.count written by teammate-checkpoint.sh) do not accumulate
#      unbounded — no reaper GCs that directory (cc-reaper does not touch it).
# A genuine crash / OOM / SIGKILL does NOT run SessionEnd, so its pid file
# persists and the daemon still correctly detects and classifies the crash.
# stdin is the SessionEnd hook JSON (same `cat` pattern as lead-crash-watchdog.sh);
# sid is validated to a safe charset before any rm (defense-in-depth).
_se_input=$(cat 2>/dev/null || echo '{}')
_se_sid=$(printf '%s' "$_se_input" | jq -r '.session_id // empty' 2>/dev/null || echo "")
_se_reason=$(printf '%s' "$_se_input" | jq -r '.reason // empty' 2>/dev/null || echo "")
# Skip the per-sid pidfile removal on reason=clear: /clear ends the sid but the PROCESS and pane
# SURVIVE, and team-orphan-reaper reads a missing pidfile as lead-death — removing it mid-team-wave
# would archive a LIVE team and shutdown-deny its teammates. Real exits (logout / prompt_input_exit
# / other) proceed normally. The cp-count is still safe to drop on clear (it just re-creates).
if [[ -n "$_se_sid" && "$_se_sid" =~ ^[A-Za-z0-9._-]+$ && "$_se_reason" != "clear" ]]; then
  rm -f "$HOME/.claude/watchdog/$_se_sid.pid" \
        "$HOME/.claude/watchdog/$_se_sid.id" \
        "$HOME/.claude/watchdog/cp-$_se_sid.count" 2>/dev/null || true
fi

# Opportunistic straggler GC (backgrounded, non-blocking). The per-session rm above only reaps
# THIS clean exit; it cannot reach files orphaned by a crash/OOM/reboot (no SessionEnd ran) or the
# historical backlog (1900+ cp-*.count + stale pids, back to Apr — no reaper covers this dir, nor
# the per-fire /tmp handoff watcher logs). Reap them here, liveness- and age-gated so a long-lived
# session's OWN live files are never touched:
#   • <sid>.pid/.id  — removed only when the recorded pid is dead (a live session keeps its pair).
#   • cp-<sid>.count — a live session bumps its mtime every tool use, so +2d ⇒ a dead session.
#   • /tmp handoff-*  — a live fire's watcher log is seconds old; +2d ⇒ long finished.
(
  _wd="$HOME/.claude/watchdog"
  for _pf in "$_wd"/*.pid; do
    [[ -f "$_pf" ]] || continue
    _p=$(cat "$_pf" 2>/dev/null)
    if [[ "$_p" =~ ^[0-9]+$ ]] && kill -0 "$_p" 2>/dev/null; then continue; fi
    _sid=$(basename "$_pf" .pid)
    rm -f "$_wd/$_sid.pid" "$_wd/$_sid.id" "$_wd/cp-$_sid.count" 2>/dev/null || true
  done
  find "$_wd" -name 'cp-*.count' -mtime +2 -delete 2>/dev/null || true
  # tmp sweep dirs are env-overridable so tests stay hermetic (never touch the real /tmp).
  # shellcheck disable=SC2086  # intentional word-split over space-separated dirs
  for _td in ${CC_TMP_SWEEP_DIRS:-${TMPDIR:-/tmp} /private/tmp}; do
    [[ -d "$_td" ]] || continue
    find "$_td" -maxdepth 1 \( -name 'handoff-selfclose-*.log' -o -name 'handoff-recycle-*' \
         -o -name 'handoff-prompt-nb-*' \) -mtime +2 -delete 2>/dev/null || true
  done
) &
disown 2>/dev/null || true

# Secondary GC trigger: clean stale Claude versions on session end (background, non-blocking)
# Primary trigger is in claude-latest (threshold-based). This catches any accumulation
# that slipped below threshold or when updates happened outside claude-latest.
(
  VERSIONS_DIR="$HOME/.claude-versions"
  CURRENT_LINK="$VERSIONS_DIR/current"
  KEEP_COUNT="${CLAUDE_VERSIONS_KEEP:-2}"
  GC_THRESHOLD=$(( KEEP_COUNT + 2 ))

  # Count versions (fast — single ls + wc)
  version_count=$(find "$VERSIONS_DIR" -maxdepth 1 -mindepth 1 -type d ! -name current ! -name '.*' 2>/dev/null | wc -l)
  [[ "$version_count" -le "$GC_THRESHOLD" ]] && exit 0

  # Acquire lock (skip if another cleanup is running)
  lock_dir="$VERSIONS_DIR/.cleanup_lock"
  mkdir "$lock_dir" 2>/dev/null || exit 0
  echo $$ > "$lock_dir/pid"

  current_target=$(readlink "$CURRENT_LINK" 2>/dev/null | xargs basename 2>/dev/null || echo "")

  # Sort versions, build keep set
  versions=()
  for dir in "$VERSIONS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    v=$(basename "$dir")
    [[ "$v" == "current" || "$v" == .* ]] && continue
    versions+=("$v")
  done
  IFS=$'\n' sorted=($(printf '%s\n' "${versions[@]}" | sort -t. -k1,1rn -k2,2rn -k3,3rn))
  unset IFS

  declare -A keep_set
  keep_set["$current_target"]=1
  kept=0
  for v in "${sorted[@]}"; do
    [[ "$v" == "$current_target" ]] && continue
    if [[ $kept -lt $KEEP_COUNT ]]; then
      keep_set["$v"]=1
      kept=$((kept + 1))
    fi
  done

  for v in "${sorted[@]}"; do
    [[ -n "${keep_set[$v]:-}" ]] && continue
    pgrep -f "claude-versions/$v" >/dev/null 2>&1 && continue
    rm -rf "$VERSIONS_DIR/$v" 2>/dev/null && \
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] SessionEnd GC: removed $v" >> "$HOME/.claude/.update-versions.log"
  done

  rm -rf "$lock_dir"
) &
disown 2>/dev/null || true

exit 0
