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
  # `run` drives the real sampler end-to-end, which reaches spawn-presence and through it the
  # capacity gate — a gate that reads live load, memory and the session census and refuses above its
  # thresholds. Leaving it armed makes this suite red-by-desk (how busy the operator is) rather than
  # red-by-subject, which is the one input a gate corpus may never depend on.
  export CC_ADMIT_GATE=off
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

# ── `run`: the PROTOCOL, not the instrument ─────────────────────────────────────────────────────
#
# WHAT THESE PIN. `sample` and `analyze` are the instrument and the tests above cover them. `run` is
# the stopping rule from docs/research/marginal-load-per-active-session-2026-08-19.md §6 — "extend
# the window until the verdict stops being NO-ATTRIBUTION *or* the refusal repeats with the same
# term across several windows, which would itself be the finding" — and a stopping rule is a
# property of the LOOP, not of any window. So these drive `run` against a STUB sampler whose verdict
# per round is scripted, which is the only way to assert "stopped for reason X after N rounds"
# without an hour of wall clock or a live fleet. One test at the end drives the real path.
#
# The stub speaks `analyze`'s text contract, because that contract is what `run` parses: a
# `  C<n> <LABEL>  PASS|FAIL` line per control, and an exit code. If `analyze`'s rendering ever
# changes shape, these fail — which is correct, because `run`'s term-parsing would have broken too.

# plan(): one line per analyze round — `PASS`, `NODATA`, or a comma list of FAILING controls.
plan() { printf '%s\n' "$@" > "$D/plan"; }

stub() {
  cat > "$D/stub.sh" <<'EOF'
#!/bin/bash
S="$(dirname "$0")"
case "${1:-}" in
  sample)  printf 'x\n' >> "$S/sampled"; exit 0 ;;
  analyze)
    n=$(( $(cat "$S/round" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$S/round"
    p="$(sed -n "${n}p" "$S/plan")"; [ -n "$p" ] || p="$(tail -1 "$S/plan")"
    printf 'CAPACITY-MARGINAL  n=99  n_eff=60.0  span=3600s  unit=proc  load1 8.00..40.00 (5.00x)\n'
    [ "$p" = NODATA ] && { printf 'CAPACITY-MARGINAL: NO-DATA — rows mix census units; refusing to pool them\n'; exit 3; }
    [ "$p" = FEWROWS ] && { printf 'CAPACITY-MARGINAL: NO-DATA — 2 usable row(s)\n'; exit 3; }
    for c in C1 C2 C3; do
      case ",$p," in *",$c,"*) v=FAIL ;; *) v=PASS ;; esac
      case "$c" in C1) l=LEVEL ;; C2) l=DYNAMICS ;; *) l=IDENTIFY ;; esac
      printf '  %s %-9s %-4s  stub\n' "$c" "$l" "$v"
    done
    [ "$p" = PASS ] && {
      printf 'VERDICT: MARGINAL 0.412 load units per ACTIVE session  (+/- 0.061, 1 s.e.; ratio 1.100 load/runnable-proc)\n'
      exit 0; }
    printf 'VERDICT: NO-ATTRIBUTION — a control failed; no coefficient is quotable from this window.\n'
    printf '  (the fit that WOULD have been reported: 0.412 load units per ACTIVE session — withheld)\n'
    exit 1 ;;
esac
exit 2
EOF
  chmod +x "$D/stub.sh"
}

@test "run PREFLIGHT refuses a blind ACTIVE sensor in one second, spending NO window" {
  # The failure this exists to stop: an HOUR spent against a sensor that was never going to answer.
  # Off the fleet box cc_sp_active reads nothing, every row records `-`, and C3 fails at the end on
  # "0 row(s) carry an ACTIVE count" — a verdict available before the first sample. Asserting the
  # sampler was never invoked is the whole test; a preflight that merely printed a warning and then
  # sampled anyway would pass a message check and still burn the window.
  stub; plan PASS
  run env CC_MARG_ACTIVE_OVERRIDE="-" CC_MARG_SELF="$D/stub.sh" \
    bash "$M" run --out "$D/pre.tsv" --first-window-s 1 --interval-s 1 --budget-s 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"PREFLIGHT FAILED"* ]] || false
  [[ "$output" == *"cc_sp_active"* ]] || false
  [ ! -e "$D/sampled" ]
}

@test "run PREFLIGHT passes through when all three inputs answer" {
  # The other half: a preflight that refused everywhere would be indistinguishable from a broken
  # script, and nothing above would catch it.
  stub; plan PASS
  run env CC_MARG_ACTIVE_OVERRIDE=7 CC_MARG_SELF="$D/stub.sh" \
    bash "$M" run --out "$D/ok.tsv" --first-window-s 1 --interval-s 1 --budget-s 1
  [ "$status" -eq 0 ]
  [ -e "$D/sampled" ]
}

@test "run stops on the FIRST pass and hands over the citation sites" {
  # §6: "On a PASS, quote the coefficient with its standard error and its window, update
  # capacity-admit.sh and agent-teams-enforce.sh (both currently carry 2.5-5), and close the item."
  # That list is the reason the run ends anywhere but a scrollback buffer.
  stub; plan PASS
  run env CC_MARG_SELF="$D/stub.sh" bash "$M" run --no-preflight \
    --out "$D/r.tsv" --first-window-s 1 --interval-s 1 --budget-s 4
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$D/sampled")" -eq 1 ]
  [[ "$output" == *"VERDICT: MARGINAL"* ]] || false
  [[ "$output" == *"CITATION"* ]] || false
  [[ "$output" == *"capacity-admit.sh"* ]] || false
  [[ "$output" == *"agent-teams-enforce.sh"* ]] || false
  [[ "$output" == *"193ae8ddce72"* ]]
}

@test "run EXTENDS a refused window rather than reporting from it" {
  # The defect this forbids is a driver that samples once, sees NO-ATTRIBUTION and returns. The
  # window IS the remedy for C2 (n_eff) and often for C1/C3, so one round is never an answer.
  stub; plan C2 C2 PASS
  run env CC_MARG_SELF="$D/stub.sh" bash "$M" run --no-preflight \
    --out "$D/e.tsv" --first-window-s 1 --extend-s 1 --interval-s 1 --budget-s 9 --repeat-k 5
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$D/sampled")" -eq 3 ]
  [[ "$output" == *"VERDICT: MARGINAL"* ]]
}

@test "run calls a REPEATED refusal the finding, and names the term" {
  # §6's second exit: "or the refusal repeats with the same term across several windows — which
  # would itself be the finding". Exactly --repeat-k identical refusals, then stop; the term is
  # named because "we could not measure it" and "C3 never varied" are different results.
  stub; plan C3 C3 C3 PASS
  run env CC_MARG_SELF="$D/stub.sh" bash "$M" run --no-preflight \
    --out "$D/s.tsv" --first-window-s 1 --extend-s 1 --interval-s 1 --budget-s 60 --repeat-k 3
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$D/sampled")" -eq 3 ]
  [[ "$output" == *"STABLE REFUSAL"* ]] || false
  [[ "$output" == *"C3"* ]] || false
  # It stopped for the RIGHT reason: the budget was 60s and only 3s was spent.
  [[ "$output" != *"BUDGET EXHAUSTED"* ]]
}

@test "run does not call a MOVING refusal stable — it spends the budget instead" {
  # The counterpart, and the reason `run` tracks the failing SET rather than a bare refusal count:
  # a window whose failing term keeps changing is still converging, and stopping there would report
  # "this is the finding" about an instrument that was still moving.
  stub; plan C1 C3 C1 C3 C1
  run env CC_MARG_SELF="$D/stub.sh" bash "$M" run --no-preflight \
    --out "$D/m.tsv" --first-window-s 2 --extend-s 1 --interval-s 1 --budget-s 5 --repeat-k 3
  [ "$status" -eq 1 ]
  [[ "$output" == *"BUDGET EXHAUSTED"* ]] || false
  [[ "$output" != *"STABLE REFUSAL"* ]]
}

@test "run emits NOTHING quotable on any refusal path" {
  # The invariant the whole instrument exists for, restated one layer up: a DRIVER that summarised a
  # refused window would re-open the hole the four published values came out of. `run` relays
  # `analyze` verbatim and prints the citation block only on exit 0.
  stub; plan C2 C2 C2
  run env CC_MARG_SELF="$D/stub.sh" bash "$M" run --no-preflight \
    --out "$D/q.tsv" --first-window-s 1 --extend-s 1 --interval-s 1 --budget-s 60 --repeat-k 3
  [ "$status" -eq 1 ]
  [[ "$output" != *"VERDICT: MARGINAL"* ]] || false
  [[ "$output" != *"CITATION"* ]] || false
  [[ "$output" == *"withheld"* ]]
}

@test "run stops on NO-DATA rather than extending a window that cannot become one" {
  # NO-DATA is not a small window, it is an unreadable or unpoolable file. Extending it spends the
  # budget to re-learn the same thing.
  stub; plan NODATA
  run env CC_MARG_SELF="$D/stub.sh" bash "$M" run --no-preflight \
    --out "$D/n.tsv" --first-window-s 1 --extend-s 1 --interval-s 1 --budget-s 60
  [ "$status" -eq 3 ]
  [ "$(wc -l < "$D/sampled")" -eq 1 ]
  [[ "$output" == *"NO-DATA"* ]]
}

@test "run EXTENDS a NO-DATA that is only a short window, and does not confuse it with a broken file" {
  # `analyze` returns 3 for a file it cannot read, for one whose rows mix units, AND for "%d usable
  # row(s)" — which is not a broken file at all, just a window that has not reached three rows yet.
  # Collapsing the three aborts a run whose first window was short and blames the file. Caught by
  # the end-to-end test below, which did exactly that on a 2-second first window.
  stub; plan FEWROWS FEWROWS PASS
  run env CC_MARG_SELF="$D/stub.sh" bash "$M" run --no-preflight \
    --out "$D/few.tsv" --first-window-s 1 --extend-s 1 --interval-s 1 --budget-s 9 --repeat-k 5
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$D/sampled")" -eq 3 ]
  [[ "$output" == *"VERDICT: MARGINAL"* ]]
}

@test "run that never reaches three rows exits NO-DATA, not NO-ATTRIBUTION" {
  # ...and the two must not be laundered into each other: "the controls refused" and "the sampler
  # recorded almost nothing" send the operator to different places, so the persistent row-count
  # form keeps exit 3 and says to check load1 and `ps` rather than to buy more window.
  stub; plan FEWROWS
  run env CC_MARG_SELF="$D/stub.sh" bash "$M" run --no-preflight \
    --out "$D/few2.tsv" --first-window-s 1 --extend-s 1 --interval-s 1 --budget-s 60 --repeat-k 3
  [ "$status" -eq 3 ]
  [[ "$output" == *"NO-DATA(rows)"* ]] || false
  [[ "$output" == *"fewer than three usable rows"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]]
}

@test "run is re-runnable over a growing file — it never truncates the window it inherits" {
  # §6's honest protocol is "sample, analyze, and extend"; a second invocation that started the file
  # over would silently throw away the first hour, and the only symptom would be a verdict that
  # never improves.
  local f="$D/grow.tsv"; hdr "$f"; row "$f" 1000000 12.0 19 3 4
  stub; plan PASS
  run env CC_MARG_SELF="$D/stub.sh" bash "$M" run --no-preflight \
    --out "$f" --first-window-s 1 --interval-s 1 --budget-s 1
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$f")" -eq 2 ]
}

@test "run refuses a budget smaller than its own first window, rather than silently shrinking it" {
  run bash "$M" run --no-preflight --first-window-s 3600 --budget-s 600 --out "$D/b.tsv"
  [ "$status" -eq 2 ]
}

@test "run drives the REAL sampler end-to-end, controls and all" {
  # Every test above stubs the instrument to pin the loop. This one does not: it drives the shipped
  # `sample` and `analyze` over the live process table with a seconds-long window, and asserts the
  # thing that must be true of a real short window — it refuses, and it refuses through the same
  # rendering `run` parses. Without this, a rename inside `analyze` would leave the suite green and
  # the driver blind.
  run env CC_MARG_ACTIVE_OVERRIDE=5 bash "$M" run \
    --out "$D/real.tsv" --interval-s 1 --first-window-s 5 --extend-s 2 --budget-s 9 --repeat-k 9
  [ "$status" -eq 1 ]
  [[ "$output" == *"NO-ATTRIBUTION"* ]] || false
  [[ "$output" == *"BUDGET EXHAUSTED"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]]
}
