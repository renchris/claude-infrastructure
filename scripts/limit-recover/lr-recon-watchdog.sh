#!/usr/bin/env bash
# lr-recon-watchdog.sh — the standalone watchdog for the lr_recon reconciler daemon (§C9).
#
# One run per launchd tick (com.reso.lr-reconciler-watchdog, StartInterval 30). It reads the daemon's
# heartbeat and does exactly two things:
#   KILL  a holder that is alive but whose main loop has stopped making progress. KeepAlive restarts
#         the daemon; actuators survive because they run in their own sessions.
#   PAGE  a crash loop (holder pid changed twice within 10 min) or a dead daemon (heartbeat stale
#         >60 s with no live holder), latched once per 15 min, with the last line of its stderr.
#         A pid change this watchdog caused is not a crash: each kill is recorded as `kills=` in the
#         state, a change away from a killed (pid, lstart) is left out of the crash-loop count, and
#         two kills inside 10 min page as "watchdog killed N stalled holders" (FLEET_V2 W7d — the
#         2026-10-01 "crash loop" page was the watchdog's own two kills).
#
# WHY IT IS SEPARATE AND BASH 3.2: a watchdog that imports the package it watches shares its bugs and
# its interpreter. This imports nothing from lr_recon, reads the heartbeat with sed, and runs under
# launchd's /bin/bash 3.2 (no associative arrays, no mapfile, no ${x,,}).
#
# WHY FOUR CONDITIONS FOR A KILL, all required (§C9; condition 4 rewritten by FLEET_V2 W7d):
#   1. the holder (pid, lstart) is alive and not a zombie — lstart makes pid reuse unkillable;
#   2. `progress` unchanged across two reads >=30 s apart — one read cannot tell stalled from slow;
#   3. >=180 s since the last advance, measured from max(progress_wall, first time we saw this value)
#      — the later of the two, so a watchdog that just started cannot convict on the daemon's word;
#      and now - kern.waketime > 120 s — after a wake every clock-derived age is inflated by the sleep
#      (an unreadable waketime counts as "just woke": no verdict, no kill);
#   4. positive evidence the holder is NOT working: its CPU time (self + reaped children, `ps -S`)
#      advanced < 0.5 s over the trailing >=180 s window. Conditions 1-3 alone cannot tell a wedged
#      holder from a starved one: at load 174-427 (2026-10-01) they killed a working daemon mid-pass
#      and then its replacement at progress 0, and each kill made the next first pass slower. A
#      holder that accrues CPU is slow, and is logged "slow, not stalled", not killed. The floor sits
#      above the heartbeat thread's own writes (one per 10 s, a few centiseconds per window) and far
#      below a starved pass's share. Two exceptions bound it: a holder still at progress 0 within
#      600 s of its own lstart is on its first pass and is spared whatever its CPU (startup grace);
#      and frozen progress past 900 s is killed whatever its CPU, so a loop spinning without
#      progress still dies. No CPU reading yet (no sample 180 s old, or an unparsable `time`) means
#      no verdict and no kill until that 900 s ceiling.
#
# Never `launchctl kickstart -k` (the kill is ours to attribute; KeepAlive does the restart), never
# flock(1) (absent on macOS; one launchd job cannot overlap itself anyway).
#
# State: $LR_RECON_ROOT/watchdog.state (key=value, rewritten atomically every run).
# Log:   $LR_RECON_ROOT/watchdog.log (events only; rotated to .1 above 1 MiB).
# Test seams: LR_RECON_NOW, LR_RECON_WAKETIME, LR_RECON_KILL, LR_RECON_PAGE, LR_RECON_SLEEP,
#             LR_RECON_PS.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
WAKE_GUARD_S=120     # condition 3, wake half
CPU_MIN_CS=50        # condition 4: CPU centiseconds over the trailing STALL_AGE_S window = working
STARTUP_GRACE_S=600  # progress 0 this soon after the holder's own lstart = still on its first pass
STALL_MAX_S=900      # frozen progress this long is killed whatever the CPU says (a spinning loop)
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

# ── holder CPU (condition 4): self + reaped children, so work done in subprocesses counts ────────
cpu_cs() {  # $1=pid → accumulated CPU in centiseconds from `ps -S -o time=` ([h:]m:ss.cc), or nothing
  local t whole part acc=0 IFS=:
  t="$(LC_ALL=C "$PS" -S -o time= -p "$1" 2>/dev/null | tr -d '[:space:]')"
  case "$t" in *[!0-9:.]*|:*|*::*|*:.*) return 0 ;; *[0-9].[0-9][0-9]) ;; *) return 0 ;; esac
  whole="${t%.*}"
  for part in $whole; do acc=$((acc * 60 + 10#$part)); done
  printf '%s' "$((acc * 100 + 10#${t##*.}))"
}

lstart_epoch() {  # $1=lstart as ps prints it under TZ=UTC LC_ALL=C → epoch seconds, or nothing
  TZ=UTC LC_ALL=C date -j -f '%a %b %d %T %Y' "$1" +%s 2>/dev/null
}

secs() { printf '%d.%02d' "$(($1 / 100))" "$(($1 % 100))"; }  # centiseconds → "s.cc"

# ── previous run's state ─────────────────────────────────────────────────────────────────────────
S_PID=""; S_LSTART=""; S_PROG=""; S_PROG_SEEN=""; S_CHANGES=""; S_LAST_PAGE=""; S_CPU=""; S_KILLS=""
if [ -f "$STATE" ]; then
  while IFS='=' read -r k v; do
    case "$k" in
      cpu_samples) S_CPU="$v" ;;
      kills) S_KILLS="$v" ;;
      pid) S_PID="$v" ;;
      lstart) S_LSTART="$v" ;;
      progress) S_PROG="$v" ;;
      progress_seen) S_PROG_SEEN="$v" ;;
      pid_changes) S_CHANGES="$v" ;;
      last_page) S_LAST_PAGE="$v" ;;
    esac
  done < "$STATE"
fi

# Holder identity change ⇒ record it (crash-loop evidence) and restart progress tracking — unless
# this watchdog killed the old holder, in which case the restart is ours, not a crash.
kill_key() { printf '%s@%s' "$1" "$2" | tr ' ' '_'; }  # $1=pid $2=lstart → "pid@Thu_Oct_1_06:50:36_2026"
CHANGES=""
for t in $S_CHANGES; do
  is_int "$t" && [ $((NOW - t)) -le "$LOOP_WINDOW_S" ] && CHANGES="$CHANGES $t"
done
KILLS=""  # "t@pid@lstart" per kill this watchdog made, kept LOOP_WINDOW_S
for r in $S_KILLS; do
  t="${r%%@*}"
  is_int "$t" && [ $((NOW - t)) -le "$LOOP_WINDOW_S" ] && KILLS="$KILLS $r"
done
if [ "$S_PID" != "$HB_PID" ] || [ "$S_LSTART" != "$HB_LSTART" ]; then
  if [ -n "$S_PID" ]; then
    ours=0
    for r in $KILLS; do [ "${r#*@}" = "$(kill_key "$S_PID" "$S_LSTART")" ] && ours=1; done
    if [ "$ours" -eq 1 ]; then
      log "holder changed: $S_PID -> $HB_PID (restart after this watchdog's kill — not a crash)"
    else
      CHANGES="$CHANGES $NOW"
      log "holder changed: $S_PID -> $HB_PID"
    fi
  fi
  S_PROG=""; S_PROG_SEEN=""
fi
CHANGES="${CHANGES# }"
KILLS="${KILLS# }"

PROG_SEEN="$NOW"
CPU_SAMPLES=""
if is_int "$HB_PROGRESS" && [ "$S_PROG" = "$HB_PROGRESS" ] && is_int "$S_PROG_SEEN"; then
  PROG_SEEN="$S_PROG_SEEN"
  CPU_SAMPLES="$S_CPU"  # the same stall continues: so does its CPU history
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
    printf 'cpu_samples=%s\n' "$CPU_SAMPLES"
    printf 'kills=%s\n' "$KILLS"
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
  # lr-page.sh, the liveness-free page (FLEET_V2 W6 D6.5). This used `cc-notify --page`, an option
  # cc-notify never had: exit 2, discarded, and the latch set anyway, so no page ever reached anyone.
  # Only a posted page latches; a failed one is logged and tried again on the next run.
  if [ -n "${LR_RECON_PAGE:-}" ]; then
    "$LR_RECON_PAGE" "$text" >/dev/null 2>&1
  else
    /bin/bash "$HERE/lr-page.sh" --title reconciler-watchdog "$text" >/dev/null 2>&1
  fi || {
    log "PAGE FAILED (no channel took it): $text"
    return 0
  }
  LAST_PAGE="$NOW"
  log "PAGE: $text"
}

ALIVE=0
holder_alive "$HB_PID" "$HB_LSTART" && ALIVE=1

# CPU samples "t:cs", oldest first: one anchor at least STALL_AGE_S old (the newest such) plus every
# younger sample. CPU_WIN is the CPU spent between that anchor and now; empty = no evidence yet.
CPU_WIN=""; CPU_SPAN=""
if [ "$ALIVE" -eq 1 ]; then
  cpu_now="$(cpu_cs "$HB_PID")"
  is_int "$cpu_now" && CPU_SAMPLES="$CPU_SAMPLES $NOW:$cpu_now"
  anchor=""; younger=""
  for s in $CPU_SAMPLES; do
    st="${s%%:*}"; sc="${s#*:}"
    is_int "$st" && is_int "$sc" || continue
    if [ $((NOW - st)) -ge "$STALL_AGE_S" ]; then anchor="$s"; else younger="$younger $s"; fi
  done
  CPU_SAMPLES="${anchor}${younger}"
  CPU_SAMPLES="${CPU_SAMPLES# }"
  if [ -n "$anchor" ] && is_int "$cpu_now"; then
    CPU_WIN=$((cpu_now - ${anchor#*:}))
    CPU_SPAN=$((NOW - ${anchor%%:*}))
  fi
else
  CPU_SAMPLES=""
fi

# ── crash loop / dead daemon ─────────────────────────────────────────────────────────────────────
n_changes=0
for t in $CHANGES; do n_changes=$((n_changes + 1)); done
n_kills=0
for r in $KILLS; do n_kills=$((n_kills + 1)); done
if [ "$n_changes" -ge 2 ]; then
  page "crash loop — holder pid changed $n_changes times within $((LOOP_WINDOW_S / 60)) min (now pid $HB_PID)"
elif [ "$n_kills" -ge 2 ]; then
  page "watchdog killed $n_kills stalled holders within $((LOOP_WINDOW_S / 60)) min (now pid $HB_PID)"
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
    age=""; ls_epoch="$(lstart_epoch "$HB_LSTART")"
    is_int "$ls_epoch" && age=$((NOW - ls_epoch))
    load="$(/usr/sbin/sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | sed 's/^ *//; s/ *$//')"
    why=""
    if ! is_int "$wake"; then
      log "stalled ${stalled}s at progress=$HB_PROGRESS but kern.waketime unreadable — no kill"
    elif [ $((NOW - wake)) -le "$WAKE_GUARD_S" ]; then
      log "stalled ${stalled}s at progress=$HB_PROGRESS but woke $((NOW - wake))s ago — no kill"
    elif [ "$stalled" -ge "$STALL_MAX_S" ]; then
      why="past the ${STALL_MAX_S}s ceiling, whatever its CPU"
    elif [ "$HB_PROGRESS" = 0 ] && is_int "$age" && [ "$age" -lt "$STARTUP_GRACE_S" ]; then
      log "first pass: progress=0 for ${stalled}s, holder started ${age}s ago (startup grace ${STARTUP_GRACE_S}s) — no kill"
    elif ! is_int "$CPU_WIN"; then
      log "stalled ${stalled}s at progress=$HB_PROGRESS but no CPU reading across ${STALL_AGE_S}s yet — no kill"
    elif [ "$CPU_WIN" -ge "$CPU_MIN_CS" ]; then
      log "slow, not stalled: pid=$HB_PID progress=$HB_PROGRESS unchanged ${stalled}s, CPU +$(secs "$CPU_WIN")s over the last ${CPU_SPAN}s (load ${load:-?}) — no kill"
    else
      why="CPU +$(secs "$CPU_WIN")s over the last ${CPU_SPAN}s, under the $(secs "$CPU_MIN_CS")s floor (load ${load:-?})"
    fi
    if [ -n "$why" ]; then
      log "KILL -TERM pid=$HB_PID: progress=$HB_PROGRESS unchanged ${stalled}s; $why"
      KILLS="${KILLS:+$KILLS }$NOW@$(kill_key "$HB_PID" "$HB_LSTART")"
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
