#!/usr/bin/env bats
# capacity-marginal — the sampler that must REFUSE to state a marginal its own controls cannot
# support (backlog 193ae8ddce72; DoD docs/research/gc-cpu-vs-session-ceiling-2026-08-18.md §5).
#
# WHAT THIS SUITE IS FOR. The item this script answers exists because the repo published four
# values for marginal load per ACTIVE session spanning 30x, and every one of them came from an
# instrument that always answers. The deliverable is therefore NOT "a number" and not even "a
# script that computes a number" — it is a control that can FAIL, and a control is only known to be
# able to fail once something has watched it do so. So the first test here replays the exact census
# shape that killed this wave's own headline (flat at 19-20 across a 2.2x load range,
# corr = -0.05) and asserts the script refuses; the second plants a known coefficient and asserts
# it is recovered. A suite with only the second test would certify a rubber stamp.
#
# WHY FIXTURES AND NOT THE LIVE BOX. Every control arm is a property of a SERIES, so the subject is
# a file, not a machine. Testing this against the live box would make the suite pass or fail on how
# busy the operator is — the one input a gate corpus may never depend on.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  M="$REPO/scripts/capacity-marginal.sh"
  D="$BATS_TEST_TMPDIR"
  # Hermetic HOME: nothing here writes to it today, but `sample` resolves spawn-presence.sh, which
  # reads the operator's beat directory. A probe must never see the live fleet.
  export HOME="$D/home"; mkdir -p "$HOME/.claude"
  hdr() { printf '#ts\tload1\tunit\ttotal_run\tclaude_run\tactive\tresident\n' > "$1"; }
}

# One row: <file> <ts> <load1> <total_run> <claude_run> <active> [unit]
row() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t14\n' "$2" "$3" "${7:-proc}" "$4" "$5" "$6" >> "$1"
}

# ── THE CONTROL MUST BE ABLE TO FAIL ────────────────────────────────────────────────────────────

@test "POSITIVE CONTROL: the census shape that killed the wave's own headline is REFUSED" {
  # docs/research/gc-cpu-vs-session-ceiling-2026-08-18.md §2: "REFUTED as a number — the census
  # failed a correlation control it never ran: corr(load, R-procs) = -0.05, flat at 19-20 R procs
  # across a 2.3x load range." Replayed here at 60 s spacing so n_eff is NOT the reason it fails —
  # the correlation has to be what refuses, or this test proves the wrong thing.
  local f="$D/flat.tsv"; hdr "$f"
  local i ts=1000000 load
  for i in $(seq 0 39); do
    load="$(awk -v i="$i" 'BEGIN { printf "%.2f", 12 + 14 * i / 39 }')"
    row "$f" "$ts" "$load" "$(( 19 + i % 2 ))" "$(( 2 + i % 3 ))" "$(( 3 + i % 4 ))"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C2 DYNAMICS   FAIL"* ]] || false
  [[ "$output" == *"does not track the load it apportions"* ]] || false
  [[ "$output" == *"NO-ATTRIBUTION"* ]]
}

@test "a refused window emits NO quotable coefficient" {
  # The failure mode this whole file exists to stop is a number escaping a failed control and being
  # quoted six weeks later with its provenance gone. The withheld fit is printed in parentheses,
  # explicitly labelled withheld, and the string a reader greps for — "VERDICT: MARGINAL" — must
  # not appear at all.
  local f="$D/flat2.tsv"; hdr "$f"
  local i ts=1000000
  for i in $(seq 0 39); do
    row "$f" "$ts" "$(awk -v i="$i" 'BEGIN { printf "%.2f", 12 + 14 * i / 39 }')" 19 3 4
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" != *"VERDICT: MARGINAL"* ]] || false
  [[ "$output" == *"withheld"* ]]
}

@test "NEGATIVE CONTROL: a planted coefficient is recovered and all three controls PASS" {
  # Ambient (the 87.3% confounder B3 measured) moves on its own; Claude's attributed census carries
  # a planted 0.25 runnable procs per ACTIVE session; load1 = 1.30 x census. Expected marginal
  # 0.25 x 1.30 = 0.325 load units. If the estimator cannot recover a coefficient that IS there,
  # a refusal from it proves nothing.
  local f="$D/planted.tsv"; hdr "$f"
  local i ts=2000000 act amb cl tot load
  for i in $(seq 0 39); do
    act=$(( 2 + i % 6 ))
    amb="$(awk -v i="$i" 'BEGIN { printf "%.3f", 9 + 6 * ((i * 7) % 11) / 10 }')"
    cl="$(awk -v a="$act" 'BEGIN { printf "%.3f", 0.25 * a }')"
    tot="$(awk -v a="$amb" -v c="$cl" 'BEGIN { printf "%.3f", a + c }')"
    load="$(awk -v t="$tot" 'BEGIN { printf "%.3f", 1.30 * t }')"
    row "$f" "$ts" "$load" "$tot" "$cl" "$act"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"C1 LEVEL      PASS"* ]] || false
  [[ "$output" == *"C2 DYNAMICS   PASS"* ]] || false
  [[ "$output" == *"C3 IDENTIFY   PASS"* ]] || false
  # Recovered within 5% of the planted 0.325.
  local got; got="$(printf '%s\n' "$output" | awk '/VERDICT: MARGINAL/ { print $3 }')"
  run awk -v g="$got" 'BEGIN { exit !(g > 0.309 && g < 0.342) }'
  [ "$status" -eq 0 ]
}

# ── EACH CONTROL, FAILING FOR ITS OWN REASON ────────────────────────────────────────────────────

@test "C2 fails as UNINFORMATIVE (not refuting) when the window holds too few independent samples" {
  # B3's own defect, by name: three windows of 2.5-4 min against load1's 60 s time constant is
  # ~2.5 independent observations, so its negative correlation was undecided rather than refuting.
  # Here the correlation is near-perfect and the window is still refused — n_eff, never n.
  local f="$D/short.tsv"; hdr "$f"
  local i ts=3000000 tot
  for i in $(seq 0 39); do
    tot=$(( 10 + i ))
    row "$f" "$ts" "$(awk -v t="$tot" 'BEGIN { printf "%.2f", 1.3 * t }')" "$tot" "$(( 2 + i % 5 ))" "$(( 2 + i % 5 ))"
    ts=$(( ts + 5 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C2 DYNAMICS   FAIL"* ]] || false
  [[ "$output" == *"uninformative, not refuting"* ]]
}

@test "C2 names a CONSTANT census for what it is — the instrument, not the box" {
  local f="$D/const.tsv"; hdr "$f"
  local i ts=4000000
  for i in $(seq 0 39); do
    row "$f" "$ts" "$(awk -v i="$i" 'BEGIN { printf "%.2f", 10 + 15 * i / 39 }')" 20 4 "$(( 2 + i % 5 ))"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"census is CONSTANT"* ]]
}

@test "C3 fails when the ACTIVE count never moves — a slope needs a regressor" {
  # The 1.89 defect's smaller sibling: fitting a marginal across one level of the thing whose
  # marginal is being fitted.
  local f="$D/flatact.tsv"; hdr "$f"
  local i ts=5000000 tot
  for i in $(seq 0 39); do
    tot=$(( 10 + i % 12 ))
    row "$f" "$ts" "$(awk -v t="$tot" 'BEGIN { printf "%.2f", 1.3 * t }')" "$tot" 4 5
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C3 IDENTIFY   FAIL"* ]] || false
  [[ "$output" == *"1 level"* ]]
}

@test "C3 fails, and says how many rows were blind, when no row carries an ACTIVE count" {
  # cc_sp_active records `-` when unmeasurable rather than 0, so a dead sensor can never read as a
  # quiet box. The analyzer has to carry that distinction through instead of coercing it to zero.
  local f="$D/noact.tsv"; hdr "$f"
  local i ts=6000000 tot
  for i in $(seq 0 39); do
    tot=$(( 10 + i % 12 ))
    row "$f" "$ts" "$(awk -v t="$tot" 'BEGIN { printf "%.2f", 1.3 * t }')" "$tot" 4 -
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C3 IDENTIFY   FAIL"* ]] || false
  [[ "$output" == *"0 row(s) carry an ACTIVE count (40 unmeasurable)"* ]]
}

@test "C1 fails on a window that never moved — a ratio agreeing at one load has reproduced nothing" {
  local f="$D/quiet.tsv"; hdr "$f"
  local i ts=7000000
  for i in $(seq 0 39); do
    row "$f" "$ts" "10.0$(( i % 9 ))" "$(( 8 + i % 2 ))" "$(( 2 + i % 5 ))" "$(( 2 + i % 5 ))"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C1 LEVEL      FAIL"* ]] || false
  [[ "$output" == *"load span"* ]]
}

@test "C1 fails a ratio that drifts across the load range — the x1.553 single-point-fit defect" {
  # A8's x1.553 R-procs->load factor was fitted at ONE load and B3 reproduced none of it
  # (0.913 / 1.077 / 1.235). Here the census tracks load's RANK perfectly — C2 passes — while the
  # ratio drifts 2x across the tertiles, and C1 alone refuses.
  local f="$D/drift.tsv"; hdr "$f"
  local i ts=8000000 load tot
  for i in $(seq 0 39); do
    load="$(awk -v i="$i" 'BEGIN { printf "%.2f", 10 + 30 * i / 39 }')"
    tot="$(awk -v l="$load" 'BEGIN { printf "%.3f", l / (0.8 + l / 40) }')"
    row "$f" "$ts" "$load" "$tot" "$(( 2 + i % 5 ))" "$(( 2 + i % 5 ))"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C1 LEVEL      FAIL"* ]] || false
  [[ "$output" == *"C2 DYNAMICS   PASS"* ]] || false
  [[ "$output" == *"swing"* ]]
}

# ── DATA HYGIENE ────────────────────────────────────────────────────────────────────────────────

@test "mixed census units are NO-DATA, never pooled" {
  # Process-unit and thread-unit censuses have different ratios (1.30-1.55 vs 0.913). Pooling them
  # would produce a ratio that is neither, and C1 would then certify the average of two wrongs.
  local f="$D/mixed.tsv"; hdr "$f"
  local i ts=9000000 tot
  for i in $(seq 0 39); do
    tot=$(( 10 + i % 12 ))
    row "$f" "$ts" "$(awk -v t="$tot" 'BEGIN { printf "%.2f", 1.3 * t }')" "$tot" "$(( 2 + i % 5 ))" "$(( 2 + i % 5 ))" \
        "$( [ $(( i % 2 )) -eq 0 ] && echo proc || echo thread )"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 3 ]
  [[ "$output" == *"mix census units"* ]]
}

@test "an unreadable or near-empty input is NO-DATA (3), never a zero coefficient" {
  run bash "$M" analyze --in "$D/absent.tsv"
  [ "$status" -eq 3 ]
  [[ "$output" == *"NO-DATA"* ]] || false
  local f="$D/thin.tsv"; hdr "$f"; row "$f" 1 10 8 2 3
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 3 ]
  [[ "$output" == *"usable row"* ]]
}

@test "--json emits parseable JSON whose verdict matches the text verdict" {
  local f="$D/planted2.tsv"; hdr "$f"
  local i ts=2000000 act amb cl tot load
  for i in $(seq 0 39); do
    act=$(( 2 + i % 6 ))
    amb="$(awk -v i="$i" 'BEGIN { printf "%.3f", 9 + 6 * ((i * 7) % 11) / 10 }')"
    cl="$(awk -v a="$act" 'BEGIN { printf "%.3f", 0.25 * a }')"
    tot="$(awk -v a="$amb" -v c="$cl" 'BEGIN { printf "%.3f", a + c }')"
    load="$(awk -v t="$tot" 'BEGIN { printf "%.3f", 1.30 * t }')"
    row "$f" "$ts" "$load" "$tot" "$cl" "$act"; ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.verdict == "MARGINAL" and .c1_level and .c2_dynamics and .c3_identify' >/dev/null
}

# ── THE ATTRIBUTION ─────────────────────────────────────────────────────────────────────────────

@test "attribution walks ancestry: a session's jq/ugrep forks count as the session's load" {
  # B3 measured the forks a session spawns at ~3x claude.exe's own threads, so a census that
  # attributed only the launcher process would undercount Claude by two thirds. 200 is a session
  # (2 runnable descendants), 500 is an idle session with one uninterruptible child, and kitty +
  # mediaanalysisd are runnable but not ours.
  cat > "$D/ps.txt" <<'EOF'
  100     1 S    /sbin/launchd
  200   100 R    /Users/x/.claude-220/node_modules/.bin/claude
  201   200 R    jq
  202   200 S    bash
  203   201 R    ugrep
  300   100 R    /Applications/kitty.app/Contents/MacOS/kitty
  400   100 R    mediaanalysisd
  500   100 S    /Users/x/.claude-220/node_modules/.bin/claude
  501   500 D    node
EOF
  run env CC_MARG_PS_OVERRIDE="$D/ps.txt" bash -c '
    set -uo pipefail
    CC_MARG_EXEC_RE="\.claude-[0-9]+/node_modules/|claude\.exe$"
    '"$(sed -n '/^census_row() {/,/^}/p' "$REPO/scripts/capacity-marginal.sh")"'
    census_row'
  [ "$status" -eq 0 ]
  # total runnable 6 (200,201,203,300,400,501) · Claude-owned 4 (200,201,203,501) · resident 2
  [ "$output" = "6 4 2" ]
}

@test "the RESIDENT census reads the executable path, never argv" {
  # DoD §5, verbatim: count "by executable path, never argv — argv reads 30-33 against a true
  # 15-16, because briefs mention the path". A future edit swapping comm= for args= would double
  # the denominator of every capacity claim and change no test but this one.
  run grep -noE 'ps -[ae]xo [a-z=,]+' "$REPO/scripts/capacity-marginal.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"comm="* ]] || false
  [[ "$output" != *"args="* ]]
}

@test "a bad interval is a usage error, not a busy loop" {
  run bash "$M" sample --interval-s 0 --window-s 1 --out "$D/x.tsv"
  [ "$status" -eq 2 ]
}

# ── THE RUN LOOP: ITS STOP RULE IS THE PART THAT COULD LIE ──────────────────────────────────────
#
# `run` exists because §6 of the adjudication doc is a loop, not two commands: sample, analyze,
# EXTEND, and stop on a PASS or on the same control refusing as the window grows. A loop whose only
# real windows are hours long would otherwise ship with a stop rule nobody has watched execute —
# so CC_MARG_RUN_APPEND stands in for the live sample (blocks separated by `--`, one per
# iteration) exactly as CC_MARG_PS_OVERRIDE stands in for `ps`. Every test below asserts an exit
# code AND, on every non-PASS path, that no coefficient escaped.

# 40 rows carrying a planted 0.25 runnable procs per ACTIVE session, load1 = 1.30 x census.
planted_rows() { # <ts0>
  local i ts="$1" act amb cl tot load
  for i in $(seq 0 39); do
    act=$(( 2 + i % 6 ))
    amb="$(awk -v i="$i" 'BEGIN { printf "%.3f", 9 + 6 * ((i * 7) % 11) / 10 }')"
    cl="$(awk -v a="$act" 'BEGIN { printf "%.3f", 0.25 * a }')"
    tot="$(awk -v a="$amb" -v c="$cl" 'BEGIN { printf "%.3f", a + c }')"
    load="$(awk -v t="$tot" 'BEGIN { printf "%.3f", 1.30 * t }')"
    printf '%s\t%s\tproc\t%s\t%s\t%s\t14\n' "$ts" "$load" "$tot" "$cl" "$act"
    ts=$(( ts + 60 ))
  done
}

# 40 rows of the census shape that killed this wave's own headline: flat at 19-20 while load moves.
flat_rows() { # <ts0>
  local i ts="$1" load
  for i in $(seq 0 39); do
    load="$(awk -v i="$i" 'BEGIN { printf "%.2f", 12 + 14 * i / 39 }')"
    printf '%s\t%s\tproc\t%s\t%s\t%s\t14\n' "$ts" "$load" "$(( 19 + i % 2 ))" "$(( 2 + i % 3 ))" "$(( 3 + i % 4 ))"
    ts=$(( ts + 60 ))
  done
}

@test "run STOPS on a PASS and hands over the next action, not another window" {
  local fix="$D/pass.blocks"; planted_rows 2000000 > "$fix"
  run env CC_MARG_RUN_APPEND="$fix" bash "$M" run --out "$D/r1.tsv" \
    --chunk-s 1 --interval-s 1 --max-s 30 --repeat-refusals 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: MARGINAL"* ]] || false
  [[ "$output" == *"RUN: PASS after 1 window"* ]] || false
  # The close-out step is named in the tool, so the operator is never handed a verdict plus a
  # question about what to do with it.
  [[ "$output" == *"cc-backlog done 193ae8ddce72"* ]] || false
  # And the verdict is durable — a run whose scrollback is gone is not a measurement.
  [ -s "$D/r1.tsv.verdict" ]
  grep -q 'VERDICT: MARGINAL' "$D/r1.tsv.verdict"
}

@test "run reports a STABLE REFUSAL as a FINDING once the same control fails across grown windows" {
  # The distinction the exit code carries: 1 is "the window ran out", 4 is "this census cannot
  # apportion this box" — which is what sends the next increment to the thread-unit parser (§7)
  # instead of buying another hour of the same instrument.
  local fix="$D/refuse.blocks"
  { flat_rows 1000000; printf -- '--\n'; flat_rows 1002400; printf -- '--\n'; flat_rows 1004800; } > "$fix"
  run env CC_MARG_RUN_APPEND="$fix" bash "$M" run --out "$D/r2.tsv" \
    --chunk-s 1 --interval-s 1 --max-s 30 --repeat-refusals 3
  [ "$status" -eq 4 ]
  [[ "$output" == *"STABLE REFUSAL"* ]] || false
  [[ "$output" == *"C2"* ]] || false
  [[ "$output" == *"thread-unit census"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]]
}

@test "a window that did NOT grow is not a second refusal — and a collector that stops is named" {
  # Re-reading one window three times is one observation of it, not three refusals; the streak may
  # not advance on it. Here block 1 refuses and the fixture then runs out, so a loop that counted
  # re-reads would report a STABLE REFUSAL (exit 4) off a single window. It must not.
  local fix="$D/once.blocks"; flat_rows 1000000 > "$fix"
  run env CC_MARG_RUN_APPEND="$fix" bash "$M" run --out "$D/r3.tsv" \
    --chunk-s 1 --interval-s 1 --max-s 30 --repeat-refusals 2
  [ "$status" -eq 3 ]
  [[ "$output" == *"window did NOT grow"* ]] || false
  [[ "$output" == *"sampler stopped producing rows"* ]] || false
  [[ "$output" != *"STABLE REFUSAL"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]]
}

@test "run gives up UNDECIDED when the clock runs out, and says so in different words than a finding" {
  local fix="$D/undec.blocks"; { flat_rows 1000000; printf -- '--\n'; flat_rows 1002400; } > "$fix"
  run env CC_MARG_RUN_APPEND="$fix" bash "$M" run --out "$D/r4.tsv" \
    --chunk-s 1 --interval-s 1 --max-s 0 --repeat-refusals 3
  [ "$status" -eq 1 ]
  [[ "$output" == *"RUN: UNDECIDED"* ]] || false
  [[ "$output" == *"keep extending it"* ]] || false
  [[ "$output" != *"STABLE REFUSAL"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]]
}

@test "run EXTENDS an existing sample file, never truncates it" {
  # An interrupted run has banked real minutes of a window that only becomes decidable by growing;
  # a re-run that reset the file would silently spend them again.
  local out="$D/r5.tsv"; hdr "$out"; flat_rows 1000000 >> "$out"
  local before; before="$(grep -c . "$out")"
  local fix="$D/ext.blocks"; flat_rows 1002400 > "$fix"
  run env CC_MARG_RUN_APPEND="$fix" bash "$M" run --out "$out" \
    --chunk-s 1 --interval-s 1 --max-s 0 --repeat-refusals 3
  [ "$status" -eq 1 ]
  local after; after="$(grep -c . "$out")"
  [ "$after" -eq $(( before + 40 )) ]
}

@test "one refusal is a window, not a pattern — --repeat-refusals 1 is a usage error" {
  run bash "$M" run --out "$D/r6.tsv" --repeat-refusals 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a pattern"* ]]
}

# ── A REFUSAL IS NOT AUTOMATICALLY A FINDING ────────────────────────────────────────────────────

@test "analyze classifies a short window as UNDECIDED, not as a refutation of the census" {
  # 5 s spacing against load1's 60 s time constant: the correlation is near-perfect and the window
  # is still refused, but the reason is the window. Reporting that as evidence about the instrument
  # would be the wave's own error run backwards.
  local f="$D/undec1.tsv"; hdr "$f"
  local i ts=3000000 tot
  for i in $(seq 0 39); do
    tot=$(( 10 + i ))
    row "$f" "$ts" "$(awk -v t="$tot" 'BEGIN { printf "%.2f", 1.3 * t }')" "$tot" "$(( 2 + i % 5 ))" "$(( 2 + i % 5 ))"
    ts=$(( ts + 5 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSAL: UNDECIDED"* ]] || false
  [[ "$output" == *"EXTEND the window"* ]]
}

@test "analyze classifies a census that does not track the load as REFUTING" {
  local f="$D/refut1.tsv"; hdr "$f"
  local i ts=1000000
  for i in $(seq 0 39); do
    row "$f" "$ts" "$(awk -v i="$i" 'BEGIN { printf "%.2f", 12 + 14 * i / 39 }')" "$(( 19 + i % 2 ))" "$(( 2 + i % 3 ))" "$(( 3 + i % 4 ))"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  # Both refuting arms fire on this shape: the census neither tracks the load (C2) nor holds a
  # stable ratio to it across the range (C1). Neither is fixable by sampling longer.
  [[ "$output" == *"REFUSAL: REFUTING (C1+C2)"* ]] || false
  [[ "$output" == *"more of the same will not help"* ]]
}

@test "a quiet night never accumulates into a finding — UNDECIDED refusals reset the streak" {
  # The defect the first LIVE smoke run of `run` produced: two 12-second windows, both refused with
  # "uninformative, not refuting" in their own text, reported as "the process-unit census cannot
  # apportion this box". Three grown-but-undecided windows here must reach the stalled-collector
  # exit (3), never STABLE REFUSAL (4).
  local fix="$D/quiet.blocks" b
  : > "$fix"
  for b in 0 1 2; do
    [ "$b" -eq 0 ] || printf -- '--\n' >> "$fix"
    local i ts=$(( 3000000 + b * 400 )) tot
    for i in $(seq 0 39); do
      tot=$(( 10 + i ))
      printf '%s\t%s\tproc\t%s\t%s\t%s\t14\n' "$ts" \
        "$(awk -v t="$tot" 'BEGIN { printf "%.2f", 1.3 * t }')" "$tot" "$(( 2 + i % 5 ))" "$(( 2 + i % 5 ))" >> "$fix"
      ts=$(( ts + 5 ))
    done
  done
  run env CC_MARG_RUN_APPEND="$fix" bash "$M" run --out "$D/r7.tsv" \
    --chunk-s 1 --interval-s 1 --max-s 60 --repeat-refusals 2
  [ "$status" -eq 3 ]
  [[ "$output" == *"UNDECIDED, not a refutation"* ]] || false
  [[ "$output" != *"STABLE REFUSAL"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]]
}

@test "C1 drift over a window with too few independent observations is UNDECIDED, not REFUTING" {
  # The same independence gate C2 applies to itself. 12 samples at 3 s spacing is ~1.6 independent
  # observations of a 60 s moving average: its three load tertiles are three slices of one reading,
  # so a ratio that "drifts" across them has refuted nothing. Seen live on a quiet box, where this
  # arm alone would have carried a stable-refusal streak.
  local f="$D/c1short.tsv"; hdr "$f"
  local i ts=6000000 tot load
  for i in $(seq 0 11); do
    tot=$(( 10 + i ))
    load="$(awk -v i="$i" 'BEGIN { printf "%.2f", (10 + i) * (0.9 + 0.09 * i) }')"
    row "$f" "$ts" "$load" "$tot" "$(( 2 + i % 4 ))" "$(( 2 + i % 4 ))"
    ts=$(( ts + 3 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C1 LEVEL      FAIL"* ]] || false
  [[ "$output" == *"drift not yet decidable"* ]] || false
  [[ "$output" == *"REFUSAL: UNDECIDED"* ]]
}
