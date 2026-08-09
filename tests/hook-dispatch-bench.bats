#!/usr/bin/env bats
# hook-dispatch-bench.bats — the parallel-vs-serial occupancy bench (Wave B / §S6.4).
#
# WHY THE VERDICT IS TESTED THROUGH --analyse. A bench that can only be exercised by running it is
# a bench whose arithmetic nobody has checked: a live run's numbers move with the box, so no
# assertion over them can be exact, and the interesting failures (a missing ambient subtraction, a
# missing divide-by-work, a mean where a median was specified) all produce plausible output. Feeding
# a SYNTHETIC results file makes every one of them exactly assertable — and it is the same
# separation idle-slope-sweep.sh:131-134 already established for --regress.
#
# Harness laws (repo convention): L1 fixtures reproduce the LIVE shape; L2 assertions key on
# failure-distinct values; L3 `[ ]` / `grep -q` only; L4 every behaviour has a must-change AND a
# must-NOT-change fixture.

setup() {
  # HERMETICITY first — the subject resolves its probe and its scratch relative to $HOME-adjacent
  # state, and a live run would touch the operator's box.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/hook-dispatch-bench.sh"
  D="$BATS_TEST_TMPDIR"

  # The results shape run_arm writes: cycle, arm, mean_runnable, top-bucket, wall, dispatches.
  # Ambient 4.0; serial 8.0 over 100 dispatches; parallel 16.0 over 200. Equal WORK per dispatch by
  # construction, so a correct verdict must report serial 0.16, parallel 0.24, ratio 1.50.
  FIX="$D/flat.tsv"
  { for c in 1 2 3; do
      printf '%s\tidle\t4.000\tbash\t4\t0\n' "$c"
      printf '%s\tserial\t8.000\tgit\t4\t100\n' "$c"
      printf '%s\tparallel\t16.000\tgit\t4\t200\n' "$c"
    done; } > "$FIX"
}

# ══ §A — USAGE AND REFUSALS ══

@test "A1: a non-integer or zero seam is a usage error, not a run" {
  run bash "$S" --members 0 --analyse "$FIX"
  [ "$status" -eq 64 ]
  printf '%s' "$output" | grep -q 'MEMBERS must be a positive integer'
}

@test "A2: an unknown profile is refused by name" {
  run bash "$S" --profile wishful --analyse "$FIX"
  [ "$status" -eq 64 ]
  printf '%s' "$output" | grep -q 'profile must be git|cached|noop'
}

@test "A3: an unknown argument is refused rather than ignored" {
  run bash "$S" --turbo
  [ "$status" -eq 64 ]
  printf '%s' "$output" | grep -q "unknown arg '--turbo'"
}

@test "A4: the fork-bomb bound REFUSES rather than throttling" {
  # The parallel arm holds sessions x members processes by construction — that IS the quantity under
  # test, so it can only be refused, never quietly reduced. A bench for a capacity ceiling must not
  # be the thing that breaches it.
  CC_HDB_MAX_PROCS=10 run bash "$S" --sessions 6 --members 10
  [ "$status" -eq 4 ]
  printf '%s' "$output" | grep -q 'REFUSED — parallel arm would hold 60 processes'
}

@test "A5: --analyse is answered BEFORE any check on the state of the box" {
  # Re-reading a run taken an hour ago must not be refusable because the box is busy now.
  CC_HDB_MAX_START_LOAD=0 run bash "$S" --analyse "$FIX"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'MEDIAN RATIO'
}

@test "A6: an unreadable --analyse path is a usage error" {
  run bash "$S" --analyse "$D/nope.tsv"
  [ "$status" -eq 64 ]
  printf '%s' "$output" | grep -q "cannot read"
}

# ══ §B — THE ARITHMETIC ══

@test "B1: ambient is subtracted per cycle and the result is divided by WORK" {
  run bash "$S" --analyse "$FIX"
  [ "$status" -eq 0 ]
  # (8.0-4.0)*4/100 = 0.16000   and   (16.0-4.0)*4/200 = 0.24000
  printf '%s' "$output" | grep -q 'serial         0.16000'
  printf '%s' "$output" | grep -q 'parallel       0.24000'
  printf '%s' "$output" | grep -q 'MEDIAN RATIO = 1.50x'
}

@test "B2: fewer than 2 cycles reports NOT COMPUTED rather than a number" {
  head -3 "$FIX" > "$D/one.tsv"
  run bash "$S" --analyse "$D/one.tsv"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'VERDICT: not computed'
  # A one-cycle run must not emit a ratio at all — a single draw from a 2x-swinging ambient.
  ! printf '%s' "$output" | grep -q 'MEDIAN RATIO' || false
}

@test "B3: the ambient subtraction is PER CYCLE — a cycle with different ambient still reads 1.50" {
  # Cycle 2 sits on double the ambient, with every arm shifted by the same amount. A per-cycle
  # subtraction is unmoved; a run-level average is not. This is precisely the correction wave A's
  # sweep lacked, and the reason its slope came out negative.
  { printf '1\tidle\t4.000\tbash\t4\t0\n'
    printf '1\tserial\t8.000\tgit\t4\t100\n'
    printf '1\tparallel\t16.000\tgit\t4\t200\n'
    printf '2\tidle\t8.000\tbash\t4\t0\n'
    printf '2\tserial\t12.000\tgit\t4\t100\n'
    printf '2\tparallel\t20.000\tgit\t4\t200\n'; } > "$D/drift.tsv"
  run bash "$S" --analyse "$D/drift.tsv"
  printf '%s' "$output" | grep -q 'per-cycle parallel/serial ratios: 1.50 1.50'
}

@test "B4: the headline is a MEDIAN — one contaminated cycle cannot carry it" {
  { cat "$FIX"
    printf '4\tidle\t4.000\tbash\t4\t0\n'
    printf '4\tserial\t8.000\tgit\t4\t100\n'
    printf '4\tparallel\t204.000\tgit\t4\t200\n'; } > "$D/spike.tsv"
  run bash "$S" --analyse "$D/spike.tsv"
  # The spiked cycle is ratio 25.0; a mean would report ~7.4. The median holds at 1.50.
  printf '%s' "$output" | grep -q 'MEDIAN RATIO = 1.50x'
  printf '%s' "$output" | grep -q 'spread 1.50..25.00'
  # ...and the spread must be called out, because a median over that range has no power.
  printf '%s' "$output" | grep -q 'SPREAD 1.50..25.00 exceeds 2.5x'
}

# ══ §C — THE NULL CONTROL CERTIFIES OR REFUSES ══

@test "C1: --control PASSES when the two arms genuinely agree" {
  { for c in 1 2 3; do
      printf '%s\tidle\t4.000\tbash\t4\t0\n' "$c"
      printf '%s\tserial\t8.000\tgit\t4\t100\n' "$c"
      printf '%s\tserial-b\t8.000\tgit\t4\t100\n' "$c"
    done; } > "$D/ctrl-ok.tsv"
  run bash "$S" --control --analyse "$D/ctrl-ok.tsv"
  printf '%s' "$output" | grep -q 'CONTROL PASSED'
  printf '%s' "$output" | grep -q 'MEDIAN RATIO = 1.00x'
}

@test "C2: --control FAILS when the rig cannot resolve its own null" {
  { for c in 1 2 3; do
      printf '%s\tidle\t4.000\tbash\t4\t0\n' "$c"
      printf '%s\tserial\t8.000\tgit\t4\t100\n' "$c"
      printf '%s\tserial-b\t10.000\tgit\t4\t100\n' "$c"
    done; } > "$D/ctrl-bad.tsv"
  run bash "$S" --control --analyse "$D/ctrl-bad.tsv"
  printf '%s' "$output" | grep -q 'CONTROL FAILED'
  printf '%s' "$output" | grep -q 'Do NOT quote a live run'
}

@test "C3: the two control arms are keyed DISTINCTLY — the control cannot compare a value to itself" {
  # The first draft labelled both control arms `serial`, so awk overwrote one with the other and the
  # control reported exactly 1.00x by construction: a rig that could not fail. C2's fixture is the
  # proof it can now; this asserts the mechanism directly.
  grep -q 'ARM_B="serial-b"' "$S"
  ! grep -q 'ARM_B="parallel"; \[ "$CONTROL" -eq 1 \] && ARM_B="serial"$' "$S" || false
}

# ══ §D — MUTATION CHECKS ══

@test "D1: MUTATION — dropping the ambient subtraction inflates both arms and moves the ratio" {
  m="$D/mut1.sh"
  sed 's|ds = (s-is)\*wall|ds = (s-0)*wall|; s|db = (b-is)\*wall|db = (b-0)*wall|' "$S" > "$m"
  grep -q 'ds = (s-0)\*wall' "$m"
  ! grep -q 'ds = (s-is)\*wall' "$m" || false

  run bash "$m" --analyse "$FIX"
  # Unsubtracted: serial 8*4/100 = 0.32, parallel 16*4/200 = 0.32 — the effect VANISHES entirely.
  if printf '%s' "$output" | grep -q 'MEDIAN RATIO = 1.50x'; then
    echo "MUTATION SURVIVED: ambient subtraction removed but the ratio was unchanged" >&2
    false
  fi
  printf '%s' "$output" | grep -q 'MEDIAN RATIO = 1.00x'
}

@test "D2: MUTATION — dropping the divide-by-work credits the arm that did more of it" {
  m="$D/mut2.sh"
  sed 's|/disp\[c"/serial"\]||; s|/disp\[c"/" armb\]||' "$S" > "$m"
  ! grep -q '/disp\[c"/serial"\]' "$m" || false

  run bash "$m" --analyse "$FIX"
  # Without the equal-work divisor: serial (8-4)*4 = 16, parallel (16-4)*4 = 48 — a 3.00x ratio
  # over the SAME work per dispatch. This is the trap that would have manufactured the wave's
  # hoped-for answer.
  if printf '%s' "$output" | grep -q 'MEDIAN RATIO = 1.50x'; then
    echo "MUTATION SURVIVED: divide-by-dispatches removed but the ratio was unchanged" >&2
    false
  fi
  printf '%s' "$output" | grep -q 'MEDIAN RATIO = 3.00x'
}

@test "D3: MUTATION — reporting the mean instead of the median lets one spike carry the headline" {
  m="$D/mut3.sh"
  sed 's|med = (m==0) ? 0 : ((m%2) ? R\[int((m+1)/2)\] : (R\[m/2\]+R\[m/2+1\])/2)|med = 0; for (q=1;q<=m;q++) med += R[q]; med = (m==0)?0:med/m|' "$S" > "$m"
  grep -q 'med = 0; for (q=1' "$m"

  { cat "$FIX"
    printf '4\tidle\t4.000\tbash\t4\t0\n'
    printf '4\tserial\t8.000\tgit\t4\t100\n'
    printf '4\tparallel\t204.000\tgit\t4\t200\n'; } > "$D/spike2.tsv"
  run bash "$m" --analyse "$D/spike2.tsv"
  # Mean of {1.5, 1.5, 1.5, 25.0} = 7.375 — the spike now carries the headline.
  if printf '%s' "$output" | grep -q 'MEDIAN RATIO = 1.50x'; then
    echo "MUTATION SURVIVED: mean substituted for median but the spike did not move the headline" >&2
    false
  fi
  printf '%s' "$output" | grep -q 'MEDIAN RATIO = 7.38x'
}
