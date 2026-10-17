#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 52-load-2026-10-17  —  the operator's switches for the load-root-cause program (DESIGN WP-16)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHY (docs/research/load-root-cause-2026-10-17/DESIGN.md §3.4, §4.1, rows X5 / X9 / X17, WP-16):
#   the program ships every new behaviour INERT. The 5 s sampler is a staged plist, the worktree-gc wake
#   run logs what it WOULD do, the load rung keeps paging. Each turns on by one switch that only the
#   operator flips, after reading the evidence this script prints next to it. No agent runs this (C10).
#
#   52-load-2026-10-17-activate.sh                       report every step's state; change NOTHING
#   52-load-2026-10-17-activate.sh --confirm <target>    repeatable; each target is one gated step:
#     capacity-attrib            install launchd/staged/com.claude.capacity-attrib.plist into
#                                ~/Library/LaunchAgents if absent or different, clear a disabled bit,
#                                bootstrap it, then read back: `launchctl print` running with a pid AND
#                                ~/.claude/logs/attrib-latest.json under 15 s old naming that same pid.
#     worktree-gc-events         print the observe evidence (would_park / would_detach / would_lock /
#                                would_keep counts, first and last row dates, from the wake and foreign
#                                logs), refuse if neither log has a row, then write `act` to
#                                ~/.claude/autonomy/worktree-gc-events.mode and read it back.
#     capacity-alarm-load-rung   write `record-only` to ~/.claude/autonomy/capacity-alarm-load-rung.mode,
#                                refused until detector D2 has run record-only for 7 d (D2 GATE).
#   52-load-2026-10-17-activate.sh --archive-floor-gb <N>
#                                write the whole number N (GB) to ~/.claude/autonomy/worktree-gc-archive-floor.gb;
#                                the backstop exports it as CC_WTGC_ARCHIVE_FLOOR_GB in act mode.
#   Arguments combine; every argument is validated before anything is written. A refused step leaves its
#   file untouched and the run exits 1; the other confirmed steps still run.
#
# NEVER DONE HERE, BY DESIGN:
#   · ~/.claude/autonomy/worktree-gc-repos.promoted is NEVER written. That is OP-5: the operator appends a
#     foreign repo's absolute common dir after reading 7 d of that repo's observe log (printed below).
#   · the ms365 cutover is reported, never run: it is WP-8's own migration (0067-ms365-shared.sh, branch
#     load-w1-ci at time of writing), which carries its own gate and its own --confirm.
#   · no tracked file is edited. Once the capacity-attrib read-back passes, an agent moves that label's
#     launchd/fleet.manifest row staged -> run (printed at the end).
#
# D2 GATE (program lead's ruling 2026-10-17, leg 2 amended): "7 d of D2 record-only" is proven by two
#   legs, never by D2's own rows. (1) The DEPLOYED ~/.claude/scripts/lib/capacity-attrib.py calls the
#   detectors (a static grep for capacity-detect / Detectors) AND trunk has a commit that wired them
#   (`git log -1 -S capacity-detect origin/main -- scripts/lib/capacity-attrib.py`); at time of writing
#   neither holds, so this step refuses today, and says so. (2) A 7 d clock that starts at the LATER of
#   the installed capacity-attrib plist's mtime (this script's cp sets it, and a reinstall resets it)
#   and that wiring commit's time, AND the daemon is live now: attrib-latest.json under 15 s old,
#   naming launchd's running pid. D2's rows in ~/.claude/logs/capacity-detect.jsonl are
#   printed as information only: they are event-sparse (a calm D2 writes none), and `--replay` stamps
#   them with SERIES time, so neither their count nor their age can prove the detector ran. The
#   daemon's own series cannot carry the 7 d either: it keeps two 4 MiB generations, ~10 h.
#   WEAKNESS, stated: leg 2 proves activation (of both the plist and the wiring) 7 d ago plus liveness
#   now, NOT 7 d of continuous ticks; a daemon that was down for six of those days passes. The sound
#   measure would be a counter the daemon itself persists per tick. No override flag.
#
# MIGRATION NUMBERING (WP-16 is the single numbering owner, checked 2026-10-17): origin/main's highest is
#   0066-hook-if-filters; WP-8's is 0067-ms365-shared on load-w1-ci, so the numbers are distinct. Both
#   write ~/.claude/settings.json `.hooks.PreToolUse` (0066 also `.hooks.PostToolUse`), but neither
#   clobbers the other: 0067 APPENDS one entry (matcher `mcp__ms365__.*`, command ms365-shared-guard.sh)
#   and verifies everything outside PreToolUse unchanged and PreToolUse equal to old + that entry; 0066
#   rewrites only hooks whose command matches pr-gate / relay-verbatim / ship-rail-push-allow and
#   verifies the rest byte-equal after normalising out exactly those. So either order converges. Each
#   does an unlocked read-backup-tmp-mv: run them one at a time, never concurrently.
#
# UNDO, per step:
#   capacity-attrib       launchctl bootout gui/$(id -u)/com.claude.capacity-attrib; rm ~/Library/LaunchAgents/com.claude.capacity-attrib.plist
#   worktree-gc-events    echo observe > ~/.claude/autonomy/worktree-gc-events.mode   (absent also reads observe)
#   load rung             rm ~/.claude/autonomy/capacity-alarm-load-rung.mode
#   archive floor         rm ~/.claude/autonomy/worktree-gc-archive-floor.gb   (unset ⇒ never archive)
# Seams (tests): CC_ACT52_LAUNCHCTL · CC_ACT52_REPO · CC_ACT52_WAIT_S · HOME.
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
N=52
REPO="${CC_ACT52_REPO:-$HOME/Development/claude-infrastructure}"
LC="${CC_ACT52_LAUNCHCTL:-launchctl}"
WAIT_S="${CC_ACT52_WAIT_S:-20}"
DOMAIN="gui/$(id -u)"
AUTO="$HOME/.claude/autonomy"
LOGS="$HOME/.claude/logs"
LABEL=com.claude.capacity-attrib
SRC_PLIST="$REPO/launchd/staged/$LABEL.plist"   # staged/: outside install.sh's glob, so only THIS loads it
DST_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LATEST="$LOGS/attrib-latest.json"
EV_MODE="$AUTO/worktree-gc-events.mode"
WAKE_LOG="$LOGS/worktree-gc-wake.log"
FOREIGN_LOG="$LOGS/worktree-gc-foreign.log"
RUNG_MODE="$AUTO/capacity-alarm-load-rung.mode"
DETECT_LOG="$LOGS/capacity-detect.jsonl"
FLOOR_FILE="$AUTO/worktree-gc-archive-floor.gb"
PROMOTED="$AUTO/worktree-gc-repos.promoted"
MS_MARKER="$HOME/.claude/state/ms365-shared.active"
DONE="$AUTO/pending-activation/52-load-2026-10-17-activate.sh.done"
WEEK_S=604800

usage() {
  echo "usage: $0 [--confirm capacity-attrib|worktree-gc-events|capacity-alarm-load-rung]... [--archive-floor-gb N]" >&2
  echo "       no arguments = report only, nothing written" >&2
  exit 2
}

# ── Validate EVERY argument before anything is written ─────────────────────────────────────────
do_attrib=0; do_events=0; do_rung=0; floor=""
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm)
      case "${2:-}" in
        capacity-attrib) do_attrib=1 ;;
        worktree-gc-events) do_events=1 ;;
        capacity-alarm-load-rung) do_rung=1 ;;
        *) echo "$N: --confirm must name its target, one of capacity-attrib, worktree-gc-events, capacity-alarm-load-rung (got '${2:-}')" >&2; usage ;;
      esac
      shift 2 ;;
    --archive-floor-gb)
      # A whole, positive number of GB. 0 or a leading zero is refused rather than guessed at: the
      # consumer (worktree-gc.sh) reads anything non-numeric as "no archive", and a typo must not be
      # silently stored as a different floor.
      case "${2:-}" in
        ''|*[!0-9]*|0*) echo "$N: --archive-floor-gb needs a whole number of GB, 1 or more (got '${2:-}')" >&2; usage ;;
      esac
      floor="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "$N: unknown argument '$1'" >&2; usage ;;
  esac
done

failed=0
refuse() { echo "   REFUSED: $*" >&2; failed=1; }

# read_word <file> → the file's first word, or empty. A separate call from any write, so a read-back
# proves what is on disk, not what the writer meant.
read_word() {
  local w=""
  [ -r "$1" ] && { read -r w _ < "$1" || true; }
  printf '%s' "$w"
}

# write_switch <file> <value>: atomic write, then a read-back by read_word. rc 1 on any mismatch.
write_switch() {
  local f="$1" v="$2" tmp
  mkdir -p "$(dirname "$f")" || return 1
  tmp="$f.tmp.$$"
  printf '%s\n' "$v" > "$tmp" && mv "$tmp" "$f" || { rm -f "$tmp"; return 1; }
  [ "$(read_word "$f")" = "$v" ]
}

age_of() { echo $(( $(date +%s) - $(stat -f %m "$1" 2>/dev/null || echo 0) )); }
lc_pid() { "$LC" print "$DOMAIN/$LABEL" 2>/dev/null | awk '$1 == "pid" && $2 == "=" { print $3; exit }'; }
latest_pid() { /usr/bin/plutil -extract pid raw -o - "$LATEST" 2>/dev/null; }

# ── 1. capacity-attrib ─────────────────────────────────────────────────────────────────────────
echo "== 1. $LABEL (the 5 s sampler, DESIGN §4.1)"
if [ ! -f "$SRC_PLIST" ]; then echo "   source plist: MISSING ($SRC_PLIST — has WP-16 landed and converged?)"
elif [ -f "$DST_PLIST" ] && cmp -s "$SRC_PLIST" "$DST_PLIST"; then echo "   plist: installed, matches the repo"
elif [ -f "$DST_PLIST" ]; then echo "   plist: installed, DIFFERS from the repo (confirm reinstalls it)"
else echo "   plist: not installed"
fi
if "$LC" print "$DOMAIN/$LABEL" >/dev/null 2>&1; then echo "   launchd: loaded, pid $(lc_pid || true)"
else echo "   launchd: not loaded"
fi
if [ -f "$LATEST" ]; then echo "   attrib-latest.json: $(age_of "$LATEST") s old, pid $(latest_pid || echo '?')"
else echo "   attrib-latest.json: absent"
fi
if [ "$do_attrib" = 1 ]; then
  attrib_step() {
    [ -f "$SRC_PLIST" ] || { refuse "missing $SRC_PLIST"; return; }
    /usr/bin/plutil -lint "$SRC_PLIST" >/dev/null || { refuse "$SRC_PLIST does not parse"; return; }
    mkdir -p "$(dirname "$DST_PLIST")"
    if ! { [ -f "$DST_PLIST" ] && cmp -s "$SRC_PLIST" "$DST_PLIST"; }; then
      /bin/cp "$SRC_PLIST" "$DST_PLIST" || { refuse "could not write $DST_PLIST"; return; }
      cmp -s "$SRC_PLIST" "$DST_PLIST" || { refuse "$DST_PLIST does not match after the copy"; return; }
      echo "   installed $DST_PLIST"
    fi
    if ! "$LC" print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      if "$LC" print-disabled "$DOMAIN" 2>/dev/null | grep -F "\"$LABEL\" => disabled" >/dev/null; then
        "$LC" enable "$DOMAIN/$LABEL" || { refuse "launchctl enable $LABEL failed"; return; }
        echo "   cleared the domain-level disabled bit"
      fi
      "$LC" bootstrap "$DOMAIN" "$DST_PLIST" 2>/dev/null || true
      "$LC" print "$DOMAIN/$LABEL" >/dev/null 2>&1 || { refuse "could not load $LABEL"; return; }
      echo "   bootstrapped"
    fi
    # Read back, fail closed: launchd's pid, and the heartbeat naming THAT pid, under 15 s old (the
    # same line past which capacity-alarm stops trusting the file).
    local pid="" hpid="" age=999 i=0
    while [ "$i" -lt "$WAIT_S" ]; do
      pid="$(lc_pid)"; hpid="$(latest_pid)"
      if [ -n "$pid" ] && [ -f "$LATEST" ]; then
        age="$(age_of "$LATEST")"
        [ "$age" -le 15 ] && [ "$hpid" = "$pid" ] && break
      fi
      i=$((i + 1)); sleep 1
    done
    "$LC" print "$DOMAIN/$LABEL" 2>/dev/null | grep 'state = running' >/dev/null \
      || { refuse "$LABEL is loaded but not running — check ~/.claude/logs/capacity-attrib.err.log"; return; }
    [ -n "$pid" ] || { refuse "$LABEL reports no pid"; return; }
    [ -f "$LATEST" ] || { refuse "no $LATEST after ${WAIT_S} s — check ~/.claude/logs/capacity-attrib.err.log"; return; }
    [ "$age" -le 15 ] || { refuse "$LATEST is ${age} s old (capacity-alarm would ignore it)"; return; }
    [ "$hpid" = "$pid" ] || { refuse "$LATEST names pid '$hpid', launchd runs $pid — another writer, or a stale file"; return; }
    echo "   VERIFIED: running, pid $pid, heartbeat ${age} s old and written by that pid"
    attrib_ok=1
  }
  attrib_ok=0; attrib_step
else
  echo "   would: install + bootstrap + read back   (--confirm capacity-attrib)"
fi

# ── 2. worktree-gc event mode ──────────────────────────────────────────────────────────────────
# Evidence is counted by token, whatever the row layout: a line counts toward would_park if it carries
# that word (grep -w; `verdict=would_park` matches, `would_parked` does not).
ev_rows_total=0
ev_report() {
  local f="$1" rows t c first last line=""
  if [ ! -s "$f" ]; then echo "   $f: no rows"; return; fi
  rows="$(grep -c . "$f" 2>/dev/null || true)"; rows="${rows:-0}"
  ev_rows_total=$((ev_rows_total + rows))
  line="   $f: $rows row(s)"
  for t in would_park would_detach would_lock would_keep; do
    c="$(grep -cw -- "$t" "$f" 2>/dev/null || true)"
    line="$line · $t ${c:-0}"
  done
  first="$(grep -m1 . "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
  last="$(grep . "$f" | tail -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
  echo "$line"
  echo "      first row ${first:-undated} · last row ${last:-undated}"
}
echo "== 2. worktree-gc event mode (DESIGN §3.4; read by scripts/lib/wtgc-scope.sh)"
cur="$(read_word "$EV_MODE")"
echo "   mode: ${cur:-absent} ⇒ $([ "$cur" = act ] && echo act || echo observe)"
ev_report "$WAKE_LOG"
ev_report "$FOREIGN_LOG"
if [ "$do_events" = 1 ]; then
  if [ "$ev_rows_total" -eq 0 ]; then
    refuse "neither observe log has a row: there is no evidence to activate on"
  elif write_switch "$EV_MODE" act; then
    echo "   VERIFIED: $EV_MODE reads back 'act' — the next wake or backstop run acts on the home repo"
  else
    refuse "could not write $EV_MODE, or it did not read back 'act'"
  fi
else
  echo "   would: write 'act' after reading the counts above   (--confirm worktree-gc-events)"
fi

# OP-5, printed every run and never acted on.
echo "   OP-5 (foreign repos — yours, not this script's): no foreign repo's trees are ever moved or removed"
echo "      until you append its absolute git common dir, one per line, to $PROMOTED, after at least 7 d"
echo "      of its rows in $FOREIGN_LOG. Delete the line to demote. This script never writes that file."
if [ -s "$PROMOTED" ]; then echo "      promoted today: $(grep -c . "$PROMOTED" 2>/dev/null || echo 0) repo(s)"
else echo "      promoted today: none"
fi

# ── 3. capacity-alarm load rung ────────────────────────────────────────────────────────────────
echo "== 3. capacity-alarm load rung (DESIGN X17)"
cur="$(read_word "$RUNG_MODE")"
echo "   mode: ${cur:-absent (the rung pages as today)}"
d2="$(python3 -I -c '
import calendar, json, sys, time
n, raises, first, last = 0, 0, None, None
try:
    fh = open(sys.argv[1], errors="replace")
except OSError:
    print("0 0 - -"); sys.exit(0)
for line in fh:
    try:
        r = json.loads(line)
        if r.get("det") != "D2" or r.get("mode") != "record-only":
            continue
        t = calendar.timegm(time.strptime(r["ts"], "%Y-%m-%dT%H:%M:%SZ"))
    except Exception:
        continue
    n += 1
    raises += r.get("event") == "raise"
    first = t if first is None or t < first else first
    last = t if last is None or t > last else last
print(n, raises, first if first is not None else "-", last if last is not None else "-")
' "$DETECT_LOG" 2>/dev/null || echo "0 0 - -")"
# shellcheck disable=SC2086  # deliberate split of the four-field "n raises first last" line
set -- $d2
d2_n="${1:-0}"; d2_raises="${2:-0}"; d2_first="${3:--}"; d2_last="${4:--}"
if [ "$d2_n" -gt 0 ] 2>/dev/null; then
  echo "   D2 rows (information only): $d2_n, $d2_raises raise(s) · first $(date -u -r "$d2_first" +%Y-%m-%dT%H:%MZ)" \
       "· last $(date -u -r "$d2_last" +%Y-%m-%dT%H:%MZ)"
else
  echo "   D2 rows (information only): none in $DETECT_LOG"
fi
# Leg 1: the deployed sampler calls the detectors. Leg 2: installed 7 d ago, live now (header, D2 GATE).
DEPLOYED_ATTRIB="$HOME/.claude/scripts/lib/capacity-attrib.py"
d2_wired=0
wired_ct="$(git -C "$REPO" log -1 --format=%ct -S capacity-detect origin/main -- scripts/lib/capacity-attrib.py 2>/dev/null || true)"
case "$wired_ct" in ''|*[!0-9]*) wired_ct="" ;; esac
grep -Eq 'capacity-detect|Detectors' "$DEPLOYED_ATTRIB" 2>/dev/null && [ -n "$wired_ct" ] && d2_wired=1
echo "   leg 1, D2 wired into the deployed sampler: $([ "$d2_wired" = 1 ] && echo "yes (trunk commit $(date -u -r "$wired_ct" +%Y-%m-%dT%H:%MZ))" || echo "NO ($DEPLOYED_ATTRIB; trunk wiring commit: ${wired_ct:-none})")"
# The 7 d clock starts at the LATER of the plist install and the wiring commit.
clock_start="$(date +%s)"
if [ -f "$DST_PLIST" ]; then
  clock_start="$(stat -f %m "$DST_PLIST" 2>/dev/null || echo "$clock_start")"
  [ -n "$wired_ct" ] && [ "$wired_ct" -gt "$clock_start" ] && clock_start="$wired_ct"
fi
clock_age=$(( $(date +%s) - clock_start ))
live_pid="$(lc_pid || true)"; hb_pid="$(latest_pid || true)"; hb_age=999999
[ -f "$LATEST" ] && hb_age="$(age_of "$LATEST")"
d2_live=0
[ -n "$live_pid" ] && [ "$hb_pid" = "$live_pid" ] && [ "$hb_age" -le 15 ] && d2_live=1
echo "   leg 2, $((clock_age / 86400)) d since the later of sampler install and wiring (7 required), live now: $([ "$d2_live" = 1 ] && echo yes || echo no)"
if [ "$do_rung" = 1 ]; then
  if [ "$d2_wired" = 0 ]; then
    refuse "D2 is not running live; capacity-attrib does not call the detectors"
  elif [ ! -f "$DST_PLIST" ] || [ "$clock_age" -lt "$WEEK_S" ]; then
    refuse "D2 has run live for $((clock_age / 86400)) d (from the later of the sampler install and the wiring commit); 7 d are required"
  elif [ "$d2_live" = 0 ]; then
    refuse "the capacity-attrib sampler is not live now (launchd pid '${live_pid}', heartbeat pid '${hb_pid}', ${hb_age} s old)"
  elif write_switch "$RUNG_MODE" record-only; then
    echo "   VERIFIED: $RUNG_MODE reads back 'record-only'"
  else
    refuse "could not write $RUNG_MODE, or it did not read back 'record-only'"
  fi
else
  echo "   would: write 'record-only' once both legs hold   (--confirm capacity-alarm-load-rung)"
fi

# ── 4. worktree-gc ARCHIVE floor ───────────────────────────────────────────────────────────────
echo "== 4. worktree-gc ARCHIVE free-space floor (CC_WTGC_ARCHIVE_FLOOR_GB in act mode)"
cur="$(read_word "$FLOOR_FILE")"
echo "   floor: ${cur:-unset (never archive)}${cur:+ GB}"
if [ -n "$floor" ]; then
  if write_switch "$FLOOR_FILE" "$floor"; then echo "   VERIFIED: $FLOOR_FILE reads back $floor"
  else refuse "could not write $FLOOR_FILE, or it did not read back $floor"
  fi
else
  echo "   would: record your floor   (--archive-floor-gb N)"
fi

# ── 5. ms365 shared server (WP-8) — report only ────────────────────────────────────────────────
echo "== 5. ms365 shared server (WP-8; report only, never run here)"
if [ -e "$MS_MARKER" ]; then echo "   active: $MS_MARKER exists"
else echo "   not active: no $MS_MARKER"
fi
mig=""
for m in "$REPO"/migrations/0*-ms365-shared.sh; do [ -f "$m" ] && mig="$m"; done
if [ -n "$mig" ]; then
  run_line="$(sed -n 's/^# migration-run: //p' "$mig" | head -1)"
  echo "   its own command (it has its own gate): ${run_line:-see the header of $mig}"
else
  echo "   its migration is not in $REPO/migrations yet (WP-8, branch load-w1-ci)"
fi

# ── Close ──────────────────────────────────────────────────────────────────────────────────────
# Marked done only when every gated switch reads back in place, read here and not from this run's
# flags, so a re-run after a partial activation can complete it.
if "$LC" print "$DOMAIN/$LABEL" 2>/dev/null | grep 'state = running' >/dev/null \
   && [ "$(read_word "$EV_MODE")" = act ] && [ "$(read_word "$RUNG_MODE")" = record-only ] \
   && [ "$((do_attrib + do_events + do_rung))" -gt 0 ] && [ "$failed" = 0 ]; then
  mkdir -p "$(dirname "$DONE")" && touch "$DONE" && echo "== all three switches in place: marked $DONE"
fi
if [ "${attrib_ok:-0}" = 1 ]; then
  echo "FOLLOW-UP (an agent's edit, not this script's): move the $LABEL row in launchd/fleet.manifest staged -> run."
fi
if [ "$failed" = 1 ]; then echo "$N: one or more confirmed steps were REFUSED (above); nothing else was changed." >&2; exit 1; fi
if [ "$((do_attrib + do_events + do_rung))" -eq 0 ] && [ -z "$floor" ]; then echo "$N: report only — nothing written."; fi
exit 0
