#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 55-load-2026-10-17-w0-operator  —  Wave 0 of the load-root-cause program, handed over as one script
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHY (docs/plans/LOAD_ROOT_CAUSE_2026_10_17.md scope: "hand every operator-only step over as one
#   script"; DESIGN §5 rows OP-1, OP-2, OP-2b, OP-2c, OP-4): W1-W5 landed, but W0 is root-only and was
#   left as prose in the design. Every W0 step needs sudo, a GUI, or a judgment only the operator makes,
#   so no agent runs this (C10). It reads each step's state, prints the evidence next to it, and acts
#   only on a step the operator names.
#
#   55-load-2026-10-17-w0-operator.sh                  report every step's state; change NOTHING, no sudo
#   55-load-2026-10-17-w0-operator.sh --confirm <target> [--window peak|idle]   repeatable:
#     spotlight-privacy   OP-1 precondition: back up the Data volume's Spotlight VolumeConfiguration.plist
#                         into the capture dir, add ~/Development to its Exclusions, read it back.
#     fseventsd-restart   OP-1 / X1: refused unless the Exclusions entry reads back AND fseventsd's
#                         footprint is >= 1 GB (healthy is under 100 MB; X1 ran ~10:00Z 2026-10-17 and
#                         left it at 14 MB). Records mdutil + mds CPU, `sample`s the daemon, TERM, up to
#                         10 s, KILL only if still alive, then requires launchd's NEW pid.
#     mds-record          OP-1 follow-up: one mdutil -s + mds/mds_stores CPU record. Run it 10 min and
#                         1 h after the restart (DESIGN X1 verify).
#     xcrun-cache         OP-2 / X24: `xcrun --kill-cache`, re-stat after 3 s (a rename race can restore
#                         the old db), remove xcrun_db-* temp files older than 60 min in that dir only.
#     wired-capture       OP-2b: zprint (top 40 + full), vm_stat, top, AGXAccelerator; needs --window.
#     fsusage-capture     OP-2c: fs_usage recipes A (filesys, 10 s) and B (diskio, 20 s) with the IOKit
#                         Statistics counters read before and after as the positive control; needs --window.
#   --window peak needs >= 2 test gates running (DESIGN: "at peak (>= 2 gates running)"); --window idle
#   needs none. The census is recorded beside the capture either way. Each window is captured once.
#   Every argument is validated before anything runs; a refused step exits 1 and the others still run.
#
# NEVER DONE HERE, BY DESIGN:
#   · no process is signalled by a pid named in this file or the design. The X24 orphans (render.mjs,
#     the zfav driver) and the stale `claude stop` session are CENSUSED BY KIND and printed; the
#     decision and the kill are the operator's (a pid recorded at filing is re-issued, never defused).
#   · coreaudiod is not restarted: 48-coreaudiod-watchdog-install.sh owns that repair, with its own gates.
#   · OP-4 (kern.maxvnodes) is reported only: W6 is conditional on the re-measurement (backlog
#     75b041426dba), so the sysctl is printed for after that ruling, never run.
#   · OP-3, OP-5, OP-6 and the program's migrations are listed with their backlog rows, not run.
#
# Captures land in ~/.claude/logs/load-2026-10-17/w0/, never /tmp (the /tmp cleaner erodes old files).
# UNDO: spotlight-privacy → restore the backup it printed (sudo cp <backup> <plist>) or remove the entry
#   in System Settings → Spotlight → Search Privacy. The rest change no setting and have nothing to undo.
# Seams (tests): CC_W0_SUDO · CC_W0_OUT · CC_W0_DEV · CC_W0_SPOT_PLIST · CC_W0_PLISTBUDDY · CC_W0_WAIT_S · HOME.
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
N=55
SUDO="${CC_W0_SUDO:-sudo}"
OUT="${CC_W0_OUT:-$HOME/.claude/logs/load-2026-10-17/w0}"
DEV="${CC_W0_DEV:-$HOME/Development}"
SPOT_PLIST="${CC_W0_SPOT_PLIST:-/System/Volumes/Data/.Spotlight-V100/VolumeConfiguration.plist}"
PB="${CC_W0_PLISTBUDDY:-/usr/libexec/PlistBuddy}"
WAIT_S="${CC_W0_WAIT_S:-10}"
DONE="$HOME/.claude/autonomy/pending-activation/55-load-2026-10-17-w0-operator.sh.done"
FOOT_WEDGED_MB=1024   # refuse a restart below this: the wedge measured 11-13 GB, healthy is < 100 MB

usage() {
  echo "usage: $0 [--confirm spotlight-privacy|fseventsd-restart|mds-record|xcrun-cache|wired-capture|fsusage-capture]... [--window peak|idle]" >&2
  echo "       no arguments = report only, nothing written, no sudo" >&2
  exit 2
}

# ── Validate EVERY argument before anything runs ───────────────────────────────────────────────
do_spot=0; do_fsev=0; do_mds=0; do_xcrun=0; do_wired=0; do_fsu=0; window=""
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm)
      [ $# -ge 2 ] || { echo "$N: --confirm needs a target" >&2; usage; }
      case "$2" in
        spotlight-privacy) do_spot=1 ;;
        fseventsd-restart) do_fsev=1 ;;
        mds-record) do_mds=1 ;;
        xcrun-cache) do_xcrun=1 ;;
        wired-capture) do_wired=1 ;;
        fsusage-capture) do_fsu=1 ;;
        *) echo "$N: unknown --confirm target '$2'" >&2; usage ;;
      esac
      shift 2 ;;
    --window)
      [ $# -ge 2 ] || { echo "$N: --window needs peak or idle" >&2; usage; }
      case "$2" in peak|idle) window="$2" ;; *) echo "$N: --window must be peak or idle (got '$2')" >&2; usage ;; esac
      shift 2 ;;
    -h|--help) usage ;;
    *) echo "$N: unknown argument '$1'" >&2; usage ;;
  esac
done
if [ $((do_wired + do_fsu)) -gt 0 ] && [ -z "$window" ]; then
  echo "$N: wired-capture and fsusage-capture need --window peak|idle" >&2; usage
fi

failed=0
refuse() { echo "   REFUSED: $*" >&2; failed=1; }
stamp() { date -u +%Y%m%dT%H%M%SZ; }
outdir() { mkdir -p "$OUT" || { refuse "cannot create $OUT"; return 1; }; }

# top's MEM column ("11G", "14M", "512K", "980B", optionally with a trailing +/-) → whole MB; empty if
# unreadable. top is the instrument DESIGN F §1 measured the wedge with (MEM 11G, CMPRS 4231M).
to_mb() {
  local v="${1%[+-]}" n u
  n="${v%[BKMGT]}"; u="${v#"$n"}"
  case "$n" in ''|*[!0-9.]*) return 0 ;; esac
  awk -v n="$n" -v u="$u" 'BEGIN { m = (u=="G") ? 1024 : (u=="T") ? 1048576 : (u=="K") ? 1/1024 : (u=="B") ? 1/1048576 : 1; printf "%d\n", n*m }'
}
alive() { ps -p "$1" >/dev/null 2>&1; }
fsev_pid() { pgrep -x fseventsd 2>/dev/null | head -1; }
fsev_mb() { [ -n "$1" ] && to_mb "$(top -l 1 -pid "$1" -stats mem 2>/dev/null | tail -1 | tr -d ' ')"; }
# Test gates in flight: pytest and bats controllers. pgrep never lists itself, so this census cannot
# match its own pattern (an argv-carrying `ps | awk` would).
gate_count() { pgrep -f 'pytest|bin/bats|libexec/bats' 2>/dev/null | wc -l | tr -d ' '; }
excluded() {   # needs root: the Data volume's Spotlight store is root-only
  "$SUDO" "$PB" -c 'Print :Exclusions' "$SPOT_PLIST" 2>/dev/null | sed 's/^[[:space:]]*//' | grep -Fx -- "$DEV" >/dev/null
}
mds_record() {   # → one record file; the X1 verify reads these at -0, +10 min and +1 h
  local f; f="$OUT/$(stamp)-mds.txt"
  {
    echo "# mdutil -s /System/Volumes/Data"; mdutil -s /System/Volumes/Data 2>&1
    echo "# ps -o pid,time,comm (mds, mds_stores): diff two records for CPU-s"
    for p in $(pgrep -x mds 2>/dev/null) $(pgrep -x mds_stores 2>/dev/null); do ps -o pid=,time=,comm= -p "$p" 2>/dev/null; done
  } > "$f"
  echo "   recorded $f"
}
has_capture() { compgen -G "$OUT/*-$1-$2-*.txt" >/dev/null; }

# ── 1. OP-1 precondition: Spotlight Privacy entry ──────────────────────────────────────────────
echo "== 1. OP-1 precondition — Spotlight Privacy entry for $DEV (DESIGN X1, F §2.2-2.3)"
echo "   mdutil -s /System/Volumes/Data: $(mdutil -s /System/Volumes/Data 2>&1 | tr '\n' ' ' | sed 's/  */ /g')"
echo "   the entry itself is root-only to read; --confirm spotlight-privacy reads it, adds it if absent"
if [ "$do_spot" = 1 ]; then
  spot_step() {
    outdir || return
    if excluded; then echo "   already excluded: $DEV"; return; fi
    local bak; bak="$OUT/$(stamp)-VolumeConfiguration.plist.bak"
    "$SUDO" cp "$SPOT_PLIST" "$bak" || { refuse "could not back up $SPOT_PLIST"; return; }
    echo "   backed up to $bak"
    "$SUDO" "$PB" -c "Add :Exclusions: string $DEV" "$SPOT_PLIST" || { refuse "PlistBuddy Add failed"; return; }
    excluded || { refuse "the entry does not read back — use System Settings → Spotlight → Search Privacy"; return; }
    echo "   VERIFIED: $DEV is in Exclusions"
  }
  spot_step
fi

# ── 2. OP-1 / X1: fseventsd ────────────────────────────────────────────────────────────────────
echo "== 2. OP-1 / X1 — fseventsd (restarted by another actor ~10:00Z 2026-10-17: 14 MB, was 12-13 GB)"
pid="$(fsev_pid)"; mb="$(fsev_mb "$pid")"
echo "   pid ${pid:-none}, footprint ${mb:-?} MB (wedged >= $FOOT_WEDGED_MB MB; healthy < 100 MB)"
if [ "$do_fsev" = 1 ]; then
  fsev_step() {
    outdir || return
    [ -n "$pid" ] || { refuse "no fseventsd process"; return; }
    case "$mb" in ''|*[!0-9]*) refuse "footprint unreadable — nothing to judge a restart by"; return ;; esac
    [ "$mb" -ge "$FOOT_WEDGED_MB" ] || { refuse "footprint $mb MB is not wedged; a restart repairs nothing and forces every FSEvents client to rescan"; return; }
    excluded || { refuse "$DEV is not in Spotlight Exclusions — run --confirm spotlight-privacy first (mds would rescan 49M inodes)"; return; }
    mds_record
    "$SUDO" sample "$pid" 5 -file "$OUT/$(stamp)-fseventsd-sample.txt" >/dev/null 2>&1 || echo "   (sample failed; continuing)"
    "$SUDO" kill -TERM "$pid" || { refuse "kill -TERM $pid failed"; return; }
    local i=0
    # ps, not `kill -0`: an unprivileged kill -0 on a root daemon fails EPERM and reads as "gone".
    while [ "$i" -lt "$WAIT_S" ] && alive "$pid"; do i=$((i + 1)); sleep 1; done
    if alive "$pid" && [ "$(fsev_pid)" = "$pid" ]; then
      echo "   still alive after ${WAIT_S} s: KILL"; "$SUDO" kill -KILL "$pid" || true
    fi
    local new="" j=0
    while [ "$j" -lt 30 ]; do new="$(fsev_pid)"; [ -n "$new" ] && [ "$new" != "$pid" ] && break; j=$((j + 1)); sleep 1; done
    [ -n "$new" ] && [ "$new" != "$pid" ] || { refuse "no new fseventsd pid after 30 s (fallback: sudo launchctl kickstart -k system/com.apple.fseventsd)"; return; }
    echo "   VERIFIED: fseventsd $pid → $new. Now: re-run with --confirm mds-record at +10 min and +1 h"
  }
  fsev_step
fi
if [ "$do_mds" = 1 ]; then outdir && mds_record; fi

# ── 3. OP-2 / X24: one-time cleanups ───────────────────────────────────────────────────────────
echo "== 3. OP-2 / X24 — one-time cleanups"
xdir="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)"
xdb="${xdir}xcrun_db"
XCRUN_DONE="$OUT/xcrun-cache.cleaned"   # xcrun rebuilds its db on the next call, so absence is no record
old_tmp() { [ -n "$xdir" ] && find "$xdir" -maxdepth 1 -name 'xcrun_db-*' -type f -mmin +60 2>/dev/null; }
if [ -n "$xdir" ]; then
  echo "   xcrun_db: $(stat -f %z "$xdb" 2>/dev/null || echo absent) bytes; xcrun_db-* older than 60 min: $(old_tmp | wc -l | tr -d ' ')"
else
  echo "   xcrun_db: DARWIN_USER_TEMP_DIR unreadable"
fi
if [ "$do_xcrun" = 1 ]; then
  xcrun_step() {
    [ -n "$xdir" ] || { refuse "DARWIN_USER_TEMP_DIR unreadable"; return; }
    xcrun --kill-cache || { refuse "xcrun --kill-cache failed"; return; }
    sleep 3
    local f n=0
    while IFS= read -r f; do [ -n "$f" ] && rm -f -- "$f" && n=$((n + 1)); done < <(old_tmp)
    echo "   removed $n stale xcrun_db-* files"
    [ -e "$xdb" ] && { refuse "xcrun_db is back after 3 s ($(stat -f %z "$xdb") bytes): a concurrent rename restored it; re-run when no gate is running"; return; }
    outdir && date -u +%FT%TZ > "$XCRUN_DONE"
    echo "   VERIFIED: xcrun_db absent 3 s after --kill-cache (recorded $XCRUN_DONE)"
  }
  xcrun_step
fi
echo "   X24 orphans, by kind (the decision is yours; this script signals none of them):"
for kind in 'render\.mjs' 'zfav'; do
  rows="$(pgrep -fl "$kind" 2>/dev/null)"
  echo "     $kind: ${rows:-none running}"
done
echo "   stale session named at filing (skip if gone; check inFlight.queued first):"
echo "     CLAUDE_CONFIG_DIR=~/.claude-next claude stop 9aa483e9"
if [ -e "$HOME/.claude/autonomy/pending-activation/48-coreaudiod-watchdog-install.sh.done" ]; then
  echo "   coreaudiod: the 48-coreaudiod-watchdog daemon is installed (.done) and owns the restart"
else
  echo "   coreaudiod: owned by 48-coreaudiod-watchdog-install.sh (not marked done) — run that, not a bare killall"
fi

# ── 4. OP-2b / OP-2c: wired-memory split and fs_usage capture ──────────────────────────────────
gates="$(gate_count)"
echo "== 4. OP-2b wired split / OP-2c fs_usage — test gates running now: $gates"
for w in peak idle; do
  echo "   $w: wired $(has_capture "$w" wired && echo captured || echo pending) · fs_usage $(has_capture "$w" fsusage && echo captured || echo pending)"
done
window_ok() {   # <step> — refuse a window the box is not in, or one already captured
  case "$window" in
    peak) [ "$gates" -ge 2 ] || { refuse "$1 --window peak needs >= 2 gates running (have $gates)"; return 1; } ;;
    idle) [ "$gates" -eq 0 ] || { refuse "$1 --window idle needs no gate running (have $gates)"; return 1; } ;;
  esac
  ! has_capture "$window" "$1" || { refuse "$1 $window is already captured in $OUT"; return 1; }
  outdir
}
census() { echo "# $(date -u +%FT%TZ) window=$window gates=$gates"; pgrep -fl 'pytest|bin/bats|libexec/bats' 2>/dev/null; }
iostats() { ioreg -c IOBlockStorageDriver -r -w 0 2>/dev/null | grep -i '"Statistics"'; }
if [ "$do_wired" = 1 ] && window_ok wired; then
  p="$OUT/$(stamp)-$window-wired"
  census > "$p-census.txt"
  "$SUDO" zprint -t -s 2>&1 | head -40 > "$p-zprint-top.txt"
  "$SUDO" zprint > "$p-zprint.txt" 2>&1
  { vm_stat; top -l 1 -n 0; ioreg -r -c AGXAccelerator -d 1; } > "$p-vm.txt" 2>&1
  if [ -s "$p-zprint.txt" ]; then echo "   captured $p-*.txt"; else refuse "zprint wrote nothing ($p-zprint.txt)"; fi
fi
if [ "$do_fsu" = 1 ] && window_ok fsusage; then
  p="$OUT/$(stamp)-$window-fsusage"
  census > "$p-census.txt"
  iostats > "$p-iokit-before.txt"
  "$SUDO" fs_usage -w -f filesys -t 10 > "$p-A-filesys.txt" 2>&1
  "$SUDO" fs_usage -w -f diskio -t 20 > "$p-B-diskio.txt" 2>&1
  iostats > "$p-iokit-after.txt"
  if [ -s "$p-A-filesys.txt" ] && [ -s "$p-B-diskio.txt" ]; then echo "   captured $p-*.txt"
  else refuse "fs_usage wrote nothing ($p-A-filesys.txt / $p-B-diskio.txt)"; fi
  cmp -s "$p-iokit-before.txt" "$p-iokit-after.txt" && echo "   ⚠ IOKit Statistics did not move: the positive control saw no I/O"
fi

# ── 5. OP-4 / X23 (W6, conditional) ────────────────────────────────────────────────────────────
echo "== 5. OP-4 / X23 — kern.maxvnodes now $(sysctl -n kern.maxvnodes 2>/dev/null || echo '?'); NOT run here"
echo "   only after the re-measurement (backlog 75b041426dba) rules for it: sudo sysctl -w kern.maxvnodes=524288"

# ── 6. The program's other operator steps (filed; this script runs none of them) ───────────────
cat <<'EOF'
== 6. Other operator steps of this program — each is its own row or script
   52-load-2026-10-17-activate.sh   capacity-attrib, worktree-gc-events, load rung, archive floor (W3)
   migration 0066-hook-if-filters --confirm settings.json   (W4, WP-28)
   migration 0067-ms365-shared                               (W1-CI, backlog 62694f2b1ffb)
   0057 root re-install (backlog f433e92713c8) · OP-3 native pandoc + uv.toml (2c1acaa94c3b)
   OP-5 worktree-gc-repos.promoted, by hand after 7 d of observe logs · OP-6 lane briefs → docs/lanes/COMMON.md (dfc2d3f79629)
   3 orphaned W2 teammate pids (678ee1ea5f12)
EOF

# Marked done only when every W0 step reads complete from disk: fseventsd healthy now, the xcrun
# cleanup recorded, and all four captures present. Read here, not from this run's flags.
mb_now="$(fsev_mb "$(fsev_pid)")"
if case "$mb_now" in ''|*[!0-9]*) false ;; *) [ "$mb_now" -lt 100 ] ;; esac \
   && [ -f "$XCRUN_DONE" ] \
   && has_capture peak wired && has_capture idle wired && has_capture peak fsusage && has_capture idle fsusage; then
  mkdir -p "$(dirname "$DONE")" && touch "$DONE" && echo "== W0 complete: marked $DONE"
fi
exit "$failed"
