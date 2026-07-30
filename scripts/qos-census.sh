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
# PRI BANDS — calibrated empirically, re-derived 2026-07-30 under `env -i` to isolate inherited NI:
#   nice 19 + taskpolicy -c background  -> NI=20  PRI=4    <- demoted
#   taskpolicy -c background ALONE      -> NI=0   PRI=4    <- ALSO demoted (the row first omitted)
#   nice 19 alone                       -> NI=20  PRI=31   <- NOT demoted
#   plain                               -> NI=0   PRI=31
# THE TWO LEGS ARE STRICTLY ORTHOGONAL: nice(1) moves NI and nothing else; taskpolicy(8) moves PRI
# (and the I/O tier) and nothing else. PRI tracks the taskpolicy column exactly, in both directions,
# regardless of nice. So `taskpolicy` is the load-bearing mechanism and `nice` is near-cosmetic for
# PRI — an earlier three-row version of this table omitted the taskpolicy-alone row and thereby
# implied nice contributed something, which mislabelled the shim's "PARTIAL" mode as a partial
# demotion when it is ZERO demotion. This census counts only the PRI band, so it was never wrong —
# but the table a reader reasons from was.
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
DEMOTED_PRI_MAX="${QOS_DEMOTED_PRI_MAX:-10}"  # calibrated: background tier is 4; 10 is headroom
LOG="${QOS_CENSUS_LOG:-$HOME/.claude/logs/qos-census.jsonl}"
PATTERN="${QOS_CENSUS_PATTERN:-bats}"
NO_CONTROL="${QOS_CENSUS_NO_CONTROL:-0}"      # tests only; production must keep the control on

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

# ── classify one pid: prints "demoted" | "full" | "gone" ──────────────────────────────────────
classify_pid() {
  local pid="$1" pri
  pri=$(ps -p "$pid" -o pri= 2>/dev/null | tr -d ' ')
  if [ -z "$pri" ]; then printf 'gone'; return 0; fi
  if [ "$pri" -le "$DEMOTED_PRI_MAX" ] 2>/dev/null; then printf 'demoted'; else printf 'full'; fi
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
    /usr/bin/nice -n 19 "$_tp" -c background /bin/sleep 3 >/dev/null 2>&1 &
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

N_DEMOTED=0; N_FULL=0; CPU_DEMOTED=0; CPU_FULL=0
if [ -n "$SNAP" ]; then
  read -r N_DEMOTED N_FULL CPU_DEMOTED CPU_FULL <<EOF
$(printf '%s\n' "$SNAP" | awk -v m="$DEMOTED_PRI_MAX" '
  { pri=$3+0; cpu=$4+0; if (pri<=m) { nd++; cd+=cpu } else { nf++; cf+=cpu } }
  END { printf "%d %d %.1f %.1f", nd+0, nf+0, cd+0, cf+0 }')
EOF
fi

N_TOTAL=$((N_DEMOTED + N_FULL))
CPU_TOTAL=$(awk -v a="$CPU_DEMOTED" -v b="$CPU_FULL" 'BEGIN{printf "%.1f", a+b}')

# distinct concurrent gate RUNS — bats stamps a unique bats-run-XXXXXX tmpdir per invocation, so
# this counts real concurrency rather than the proc fan-out of a single run.
N_RUNS=$(printf '%s\n' "$SNAP" | grep -oE 'bats-run-[A-Za-z0-9]+' | sort -u | grep -c . || true)
[ -z "$N_RUNS" ] && N_RUNS=0

COV_PROC=$(awk -v d="$N_DEMOTED" -v t="$N_TOTAL" 'BEGIN{ if(t<=0){print "0.0"} else {printf "%.1f", 100*d/t} }')
COV_CPU=$(awk -v d="$CPU_DEMOTED" -v t="$CPU_TOTAL" 'BEGIN{ if(t<=0){print "0.0"} else {printf "%.1f", 100*d/t} }')

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
  # Seam: QOS_GATE_ON=cpu switches the gate to CPU coverage for a burst known to be CPU-active.
  _gate_metric="${QOS_GATE_ON:-proc}"
  if [ "$_gate_metric" = "cpu" ]; then _gv="$COV_CPU"; else _gv="$COV_PROC"; fi
  _ok=$(awk -v c="$_gv" -v t="$THRESHOLD" 'BEGIN{print (c+0 >= t+0) ? 1 : 0}')
  if [ "$_ok" = "1" ]; then VERDICT="PASS"; RC=0; else VERDICT="FAIL"; RC=1; fi
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOAD1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
JSON=$(printf '{"ts":"%s","verdict":"%s","control":"%s","runs_in_flight":%s,"procs_total":%s,"procs_demoted":%s,"procs_full":%s,"cpu_total":%s,"cpu_demoted":%s,"coverage_proc_pct":%s,"coverage_cpu_pct":%s,"threshold":%s,"demoted_pri_max":%s,"loadavg1":"%s","pattern":"%s","gate_on":"%s"}' \
  "$TS" "$VERDICT" "$CONTROL" "$N_RUNS" "$N_TOTAL" "$N_DEMOTED" "$N_FULL" \
  "$CPU_TOTAL" "$CPU_DEMOTED" "$COV_PROC" "$COV_CPU" "$THRESHOLD" "$DEMOTED_PRI_MAX" \
  "${LOAD1:-?}" "$PATTERN" "${_gate_metric:-proc}")

if [ "$APPEND" = "1" ]; then
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  printf '%s\n' "$JSON" >> "$LOG" 2>/dev/null || true
fi

if [ "$QUIET" != "1" ] && [ "$WANT_JSON" != "1" ]; then
  echo "QoS census — $TS"
  echo "  positive control (two-sided): $CONTROL"
  echo "  gate runs in flight:          $N_RUNS"
  echo "  procs   demoted/total:        $N_DEMOTED/$N_TOTAL   (${COV_PROC}%)"
  echo "  CPU     demoted/total:        ${CPU_DEMOTED}/${CPU_TOTAL}   (${COV_CPU}%)"
  echo "  threshold (${_gate_metric:-proc}):             ${THRESHOLD}%   band: pri<=${DEMOTED_PRI_MAX}"
  echo "  VERDICT:                      $VERDICT"
  if [ "$VERDICT" = "NO-BURST" ]; then
    echo "  NOTE: <2 concurrent gate runs — this is a NON-VERDICT, not a pass."
  fi
fi
[ "$WANT_JSON" = "1" ] && printf '%s\n' "$JSON"

exit "$RC"
