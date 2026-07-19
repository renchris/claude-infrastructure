#!/usr/bin/env bats
# lead-supervisor — the out-of-session (bash) autonomy watchdog. Its own scripts/supervisor-e2e.sh
# RED-proves the PAGE-only routing (DEAD / STALL? / PAST-THRESHOLD / OK), the S-3b re-observe law, the
# S-4 heartbeat, notify damping, AND the clean-completion auto-reap vs stranded-death page discrimination
# (item 9b183d78c723). This wrapper puts that suite into the gated `bats tests/` run — lead-supervisor was
# the one tool whose --selftest nothing gated (its e2e ran only on a manual `--selftest`).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUP="$REPO/scripts/lead-supervisor.sh"
}

@test "supervisor-e2e --selftest is GREEN (0 failed) and runs a non-trivial suite" {
  run bash "$SUP" --selftest
  [ "$status" -eq 0 ]
  # the summary line is the un-fakeable outcome: "N passed, 0 failed"
  echo "$output" | grep -qE 'supervisor-e2e: [0-9]+ passed, 0 failed'
  # guard against a zero-check 'pass' (a suite that silently runs nothing must not read green)
  n_pass="$(echo "$output" | sed -nE 's/.*supervisor-e2e: ([0-9]+) passed.*/\1/p')"
  [ "${n_pass:-0}" -ge 24 ]
}

@test "clean-completion reap + stranded-death page are both exercised (item 9b183d78c723)" {
  run bash "$SUP" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'T11 CLEAN COMPLETION'
  echo "$output" | grep -q 'T12 STRANDED (dirty)'
  echo "$output" | grep -q 'T13 STRANDED (unlanded)'
}

@test "PermissionRequest beacon sweep — page/threshold/reap/damping all exercised (item 08d514250031)" {
  run bash "$SUP" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'T14 PERMISSION-PENDING'
  echo "$output" | grep -q 'T15 THRESHOLD GATE'
  echo "$output" | grep -q 'T16 REAP orphan'
  echo "$output" | grep -q 'T17 REAP dead-pid'
  echo "$output" | grep -q 'T18 DAMPING'
}
