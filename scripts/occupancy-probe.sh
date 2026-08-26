#!/bin/bash
# occupancy-probe.sh — measure OCCUPANCY: the mean number of simultaneously-runnable threads, and
# WHICH components hold those slots.
#
# WHY THIS EXISTS. docs/research/session-capacity-ceiling-2026-08-09.md §12 settled the capacity
# mechanism: `load ≈ mean number of simultaneously-runnable threads`, and fork RATE is not a capacity
# variable — fork CONCURRENCY is. The measured cross-over is the whole argument: 2,376 forks/s at
# concurrency 4 adds +1.6 load, while 1,255 forks/s at concurrency 16 adds +17.5. Rate DOWN 1.9x,
# load UP 11x.
#
# §12.2 then names the next measurement and explicitly does not run it:
#     "sample runnable-thread count per session directly … attributed by process tree … That
#      converts the 12x target into a named list of things to serialise."
# This is that instrument. Without it, "consolidate the pollers" is a hope; with it, every claim in
# Phase A is a regression coefficient over a swept N.
#
# WHY NOT JUST READ loadavg. Two reasons, both measured:
#   · loadavg is a 1-minute EWMA. It has not reached 63% of its target before a 30 s burst is over
#     (docs/research/session-capacity-blind-terms-2026-08-09.md §3) — the gauge whose job is to catch
#     bursts is slower than the bursts. A ≥1 Hz instantaneous sampler has no such lag.
#   · loadavg is one scalar. It cannot say WHICH component holds the slot, and the named list is the
#     entire point. This probe emits loadavg BESIDE its own count precisely so the two can be
#     cross-checked: an R-count that does not track loadavg over a run indicts the probe.
#
# THE DENOMINATOR IS CONTROLLED, NOT ASSUMED (memory: positive-control-the-denominator). A probe that
# samples `ps` is itself runnable at the instant it samples, and so is the `ps` it forked. Left
# uncorrected that is a floor of ~2 runnable threads that the probe manufactures and then reports as
# the machine's. Self rows are EXCLUDED from the occupancy figure and COUNTED into a `self` field, so
# the correction is auditable rather than silent — a probe that silently drops rows cannot be
# distinguished from one whose filter is wrong.
#
# ATTRIBUTION IS BY COMMAND POSITION, NEVER BY ARGV SUBSTRING (memory: pgrep-f-matches-agent-briefs).
# Agent briefs travel in argv: on this box `pgrep -f cc-reaper` counts every session whose prompt
# merely MENTIONS cc-reaper, and read 50 where the truth was 1. Rows are bucketed on the basename of
# the EXECUTABLE, with one deliberate extension: for an interpreter (`/bin/bash /path/to/foo.sh`) the
# bucket is the SCRIPT's basename, because `bash` is the answer to a question nobody asked. That
# extension applies only when the second field is a path — `bash -c …` stays `bash`.
#
# Verdict-free by design where it can be: this is a measuring instrument, so it exits 0 on a
# completed run, 64 on a usage error, and 3 when it could not read the machine on ANY sample. Zero
# usable samples must never exit 0 into a caller that would read success (the exact defect
# compressor-sentinel.sh:579 guards).
#
# Seams: CC_OCC_HZ (2) · CC_OCC_SECONDS (30) · CC_OCC_TOPN (18) · CC_OCC_LABEL ("")
set -uo pipefail

HZ="${CC_OCC_HZ:-2}"
SECONDS_TOTAL="${CC_OCC_SECONDS:-30}"
TOPN="${CC_OCC_TOPN:-18}"
LABEL="${CC_OCC_LABEL:-}"
JSON=0
FIXTURE=""

usage() {
  sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --hz)       HZ="${2:-}";            shift ;;
    --seconds)  SECONDS_TOTAL="${2:-}"; shift ;;
    --topn)     TOPN="${2:-}";          shift ;;
    --label)    LABEL="${2:-}";         shift ;;
    --json)     JSON=1 ;;
    # A canned `ps` capture, one sample per run. This is what lets the suite drive the classifier
    # without a machine, so the tests are identical on a loaded box and an idle one.
    --fixture)  FIXTURE="${2:-}";       shift ;;
    -h|--help)  usage ;;
    *) echo "occupancy-probe.sh: unknown arg '$1'" >&2; exit 64 ;;
  esac
  shift
done

for _v in HZ SECONDS_TOTAL TOPN; do
  _x="${!_v}"
  case "$_x" in ''|*[!0-9]*)
    printf 'occupancy-probe.sh: %s must be a positive integer (got "%s")\n' "$_v" "$_x" >&2; exit 64 ;;
  esac
  [ "$_x" -gt 0 ] || { printf 'occupancy-probe.sh: %s must be > 0\n' "$_v" >&2; exit 64; }
done

# ── the classifier ────────────────────────────────────────────────────────────────────────────────
# stdin: `ps -axo state=,pid=,ppid=,command=`.
# stdout: one line per RUNNABLE row — "<pid> <bucket>" — plus a trailing "#self <n>" line.
#
# RUNNABLE is state beginning with R. Darwin's load average is sched_run_buckets[TH_BUCKET_RUN], i.e.
# threads in the run bucket; `ps` reports a PROCESS state, so this is a per-process proxy for a
# per-thread quantity. That approximation is stated rather than hidden: it UNDER-counts a process
# with several runnable threads (one `claude` node process can hold more than one), so the figure is
# a LOWER bound on occupancy. A lower bound is the safe direction for a probe whose job is to prove a
# reduction — it cannot manufacture the win it is looking for.
#
# The self set is the probe pid and its ENTIRE DESCENDANT SUBTREE, resolved by walking the ppid chain
# of every row against a map built from the same sample. A one-level `ppid == self` test is NOT
# sufficient and the first version of this probe shipped with that bug: `RAW="$(ps …)"` runs the `ps`
# in a command-substitution SUBSHELL, so its parent is the subshell and its grandparent is the probe.
# The measured symptom was a `ps` bucket sitting at exactly 1.000 runnable rows per sample — a floor
# the instrument manufactured and then reported as the machine's. Depth is not knowable in advance
# (a pipeline adds another level), so the walk is unbounded rather than tuned to the current shape.
#
# The walk is depth-capped only to defend against a ppid cycle, which cannot occur on a live kernel
# but can trivially be written into a fixture; a cycle would otherwise hang the classifier.
classify_rows() { # <self_pid>
  awk -v self="$1" '
    # PASS 1 — over EVERY row, not just the runnable ones, because the walk breaks the moment an
    # intermediate ancestor is SLEEPING, and that is the common case rather than the exception: the
    # probe shell sits blocked in `wait` while the `ps` it spawned is the runnable one.
    #
    # The three leading columns are read as $1/$2/$3 under awk default field splitting, which skips
    # leading blanks — ps right-aligns the state column, so a positional read of the raw line would
    # be off by one on every indented row.
    #
    # The three columns are CAPTURED HERE and never re-split later. Re-splitting the stored line in
    # END with an explicit separator — `split(line, c, /[ \t]+/)` — is a live trap and this probe
    # shipped with it for one revision: awk skips leading blanks only under the DEFAULT field
    # separator, so with an explicit one the right-aligned state column lands in c[2] and c[1] is the
    # empty string before it. Every row then read as state "" and the classifier emitted nothing at
    # all while still printing a well-formed `#self 0` footer — an instrument that looked like it
    # ran and had classified precisely zero rows.
    NF >= 4 && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {
      par[$2] = $3
      n++; st[n] = $1; pid[n] = $2; ppid[n] = $3; rows[n] = $0
    }

    # Walks the ppid chain to the root. Depth-capped ONLY to defend against a ppid cycle: it cannot
    # occur on a live kernel but is trivially writable into a fixture, and a cycle would hang the
    # classifier rather than fail it.
    function is_self(p,   d) {
      for (d = 0; d < 64; d++) {
        if (p == self) return 1
        if (p <= 1) return 0
        if (!(p in par)) return 0
        if (par[p] == p) return 0
        p = par[p]
      }
      return 0
    }

    END {
      for (r = 1; r <= n; r++) {
        line = rows[r]
        if (st[r] !~ /^R/) continue
        if (is_self(pid[r])) { selfn++; continue }

        # The command is taken as the VERBATIM remainder after the three fixed columns rather than
        # rejoined from $4..$NF, because rejoining collapses runs of whitespace inside argv and so
        # silently rewrites the record (compressor-sentinel.sh:286 records the same trap).
        if (!match(line, /^[ \t]*[^ \t]+[ \t]+[0-9]+[ \t]+[0-9]+[ \t]+/)) continue
        cmd = substr(line, RSTART + RLENGTH)

        nf = split(cmd, f, /[ \t]+/)
        cc = split(f[1], p, "/"); base = p[cc]

        # Interpreter extension: bucket on the SCRIPT, not the interpreter, because `bash` is the
        # answer to a question nobody asked — 40 different hooks all render as one bucket otherwise.
        # It applies ONLY when the next field is a path, so `bash -c …`, `awk {…}` and a bare `node`
        # keep their own name: there is no script there to name.
        if (base ~ /^(bash|sh|zsh|dash|ksh|python[0-9.]*|perl|ruby|osascript)$/ && nf >= 2 && f[2] ~ /^\.?\.?\//) {
          c2 = split(f[2], q, "/"); base = q[c2]
        }
        # A parenthesised comm — `(bash)`, `(jq)` — is how macOS ps renders a process whose argv it
        # cannot read (mid-exec, or a zombie mid-reap). It keeps its own bucket rather than being
        # folded into the real one: an unreadable row is a different fact from a readable one, and a
        # bucket that absorbed it would overstate whatever it was folded into.
        gsub(/[()]/, "", base)
        if (base == "") base = "?"
        printf "%s %s\n", pid[r], base
      }
      printf "#self %d\n", selfn + 0
    }'
}

# ── fixture mode: one classified sample, then out ─────────────────────────────────────────────────
# Exists so the suite can assert the classifier's behaviour — interpreter extension, self-exclusion,
# argv-substring immunity — against a canned capture, with no machine involved.
if [ -n "$FIXTURE" ]; then
  [ -r "$FIXTURE" ] || { printf 'occupancy-probe.sh: cannot read fixture "%s"\n' "$FIXTURE" >&2; exit 64; }
  # Self pid 0 never matches a real row, so a fixture exercises the classifier with the exclusion
  # inert unless the fixture itself carries pid/ppid 0 rows.
  classify_rows "${CC_OCC_SELF_PID:-0}" < "$FIXTURE"
  exit 0
fi

# ── readers ───────────────────────────────────────────────────────────────────────────────────────
# Non-zero rather than a value when the instrument is unreadable. No fallbacks, no fabricated zeros:
# "could not measure" must never render as "the box was idle".
read_loadavg_1m() {
  local v
  v="$(sysctl -n vm.loadavg 2>/dev/null)" || return 1
  # `{ 9.04 8.43 8.67 }` → 9.04
  v="${v#*\{ }"; v="${v%% *}"
  case "$v" in ''|*[!0-9.]*) return 1 ;; esac
  printf '%s' "$v"
}

# ── sampling loop ─────────────────────────────────────────────────────────────────────────────────
SELF=$$
INTERVAL="$(awk -v hz="$HZ" 'BEGIN{ printf "%.4f", 1/hz }')"
NSAMPLES=$((SECONDS_TOTAL * HZ))
[ "$NSAMPLES" -gt 0 ] || { echo "occupancy-probe.sh: seconds x hz must be > 0" >&2; exit 64; }

TALLY_FILE="$(mktemp -t occ-tally)" || { echo "occupancy-probe.sh: mktemp failed" >&2; exit 3; }
trap 'rm -f "$TALLY_FILE"' EXIT

TOTAL_R=0
TOTAL_SELF=0
GOOD=0
SKIPPED=0
LOAD_SUM=0
LOAD_N=0

i=0
while [ "$i" -lt "$NSAMPLES" ]; do
  i=$((i + 1))
  RAW="$(ps -axo state=,pid=,ppid=,command= 2>/dev/null)" || RAW=""
  if [ -z "$RAW" ]; then
    # An unreadable ps is a BLIND sample, not an idle box. It is counted and reported, never
    # averaged in as a zero — a zero here would drag the mean toward the answer the wave wants.
    SKIPPED=$((SKIPPED + 1))
    sleep "$INTERVAL"
    continue
  fi

  OUT="$(printf '%s\n' "$RAW" | classify_rows "$SELF")"
  SELF_N="$(printf '%s\n' "$OUT" | awk '/^#self /{print $2; exit}')"
  R_N="$(printf '%s\n' "$OUT" | awk '!/^#self /{n++} END{print n+0}')"
  printf '%s\n' "$OUT" | awk '!/^#self /{print $2}' >> "$TALLY_FILE"

  TOTAL_R=$((TOTAL_R + R_N))
  TOTAL_SELF=$((TOTAL_SELF + ${SELF_N:-0}))
  GOOD=$((GOOD + 1))

  if L="$(read_loadavg_1m)"; then
    LOAD_SUM="$(awk -v a="$LOAD_SUM" -v b="$L" 'BEGIN{printf "%.4f", a+b}')"
    LOAD_N=$((LOAD_N + 1))
  fi

  sleep "$INTERVAL"
done

# Zero usable samples is a broken instrument. Exiting 0 here would hand a caller a clean-looking
# "0.00 occupancy" that is the absence of measurement, not the absence of load.
[ "$GOOD" -gt 0 ] || {
  printf 'occupancy-probe.sh: ZERO readable samples of %s — instrument blind, no verdict\n' "$NSAMPLES" >&2
  exit 3
}

MEAN_R="$(awk -v t="$TOTAL_R" -v n="$GOOD" 'BEGIN{printf "%.3f", t/n}')"
MEAN_SELF="$(awk -v t="$TOTAL_SELF" -v n="$GOOD" 'BEGIN{printf "%.3f", t/n}')"
MEAN_LOAD="$(awk -v s="$LOAD_SUM" -v n="$LOAD_N" 'BEGIN{ if (n<=0) print "null"; else printf "%.3f", s/n}')"

if [ "$JSON" = 1 ]; then
  BUCKETS="$(sort "$TALLY_FILE" | uniq -c | sort -rn | head -n "$TOPN" \
    | awk -v n="$GOOD" 'BEGIN{printf "{"} { printf "%s\"%s\":%.3f", (k++?",":""), $2, $1/n } END{printf "}"}')"
  printf '{"label":"%s","samples":%s,"skipped":%s,"hz":%s,"seconds":%s,"mean_runnable":%s,"mean_self_excluded":%s,"mean_load1":%s,"buckets":%s}\n' \
    "$LABEL" "$GOOD" "$SKIPPED" "$HZ" "$SECONDS_TOTAL" "$MEAN_R" "$MEAN_SELF" "$MEAN_LOAD" "$BUCKETS"
else
  printf '─── occupancy %s ───\n' "${LABEL:-(unlabelled)}"
  printf 'samples        : %s good, %s BLIND (unreadable ps — not counted as zero)\n' "$GOOD" "$SKIPPED"
  printf 'rate           : %s Hz for %s s\n' "$HZ" "$SECONDS_TOTAL"
  printf 'MEAN RUNNABLE  : %s   (self-excluded: %s rows/sample)\n' "$MEAN_R" "$MEAN_SELF"
  printf 'mean load1     : %s   (EWMA — lags this probe by design; cross-check, not ground truth)\n' "$MEAN_LOAD"
  printf '\nheld slots, by component (mean runnable rows per sample, top %s):\n' "$TOPN"
  sort "$TALLY_FILE" | uniq -c | sort -rn | head -n "$TOPN" \
    | awk -v n="$GOOD" '{ printf "  %8.3f  %s\n", $1/n, $2 }'
fi

exit 0
