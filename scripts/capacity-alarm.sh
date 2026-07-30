#!/bin/bash
# capacity-alarm.sh — surface machine-capacity pressure BEFORE the box starts swapping.
#
# WHY (row 13 M6, MACHINE_CAPACITY_V2.md §4). The row measured a real ceiling — ~50 concurrent
# sessions on this 10-core/64 GiB box — and the ceiling was STATED with nothing that would notice it
# being approached. An unalarmed ceiling is discovered by swapping, which is the lagging indicator.
#
# THIS IS AN ALARM, NOT A GATE — and that distinction is the whole design.
# The landed `capacity_gate()` (handoff-fire.sh, CC_FIRE_MAX_LOAD_PER_CORE=2.0) is the cautionary
# case: measured against 13 real samples it scores REFUSE 10/10, because it keys on a system-wide
# loadavg dominated by the TUI renderer and macOS scanning — neither sheddable by refusing a spawn.
# Deployed, it would be a permanent dispatch outage. So this file:
#   · NEVER refuses, blocks, queues, sleeps, or polls-until-clear. It reports and exits (R1: a
#     shedder that WAITS amplifies).
#   · keys on MEMORY, which is genuinely sheddable and genuinely attributable to sessions — never on
#     loadavg, which swung 2.05x (29.15 -> 59.80) at a CONSTANT 31-32 sessions.
#
# THE INSTRUMENT, chosen because the obvious ones lie:
#   · `ps rss` summed over sessions OVERCOUNTS ~2.34x (it double-counts shared pages) — do not use
#     it to decide anything. It is fine for per-process comparison, wrong for a fleet total.
#   · loadavg is high-variance and not session-attributable (above).
#   · What actually decides whether the box swaps is RECLAIMABLE HEADROOM:
#     free + speculative + inactive + purgeable. Measured 28.2 GB with 8 sessions live.
#   · `sysctl vm.swapusage` used > 0 is the HARD signal — by then it is already happening.
#
# Verdicts (four, never a boolean — "could not measure" must not read as "fine"):
#   OK       every rung clear.                                        exit 0
#   WARN     any rung at its warn floor, none at alarm.               exit 1
#   ALARM    any rung at its alarm floor.                             exit 2
#   NO-DATA  vm_stat unreadable — nothing is asserted.                exit 3
#
# FOUR RUNGS, MAX-COMBINED (M9/M9-ext, §11.3). The verdict is the WORST rung, never the last one
# evaluated — so a new term can only ever raise the verdict, never mask an existing one:
#   1. swap in use            > 0 MB           ⇒ ALARM   (the hard, LAGGING signal)
#   2. reclaimable headroom   < ALARM_GB/WARN_GB
#   3. kernel pressure level  >= 4 / >= 2      ⇒ ALARM / WARN   (the kernel's own LEADING indicator)
#   4. per-proc phys outlier  > PROC_WARN_GB   ⇒ WARN    (the leak term; report always, gate softly)
#
# WHY RUNG 3 EXISTS. 2026-07-26 proved the swap rung fires only AFTER the pain: 2.56 GB of swap was
# in use at 57 procs, and the swap file was later reset by a reboot — so "swap 0" today is not
# evidence the ceiling was never hit. `kern.memorystatus_vm_pressure_level` is what the kernel itself
# uses to decide it is unhappy, and it moves BEFORE swapping. Compressor stays REPORTED-BUT-NOT-GATED:
# no calibrated threshold for it exists, and inventing one would be a made-up number in a verdict.
#
# AN UNREADABLE PRESSURE LEVEL IS NOT NO-DATA — deliberately. NO-DATA belongs to the ONE instrument
# the verdict cannot exist without (vm_stat headroom). The pressure sysctl is a supplementary rung:
# if it is missing on some macOS build, the headroom/swap verdict is still fully valid, and demoting
# it to NO-DATA would destroy a working alarm to report the absence of a bonus. So a missing level is
# skipped (and logged as null), while a missing headroom is still NO-DATA.
#
# Seams: CC_CAPACITY_ALARM=off (kill switch) · CC_CAP_WARN_GB (default 8) ·
#        CC_CAP_ALARM_GB (default 3) · CC_CAP_PROC_WARN_GB (default 3) · CC_CAP_LOG ·
#        CC_CAP_TOP (top(1) binary, for stubbing) · CC_CAP_SELFTEST=1 (positive control)
#
# bash 3.2 safe. Ships to launchd ⇒ tested under /bin/bash.

set -uo pipefail

WARN_GB="${CC_CAP_WARN_GB:-8}"
ALARM_GB="${CC_CAP_ALARM_GB:-3}"
PROC_WARN_GB="${CC_CAP_PROC_WARN_GB:-3}"
LOG="${CC_CAP_LOG:-$HOME/.claude/logs/capacity-alarm.jsonl}"
APPEND=1; WANT_JSON=0; QUIET=0

while [ $# -gt 0 ]; do
  if   [ "$1" = "--json" ];      then WANT_JSON=1
  elif [ "$1" = "--quiet" ];     then QUIET=1
  elif [ "$1" = "--no-append" ]; then APPEND=0
  elif [ "$1" = "--selftest" ];  then CC_CAP_SELFTEST=1
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0
  else echo "capacity-alarm.sh: unknown arg '$1'" >&2; exit 64
  fi
  shift
done

if [ "${CC_CAPACITY_ALARM:-on}" = "off" ]; then
  [ "$QUIET" = 1 ] || echo "capacity-alarm: disabled (CC_CAPACITY_ALARM=off)"
  exit 0
fi

# ── read machine memory truth ─────────────────────────────────────────────────────────────────────
# One python3 pass over vm_stat: the page size is authoritative from vm_stat's own header, never
# assumed to be 4096 (it is 16384 on Apple silicon, and assuming 4096 understates by 4x).
#
# NOTE ON THE INVOCATION FORM — `python3 -c`, never `python3 - <<'HEREDOC'`.
# The heredoc form was written here first and was silently broken: with `python3 -`, the PROGRAM is
# read from stdin, so a heredoc claims the very stdin the pipe was supposed to deliver and
# `sys.stdin.read()` gets nothing. The result was a permanent NO-DATA. This is the documented trap in
# memory blind-check-generators-stdin-and-sid-keys ("`python3 - <<PY` eats the stdin a guard meant to
# read"), and shellcheck flags it as SC2259. Keep the program in -c so stdin stays the data channel.
read_mem() {
  vm_stat 2>/dev/null | "${CC_CAP_PYTHON:-python3}" -c '
import sys,re
o=sys.stdin.read()
m=re.search(r"page size of (\d+)",o)
if not m: sys.exit(1)
pg=int(m.group(1)); d={}
for line in o.splitlines()[1:]:
    if ":" not in line: continue
    k,v=line.split(":",1); v=v.strip().rstrip(".")
    if v.isdigit(): d[k.strip()]=int(v)
G=lambda k: d.get(k,0)*pg/1024**3
head=G("Pages free")+G("Pages speculative")+G("Pages inactive")+G("Pages purgeable")
comp=G("Pages occupied by compressor")
act=G("Pages active"); wired=G("Pages wired down")
if head==0 and act==0: sys.exit(1)
print("%.2f %.2f %.2f %.2f" % (head,comp,act,wired))
' 2>/dev/null
}

MEM="$(read_mem || true)"
SWAP_MB="$(sysctl -n vm.swapusage 2>/dev/null \
            | sed -n 's/.*used = \([0-9.]*\)M.*/\1/p' | head -1)"
# ── session census — BOTH pid families, counted as TREES, matched at the COMMAND POSITION ─────────
# THREE separate census defects are fixed here, each measured, each of which silently understated or
# overstated the fleet. This function is the reason the row exists, so the reasoning stays in-file.
#
# (1) pgrep SILENTLY UNDERCOUNTS — the original defect. Measured 2026-07-29 with 8 live sessions,
#     `pgrep -cf 'claude-code/bin/claude\.exe'` returned 0 while a `ps` read returned 8: macOS
#     pgrep -f matches against a TRUNCATED argv, so a long absolute path never matches, and
#     `pgrep -x` cannot see the path at all. A counter that reads 0 forever is the exact failure in
#     memory actuator-must-see-the-target-population (134/134 MISS) — here it would make this alarm
#     permanently report an empty fleet. Hence ps, not pgrep.
#
# (2) ONE FAMILY IS NOT THE FLEET — the defect this row fixes. The incumbent matched only
#     `claude-code/bin/claude.exe` and so reported 13 of 31 real session trees (archaeology, §11.2):
#     sessions launch under TWO disjoint spellings — `.../claude-code/bin/claude.exe` (measured
#     ≡ exactly the `--agent-id` teammate set) and `.../node_modules/.bin/claude` (the interactive
#     launcher path). Measured intersection: ZERO — they are disjoint populations, not two views of
#     one, so the fleet is their SUM. Re-measured live while writing this: 35 + 25 = 60 trees where
#     the incumbent pattern saw 35. Both families are ~350-765 MB each, so missing one is missing
#     half the memory the alarm exists to watch.
#
# (3) MATCHING ANYWHERE IN argv OVERCOUNTS — found by measurement while fixing (2), and the reason
#     this reads a specific FIELD rather than the whole line. A whole-argv grep for the same two
#     patterns returned 83 where the true population is 60: the 23 extras are `bash
#     .../cc-close-attrib .../node_modules/.bin/claude ...` wrappers, which merely NAME a claude
#     binary in their arguments. This is memory pgrep-f-matches-agent-briefs ("argv carries whole
#     briefs, so `pgrep -f X` counts sessions that MENTION X") — the fix is to match on the COMMAND
#     POSITION (argv[0]) only. Note a PPID-in-family subtraction alone does NOT fix this: those
#     wrappers' parents are mostly NOT in-family, so 12 of the 23 would have survived it.
#
# TREES, NOT PROCESSES. What consumes the ~500 MB is a session tree, so a proc whose parent is itself
# in-family is a child of an already-counted tree and must not be counted twice. Measured today that
# subtraction removes 0 (§11.2: "no claude process has a claude parent" — background subagents are
# in-process), i.e. it is currently a no-op — it is kept because it is the CORRECT reduction, so a
# future binary that does fork an in-family child cannot silently double the count.
#
# `comm` was rejected as the matching field: measured, a `.bin/claude` session reports COMMAND `node`
# to top(1), so the resolved executable name loses the very distinction being counted.
census() { # → "<trees> <exe_trees> <bin_trees>"
  ps -eo pid=,ppid=,args= 2>/dev/null | awk '
    {
      cmd = $3; f = ""
      if      (cmd ~ /claude-code\/bin\/claude\.exe$/) f = "exe"
      else if (cmd ~ /node_modules\/\.bin\/claude$/)   f = "bin"
      if (f != "") { fam[$1] = f; par[$1] = $2 }
    }
    END {
      exe = 0; bin = 0
      for (p in fam) {
        if (par[p] in fam) continue        # child of an already-counted tree
        if (fam[p] == "exe") exe++; else bin++
      }
      printf "%d %d %d\n", exe + bin, exe, bin
    }'
}

CENSUS="$(census || true)"
SESSIONS=0; SESSIONS_EXE=0; SESSIONS_BIN=0
if [ -n "$CENSUS" ]; then
  # shellcheck disable=SC2086  # deliberate word-split of the 3-field awk output
  set -- $CENSUS
  SESSIONS="${1:-0}"; SESSIONS_EXE="${2:-0}"; SESSIONS_BIN="${3:-0}"
fi
case "$SESSIONS"     in ''|*[!0-9]*) SESSIONS=0 ;;     esac
case "$SESSIONS_EXE" in ''|*[!0-9]*) SESSIONS_EXE=0 ;; esac
case "$SESSIONS_BIN" in ''|*[!0-9]*) SESSIONS_BIN=0 ;; esac

# ── the kernel's own leading indicator (M9-ext rung 3) ────────────────────────────────────────────
# Empty when the sysctl does not exist on this build; see the header — that is a skipped rung, never
# NO-DATA. Stripped of whitespace so the numeric guards in classify() see a bare integer.
PRESSURE="$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null | tr -dc '0-9')"

# ── per-proc physical-footprint outlier (M9b rung 4) ──────────────────────────────────────────────
# §8.5.6 prescribed footprint(1) as the instrument because summed `ps rss` OVERCOUNTS ~2.34x (shared
# pages counted once per process). top(1)'s MEM column is that same physical-footprint accounting, and
# unlike footprint(1) it needs no per-pid loop over a 250-proc box — one sample yields the top N.
#
# ALARM-NOT-GATE, ABSOLUTELY. This is the leak term the directive asked for, and a leak is diagnosed
# by a TREND across rows, not by one sample. So the top rows are reported on EVERY row (that is what
# makes the trend readable at all) and only an absolute breach of PROC_WARN_GB floors WARN — never
# ALARM, never a refusal. Today's max is iTerm2 at 2.24 GB against a 3 GB floor: the rung is armed
# and quiet, which is the state a threshold should ship in.
#
# ps rss is the FALLBACK, and it is deliberately a worse instrument used only when the better one is
# unavailable: it overcounts shared pages, so it can only ever raise a false WARN, never hide a real
# one. Failing toward the louder direction is the right way for a fallback to be wrong.
read_top_procs() { # → lines "<pid> <mb> <cmd>"
  "${CC_CAP_TOP:-top}" -l 1 -o mem -n 3 -stats pid,mem,command 2>/dev/null | awk '
    $1 ~ /^[0-9]+$/ && NF >= 3 {
      raw = $2; unit = "M"
      if (raw ~ /[KkMmGg]/) { unit = raw; gsub(/[^KkMmGg]/, "", unit) }
      n = raw; gsub(/[^0-9.]/, "", n); if (n == "") next
      mb = n + 0
      if      (unit == "K" || unit == "k") mb = mb / 1024
      else if (unit == "G" || unit == "g") mb = mb * 1024
      cmd = $3; for (i = 4; i <= NF; i++) cmd = cmd " " $i
      gsub(/[\\"]/, "", cmd); gsub(/[[:space:]]+$/, "", cmd)
      printf "%s %.0f %s\n", $1, mb, cmd
      if (++seen == 3) exit
    }'
}

TOP_PROCS="$(read_top_procs || true)"
if [ -z "$TOP_PROCS" ]; then
  TOP_PROCS="$(ps -eo pid=,rss=,comm= 2>/dev/null \
                | sort -k2 -nr | head -3 \
                | awk '{ cmd = $3; for (i = 4; i <= NF; i++) cmd = cmd " " $i
                         gsub(/[\\"]/, "", cmd); printf "%s %.0f %s\n", $1, $2/1024, cmd }' || true)"
fi

# JSON array + the max, from the same rows — so the number in the verdict and the rows in the log can
# never disagree about which process was the outlier.
TOP_JSON='[]'; MAX_PROC_GB=""
if [ -n "$TOP_PROCS" ]; then
  TOP_JSON="$(printf '%s\n' "$TOP_PROCS" | awk '
    BEGIN { printf "[" }
    { if (NR > 1) printf ","
      cmd = $3; for (i = 4; i <= NF; i++) cmd = cmd " " $i
      printf "{\"pid\":%s,\"mb\":%s,\"cmd\":\"%s\"}", $1, $2, cmd }
    END { printf "]" }')"
  MAX_PROC_GB="$(printf '%s\n' "$TOP_PROCS" \
                  | awk 'BEGIN{m=0} {if ($2+0 > m) m = $2+0} END{printf "%.2f", m/1024}')"
fi

# ── positive control (R6) — prove the ladder can reach every rung ─────────────────────────────────
# Without this, "OK" is indistinguishable from "the thresholds are unreachable". Runs the SAME
# classify function against synthetic inputs, so it tests the real code path, not a description.
#
# MAX-COMBINED, not first-match. The rungs are evaluated into a severity level and the WORST wins, so
# adding a rung can only raise a verdict. The incumbent returned on first match, which would have let
# a later-added rung be shadowed — and worse, would have made rung ORDER a silent policy decision.
classify() { # <headroom_gb> <swap_mb> [pressure_level] [max_proc_gb] → prints verdict
  local h="$1" s="$2" pl="${3:-}" mp="${4:-}" v=0 si=0
  # headroom is the ONE instrument the verdict cannot exist without (see header).
  if [ -z "$h" ]; then printf 'NO-DATA'; return 0; fi

  # rung 1 — swap in use: the hard signal, and the LAGGING one (by now it is already happening).
  if [ -n "$s" ]; then
    si="$(printf '%s\n' "$s" | cut -d. -f1)"
    case "$si" in ''|*[!0-9]*) si=0 ;; esac
    if [ "$si" -gt 0 ]; then v=2; fi
  fi

  # rung 2 — reclaimable headroom: what actually decides whether the box swaps.
  if awk -v a="$h" -v b="$ALARM_GB" 'BEGIN{exit !(a+0 < b+0)}'; then
    v=2
  elif awk -v a="$h" -v b="$WARN_GB" 'BEGIN{exit !(a+0 < b+0)}'; then
    if [ "$v" -lt 1 ]; then v=1; fi
  fi

  # rung 3 — kernel pressure level (M9-ext). Absent ⇒ SKIPPED, never NO-DATA (header).
  case "$pl" in
    ''|*[!0-9]*) : ;;
    *) if [ "$pl" -ge 4 ]; then v=2
       elif [ "$pl" -ge 2 ]; then if [ "$v" -lt 1 ]; then v=1; fi
       fi ;;
  esac

  # rung 4 — per-proc footprint outlier (M9b). WARN ceiling by design: one big process is a lead to
  # follow, not grounds to declare the box in trouble.
  if [ -n "$mp" ] && awk -v a="$mp" -v b="$PROC_WARN_GB" 'BEGIN{exit !(a+0 > b+0)}'; then
    if [ "$v" -lt 1 ]; then v=1; fi
  fi

  case "$v" in 2) printf 'ALARM' ;; 1) printf 'WARN' ;; *) printf 'OK' ;; esac
}

if [ "${CC_CAP_SELFTEST:-0}" = "1" ]; then
  fails=0
  # Every rung, in both directions, plus the three cases that are POLICY rather than arithmetic:
  # max-combine (a WARN rung must not downgrade an ALARM), an unreadable pressure level staying OK,
  # and the outlier rung being unable to reach ALARM. probe = headroom:swap:pressure:maxproc:want
  for probe in \
      "99:0:1:0:OK"       "5:0:1:0:WARN"    "1:0:1:0:ALARM"   "99:512:1:0:ALARM" ":0:1:0:NO-DATA" \
      "99:0:2:0:WARN"     "99:0:4:0:ALARM"  "99:0:1:9:WARN"   "5:0:4:0:ALARM"    "1:0:1:9:ALARM" \
      "99:0::0:OK"        "99:0:1::OK"; do
    h="${probe%%:*}";  r="${probe#*:}"
    s="${r%%:*}";      r="${r#*:}"
    pl="${r%%:*}";     r="${r#*:}"
    mp="${r%%:*}";     want="${r#*:}"
    got="$(classify "$h" "$s" "$pl" "$mp")"
    if [ "$got" = "$want" ]; then
      echo "  control OK   headroom='$h' swap='$s' pressure='$pl' maxproc='$mp' → $got"
    else
      echo "  control FAIL headroom='$h' swap='$s' pressure='$pl' maxproc='$mp' → $got (want $want)"
      fails=$((fails+1))
    fi
  done
  # The census is an instrument too, and its failure mode is a plausible-looking zero. Assert the
  # invariant a miscount breaks: the two families are disjoint, so the trees must be their exact sum.
  cs="$(census || true)"
  # shellcheck disable=SC2086  # deliberate word-split of the 3-field census output
  set -- $cs
  if [ "${1:-x}" = "$(( ${2:-0} + ${3:-0} ))" ]; then
    echo "  control OK   census trees=${1:-?} = exe ${2:-?} + bin ${3:-?} (disjoint-family sum)"
  else
    echo "  control FAIL census trees=${1:-?} != exe ${2:-?} + bin ${3:-?}"; fails=$((fails+1))
  fi
  [ "$fails" -eq 0 ] && { echo "capacity-alarm: selftest GREEN (4 rungs + no-data + census reachable)"; exit 0; }
  echo "capacity-alarm: selftest RED ($fails)" >&2; exit 70
fi

HEAD=""; COMP=""; ACT=""; WIRED=""
if [ -n "$MEM" ]; then
  # shellcheck disable=SC2086  # deliberate word-split of the 4-field python output
  set -- $MEM
  HEAD="${1:-}"; COMP="${2:-}"; ACT="${3:-}"; WIRED="${4:-}"
fi

VERDICT="$(classify "$HEAD" "${SWAP_MB:-0}" "$PRESSURE" "$MAX_PROC_GB")"
case "$VERDICT" in
  OK)      RC=0 ;;
  WARN)    RC=1 ;;
  ALARM)   RC=2 ;;
  *)       RC=3 ;;
esac

# Projected ceiling: how many MORE sessions fit in the reclaimable headroom.
#
# THE CONSTANT IS KNOWN-BIASED, AND THE BIAS DIRECTION IS THE POINT. 636 MB is the mean of summed
# per-process `ps rss`, and that instrument OVERCOUNTS because it bills every process for shared
# pages it does not exclusively own (the row that produced it retracted the derived fleet total for
# exactly this reason — see MACHINE_CAPACITY_V2 §8.5.6). A deliberately corrected constant is NOT
# substituted here: dividing by a re-derived overcount factor would invent a precision nobody
# measured, which is the failure this row keeps recording.
#
# So it is left as an UPPER BOUND on per-session cost, which makes est_room_sessions a LOWER BOUND
# on remaining capacity — i.e. the alarm under-promises headroom. For a capacity alarm that is the
# correct direction to be wrong in: it can only ever tell you there is less room than there is.
# It is never used in the VERDICT (that keys on measured reclaimable headroom and swap), only in the
# human line, and it is labelled as a floor there. Override with CC_CAP_PER_SESSION_MB if you have
# measured your own with footprint(1).
#
# Projected ceiling: how many MORE sessions fit in the reclaimable headroom, at the row's measured
# ~636 MB/session process RSS. Reported as an ESTIMATE and never used in the verdict — per-session
# RSS overcounts shared pages, so this is directional guidance for the operator, not a threshold.
#
# TWO VALUES, deliberately — `?` reads well to a human and is not JSON. The display default is the
# literal `?`, and because that is NON-EMPTY a `${ROOM:-null}` fallback in the printf below cannot
# rescue it: on the NO-DATA path (headroom unreadable) the row emitted `"est_room_sessions":?`, which
# no JSON parser accepts. The row that says "the instrument broke" was therefore the one row in the
# log that could not be read — and NO-DATA rows ARE appended, so a single blind sample poisoned the
# file for every consumer. The regex-based NO-DATA test did not catch it because matching
# `"verdict":"NO-DATA"` never requires the surrounding document to parse.
PER_MB="${CC_CAP_PER_SESSION_MB:-636}"
ROOM="?"          # human-readable
ROOM_JSON="null"  # machine-readable — must stay a JSON literal in every branch
if [ -n "$HEAD" ]; then
  ROOM="$(awk -v h="$HEAD" -v p="$PER_MB" 'BEGIN{printf "%d", (h*1024)/p}')"
  ROOM_JSON="$ROOM"
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Fields are APPEND-ONLY — every consumer of an existing key keeps working, and a row from before this
# change stays parseable. `sessions` keeps its name and gains its correct VALUE (trees across both
# families); the two per-family counts are added beside it so a future census regression is visible in
# the log itself rather than only in an aggregate that looks plausible either way.
JSON="$(printf '{"ts":"%s","verdict":"%s","sessions":%s,"headroom_gb":%s,"compressor_gb":%s,"active_gb":%s,"wired_gb":%s,"swap_used_mb":%s,"warn_gb":%s,"alarm_gb":%s,"est_room_sessions":%s,"per_session_mb_est":%s,"sessions_exe":%s,"sessions_binclaude":%s,"pressure_level":%s,"proc_warn_gb":%s,"max_proc_gb":%s,"top_procs":%s}' \
  "$TS" "$VERDICT" "$SESSIONS" "${HEAD:-null}" "${COMP:-null}" "${ACT:-null}" "${WIRED:-null}" \
  "${SWAP_MB:-0}" "$WARN_GB" "$ALARM_GB" "$ROOM_JSON" "$PER_MB" \
  "$SESSIONS_EXE" "$SESSIONS_BIN" "${PRESSURE:-null}" "$PROC_WARN_GB" "${MAX_PROC_GB:-null}" \
  "$TOP_JSON")"

if [ "$APPEND" = 1 ]; then
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  printf '%s\n' "$JSON" >> "$LOG" 2>/dev/null || true
fi

# ── page the operator on WARN/ALARM, and SELF-CLEAR on OK ─────────────────────────────────────────
# A built alarm that nothing invokes is inert, and an alarm that only logs is not an alarm — so this
# writes the repo's standard page envelope (~/.claude/autonomy/pages/<slug>.page: epoch, headline,
# detail, re-run).
#
# ONE FIXED SLUG, deliberately. Every write overwrites the same file, so a job on a 10-minute
# interval cannot accumulate 490 pages the way the unslugged channel has. Damping by construction
# rather than by a separate damper (memory notify-channel-golive-damp-first).
#
# AND IT SELF-CLEARS. On OK the page and its .notified sibling are REMOVED. This is the defect
# observed 2026-07-29 on the deploy channel: a `deploy-host-red` page from 15:35 was still on disk
# hours after the condition cleared (the lint re-ran 16/16 green), so the board reported a problem
# that no longer existed. A page whose condition has passed is misinformation, not history — the
# durable record is the jsonl log, which is append-only and keeps every sample.
# Kill switch: CC_CAP_PAGE=off.
PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
PAGE="$PAGES_DIR/capacity-alarm.page"
if [ "${CC_CAP_PAGE:-on}" != "off" ] && [ "$APPEND" = 1 ]; then
  if [ "$VERDICT" = "WARN" ] || [ "$VERDICT" = "ALARM" ]; then
    mkdir -p "$PAGES_DIR" 2>/dev/null || true
    {
      date +%s 2>/dev/null || echo 0
      printf 'capacity %s — reclaimable headroom %s GB with %s live sessions (warn <%s, alarm <%s)\n' \
        "$VERDICT" "${HEAD:-?}" "$SESSIONS" "$WARN_GB" "$ALARM_GB"
      printf 'swap used: %s MB  ·  compressor: %s GB  ·  est. room: ~%s more sessions\n' \
        "${SWAP_MB:-0}" "${COMP:-?}" "${ROOM:-?}"
      printf 'sessions: %s trees (%s claude.exe + %s .bin/claude)  ·  kernel pressure level: %s\n' \
        "$SESSIONS" "$SESSIONS_EXE" "$SESSIONS_BIN" "${PRESSURE:-unreadable}"
      # NAME the outlier. A page that says "a process is large" sends the operator hunting; the whole
      # value of the rung is arriving with the pid already identified.
      if [ -n "$MAX_PROC_GB" ] \
         && awk -v a="$MAX_PROC_GB" -v b="$PROC_WARN_GB" 'BEGIN{exit !(a+0 > b+0)}'; then
        printf 'PER-PROC OUTLIER: %s GB > %s GB floor. Top footprints:\n' "$MAX_PROC_GB" "$PROC_WARN_GB"
        printf '%s\n' "$TOP_PROCS" | awk '{ cmd = $3; for (i = 4; i <= NF; i++) cmd = cmd " " $i
                                            printf "  pid %s  %s MB  %s\n", $1, $2, cmd }'
      elif [ -n "$TOP_PROCS" ]; then
        printf 'top footprints: %s\n' "$(printf '%s\n' "$TOP_PROCS" \
          | awk '{ cmd = $3; for (i = 4; i <= NF; i++) cmd = cmd " " $i
                   printf "%s%s %s MB", (NR > 1 ? " · " : ""), cmd, $2 } END { print "" }')"
      fi
      printf 'shed by CLOSING idle sessions (/handoff them). Do NOT add a load-based spawn gate —\n'
      printf 'measured REFUSE 10/10 against real load; see docs/plans/MACHINE_CAPACITY_V2.md §8.5.7.\n'
      printf 're-run:  %s\n' "$0"
    } > "$PAGE" 2>/dev/null || true
  else
    # OK or NO-DATA ⇒ this alarm asserts nothing; retract any page we previously raised.
    # NO-DATA deliberately clears too: leaving a stale WARN up while blind would be asserting a
    # condition we can no longer see.
    rm -f "$PAGE" "$PAGE.notified" 2>/dev/null || true
  fi
fi

if [ "$QUIET" != 1 ] && [ "$WANT_JSON" != 1 ]; then
  echo "capacity-alarm — $TS"
  echo "  live sessions:          ${SESSIONS} trees   (${SESSIONS_EXE} claude.exe + ${SESSIONS_BIN} .bin/claude)"
  echo "  reclaimable headroom:   ${HEAD:-?} GB   (warn <${WARN_GB} · alarm <${ALARM_GB})"
  echo "  compressor / active:    ${COMP:-?} GB / ${ACT:-?} GB"
  echo "  kernel pressure level:  ${PRESSURE:-unreadable}   (>=2 ⇒ WARN · >=4 ⇒ ALARM · absent ⇒ rung skipped)"
  echo "  largest proc footprint: ${MAX_PROC_GB:-?} GB   (warn >${PROC_WARN_GB})"
  if [ -n "$TOP_PROCS" ]; then
    printf '%s\n' "$TOP_PROCS" | awk '{ cmd = $3; for (i = 4; i <= NF; i++) cmd = cmd " " $i
                                        printf "      pid %-7s %6s MB  %s\n", $1, $2, cmd }'
  fi
  echo "  swap used:              ${SWAP_MB:-0} MB   (>0 ⇒ ALARM, the lagging indicator)"
  echo "  est. room for:          >=${ROOM} more sessions (FLOOR: ~${PER_MB} MB/session is an rss-derived UPPER bound, so this under-promises)"
  echo "  VERDICT:                ${VERDICT}"
  if [ "$VERDICT" = "WARN" ] || [ "$VERDICT" = "ALARM" ]; then
    echo "  This alarm never refuses a spawn. Shed by CLOSING sessions (/handoff the idle ones);"
    echo "  do NOT add a load-based spawn gate — see MACHINE_CAPACITY_V2.md §8.5.7."
  fi
fi
[ "$WANT_JSON" = 1 ] && printf '%s\n' "$JSON"
exit "$RC"
