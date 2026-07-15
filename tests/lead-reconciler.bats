#!/usr/bin/env bats
# L4 — lead-reconciler: three-way anti-entropy reconciler. The tool's own --selftest RED-proves
# L4-a/b/c + the declared blindness; these bats add CLI-level regression on the --once path with
# env-injected rosters (independent of the selftest harness).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  REC="$REPO/scripts/lead-reconciler.sh"
  export CC_RECON_DIR="$BATS_TEST_TMPDIR/state"
  printf '#!/bin/bash\nprintf "%%s\\n" "$2" >> "%s/pages.log"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/page"
  chmod +x "$BATS_TEST_TMPDIR/page"
  export CC_WAIT_PAGE_CMD="$BATS_TEST_TMPDIR/page"
  # tasks list pid 4242 (the incident shape); registry + disk do NOT — a real divergence.
  export CC_RECON_ROSTER_TASKS='echo 4242; echo 100'
  export CC_RECON_ROSTER_REGISTRY='echo 100'
  export CC_RECON_ROSTER_DISK='echo 100'
}

@test "selftest passes and runs all 5 checks (a zero-check suite must not 'pass')" {
  run "$REC" --selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 5 ]
}

@test "L4-a: a persistent divergence (grace 0) pages an alarm that NAMES the pair" {
  CC_RECON_GRACE_S=0 run "$REC" --once
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/pages.log" ]
  grep -q 'tasks-x-registry' "$BATS_TEST_TMPDIR/pages.log"
  grep -q '4242' "$BATS_TEST_TMPDIR/pages.log"
}

@test "L4-b: a just-appeared divergence within grace does NOT alarm, but IS state-tracked" {
  CC_RECON_GRACE_S=9999 run "$REC" --once
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/pages.log" ]            # no alarm (anti-cry-wolf)
  ls "$CC_RECON_DIR"/div-tasks-x-registry-4242.json # but the divergence IS tracked for persistence
}

@test "L4-c: every reconcile pass writes the reconciler's own heartbeat" {
  CC_RECON_GRACE_S=60 run "$REC" --once
  [ "$status" -eq 0 ]
  [ -f "$CC_RECON_DIR/heartbeat.json" ]
  [ "$(jq -r '.kind' "$CC_RECON_DIR/heartbeat.json")" = "reconciler-heartbeat" ]
}

@test "L4-blind: when all three rosters agree, no alarm fires (the declared coherent-wrong blindness)" {
  export CC_RECON_ROSTER_TASKS='echo 7; echo 8'
  export CC_RECON_ROSTER_REGISTRY='echo 7; echo 8'
  export CC_RECON_ROSTER_DISK='echo 7; echo 8'
  CC_RECON_GRACE_S=0 run "$REC" --once
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/pages.log" ]
}
