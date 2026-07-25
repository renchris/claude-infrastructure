#!/usr/bin/env bats
# growth-coverage-lint — the missing DUAL of reaper-horizon-lint (audit 03 §3, fix 9).
#
# reaper-horizon-lint fails when a reaper deletes evidence too soon. Nothing failed when a state
# dir had NO reaper at all — which is how autonomy/comms-alarms reached 395 files with zero rm
# sites of any kind. This gate is the ceiling.
#
# Harness laws: L1 the fixture root is a real directory tree and a real conf file, driven through
# the real script; L2 every assertion is failure-distinct (the unclassified dir FAILS, and the
# same dir once classified PASSES — so neither "always fail" nor "always pass" survives); L3
# `[ ]` / `grep -q` only; L4 the fail-closed path (unreadable SSOT) is tested, because a lint that
# reports health when it cannot read its own list is worse than no lint.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/growth-coverage-lint.sh"
  export GROWTH_ROOT="$BATS_TEST_TMPDIR/root"
  export GROWTH_COVERAGE_SSOT="$BATS_TEST_TMPDIR/ssot.conf"
  mkdir -p "$GROWTH_ROOT"
  : > "$GROWTH_COVERAGE_SSOT"
}

# ── the class-stopper ──────────────────────────────────────────────────────────────────────────
@test "a state dir on disk with NO row fails the gate" {
  mkdir -p "$GROWTH_ROOT/brand-new-event-dir"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "UNCLASSIFIED"
  echo "$output" | grep -q "brand-new-event-dir"
}

@test "classifying that same dir clears the gate" {
  mkdir -p "$GROWTH_ROOT/brand-new-event-dir"
  echo 'brand-new-event-dir ignore=fixture' > "$GROWTH_COVERAGE_SSOT"
  run bash "$LINT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "clean"
}

@test "a new dir under autonomy/ is caught too (the dir family that started this)" {
  mkdir -p "$GROWTH_ROOT/autonomy/new-alarms"
  echo 'autonomy ignore=container' > "$GROWTH_COVERAGE_SSOT"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "autonomy/new-alarms"
}

@test "a new append-only log beside the roots is caught" {
  : > "$GROWTH_ROOT/some-new.log"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "some-new.log"
}

# ── reaper claims must resolve in the source ───────────────────────────────────────────────────
@test "a row claiming a reaper that does not exist in the source fails" {
  mkdir -p "$GROWTH_ROOT/covered"
  # assembled so this test file cannot itself satisfy the grep
  echo "covered reaper=totally-$(printf '%s' missing)-reaper.sh" > "$GROWTH_COVERAGE_SSOT"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "renamed or deleted"
}

@test "a row naming a reaper that DOES exist passes" {
  mkdir -p "$GROWTH_ROOT/covered"
  echo 'covered reaper=prune-backups.sh' > "$GROWTH_COVERAGE_SSOT"
  run bash "$LINT"
  [ "$status" -eq 0 ]
}

# ── declaration hygiene ────────────────────────────────────────────────────────────────────────
@test "unbounded-by-design with no reason fails (the reason IS the deliverable)" {
  mkdir -p "$GROWTH_ROOT/ledger"
  echo 'ledger unbounded-by-design=' > "$GROWTH_COVERAGE_SSOT"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "empty value"
}

@test "an unknown disposition verb fails" {
  mkdir -p "$GROWTH_ROOT/thing"
  echo 'thing whatever=sure' > "$GROWTH_COVERAGE_SSOT"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "unknown disposition"
}

@test "a row with no verb at all fails" {
  mkdir -p "$GROWTH_ROOT/thing"
  echo 'thing' > "$GROWTH_COVERAGE_SSOT"
  run bash "$LINT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "malformed row"
}

# ── gaps are visible, not fatal — unless --strict ──────────────────────────────────────────────
@test "a declared gap warns but stays green; --strict makes it fail" {
  mkdir -p "$GROWTH_ROOT/uncovered"
  echo 'uncovered gap=audit-03-fix-10' > "$GROWTH_COVERAGE_SSOT"
  run bash "$LINT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "GAP uncovered"
  run bash "$LINT" --strict
  [ "$status" -eq 1 ]
}

@test "a row for a path that no longer exists warns without failing" {
  echo 'long-gone ignore=fixture' > "$GROWTH_COVERAGE_SSOT"
  run bash "$LINT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "stale row"
}

# ── fail-closed ────────────────────────────────────────────────────────────────────────────────
@test "an unreadable SSOT exits 2 and never reports health" {
  rm -f "$GROWTH_COVERAGE_SSOT"
  run bash "$LINT"
  [ "$status" -eq 2 ]
  ! echo "$output" | grep -q "clean"
}

# ── the shipped SSOT must describe the real live layer ─────────────────────────────────────────
@test "the checked-in SSOT is green against the LIVE layer" {
  run env -u GROWTH_ROOT -u GROWTH_COVERAGE_SSOT bash "$LINT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "0 unclassified"
}

@test "--selftest proves each failure mode fires, and nightly picks it up by name" {
  run env -u GROWTH_ROOT -u GROWTH_COVERAGE_SSOT bash "$LINT" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "an unclassified dir fails the gate"
  echo "$output" | grep -q "a dangling reaper claim fails the gate"
  echo "$output" | grep -q "a missing SSOT fails closed"
  # scripts/*lint*.sh is the nightly glob; --selftest support is how nightly invokes it
  case "$(basename "$LINT")" in *lint*.sh) : ;; *) false ;; esac
  grep -q -- '--selftest' "$LINT"
}

# ── every audit-named surface is present in the shipped SSOT ───────────────────────────────────
@test "the SSOT carries the audit's own inventory, with the four ledgers unbounded-by-design" {
  local conf="$REPO/scripts/growth-coverage.conf"
  grep -qE '^autonomy/decisions +unbounded-by-design=' "$conf"
  grep -qE '^autonomy/backlog\.jsonl +unbounded-by-design=' "$conf"
  grep -qE '^history\.jsonl +unbounded-by-design=' "$conf"
  grep -qE '^archives +unbounded-by-design=' "$conf"
  # and the six dirs this branch just gave a reaper name theirs
  grep -qE '^autonomy/pages +reaper=' "$conf"
  grep -qE '^autonomy/comms-alarms +reaper=' "$conf"
  grep -qE '^autonomy/push-records +reaper=' "$conf"
  grep -qE '^completion-push +reaper=' "$conf"
  grep -qE '^cc-teardown +reaper=' "$conf"
  grep -qE '^autonomy/inbox-guard +reaper=' "$conf"
}
