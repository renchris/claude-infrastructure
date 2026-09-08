#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329,SC2317
# SC2317/SC2329: bats invokes each @test body through the runner, so the linter reads them as dead
# code. File-level, because it is a property of the harness rather than of any single line.
# (NB: no comment line here may BEGIN with the linter's own name — it parses as a directive.)
#
# ONE CENSUS, TWO CONSUMERS (backlog c4383f1c9172).
#
# capacity-alarm.sh census() and scripts/lib/spawn-presence.sh were two copies of one awk program,
# and they DIVERGED in the direction copies always do: the `rows` positive control — the guard that
# turns an unreadable process table into a refusal instead of a well-formed "0 0 0" that reads as an
# idle box — was added to the lib and not to capacity-alarm. Behaviour tests alone cannot keep that
# from happening again, because a re-inlined copy passes every one of them on the day it is written.
# So this suite asserts the STRUCTURE (there is exactly one body) and the WIRING (the consumer reads
# that body's output), not just the current answer.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CA="$REPO/scripts/capacity-alarm.sh"
  LIB="$REPO/scripts/lib/spawn-presence.sh"
  D="$BATS_TEST_TMPDIR"

  # Lift census() out of capacity-alarm.sh into a standalone file, so it can be exercised without
  # running the alarm. Sourced from $1/, its BASH_SOURCE dirname is $1 — which is exactly how it
  # resolves lib/spawn-presence.sh, so a fake lib under $1/lib is the seam.
  lift_census() {
    local into="$1"
    mkdir -p "$into/lib"
    sed -n '/^census() {/,/^}/p' "$CA" > "$into/census.sh"
    [ -s "$into/census.sh" ] || return 1
    grep -q 'cc_sp_census' "$into/census.sh" || return 1
  }
}

@test "there is exactly ONE census body in the tree, and it is in the lib" {
  # The awk's family classification is the body's fingerprint. Two matches means a copy came back.
  n="$(grep -rlF 'node_modules\/\.bin\/claude$' "$REPO/scripts" "$REPO/bin" "$REPO/hooks" 2>/dev/null \
        | xargs grep -lF 'ps -eo pid=,ppid=,args=' 2>/dev/null | sort -u | wc -l | tr -d ' ')"
  if [ "${n:-0}" -ne 1 ]; then
    echo "expected exactly 1 file carrying the census body; found $n:" >&2
    grep -rlF 'node_modules\/\.bin\/claude$' "$REPO/scripts" "$REPO/bin" "$REPO/hooks" 2>/dev/null \
      | xargs grep -lF 'ps -eo pid=,ppid=,args=' 2>/dev/null | sort -u >&2
    return 1
  fi
  grep -qF 'ps -eo pid=,ppid=,args=' "$LIB"
}

@test "capacity-alarm's census READS the lib's answer (delegation, not a copy)" {
  lift_census "$D/deleg"
  # A fake lib whose census answers something no real box would produce, so a passing assertion
  # cannot be explained by the two implementations happening to agree.
  printf 'cc_sp_census() { printf "%%s" "7 3 4"; }\n' > "$D/deleg/lib/spawn-presence.sh"
  run bash -c ". '$D/deleg/census.sh'; census"
  [ "$status" -eq 0 ]
  [ "$output" = "7 3 4" ] || { echo "got '$output' — census is not reading the lib" >&2; return 1; }
}

@test "an unreadable lib is a REFUSAL, never a well-formed zero" {
  lift_census "$D/norlib"
  rm -f "$D/norlib/lib/spawn-presence.sh"
  run bash -c ". '$D/norlib/census.sh'; census"
  [ "$status" -ne 0 ]
  # "0 0 0" here is the exact defect this extraction exists to make unrepeatable: it is
  # indistinguishable at every consumer from a genuinely idle box.
  [ -z "$output" ] || { echo "refusal printed '$output'; a triple over no measurement is the bug" >&2; return 1; }
}

@test "the lib's census refuses (rc 1) when the process table reads empty" {
  # The positive control on the denominator, asserted at its new single home. `ps` stubbed to print
  # nothing models a dead probe / exec-deny / sandbox — a live box always has processes.
  mkdir -p "$D/binstub"
  printf '#!/bin/sh\nexit 0\n' > "$D/binstub/ps"; chmod +x "$D/binstub/ps"
  run bash -c "PATH='$D/binstub:\$PATH'; . '$LIB'; cc_sp_census"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "cc_sp_trees is field 1 of the same census — the two cannot disagree" {
  run bash -c ". '$LIB'; c=\"\$(cc_sp_census)\" || exit 9; t=\"\$(cc_sp_trees)\" || exit 9; set -- \$c; [ \"\$1\" = \"\$t\" ] || { echo \"census=\$c trees=\$t\"; exit 1; }"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "NON-VACUITY: the delegation seam is real — a stub the census ignores fails the suite" {
  # Control for case 2. If census() had kept its own body, the fake lib above would be ignored and
  # the assertion would read the REAL box instead. Prove the seam by showing a second, different
  # stub value also comes through: a hardcoded copy cannot track two different answers.
  lift_census "$D/deleg2"
  printf 'cc_sp_census() { printf "%%s" "1 1 0"; }\n' > "$D/deleg2/lib/spawn-presence.sh"
  run bash -c ". '$D/deleg2/census.sh'; census"
  [ "$status" -eq 0 ]
  [ "$output" = "1 1 0" ] || { echo "got '$output'" >&2; return 1; }
}
