# shellcheck shell=bash disable=SC2016
# ^ no #! line on purpose (never exec it by path, I1); SC2016: the perl/python/sh programs are
#   single-quoted so THEIR variables stay theirs.
# break-glass rescue kit — run ONLY as `/bin/bash rescue.sh <mode>` (never by path: a #! exec leaks
# 1 KiB of kalloc per run, DESIGN.md I1). Bash 3.2: Hammerspoon and the Rescue profile run /bin/bash.
#
# Modes:
#   capture                          mini-kit (~15 s) + detached hand-off to the forensics capture.sh
#   unpoison <pgid> <leader_lstart> [--dry-run]
#                                    the cure for a poisoned devfs node (RCA.md R17): re-verify the
#                                    exiting/orphaned pty session leader, then SIGKILL every process
#                                    group of its R3 target set (ppid descendants ∪ getsid==leader ∪
#                                    lockwatch's lstart-verified openers), openers first, leader last
#   brownout [minutes|off]           hold the admission brownout latch (default 60 min, by=operator)
#   selftest                         capture + a refused unpoison against our own throwaway tree
#
# Contract (incident 2026-10-25, DESIGN.md C5, §5): the foreground never touches /dev — stdin, stdout
# and stderr of every step are regular files in the kit, there is no `/dev/null`, no `lsof`, no `ps`
# tty column and no `ps` without -x. Every step is detached and ABANDONED at its deadline: a thread
# asleep in a devfs lookup is uninterruptible, so `alarm`+`exec` alone does not bound the caller
# (mac-forensics.md §2.4). A stuck child costs one leaked process, never the kit.
#
# unpoison exit codes (§5): 0 cured (canaries clean) · 1 signal sent, still stuck · 2 verification
# refused, NO signal sent · 4 --dry-run: verification passed, WOULD signal (no signal sent).
# The only signal this file ever sends to a pty session is `kill -KILL -- -<pgid>` (I9): never a
# session leader by pid, which is the incident's likely trigger (RCA.md §3.1).
set -u
MODE="${1:-capture}"
ROOT="${BG_ROOT:-$HOME/.claude/autonomy/break-glass}"
LW="${CC_LOCKWATCH_DIR:-$HOME/.claude/autonomy/lockwatch}"
export PATH=/usr/bin:/bin:/usr/sbin:/sbin PAGER=cat LC_ALL=C
TS="$(date +%Y%m%dT%H%M%S)"
OUT="$ROOT/kits/$TS-$MODE-$$"
mkdir -p "$OUT" || { echo "break-glass: cannot create $OUT"; exit 3; }
: > "$OUT/empty"
PROG="$OUT/progress"
ERR="$OUT/err"
T0=$(date +%s)
ABANDONED=""
log() { echo "$(date +%s) $*" >> "$PROG"; }

# The repo this file really lives in (the ~/.claude/scripts/break-glass link resolves into it), so
# lane A's canaries are found by path whether or not install.sh links their directories.
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
  _sd="$(cd "$(dirname "$_self")" && pwd)"; _self="$(readlink "$_self")"
  case "$_self" in /*) ;; *) _self="$_sd/$_self" ;; esac
done
REPO="$(cd "$(dirname "$_self")/../.." && pwd)"

# A <secs> cmd... — the house alarm wrapper; alarm survives exec, so the exec'd tool dies at <secs>
A() { local n=$1; shift; /usr/bin/perl -e 'alarm(shift); exec @ARGV or exit 127' -- "$n" "$@"; }

# bstep <name> <deadline_s> cmd... — detached, stdin from a regular file, stdout/err to the kit.
# Waits at most deadline+1 s; a child that outlives that (uninterruptible wait) is abandoned and named.
# BSTEP_NOALARM=1 drops the alarm: a pty canary is ABANDONED at its deadline, never killed, so its
# master stays open for zsh's whole life (DESIGN.md I9, §11 item 4).
bstep() {
  local name=$1 dl=$2; shift 2
  log "BEGIN $name"
  if [ -n "${BSTEP_NOALARM:-}" ]; then
    ( "$@" < "$OUT/empty" > "$OUT/$name.txt" 2>&1; echo "$?" > "$OUT/$name.rc" ) < "$OUT/empty" > "$OUT/bg.out" 2>&1 &
  else
    ( A "$dl" "$@" < "$OUT/empty" > "$OUT/$name.txt" 2>&1; echo "$?" > "$OUT/$name.rc" ) < "$OUT/empty" > "$OUT/bg.out" 2>&1 &
  fi
  local p=$!
  # ONE waiter process with a wall-clock deadline, not a fork of `sleep` per tick: at load 200 a
  # quarter-second poll loop forks ~4 times a second and its tick count stops meaning time.
  if ! /usr/bin/perl -MTime::HiRes=time,sleep -e 'my ($p, $d) = @ARGV; my $t = time + $d + 1;
        while (kill 0, $p) { exit 1 if time > $t; sleep 0.1 } exit 0' "$p" "$dl" < "$OUT/empty" 2>>"$ERR"; then
    log "ABANDON $name pid=$p"; ABANDONED="${ABANDONED}$name,"; return 1
  fi
  log "END $name rc=$(cat "$OUT/$name.rc" 2>>"$ERR")"
  return 0
}

# devprobe: the zsh/login failure, measured. Prints each /dev name BEFORE its lstat, so a hang
# leaves the stuck entry as the last, unterminated line. Never waited on beyond its deadline.
DEVPROBE='$|=1; use Time::HiRes qw(time); my $t0=time; print "OPENDIR\n";
opendir(my $d,"/dev") or do { print "OPENDIR_FAIL $!\n"; exit 2 };
printf "OPENED %.6f\n", time-$t0; my ($n,$max,$maxe)=(0,0,"");
while (defined(my $e=readdir $d)) { $n++; my $t=time; print "L $n $e ";
  my @s=lstat("/dev/$e"); my $dt=time-$t; printf "%.6f\n",$dt; if ($dt>$max){$max=$dt;$maxe=$e} }
printf "DONE n=%d total=%.3f max=%.6f maxe=%s\n",$n,time-$t0,$max,$maxe;'

PSFMT=pid,ppid,pgid,stat,pri,nice,%cpu,%mem,rss,etime,time,wq,ucomm

summary_capture() {
  local ps="$OUT/ps.txt" dp="$OUT/devprobe.txt" procs thr U E claude top dpv
  procs=$(awk 'NR>1' "$ps" 2>>"$ERR" | wc -l | tr -d ' ')
  U=$(awk 'NR>1 && $4 ~ /U/' "$ps" 2>>"$ERR" | wc -l | tr -d ' ')
  E=$(awk 'NR>1 && $4 ~ /E/' "$ps" 2>>"$ERR" | wc -l | tr -d ' ')
  claude=$(awk 'NR>1 && ($NF=="claude" || $NF=="claude.exe")' "$ps" 2>>"$ERR" | wc -l | tr -d ' ')
  thr=$(sed -n 's/^Processes: .*, \([0-9]*\) threads.*/\1/p' "$OUT/top.txt" 2>>"$ERR")
  top=$(sed -n 's/^CPU usage: \(.*\)/\1/p' "$OUT/top.txt" 2>>"$ERR" | tr -d '\n')
  if grep -q '^DONE' "$dp" 2>>"$ERR"; then dpv="devprobe OK $(sed -n 's/^DONE \(.*\)/\1/p' "$dp")"
  else dpv="devprobe STUCK at: $(tail -c 120 "$dp" 2>>"$ERR" | tail -1)"; fi
  echo "procs=$procs threads=${thr:-?} U=$U E=$E claude=$claude cpu[$top] | $dpv | abandoned=${ABANDONED:-none} | $(( $(date +%s) - T0 ))s | kit=$OUT"
}

capture() {
  # A test seam: one extra step first, so the abandon path is exercised without a real devfs wedge.
  if [ -n "${BG_TEST_STEP:-}" ]; then bstep teststep "${BG_TEST_STEP_DL:-1}" /bin/sh -c "$BG_TEST_STEP"; fi
  # cheap, no /dev, highest signal first
  bstep meta 5 /bin/sh -c 'date; sysctl kern.boottime kern.bootsessionuuid vm.loadavg kern.tty.ptmx_max vm.swapusage vm.compressor_bytes_used vm.compressor_compressed_bytes vm.page_free_count kern.memorystatus_level kern.maxvnodes kern.num_vnodes kern.free_vnodes kern.num_recycledvnodes vfs.vnstats.num_newvnode_calls kern.num_files kern.maxfiles 2>&1'
  # ps WITH -x and WITHOUT a tty column: Apple ps calls devname() only for tt/tty columns, -t/-T, or
  # when -x is absent (adv_cmds ps.c:687, print.c:623). tdev prints major/minor with no lookup.
  bstep ps 15 /bin/ps -axww -o "$PSFMT"
  bstep devprobe 6 /usr/bin/perl -e "$DEVPROBE"
  bstep pstree 15 /bin/ps -axww -o pid,ppid,pgid,tpgid,tdev,stat,lstart,ucomm
  bstep psargs 15 /bin/ps -axww -o pid,command
  bstep top 20 /usr/bin/top -l 1 -n 25 -o cpu -s 0 -stats pid,command,cpu,threads,state,pstate
  bstep vm 10 /usr/bin/vm_stat
  bstep lockwatch 5 /bin/sh -c 'for f in "$0"/state.json "$0"/pty.json "$0"/hb; do echo "== $f"; cat "$f"; echo; done; echo "== levels"; tail -n 20 "$0"/levels.jsonl' "$LW"
  # kitty main thread (the app that went Not Responding) and up to 4 uninterruptible processes.
  # NOT pgrep: macOS pgrep silently drops the caller's ancestors (-a re-includes them), and a kit
  # launched from inside a kitty pane would never find kitty. ucomm is the 16-char p_comm.
  if [ -z "${BG_LIGHT:-}" ]; then
    local kp; kp=$(awk 'NR>1 && $NF=="kitty" {print $1; exit}' "$OUT/ps.txt" 2>>"$ERR")
    [ -n "$kp" ] && bstep sample-kitty 12 /usr/bin/sample "$kp" 3 -mayDie
    local p
    for p in $(awk 'NR>1 && $4 ~ /U/ {print $1}' "$OUT/ps.txt" 2>>"$ERR" | head -4); do
      bstep "sample-U-$p" 8 /usr/bin/sample "$p" 1 -mayDie
    done
  fi
  # The FULL kit is the forensics lane's capture.sh (one instrument; its own mutex + rate limit).
  # Detached and never awaited, so this mini-kit's summary reaches the operator in ~15 s.
  local FX="${BG_FORENSICS_KIT:-$HOME/.claude/scripts/forensics/capture.sh}"
  [ -f "$FX" ] || FX="$REPO/scripts/forensics/capture.sh"
  if [ -n "${BG_FORENSICS_KIT:-}" ] && [ ! -f "$BG_FORENSICS_KIT" ]; then FX="$BG_FORENSICS_KIT"; fi
  if [ -f "$FX" ]; then
    ( CC_FX_FORCE=1 /bin/bash "$FX" "${BG_FX_TIER:-full}" "${BG_REASON:-breakglass}" < "$OUT/empty" > "$OUT/forensics.out" 2>&1 ) < "$OUT/empty" > "$OUT/bg.out" 2>&1 &
    log "FORENSICS pid=$! kit=$FX"
  else
    log "FORENSICS missing=$FX"
    [ -n "${BG_LIGHT:-}" ] || bstep kernlog 30 /usr/bin/log show --last 3m --style compact --predicate 'process == "kernel"'
  fi
}

# ── unpoison ─────────────────────────────────────────────────────────────────────────────────────
# The observed class (RCA-draft §3, R3/R12): session leader 68298 exited into vn_revoke→drain while a
# member of its process group (96296) slept in open() on the pty — a PCATCH wait, so SIGKILL of the
# group should let the revoke finish (L, untested until the Q2 VM reproduction). The guard against a
# wrong target is a FRESH re-read: (pid, lstart) must match, the leader must be exiting or orphaned
# on a pty, and a member other than the leader must still be asleep.

json_s() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037'; }

act_log() { # <result> <detail> — one JSONL row in lockwatch/actions.jsonl (§5)
  mkdir -p "$LW" 2>>"$ERR" || return 0
  printf '{"ts":"%s","boot":"%s","action":"unpoison","by":"%s","pgid":%s,"lstart":"%s","result":"%s","detail":"%s","kit":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(json_s "$BOOT")" "$(json_s "${RESCUE_CALLER:-operator}")" "$PG" \
    "$(json_s "$WANT_LS")" "$1" "$(json_s "$2")" "$(json_s "$OUT")" >> "$LW/actions.jsonl" 2>>"$ERR"
}

# lstart_epoch <text> → epoch seconds of a `ps -o lstart` string, an ISO-8601 UTC stamp or a bare
# epoch (lockprobe's pty.json may carry any of the three), or nothing
lstart_epoch() {
  case "$1" in
    '') return 1 ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) date -j -u -f '%Y-%m-%dT%H:%M:%S' "$(echo "$1" | cut -c1-19)" +%s 2>>"$ERR" ;;
    *[!0-9.]*)   # the caller's locale picks the word order: C gives "Sun Oct 25 …", en_CA "Sun 25 Oct …"
      local t f; t="$(printf '%s' "$1" | tr -s ' ' | sed 's/^ //; s/ $//')"   # drop the column padding
      for f in '%a %b %e %T %Y' '%a %e %b %T %Y'; do
        date -j -f "$f" "$t" +%s 2>>"$ERR" && return 0
      done
      return 1 ;;
    *) echo "${1%%.*}" ;;
  esac
}

# ttymap_tdev <pid> → the tdev lockprobe last recorded for the pid (an exiting leader reads NODEV
# live, R13), from the boot-scoped ttymap or pty.json; any of "16/N", an integer dev_t, "ttysNNN".
ttymap_tdev() {
  local f
  for f in "${RESCUE_TTYMAP:-}" "$LW/run/$BOOT/ttymap.json" "$LW/pty.json"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    /usr/bin/jq -r --arg p "$1" '
      [ (.. | objects | select((.pid? | tostring) == $p) | (.tdev?, .tty?)),
        (.. | objects | to_entries[] | select(.key == $p or (.key | startswith($p + ":")))
            | .value | objects | (.tdev?, .tty?)) ]
      | map(select(. != null)) | .[0] // empty | tostring' "$f" 2>>"$ERR" | head -1
    return 0
  done
}

# lw_targets <leader> → "<pid> <lstart>" per opener lockwatch named for this leader (diagnosis.json,
# pty.json or state.json `targets`: plain pids or {pid, lstart} objects); nothing when there are none
lw_targets() {
  local f
  for f in "${RESCUE_DIAGNOSIS:-}" "$LW/pty.json" "$LW/state.json"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    /usr/bin/jq -r --arg p "$1" '
      .. | objects | select(((.leader? // .pgid? // .pid?) | tostring) == $p) | .targets? // empty
      | .[]? | if type == "object" then "\(.pid) \(.lstart // "")" else "\(.) " end' "$f" 2>>"$ERR"
  done
}

tdev_is_pty() { # <tdev in any form> → 0 iff major 16 (the ptmx clone major, ttys%03d)
  case "$1" in
    16/[0-9]*|ttys[0-9]*) return 0 ;;
    *[!0-9]*|'') return 1 ;;
    *) [ $(( $1 >> 24 )) -eq 16 ] ;;
  esac
}

# The fresh-pty zsh canary (DESIGN.md P1): openpty, slave on zsh's stdio, master held by the parent
# for zsh's whole life. No setsid and no ctty, so its exit revokes nothing (§11 item 4).
PTYCANARY='import os, subprocess, time
m, s = os.openpty()
t = time.time()
p = subprocess.Popen(["/bin/zsh", "-fc", ": lockwatch-canary; exit"], stdin=s, stdout=s, stderr=s, close_fds=True)
rc = p.wait()
print("zsh_ms=%d rc=%d" % ((time.time() - t) * 1000, rc))
os.close(m)'

canaries() { # <tag> → 0 iff both the /dev walk and the fresh-pty zsh canary complete
  local ok=0 py
  bstep "canary-walk-$1" "${RESCUE_CANARY_DL:-8}" /usr/bin/perl -e "$DEVPROBE" || ok=1
  grep -q '^DONE' "$OUT/canary-walk-$1.txt" 2>>"$ERR" || ok=1
  py="$(command -v python3 2>>"$ERR")"
  if [ -n "$py" ]; then
    BSTEP_NOALARM=1 bstep "canary-zsh-$1" "${RESCUE_CANARY_DL:-8}" "$py" -I -c "$PTYCANARY" || ok=1
    grep -q 'rc=0$' "$OUT/canary-zsh-$1.txt" 2>>"$ERR" || ok=1
  fi
  log "CANARIES $1 ok=$ok walk=[$(tail -1 "$OUT/canary-walk-$1.txt" 2>>"$ERR")] zsh=[$(tail -1 "$OUT/canary-zsh-$1.txt" 2>>"$ERR")]"
  return "$ok"
}

unpoison() {
  PG="${1:-}" WANT_LS="${2:-}"
  local dry=0; [ "${3:-}" = "--dry-run" ] && dry=1
  BOOT="$(sysctl -n kern.bootsessionuuid 2>>"$ERR")"
  case "$PG" in ''|*[!0-9]*) echo "unpoison: REFUSED — pgid must be a number (got '$PG')"; act_log refused bad-pgid; PG=0; return 2 ;; esac
  if [ "$PG" -le 1 ]; then echo "unpoison: REFUSED — pgid $PG"; act_log refused pgid-le-1; return 2; fi
  local want; want="$(lstart_epoch "$WANT_LS")"
  if [ -z "$want" ]; then echo "unpoison: REFUSED — leader lstart '$WANT_LS' is not a ps lstart or epoch"; act_log refused bad-lstart; return 2; fi
  log "UNPOISON pgid=$PG lstart=$WANT_LS boot=$BOOT dry=$dry"

  # Fresh, bounded census: -x, tdev not tty, one KERN_PROC read in a detached, abandonable child.
  if ! bstep scan "${RESCUE_SCAN_DL:-15}" /bin/ps -axww -o pid=,ppid=,pgid=,stat=,tdev=,lstart=,ucomm=; then
    echo "unpoison: REFUSED — the process scan did not return (abandoned); no signal sent | kit=$OUT"
    act_log refused scan-abandoned; return 2
  fi
  local scan="$OUT/scan.txt"
  # columns: pid ppid pgid stat tdev lstart(5 words) ucomm(rest)
  local row; row="$(awk -v p="$PG" '$1 == p' "$scan" 2>>"$ERR")"
  if [ -z "$row" ]; then echo "unpoison: REFUSED — leader $PG is gone (nothing to cure, or the pgid is wrong)"; act_log refused leader-gone; return 2; fi
  local l_ppid l_pgid l_stat l_tdev l_ls l_comm got
  l_ppid=$(echo "$row" | awk '{print $2}'); l_pgid=$(echo "$row" | awk '{print $3}')
  l_stat=$(echo "$row" | awk '{print $4}'); l_tdev=$(echo "$row" | awk '{print $5}')
  l_ls=$(echo "$row" | awk '{print $6, $7, $8, $9, $10}')
  l_comm=$(echo "$row" | awk '{for (i = 11; i <= NF; i++) printf "%s%s", $i, (i < NF ? " " : "")}')
  got="$(lstart_epoch "$l_ls")"
  if [ "$l_pgid" != "$PG" ]; then echo "unpoison: REFUSED — pid $PG is not its group's leader (pgid $l_pgid)"; act_log refused not-leader; return 2; fi
  if [ -z "$got" ] || [ $(( got - want )) -gt 1 ] || [ $(( want - got )) -gt 1 ]; then
    echo "unpoison: REFUSED — leader $PG started '$l_ls', not '$WANT_LS' (pid reused); no signal sent"
    act_log refused lstart-mismatch; return 2
  fi
  if [ -n "${RESCUE_BOOT:-}" ] && [ "$RESCUE_BOOT" != "$BOOT" ]; then
    echo "unpoison: REFUSED — target recorded on boot $RESCUE_BOOT, this is $BOOT"; act_log refused boot-mismatch; return 2
  fi
  case "$l_comm" in kitty|launchd|loginwindow|WindowServer|Hammerspoon|iTerm2)
    echo "unpoison: REFUSED — leader $PG is $l_comm"; act_log refused protected-comm; return 2 ;; esac
  # never our own group or an ancestor's: the kit must not kill the terminal it runs from
  local a=$$ hops=0 protect=" "
  while [ -n "$a" ] && [ "$a" -gt 1 ] && [ "$hops" -lt 64 ]; do
    protect="$protect$(awk -v p="$a" '$1 == p {print $3}' "$scan") "
    a="$(awk -v p="$a" '$1 == p {print $2}' "$scan")"; hops=$((hops + 1))
  done
  case "$protect" in *" $PG "*)
    echo "unpoison: REFUSED — pgid $PG contains this kit or one of its ancestors"; act_log refused own-group; return 2 ;; esac
  local exiting=0 orphan=0 mapped
  case "$l_stat" in *E*|Z*) exiting=1 ;; esac
  [ "$l_ppid" = 1 ] && orphan=1
  mapped="$(ttymap_tdev "$PG")"
  [ -n "$mapped" ] || mapped="$l_tdev"
  if [ "$exiting$orphan" = 00 ]; then
    echo "unpoison: REFUSED — leader $PG ($l_stat, ppid $l_ppid) is neither exiting nor orphaned"; act_log refused leader-healthy; return 2
  fi
  if ! tdev_is_pty "$mapped"; then
    echo "unpoison: REFUSED — no pty (major 16) on record for leader $PG (tdev '$mapped')"; act_log refused no-pty; return 2
  fi
  # The target set is RCA R3's, not the pgid alone (RCA.md §7 R3, R17 step 3-4): the leader's
  # descendants by ppid walk, plus every pid whose getsid() is the leader, plus every process group
  # those pids are in. An opener can sit in another group of the same session (13:15: zsh 27387 in
  # pgid 27387 under leader 81102), and members' tdev reads NODEV once the revoke starts, so tdev
  # cannot find them. getsid runs in a bounded child: it is a plain syscall, no /dev, but the rule is
  # that nothing in this kit waits unbounded.
  awk '{print $1}' "$scan" > "$OUT/pids.txt"
  local py; py="$(command -v python3 2>>"$ERR")"
  : > "$OUT/sids.txt"
  if [ -n "$py" ]; then
    bstep sids 10 "$py" -I -c 'import os, sys
for l in open(sys.argv[1]):
    try: print(l.strip(), os.getsid(int(l)))
    except Exception: pass' "$OUT/pids.txt" || log "SIDS abandoned — descendants by ppid only"
  else
    log "SIDS no python3 — descendants by ppid only"
  fi
  awk -v L="$PG" 'FNR == NR { sid[$1] = $2; next }
    { ppid[$1] = $2; pg[$1] = $3; st[$1] = $4; kids[$2] = kids[$2] " " $1; all[++n] = $1 }
    END {
      q[1] = L; h = 1; t = 1; seen[L] = 1
      while (h <= t) { p = q[h++]; m = split(kids[p], k, " ")
        for (i = 1; i <= m; i++) if (!(k[i] in seen)) { seen[k[i]] = 1; q[++t] = k[i] } }
      for (i = 1; i <= n; i++) if (sid[all[i]] == L) seen[all[i]] = 1
      for (p in seen) if (p != L && (p in pg)) print p, pg[p], st[p]
    }' "$OUT/sids.txt" "$scan" > "$OUT/targets.txt"
  # Lane A's diagnosis may name openers OUTSIDE the tree (found by an `__open` sample leaf). Each is
  # accepted only with an lstart that matches the live pid, so a reused pid is never a target.
  local tp tls trow tgot
  while read -r tp tls; do
    case "$tp" in ''|*[!0-9]*) continue ;; esac
    trow="$(awk -v p="$tp" '$1 == p' "$scan")"
    [ -n "$trow" ] || { log "TARGET $tp from lockwatch is gone"; continue; }
    [ -n "$tls" ] || { log "TARGET $tp from lockwatch has no lstart — skipped (unverifiable)"; continue; }
    tgot="$(lstart_epoch "$(echo "$trow" | awk '{print $6, $7, $8, $9, $10}')")"; tls="$(lstart_epoch "$tls")"
    if [ -z "$tgot" ] || [ -z "$tls" ] || [ $(( tgot - tls )) -gt 1 ] || [ $(( tls - tgot )) -gt 1 ]; then
      log "TARGET $tp from lockwatch: lstart mismatch — skipped"; continue
    fi
    grep -q "^$tp " "$OUT/targets.txt" || echo "$trow" | awk '{print $1, $3, $4}' >> "$OUT/targets.txt"
  done <<EOF
$(lw_targets "$PG")
EOF
  local sleepers
  sleepers="$(awk '$3 ~ /^[SUD]/' "$OUT/targets.txt" | wc -l | tr -d ' ')"
  if [ "${sleepers:-0}" -lt 1 ]; then
    echo "unpoison: REFUSED — no process in leader $PG's session or tree is asleep (nothing holds the node)"; act_log refused no-sleeper; return 2
  fi
  # Groups other than the leader's first (the openers), the leader's group last (R3: "kill those,
  # then the leader"). A group that holds this kit's own ancestors or a protected app is refused whole.
  local groups="" g gc
  for g in $(awk -v L="$PG" '$2 != L {print $2}' "$OUT/targets.txt" | sort -un) "$PG"; do
    case "$protect" in *" $g "*)
      echo "unpoison: REFUSED — group $g in the target set holds this kit or an ancestor"; act_log refused own-group-in-set; return 2 ;; esac
    [ "$g" -gt 1 ] || { echo "unpoison: REFUSED — group $g in the target set"; act_log refused pgid-le-1-in-set; return 2; }
    gc="$(awk -v p="$g" '$1 == p {for (i = 11; i <= NF; i++) printf "%s%s", $i, (i < NF ? " " : "")}' "$scan")"
    case "$gc" in kitty|launchd|loginwindow|WindowServer|Hammerspoon|iTerm2)
      echo "unpoison: REFUSED — group $g in the target set is led by $gc"; act_log refused protected-group; return 2 ;; esac
    case " $groups " in *" $g "*) ;; *) groups="${groups:+$groups }$g" ;; esac
  done

  local verdict
  verdict="leader $PG ($l_comm, $l_stat, ppid $l_ppid, pty $mapped), $(wc -l < "$OUT/targets.txt" | tr -d ' ') target(s), $sleepers asleep, groups: $groups"
  if [ "$dry" = 1 ]; then
    echo "unpoison: WOULD kill -KILL -- -<pgid> for $verdict | kit=$OUT"
    act_log would "$verdict"; return 4
  fi
  for g in $groups; do
    if kill -KILL -- "-$g" 2>>"$ERR"; then log "KILL -$g"; else log "KILL -$g failed"; fi
  done
  act_log signalled "$verdict"
  # the last-close drain is ~0.6 s healthy (experiments.md §2b); give the revoke a few seconds
  local i=0
  while [ "$i" -lt 20 ]; do
    kill -0 "$PG" 2>>"$ERR" || break
    sleep 0.25; i=$((i + 1))
  done
  # The exiting leader (inside its own revoke) and children waiting in proc_parent cannot die until
  # their syscall returns (RCA R3): name them, never retry them.
  local unk="" up
  for up in "$PG" $(awk '{print $1}' "$OUT/targets.txt"); do kill -0 "$up" 2>>"$ERR" && unk="${unk:+$unk }$up"; done
  [ -z "$unk" ] || { log "UNKILLABLE $unk"; verdict="$verdict; unkillable: $unk"; }
  if canaries post; then
    echo "unpoison: CURED — killed groups $groups; canaries clean${unk:+; still present (unkillable): $unk} | kit=$OUT"
    act_log cured "$verdict"; return 0
  fi
  echo "unpoison: STILL STUCK after killing groups $groups${unk:+ (unkillable: $unk)} — next: Apple menu > Restart (writes the shutdown_stall stackshot) | kit=$OUT"
  act_log still-stuck "$verdict"; return 1
}

# ── brownout ─────────────────────────────────────────────────────────────────────────────────────
# The operator's hold on the admission brownout (V4 latch, §5 brownout.json): new fleet spawns are
# refused while it holds. `off` removes only a latch this kit (by=operator) wrote.
brownout() {
  local f="${CC_BROWNOUT_FILE:-$HOME/.claude/autonomy/brownout.json}" arg="${1:-60}"
  mkdir -p "$(dirname "$f")" || { echo "brownout: cannot create $(dirname "$f")"; return 3; }
  if [ "$arg" = off ]; then
    if [ -f "$f" ] && grep -q '"by":"operator"' "$f" 2>>"$ERR"; then rm -f "$f"; echo "brownout: operator hold released"
    else echo "brownout: no operator hold to release (left $f as it is)"; fi
    return 0
  fi
  case "$arg" in ''|*[!0-9]*) echo "brownout: minutes must be a number or 'off'"; return 2 ;; esac
  local now until
  now=$(date -u +%s); until=$(( now + arg * 60 ))
  printf '{"surface_unavailable_since":"%s","by":"operator","hold_s":%s,"hold_until":"%s","source":"break-glass"}\n' \
    "$(date -u -r "$now" +%Y-%m-%dT%H:%M:%SZ)" "$(( arg * 60 ))" "$(date -u -r "$until" +%Y-%m-%dT%H:%M:%SZ)" > "$f.tmp.$$" \
    && mv -f "$f.tmp.$$" "$f" || { echo "brownout: write failed"; return 3; }
  log "BROWNOUT hold ${arg}m"
  echo "brownout: held for $arg min (until $(date -r "$until" +%H:%M)) — release: /bin/bash rescue.sh brownout off"
}

# ── selftest ─────────────────────────────────────────────────────────────────────────────────────
selftest() {
  local verdict=pass why=""
  capture
  local s; s=$(summary_capture)
  grep -q '^DONE' "$OUT/devprobe.txt" 2>>"$ERR" || { verdict=fail; why="${why}devprobe;"; }
  [ "$(awk 'NR>1' "$OUT/ps.txt" 2>>"$ERR" | wc -l)" -gt 100 ] || { verdict=fail; why="${why}ps;"; }
  grep -q '^CPU usage' "$OUT/top.txt" 2>>"$ERR" || { verdict=fail; why="${why}top;"; }
  [ -z "$ABANDONED" ] || { verdict=fail; why="${why}abandoned=$ABANDONED;"; }
  # unpoison's refusal path, against a group we own: a wrong lstart must send NO signal (rc 2)
  /usr/bin/perl -e 'use POSIX; POSIX::setsid(); exec @ARGV' -- /bin/sleep 120 < "$OUT/empty" > "$OUT/bg.out" 2>&1 &
  local c=$! rc
  sleep 0.5
  ( LW="$OUT/lw"; unpoison "$c" 1 ) > "$OUT/selftest-unpoison.txt" 2>&1; rc=$?
  kill -0 "$c" 2>>"$ERR" || { verdict=fail; why="${why}unpoison-killed-on-refusal;"; }
  [ "$rc" = 2 ] || { verdict=fail; why="${why}unpoison-rc=$rc;"; }
  kill -KILL -- "-$c" 2>>"$ERR"
  local dur=$(( $(date +%s) - T0 ))
  # Duration is ADVISORY: a bound sized on an idle box is a non-verdict under load (lesson 3).
  [ "$dur" -le 75 ] || why="${why}slow=${dur}s@load=$(sysctl -n vm.loadavg | awk '{print $2}');"
  printf '%s %s dur=%s why=%s kit=%s\n' "$verdict" "$(date +%s)" "$dur" "${why:-none}" "$OUT" > "$ROOT/selftest.last"
  echo "selftest $verdict ($dur s) ${why} | $s"
  [ "$verdict" = pass ]
}

rc=0
case "$MODE" in
  capture)  capture; summary_capture ;;
  unpoison) shift; unpoison "$@"; rc=$? ;;
  brownout) shift; brownout "$@"; rc=$? ;;
  selftest) selftest; rc=$? ;;
  *) echo "usage: /bin/bash rescue.sh capture | unpoison <pgid> <leader_lstart> [--dry-run] | brownout [minutes|off] | selftest"; rc=2 ;;
esac
log "EXIT rc=$rc"
exit "$rc"
