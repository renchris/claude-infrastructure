#!/usr/bin/env bats
# MARGINAL LOAD PER ACTIVE SESSION — the denominator, and the control that must be able to fail.
# Backlog 193ae8ddce72; DoD docs/research/gc-cpu-vs-session-ceiling-2026-08-18.md §5.
#
# WHAT IS UNDER TEST, and why each half alone is worthless:
#
#   1. THE ESTIMATOR IDENTIFIES A MARGINAL. Cases 01-03 fit a series whose beta is KNOWN by
#      construction and assert the interval brackets it. Ground truth is the whole point: the four
#      incumbent values (0.172 / 0.566 / 1.89 / 2.5-5) were each produced by arithmetic that is
#      correct on its own terms, so "the code computes what it says" proves nothing about whether
#      the quantity is the marginal. Only a fixture with a planted answer can separate those.
#
#   2. THE CONTROL CAN FAIL. Case 10 replays the shape that killed the wave's "64% is our own
#      automation" headline — load sweeping a 2.3x range while the census sits flat at 19-20 — and
#      asserts BLIND with NO figure emitted in either render. A control whose failing branch is
#      never executed is decoration, and this suite exists mainly to keep that branch live.
#
# THE FIXTURES CARRY THE BOX'S OWN PARAMETERS, not convenient ones: non-session load wanders with
# sd ~ 8 (the measured 11.21-36.07 spread at a CONSTANT N=15-16), and the census visits the 4-16 the
# fleet actually runs at. A fixture easier than the subject certifies an estimator that cannot
# survive the series it was built for.
#
# HERMETICITY: HOME, the series path and every probe are fixtured under BATS_TEST_TMPDIR, and the
# two censuses are stubbed through CC_SP_*_OVERRIDE rather than by reading the machine. Nothing here
# consults the mood of the box running the suite, so it is deterministic on the Linux CI arm as well
# as on the macOS target — which matters because the subject's probes are per-platform and an
# untestable term is one that rots. No fixture carries an absolute wall-clock stamp: every series is
# generated from a fixed synthetic epoch, so this suite cannot age into red the way
# tests/cc-relogin-status.bats did on 2026-07-27.
#
# RED-PROOF (measured, re-runnable — `git stash push scripts/session-load-marginal.sh`, run,
# `git stash pop`): 21 of 22 cases fail against pristine trunk, where the subject does not exist.
#
# THE EXCEPTION IS RECORDED RATHER THAN SMOOTHED OVER, because it is the one case here that is not
# about the subject at all. Case 05 survives the subject's deletion, and correctly: it refits the
# fixture the way 0.172 and 0.566 were produced and asserts that THAT estimator cannot separate the
# incumbents. Its claim is about the level family and the data, so no implementation of this script
# could make it pass or fail. It is kept because it is the load-bearing diagnosis — without it the
# suite proves the new estimator works but never says why the old numbers disagreed — and it is
# flagged here so nobody counts it as coverage of the subject.
#
# A new file red-proofs trivially, so the cases that matter carry a SECOND, non-degenerate
# assertion: 04 changes the planted truth and requires the answer to follow (a hardcoded constant
# passes 03 and fails 04), 11/12/24 assert the ABSENCE of a figure rather than the presence of a
# verdict string, and 14 moves a threshold through its seam and requires the verdict to move with
# it. An assertion satisfiable by a DELETED subject is the leak the verdict-shaped cases would
# otherwise carry.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/scripts/session-load-marginal.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CC_MLOAD_SERIES="$BATS_TEST_TMPDIR/series.jsonl"
  # Every threshold pinned explicitly: a suite that inherits the subject's defaults stops testing
  # the moment a default is retuned, and silently.
  export CC_MLOAD_DT_MIN=30 CC_MLOAD_DT_MAX=300 CC_MLOAD_KMAX=2
  export CC_MLOAD_MIN_TRANS=5 CC_MLOAD_MIN_BASELINES=3
  export CC_MLOAD_CTRL_LOAD_SD=1.0 CC_MLOAD_CTRL_CENSUS_SD=0.30
  export CC_MLOAD_TARGET_HALFW=0.20
}

# ── fixture generators ────────────────────────────────────────────────────────────────────────────

# A series with a PLANTED marginal. beta is passed in; the non-session wander is the box's own.
mk_known() { # <beta> <rows> <outfile>
  awk -v BETA="$1" -v N="$2" 'BEGIN{ t=1000; l=22; base=22; c=9
    for(i=0;i<N;i++){
      dc = 0
      if      ((i*13)%7 == 0) dc =  1
      else if ((i*13)%7 == 3) dc = -1
      c += dc; if (c < 4) { c = 4; dc = 0 } ; if (c > 16) { c = 16; dc = 0 }
      nb = 22 + 9.0*sin(i/23.0) + 5.0*sin(i/7.3) + ((i*5)%17)*0.35 - 2.8
      l += (nb - base) + dc*BETA; base = nb
      if (l < 0.5) l = 0.5
      t += 60
      printf "{\"t\":%d,\"load1\":%.3f,\"ncpu\":10,\"active\":%d,\"trees\":%d}\n", t, l, c, c+6
    }}' > "$3"
}

# The dead headline's shape: load sweeps a 2.3x range, the census sits at 19-20.
mk_flat_census() { # <outfile>
  awk 'BEGIN{ t=1000
    for(i=0;i<60;i++){
      l = 16 + 10*sin(i/6.0) + (i%5)*0.7
      c = 19 + (i%13==0 ? 1 : 0)
      t += 60
      printf "{\"t\":%d,\"load1\":%.3f,\"ncpu\":10,\"active\":%d,\"trees\":%d}\n", t, l, c, c
    }}' > "$1"
}

json_field() { # <json> <key> → value
  printf '%s' "$1" | sed -n 's/.*"'"$2"'":\([^,}]*\).*/\1/p'
}

# ══ 1. THE ESTIMATOR IDENTIFIES A MARGINAL ════════════════════════════════════════════════════════

@test "01 a series with a planted marginal reads MEASURED" {
  mk_known 1.0 400 "$CC_MLOAD_SERIES"
  run "$SUT" analyze
  [ "$status" -eq 0 ]
  [[ "$output" == MEASURED* ]]
}

@test "02 the fit reports drift separately from the marginal" {
  # The arm 1.89 had no way to subtract. If alpha is absent the estimator has silently become the
  # aggregate-over-N it was built to replace.
  mk_known 1.0 400 "$CC_MLOAD_SERIES"
  run "$SUT" analyze
  [ "$status" -eq 0 ]
  [[ "$output" == *"drift"* ]] || false
  [[ "$output" == *"alpha ="* ]]
}

@test "03 the 95 percent interval brackets the planted beta" {
  mk_known 1.0 400 "$CC_MLOAD_SERIES"
  run "$SUT" analyze --json
  [ "$status" -eq 0 ]
  local lo hi b
  lo="$(json_field "$output" ci95_lo)"; hi="$(json_field "$output" ci95_hi)"
  b="$(json_field "$output" marginal_load_per_session)"
  # Brackets truth AND the point estimate is close to it — an interval alone is satisfiable by an
  # estimator that returns a useless [-inf, inf].
  run awk -v lo="$lo" -v hi="$hi" -v b="$b" 'BEGIN{ exit !(lo <= 1.0 && hi >= 1.0 && b > 0.7 && b < 1.3) }'
  [ "$status" -eq 0 ]
}

@test "04 a different planted beta moves the estimate with it" {
  # The strongest cheap control against a constant: change the truth, the answer must follow. A
  # hardcoded 1.0 passes case 03 and fails here.
  mk_known 2.5 400 "$CC_MLOAD_SERIES"
  run "$SUT" analyze --json
  local b
  b="$(json_field "$output" marginal_load_per_session)"
  run awk -v b="$b" 'BEGIN{ exit !(b > 2.0 && b < 3.0) }'
  [ "$status" -eq 0 ]
}

@test "05 the level-family fit cannot separate the incumbents on the same series" {
  # THE DIAGNOSIS OF THE 30x SPREAD, made executable. Refit the planted series the way 0.172 and
  # 0.566 were produced — OLS over LEVELS — and show its own 95% interval spans them all. The
  # incumbents do not disagree because the box changed; they are draws from an estimator whose
  # interval is several load points wide, and none of them carried one.
  mk_known 1.0 400 "$CC_MLOAD_SERIES"
  run awk -F'[:,]' '{ for(i=1;i<=NF;i++){ if($i ~ /"load1"/) l=$(i+1); if($i ~ /"active"/) c=$(i+1) }
        n++; sl+=l; sc+=c; L[n]=l; C[n]=c }
      END{ ml=sl/n; mc=sc/n
        for(i=1;i<=n;i++){ dl=L[i]-ml; dc=C[i]-mc; sxx+=dc*dc; syy+=dl*dl; sxy+=dc*dl }
        b=sxy/sxx; r2=(sxy*sxy)/(sxx*syy)
        for(i=1;i<=n;i++){ e=(L[i]-ml)-b*(C[i]-mc); rss+=e*e }
        se=sqrt((rss/(n-2))/sxx); lo=b-1.96*se; hi=b+1.96*se
        # negligible explained variance AND an interval that contains 0.172 and 1.89 alike
        exit !(r2 < 0.05 && lo <= 0.172 && hi >= 1.89) }' "$CC_MLOAD_SERIES"
  [ "$status" -eq 0 ]
}

@test "06 the first-difference fit does separate at least one incumbent" {
  # The converse of 05 on the same data: differencing buys real discrimination, or the whole
  # re-derivation is pointless.
  mk_known 1.0 400 "$CC_MLOAD_SERIES"
  run "$SUT" analyze
  [ "$status" -eq 0 ]
  [[ "$output" == *"excludes"* ]] || false
  [[ "$output" != *"excludes    none"* ]]
}

# ══ 2. THE CONTROL THAT MUST BE ABLE TO FAIL ══════════════════════════════════════════════════════

@test "10 a census flat under a moving load is BLIND" {
  mk_flat_census "$CC_MLOAD_SERIES"
  run "$SUT" analyze
  [ "$status" -eq 2 ]
  [[ "$output" == BLIND* ]] || false
  [[ "$output" == *"census-flat"* ]]
}

@test "11 BLIND prints no marginal in the text render" {
  # Asserting an ABSENCE. The DoD's rule is that no attribution figure may be quoted until a sampler
  # clears this control, so the figure must not appear wide, hedged or greyed out — a number on the
  # page is quotable no matter what qualifies it.
  mk_flat_census "$CC_MLOAD_SERIES"
  run "$SUT" analyze
  [[ "$output" == *SUPPRESSED* ]] || false
  [[ "$output" != *"beta ="* ]] || false
  [[ "$output" != *"95% CI"* ]]
}

@test "12 BLIND emits a null marginal in the json render" {
  mk_flat_census "$CC_MLOAD_SERIES"
  run "$SUT" analyze --json
  [[ "$output" == *'"marginal_load_per_session":null'* ]] || false
  [[ "$output" != *'"ci95_lo"'* ]]
}

@test "13 a quiet box is not BLIND — the control arms only when load moves" {
  # C1 must not fire on an idle series. A control that trips whenever nothing happens carries no
  # information, and it would mark every quiet night as instrument failure.
  awk 'BEGIN{ t=1000; for(i=0;i<40;i++){ t+=60
      printf "{\"t\":%d,\"load1\":2.000,\"ncpu\":10,\"active\":4,\"trees\":10}\n", t }}' \
    > "$CC_MLOAD_SERIES"
  run "$SUT" analyze
  [ "$status" -eq 1 ]
  [[ "$output" == INCONCLUSIVE* ]] || false
  [[ "$output" != *SUPPRESSED* ]]
}

@test "14 the C1 census-sd floor is a seam, not a literal" {
  # Raising the floor above the fixture's census sd must convert a MEASURED series into BLIND. This
  # proves the threshold in the verdict is the one in the environment, so tuning never needs a code
  # edit — and it proves C1 is evaluated at all on a series that otherwise passes.
  mk_known 1.0 400 "$CC_MLOAD_SERIES"
  run "$SUT" analyze
  [ "$status" -eq 0 ]
  CC_MLOAD_CTRL_CENSUS_SD=99 run "$SUT" analyze
  [ "$status" -eq 2 ]
  [[ "$output" == BLIND* ]]
}

# ══ 3. THE SERIES CONTRACT — what may and may not become a data point ═════════════════════════════

@test "20 too few transitions is INCONCLUSIVE, never MEASURED" {
  awk 'BEGIN{ t=1000; l=20; c=8
    for(i=0;i<20;i++){ dc=(i==5||i==11)?1:0; c+=dc; l+=dc*1.0+((i%3)-1)*0.4; t+=60
      printf "{\"t\":%d,\"load1\":%.3f,\"ncpu\":10,\"active\":%d,\"trees\":%d}\n", t,l,c,c }}' \
    > "$CC_MLOAD_SERIES"
  run "$SUT" analyze
  [ "$status" -eq 1 ]
  [[ "$output" == *"too few transitions"* ]] || false
}

@test "21 an inconclusive run states the n that would end it" {
  # An INCONCLUSIVE that does not say what would resolve it is a shrug, and a shrug is how a
  # measurement stays unmade for another wave.
  awk 'BEGIN{ t=1000; l=20; c=8
    for(i=0;i<20;i++){ dc=(i==5||i==11)?1:0; c+=dc; l+=dc*1.0+((i%3)-1)*0.4; t+=60
      printf "{\"t\":%d,\"load1\":%.3f,\"ncpu\":10,\"active\":%d,\"trees\":%d}\n", t,l,c,c }}' \
    > "$CC_MLOAD_SERIES"
  run "$SUT" analyze
  [[ "$output" == *"to decide"* ]] || false
}

@test "22 samples separated by a gap are not an interval" {
  # Differencing across a two-hour hole attributes two hours of drift to whatever the census did,
  # which is the 1.89 defect arriving through the back door.
  awk 'BEGIN{ t=1000; c=8; for(i=0;i<20;i++){ t+=7200; c+=(i%2);
      printf "{\"t\":%d,\"load1\":%.3f,\"ncpu\":10,\"active\":%d,\"trees\":%d}\n", t, 20+i, c, c }}' \
    > "$CC_MLOAD_SERIES"
  run "$SUT" analyze
  [ "$status" -eq 3 ]
  [[ "$output" == NO-DATA* ]]
}

@test "23 an unreadable census is dropped, never imputed as no-transition" {
  # A null row straddles two intervals. Imputing it as "unchanged" manufactures a drift observation
  # out of an absent measurement — the conflation NO-DATA exists to prevent.
  mk_known 1.0 400 "$BATS_TEST_TMPDIR/base.jsonl"
  awk 'NR%9==3 { sub(/"active":[0-9]+/, "\"active\":null"); sub(/"trees":[0-9]+/, "\"trees\":null") } { print }' \
    "$BATS_TEST_TMPDIR/base.jsonl" > "$CC_MLOAD_SERIES"
  run "$SUT" analyze --json
  [ "$status" -eq 0 ]
  local b
  b="$(json_field "$output" marginal_load_per_session)"
  run awk -v b="$b" 'BEGIN{ exit !(b > 0.7 && b < 1.3) }'
  [ "$status" -eq 0 ]
}

@test "24 a nine-at-once arrival is excluded from the fit" {
  # KMAX is why. The cited 1.89 came from nine sessions landing together, a regime whose per-session
  # cost need not equal a single arrival's; folding it in would re-import the number being replaced.
  mk_known 1.0 400 "$CC_MLOAD_SERIES"
  run "$SUT" analyze --json
  [ "$status" -eq 0 ]
  local n_all
  n_all="$(json_field "$output" n_transitions)"
  [ "$n_all" -gt 0 ]
  # KMAX=0 excludes every transition, so nothing is fitted — and an unfitted run must print no
  # figure, exactly as BLIND does. A degenerate 0.0000 here would be quotable.
  CC_MLOAD_KMAX=0 run "$SUT" analyze --json
  [[ "$output" == *'"marginal_load_per_session":null'* ]] || false
  [[ "$output" == *'"n_transitions":0'* ]]
}

@test "25 a missing series is NO-DATA, not a zero measurement" {
  export CC_MLOAD_SERIES="$BATS_TEST_TMPDIR/absent.jsonl"
  run "$SUT" analyze
  [ "$status" -eq 3 ]
  [[ "$output" == NO-DATA* ]]
}

# ══ 4. THE RECORDER ═══════════════════════════════════════════════════════════════════════════════

@test "30 sample appends a well-formed row from stubbed probes" {
  CC_MLOAD_LOAD1_OVERRIDE=17.25 CC_MLOAD_NCPU_OVERRIDE=10 \
    CC_SP_ACTIVE_OVERRIDE=7 CC_SP_TREES_OVERRIDE=14 \
    run "$SUT" sample
  [ "$status" -eq 0 ]
  run cat "$CC_MLOAD_SERIES"
  [[ "$output" == *'"load1":17.25'* ]] || false
  [[ "$output" == *'"active":7'* ]] || false
  [[ "$output" == *'"trees":14'* ]]
}

@test "31 an unreadable census is recorded as null, never as zero" {
  # THE POSITIVE CONTROL ON THE DENOMINATOR. A dead probe writing 0 reads back downstream as an
  # empty fleet — infinite headroom — and every transition against it is fabricated. The library's
  # own header found this bug on its own census; the recorder must not reintroduce it one layer up.
  CC_MLOAD_LOAD1_OVERRIDE=17.25 CC_MLOAD_NCPU_OVERRIDE=10 \
    CC_MLOAD_PRESENCE_LIB="$BATS_TEST_TMPDIR/no-such-lib.sh" \
    run "$SUT" sample
  [ "$status" -eq 0 ]
  run cat "$CC_MLOAD_SERIES"
  [[ "$output" == *'"active":null'* ]] || false
  [[ "$output" != *'"active":0'* ]]
}

@test "32 an unreadable load is NO-DATA and writes no row" {
  # A row is a claim about the box. If the quantity being attributed could not be read, the honest
  # output is no row at all — a row with a guessed load is a data point that never happened.
  CC_MLOAD_SYSCTL="$BATS_TEST_TMPDIR/no-such-sysctl" \
    CC_MLOAD_LOAD1_OVERRIDE="" \
    run env -u CC_MLOAD_LOAD1_OVERRIDE PATH="$BATS_TEST_TMPDIR/emptybin" "$SUT" sample
  # On a box with a readable /proc/loadavg the probe legitimately succeeds; accept either, but a
  # failure must never leave a malformed row behind.
  if [ "$status" -eq 3 ]; then
    [ ! -s "$CC_MLOAD_SERIES" ]
  else
    run cat "$CC_MLOAD_SERIES"
    [[ "$output" == *'"load1":'* ]]
  fi
}

@test "33 the recorder and the analyzer agree on the series shape" {
  # An end-to-end round trip: rows the recorder actually writes must be parseable by the analyzer.
  # Two components sharing a format by assertion rather than by contract is how a store silently
  # becomes unreadable.
  local i=0
  while [ "$i" -lt 12 ]; do
    CC_MLOAD_LOAD1_OVERRIDE="$((10 + i)).50" CC_MLOAD_NCPU_OVERRIDE=10 \
      CC_SP_ACTIVE_OVERRIDE="$((5 + i % 3))" CC_SP_TREES_OVERRIDE=14 \
      "$SUT" sample
    i=$((i + 1))
  done
  run "$SUT" analyze --json
  # The rows all carry the same timestamp (no clock advance inside one test), so every interval is
  # inadmissible and the verdict is NO-DATA — the point here is that the PARSE succeeded: a shape
  # mismatch reports "census never readable", which is a different NO-DATA and is the failure.
  [[ "$output" != *"census never readable"* ]]
}

# ══ 5. THE SELFTEST IS PART OF THE SUBJECT ════════════════════════════════════════════════════════

@test "40 the shipped selftest passes" {
  run "$SUT" selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"all cases pass"* ]]
}
