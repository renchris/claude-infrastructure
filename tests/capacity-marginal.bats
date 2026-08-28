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
  run grep -noE 'ps -[aew]+o [a-z=,]+' "$REPO/scripts/capacity-marginal.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"comm="* ]] || false
  [[ "$output" != *"args="* ]]
}

@test "every live ps read is width-unlimited — truncation is the one defect the controls cannot see" {
  # macOS ps renders a row only as wide as the terminal and falls back to 79 columns when no fd is a
  # tty, which is the case inside $(...). This file's columns cost ~17 characters before comm, and
  # the launcher image on the box is 81 characters
  # (/Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe), so the row
  # is ~98 and the tail is cut — defeating CC_MARG_EXEC_RE's END-ANCHORED `claude\.exe$` alternative.
  #
  # WHY THIS GETS ITS OWN TEST RATHER THAN A COMMENT. Truncation moves processes out of `claude_run`
  # without touching `total_run`. C1, C2 and C3 are all computed on `total_run`; the coefficient is
  # fit on `claude_run`. So this is the one defect in the instrument that passes every control and
  # still lands inside `VERDICT: MARGINAL` — a wrong number wearing a certificate, which is the
  # exact artifact the whole item exists to prevent. Sibling measurements, both on this box:
  # compressor-sentinel.sh:465 (16-char column truncation, 2026-08-11) and cc-reaper:2396 ("it read
  # 0 matches where the per-pid form read 6").
  # PER-INVOCATION, NOT PER-LINE. Written per-line first, this test PASSED against a deliberate
  # revert of the primary read to `-axo` — because the Darwin read and its Linux fallback share one
  # source line, so the fallback's own `ww` satisfied a substring check for the pair. A control that
  # green-lights the mutation it was written to catch is worse than no control, so the scan strips
  # comments (leaving only executable text, which excludes the prose citing the narrower
  # `ps -o comm=` form and the per-thread `ps -axM` this file names but never calls) and then
  # extracts each `-o`-bearing invocation ON ITS OWN, so every read is judged alone.
  run bash -c "sed 's/#.*//' '$REPO/scripts/capacity-marginal.sh' | grep -oE 'ps -[a-z]+o '"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -ge 2 ]
  local inv
  while IFS= read -r inv; do
    [ -n "$inv" ] || continue
    [[ "$inv" == *ww* ]] || { echo "width-limited ps read: '$inv'"; return 1; }
  done <<< "$output"
}

@test "a bad interval is a usage error, not a busy loop" {
  run bash "$M" sample --interval-s 0 --window-s 1 --out "$D/x.tsv"
  [ "$status" -eq 2 ]
}

# ── THE PUBLISHED UNCERTAINTY ───────────────────────────────────────────────────────────────────

@test "the s.e. is inflated for load1 autocorrelation, and says so" {
  # C2 refuses to READ a correlation off n rather than n_eff. An s.e. computed off n would concede
  # at the last step exactly what C2 refuses at the first — and the s.e. is the half of this number
  # a reader uses to decide whether it separates from the four values it replaces. Same planted
  # series at two spacings: 60 s (n_eff == n, factor 1, no note) and 15 s (n_eff == n/4, so the
  # s.e. must roughly double and the note must appear).
  local sp f
  for sp in 60 15; do
    f="$D/vif-$sp.tsv"; hdr "$f"
    local i ts=2000000 act amb cl tot load
    for i in $(seq 0 79); do
      act=$(( 2 + i % 6 ))
      amb="$(awk -v i="$i" 'BEGIN { printf "%.3f", 9 + 6 * ((i * 7) % 11) / 10 }')"
      cl="$(awk -v a="$act" -v i="$i" 'BEGIN { printf "%.3f", 0.25 * a + 0.05 * ((i * 3) % 7) / 7 }')"
      tot="$(awk -v a="$amb" -v c="$cl" 'BEGIN { printf "%.3f", a + c }')"
      load="$(awk -v t="$tot" 'BEGIN { printf "%.3f", 1.30 * t }')"
      row "$f" "$ts" "$load" "$tot" "$cl" "$act"
      ts=$(( ts + sp ))
    done
  done
  # 60 s: independent, so no inflation and no note.
  run bash "$M" analyze --in "$D/vif-60.tsv" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.se_autocorr_factor > 0.99 and .se_autocorr_factor < 1.01' >/dev/null
  local se60; se60="$(printf '%s' "$output" | jq -r '.se')"
  # 15 s: C2 correctly refuses the window (n_eff 20.75 is barely decidable), but the s.e. arithmetic
  # is what is under test here, so read it from the same JSON the refusal emits.
  run bash "$M" analyze --in "$D/vif-15.tsv" --json
  printf '%s' "$output" | jq -e '.n_eff < .n' >/dev/null
  run bash "$M" analyze --in "$D/vif-60.tsv"
  [[ "$output" != *"inflated x"* ]] || false
  # And the note is emitted whenever the factor is real: shrink tau so n_eff < n on the 60 s file.
  run env CC_MARG_TAU=240 CC_MARG_MIN_N=5 bash "$M" analyze --in "$D/vif-60.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"inflated x"* ]] || false
  local se_inf; se_inf="$(printf '%s\n' "$output" | awk -F'[()]' '/VERDICT: MARGINAL/ { print $2 }' | awk '{print $2}')"
  run awk -v a="$se60" -v b="$se_inf" 'BEGIN { exit !(b > a * 1.5) }'
  [ "$status" -eq 0 ]
}

# ── THE DRIVER ──────────────────────────────────────────────────────────────────────────────────

@test "run STOPS EARLY the moment the controls pass, instead of burning the whole window" {
  # The scarce input in this measurement is an operator hour on a 10-core Darwin box. A driver that
  # samples its full --total-s after the answer already exists spends that hour for nothing.
  # CC_MARG_PS_OVERRIDE + a pre-seeded file make the census deterministic and the window instant.
  local f="$D/run-pass.tsv"; hdr "$f"
  local i ts act amb cl tot load
  ts="$(( $(date +%s) - 4000 ))"
  for i in $(seq 0 39); do
    act=$(( 2 + i % 6 ))
    amb="$(awk -v i="$i" 'BEGIN { printf "%.3f", 9 + 6 * ((i * 7) % 11) / 10 }')"
    cl="$(awk -v a="$act" 'BEGIN { printf "%.3f", 0.25 * a }')"
    tot="$(awk -v a="$amb" -v c="$cl" 'BEGIN { printf "%.3f", a + c }')"
    load="$(awk -v t="$tot" 'BEGIN { printf "%.3f", 1.30 * t }')"
    row "$f" "$ts" "$load" "$tot" "$cl" "$act"; ts=$(( ts + 60 ))
  done
  # --total-s 60 with --chunk-s/--interval-s 1: without early exit this would sample for a minute.
  local t0 t1
  t0="$(date +%s)"
  run bash "$M" run --total-s 60 --chunk-s 1 --interval-s 1 --out "$f" --append
  t1="$(date +%s)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: MARGINAL"* ]] || false
  [ "$(( t1 - t0 ))" -lt 30 ]
}

@test "run REFUSES to silently extend a window left over from another day" {
  # `sample` appends by design — that is what "extend the window" means. But a file from a previous
  # run extends `span` across the gap, `n_eff` grows with it, and C2 becomes decidable on evidence
  # that is half stale. The operator must say --append, which is the honest form of re-runnable.
  local f="$D/stale.tsv"; hdr "$f"; row "$f" 1000000 12.0 9 2 3
  run bash "$M" run --total-s 4 --chunk-s 2 --interval-s 1 --out "$f"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--append"* ]] || false
}

@test "run reports a STABLE refusal as the finding it is, and quotes no number" {
  # §6's second branch, which the two-command protocol left to the operator to notice across
  # separately-typed invocations: "the refusal repeats with the same term across several windows —
  # which would itself be the finding". Seeded flat (the shape that killed the wave's own headline)
  # so every extending window refuses on C2 for the same reason.
  local f="$D/run-flat.tsv"; hdr "$f"
  local i ts
  ts="$(( $(date +%s) - 4000 ))"
  for i in $(seq 0 39); do
    row "$f" "$ts" "$(awk -v i="$i" 'BEGIN { printf "%.2f", 12 + 14 * i / 39 }')" \
        "$(( 19 + i % 2 ))" "$(( 2 + i % 3 ))" "$(( 3 + i % 4 ))"
    ts=$(( ts + 60 ))
  done
  # WHICH control refuses is deliberately not asserted: the driver appends LIVE rows from whatever
  # box the suite runs on, so the term is a property of that box. What is under test is that the
  # driver carries a signature ACROSS separately-analyzed windows and names the repeat — the thing
  # a human re-typing two commands has to hold in their head, and the half of §6 the two-command
  # protocol never automated.
  run bash "$M" run --total-s 12 --chunk-s 1 --interval-s 1 --out "$f" --append
  [ "$status" -eq 1 ]
  [[ "$output" == *"window history: #1 "* ]] || false
  [[ "$output" == *"STABLE REFUSAL"* ]] || false
  [[ "$output" == *"thread-unit"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]]
}

@test "run rejects an incoherent window rather than looping on it" {
  run bash "$M" run --total-s 10 --chunk-s 60 --out "$D/y.tsv"
  [ "$status" -eq 2 ]
  run bash "$M" run --chunk-s 5 --interval-s 60 --out "$D/z.tsv"
  [ "$status" -eq 2 ]
}
