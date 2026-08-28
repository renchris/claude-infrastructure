#!/usr/bin/env bats
# capacity-marginal-run — the driver that turns §6's run protocol into one command, and must
# REFUSE a box that cannot answer before it spends the budget rather than after
# (backlog 193ae8ddce72; protocol docs/research/marginal-load-per-active-session-2026-08-19.md §6).
#
# WHAT THIS SUITE IS FOR. The sibling suite (capacity-marginal.bats) pins the three CONTROLS. This
# one pins the three JUDGMENTS the protocol previously left to a human: when to stop sampling, when
# a refusal is the finding rather than a short window, and when the box is the wrong box. Each of
# those is a place where an always-answering driver would re-create the defect the instrument was
# built to refuse — a persistent-refusal verdict declared over four minutes of data is the B3
# mistake with a nicer wrapper — so every one of them is tested by watching it decline to fire.
#
# WHY A STUB SAMPLER. The subject here is the DRIVER's control flow over a sequence of verdicts,
# not the sampler's arithmetic (already covered next door). A stub lets a test say "refuse with C1
# three times, then pass" in three lines, and — decisively — lets the suite run in a second instead
# of the two hours a real settle floor would take. The stub is the sampler's CONTRACT, not a
# reimplementation of it: it speaks the same subcommands, the same --json shape and the same exit
# codes, and any drift in those is what the sibling suite's own tests pin.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  R="$REPO/scripts/capacity-marginal-run.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude"
  export OUT="$D/marg.tsv"
  STUB="$D/stub-sampler.sh"
  export STUB_DIR="$D/plan"; mkdir -p "$STUB_DIR"
  write_stub
  export CC_MARGRUN_SAMPLER="$STUB"
}

# A stand-in for capacity-marginal.sh speaking its exact contract:
#   sample  — appends one row of $STUB_ROW to --out, exits $STUB_SAMPLE_RC (default 0)
#   analyze --json — advances the step counter, prints $STUB_DIR/step-N.json, exits its rc
#   analyze (text) — prints $STUB_DIR/step-N.txt at the CURRENT step, without advancing
# The driver always calls --json first and the text form second for the same window, so the two
# must report the same step or the recorded "why" would describe a different window than the terms.
write_stub() {
  cat > "$STUB" <<'STUBEOF'
#!/bin/bash
set -uo pipefail
sub="${1:-}"; shift || true
out=""; in=""; json=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) out="${2:-}"; shift 2 ;;
    --in)  in="${2:-}";  shift 2 ;;
    --json) json=1; shift ;;
    *) shift ;;
  esac
done
n_file="$STUB_DIR/n"; [ -f "$n_file" ] || echo 0 > "$n_file"
n="$(cat "$n_file")"
last() { ls "$STUB_DIR"/step-*.json 2>/dev/null | sed 's/.*step-//;s/\.json//' | sort -n | tail -1; }
case "$sub" in
  sample)
    [ -s "$out" ] || printf '#ts\tload1\tunit\ttotal_run\tclaude_run\tactive\tresident\n' > "$out"
    printf '%s\n' "${STUB_ROW:-$(date +%s)$'\t'2.00$'\t'proc$'\t'20$'\t'4$'\t'3$'\t'14}" >> "$out"
    exit "${STUB_SAMPLE_RC:-0}" ;;
  analyze)
    [ -r "$in" ] || { echo "CAPACITY-MARGINAL: NO-DATA — cannot read $in"; exit 3; }
    if [ -n "$json" ]; then n=$(( n + 1 )); echo "$n" > "$n_file"; fi
    [ "$n" -ge 1 ] || n=1
    hi="$(last)"; [ -n "$hi" ] || hi=1
    [ "$n" -le "$hi" ] || n="$hi"          # a plan shorter than the run repeats its last step
    if [ -n "$json" ]; then cat "$STUB_DIR/step-$n.json"; else cat "$STUB_DIR/step-$n.txt"; fi
    exit "$(cat "$STUB_DIR/step-$n.rc")" ;;
esac
exit 2
STUBEOF
  chmod +x "$STUB"
}

# step <n> <rc> <c1 true|false> <c2 …> <c3 …> [c2_why]
step() {
  local n="$1" rc="$2" c1="$3" c2="$4" c3="$5" why="${6:-corr(load1, census) = 0.10 < 0.30 over n_eff 44.0 — the census does not track the load it apportions}"
  printf '{"n":40,"n_eff":44.00,"span_s":2600,"unit":"proc","load_min":8.00,"load_max":40.00,"c1_level":%s,"c2_dynamics":%s,"c3_identify":%s,"c1_why":"x","c2_why":"y","c3_why":"z","ratio":1.2,"naive_slope":0.4%s}\n' \
    "$c1" "$c2" "$c3" \
    "$( [ "$rc" = 0 ] && printf ',"verdict":"MARGINAL","marginal_load_per_active_session":0.3330,"se":0.0210' || printf ',"verdict":"NO-ATTRIBUTION"' )" \
    > "$STUB_DIR/step-$n.json"
  {
    printf 'CAPACITY-MARGINAL  n=40  n_eff=44.0  span=2600s  unit=proc  load1 8.00..40.00 (5.00x)\n'
    printf '  C1 LEVEL      %-4s  tertile ratios 1.10 / 1.12 / 1.15 swing 1.05x\n' "$( [ "$c1" = true ] && echo PASS || echo FAIL )"
    printf '  C2 DYNAMICS   %-4s  %s\n' "$( [ "$c2" = true ] && echo PASS || echo FAIL )" "$why"
    printf '  C3 IDENTIFY   %-4s  active spans 2..7 over 5 levels, 40 rows\n' "$( [ "$c3" = true ] && echo PASS || echo FAIL )"
    if [ "$rc" = 0 ]; then
      printf 'VERDICT: MARGINAL 0.333 load units per ACTIVE session  (+/- 0.021, 1 s.e.; ratio 1.200 load/runnable-proc)\n'
    else
      printf 'VERDICT: NO-ATTRIBUTION — a control failed; no coefficient is quotable from this window.\n'
    fi
  } > "$STUB_DIR/step-$n.txt"
  printf '%s' "$rc" > "$STUB_DIR/step-$n.rc"
}

# ── PREFLIGHT: refuse the wrong box in a second, not an hour ─────────────────────────────────────

@test "PREFLIGHT refuses a box whose ACTIVE sensor is unmeasurable, and samples nothing" {
  # The live case this session ran into: a container with no fleet writes '-' in the active column.
  # cc_sp_active is the population the coefficient is DENOMINATED in, so a dash there is not a
  # quiet box, it is no measurement at all — and sampling zeros for an hour would produce a C3
  # failure that reads identically to a real one.
  export STUB_ROW=$'1000000\t2.00\tproc\t20\t4\t-\t14'
  step 1 1 true true true
  run bash "$R" --out "$OUT" --window-s 1 --interval-s 1 --max-total-s 1
  [ "$status" -eq 4 ]
  [[ "$output" == *"PREFLIGHT-REFUSED — active"* ]] || false
  [[ "$output" == *"must not read as a quiet box"* ]] || false
  # nothing was spent: the only row on disk is preflight's own probe, which lives in its own file
  [ ! -s "$OUT" ]
}

@test "PREFLIGHT refuses a box with no fleet — the measurement's own subject is missing" {
  export STUB_ROW=$'1000000\t2.00\tproc\t20\t4\t3\t0'
  step 1 1 true true true
  run bash "$R" --out "$OUT" --window-s 1 --interval-s 1 --max-total-s 1
  [ "$status" -eq 4 ]
  [[ "$output" == *"PREFLIGHT-REFUSED — fleet: 0 resident session(s)"* ]] || false
  [[ "$output" == *"slope through one point"* ]] || false
}

@test "PREFLIGHT refuses when the sampler records no row at all — load1 unreadable" {
  # `sample` drops a row rather than writing load1 as 0, and returns 3 when it recorded none.
  # Without this arm the driver would sample its whole budget into an empty file.
  export STUB_SAMPLE_RC=3 STUB_ROW=""
  step 1 1 true true true
  run bash "$R" --out "$OUT" --window-s 1 --interval-s 1 --max-total-s 1
  [ "$status" -eq 4 ]
  [[ "$output" == *"PREFLIGHT-REFUSED — load1"* ]] || false
}

@test "PREFLIGHT passes a healthy box, and --preflight-only spends no budget" {
  export STUB_ROW=$'1000000\t2.00\tproc\t20\t4\t3\t14'
  step 1 1 true true true
  run bash "$R" --out "$OUT" --preflight-only --window-s 1 --interval-s 1 --max-total-s 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"PREFLIGHT PASS"* ]] || false
  [[ "$output" == *"cc_sp_active = 3"* ]] || false
  [[ "$output" != *"sampling"* ]] || false
}

# ── THE THREE VERDICTS THE PROTOCOL LEFT TO A HUMAN ─────────────────────────────────────────────

@test "a PASS stops the loop, emits the coefficient, and re-greps the citation sites" {
  export STUB_ROW=$'1000000\t2.00\tproc\t20\t4\t3\t14'
  step 1 0 true true true
  run bash "$R" --out "$OUT" --window-s 1 --interval-s 1 --max-total-s 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: MARGINAL"* ]] || false
  [[ "$output" == *"0.333 load units per ACTIVE session"* ]] || false
  # §6a's lesson: the sites are DERIVED at the PASS, never recited from a stored list
  [[ "$output" == *"CITATION SITES — re-grepped just now"* ]] || false
  [[ "$output" == *"cc-backlog done 193ae8ddce72"* ]] || false
}

@test "PERSISTENT-REFUSAL: the same term across N windows past the settle floor IS the finding" {
  # §6: "the refusal repeats with the same term across several windows — which would itself be the
  # finding". Exit 3, distinct from UNDECIDED, so a caller can tell "we learned something" from
  # "we ran out of budget".
  export STUB_ROW=$'1000000\t2.00\tproc\t20\t4\t3\t14'
  step 1 1 false true true
  CC_MARGRUN_SETTLE_S=1 run bash "$R" --out "$OUT" --window-s 1 --interval-s 1 --max-total-s 10 \
      --repeat-refusals 3
  [ "$status" -eq 3 ]
  [[ "$output" == *"VERDICT: PERSISTENT-REFUSAL"* ]] || false
  [[ "$output" == *"'C1' refused 3 consecutive windows"* ]] || false
  [[ "$output" == *"IS the finding"* ]] || false
  [[ "$output" == *"thread-unit refinement"* ]] || false
}

@test "THE SETTLE FLOOR: the same term repeated below the floor is NOT yet a finding" {
  # The guard that stops this driver from re-committing B3's mistake. Identical input to the test
  # above; only the floor moves. A persistent-refusal verdict declared over a few minutes of data
  # would be exactly the "2.5-4 min window reported as refuting" defect.
  export STUB_ROW=$'1000000\t2.00\tproc\t20\t4\t3\t14'
  step 1 1 false true true
  CC_MARGRUN_SETTLE_S=100000 run bash "$R" --out "$OUT" --window-s 1 --interval-s 1 \
      --max-total-s 10 --repeat-refusals 3
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERDICT: UNDECIDED"* ]] || false
  [[ "$output" != *"PERSISTENT-REFUSAL"* ]] || false
}

@test "an UNINFORMATIVE C2 never builds a streak, however often it repeats" {
  # B3 by name: a window too short for load1's 60 s time constant carries no information about the
  # correlation, so repeating it cannot become evidence that the instrument is wrong. Same shape as
  # the PERSISTENT-REFUSAL test, same floor — only the wording of the C2 failure differs.
  export STUB_ROW=$'1000000\t2.00\tproc\t20\t4\t3\t14'
  step 1 1 true false true \
    "corr 0.900 but n_eff 4.2 < 20 independent observations (span 20s / tau 60s) — uninformative, not refuting"
  CC_MARGRUN_SETTLE_S=1 run bash "$R" --out "$OUT" --window-s 1 --interval-s 1 \
      --max-total-s 8 --repeat-refusals 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"uninformative, not refuting"* ]] || false
  [[ "$output" == *"does not count toward a persistent refusal"* ]] || false
  [[ "$output" != *"PERSISTENT-REFUSAL"* ]] || false
}

@test "UNDECIDED when the failing term is still moving — and it names the command that extends" {
  # Three windows, three different terms: nothing has been established, and the honest answer is
  # "extend", over the SAME series, because analyze is re-runnable over a growing file.
  export STUB_ROW=$'1000000\t2.00\tproc\t20\t4\t3\t14'
  step 1 1 false true true
  step 2 1 true true false
  step 3 1 false true true
  step 4 1 true true false
  CC_MARGRUN_SETTLE_S=1 run bash "$R" --out "$OUT" --window-s 1 --interval-s 1 \
      --max-total-s 4 --repeat-refusals 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERDICT: UNDECIDED"* ]] || false
  [[ "$output" == *"--max-total-s 8"* ]] || false
  [[ "$output" == *"--no-preflight"* ]] || false
}

# ── the ordinary guards ─────────────────────────────────────────────────────────────────────────

@test "the series accumulates across increments — analyze re-runs over a GROWING file" {
  # The protocol's own mechanic: increments extend one series rather than measuring N short ones,
  # because n_eff is a property of the window's span.
  export STUB_ROW=$'1000000\t2.00\tproc\t20\t4\t3\t14'
  step 1 1 false true true
  CC_MARGRUN_SETTLE_S=100000 run bash "$R" --out "$OUT" --window-s 1 --interval-s 1 --max-total-s 3
  [ "$status" -eq 1 ]
  [ "$(grep -vc '^#' "$OUT")" -eq 3 ]
}

@test "--fresh discards a prior series instead of pooling two windows" {
  export STUB_ROW=$'1000000\t2.00\tproc\t20\t4\t3\t14'
  step 1 1 false true true
  printf '#stale\nrubbish\n' > "$OUT"
  CC_MARGRUN_SETTLE_S=100000 run bash "$R" --out "$OUT" --fresh --window-s 1 --interval-s 1 --max-total-s 1
  [ "$status" -eq 1 ]
  [ "$(grep -c 'rubbish' "$OUT")" -eq 0 ]
}

@test "a bad interval is a usage error, not a busy loop" {
  run bash "$R" --out "$OUT" --interval-s 0
  [ "$status" -eq 2 ]
  run bash "$R" --out "$OUT" --window-s abc
  [ "$status" -eq 2 ]
  run bash "$R" --nonsense
  [ "$status" -eq 2 ]
}

@test "a missing sampler is refused before anything is sampled" {
  CC_MARGRUN_SAMPLER="$D/nope.sh" run bash "$R" --out "$OUT" --window-s 1 --max-total-s 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"sampler not readable"* ]] || false
}

@test "the run is recorded beside the series, so a verdict outlives the terminal it printed in" {
  export STUB_ROW=$'1000000\t2.00\tproc\t20\t4\t3\t14'
  step 1 0 true true true
  run bash "$R" --out "$OUT" --window-s 1 --interval-s 1 --max-total-s 2
  [ "$status" -eq 0 ]
  [ -s "$OUT.log" ]
  grep -q 'VERDICT: MARGINAL' "$OUT.log"
}
