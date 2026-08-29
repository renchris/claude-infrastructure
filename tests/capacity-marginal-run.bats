#!/usr/bin/env bats
# capacity-marginal-run — the §6 protocol's LOOP, STOP RULE and ADJUDICATION, which were prose
# (backlog 193ae8ddce72; docs/research/marginal-load-per-active-session-2026-08-19.md §6).
#
# WHAT THIS SUITE IS FOR, and why it is not "does the wrapper wrap". `capacity-marginal.sh` already
# has a suite proving its three controls can FAIL. The thing this driver adds is a JUDGEMENT: §6
# says extend the window until the verdict clears "OR the refusal repeats with the same term across
# several windows — which would itself be the finding". Two failure modes live in that sentence and
# neither is visible from the analyzer:
#
#   1. Calling a QUIET BOX an instrument failure. `C2:neff` clears itself with wall clock by
#      construction (n_eff = span/tau + 1) and `C3:flat` clears when a dispatch wave moves the
#      ACTIVE count. Reporting either as §6's finding would be this wave's original sin — an
#      instrument that always answers — wearing the opposite sign.
#   2. Letting a coefficient escape a failed control. Four values spanning 30x are in the archive
#      because a number outlived the control that should have killed it. Every non-PASS stop is
#      asserted to print no coefficient at all.
#
# THE TOKENS ARE PINNED AGAINST THE REAL ANALYZER, NOT AGAINST A MOCK OF IT. The driver reduces a
# refusal to a reason token by matching the analyzer's own why-string, so a reworded why-string
# would silently collapse every signature to `:other` and turn the stop rule back into "it failed
# again". The three token tests below therefore run the REAL `capacity-marginal.sh analyze` over a
# fixture engineered to produce that exact why-string, and assert the token the driver derived. A
# suite that mocked the analyzer's text would pass forever against a script that had drifted.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RUN="$REPO/scripts/capacity-marginal-run.sh"
  REAL="$REPO/scripts/capacity-marginal.sh"
  D="$BATS_TEST_TMPDIR"
  # Hermetic HOME: `sample` resolves spawn-presence.sh, which reads the operator's beat directory.
  # A probe must never see the live fleet.
  export HOME="$D/home"; mkdir -p "$HOME/.claude"
  export CC_MARG_OUT="$D/run.tsv"
}

hdr() { printf '#ts\tload1\tunit\ttotal_run\tclaude_run\tactive\tresident\n' > "$1"; }

# A stub capacity-marginal.sh whose `analyze` replays SCRIPTED verdict blocks, one per call, and
# whose `sample` is a no-op. $1 = path to write; remaining args = one file per window, replayed in
# order (the last is repeated once the list is exhausted).
stub_scripted() {
  local path="$1"; shift
  printf '%s\n' "$@" > "$path.plan"
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
self="${BASH_SOURCE[0]}"
case "${1:-}" in
  sample) exit 0 ;;
  analyze)
    n=0; [ -r "$self.n" ] && n="$(cat "$self.n")"
    n=$(( n + 1 )); printf '%s' "$n" > "$self.n"
    f="$(sed -n "${n}p" "$self.plan")"
    [ -n "$f" ] || f="$(tail -1 "$self.plan")"
    cat "$f"
    grep -q '^VERDICT: MARGINAL' "$f" && exit 0
    grep -q 'NO-DATA' "$f" && exit 3
    exit 1 ;;
esac
exit 2
STUB
  chmod +x "$path"
}

# One canned analyze block. $1 = file, $2 = C1 verdict line tail, $3 = C2, $4 = C3.
block() {
  local f="$1"
  { printf 'CAPACITY-MARGINAL  n=60  n_eff=60.0  span=3540s  unit=proc  load1 10.00..30.00 (3.00x)\n'
    printf '  C1 LEVEL      %s\n' "$2"
    printf '  C2 DYNAMICS   %s\n' "$3"
    printf '  C3 IDENTIFY   %s\n' "$4"
    printf 'VERDICT: NO-ATTRIBUTION — a control failed; no coefficient is quotable from this window.\n'
    printf '  (the fit that WOULD have been reported: 0.412 load units per ACTIVE session — withheld)\n'
  } > "$f"
}

pass_block() {
  { printf 'CAPACITY-MARGINAL  n=60  n_eff=60.0  span=3540s  unit=proc  load1 10.00..30.00 (3.00x)\n'
    printf '  C1 LEVEL      PASS  tertile ratios 1.100 / 1.150 / 1.120 swing 1.05x\n'
    printf '  C2 DYNAMICS   PASS  corr(load1, census) = 0.812 over n_eff 60.0\n'
    printf '  C3 IDENTIFY   PASS  active spans 2..7 over 5 levels, 60 rows\n'
    printf 'VERDICT: MARGINAL 0.412 load units per ACTIVE session  (+/- 0.031, 1 s.e.; ratio 1.120 load/runnable-proc)\n'
  } > "$1"
}

# ── §6's FIRST EXIT: the verdict stops being NO-ATTRIBUTION ──────────────────────────────────────

@test "PASS stops the loop and hands over the close-out, re-GREP not a path list" {
  # §6a's finding is that the ban was enumerated as two paths and a grep found three, so the PASS
  # handover must print the SEARCH, never the list. A driver that pasted the two known paths would
  # re-commit the exact defect §6a exists to record.
  pass_block "$D/p"
  stub_scripted "$D/stub" "$D/p"
  run env CC_MARG_BIN="$D/stub" bash "$RUN" --out "$D/run.tsv" --window-s 1 --max-windows 3 --quiet
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS after 1 window(s)"* ]] || false
  [[ "$output" == *"MARGINAL 0.412 load units"* ]] || false
  [[ "$output" == *"grep -rnE"* ]] || false
  [[ "$output" == *"cc-backlog done 193ae8ddce72"* ]] || false
  # It stopped rather than spending the budget.
  [[ "$output" != *"window 2/3"* ]] || false
}

# ── §6's SECOND EXIT: the refusal repeats with the same term ─────────────────────────────────────

@test "THE FINDING: an INSTRUMENT term repeated exits 1 and routes to the thread-unit increment" {
  block "$D/corr" \
    "PASS  tertile ratios 1.10 / 1.12 / 1.15 swing 1.05x" \
    "FAIL  corr(load1, census) = 0.021 < 0.30 over n_eff 60.0 — the census does not track the load it apportions" \
    "PASS  active spans 2..7 over 5 levels, 60 rows"
  stub_scripted "$D/stub" "$D/corr"
  run env CC_MARG_BIN="$D/stub" bash "$RUN" --out "$D/run.tsv" --window-s 1 --max-windows 6 --repeat-stop 3
  [ "$status" -eq 1 ]
  [[ "$output" == *"THE FINDING"* ]] || false
  [[ "$output" == *"[C2:corr] refused 3 windows running"* ]] || false
  [[ "$output" == *"ps -axM"* ]] || false
  # It waited for the repeat rather than firing on the first refusal.
  [[ "$output" == *"window 3/6"* ]] || false
  [[ "$output" != *"window 4/6"* ]] || false
}

@test "a CONDITION term repeated is NOT the finding — a quiet box is not a broken census" {
  # C3:flat is the lull, and §6 names its remedy: run the window across a dispatch wave, and
  # explicitly do NOT synthesise levels by pausing the box. Calling this the instrument's failure
  # would kill the process-unit census on evidence about the operator's afternoon.
  block "$D/flat" \
    "PASS  tertile ratios 1.10 / 1.12 / 1.15 swing 1.05x" \
    "PASS  corr(load1, census) = 0.812 over n_eff 60.0" \
    "FAIL  active spans 4..4 over 1 level(s) — need spread >= 2 across >= 3 levels"
  stub_scripted "$D/stub" "$D/flat"
  run env CC_MARG_BIN="$D/stub" bash "$RUN" --out "$D/run.tsv" --window-s 1 --max-windows 6 --repeat-stop 3 --quiet
  [ "$status" -eq 3 ]
  [[ "$output" == *"still CONDITION-limited"* ]] || false
  [[ "$output" == *"ACROSS A DISPATCH WAVE"* ]] || false
  [[ "$output" != *"THE FINDING"* ]] || false
}

@test "C2:neff is a CONDITION — it clears itself with wall clock, so it may never be the finding" {
  # n_eff = span/tau + 1. A driver that stopped on this would refuse the census over the one term
  # that is arithmetically guaranteed to pass given another hour, and the analyzer says so in its
  # own words: "uninformative, not refuting".
  block "$D/neff" \
    "PASS  tertile ratios 1.10 / 1.12 / 1.15 swing 1.05x" \
    "FAIL  corr 0.991 but n_eff 4.2 < 20 independent observations (span 190s / tau 60s) — uninformative, not refuting" \
    "PASS  active spans 2..7 over 5 levels, 60 rows"
  stub_scripted "$D/stub" "$D/neff"
  run env CC_MARG_BIN="$D/stub" bash "$RUN" --out "$D/run.tsv" --window-s 1 --max-windows 4 --repeat-stop 2 --quiet
  [ "$status" -eq 3 ]
  [[ "$output" == *"still CONDITION-limited"* ]] || false
  [[ "$output" == *"[C2:neff]"* ]] || false
  [[ "$output" != *"THE FINDING"* ]] || false
}

@test "an unrecognised why-string is treated as an INSTRUMENT term — 'I cannot tell' stops" {
  # The safe side of a wording drift is to stop and make a human read it. The alternative is to
  # keep burning hours on a refusal whose meaning this file has silently lost.
  block "$D/odd" \
    "PASS  tertile ratios 1.10 / 1.12 / 1.15 swing 1.05x" \
    "FAIL  some future wording nobody here anticipated" \
    "PASS  active spans 2..7 over 5 levels, 60 rows"
  stub_scripted "$D/stub" "$D/odd"
  run env CC_MARG_BIN="$D/stub" bash "$RUN" --out "$D/run.tsv" --window-s 1 --max-windows 4 --repeat-stop 2 --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"[C2:other] refused 2 windows running"* ]] || false
}

@test "a MOVING refusal earns neither exit — it spends the budget and says the terms it saw" {
  block "$D/a" "FAIL  load span 1.02x < 1.50x required" "PASS  corr(load1, census) = 0.812 over n_eff 60.0" "PASS  active spans 2..7 over 5 levels, 60 rows"
  block "$D/b" "PASS  tertile ratios 1.10 / 1.12 / 1.15 swing 1.05x" "FAIL  corr(load1, census) = 0.021 < 0.30 over n_eff 60.0 — the census does not track the load it apportions" "PASS  active spans 2..7 over 5 levels, 60 rows"
  stub_scripted "$D/stub" "$D/a" "$D/b" "$D/a" "$D/b"
  run env CC_MARG_BIN="$D/stub" bash "$RUN" --out "$D/run.tsv" --window-s 1 --max-windows 4 --repeat-stop 2 --quiet
  [ "$status" -eq 3 ]
  [[ "$output" == *"budget spent"* ]] || false
  [[ "$output" == *"C1:span"* ]] || false
  [[ "$output" == *"C2:corr"* ]] || false
  [[ "$output" != *"THE FINDING"* ]] || false
}

# ── THE INHERITED INVARIANT: no coefficient escapes a failed control ─────────────────────────────

@test "NO stop path other than PASS prints a quotable coefficient" {
  # The analyzer withholds the fit and never prints `VERDICT: MARGINAL` on a refusal. A driver that
  # summarised its own run could re-introduce the leak the whole instrument exists to close, so the
  # property is asserted over every non-PASS exit rather than over one of them.
  block "$D/corr" "PASS  tertile ratios 1.10 / 1.12 / 1.15 swing 1.05x" "FAIL  corr(load1, census) = 0.021 < 0.30 over n_eff 60.0 — the census does not track the load it apportions" "PASS  active spans 2..7 over 5 levels, 60 rows"
  block "$D/flat" "PASS  tertile ratios 1.10 / 1.12 / 1.15 swing 1.05x" "PASS  corr(load1, census) = 0.812 over n_eff 60.0" "FAIL  active spans 4..4 over 1 level(s) — need spread >= 2 across >= 3 levels"
  local f
  for f in "$D/corr" "$D/flat"; do
    rm -f "$D/stub.n"
    stub_scripted "$D/stub" "$f"
    run env CC_MARG_BIN="$D/stub" bash "$RUN" --out "$D/run.tsv" --window-s 1 --max-windows 3 --repeat-stop 2 --quiet
    [ "$status" -ne 0 ]
    [[ "$output" != *"VERDICT: MARGINAL"* ]] || false
    [[ "$output" != *"CAPACITY-MARGINAL-RUN: PASS"* ]] || false
    # The withheld fit stays labelled withheld and is never restated as a result.
    [[ "$output" == *"withheld"* ]] || false
  done
}

# ── THE TOKENS, PINNED AGAINST THE REAL ANALYZER ─────────────────────────────────────────────────

# A stub whose `analyze` delegates to the REAL script over a fixture, so the driver classifies the
# analyzer's actual wording. $1 = stub path, $2 = fixture TSV.
stub_real() {
  cat > "$1" <<STUB
#!/usr/bin/env bash
case "\${1:-}" in
  sample) exit 0 ;;
  analyze) exec bash "$REAL" analyze --in "$2" ;;
esac
exit 2
STUB
  chmod +x "$1"
}

@test "C2:corr is derived from the REAL analyzer over the census shape that killed the headline" {
  # The same series tests/capacity-marginal.bats replays as its positive control: flat 19-20 across
  # a 2.2x load range at 60 s spacing, so n_eff is not the reason. If the analyzer's wording ever
  # changes, this fails here rather than degrading every signature to `other`.
  local f="$D/fx.tsv"; hdr "$f"
  local i ts=1000000 load
  for i in $(seq 0 39); do
    load="$(awk -v i="$i" 'BEGIN { printf "%.2f", 12 + 14 * i / 39 }')"
    printf '%s\t%s\tproc\t%s\t%s\t%s\t14\n' "$ts" "$load" "$(( 19 + i % 2 ))" "$(( 2 + i % 3 ))" "$(( 3 + i % 4 ))" >> "$f"
    ts=$(( ts + 60 ))
  done
  stub_real "$D/stub" "$f"
  run env CC_MARG_BIN="$D/stub" bash "$RUN" --out "$D/run.tsv" --window-s 1 --max-windows 3 --repeat-stop 2 --quiet
  [ "$status" -eq 1 ]
  # That series fails C1 as well — its tertile ratios swing 1.67x, the x1.553 single-point-fit
  # defect, which is why the signature carries BOTH terms. Pinned whole rather than as a substring:
  # a signature is the set of failing terms, and asserting one of two would pass against a driver
  # that had silently dropped the other.
  [[ "$output" == *"[C1:swing C2:corr] refused 2 windows running"* ]] || false
}

@test "C3:flat is derived from the REAL analyzer over a window whose ACTIVE count never moved" {
  local f="$D/fx3.tsv"; hdr "$f"
  local i ts=1000000 load cen
  for i in $(seq 0 39); do
    load="$(awk -v i="$i" 'BEGIN { printf "%.2f", 12 + 14 * i / 39 }')"
    cen="$(awk -v i="$i" 'BEGIN { printf "%d", 11 + 13 * i / 39 }')"
    printf '%s\t%s\tproc\t%s\t%s\t%s\t14\n' "$ts" "$load" "$cen" "$(( 2 + i % 3 ))" 4 >> "$f"
    ts=$(( ts + 60 ))
  done
  stub_real "$D/stub" "$f"
  run env CC_MARG_BIN="$D/stub" bash "$RUN" --out "$D/run.tsv" --window-s 1 --max-windows 3 --repeat-stop 2 --quiet
  [ "$status" -eq 3 ]
  [[ "$output" == *"[C3:flat]"* ]] || false
  [[ "$output" == *"still CONDITION-limited"* ]] || false
}

@test "C2:neff is derived from the REAL analyzer over a window sampled too fast to be independent" {
  local f="$D/fx2.tsv"; hdr "$f"
  local i ts=1000000 load cen
  for i in $(seq 0 39); do
    load="$(awk -v i="$i" 'BEGIN { printf "%.2f", 12 + 14 * i / 39 }')"
    cen="$(awk -v i="$i" 'BEGIN { printf "%d", 11 + 13 * i / 39 }')"
    printf '%s\t%s\tproc\t%s\t%s\t%s\t14\n' "$ts" "$load" "$cen" "$(( 2 + i % 3 ))" "$(( 3 + i % 4 ))" >> "$f"
    ts=$(( ts + 5 ))
  done
  stub_real "$D/stub" "$f"
  run env CC_MARG_BIN="$D/stub" bash "$RUN" --out "$D/run.tsv" --window-s 1 --max-windows 3 --repeat-stop 2 --quiet
  [ "$status" -eq 3 ]
  [[ "$output" == *"[C2:neff]"* ]] || false
}

# ── THE PROTOCOL IS RESUMABLE, AND THAT IS THE STATE MODEL ───────────────────────────────────────

@test "an existing TSV is EXTENDED, never restarted — the file is the run's whole state" {
  # §6: "analyze is re-runnable over a growing file". An interrupted 4-hour run that restarted from
  # zero would make the protocol unaffordable in exactly the case it is designed for.
  local f="$D/run.tsv"; hdr "$f"
  printf '1000000\t12.00\tproc\t19\t2\t3\t14\n' >> "$f"
  printf '1000060\t18.00\tproc\t20\t3\t4\t14\n' >> "$f"
  block "$D/corr" "PASS  tertile ratios 1.10 / 1.12 / 1.15 swing 1.05x" "FAIL  corr(load1, census) = 0.021 < 0.30 over n_eff 60.0 — the census does not track the load it apportions" "PASS  active spans 2..7 over 5 levels, 60 rows"
  stub_scripted "$D/stub" "$D/corr"
  run env CC_MARG_BIN="$D/stub" bash "$RUN" --out "$f" --window-s 1 --max-windows 2 --repeat-stop 2
  [[ "$output" == *"RESUMING"* ]] || false
  [[ "$output" == *"already carries 2 row(s)"* ]] || false
  # The rows are still there: nothing truncated them.
  [ "$(grep -cv '^#' "$f")" -eq 2 ]
}

# ── USAGE ────────────────────────────────────────────────────────────────────────────────────────

@test "one refusal is not a repeat: --repeat-stop 1 is a usage error, not a hair trigger" {
  run env CC_MARG_BIN="$REAL" bash "$RUN" --repeat-stop 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"one refusal is not a repeat"* ]] || false
}

@test "a non-integer window is a usage error, not a busy loop" {
  run env CC_MARG_BIN="$REAL" bash "$RUN" --window-s abc
  [ "$status" -eq 2 ]
}

@test "a missing analyzer is named, never silently treated as a refusal" {
  run env CC_MARG_BIN="$D/nope" bash "$RUN" --window-s 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot read analyzer"* ]] || false
}

# ── THE WIRING, AGAINST THE REAL SAMPLER ─────────────────────────────────────────────────────────

@test "end to end against the real sampler: a window too short to decide is NO-DATA, not a number" {
  # Every test above stubs one half. This one stubs neither, so a driver wired to the wrong verb or
  # the wrong flag fails here rather than at 1 a.m. on the operator's box. It asserts only what is
  # true on any host — the run reaches a verdict and quotes nothing — because a gate corpus may
  # never depend on how busy the machine running it happens to be.
  run bash "$RUN" --out "$D/e2e.tsv" --window-s 2 --interval-s 1 --max-windows 1 --quiet
  [ "$status" -ne 0 ]
  [[ "$output" != *"VERDICT: MARGINAL"* ]] || false
  [ -s "$D/e2e.tsv" ]
}
