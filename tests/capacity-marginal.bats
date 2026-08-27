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

# ── THE CONVERGENCE PROTOCOL (`run`) ────────────────────────────────────────────────────────────
# DoD §6 is a LOOP, not a command: "sample, analyze, and extend the window until the verdict stops
# being NO-ATTRIBUTION *or* the refusal repeats with the same term across several windows — which
# would itself be the finding". Shipping that as prose makes the operator the interpreter, and its
# one judgment — which refusals count as repeats — is exactly the distinction the four published
# values died on. These rows pin that judgment.

# A series whose census tracks load's RANK perfectly but whose ratio drifts across tertiles: C1
# FAIL, C2/C3 PASS. An INFORMATIVE refusal — the kind a repeat of makes a finding.
seed_informative_refusal() {
  local f="$1" i ts=1000000 load cen
  hdr "$f"
  for i in $(seq 0 39); do
    load="$(awk -v i="$i" 'BEGIN { printf "%.2f", 10 + 20 * i / 39 }')"
    # census rises with load but sub-linearly, so load/census drifts hard across tertiles
    cen="$(awk -v i="$i" 'BEGIN { printf "%d", 10 + 3 * i / 39 }')"
    row "$f" "$ts" "$load" "$cen" "$(( 2 + i % 4 ))" "$(( 3 + i % 5 ))"
    ts=$(( ts + 60 ))
  done
}

@test "classify: all controls passing is 'pass' — the protocol is done" {
  run bash -c 'printf "VERDICT: MARGINAL 0.3\n" | bash "$0" classify 0' "$M"
  [ "$status" -eq 0 ]
  [[ "$output" == pass\|\|* ]] || false
}

@test "classify: an n_eff shortfall is EXTEND, never a refusal — 'uninformative, not refuting'" {
  # The load-bearing row. n_eff grows monotonically as the file grows, so a C2 failure worded
  # "uninformative, not refuting" means the window is YOUNG, not the instrument wrong. A driver
  # that counted it toward "the refusal repeated" would report "the process census is the wrong
  # instrument" from a window that was merely short — B3's defect, mechanised. Note C1 and C3 are
  # ALSO failing here, as they always do in a young window: the n_eff reading must still win.
  local t="$D/young.txt"
  cat > "$t" <<'EOF'
CAPACITY-MARGINAL  n=4  n_eff=1.1  span=6s  unit=proc  load1 0.22..0.24 (1.09x)
  C1 LEVEL      FAIL  load span 1.09x < 1.50x required
  C2 DYNAMICS   FAIL  corr 0.000 but n_eff 1.1 < 20 independent observations (span 6s / tau 60s) — uninformative, not refuting
  C3 IDENTIFY   FAIL  active spans 3..4 over 2 level(s) — need spread >= 2 across >= 3 levels
VERDICT: NO-ATTRIBUTION — a control failed; no coefficient is quotable from this window.
EOF
  run bash -c 'bash "$1" classify 1 < "$2"' _ "$M" "$t"
  [ "$status" -eq 0 ]
  [[ "$output" == extend\|n_eff\|* ]] || false
}

@test "classify: an unreadable ACTIVE census is 'sensor' and OUTRANKS the young-window reading" {
  # No amount of extending fixes a dead regressor, so this must not be reported as "extend" (which
  # would burn the whole deadline) nor as a control failure (which would blame the box for an
  # environment fault). Both wordings are present here; `sensor` has to win.
  local t="$D/blind.txt"
  cat > "$t" <<'EOF'
CAPACITY-MARGINAL  n=4  n_eff=1.1  span=6s  unit=proc  load1 0.22..0.24 (1.09x)
  C1 LEVEL      FAIL  load span 1.09x < 1.50x required
  C2 DYNAMICS   FAIL  corr 0.000 but n_eff 1.1 < 20 independent observations — uninformative, not refuting
  C3 IDENTIFY   FAIL  0 row(s) carry an ACTIVE count (4 unmeasurable)
VERDICT: NO-ATTRIBUTION — a control failed; no coefficient is quotable from this window.
EOF
  run bash -c 'bash "$1" classify 1 < "$2"' _ "$M" "$t"
  [ "$status" -eq 0 ]
  [[ "$output" == sensor\|* ]] || false
}

@test "classify: an informative failure is a refusal, signed with the terms that failed" {
  # The signature is what makes "the SAME term across several windows" checkable. Different terms
  # failing in different windows is a moving target, not a reproduced refusal.
  local t="$D/informative.txt"
  cat > "$t" <<'EOF'
CAPACITY-MARGINAL  n=40  n_eff=40.0  span=2340s  unit=proc  load1 10.00..30.00 (3.00x)
  C1 LEVEL      FAIL  tertile ratios 0.900 / 1.400 / 2.100 swing 2.33x > 1.35x
  C2 DYNAMICS   PASS  corr(load1, census) = 0.980 over n_eff 40.0
  C3 IDENTIFY   PASS  active spans 2..5 over 4 levels, 40 rows
VERDICT: NO-ATTRIBUTION — a control failed; no coefficient is quotable from this window.
EOF
  run bash -c 'bash "$1" classify 1 < "$2"' _ "$M" "$t"
  [ "$status" -eq 0 ]
  [[ "$output" == refuse\|C1\|* ]] || false
}

@test "classify: NO-DATA is EXTEND — a file still filling is not a verdict" {
  run bash -c 'printf "CAPACITY-MARGINAL: NO-DATA — 2 usable row(s)\n" | bash "$0" classify 3' "$M"
  [ "$status" -eq 0 ]
  [[ "$output" == extend\|nodata\|* ]] || false
}

@test "run PREFLIGHTS the ACTIVE sensor and refuses in the first second, not at hour four" {
  # Off-box (and on a box whose spawn-presence beat dir is absent) cc_sp_active is unreadable, so
  # C3 can never pass and the answer is written before the first sample. Refusing here is the
  # difference between a 4-hour run that reports the wrong conclusion and a one-second NO-DATA.
  # It must be NO-DATA (3), never NO-ATTRIBUTION (1): "could not measure the regressor" must not
  # read as "the census failed its control".
  run bash "$M" run --out "$D/pf.tsv" --chunk-s 1 --interval-s 1 --max-s 2
  [ "$status" -eq 3 ]
  [[ "$output" == *"ACTIVE census (cc_sp_active) is unreadable"* ]] || false
  [[ "$output" == *"needs the live fleet"* ]] || false
  [ ! -s "$D/pf.tsv" ]
}

@test "run CONVERGES: a series that passes all three controls stops the protocol at once" {
  # The planted coefficient from the NEGATIVE CONTROL, driven through the loop rather than through
  # `analyze` alone. Without this row a refusal-only suite would certify a loop that never stops.
  local f="$D/pass.tsv"; hdr "$f"
  local i ts=1000000 load act cl
  for i in $(seq 0 39); do
    act=$(( 2 + i % 6 ))
    load="$(awk -v i="$i" 'BEGIN { printf "%.2f", 12 + 16 * i / 39 }')"
    cl="$(awk -v a="$act" 'BEGIN { printf "%d", 0.25 * a + 1 }')"
    row "$f" "$ts" "$load" "$(awk -v l="$load" 'BEGIN { printf "%d", l / 1.3 }')" "$cl" "$act"
    ts=$(( ts + 60 ))
  done
  run env CC_MARG_RUN_NO_SAMPLE=1 bash "$M" run --force --out "$f" --chunk-s 1 --interval-s 1 --max-s 6
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: MARGINAL"* ]] || false
  [[ "$output" == *"PROTOCOL: CONVERGED"* ]] || false
}

@test "run STOPS on a repeated informative refusal — DoD §6's 'that would itself be the finding'" {
  local f="$D/stable.tsv"; seed_informative_refusal "$f"
  run env CC_MARG_RUN_NO_SAMPLE=1 bash "$M" run --force --out "$f" \
    --chunk-s 1 --interval-s 1 --max-s 30 --repeat-refusals 3
  [ "$status" -eq 1 ]
  [[ "$output" == *"PROTOCOL: STABLE REFUSAL"* ]] || false
  [[ "$output" == *"C1 failed identically on 3 consecutive informative windows"* ]] || false
  # and it must not leak the withheld fit as a conclusion
  [[ "$output" == *"Do NOT quote the withheld fit"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]]
}

@test "run does NOT stop early on repeated n_eff shortfalls — it runs to its deadline" {
  # The inverse of the row above, and the reason the two are not one test: a short window fails
  # every round with the SAME text, so a driver keying on repetition alone would call three young
  # windows a stable refusal and report the instrument wrong. This series is informative in every
  # other respect; only n_eff is short.
  local f="$D/young.tsv"; hdr "$f"
  local i ts=1000000 load
  for i in $(seq 0 5); do
    load="$(awk -v i="$i" 'BEGIN { printf "%.2f", 10 + 20 * i / 5 }')"
    row "$f" "$ts" "$load" "$(( 10 + i * 2 ))" "$(( 2 + i ))" "$(( 2 + i % 4 ))"
    ts=$(( ts + 5 ))
  done
  run env CC_MARG_RUN_NO_SAMPLE=1 bash "$M" run --force --out "$f" \
    --chunk-s 1 --interval-s 1 --max-s 4 --repeat-refusals 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"PROTOCOL: DEADLINE"* ]] || false
  [[ "$output" != *"STABLE REFUSAL"* ]]
}

@test "run rejects a chunk smaller than its own sampling interval" {
  run bash "$M" run --force --chunk-s 1 --interval-s 60 --max-s 2 --out "$D/y.tsv"
  [ "$status" -eq 2 ]
}
