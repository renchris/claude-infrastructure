#!/usr/bin/env bats
# capacity-marginal-run — the driver that turns §6 of
# docs/research/marginal-load-per-active-session-2026-08-19.md from a worksheet into a program
# (backlog 193ae8ddce72).
#
# WHAT THIS SUITE IS FOR. The driver's whole contract is WHEN TO STOP ASKING, and it must not be
# able to manufacture an answer while doing it. So the suite pins two things and nothing else:
# (1) the three stop conditions §6 names, each reached for its own reason, and (2) the negative
# property that a refusal never leaks a quotable number — the same property `capacity-marginal.bats`
# pins for the instrument, re-asserted at the layer above it, because a driver that summarised its
# rounds would be a fifth published value.
#
# WHY A FAKE SAMPLER. The subject is the LOOP, not the census. Driving the real sampler would make
# the suite a function of how busy the box is — the one input a gate corpus may never depend on —
# and would take an hour per test. The fake records the argv it was called with, so the tests can
# also assert the WINDOWS the driver asked for, which is the half of the protocol the exit code
# cannot show.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  R="$REPO/scripts/capacity-marginal-run.sh"
  D="$BATS_TEST_TMPDIR"
  # Hermetic HOME: the driver itself writes nothing there, but it execs the sampler, which sources
  # spawn-presence.sh and reads the operator's beat directory. A probe must never see the live fleet.
  export HOME="$D/home"; mkdir -p "$HOME/.claude"
  export FAKE_LOG="$D/argv.log"; export FAKE_PLAN="$D/plan"; export FAKE_ROUND="$D/round"
  : > "$FAKE_LOG"; printf '0\n' > "$FAKE_ROUND"

  # The fake sampler. `sample` records its argv and returns instantly; `analyze` serves the verdict
  # this round's plan line names. The round advances on the TEXT call only, because the driver asks
  # for text then json and both must describe the same window.
  cat > "$D/fake.sh" <<'FAKE'
#!/bin/bash
case "$1" in
  sample)
    printf '%s\n' "$*" >> "$FAKE_LOG"
    [ -z "${FAKE_SLEEP:-}" ] || sleep "$FAKE_SLEEP"
    exit 0 ;;
  analyze)
    json=""; for a in "$@"; do [ "$a" = "--json" ] && json=1; done
    n="$(cat "$FAKE_ROUND")"
    [ -n "$json" ] || { n=$(( n + 1 )); printf '%s\n' "$n" > "$FAKE_ROUND"; }
    # The plan CYCLES, so a test can describe a signature that never settles without writing an
    # infinite file; a one-line plan therefore repeats that line, as the simple cases expect.
    lines="$(grep -c . "$FAKE_PLAN")"
    line="$(sed -n "$(( (n - 1) % lines + 1 ))p" "$FAKE_PLAN")"
    case "$line" in
      pass)
        if [ -n "$json" ]; then printf '{"c1_level":true,"c2_dynamics":true,"c3_identify":true,"verdict":"MARGINAL","marginal_load_per_active_session":0.3330,"se":0.0410}\n'
        else printf 'CAPACITY-MARGINAL  n=60\n  C1 LEVEL      PASS  ok\n  C2 DYNAMICS   PASS  ok\n  C3 IDENTIFY   PASS  ok\nVERDICT: MARGINAL 0.333 load units per ACTIVE session  (+/- 0.041, 1 s.e.)\n'; fi
        exit 0 ;;
      nodata)
        printf 'CAPACITY-MARGINAL: NO-DATA\n'; exit 3 ;;
      refuse:*)
        f="${line#refuse:}"   # which controls FAILED this round, e.g. c2 or c1c2
        c1=true; c2=true; c3=true
        case "$f" in *c1*) c1=false ;; esac
        case "$f" in *c2*) c2=false ;; esac
        case "$f" in *c3*) c3=false ;; esac
        if [ -n "$json" ]; then printf '{"c1_level":%s,"c2_dynamics":%s,"c3_identify":%s,"verdict":"NO-ATTRIBUTION"}\n' "$c1" "$c2" "$c3"
        else printf 'CAPACITY-MARGINAL  n=30\n  C1 LEVEL      %s\n  C2 DYNAMICS   %s\n  C3 IDENTIFY   %s\nVERDICT: NO-ATTRIBUTION — a control failed; no coefficient is quotable from this window.\n  (the fit that WOULD have been reported: 0.412 load units per ACTIVE session — withheld)\n' \
          "$([ $c1 = true ] && echo PASS || echo FAIL)" "$([ $c2 = true ] && echo PASS || echo FAIL)" "$([ $c3 = true ] && echo PASS || echo FAIL)"; fi
        exit 1 ;;
    esac ;;
esac
exit 2
FAKE
  chmod +x "$D/fake.sh"
  export CC_MARGRUN_BIN="$D/fake.sh"
}

# Every round is a no-op in the fake, so the windows are nominal and the suite runs in milliseconds.
run_driver() { run bash "$R" --out "$D/s.tsv" --first-s 60 --extend-s 60 --interval-s 60 --quiet "$@"; }

# ── THE THREE STOP CONDITIONS ───────────────────────────────────────────────────────────────────

@test "PASS stops on the first passing window and reports the coefficient" {
  printf 'pass\n' > "$FAKE_PLAN"
  run_driver --max-s 600
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: MARGINAL 0.333"* ]] || false
  [[ "$output" == *"RUN: PASS after 1 round(s)"* ]] || false
  [ "$(grep -c . "$FAKE_LOG")" -eq 1 ]
}

@test "SETTLED-REFUSAL: the same control refusing N rounds running is the stop, not a hang" {
  # §6: "or the refusal repeats with the same term across several windows — which would itself be
  # the finding." Three identical C2 refusals with --settle 3 must stop at round 3, not at the cap.
  printf 'refuse:c2\n' > "$FAKE_PLAN"
  run_driver --max-s 600 --settle 3
  [ "$status" -eq 1 ]
  [[ "$output" == *"RUN: SETTLED-REFUSAL after 3 round(s)"* ]] || false
  [[ "$output" == *"§7 thread-unit is the next increment"* ]] || false
  [ "$(grep -c . "$FAKE_LOG")" -eq 3 ]
}

@test "a MOVING signature does not settle — it keeps extending until the cap" {
  # The stop is "the SAME term", not "a refusal". A window whose failing control keeps changing is
  # still converging, and stopping there would report a settled finding that never settled.
  printf 'refuse:c1\nrefuse:c2\nrefuse:c3\n' > "$FAKE_PLAN"
  FAKE_SLEEP=1 run_driver --max-s 2 --settle 3
  [ "$status" -eq 1 ]
  [[ "$output" == *"RUN: UNSETTLED"* ]] || false
  [[ "$output" == *"Re-run with the same --out to extend"* ]]
}

@test "NO-DATA propagates as 3 — an unreadable box is not a refusal" {
  printf 'nodata\n' > "$FAKE_PLAN"
  run_driver --max-s 600
  [ "$status" -eq 3 ]
  [[ "$output" == *"RUN: NO-DATA"* ]]
}

# ── THE DRIVER MAY NEVER MANUFACTURE AN ANSWER ──────────────────────────────────────────────────

@test "no quotable number survives a refusal, in stdout or in the artifact" {
  # The instrument's own suite pins this for one window; a driver that pooled rounds would be a
  # fifth published value. The withheld fit must stay labelled withheld and MARGINAL must be absent.
  printf 'refuse:c2\n' > "$FAKE_PLAN"
  run_driver --max-s 600 --settle 2 --artifact-dir "$D/art"
  [ "$status" -eq 1 ]
  [[ "$output" != *"VERDICT: MARGINAL"* ]] || false
  [[ "$output" == *"withheld"* ]] || false
  run grep -c 'VERDICT: MARGINAL' "$D/art/marginal.txt"
  [ "$output" -eq 0 ]
}

@test "the driver computes nothing: it has no arithmetic on the coefficient" {
  # The verdict, the controls and the number all come from `analyze` unmodified. A second
  # implementation of the arithmetic is a second thing to keep true — and the item exists because
  # this repo already had four numbers from instruments nobody controlled.
  run grep -nE 'marginal_load_per_active_session|slope|corr' "$R"
  [ "$status" -ne 0 ]
}

# ── THE PROTOCOL IT ASKS FOR ────────────────────────────────────────────────────────────────────

@test "round 1 uses --first-s and later rounds use --extend-s" {
  printf 'refuse:c2\n' > "$FAKE_PLAN"
  run bash "$R" --out "$D/s.tsv" --first-s 3600 --extend-s 1800 --interval-s 60 --max-s 99999 --settle 2 --quiet
  [ "$status" -eq 1 ]
  [[ "$(sed -n 1p "$FAKE_LOG")" == *"--window-s 3600"* ]] || false
  [[ "$(sed -n 2p "$FAKE_LOG")" == *"--window-s 1800"* ]]
}

@test "--max-s is a deadline: the last window is truncated, never overrun" {
  # A cap that only gates the NEXT round lets a 30-minute extension run 29 minutes past a 1-minute
  # budget. The remaining budget, not the nominal window, is what the last round may spend.
  printf 'refuse:c1\nrefuse:c2\n' > "$FAKE_PLAN"
  run bash "$R" --out "$D/s.tsv" --first-s 99999 --extend-s 99999 --interval-s 60 --max-s 7 --settle 9 --quiet
  [ "$status" -eq 1 ]
  w="$(sed -n 1p "$FAKE_LOG" | sed -E 's/.*--window-s ([0-9]+).*/\1/')"
  [ "$w" -le 7 ]
}

@test "the artifact records the BOX, because a marginal is a property of a machine" {
  printf 'pass\n' > "$FAKE_PLAN"
  run_driver --max-s 600 --artifact-dir "$D/art"
  [ "$status" -eq 0 ]
  [ -s "$D/art/marginal.txt" ]
  [ -s "$D/art/marginal.json" ]
  run grep -E '"ncpu":[0-9]+' "$D/art/marginal.json"
  [ "$status" -eq 0 ]
  run grep -E '"stop":"PASS"' "$D/art/marginal.json"
  [ "$status" -eq 0 ]
}

# ── USAGE ───────────────────────────────────────────────────────────────────────────────────────

@test "a bad knob is a usage error, not a busy loop" {
  printf 'pass\n' > "$FAKE_PLAN"
  run bash "$R" --settle 0 --quiet
  [ "$status" -eq 2 ]
  run bash "$R" --interval-s x --quiet
  [ "$status" -eq 2 ]
  run bash "$R" --nonsense
  [ "$status" -eq 2 ]
}

@test "an unreadable sampler is refused up front, not discovered mid-window" {
  printf 'pass\n' > "$FAKE_PLAN"
  CC_MARGRUN_BIN="$D/does-not-exist.sh" run bash "$R" --quiet
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot read sampler"* ]]
}
