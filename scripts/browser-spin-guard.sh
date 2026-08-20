#!/usr/bin/env bash
# browser-spin-guard.sh — catch an AUTOMATION browser tree that has wedged into a CPU spin.
#
# THE INCIDENT (2026-08-17). An `agent-browser` daemon (pid 3153, up 2d21h) held a headless Chrome
# (pid 80986, up 1d15h) whose EVERY service process — GPU, NetworkService, StorageService,
# AudioService, VideoCaptureService, and three renderers — sat at 86-103% CPU simultaneously.
# Aggregate: 761% of the box's 1000%. Measured effect: load average 244, `top` reporting 85.9% SYS
# and 0.0% idle, seconds-per-keystroke lag. It had been doing this for a day and a half and
# NOTHING ON THE BOX EVER SAID SO. Killing the tree took the machine from 905% -> 309% total CPU
# and load 244 -> 56 within one minute.
#
# WHY NOTHING CAUGHT IT. Two guards could plausibly have owned this class and neither does:
#   - `cc-reaper garbage` collects the residue of DEAD sessions. Its snapshot is
#     `pid=,ppid=,etime=,ucomm=` — no CPU field at all — so a process that is *very much alive* and
#     burning a core is invisible to it by construction.
#   - `compressor-sentinel.sh` samples pcpu but adjudicates MEMORY (compressor segments). At the
#     time of the incident segment utilisation was 12.8% of limit — correctly quiet. The box was
#     not dying of memory; it was dying of CPU, and no rung watched that.
#
# WHY "STILL RUNNING" IS NOT THE DEFECT. A warm idle automation browser is `agent-browser`'s whole
# value proposition — the daemon persists so the next command does not pay a browser cold start.
# It is SUPPOSED to outlive the session that spawned it, at ~0% CPU. So neither "is it old" nor
# "is it orphaned" discriminates. Orphanhood especially does not: on this box essentially every
# backgrounded worker is reparented to launchd, so ppid==1 is the healthy population, not the sick
# one. The axis that separates them is the one that hurt: SUSTAINED CPU.
#
# THE INSTRUMENT, AND WHY IT NEEDS NO SECOND SAMPLE. `ps -o pcpu` on Darwin is not an instantaneous
# reading — it is the process's accumulated CPU time divided by its elapsed lifetime. That makes it
# exactly the right instrument here, and it is worth being explicit about why: for a process that
# has been alive for AGE seconds, pcpu >= PCT means it averaged PCT% across that ENTIRE window. A
# burst cannot reach it. A 30-second spike inside a 15-minute lifetime contributes ~3%. So a single
# sample over an age floor already encodes "has been pegged for a long time" — there is no need to
# sample twice and no sampling race to lose. (The incident's processes read 86-103% against
# lifetimes of 8h-1d15h, i.e. pegged for essentially all of it.)
#
# THE SCOPE, AND WHY IT IS NARROW ON PURPOSE. This fires only on browser processes belonging to an
# AUTOMATION tree: a browser root whose argv carries `--remote-debugging-port`, plus its
# descendants. The operator's own browsers (Dia, a hand-launched Chrome) never carry that flag, so
# they are outside the population entirely rather than being excused by a name check. A broad
# "anything pegged" alarm was considered and rejected: legitimate long burners exist (XprotectService
# was measured at 105% during this very investigation), and an alarm that fires on them teaches the
# operator to ignore it — the attention-budget failure this repo has already paid for elsewhere.
# Narrow population + a named owner + one drivable remedy is the whole design.
#
# VERDICT CONTRACT. Always exits 0 on a successful measurement and prints a parseable token —
# `verdict=clean`, `verdict=spin`, or `verdict=unknown`. A non-verdict (snapshot unavailable) is
# `unknown`, NOT a failure exit: this is an acquit-only detector, and using the error channel to
# mean "nothing found" is how a null result gets read as a fault. Exit is non-zero only for a
# usage error.
#
# WHY IT ONLY DETECTS, AND DOES NOT REAP, ON THE SCHEDULE. `--reap` exists and is tested, but the
# launchd job does not pass it. This arm acts on live processes, which this repo treats as an
# operator decision rather than a maintenance default (see the header of
# launchd/com.claude.compressor-sentinel.plist, where arming was an explicit in-session
# authorization). The asymmetry that justifies waiting here and not there: the compressor panic
# gives ~7.6 seconds of warning, so nothing but an armed actuator can act inside it — whereas this
# wedge ran for a day and a half. Any surfaced alarm has abundant time to be acted on, so the
# marginal value of auto-killing is small and the downside (killing a browser mid-automation) is
# not. Arming is one word in the plist's ProgramArguments if the operator wants it.
#
# Usage:
#   browser-spin-guard.sh              # detect + report (never kills)
#   browser-spin-guard.sh --notify     # + damped cc-notify to the desk role on a state change
#   browser-spin-guard.sh --reap       # graceful `agent-browser close --all`, then KILL survivors
#   browser-spin-guard.sh --json       # machine-readable
#
# Env:
#   CC_SPIN_GUARD=0                    kill switch — arm is inert, verdict=clean
#   CC_SPIN_PCT   (default 80)         lifetime-average %CPU floor
#   CC_SPIN_AGE_S (default 900)        minimum process age, seconds
#   CC_SPIN_RENOTIFY_S (default 21600) re-assert interval while STILL spinning (6 h)
#   CC_SPIN_GUARD_PS                   test seam: file replacing the live ps snapshot
#   CC_SPIN_GUARD_KILL                 test seam: collector invoked instead of kill(1)
#   CC_SPIN_GUARD_CLOSE                test seam: command replacing `agent-browser close --all`
#   CC_SPIN_GUARD_NOTIFY               test seam: command replacing cc-notify
#   CC_SPIN_GUARD_STATE                test seam: damping state file
set -uo pipefail

# LC_ALL=C: a locale rendering %CPU as "0,0" would make every numeric comparison below meaningless.
export LC_ALL=C

PCT="${CC_SPIN_PCT:-80}"
AGE_S="${CC_SPIN_AGE_S:-900}"
LOG_FILE="${CC_SPIN_GUARD_LOG:-$HOME/.claude/logs/browser-spin-guard.log}"

REAP=0; JSON=0; NOTIFY=0
RENOTIFY_S="${CC_SPIN_RENOTIFY_S:-21600}"
STATE_FILE="${CC_SPIN_GUARD_STATE:-$HOME/.claude/state/browser-spin-guard.state}"
while [ $# -gt 0 ]; do
  case "$1" in
    --reap) REAP=1 ;;
    --json) JSON=1 ;;
    --notify) NOTIFY=1 ;;
    -h|--help) sed -n '1,60p' "$0"; exit 0 ;;
    *) printf 'browser-spin-guard: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

log() {
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

if [ "${CC_SPIN_GUARD:-1}" != 1 ]; then
  log "disabled (CC_SPIN_GUARD=0)"
  printf 'browser-spin-guard: disabled (CC_SPIN_GUARD=0)\nverdict=clean\n'
  exit 0
fi

# ── snapshot ──────────────────────────────────────────────────────────────────────────────────
# -ww: argv must not be truncated at terminal width, or the `--remote-debugging-port` marker that
# defines the whole population can fall off the end of the line on a narrow tty.
if [ -n "${CC_SPIN_GUARD_PS:-}" ]; then
  SNAP="$(cat "$CC_SPIN_GUARD_PS" 2>/dev/null)" || SNAP=""
else
  SNAP="$(/bin/ps -Awwo pid=,ppid=,etime=,pcpu=,args= 2>/dev/null)" || SNAP=""
fi

if [ -z "$SNAP" ]; then
  log "snapshot unavailable — no verdict (fail-open)"
  printf 'browser-spin-guard: process snapshot unavailable — cannot judge\nverdict=unknown\n'
  exit 0
fi

# ── classify ──────────────────────────────────────────────────────────────────────────────────
# Emits, per pegged member: pid<TAB>pcpu<TAB>age_s<TAB>role<TAB>argv-signature
FOUND="$(printf '%s\n' "$SNAP" | awk -v pct="$PCT" -v agefloor="$AGE_S" '
  function esec(e,  d,a,n,hms) { d=0; if (index(e,"-")>0) { split(e,a,"-"); d=a[1]; e=a[2] }
    n=split(e,hms,":")
    if (n==3) return d*86400+hms[1]*3600+hms[2]*60+hms[3]
    if (n==2) return d*86400+hms[1]*60+hms[2]
    return d*86400+hms[1] }
  # role() — what the process is inside the browser tree, for a legible report line. Chrome tags
  # every child with --type=; the untagged one is the browser (root) process itself.
  function role(a,  m) {
    if (a ~ /--type=renderer/)     return "renderer"
    if (a ~ /--type=gpu-process/)  return "gpu"
    if (a ~ /--utility-sub-type=/) { m=a; sub(/.*--utility-sub-type=/,"",m); sub(/ .*/,"",m); return m }
    if (a ~ /--type=/)             { m=a; sub(/.*--type=/,"",m); sub(/ .*/,"",m); return m }
    return "browser-root" }
  function sig(a,  s) { s=a; gsub(/\t/," ",s); return substr(s,1,110) }
  {
    if ($1 !~ /^[0-9]+$/) next
    pid=$1; ppid=$2; secs=esec($3); cpu=$4+0
    a=$5; for (i=6; i<=NF; i++) a=a" "$i
    P[pid]=ppid; S[pid]=secs; C[pid]=cpu; A[pid]=a
    # An automation ROOT is the browser binary itself (no --type=) carrying the remote-debugging
    # marker. Requiring the absence of --type= matters: Chrome passes the parent command line
    # fragments around, and without it a helper could nominate itself as a root.
    if (a ~ /--remote-debugging-port/ && a !~ /--type=/) ROOT[pid]=1
  }
  END {
    # Mark every descendant of every automation root. Bounded walk: the chain cannot exceed the
    # number of processes observed, so a malformed/cyclic ppid table cannot hang this.
    n=0; for (p in P) n++
    for (p in P) {
      q=p; hops=0
      while (q != "" && q > 1 && hops <= n) {
        if (q in ROOT) { TREE[p]=1; break }
        q=P[q]; hops++
      }
    }
    for (p in ROOT) TREE[p]=1
    for (p in TREE) {
      if (S[p] >= agefloor && C[p] >= pct)
        printf "%s\t%.1f\t%d\t%s\t%s\n", p, C[p], S[p], role(A[p]), sig(A[p])
    }
  }' | sort -k2 -rn)"

NPEG=0; TOTCPU=0
if [ -n "$FOUND" ]; then
  NPEG="$(printf '%s\n' "$FOUND" | wc -l | tr -d ' ')"
  TOTCPU="$(printf '%s\n' "$FOUND" | awk -F'\t' '{s+=$2} END {printf "%.0f", s+0}')"
fi

# ── damping ───────────────────────────────────────────────────────────────────────────────────
# A 5-minute job that re-pages every tick for a day and a half is a worse instrument than silence:
# the operator learns the line means nothing. So the alarm speaks on the EDGE (clean -> spin) and
# then re-asserts only every CC_SPIN_RENOTIFY_S while the condition persists. The clean branch
# writes state too — that is what makes the next spin an edge rather than a continuation, and
# skipping it is how a damped alarm goes permanently silent after its first fire.
read_state() { [ -f "$STATE_FILE" ] && cat "$STATE_FILE" 2>/dev/null || printf 'clean 0\n'; }
write_state() { # <verdict> <last_notify_epoch>
  mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
  printf '%s %s\n' "$1" "$2" > "$STATE_FILE" 2>/dev/null || true
}
maybe_notify() { # <n> <cpu>
  [ "$NOTIFY" = 1 ] || return 0
  local prev last now msg
  read -r prev last <<EOF
$(read_state)
EOF
  case "${last:-0}" in ''|*[!0-9]*) last=0 ;; esac
  now="$(date +%s 2>/dev/null || echo 0)"
  if [ "$prev" = "spin" ] && [ $((now - last)) -lt "$RENOTIFY_S" ]; then
    log "notify: damped (still spinning, last sent $((now - last))s ago)"
    write_state spin "$last"; return 0
  fi
  msg="⚠️ wedged automation browser: $1 processes at $2% aggregate CPU for >$((AGE_S/60))m. This is the 2026-08-17 class (load 244, 0% idle). Remedy: agent-browser close --all"
  if [ -n "${CC_SPIN_GUARD_NOTIFY:-}" ]; then "$CC_SPIN_GUARD_NOTIFY" "$msg" || true
  else command -v cc-notify >/dev/null 2>&1 && { cc-notify --role desk "$msg" >/dev/null 2>&1 || true; }
  fi
  log "notify: SENT ($1 procs, $2%)"
  write_state spin "$now"
}

# ── report ────────────────────────────────────────────────────────────────────────────────────
if [ "$NPEG" -eq 0 ]; then
  log "clean: no automation browser process at >=${PCT}% for >=${AGE_S}s"
  write_state clean 0
  if [ "$JSON" = 1 ]; then
    printf '{"verdict":"clean","pegged":0,"cpu_pct_total":0,"pct_floor":%s,"age_floor_s":%s}\n' "$PCT" "$AGE_S"
  else
    printf 'browser-spin-guard: no wedged automation browser (floor %s%%CPU / %ss)\nverdict=clean\n' "$PCT" "$AGE_S"
  fi
  exit 0
fi

log "SPIN: $NPEG pegged automation-browser procs, ${TOTCPU}% aggregate CPU"
maybe_notify "$NPEG" "$TOTCPU"

if [ "$JSON" = 1 ]; then
  printf '{"verdict":"spin","pegged":%s,"cpu_pct_total":%s,"pct_floor":%s,"age_floor_s":%s,"procs":[' \
    "$NPEG" "$TOTCPU" "$PCT" "$AGE_S"
  printf '%s\n' "$FOUND" | awk -F'\t' 'BEGIN{f=1}
    { gsub(/\\/,"\\\\",$5); gsub(/"/,"\\\"",$5)
      if(!f) printf ","; f=0
      printf "{\"pid\":%s,\"cpu\":%s,\"age_s\":%s,\"role\":\"%s\",\"argv\":\"%s\"}", $1,$2,$3,$4,$5 }'
  printf ']}\n'
else
  printf 'browser-spin-guard: WEDGED AUTOMATION BROWSER — %s processes, %s%% aggregate CPU\n\n' "$NPEG" "$TOTCPU"
  printf '  %-8s %7s %10s  %s\n' PID %CPU AGE ROLE
  printf '%s\n' "$FOUND" | awk -F'\t' '{ printf "  %-8s %7s %9dm  %s\n", $1, $2, $3/60, $4 }'
  printf '\nRemedy: agent-browser close --all   (or re-run this with --reap)\nverdict=spin\n'
fi

[ "$REAP" = 1 ] || exit 0

# ── reap ──────────────────────────────────────────────────────────────────────────────────────
# Graceful first: `agent-browser close --all` is the vendor's own teardown and lets the daemon
# clean up its session state. Then hard-kill whatever is STILL pegged.
printf '\nreaping…\n'
if [ -n "${CC_SPIN_GUARD_CLOSE:-}" ]; then
  "$CC_SPIN_GUARD_CLOSE" || true
else
  # `type -P`, never a bare `agent-browser` at command position. This job's PATH is
  # com.claude.browser-spin-guard.plist's, and on this box agent-browser exists ONLY inside an fnm
  # multishell dir — a path that changes per shell — so the bare name resolved in the operator's
  # shell and NOWHERE the daemon actually runs. The graceful close is best-effort by construction,
  # so the unreachable case stays a skip, but a LOGGED one: a silent skip is exactly the fail-open
  # polarity unattended-path-lint exists to catch. The hard kill below runs either way.
  _ab_close="$(type -P agent-browser 2>/dev/null || true)"
  if [ -n "$_ab_close" ]; then
    "$_ab_close" close --all >/dev/null 2>&1 || true
  else
    printf '  agent-browser is not on this job%s PATH — skipping the graceful close, going straight to the hard kill\n' "'s"
  fi
  sleep 3
fi

NKILL=0
while IFS="$(printf '\t')" read -r pid cpu age role argsig; do
  [ -n "$pid" ] || continue
  case "$pid" in *[!0-9]*) continue ;; esac
  # RE-VERIFY BEFORE KILLING (pid reuse). The snapshot above is a moment in the past; between
  # classification and here the pid may belong to something else entirely. Re-read argv and require
  # the automation marker to still be present. If it is not, the pid is no longer the thing we
  # judged — refuse rather than kill a stranger.
  if [ -n "${CC_SPIN_GUARD_KILL:-}" ]; then
    "$CC_SPIN_GUARD_KILL" "$pid" "$role" "$argsig"; NKILL=$((NKILL+1)); continue
  fi
  live="$(/bin/ps -p "$pid" -o args= 2>/dev/null)" || live=""
  if [ -z "$live" ]; then
    log "reap: $pid already gone ($role)"
    continue
  fi
  case "$live" in
    *--remote-debugging-port*|*"Google Chrome"*|*Chromium*) ;;
    *) log "reap: REFUSED $pid — argv no longer an automation browser (pid reused): <$live>"; continue ;;
  esac
  # SIGKILL, not SIGTERM, and this is measured rather than assumed: in the incident SIGTERM was
  # delivered to the browser root and every helper and was ignored by all of them — they were
  # spinning inside the kernel and never ran a signal handler. TERM here would look like a
  # successful reap while changing nothing.
  if kill -9 "$pid" 2>/dev/null; then
    NKILL=$((NKILL+1)); log "reap: KILLED $pid ($role) cpu=$cpu age=${age}s"
  fi
done <<EOF
$FOUND
EOF

log "reap: $NKILL killed of $NPEG"
printf 'reaped %s of %s\nverdict=spin\n' "$NKILL" "$NPEG"
exit 0
