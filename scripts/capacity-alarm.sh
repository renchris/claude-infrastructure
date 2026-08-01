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
# SIX RUNGS, MAX-COMBINED (M9/M9-ext, §11.3). The verdict is the WORST rung, never the last one
# evaluated — so a new term can only ever raise the verdict, never mask an existing one:
#   1. swap in use            > 0 MB           ⇒ ALARM   (the hard, LAGGING signal)
#   2. reclaimable headroom   < ALARM_GB/WARN_GB
#   3. kernel pressure level  >= 4 / >= 2      ⇒ ALARM / WARN   (the kernel's own LEADING indicator)
#   4. per-proc phys outlier  > PROC_WARN_GB   ⇒ WARN    (the leak term; report always, gate softly)
#   5. compressor SEGMENTS    >= 70% / >= 45%  ⇒ ALARM / WARN   (the 2026-07-30 panic axis)
#   6. terminal-coalition procs >= 700 / >= 500 ⇒ ALARM / WARN  (the 2026-07-31 panic axis)
#
# WHY RUNG 6 IS NOT PART OF RUNG 4. They count different nouns, and 2026-07-31 proved the
# difference is fatal. That box died with the iTerm2 coalition at 139.5 GiB — 89.6% of all process
# memory — spread across 1,002 child processes. Rung 4 read 1.64 GB and was CORRECT: no single
# process was large. A per-process ceiling cannot see a population explosion, so the mass has to be
# counted as a population or it is not counted at all.
#
# WHAT THIS GUARD STILL CANNOT DO — stated here so its OK is not over-read. At StartInterval 600 it
# samples every 10 minutes, and the 2026-07-31 event went from healthy to unrecoverable inside ONE
# interval (the sample due mid-event never landed; the last one before the panic was 20m23s stale
# and every field in it was true when taken). Rung 6 makes the event VISIBLE; it does not make this
# sampler FAST enough to precede it. Until the cadence is adaptive, treat a green row as forensic
# evidence about 10 minutes ago, not as protection now.
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
#        CC_CAP_TOP (top(1) binary, for stubbing) · CC_CAP_SELFTEST=1 (positive control) ·
#        CC_CAP_COAL_WARN (default 500) · CC_CAP_COAL_ALARM (default 700) ·
#        CC_CAP_PS (ps(1) binary, for stubbing rung 6's tree walk)
#
# bash 3.2 safe. Ships to launchd ⇒ tested under /bin/bash.

set -uo pipefail

WARN_GB="${CC_CAP_WARN_GB:-8}"
ALARM_GB="${CC_CAP_ALARM_GB:-3}"
PROC_WARN_GB="${CC_CAP_PROC_WARN_GB:-3}"
# Compressor-segment saturation (rung 5). Deliberately low: the 2026-07-30 panic went from a cold
# compressor to 100% of segments in ~26 seconds, so a threshold set near the ceiling would fire only
# after the box was already unrecoverable. These are canary values, not capacity values.
SEG_WARN_PCT="${CC_CAP_SEG_WARN_PCT:-45}"
SEG_ALARM_PCT="${CC_CAP_SEG_ALARM_PCT:-70}"
# Terminal-coalition process population (rung 6). DERIVED, not chosen: 38 healthy CoalitionMemory
# samples of the iTerm2 coalition over the 2026-07-31 boot top out at 353 procs with ZERO above
# 400; the sample taken 4.3 min before the panic read 1002. 500/700 is 1.42x/1.98x the observed
# healthy max — no false positive in the whole series, and the fatal sample clears both. Re-derive
# before touching these (panic-iterm2-coalition-2026-07-31.md §7).
COAL_WARN="${CC_CAP_COAL_WARN:-500}"
COAL_ALARM="${CC_CAP_COAL_ALARM:-700}"
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

# ── compressor SEGMENT saturation — the term that killed the box on 2026-07-30 ────────────────────
# The 02:18:05 panic printed `watchdog timeout: no checkins from watchdogd in 92 seconds`, but the
# cause is one line further down the same panic log:
#     Compressor Info: 33% of compressed pages limit (OK) and 100% of segments limit (BAD)
# and the kernel's own memorystatus verdict at 02:15:36 was:
#     {"compressor_exhausted": 1, "zone_map_is_exhausted": 0, "swap_low": 0, "swap_exhausted": 0}
# with memorystatus_available_pages: 1310531 — i.e. TWENTY GIGABYTES STILL FREE, and swap healthy.
#
# That is precisely why this rung must exist separately from every rung above it. Headroom (rung 2),
# swap (rung 1) and kernel pressure (rung 3) ALL read healthy at the moment of death. `COMP` was
# already sampled by read_mem and printed to the log, but it never reached classify(), so the verdict
# could not see the one number that was out of range. This closes that gap.
#
# WHY SEGMENTS AND NOT COMPRESSOR SIZE. Each segment holds up to 16 compressed pages
# (segment_pages_compressed_limit / segment_limit = 26073840 / 1629615 = exactly 16.0). At the panic
# packing was 5.3/16 = 33%, so all 1,629,615 DESCRIPTORS were consumed while holding only ~41 GiB.
# Segment count is invisible to compressor size, free memory, swap and pressure — it is its own axis.
# Note the structural consequence, from this machine's own sysctls:
#     segment_limit x alloc_size = 1629615 x 81920 = 124.3 GiB  ==  vm.compressor_pool_size (exact)
# The pool is provisioned for 124.3 GiB on a 64 GiB machine, so FULLY-PACKED segments could never be
# exhausted — there is not enough RAM to fill them. Exhaustion is reachable ONLY through under-packing.
# This rung is therefore a CANARY, not a predictor: it may lead by seconds rather than minutes. It
# ships anyway because it is the only instrument that can see this failure mode at all.
#
# zprint is the ONLY live source for the in-use descriptor count — no sysctl exposes it. Column 7 is
# `cur inuse`, validated 2026-07-30 against zones with known-nonzero counts; the `cur size`/`#elts`
# columns read 0 on this build, so position 7 (not a size column) is the one to parse.
read_segments() { # → "<inuse> <limit>", or nothing when unreadable (never a fabricated 0)
  local row inuse limit
  command -v "${CC_CAP_ZPRINT:-zprint}" >/dev/null 2>&1 || return 1
  row="$("${CC_CAP_ZPRINT:-zprint}" 2>/dev/null | awk '$1=="compressor_segment"{print; exit}')"
  [ -n "$row" ] || return 1
  inuse="$(printf '%s\n' "$row" | awk '{print $7}')"
  case "$inuse" in ''|*[!0-9]*) return 1 ;; esac
  limit="$(sysctl -n vm.compressor_segment_limit 2>/dev/null)"
  case "$limit" in ''|*[!0-9]*) return 1 ;; esac
  [ "$limit" -gt 0 ] || return 1
  printf '%s %s' "$inuse" "$limit"
}

# Unreadable ⇒ SEG_PCT stays empty ⇒ rung 5 is SKIPPED, never a fabricated healthy 0 (see rung 3's
# identical policy in the header: absent instrument is SKIPPED, only headroom can produce NO-DATA).
SEG_PCT=""
if SEG_RAW="$(read_segments)"; then
  SEG_PCT="$(awk -v a="${SEG_RAW% *}" -v b="${SEG_RAW#* }" 'BEGIN{printf "%.1f", 100*a/b}')"
fi

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

# ── terminal-coalition process population (rung 6) ────────────────────────────────────────────────
# THE 2026-07-31 PANIC IS THIS RUNG. That box died with the iTerm2 coalition holding 139.5 GiB —
# 89.6% of all process memory — while iTerm2 ITSELF held 983 MB. The mass was in 1,002 child
# processes, up from 257 twelve minutes earlier. Rung 4 read 1.64 GB and was right: no SINGLE
# process was large. A per-process ceiling is blind to a population explosion BY CONSTRUCTION, which
# is why this rung cannot be folded into rung 4 — it counts a different noun.
#
# macOS rolls coalition memory up to the owning app, so the operator's out-of-memory modal blamed
# the terminal for what we launched inside it. There is no cheap per-coalition sysctl, so the live
# read walks the process tree and counts descendants of the controlling terminal app.
#
# Reports the LARGEST terminal coalition, not the sum: two terminals at 300 each is a different
# (and benign) state from one at 600, and the threshold was derived against a single coalition.
# Unreadable ⇒ prints nothing ⇒ rung SKIPPED, never a fabricated healthy 0 (rung 3's policy).
read_coalition_procs() { # → "<procs> <app>" for the largest terminal coalition, or nothing
  "${CC_CAP_PS:-ps}" -Ao pid=,ppid=,comm= 2>/dev/null | awk '
    { p = $1; pp = $2; c = $3; for (i = 4; i <= NF; i++) c = c " " $i
      sub(/.*\//, "", c)
      parent[p] = pp; pids[++np] = p
      if (c == "iTerm2" || c == "kitty" || c == "ghostty" || c == "Ghostty") root[p] = c }
    END {
      for (i = 1; i <= np; i++) {
        q = pids[i]; d = 0
        # Depth cap is a cycle guard, not a tree-depth assumption: a corrupt ppid chain must not
        # spin here. Exceeding it drops the process from the count (under-counts, never over).
        while (q != "" && q + 0 > 1 && d < 64) {
          if (q in root) { cnt[q]++; break }
          q = parent[q]; d++
        }
      }
      best = -1; bestn = ""
      for (r in root) if (cnt[r] + 0 > best) { best = cnt[r] + 0; bestn = root[r] }
      if (bestn != "") printf "%d %s\n", best, bestn
    }'
}

COAL_ROW="$(read_coalition_procs || true)"
COAL_PROCS=""; COAL_APP=""
if [ -n "$COAL_ROW" ]; then
  COAL_PROCS="${COAL_ROW%% *}"
  COAL_APP="${COAL_ROW#* }"
fi

# ── positive control (R6) — prove the ladder can reach every rung ─────────────────────────────────
# Without this, "OK" is indistinguishable from "the thresholds are unreachable". Runs the SAME
# classify function against synthetic inputs, so it tests the real code path, not a description.
#
# MAX-COMBINED, not first-match. The rungs are evaluated into a severity level and the WORST wins, so
# adding a rung can only raise a verdict. The incumbent returned on first match, which would have let
# a later-added rung be shadowed — and worse, would have made rung ORDER a silent policy decision.
classify() { # <headroom_gb> <swap_mb> [pressure_level] [max_proc_gb] [seg_pct] [coal_procs] → verdict
  local h="$1" s="$2" pl="${3:-}" mp="${4:-}" sg="${5:-}" cp="${6:-}" v=0 si=0
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

  # rung 5 — compressor SEGMENT saturation (2026-07-30 panic). Reaches ALARM, unlike rung 4: this is
  # the axis the machine actually died on, and it dies with memory and swap both reading healthy.
  # Absent instrument ⇒ SKIPPED (rung 3's policy), never a fabricated OK.
  case "$sg" in
    ''|*[!0-9.]*) : ;;
    *) if awk -v a="$sg" -v b="$SEG_ALARM_PCT" 'BEGIN{exit !(a+0 >= b+0)}'; then v=2
       elif awk -v a="$sg" -v b="$SEG_WARN_PCT" 'BEGIN{exit !(a+0 >= b+0)}'; then
         if [ "$v" -lt 1 ]; then v=1; fi
       fi ;;
  esac

  # rung 6 — terminal-coalition process population (2026-07-31 panic). Reaches ALARM: this is the
  # axis that box died on, and it died with rungs 1-5 all reading healthy 20 minutes earlier.
  # Absent instrument ⇒ SKIPPED (rung 3's policy), never a fabricated OK.
  case "$cp" in
    ''|*[!0-9]*) : ;;
    *) if [ "$cp" -ge "$COAL_ALARM" ]; then v=2
       elif [ "$cp" -ge "$COAL_WARN" ]; then if [ "$v" -lt 1 ]; then v=1; fi
       fi ;;
  esac

  case "$v" in 2) printf 'ALARM' ;; 1) printf 'WARN' ;; *) printf 'OK' ;; esac
}

if [ "${CC_CAP_SELFTEST:-0}" = "1" ]; then
  fails=0
  # Every rung, in both directions, plus the three cases that are POLICY rather than arithmetic:
  # max-combine (a WARN rung must not downgrade an ALARM), an unreadable pressure level staying OK,
  # and the outlier rung being unable to reach ALARM. probe = headroom:swap:pressure:maxproc:want
  # probe = headroom:swap:pressure:maxproc:seg:coalprocs:want
  # The rung-5 rows encode the 2026-07-30 panic directly: `99:0:1:0:100::ALARM` is the machine's
  # actual dying state — abundant headroom, zero swap, normal pressure, no outlier process, and
  # segments at 100%. Every pre-existing rung called that box HEALTHY, which is the whole point.
  #
  # The rung-6 rows do the same for 2026-07-31: `99:0:1:0::1002:ALARM` is THAT machine's dying
  # state, and `99:0:1:0::353:OK` is the highest reading of the 38 healthy samples it was derived
  # from — that row is the no-false-positive claim, executable. If a future threshold edit makes
  # 353 fire, this control goes RED rather than the fleet learning it the expensive way.
  for probe in \
      "99:0:1:0:::OK"      "5:0:1:0:::WARN"   "1:0:1:0:::ALARM" "99:512:1:0:::ALARM" ":0:1:0:::NO-DATA" \
      "99:0:2:0:::WARN"    "99:0:4:0:::ALARM" "99:0:1:9:::WARN" "5:0:4:0:::ALARM"    "1:0:1:9:::ALARM" \
      "99:0::0:::OK"       "99:0:1::::OK" \
      "99:0:1:0:100::ALARM" "99:0:1:0:70::ALARM" "99:0:1:0:45::WARN" "99:0:1:0:44::OK" \
      "99:0:1:0:0::OK"      "99:0:1:0:?::OK"     "1:0:1:0:0::ALARM"  "99:0:1:9:100::ALARM" \
      "99:0:1:0::1002:ALARM" "99:0:1:0::700:ALARM" "99:0:1:0::699:WARN" "99:0:1:0::500:WARN" \
      "99:0:1:0::499:OK"     "99:0:1:0::353:OK"    "99:0:1:0::?:OK"     "1:0:1:0::353:ALARM" \
      "99:0:1:0:100:1002:ALARM"; do
    h="${probe%%:*}";  r="${probe#*:}"
    s="${r%%:*}";      r="${r#*:}"
    pl="${r%%:*}";     r="${r#*:}"
    mp="${r%%:*}";     r="${r#*:}"
    sg="${r%%:*}";     r="${r#*:}"
    cp="${r%%:*}";     want="${r#*:}"
    got="$(classify "$h" "$s" "$pl" "$mp" "$sg" "$cp")"
    if [ "$got" = "$want" ]; then
      echo "  control OK   headroom='$h' swap='$s' pressure='$pl' maxproc='$mp' seg='$sg' coal='$cp' → $got"
    else
      echo "  control FAIL headroom='$h' swap='$s' pressure='$pl' maxproc='$mp' seg='$sg' coal='$cp' → $got (want $want)"
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
  # Rung 6's instrument has the same failure mode the census has: a plausible-looking nothing. An
  # empty read is INDISTINGUISHABLE from "no terminal is running" at the verdict, so without this
  # control a broken tree-walk would skip the rung silently and forever — the exact shape of the
  # 2026-07-31 blind spot. Assert the invariant a miscount breaks: the coalition is a SUBSET of the
  # process table, so 1 <= procs <= total. (Absent terminal ⇒ genuinely empty ⇒ reported, not failed.)
  cr="$(read_coalition_procs || true)"
  ctot="$(ps -Ao pid= 2>/dev/null | wc -l | tr -d ' ')"
  if [ -z "$cr" ]; then
    echo "  control SKIP coalition — no terminal app in the process table (instrument returned empty)"
  else
    cn="${cr%% *}"; ca="${cr#* }"
    if [ "$cn" -ge 1 ] 2>/dev/null && [ "$cn" -le "$ctot" ] 2>/dev/null; then
      echo "  control OK   coalition ${ca}=${cn} procs, within 1..${ctot} process table (subset invariant)"
    else
      echo "  control FAIL coalition ${ca}=${cn} outside 1..${ctot} — tree-walk is miscounting"
      fails=$((fails+1))
    fi
  fi
  [ "$fails" -eq 0 ] && { echo "capacity-alarm: selftest GREEN (6 rungs + no-data + census + coalition reachable)"; exit 0; }
  echo "capacity-alarm: selftest RED ($fails)" >&2; exit 70
fi

HEAD=""; COMP=""; ACT=""; WIRED=""
if [ -n "$MEM" ]; then
  # shellcheck disable=SC2086  # deliberate word-split of the 4-field python output
  set -- $MEM
  HEAD="${1:-}"; COMP="${2:-}"; ACT="${3:-}"; WIRED="${4:-}"
fi

VERDICT="$(classify "$HEAD" "${SWAP_MB:-0}" "$PRESSURE" "$MAX_PROC_GB" "$SEG_PCT" "$COAL_PROCS")"
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
JSON="$(printf '{"ts":"%s","verdict":"%s","sessions":%s,"headroom_gb":%s,"compressor_gb":%s,"active_gb":%s,"wired_gb":%s,"swap_used_mb":%s,"warn_gb":%s,"alarm_gb":%s,"est_room_sessions":%s,"per_session_mb_est":%s,"sessions_exe":%s,"sessions_binclaude":%s,"pressure_level":%s,"proc_warn_gb":%s,"max_proc_gb":%s,"seg_pct":%s,"seg_warn_pct":%s,"seg_alarm_pct":%s,"coal_procs":%s,"coal_app":"%s","coal_warn":%s,"coal_alarm":%s,"top_procs":%s}' \
  "$TS" "$VERDICT" "$SESSIONS" "${HEAD:-null}" "${COMP:-null}" "${ACT:-null}" "${WIRED:-null}" \
  "${SWAP_MB:-0}" "$WARN_GB" "$ALARM_GB" "$ROOM_JSON" "$PER_MB" \
  "$SESSIONS_EXE" "$SESSIONS_BIN" "${PRESSURE:-null}" "$PROC_WARN_GB" "${MAX_PROC_GB:-null}" \
  "${SEG_PCT:-null}" "$SEG_WARN_PCT" "$SEG_ALARM_PCT" \
  "${COAL_PROCS:-null}" "${COAL_APP:-}" "$COAL_WARN" "$COAL_ALARM" \
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
  # SKIPPED, not "0%" — an unreadable zprint must never render as a healthy reading (2026-07-30).
  echo "  compressor segments:    ${SEG_PCT:-SKIPPED (zprint unreadable)}${SEG_PCT:+% of limit  (warn ${SEG_WARN_PCT}% / alarm ${SEG_ALARM_PCT}%)}"
  echo "  kernel pressure level:  ${PRESSURE:-unreadable}   (>=2 ⇒ WARN · >=4 ⇒ ALARM · absent ⇒ rung skipped)"
  echo "  largest proc footprint: ${MAX_PROC_GB:-?} GB   (warn >${PROC_WARN_GB})"
  # SKIPPED, not "0" — an unreadable ps must never render as an empty, healthy-looking coalition.
  echo "  terminal coalition:     ${COAL_PROCS:-SKIPPED (ps unreadable)}${COAL_PROCS:+ procs in ${COAL_APP}  (warn >=${COAL_WARN} / alarm >=${COAL_ALARM})}"
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
