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
  # ...and the dispersion must be called out, because a median over that range has no power.
  # The wording moved with the statistic on 2026-09-08 (max/min range -> sign-test interval on the
  # median); at m=4 no k reaches 90% coverage, so the interval still degenerates to the full range
  # and the SAME two failure-distinct endpoints appear. What is new beside them is the coverage
  # figure, which is what makes "no power" a claim rather than an adjective.
  printf '%s' "$output" | grep -q 'CI 1.50..25.00 spans more than 2.5x'
  printf '%s' "$output" | grep -q '88% CI on the median = 1.50..25.00'
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
  # Assert the DIAGNOSIS, not the boilerplate: a median off 1.00 means one arm is measured
  # differently from the other, which is a different fault with a different remedy from mere noise.
  # (Keying on the sentence 'Do NOT quote a live run' broke the moment the line wrapped between
  # 'quote' and 'a live run' — an assertion on prose layout, not on meaning.)
  printf '%s' "$output" | grep -q 'BIASED'
  ! printf '%s' "$output" | grep -q 'UNDERPOWERED' || false
}

@test "C2b: --control distinguishes UNDERPOWERED from BIASED" {
  # Median exactly 1.00 but a spread far too wide to resolve anything: the rig is unbiased and
  # underpowered. That verdict must NOT read as bias — the remedies differ (re-run quieter / with
  # more cycles, versus find the asymmetry between the arms), and only this one leaves a
  # directional reading available.
  { printf '1\tidle\t4.000\tbash\t4\t0\n'
    printf '1\tserial\t8.000\tgit\t4\t100\n'
    printf '1\tserial-b\t5.600\tgit\t4\t100\n'
    printf '2\tidle\t4.000\tbash\t4\t0\n'
    printf '2\tserial\t8.000\tgit\t4\t100\n'
    printf '2\tserial-b\t8.000\tgit\t4\t100\n'
    printf '3\tidle\t4.000\tbash\t4\t0\n'
    printf '3\tserial\t8.000\tgit\t4\t100\n'
    printf '3\tserial-b\t14.000\tgit\t4\t100\n'; } > "$D/ctrl-wide.tsv"
  run bash "$S" --control --analyse "$D/ctrl-wide.tsv"
  printf '%s' "$output" | grep -q 'MEDIAN RATIO = 1.00x'
  printf '%s' "$output" | grep -q 'CONTROL FAILED ON SPREAD'
  printf '%s' "$output" | grep -q 'UNDERPOWERED'
  ! printf '%s' "$output" | grep -q 'The rig is BIASED' || false
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

# ══ §E — THE ACCEPTANCE INTERVAL MUST NARROW AS EVIDENCE IS ADDED ══
#
# The gate these cover replaced a max/min range test on 2026-09-08. A range is non-decreasing in
# the sample size, so that gate could only ever get harder to pass as cycles were added — while the
# median it guarded converged. The bench printed "re-run ... with more cycles" as the remedy for a
# spread failure, and active-session-occupancy-2026-08-09.md §3.1 prescribes the same remedy for
# certifying the one live result this rig has produced. Both were self-defeating: measured over
# 2,000 replicates at the noise that run actually showed, P(certify) fell 51.7% -> 0.0% between 3
# and 40 cycles. E1 is the must-change fixture; E3 is the must-NOT-change one.

_ratio_rows() { # <cycle> <ratio>   — idle 4.0, serial occ 0.16, equal work both arms, so ratio = $2
  printf '%s\tidle\t4.000\tbash\t4\t0\n' "$1"
  printf '%s\tserial\t8.000\tgit\t4\t100\n' "$1"
  awk -v c="$1" -v r="$2" 'BEGIN{ printf "%s\tparallel\t%.4f\tgit\t4\t100\n", c, 4.0 + 4.0*r }'
}

@test "E1: the interval NARROWS as cycles are added, even as the sample RANGE widens" {
  # Five cycles at ratios 1..5. m=5 admits no k above 1, so the interval degenerates to the range.
  { for r in 1 2 3 4 5; do _ratio_rows "$r" "$r"; done; } > "$D/narrow-5.tsv"
  # Twenty-one cycles: the same five ratios four times over, plus ONE outlier at 100x. The range
  # explodes 5 -> 100; a converging statistic must go the other way.
  { c=0
    for _rep in 1 2 3 4; do : "$_rep"; for r in 1 2 3 4 5; do c=$((c+1)); _ratio_rows "$c" "$r"; done; done
    c=$((c+1)); _ratio_rows "$c" 100; } > "$D/narrow-21.tsv"

  run bash "$S" --analyse "$D/narrow-5.tsv"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'CI on the median = 1.00..5.00'
  printf '%s' "$output" | grep -q 'spread 1.00..5.00'

  run bash "$S" --analyse "$D/narrow-21.tsv"
  [ "$status" -eq 0 ]
  # RANGE widened 5x -> 100x ...
  printf '%s' "$output" | grep -q 'spread 1.00..100.00'
  # ... while the interval narrowed from 1.00..5.00 to 2.00..4.00. Keyed on the exact order
  # statistics -- P(Bin(21,1/2) <= 6) = 82160/2097152 = 0.0392 is the last tail at or under 0.05, so
  # the sign test selects k=7 and the interval is R[7]..R[15]. A rig that merely printed a
  # narrower-looking number cannot pass: those are the two values it selects and nothing else.
  printf '%s' "$output" | grep -q 'CI on the median = 2.00..4.00'
  printf '%s' "$output" | grep -q 'k=7 of 21 cycles'
}

@test "E2: the interval is the SIGN-TEST interval — exact order statistics, not a guess" {
  # m=20 at ratios 1..20. P(Bin(20,1/2) <= 5) = 21700/1048576 = 0.0207, so k=6 is the tightest
  # index reaching 90% coverage and the interval is R[6]..R[15] = 6.00..15.00 at 96%. Every one of
  # those three numbers is failure-distinct: k=5 would read 5.00..16.00, k=7 would read 7.00..14.00.
  { for r in $(seq 1 20); do _ratio_rows "$r" "$r"; done; } > "$D/signtest-20.tsv"
  run bash "$S" --analyse "$D/signtest-20.tsv"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '96% CI on the median = 6.00..15.00'
  printf '%s' "$output" | grep -q 'k=6 of 20 cycles'
}

@test "E3: at the 3-cycle default the interval IS the range — the replacement changes no verdict there" {
  # MUST-NOT-CHANGE. Below m=5 no k reaches 90% coverage, so the interval degenerates to the full
  # range and this gate is byte-identical to the max/min one it replaced. C1/C2/C2b all run at three
  # cycles and keep their verdicts for exactly this reason; that degeneracy is the honest reading of
  # three points, and it must be LABELLED rather than dressed up as a 90% result.
  { for r in 1 2 3; do _ratio_rows "$r" "$r"; done; } > "$D/three.tsv"
  run bash "$S" --analyse "$D/three.tsv"
  printf '%s' "$output" | grep -q '75% CI on the median = 1.00..3.00'
  printf '%s' "$output" | grep -q 'below the 90% target'
}

@test "D4: MUTATION — restoring the max/min range as the gate makes E1 unpassable again" {
  # The defect being fixed, reinstated in one line: if the interval endpoints are the sample
  # extremes, then adding cycles can only widen it. E1's 21-cycle fixture is the discriminator — it
  # was built so that the range and the interval move in OPPOSITE directions on the same data.
  m="$D/mut4.sh"
  sed 's|      ci_lo = R\[ci_k\]; ci_hi = R\[m+1-ci_k\]|      ci_lo = R[1]; ci_hi = R[m]|' "$S" > "$m"
  grep -q 'ci_lo = R\[1\]; ci_hi = R\[m\]' "$m"

  { c=0
    for _rep in 1 2 3 4; do : "$_rep"; for r in 1 2 3 4 5; do c=$((c+1)); _ratio_rows "$c" "$r"; done; done
    c=$((c+1)); _ratio_rows "$c" 100; } > "$D/mut-21.tsv"
  run bash "$m" --analyse "$D/mut-21.tsv"
  if printf '%s' "$output" | grep -q 'CI on the median = 2.00..4.00'; then
    echo "MUTATION SURVIVED: interval endpoints replaced by the sample extremes, yet it still narrowed" >&2
    false
  fi
  printf '%s' "$output" | grep -q 'CI on the median = 1.00..100.00'
}

@test "E4: past m=1000 the exact binomial computes inf/inf — the approximation guard stops it" {
  # 2^m is +inf in a double from m=1024 and C(m,m/2) overflows with it, so the exact branch divides
  # inf by inf. Measured at m=1100 it selects k=550 — exactly m/2, the NARROWEST interval the order
  # statistics admit, which is no confidence at all — and labels it `nan%`. The caveat cannot save
  # it either: `nan < 0.895` is false, so the "below the 90% target" label is suppressed and a noisy
  # run reads as decisively resolved with no coverage figure to contradict it. Keyed on both the
  # coverage token AND k, which differ between the two branches (522 vs 550).
  { for c in $(seq 1 1100); do
      printf '%s\tidle\t4.000\tx\t4\t100\n' "$c"
      printf '%s\tserial\t8.000\tx\t4\t100\n' "$c"
      awk -v c="$c" 'BEGIN{ printf "%s\tparallel\t%.4f\tx\t4\t100\n", c, 4.0 + 4.0*(1.0 + (c%7)*0.1) }'
    done; } > "$D/huge.tsv"

  run bash "$S" --analyse "$D/huge.tsv"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '90% CI on the median = '
  printf '%s' "$output" | grep -q 'normal approximation, m>1000'
  printf '%s' "$output" | grep -q 'k=522 of 1100 cycles'
  ! printf '%s' "$output" | grep -q 'nan' || false

  # MUTATION: drop the bound and the exact branch takes an infinite denominator.
  m="$D/mut5.sh"
  sed 's|if (m >= 2 \&\& m <= 1000) {|if (m >= 2) {|' "$S" > "$m"
  ! grep -q 'm >= 2 && m <= 1000' "$m" || false
  run bash "$m" --analyse "$D/huge.tsv"
  printf '%s' "$output" | grep -q 'nan% CI on the median'
  printf '%s' "$output" | grep -q 'k=550 of 1100 cycles'
}

# ══ §F — AMBIENT SENSITIVITY OF THE RATIO ══
#
# Added 2026-09-09 after two runs of §5 verbatim commands read 2.90x and 5.98x on the same box and
# agreed at their shared ambient (readjudication doc §5.2). The pre-existing check on ambient is
# `max/min > 2.0` over the idle arm — a RANGE, the same shape §2 removed from the acceptance gate —
# and BOTH those runs tripped it and were quoted past it anyway. These cases pin the replacement:
# a correlation between ambient and the per-cycle ratio, which is a property of the ESTIMATE.
#
# L4 pairing is the point here. F1 and F2 differ in ONE thing: whether the ratio moves with ambient.
# Both swing ambient by more than 2x, so both trip the old range warning; only F2 may fire the new
# one. A diagnostic that fired on both would carry exactly as much information as the range did.

_fx_ambient() { # <path> <mode: flat|tracking>  — 20 cycles, ambient rising 8.5..18.0
  local p="$1" mode="$2" c I r S P
  : > "$p"
  for c in $(seq 20); do
    I="$(awk -v c="$c" 'BEGIN{printf "%.3f", 8.0+c*0.5}')"
    if [ "$mode" = tracking ]; then
      r="$(awk -v i="$I" 'BEGIN{printf "%.4f", 1.5+0.45*(i-8.0)}')"
    else
      # jitter that is deliberately NOT monotone in the cycle index, so ranks vary without
      # tracking ambient; an all-ties ratio would make the correlation vacuously zero.
      r="$(awk -v c="$c" 'BEGIN{split("1.05 0.97 1.02 0.94 1.00 1.06 0.96 1.03 0.93 1.01",j," "); printf "%.4f", 3.0*j[(c*7)%10+1]}')"
    fi
    S="$(awk -v i="$I" 'BEGIN{printf "%.3f", i+0.06*240/6}')"
    P="$(awk -v i="$I" -v r="$r" 'BEGIN{printf "%.3f", i+0.06*r*720/6}')"
    {
      printf '%s\tidle\t%s\tbash\t6\t0\n'       "$c" "$I"
      printf '%s\tserial\t%s\tgit\t6\t240\n'    "$c" "$S"
      printf '%s\tparallel\t%s\tbash\t6\t720\n' "$c" "$P"
    } >> "$p"
  done
}

@test "F1: ambient swinging >2x with a FLAT ratio trips the range check but NOT the correlation" {
  _fx_ambient "$D/amb-flat.tsv" flat
  run bash "$S" --analyse "$D/amb-flat.tsv"
  [ "$status" -eq 0 ]
  # the control arm of the pair: the old range statistic DOES fire here, so silence below is
  # discrimination and not a dead code path.
  printf '%s' "$output" | grep -q 'AMBIENT MOVED >2x'
  printf '%s' "$output" | grep -q 'ambient-sensitivity: Spearman'
  ! printf '%s' "$output" | grep -q 'THE RATIO IS TRACKING AMBIENT'
}

@test "F2: the SAME ambient swing with a ratio that tracks it fires the correlation warning" {
  _fx_ambient "$D/amb-track.tsv" tracking
  run bash "$S" --analyse "$D/amb-track.tsv"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'THE RATIO IS TRACKING AMBIENT'
  # and it must report the actionable split, not merely complain
  printf '%s' "$output" | grep -q 'Quietest 10 cycles median'
}

@test "F3: the warning reports the quiet half BELOW the noisy half, which is the reason to quote it" {
  _fx_ambient "$D/amb-track.tsv" tracking
  run bash "$S" --analyse "$D/amb-track.tsv"
  [ "$status" -eq 0 ]
  local q n
  q="$(printf '%s' "$output" | sed -n 's/.*Quietest 10 cycles median \([0-9.]*\)x.*/\1/p')"
  n="$(printf '%s' "$output" | sed -n 's/.*noisiest 10 median \([0-9.]*\)x.*/\1/p')"
  [ -n "$q" ] && [ -n "$n" ] || false
  awk -v a="$q" -v b="$n" 'BEGIN{exit !(a < b)}'
}

@test "F4: MUTATION — correlating the ratio with ITSELF fires on the flat fixture too" {
  # Attribution, not merely liveness: the diagnostic must be keyed on AMBIENT specifically. Swap the
  # ambient vector for the ratio vector and the correlation becomes 1.00 by construction, so F1 —
  # whose whole point is that a flat ratio must stay silent under a >2x ambient swing — now fires.
  # A test that only checked "the warning can appear" would pass this mutant.
  _fx_ambient "$D/amb-flat.tsv" flat
  local M="$D/mutant-self.sh"
  sed 's|rho = spearman(RI, RU, m)|rho = spearman(RU, RU, m)|' "$S" > "$M"
  ! cmp -s "$S" "$M" || false
  run bash "$S" --analyse "$D/amb-flat.tsv"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'THE RATIO IS TRACKING AMBIENT' || false # subject: correctly silent
  run bash "$M" --analyse "$D/amb-flat.tsv"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'THE RATIO IS TRACKING AMBIENT'      # mutant: wrongly fires
}

@test "F5: below 5 retained cycles the correlation is not computed at all" {
  # 3 cycles is the bench default and 3 points cannot support a rank correlation; asserting a
  # dependence there would be the same overreach §2 removed from the gate.
  run bash "$S" --analyse "$FIX"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'ambient-sensitivity'
}

# ══ §G — RAW RESULTS ARE NOT CLOBBERED ══
#
# §5 publishes commands with hardcoded /tmp paths, so two workers on one box overwrite each other.
# That happened on 2026-09-09 and the loss was silent: --analyse then returns the OTHER run numbers
# under the earlier run name. rotate_out is a function so this is testable without a live bench.

_load_rotate() { eval "$(sed -n '/^rotate_out() {/,/^}/p' "$S")"; }

@test "G1: rotate_out preserves an existing file under a timestamped name" {
  _load_rotate
  local out="$D/results.tsv"
  printf 'PRIOR\tRUN\tDATA\n' > "$out"
  run rotate_out "$out"
  [ "$status" -eq 0 ]
  [ ! -e "$out" ]                               # moved aside, so the caller may now write freshly
  local -a kept=( "$D"/results.tsv.* )
  [ "${#kept[@]}" -eq 1 ] && [ -f "${kept[0]}" ] || false
  grep -q 'PRIOR' "${kept[0]}"                        # the prior run data survives, read back by path
  printf '%s' "$output" | grep -q 'rather than overwritten'
}

@test "G2: rotate_out is a no-op when there is nothing to lose" {
  _load_rotate
  local out="$D/fresh.tsv"
  run rotate_out "$out"
  [ "$status" -eq 0 ]
  [ -z "$output" ]                               # silent: a first run must not narrate a non-event
  [ ! -e "$out" ]
}

@test "G3: two rotations in the same second do not collide" {
  # Same-second reruns are the realistic case for a fast --analyse loop, and the stamp has 1s
  # resolution, so the first rotation must not be overwritten by the second.
  _load_rotate
  local out="$D/twice.tsv"
  printf 'FIRST\n'  > "$out"; rotate_out "$out" >/dev/null
  printf 'SECOND\n' > "$out"; rotate_out "$out" >/dev/null
  local -a rots=( "$D"/twice.tsv.* )
  [ "${#rots[@]}" -eq 2 ]                        # both preserved, neither name reused
  grep -rq 'FIRST'  "$D"
  grep -rq 'SECOND' "$D"
}

@test "G4: MUTATION — a plain overwrite loses the prior run with no error" {
  # The pre-2026-09-09 behaviour, as a control: it exits 0 and says nothing, which is exactly why
  # the loss went unnoticed for two hours.
  local out="$D/mut.tsv"
  printf 'PRIOR\n' > "$out"
  run bash -c "cp /dev/null '$out'"
  [ "$status" -eq 0 ]
  ! grep -q 'PRIOR' "$out" || false
  [ -z "$output" ]
}
