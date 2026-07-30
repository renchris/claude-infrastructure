#!/usr/bin/env bats
# lead-supervisor — the out-of-session (bash) autonomy watchdog. Its own scripts/supervisor-e2e.sh
# RED-proves the PAGE-only routing (DEAD / STALL? / PAST-THRESHOLD / OK), the S-3b re-observe law, the
# S-4 heartbeat, notify damping, AND the clean-completion auto-reap vs stranded-death page discrimination
# (item 9b183d78c723). This wrapper puts that suite into the gated `bats tests/` run — lead-supervisor was
# the one tool whose --selftest nothing gated (its e2e ran only on a manual `--selftest`).

# The e2e is ONE ~15s run of the same 36-check suite; every @test below only greps a different string
# out of its output. Running it per-test cost 5× the wall-clock AND 5× the flake exposure (each run
# spawns real processes + touches real clocks). setup_file runs it ONCE and caches output+status; the
# tests assert on the cache. Bats runs setup_file once per FILE, before any test in it.
setup_file() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUP="$REPO/scripts/lead-supervisor.sh"
  # $BATS_FILE_TMPDIR is created by bats before setup_file and survives for every test in the file.
  export E2E_OUT="$BATS_FILE_TMPDIR/e2e.out"
  export E2E_STATUS="$BATS_FILE_TMPDIR/e2e.status"
  local st=0
  bash "$SUP" --selftest > "$E2E_OUT" 2>&1 || st=$?
  printf '%s\n' "$st" > "$E2E_STATUS"
}

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUP="$REPO/scripts/lead-supervisor.sh"
  status="$(cat "$E2E_STATUS")"     # the cached exit code of the single e2e run
  output="$(cat "$E2E_OUT")"        # ...and its combined stdout+stderr
}

@test "supervisor-e2e --selftest is GREEN (0 failed) and runs a non-trivial suite" {
  [ "$status" -eq 0 ]
  # the summary line is the un-fakeable outcome: "N passed, 0 failed"
  echo "$output" | grep -qE 'supervisor-e2e: [0-9]+ passed, 0 failed'
  # guard against a zero-check 'pass' (a suite that silently runs nothing must not read green).
  # RATCHET: raised 36 → 74 with T30 (bounded externals). The floor is the whole point — a refactor that
  # silently drops checks must fail here rather than read green on a shrunken suite.
  # T30's 9 checks need a real timeout(1); where the box has none it SKIPs wholesale, so the floor drops
  # to 65 for that case only. Deriving the floor from the skip line (rather than pinning the lower number
  # everywhere) keeps the ratchet at full strength on every box that can actually run the checks.
  floor=74
  if echo "$output" | grep -q 'SKIP T30'; then floor=65; fi
  n_pass="$(echo "$output" | sed -nE 's/.*supervisor-e2e: ([0-9]+) passed.*/\1/p')"
  [ "${n_pass:-0}" -ge "$floor" ]
}

@test "clean-completion reap + stranded-death page are both exercised (item 9b183d78c723)" {
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'T11 CLEAN COMPLETION'
  echo "$output" | grep -q 'T12 STRANDED (dirty)'
  echo "$output" | grep -q 'T13 STRANDED (unlanded)'
}

@test "PermissionRequest beacon sweep — page/threshold/reap/damping all exercised (item 08d514250031)" {
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'T14 PERMISSION-PENDING'
  echo "$output" | grep -q 'T15 THRESHOLD GATE'
  echo "$output" | grep -q 'T16 REAP orphan'
  echo "$output" | grep -q 'T17 REAP dead-pid'
  echo "$output" | grep -q 'T18 DAMPING'
}

@test "same-sweep guard: a page created this sweep is never same-sweep resolved (second-boundary race, 2026-07-25 flaky-gate incident)" {
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'T22b SAME-SWEEP GUARD'
}

@test "registered-desk STALL? exemption — role=sid, role=pane→registry, desk-specific, dead-still-DEAD (item ff95faea46c8)" {
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'T23 REGISTERED-DESK EXEMPTION (role=sid)'
  echo "$output" | grep -q 'T24 REGISTERED-DESK EXEMPTION (role=pane→registry)'
  echo "$output" | grep -q 'T25 EXEMPTION IS DESK-SPECIFIC'
  echo "$output" | grep -q 'T26 DEAD DESK'
}

@test "T29: a cc-notify-REFUSED page is IDL-loud and retried, never damping-marked (comms truthfulness)" {
  run bash "$SUP" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'T29 SEND-RC HONORED'
  echo "$output" | grep -q 'refused send leaves NO damping marker'
  echo "$output" | grep -q 'refused send is IDL-recorded'
  echo "$output" | grep -q 'refused page RETRIED on the next sweep'
}

@test "T30: a hung external fork does not end supervision — bounded git/find + the INDETERMINATE third state" {
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'T30 BOUNDED EXTERNALS'
  # A SKIP is legitimate only where the box genuinely has no timeout(1) (the subject then degrades to
  # unbounded BY DESIGN). Anywhere else the assertions below must have actually run — a silently-skipped
  # T30 would read green while proving nothing, so the skip line is accepted only in place of the rest.
  if echo "$output" | grep -q 'SKIP T30'; then skip "no timeout(1) on this box — subject is unbounded by design"; fi
  # the S1 itself: the sweep completes, and its S-4 heartbeat proves it completed rather than died quiet
  echo "$output" | grep -q 'sweep COMPLETES with a hung git'
  echo "$output" | grep -q 'S-4 heartbeat still written despite the hung git'
  echo "$output" | grep -q 'sweep COMPLETES with a hung find'
  # a cut probe is neither fresh nor dark: no escalation, no laundering, and a durable non-verdict record
  echo "$output" | grep -q 'records the INDETERMINATE non-verdict'
  echo "$output" | grep -q 'cut re-read does NOT escalate'
  echo "$output" | grep -q 'not laundered as fresh'
  # an unprovable landed-check must never reap, and a MISSING timeout(1) must not break the call
  echo "$output" | grep -q 'no false clean-completion reap'
  echo "$output" | grep -q 'run UNBOUNDED, not broken'
}
