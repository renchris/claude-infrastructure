#!/bin/bash
# compressor-sentinel.sh — the one sensor that cannot be starved, for the thing that keeps killing
# this box: VM-compressor SEGMENT exhaustion (three kernel panics in six days, 2026-07-30 → 08-05).
#
# WHY A NEW DAEMON RATHER THAN ANOTHER RUNG ON capacity-alarm.sh
# (docs/research/panic-compressor-2026-08-05.md §5 — the sensor postmortem):
#   · EVERY existing rung read a HEALTHY box at death. 20 GB free, swap idle, pressure normal, and
#     the kernel's own memorystatus verdict already `"compressor_exhausted": 1`. Headroom, swap and
#     pressure are not slow versions of this signal — they are blind to it.
#   · The one instrument that CAN see the descriptor count, `zprint`, HANGS under the very storm it
#     measures (the 00:14 run was still TH_WAIT at panic). So it is banned from the tick here.
#     §7.7's cheap-sysctl recipe replaces it: in-core segments ≈ vm_stat "Pages occupied by
#     compressor" ÷ (segment_buffer / pagesize), swapped segments = vm.swapusage used ÷ 65536
#     (EXACT — swap is allocated in 64 KiB compressed chunks). Their sum tracks c_segment_count.
#   · capacity-alarm.sh runs at ProcessType Adaptive on a 60 s StartInterval. That is right for a
#     capacity report and wrong for this: §6 discriminator 4 records that the background-band
#     sampler's own DEATH — the absence of its row — was the earliest machine-readable distress
#     signal in all three events, firing ~3 min before the wedge. A sampler that dies during the
#     event cannot be the guard for the event. Hence: internal loop, no launchd band, no ProcessType.
#
# WHY IT KEYS ON RATE, NOT ON A CEILING (§4a). The kernel's own edge signal fires at 98% of the
# segment limit, which at the measured ramp is SEVEN POINT SIX SECONDS of warning. Any actuator keyed
# on the ceiling is too late by construction. The trip is therefore level AND rate (>15% of limit with
# >600 segments/s), or a byte-rate burst — far below the ceiling, on the way up.
#
# WHY IT CAN ACT (§7.2). Detection alone saved nothing three times. The actuator SIGSTOPs the burst
# cohort — newest node workers, never claude.exe, never anything claude/mcp-shaped. SIGSTOP removes
# the demand instantly, is reversible, and cannot lose work; a frozen worker is recoverable, a
# panicked box is not. It is DEFAULT OFF and arms only on CC_SENTINEL_ACT=stop.
#
# WHY IT ALSO BREAKS THE PARENT (§7, crash-rootcause-2026-08-09). Freezing the cohort alone does not
# end the storm, because the thing MINTING it is not in the cohort. The 03:39 panic's 700 node procs
# were `postcss.js` workers of ONE `next-server` (pid 36923) whose comm is not `^node`, so the cohort
# test cannot reach it — and the cooldown is 60 s, which is a spawner's whole working day at the
# measured rate. So after the cohort is chosen, any eligible parent owning enough of it is SIGSTOPped
# FIRST, then the children. Same signal, same reversibility, same exclusions (never claude/mcp-shaped,
# never pid ≤ 1, never this daemon or its launcher).
#
# WHY NO KILL PATH EXISTS ANYWHERE IN HERE (§4a). macOS ships CONFIG_JETSAM off; the release-kernel
# compressor-exhaustion branch can only harvest IDLE-band processes (measured: ~2 MB of Apple
# daemons), and no_paging_space_action needs ONE process holding >50% of the whole compressor
# (>66 GiB) — structurally untrippable by a fleet of 200 MB workers. Nothing above us will act. That
# is why this exists, and it is also why it must never SIGKILL: we are the only actor, so we must be
# the reversible one.
#
# THE INSTRUMENT'S OWN FAILURE MODES, handled explicitly rather than assumed away:
#   · An unreadable trip-bearing sysctl SKIPS THE TICK — no row. It never renders as 0. This is the
#     exact defect capacity-alarm.sh ate on its launchd PATH (a dead rung reporting the healthy
#     value); "could not measure" must never read as "fine".
#   · Rates divide by MEASURED elapsed seconds, never by the configured interval. Under the storm
#     this exists to catch, a 10 s sleep takes far longer — dividing a 25 s delta by 10 would
#     manufacture a 2.5x trip out of an unchanged machine. The instrument must not invent its subject.
#   · A skipped or stretched tick RESETS the two-consecutive-tick streak. Consecutiveness asserted
#     across a gap is a fabrication.
#   · THE SNAPSHOT NAMES WHAT IT RANKS. Its first shape could not: an argv list cut at `head -80`
#     (truncated in 16 of 18 trips) beside a COMM-only top-30, which renders every Node workload as
#     `node`. Joining the two by pid still left 1-8 of the LARGEST rows unidentified at every trip,
#     so no count of `tsc` — zero or four — could be read off it, and two successive analyses read a
#     confident "tsc = 0" that was an artifact first of the cut and then of the column. An instrument
#     that fires 18 times in an incident without naming its subject is how an unverified cause gets
#     filed. Rank by RSS FIRST, then print the full argv of the rows that ranked (§7-bis(b) of
#     docs/research/machine-lag-and-kitty-2026-08-06.md).
#
# Verdict-free by design: this is a daemon, not a reporting command. It exits 0 on clean shutdown,
# 64 on a usage error, 3 when it cannot read the machine at all on the very first tick.
#
# Seams:  CC_SENTINEL=off (kill switch) · CC_SENTINEL_INTERVAL (10) · CC_SENTINEL_TRIP_SEG_RATE (600)
#         CC_SENTINEL_TRIP_SEG_PCT (15) · CC_SENTINEL_TRIP_CBU_MB (640) · CC_SENTINEL_TRIP_SWAP_MB
#         (1024) · CC_SENTINEL_COOLDOWN (60) · CC_SENTINEL_CENSUS_EVERY (6) · CC_SENTINEL_LOG
#         (moves the snap log with it) · CC_SENTINEL_SNAP · CC_PAGES_DIR · CC_SENTINEL_ACT=stop
#         CC_SENTINEL_ACT_RSS_KB (102400) · CC_SENTINEL_ACT_CAP (200) · CC_SENTINEL_ACT_PARENT
#         (on — the parent-breaker's OPT-OUT; it rides CC_SENTINEL_ACT=stop, see below) ·
#         CC_SENTINEL_ACT_PARENT_MIN (3) · CC_SENTINEL_ACT_PARENT_CAP (4) ·
#         CC_SENTINEL_SNAP_TOPN (30) · CC_SENTINEL_SNAP_TOPN_FUP (10) · CC_SENTINEL_SNAP_ARGV_MAX
#         (400) · CC_SENTINEL_SNAP_AGG_N (15)
set -uo pipefail

INTERVAL="${CC_SENTINEL_INTERVAL:-10}"
TRIP_SEG_PCT="${CC_SENTINEL_TRIP_SEG_PCT:-15}"
TRIP_SEG_RATE="${CC_SENTINEL_TRIP_SEG_RATE:-600}"
TRIP_CBU_MB="${CC_SENTINEL_TRIP_CBU_MB:-640}"
TRIP_SWAP_MB="${CC_SENTINEL_TRIP_SWAP_MB:-1024}"
COOLDOWN="${CC_SENTINEL_COOLDOWN:-60}"
CENSUS_EVERY="${CC_SENTINEL_CENSUS_EVERY:-6}"
LOG="${CC_SENTINEL_LOG:-$HOME/.claude/logs/compressor-sentinel.jsonl}"
# The snap log DERIVES from LOG so one override moves both — a test that redirects only the JSONL
# would otherwise still append trip snapshots to the operator's live logs.
SNAP="${CC_SENTINEL_SNAP:-${LOG%.jsonl}-snap.log}"
# The freeze ledger DERIVES from LOG for the same reason SNAP does, and here the stake is higher
# than tidiness: this file is the ONLY record of which pids this daemon owes a SIGCONT to. A test
# that redirected the JSONL but not the ledger would append the operator's live cohort with its
# fixtured pids, and the next real release would then skip them as pid-reuse mismatches.
FROZEN_DB="${CC_SENTINEL_FROZEN_DB:-${LOG%.jsonl}-frozen.tsv}"
PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
PAGE="$PAGES_DIR/compressor-sentinel.page"
ACT="${CC_SENTINEL_ACT:-off}"
ACT_RSS_KB="${CC_SENTINEL_ACT_RSS_KB:-102400}"   # 100 MB — below this a worker is not the burst
ACT_CAP="${CC_SENTINEL_ACT_CAP:-200}"
# The parent-breaker RIDES CC_SENTINEL_ACT=stop rather than taking an arm of its own, and that is a
# deliberate reversal of this file's opt-in habit. The live job is already armed by an export inside
# launchd/com.claude.compressor-sentinel.plist's wrapper; a second, separately-defaulted-off flag
# would ship the mechanism INERT on the one box it was written for, and its absence would be
# invisible — the trip snapshot would look exactly as it does today. So this is an OPT-OUT
# (CC_SENTINEL_ACT_PARENT=off), the arming decision stays the single one the operator already made,
# and the snapshot prints a parent-break verdict on EVERY armed trip, including "none".
ACT_PARENT="${CC_SENTINEL_ACT_PARENT:-on}"
ACT_PARENT_MIN="${CC_SENTINEL_ACT_PARENT_MIN:-3}"   # burst children a parent must own to be a spawner
ACT_PARENT_CAP="${CC_SENTINEL_ACT_PARENT_CAP:-4}"   # most spawners frozen per trip, biggest first
# The unfreeze arm's two bounds. HOLD_MIN matches COOLDOWN by construction so a release can never
# land inside the ramp the freeze interrupted; HOLD_MAX is the ceiling past which an unreleased
# freeze is treated as the incident rather than the remedy (see the release policy above the arm).
HOLD_MIN_S="${CC_SENTINEL_HOLD_MIN_S:-60}"
HOLD_MAX_S="${CC_SENTINEL_HOLD_MAX_S:-600}"
FOLLOWUP_N="${CC_SENTINEL_FOLLOWUP_N:-12}"       # 12 x 5 s = the 60 s cooldown, by construction
FOLLOWUP_SEC="${CC_SENTINEL_FOLLOWUP_SEC:-5}"
SNAP_TOPN="${CC_SENTINEL_SNAP_TOPN:-30}"         # trip snapshot: how many RSS ranks carry full argv
SNAP_TOPN_FUP="${CC_SENTINEL_SNAP_TOPN_FUP:-10}" # each follow-up sample: same shape, tighter (x12)
SNAP_ARGV_MAX="${CC_SENTINEL_SNAP_ARGV_MAX:-400}" # per-ROW argv cap in chars; 0 = uncapped
SNAP_AGG_N="${CC_SENTINEL_SNAP_AGG_N:-15}"       # executables in the coarse by-executable total
TICKS=0                                          # 0 = run forever; >0 bounds a smoke/test run

# ── PANIC ATTRIBUTION (master 66ef300dd0b4 — "the next death is attributable") ─────────────────
# WHAT IS MISSING TODAY. When this box dies, nothing survives to say WHY. Measured 2026-08-09:
#   · A kernel panic writes NO crash row at all. hooks/lead-crash-watchdog.sh writes the ledger
#     from a daemon that the panic kills with everything else — the ledger's last row is 04:03:39,
#     fifteen minutes BEFORE panic #6 at 04:18:59, and there is nothing after it.
#   · 132 of 171 rows in claude-crashes.jsonl read cause:"abrupt-unknown" with an empty
#     stderr_log — 77% unattributed, because the two things it joins on (a close-record and a
#     stderr file) are both written by processes a group SIGKILL takes down first.
#   · The kernel DID write the answer, and nothing in this repo has ever read it. A repo-wide grep
#     for `.panic` finds no parser: jetsam_near_death() globs JetsamEvent-*.ips only. Meanwhile
#     panic-full-2026-08-09-034124 carries the verdict in its first lines — "Compressor Info: 32%
#     of compressed pages limit (OK) and 100% of segments limit (BAD) with 66 swapfiles" — and a
#     per-process table below them: 780 "node, 13 "claude.exe, 1 "WindowServer. That is the
#     culprit, named and counted, by the kernel, at the moment of death.
#   · And macOS is deleting it. Five panics have occurred; THREE files remain — the Jul-30/31 pair
#     has already rotated away, and docs/research/crash-rootcause-2026-08-09.md §5.3 predicted
#     exactly that. So the evidence for the 5th panic will be gone before anyone asks about the 6th.
#
# WHAT THIS DOES. One bounded read of the newest panic report at STARTUP, distilled to one JSONL
# row in a store WE own. It never re-records the same panic (keyed on the report's own basename),
# so it is idempotent across restarts and its ledger is a panic history, not a boot history.
#
# WHY AT STARTUP OF *THIS* DAEMON, AND NOT A NEW JOB. A panic reader is only ever useful in the
# minutes after a reboot, and this is the only instrument on the box guaranteed to run then:
# com.claude.compressor-sentinel is KeepAlive + RunAtLoad, so it starts before anything else this
# repo owns. A dedicated launchd job would need a C10 operator step and would sit in the
# pending-activation queue where such things rot — the inertness generator. An edit to a file that
# already runs rides its existing per-file symlink and goes live on the trunk fast-forward.
#
# WHY IT IS SAFE AT STARTUP. It is read-only, bounded (head -c on a 6.5 MB report, never a full
# scan), wrapped so any failure is recorded rather than raised, and it can never delay the loop by
# more than one bounded read. A post-mortem that could stop the sensor from starting would be
# trading the next death's evidence for this one's.
#
# THE STATES ARE KEPT DISTINCT, because "no panic" and "could not read one" are different facts and
# a single value for both is what makes a blind sensor read healthy (memory:
# sensor-default-off-makes-blindness-the-shipping-path):
#   scanned    a panic was found, parsed, and recorded
#   already    the newest panic is already in our ledger — nothing to do
#   none       the panic directory is readable and holds no report: genuinely no panic
#   unreadable the directory or file could not be read — we do NOT know, and say so
PANIC_DIRS="${CC_PANIC_DIRS:-/Library/Logs/DiagnosticReports}"
PANIC_LEDGER="${CC_PANIC_LEDGER:-$HOME/.claude/logs/panic-attribution.jsonl}"
PANIC_SCAN="${CC_PANIC_SCAN:-on}"
# THE BOUND MUST COVER THE WHOLE TABLE OR THE CENSUS INVERTS. Sized at 2 MB first, on the reasoning
# that "the table is well inside it". Measured against the live 6.5 MB report, that bound returned
# `bash=33 node=21` — i.e. it named BASH as the top process, when the true full-file census is
# node=780, xpcproxy=152, bash=90, claude.exe=13. The truncation does not degrade the answer, it
# REVERSES it, and a reversed culprit is worse than no culprit. macOS caps a panic report well under
# this, so the bound is a runaway guard rather than a working limit — and when it IS reached, the
# census says so in census_source rather than quietly reporting a biased ranking.
PANIC_HEAD_BYTES="${CC_PANIC_HEAD_BYTES:-16000000}"
TICKS_PANIC_ONLY=0

# ── FREEZE ATTRIBUTION (2026-08-13 — the deaths that write NO panic file) ─────────────────────────
# THE GAP THIS CLOSES. panic_scan globs `*.panic`. On 2026-08-13 21:22:39 this box wedged hard
# during active use and the operator recovered it by HOLDING THE POWER BUTTON 80 minutes later.
# A forced power-off is a power cut from software's point of view: no panic string is written, no
# SOCD data is stored (`DumpPanic` read the NVMe panic region at the next boot and found it all
# zeros), and so panic_scan correctly reported `none` and the ledger recorded NOTHING. The single
# worst stability event since the compressor panics left no row in the store built to make the next
# death attributable, and re-deriving it by hand cost a whole session of log forensics.
#
# WHY A SIBLING READER AND NOT A WIDER GLOB. There is no file to widen the glob to. The panic
# path's evidence is a report; this path's evidence is the ABSENCE of one, plus the machine's own
# record that a human had to intervene physically. Different artifacts, read different ways — so
# different functions writing different `kind`s into the one ledger.
#
# THE SIGNAL, AND WHY NOBODY CAN FAKE IT. macOS writes `ResetCounter-*.diag` on an abnormal boot,
# carrying a `Boot faults:` line straight from the PMU. This box holds one verified sample of each
# class and they discriminate cleanly:
#     2026-08-13 (freeze, forced restart) → `Boot faults: btn_rst,finger_reset force_off`
#     2026-08-09 (watchdog panic #6)      → `Boot faults: wdog,reset_in1`
# `force_off`/`btn_rst` IS the power button. It is the hardware's own record that the OS stopped
# answering and a person reached for the case — self-reported by nobody, which is exactly the
# property every other rung in this repo has to work for. `wdog` always pairs with a panic report,
# so that branch DEFERS to panic_scan rather than recording one death as two incidents.
#
# WHY THE .diag OUTRANKS THE SYSCTL. `kern.shutdownreason` on this box reads
# `btn_rst,finger_reset force_off ap_panic` — it carries an `ap_panic` token on a boot where no
# panic occurred and none was recoverable, so classifying on the sysctl alone would have called
# tonight's freeze a panic. The dated `.diag` is per-incident, has a verified sample of BOTH
# classes, and does not carry that token. The sysctl stays as a fallback for when no .diag exists,
# and BOTH are recorded raw so a later reader can re-adjudicate instead of inheriting this reading
# (memory: read-the-diff-not-the-commit-subject).
#
# WHAT MAKES THE ROW WORTH HAVING: THE DARK WINDOW. A freeze's whole difficulty is that the
# evidence stops. But the samplers' LAST ROW is the pre-freeze state and it survives — on
# 2026-08-13 capacity-alarm's final tick (04:22:39Z, to the second) carried load_1m 13.11 (up from
# 9.35), ptys_used 9 (down from 16) and active_gb 13.79 (down 5.4 GB in 63 s): a mass session
# teardown under a load spike, which is the only description of the trigger that exists anywhere.
# So the row records where the darkness STARTS, how long it ran, and that last tick verbatim. §6
# discriminator 4 already established the sampler's own death as the earliest machine-readable
# distress signal on this box; this reads it deliberately instead of by hand, once, after the fact.
#
# THE STATES ARE KEPT DISTINCT, for panic_scan's reason — "the last shutdown was clean" and "I
# could not tell" must never share a value:
#   freeze     a forced power-off with no panic for this boot — recorded
#   watchdog   the watchdog fired; panic_scan owns the detail — no row, deliberately
#   clean      an abnormal-boot record was looked for and genuinely does not exist
#   already    this boot is in the ledger — idempotent across daemon restarts
#   unreadable the boot identity could not be read — we do NOT know, and say so (rc 3)
FREEZE_SCAN="${CC_FREEZE_SCAN:-on}"
# Colon-separated. Defaults to the two samplers that tick fast enough to bound a freeze: the 60 s
# capacity report and this daemon's own 10 s loop. An absent or unreadable file is NAMED in
# sampler_source rather than silently skipped.
FREEZE_SAMPLERS="${CC_FREEZE_SAMPLERS:-$HOME/.claude/logs/capacity-alarm.jsonl:${CC_SENTINEL_LOG:-$HOME/.claude/logs/compressor-sentinel.jsonl}}"
FREEZE_RESET_DIRS="${CC_FREEZE_RESET_DIRS:-$PANIC_DIRS}"
# A fixed cost. The samplers tick at 60 s and 10 s, so 400 rows is hours of tail — and at daemon
# startup every row in the file is pre-boot anyway. A runaway guard, not a working limit.
FREEZE_TAIL_ROWS="${CC_FREEZE_TAIL_ROWS:-400}"
# A ResetCounter is written seconds AFTER the boot it describes (measured: boot 22:42:29, file
# 22:43:17), so the match window opens before boottime rather than at it.
FREEZE_RESET_SLACK_S="${CC_FREEZE_RESET_SLACK_S:-120}"
TICKS_FREEZE_ONLY=0

while [ $# -gt 0 ]; do
  if   [ "$1" = "--ticks" ]; then
    TICKS="${2:-}"
    case "$TICKS" in ''|*[!0-9]*) echo "compressor-sentinel.sh: --ticks needs a non-negative integer" >&2; exit 64 ;; esac
    shift
  elif [ "$1" = "--once" ];  then TICKS=1
  elif [ "$1" = "--panic-scan" ]; then TICKS_PANIC_ONLY=1
  elif [ "$1" = "--freeze-scan" ]; then TICKS_FREEZE_ONLY=1
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0
  else echo "compressor-sentinel.sh: unknown arg '$1'" >&2; exit 64
  fi
  shift
done

if [ "${CC_SENTINEL:-on}" = "off" ]; then
  echo "compressor-sentinel: disabled (CC_SENTINEL=off)" >&2
  exit 0
fi

# A non-numeric snapshot seam must never reach awk: there `-v n=abc` becomes 0, an n of 0 renders an
# EMPTY attribution section, and a typo in an env var would silently restore the exact blindness the
# snapshot exists to remove — a section that looks rendered and names nothing. Refuse at startup the
# same way --ticks does, rather than run blind.
# It checks the ENV NAMES, not the internals they feed, so the message names the thing the operator
# can actually act on — an error reading `SNAP_TOPN` sends them looking for a variable that does not
# exist on their side. An unset seam is skipped: the default above already applied, and the defaults
# are numeric by construction.
for _v in CC_SENTINEL_SNAP_TOPN CC_SENTINEL_SNAP_TOPN_FUP CC_SENTINEL_SNAP_ARGV_MAX CC_SENTINEL_SNAP_AGG_N; do
  _x="${!_v:-}"
  [ -n "$_x" ] || continue
  case "$_x" in *[!0-9]*)
    printf 'compressor-sentinel.sh: %s must be a non-negative integer (got "%s")\n' "$_v" "$_x" >&2
    exit 64 ;;
  esac
done

# ── readers ───────────────────────────────────────────────────────────────────────────────────────
# Every one of these returns NON-ZERO rather than a value when the instrument is unreadable. None of
# them has a fallback. That is the whole contract.

# One numeric sysctl. rc 1 when absent, empty, or non-numeric — never a fabricated 0.
read_num_sysctl() { # <name>
  local v
  v="$(sysctl -n "$1" 2>/dev/null)" || return 1
  case "$v" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$v"
}

# vm.swapusage → USED BYTES. Parsed from the unit suffix, never assumed to be M: this is the exact
# term §7.7 calls the swapped-segment count (used ÷ 65536), so a silent 1024x misread here would
# understate the half of the pool that lives on disk.
parse_swap_used_bytes() { # stdin: a vm.swapusage line
  awk '
    { for (i = 1; i < NF; i++) if ($i == "used") { v = $(i + 2); break } }
    END {
      if (v == "") exit 1
      u = substr(v, length(v)); n = substr(v, 1, length(v) - 1) + 0
      m = (u == "G") ? 1073741824 : (u == "M") ? 1048576 : (u == "K") ? 1024 : 0
      if (m == 0) exit 1
      printf "%.0f", n * m
    }'
}

read_swap_used_bytes() {
  local raw
  raw="$(sysctl -n vm.swapusage 2>/dev/null)" || return 1
  [ -n "$raw" ] || return 1
  printf '%s\n' "$raw" | parse_swap_used_bytes
}

# ONE vm_stat pass → "<pagesize> <pages_occupied_by_compressor> <compressions> <decompressions>".
# Page size comes from vm_stat's OWN header and is never assumed to be 4096 (it is 16384 on Apple
# silicon; assuming 4096 understates by 4x — capacity-alarm.sh:147 records the same trap).
read_vm_stat() {
  vm_stat 2>/dev/null | awk -F: '
    NR == 1 {
      if (match($0, /page size of [0-9]+/)) { s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); pg = s + 0 }
      next
    }
    {
      k = $1; v = $2
      gsub(/^[ \t]+|[ \t.]+$/, "", v); gsub(/"/, "", k)
      if (v ~ /^[0-9]+$/) d[k] = v + 0
    }
    END {
      if (pg <= 0) exit 1
      if (!("Pages occupied by compressor" in d) || !("Compressions" in d) || !("Decompressions" in d)) exit 1
      printf "%d %d %d %d", pg, d["Pages occupied by compressor"], d["Compressions"], d["Decompressions"]
    }'
}

# ── segment arithmetic (§7.7) ─────────────────────────────────────────────────────────────────────
# The divisor is DERIVED (segment_buffer ÷ pagesize), not the literal 4. Four is only correct at a
# 16 KiB page size — true on this box (65536/16384), false on a 4 KiB one, where the right answer is
# 16 and the literal would understate in-core segments by 4x.
segs_in_core() { # <pages_occupied> <pagesize> <segment_buffer_size>
  awk -v p="$1" -v pg="$2" -v buf="$3" 'BEGIN {
    if (pg <= 0 || buf <= 0 || buf < pg) exit 1
    printf "%d", p / (buf / pg)
  }'
}

# EXACT, not an estimate: swap is allocated in one-segment (64 KiB) compressed chunks.
segs_swapped() { # <swap_used_bytes> <segment_buffer_size>
  awk -v b="$1" -v buf="$2" 'BEGIN { if (buf <= 0) exit 1; printf "%d", b / buf }'
}

# ── the trip predicate ────────────────────────────────────────────────────────────────────────────
# Prints the breach reason and returns 0 when THIS SAMPLE breaches; rc 1 when clear. Pure: every
# threshold arrives as a variable, so the suite can drive it without a machine.
#
# All three arms are RATES normalised to the configured interval. The brief's "640 MB/tick" and
# "1 GB/tick" are 64 MB/s and 102.4 MB/s at the 10 s default — which is exactly how §7.1 states the
# ramp ("on ramp (>64 MB/s sustained)"). Comparing raw per-tick deltas would let a tick stretched by
# the storm manufacture a trip on an unchanged machine.
classify_breach() { # <seg_est> <seg_limit> <seg_rate_per_s> <dcbu_bytes_per_s> <dswap_bytes_per_s>
  awk -v seg="$1" -v lim="$2" -v rate="$3" -v dcbu="$4" -v dswap="$5" \
      -v pct="$TRIP_SEG_PCT" -v rmin="$TRIP_SEG_RATE" -v cmb="$TRIP_CBU_MB" -v smb="$TRIP_SWAP_MB" \
      -v iv="$INTERVAL" '
    BEGIN {
      if (iv <= 0) exit 1
      n = 0; why = ""
      # Level AND rate. Level alone is a standing state (this box idles well under 15%); rate alone
      # fires on every benign build. §6 discriminator 1+2: it is the conjunction that has no observed
      # benign counterpart in 102 h.
      if (lim > 0 && seg > lim * pct / 100 && rate > rmin) { why = "seg"; n++ }
      if (dcbu  > cmb * 1048576 / iv) { why = why (n ? "+" : "") "cbu";  n++ }
      if (dswap > smb * 1048576 / iv) { why = why (n ? "+" : "") "swap"; n++ }
      if (n == 0) exit 1
      print why
    }'
}

# ── the executable-name table: the ONE place a process is named ───────────────────────────────────
# → "<pid> <ppid> <rss_kb> <exe_basename>" for EVERY process. Three consumers — the census, the
# actuator's cohort test, and the parent-breaker's protection list — so "is this thing node" is
# decided once, here, and never re-spelled per caller.
#
# WHY THE COMM MUST BE REBUILT TO END-OF-LINE. `ps -o comm=` prints the executable's FULL path, and
# on this box node lives at `…/Library/Application Support/fnm/node-versions/…/bin/node`. `$4` is one
# WHITESPACE-split field, so that path's basename read `Application`, failed `^node`, and the row was
# dropped — census n=0 while 12,105 of 55,631 rows were node (docs/research/
# mcp-memory-groundup-2026-08-10/01-census-trees.md §7 item 5). Rebuilding $4..NF is exact HERE and
# only here, because `comm=` is the LAST column in this read and nothing follows it to swallow.
#
# WHY THE BASENAME'S SPACES BECOME UNDERSCORES. A basename can itself contain spaces (`Razer
# Elevation Service`, 41 of 1224 live rows). Emitting it raw would make this table's own 4th field
# ambiguous for every consumer below — the same defect one layer down. `_` cannot appear in a name
# this file tests for, so collapsing is lossless for every decision made on it.
exe_table() {
  ps -axwwo pid=,ppid=,rss=,comm= 2>/dev/null | awk '
    $1 ~ /^[0-9]+$/ {
      comm = $4; for (i = 5; i <= NF; i++) comm = comm " " $i
      n = split(comm, p, "/"); base = p[n]
      gsub(/[[:space:]]+/, "_", base)
      print $1, $2, $3, base
    }'
}

# ── node census (every CENSUS_EVERY ticks) ────────────────────────────────────────────────────────
# → "<node_count> <orphans> <node_rss_mb>|<pid pid ...>". The pid list is what makes the actuator
# able to say "new since 60 s ago" — the burst cohort — instead of stopping the whole fleet.
census() {
  exe_table | awk '
    $4 ~ /^node/ {
      c++; rss += $3; if ($2 == 1) orph++
      pids = pids " " $1
    }
    END { printf "%d %d %d|%s", c + 0, orph + 0, rss / 1024, pids }'
}

# ── actuator target selection ─────────────────────────────────────────────────────────────────────
# stdin: `ps -axwwo pid=,ppid=,rss=,args=`; <exe_file> is one `exe_table` capture taken immediately
# before it. Prints "<pid> <rss_kb> <exe_basename>" per line, capped.
#
# WHY THE NAME COMES FROM A SECOND READ, when the comment this replaces insisted on one table.
# `ps` gives a column its FULL value only when that column is LAST — measured 2026-08-11, in
# `pid=,ppid=,rss=,comm=,args=` the comm column is truncated to a FIXED 16 characters
# (`/Users/chrisren/`, `/Library/Applica`, `endpointsecurity` — all exactly 16). A basename is
# therefore not merely space-split in that stream, it is ABSENT: every real node install is a path
# longer than 16 characters, so `base` was `` or `bi` and the cohort test could match nothing but a
# process whose comm was literally the short string `node`. argv[0] is no escape either — it carries
# the same spaced path and splits identically. comm-last and args-last cannot both hold in one read,
# so the split is drawn where it costs least:
#   · ARGS stays last, so every exclusion below reads a complete argv. These are the safety rails;
#     a truncated argv is how an operator's session gets frozen.
#   · PARENTAGE stays in this one table too — that is what the old comment was really protecting
#     (a ppid attributed from a later read can name a recycled pid), and select_break_parents still
#     takes its ppid column from here.
#   · Only the NAME comes from the adjacent read, and it can only ever REMOVE a process from the
#     cohort: a pid that is stale by the time this table is read simply has no row here to select.
#
# Deliberately UNDER-inclusive: the cohort test is the EXECUTABLE NAME (comm basename ~ /^node/),
# never the argv. Matching argv would sweep in any shell whose command line merely mentions node, and
# the cost asymmetry is total — a missed worker costs one more tick of ramp, a wrongly-stopped
# process costs the operator's session. For the same reason claude.exe/claude and anything
# claude/mcp-shaped are excluded twice over (name and args), even though the name filter alone
# already excludes claude.exe.
#
# THE MCP EXCLUSION IS A CLASS TEST, NOT A SPELLING. `args ~ /mcp/` was a substring denylist, and it
# had never had to be right: with the cohort test blind, nothing reached it. Repairing the name
# RE-ARMS this predicate against the whole live population at once, so it now matches mcp as a TOKEN
# at any of the separators a real command line uses, plus the protocol's own full name — the class,
# not the four spellings someone happened to think of (memory denylist-enumerates-spellings).
#
# THE RECYCLE GUARD. A second read is a second instant, and the hazard it opens is a pid that named
# one process in the exe table and a different one here. Both tables carry PPID, so the two rows have
# to agree on it before the name is believed; they are taken back-to-back, so a healthy process
# agrees trivially, while the one case this exists for — a pid reused between the reads — has to
# reproduce its predecessor's parent to get through. UNIDENTIFIABLE ⇒ NEVER ACTED ON is the polarity
# throughout: absent from the exe table, or disagreeing with it, means not a target here (and, in
# select_break_parents, PROTECTED — there the same ignorance means the claude/claude.exe name test
# cannot be applied, so the only safe reading is that it might be one).
select_stop_targets() { # <exe_file> <prev_census_pids> <rss_floor_kb> <cap>
  awk -v prev=" $2 " -v floor="$3" -v cap="$4" '
    NR == FNR { if ($1 ~ /^[0-9]+$/) { base[$1] = $4; eppid[$1] = $2 } next }
    $1 ~ /^[0-9]+$/ {
      pid = $1; rss = $3 + 0
      args = ""; for (i = 4; i <= NF; i++) args = args " " $i
      if (!(pid in base)) next                        # named by no exe_table row ⇒ never a target
      if (eppid[pid] != $2) next                      # the two reads disagree on its parent ⇒ ditto
      b = base[pid]
      if (b !~ /^node/) next
      if (b == "claude.exe" || b == "claude") next
      if (args ~ /claude/) next
      if (args ~ /(^|[\/ _-])mcp([-_\/ @.]|$)|modelcontextprotocol/) next
      if (rss <= floor) next
      if (index(prev, " " pid " ") > 0) next          # present at the last census ⇒ not the burst
      if (++k > cap) exit
      printf "%s %s %s\n", pid, rss, b
    }' "$1" -
}

# ── parent-breaker: the spawner is not in the cohort ──────────────────────────────────────────────
# stdin: the SAME `ps -axwwo pid=,ppid=,rss=,args=` table the cohort was selected from, and the SAME
# <exe_file>. Prints "<pid> <burst_children> <exe_basename>" per eligible spawner, ranked, capped.
#
# WHY A SPAWNER NEEDS ITS OWN SELECTOR. `select_stop_targets` is keyed on comm `^node`, and the
# thing minting the horde is by observation NOT node-named — `next-server` on 08-09, a shell or a
# task runner in the general case. It is therefore unreachable by widening the cohort, and widening
# it is the wrong lever anyway (that rule is deliberately under-inclusive because a wrongly-stopped
# process costs the operator's session). This asks a different question — "who just made these?" —
# and answers it from evidence already in hand.
#
# THE THRESHOLD IS A COUNT, NOT UNANIMITY. The obvious reading of "the cohort shares one parent" is
# `all children agree`, and it would retire the mechanism's own main path: a real storm's cohort
# picks up strays — an unrelated worker over the floor, a second worktree's server — and one stray
# would veto the break every time (memory abstain-rule-can-retire-the-common-case). So the rule is
# per-parent and ranked: every parent owning >= <min> of the selected burst is a spawner, biggest
# first, at most <cap> of them. That also answers the two-`next dev` case, which unanimity cannot.
#
# THE FIVE EXCLUSIONS, each for a different failure:
#   · pid <= 1 — launchd. It is also where the kernel REPARENTS the children of a spawner that has
#     already exited, so the one bucket guaranteed to clear any threshold is exactly the one whose
#     "parent" no longer exists. (Those ownerless servers are devserver-gc's job, not a signal's.)
#   · this daemon and its launcher — a guard that can freeze its own supervisor is not a guard.
#   · claude/claude.exe by comm, anything claude/mcp-shaped by argv — the same double test the cohort
#     uses, and for the stronger reason: SIGSTOP is only reversible if something is left running to
#     send SIGCONT, and that something is the operator's session.
#   · a parent already in the selected cohort — it is about to be frozen as a child; counting it
#     twice would inflate the reported spawner count over a process that gets exactly one signal.
#   · a parent with no row of its own in this table — it exited between spawning and this read, so
#     there is nothing to stop and nothing to name. Printing it would fabricate a comm.
#
# Only pid → (comm, protected?) is retained, never argv: agent briefs travel in argv (memory
# pgrep-f-matches-agent-briefs), so buffering the table's argv to answer a question about parentage
# would make the instrument allocate in proportion to the fleet at the one moment memory is scarce.
select_break_parents() { # <exe_file> <cohort_pids> <min_children> <cap> <self_pid> <self_ppid>
  awk -v cohort=" $2 " -v min="$3" -v cap="$4" -v self="$5" -v selfp="$6" '
    NR == FNR { if ($1 ~ /^[0-9]+$/) { ebase[$1] = $4; eppid[$1] = $2 } next }
    $1 ~ /^[0-9]+$/ {
      pid = $1; ppid = $2
      args = ""; for (i = 4; i <= NF; i++) args = args " " $i
      named = (pid in ebase && eppid[pid] == ppid)
      base = named ? ebase[pid] : "?"
      seen[pid] = 1; name[pid] = base
      if (!named) protect[pid] = 1                    # cannot apply the name test ⇒ assume it fails
      if (base == "claude.exe" || base == "claude" || args ~ /claude/ \
          || args ~ /(^|[\/ _-])mcp([-_\/ @.]|$)|modelcontextprotocol/) protect[pid] = 1
      if (index(cohort, " " pid " ") > 0) kids[ppid]++
    }
    END {
      k = 0
      # `pp`, not `p` — `p` is the split() array in the per-row block above, and awk refuses to
      # reuse that name for a scalar: it dies with "can-not assign to p; it is an array name", and
      # only once `kids` is non-empty — i.e. on the FIRST table with a parent to consider, which is
      # exactly the storm this exists for and never an idle box.
      # (This comment lives inside a single-quoted awk program: NO APOSTROPHES. Two of them close
      # and reopen the shell string, and the awk source between them is silently word-split — which
      # turned all 13 cases below red on the run that first wrote it.)
      for (pp in kids) {
        if (kids[pp] < min) continue
        if (pp + 0 <= 1) continue
        if (pp + 0 == self + 0 || pp + 0 == selfp + 0) continue
        if (index(cohort, " " pp " ") > 0) continue
        if (!(pp in seen)) continue
        if (pp in protect) continue
        cand[++k] = pp
      }
      # Selection sort rather than a pipe to sort(1): `sort | head` under `set -o pipefail` SIGPIPEs
      # the producer and promotes the pipeline to 141, and k is bounded by cohort_size/min anyway.
      for (i = 1; i <= k && i <= cap; i++) {
        b = i
        for (j = i + 1; j <= k; j++)
          if (kids[cand[j]] > kids[cand[b]] || \
             (kids[cand[j]] == kids[cand[b]] && cand[j] + 0 < cand[b] + 0)) b = j
        t = cand[i]; cand[i] = cand[b]; cand[b] = t
        printf "%s %s %s\n", cand[i], kids[cand[i]], name[cand[i]]
      }
    }' "$1" -
}

# ── trip capture: rank first, then attribute ──────────────────────────────────────────────────────
# §7-bis(b) of docs/research/machine-lag-and-kitty-2026-08-06.md is the postmortem of what these
# replaced, and it is why BOTH of the old sections are gone rather than widened:
#   · `--- argv (node|chrom|…, head -80) ---` hit the cut in 16 of 18 trips. A `head` over a
#     NAME-filtered, unranked list drops whole PROCESSES, and a dropped process is a lookup MISS that
#     reads as an ABSENCE — the filter was a second blindness besides, since nothing outside its six
#     names could appear at all.
#   · `--- top by memory ---` printed COMM only, so every Node workload rendered as `node`: tsc,
#     next-server and an MCP chain were indistinguishable.
# The composition is now inverted. What bounds a section is a RANK, in the exact quantity the
# incident is about, so what falls off the end is provably smaller than everything that stays; the
# old bound was a line count over an unranked list, where what fell off was whatever `ps` happened
# to emit last. `pgrep -f` remains no substitute for `ps` here — macOS matches it against a TRUNCATED
# argv (capacity-alarm.sh:231 measured it returning 0 against a real 8) — and neither renderer pipes
# to `head`, which under `set -o pipefail` would SIGPIPE the producer and promote the pipeline to 141.

# stdin: `ps -Awwo pid=,ppid=,rss=,pcpu=,args=` → the <n> highest-RSS rows, argv intact.
#
# Only <n> rows are ever held, by bounded insertion. Buffering the whole process table in order to
# sort it would make the instrument allocate in proportion to the fleet it is measuring, at the one
# moment memory is the scarce thing.
#
# The four leading columns are matched as a PREFIX and the remainder taken verbatim rather than
# rejoined from $5..$NF, because rejoining collapses runs of whitespace INSIDE argv and so silently
# rewrites the record. The fourth column is matched as "any non-blank" rather than [0-9.]+ so that a
# locale rendering %CPU as `0,0` cannot drop every row on the floor.
#
# argv is capped per ROW at <amax> chars (0 = uncapped) and the cut is STAMPED with how much it
# dropped. That is not the head -80 defect returning by another door: that one dropped whole
# processes silently, this shortens ONE named row's tail and says by exactly how much. Agent briefs
# travel in argv (memory pgrep-f-matches-agent-briefs), so uncapped rows run to tens of KB each,
# 13 snapshots per trip, into a 25 MiB rotation.
top_by_rss() { # <n> <argv_max_chars>
  awk -v n="$1" -v amax="$2" '
    match($0, /^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+[0-9]+[ \t]+[^ \t]+[ \t]+/) {
      rss = $3 + 0
      args = substr($0, RSTART + RLENGTH)
      if (amax > 0 && length(args) > amax)
        args = substr(args, 1, amax) sprintf("…[+%d chars]", length(args) - amax)
      row = sprintf("%7s %7s %10d %6s  %s", $1, $2, rss, $4, args)
      if (k < n)           { pos = ++k }
      else if (rss > r[k]) { pos = k }
      else                 { next }
      while (pos > 1 && r[pos - 1] < rss) { r[pos] = r[pos - 1]; l[pos] = l[pos - 1]; pos-- }
      r[pos] = rss; l[pos] = row
    }
    END { for (i = 1; i <= k; i++) print l[i] }'
}

# stdin: `ps -Awwo rss=,comm=` → the <n> executables holding the most RSS, with their counts.
#
# It takes its OWN ps rather than reusing the rows above: comm is the last field there, so everything
# past the RSS column is the executable path verbatim, spaces included (`…/Google Chrome for
# Testing`). With argv trailing instead, no parseable boundary exists.
#
# Coarse BY CONSTRUCTION — it groups on the executable, the very column §7-bis convicted — so it is
# labelled a total and never attribution. It is here because the ranked section above cannot see the
# one shape the old unranked list caught by accident: forty workers at 180 MB each outweigh any
# single row and appear in none of them. Removing that list without this would be a net loss.
rss_by_exe() { # <n>
  awk -v n="$1" '
    match($0, /^[ \t]*[0-9]+[ \t]+/) {
      exe = substr($0, RSTART + RLENGTH)
      c = split(exe, p, "/"); base = p[c]
      sum[base] += $1 + 0; cnt[base]++
    }
    END {
      for (b in sum) {
        v = sum[b]
        if (m < n)          { pos = ++m }
        else if (v > sv[m]) { pos = m }
        else                { continue }
        while (pos > 1 && sv[pos - 1] < v) { sv[pos] = sv[pos - 1]; sb[pos] = sb[pos - 1]; pos-- }
        sv[pos] = v; sb[pos] = b
      }
      for (i = 1; i <= m; i++) printf "%10.1f MB  x%-4d %s\n", sv[i] / 1024, cnt[sb[i]], sb[i]
    }'
}

# One sample of attribution. The follow-ups render it too, at a tighter rank: under the old shape
# those twelve samples were COMM-only, which made the part of the record that WATCHES the ramp the
# blindest part of it — and a process born after the trip appeared in no section at all.
# <agg_n> 0 omits the coarse total, which is a standing shape rather than a ramp.
render_attribution() { # <top_n> <argv_max_chars> <agg_n>
  local rows exe
  rows="$(ps -Awwo pid=,ppid=,rss=,pcpu=,args= 2>/dev/null)" || rows=""
  if [ -z "$rows" ]; then
    # An empty section would read as an idle machine. Say which of the two it is: this is the same
    # contract the readers hold, where "could not measure" must never render as the healthy value.
    printf '\n--- top %s by RSS ---\n(NO ROWS — ps was unreadable. A blind instrument, not an idle box.)\n' "$1"
  else
    printf '\n--- top %s by RSS, full argv (a RANK bound — nothing below is a line cut) ---\n' "$1"
    printf '    PID    PPID     RSS_KB   %%CPU  ARGV\n'
    printf '%s\n' "$rows" | top_by_rss "$1" "$2"
  fi

  [ "$3" -gt 0 ] || return 0
  exe="$(ps -Awwo rss=,comm= 2>/dev/null)" || exe=""
  if [ -z "$exe" ]; then
    printf '\n--- RSS by executable ---\n(NO ROWS — ps was unreadable.)\n'
  else
    printf '\n--- RSS by executable, top %s (COARSE total: shared pages double-count, so an upper bound. The argv above is the attribution) ---\n' "$3"
    printf '%s\n' "$exe" | rss_by_exe "$3"
  fi
}

snapshot_trip() { # <ts> <why> <headline>
  {
    printf '\n═══ TRIP %s  why=%s ═══\n%s\n' "$1" "$2" "$3"
    render_attribution "$SNAP_TOPN" "$SNAP_ARGV_MAX" "$SNAP_AGG_N"
    printf '\n--- vm_stat ---\n'
    vm_stat 2>/dev/null
  } >> "$SNAP" 2>/dev/null || true
}

# Twelve more top-RSS reads at 5 s. Run in the BACKGROUND, and that is a design decision, not a
# convenience: 12 x 5 s blocking would blind the JSONL for a full minute starting at the exact moment
# the ramp becomes interesting — and §6 discriminator 4 makes a row GAP a distress signal in its own
# right, so a self-inflicted gap would poison the one channel the post-mortem trusts most.
snapshot_followup() {
  local i=0
  while [ "$i" -lt "$FOLLOWUP_N" ]; do
    sleep "$FOLLOWUP_SEC"
    i=$((i + 1))
    {
      printf '\n--- follow-up %s/%s  %s ---\n' "$i" "$FOLLOWUP_N" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      render_attribution "$SNAP_TOPN_FUP" "$SNAP_ARGV_MAX" 0
    } >> "$SNAP" 2>/dev/null || true
  done
}

# The page envelope, same shape as capacity-alarm.sh:609-643 (epoch, headline, detail, re-run) and
# one fixed slug so no cadence can accumulate pages.
#
# IT DOES NOT SELF-CLEAR, and that is the one place it deliberately diverges from capacity-alarm's
# page contract. That page asserts a LEVEL, so a cleared level must retract it. This one records an
# EDGE: by the time anyone reads it the ramp is usually over, but the trip still happened and the
# page is the only pointer to the snapshot that explains it. Retracting it would delete the receipt.
write_page() { # <ts> <why> <headline> <detail>
  mkdir -p "$PAGES_DIR" 2>/dev/null || true
  {
    date +%s 2>/dev/null || echo 0
    printf 'compressor-sentinel TRIP (%s) — %s\n' "$2" "$3"
    printf '%s\n' "$4"
    printf 'This is the axis three kernel panics died on. The kernel edge leaves 7.6 s; this fired\n'
    printf 'on RATE, well below it. Actuator: %s.\n' "$ACT"
    printf 'snapshot: %s\n' "$SNAP"
    printf 'samples:  %s\n' "$LOG"
    printf 're-run:   %s\n' "$0"
  } > "$PAGE" 2>/dev/null || true
}

# ── THE UNFREEZE ARM (master 477f0b771ec3) ────────────────────────────────────────────────────────
# The actuator SIGSTOPs and nothing resumes. That is not an oversight in the margins: the kill site
# below justifies choosing SIGSTOP over SIGKILL with the words "so we must be the reversible one",
# and the reversal was never built. Measured 2026-08-19: 109 trips, 59 real SIGSTOPped events, and
# zero SIGCONT senders anywhere in the tree (git grep -- -CONT, prose filtered, returns nothing).
# So every actuation to date has been a one-way freeze whose only exit was the process dying or the
# box rebooting.
#
# THE RELEASE POLICY, stated explicitly because the row demands one and because an implicit policy
# here is indistinguishable from the bug:
#   clear   — the breach is over (no trip this tick) AND the freeze has been held HOLD_MIN_S. This
#             is the normal path; the minimum matches the cooldown so we never resume into the ramp
#             we just interrupted.
#   ceiling — held HOLD_MAX_S, released EVEN IF STILL IN BREACH. A freeze that outlives its own
#             emergency has stopped being a guard and become the incident; at that point the honest
#             move is to give the box back and say so loudly.
#   exit    — the sentinel is going away (TERM/INT). Unconditional. Without this arm a daemon
#             restart strands the whole cohort permanently, which is the row's failure mode with
#             extra steps.
#
# WHAT MAKES THIS SAFE TO RUN UNATTENDED: we resume ONLY what we froze. Every release is gated on
# (pid, lstart) matching the ledger, TZ-pinned on BOTH sides because ps renders lstart in the
# ambient zone and a DST flip would otherwise convict every row at once (memory:
# process-start-time-renders-in-ambient-timezone). A pid that has been recycled onto a different
# process fails that compare and is dropped WITHOUT a signal — SIGCONT to an innocent stopped
# process (a debugger target, an operator ^Z) is the one harm this arm could do, and the guard is
# what forecloses it.
proc_lstart() { # <pid> → TZ-pinned start time, empty if the pid is gone
  TZ=UTC ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//'
}

record_frozen() { # <pid> <kind> <comm> — ledger one REAL SIGSTOP so it can be undone
  local ls
  ls="$(proc_lstart "$1")"
  # No lstart means the process died between the signal and this read. Nothing to owe it.
  [ -n "$ls" ] || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$ls" "$2" "$(date +%s)" "$3" >> "$FROZEN_DB" 2>/dev/null || true
}

release_frozen() { # <now-epoch> <mode: clear|ceiling|exit> → "released=N held=N stale=N"
  local now="$1" mode="$2" keep rel=0 held=0 stale=0 pid ls kind at comm cur age due
  [ -s "$FROZEN_DB" ] || { printf 'released=0 held=0 stale=0'; return 0; }
  keep="$(mktemp -t cc-sentinel-frozen)" || { printf 'released=0 held=0 stale=0'; return 0; }
  while IFS="$(printf '\t')" read -r pid ls kind at comm; do
    [ -n "$pid" ] || continue
    cur="$(proc_lstart "$pid")"
    # Gone, or the pid now belongs to someone else. Either way we owe it nothing and must not signal.
    if [ -z "$cur" ] || [ "$cur" != "$ls" ]; then stale=$((stale + 1)); continue; fi
    age=$((now - at))
    due=0
    [ "$mode" = "exit" ] && due=1
    [ "$age" -ge "$HOLD_MAX_S" ] && due=1
    [ "$mode" = "clear" ] && [ "$age" -ge "$HOLD_MIN_S" ] && due=1
    if [ "$due" -eq 1 ]; then
      kill -CONT "$pid" 2>/dev/null
      rel=$((rel + 1))
      printf 'SIGCONT pid=%s held_s=%s kind=%s comm=%s\n' "$pid" "$age" "$kind" "$comm" \
        >> "$SNAP" 2>/dev/null || true
    else
      held=$((held + 1))
      printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$ls" "$kind" "$at" "$comm" >> "$keep"
    fi
  done < "$FROZEN_DB"
  mv -f "$keep" "$FROZEN_DB" 2>/dev/null || rm -f "$keep" 2>/dev/null
  printf 'released=%s held=%s stale=%s' "$rel" "$held" "$stale"
}

# ── panic attribution: read the kernel's own verdict before it is rotated away ────────────────────
# The kernel already named the culprit; the only defect is that nobody reads it. Two facts are
# extracted, and they are the two that a post-mortem has always had to be reconstructed by hand:
#   VERDICT — the `Compressor Info:` line from panicString. It states the kill axis outright
#             ("100% of segments limit (BAD)") and it is the discriminator every other rung on
#             this box is blind to: headroom, swap and memory-pressure all read HEALTHY at death.
#   CENSUS  — the per-process table macOS embeds in a `panic-full` report, counted by comm. On
#             2026-08-09 that reads node=780, claude.exe=13 — which is the whole argument that the
#             fleet is the VICTIM and a dev-server worker pool is the killer, recoverable in one
#             command instead of the multi-hour manual trace it took the first time.
# A `panic-base+socd` report (366 KB) carries the verdict and NO process table, and a failed
# stackshot can strip the table from a `panic-full` too. `census_source` records which it was, so
# an absent census is never mistaken for a census of zero.
panic_newest() { # → path of the most recently modified *.panic across PANIC_DIRS, or empty
  # `find` + an explicit mtime sort rather than `ls -1t` (SC2012; the gate lints at info severity).
  # `stat -f '%m %N'` is BSD, `-c` is GNU — both are tried so this is not silently Darwin-only.
  # Sorting numerically descending on the epoch reproduces `ls -t` exactly, without parsing ls.
  local d rows=""
  for d in ${PANIC_DIRS//:/ }; do
    [ -d "$d" ] || continue
    rows="$rows$(
      { find "$d" -maxdepth 1 -type f -name '*.panic' -exec stat -f '%m %N' {} + \
          || find "$d" -maxdepth 1 -type f -name '*.panic' -exec stat -c '%Y %n' {} + ; } 2>/dev/null
    )
"
  done
  printf '%s' "$rows" | grep -v '^$' | sort -rn | head -1 | cut -d' ' -f2-
}


panic_scan() {
  mkdir -p "$(dirname "$PANIC_LEDGER")" 2>/dev/null || true
  local any_dir=0 d
  for d in ${PANIC_DIRS//:/ }; do [ -d "$d" ] && any_dir=1; done
  if [ "$any_dir" = 0 ]; then
    printf 'panic-scan: unreadable (no panic directory among %s)\n' "$PANIC_DIRS" >&2
    return 3
  fi

  local f; f="$(panic_newest)"
  if [ -z "$f" ]; then printf 'panic-scan: none\n' >&2; return 0; fi

  local base; base="$(basename "$f")"
  if [ -f "$PANIC_LEDGER" ] && grep -qF "\"report\":\"$base\"" "$PANIC_LEDGER" 2>/dev/null; then
    printf 'panic-scan: already recorded (%s)\n' "$base" >&2
    return 0
  fi
  if [ ! -r "$f" ]; then
    printf 'panic-scan: unreadable (%s)\n' "$base" >&2
    return 3
  fi

  # BOUNDED read. A panic-full is 6.5 MB and this runs at daemon startup; head -c keeps it a fixed
  # cost. The verdict lives in the first lines and the process table well inside the bound.
  local body; body="$(head -c "$PANIC_HEAD_BYTES" "$f" 2>/dev/null)" || body=""

  local verdict when uptime csrc census
  verdict="$(printf '%s' "$body" | grep -ao 'Compressor Info:[^\\"]*' | head -1)"
  when="$(printf '%s' "$body" | grep -ao '"timestamp":"[^"]*"' | head -1 | sed 's/.*:"//; s/"$//')"
  uptime="$(printf '%s' "$body" | grep -ao 'uptime[^,]*' | head -1)"

  # The anchor is `"procname":"<comm>"`, READ OUT OF THE REAL REPORT rather than guessed. The first
  # draft of this counted every quoted token and "found" a process table in a panic-base+socd report
  # that provably has none — census_source read `report-process-table` over a census of JSON keys
  # (`bug_type=2 socId=1`). That is the failure this field exists to make impossible, and it got
  # past a reading of the code; only opening the artifact caught it. Verified on the live pair:
  # panic-full-2026-08-09-034124 yields node/claude.exe; panic-base+socd-2026-08-09-041859 yields
  # nothing at all, which is the correct answer for a report that carries no table.
  census="$(printf '%s' "$body" \
    | grep -ao '"procname":"[^"]\{1,40\}"' \
    | sed 's/.*:"//; s/"$//' | sort | uniq -c | sort -rn | head -12 \
    | awk '{printf "%s%s=%s", (NR>1?" ":""), $2, $1}')"
  if [ -z "$census" ]; then
    csrc="absent-no-process-table"
  else
    csrc="report-process-table"
    # A census taken over a truncated report ranks by whatever fitted, which measured as an
    # INVERTED culprit (bash over node). Say so rather than let the ranking be believed.
    local sz; sz="$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)"
    case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
    [ "$sz" -gt "$PANIC_HEAD_BYTES" ] && csrc="report-process-table-TRUNCATED"
  fi

  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
         --arg report "$base" --arg pts "${when:-unknown}" --arg v "${verdict:-unknown}" \
         --arg up "${uptime:-unknown}" --arg c "${census:-}" --arg cs "$csrc" \
         --arg path "$f" \
    '{ts:$ts,kind:"panic",report:$report,panicked_at:$pts,verdict:$v,uptime:$up,
      census:$c,census_source:$cs,path:$path,
      note:"recorded by compressor-sentinel at startup; macOS rotates the source report away"}' \
    >> "$PANIC_LEDGER" 2>/dev/null || return 3

  printf 'panic-scan: recorded %s — %s\n' "$base" "${verdict:-<no compressor line>}" >&2
  return 0
}

# ── freeze attribution: the death that leaves no report, read from the boot that followed it ──────
# Every reader below returns NON-ZERO rather than a value when its instrument is unreadable, and
# none has a fallback — panic_scan's contract, kept.

# kern.boottime → the epoch seconds of THIS boot. This is the row's identity: one boot, one row,
# so the ledger stays an incident history rather than a boot history however often we restart.
freeze_boot_epoch() {
  local raw
  raw="$(sysctl -n kern.boottime 2>/dev/null)" || return 1
  # `{ sec = 1786686149, usec = 597125 }`.
  # THE `^{` ANCHOR IS THE WHOLE POINT, and it cost a live run to learn. The first draft read
  # `s/.*sec = \([0-9]*\)/\1/` — and `.*` is GREEDY, so it walked forward to the LONGEST match and
  # captured `usec`, whose name ends in the very token being anchored on. Against the real sysctl
  # that returned 597125 — the MICROSECONDS — as the boot epoch: a number that is well-formed, all
  # digits, passes every type check, and is wrong by fifty-six years. Anchoring at `^{` makes `usec`
  # unreachable, because there is only one `sec` immediately after the brace.
  raw="$(printf '%s' "$raw" | sed -n 's/^{ *sec *= *\([0-9][0-9]*\).*/\1/p')"
  case "$raw" in ''|*[!0-9]*) return 1 ;; esac
  # AND A PLAUSIBILITY FLOOR, because the anchor above is a fix for the bug that was found and this
  # is the guard for the next format change. 10^9 is 2001-09-09; no Mac boots before it. A parse
  # that yields a number this small has misread the field, and REFUSING is the only safe answer —
  # a bogus-but-numeric boot id would key a ledger row that no later run could ever match, silently
  # re-recording the same boot forever.
  [ "$raw" -ge 1000000000 ] 2>/dev/null || return 1
  printf '%s' "$raw"
}

freeze_shutdown_reason() {
  local v
  v="$(sysctl -n kern.shutdownreason 2>/dev/null)" || return 1
  v="$(printf '%s' "$v" | tr -s ' \t' ' ' | sed 's/^ *//; s/ *$//')"
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

# The `Boot faults:` line of the newest ResetCounter written for THIS boot. Empty (rc 1) when no
# abnormal-boot record exists — which is itself the answer for a clean shutdown, not a failure.
freeze_boot_faults() { # <boot_epoch>
  local d floor newest rows="" line
  floor=$(( $1 - FREEZE_RESET_SLACK_S ))
  for d in ${FREEZE_RESET_DIRS//:/ }; do
    [ -d "$d" ] || continue
    rows="$rows$(
      { find "$d" -maxdepth 1 -type f -name 'ResetCounter-*.diag' -exec stat -f '%m %N' {} + \
          || find "$d" -maxdepth 1 -type f -name 'ResetCounter-*.diag' -exec stat -c '%Y %n' {} + ; } 2>/dev/null
    )
"
  done
  newest="$(printf '%s' "$rows" | grep -v '^$' | sort -rn | awk -v f="$floor" '$1 >= f {print; exit}')"
  [ -n "$newest" ] || return 1
  newest="$(printf '%s' "$newest" | cut -d' ' -f2-)"
  [ -r "$newest" ] || return 1
  line="$(grep -a -m1 '^Boot faults:' "$newest" 2>/dev/null | sed 's/^Boot faults: *//')"
  [ -n "$line" ] || return 1
  printf '%s\t%s' "$line" "$newest"
}

# The last row a sampler wrote BEFORE this boot — i.e. its final breath before the darkness. The
# `< $b` filter matters: this runs at daemon startup, and a sampler that has already ticked once on
# the new boot would otherwise hand back a post-boot row and silently erase the whole dark window.
freeze_sampler_tail() { # <file> <boot_iso> → the row, or rc 1
  local row
  [ -r "$1" ] || return 1
  row="$(tail -n "$FREEZE_TAIL_ROWS" "$1" 2>/dev/null \
        | jq -c --arg b "$2" 'select(type == "object" and .ts != null and (.ts | tostring) < $b)' 2>/dev/null \
        | tail -1)"
  [ -n "$row" ] || return 1
  printf '%s' "$row"
}

freeze_scan() {
  mkdir -p "$(dirname "$PANIC_LEDGER")" 2>/dev/null || true

  local boot
  if ! boot="$(freeze_boot_epoch)"; then
    printf 'freeze-scan: unreadable (kern.boottime)\n' >&2
    return 3
  fi

  # Idempotent on the boot, not on a filename: the artifacts here are re-derived every start.
  if [ -f "$PANIC_LEDGER" ] && grep -qF "\"boot\":$boot," "$PANIC_LEDGER" 2>/dev/null; then
    printf 'freeze-scan: already recorded (boot %s)\n' "$boot" >&2
    return 0
  fi

  local reason="" faults="" diagpath="" src sig raw
  reason="$(freeze_shutdown_reason)" || reason=""
  if raw="$(freeze_boot_faults "$boot")"; then
    faults="${raw%%$'\t'*}"; diagpath="${raw#*$'\t'}"
  fi

  # The .diag wins when it exists; the sysctl is the fallback. Named, so a reader of the row knows
  # which artifact the verdict came off — and both are stored raw regardless.
  if [ -n "$faults" ]; then sig="$faults"; src="resetcounter"
  elif [ -n "$reason" ]; then sig="$reason"; src="kern.shutdownreason"
  else
    printf 'freeze-scan: clean (no abnormal-boot record for boot %s)\n' "$boot" >&2
    return 0
  fi

  # ORDER IS LOAD-BEARING. wdog is tested FIRST because a watchdog boot can also carry a button
  # token, and a death that panicked belongs to panic_scan — recording it here too would make one
  # event two incidents and inflate every count taken off this ledger.
  case "$sig" in
    *wdog*)
      printf 'freeze-scan: watchdog boot (%s) — the panic reader owns this one\n' "$sig" >&2
      return 0 ;;
  esac
  case "$sig" in
    *force_off*|*btn_rst*) : ;;
    *)
      printf 'freeze-scan: clean (%s)\n' "$sig" >&2
      return 0 ;;
  esac

  # A forced power-off that ALSO left a panic report is not this class: the box died, wrote its
  # report, and the button was only how it got back. Defer, rather than double-count.
  local newest_panic=""; newest_panic="$(panic_newest)"
  if [ -n "$newest_panic" ] && [ -r "$newest_panic" ]; then
    local pm; pm="$(stat -f%m "$newest_panic" 2>/dev/null || stat -c%Y "$newest_panic" 2>/dev/null || echo 0)"
    case "$pm" in ''|*[!0-9]*) pm=0 ;; esac
    if [ "$pm" -ge $(( boot - FREEZE_RESET_SLACK_S )) ]; then
      printf 'freeze-scan: forced power-off WITH a panic report (%s) — the panic reader owns it\n' \
        "$(basename "$newest_panic")" >&2
      return 0
    fi
  fi

  local boot_iso; boot_iso="$(date -u -r "$boot" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '')"

  # THE DARK WINDOW, and EVERY sampler's final breath — not just the newest one.
  # The boundary is the newest pre-boot row (darkness starts at the last evidence of life), but the
  # PAYLOAD must be all of them, because the samplers carry disjoint fields and the informative one
  # is not always the newest. Measured on this very incident: the sentinel's 04:22:54Z row won the
  # boundary by 15 s, while the fact that actually describes the trigger — load_1m 13.11 (up from
  # 9.35), ptys_used 9 (down from 16), active_gb down 5.4 GB in 63 s — lives only in capacity-alarm's
  # 04:22:39Z row. Keeping the newest ALONE would have thrown away the only description of the
  # trigger that survives, which is the entire reason this reader exists.
  # "Could not read any" stays distinct from "the darkness was zero long" — sampler_source says which.
  local f last_ts="" last_src="" ssrc="none-readable"
  local ticksf="${TMPDIR:-/tmp}/cs-freeze-ticks.$$"; : > "$ticksf"
  for f in ${FREEZE_SAMPLERS//:/ }; do
    [ -e "$f" ] || continue
    [ "$ssrc" = "none-readable" ] && ssrc="readable-no-preboot-row"
    local row ts
    row="$(freeze_sampler_tail "$f" "${boot_iso:-9999}")" || continue
    ts="$(printf '%s' "$row" | jq -r '.ts // empty' 2>/dev/null)"
    [ -n "$ts" ] || continue
    jq -cn --arg k "$(basename "$f")" --argjson v "$row" '{key:$k,value:$v}' >> "$ticksf" 2>/dev/null
    if [ -z "$last_ts" ] || [ "$ts" \> "$last_ts" ]; then
      last_ts="$ts"; last_src="$f"; ssrc="$(basename "$f")"
    fi
  done
  local ticks; ticks="$(jq -cs 'from_entries' "$ticksf" 2>/dev/null)"
  case "$ticks" in ''|'null') ticks='{}' ;; esac
  rm -f "$ticksf" 2>/dev/null || true

  local dark_min="null"
  if [ -n "$last_ts" ] && [ -n "$boot_iso" ]; then
    local le; le="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$last_ts" +%s 2>/dev/null \
                    || date -u -d "$last_ts" +%s 2>/dev/null || echo '')"
    case "$le" in ''|*[!0-9]*) le="" ;; esac
    [ -n "$le" ] && dark_min="$(awk -v a="$boot" -v b="$le" 'BEGIN{printf "%.1f", (a-b)/60}')"
  fi

  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
         --argjson boot "$boot" --arg biso "${boot_iso:-unknown}" \
         --arg sig "$sig" --arg src "$src" --arg faults "${faults:-}" \
         --arg reason "${reason:-}" --arg diag "${diagpath:-}" \
         --arg lts "${last_ts:-}" --arg lsrc "${last_src:-}" --arg ssrc "$ssrc" \
         --argjson dark "$dark_min" \
         --argjson ticks "$ticks" \
    '{ts:$ts,kind:"freeze",boot:$boot,booted_at:$biso,
      signature:$sig,signature_source:$src,boot_faults:$faults,shutdown_reason:$reason,
      reset_report:$diag,
      dark_from:(if $lts == "" then null else $lts end),dark_to:$biso,dark_minutes:$dark,
      sampler:(if $lsrc == "" then null else $lsrc end),sampler_source:$ssrc,
      last_ticks:$ticks,
      note:"forced power-off with no panic report: the OS stopped answering and a human held the button. last_ticks holds each sampler final pre-freeze row — the only description of the trigger that survives."}' \
    >> "$PANIC_LEDGER" 2>/dev/null || return 3

  printf 'freeze-scan: recorded FREEZE boot=%s dark=%s min from %s (%s)\n' \
    "$boot" "$dark_min" "${last_ts:-<no sampler row>}" "$sig" >&2
  return 0
}

if [ "$TICKS_PANIC_ONLY" = "1" ]; then
  panic_scan; exit $?
fi
if [ "$TICKS_FREEZE_ONLY" = "1" ]; then
  freeze_scan; exit $?
fi
# NEVER let the post-mortem stop the sensor from starting: a reader for the LAST death must not
# cost the evidence for the NEXT one.
[ "$PANIC_SCAN" = "off" ] || panic_scan || true
[ "$FREEZE_SCAN" = "off" ] || freeze_scan || true

# ── main loop ─────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG")" "$(dirname "$SNAP")" 2>/dev/null || true

FOLLOWUP_PID=""
# shellcheck disable=SC2329  # invoked indirectly, by the trap below.
cleanup() {
  [ -n "$FOLLOWUP_PID" ] && kill "$FOLLOWUP_PID" 2>/dev/null
  # RELEASE ON THE WAY OUT, unconditionally. Without this the row's failure mode survives the fix:
  # a daemon that freezes a cohort and is then restarted (launchd reload, an upgrade, a reboot that
  # kills it before the box goes down) leaves those pids stopped with the only record of the debt
  # sitting in a file nothing will read again. The exiting process is the last actor that still
  # knows what it owes.
  if [ "$ACT" = "stop" ] && [ -s "$FROZEN_DB" ]; then
    printf '%s compressor-sentinel: RELEASE-ON-EXIT %s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(release_frozen "$(date +%s)" exit)" >&2
  fi
  exit 0
}
trap cleanup TERM INT

PREV_T=""; PREV_SEG=""; PREV_CBU=""; PREV_SWAP=""; PREV_CMP=""; PREV_DCMP=""
# THREE SEPARATE KEYS, not one comma-joined field. The first draft emitted `"n":8,2,3404` — three
# bare values under one key, which no JSON parser accepts, so a single census would have poisoned
# every consumer of the whole file. capacity-alarm.sh:560 records the identical defect (`"est_room_
# sessions":?`) and the identical reason it survived review: a regex test for one field never
# requires the surrounding document to parse. Caught here by a 3-tick smoke, not by reading.
CENSUS_PIDS=""; CENSUS_N="null"; CENSUS_ORPH="null"; CENSUS_RSS="null"
STREAK=0; COOLDOWN_UNTIL=0; TICK=0; ROWS=0

while :; do
  TICK=$((TICK + 1))
  NOW="$(date +%s)"

  # Required — the trip cannot be evaluated without any of these, so an unreadable one skips the
  # whole tick. No row. A row with a fabricated 0 in it is worse than no row, because it reads green.
  SKIP=""
  VMS="$(read_vm_stat)"           || SKIP="vm_stat"
  SWAP_B="$(read_swap_used_bytes)" || SKIP="${SKIP:-vm.swapusage}"
  SEG_LIMIT="$(read_num_sysctl vm.compressor_segment_limit)" || SKIP="${SKIP:-vm.compressor_segment_limit}"
  SEG_BUF="$(read_num_sysctl vm.compressor_segment_buffer_size)" || SKIP="${SKIP:-vm.compressor_segment_buffer_size}"
  CBU="$(read_num_sysctl vm.compressor_bytes_used)" || SKIP="${SKIP:-vm.compressor_bytes_used}"

  if [ -n "$SKIP" ]; then
    printf '%s compressor-sentinel: SKIP tick %s — unreadable %s (no row emitted; not a 0)\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TICK" "$SKIP" >&2
    # A gap breaks consecutiveness and invalidates every baseline: the next delta would span two
    # intervals and the next streak would be asserted across a hole.
    PREV_T=""; PREV_SEG=""; PREV_CBU=""; PREV_SWAP=""; PREV_CMP=""; PREV_DCMP=""; STREAK=0
    [ "$TICKS" -gt 0 ] && [ "$TICK" -ge "$TICKS" ] && break
    sleep "$INTERVAL"
    continue
  fi

  PAGESZ="${VMS%% *}"; VMS_R="${VMS#* }"
  OCCUP="${VMS_R%% *}"; VMS_R="${VMS_R#* }"
  COMPRESSIONS="${VMS_R%% *}"; DECOMPRESSIONS="${VMS_R##* }"

  SEG_I="$(segs_in_core "$OCCUP" "$PAGESZ" "$SEG_BUF")" || SEG_I=""
  SEG_S="$(segs_swapped "$SWAP_B" "$SEG_BUF")" || SEG_S=""
  if [ -z "$SEG_I" ] || [ -z "$SEG_S" ]; then
    printf '%s compressor-sentinel: SKIP tick %s — segment arithmetic unresolvable\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TICK" >&2
    PREV_T=""; PREV_SEG=""; STREAK=0
    [ "$TICKS" -gt 0 ] && [ "$TICK" -ge "$TICKS" ] && break
    sleep "$INTERVAL"; continue
  fi
  SEG_EST=$((SEG_I + SEG_S))
  SEG_PCT="$(awk -v a="$SEG_EST" -v b="$SEG_LIMIT" 'BEGIN{ if (b <= 0) exit 1; printf "%.2f", 100*a/b }')" || SEG_PCT=""

  # Diagnostic-only sysctls. These do NOT gate the tick: they discriminate WHICH mechanism is running
  # (§4a — incompressible raw-store vs sparse-segment fragmentation), which decides the remedy but
  # not the trip. A build without them must still be guarded, so they render as JSON null — an
  # honest absence, not the fabricated 0 the required set refuses.
  INB="$(read_num_sysctl vm.compressor_input_bytes)"      || INB=""
  CPB="$(read_num_sysctl vm.compressor_compressed_bytes)" || CPB=""
  WKF="$(read_num_sysctl vm.wk_compression_failures)"     || WKF=""
  L4F="$(read_num_sysctl vm.lz4_compression_failures)"    || L4F=""
  FAILS=""
  [ -n "$WKF" ] && [ -n "$L4F" ] && FAILS=$((WKF + L4F))

  # ── deltas, normalised by MEASURED elapsed seconds ──────────────────────────────────────────────
  D_SEG="null"; D_CBU="null"; D_SWAP="null"; D_CMP="null"; D_DCMP="null"
  SEG_RATE="null"; CBU_RATE="null"; SWAP_RATE="null"; ELAPSED="null"
  HAVE_RATES=0
  if [ -n "$PREV_T" ] && [ "$NOW" -gt "$PREV_T" ]; then
    ELAPSED=$((NOW - PREV_T))
    D_SEG=$((SEG_EST - PREV_SEG))
    D_CBU=$((CBU - PREV_CBU))
    D_SWAP=$((SWAP_B - PREV_SWAP))
    D_CMP=$((COMPRESSIONS - PREV_CMP))
    D_DCMP=$((DECOMPRESSIONS - PREV_DCMP))
    SEG_RATE="$(awk -v d="$D_SEG" -v e="$ELAPSED" 'BEGIN{printf "%.1f", d/e}')"
    CBU_RATE="$(awk -v d="$D_CBU" -v e="$ELAPSED" 'BEGIN{printf "%.0f", d/e}')"
    SWAP_RATE="$(awk -v d="$D_SWAP" -v e="$ELAPSED" 'BEGIN{printf "%.0f", d/e}')"
    HAVE_RATES=1
  fi

  # ── census every CENSUS_EVERY ticks ─────────────────────────────────────────────────────────────
  if [ $((TICK % CENSUS_EVERY)) -eq 0 ]; then
    CRAW="$(census)"
    if [ -n "$CRAW" ]; then
      CENSUS_PIDS="${CRAW#*|}"
      CHEAD="${CRAW%%|*}"
      CENSUS_N="${CHEAD%% *}"; CREST="${CHEAD#* }"
      CENSUS_ORPH="${CREST%% *}"; CENSUS_RSS="${CREST##* }"
      : "${CENSUS_N:=null}" "${CENSUS_ORPH:=null}" "${CENSUS_RSS:=null}"
    fi
  fi

  # ── the row ─────────────────────────────────────────────────────────────────────────────────────
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ROW="$(printf '{"ts":"%s","t":%s,"el":%s,"seg":%s,"segi":%s,"segs":%s,"lim":%s,"pct":%s,"dseg":%s,"srate":%s,"cbu":%s,"dcbu":%s,"crate":%s,"swap":%s,"dswap":%s,"wrate":%s,"dcmp":%s,"ddec":%s,"inb":%s,"cpb":%s,"fail":%s,"n":%s,"orph":%s,"nrss":%s,"strk":%s}' \
    "$TS" "$TICK" "$ELAPSED" "$SEG_EST" "$SEG_I" "$SEG_S" "$SEG_LIMIT" "${SEG_PCT:-null}" \
    "$D_SEG" "$SEG_RATE" "$CBU" "$D_CBU" "$CBU_RATE" "$SWAP_B" "$D_SWAP" "$SWAP_RATE" \
    "$D_CMP" "$D_DCMP" "${INB:-null}" "${CPB:-null}" "${FAILS:-null}" \
    "$CENSUS_N" "$CENSUS_ORPH" "$CENSUS_RSS" "$STREAK")"
  printf '%s\n' "$ROW" >> "$LOG" 2>/dev/null || true
  ROWS=$((ROWS + 1))

  # ── breach → streak → trip ──────────────────────────────────────────────────────────────────────
  WHY=""
  if [ "$HAVE_RATES" = 1 ]; then
    WHY="$(classify_breach "$SEG_EST" "$SEG_LIMIT" "$SEG_RATE" "$CBU_RATE" "$SWAP_RATE")" || WHY=""
  fi
  if [ -n "$WHY" ]; then STREAK=$((STREAK + 1)); else STREAK=0; fi

  if [ -n "$WHY" ] && [ "$STREAK" -ge 2 ] && [ "$NOW" -ge "$COOLDOWN_UNTIL" ]; then
    HEAD_LINE="$(printf 'segments %s of %s (%s%%) · %s seg/s · compressor +%s B/s · swap +%s B/s' \
      "$SEG_EST" "$SEG_LIMIT" "${SEG_PCT:-?}" "$SEG_RATE" "$CBU_RATE" "$SWAP_RATE")"
    printf '%s compressor-sentinel: TRIP why=%s — %s\n' "$TS" "$WHY" "$HEAD_LINE" >&2
    snapshot_trip "$TS" "$WHY" "$HEAD_LINE"
    write_page "$TS" "$WHY" "$HEAD_LINE" "$ROW"

    if [ "$ACT" = "stop" ] || [ "$ACT" = "observe" ]; then
      STOPPED=0; PARENT_N=0; PARENT_STOPPED=0
      # OBSERVE runs the whole selection and signals nothing. It is the rung this actuator was
      # supposed to have on 2026-08-09 and did not: `off` computes no selection at all, so the only
      # way to learn what the predicate would touch was to arm it. Every later change to the
      # predicate — this one included — gets a logged would-stop tick first.
      [ "$ACT" = "observe" ] && ACTVERB="WOULD-STOP" || ACTVERB="SIGSTOP"
      # TWO reads, back-to-back, and the split between them is load-bearing — select_stop_targets'
      # header has the measurement. exe_table FIRST so the args table is the later instant: a pid
      # that dies between them is simply absent from the table that selects.
      EXEF="$(mktemp -t cc-sentinel-exe)"
      exe_table > "$EXEF" 2>/dev/null || true
      PSTABLE="$(ps -axwwo pid=,ppid=,rss=,args= 2>/dev/null)"
      TARGETS="$(printf '%s\n' "$PSTABLE" | select_stop_targets "$EXEF" "$CENSUS_PIDS" "$ACT_RSS_KB" "$ACT_CAP")"
      COHORT="$(printf '%s\n' "$TARGETS" | awk '$1 ~ /^[0-9]+$/ { printf "%s ", $1 }')"
      COHORT_N="$(printf '%s' "$COHORT" | wc -w | tr -d ' ')"   # derived from COHORT so they cannot disagree

      # THE SPAWNER GOES FIRST, and the order is the mechanism rather than a preference. Freezing
      # the cohort is up to <cap> kill(2) calls; a spawner left running mints throughout that window
      # and every process it mints after the table was read is invisible to this trip and survives
      # into the next 60 s cooldown. Stopping the parent first makes the cohort a closed set.
      if [ "$ACT_PARENT" = "on" ]; then
        PARENTS="$(printf '%s\n' "$PSTABLE" \
                   | select_break_parents "$EXEF" "$COHORT" "$ACT_PARENT_MIN" "$ACT_PARENT_CAP" "$$" "$PPID")"
        while read -r ppid pkids pcomm; do
          [ -n "$ppid" ] || continue
          PARENT_N=$((PARENT_N + 1))
          if [ "$ACT" = "observe" ]; then
            PARENT_STOPPED=$((PARENT_STOPPED + 1))
            printf '%s parent pid=%s kids=%s comm=%s\n' "$ACTVERB" "$ppid" "$pkids" "$pcomm" >> "$SNAP" 2>/dev/null || true
          elif kill -STOP "$ppid" 2>/dev/null; then
            PARENT_STOPPED=$((PARENT_STOPPED + 1))
            record_frozen "$ppid" parent "$pcomm"
            printf '%s parent pid=%s kids=%s comm=%s\n' "$ACTVERB" "$ppid" "$pkids" "$pcomm" >> "$SNAP" 2>/dev/null || true
          fi
        done <<< "$PARENTS"
      fi

      while read -r spid srss scomm; do
        [ -n "$spid" ] || continue
        # SIGSTOP only. Never SIGKILL — we are the only actor above the kernel here (§4a: jetsam is
        # off and no_paging_space_action is untrippable by a fleet), so we must be the reversible one.
        if [ "$ACT" = "observe" ]; then
          STOPPED=$((STOPPED + 1))
          printf '%s pid=%s rss_kb=%s comm=%s\n' "$ACTVERB" "$spid" "$srss" "$scomm" >> "$SNAP" 2>/dev/null || true
        elif kill -STOP "$spid" 2>/dev/null; then
          STOPPED=$((STOPPED + 1))
          record_frozen "$spid" proc "$scomm"
          printf '%s pid=%s rss_kb=%s comm=%s\n' "$ACTVERB" "$spid" "$srss" "$scomm" >> "$SNAP" 2>/dev/null || true
        fi
      done <<< "$TARGETS"
      rm -f "$EXEF" 2>/dev/null || true
      printf 'actuator: %s %s process(es) (cap %s, floor %s kB)\n' \
        "$([ "$ACT" = observe ] && echo 'WOULD have SIGSTOPped' || echo SIGSTOPped)" \
        "$STOPPED" "$ACT_CAP" "$ACT_RSS_KB" >> "$SNAP" 2>/dev/null || true
      # A verdict on EVERY armed trip, including the negative one. A mechanism that prints nothing
      # when it finds nothing is indistinguishable in the log from a mechanism that is not wired.
      if [ "$ACT_PARENT" != "on" ]; then
        printf 'actuator: parent-break off (CC_SENTINEL_ACT_PARENT=%s)\n' \
          "$ACT_PARENT" >> "$SNAP" 2>/dev/null || true
      elif [ "$PARENT_N" -gt 0 ]; then
        printf 'actuator: parent-break SIGSTOPped %s of %s spawner(s), each owning >= %s of the %s selected burst procs\n' \
          "$PARENT_STOPPED" "$PARENT_N" "$ACT_PARENT_MIN" "$COHORT_N" >> "$SNAP" 2>/dev/null || true
      else
        printf 'actuator: parent-break none — no eligible parent owns >= %s of the %s selected burst procs\n' \
          "$ACT_PARENT_MIN" "$COHORT_N" >> "$SNAP" 2>/dev/null || true
      fi
      # The standing freeze debt, on EVERY armed trip including the zero. Same reasoning as the
      # parent-break verdict above it: before this arm existed the snapshot looked exactly as it
      # would if a release path were wired and simply had nothing to do, which is why 59 one-way
      # freezes went unnoticed across 109 trips. A number here makes the two states distinguishable.
      printf 'actuator: freeze debt %s pid(s) awaiting SIGCONT (hold min %ss / ceiling %ss)\n' \
        "$(wc -l < "$FROZEN_DB" 2>/dev/null | tr -d ' ' || echo 0)" \
        "$HOLD_MIN_S" "$HOLD_MAX_S" >> "$SNAP" 2>/dev/null || true
    else
      printf 'actuator: DISARMED (CC_SENTINEL_ACT=%s) — detection only\n' "$ACT" >> "$SNAP" 2>/dev/null || true
    fi

    # One follow-up run at a time; it self-terminates in 60 s, which is the cooldown.
    if [ -z "$FOLLOWUP_PID" ] || ! kill -0 "$FOLLOWUP_PID" 2>/dev/null; then
      snapshot_followup &
      FOLLOWUP_PID=$!
    fi
    COOLDOWN_UNTIL=$((NOW + COOLDOWN))
    STREAK=0
  fi

  # THE RELEASE RUNS ON EVERY TICK, INCLUDING THE QUIET ONES, and that placement is the mechanism
  # rather than tidiness: a cohort frozen at tick N is owed its SIGCONT by a LATER tick, and the
  # ticks that follow a freeze are precisely the ones where nothing trips. Hanging the release off
  # the trip block would mean a cohort is only ever resumed by the NEXT emergency — i.e. never, on
  # the quiet box that is the normal case after the actuator has done its job.
  if [ "$ACT" = "stop" ] && [ -s "$FROZEN_DB" ]; then
    if [ -z "$WHY" ]; then RELMODE=clear; else RELMODE=ceiling; fi
    RELV="$(release_frozen "$NOW" "$RELMODE")"
    case "$RELV" in
      released=0\ *) : ;;   # nothing came due this tick; the trip block reports the standing debt
      *)
        printf '%s compressor-sentinel: RELEASE mode=%s %s\n' "$TS" "$RELMODE" "$RELV" >&2
        printf 'actuator: release mode=%s %s\n' "$RELMODE" "$RELV" >> "$SNAP" 2>/dev/null || true
        ;;
    esac
  fi

  PREV_T="$NOW"; PREV_SEG="$SEG_EST"; PREV_CBU="$CBU"; PREV_SWAP="$SWAP_B"
  PREV_CMP="$COMPRESSIONS"; PREV_DCMP="$DECOMPRESSIONS"

  [ "$TICKS" -gt 0 ] && [ "$TICK" -ge "$TICKS" ] && break
  sleep "$INTERVAL"
done

# KILL the follow-up on exit, never wait for it. A bounded run (--ticks, i.e. the smoke and the
# suite) that tripped on its last tick would otherwise BLOCK for the full 60 s of follow-up
# snapshots. The follow-up exists to capture a ramp we are still watching; once the sentinel is
# leaving, the capture has no consumer.
if [ -n "$FOLLOWUP_PID" ]; then kill "$FOLLOWUP_PID" 2>/dev/null; wait 2>/dev/null; fi
# Zero rows on a bounded run means the machine was unreadable for every tick — that is a broken
# instrument, and it must not exit 0 into an activation script that would read success.
[ "$ROWS" -gt 0 ] || exit 3
exit 0
