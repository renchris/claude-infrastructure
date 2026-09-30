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
# WHY A KILL RUNG NOW EXISTS (panic #5, 2026-08-24 — docs/research/panic-2026-08-24-fifth-watchdog.md).
# The original §4a rule was "never SIGKILL: we are the only actor, so we must be the reversible one"
# — macOS ships CONFIG_JETSAM off; the release-kernel compressor-exhaustion branch can only harvest
# IDLE-band processes (measured: jetsam killed 3,109 daemons over 10.9 days for 9.28 GB while the
# storm held 128 GB at band 180), and no_paging_space_action needs ONE process holding >50% of the
# whole compressor — structurally untrippable by a fleet of 200 MB workers. Nothing above us will
# act. Panic #5 measured the missing half of that argument: SIGSTOP stops the RAMP but returns ZERO
# segments (wave-2's frozen pool rode 43.66% → 71.81% on its own already-committed pages), and the
# only observed segment reclaim in five panics was mass worker EXIT (78% → 8% in ~90 s). So freeze
# buys time and only exit gives it back — reversibility preserved to the end is what panicked the
# box. The rung is bounded exactly by custody: SIGKILL is sent ONLY to pids this daemon already
# froze (they passed every exclusion at selection time, verified again by (pid,lstart) at kill
# time), only while ACT=stop, and only when the freeze is demonstrably losing (kill_due). A killed
# dev worker costs a dev-server restart; the alternative cost five kernel panics.
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
#         (400) · CC_SENTINEL_SNAP_AGG_N (15) · CC_SENTINEL_CLIFF_PCT (60) ·
#         CC_SENTINEL_REL_PARENT_PCT (15) · CC_SENTINEL_REL_PARENT_TICKS (3) ·
#         CC_SENTINEL_PARENT_HOLD_MIN_S (600) · CC_SENTINEL_PROBATION_S (300) ·
#         CC_SENTINEL_KILL (on — rides ACT=stop, opt-out) · CC_SENTINEL_KILL_PCT (60) ·
#         CC_SENTINEL_KILL_MIN_HOLD_S (30) · CC_SENTINEL_RELINQUISH_GRACE_S (30)
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
# The probation ledger DERIVES from FROZEN_DB for the same reason FROZEN_DB derives from LOG: it
# records which released SPAWNERS are still inside their re-freeze window, and a test that
# redirected the freeze ledger but not this one would probe the operator's live release history.
PROBATION_DB="${CC_SENTINEL_PROBATION_DB:-${FROZEN_DB%.tsv}-probation.tsv}"
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
# A STORM HAS MEMBERS; A ONE-OFF DOES NOT. With the cohort generalised off the `^node` name
# (2026-09-16), a single freshly-spawned unprotected process over the floor — a compile step that
# happened to start during someone else s storm — would be selectable where before it could not be.
# (This used to name "a browser renderer" as the other example. Renderers are class 2 since
# 2026-09-30 and never reach the cohort at all — see exe_table: three of them cleared this floor.) This floor says the actuator acts on a POPULATION or not at all. It costs nothing
# on any storm this box has ever recorded: the smallest measured cohort is 10 (clang-format, both
# 2026-09-16 panics) and the August node storms ran 250-736. It is the cheap half of the safety
# argument for widening the cohort; the newness gate is the other half.
ACT_MIN_COHORT="${CC_SENTINEL_ACT_MIN_COHORT:-3}"
# SCOPED TO THE NEW CLASS, and the scoping is what makes this change strictly additive. A cohort
# containing a `node`-named member is one the PRE-2026-09-16 selector would also have produced, so
# the floor does not apply to it: every behaviour this actuator shipped with is preserved exactly,
# including acting on a single node worker (tests/compressor-sentinel.bats, the write-ahead case,
# which asserts cohort_n=1 and is the control that caught an unscoped floor changing shipped
# behaviour). Only the capability this diff ADDS is asked to show a population.
ACT_PARENT="${CC_SENTINEL_ACT_PARENT:-on}"
ACT_PARENT_MIN="${CC_SENTINEL_ACT_PARENT_MIN:-3}"   # burst children a parent must own to be a spawner
ACT_PARENT_CAP="${CC_SENTINEL_ACT_PARENT_CAP:-4}"   # most spawners frozen per trip, biggest first
# The unfreeze arm's two bounds. HOLD_MIN matches COOLDOWN by construction so a release can never
# land inside the ramp the freeze interrupted; HOLD_MAX is the ceiling past which an unreleased
# freeze is treated as the incident rather than the remedy (see the release policy above the arm).
HOLD_MIN_S="${CC_SENTINEL_HOLD_MIN_S:-60}"
HOLD_MAX_S="${CC_SENTINEL_HOLD_MAX_S:-600}"
# ── PANIC #5's SEAMS (2026-08-24: the guard froze both waves in time, then SIGCONT'd the wave-2
# spawner at 71.8% of the segment limit on ONE rate-lull tick, and the resumed pool drove 72%→100%
# in ~2 minutes — docs/research/panic-2026-08-24-fifth-watchdog.md). Four mechanisms, one lesson
# each:
#   · CLIFF_PCT — above this level the box is in the death regime whatever the rate says: the trip
#     predicate grows a LEVEL-ONLY arm (the §7.7 OR form, scoped high), census/heavy snapshots are
#     skipped (ticks stretched 10 s → 121-146 s under actuation and trip-4's actuation never
#     reached disk), the cooldown no longer gates re-trips, and one breach tick suffices.
#   · REL_PARENT_* / PARENT_HOLD_MIN_S — a SPAWNER's release is a different decision from a
#     worker's. Workers release on the old clear rule (their exit IS the reclaim); a parent
#     releases only on sustained LOW LEVEL (pct < REL_PARENT_PCT for REL_PARENT_TICKS consecutive
#     clear ticks — level subsumes swap, since swapped segments are half of SEG_EST) after
#     PARENT_HOLD_MIN_S. Never on a one-tick rate lull: srate 536 < 600 at 71.81% full read as
#     "breach over" and released the primed spawner (held 68 s) into a 72%-full compressor.
#   · PROBATION_S — a released parent stays on probation: the FIRST breach tick inside the window
#     re-freezes it immediately, before streak or cooldown are consulted.
#   · KILL_* — the escalation rung (see the header). kill_due says when; custody says whom.
#   · RELINQUISH_GRACE_S — custody reads PROCESS STATE, not only identity. A ledgered pid whose
#     stat reads running/sleeping/idle (R, S, I) was resumed by someone else; once the row is at
#     least this old it is dropped with a belt SIGCONT, never killed. The grace must be at least
#     2 x INTERVAL, so a SIGSTOP sent earlier on the same tick is never misread as a resume; it is
#     raised to that floor when set lower. (2026-09-30T15:51:34Z: the lead SIGCONTed Dia by hand,
#     custody compared only lstart, still owed the row, and the next retrip SIGKILLed the browser.)
CLIFF_PCT="${CC_SENTINEL_CLIFF_PCT:-60}"
REL_PARENT_PCT="${CC_SENTINEL_REL_PARENT_PCT:-15}"
REL_PARENT_TICKS="${CC_SENTINEL_REL_PARENT_TICKS:-3}"
PARENT_HOLD_MIN_S="${CC_SENTINEL_PARENT_HOLD_MIN_S:-600}"
PROBATION_S="${CC_SENTINEL_PROBATION_S:-300}"
KILL="${CC_SENTINEL_KILL:-on}"
KILL_PCT="${CC_SENTINEL_KILL_PCT:-60}"
KILL_MIN_HOLD_S="${CC_SENTINEL_KILL_MIN_HOLD_S:-30}"
RELINQUISH_GRACE_S="${CC_SENTINEL_RELINQUISH_GRACE_S:-30}"
case "$RELINQUISH_GRACE_S" in ''|*[!0-9]*) RELINQUISH_GRACE_S=30 ;; esac
case "$INTERVAL" in ''|*[!0-9]*) : ;; *)
  [ "$RELINQUISH_GRACE_S" -ge $((2 * INTERVAL)) ] || RELINQUISH_GRACE_S=$((2 * INTERVAL)) ;;
esac
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
TICKS_FREEZE_COUNT=0

while [ $# -gt 0 ]; do
  if   [ "$1" = "--ticks" ]; then
    TICKS="${2:-}"
    case "$TICKS" in ''|*[!0-9]*) echo "compressor-sentinel.sh: --ticks needs a non-negative integer" >&2; exit 64 ;; esac
    shift
  elif [ "$1" = "--once" ];  then TICKS=1
  elif [ "$1" = "--panic-scan" ]; then TICKS_PANIC_ONLY=1
  elif [ "$1" = "--freeze-scan" ]; then TICKS_FREEZE_ONLY=1
  elif [ "$1" = "--freeze-incidents" ]; then TICKS_FREEZE_COUNT=1
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0
  else echo "compressor-sentinel.sh: unknown arg '$1'" >&2; exit 64
  fi
  shift
done

# The kill switch stops the ACTUATOR, and --freeze-incidents actuates nothing: it reads a ledger and
# prints an integer. Letting it fall in here would make the count unanswerable exactly when the
# daemon is disabled — and the falsifier on backlog row dabe706c9d79 is that count, so a silent
# empty answer there restores the immortal-row failure the count exists to end. Read-only queries
# answer regardless of whether the sensor is armed.
#
# THE ONE THING THE KILL SWITCH MUST STILL DO IS HAND BACK CUSTODY. A daemon restarted with
# CC_SENTINEL=off over a non-empty ledger would otherwise exit and leave its predecessor's frozen
# pids stopped with no living SIGCONT sender — the stranded state the unfreeze arm exists to end. So
# a would-be loop owner (no --ticks, no read-only mode) with a ledger defers the exit to the drain
# block before the mode dispatch, where the release functions exist; every other off-run exits here
# byte for byte as before.
SENTINEL_OFF_DRAIN=0
if [ "${CC_SENTINEL:-on}" = "off" ] && [ "$TICKS_FREEZE_COUNT" != "1" ]; then
  if [ "$TICKS" -eq 0 ] && [ "$TICKS_PANIC_ONLY" != 1 ] && [ "$TICKS_FREEZE_ONLY" != 1 ] \
     && { [ -s "$FROZEN_DB" ] || [ -s "$PROBATION_DB" ]; }; then SENTINEL_OFF_DRAIN=1
  else echo "compressor-sentinel: disabled (CC_SENTINEL=off)" >&2; exit 0; fi
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
      -v cliff="$CLIFF_PCT" -v iv="$INTERVAL" '
    BEGIN {
      if (iv <= 0) exit 1
      n = 0; why = ""
      # Level AND rate. Level alone is a standing state (this box idles well under 15%); rate alone
      # fires on every benign build. §6 discriminator 1+2: it is the conjunction that has no observed
      # benign counterpart in 102 h.
      if (lim > 0 && seg > lim * pct / 100 && rate > rmin) { why = "seg"; n++ }
      if (dcbu  > cmb * 1048576 / iv) { why = why (n ? "+" : "") "cbu";  n++ }
      if (dswap > smb * 1048576 / iv) { why = why (n ? "+" : "") "swap"; n++ }
      # THE CLIFF ARM — level ALONE, no rate term, above CLIFF_PCT (panic #5). The AND above is the
      # right discriminator on the way UP; it is wrong at altitude, where a swapout lull read
      # srate 536 < 600 at 71.81% full, manufactured a "clear" tick mid-incident, and the release
      # arm SIGCONTd the primed spawner. Above the cliff the box is in the death regime whatever
      # this tick s rate says: no benign workload SITS at 60% of the segment limit (10.9 days of
      # chronic-pressure baseline never idled above ~8%), so level alone discriminates here in a
      # way it cannot at 15%. This is §7.7 s OR form, scoped to where OR is true.
      if (lim > 0 && cliff > 0 && seg >= lim * cliff / 100) { why = why (n ? "+" : "") "cliff"; n++ }
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
#
# FIELDS 5 AND 6 WERE ADDED 2026-09-16, AFTER TWO PANICS IN 35 MINUTES. Field 5 is the FULL
# executable path and field 6 is a PROTECTION CLASS (a 0/1 flag until 2026-09-30). Both exist because
# the cohort test used to be the executable NAME `^node`, and on 2026-09-16 the thing that killed this
# box twice was named `clang-format`: the actuator selected 0 processes on all 12 trips across both
# storms while ten processes carried 242 GB and 274 GB of anonymous footprint (docs/research/
# kernel-watchdog-panic-2026-09-16.md). Generalising the cohort means the actuator now has to be
# told what it must NEVER touch, and that judgement is made HERE, ONCE, rather than in each of the
# three consumers — three copies of a safety predicate is three chances to drift apart.
#
# FIELD 6 IS A CLASS, AND EVERY CONSUMER READS IT THE SAME WAY: "0" is selectable, ANY other value is
# protected. The selectors test `$6 == "0"`, so adding a class changes no selector body; the value
# says WHY, which is what lets a trip count what it spared instead of reading as a quiet box.
#   0  selectable.
#   1  the path rules below — Apple daemons, claude, the unidentifiable.
#   2  an operator GUI app: a bundle root launchd started, and its whole family at any depth (HELPER,
#      below). `exe_table gui` only.
#   3  a simulator OS image — `….simruntime/Contents/Resources/RuntimeRoot/` is the simulated
#      device's own launchd, lsd and friends. The app UNDER TEST (CoreSimulator/Devices) stays 0.
#
# THE ARGV-BASED EXCLUSIONS (claude-shaped, mcp-shaped) STAY IN THE CONSUMERS, which are the readers
# that have argv. This split is deliberate: every consumer applies BOTH, and neither file can weaken
# the other. The one argv fact read here is the automation switch set below, and only as a pid list —
# argv itself is never buffered.
#
# CLASS 1, and each line is a different failure:
#   · a comm that is not an absolute path — a zombie or exiting process renders as `(git)`, and
#     UNIDENTIFIABLE ⇒ NEVER ACTED ON is this file's polarity throughout. (It also covers pid 0,
#     whose comm is the bare string `kernel_task`.)
#     ONE NARROWING, because on macOS `ps -o comm` is argv[0], NOT the executable. A process started
#     by bare name prints `node`; one that rewrites its title prints the title — the 08-09 spawner
#     rendered as `next-server (v16.2.6)`, and panic #5's 249 workers ran as `node /…/postcss.js`.
#     Protecting every non-absolute comm (790f2dc2d until 2026-09-30) therefore protected exactly the
#     two classes the parent-breaker was written for: replayed, the panic-#5 fixture selected 0 and
#     broke nothing where it must select 5 and break `42897 5 next-server_(v16.2.6)`. So the kernel's
#     exec name (`ps -axo pid=,ucomm=`, which argv rewriting cannot change) is read alongside: when it
#     is exactly `node`, and the comm neither starts with `(` or `<` nor mentions claude, the process
#     is class 0 again, as before 2026-09-16. A failed ucomm read keeps the protection.
#   · /System/, /usr/libexec/, /usr/sbin/, /sbin/ — Apple's own daemons and launchd itself. These
#     are the only processes on the box whose death is an OS-level event rather than a lost job.
#     Measured: the 60 s newness control on a healthy box under load 29 left exactly two survivors,
#     `/usr/libexec/coreduetd` and a `(git)` in parentheses, and these two rules are why the
#     cohort is now empty there instead of two.
#   · /usr/bin and /opt are deliberately NOT protected: a storm generator genuinely can live there
#     (both of 2026-09-16's clang-formats did — one in an Xcode toolchain, one in a venv), and a
#     transient CLI tool's death is not an OS event.
#
# CLASS 2, AND THE CLAIM IT REPLACES. This comment used to say a GUI app is kept out of the cohort by
# the NEWNESS gate in select_stop_targets, because "a browser that has been up for hours is in the
# previous census". REFUTED 2026-09-30: a browser starts a FRESH renderer for every tab, so the tabs
# opened in the minute before a trip are new, unprotected and over the floor, and three of them clear
# ACT_MIN_COHORT — whereupon the browser itself owns the burst and the parent-breaker freezes it.
# Since 790f2dc2d that froze Dia's main process 7 times and SIGKILLed it 4 times (the latest at
# 2026-09-30T15:51:34Z), with WindowServer logging the operator's browser unresponsive in between.
# So a GUI app is now recognised by structure, from three facts:
#   · TOP BUNDLE — the path through the FIRST `.app` component at or below /Applications/ or
#     /Users/<u>/Applications/. Found by split, so vendor folders count (/Applications/Utilities/
#     Adobe…/CCXProcess/CCXProcess.app, /Applications/Pioneer/…).
#   · ROOT — comm ends `.app|.appex|.xpc/Contents/MacOS/<name>` inside a top bundle, the parent is
#     launchd (ppid 1), and argv carries none of the automation switches (--remote-debugging-*,
#     --enable-automation, --headless, --test-type, --user-data-dir=). Automation browsers are
#     routinely reparented to launchd — all twelve ppid-1 Google Chrome roots in the snap log carry one
#     of those switches — so ppid 1 alone cannot tell the operator's app from a harness.
#   · HELPER — a child, at ANY depth, of the root's family that either lives in the same top bundle
#     (bundle-shaped or a plain in-bundle binary — Dia's agent-server), or is TITLE-REWRITTEN (a
#     non-absolute comm that is not a zombie, a shell, claude or a bare `node`). The depth is what Cursor needs: its root runs an extension host that retitles
#     itself `Cursor Helper (Plugin): extension-host …` (class 1 — no path, ucomm not node), which runs
#     `tsserver[6.0.3]: semantic` on the bundled node (ucomm node). The kernel exec name made that
#     tsserver class 0, a grandchild the direct-child rule never reached — selectable, and killable on
#     a retrip. A class 1 member stays 1; it only carries the family on.
#     The chain ENDS at any absolute path outside the bundle — a shell (/bin/zsh, /usr/bin/login), a
#     homebrew node — so an editor's terminal, kitty's shells and everything run in them stay 0, as
#     does anything a shell exec'd directly, in-bundle or not (agent-run headless Blender).
#     THE PLAIN IN-BUNDLE BINARY WAS LEFT AT 0 UNTIL 2026-09-30, on purpose, and it was the one path
#     left into a GUI app: Dia's agent-server (Contents/Resources/agent-server-resources/dist/
#     agent-server, a direct child of the Dia root) is fresh whenever Dia or it restarts, and the live
#     daemon SIGSTOPped it 6 times — so one fresh over-floor node beside it cleared the cohort floor, and
#     the next retrip-over-debt SIGKILLed it, the kill belt listing only classes 2 and 3.
#
# THE NEAR-MISS, still binding, and now carried by the ppid-1 anchor plus one carve-out rather than
# by a substring test: `python3` on this box resolves to Xcode's
# /Applications/Xcode.app/.../Python3.framework/.../Python.app/Contents/MacOS/Python — a framework
# stub, not a GUI app, and the 2026-09-16 spawner. Nothing under `/Contents/Developer/` is ever class
# 2, whatever its parent (the Xcode IDE included), except exactly
# `…/Contents/Developer/Applications/<X>.app/Contents/MacOS/<name>` — which keeps Simulator.app.
#
# CLASS 2 IS COMPUTED ONLY IN `gui` MODE (the trip, the kill belt, the startup sweep): it needs the
# argv read, and the census that runs every minute stays on the plain table. In plain mode a GUI
# process reads 0, which is what puts the long-running ones on the census roster.
exe_classify() { # [gui] — stdin: optional "@N <pid>" (kernel exec name is node), "@A <pid>" (automation argv) and "@OK N|A" (that read completed) marker rows, then "pid ppid rss comm..." rows → six fields, input order, field 6 = class 0|1|2|3
  awk -v gui="${1:-}" '
    function topb(c,   k, q, i, s, t) {
      if (c ~ /^\/Applications\//) s = 3
      else if (c ~ /^\/Users\/[^\/]+\/Applications\//) s = 5
      else return ""
      k = split(c, q, "/"); t = ""
      for (i = 2; i < k; i++) { t = t "/" q[i]; if (i >= s && q[i] ~ /\.app$/) return t }
      return ""
    }
    $1 == "@N" { knode[$2] = 1; next }
    $1 == "@A" { auto[$2] = 1; next }
    $1 == "@OK" { okm[$2] = 1; next }
    $1 ~ /^[0-9]+$/ {
      n++; P[n] = $1; PP[n] = $2; R[n] = $3
      comm = $4; for (i = 5; i <= NF; i++) comm = comm " " $i
      k = split(comm, parts, "/"); base = parts[k]
      prot = 0
      if (comm !~ /^\//) prot = (($1 in knode) && comm !~ /^[(<]/ && comm !~ /claude/) ? 0 : 1
      else if (comm ~ /^\/System\// || comm ~ /^\/usr\/libexec\// \
            || comm ~ /^\/usr\/sbin\// || comm ~ /^\/sbin\//) prot = 1
      if (base == "claude" || base == "claude.exe") prot = 1
      if (!prot && comm ~ /\.simruntime\/Contents\/Resources\/RuntimeRoot\//) prot = 3
      # IN THE BUNDLE is any path through a top bundle, bundle-shaped or not (the Dia agent-server is
      # a plain binary under Contents/Resources); only a bundle-SHAPED one can be a ROOT.
      if (gui == "gui" && !prot \
          && !(comm ~ /\/Contents\/Developer\// \
               && comm !~ /\/Contents\/Developer\/Applications\/[^\/]+\.app\/Contents\/MacOS\/[^\/]+$/)) {
        tb = topb(comm)
        if (tb != "") {
          TB[$1] = tb
          if ($2 == 1 && !($1 in auto) && comm ~ /\.(app|appex|xpc)\/Contents\/MacOS\/[^\/]+$/) ROOT[$1] = tb
        }
      }
      # TITLE-REWRITTEN: no path to judge by, so it inherits its parent family (END). Not a zombie,
      # never claude, never a SHELL — a login shell renders `-zsh`, and a shell is where the operator
      # or an agent starts its OWN work, so it is where a GUI family ends — and never a BARE `node`:
      # argv[0] equal to the exec name is a program something launched by name, not a title, and a
      # node that kitty or an editor launched that way is exactly the storm worker that must stay 0.
      if (gui == "gui" && comm !~ /^\// && comm !~ /^[(<-]/ && comm !~ /claude/ && comm !~ /^node( |$)/ \
          && comm !~ /^(sh|bash|zsh|fish|dash|ksh|tcsh|csh)( |$)/) NA[$1] = 1
      gsub(/[[:space:]]+/, "_", base)
      full = comm; gsub(/[[:space:]]+/, "_", full)
      B[n] = base; F[n] = full; X[n] = prot
    }
    END {
      # z and y, never p: the array-name clash select_break_parents records below. A helper listed
      # BEFORE its root (pid wrap) still resolves here, because every root is known by END.
      # THE FAMILY, to a fixpoint (any depth, in any row order): a root, then every child of a member
      # that is a helper of the SAME top bundle or is title-rewritten. An absolute path outside the
      # bundle (a shell, /usr/bin/login, a homebrew node) ends the chain. A member that is class 1
      # stays 1 — it only carries the family on to its children (the Cursor extension host).
      for (z in ROOT) FAM[z] = ROOT[z]
      ch = 1
      while (ch) {
        ch = 0
        for (j = 1; j <= n; j++) {
          z = P[j]; y = PP[j]
          if ((z in FAM) || !(y in FAM)) continue
          if (((z in TB) && TB[z] == FAM[y]) || (z in NA)) { FAM[z] = FAM[y]; ch = 1 }
        }
      }
      for (j = 1; j <= n; j++) {
        if (X[j] == 0 && (P[j] in FAM)) X[j] = 2
        print P[j], PP[j], R[j], B[j], F[j], X[j]
      }
      # The completion markers ride AFTER the rows, and only when they came in: every reader of
      # this table keys on a numeric $1 or on $6, so they are invisible to all of them but one.
      if ("N" in okm) print "@OK", "N"
      if ("A" in okm) print "@OK", "A"
    }'
}

exe_table() { # [gui] → exe_classify over the live table; `gui` adds the automation-argv read and class 2
  local mode="${1:-}"
  # Three reads, three instants: a pid reused between them can be misread for one tick, and the
  # selectors' ppid-agreement guard still applies to anything this table would let through. ucomm
  # is read in BOTH modes — the census and the trip must agree on who is node.
  # COMPLETION MARKERS. A marker read that fails is SILENT — no @N rows reads as "no node", no @A rows
  # as "no automation" — and each silence moves a class: every bare or retitled node falls back to 1,
  # a flagged Chrome at ppid 1 rises to 2. Selection is safe either way (any class but 0 is spared),
  # but a reader that RESUMES protected rows is not (gui_protected), so each read that ran to exit 0
  # with at least one row says so with `@OK N` / `@OK A`, and exe_classify passes them through.
  { { ps -axo pid=,ucomm= 2>/dev/null && echo '@DONE'; } \
      | awk '$1 == "@DONE" { ok = 1; next } $1 ~ /^[0-9]+$/ { r++ }
             $1 ~ /^[0-9]+$/ && NF == 2 && $2 == "node" { print "@N", $1 }
             END { if (ok && r) print "@OK", "N" }'
    if [ "$mode" = gui ]; then
      { ps -axwwo pid=,args= 2>/dev/null && echo '@DONE'; } \
        | awk '$1 == "@DONE" { ok = 1; next } $1 ~ /^[0-9]+$/ { r++ }
               $1 ~ /^[0-9]+$/ && /--remote-debugging-|--enable-automation|--headless|--test-type|--user-data-dir=/ { print "@A", $1 }
               END { if (ok && r) print "@OK", "A" }'
    fi
    ps -axwwo pid=,ppid=,rss=,comm= 2>/dev/null
  } | exe_classify "$mode"
}

# THE RESUME LIST — the one reader of the class that turns it into a SIGCONT (the kill rung's belt and
# the startup sweep), so it is narrower than "protected": a selector may spare anything that is not 0,
# because sparing is free, but resuming a frozen storm into the cliff is not. Two conditions:
#   · classes 2 and 3 ONLY. Class 1 is also what a FAILED ucomm read makes of every bare or retitled
#     node pid — the whole panic-#5 cohort and its spawner — and the belt read "not 0" as "SIGCONT and
#     drop", so one failed read on a retrip resumed the storm instead of killing it.
#   · a COMPLETE capture: both `@OK N` and `@OK A`. A failed argv read turns a flagged Chrome at ppid 1
#     into a class 2 root with class 2 helpers, and nothing in the rows says so.
# Otherwise the list is empty and the belt ABSTAINS — the rung behaves as it did before the class
# existed, which is design rule (iii): an unreadable table protects nothing extra.
gui_protected() { # [<exe_file>] (else stdin) → " pid pid " of classes 2/3 from a complete capture, else " "
  awk '$1 == "@OK" { ok[$2] = 1; next }
       $1 ~ /^[0-9]+$/ && NF >= 6 && ($6 == "2" || $6 == "3") { l = l " " $1 }
       END { printf "%s ", (("N" in ok) && ("A" in ok)) ? l : "" }' "${1:--}" 2>/dev/null
}

# ── node census (every CENSUS_EVERY ticks) ────────────────────────────────────────────────────────
# → "<node_count> <orphans> <node_rss_mb>|<pid pid ...>". The pid list is what makes the actuator
# able to say "new since 60 s ago" — the burst cohort — instead of stopping the whole fleet.
#
# THE THREE NUMBERS STAY NODE-ONLY; THE PID ROSTER DOES NOT. `n`/`orph`/`nrss` are a logged series
# with 70,000+ rows behind them, so re-defining what they count would silently change the meaning of
# every historical row (memory: changelog-and-tracker-are-different-populations). The ROSTER after
# the `|` is a different object with exactly one consumer — select_stop_targets' "new since the last
# census" test — and generalising it is the whole repair: with a node-only roster, a clang-format pid
# was never in `prev`, so the newness gate was inert for it and the name test was the only thing
# standing between a storm and the actuator. Now every unprotected process over the floor is on the
# roster, so "new" means new.
#
# THE FLOOR IS THE ACTUATOR'S OWN. Roster and cohort must be drawn from the same population or the
# newness test compares two different sets: a process under the floor is never a target, so putting
# it on the roster would only cost string length.
#
# PROTECTED CLASSES 2 AND 3 ARE ON THE ROSTER TOO (class 1 is not: it is never selectable and never
# counted). The census reads the PLAIN table, so a GUI process reads 0 here anyway; class 3 is listed
# explicitly. Neither is ever a target — the point is the trip's "protected-class spared" count, which
# is "class 2/3 over the floor and NOT on the roster", i.e. only the genuinely new ones.
census() { # <rss_floor_kb>
  exe_table | awk -v floor="${1:-0}" '
    $4 ~ /^node/ { c++; rss += $3; if ($2 == 1) orph++ }
    ($6 == "0" || $6 == "2" || $6 == "3") && $3 + 0 >= floor + 0 { pids = pids " " $1 }
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
    # NO BASELINE ⇒ NO GENERIC ARM. `prev` is the previous census roster, and "new since the last
    # census" is the gate doing nearly all of the safety work once the cohort stopped being keyed on
    # one executable name (175 processes over the floor on a healthy box, 2 of them new). An EMPTY
    # roster does not mean "nothing was running" — it means THIS DAEMON HAS NOT YET OBSERVED THE
    # POPULATION, which is true for the first CENSUS_EVERY ticks of every start, i.e. precisely the
    # minute after a reboot. Without this line a trip in that window would read the whole live desktop
    # as newly-spawned and select it. The `node` arm is exempt because it is what the
    # pre-2026-09-16 selector did in the same window, and this diff does not get to change that.
    # Found by the suite, not by review: it reddened the two cases that pin exactly this window.
    BEGIN { has_prev = (prev ~ /[0-9]/) }
    NR == FNR { if ($1 ~ /^[0-9]+$/) { base[$1] = $4; eppid[$1] = $2; eprot[$1] = ($6 == "0" ? 0 : 1) } next }
    $1 ~ /^[0-9]+$/ {
      pid = $1; rss = $3 + 0
      args = ""; for (i = 4; i <= NF; i++) args = args " " $i
      if (!(pid in base)) next                        # named by no exe_table row ⇒ never a target
      if (eppid[pid] != $2) next                      # the two reads disagree on its parent ⇒ ditto
      b = base[pid]
      # WAS `if (b !~ /^node/) next` UNTIL 2026-09-16, and that one line is why this actuator
      # SIGSTOPped 0 processes on all 12 trips of the two panics that day. The cohort is no longer
      # an ALLOW-LIST OF ONE NAME; it is everything the path-protection flag does not forbid. The
      # under-inclusive rule the old comment defended traded "one more tick of ramp" for safety —
      # the measured price of that trade was the whole machine, twice in 35 minutes.
      if (eprot[pid] == 1) next
      if (!has_prev && b !~ /^node/) next             # no observed baseline ⇒ generic arm stands down
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
# THE FOUR EXCLUSIONS, each for a different failure:
#   · pid <= 1 — launchd. It is also where the kernel REPARENTS the children of a spawner that has
#     already exited, so the one bucket guaranteed to clear any threshold is exactly the one whose
#     "parent" no longer exists. (Those ownerless servers are devserver-gc's job, not a signal's.)
#   · this daemon and its launcher — a guard that can freeze its own supervisor is not a guard.
#   · claude/claude.exe by comm, anything claude/mcp-shaped by argv — the same double test the cohort
#     uses, and for the stronger reason: SIGSTOP is only reversible if something is left running to
#     send SIGCONT, and that something is the operator's session.
#   · a parent with no row of its own in this table — it exited between spawning and this read, so
#     there is nothing to stop and nothing to name. Printing it would fabricate a comm.
#
# A SPAWNER THAT IS ITSELF IN THE COHORT IS STILL A SPAWNER. This used to be a fifth exclusion ("it is
# about to be frozen as a child; counting it twice would inflate the count"), and it decided the
# spawner's CUSTODY, not just its count: frozen as a child it was ledgered kind=proc, and the worker
# rules released it after one clear tick past 60 s — the release-into-relapse the spawner rule
# exists to block. It became reachable once the kernel exec name made a retitled next-server class 0:
# a spawner younger than the last census (`next build` always is; panic #5's 42897 spawned at the very
# census that first saw the storm, 13 s before TRIP 1) is new, over the floor, and so IN the cohort.
# It is now printed here like any other spawner, and the loop freezes it once — as a parent.
#
# Only pid → (comm, protected?) is retained, never argv: agent briefs travel in argv (memory
# pgrep-f-matches-agent-briefs), so buffering the table's argv to answer a question about parentage
# would make the instrument allocate in proportion to the fleet at the one moment memory is scarce.
select_break_parents() { # <exe_file> <cohort_pids> <min_children> <cap> <self_pid> <self_ppid>
  awk -v cohort=" $2 " -v min="$3" -v cap="$4" -v self="$5" -v selfp="$6" '
    NR == FNR { if ($1 ~ /^[0-9]+$/) { ebase[$1] = $4; eppid[$1] = $2; eprot[$1] = ($6 == "0" ? 0 : 1) } next }
    $1 ~ /^[0-9]+$/ {
      pid = $1; ppid = $2
      args = ""; for (i = 4; i <= NF; i++) args = args " " $i
      named = (pid in ebase && eppid[pid] == ppid)
      base = named ? ebase[pid] : "?"
      seen[pid] = 1; name[pid] = base
      if (!named) protect[pid] = 1                    # cannot apply the name test ⇒ assume it fails
      if (named && eprot[pid] == 1) protect[pid] = 1   # path-protected (Apple daemon, unnamed)
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

snapshot_trip() { # <ts> <why> <headline> [<cliff 0|1>]
  {
    printf '\n═══ TRIP %s  why=%s ═══\n%s\n' "$1" "$2" "$3"
    if [ "${4:-0}" = "1" ]; then
      # CLIFF: the attribution is skipped, and the skip is PRINTED so an empty section can never be
      # read as an idle box. Panic #5 measured the cost of the full snapshot at exactly the wrong
      # moment: ticks stretched 10 s → 121-146 s under actuation+storm, and TRIP 4's actuation
      # never reached disk. Above the cliff the actuator's speed IS the evidence budget; vm_stat
      # stays (one cheap read, and it carries the free-page count the postmortem needs).
      printf '(cliff regime: attribution SKIPPED to keep the tick fast — see the last full trip above)\n'
    else
      render_attribution "$SNAP_TOPN" "$SNAP_ARGV_MAX" "$SNAP_AGG_N"
    fi
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
# here is indistinguishable from the bug. PANIC #5 REWROTE IT (2026-08-24): the first shape of this
# arm reused the trip predicate's single-tick negation as "breach over" and released EVERYTHING held
# ≥ HOLD_MIN_S, spawners included — so one swapout-lull tick (srate 536 < 600) at 71.81% of the
# segment limit SIGCONTd the primed wave-2 spawner (held 68 s), whose resumed pool drove segments
# 72% → 100% in ~2 minutes and panicked the box. The policy now splits BY KIND, because the two
# kinds fail in opposite directions: a released WORKER exits — worker exit is the only segment
# reclaim ever observed (78% → 8% in ~90 s) — while a released SPAWNER re-mints its pool. And it
# splits by REGIME: above the cliff nothing releases at all, because resuming anything into a
# nearly-full compressor spends the margin the freeze bought.
#   clear   — WORKERS (kind=proc): no trip this tick AND held ≥ HOLD_MIN_S. The normal path,
#             unchanged: the minimum matches the cooldown so we never resume into the ramp we just
#             interrupted. (A "clear" tick can no longer exist above the cliff — the cliff arm of
#             classify_breach keeps WHY non-empty there by construction.)
#   parent  — SPAWNERS (kind=parent) release ONLY when the caller certifies sustained calm
#             (<parent_ok>: pct < REL_PARENT_PCT for REL_PARENT_TICKS consecutive clear ticks —
#             level, not rate; level subsumes swap since swapped segments are half of SEG_EST) AND
#             the freeze has been held ≥ PARENT_HOLD_MIN_S (the observed multi-wave horizon is
#             ~10 min; 68 s was the fatal hold). A released spawner goes on PROBATION. There is NO
#             spawner ceiling, on purpose: a ceiling is a release on a clock, and a clock is what
#             resumed panic #5's primed spawner into a 72%-full compressor. A spawner still held when
#             the freeze starts losing belongs to the kill rung, not to a timer.
#   ceiling — WORKERS ONLY, held HOLD_MAX_S, released even if still in breach — but never in the
#             cliff regime. A frozen worker past its ceiling on a calm-enough box is the guard
#             outliving its emergency; the same worker at 80% full is stored margin, and the
#             escalation rung (kill_due) owns that case, not a resume.
#   exit    — the sentinel is going away (TERM/INT). Unconditional, all kinds. Without this arm a
#             daemon restart strands the whole cohort permanently — and a stranded SIGSTOP with no
#             living SIGCONT sender is strictly worse than a released spawner, because nothing can
#             ever fix it.
#   relinquish — ANY kind, ANY mode but exit: the row is at least RELINQUISH_GRACE_S old and its
#             stat reads R/S/I — someone else resumed it. Dropped with a belt SIGCONT, no probation
#             stamp, and never a kill (kill_escalate applies the same test). The 15:51:34Z Dia kill
#             was a row the lead had resumed by hand, still owed because custody read only lstart.
#   sweep   — the startup custody pass (a loop-owning daemon, ACT=stop). Releases ONLY rows whose
#             pid is on the caller's protected-class list — a GUI app or simulator runtime adopted
#             from a predecessor killed before it could release (a launchd ExitTimeOut during a
#             121-146 s cliff tick defers the TERM trap) — and holds every other row as it stands.
#   Every SIGCONT line carries reason=<exit|protected|calm|clear|hold-max>, a relinquish writes its
#   own RELINQUISH line, a row dropped as gone or reused writes DROP-STALE, and a live row whose
#   frozen-at is unreadable is resumed and writes DROP-MALFORMED — so every custody row ends in the
#   snap log with the arm that ended it.
#
# WHAT MAKES THIS SAFE TO RUN UNATTENDED: we resume ONLY what we froze. Every release is gated on
# (pid, lstart) matching the ledger — read together with the process state in one fork, TZ-pinned on BOTH sides because ps renders lstart in the
# ambient zone and a DST flip would otherwise convict every row at once (memory:
# process-start-time-renders-in-ambient-timezone). A pid that has been recycled onto a different
# process fails that compare and is dropped WITHOUT a signal — SIGCONT to an innocent stopped
# process (a debugger target, an operator ^Z) is the one harm this arm could do, and the guard is
# what forecloses it.
proc_lstart() { # <pid> → TZ-pinned start time, empty if the pid is gone
  TZ=UTC ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//'
}

# THE SAME READ, PLUS THE PROCESS STATE, in ONE fork — so custody costs what it cost before. The
# lstart half is byte-identical to proc_lstart (verified live under /bin/bash 3.2 for $$, 1 and a GUI
# pid); callers split it as `st="${sl%% *}"; cur="${sl#* }"`. Darwin reports a SIGSTOPped task as T,
# which is what lets custody notice that someone ELSE resumed a pid it still thinks it holds.
proc_stat_lstart() { # <pid> → "<stat> <lstart>", empty if the pid is gone
  TZ=UTC ps -o stat=,lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//'
}

# A ledger row's age for a LOG line only. Never arithmetic on an unchecked field: under `set -u` a
# non-numeric frozen-at aborts the caller (see DROP-MALFORMED in release_frozen).
frozen_age() { # <now-epoch> <frozen-at> → seconds held, or `?` when frozen-at is not a number
  case "$2" in ''|*[!0-9]*) printf '?' ;; *) printf '%s' "$(($1 - $2))" ;; esac
}

# The mutex's liveness test, factored so the CC_SENTINEL=off drain asks the same question. Identity
# is (pid, lstart), so a stale pidfile — a dead pid, or a reused one — never reads as an owner.
loop_owner_live() { # <pidfile> → rc 0 when it names a LIVE instance other than $$
  local pid ls
  pid="$(sed -n 1p "$1" 2>/dev/null)"
  ls="$(sed -n 2p "$1" 2>/dev/null)"
  [ -n "$pid" ] && [ -n "$ls" ] && [ "$pid" != "$$" ] && [ "$(proc_lstart "$pid")" = "$ls" ]
}

record_frozen() { # <pid> <kind> <comm> — ledger one REAL SIGSTOP so it can be undone
  local ls
  ls="$(proc_lstart "$1")"
  # No lstart means the process died between the signal and this read. Nothing to owe it.
  [ -n "$ls" ] || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$ls" "$2" "$(date +%s)" "$3" >> "$FROZEN_DB" 2>/dev/null || true
}

# ONE ROW PER FROZEN PROCESS. Identity is (pid, lstart), and nothing used to enforce it: a fresh
# spawner ledgered as a worker on one trip and re-frozen as a parent on the next (panic #5 re-froze
# 42897 at TRIP 2) held TWO rows. release_frozen then SIGCONTed the worker row on the first clear
# tick — resuming the spawner — and read its own SIGCONT, on the parent row later in the same pass,
# as a resume from OUTSIDE: relinquished, no probation stamp, nothing left for the kill rung.
# Merged: kind=parent wins (the stricter custody), the EARLIEST frozen-at is kept (a freeze is as old
# as its first signal), first-seen order is preserved.
#
# WHERE IT RUNS, and why not inside record_frozen: a trip can SIGSTOP up to ACT_CAP (400) processes,
# and a rewrite per signal would spend the actuation window the cliff regime exists to protect. So
# record_frozen stays an append, the loop compacts ONCE after each trip's stop loops, and every
# custody pass (release_frozen, kill_escalate) reads through this — which also settles a ledger
# adopted from a predecessor that wrote duplicates.
frozen_merge() { # <ledger> → the same rows, one per (pid, lstart)
  awk -F'\t' -v OFS='\t' '
    $1 == "" { next }
    {
      k = $1 SUBSEP $2
      if (!(k in A)) { A[k] = $4; K[k] = $3; C[k] = $5; n++; O[n] = k; I[n] = $1; L[n] = $2; next }
      if ($3 == "parent" && K[k] != "parent") { K[k] = "parent"; C[k] = $5 }
      if ($4 ~ /^[0-9]+$/ && (A[k] !~ /^[0-9]+$/ || $4 + 0 < A[k] + 0)) A[k] = $4
    }
    END { for (j = 1; j <= n; j++) { k = O[j]; print I[j], L[j], K[k], A[k], C[k] } }' "$1"
}

# The ledger as custody reads it: merged into a temp file, or the raw ledger if the merge produced
# nothing — a failed merge must never read as an empty ledger, which would drop every row unsignalled.
frozen_read() { # → path to read (the caller removes it when it is not $FROZEN_DB)
  local m
  if m="$(mktemp -t cc-sentinel-frozen)" && frozen_merge "$FROZEN_DB" > "$m" 2>/dev/null && [ -s "$m" ]; then
    printf '%s' "$m"
  else
    [ -n "$m" ] && rm -f "$m" 2>/dev/null
    printf '%s' "$FROZEN_DB"
  fi
}

frozen_compact() { # rewrite the ledger merged — once per trip, after the stop loops
  local m
  [ -s "$FROZEN_DB" ] || return 0
  m="$(frozen_read)"
  [ "$m" = "$FROZEN_DB" ] || mv -f "$m" "$FROZEN_DB" 2>/dev/null || rm -f "$m" 2>/dev/null
}

release_frozen() { # <now-epoch> <mode: clear|ceiling|exit|sweep> [<parent_ok 0|1>] [<cliff 0|1>] [<protected " pid " list>] → "released=N held=N stale=N"
  local now="$1" mode="$2" parent_ok="${3:-0}" cliff="${4:-0}" protp="${5:- }"
  local keep src rel=0 held=0 stale=0 pid ls kind at comm cur age due why sl st
  [ -s "$FROZEN_DB" ] || { printf 'released=0 held=0 stale=0'; return 0; }
  keep="$(mktemp -t cc-sentinel-frozen)" || { printf 'released=0 held=0 stale=0'; return 0; }
  src="$(frozen_read)"                        # one row per process — see frozen_merge
  while IFS="$(printf '\t')" read -r pid ls kind at comm; do
    [ -n "$pid" ] || continue
    sl="$(proc_stat_lstart "$pid")"; st="${sl%% *}"; cur="${sl#* }"
    # Gone, or the pid now belongs to someone else. Either way we owe it nothing and must not signal.
    # Logged per pid: before this line a custody row that ended this way left no record at all, and
    # 73 recorded stops had no recorded end.
    if [ -z "$sl" ] || [ "$cur" != "$ls" ]; then
      stale=$((stale + 1))
      printf 'DROP-STALE pid=%s held_s=%s kind=%s comm=%s (gone or pid reused; no signal)\n' \
        "$pid" "$(frozen_age "$now" "$at")" "$kind" "$comm" >> "$SNAP" 2>/dev/null || true
      continue
    fi
    # AN UNREADABLE FROZEN-AT, on a row whose identity still matches. `read` with a tab IFS collapses
    # an EMPTY field, so a partial write shifts the comm into `at` — and `$((now - at))` under the
    # daemon's `set -u` then aborted this whole function: nothing released, the ledger never rewritten,
    # every frozen pid stranded on every later tick, and self-restart held for good. Without an age no
    # rule can hold it and none may kill it, so the row is handed back with a SIGCONT and dropped —
    # a resumed process is recoverable, a stranded one is not.
    case "$at" in
      ''|*[!0-9]*)
        kill -CONT "$pid" 2>/dev/null
        stale=$((stale + 1))
        printf 'DROP-MALFORMED pid=%s kind=%s comm=%s at=%s (frozen-at unreadable; resumed, custody dropped)\n' \
          "$pid" "$kind" "$comm" "$at" >> "$SNAP" 2>/dev/null || true
        continue ;;
    esac
    age=$((now - at))
    due=0; why=""
    if [ "$mode" = "exit" ]; then
      due=1; why="exit"
    elif case "$protp" in *" $pid "*) true ;; *) false ;; esac; then
      # The caller's protected-class list (the startup sweep): a row whose process is NOW a GUI app or a
      # simulator runtime was adopted from a predecessor that froze it before those classes existed,
      # or before a KeepAlive restart. It was never ours to hold.
      due=1; why=protected
    elif [ "$age" -ge "$RELINQUISH_GRACE_S" ] 2>/dev/null && case "$st" in [RSI]*) true ;; *) false ;; esac; then
      # RESUMED OUTSIDE THE SENTINEL. It is our identity (lstart matched) but no longer our freeze:
      # someone sent SIGCONT. Owing it a later SIGCONT is harmless; owing it a later SIGKILL is what
      # killed Dia at 15:51:34Z. So custody is relinquished — with a belt SIGCONT, a no-op on a
      # running process, so if the T-means-stopped premise were ever wrong it resumes, not strands.
      due=1; why=relinquish
    elif [ "$mode" = "sweep" ]; then
      :   # the sweep releases protected rows and nothing else — every other row keeps its hold
    elif [ "$kind" = "parent" ]; then
      # A spawner never rides the worker rules: not clear-mode (one lull tick is how panic #5
      # happened), not the ceiling (a still-loaded spawner past its ceiling is kill_due's case).
      # Only the caller's sustained-calm certificate, after the parent's own longer minimum hold.
      [ "$parent_ok" = "1" ] && [ "$age" -ge "$PARENT_HOLD_MIN_S" ] && { due=1; why=calm; }
    else
      # Never resume anything in the cliff regime — a resumed worker allocates into a compressor
      # that has no room to hold the margin the freeze bought.
      if [ "$cliff" != "1" ]; then
        [ "$age" -ge "$HOLD_MAX_S" ] && { due=1; why=hold-max; }
        [ "$mode" = "clear" ] && [ "$age" -ge "$HOLD_MIN_S" ] && { due=1; why=clear; }
      fi
    fi
    if [ "$due" -eq 1 ]; then
      kill -CONT "$pid" 2>/dev/null
      rel=$((rel + 1))
      if [ "$why" = "relinquish" ]; then
        printf 'RELINQUISH pid=%s held_s=%s kind=%s comm=%s stat=%s (resumed outside the sentinel; custody dropped, no kill)\n' \
          "$pid" "$age" "$kind" "$comm" "$st" >> "$SNAP" 2>/dev/null || true
      else
        printf 'SIGCONT pid=%s held_s=%s kind=%s comm=%s reason=%s\n' "$pid" "$age" "$kind" "$comm" "$why" \
          >> "$SNAP" 2>/dev/null || true
      fi
      # A released spawner is on probation: the first breach tick inside PROBATION_S re-freezes it
      # without waiting for streak or cooldown (probation_refreeze). Only a CALM release earns the
      # stamp: exit has no later tick to consume it (and a stale stamp would then convict the pid s
      # successor after reuse — the lstart gate already forecloses that, but a stamp nothing can
      # consume is still litter), and a protected row was never a spawner to watch.
      if [ "$kind" = "parent" ] && [ "$why" = "calm" ]; then
        printf '%s\t%s\t%s\t%s\n' "$pid" "$ls" "$now" "$comm" >> "$PROBATION_DB" 2>/dev/null || true
      fi
    else
      held=$((held + 1))
      printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$ls" "$kind" "$at" "$comm" >> "$keep"
    fi
  done < "$src"
  [ "$src" = "$FROZEN_DB" ] || rm -f "$src" 2>/dev/null
  mv -f "$keep" "$FROZEN_DB" 2>/dev/null || rm -f "$keep" 2>/dev/null
  printf 'released=%s held=%s stale=%s' "$rel" "$held" "$stale"
}

# ── PROBATION: a released spawner has not proven anything yet ─────────────────────────────────────
# The stamp is written by release_frozen above; this consumes it. Called only on a BREACH tick
# (WHY non-empty), BEFORE the streak and cooldown gates — those exist to debounce the DETECTOR, and
# a spawner released two minutes ago breaching again is not a detection question, it is the release
# being proven wrong. Same custody discipline as every signal here: (pid,lstart) must match the
# stamp, or the row is dropped without a signal. Expired and stale rows are pruned on every pass so
# the file cannot grow without bound.
probation_refreeze() { # <now-epoch> → "refroze=N" on stdout; re-ledgers each refrozen pid
  local now="$1" keep n=0 pid ls at comm cur
  [ -s "$PROBATION_DB" ] || { printf 'refroze=0'; return 0; }
  keep="$(mktemp -t cc-sentinel-probation)" || { printf 'refroze=0'; return 0; }
  while IFS="$(printf '\t')" read -r pid ls at comm; do
    [ -n "$pid" ] || continue
    [ $((now - at)) -le "$PROBATION_S" ] || continue          # window over: stamp expires silently
    cur="$(proc_lstart "$pid")"
    if [ -z "$cur" ] || [ "$cur" != "$ls" ]; then continue; fi # gone or recycled: never signal
    if kill -STOP "$pid" 2>/dev/null; then
      n=$((n + 1))
      record_frozen "$pid" parent "$comm"
      printf 'SIGSTOP probation pid=%s comm=%s (breach inside %ss of release)\n' \
        "$pid" "$comm" "$PROBATION_S" >> "$SNAP" 2>/dev/null || true
      # Refrozen ⇒ off probation: it is back in FROZEN_DB under the parent rules.
    else
      printf '%s\t%s\t%s\t%s\n' "$pid" "$ls" "$at" "$comm" >> "$keep"
    fi
  done < "$PROBATION_DB"
  mv -f "$keep" "$PROBATION_DB" 2>/dev/null || rm -f "$keep" 2>/dev/null
  printf 'refroze=%s' "$n"
}

# ── THE ESCALATION RUNG: when the freeze is losing, custody converts to a kill ────────────────────
# kill_due is the PREDICATE, pure so the suite can drive it (same contract as classify_breach). The
# freeze is losing exactly when (a) a NEW trip fires while frozen debt is already held — the storm
# is outrunning the freeze (wave 2 landed on top of wave 1's debt) — or (b) the box is above
# KILL_PCT and still climbing (srate > 0) with debt held: the frozen pool's already-committed pages
# are riding the compressor toward the ceiling on their own, which is precisely how 43.66% became
# 71.81% with every storm process SIGSTOPped. Prints the reason; rc 1 when the freeze is holding.
kill_due() { # <pct> <srate> <trip_now 0|1> <debt_n> → reason | rc 1
  awk -v pct="${1:-0}" -v srate="${2:-0}" -v trip="${3:-0}" -v debt="${4:-0}" -v kpct="$KILL_PCT" '
    BEGIN {
      if (debt + 0 < 1) exit 1
      if (trip + 0 == 1) { print "retrip-over-debt"; exit 0 }
      if (pct + 0 >= kpct + 0 && srate + 0 > 0) { print "climbing-at-" kpct "pct"; exit 0 }
      exit 1
    }'
}

# kill_escalate ACTS. The blast radius is bounded by CUSTODY, not by a name list: SIGKILL goes only
# to pids already in FROZEN_DB — they passed select_stop_targets / select_break_parents exclusions
# (never claude/claude.exe, never mcp-shaped, never this daemon or its launcher) at freeze time and
# must STILL match the ledger s (pid,lstart) here, so a recycled pid is untouchable. The comm test
# is re-applied as a belt: a ledger row whose comm now reads claude-shaped is skipped outright.
# WRITE-AHEAD: the intent line is flushed to the snap log BEFORE the first signal — trip 4 of panic
# #5 actuated (or not) with nothing ever reaching disk, and an unevidenced actuation cannot be
# adjudicated afterwards. Killing the whole frozen set, workers included, is deliberate: worker
# exit is the only observed reclaim, and a frozen worker at kill time is exactly the storm cohort
# the selectors chose under their exclusions. Age-gated (KILL_MIN_HOLD_S) so the freeze always gets
# its chance first on the very trip that created the debt.
#
# THE PROTECTED-CLASS BELT (2026-09-30). Custody was the whole blast-radius argument, and custody
# was wrong about Dia: the parent-breaker froze the operator's browser as the "spawner" of its own
# fresh tab renderers, and on the next retrip this rung SIGKILLed it (15:51:34Z). The selectors no
# longer choose GUI apps, but a ledger can hold rows written before that was true, so the class is
# re-derived HERE from the trip's own `exe_table gui` capture (<exe_file>, reused — or read fresh when
# the caller has none) and a ledgered pid of class 2 or 3 is SIGCONTed and dropped, never killed.
# The fail direction is the belt ABSTAINING: an empty or unreadable table — or one whose ucomm or argv
# read failed, which is neither, and which moves classes silently — protects nothing extra and leaves
# the rules above exactly as they were (gui_protected has the two failures this closes).
# REJECTED ON PURPOSE: exempting kind=parent from the kill, and gating retrip-over-debt on a
# non-empty cohort. Both reopen panic #5, whose spawners are exactly the rows this rung exists for.
kill_escalate() { # <now-epoch> <reason> [<exe_file>] → "killed=N spared=N" on stdout
  local now="$1" reason="$2" exef="${3:-}" own="" prot keep src killed=0 spared=0 pid ls kind at comm cur age sl st
  [ -s "$FROZEN_DB" ] || { printf 'killed=0 spared=0'; return 0; }
  src="$(frozen_read)"                        # one row per process — see frozen_merge
  printf 'actuator: KILL-INTENT reason=%s debt=%s (write-ahead: signals follow this line)\n' \
    "$reason" "$(wc -l < "$src" 2>/dev/null | tr -d ' ' || echo '?')" >> "$SNAP" 2>/dev/null || true
  if [ -z "$exef" ] || [ ! -s "$exef" ]; then
    own="$(mktemp -t cc-sentinel-exe)" && exe_table gui > "$own" 2>/dev/null
    exef="$own"
  fi
  prot="$(gui_protected "$exef")"; [ -n "$prot" ] || prot=" "      # classes 2/3, complete capture — else abstain
  keep="$(mktemp -t cc-sentinel-frozen)" || {
    [ -n "$own" ] && rm -f "$own"; [ "$src" = "$FROZEN_DB" ] || rm -f "$src"; printf 'killed=0 spared=0'; return 0; }
  while IFS="$(printf '\t')" read -r pid ls kind at comm; do
    [ -n "$pid" ] || continue
    sl="$(proc_stat_lstart "$pid")"; st="${sl%% *}"; cur="${sl#* }"
    if [ -z "$sl" ] || [ "$cur" != "$ls" ]; then                  # gone/recycled: drop, never signal
      printf 'DROP-STALE pid=%s held_s=%s kind=%s comm=%s (gone or pid reused; no signal)\n' \
        "$pid" "$(frozen_age "$now" "$at")" "$kind" "$comm" >> "$SNAP" 2>/dev/null || true
      continue
    fi
    case "$at" in                                                 # no age ⇒ never killed (release_frozen)
      ''|*[!0-9]*)
        kill -CONT "$pid" 2>/dev/null
        spared=$((spared + 1))
        printf 'DROP-MALFORMED pid=%s kind=%s comm=%s at=%s (frozen-at unreadable; resumed, custody dropped)\n' \
          "$pid" "$kind" "$comm" "$at" >> "$SNAP" 2>/dev/null || true
        continue ;;
    esac
    age=$((now - at))
    case "$comm" in
      claude*|*mcp*)
        # Belt over the selectors suspenders: nothing claude/mcp-shaped should ever have been
        # ledgered, but an escalation that can kill must re-check rather than inherit.
        spared=$((spared + 1))
        printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$ls" "$kind" "$at" "$comm" >> "$keep"
        continue ;;
    esac
    case "$prot" in
      *" $pid "*)
        kill -CONT "$pid" 2>/dev/null
        spared=$((spared + 1))
        printf 'SIGCONT pid=%s held_s=%s kind=%s comm=%s reason=protected-at-kill\n' \
          "$pid" "$age" "$kind" "$comm" >> "$SNAP" 2>/dev/null || true
        continue ;;
    esac
    # Resumed outside the sentinel (release_frozen's relinquish arm, same test): the ROOT CAUSE of the
    # 15:51:34Z kill, where a hand SIGCONT left row 18285 owed and the next retrip killed Dia for it.
    if [ "$age" -ge "$RELINQUISH_GRACE_S" ] 2>/dev/null && case "$st" in [RSI]*) true ;; *) false ;; esac; then
      kill -CONT "$pid" 2>/dev/null
      spared=$((spared + 1))
      printf 'RELINQUISH pid=%s held_s=%s kind=%s comm=%s stat=%s (resumed outside the sentinel; custody dropped, no kill)\n' \
        "$pid" "$age" "$kind" "$comm" "$st" >> "$SNAP" 2>/dev/null || true
      continue
    fi
    # …and a RUNNING row still inside the grace is not ours to kill either. The grace is at least
    # 2×INTERVAL while KILL_MIN_HOLD_S is its own knob, so whenever the grace is the longer of the two
    # (CC_SENTINEL_INTERVAL > 15, or a raised CC_SENTINEL_RELINQUISH_GRACE_S) a row resumed from
    # outside and aged between them fell through to the SIGKILL below — the 15:51:34Z kill again, by
    # configuration. Such a row is held, not killed: the next pass past the grace relinquishes it.
    if [ "$age" -lt "$RELINQUISH_GRACE_S" ] 2>/dev/null && case "$st" in [RSI]*) true ;; *) false ;; esac \
       || [ "$age" -lt "$KILL_MIN_HOLD_S" ]; then
      spared=$((spared + 1))
      printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$ls" "$kind" "$at" "$comm" >> "$keep"
      continue
    fi
    kill -KILL "$pid" 2>/dev/null
    killed=$((killed + 1))
    printf 'SIGKILL pid=%s held_s=%s kind=%s comm=%s reason=%s\n' \
      "$pid" "$age" "$kind" "$comm" "$reason" >> "$SNAP" 2>/dev/null || true
  done < "$src"
  [ "$src" = "$FROZEN_DB" ] || rm -f "$src" 2>/dev/null
  mv -f "$keep" "$FROZEN_DB" 2>/dev/null || rm -f "$keep" 2>/dev/null
  [ -n "$own" ] && rm -f "$own"
  printf 'killed=%s spared=%s' "$killed" "$spared"
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
  # `! -name '.*'` — DOTFILES ARE EXCLUDED, and this exclusion has a body count. macOS stages the
  # live panic text as `.contents.panic` beside the dated report, SAME basename every panic. On
  # 2026-08-18 it won this newest-file race, the ledger recorded report:".contents.panic" — and
  # because the idempotency key is the basename, every later panic's staging file read as "already
  # recorded". Panic #5 (2026-08-24) therefore has NO ledger row despite three sentinel restarts:
  # the instrument built to make the next death attributable was blinded by a filename, forever.
  local d rows=""
  for d in ${PANIC_DIRS//:/ }; do
    [ -d "$d" ] || continue
    rows="$rows$(
      { find "$d" -maxdepth 1 -type f -name '*.panic' ! -name '.*' -exec stat -f '%m %N' {} + \
          || find "$d" -maxdepth 1 -type f -name '*.panic' ! -name '.*' -exec stat -c '%Y %n' {} + ; } 2>/dev/null
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

# rc 0 when a freeze row for (approximately) this boot already exists. TOLERANT (±5 s), not exact:
# kern.boottime is clock-adjusted after boot, and the live ledger holds the proof — boot
# 1786686149 was re-recorded eight days later as 1786686150 (one second off), turning one incident
# into two rows. An exact-match key on a jittering identity is a dedupe that cannot dedupe.
freeze_boot_already() { # <boot_epoch>
  [ -f "$PANIC_LEDGER" ] || return 1
  grep '"kind":"freeze"' "$PANIC_LEDGER" 2>/dev/null | jq -r '.boot // empty' 2>/dev/null \
    | awk -v b="$1" 'BEGIN{hit=1} { d = $1 - b; if (d < 0) d = -d; if (d <= 5) hit=0 } END{exit hit}'
}

# HOW MANY DISTINCT FREEZES THIS BOX HAS ON RECORD — which is NOT the number of rows, and the
# difference is the whole reason this reader exists. The ledger is append-only and keyed on a boot
# epoch that JITTERS (freeze_boot_already's header records the live proof: boot 1786686149 came back
# eight days later as 1786686150). Before that tolerance landed, one incident wrote two rows. Those
# two rows are still in the live ledger and always will be — an append-only store is not rewritten,
# and the ±5 s fix prevents the NEXT duplicate without retracting the one already written.
#
# So `grep -c '"kind":"freeze"'` answers 2 for a machine that has frozen ONCE, and every question
# worth asking of this ledger is a question about incidents: has the class recurred, do we have the
# second data point the pre-freeze ring buffer is waiting on, is this freeze new. A count that is
# 2x the truth answers "yes, design it" on a sample of one.
#
# CLUSTERS WITH THE SAME ±5 s RULE freeze_boot_already dedupes on, deliberately reusing that
# predicate rather than restating it: two spellings of "is this the same boot" that could drift
# apart is the defect this repo has already paid for twice. Rows are sorted first because append
# order is arrival order, and a cluster rule that walks unsorted input splits one boot into two the
# moment a row is backfilled out of sequence.
freeze_incident_count() {
  [ -f "$PANIC_LEDGER" ] || { printf '0\n'; return 0; }
  grep '"kind":"freeze"' "$PANIC_LEDGER" 2>/dev/null | jq -r '.boot // empty' 2>/dev/null \
    | awk 'NF && $1 ~ /^[0-9]+$/' | sort -n \
    | awk 'BEGIN{n=0; have=0}
           { if (!have || ($1 - prev) > 5) { n++ } ; prev=$1; have=1 }
           END{ print n }'
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
  if freeze_boot_already "$boot"; then
    printf 'freeze-scan: already recorded (boot %s, ±5s)\n' "$boot" >&2
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

# The CC_SENTINEL=off drain (see the kill-switch gate): release a predecessor's ledger, unless
# another live instance owns the loop — a hand-run with the switch off must never release the live
# daemon's cohort.
if [ "$SENTINEL_OFF_DRAIN" = 1 ]; then
  loop_owner_live "${LOG%.jsonl}.pid" || {
    printf '%s compressor-sentinel: RELEASE-ON-DISABLE %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$(release_frozen "$(date +%s)" exit)" >&2
    : > "$PROBATION_DB" 2>/dev/null || true
  }
  echo "compressor-sentinel: disabled (CC_SENTINEL=off)" >&2; exit 0
fi
if [ "$TICKS_PANIC_ONLY" = "1" ]; then
  panic_scan; exit $?
fi
if [ "$TICKS_FREEZE_ONLY" = "1" ]; then
  freeze_scan; exit $?
fi
if [ "$TICKS_FREEZE_COUNT" = "1" ]; then
  freeze_incident_count; exit 0
fi
# NEVER let the post-mortem stop the sensor from starting: a reader for the LAST death must not
# cost the evidence for the NEXT one.
[ "$PANIC_SCAN" = "off" ] || panic_scan || true
[ "$FREEZE_SCAN" = "off" ] || freeze_scan || true

# ── self-restart on changed source ────────────────────────────────────────────────────────────────
# A land that changes this file reaches nothing until the daemon restarts: bash holds the bytes it
# started on. Measured over 30 days, the sentinel's source changed 3 times and the next natural
# restart came ~1h, ~2h and ~22m later — but the gap between restarts has reached 6 days, and the
# only other remedy on offer was granting the unattended deploy job power to bootout/bootstrap a
# resident daemon (decision 68d9af489875, migration 0031). lead-supervisor.sh already closes this
# for itself (self_restart_if_stale): notice the on-disk digest moved, exit 0, and let launchd
# KeepAlive respawn on the new bytes. Same shape here, with two holds the supervisor does not need:
#   · never while the freeze ledger is non-empty — install.sh refuses a restart then for the same
#     reason: a cohort in custody is released by THIS process's tick schedule, and although the
#     TERM trap would release on exit, an unforced exit mid-custody is exactly the case to avoid;
#   · never mid-breach (STREAK > 0) or in the cliff regime — a restart drops every rate baseline
#     for one INTERVAL, and those are the ticks where a blind interval costs the most.
# The new digest must also be seen on TWO consecutive checks: a checkout rewrites the file in place,
# and restarting onto a half-written script is a syntax error that burns launchd's throttle window.
self_sha() { # <path> → sha256 of the on-disk bytes, or NOTHING when unreadable (⇒ abstain)
  [ -f "$1" ] && [ -r "$1" ] || return 0
  /usr/bin/shasum -a 256 "$1" 2>/dev/null | awk 'NR==1{print $1}'
}

self_restart_verdict() { # <running_sha> <disk_sha> <prev_disk_sha> <frozen_db> <streak> <cliff 0|1>
  # → abstain | same | settling | hold-frozen | hold-breach | restart   (always rc 0)
  if [ -z "$1" ] || [ -z "$2" ]; then echo abstain; return 0; fi
  if [ "$1" = "$2" ]; then echo same; return 0; fi
  if [ "$2" != "$3" ]; then echo settling; return 0; fi
  if [ -s "$4" ]; then echo hold-frozen; return 0; fi
  if [ "${5:-0}" -gt 0 ] || [ "${6:-0}" = "1" ]; then echo hold-breach; return 0; fi
  echo restart
}

SELF="${BASH_SOURCE[0]}"
SELF_SHA0="$(self_sha "$SELF")"
SELF_PREV_DISK="$SELF_SHA0"; SELF_LAST_V=""
SELFCHK_EVERY="${CC_SENTINEL_SELFCHK_TICKS:-6}"   # every 6th tick — once a minute at the 10 s default
case "$SELFCHK_EVERY" in ''|0|*[!0-9]*) SELFCHK_EVERY=6 ;; esac

# ── single instance ───────────────────────────────────────────────────────────────────────────────
# SIX live sentinels were observed minutes after the panic-#5 reboot (kernel-zone axis of the
# postmortem). Six concurrent actuators over one freeze ledger is six writers racing one TSV and up
# to six SIGSTOP/SIGCONT senders disagreeing about custody. Identity is (pid, lstart) — the same
# compare every signal path here uses — so a stale pidfile from a dead instance can never block a
# start. Bounded runs (--ticks/--once: the smoke and the suite) skip the mutex: they are not the
# daemon, and refusing them while the daemon lives would make every hand-run read as broken.
if [ "$TICKS" -eq 0 ]; then
  PIDFILE="${LOG%.jsonl}.pid"
  if loop_owner_live "$PIDFILE"; then
    printf 'compressor-sentinel: another live instance owns the loop (pid %s) — exiting 0\n' \
      "$(sed -n 1p "$PIDFILE" 2>/dev/null)" >&2
    exit 0
  fi
  mkdir -p "$(dirname "$PIDFILE")" 2>/dev/null || true
  printf '%s\n%s\n' "$$" "$(proc_lstart "$$")" > "$PIDFILE" 2>/dev/null || true
fi

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
  # knows what it owes. A LOOP-OWNING daemon (TICKS=0) releases whatever its ACT, because it may
  # have adopted a predecessor's ledger; a bounded run with ACT off/observe (a hand smoke on the
  # default ledger path) still cannot release the live daemon's cohort on Ctrl-C.
  if { [ "$ACT" = "stop" ] || [ "$TICKS" -eq 0 ]; } && [ -s "$FROZEN_DB" ]; then
    printf '%s compressor-sentinel: RELEASE-ON-EXIT %s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(release_frozen "$(date +%s)" exit)" >&2
  fi
  [ -n "${PIDFILE:-}" ] && rm -f "$PIDFILE" 2>/dev/null
  exit 0
}
trap cleanup TERM INT

# ── startup custody: a loop-owning daemon settles what it inherited ───────────────────────────────
# The ledger outlives the process that wrote it whenever that process dies without its TERM trap —
# a launchd ExitTimeOut during a 121-146 s cliff tick is enough, because bash defers the trap until
# the running command returns. The KeepAlive successor then ADOPTS every row, including rows written
# before GUI apps had a class of their own. So once, before the first tick, the owner of the loop
# sweeps both ledgers: a row whose pid is NOW protected (class 2 or 3, from a complete capture — see
# gui_protected) is SIGCONTed and dropped, and its probation stamp with it. Every other row keeps its
# hold — the sweep is not a release policy, and an incomplete capture sweeps nothing.
# A loop owner that is NOT armed (ACT off/observe) can never release anything on its own ticks, so
# it hands the whole ledger back at once (exit mode) and truncates probation: without this, an
# armed daemon restarted disarmed leaves its predecessor's cohort stopped for good.
if [ "$TICKS" -eq 0 ]; then
  if [ "$ACT" = stop ]; then
    if [ -s "$FROZEN_DB" ] || [ -s "$PROBATION_DB" ]; then
      _prot="$(exe_table gui 2>/dev/null | gui_protected)"; [ -n "$_prot" ] || _prot=" "
      [ -s "$FROZEN_DB" ] && printf '%s compressor-sentinel: STARTUP-SWEEP %s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(release_frozen "$(date +%s)" sweep 0 0 "$_prot")" >&2
      if [ -s "$PROBATION_DB" ] && _pk="$(mktemp -t cc-sentinel-probation)"; then
        awk -F'\t' -v p="$_prot" 'index(p, " " $1 " ") == 0' "$PROBATION_DB" > "$_pk" && mv -f "$_pk" "$PROBATION_DB"
      fi
    fi
  elif [ -s "$FROZEN_DB" ] || [ -s "$PROBATION_DB" ]; then
    printf '%s compressor-sentinel: RELEASE-ON-DISARM (ACT=%s) %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$ACT" "$(release_frozen "$(date +%s)" exit)" >&2
    : > "$PROBATION_DB" 2>/dev/null || true
  fi
fi

PREV_T=""; PREV_SEG=""; PREV_CBU=""; PREV_SWAP=""; PREV_CMP=""; PREV_DCMP=""
# THREE SEPARATE KEYS, not one comma-joined field. The first draft emitted `"n":8,2,3404` — three
# bare values under one key, which no JSON parser accepts, so a single census would have poisoned
# every consumer of the whole file. capacity-alarm.sh:560 records the identical defect (`"est_room_
# sessions":?`) and the identical reason it survived review: a regex test for one field never
# requires the surrounding document to parse. Caught here by a 3-tick smoke, not by reading.
CENSUS_PIDS=""; CENSUS_N="null"; CENSUS_ORPH="null"; CENSUS_RSS="null"
STREAK=0; CLEAR_STREAK=0; COOLDOWN_UNTIL=0; TICK=0; ROWS=0

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
    # intervals and the next streak would be asserted across a hole. CLEAR_STREAK equally — three
    # calm ticks asserted across a blind spot would certify a spawner release over a gap.
    PREV_T=""; PREV_SEG=""; PREV_CBU=""; PREV_SWAP=""; PREV_CMP=""; PREV_DCMP=""; STREAK=0; CLEAR_STREAK=0
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

  # THE CLIFF REGIME (panic #5). Above CLIFF_PCT every cost the instrument pays for its own
  # evidence comes out of the actuation window: census + full snapshot stretched ticks 10 s →
  # 121-146 s and TRIP 4's actuation never reached disk. In cliff: no census, minimal snapshot, no
  # follow-up spawn, no cooldown gate, one breach tick trips, and nothing is ever released.
  CLIFF=0
  if [ -n "$SEG_PCT" ]; then
    awk -v p="$SEG_PCT" -v c="$CLIFF_PCT" 'BEGIN{ exit (p + 0 >= c + 0) ? 0 : 1 }' && CLIFF=1
  fi

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

  # ── census every CENSUS_EVERY ticks — never in the cliff regime ─────────────────────────────────
  # A stale CENSUS_PIDS in cliff only WIDENS the cohort ("new since the last census" excludes fewer
  # pids), which is the safe direction there.
  if [ "$CLIFF" = "0" ] && [ $((TICK % CENSUS_EVERY)) -eq 0 ]; then
    CRAW="$(census "$ACT_RSS_KB")"
    if [ -n "$CRAW" ]; then
      CENSUS_PIDS="${CRAW#*|}"
      CHEAD="${CRAW%%|*}"
      CENSUS_N="${CHEAD%% *}"; CREST="${CHEAD#* }"
      CENSUS_ORPH="${CREST%% *}"; CENSUS_RSS="${CREST##* }"
      : "${CENSUS_N:=null}" "${CENSUS_ORPH:=null}" "${CENSUS_RSS:=null}"
    fi
  fi

  # ── breach → streak, BEFORE the row so `strk` is THIS tick's verdict ────────────────────────────
  # (The pre-#5 shape wrote the row first, so every logged strk was the PREVIOUS sample's — the
  # off-by-one cost the postmortem an instrument-verification detour, synthesis open question 8.)
  WHY=""
  if [ "$HAVE_RATES" = 1 ]; then
    WHY="$(classify_breach "$SEG_EST" "$SEG_LIMIT" "$SEG_RATE" "$CBU_RATE" "$SWAP_RATE")" || WHY=""
  else
    # No baseline ⇒ no rates — but the CLIFF arm is a LEVEL test and must not wait a tick for one:
    # the first readable tick after a gap at 85% full is exactly the tick that cannot be spent
    # rebuilding a baseline. Zero rates keep every rate arm silent by construction.
    WHY="$(classify_breach "$SEG_EST" "$SEG_LIMIT" 0 0 0)" || WHY=""
  fi
  if [ -n "$WHY" ]; then STREAK=$((STREAK + 1)); else STREAK=0; fi
  # The spawner-release certificate: consecutive ticks that are clear AND calm (level below
  # REL_PARENT_PCT). Distinct from mere !WHY — a rate-lull tick at 71.81% was "clear" by the old
  # test and is precisely what may never again certify a spawner release.
  if [ -z "$WHY" ] && [ -n "$SEG_PCT" ] \
     && awk -v p="$SEG_PCT" -v t="$REL_PARENT_PCT" 'BEGIN{ exit (p + 0 < t + 0) ? 0 : 1 }'; then
    CLEAR_STREAK=$((CLEAR_STREAK + 1))
  else
    CLEAR_STREAK=0
  fi

  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # ── probation: a breach tick re-freezes recently-released spawners FIRST ────────────────────────
  # Before streak and cooldown — those debounce the DETECTOR; a spawner released minutes ago
  # breaching again is not a detection question, it is the release being proven wrong.
  if [ -n "$WHY" ] && [ "$ACT" = "stop" ] && [ -s "$PROBATION_DB" ]; then
    PROBV="$(probation_refreeze "$NOW")"
    case "$PROBV" in
      refroze=0) : ;;
      *) printf '%s compressor-sentinel: PROBATION %s (why=%s)\n' "$TS" "$PROBV" "$WHY" >&2 ;;
    esac
  fi

  # ── the row ─────────────────────────────────────────────────────────────────────────────────────
  ROW="$(printf '{"ts":"%s","t":%s,"el":%s,"seg":%s,"segi":%s,"segs":%s,"lim":%s,"pct":%s,"dseg":%s,"srate":%s,"cbu":%s,"dcbu":%s,"crate":%s,"swap":%s,"dswap":%s,"wrate":%s,"dcmp":%s,"ddec":%s,"inb":%s,"cpb":%s,"fail":%s,"n":%s,"orph":%s,"nrss":%s,"strk":%s}' \
    "$TS" "$TICK" "$ELAPSED" "$SEG_EST" "$SEG_I" "$SEG_S" "$SEG_LIMIT" "${SEG_PCT:-null}" \
    "$D_SEG" "$SEG_RATE" "$CBU" "$D_CBU" "$CBU_RATE" "$SWAP_B" "$D_SWAP" "$SWAP_RATE" \
    "$D_CMP" "$D_DCMP" "${INB:-null}" "${CPB:-null}" "${FAILS:-null}" \
    "$CENSUS_N" "$CENSUS_ORPH" "$CENSUS_RSS" "$STREAK")"
  printf '%s\n' "$ROW" >> "$LOG" 2>/dev/null || true
  ROWS=$((ROWS + 1))

  # ── trip ────────────────────────────────────────────────────────────────────────────────────────
  # In cliff: ONE breach tick suffices (the two-tick streak debounces false positives on the way
  # up; at 60%+ a false positive costs a snapshot, a miss costs the box) and the cooldown no longer
  # gates — the 60 s cooldown was a spawner's whole working day at the measured rate, and wave 2
  # re-ignited inside it.
  TRIP_FIRED=0; EXEF=""
  STREAK_REQ=2; [ "$CLIFF" = "1" ] && STREAK_REQ=1
  if [ -n "$WHY" ] && [ "$STREAK" -ge "$STREAK_REQ" ] && { [ "$CLIFF" = "1" ] || [ "$NOW" -ge "$COOLDOWN_UNTIL" ]; }; then
    HEAD_LINE="$(printf 'segments %s of %s (%s%%) · %s seg/s · compressor +%s B/s · swap +%s B/s' \
      "$SEG_EST" "$SEG_LIMIT" "${SEG_PCT:-?}" "$SEG_RATE" "$CBU_RATE" "$SWAP_RATE")"
    printf '%s compressor-sentinel: TRIP why=%s — %s\n' "$TS" "$WHY" "$HEAD_LINE" >&2
    snapshot_trip "$TS" "$WHY" "$HEAD_LINE" "$CLIFF"
    write_page "$TS" "$WHY" "$HEAD_LINE" "$ROW"

    if [ "$ACT" = "stop" ] || [ "$ACT" = "observe" ]; then
      STOPPED=0; PARENT_N=0; PARENT_STOPPED=0; PARENT_PIDS=" "
      # OBSERVE runs the whole selection and signals nothing. It is the rung this actuator was
      # supposed to have on 2026-08-09 and did not: `off` computes no selection at all, so the only
      # way to learn what the predicate would touch was to arm it. Every later change to the
      # predicate — this one included — gets a logged would-stop tick first.
      [ "$ACT" = "observe" ] && ACTVERB="WOULD-STOP" || ACTVERB="SIGSTOP"
      # TWO reads, back-to-back, and the split between them is load-bearing — select_stop_targets'
      # header has the measurement. exe_table FIRST so the args table is the later instant: a pid
      # that dies between them is simply absent from the table that selects.
      # `gui` mode, so class 2 (the operator's apps) is computed for the one read that selects. The
      # capture outlives this block: the kill rung below reuses it as its protected-class belt.
      EXEF="$(mktemp -t cc-sentinel-exe)"
      exe_table gui > "$EXEF" 2>/dev/null || true
      PSTABLE="$(ps -axwwo pid=,ppid=,rss=,args= 2>/dev/null)"
      TARGETS="$(printf '%s\n' "$PSTABLE" | select_stop_targets "$EXEF" "$CENSUS_PIDS" "$ACT_RSS_KB" "$ACT_CAP")"
      COHORT="$(printf '%s\n' "$TARGETS" | awk '$1 ~ /^[0-9]+$/ { printf "%s ", $1 }')"
      COHORT_N="$(printf '%s' "$COHORT" | wc -w | tr -d ' ')"   # derived from COHORT so they cannot disagree
      # THE POPULATION FLOOR (ACT_MIN_COHORT). Below it nothing is signalled and the tick says so in
      # one line, so a below-floor selection is legible as a DECISION rather than as the silent
      # `cohort_n=0` that the 2026-09-16 panics printed twelve times. The trip, the snapshot and the
      # page have already happened; only the signals are withheld.
      COHORT_NODE_N="$(printf '%s\n' "$TARGETS" | awk '$3 ~ /^node/' | wc -l | tr -d ' ')"
      if [ "$COHORT_N" -lt "$ACT_MIN_COHORT" ] && [ "$COHORT_N" -gt 0 ] && [ "$COHORT_NODE_N" -eq 0 ]; then
        printf 'actuator: HELD cohort_n=%s < ACT_MIN_COHORT=%s and no node-named member — a population, not a one-off, is the trigger\n' \
          "$COHORT_N" "$ACT_MIN_COHORT" >> "$SNAP" 2>/dev/null || true
        TARGETS=""; COHORT=""; COHORT_N=0
      fi
      # THE PROTECTED-CLASS VERDICT, on every armed trip including the zero. Without it a cohort left
      # empty because Dia's fresh renderers were spared reads exactly like a quiet box — and "spared"
      # is the fact a post-mortem needs. Counted the way the cohort would have been: over the floor
      # and NOT on the census roster, i.e. new since the last census.
      SPARED="$(awk -v prev=" $CENSUS_PIDS " -v floor="$ACT_RSS_KB" '($6 == "2" || $6 == "3") && $3 + 0 > floor + 0 && index(prev, " " $1 " ") == 0 { n[$6]++ } END { printf "app=%d sim=%d", n["2"] + 0, n["3"] + 0 }' "$EXEF" 2>/dev/null)" || SPARED="app=? sim=?"
      printf 'actuator: protected-class spared %s new over-floor proc(s) (GUI app bundle / simulator runtime — never selectable)\n' \
        "$SPARED" >> "$SNAP" 2>/dev/null || true
      # WRITE-AHEAD (panic #5, trip 4): the intent reaches disk BEFORE the first signal, so an
      # actuation the storm kills mid-flight is distinguishable from one that never ran. The
      # per-signal lines that follow are the confirmations.
      printf 'actuator: INTENT %s cohort_n=%s cliff=%s (write-ahead; signals follow)\n' \
        "$ACTVERB" "$COHORT_N" "$CLIFF" >> "$SNAP" 2>/dev/null || true

      # THE SPAWNER GOES FIRST, and the order is the mechanism rather than a preference. Freezing
      # the cohort is up to <cap> kill(2) calls; a spawner left running mints throughout that window
      # and every process it mints after the table was read is invisible to this trip and survives
      # into the next 60 s cooldown. Stopping the parent first makes the cohort a closed set.
      if [ "$ACT_PARENT" = "on" ]; then
        PARENTS="$(printf '%s\n' "$PSTABLE" \
                   | select_break_parents "$EXEF" "$COHORT" "$ACT_PARENT_MIN" "$ACT_PARENT_CAP" "$$" "$PPID")"
        while read -r ppid pkids pcomm; do
          [ -n "$ppid" ] || continue
          PARENT_N=$((PARENT_N + 1)); PARENT_PIDS="$PARENT_PIDS$ppid "
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
        # A cohort member the breaker named a spawner has had its one signal, as a PARENT — freezing
        # it again here would ledger it a second time under the worker rules (select_break_parents).
        case "$PARENT_PIDS" in *" $spid "*) continue ;; esac
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
      # ONE REWRITE PER TRIP, after every signal: a pid this trip froze as a parent may already be
      # owed as a worker from an earlier trip, and custody must see one row (frozen_merge).
      [ "$ACT" = "stop" ] && [ $((PARENT_STOPPED + STOPPED)) -gt 0 ] && frozen_compact
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
      # The hold rule is spelled out per kind. The old text, "(hold min 60s / ceiling 600s)", was
      # true only of WORKERS and read as a 600 s ceiling on spawners — which do not have one.
      printf 'actuator: freeze debt %s pid(s) awaiting SIGCONT (workers: min %ss / ceiling %ss; spawners: min %ss, then %s calm ticks < %s%%, no ceiling; nothing releases in cliff)\n' \
        "$(wc -l < "$FROZEN_DB" 2>/dev/null | tr -d ' ' || echo 0)" \
        "$HOLD_MIN_S" "$HOLD_MAX_S" "$PARENT_HOLD_MIN_S" "$REL_PARENT_TICKS" "$REL_PARENT_PCT" \
        >> "$SNAP" 2>/dev/null || true
    else
      printf 'actuator: DISARMED (CC_SENTINEL_ACT=%s) — detection only\n' "$ACT" >> "$SNAP" 2>/dev/null || true
    fi

    # One follow-up run at a time; it self-terminates in 60 s, which is the cooldown. Not in cliff:
    # 12 more ps sweeps on a box at 60%+ spend the actuation window on evidence (trip 4's lesson).
    if [ "$CLIFF" != "1" ] && { [ -z "$FOLLOWUP_PID" ] || ! kill -0 "$FOLLOWUP_PID" 2>/dev/null; }; then
      snapshot_followup &
      FOLLOWUP_PID=$!
    fi
    COOLDOWN_UNTIL=$((NOW + COOLDOWN))
    TRIP_FIRED=1
    STREAK=0
  fi

  # ── the escalation rung: custody converts to a kill when the freeze is losing ───────────────────
  # Rides ACT=stop with an opt-out (CC_SENTINEL_KILL=off) for the parent-breaker's reason: a
  # separately-defaulted-off flag ships the mechanism inert on the one box it was written for.
  # DEBT_ELIG counts only rows past KILL_MIN_HOLD_S, so the trip that CREATES the debt never kills
  # on the same tick — the freeze always gets its chance first, and the intent line cannot fire
  # over a set that would be wholly spared.
  if [ "$ACT" = "stop" ] && [ "$KILL" = "on" ] && [ -s "$FROZEN_DB" ]; then
    DEBT_ELIG="$(awk -F'\t' -v now="$NOW" -v min="$KILL_MIN_HOLD_S" \
      'NF >= 4 && ($4 + 0) > 0 && (now - $4) >= min { n++ } END { print n + 0 }' "$FROZEN_DB" 2>/dev/null || echo 0)"
    KREASON="$(kill_due "${SEG_PCT:-0}" "${SEG_RATE:-0}" "$TRIP_FIRED" "$DEBT_ELIG")" || KREASON=""
    if [ -n "$KREASON" ]; then
      KV="$(kill_escalate "$NOW" "$KREASON" "$EXEF")"
      printf '%s compressor-sentinel: KILL-ESCALATE reason=%s %s\n' "$TS" "$KREASON" "$KV" >&2
      printf 'actuator: kill-escalate reason=%s %s\n' "$KREASON" "$KV" >> "$SNAP" 2>/dev/null || true
    fi
  fi
  # The trip's exe capture lives until here so the kill rung can reuse it. Free at the defaults:
  # retrip-over-debt needs TRIP_FIRED=1, and climbing-at-60pct needs pct >= KILL_PCT = CLIFF_PCT,
  # where every breach tick trips — so every kill tick already holds one.
  [ -n "$EXEF" ] && rm -f "$EXEF" 2>/dev/null; EXEF=""

  # THE RELEASE RUNS ON EVERY TICK, INCLUDING THE QUIET ONES, and that placement is the mechanism
  # rather than tidiness: a cohort frozen at tick N is owed its SIGCONT by a LATER tick, and the
  # ticks that follow a freeze are precisely the ones where nothing trips. Hanging the release off
  # the trip block would mean a cohort is only ever resumed by the NEXT emergency — i.e. never, on
  # the quiet box that is the normal case after the actuator has done its job.
  if [ "$ACT" = "stop" ] && [ -s "$FROZEN_DB" ]; then
    if [ -z "$WHY" ]; then RELMODE=clear; else RELMODE=ceiling; fi
    # The spawner-release certificate travels separately from the mode: clear-mode still releases
    # WORKERS after HOLD_MIN_S, but a PARENT needs CLEAR_STREAK ticks of clear-AND-calm plus its
    # own longer hold (release_frozen's parent branch — panic #5's fatal SIGCONT is the case this
    # split exists for).
    PARENT_OK=0
    [ "$CLEAR_STREAK" -ge "$REL_PARENT_TICKS" ] && PARENT_OK=1
    RELV="$(release_frozen "$NOW" "$RELMODE" "$PARENT_OK" "$CLIFF")"
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

  # Daemon only: a bounded run (--ticks/--once) is the smoke and the suite, and has no successor.
  if [ "$TICKS" -eq 0 ] && [ "${CC_SENTINEL_SELF_RESTART:-on}" != "off" ] \
     && [ $((TICK % SELFCHK_EVERY)) -eq 0 ]; then
    SELF_DISK="$(self_sha "$SELF")"
    SELF_V="$(self_restart_verdict "$SELF_SHA0" "$SELF_DISK" "$SELF_PREV_DISK" "$FROZEN_DB" "$STREAK" "${CLIFF:-0}")"
    [ -n "$SELF_DISK" ] && SELF_PREV_DISK="$SELF_DISK"
    if [ "$SELF_V" = "restart" ]; then
      printf '%s compressor-sentinel: SELF-RESTART on-disk sha256 changed (%s -> %s) — exiting 0 for launchd KeepAlive to respawn on the new bytes\n' \
        "$TS" "${SELF_SHA0:0:12}" "${SELF_DISK:0:12}" >&2
      cleanup                     # releases nothing (the ledger is empty by the verdict), drops the pidfile, exits 0
    elif [ "$SELF_V" != "$SELF_LAST_V" ] && [ "${SELF_V%%-*}" = "hold" ]; then
      printf '%s compressor-sentinel: SELF-RESTART deferred (%s) — source changed, restart waits for a quiet tick\n' "$TS" "$SELF_V" >&2
    fi
    SELF_LAST_V="$SELF_V"
  fi

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
