#!/usr/bin/env bats
# cc-cpubound — the per-process CPU-time ceiling behind qos-rewrite transform (c) (backlog
# 2af4c4908422; the 2026-08-02 ugrep that burned 12m48s of CPU on one HTML file with nothing to
# stop it).
#
# WHAT MAKES THESE TESTS NON-VACUOUS. A ceiling test can pass for the wrong reason in two ways, and
# both are pinned here rather than assumed:
#   1. The subject might not actually run away, so ANY wrapper would look like it worked. Every
#      bounding test has a POSITIVE CONTROL that runs the SAME fixture unbounded and proves it is
#      still going. Without that, a subject that exits on its own turns the whole suite green while
#      the mechanism does nothing.
#   2. The limit might never have been APPLIED. `ulimit -H -t N` on a fresh shell is EINVAL (a hard
#      limit below the current soft limit), which fails SILENTLY and leaves both unlimited — the
#      exact trap this script's soft-then-hard order exists to avoid. A test that only checks "the
#      command died" cannot tell an applied ceiling from a subject that crashed, so the order
#      property is asserted directly.
#
# The subject is a pure-bash spin loop: no external binary, so nothing here depends on what is
# reachable on the test PATH. Ceilings are 1-2 seconds to keep the suite fast; the shipped table
# uses 60.

# EVERY probe that runs the spin fixture is itself bounded, and that is not belt-and-braces — it is
# what makes a broken ceiling REPORTABLE. Measured while building this suite: with the ceiling
# mutated out, an unbounded death test does not fail, it HANGS, and the run is killed from outside
# with no per-test verdict at all — `not ok` count 0, which reads exactly like "the mutant was not
# caught" when in truth nothing was ever asserted. A non-verdict is not a pass.
#
# timeout(1) is Homebrew-only on macOS and a tests/*.bats file is on an unattended path, so it may
# never be invoked by bare name at command position (scripts/unattended-path-lint.sh:93-99): resolve
# it absolutely, through the same ladder scripts/lead-supervisor.sh:51-80 uses. If it cannot be
# resolved we SKIP rather than run unbounded — a probe that cannot bound itself declares itself
# unrun instead of risking the hang it exists to prevent.
resolve_timeout() {
  local c
  for c in "$(command -v timeout 2>/dev/null)" "$(command -v gtimeout 2>/dev/null)" \
           /opt/homebrew/bin/timeout /opt/homebrew/bin/gtimeout \
           /usr/local/bin/timeout /usr/local/bin/gtimeout; do
    if [ -n "$c" ] && [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BOUND="$REPO/bin/cc-cpubound"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"      # never read the operator's live ~/
  TMO="$(resolve_timeout)" || TMO=""
  # Comfortably above every ceiling used below, so it only ever fires on a BROKEN ceiling.
  TMO_S=20

  # A subject that burns CPU forever and never blocks — the runaway shape.
  SPIN="$D/spin"
  printf '#!/bin/bash\nwhile :; do :; done\n' > "$SPIN"; chmod +x "$SPIN"

  # A subject that consumes NO cpu but takes wall-clock — the false-positive shape.
  IDLE="$D/idle"
  printf '#!/bin/bash\nsleep "$1"\n' > "$IDLE"; chmod +x "$IDLE"

  # A subject that exits immediately with a chosen status — for status pass-through.
  RC="$D/rc"
  printf '#!/bin/bash\nexit "$1"\n' > "$RC"; chmod +x "$RC"
}

# ── the ceiling fires, and the subject really would have run away ───────────────────────────────
@test "a CPU-burning command is stopped at the ceiling with rc 152 (SIGXCPU)" {
  [ -n "$TMO" ] || skip "no timeout(1) resolvable — cannot bound this probe"
  run "$TMO" "$TMO_S" "$BOUND" 1 "$SPIN"
  # 152 = the ceiling fired. 124 would mean OUR bound fired instead, i.e. the ceiling did not —
  # a failing verdict, which is the whole point of bounding this probe.
  [ "$status" -eq 152 ]
}

# THE POSITIVE CONTROL for the test above. If this ever stops timing out, the spin fixture has
# stopped being a runaway and every bounding assertion in this file has gone vacuous.
@test "positive control: the SAME fixture is genuinely unbounded without the wrapper" {
  [ -n "$TMO" ] || skip "no timeout(1) resolvable — cannot bound this probe"
  run "$TMO" 4 "$SPIN"
  [ "$status" -eq 124 ]      # 124 = our timeout fired, i.e. it was still running
}

# ── the false-positive property: it bounds COMPUTE, not patience ────────────────────────────────
# This is the whole reason the mechanism is a CPU ceiling and not a wall clock. A command that is
# slow because it WAITS must survive a ceiling far below its wall time.
@test "a command that sleeps well past the ceiling is NOT stopped" {
  run "$BOUND" 1 "$IDLE" 3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── the verdict: the only consumer is an agent BLOCKED on this very call ────────────────────────
@test "the ceiling verdict is emitted on stderr, parseable, naming the limit" {
  [ -n "$TMO" ] || skip "no timeout(1) resolvable — cannot bound this probe"
  run "$TMO" "$TMO_S" "$BOUND" 1 "$SPIN"
  [ "$status" -eq 152 ] || false
  [[ "$output" == *"verdict=cpu-ceiling-exceeded"* ]] || false
  [[ "$output" == *"limit_cpu_s=1"* ]] || false
  [[ "$output" == *"rc=152"* ]]
}

@test "a command that exits normally produces NO verdict — the guard is silent when it does nothing" {
  run "$BOUND" 5 "$RC" 0
  [ "$status" -eq 0 ] || false
  [[ "$output" != *"verdict="* ]]
}

# ── status pass-through: the wrapper must be transparent to everything but its own ceiling ──────
@test "a non-zero exit status from the command is passed through verbatim" {
  run "$BOUND" 5 "$RC" 3
  [ "$status" -eq 3 ] || false
  [[ "$output" != *"verdict="* ]]
}

@test "stdout passes through untouched" {
  ECHOER="$D/echoer"
  printf '#!/bin/bash\nprintf %%s "marker-stdout"\n' > "$ECHOER"; chmod +x "$ECHOER"
  run "$BOUND" 5 "$ECHOER"
  [ "$status" -eq 0 ] || false
  [ "$output" = "marker-stdout" ]
}

@test "stdin is not consumed by the wrapper — it reaches the command" {
  CAT="$D/catter"
  printf '#!/bin/bash\ncat\n' > "$CAT"; chmod +x "$CAT"
  result="$(printf 'marker-stdin' | "$BOUND" 5 "$CAT")"
  [ "$result" = "marker-stdin" ]
}

# ── the ORDER property: soft BEFORE hard, or the ceiling silently does not exist ─────────────────
# Asserted from inside the wrapper's own process so it reads the limit that was actually applied,
# not one we hope was. A regression to hard-first would leave this "unlimited" while every death
# test above still passed for other reasons.
@test "the soft ceiling is really applied to the child (not silently refused)" {
  READER="$D/reader"
  printf '#!/bin/bash\nulimit -S -t\n' > "$READER"; chmod +x "$READER"
  run "$BOUND" 7 "$READER"
  [ "$status" -eq 0 ] || false
  [ "$output" = "7" ]
}

@test "the hard ceiling sits above the soft one, leaving a grace window" {
  READER="$D/hreader"
  printf '#!/bin/bash\nulimit -H -t\n' > "$READER"; chmod +x "$READER"
  CC_CPUBOUND_GRACE_S=4 run "$BOUND" 7 "$READER"
  [ "$status" -eq 0 ] || false
  [ "$output" = "11" ]
}

# ── fail-open: a guard that breaks a working command is worse than the runaway ───────────────────
@test "a non-numeric ceiling runs the command UNBOUNDED rather than refusing it" {
  run "$BOUND" abc "$RC" 0
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=bad-limit"* ]]
}

@test "a zero ceiling runs the command UNBOUNDED rather than bounding it to nothing" {
  run "$BOUND" 0 "$RC" 0
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=bad-limit"* ]]
}

# The fail-open control: a bad ceiling must not merely avoid killing the command, it must leave the
# command genuinely unbounded. Same spin fixture, bad ceiling, still running when our timeout fires.
@test "fail-open control: with a bad ceiling the runaway really is left unbounded" {
  [ -n "$TMO" ] || skip "no timeout(1) resolvable — cannot bound this probe"
  run "$TMO" 4 "$BOUND" abc "$SPIN"
  [ "$status" -eq 124 ]
}

@test "fewer than two arguments is a usage error (exit 2), never a silent pass" {
  run "$BOUND" 5
  [ "$status" -eq 2 ] || false
  run "$BOUND"
  [ "$status" -eq 2 ]
}
