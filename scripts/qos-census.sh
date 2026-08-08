#!/bin/bash
# qos-census.sh — census the QoS actuator against its REAL target population.
#
# WHY (row 13, MACHINE_CAPACITY_V2.md §7 AC1/AC2). A mechanism is presumed inert until counted
# against live targets (R3, memory actuator-must-see-the-target-population: 134/134 MISS). The
# 2026-07-29 baseline census is exactly why row 13 exists — the QoS band looked applied and covered
# 30% of procs / 0% of CPU.
#
# THREE-STATE VERDICT, never a boolean. A coverage number computed on a quiet box is a NON-VERDICT,
# not a pass: with 0 gate runs in flight there is nothing to demote and naive arithmetic reads 100%.
# Conflating "nothing to measure" with "measured clean" is the signal-death failure this repo has
# hit repeatedly (memory named-failure-vs-no-verdict, gate-never-ran-vs-gate-red).
#
#   verdict=NO-BURST     <2 distinct gate runs in flight — cannot judge. Exit 3.
#   verdict=PASS         burst present AND the GATED coverage metric >= threshold. Exit 0.
#   verdict=FAIL         burst present AND coverage below threshold. Exit 1.
#   verdict=SIGNAL-DEAD  the two-sided positive control could not tell demoted from undemoted;
#                        every other number in this run is untrustworthy. Exit 4.
#
# TWO-SIDED POSITIVE CONTROL (R6). Absence alarms need existence evidence, so before judging
# anything we spawn one KNOWN-DEMOTED and one KNOWN-FULL process and require the detector to
# classify BOTH correctly. A one-sided control (only proving we can see a demoted proc) would still
# pass if the classifier said "demoted" about everything.
#
# PRI BANDS — calibrated empirically, not assumed. Re-measured on this box 2026-07-30 (M1-rev):
#   taskpolicy -c utility      -> PRI 20   <- THE BAND THE ACTUATORS NOW USE (P-core-eligible)
#   taskpolicy -c background   -> PRI 4    <- E-core confined; ~84-89x tax on long batch work
#   taskpolicy -c maintenance  -> PRI 4    <- indistinguishable from background by PRI alone
#   nice 19 alone              -> PRI 31   <- NOT demoted; this is why nice is gone from the prefix
#   plain                      -> PRI 31
# THE TWO LEGS ARE STRICTLY ORTHOGONAL (re-derived under `env -i` to isolate inherited NI):
# nice(1) moves NI and nothing else; taskpolicy(8) moves PRI (and the I/O tier) and nothing else.
# PRI tracks the taskpolicy column exactly, in both directions, regardless of nice — which is why
# the shim's old nice-only "PARTIAL" tier was ZERO demotion, not partial, and is now deleted.
#
# WHY THIS CENSUS DOES NOT USE A BARE `pri <= N` TEST (measured 2026-07-30, and it is the whole
# reason the classifier below is shaped the way it is). When the actuators moved from background
# (PRI 4) to utility (PRI 20), the obvious change was to raise the demoted ceiling from 10 to 20.
# That is WRONG, in the dangerous direction. Darwin's timeshare scheduler DECAYS the priority of a
# busy undemoted process: 60 samples of a CPU-bound process at normal priority read mostly 31, but
# also 30, 29, 26, and a floor of **PRI 17**. A ceiling of 20 therefore counts busy UNDEMOTED work as
# demoted — the census would over-report coverage and could produce a false PASS on the exact metric
# AC15 accrues from. A miscalibrated check is a deleted check.
#
# THE FIX — classify on the CLAMP CONSTANTS, not a range. A QoS clamp PINS priority: utility is
# exactly 20 and background exactly 4, neither drifts. Undemoted work FLOATS through 17..31. So a
# proc counts as demoted only when its PRI is BOTH within the ceiling AND equal to one of the clamp
# values. That closes the entire 5..19 false-positive window.
#
# RESIDUAL, stated rather than hidden: an undemoted proc sampled at exactly 20 still misreads as
# demoted. That is one value instead of a 16-wide window (~4x smaller false-positive surface), and
# there is no better instrument available — `taskpolicy -g` is a set-side flag, not a pid read, and
# `/usr/bin/taskinfo` exits "must be run as root", so it is unusable from a launchd/hook context.
# PRI is the only unprivileged signal there is.
#
# THREE COVERAGE METRICS, and the one an operator actually asks for is RUN-weighted (added
# 2026-08-07). PROC coverage answers "what fraction of bats PROCESSES are demoted", which is not the
# question the box poses. Two properties make it a poor headline:
#
#   · IT IS PROC-WEIGHTED, so runs vote in proportion to their fan-out. A 40-proc suite and a 1-proc
#     suite are one gate run each to the operator, but 40:1 to this metric — so one large covered
#     run can outvote several small uncovered ones and hold the number above threshold.
#   · IT IS MOVABLE BY A SINGLE PROCESS. Not theoretical: that is the defect DENOMINATOR PURITY
#     below was written to fix, where one `timeout` wrapper per run sat at pri=31 and dragged a
#     genuinely 114/114 population down to 73.2%. Strict matching removed those particular wrappers;
#     it did not remove the SHAPE, because the metric still lets one proc speak for a whole run.
#
# RUN coverage answers it directly — how many concurrent gate RUNS are undemoted — and one stray
# process cannot move it, because a run is one vote no matter how many procs carry it. A run counts
# as covered only when EVERY attributed proc of that run is demoted, which is the conservative
# direction: a partially-demoted run is uncovered.
#
# ATTRIBUTION, stated rather than assumed. bats stamps its per-invocation tmpdir (bats-run-XXXXXX)
# into argv, and MEASURED on this box only the `bats-exec-file` rows carry it — the top-level `bats`,
# `bats-exec-suite` and `bats-exec-test` rows do not. So the run metric is computed over the rows
# that carry a run stamp, and the rows that do not are counted into `procs_unattributed` rather than
# silently dropped: an exclusion nobody can see is how the proc denominator went wrong in the first
# place. This costs nothing in fidelity, because the clamp is applied ONCE at the root of a run and
# every descendant inherits it (verified: all five procs of a sampled run read the same PRI), so any
# proc of a run reports that run's band.
#
# NO-BURST is unchanged and still gates everything: runs_in_flight < 2 is a NON-VERDICT whichever
# coverage metric is selected. runs_demoted + runs_full == runs_in_flight BY CONSTRUCTION — all three
# derive from the same run-id extraction over the same snapshot — which makes the trio a reconcilable
# check on the classifier rather than three numbers that can drift apart unnoticed.
#
# READ-ONLY with respect to the fleet: spawns nothing but its own two short-lived controls, kills
# nothing, waits on nothing (R1 — no load polling, ever).
#
# bash 3.2 safe (no `case` in command substitution). Ships to launchd ⇒ tested under /bin/bash.

set -uo pipefail

# AC1 bar. Applies to the GATED metric, which is PROC coverage by default — a sleeping demoted proc
# contributes 0 to `ps %cpu`, so CPU-weighted coverage can read 0% with every proc correctly
# demoted. QOS_GATE_ON=cpu switches it. Both numbers are always reported.
THRESHOLD="${QOS_COVERAGE_THRESHOLD:-95}"
# Ceiling for the demoted set. Default 20 = XNU BASEPRI_UTILITY, the band the actuators now request
# (background's 4 is still <= 20, so both clamps count). Paired with the clamp filter below — the
# ceiling ALONE would misclassify decayed undemoted procs; see PRI BANDS in the header.
DEMOTED_PRI_MAX="${QOS_DEMOTED_PRI_MAX:-20}"
# The clamp-pinned PRI values. Single-dash `${VAR-default}`: set-but-EMPTY is honoured verbatim and
# DISABLES the filter, reverting to the incumbent bare-ceiling behaviour — the escape hatch if a
# future OS changes what a clamp pins to.
CLAMP_PRIS="${QOS_CLAMP_PRIS-4 20}"
LOG="${QOS_CENSUS_LOG:-$HOME/.claude/logs/qos-census.jsonl}"
PATTERN="${QOS_CENSUS_PATTERN:-bats}"
NO_CONTROL="${QOS_CENSUS_NO_CONTROL:-0}"      # tests only; production must keep the control on

# ── PATH-INDEPENDENT sysctl(8) (item ff544977e4ea, 2026-08-06) ───────────────────────────────────
# sysctl lives in /usr/sbin; this job's plist wrapper exports a PATH that ends /usr/bin:/bin. So the
# bare name below resolved in a terminal and not in any SCHEDULED run — measured on this machine's
# own log, 859 of 867 census rows carry loadavg1 "?". That is the blind column in the instrument
# whose entire purpose is to measure contention: every row taken by the daemon that runs it.
# `taskpolicy` above already resolves /usr/sbin absolutely; this is the one call that did not.
# Fixed script-side, not by editing the plist — a plist-only edit fails launchd-parity-lint
# assertion (c) fleet-wide, and stays red pending an operator reload (see postland-verify.sh's note).
# Seam: QOS_CENSUS_SYSCTL — set-but-EMPTY honored verbatim, so the unreadable path stays testable.
if [ -n "${QOS_CENSUS_SYSCTL+set}" ]; then
  SYSCTL="$QOS_CENSUS_SYSCTL"
elif [ -x /usr/sbin/sysctl ]; then
  SYSCTL=/usr/sbin/sysctl
else
  SYSCTL="$(command -v sysctl 2>/dev/null || true)"
fi

usage() {
  cat <<'EOF'
qos-census.sh — census the QoS band against live gate processes.

  --json        emit one JSON object (default: human table + the JSON line)
  --quiet       suppress the human table
  --no-append   do not append to the census log
  -h|--help     this text

Exit: 0 PASS · 1 FAIL · 3 NO-BURST (non-verdict) · 4 SIGNAL-DEAD (control failed)
EOF
}

WANT_JSON=0; QUIET=0; APPEND=1
while [ $# -gt 0 ]; do
  if [ "$1" = "--json" ]; then WANT_JSON=1
  elif [ "$1" = "--quiet" ]; then QUIET=1
  elif [ "$1" = "--no-append" ]; then APPEND=0
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then usage; exit 0
  else echo "qos-census.sh: unknown arg '$1'" >&2; usage >&2; exit 2
  fi
  shift
done

# ── is this PRI a clamp-pinned value? (empty filter ⇒ everything passes) ───────────────────────
#
# CHOPPED BY PARAMETER EXPANSION, not `for p in $CLAMP_PRIS`. Word-splitting an unquoted expansion
# ALSO pathname-expands each field, and this filter decides the census's own POSITIVE CONTROL — so
# the working directory was able to decide whether that control passed. Measured 2026-08-07 with
# identical environment, varying only the contents of cwd:
#
#     QOS_CLAMP_PRIS='2*'  cwd empty                 → control FAIL, verdict SIGNAL-DEAD  (honest)
#     QOS_CLAMP_PRIS='2*'  cwd contains a file `20`  → control OK,   verdict NO-BURST     (a lie)
#
# In the second run the clamp value came from a FILENAME: the glob matched `20`, the shell filter
# then accepted a PRI-20 process as clamped, and the control declared itself healthy. The awk filter
# used for the POPULATION never globs, so the two halves of this script disagreed about what
# "demoted" means — and the disagreement is silent in exactly the direction that matters, since a
# green control is what licenses every other number in the row. A control a stray file can flip is
# not a control.
#
# `set -f` would suppress it, but it mutates SHELLOPTS, which an exporting environment propagates
# into every child; chopping the string removes the exposure by construction. (The trap is invisible
# under zsh, which does not word-split unquoted parameters — memory
# verification-harness-vacuous-pass-traps. This file ships to launchd and is tested under /bin/bash.)
_is_clamp_pri() {
  [ -z "$CLAMP_PRIS" ] && return 0
  local rest="$CLAMP_PRIS" p
  while [ -n "$rest" ]; do
    p="${rest%% *}"
    if [ "$p" = "$rest" ]; then rest=""; else rest="${rest#* }"; fi
    [ -n "$p" ] || continue
    [ "$1" = "$p" ] && return 0
  done
  return 1
}

# ── classify one pid: prints "demoted" | "full" | "gone" ──────────────────────────────────────
# Demoted requires BOTH the ceiling and a clamp-pinned value — see PRI BANDS in the header for why
# the ceiling alone reads busy undemoted work (PRI decayed as low as 17) as demoted.
classify_pid() {
  local pid="$1" pri
  pri=$(ps -p "$pid" -o pri= 2>/dev/null | tr -d ' ')
  if [ -z "$pri" ]; then printf 'gone'; return 0; fi
  if [ "$pri" -le "$DEMOTED_PRI_MAX" ] 2>/dev/null && _is_clamp_pri "$pri"; then
    printf 'demoted'
  else
    printf 'full'
  fi
}

# ── two-sided positive control (R6) ───────────────────────────────────────────────────────────
#
# MEASURED CONSTRAINT 2026-07-29 — THE BACKGROUND BAND IS A ONE-WAY RATCHET. A plain child of a
# demoted parent INHERITS pri=4; `taskpolicy -B -p <pid>` does NOT lift it back (verified: pri
# stayed 4); and there is no `default`/`none` QoS clamp (only utility/background/maintenance).
# So a known-FULL control process CANNOT be constructed from inside a demoted process.
#
# That is a property of Darwin, not a bug here — but it means a control calibrated for a
# full-priority caller is UNRUNNABLE from a demoted caller, and reporting "FAIL" in that case
# would be a false conviction (memory exoneration-bound-must-fit-what-it-bounds: a bound under
# what it measures can only convict). Hence FOUR control states, and the census reads its OWN band
# first:
#   OK               both sides classified correctly — full confidence.
#   AMBIENT-DEMOTED  this census is itself in the background band, so the FULL side cannot be
#                    constructed. The demoted side is still verified, and the population census is
#                    still valid; only the classifier's full-side self-check is unavailable.
#   NO-TASKPOLICY    cannot construct the demoted side at all.
#   FAIL             running at full priority AND the control still failed ⇒ classifier broken.
CONTROL="SKIPPED"
if [ "$NO_CONTROL" != "1" ]; then
  CONTROL="FAIL"
  _tp=""
  for c in /usr/sbin/taskpolicy "$(command -v taskpolicy 2>/dev/null || true)"; do
    if [ -n "$c" ] && [ -x "$c" ]; then _tp="$c"; break; fi
  done
  # Our own band decides which control is even constructible.
  #
  # SAMPLED, not read once. `classify_pid "$$"` milliseconds after a `taskpolicy` exec transiently
  # reads pri=31 even when this process IS demoted. On that reading the code takes the two-sided
  # branch, where the "full" control inherits pri=4 from the demoted parent (the one-way ratchet) and
  # is classified `demoted` ⇒ CONTROL=FAIL ⇒ a spurious SIGNAL-DEAD. Measured: 1 failure in 5 runs
  # inside a bats suite, 0 in 11 direct invocations — a race, not a defect in the ladder.
  # Three samples, and ANY demoted reading wins: the band is a one-way ratchet, so a process that has
  # ever read demoted cannot have climbed back out. Biased toward AMBIENT-DEMOTED, which is the
  # honest degradation, never toward a false SIGNAL-DEAD.
  _self_band="full"
  for _i in 1 2 3; do
    if [ "$(classify_pid "$$")" = "demoted" ]; then _self_band="demoted"; break; fi
    /bin/sleep 0.1 2>/dev/null || true
  done
  if [ -z "$_tp" ]; then
    CONTROL="NO-TASKPOLICY"
  else
    # The control constructs the band the ACTUATORS request (utility), not a band nothing uses: a
    # control that only proves PRI-4 detection while every actuator emits PRI 20 would leave the
    # load-bearing leg of the classifier unverified. nice(1) is absent for the same reason it is gone
    # from the actuators — it moves NI and leaves PRI at 31.
    "$_tp" -c "${QOS_CONTROL_BAND:-utility}" /bin/sleep 3 >/dev/null 2>&1 &
    _cd=$!
    /bin/sleep 3 >/dev/null 2>&1 &
    _cf=$!
    /bin/sleep 1
    _gd=$(classify_pid "$_cd")
    _gf=$(classify_pid "$_cf")
    if [ "$_self_band" = "demoted" ]; then
      # FULL side is unconstructible from here. Verify the demoted side only, and say so.
      if [ "$_gd" = "demoted" ]; then CONTROL="AMBIENT-DEMOTED"; fi
    else
      # BOTH sides must be right. Either one wrong ⇒ the classifier cannot separate the bands.
      if [ "$_gd" = "demoted" ] && [ "$_gf" = "full" ]; then CONTROL="OK"; fi
    fi
    kill "$_cd" "$_cf" >/dev/null 2>&1 || true
    wait "$_cd" 2>/dev/null || true
    wait "$_cf" 2>/dev/null || true
  fi
fi

# ── census the real population ────────────────────────────────────────────────────────────────
# ps|grep is deliberate: `ps -o comm=` TRUNCATES AT 16 CHARS, which silently hides
# bats-exec-suite / bats-format-cat (memory actuator-must-see-the-target-population). Match on the
# full args line instead, and exclude this script and its own grep.
# BUG CAUGHT BY TEST (vii): $PATTERN was reported in the JSON but the grep was hardcoded to
# `[b]ats`, so the seam was DEAD — QOS_CENSUS_PATTERN could not change what was counted, and a test
# that set it to a no-such-process value still matched the live corpus. A seam that cannot change
# the behaviour it names is not a seam (the same defect class as `${VAR:-}` vs `${VAR+set}`).
# The bracket trick that excludes our own grep is applied to the FIRST character of $PATTERN.
_p_head=$(printf '%s' "$PATTERN" | cut -c1)
_p_tail=$(printf '%s' "$PATTERN" | cut -c2-)

# ── DENOMINATOR PURITY (added 2026-07-30 after this census was found contaminated) ────────────────
# The first version counted ANY process whose argv contained "bats". Measured on the live box that
# was 157 rows, of which only 114 were real bats processes:
#     real bats internals   114 rows   0 at pri=31
#     timeout wrappers        6 rows   6 at pri=31
#     shell -c lines         17 rows  17 at pri=31
#     claude sessions        19 rows  18 at pri=31
# EVERY pri=31 row was pollution, so the census reported ~70% coverage where the real figure was
# 114/114. A `timeout 800 bats …` WRAPPER is the worst offender: it legitimately sits at pri=31 while
# every bats child it spawned is at pri=4 (reproduced on 3 live wrappers), so it manufactures exactly
# the "uncovered" signal this tool exists to detect.
#
# This is the same failure as memory `detector-matching-its-own-skill-description` and the
# path-substring misclassification recorded in this row's own §1.1 — text in an argv is not evidence
# that the process IS the thing. Count only what bats itself execs.
#
# Seam: QOS_CENSUS_STRICT=off restores the old permissive matching (for comparing against the
# historical, contaminated rows already in the log — never for a verdict).
_census_rows() {
  # shellcheck disable=SC2009  # ps|grep is REQUIRED: pgrep matches the process NAME, and this census
  # must see bats-exec-suite / bats-format-cat, which `ps -o comm=` truncates at 16 chars — the exact
  # way an actuator census goes blind to its own population. We also need pri and %cpu per row.
  ps -eo pid,nice,pri,%cpu,args 2>/dev/null \
    | grep -E "[${_p_head}]${_p_tail}" \
    | grep -v 'qos-census'
}
if [ "${QOS_CENSUS_STRICT:-on}" = "off" ]; then
  SNAP="$(_census_rows || true)"
else
  # POSITIONAL discriminator, NOT a substring blacklist.
  #
  # The first attempt at this fix excluded rows containing `timeout `, `<shell> -c ` or `claude`.
  # That was WORSE than the contamination it replaced: this repo's own primary checkout is
  # /Users/chrisren/Development/claude-infrastructure, so `grep -v claude` deleted GENUINE bats rows
  # whose test path merely contained the word. Measured against one live run: strict saw 0 rows,
  # permissive saw 5 — and all 5 were real bats libexec processes at pri=31, i.e. exactly the
  # undemoted population this census exists to find. A census that reports 100% with a whole
  # undemoted run in front of it is worse than one that over-counts.
  #
  # bats execs its internals as `bash <…>/libexec/bats-core/bats-exec-*`, so the libexec path is
  # argv field 1 or 2. Anchoring there admits every real bats process regardless of what its test
  # PATHS are called, and rejects the wrapper classes by construction — a `timeout 800 bats …` has
  # `timeout` in field 1 and a non-libexec `bats` in field 2; `zsh -c '… bats …'` has `-c` in
  # field 2; a claude session has neither. No blacklist, so no word can be collateral damage.
  SNAP="$(_census_rows | awk '
    # ps -eo pid,nice,pri,%cpu,args ⇒ $1=pid $2=nice $3=pri $4=%cpu $5=executable $6=first arg.
    # bats runs its internals as `bash <…>/libexec/bats-core/bats-exec-*`, so the libexec path is
    # $5 (direct exec) or $6 (via bash). Checking $1/$2 — the pid and nice columns — was the first
    # attempt and matched nothing, which is why this is anchored on named fields.
    { if ($5 ~ /bats-core\/(bats|bats-exec-[a-z]+|bats-format-[a-z]+|bats-preprocess|bats-gather-tests)$/ \
         || $6 ~ /bats-core\/(bats|bats-exec-[a-z]+|bats-format-[a-z]+|bats-preprocess|bats-gather-tests)$/) print }
  ' || true)"
fi

# PER-TIER SPLIT (M1-rev): the demoted set is partitioned into the two clamp tiers, so a row records
# WHICH band the fleet actually landed in rather than only "demoted". By construction
# N_PRI4 + N_PRI20 == N_DEMOTED, which makes the pair a reconcilable check on the classifier rather
# than two independent numbers that can silently disagree.
#   N_PRI4  pri <= 4   background / maintenance
#   N_PRI20 the rest of the demoted set — utility (PRI 20)
N_DEMOTED=0; N_FULL=0; CPU_DEMOTED=0; CPU_FULL=0; N_PRI4=0; N_PRI20=0
if [ -n "$SNAP" ]; then
  read -r N_DEMOTED N_FULL CPU_DEMOTED CPU_FULL N_PRI4 N_PRI20 <<EOF
$(printf '%s\n' "$SNAP" | awk -v m="$DEMOTED_PRI_MAX" -v cl="$CLAMP_PRIS" '
  function isclamp(p) {
    if (cl == "") return 1
    n = split(cl, a, " ")
    for (i = 1; i <= n; i++) if (p == a[i]+0) return 1
    return 0
  }
  { pri=$3+0; cpu=$4+0
    if (pri<=m && isclamp(pri)) { nd++; cd+=cpu; if (pri<=4) n4++; else n20++ }
    else                        { nf++; cf+=cpu } }
  END { printf "%d %d %.1f %.1f %d %d", nd+0, nf+0, cd+0, cf+0, n4+0, n20+0 }')
EOF
fi

N_TOTAL=$((N_DEMOTED + N_FULL))
CPU_TOTAL=$(awk -v a="$CPU_DEMOTED" -v b="$CPU_FULL" 'BEGIN{printf "%.1f", a+b}')

# distinct concurrent gate RUNS — bats stamps a unique bats-run-XXXXXX tmpdir per invocation, so
# this counts real concurrency rather than the proc fan-out of a single run.
N_RUNS=$(printf '%s\n' "$SNAP" | grep -oE 'bats-run-[A-Za-z0-9]+' | sort -u | grep -c . || true)
[ -z "$N_RUNS" ] && N_RUNS=0

# ── RUN-WEIGHTED tiers (see THREE COVERAGE METRICS in the header) ─────────────────────────────
# A run is COVERED only when every attributed proc of that run is demoted; any full-priority proc
# condemns the whole run. Rows carrying no run stamp cannot be attributed and are counted separately
# rather than dropped in silence. The clamp predicate is deliberately the SAME awk function as the
# proc pass, so the two metrics can never disagree about what "demoted" means.
RUNS_DEMOTED=0; RUNS_FULL=0; N_UNATTRIB=0
if [ -n "$SNAP" ]; then
  read -r RUNS_DEMOTED RUNS_FULL N_UNATTRIB <<EOF
$(printf '%s\n' "$SNAP" | awk -v m="$DEMOTED_PRI_MAX" -v cl="$CLAMP_PRIS" '
  function isclamp(p) {
    if (cl == "") return 1
    n = split(cl, a, " ")
    for (i = 1; i <= n; i++) if (p == a[i]+0) return 1
    return 0
  }
  # EVERY id on the row, not the first. A row can legitimately carry TWO: bats-exec-file names its
  # own run tmpdir, and a corpus whose PATH sits under another run tmpdir names that one too (the
  # shape (xxxiii) already relies on). runs_in_flight is a `grep -o | sort -u`, which sees all of
  # them — so taking only the first here made runs_demoted + runs_full != runs_in_flight, i.e. the
  # partition silently failed to hold and the trio stopped being reconcilable. Matching the
  # denominator EXACTLY is what keeps it a check rather than three independent numbers.
  #
  # RESIDUAL, stated: a proc is attributed to every run it mentions, so in that nested shape one
  # full-priority proc can condemn the run whose tmpdir merely CONTAINS its corpus. That is the
  # conservative direction — it can only UNDER-report coverage, never over-report it, and
  # over-reporting is the exact failure this whole row exists to prevent. In the production shape
  # (corpus paths are repo paths, not bats tmpdirs) a row carries one id and the question does not
  # arise.
  { pri=$3+0
    t=$0; n=0
    while (match(t, /bats-run-[A-Za-z0-9]+/)) {
      run = substr(t, RSTART, RLENGTH)
      t = substr(t, RSTART + RLENGTH)
      n++
      seen[run]=1
      if (!(pri<=m && isclamp(pri))) bad[run]=1
    }
    if (n == 0) { un++ } }
  END { nd=0; nf=0
        for (r in seen) { if (r in bad) nf++; else nd++ }
        printf "%d %d %d", nd+0, nf+0, un+0 }')
EOF
fi

COV_PROC=$(awk -v d="$N_DEMOTED" -v t="$N_TOTAL" 'BEGIN{ if(t<=0){print "0.0"} else {printf "%.1f", 100*d/t} }')
COV_CPU=$(awk -v d="$CPU_DEMOTED" -v t="$CPU_TOTAL" 'BEGIN{ if(t<=0){print "0.0"} else {printf "%.1f", 100*d/t} }')
COV_RUN=$(awk -v d="$RUNS_DEMOTED" -v t="$N_RUNS" 'BEGIN{ if(t<=0){print "0.0"} else {printf "%.1f", 100*d/t} }')

# ── verdict ───────────────────────────────────────────────────────────────────────────────────
# AMBIENT-DEMOTED is a TRUSTWORTHY control state, not a failure: the demoted side was verified and
# only the (unconstructible) full side was skipped. Omitting it here made the honest degradation
# report SIGNAL-DEAD — caught by test (xv). The distinction matters because a census fired from
# inside a gate is a normal, expected call path.
if [ "$CONTROL" != "OK" ] && [ "$CONTROL" != "SKIPPED" ] && [ "$CONTROL" != "AMBIENT-DEMOTED" ]; then
  VERDICT="SIGNAL-DEAD"; RC=4
elif [ "$N_RUNS" -lt 2 ]; then
  # NOT a pass. Nothing to demote ⇒ nothing proven.
  VERDICT="NO-BURST"; RC=3
else
  # PRIMARY METRIC = PROC coverage, not CPU coverage. Measured 2026-07-29: a demoted bats proc that
  # is SLEEPING contributes 0.0 to `ps %cpu`, so CPU-weighted coverage reads 0% even when every
  # single proc is correctly demoted — it would fail for reasons unrelated to the fix. (A
  # CPU-ACTIVE demoted proc does register correctly: verified 14.4% at pri=4, so CPU coverage is
  # still worth REPORTING as the impact metric — it is just the wrong thing to GATE on.)
  # Seam: QOS_GATE_ON=cpu switches the gate to CPU coverage for a burst known to be CPU-active;
  # QOS_GATE_ON=run gates on RUN coverage, the metric one stray proc cannot distort (header, THREE
  # COVERAGE METRICS). The DEFAULT deliberately stays proc: changing what an ACCRUING metric gates
  # on would silently re-base the AC1 record that has been accumulating against it, so run coverage
  # is REPORTED on every row from today and GATED only on an explicit, separate call.
  _gate_metric="${QOS_GATE_ON:-proc}"
  if [ "$_gate_metric" = "cpu" ]; then _gv="$COV_CPU"
  elif [ "$_gate_metric" = "run" ]; then _gv="$COV_RUN"
  else _gv="$COV_PROC"; fi
  _ok=$(awk -v c="$_gv" -v t="$THRESHOLD" 'BEGIN{print (c+0 >= t+0) ? 1 : 0}')
  if [ "$_ok" = "1" ]; then VERDICT="PASS"; RC=0; else VERDICT="FAIL"; RC=1; fi
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [ -n "$SYSCTL" ] && [ -x "$SYSCTL" ]; then
  LOAD1=$("$SYSCTL" -n vm.loadavg 2>/dev/null | awk '{print $2}')
else
  LOAD1=""                                    # rendered "?" below — unknown, never a number
fi
# APPEND-ONLY schema discipline: the M1-rev fields go at the END and no existing key is renamed or
# re-typed, so every consumer of a historical row keeps parsing (the tier fields simply read as
# absent on pre-M1-rev rows, which is the truthful answer for a row taken before the split existed).
# The run-weighted fields (2026-08-07) follow the same rule and for the same reason — they append,
# and a pre-run-metric row reads as absent rather than as zero.
JSON=$(printf '{"ts":"%s","verdict":"%s","control":"%s","runs_in_flight":%s,"procs_total":%s,"procs_demoted":%s,"procs_full":%s,"cpu_total":%s,"cpu_demoted":%s,"coverage_proc_pct":%s,"coverage_cpu_pct":%s,"threshold":%s,"demoted_pri_max":%s,"loadavg1":"%s","pattern":"%s","gate_on":"%s","procs_pri4":%s,"procs_pri20":%s,"clamp_pris":"%s","runs_demoted":%s,"runs_full":%s,"coverage_run_pct":%s,"procs_unattributed":%s}' \
  "$TS" "$VERDICT" "$CONTROL" "$N_RUNS" "$N_TOTAL" "$N_DEMOTED" "$N_FULL" \
  "$CPU_TOTAL" "$CPU_DEMOTED" "$COV_PROC" "$COV_CPU" "$THRESHOLD" "$DEMOTED_PRI_MAX" \
  "${LOAD1:-?}" "$PATTERN" "${_gate_metric:-proc}" "$N_PRI4" "$N_PRI20" "$CLAMP_PRIS" \
  "$RUNS_DEMOTED" "$RUNS_FULL" "$COV_RUN" "$N_UNATTRIB")

if [ "$APPEND" = "1" ]; then
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  printf '%s\n' "$JSON" >> "$LOG" 2>/dev/null || true
fi

if [ "$QUIET" != "1" ] && [ "$WANT_JSON" != "1" ]; then
  echo "QoS census — $TS"
  echo "  positive control (two-sided): $CONTROL"
  echo "  gate runs in flight:          $N_RUNS"
  echo "  procs   demoted/total:        $N_DEMOTED/$N_TOTAL   (${COV_PROC}%)"
  echo "    by band  utility/bg+maint:  ${N_PRI20}/${N_PRI4}   (pri 20 / pri<=4)"
  # RUN coverage is the operator-facing one — one vote per gate run, undistortable by a single proc
  # (header, THREE COVERAGE METRICS). Unattributed rows are NAMED here rather than quietly excluded.
  echo "  runs    demoted/total:        ${RUNS_DEMOTED}/${N_RUNS}   (${COV_RUN}%)   [${N_UNATTRIB} proc(s) unattributed]"
  echo "  CPU     demoted/total:        ${CPU_DEMOTED}/${CPU_TOTAL}   (${COV_CPU}%)"
  # The label names the metric actually GATED (seam QOS_GATE_ON), which is PROC by default. It read
  # "(CPU)" while gating proc — a static falsehood in the operator-facing line, fixed here because
  # M1-rev rewrites this line anyway.
  if [ -n "$CLAMP_PRIS" ]; then
    echo "  threshold (${_gate_metric:-proc}):             ${THRESHOLD}%   demoted = pri<=${DEMOTED_PRI_MAX} AND pri in {${CLAMP_PRIS}}"
  else
    echo "  threshold (${_gate_metric:-proc}):             ${THRESHOLD}%   demoted = pri<=${DEMOTED_PRI_MAX}   (clamp filter OFF)"
  fi
  echo "  VERDICT:                      $VERDICT"
  if [ "$VERDICT" = "NO-BURST" ]; then
    echo "  NOTE: <2 concurrent gate runs — this is a NON-VERDICT, not a pass."
  fi
fi
[ "$WANT_JSON" = "1" ] && printf '%s\n' "$JSON"

exit "$RC"
