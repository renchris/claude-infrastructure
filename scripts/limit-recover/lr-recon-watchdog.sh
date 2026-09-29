#!/usr/bin/env bash
# lr-recon-watchdog.sh — the standalone watchdog for the lr_recon reconciler daemon (§C9).
#
# One run per launchd tick (com.reso.lr-reconciler-watchdog, StartInterval 30). It reads the daemon's
# heartbeat and does exactly two things:
#   KILL  a holder that is alive but whose main loop has stopped making progress. KeepAlive restarts
#         the daemon; actuators survive because they run in their own sessions.
#   PAGE  a crash loop (holder pid changed twice within 10 min) or a dead daemon (heartbeat stale
#         >60 s with no live holder), latched once per 15 min, with the last line of its stderr.
#
# WHY IT IS SEPARATE AND BASH 3.2: a watchdog that imports the package it watches shares its bugs and
# its interpreter. This imports nothing from lr_recon, reads the heartbeat with sed, and runs under
# launchd's /bin/bash 3.2 (no associative arrays, no mapfile, no ${x,,}).
#
# WHY FOUR CONDITIONS FOR A KILL, all required (§C9):
#   1. the holder (pid, lstart) is alive and not a zombie — lstart makes pid reuse unkillable;
#   2. `progress` unchanged across two reads >=30 s apart — one read cannot tell stalled from slow;
#   3. >=180 s since the last advance, measured from max(progress_wall, first time we saw this value)
#      — the later of the two, so a watchdog that just started cannot convict on the daemon's word;
#   4. now - kern.waketime > 120 s — after a wake every clock-derived age is inflated by the sleep.
#   An unreadable waketime counts as "just woke": no verdict, no kill.
#
# Never `launchctl kickstart -k` (the kill is ours to attribute; KeepAlive does the restart), never
# flock(1) (absent on macOS; one launchd job cannot overlap itself anyway).
#
# State: $LR_RECON_ROOT/watchdog.state (key=value, rewritten atomically every run).
# Log:   $LR_RECON_ROOT/watchdog.log (events only; rotated to .1 above 1 MiB).
# Test seams: LR_RECON_NOW, LR_RECON_WAKETIME, LR_RECON_KILL, LR_RECON_PAGE, LR_RECON_SLEEP,
#             LR_RECON_PS.
set -u

LR_STATE_DIR="${LR_STATE_DIR:-$HOME/.reso/limit-recover}"
ROOT="${LR_RECON_ROOT:-$LR_STATE_DIR/recon}"
HB="$ROOT/heartbeat"
STATE="$ROOT/watchdog.state"
LOG="$ROOT/watchdog.log"
ERR="$ROOT/reconciler.err"

# No heartbeat ⇒ the daemon was never started or is not installed. Nothing to judge, say nothing.
[ -f "$HB" ] || exit 0

PS="${LR_RECON_PS:-/bin/ps}"
KILL="${LR_RECON_KILL:-kill}"
SLEEP="${LR_RECON_SLEEP:-sleep}"

STALL_READ_S=30      # condition 2: two reads at least this far apart
STALL_AGE_S=180      # condition 3
WAKE_GUARD_S=120     # condition 4
STALE_HB_S=60        # dead-daemon page
LOOP_WINDOW_S=600    # two pid changes inside this window = crash loop
PAGE_LATCH_S=900     # at most one page per this window
LOG_MAX_BYTES=1048576

NOW="${LR_RECON_NOW:-$(date +%s)}"
NOW="${NOW%%.*}"

log() {
  local sz ts
  if [ -f "$LOG" ]; then
    sz="$(wc -c < "$LOG" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$sz" ] && [ "$sz" -gt "$LOG_MAX_BYTES" ]; then mv -f "$LOG" "$LOG.1"; fi
  fi
  ts="$(date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '%s' "$NOW")"
  printf '%s %s\n' "$ts" "$*" >> "$LOG"
}

# ── heartbeat fields (compact JSON; sed, never jq or python) ─────────────────────────────────────
hb_num() {  # $1=key → the numeric value, integer part only; "wall" never matches "progress_wall"
  local v
  v="$(sed -n 's/.*"'"$1"'":[[:space:]]*\(-\{0,1\}[0-9][0-9.]*\).*/\1/p' "$HB" | head -n 1)"
  printf '%s' "${v%%.*}"
}
HB_PID="$(hb_num pid)"
HB_PROGRESS="$(hb_num progress)"
HB_WALL="$(hb_num wall)"
HB_PWALL="$(hb_num progress_wall)"
HB_LSTART="$(sed -n 's/.*"lstart":[[:space:]]*"\([^"]*\)".*/\1/p' "$HB" | head -n 1 | tr -s ' ')"

is_int() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

if ! is_int "$HB_PID" || [ -z "$HB_LSTART" ]; then
  log "heartbeat unreadable (pid='$HB_PID' lstart='$HB_LSTART') — no verdict"
  exit 0
fi

# ── holder liveness: (pid, lstart) exact under TZ=UTC LC_ALL=C, and not a zombie ─────────────────
holder_alive() {  # $1=pid $2=lstart
  local ls st
  ls="$(TZ=UTC LC_ALL=C "$PS" -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//')"
  [ -n "$ls" ] && [ "$ls" = "$2" ] || return 1
  st="$(LC_ALL=C "$PS" -o stat= -p "$1" 2>/dev/null | tr -d '[:space:]')"
  case "$st" in Z*|'') return 1 ;; esac
  return 0
}

# ── previous run's state ─────────────────────────────────────────────────────────────────────────
S_PID=""; S_LSTART=""; S_PROG=""; S_PROG_SEEN=""; S_CHANGES=""; S_LAST_PAGE=""
if [ -f "$STATE" ]; then
  while IFS='=' read -r k v; do
    case "$k" in
      pid) S_PID="$v" ;;
      lstart) S_LSTART="$v" ;;
      progress) S_PROG="$v" ;;
      progress_seen) S_PROG_SEEN="$v" ;;
      pid_changes) S_CHANGES="$v" ;;
      last_page) S_LAST_PAGE="$v" ;;
    esac
  done < "$STATE"
fi

# Holder identity change ⇒ record it (crash-loop evidence) and restart progress tracking.
CHANGES=""
for t in $S_CHANGES; do
  is_int "$t" && [ $((NOW - t)) -le "$LOOP_WINDOW_S" ] && CHANGES="$CHANGES $t"
done
if [ "$S_PID" != "$HB_PID" ] || [ "$S_LSTART" != "$HB_LSTART" ]; then
  if [ -n "$S_PID" ]; then
    CHANGES="$CHANGES $NOW"
    log "holder changed: $S_PID -> $HB_PID"
  fi
  S_PROG=""; S_PROG_SEEN=""
fi
CHANGES="${CHANGES# }"

PROG_SEEN="$NOW"
if is_int "$HB_PROGRESS" && [ "$S_PROG" = "$HB_PROGRESS" ] && is_int "$S_PROG_SEEN"; then
  PROG_SEEN="$S_PROG_SEEN"
fi

LAST_PAGE="$S_LAST_PAGE"
save_state() {
  local tmp="$STATE.tmp.$$"
  {
    printf 'pid=%s\n' "$HB_PID"
    printf 'lstart=%s\n' "$HB_LSTART"
    printf 'progress=%s\n' "$HB_PROGRESS"
    printf 'progress_seen=%s\n' "$PROG_SEEN"
    printf 'pid_changes=%s\n' "$CHANGES"
    printf 'last_page=%s\n' "$LAST_PAGE"
  } > "$tmp" && mv -f "$tmp" "$STATE"
}

page() {  # $1=reason — latched once per PAGE_LATCH_S across every reason
  local errline text
  if is_int "$LAST_PAGE" && [ $((NOW - LAST_PAGE)) -lt "$PAGE_LATCH_S" ]; then
    log "page latched ($(( NOW - LAST_PAGE ))s since last): $1"
    return 0
  fi
  errline="$(tail -n 1 "$ERR" 2>/dev/null)"
  text="lr-reconciler: $1 — last stderr: ${errline:-<none>}"
  if [ -n "${LR_RECON_PAGE:-}" ]; then
    "$LR_RECON_PAGE" "$text" >/dev/null 2>&1
  else
    "$HOME/.claude/bin/cc-notify" --page "$text" >/dev/null 2>&1
  fi
  LAST_PAGE="$NOW"
  log "PAGE: $text"
}

ALIVE=0
holder_alive "$HB_PID" "$HB_LSTART" && ALIVE=1

# ── crash loop / dead daemon ─────────────────────────────────────────────────────────────────────
n_changes=0
for t in $CHANGES; do n_changes=$((n_changes + 1)); done
if [ "$n_changes" -ge 2 ]; then
  page "crash loop — holder pid changed $n_changes times within $((LOOP_WINDOW_S / 60)) min (now pid $HB_PID)"
elif [ "$ALIVE" -eq 0 ] && is_int "$HB_WALL" && [ $((NOW - HB_WALL)) -gt "$STALE_HB_S" ]; then
  page "heartbeat stale $((NOW - HB_WALL))s and no live holder (last pid $HB_PID)"
fi

# ── the four-condition kill ──────────────────────────────────────────────────────────────────────
if [ "$ALIVE" -eq 1 ] && is_int "$HB_PROGRESS" && [ $((NOW - PROG_SEEN)) -ge "$STALL_READ_S" ]; then
  since="$PROG_SEEN"
  is_int "$HB_PWALL" && [ "$HB_PWALL" -gt "$since" ] && since="$HB_PWALL"
  stalled=$((NOW - since))
  if [ "$stalled" -ge "$STALL_AGE_S" ]; then
    wake="${LR_RECON_WAKETIME:-$(/usr/sbin/sysctl -n kern.waketime 2>/dev/null | sed -n 's/^{ *sec = \([0-9][0-9]*\).*/\1/p')}"
    wake="${wake%%.*}"
    if ! is_int "$wake"; then
      log "stalled ${stalled}s at progress=$HB_PROGRESS but kern.waketime unreadable — no kill"
    elif [ $((NOW - wake)) -le "$WAKE_GUARD_S" ]; then
      log "stalled ${stalled}s at progress=$HB_PROGRESS but woke $((NOW - wake))s ago — no kill"
    else
      log "KILL -TERM pid=$HB_PID: progress=$HB_PROGRESS unchanged ${stalled}s"
      "$KILL" -TERM "$HB_PID" >/dev/null 2>&1
      "$SLEEP" 10
      if holder_alive "$HB_PID" "$HB_LSTART"; then
        log "KILL -KILL pid=$HB_PID: still alive 10s after TERM"
        "$KILL" -KILL "$HB_PID" >/dev/null 2>&1
      fi
    fi
  fi
fi

save_state
exit 0
