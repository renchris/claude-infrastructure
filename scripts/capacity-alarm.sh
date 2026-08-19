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
#   · SHEDS on MEMORY, which is genuinely sheddable and genuinely attributable to sessions. Load is
#     not a shedding quantity: it swung 2.05x (29.15 -> 59.80) at a CONSTANT 31-32 sessions, so no
#     spawn refusal moves it. That argument is about a GATE and it stands unchanged — but it was
#     never an argument for not LOOKING, and this file read it as one for six rungs. Rung 7 (D4
#     below) REPORTS the scheduler axis, because four panics in a row arrived on it while every
#     memory rung read healthy. Watch it; never gate on it.
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
# SEVEN RUNGS, MAX-COMBINED (M9/M9-ext, §11.3). The verdict is the WORST rung, never the last one
# evaluated — so a new term can only ever raise the verdict, never mask an existing one:
#   1. swap GROWTH  >= SWAP_DELTA_MB in SWAP_WINDOW_S ⇒ ALARM   (a LEVEL latches; a DELTA cannot)
#   2. reclaimable headroom   < ALARM_GB/WARN_GB
#   3. kernel pressure level  >= 4 / >= 2      ⇒ ALARM / WARN   (the kernel's own LEADING indicator)
#   4. per-proc phys outlier  > PROC_WARN_GB   ⇒ WARN    (the leak term; report always, gate softly)
#   5. compressor SEGMENTS    >= 70% / >= 45%  ⇒ ALARM / WARN   (the 2026-07-30 panic axis)
#   6. terminal-coalition procs >= 700 / >= 500 ⇒ ALARM / WARN  (the 2026-07-31 panic axis)
#   7. load-average PER CORE  >= 2.5 / >= 1.5   ⇒ ALARM / WARN  (the scheduler axis, D4 below)
#
# WHY RUNG 6 IS NOT PART OF RUNG 4. They count different nouns, and 2026-07-31 proved the
# difference is fatal. That box died with the iTerm2 coalition at 139.5 GiB — 89.6% of all process
# memory — spread across 1,002 child processes. Rung 4 read 1.64 GB and was CORRECT: no single
# process was large. A per-process ceiling cannot see a population explosion, so the mass has to be
# counted as a population or it is not counted at all.
#
# THE CADENCE IS PART OF THE INSTRUMENT — a rung you cannot sample in time is not a rung.
# This ran at StartInterval 600 through the 2026-07-31 panic and could not resolve it: the box went
# from a genuinely healthy sample to dead inside ONE interval (last row OK and 20m23s stale, the row
# due mid-event never landed). The interval is now 60 s, measured at 0.73 s/tick ⇒ ~1.2% of one core.
# Against that event's own growth rate (~68 procs/min off a 257 baseline) 60 s yields rung-6 WARN at
# ~3.6 min and ALARM at ~6.5 min, against death at ~11-12 min — roughly five minutes of ALARM where
# 600 s produced none. tests/capacity-alarm-launchd-path.bats pins the interval, because the number
# living in a plist while the reasoning lives here is exactly how a cadence silently regresses.
#
# WHY NOT A DWELL LOOP (the cheaper-looking design that does not work). Tightening the cadence only
# AFTER a non-green reading can only arm once a bad sample exists, and the 2026-07-31 series went
# green → dead with no non-green sample in between: a dwell would never have armed. Fast always, or
# fast only when it is already too late. This is also why the script still NEVER sleeps or polls
# (R1) — the fix was the interval, not a wait.
#
# WHAT IT STILL DOES NOT DO: it does not ACT. Five minutes of ALARM on an unattended box is five
# minutes of a page nobody reads. Shedding — refusing new session spawns above a coalition ceiling —
# is the only thing that would make this preventive rather than merely early, and it is deliberately
# NOT here: this file's whole design is ALARM-NOT-GATE (see the header below and §8.5.7), and
# flipping that is an operator decision, not a maintenance edit.
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
# ══ THE 2026-08-05 SENSOR POSTMORTEM — three measured defects, fixed below ═══════════════════════
# (docs/research/panic-compressor-2026-08-05.md §5 + §7.5/§7.7. All three are defects of the
# INSTRUMENT, not of the thresholds: the box died while this sampler was running, reporting, and
# paging — and every bit it emitted in the 59 hours before the panic was already known.)
#
# D1 — A LEVEL LATCHES; ONLY A DELTA CARRIES INFORMATION. Rung 1 was `swap_used > 0 ⇒ ALARM`, and
# macOS `vm.swapusage used` decays ~8 MB per 5.5 h and only truly resets at REBOOT. One Aug-2 event
# put 407 MB in the swap file and the rung then read ALARM for 59 hours — 2,961 consecutive ALARM
# rows carrying exactly ONE notification (the first). Three genuinely new signals (max_proc 40 GB,
# segments 53.5%, pressure 2) arrived INSIDE that latch and were invisible, because already-ALARM
# means no state change means no page. So rung 1 now asks whether swap GREW: ALARM iff swap-used
# rose by >= CC_CAP_SWAP_DELTA_MB inside CC_CAP_SWAP_WINDOW_S, measured against this script's OWN
# jsonl log (the log is the state; there is no sidecar to go stale). A large STATIC swap file is
# OK — it is history, not news. Unknown history (no log, rotated log, unparseable rows, a gap
# longer than the window) ⇒ the RUNG reads OK and the row emits `swap_delta_mb:null`: fail-quiet on
# one rung, never on the row, because a delta we cannot compute is not evidence of growth.
#
# D2 — THE PROBE MUST NOT BLOCK ON THE RESOURCE IT MEASURES. rung 5 read the in-use segment count
# from `zprint`, which walks the kernel zone map under the very lock a compressor storm contends.
# The 00:14 sample never returned: it was still TH_WAIT at the panic, so the one row that would
# have shown the ramp is the row the storm ate. No interval fixes that. The primary source is now
# the CHEAP ESTIMATE from §7.7 — in-core segments from vm_stat's compressor pages, swapped-out
# segments from vm.swapusage (swap is written in 64 KiB compressed chunks, so both terms are
# 64 KiB/segment) — three counter reads, no zone walk, nothing to block on. zprint survives only
# behind CC_CAP_SEG_SOURCE=zprint and only wrapped in timeout(1).
#
# D3 — PER-RUNG PAGES, because a NEW crossing inside a standing alarm is the signal that matters.
# One fixed slug damped by construction (below) also damped every subsequent rung: once ANY rung
# held the verdict at ALARM there was no state change to page on, so the segment and per-proc
# crossings in the final hour wrote nothing. Each rung now owns capacity-alarm-<rung>.page and
# writes it on ITS OWN transition. The combined fixed-slug page stays exactly as it was — this is
# additive, so nothing that reads the old path breaks.
#
# ══ D4 — THE SCHEDULER AXIS WAS NOT INSTRUMENTED AT ALL (rung 7, added 2026-08-05) ════════════════
# The fourth panic — 2026-08-05 00:18:22, `watchdog timeout: no checkins from watchdogd in 94
# seconds`, bug_type 210, panicFlags 0x802 — makes the panic/saturation correlation 4-for-4
# (07-30, 07-31 x2, 08-05). This sampler reported OK through it at load 25.3 on a 10-core box,
# and it was not wrong about anything it measured: it emitted memory and coalition fields and
# NOTHING ELSE. No load average, no run-queue depth, no CPU term of any kind. Six rungs cannot
# outvote a seventh that does not exist.
#
# The axis is real and it is not memory. The panic is a watchdogd starvation, and the same event
# resampled 8,429 of 9,338 threads with truncated backtraces across 1,317 pids — 9,338 threads on
# 10 cores IS the measurement. (Contrast the three EMPTY stackshots §9 of reso's
# NODE_SEGFAULT_ABRUPT_SESSION_CLOSE_2026-08-02.md reasons from: this one sampled. That doc's
# "42h at load 25 with no panic" hedge is superseded as a reason not to look — see below for what
# it is still evidence OF.)
#
# THE INSTRUMENT: `vm.loadavg` field 1 (the 1-minute average) divided by `hw.ncpu`. The 1-minute
# average, not the 5- or 15-, for two reasons: the watchdog window is 94 s, and a 60 s sampler
# differencing a 15-minute EWMA is reading yesterday. All three are EMITTED, because burst-vs-
# plateau is exactly what the 1-minute number alone cannot tell you, and no historical load series
# for this box exists to calibrate against — the log has to become that series first.
#
# ⚠️ THESE TWO THRESHOLDS ARE NOT CALIBRATED, AND THE COUNTER-EVIDENCE IS SPECIFIC. Same status as
# rung 6's, and stated here so no reader mistakes an ALARM on this rung for "the box is dying":
#   (1) THE SURVIVED POPULATION CONTAINS THE FATAL VALUE. Fatal 2026-08-05: 25.3 on 10 cores =
#       2.53/core. Survived: MACHINE_CAPACITY_V2 §8.5.7 records 13 consecutive samples at a
#       CONSTANT 31-32 sessions spanning 29.15-59.80, i.e. 2.92-5.98/core — every one of them
#       ABOVE the fatal reading, all 13 on a box that lived. reso adds 42 h at load 25 (2.5/core)
#       with no panic. So load-per-core does not separate fatal from survived, and no setting of
#       these two numbers can make it. 13/13 of that window would read ALARM at the 2.5 floor.
#   (2) IT DOES NOT MEASURE THE WEDGE, ONLY THE BURST THAT PRECEDES IT. A thread blocked on a
#       page-in is not on a run queue, and at death 90.3% of backtraces were truncated because
#       userspace was paged out. What lifted load to 25.3 was the allocator — 670 node processes
#       spawned in 720 s, all runnable. That is the leading edge and it is worth seeing; the
#       terminal starvation itself is invisible to this rung by construction.
# It ships anyway, at the commissioned floors (1.5 / 2.5 per core), for rung 5's reason: it is the
# only instrument that can see this axis AT ALL, and a rung that is uncalibrated is still strictly
# more than a rung that is absent. Both floors are seams (CC_CAP_LOAD_WARN_PER_CORE /
# CC_CAP_LOAD_ALARM_PER_CORE) so tuning never needs a code edit, and the false-positive population
# above is EXECUTABLE in the selftest — 5.98/core is pinned as a known false ALARM, so a future
# re-derivation has to argue with a control rather than with this paragraph.
#
# THE RUNG WAS PROVEN AGAINST A REAL LOAD, not only against probes. Measured 2026-08-06 on this box
# with 16 background-band (PRI 4) spinners — the band still counts toward loadavg, because loadavg
# counts RUNNABLE threads and not priority:
#     before  load1 4.16  = 0.42/core → OK    rc 0
#     during  load1 15.17 = 1.52/core → WARN  rc 1   swap=OK headroom=OK pressure=OK maxproc=OK load=WARN
# The rung-state line is the part that matters: the verdict moved and every OTHER rung stayed OK, so
# the red is attributable to rung 7 alone rather than to a coincidence on a busy box. That is the
# one claim a stubbed control can never make, and its absence is how a rung wired to nothing passes
# every unit test ever written for it (tests/capacity-alarm.bats (xxviii)/(xxxii) keep both halves).
#
# WHY A FALSE ALARM HERE IS AFFORDABLE, precisely: this file never refuses anything (ALARM-NOT-GATE),
# per-rung pages fire on the TRANSITION only (D3), so 42 h above the floor writes ONE page, not
# 2,520 — and the combined page is one fixed self-clearing slug. The cost of being wrong is one
# page; the cost of the blindness it replaces was measured four times.
#
# ABSOLUTE-PATH sysctl — now EVERY sysctl site in this file, not just rung 7. This job runs under
# launchd with a PATH the wrapper EXPORTS, and the bare-name class has already cost this repo three
# silently dead rungs (see the plist's own /usr/sbin paragraph). Rung 7 resolved /usr/sbin/sysctl
# directly from the start, falling back to the bare name only when that file is absent.
#
# THE INCUMBENT SITES WERE CONVERTED 2026-08-08 (backlog 2c1388d063bf), closing the deferral this
# paragraph used to record. What made it a deferral: converting them is an edit to a LANDED GUARD,
# because tests/capacity-alarm-launchd-path.bats induced "sysctl is unreachable" by stripping
# /usr/sbin from PATH, and an absolutely-resolved rung is by construction immune to that. The first
# attempt (e6de2e15) converted the sites without touching the guard, so the guard went red and the
# post-land verifier auto-reverted the whole commit (d12a4812) — including three unrelated fixes.
#
# The guard was not stale and it was not wrong; it conflated two things. Its INVARIANT — an
# unreadable sysctl yields a SKIPPED rung, never a fabricated healthy 0 — is exactly right and is
# still pinned. Its MECHANISM for making sysctl unreadable (drop /usr/sbin) was only ever a proxy,
# and hardening the code is precisely what retires a proxy. It now induces the unreadable state
# through the seam ($SYSCTL / CC_CAP_SYSCTL, honoured verbatim), which tests the invariant against
# any resolution strategy, and a NEW test pins the property the old mechanism used to stand for:
# these rungs answer with /usr/sbin off the PATH. That is strictly more than the old pair proved —
# the plist's PATH string is a fact about ANOTHER FILE, it has already been false once, and three
# rungs died silently for the whole time it was.
#
# Seams: CC_CAPACITY_ALARM=off (kill switch) · CC_CAP_WARN_GB (default 8) ·
#        CC_CAP_ALARM_GB (default 3) · CC_CAP_PROC_WARN_GB (default 3) · CC_CAP_LOG ·
#        CC_CAP_PRESSURE_WARN (default 2) · CC_CAP_PRESSURE_ALARM (default 4) ·
#        CC_CAP_TOP (top(1) binary, for stubbing) · CC_CAP_SELFTEST=1 (positive control) ·
#        CC_CAP_COAL_WARN (default 500) · CC_CAP_COAL_ALARM (default 700) ·
#        CC_CAP_PS (ps(1) binary, for stubbing rung 6's tree walk AND the per-session cost walk) ·
#        CC_CAP_PER_SESSION_MB (explicit per-session MB; wins over the live tree-RSS derivation) ·
#        CC_CAP_SWAP_DELTA_MB (default 256) · CC_CAP_SWAP_WINDOW_S (default 600) ·
#        CC_CAP_PRIOR_ROWS (default 15, tail depth of the log's own history) ·
#        CC_CAP_SEG_SOURCE (est | zprint — default est) ·
#        CC_CAP_TIMEOUT (timeout(1) binary, for stubbing the zprint slow lane) ·
#        CC_CAP_LOAD_WARN_PER_CORE (default 1.5) · CC_CAP_LOAD_ALARM_PER_CORE (default 2.5) ·
#        CC_CAP_SYSCTL (sysctl(1) binary for EVERY rung — absolute by default, see D4; an explicit
#          value is honoured verbatim, so =/nonexistent/sysctl is how a test reaches "unreadable")
#
# bash 3.2 safe. Ships to launchd ⇒ tested under /bin/bash.

set -uo pipefail

WARN_GB="${CC_CAP_WARN_GB:-8}"
ALARM_GB="${CC_CAP_ALARM_GB:-3}"
PROC_WARN_GB="${CC_CAP_PROC_WARN_GB:-3}"
# Kernel memorystatus pressure (rung 3). The DEFAULTS ARE UNCHANGED — 2/4 is what the kernel's own
# levels mean and there is nothing to tune here. The seam exists because rung 3 was the only one of
# the seven whose floors were literals, and that asymmetry had a cost paid entirely by the tests: a
# rung with a floor seam can be pinned neutral by a test that does not own it, and a rung without one
# can only be pinned by stubbing sysctl — which is exactly what (xxxii) must NOT do, since its whole
# subject is that the REAL sysctl is reached. So the one un-pinnable ambient input kept turning
# tests/capacity-alarm.bats::(ii) red in postland (5 flake rows, 2026-07-31..08-08), and the fix for
# that test was unavailable until this line existed. Uniform seams, same behaviour.
PRESSURE_WARN="${CC_CAP_PRESSURE_WARN:-2}"
PRESSURE_ALARM="${CC_CAP_PRESSURE_ALARM:-4}"
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
#
# ⚠️ THESE TWO NUMBERS ARE NOT CALIBRATED — measured 2026-08-01, see §8 of the same doc. Every figure
# above reproduces, but only against ONE boot. Two findings bound what this rung can do:
#   (1) WRONG NOUN. The PREVIOUS boot's iTerm2 coalition (331 samples) sat >=500 procs for 3h10m,
#       10 samples >=700, peaking at 996 — and SURVIVED. The fatal sample was 1002. Six processes
#       separate the survived class from the fatal one, so no setting of these thresholds can tell
#       them apart. Mass per process does not separate them either (a SURVIVED kitty sample reads
#       458 MiB/proc vs the fatal 142.6; 234 of 567 survived samples exceed what looked like the
#       healthy ceiling). The one quantity that does is the coalition's TOTAL ANON FOOTPRINT:
#       139.50 GiB fatal vs a 28.18 GiB survived ceiling across every boot -- 4.95x apart with an
#       empty interval, on a 64 GiB box (2.2x oversubscription; the panic was a watchdogd timeout).
#       n=1 fatal sample, so that is an ORDERING, not yet a calibrated threshold.
#   (2) WRONG UNITS. The thresholds were derived from systemstats CoalitionMemory.process_count, but
#       read_coalition_procs() below is a ps tree-walk, which measures 0.57x that (6 time-aligned
#       pairs, mean 0.57, range 0.43-0.62): a coalition keeps reparented orphans, the walk stops at
#       pid 1 by construction. So 500/700 here mean ~877/~1228 coalition procs, and the fatal sample
#       would have walked to ~571 — WARN, never ALARM, on the very event this rung exists for.
# Left AS-IS deliberately: fixing (2) alone would make the rung fire correctly on a quantity that
# (1) shows cannot discriminate. Re-nouning needs a per-coalition FOOTPRINT instrument that does not
# exist yet (summing `ps rss` is the ~2.34x shared-page over-count this header bans above), so it is
# a design change, not a maintenance edit. Backlogged; do not tune these in the meantime.
COAL_WARN="${CC_CAP_COAL_WARN:-500}"
COAL_ALARM="${CC_CAP_COAL_ALARM:-700}"
# Rung 1 is a DELTA (D1 above). 256 MB is a QUARTER of the smallest swap file macOS creates (1 GB)
# and ~32x the ~8 MB/5.5 h decay rate, so decay can never reach it and a real swap-out burst clears
# it in one sample. The window is 10 minutes = 10 samples at the 60 s cadence; the tail depth (15)
# covers it with slack for a missed tick or two without ever re-reading the whole file.
SWAP_DELTA_MB="${CC_CAP_SWAP_DELTA_MB:-256}"
SWAP_WINDOW_S="${CC_CAP_SWAP_WINDOW_S:-600}"
PRIOR_ROWS="${CC_CAP_PRIOR_ROWS:-15}"
# Scheduler saturation (rung 7, D4). Commissioned values, NOT derived ones — read D4 before touching
# them, and read the selftest's 5.98 probe before believing an ALARM here means the box is dying.
LOAD_WARN_PER_CORE="${CC_CAP_LOAD_WARN_PER_CORE:-1.5}"
LOAD_ALARM_PER_CORE="${CC_CAP_LOAD_ALARM_PER_CORE:-2.5}"
# An EXPLICIT override is honoured verbatim; only the DEFAULT falls back. Folding the override into
# the fallback list is how an override stops being one (memory path-resolved-dependency-in-daemon-code).
SYSCTL="${CC_CAP_SYSCTL:-}"
if [ -z "$SYSCTL" ]; then
  if [ -x /usr/sbin/sysctl ]; then SYSCTL=/usr/sbin/sysctl; else SYSCTL=sysctl; fi
fi
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
SWAP_MB="$("$SYSCTL" -n vm.swapusage 2>/dev/null \
            | sed -n 's/.*used = \([0-9.]*\)M.*/\1/p' | head -1)"

# ── the log's own recent history — the state D1 and D3 need, with no sidecar to go stale ─────────
# THE LOG IS THE STATE. A delta needs a baseline and a per-rung transition needs a previous rung
# state; both could have lived in a sidecar file, and a sidecar is one more thing that can be
# missing, stale, or out of sync with the row it claims to describe. The jsonl already records every
# input to every rung, once per minute, durably — so the previous state is READ BACK from it, and
# the row a reader sees is by construction the row the alarm reasoned from.
#
# One awk pass over the tail returns two different things:
#   · the swap BASELINE — the MINIMUM swap_used_mb over rows inside the window. Minimum, not oldest:
#     swap-used decays downward between events, so a trough mid-window followed by growth is exactly
#     the burst rung 1 must catch, and an oldest-row baseline would subtract the decay from the
#     growth and hide it.
#   · the PREVIOUS ROW's rung inputs — re-classified below to recover its per-rung states. No new
#     "rung state" field is invented for this: every input already ships in the row, so a state can
#     always be recomputed, and recomputing means today's thresholds are what a transition is judged
#     against rather than whatever was configured when the old row was written.
#
# ts is converted with days-from-civil arithmetic rather than `date -j -f`, which would be one
# subprocess per row per tick and would put a BSD/GNU flag difference on the hot path. The rows this
# script writes are always `%Y-%m-%dT%H:%M:%SZ`; anything else fails the shape check and is skipped.
NOW_EPOCH="$(date -u +%s 2>/dev/null || echo 0)"
read_prior() { # → "base|head|swapdelta|pressure|maxproc|seg|coal|compressions|decompressions|loadpercore"
  [ -f "$LOG" ] || return 1
  tail -n "$PRIOR_ROWS" "$LOG" 2>/dev/null | awk -v now="$NOW_EPOCH" -v win="$SWAP_WINDOW_S" '
    function jnum(s, key,   v) {
      if (!match(s, "\"" key "\":-?[0-9][0-9.]*")) return ""
      v = substr(s, RSTART, RLENGTH); sub(/^.*":/, "", v); return v
    }
    function jts(s,   v) {
      if (!match(s, "\"ts\":\"[^\"]*\"")) return ""
      v = substr(s, RSTART, RLENGTH); sub(/^"ts":"/, "", v); sub(/"$/, "", v); return v
    }
    function ep(t,   y,mo,d,h,mi,se,yy,era,yoe,doy,doe,days) {
      if (length(t) != 20) return -1
      if (substr(t,5,1) != "-" || substr(t,11,1) != "T" || substr(t,20,1) != "Z") return -1
      y = substr(t,1,4)+0; mo = substr(t,6,2)+0;  d  = substr(t,9,2)+0
      h = substr(t,12,2)+0; mi = substr(t,15,2)+0; se = substr(t,18,2)+0
      if (y < 1970 || mo < 1 || mo > 12 || d < 1 || d > 31) return -1
      yy  = (mo <= 2) ? y - 1 : y
      era = int(yy / 400); yoe = yy - era * 400
      doy = int((153 * (mo + ((mo > 2) ? -3 : 9)) + 2) / 5) + d - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      days = era * 146097 + doe - 719468
      return days * 86400 + h * 3600 + mi * 60 + se
    }
    {
      ts = jts($0); sw = jnum($0, "swap_used_mb")
      if (ts != "" && sw != "") {
        e = ep(ts)
        # A row from the future is clock skew, not data; 5 s of slack absorbs rounding only.
        if (e >= 0 && e <= now + 5 && now - e <= win) {
          if (base == "" || sw + 0 < base + 0) base = sw
        }
      }
      last = $0; n++
    }
    END {
      if (n == 0) exit 1
      printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", base, \
        jnum(last, "headroom_gb"), jnum(last, "swap_delta_mb"), jnum(last, "pressure_level"), \
        jnum(last, "max_proc_gb"), jnum(last, "seg_pct"), jnum(last, "coal_procs"), \
        jnum(last, "compressions"), jnum(last, "decompressions"), jnum(last, "load_per_core")
    }'
}

SWAP_BASE=""; P_HEAD=""; P_SWAP_DELTA=""; P_PRESSURE=""; P_MAX_PROC=""; P_SEG=""; P_COAL=""
P_COMPRESSIONS=""; P_DECOMPRESSIONS=""; P_LOAD=""
PRIOR="$(read_prior || true)"
if [ -n "$PRIOR" ]; then
  IFS='|' read -r SWAP_BASE P_HEAD P_SWAP_DELTA P_PRESSURE P_MAX_PROC P_SEG P_COAL \
                  P_COMPRESSIONS P_DECOMPRESSIONS P_LOAD <<< "$PRIOR"
fi

# The delta itself. Empty when EITHER end is unknown — an unreadable sysctl must not be differenced
# against a real baseline (that is how `${SWAP_MB:-0}` would manufacture a 407 MB "growth" out of a
# PATH regression), and no in-window baseline means no trajectory to report.
SWAP_DELTA=""
if [ -n "$SWAP_MB" ] && [ -n "$SWAP_BASE" ]; then
  SWAP_DELTA="$(awk -v a="$SWAP_MB" -v b="$SWAP_BASE" 'BEGIN{printf "%.2f", a-b}')"
fi

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
# HOW THE COUNT IS READ — and why it is no longer zprint by default (D2 in the header).
#
# zprint's `compressor_segment` row IS the exact in-use descriptor count, root-free, and no sysctl
# exposes that number directly. It is also 89% of this script's wall time and it walks the kernel
# zone map under the lock a compressor storm contends: the 2026-08-05 sample taken 4 minutes before
# the panic entered zprint and never came out (still TH_WAIT at the panic), so the ONE row that
# would have shown the final ramp is the row the storm ate. A probe that blocks on the resource it
# measures is not a sensor, and no cadence change repairs that.
#
# So the primary source is the estimate from panic-compressor-2026-08-05.md §7.7, built from three
# counters that cannot block:
#     in-core segments  = vm_stat "Pages occupied by compressor" x page_size / 65536
#     swapped segments  = vm.swapusage used bytes / 65536
#     seg_est           = in-core + swapped
# Both terms are 64 KiB per segment: swap is written in 64 KiB compressed chunks (exact), and a
# 16 KiB-page box holds four pages per in-core segment — which is why §7.7 states the first term as
# "compressor pages / 4". The page size is read from vm_stat's OWN header rather than assumed, for
# the reason read_mem argues above: assuming 4096 understates an Apple-silicon box 4x.
#
# THE ESTIMATE DELIBERATELY INCLUDES SWAPPED-OUT SEGMENTS. That is not double-counting — it is the
# kernel's own accounting. A segment that has been swapped out still holds its descriptor against
# vm.compressor_segment_limit, which is precisely the ceiling the 2026-07-30 panic hit ("100% of
# segments limit (BAD)") while only 33% of the compressed-PAGES limit was in use. Counting only
# resident segments would under-read exactly the state this rung exists to see.
#
# Column 7 of the zprint row is `cur inuse`, validated 2026-07-30 against zones with known-nonzero
# counts; the `cur size`/`#elts` columns read 0 on this build, so position 7 is the one to parse.
read_segments() { # → "<inuse> <limit> <source>", or nothing when unreadable (never a fabricated 0)
  local to row inuse limit pgsz pages swap_mb sysctl_bin
  # Resolved INSIDE the function rather than read from the file-level $SYSCTL, because this function
  # is EXTRACTED and called standalone by tests/capacity-alarm-segments.bats and by this file's
  # launchd-PATH suite — a bare dependency on a global set elsewhere would make it behave differently
  # under test than in production. An explicit $SYSCTL is still honoured VERBATIM (that is how both
  # suites inject a stub, and the only way to reach the unreadable arm on a host that HAS the binary);
  # absent one, the fallback computes the SAME value the file-level block does, so extracted and
  # shipped behaviour are identical. See the header's D4 paragraph for why this is absolute at all.
  if   [ -n "${SYSCTL+set}" ];  then sysctl_bin="$SYSCTL"
  elif [ -x /usr/sbin/sysctl ]; then sysctl_bin=/usr/sbin/sysctl
  else                               sysctl_bin=sysctl
  fi
  limit="$("$sysctl_bin" -n vm.compressor_segment_limit 2>/dev/null)"
  case "$limit" in ''|*[!0-9]*) return 1 ;; esac
  [ "$limit" -gt 0 ] || return 1

  # SLOW LANE, opt-in only. timeout(1) is REQUIRED, not optional: an unwrapped zprint is the exact
  # hang this fix exists to remove, so an absent timeout means the slow lane is skipped entirely
  # rather than run bare. -k also sends KILL, because a TERM-ignoring child keeps the pipe open and
  # the command substitution would wait on it anyway. (A task wedged in an UNINTERRUPTIBLE kernel
  # wait cannot be rescued by any userspace timeout — which is the whole reason this lane is opt-in
  # and the estimate below is the default.) Any failure falls through to the estimate: a slow lane
  # that deletes the rung when it stalls would be strictly worse than not having it.
  if [ "${CC_CAP_SEG_SOURCE:-est}" = "zprint" ]; then
    to="${CC_CAP_TIMEOUT:-timeout}"
    if command -v "$to" >/dev/null 2>&1 && command -v "${CC_CAP_ZPRINT:-zprint}" >/dev/null 2>&1; then
      row="$("$to" -k 1 3 "${CC_CAP_ZPRINT:-zprint}" 2>/dev/null \
              | awk '$1=="compressor_segment"{print; exit}')"
      inuse="$(printf '%s\n' "$row" | awk '{print $7}')"
      case "$inuse" in
        ''|*[!0-9]*) : ;;
        *) printf '%s %s zprint' "$inuse" "$limit"; return 0 ;;
      esac
    fi
  fi

  # FAST LANE (default). Three counter reads, no zone walk, nothing to block on.
  row="$(vm_stat 2>/dev/null | awk '
    NR == 1 { if (match($0, /page size of [0-9]+ bytes/)) {
                s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); pg = s + 0 } }
    /^Pages occupied by compressor:/ { c = $NF + 0; seen = 1 }
    END { if (pg > 0 && seen) printf "%d %d\n", pg, c }')"
  [ -n "$row" ] || return 1
  pgsz="${row%% *}"; pages="${row##* }"
  case "$pgsz" in ''|*[!0-9]*) return 1 ;; esac
  case "$pages" in ''|*[!0-9]*) return 1 ;; esac
  swap_mb="$("$sysctl_bin" -n vm.swapusage 2>/dev/null \
              | sed -n 's/.*used = \([0-9.]*\)M.*/\1/p' | head -1)"
  case "$swap_mb" in ''|*[!0-9.]*) return 1 ;; esac
  inuse="$(awk -v p="$pages" -v z="$pgsz" -v s="$swap_mb" \
            'BEGIN{printf "%d", (p*z)/65536 + (s*1048576)/65536}')"
  printf '%s %s est' "$inuse" "$limit"
}

# vm_stat's cumulative compression counters. Levels are useless here (a lifetime ratio says nothing
# about now) — they exist so the NEXT row can difference them, which is why they are emitted.
read_vm_counters() { # → "<compressions> <decompressions>", or nothing when unreadable
  vm_stat 2>/dev/null | awk '
    /^Compressions:/   { c = $NF + 0; hc = 1 }
    /^Decompressions:/ { d = $NF + 0; hd = 1 }
    END { if (hc && hd) printf "%d %d\n", c, d }'
}

# Unreadable ⇒ SEG_PCT stays empty ⇒ rung 5 is SKIPPED, never a fabricated healthy 0 (see rung 3's
# identical policy in the header: absent instrument is SKIPPED, only headroom can produce NO-DATA).
SEG_PCT=""; SEG_EST=""; SEG_SOURCE=""
SEG_RAW="$(read_segments || true)"
if [ -n "$SEG_RAW" ]; then
  # shellcheck disable=SC2086  # deliberate word-split of the 3-field read_segments output
  set -- $SEG_RAW
  SEG_EST="$1"; SEG_SOURCE="$3"
  SEG_PCT="$(awk -v a="$1" -v b="$2" 'BEGIN{printf "%.1f", 100*a/b}')"
fi

# ── the two §6 discriminators that separated fatal from survived across all three deaths ──────────
# Neither gates a rung: they are ORDERINGS from one fatal sample each, not calibrated thresholds,
# and inventing a floor for them would be the made-up number in a verdict this file's header bans.
# They are emitted on every row so the threshold can be DERIVED from real history later.
#
# occupancy_pct — pages actually packed per segment, against the 16 a segment can hold. The
# 2026-07-30 panic exhausted every descriptor at 5.3/16 = 33% packing: exhaustion is reachable only
# through UNDER-packing (the pool is provisioned for 124.3 GiB on a 64 GiB box), so a falling
# occupancy while seg_pct climbs is the fragmentation signature.
OCCUPANCY_PCT=""
SEG_PAGES="$("$SYSCTL" -n vm.compressor_segment_pages_compressed 2>/dev/null | tr -dc '0-9')"
if [ -n "$SEG_PAGES" ] && [ -n "$SEG_EST" ] && [ "$SEG_EST" -gt 0 ]; then
  OCCUPANCY_PCT="$(awk -v p="$SEG_PAGES" -v s="$SEG_EST" 'BEGIN{printf "%.1f", 100*p/(16*s)}')"
fi

# thrash_cd_ratio — decompressions per compression since the previous row. The measured fatal
# signature is ~0.60 with ~0% net retention (491 MiB/s in, almost all of it coming straight back
# out); no benign counterpart was observed in 102 h. Null on the first row, on a counter reset
# (reboot), and on an idle interval with no compressions — all three are "no ratio exists", never 0.
COMPRESSIONS=""; DECOMPRESSIONS=""; THRASH_CD_RATIO=""
VM_COUNTERS="$(read_vm_counters || true)"
if [ -n "$VM_COUNTERS" ]; then
  # shellcheck disable=SC2086  # deliberate word-split of the 2-field counter output
  set -- $VM_COUNTERS
  COMPRESSIONS="$1"; DECOMPRESSIONS="$2"
  if [ -n "$P_COMPRESSIONS" ] && [ -n "$P_DECOMPRESSIONS" ]; then
    THRASH_CD_RATIO="$(awk -v c="$COMPRESSIONS" -v d="$DECOMPRESSIONS" \
                           -v pc="$P_COMPRESSIONS" -v pd="$P_DECOMPRESSIONS" \
      'BEGIN{ dc = c - pc; dd = d - pd; if (dc > 0 && dd >= 0) printf "%.2f", dd/dc }')"
  fi
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
PRESSURE="$("$SYSCTL" -n kern.memorystatus_vm_pressure_level 2>/dev/null | tr -dc '0-9')"

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

# ── argv[0] resolution — the discriminator this rung was missing ──────────────────────────────────
# `top -stats command` reports the kernel p_comm, which is derived from the EXECUTABLE IMAGE. Claude
# Code ships an embedded ugrep/bfs and the shell snapshot shadows grep/find to reach them:
# `ARGV0=ugrep "$CLAUDE_CODE_EXECPATH" ...` (zsh) / `exec -a ugrep ...`. So an embedded grep IS the
# claude.exe image with argv[0] rewritten, and the two instruments disagree BY CONSTRUCTION.
#
# Measured live on one process, 2026-08-19, same pid and same moment (pid 71388):
#     top -stats pid,mem,command  ->  71388  10M  claude.exe      <- what this rung read
#     ps -o comm=                 ->  ugrep
#     ps -o command= (argv[0])    ->  ugrep                       <- what it reads now
# Darwin resolves both ps columns through argv[0], so `top` is the ONLY blind one of the three.
# That is why the fallback below is not the bug and this reader is: it is the top(1) path that
# renames every embedded search to the binary that hosts it.
#
# THE MEASUREMENT THAT MOTIVATES THIS (2026-08-19, this box, its own logs). `ugrep` appears 0 times
# in 22,575 rows of capacity-alarm.jsonl, while compressor-sentinel-snap.log — which reads argv —
# caught pid 15222 climbing 6.8 -> 12.2 GB as `ugrep`, printing the whole command line. This alarm
# logged THAT SAME PID in THAT SAME MINUTE as `claude.exe` at 16 GB. One process, two names, and the
# rung kept the one that cannot be acted on: 150 multi-GB events over 20 days all read `claude.exe`,
# so every one of them looked like a session leaking and none of them was.
#
# ARGV[0] ONLY, AND HARD-BOUNDED — full argv is not an option here. argv carries whole agent briefs
# (memory pgrep-f-matches-agent-briefs), so logging it would put multi-KB prompts into a row written
# every ~65 s. `cut -c1-200` bounds the read before awk sees it, and only the BASENAME of argv[0] is
# kept: ~10 bytes per process against ~823 bytes per row today. The field is additive and readers
# that never heard of it are unaffected.
read_argv0() { # $1 = comma-separated pids → lines "<pid> <argv0-basename>"
  [ -n "${1:-}" ] || return 0
  "${CC_CAP_PS:-ps}" -o pid=,command= -p "$1" 2>/dev/null \
    | cut -c1-200 \
    | awk 'NF >= 2 && $1 ~ /^[0-9]+$/ {
             n = split($2, a, "/"); v = a[n]
             gsub(/[^A-Za-z0-9._-]/, "", v)
             if (v != "") print $1, v }'
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
  # Resolved for BOTH producers, so `argv0` is on every row whatever produced it — a field present
  # only on the top(1) path would make its ABSENCE ambiguous between "fallback ran" and "lookup
  # failed", and a reader cannot tell those apart. The fallback itself is already sighted (it reads
  # comm=, which Darwin resolves through argv[0]); this is schema uniformity, not a second fix.
  # The two streams are tagged and fed to one awk rather than passed with -v, so a newline in the map
  # cannot corrupt the program text.
  TOP_PIDS="$(printf '%s\n' "$TOP_PROCS" | awk 'NF { printf "%s%s", (n++ ? "," : ""), $1 }')"
  ARGV0_ROWS="$(read_argv0 "$TOP_PIDS" || true)"
  TOP_JSON="$(
    { printf '%s\n' "$ARGV0_ROWS" | awk 'NF == 2 { print "A " $1 " " $2 }'
      printf '%s\n' "$TOP_PROCS"  | awk 'NF >= 3 { print "T " $0 }'
    } | awk '
      BEGIN { printf "[" }
      $1 == "A" { A[$2] = $3; next }
      $1 == "T" {
        pid = $2; mb = $3
        cmd = $4; for (i = 5; i <= NF; i++) cmd = cmd " " $i
        v = (pid in A) ? A[pid] : ""
        if (n++ > 0) printf ","
        printf "{\"pid\":%s,\"mb\":%s,\"cmd\":\"%s\",\"argv0\":\"%s\"}", pid, mb, cmd, v }
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
# ── ONE ppid walk, shared by rung 6 and the per-session cost derivation ───────────────────────────
# Two callers need the same question answered — "which root, if any, owns this pid?" — over two
# different root sets (terminal apps for rung 6; session roots for the per-session cost below). The
# walk is therefore written ONCE, here, and both callers prepend it to their own awk program. A
# second copy would be a second place for the cycle cap to drift, and the cap is the part that makes
# a corrupt ppid chain survivable at all.
#
# Callers must fill `parent[pid]` and `root[pid]` before calling. Returns the owning root's pid, or
# "" when the chain reaches pid 1, dead-ends, or exceeds the cap. Exceeding the cap drops the
# process (under-counts, never over) — a capacity instrument that spins is worse than one that
# under-reports, and over-reporting is the direction that lies about safety.
TREE_WALK_AWK='
function tree_root(p,   q, d) {
  q = p; d = 0
  while (q != "" && q + 0 > 1 && d < 64) {
    if (q in root) return q
    q = parent[q]; d++
  }
  return ""
}'

read_coalition_procs() { # → "<procs> <app>" for the largest terminal coalition, or nothing
  "${CC_CAP_PS:-ps}" -Ao pid=,ppid=,comm= 2>/dev/null | awk "$TREE_WALK_AWK"'
    { p = $1; pp = $2; c = $3; for (i = 4; i <= NF; i++) c = c " " $i
      sub(/.*\//, "", c)
      parent[p] = pp; pids[++np] = p
      if (c == "iTerm2" || c == "kitty" || c == "ghostty" || c == "Ghostty") root[p] = c }
    END {
      for (i = 1; i <= np; i++) { r = tree_root(pids[i]); if (r != "") cnt[r]++ }
      best = -1; bestn = ""
      for (r in root) if (cnt[r] + 0 > best) { best = cnt[r] + 0; bestn = root[r] }
      if (bestn != "") printf "%d %s\n", best, bestn
    }'
}

# ── per-session memory cost, DERIVED from live session TREES ──────────────────────────────────────
# THE FROZEN CONSTANT WAS ROOT-ONLY, AND THAT IS THE DEFECT (2026-08-11). The 636 MB figure below was
# the mean of summed `ps rss` over session tree ROOTS. A session does not stop at its root: teammates,
# MCP servers and tool children are memory this box is holding on that session's behalf. The same
# research measured 616 MB root-only against 681 MB per whole TREE — so the constant undercounts a
# session by every descendant it owns, and PER_MB is a DIVISOR of headroom, so undercounting the cost
# OVERSTATES how many more sessions fit. That is the unsafe direction for a capacity figure, and it is
# the one direction the surrounding prose promised this number would never be wrong in.
#
# So the cost is MEASURED each tick instead of remembered: sum rss over every process whose ppid chain
# reaches a session root, divide by the number of roots. Roots are matched at the COMMAND POSITION,
# exactly as census() does and for the same measured reason (a whole-argv grep counts wrappers that
# merely NAME a claude binary — see census's prose); nested roots attribute to the OUTERMOST root, so
# a tree is counted once whichever way a future binary forks.
#
# Prints nothing when ps is unreadable or the box holds no session at all. Nothing is a real answer
# here — the caller falls back to the documented constant and SAYS SO in the row, rather than
# rendering a fabricated value (rung 3's policy, and the `${SWAP_MB:-0}` lesson: one value that means
# both "measured" and "could not measure" is how a dead instrument reads as healthy).
read_session_tree_mb() { # → "<total_tree_mb> <trees>", or nothing when unreadable / no sessions
  "${CC_CAP_PS:-ps}" -eo pid=,ppid=,rss=,args= 2>/dev/null | awk "$TREE_WALK_AWK"'
    {
      p = $1; pp = $2; kb = $3; cmd = $4
      if (p !~ /^[0-9]+$/ || pp !~ /^[0-9]+$/ || kb !~ /^[0-9]+$/) next
      parent[p] = pp; pids[++np] = p; kbytes[p] = kb + 0
      if (cmd ~ /claude-code\/bin\/claude\.exe$/ || cmd ~ /node_modules\/\.bin\/claude$/) cand[p] = 1
    }
    END {
      nroot = 0
      # A root whose parent is also a root is a child of an already-counted tree (census(), same
      # reduction): its RSS is attributed to the OUTER root and it is not counted as its own tree.
      for (p in cand) if (!(parent[p] in cand)) { root[p] = 1; nroot++ }
      if (nroot == 0) exit 0
      tot = 0
      for (i = 1; i <= np; i++) if (tree_root(pids[i]) != "") tot += kbytes[pids[i]]
      printf "%.0f %d\n", tot / 1024, nroot
    }'
}

COAL_ROW="$(read_coalition_procs || true)"
COAL_PROCS=""; COAL_APP=""
if [ -n "$COAL_ROW" ]; then
  COAL_PROCS="${COAL_ROW%% *}"
  COAL_APP="${COAL_ROW#* }"
fi

# ── scheduler saturation (rung 7) — the axis four panics arrived on, previously not instrumented ──
# Two counter reads, no walk, nothing to block on — the D2 property rung 5 had to be rebuilt to get.
#
# THE BRACES ARE PART OF THE OUTPUT: `vm.loadavg` prints `{ 6.22 6.31 8.23 }`, so the three averages
# are fields 2-4 of the raw line. They are stripped instead of indexed around, because a build that
# omits them would silently shift every index by one and hand rung 7 the 5-minute average while
# still looking correct. After the gsub the fields are the numbers on BOTH shapes, and each is
# shape-checked: a non-numeric field means the format changed, which is an unreadable instrument
# (rung SKIPPED), never a value to divide.
#
# hw.ncpu is the denominator the spec names. Note what it flattens on Apple silicon: P- and E-cores
# count alike, so N/ncpu treats an E-core as a full core and UNDER-states saturation on an
# efficiency-heavy mix. Wrong in the quiet direction, which is the wrong direction for an alarm —
# recorded here rather than corrected, because a correction factor nobody measured is the made-up
# number in a verdict this header bans.
read_load() { # → "<load1> <load5> <load15> <ncpu>", or nothing when unreadable
  local n row
  n="$("$SYSCTL" -n hw.ncpu 2>/dev/null | tr -dc '0-9')"
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  [ "$n" -gt 0 ] || return 1
  row="$("$SYSCTL" -n vm.loadavg 2>/dev/null | awk '
    NR == 1 {
      gsub(/[{}]/, "")            # assigning $0 re-splits: fields become the three averages
      if (NF >= 3 && $1 ~ /^[0-9]+(\.[0-9]+)?$/ && $2 ~ /^[0-9]+(\.[0-9]+)?$/ \
                  && $3 ~ /^[0-9]+(\.[0-9]+)?$/) printf "%s %s %s\n", $1, $2, $3
    }')"
  [ -n "$row" ] || return 1
  printf '%s %s' "$row" "$n"
}

LOAD_1M=""; LOAD_5M=""; LOAD_15M=""; NCPU=""; LOAD_PER_CORE=""
LOAD_RAW="$(read_load || true)"
if [ -n "$LOAD_RAW" ]; then
  # shellcheck disable=SC2086  # deliberate word-split of the 4-field read_load output
  set -- $LOAD_RAW
  LOAD_1M="$1"; LOAD_5M="$2"; LOAD_15M="$3"; NCPU="$4"
  LOAD_PER_CORE="$(awk -v l="$LOAD_1M" -v n="$NCPU" 'BEGIN{printf "%.2f", l/n}')"
fi

# ── positive control (R6) — prove the ladder can reach every rung ─────────────────────────────────
# Without this, "OK" is indistinguishable from "the thresholds are unreachable". Runs the SAME
# classify function against synthetic inputs, so it tests the real code path, not a description.
#
# MAX-COMBINED, not first-match. The rungs are evaluated into a severity level and the WORST wins, so
# adding a rung can only raise a verdict. The incumbent returned on first match, which would have let
# a later-added rung be shadowed — and worse, would have made rung ORDER a silent policy decision.
#
# PER-RUNG DETAIL is a MODE of this same function, never a second implementation. D3 needs each
# rung's own state to page on its own transition, and the one thing that must never happen is a
# threshold living in two places and drifting: the verdict would then disagree with the page it
# writes. With CC_CAP_RUNG_DETAIL=1 the output becomes
#     "<VERDICT> swap=<S> headroom=<S> pressure=<S> maxproc=<S> segments=<S> coalition=<S> load=<S>"
# where <S> is OK | WARN | ALARM | SKIPPED. Unset, the output is byte-identical to what every
# existing caller and control already expects.
classify() { # <headroom_gb> <swap_delta_mb> [pressure] [max_proc_gb] [seg_pct] [coal_procs] [load_per_core] → verdict
  local h="$1" sd="$2" pl="${3:-}" mp="${4:-}" sg="${5:-}" cp="${6:-}" lp="${7:-}" v=0
  local r1=SKIPPED r2=SKIPPED r3=SKIPPED r4=SKIPPED r5=SKIPPED r6=SKIPPED r7=SKIPPED
  # headroom is the ONE instrument the verdict cannot exist without (see header).
  if [ -z "$h" ]; then
    printf 'NO-DATA'
    [ "${CC_CAP_RUNG_DETAIL:-0}" = 1 ] && printf ' swap=%s headroom=%s pressure=%s maxproc=%s segments=%s coalition=%s load=%s' \
      SKIPPED SKIPPED SKIPPED SKIPPED SKIPPED SKIPPED SKIPPED
    return 0
  fi

  # rung 1 — swap GROWTH inside the window (D1). A LEVEL is history and latches for days; only the
  # delta is news. Unknown delta ⇒ SKIPPED, never a fabricated OK-because-zero: the leading `-` is
  # stripped before the numeric shape test so a DECAYING swap file reads as the non-event it is.
  case "${sd#-}" in
    ''|*[!0-9.]*) : ;;
    *) if awk -v a="$sd" -v b="$SWAP_DELTA_MB" 'BEGIN{exit !(a+0 >= b+0)}'; then r1=ALARM; v=2
       else r1=OK; fi ;;
  esac

  # rung 2 — reclaimable headroom: what actually decides whether the box swaps.
  if awk -v a="$h" -v b="$ALARM_GB" 'BEGIN{exit !(a+0 < b+0)}'; then
    r2=ALARM; v=2
  elif awk -v a="$h" -v b="$WARN_GB" 'BEGIN{exit !(a+0 < b+0)}'; then
    r2=WARN; if [ "$v" -lt 1 ]; then v=1; fi
  else
    r2=OK
  fi

  # rung 3 — kernel pressure level (M9-ext). Absent ⇒ SKIPPED, never NO-DATA (header).
  case "$pl" in
    ''|*[!0-9]*) : ;;
    *) if [ "$pl" -ge "$PRESSURE_ALARM" ]; then r3=ALARM; v=2
       elif [ "$pl" -ge "$PRESSURE_WARN" ]; then r3=WARN; if [ "$v" -lt 1 ]; then v=1; fi
       else r3=OK
       fi ;;
  esac

  # rung 4 — per-proc footprint outlier (M9b). WARN ceiling by design: one big process is a lead to
  # follow, not grounds to declare the box in trouble.
  if [ -n "$mp" ]; then
    if awk -v a="$mp" -v b="$PROC_WARN_GB" 'BEGIN{exit !(a+0 > b+0)}'; then
      r4=WARN; if [ "$v" -lt 1 ]; then v=1; fi
    else
      r4=OK
    fi
  fi

  # rung 5 — compressor SEGMENT saturation (2026-07-30 panic). Reaches ALARM, unlike rung 4: this is
  # the axis the machine actually died on, and it dies with memory and swap both reading healthy.
  # Absent instrument ⇒ SKIPPED (rung 3's policy), never a fabricated OK.
  case "$sg" in
    ''|*[!0-9.]*) : ;;
    *) if awk -v a="$sg" -v b="$SEG_ALARM_PCT" 'BEGIN{exit !(a+0 >= b+0)}'; then r5=ALARM; v=2
       elif awk -v a="$sg" -v b="$SEG_WARN_PCT" 'BEGIN{exit !(a+0 >= b+0)}'; then
         r5=WARN; if [ "$v" -lt 1 ]; then v=1; fi
       else r5=OK
       fi ;;
  esac

  # rung 6 — terminal-coalition process population (2026-07-31 panic). Reaches ALARM: this is the
  # axis that box died on, and it died with rungs 1-5 all reading healthy 20 minutes earlier.
  # Absent instrument ⇒ SKIPPED (rung 3's policy), never a fabricated OK.
  case "$cp" in
    ''|*[!0-9]*) : ;;
    *) if [ "$cp" -ge "$COAL_ALARM" ]; then r6=ALARM; v=2
       elif [ "$cp" -ge "$COAL_WARN" ]; then r6=WARN; if [ "$v" -lt 1 ]; then v=1; fi
       else r6=OK
       fi ;;
  esac

  # rung 7 — scheduler saturation (D4). Reaches ALARM: this is the axis all four panics arrived on,
  # and on 2026-08-05 it stood at 2.53/core while every rung above it read healthy. Absent
  # instrument ⇒ SKIPPED (rung 3's policy), never a fabricated OK — a dead sysctl reading as load 0
  # would be the launchd-PATH failure shape exactly, on the one rung whose sensor is a daemon read.
  case "$lp" in
    ''|*[!0-9.]*) : ;;
    *) if awk -v a="$lp" -v b="$LOAD_ALARM_PER_CORE" 'BEGIN{exit !(a+0 >= b+0)}'; then r7=ALARM; v=2
       elif awk -v a="$lp" -v b="$LOAD_WARN_PER_CORE" 'BEGIN{exit !(a+0 >= b+0)}'; then
         r7=WARN; if [ "$v" -lt 1 ]; then v=1; fi
       else r7=OK
       fi ;;
  esac

  case "$v" in 2) printf 'ALARM' ;; 1) printf 'WARN' ;; *) printf 'OK' ;; esac
  [ "${CC_CAP_RUNG_DETAIL:-0}" = 1 ] && printf ' swap=%s headroom=%s pressure=%s maxproc=%s segments=%s coalition=%s load=%s' \
    "$r1" "$r2" "$r3" "$r4" "$r5" "$r6" "$r7"
  return 0
}

if [ "${CC_CAP_SELFTEST:-0}" = "1" ]; then
  fails=0
  # Every rung, in both directions, plus the three cases that are POLICY rather than arithmetic:
  # max-combine (a WARN rung must not downgrade an ALARM), an unreadable pressure level staying OK,
  # and the outlier rung being unable to reach ALARM.
  # probe = headroom:swapDELTA:pressure:maxproc:seg:coalprocs:want
  #
  # The rung-1 rows encode the 59-hour latch directly (D1). Field 2 is now a DELTA, so `99:0:...:OK`
  # IS the 407 MB static swap file that held this alarm at ALARM for 2,961 consecutive rows: no
  # growth, no news. `99:-8:...` is the measured decay rate (~8 MB / 5.5 h) — a swap file draining
  # must never page. `99:255` / `99:256` pin the floor from both sides, and `1:?:...:ALARM` proves an
  # unknown delta SKIPS its own rung without masking a breach found by another.
  # The rung-5 rows encode the 2026-07-30 panic directly: `99:0:1:0:100::ALARM` is the machine's
  # actual dying state — abundant headroom, zero swap, normal pressure, no outlier process, and
  # segments at 100%. Every pre-existing rung called that box HEALTHY, which is the whole point.
  #
  # The rung-6 rows do the same for 2026-07-31: `99:0:1:0::1002:ALARM` is THAT machine's dying
  # state, and `99:0:1:0::353:OK` is the highest reading of the 38 healthy samples it was derived
  # from — that row is the no-false-positive claim, executable. If a future threshold edit makes
  # 353 fire, this control goes RED rather than the fleet learning it the expensive way.
  #
  # The rung-7 rows carry the load axis in BOTH directions, and two of them are named events rather
  # than round numbers. `2.53` is the 2026-08-05 fatal sample itself (load 25.3 on 10 cores) — the
  # executable form of "this rung would have fired on the panic it was commissioned for", where the
  # shipped sampler emitted no CPU field at all. `5.98` is the opposite claim and it is deliberately
  # pinned as an ALARM the box SURVIVED (MACHINE_CAPACITY_V2 §8.5.7's highest of 13 consecutive
  # samples at a constant 31-32 sessions): the false-positive population is part of this rung's
  # specification, not a defect discovered later, and anyone re-deriving these floors has to move
  # that row rather than a comment. `0` proves a genuinely idle box is a READING, not a skip.
  for probe in \
      "99:0:1:0::::OK"      "5:0:1:0::::WARN"   "1:0:1:0::::ALARM" "99:512:1:0::::ALARM" ":0:1:0::::NO-DATA" \
      "99:0:2:0::::WARN"    "99:0:4:0::::ALARM" "99:0:1:9::::WARN" "5:0:4:0::::ALARM"    "1:0:1:9::::ALARM" \
      "99:0::0::::OK"       "99:0:1:::::OK" \
      "99:0:1:0:100:::ALARM" "99:0:1:0:70:::ALARM" "99:0:1:0:45:::WARN" "99:0:1:0:44:::OK" \
      "99:0:1:0:0:::OK"      "99:0:1:0:?:::OK"     "1:0:1:0:0:::ALARM"  "99:0:1:9:100:::ALARM" \
      "99:0:1:0::1002::ALARM" "99:0:1:0::700::ALARM" "99:0:1:0::699::WARN" "99:0:1:0::500::WARN" \
      "99:0:1:0::499::OK"     "99:0:1:0::353::OK"    "99:0:1:0::?::OK"     "1:0:1:0::353::ALARM" \
      "99:0:1:0:100:1002::ALARM" \
      "99:256:1:0::::ALARM"   "99:255:1:0::::OK"     "99:-8:1:0::::OK"     "99:?:1:0::::OK" \
      "1:?:1:0::::ALARM" \
      "99:0:1:0:::0:OK"       "99:0:1:0:::0.62:OK"   "99:0:1:0:::1.49:OK"  "99:0:1:0:::1.5:WARN" \
      "99:0:1:0:::2.49:WARN"  "99:0:1:0:::2.5:ALARM" "99:0:1:0:::2.53:ALARM" \
      "99:0:1:0:::5.98:ALARM" "99:0:1:0:::?:OK"      "1:0:1:0:::?:ALARM" \
      "99:0:1:0:100::2.53:ALARM"; do
    h="${probe%%:*}";  r="${probe#*:}"
    s="${r%%:*}";      r="${r#*:}"
    pl="${r%%:*}";     r="${r#*:}"
    mp="${r%%:*}";     r="${r#*:}"
    sg="${r%%:*}";     r="${r#*:}"
    cp="${r%%:*}";     r="${r#*:}"
    lp="${r%%:*}";     want="${r#*:}"
    got="$(classify "$h" "$s" "$pl" "$mp" "$sg" "$cp" "$lp")"
    if [ "$got" = "$want" ]; then
      echo "  control OK   headroom='$h' swap_delta='$s' pressure='$pl' maxproc='$mp' seg='$sg' coal='$cp' load='$lp' → $got"
    else
      echo "  control FAIL headroom='$h' swap_delta='$s' pressure='$pl' maxproc='$mp' seg='$sg' coal='$cp' load='$lp' → $got (want $want)"
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
  # Rung 7's instrument is the only one in this file whose sensor is a DAEMON-context sysctl read,
  # and the bare-name class is not hypothetical here — it is LIVE: every capacity-gate row in
  # handoffs.jsonl reads `hw.ncpu unreadable ('') — load term not evaluated`, which is this exact
  # sysctl resolved by bare name from a hook context. So the control is not "does it return a
  # number", it is "does it return one with /usr/sbin OFF the PATH" — the launchd shape exactly. A
  # rung that only answers from an interactive shell is the 2026-07-30 defect under a new name, and
  # it would present as a permanently-SKIPPED rung nobody notices.
  lr="$(read_load || true)"
  lr_nopath="$( PATH=/usr/bin:/bin; read_load 2>/dev/null || true )"
  if [ -z "$lr" ]; then
    echo "  control FAIL load — read_load returned nothing; rung 7 would be permanently SKIPPED"
    fails=$((fails+1))
  else
    # shellcheck disable=SC2086  # deliberate word-split of the 4-field read_load output
    set -- $lr
    if [ "$#" -eq 4 ] && [ "${4:-0}" -ge 1 ] 2>/dev/null \
       && awk -v l="${1:-}" 'BEGIN{exit !(l+0 >= 0)}'; then
      echo "  control OK   load ${1} (1-min) on ${4} cores = $(awk -v l="$1" -v n="$4" \
        'BEGIN{printf "%.2f", l/n}')/core   (warn ${LOAD_WARN_PER_CORE} · alarm ${LOAD_ALARM_PER_CORE})"
    else
      echo "  control FAIL load — read_load gave '$lr', not '<l1> <l5> <l15> <ncpu>' with ncpu>=1"
      fails=$((fails+1))
    fi
  fi
  if [ -n "$lr_nopath" ]; then
    echo "  control OK   load instrument is PATH-INDEPENDENT — reads with /usr/sbin off the PATH"
  else
    echo "  control FAIL load instrument needs /usr/sbin on PATH — it goes SKIPPED under launchd"
    fails=$((fails+1))
  fi
  [ "$fails" -eq 0 ] && { echo "capacity-alarm: selftest GREEN (7 rungs + no-data + census + coalition + load reachable)"; exit 0; }
  echo "capacity-alarm: selftest RED ($fails)" >&2; exit 70
fi

HEAD=""; COMP=""; ACT=""; WIRED=""
if [ -n "$MEM" ]; then
  # shellcheck disable=SC2086  # deliberate word-split of the 4-field python output
  set -- $MEM
  HEAD="${1:-}"; COMP="${2:-}"; ACT="${3:-}"; WIRED="${4:-}"
fi

# The verdict AND the six rung states from ONE call (see classify's DETAIL note) — a second
# evaluation could disagree with the first, and a page that contradicts the verdict beside it is
# worse than no page.
CLASSIFY_OUT="$(CC_CAP_RUNG_DETAIL=1 classify "$HEAD" "$SWAP_DELTA" "$PRESSURE" "$MAX_PROC_GB" "$SEG_PCT" "$COAL_PROCS" "$LOAD_PER_CORE")"
VERDICT="${CLASSIFY_OUT%% *}"
RUNG_STATES="${CLASSIFY_OUT#* }"

# The PREVIOUS row's rung states, recomputed from the inputs it recorded. Empty when there is no
# previous row — and "unknown" must not read as "OK", or the very first WARN after a restart would
# be treated as unchanged and never page.
PREV_STATES=""
if [ -n "$PRIOR" ]; then
  PREV_STATES="$(CC_CAP_RUNG_DETAIL=1 classify "$P_HEAD" "$P_SWAP_DELTA" "$P_PRESSURE" "$P_MAX_PROC" "$P_SEG" "$P_COAL" "$P_LOAD")"
  PREV_STATES="${PREV_STATES#* }"
fi

rung_state() { # <states-string> <rung> → OK|WARN|ALARM|SKIPPED, or empty when unknown
  local t
  case " $1 " in *" $2="*) : ;; *) return 0 ;; esac
  t="${1#*"$2"=}"
  printf '%s' "${t%% *}"
}

case "$VERDICT" in
  OK)      RC=0 ;;
  WARN)    RC=1 ;;
  ALARM)   RC=2 ;;
  *)       RC=3 ;;
esac

# Projected ceiling: how many MORE sessions fit in the reclaimable headroom.
#
# HISTORY — the paragraph below described the FROZEN constant and is kept because its bias argument
# is still the argument for the fallback path; it is SUPERSEDED as a description of the live figure
# by the derivation note further down (2026-08-11). Its "UPPER BOUND / under-promises" claim was only
# ever true of the ROOT-ONLY population it was measured over, which is exactly the hole this row now
# closes: the shared-page overcount it warns about is real, but a whole session tree is bigger than
# one root by more than that overcount inflates it (616 MB root-only vs 681 MB per tree, measured).
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
#
# THE FIGURE IS NOW DERIVED, NOT FROZEN (2026-08-11) — see read_session_tree_mb() for why a root-only
# constant is wrong in the unsafe direction. Three sources, and the row NAMES which one it used:
#   override — CC_CAP_PER_SESSION_MB, honoured verbatim (a measured footprint(1) figure, say)
#   derived  — this tick's live tree RSS ÷ live trees
#   fallback — the documented root-only constant, used ONLY when the derivation could not be made
# The fallback is LABELLED rather than silent for the reason the `?` incident below records: a row
# that cannot say which instrument produced its number is a row a consumer will read as measured.
PER_MB_FALLBACK=636
PER_MB=""
PER_MB_SRC="derived"
if [ -n "${CC_CAP_PER_SESSION_MB:-}" ]; then
  # Shape-checked, because this value lands unquoted in the JSON row: a non-numeric override would
  # break every consumer of the log, which is the same class of defect as the `?` below.
  case "$CC_CAP_PER_SESSION_MB" in
    ''|*[!0-9.]*|.*|*.|*.*.*) : ;;
    *) PER_MB="$CC_CAP_PER_SESSION_MB"; PER_MB_SRC="override" ;;
  esac
fi
if [ -z "$PER_MB" ]; then
  TREE_ROW="$(read_session_tree_mb || true)"
  if [ -n "$TREE_ROW" ]; then
    TREE_MB="${TREE_ROW%% *}"; TREE_N="${TREE_ROW##* }"
    case "$TREE_MB" in ''|*[!0-9]*) TREE_MB="" ;; esac
    case "$TREE_N"  in ''|*[!0-9]*) TREE_N=0 ;; esac
    # 0 trees ⇒ fall back, never divide. PER_MB is itself a DIVISOR two lines below, so a 0 here
    # would take the whole row down rather than merely mis-report it.
    if [ -n "$TREE_MB" ] && [ "$TREE_N" -gt 0 ]; then
      PER_MB="$(awk -v t="$TREE_MB" -v n="$TREE_N" 'BEGIN{printf "%d", t/n}')"
      case "$PER_MB" in ''|0|*[!0-9]*) PER_MB="" ;; esac
    fi
  fi
fi
if [ -z "$PER_MB" ]; then
  PER_MB="$PER_MB_FALLBACK"
  PER_MB_SRC="fallback"
fi
case "$PER_MB_SRC" in
  derived)  PER_MB_NOTE="measured this tick: live session TREES (roots + every descendant), ${TREE_MB:-?} MB over ${TREE_N:-?} trees" ;;
  override) PER_MB_NOTE="from CC_CAP_PER_SESSION_MB" ;;
  *)        PER_MB_NOTE="FALLBACK CONSTANT — tree RSS unreadable or no live session; this figure is ROOT-ONLY and undercounts descendants" ;;
esac
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
# `swap_used_mb` becomes null — NOT 0 — when the sysctl is unreadable. That was the shape the
# launchd-PATH regression exposed (`${SWAP_MB:-0}` renders a dead instrument as the HEALTHY value),
# and under D1 it is no longer merely misleading: a fabricated 0 lands in the log, becomes the next
# tick's in-window MINIMUM, and manufactures a 407 MB "growth" out of a PATH bug. The key is
# unchanged and still present on every row; only the lie is gone.
#
# `compressions`/`decompressions` are emitted because thrash_cd_ratio is a DIFFERENCE: the ratio on
# this row can only be computed from the counters on the last one, so the row has to carry them or
# the discriminator cannot exist. Same reason as swap's baseline — the log is the state.
SEG_SOURCE_JSON='null'
[ -n "$SEG_SOURCE" ] && SEG_SOURCE_JSON="\"$SEG_SOURCE\""
#
# `load_1m` gates the rung; `load_5m`/`load_15m` are emitted because a single 1-minute number cannot
# distinguish a burst from a plateau, and D4's whole calibration problem is that no historical load
# series for this box exists. The log has to BECOME that series before these floors can be re-derived
# from anything better than two panics and thirteen survived samples. `ncpu` ships beside them so a
# row stays interpretable if it is ever read on another machine — a per-core figure whose denominator
# is not in the row is not a measurement, it is a number.
# ── pty census: the finite table nothing on this box was watching (S6.7 Phase E) ─────────────────
# A pty is consumed per PANE. It is the only kernel table on this box sized in HUNDREDS while every
# other is 10^4-10^6, and the only one still at its stock value — so it is the next wall and nothing
# reported it.
#
# 🚨 THE PREDICATE IS THE POINT. `ls /dev/ttys*` matches two disjoint device classes:
#     /dev/ttys000..999   major 16, <user>:tty, created on open and REMOVED on last close  ← the resource
#     /dev/ttys0..ttysf   major 64, root:wheel, present since boot, static legacy BSD nodes ← NOT
# Exactly 16 of the latter, always, allocated to nobody. The naive glob therefore carries a CONSTANT
# +16, and at the 6- and 15-session fleets the program's published figures were taken at, that
# offset WAS the reported effect (2.2 ptys/session where the truth is 1.13). The 3-digit form is not
# a heuristic: slaves are named /dev/ttys%03d, which is also where the ~999 architectural ceiling
# comes from. Detail: docs/research/pty-ceiling-2026-08-09.md.
#
# GAUGE ONLY — it feeds no rung and no verdict here, and no term in the admission gate
# (scripts/lib/capacity-admit.sh is wave D's; a refusing term is operator-gated).
PTY_USED=0
for _p in /dev/ttys[0-9][0-9][0-9]; do [ -e "$_p" ] && PTY_USED=$((PTY_USED+1)); done
# sysctl lives in /usr/sbin, which a restricted PATH does not carry. Resolved absolutely so the
# limit cannot read empty, become 0, and render as a reassuring "0%" — one value meaning both
# "empty" and "could not ask".
PTY_SYSCTL=""
for _c in /usr/sbin/sysctl /sbin/sysctl; do [ -x "$_c" ] && { PTY_SYSCTL="$_c"; break; }; done
[ -z "$PTY_SYSCTL" ] && PTY_SYSCTL="$(command -v sysctl 2>/dev/null || true)"
PTY_MAX=""
[ -n "$PTY_SYSCTL" ] && PTY_MAX="$("$PTY_SYSCTL" -n kern.tty.ptmx_max 2>/dev/null || true)"
case "$PTY_MAX" in ''|*[!0-9]*) PTY_MAX="" ;; esac
PTY_PCT=""
if [ -n "$PTY_MAX" ] && [ "$PTY_MAX" -gt 0 ]; then PTY_PCT=$(( PTY_USED * 100 / PTY_MAX )); fi

JSON="$(printf '{"ts":"%s","verdict":"%s","sessions":%s,"headroom_gb":%s,"compressor_gb":%s,"active_gb":%s,"wired_gb":%s,"swap_used_mb":%s,"warn_gb":%s,"alarm_gb":%s,"est_room_sessions":%s,"per_session_mb_est":%s,"sessions_exe":%s,"sessions_binclaude":%s,"pressure_level":%s,"proc_warn_gb":%s,"max_proc_gb":%s,"seg_pct":%s,"seg_warn_pct":%s,"seg_alarm_pct":%s,"coal_procs":%s,"coal_app":"%s","coal_warn":%s,"coal_alarm":%s,"top_procs":%s,"seg_source":%s,"swap_delta_mb":%s,"swap_delta_floor_mb":%s,"swap_window_s":%s,"occupancy_pct":%s,"thrash_cd_ratio":%s,"compressions":%s,"decompressions":%s,"load_1m":%s,"load_5m":%s,"load_15m":%s,"ncpu":%s,"load_per_core":%s,"load_warn_per_core":%s,"load_alarm_per_core":%s,"ptys_used":%s,"ptys_max":%s,"ptys_pct":%s,"per_session_mb_src":"%s"}' \
  "$TS" "$VERDICT" "$SESSIONS" "${HEAD:-null}" "${COMP:-null}" "${ACT:-null}" "${WIRED:-null}" \
  "${SWAP_MB:-null}" "$WARN_GB" "$ALARM_GB" "$ROOM_JSON" "$PER_MB" \
  "$SESSIONS_EXE" "$SESSIONS_BIN" "${PRESSURE:-null}" "$PROC_WARN_GB" "${MAX_PROC_GB:-null}" \
  "${SEG_PCT:-null}" "$SEG_WARN_PCT" "$SEG_ALARM_PCT" \
  "${COAL_PROCS:-null}" "${COAL_APP:-}" "$COAL_WARN" "$COAL_ALARM" \
  "$TOP_JSON" "$SEG_SOURCE_JSON" "${SWAP_DELTA:-null}" "$SWAP_DELTA_MB" "$SWAP_WINDOW_S" \
  "${OCCUPANCY_PCT:-null}" "${THRASH_CD_RATIO:-null}" \
  "${COMPRESSIONS:-null}" "${DECOMPRESSIONS:-null}" \
  "${LOAD_1M:-null}" "${LOAD_5M:-null}" "${LOAD_15M:-null}" "${NCPU:-null}" \
  "${LOAD_PER_CORE:-null}" "$LOAD_WARN_PER_CORE" "$LOAD_ALARM_PER_CORE" \
  "$PTY_USED" "${PTY_MAX:-null}" "${PTY_PCT:-null}" "$PER_MB_SRC")"

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
      printf 'swap used: %s MB  ·  compressor: %s GB  ·  est. room: ~%s more sessions (~%s MB/session, %s)\n' \
        "${SWAP_MB:-0}" "${COMP:-?}" "${ROOM:-?}" "$PER_MB" "$PER_MB_SRC"
      printf 'sessions: %s trees (%s claude.exe + %s .bin/claude)  ·  kernel pressure level: %s\n' \
        "$SESSIONS" "$SESSIONS_EXE" "$SESSIONS_BIN" "${PRESSURE:-unreadable}"
      printf 'load: %s/%s/%s on %s cores = %s/core (warn %s · alarm %s — UNCALIBRATED, see D4)\n' \
        "${LOAD_1M:-?}" "${LOAD_5M:-?}" "${LOAD_15M:-?}" "${NCPU:-?}" "${LOAD_PER_CORE:-unreadable}" \
        "$LOAD_WARN_PER_CORE" "$LOAD_ALARM_PER_CORE"
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

  # ── PER-RUNG SLUGS (D3) ─────────────────────────────────────────────────────────────────────
  # The combined page above is damped by the verdict, and the verdict is a MAX: once any rung holds
  # it at ALARM, no later rung crossing can change it, so no later rung crossing pages. That is how
  # max_proc 40 GB, segments 53.5% and pressure 2 all arrived unannounced inside a 59-hour swap
  # latch. Each rung now owns its own slug and fires on ITS OWN transition, so a new signal is
  # audible inside a standing alarm.
  #
  # WRITTEN ON CHANGE, NOT ON STATE. A rung that stays ALARM for hours writes once, at the
  # crossing — the file's epoch then means "when this started", which is the question an operator
  # actually has, and 60-second re-writes would reset that clock every tick. The cost is that a
  # hand-deleted page is not recreated while the rung holds; the combined page (rewritten every
  # tick) covers that, and the jsonl covers everything.
  #
  # OK / SKIPPED / NO-DATA all RETRACT, for the same reason the combined page self-clears: a page
  # whose condition has passed is misinformation, and a rung whose instrument just went blind is
  # not asserting anything either.
  for _rung in swap headroom pressure maxproc segments coalition load; do
    _now_state="$(rung_state "$RUNG_STATES" "$_rung")"
    _prev_state="$(rung_state "$PREV_STATES" "$_rung")"
    _rung_page="$PAGES_DIR/capacity-alarm-$_rung.page"
    case "$_now_state" in
      WARN|ALARM)
        [ "$_now_state" = "$_prev_state" ] && continue
        mkdir -p "$PAGES_DIR" 2>/dev/null || true
        case "$_rung" in
          swap)      _detail="swap grew ${SWAP_DELTA:-?} MB in ${SWAP_WINDOW_S}s (floor ${SWAP_DELTA_MB} MB) — now ${SWAP_MB:-?} MB in use" ;;
          headroom)  _detail="reclaimable headroom ${HEAD:-?} GB (warn <${WARN_GB} · alarm <${ALARM_GB}) with ${SESSIONS} live sessions" ;;
          pressure)  _detail="kernel memorystatus pressure level ${PRESSURE:-?} (>=${PRESSURE_WARN} WARN · >=${PRESSURE_ALARM} ALARM)" ;;
          maxproc)   _detail="largest process footprint ${MAX_PROC_GB:-?} GB > ${PROC_WARN_GB} GB floor" ;;
          segments)  _detail="compressor segments ${SEG_PCT:-?}% of limit (warn ${SEG_WARN_PCT}% · alarm ${SEG_ALARM_PCT}%) · source ${SEG_SOURCE:-?} · occupancy ${OCCUPANCY_PCT:-?}% of 16 pages/segment" ;;
          coalition) _detail="${COAL_PROCS:-?} procs in the ${COAL_APP:-?} coalition (warn >=${COAL_WARN} · alarm >=${COAL_ALARM})" ;;
          # NAME the survived counter-example in the page itself. This rung's floors are not
          # calibrated (D4), and an operator who reads "ALARM" without knowing the box has lived
          # above this number for 42 h will shed sessions it did not need to shed.
          load)      _detail="load ${LOAD_1M:-?} (1-min) on ${NCPU:-?} cores = ${LOAD_PER_CORE:-?}/core (warn >=${LOAD_WARN_PER_CORE} · alarm >=${LOAD_ALARM_PER_CORE}) · 5/15-min ${LOAD_5M:-?}/${LOAD_15M:-?} · UNCALIBRATED: 2.53/core was fatal 2026-08-05, 5.98/core survived" ;;
          *)         _detail="" ;;
        esac
        {
          date +%s 2>/dev/null || echo 0
          printf 'capacity rung %s: %s (was %s)\n' "$_rung" "$_now_state" "${_prev_state:-unknown}"
          printf '%s\n' "$_detail"
          printf 'combined verdict this sample: %s  ·  thrash d/c %s\n' \
            "$VERDICT" "${THRASH_CD_RATIO:-n/a}"
          printf 'shed by CLOSING idle sessions (/handoff them). This alarm never refuses a spawn.\n'
          printf 're-run:  %s\n' "$0"
        } > "$_rung_page" 2>/dev/null || true ;;
      *)
        rm -f "$_rung_page" "$_rung_page.notified" 2>/dev/null || true ;;
    esac
  done
fi

if [ "$QUIET" != 1 ] && [ "$WANT_JSON" != 1 ]; then
  echo "capacity-alarm — $TS"
  echo "  live sessions:          ${SESSIONS} trees   (${SESSIONS_EXE} claude.exe + ${SESSIONS_BIN} .bin/claude)"
  echo "  reclaimable headroom:   ${HEAD:-?} GB   (warn <${WARN_GB} · alarm <${ALARM_GB})"
  echo "  compressor / active:    ${COMP:-?} GB / ${ACT:-?} GB"
  # SKIPPED, not "0%" — an unreadable instrument must never render as a healthy reading (2026-07-30).
  echo "  compressor segments:    ${SEG_PCT:-SKIPPED (segment estimate unreadable)}${SEG_PCT:+% of limit  (warn ${SEG_WARN_PCT}% / alarm ${SEG_ALARM_PCT}%, source ${SEG_SOURCE})}"
  echo "  segment occupancy:      ${OCCUPANCY_PCT:-?}% of 16 pages/segment   (low + rising seg% = fragmentation, the 2026-07-30 shape)"
  echo "  thrash (decomp/comp):   ${THRASH_CD_RATIO:-n/a}   (~0.60 sustained with ~0% retention is the fatal signature)"
  echo "  kernel pressure level:  ${PRESSURE:-unreadable}   (>=${PRESSURE_WARN} ⇒ WARN · >=${PRESSURE_ALARM} ⇒ ALARM · absent ⇒ rung skipped)"
  echo "  largest proc footprint: ${MAX_PROC_GB:-?} GB   (warn >${PROC_WARN_GB})"
  # SKIPPED, not "0" — an unreadable ps must never render as an empty, healthy-looking coalition.
  echo "  terminal coalition:     ${COAL_PROCS:-SKIPPED (ps unreadable)}${COAL_PROCS:+ procs in ${COAL_APP}  (warn >=${COAL_WARN} / alarm >=${COAL_ALARM})}"
  # SKIPPED, not "0.00" — a dead sysctl must never render as a perfectly idle box (that is exactly
  # the shape the launchd-PATH regression put on three other rungs).
  echo "  load per core:          ${LOAD_PER_CORE:-SKIPPED (sysctl unreadable)}${LOAD_PER_CORE:+/core   (${LOAD_1M} 1-min on ${NCPU} cores · warn >=${LOAD_WARN_PER_CORE} / alarm >=${LOAD_ALARM_PER_CORE})}"
  echo "  load 1/5/15-min:        ${LOAD_1M:-?} / ${LOAD_5M:-?} / ${LOAD_15M:-?}   (1-min gates; the other two say burst-vs-plateau — UNCALIBRATED, see D4)"
  if [ -n "$TOP_PROCS" ]; then
    printf '%s\n' "$TOP_PROCS" | awk '{ cmd = $3; for (i = 4; i <= NF; i++) cmd = cmd " " $i
                                        printf "      pid %-7s %6s MB  %s\n", $1, $2, cmd }'
  fi
  echo "  ptys (ptmx clones):     ${PTY_USED} / ${PTY_MAX:-unknown}   (${PTY_PCT:-unknown}% of kern.tty.ptmx_max · 1 per PANE · gauge only, feeds no rung)"
  echo "  swap used:              ${SWAP_MB:-unreadable} MB   (a LEVEL never alarms — it latches for days)"
  echo "  swap growth:            ${SWAP_DELTA:-unknown} MB in the last ${SWAP_WINDOW_S}s   (>=${SWAP_DELTA_MB} ⇒ ALARM)"
  echo "  est. room for:          >=${ROOM} more sessions   (~${PER_MB} MB/session · ${PER_MB_SRC}: ${PER_MB_NOTE})"
  echo "  VERDICT:                ${VERDICT}"
  if [ "$VERDICT" = "WARN" ] || [ "$VERDICT" = "ALARM" ]; then
    echo "  This alarm never refuses a spawn. Shed by CLOSING sessions (/handoff the idle ones);"
    echo "  do NOT add a load-based spawn gate — see MACHINE_CAPACITY_V2.md §8.5.7."
  fi
fi
[ "$WANT_JSON" = 1 ] && printf '%s\n' "$JSON"
exit "$RC"
