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

# ── `run`: THE §6 PROTOCOL, AND ITS STOPPING RULE ───────────────────────────────────────────────
# The DoD's remaining step was prose — "sample, analyze, and extend the window until the verdict
# stops being NO-ATTRIBUTION or the refusal repeats with the same term across several windows" —
# i.e. a loop with a stopping rule that a human was expected to run by hand for an hour or more.
# These rows pin the three ways it may terminate. CC_MARG_ROUND_HOOK replaces the sampling step so
# the subject is the RULE and not the operator's load average; the sampling it replaces is already
# pinned by the rows above.

# Writes the flat 19-20 census (the shape that killed the wave's headline) at 60 s spacing: C2
# refuses it on correlation, and n_eff clears the floor, so it is a DECIDABLE refusal.
_flat_round() { # <out> <round>
  local f="$1" r="$2" i ts base
  base=$(( 1000000 + (r - 1) * 3000 ))
  [ -s "$f" ] || printf '#ts\tload1\tunit\ttotal_run\tclaude_run\tactive\tresident\n' > "$f"
  for i in $(seq 0 39); do
    ts=$(( base + i * 60 ))
    printf '%s\t%s\tproc\t%s\t%s\t%s\t14\n' "$ts" \
      "$(awk -v i="$i" 'BEGIN { printf "%.2f", 12 + 14 * i / 39 }')" \
      "$(( 19 + i % 2 ))" "$(( 2 + i % 3 ))" "$(( 3 + i % 4 ))" >> "$f"
  done
}
export -f _flat_round

@test "run: SETTLED after --repeat-k identical DECIDABLE refusals, and says it is a finding" {
  run env CC_MARG_ROUND_HOOK="_flat_round" bash "$M" run \
    --out "$D/run-settled.tsv" --repeat-k 2 --max-s 600 --chunk-s 1 --interval-s 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"streak 1/2"* ]] || false
  [[ "$output" == *"streak 2/2"* ]] || false
  [[ "$output" == *"SETTLED"* ]] || false
  [[ "$output" == *"c2"* ]] || false
  # A settled refusal is the §7.3 finding, not a silent give-up — and it stays unquotable.
  [[ "$output" == *"thread-unit census is the next increment"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]]
}

# A window too SHORT to refute anything: near-perfect correlation at 5 s spacing, n_eff ~4 against a
# floor of 20. This is B3's own defect, and a streak that counted it would retire the instrument
# over the chunk size rather than over the box.
# CONTIGUOUS in time across rounds, deliberately: the span is what n_eff is computed from, so a
# fixture that jumped the clock between rounds would become decidable through the gap rather than
# through anything it sampled — the same "extra n is not extra information" error the control exists
# to refuse, committed by the test instead of the code.
_short_round() { # <out> <round>
  local f="$1" r="$2" i ts base
  base=$(( 1000000 + (r - 1) * 20 ))
  [ -s "$f" ] || printf '#ts\tload1\tunit\ttotal_run\tclaude_run\tactive\tresident\n' > "$f"
  for i in $(seq 0 3); do
    ts=$(( base + i * 5 ))
    printf '%s\t%s\tproc\t%s\t%s\t%s\t14\n' "$ts" "$(( 10 + i ))" "$(( 10 + i ))" "$(( 2 + i ))" "$(( 3 + i ))" >> "$f"
  done
}
export -f _short_round

@test "run: an UNDECIDABLE window never settles, and spends the budget instead — n_eff, not n" {
  # --max-s 0 buys exactly one round, which is what makes this deterministic: the assertion is that
  # a round failing every control for the trivial reason that it is SHORT resets the streak rather
  # than advancing it, so `run` can only ever exit UNDECIDED here, never SETTLED. A streak that
  # counted short windows would retire the instrument over the chunk size (B3's defect, by name).
  run env CC_MARG_ROUND_HOOK="_short_round" bash "$M" run \
    --out "$D/run-short.tsv" --repeat-k 2 --max-s 0 --chunk-s 1 --interval-s 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"window too short to refute"* ]] || false
  [[ "$output" == *"UNDECIDED"* ]] || false
  [[ "$output" != *"streak"* ]] || false
  [[ "$output" != *"SETTLED"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]]
}

# Round 1 refuses (flat census); round 2 REPLACES the file with a window carrying a planted
# coefficient over a moving ambient — the NEGATIVE CONTROL's shape. Replacing rather than appending
# is a fixture convenience, not a claim about `sample`, which always appends: the subject here is
# solely that `run` stops the instant the controls clear rather than spending its whole budget.
_pass_round() { # <out> <round>
  local f="$1" r="$2" i ts act cl tot load
  [ -s "$f" ] || printf '#ts\tload1\tunit\ttotal_run\tclaude_run\tactive\tresident\n' > "$f"
  if [ "$r" = 1 ]; then _flat_round "$f" 1; return 0; fi
  : > "$f"; printf '#ts\tload1\tunit\ttotal_run\tclaude_run\tactive\tresident\n' > "$f"
  for i in $(seq 0 59); do
    ts=$(( 2000000 + i * 60 ))
    act=$(( 2 + i % 9 ))
    cl="$(awk -v a="$act" 'BEGIN { printf "%.0f", 3 + 0.25 * a }')"
    tot="$(awk -v i="$i" -v c="$cl" 'BEGIN { printf "%.0f", c + 8 + 6 * (i % 7) }')"
    load="$(awk -v t="$tot" 'BEGIN { printf "%.2f", t * 1.3 }')"
    printf '%s\t%s\tproc\t%s\t%s\t%s\t14\n' "$ts" "$load" "$tot" "$cl" "$act" >> "$f"
  done
}
export -f _pass_round

@test "run: stops at the FIRST PASS and emits the coefficient" {
  run env CC_MARG_ROUND_HOOK="_pass_round" bash "$M" run \
    --out "$D/run-pass.tsv" --repeat-k 5 --max-s 600 --chunk-s 1 --interval-s 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"round 2 — PASS"* ]] || false
  [[ "$output" == *"VERDICT: MARGINAL"* ]] || false
  [[ "$output" == *"load units per ACTIVE session"* ]]
}

@test "run: rejects a chunk shorter than its own sampling interval" {
  run bash "$M" run --chunk-s 5 --interval-s 60 --out "$D/x.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--chunk-s"* ]]
}
