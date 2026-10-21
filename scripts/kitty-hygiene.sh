#!/bin/bash
# kitty-hygiene.sh — READ-ONLY kitty hygiene for limit-recover (REPORT B8; design and both reviews:
# docs/research/lr-sustained-load-2026-10-20/impl/B8-kitty-hygiene.md; plan LR_SUSTAINED_LOAD_IMPL W7).
# It never writes a setting, never signals, launches, hides or upgrades kitty (tests/kitty-hygiene.bats
# pins that with a source lint and argv-logging stubs). Its only signals go to the bounded child it
# forked itself (_kh_to) and `kill -0` liveness reads.
#
#   kitty-hygiene.sh status [--pid P] [--only f1,f2,…]   exit 0 OK · 1 WARN · 2 usage
#   kitty-hygiene.sh naps   [--pid P] [--since 'Y-m-d H:M:S'] [--timeout S] [--max-slices N] [--json]
#                                                         exit 0 NO-ADAPTER · 1 NAPPING/ENROLLED · 2 usage · 3 UNKNOWN
#   kitty-hygiene.sh sample [--pid P] [--every S] [--count N] [--out F] [--rc SOCK [--rc-production]]
#
# status: one key=value line per check, then verdict=OK or verdict=WARN(<fields>). Fields for --only:
#   key      NSAppSleepDisabled for net.kovidgoyal.kitty: on | off | absent | ?  (WARN unless on)
#   adopted  yes | pending | ? | n/a — kitty's start against the key's write time (the plist mtime). A
#            necessary condition only: the O4 hide challenge below is the proof.
#   band     <base>/<main thread> — lr_recon/band.py and `ps -M` row 2 (WARN base < 31, or ?)
#   fds      fds=<numeric fds>/<soft> fds_all=<every lsof row: cc-restore's fd_gate metric>
#            fds_unix=<unix sockets: the abandoned-peer indicator> (WARN numeric >= CC_KH_FD_WARN 180;
#            WARN restore-fd-gate when fds_all > CC_RESTORE_FD_MAX 180: a second restore round STOPS)
#   zombies  <n> (WARN > 0 below 0.49.0, kitty#10436)
#   version  version=… team=… signature=… fixes=signal:y/n listener:y/n — version=? (WARN) when the
#            bundle on disk is newer than the running process, or the process is not the bundle
#   main     main_kitties=<n> plus main=<pid> ppid=<ppid> parent=<its command> per main kitty
#            (WARN n != 1: cc-restore --restart-kitty refuses; the parent names who runs a dev kitty)
#   probe    probe=<pid> group=<g> per --instance-group kitty (WARN: cc-restore's `open -a` would
#            ACTIVATE that probe instead of launching a kitty, and the fleet would come back to nothing)
#   load     load1=<x> ncpu=<n> (every live reading carries the load beside it)
# Every read is bounded (the repo's timeout resolver, with -k); any rc != 0 prints ? and makes the
# verdict WARN(unknown:<field>), never OK. Per-pid fields are skipped (n/a) when there is not exactly
# one main kitty and no --pid. `--only key,main,probe` is the cheap form: one defaults read, one ps.
#
# naps: RunningBoard's record of the pid, from --since (default: the process start; an earlier one is
# refused, because a reused pid would count another process's lines) to now, in slices of at most
# 20 min, each under its own bound (--timeout, default 240 s), at most --max-slices (36). See
# scripts/lib/kitty-naps.py for the verdicts. Run it from a priority-31 shell (a kitty pane). Never
# inside cc-restore (refused when CC_KH_CALLER=cc-restore).
#
# sample: one TSV row per interval — ts pid load1 locked front band main_thr threads_at_4 rc_rc rtt_ms
# fds fds_unix. Run it in a kitty pane, never detached from a tool call. Remote control is OFF by
# default; --rc SOCK turns it on, and a main (production) kitty also needs --rc-production. Each
# unanswered call costs kitty an fd until its main thread answers (prune_peers), so after the first
# rc != 0 the sampler stops calling until the band reads >= 31 again, backing off (doubling, to
# 1800 s), and stops for good after 10 unanswered calls. rc_rc 124 means our 12 s bound fired: UNKNOWN,
# never "deaf"; "-" means no call was made.
#
# OPERATOR SCRIPT (B8; run each block in a kitty pane; none of it touches the live windows until O4).
#  O0 baseline:   bash ~/.claude/scripts/kitty-hygiene.sh status
#  O1 control arm (no key yet; must come out RED, else the A/B has no power):
#     mkdir -p /tmp/b8probe && open -n -a /Applications/kitty.app --args --config NONE \
#       --instance-group b8-ctl --listen-on unix:/tmp/b8probe/ctl.sock -o allow_remote_control=socket-only
#     sleep 5; P=$(pgrep -f 'instance-group b8-ctl' | head -1); echo "probe pid=$P"
#     # hide the PROBE by pid, never by keyboard focus (a missed click hides the production kitty):
#     osascript -e "tell application \"System Events\" to set visible of (first process whose unix id is $P) to false"
#     bash ~/.claude/scripts/kitty-hygiene.sh sample --pid "$P" --every 30 --count 6 --rc unix:/tmp/b8probe/ctl.sock --out /tmp/b8-ctl.tsv
#     bash ~/.claude/scripts/kitty-hygiene.sh naps --pid "$P"
#     expect: band 4 within ~90 s; naps=NAPPING or ENROLLED. rc_rc 124 is UNKNOWN, not a verdict.
#  O2 write the key:   defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES
#     Live adoption (Q1): re-hide the O1 control probe (it started before the key), never the main kitty.
#  O2b fd headroom, in place (until kitty 0.50.0): on the probe first, then the main kitty:
#     kitten @ --to unix:/tmp/b8probe/ctl.sock kitten ~/.claude/scripts/lib/kitty-fd-headroom.py set
#     kitten @ --to unix:/tmp/b8probe/ctl.sock kitten ~/.claude/scripts/lib/kitty-fd-headroom.py get
#     then the same two with --to unix:/tmp/kitty-<main pid>; expect fd_headroom=… soft=8192.
#  O3 treatment arm: O1 again with b8-trt / trt.sock; expect band >= 31 throughout, naps=NO-ADAPTER.
#     O1, O3 and O3b END with: kill "$P"; pgrep -f 'instance-group b8-'   # must print nothing
#  O3b (optional) display-off: run a keyless control probe AND the keyed probe concurrently, both
#     hidden, plus `sample --pid <main>` (no RC); readings are "consistent with", not a cause.
#  O4 at the next kitty start. Before a planned restart: the key reads 1; exactly one main kitty
#     (status main_kitties=1); `pgrep -f 'instance-group b8-'` prints nothing; no ship-land.sh in
#     flight; `cc-lr status` shows no record mid-actuation; every unsent draft is lost (cc-restore
#     captures none). Optional upgrade LAST: on the reboot path only after alarm-reboot-prep.sh has
#     saved the drafts and the heartbeat; after it, `kitten @ ls` and a `get-text` parse against the
#     new kitty, else `bash ~/.claude/scripts/kitty-build-swap.sh rollback --confirm /Applications/kitty.app`.
#     Restart without the per-round load gate:
#       CC_RESTORE_GATE_MAX_S=0 ~/.claude/bin/cc-restore --restart-kitty --confirm <main kitty pid>
#     Post-start check (challenge-based): ⌘H the NEW kitty for 90 s, then
#       bash ~/.claude/scripts/kitty-hygiene.sh status      # band >= 31, adopted=yes
#       bash ~/.claude/scripts/kitty-hygiene.sh naps        # NO-ADAPTER (default --since = its start)
#  O5 the nights after: `sample --pid <main>` (no RC) overnight; a night counts only when every locked
#     or non-focal row with a band reading reads >= 31 and load1 >= 15/core; too many ? rows: run again.
#
# Kill switch: CC_KITTY_HYGIENE=off (status prints verdict=OFF, exit 0; alarm-reboot-prep prints
# nothing). For cc-restore, point CC_RESTORE_HYGIENE_BIN at /usr/bin/true.
# Seams (tests): CC_KH_{DEFAULTS,PS,LSOF,LOG,CODESIGN,PLISTBUDDY,SYSCTL,IOREG,LSAPPINFO,KITTEN,STAT}_BIN,
#   CC_KH_PYTHON, CC_KH_BAND_PY, CC_KH_NAPS_PY, CC_KH_PLIST, CC_KITTY_APP, CC_KH_TIMEOUT_BIN,
#   CC_KH_FD_SOFT (256), CC_KH_FD_WARN (180), CC_RESTORE_FD_MAX (180), CC_KH_{PS,LSOF,DEFAULTS,BAND}_TIMEOUT_S.
set -u

DOMAIN=net.kovidgoyal.kitty
_src="${BASH_SOURCE[0]}"
_lnk="$(readlink "$_src" 2>/dev/null || true)"
case "$_lnk" in '') ;; /*) _src="$_lnk" ;; *) _src="$(dirname "$_src")/$_lnk" ;; esac
HERE="$(cd "$(dirname "$_src")" && pwd)"

DEFAULTS="${CC_KH_DEFAULTS_BIN:-/usr/bin/defaults}"; PS="${CC_KH_PS_BIN:-/bin/ps}"
LSOF="${CC_KH_LSOF_BIN:-/usr/sbin/lsof}"; LOGB="${CC_KH_LOG_BIN:-/usr/bin/log}"
CODESIGN="${CC_KH_CODESIGN_BIN:-/usr/bin/codesign}"; PBUDDY="${CC_KH_PLISTBUDDY_BIN:-/usr/libexec/PlistBuddy}"
SYSCTL="${CC_KH_SYSCTL_BIN:-/usr/sbin/sysctl}"; IOREG="${CC_KH_IOREG_BIN:-/usr/sbin/ioreg}"
LSAPPINFO="${CC_KH_LSAPPINFO_BIN:-/usr/bin/lsappinfo}"; STATB="${CC_KH_STAT_BIN:-/usr/bin/stat}"
PY="${CC_KH_PYTHON:-/usr/bin/python3}"
BAND="${CC_KH_BAND_PY:-$HERE/limit-recover/lr_recon/band.py}"; NAPS="${CC_KH_NAPS_PY:-$HERE/lib/kitty-naps.py}"
PLIST="${CC_KH_PLIST:-$HOME/Library/Preferences/$DOMAIN.plist}"; APP="${CC_KITTY_APP:-/Applications/kitty.app}"
KITTEN="${CC_KH_KITTEN_BIN:-$APP/Contents/MacOS/kitten}"
FD_SOFT="${CC_KH_FD_SOFT:-256}"; FD_WARN="${CC_KH_FD_WARN:-180}"; FD_GATE="${CC_RESTORE_FD_MAX:-180}"
PS_T="${CC_KH_PS_TIMEOUT_S:-10}"; LSOF_T="${CC_KH_LSOF_TIMEOUT_S:-30}"; DEF_T="${CC_KH_DEFAULTS_TIMEOUT_S:-10}"; BAND_T="${CC_KH_BAND_TIMEOUT_S:-10}"

usage() { sed -n '2,/^set -u$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

# BEGIN own-child bound — the only place this file sends a signal other than `kill -0`: to the
# process group of the child it forked itself, when that child outlives its bound.
# _kh_to <secs> <cmd…> — the repo's resolver (restore-heartbeat.sh _hb_to), with -k: rc 124 on the
# bound, 137 when the child ignored TERM. Stock macOS has no timeout(1); then a perl alarm.
_kh_to() {
  local t="$1" tb; shift
  tb="${CC_KH_TIMEOUT_BIN-$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null \
      || { [ -x /opt/homebrew/bin/timeout ] && printf '%s' /opt/homebrew/bin/timeout; })}"
  if [ -n "$tb" ]; then "$tb" -k 2 "$t" "$@"; return $?; fi
  /usr/bin/perl -e 'my $t = shift; my $pid = fork; exit 125 unless defined $pid;
    if ($pid == 0) { setpgrp(0, 0); exec { $ARGV[0] } @ARGV; exit 127 }
    $SIG{ALRM} = sub { kill "TERM", -$pid; select(undef, undef, undef, 2); kill "KILL", -$pid; exit 124 };
    alarm $t; waitpid($pid, 0); exit(($? & 127) ? 128 + ($? & 127) : $? >> 8)' "$t" "$@"
}
# END own-child bound

warn=""
addw() { case ",$warn," in *",$1,"*) ;; *) warn="${warn:+$warn,}$1" ;; esac; }
alive() { kill -0 "$1" 2>/dev/null; }

# census → CENSUS lines: "main <pid> <ppid> <lstart_with_underscores> <exe>" / "probe <pid> <ppid> <group>",
# plus "parent <ppid> <its exe>" for each main kitty's parent. The bin/cc-restore:137-152 rule: a
# process whose executable is named kitty, not a `kitty +kitten …` helper, without --instance-group.
CENSUS="" CENSUS_RC=0
census() {
  local out
  out="$(_kh_to "$PS_T" /usr/bin/env TZ=UTC LC_ALL=C "$PS" -axo pid=,ppid=,lstart=,args= 2>/dev/null)"; CENSUS_RC=$?
  [ "$CENSUS_RC" = 0 ] || { CENSUS=""; return 1; }
  CENSUS="$(printf '%s\n' "$out" | awk '
    { exe[$1] = $8 }
    { n = split($8, a, "/"); if (a[n] != "kitty") next
      if ($9 ~ /^\+/) next
      g = ""
      for (i = 9; i <= NF; i++) {
        if ($i == "--instance-group") { g = $(i + 1); break }
        if ($i ~ /^--instance-group=/) { g = substr($i, 18); break }
      }
      if (g != "") { probes[++np] = "probe " $1 " " $2 " " g; next }
      mains[++nm] = "main " $1 " " $2 " " $3 "_" $4 "_" $5 "_" $6 "_" $7 " " $8; par[nm] = $2 }
    END { for (i = 1; i <= nm; i++) { print mains[i]; print "parent " par[i] " " (par[i] in exe ? exe[par[i]] : "?") }
          for (i = 1; i <= np; i++) print probes[i] }')"
}
mains() { printf '%s\n' "$CENSUS" | awk '$1 == "main" { print $2 }'; }

start_epoch() { # <pid> → epoch of its start (UTC parse of a UTC lstart), or empty
  local ls
  ls="$(_kh_to "$PS_T" /usr/bin/env TZ=UTC LC_ALL=C "$PS" -p "$1" -o lstart= 2>/dev/null)" || return 0
  ls="$(printf '%s' "$ls" | tr -s ' ' | sed 's/^ //;s/ $//')"
  [ -n "$ls" ] && TZ=UTC LC_ALL=C /bin/date -j -f '%a %b %d %T %Y' "$ls" +%s 2>/dev/null
  return 0
}
mtime() { "$STATB" -f %m "$1" 2>/dev/null; }

key_state() {
  local out rc
  out="$(_kh_to "$DEF_T" "$DEFAULTS" read "$DOMAIN" NSAppSleepDisabled 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then
    case "$out" in 1) echo on ;; 0) echo off ;; *) echo '?' ;; esac; return
  fi
  # defaults itself exits 1 and SAYS so for an absent key; a timeout, a cfprefsd error or a missing
  # binary says nothing of the kind, and is unknown, never "absent" or "on".
  case "$rc:$out" in 1:*"does not exist"*) echo absent ;; *) echo '?' ;; esac
}

ver_ge() { # <a> <b> → 0 when version a >= b
  awk -v a="$1" -v b="$2" 'BEGIN { na = split(a, x, "."); nb = split(b, y, ".")
    for (i = 1; i <= 3; i++) { p = (i <= na ? x[i] + 0 : 0); q = (i <= nb ? y[i] + 0 : 0)
      if (p > q) exit 0; if (p < q) exit 1 } exit 0 }'
}

lsof_rows() { # <pid> [-a -d 0-65535] → lsof output minus its header; rc != 0 ⇒ fails
  local out
  out="$(_kh_to "$LSOF_T" "$LSOF" -n -P -p "$@" 2>/dev/null)" || return 1
  printf '%s\n' "$out" | awk 'NR > 1 && NF'
}

want() { case ",$ONLY," in ",,"|*",$1,"*) return 0 ;; *) return 1 ;; esac; }

cmd_status() {
  local pid="" ONLY="" k
  while [ $# -gt 0 ]; do
    case "$1" in
      --pid) pid="${2:-}"; shift ;;
      --only) ONLY="${2:-}"; shift ;;
      *) echo "kitty-hygiene: status: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
  done
  case "$pid" in ''|*[!0-9]*) [ -z "$pid" ] || { echo "kitty-hygiene: --pid takes a number" >&2; exit 2; } ;; esac
  for k in $(printf '%s' "$ONLY" | tr ',' ' '); do
    case "$k" in key|adopted|band|fds|zombies|version|main|probe|load) ;;
      *) echo "kitty-hygiene: --only: unknown field '$k'" >&2; exit 2 ;; esac
  done
  if [ "${CC_KITTY_HYGIENE:-on}" = off ]; then echo "verdict=OFF (CC_KITTY_HYGIENE=off)"; exit 0; fi

  local key="" nmain="" st=""
  if want key || want adopted; then
    key="$(key_state)"
    if want key; then
      echo "key=$key"
      case "$key" in on) ;; '?') addw unknown:key ;; *) addw key ;; esac
    fi
  fi
  if want main || want probe || [ -z "$pid" ]; then
    census
  fi
  if want main; then
    if [ "$CENSUS_RC" != 0 ]; then echo "main_kitties=? (ps rc $CENSUS_RC)"; addw unknown:main
    else
      nmain="$(mains | grep -c .)"
      echo "main_kitties=$nmain$([ "$nmain" = 1 ] || echo " (cc-restore --restart-kitty will refuse: it needs exactly one)")"
      printf '%s\n' "$CENSUS" | awk '
        $1 == "parent" { par[$2] = $3 }
        $1 == "main" { m[++n] = $0 }
        END { for (i = 1; i <= n; i++) { split(m[i], f, " "); gsub("_", " ", f[4])
                print "main=" f[2] " ppid=" f[3] " parent=" (f[3] in par ? par[f[3]] : "?") " started=" f[4] "Z exe=" f[5] } }'
      [ "$nmain" = 1 ] || addw main
    fi
  fi
  if want probe && [ "$CENSUS_RC" = 0 ]; then
    if printf '%s\n' "$CENSUS" | grep -q '^probe '; then
      printf '%s\n' "$CENSUS" | awk '$1 == "probe" { print "probe=" $2 " group=" $4 " ppid=" $3 " (cc-restore'"'"'s open -a would activate this probe instead of launching a kitty)" }'
      addw probe
    fi
  fi
  if [ -z "$pid" ] && [ "$CENSUS_RC" = 0 ] && [ "$(mains | grep -c .)" = 1 ]; then pid="$(mains)"; fi

  if want load; then
    local l1 nc
    l1="$(_kh_to 5 "$SYSCTL" -n vm.loadavg 2>/dev/null | awk '{ print $2 }')"
    nc="$(_kh_to 5 "$SYSCTL" -n hw.ncpu 2>/dev/null)"
    echo "load1=${l1:-?} ncpu=${nc:-?}"
  fi

  if [ -z "$pid" ]; then
    for k in adopted band fds zombies version; do
      want "$k" && [ -n "$ONLY" ] && echo "$k=n/a (no single main kitty; pass --pid)"
    done
    [ -n "$ONLY" ] || echo "per-pid checks: n/a (no single main kitty; pass --pid)"
    [ -n "$warn" ] || addw main
    echo "verdict=WARN($warn)"; exit 1
  fi
  if ! alive "$pid"; then
    echo "pid=$pid not running"; addw unknown:pid
    echo "verdict=WARN($warn)"; exit 1
  fi
  if want adopted || want version; then st="$(start_epoch "$pid")"; fi

  if want adopted; then
    local mt
    case "$key" in
      on)
        mt="$(mtime "$PLIST")"
        if [ -z "$st" ] || [ -z "$mt" ]; then echo "adopted=? (start ${st:-unreadable}, key written ${mt:-unreadable})"; addw unknown:adopted
        elif [ "$st" -gt "$mt" ]; then echo "adopted=yes (kitty $pid started after the key was written)"
        else echo "adopted=pending (kitty $pid started before the key; it takes effect at the next kitty start)"; addw adopted; fi ;;
      '?') echo "adopted=? (key unreadable)"; addw unknown:adopted ;;
      *) echo "adopted=n/a (key $key)" ;;
    esac
  fi

  if want band; then
    local base thr
    base="$(_kh_to "$BAND_T" "$PY" -I "$BAND" "$pid" 2>/dev/null)" || base='?'
    case "$base" in ''|*[!0-9]*) base='?' ;; esac
    thr="$(_kh_to "$PS_T" /usr/bin/env LC_ALL=C "$PS" -M -p "$pid" 2>/dev/null | awk 'NR == 2 { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+[A-Z]?$/ && $(i-1) ~ /^[A-Z+<]+$/) { print $i; exit } }')"
    echo "band=$base/${thr:-?}"
    if [ "$base" = '?' ]; then addw unknown:band; elif [ "$base" -lt 31 ]; then addw napped-now; fi
  fi

  if want fds; then
    local num all ux rows
    if rows="$(lsof_rows "$pid" -a -d 0-65535)"; then
      num="$(printf '%s\n' "$rows" | grep -c .)"; ux="$(printf '%s\n' "$rows" | awk '$5 == "unix"' | grep -c .)"
    else num='?' ux='?'; fi
    if rows="$(lsof_rows "$pid")"; then all="$(printf '%s\n' "$rows" | grep -c .)"; else all='?'; fi
    echo "fds=$num/$FD_SOFT fds_all=$all fds_unix=$ux"
    if [ "$num" = '?' ] || [ "$all" = '?' ]; then addw unknown:fds; fi
    [ "$num" != '?' ] && [ "$num" -ge "$FD_WARN" ] && addw fds
    if [ "$all" != '?' ] && [ "$all" -gt "$FD_GATE" ]; then
      echo "restore-fd-gate: fds_all $all > CC_RESTORE_FD_MAX $FD_GATE — a second cc-restore round would STOP (S9)"
      addw restore-fd-gate
    fi
  fi

  local ver="" exe vok=1
  if want version || want zombies; then
    exe="$(printf '%s\n' "$CENSUS" | awk -v p="$pid" '$1 == "main" && $2 == p { print $5 }')"
    ver="$(_kh_to 10 "$PBUDDY" -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)" || ver=""
    local bm bm2
    bm="$(mtime "$APP/Contents/Info.plist")"; bm2="$(mtime "$APP/Contents/MacOS/kitty")"
    [ -n "$bm2" ] && { [ -z "$bm" ] || [ "$bm2" -gt "$bm" ]; } && bm="$bm2"
    if [ -z "$ver" ]; then vok=0
    elif [ -n "$exe" ] && [ "$exe" != "$APP/Contents/MacOS/kitty" ]; then vok=0
    elif [ -z "$st" ] || [ -z "$bm" ] || [ "$bm" -gt "$st" ]; then vok=0; fi
  fi
  if want version; then
    local cs team sig
    cs="$(_kh_to 20 "$CODESIGN" -dv "$APP" 2>&1)" || cs=""
    team="$(printf '%s\n' "$cs" | sed -n 's/^TeamIdentifier=//p' | head -1)"
    case "$cs" in *"Signature=adhoc"*) sig=adhoc ;; *"Signature size="*) sig=developer ;; *) sig='?' ;; esac
    if [ "$vok" = 1 ]; then
      echo "version=$ver team=${team:-?} signature=$sig fixes=signal:$(ver_ge "$ver" 0.49.0 && echo y || echo n) listener:$(ver_ge "$ver" 0.50.0 && echo y || echo n)"
    else
      echo "version=? (bundle ${ver:-unreadable}; kitty $pid runs ${exe:-?}, started ${st:-?}, bundle written ${bm:-?}) team=${team:-?} signature=$sig fixes=signal:? listener:?"
      addw version
    fi
    [ "$sig" = adhoc ] && addw adhoc
    [ "$sig" = '?' ] && addw unknown:signature
  fi

  if want zombies; then
    local z
    if z="$(_kh_to "$PS_T" /usr/bin/env LC_ALL=C "$PS" -axo ppid=,stat= 2>/dev/null)"; then
      z="$(printf '%s\n' "$z" | awk -v k="$pid" '$1 == k && $2 ~ /^Z/' | grep -c .)"
      echo "zombies=$z"
      if [ "$z" -gt 0 ] && { [ "$vok" = 0 ] || ! ver_ge "$ver" 0.49.0; }; then addw signals; fi
    else echo "zombies=?"; addw unknown:zombies; fi
  fi

  if [ -z "$warn" ]; then echo "verdict=OK"; exit 0; fi
  echo "verdict=WARN($warn)"; exit 1
}

cmd_naps() {
  local pid="" since="" to=240 cap=36 js=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --pid) pid="${2:-}"; shift ;;
      --since) since="${2:-}"; shift ;;
      --timeout) to="${2:-}"; shift ;;
      --max-slices) cap="${2:-}"; shift ;;
      --json) js=--json ;;
      *) echo "kitty-hygiene: naps: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
  done
  if [ "${CC_KH_CALLER:-}" = cc-restore ]; then
    echo "kitty-hygiene: naps is never run inside cc-restore (minutes of log show on the restore's path)" >&2; exit 2
  fi
  case "$to$cap" in *[!0-9]*|'') echo "kitty-hygiene: --timeout and --max-slices take numbers" >&2; exit 2 ;; esac
  if [ -z "$pid" ]; then
    census || { echo "naps=UNKNOWN (ps rc $CENSUS_RC: no main kitty census)"; exit 3; }
    [ "$(mains | grep -c .)" = 1 ] || { echo "kitty-hygiene: naps: $(mains | grep -c .) main kitties — pass --pid" >&2; exit 2; }
    pid="$(mains)"
  fi
  case "$pid" in *[!0-9]*) echo "kitty-hygiene: --pid takes a number" >&2; exit 2 ;; esac
  local st se
  st="$(start_epoch "$pid")"
  [ -n "$st" ] || { echo "naps=UNKNOWN (cannot read the start of pid $pid)"; exit 3; }
  if [ -z "$since" ]; then se="$st"
  else
    se="$(LC_ALL=C /bin/date -j -f '%Y-%m-%d %H:%M:%S' "$since" +%s 2>/dev/null)" \
      || { echo "kitty-hygiene: --since must read 'Y-m-d H:M:S' (local time)" >&2; exit 2; }
    if [ "$se" -lt "$st" ]; then
      echo "kitty-hygiene: --since $since is before kitty $pid started ($(/bin/date -r "$st" '+%Y-%m-%d %H:%M:%S')): refused — a reused pid would count another process's lines" >&2
      exit 2
    fi
  fi
  "$PY" -I "$NAPS" scan --pid "$pid" --since-epoch "$se" --slice-timeout "$to" --max-slices "$cap" --log "$LOGB" $js
  exit $?
}

ms() { /usr/bin/perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }

cmd_sample() {
  local pid="" every=60 count=0 out="" sock="" prod=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --pid) pid="${2:-}"; shift ;;
      --every) every="${2:-}"; shift ;;
      --count) count="${2:-}"; shift ;;
      --out) out="${2:-}"; shift ;;
      --rc) sock="${2:-}"; shift ;;
      --rc-production) prod=1 ;;
      *) echo "kitty-hygiene: sample: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
  done
  case "$every$count" in *[!0-9]*|'') echo "kitty-hygiene: --every and --count take numbers" >&2; exit 2 ;; esac
  census || true
  if [ -z "$pid" ]; then
    [ "$(mains | grep -c .)" = 1 ] || { echo "kitty-hygiene: sample: pass --pid (not exactly one main kitty)" >&2; exit 2; }
    pid="$(mains)"
  fi
  case "$pid" in ''|*[!0-9]*) echo "kitty-hygiene: --pid takes a number" >&2; exit 2 ;; esac
  if [ -n "$sock" ] && [ "$prod" = 0 ] && mains | grep -qx "$pid"; then
    echo "kitty-hygiene: sample: $pid is a main kitty; remote control to it needs --rc-production (each unanswered call costs it an fd)" >&2
    exit 2
  fi
  out="${out:-/tmp/kh-samples-$pid.tsv}"
  [ -s "$out" ] || printf 'ts\tpid\tload1\tlocked\tfront\tband\tmain_thr\tthreads_at_4\trc_rc\trtt_ms\tfds\tfds_unix\n' > "$out"
  local i=0 unanswered=0 paused=0 backoff=$((every * 2)) next_rc=0
  while alive "$pid"; do
    local ts l1 locked front base thr n4 rc="-" rtt="-" rows fds ux now t0
    ts="$(date -u +%FT%TZ)"; now="$(date +%s)"
    l1="$(_kh_to 5 "$SYSCTL" -n vm.loadavg 2>/dev/null | awk '{ print $2 }')"
    if _kh_to 5 "$IOREG" -n Root -d1 2>/dev/null | grep -q '"CGSSessionScreenIsLocked"=Yes'; then locked=1; else locked=0; fi
    front="$(_kh_to 5 "$LSAPPINFO" info -only name "$(_kh_to 5 "$LSAPPINFO" front 2>/dev/null)" 2>/dev/null | sed -n 's/.*"LSDisplayName"="\(.*\)".*/\1/p')"
    base="$(_kh_to "$BAND_T" "$PY" -I "$BAND" "$pid" 2>/dev/null)" || base='?'
    case "$base" in ''|*[!0-9]*) base='?' ;; esac
    rows="$(_kh_to "$PS_T" /usr/bin/env LC_ALL=C "$PS" -M -p "$pid" 2>/dev/null)"
    thr="$(printf '%s\n' "$rows" | awk 'NR == 2 { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+[A-Z]?$/ && $(i-1) ~ /^[A-Z+<]+$/) { print $i; exit } }')"
    n4="$(printf '%s\n' "$rows" | awk 'NR > 1' | grep -c -E '[[:space:]]4T[[:space:]]')"
    if [ -n "$sock" ] && [ "$unanswered" -lt 10 ]; then
      # paused after an unanswered call: resume only once the band reads >= 31 AND the backoff ran out
      if [ "$paused" = 1 ] && [ "$base" != '?' ] && [ "$base" -ge 31 ] && [ "$now" -ge "$next_rc" ]; then paused=0; fi
      if [ "$paused" = 0 ]; then
        t0="$(ms)"; _kh_to 12 "$KITTEN" @ --to "$sock" ls >/dev/null 2>&1; rc=$?; rtt=$(( $(ms) - t0 ))
        if [ "$rc" != 0 ]; then
          unanswered=$((unanswered + 1)); paused=1; next_rc=$((now + backoff))
          backoff=$((backoff * 2)); [ "$backoff" -gt 1800 ] && backoff=1800
        fi
      fi
    fi
    if fds="$(lsof_rows "$pid" -a -d 0-65535)"; then
      ux="$(printf '%s\n' "$fds" | awk '$5 == "unix"' | grep -c .)"; fds="$(printf '%s\n' "$fds" | grep -c .)"
    else fds='?' ux='?'; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ts" "$pid" "${l1:-?}" "$locked" "${front:-?}" \
      "$base" "${thr:-?}" "$n4" "$rc" "$rtt" "$fds" "$ux" >> "$out"
    i=$((i + 1)); [ "$count" -gt 0 ] && [ "$i" -ge "$count" ] && break
    sleep "$every"
  done
  echo "kitty-hygiene: sample: $i row(s) → $out (unanswered rc calls: $unanswered/10)"
}

case "${1:-}" in
  status|naps|sample) c="$1"; shift; "cmd_$c" "$@" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
