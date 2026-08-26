#!/usr/bin/env bats
# capacity-marginal-run — the DRIVER for §6 of
# docs/research/marginal-load-per-active-session-2026-08-19.md (backlog 193ae8ddce72).
#
# WHAT THIS SUITE IS FOR. The sampler's own suite proves the three CONTROLS can fail. This one
# proves the LOOP AROUND THEM stops in the right place, which is a different property and the one
# §6 delegates to a human today. Two decisions carry the whole file:
#
#   1. The PREFLIGHT must be able to ADMIT. A guard that refused everywhere would pass every
#      refusal test here and silently make the measurement unrunnable. Hence a positive control
#      with a live sensor and a resident fleet, paired against each refusal.
#   2. An `n_eff` shortfall is NOT the finding. It is the ONE refusal extending the window cures,
#      and §6's terminal condition ("the refusal repeats with the same term") reads as terminal if
#      taken literally. A driver that stopped there would report "the instrument cannot answer"
#      the moment the instrument was merely early — B3's exact defect, one layer up.
#
# WHY A STUB SAMPLER. Every property under test is a property of the SEQUENCE of verdicts, so the
# subject is a scripted series, not a machine. Driving the real sampler would make this suite pass
# or fail on how busy the box is — the one input a gate corpus may never depend on, and the same
# reason capacity-marginal.bats uses fixtures.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  R="$REPO/scripts/capacity-marginal-run.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude"
  # The driver's preflight sources lib/spawn-presence.sh, which reaches scripts/lib/capacity-admit.sh
  # — a gate that reads LIVE load, memory and session census. Left ambient, this suite would go
  # red-by-desk rather than by its subject (backlog 5ef0dcb22aec). The gate is not what is under
  # test here; the preflight's own two facts are, and `staged()` pins those directly.
  export CC_ADMIT_GATE=off

  # ── the stub sampler: one scripted analyze verdict per round ──────────────────────────────────
  export STUB_DIR="$D/plan"; mkdir -p "$STUB_DIR"
  export STUB_N="$D/n"
  cat > "$D/stub.sh" <<'STUB'
#!/bin/bash
case "${1:-}" in
  sample) exit 0 ;;
  analyze)
    n=0; [ -r "$STUB_N" ] && n="$(cat "$STUB_N")"
    n=$(( n + 1 )); printf '%s' "$n" > "$STUB_N"
    f="$STUB_DIR/round$n"; [ -r "$f" ] || f="$STUB_DIR/default"
    [ -r "$f" ] || { echo "stub: no plan"; exit 3; }
    rc="$(head -1 "$f")"; tail -n +2 "$f"; exit "$rc" ;;
  *) exit 2 ;;
esac
STUB
  export CC_MARGRUN_SAMPLER="$D/stub.sh"
}

# plan <round|default> <rc> <analyze text>
plan() { printf '%s\n%s\n' "$2" "$3" > "$STUB_DIR/round$1"; }
plan_default() { printf '%s\n%s\n' "$1" "$2" > "$STUB_DIR/default"; }

# A driver copy whose sibling lib/ we control, so the preflight's two facts are settable.
# <active-or-empty> -> echoes the path to run
staged() {
  local a="$1" dir="$D/stage$RANDOM"
  mkdir -p "$dir/scripts/lib"
  cp "$R" "$dir/scripts/capacity-marginal-run.sh"
  if [ -n "$a" ]; then
    printf 'cc_sp_active() { printf %%s %s; }\n' "$a" > "$dir/scripts/lib/spawn-presence.sh"
  else
    printf 'cc_sp_active() { printf %%s ""; }\n' > "$dir/scripts/lib/spawn-presence.sh"
  fi
  printf '%s' "$dir/scripts/capacity-marginal-run.sh"
}

PASS_TXT='CAPACITY-MARGINAL  n=60  n_eff=60.0  span=3540s  unit=proc  load1 11.20..29.70 (2.65x)
  C1 LEVEL      PASS  tertile ratios 1.310 / 1.288 / 1.402 swing 1.09x
  C2 DYNAMICS   PASS  corr(load1, census) = 0.741 over n_eff 60.0
  C3 IDENTIFY   PASS  active spans 2..7 over 5 levels, 60 rows
VERDICT: MARGINAL 0.412 load units per ACTIVE session  (+/- 0.061, 1 s.e.; ratio 1.333 load/runnable-proc)'

NEFF_TXT='CAPACITY-MARGINAL  n=6  n_eff=1.8  span=48s  unit=proc  load1 11.20..17.40 (1.55x)
  C1 LEVEL      PASS  tertile ratios 1.310 / 1.288 / 1.402 swing 1.09x
  C2 DYNAMICS   FAIL  corr 0.812 but n_eff 1.8 < 20 independent observations (span 48s / tau 60s) — uninformative, not refuting
  C3 IDENTIFY   PASS  active spans 2..7 over 5 levels, 6 rows
VERDICT: NO-ATTRIBUTION — a control failed; no coefficient is quotable from this window.
  (the fit that WOULD have been reported: 0.377 load units per ACTIVE session — withheld)'

C1_TXT='CAPACITY-MARGINAL  n=60  n_eff=60.0  span=3540s  unit=proc  load1 9.10..31.40 (3.45x)
  C1 LEVEL      FAIL  tertile ratios 0.913 / 1.077 / 1.980 swing 2.17x > 1.35x
  C2 DYNAMICS   PASS  corr(load1, census) = 0.688 over n_eff 60.0
  C3 IDENTIFY   PASS  active spans 2..7 over 5 levels, 60 rows
VERDICT: NO-ATTRIBUTION — a control failed; no coefficient is quotable from this window.'

C2_TXT='CAPACITY-MARGINAL  n=60  n_eff=60.0  span=3540s  unit=proc  load1 9.10..31.40 (3.45x)
  C1 LEVEL      PASS  tertile ratios 1.310 / 1.288 / 1.402 swing 1.09x
  C2 DYNAMICS   FAIL  corr(load1, census) = 0.041 < 0.30 over n_eff 60.0 — the census does not track the load it apportions
  C3 IDENTIFY   PASS  active spans 2..7 over 5 levels, 60 rows
VERDICT: NO-ATTRIBUTION — a control failed; no coefficient is quotable from this window.'

# ── THE PREFLIGHT MUST BE ABLE TO ADMIT ─────────────────────────────────────────────────────────

@test "PREFLIGHT POSITIVE CONTROL: a live ACTIVE sensor and a resident fleet are ADMITTED" {
  # Without this row every refusal below would also pass against a guard that refuses everywhere,
  # and the measurement would be quietly unrunnable on the one box it is for.
  local s; s="$(staged 5)"
  plan_default 0 "$PASS_TXT"
  CC_MARG_EXEC_RE='bash' run bash "$s" --round-s 1 --interval-s 1 --max-rounds 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: MARGINAL"* ]] || false
  [[ "$output" != *"PREFLIGHT-REFUSED"* ]]
}

@test "PREFLIGHT refuses an UNMEASURABLE active census, and names the control it starves" {
  # The expensive failure: a Darwin box with a dead sensor burns the whole window to discover C3
  # could never have passed. Refusing costs nothing and says why.
  local s; s="$(staged '')"
  plan_default 0 "$PASS_TXT"
  CC_MARG_EXEC_RE='bash' run bash "$s" --round-s 1 --interval-s 1 --max-rounds 1
  [ "$status" -eq 4 ]
  [[ "$output" == *"PREFLIGHT-REFUSED"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]] || false
  [[ "$stderr" == *"UNMEASURABLE"* ]] || [[ "$output" == *"UNMEASURABLE"* ]] || \
    { CC_MARG_EXEC_RE='bash' bash "$s" --round-s 1 --interval-s 1 --max-rounds 1 2>&1 | grep -q "C3 IDENTIFY can never"; }
}

@test "PREFLIGHT refuses when no resident fleet matches the launcher path — off-box, this is the line" {
  local s; s="$(staged 5)"
  plan_default 0 "$PASS_TXT"
  CC_MARG_EXEC_RE='zzz-no-such-process-zzz' run bash "$s" --round-s 1 --interval-s 1 --max-rounds 1
  [ "$status" -eq 4 ]
  [[ "$output" == *"PREFLIGHT-REFUSED"* ]] || false
  CC_MARG_EXEC_RE='zzz-no-such-process-zzz' bash "$s" --round-s 1 --interval-s 1 --max-rounds 1 2>&1 \
    | grep -q "RESIDENT fleet  NONE"
}

@test "--force runs the rounds anyway, and never suppresses the reason" {
  local s; s="$(staged '')"
  plan_default 0 "$PASS_TXT"
  CC_MARG_EXEC_RE='bash' run bash "$s" --round-s 1 --interval-s 1 --max-rounds 1 --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: MARGINAL"* ]]
}

# ── THE ONE JUDGMENT: WHICH REFUSALS ARE THE FINDING ────────────────────────────────────────────

@test "an n_eff shortfall NEVER becomes the finding, however often it repeats" {
  # THE row this file exists for. §6's terminal condition read literally ("the refusal repeats with
  # the same term") fires on the first short window every single time — and that refusal is the one
  # extending the window CURES. The sampler words it "uninformative, not refuting" precisely so a
  # reader can tell; the driver has to act on the distinction.
  local s; s="$(staged 4)"
  plan_default 1 "$NEFF_TXT"
  CC_MARG_EXEC_RE='bash' run bash "$s" --round-s 1 --interval-s 1 --max-rounds 3 --repeat 2
  [ "$status" -eq 6 ]
  [[ "$output" == *"VERDICT: UNDECIDED"* ]] || false
  [[ "$output" != *"TERMINAL-REFUSAL"* ]]
}

@test "a SUBSTANTIVE refusal repeating with the same term IS reported as the finding" {
  local s; s="$(staged 4)"
  plan_default 1 "$C1_TXT"
  CC_MARG_EXEC_RE='bash' run bash "$s" --round-s 1 --interval-s 1 --max-rounds 4 --repeat 2
  [ "$status" -eq 5 ]
  [[ "$output" == *"TERMINAL-REFUSAL"* ]] || false
  [[ "$output" == *"[C1]"* ]] || false
  [[ "$output" == *"thread-unit"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]]
}

@test "a refusal whose failing TERM changes is not 'the same term' — it never reaches the finding" {
  # Two different controls failing in alternation is an unstable window, not a reproduced verdict.
  local s; s="$(staged 4)"
  plan 1 1 "$C1_TXT"; plan 2 1 "$C2_TXT"; plan 3 1 "$C1_TXT"; plan 4 1 "$C2_TXT"
  CC_MARG_EXEC_RE='bash' run bash "$s" --round-s 1 --interval-s 1 --max-rounds 4 --repeat 2
  [ "$status" -eq 6 ]
  [[ "$output" == *"VERDICT: UNDECIDED"* ]] || false
  [[ "$output" != *"TERMINAL-REFUSAL"* ]]
}

@test "a NO-DATA round breaks the streak — nothing sampled is not a refusal" {
  local s; s="$(staged 4)"
  plan 1 1 "$C1_TXT"; plan 2 3 'CAPACITY-MARGINAL: NO-DATA — 1 usable row(s)'; plan 3 1 "$C1_TXT"
  CC_MARG_EXEC_RE='bash' run bash "$s" --round-s 1 --interval-s 1 --max-rounds 3 --repeat 2
  [ "$status" -eq 6 ]
  [[ "$output" != *"TERMINAL-REFUSAL"* ]]
}

@test "the n_eff carve-out survives an analyze payload larger than the pipe buffer" {
  # REGRESSION, caught by the land gate's pipefail/SIGPIPE ratchet and not by any test above. The
  # driver runs under `pipefail`, so an early-exiting consumer (`grep -q`) SIGPIPEs its producer
  # and the pipeline reports the producer's 141 — the condition reads FALSE ON A MATCH as soon as
  # the payload outgrows the pipe buffer. Every row above passed with `grep -q` in place, because
  # a five-line fixture fits the buffer and printf finishes before grep exits. This row makes the
  # payload big enough that it cannot, so the inversion is what fails the test rather than what
  # ships. If it ever goes red, the n_eff carve-out has silently inverted and a short window is
  # being reported as the finding.
  local s pad; s="$(staged 4)"
  pad="$(awk 'BEGIN { for (i = 0; i < 4000; i++) print "  padding row to outgrow the 64 KiB pipe buffer" }')"
  plan_default 1 "$NEFF_TXT
$pad"
  CC_MARG_EXEC_RE='bash' run bash "$s" --round-s 1 --interval-s 1 --max-rounds 3 --repeat 2
  [ "$status" -eq 6 ]
  [[ "$output" != *"TERMINAL-REFUSAL"* ]]
}

# ── NOTHING QUOTABLE ESCAPES A NON-PASS ─────────────────────────────────────────────────────────

@test "the deadline is its own outcome, and emits no coefficient" {
  # UNDECIDED must never round to either neighbour. The four published values are what happens when
  # an inconclusive run gets reported as a number.
  local s; s="$(staged 4)"
  plan_default 1 "$NEFF_TXT"
  CC_MARG_EXEC_RE='bash' run bash "$s" --round-s 1 --interval-s 1 --max-rounds 2 --repeat 9
  [ "$status" -eq 6 ]
  [[ "$output" == *"UNDECIDED"* ]] || false
  [[ "$output" != *"VERDICT: MARGINAL"* ]] || false
  [[ "$output" == *"CUMULATIVE"* ]]
}

@test "a PASS hands over the standard error and the close command, not a bare number" {
  local s; s="$(staged 6)"
  plan_default 0 "$PASS_TXT"
  CC_MARG_EXEC_RE='bash' run bash "$s" --round-s 1 --interval-s 1 --max-rounds 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"+/- 0.061"* ]] || false
  [[ "$output" == *"never bare"* ]] || false
  [[ "$output" == *"cc-backlog done 193ae8ddce72"* ]]
}

# ── THE SITE LIST IS RE-GREPPED, NEVER STORED ───────────────────────────────────────────────────

@test "the PASS report re-greps the citation sites and stores no path list" {
  # §6a of the adjudication doc: the stored list of sites was WRONG when written (it named two; a
  # grep returned three, the third being the library that defines the population the coefficient is
  # denominated in). "Re-grep at the PASS, do not work from this table." An edit that replaced the
  # grep with the three known paths would pass every other test in this file and re-create the
  # denylist-of-spellings defect the doc exists to refute.
  grep -q 'grep -rnE' "$R"
  ! grep -qE '^\s*(printf|echo).*capacity-admit\.sh.*agent-teams-enforce\.sh' "$R" || false
  grep -q 'do not work from a stored list' "$R"
}

@test "a bad argument is a usage error, never a silent default" {
  run bash "$R" --round-s 0
  [ "$status" -eq 2 ]
  run bash "$R" --nonsense
  [ "$status" -eq 2 ]
}
