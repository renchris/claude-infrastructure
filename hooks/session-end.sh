#!/bin/bash
# ── stdin is read FIRST so the sessions.log line can carry ATTRIBUTION ─────────
# This read used to sit at line 20, below a bare `echo "... Session ended"`. That
# ordering made the fleet's only session-end record UNATTRIBUTABLE: no sid, no
# reason, on a log where the MAJORITY of such lines are not real session ends at
# all. `hooks/session-start.sh` runs `claude mcp list` on EVERY SessionStart and
# that subprocess emits a SessionEnd of its own — reason "other", a fresh random
# session_id, no matching SessionStart — so 5360 of 6208 `MCP Status` lines are
# immediately preceded by a PHANTOM "Session ended" (measured 2026-08-05; see
# hooks/session-deregister.sh and docs/research/registry-row-removal-2026-08-05.md).
# A reader could therefore neither tell WHICH session ended nor whether the line
# was a real end or the phantom, and the two are only ~14% / ~86% of the file.
#
# The cost of that was paid in full: backlog row b521cb445465 spent 20 days as an
# "UNEXPLAINED ABRUPT SESSION DEATH" because the one line written at the death
# second could not be tied to the session that died. Both fields were already in
# this hook's own stdin and already parsed four lines down — they were simply
# thrown away before being written. Emitting them makes the phantom mechanically
# separable (reason=other + a sid with no matching SessionStart) and turns that
# investigation into a grep.
#
# The literal phrase "Session ended" is PRESERVED verbatim and the fields are
# APPENDED, so every existing consumer that greps it keeps matching unchanged
# (tests/session-end.bats, plus the forensics docs that count these lines).
_se_input=$(cat 2>/dev/null || echo '{}')
_se_sid=$(printf '%s' "$_se_input" | jq -r '.session_id // empty' 2>/dev/null || echo "")
_se_reason=$(printf '%s' "$_se_input" | jq -r '.reason // empty' 2>/dev/null || echo "")
# Log-field sanitation is independent of the charset GUARD below: that guard gates
# `rm`, this one gates what reaches a shared append-only log. A sid/reason is
# attacker-adjacent free text, so strip to a safe charset and bound the length —
# an embedded newline would otherwise forge an entire extra log record.
_se_sid_log=$(printf '%s' "${_se_sid:--}" | tr -cd 'A-Za-z0-9._-' | cut -c1-64)
_se_reason_log=$(printf '%s' "${_se_reason:--}" | tr -cd 'A-Za-z0-9._-' | cut -c1-32)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Session ended sid=${_se_sid_log:--} reason=${_se_reason_log:--}" \
  >> ~/.claude/logs/sessions.log

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
# sid is validated to a safe charset before any rm (defense-in-depth). It is read
# ONCE, at the top of this file, for the attributed log line — a second `cat` here
# would read an already-consumed stdin, come back EMPTY, and (because an empty read
# still EXITS 0, so the `|| echo '{}'` fallback never fires) silently blank the sid
# and disable every removal below.
# Skip the per-sid pidfile removal on reason=clear: /clear ends the sid but the PROCESS and pane
# SURVIVE, and team-orphan-reaper reads a missing pidfile as lead-death — removing it mid-team-wave
# would archive a LIVE team and shutdown-deny its teammates. Real exits (logout / prompt_input_exit
# / other) proceed normally. The cp-count is still safe to drop on clear (it just re-creates).
if [[ -n "$_se_sid" && "$_se_sid" =~ ^[A-Za-z0-9._-]+$ && "$_se_reason" != "clear" ]]; then
  # `.daemon` holds the watchdog daemon's {pid,start-time} for the single-instance guard. It is dropped
  # with the pair it describes: leaving it behind would let a LATER session reusing this sid consult a
  # record of a daemon that has exited — and a pid-recycle match there would skip the spawn and leave
  # that session with no watcher at all.
  rm -f "$HOME/.claude/watchdog/$_se_sid.pid" \
        "$HOME/.claude/watchdog/$_se_sid.id" \
        "$HOME/.claude/watchdog/$_se_sid.daemon" \
        "$HOME/.claude/watchdog/cp-$_se_sid.count" 2>/dev/null || true
fi

# Opportunistic straggler GC (backgrounded, non-blocking). The per-session rm above only reaps
# THIS clean exit; it cannot reach files orphaned by a crash/OOM/reboot (no SessionEnd ran) or the
# historical backlog (1900+ cp-*.count + stale pids, back to Apr — no reaper covers this dir, nor
# the per-fire /tmp handoff watcher logs). Reap them here, liveness- and age-gated so a long-lived
# session's OWN live files are never touched:
#   • <sid>.pid/.id/.daemon — removed only when the recorded LEAD pid is dead (a live session keeps
#     its set). `.daemon` rides with them for the pid-recycle reason above.
#   • cp-<sid>.count — a live session bumps its mtime every tool use, so +2d ⇒ a dead session.
#   • <sid>.death-<pid>.d — the watchdog's per-death claim dir. handle_crash rmdir's its own on both
#     exits, so one surviving +2d means the handler itself died mid-crash; reaping it lets a future
#     death for that sid be claimed again instead of being refused by a dead holder forever.
#   • /tmp handoff-*  — a live fire's watcher log is seconds old; +2d ⇒ long finished.
(
  _wd="$HOME/.claude/watchdog"
  for _pf in "$_wd"/*.pid; do
    [[ -f "$_pf" ]] || continue
    _p=$(cat "$_pf" 2>/dev/null)
    if [[ "$_p" =~ ^[0-9]+$ ]] && kill -0 "$_p" 2>/dev/null; then continue; fi
    _sid=$(basename "$_pf" .pid)
    rm -f "$_wd/$_sid.pid" "$_wd/$_sid.id" "$_wd/$_sid.daemon" "$_wd/cp-$_sid.count" 2>/dev/null || true
  done
  find "$_wd" -name 'cp-*.count' -mtime +2 -delete 2>/dev/null || true
  find "$_wd" -maxdepth 1 -type d -name '*.death-*.d' -mtime +2 -exec rmdir {} + 2>/dev/null || true
  # tmp sweep dirs are env-overridable so tests stay hermetic (never touch the real /tmp).
  # shellcheck disable=SC2086  # intentional word-split over space-separated dirs
  for _td in ${CC_TMP_SWEEP_DIRS:-${TMPDIR:-/tmp} /private/tmp}; do
    [[ -d "$_td" ]] || continue
    find "$_td" -maxdepth 1 \( -name 'handoff-selfclose-*.log' -o -name 'handoff-recycle-*' \
         -o -name 'handoff-prompt-nb-*' \) -mtime +2 -delete 2>/dev/null || true
  done
  # >/dev/null: a backgrounded subshell INHERITS the hook stdout pipe, and the harness does not
  # see EOF until every writer closes it — a wedge with no live hook child (backlog 50627335fe9b).
) >/dev/null &
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

  # Acquire lock (skip if another cleanup is running).
  #
  # OWNER-VERIFIED STALE RECLAIM (a15/D6). This lock had neither a stale reap nor a trap: a bare
  # `mkdir || exit 0` released only by the `rm -rf` at the end of the block. A SIGKILL/OOM/reboot
  # between the two orphans the dir FOREVER, and every later SessionEnd GC then does
  # `mkdir → fail → exit 0` — a silent permanent skip.
  #
  # The asymmetry is the actual bug: this lock dir is SHARED with claude-latest:96 (both resolve
  # $HOME/.claude-versions/.cleanup_lock), and claude-latest DOES reclaim it by pid-liveness. So one
  # holder of the same mutex self-heals and the other wedges. Adopt the same reclaim so the policy
  # is symmetric — a lock is only ever stolen from a hoder that is provably GONE.
  #
  # pid+lstart, not pid alone: under load the OS recycles a dead holder's pid onto a new process and
  # `kill -0` then reports the corpse as alive, wedging the lock exactly as before (the land-lock
  # flake of 2026-07-25; scripts/land-lock.sh:96-112 carries the same rule). A recycled pid has a
  # different start time, so an lstart mismatch convicts it. When no lstart was recorded — a holder
  # from before this change, or claude-latest, which writes pid only — fall back to pid-liveness
  # alone rather than reaping a possibly-live holder: never steal from a maybe-live process.
  lock_dir="$VERSIONS_DIR/.cleanup_lock"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    lock_pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "")
    if [[ -z "$lock_pid" ]]; then
      # mkdir'd but the pid not yet written: a real owner mid-acquire. Give it a grace window and
      # only then treat it as debris, so we never race a holder that is 2 ms from writing its pid.
      lock_age=$(( $(date +%s) - $(stat -f %m "$lock_dir" 2>/dev/null || echo 0) ))
      [[ "$lock_age" -lt 30 ]] && exit 0
    elif kill -0 "$lock_pid" 2>/dev/null; then
      rec_lstart=$(cat "$lock_dir/lstart" 2>/dev/null || echo "")
      cur_lstart=$(ps -o lstart= -p "$lock_pid" 2>/dev/null || echo "")
      # live AND identity confirmed (or unrecorded) ⇒ a real holder ⇒ skip, never steal
      [[ -z "$rec_lstart" || "$rec_lstart" == "$cur_lstart" ]] && exit 0
    fi
    # holder is provably dead (or its pid was recycled) → reclaim
    rm -rf "$lock_dir" 2>/dev/null || exit 0
    mkdir "$lock_dir" 2>/dev/null || exit 0
  fi
  # THE RECORDED PID MUST BE THIS SUBSHELL'S, NOT `$$`. This GC body runs in a backgrounded,
  # disowned `( … ) &`, and on bash 3.2 `$$` inside a subshell is the PARENT shell's pid (verified:
  # 3.2.57 prints the same value in both; `BASHPID` does not exist before bash 4). That parent is the
  # SessionEnd hook, which exits within milliseconds of backgrounding us — so recording `$$` would
  # write a pid that is dead for almost the entire critical section, and the reclaim above would then
  # correctly conclude "holder dead" and steal the lock from this very much LIVE GC. A liveness token
  # has to name the process that actually holds the section.
  #
  # `$(exec sh -c 'echo $PPID')` is the bash-3.2 way to get it: `exec` replaces the command
  # substitution's forked child with `sh`, so sh's parent IS this subshell (verified against `$!`
  # from the parent — the non-exec form returns the cmd-subst fork instead and is wrong here).
  # Fall back to `$$` only if that yields no integer: a conservative token beats an empty one, which
  # the reclaim would read as "mid-acquire debris".
  own_pid=$(exec sh -c 'echo $PPID' 2>/dev/null)
  case "$own_pid" in ''|*[!0-9]*) own_pid=$$ ;; esac
  echo "$own_pid" > "$lock_dir/pid"
  ps -o lstart= -p "$own_pid" 2>/dev/null > "$lock_dir/lstart" || true
  # Release on EVERY exit of this subshell, not just the happy path at the bottom: any `exit`/error
  # between here and there would otherwise leave the dir for the reclaim above to clean up later.
  # (The reclaim is the SIGKILL backstop; the trap is what keeps ordinary exits from needing it.)
  #
  # OWNER-VERIFIED RELEASE: delete only while the recorded pid is still OURS. If our lock was
  # reclaimed as stale by a peer that now holds its own, the pid file is theirs and an unconditional
  # `rm -rf` here would delete a LIVE holder's lock and admit a third — the steal-then-double-release
  # chain (a15/D4). Verifying the token on the way out makes release idempotent and safe.
  trap '[ "$(cat "$lock_dir/pid" 2>/dev/null || echo)" = "$own_pid" ] && rm -rf "$lock_dir" 2>/dev/null; true' EXIT

  current_target=$(readlink "$CURRENT_LINK" 2>/dev/null | xargs basename 2>/dev/null || echo "")

  # Sort versions, build keep set
  versions=()
  for dir in "$VERSIONS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    v=$(basename "$dir")
    [[ "$v" == "current" || "$v" == .* ]] && continue
    versions+=("$v")
  done
  # shellcheck disable=SC2207  # intentional word-split of sorted version list (pre-existing)
  IFS=$'\n' sorted=($(printf '%s\n' "${versions[@]}" | sort -t. -k1,1rn -k2,2rn -k3,3rn))
  unset IFS

  # Keep set as a |-delimited STRING, not an associative array. `declare -A` is bash 4+; the shebang
  # here is /bin/bash, which on macOS is 3.2.57 with no bash 4 anywhere on PATH. So `declare -A`
  # failed on EVERY SessionEnd ("declare: -A: invalid option"), and the next line then parsed
  # `keep_set["$current_target"]=1` as an arithmetic index — "1.0.6: syntax error: invalid arithmetic
  # operator" — leaving the keep set empty and aborting the block. This GC has therefore never once
  # run: 0 "SessionEnd GC: removed" lines in ~/.claude/.update-versions.log against 29 removals from
  # claude-latest's path, with ~/.claude-versions sitting at 7 dirs / 833 MB. Found while testing the
  # lock above — a mutex whose critical section could not execute.
  #
  # This is claude-latest:117-130's idiom verbatim (the sibling that shares this very lock dir and
  # does the identical keep-set computation) rather than a new one: same repo, same logic, already
  # proven on 3.2. Pipes fence the match so `1.0.1` can never substring-match `11.0.1`.
  keep_set="|${current_target}|"
  kept=0
  for v in "${sorted[@]}"; do
    [[ "$v" == "$current_target" ]] && continue
    if [[ $kept -lt $KEEP_COUNT ]]; then
      keep_set="${keep_set}${v}|"
      kept=$((kept + 1))
    fi
  done

  for v in "${sorted[@]}"; do
    [[ "$keep_set" == *"|${v}|"* ]] && continue
    pgrep -f "claude-versions/$v" >/dev/null 2>&1 && continue
    # shellcheck disable=SC2115  # VERSIONS_DIR is always set (top of block); guard is defensive (pre-existing)
    rm -rf "$VERSIONS_DIR/$v" 2>/dev/null && \
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] SessionEnd GC: removed $v" >> "$HOME/.claude/.update-versions.log"
  done

  # No `rm -rf "$lock_dir"` here — the EXIT trap above is the SOLE release point. Doing both would
  # open the double-release hole this change exists to close: release here, a peer acquires in the
  # microseconds before this subshell exits, then our trap fires and deletes THEIR lock, admitting a
  # third holder. One releaser, and it verifies ownership before deleting (see the trap).
  # >/dev/null: a backgrounded subshell INHERITS the hook stdout pipe, and the harness does not
  # see EOF until every writer closes it — a wedge with no live hook child (backlog 50627335fe9b).
) >/dev/null &
disown 2>/dev/null || true

exit 0
