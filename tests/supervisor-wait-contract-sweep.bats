#!/usr/bin/env bats
# G-P4-2 (desk-audit 2026-07-18, still OPEN) — the L2-c wait-contract WATCHDOG had no scheduled caller.
#
# `scripts/wait-contract-lint.sh --sweep` is the only organ that enforces a wait contract INDEPENDENT
# of the waiter's own liveness: it scans the contracts dir on DISK, uses {pid,start-time} identity so a
# recycled pid cannot fake liveness, and pages a dead-waiter / past-deadline divergence page-once. Its
# own --selftest is 13/13 GREEN. Nothing ever ran it: `grep -rn wait-contract-lint` found the script,
# its bats suite, one comment in bin/cc-wait, and docs — no supervisor call, no launchd plist.
#
# 🚨 The obvious exoneration is FALSE and must not be re-derived: "0 OPEN-dead contracts on disk, so the
# sweep must be working". SATISFIED / TIMED_OUT are written by bin/cc-wait's own close_contract at
# block-end — closure is PRODUCER-side. The sweep only PAGES and MARKS; it never closes anything. So a
# clean contracts dir is the consumer self-closing, and says nothing about the watchdog, which has never
# fired in production at all.
#
# These are BEHAVIOURAL cases, not greps: they fabricate a contract on disk, run one real supervisor
# sweep (`--once`, every write seam redirected into BATS_TEST_TMPDIR), and read what the sweep did to
# the contract file and to the page stub. A structural grep for the call site would pass the moment the
# string appeared, whether or not a divergence was ever detected.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SUP="$REPO/scripts/lead-supervisor.sh"
  [ -f "$SUP" ] || skip "lead-supervisor.sh not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  # every write seam of the supervisor points inside the test tmpdir — a sweep run by the suite must
  # never touch the live fleet's telemetry, pages, IDL or contracts.
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel";       mkdir -p "$CC_TELEMETRY_DIR"
  export CC_PERMPEND_DIR="$BATS_TEST_TMPDIR/permpend";   mkdir -p "$CC_PERMPEND_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry";   mkdir -p "$CC_REGISTRY_DIR"
  export CC_SUPERVISOR_PAGEDIR="$BATS_TEST_TMPDIR/pages"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_SUPERVISOR_LOG="$BATS_TEST_TMPDIR/sup.log"
  export CC_PAGE_TO_FILE=/dev/null          # no role file ⇒ the supervisor's own pager has no channel
  export CC_SUP_OS_CHANNEL=off              # and no Notification Center post from a test run
  export CC_SUP_SELFCHECK_MIN_PERSIST=99    # the telemetry↔pane self-check is a different organ; keep it out
  export CC_WAIT_CONTRACTS_DIR="$BATS_TEST_TMPDIR/contracts"; mkdir -p "$CC_WAIT_CONTRACTS_DIR"

  PAGELOG="$BATS_TEST_TMPDIR/pages.log"
  export CC_WAIT_PAGE_CMD="$BATS_TEST_TMPDIR/fakepage"
  cat >"$CC_WAIT_PAGE_CMD" <<PG
#!/bin/bash
printf '%s | %s\n' "\$1" "\$2" >> "$PAGELOG"
PG
  chmod +x "$CC_WAIT_PAGE_CMD"
}

# an OPEN contract whose waiter pid cannot exist — the orphaned-wait divergence, deadline still in the
# future so the ONLY thing under test is dead-waiter detection (same fixture shape as the lint selftest).
dead_contract() {
  printf '{"id":"dead","waiter":"WD","waiter_pid":2147483641,"waiter_start":"stale","waitee":"X","expected_signal":"ping","deadline":%s,"deadline_s":3600,"on_timeout_action":"reobserve","status":"OPEN"}\n' \
    "$(( $(date +%s) + 3600 ))" > "$CC_WAIT_CONTRACTS_DIR/dead.json"
}

pages() { [ -f "$PAGELOG" ] && wc -l < "$PAGELOG" | tr -d ' ' || echo 0; }

@test "one supervisor sweep PAGES a dead-waiter OPEN wait contract" {
  dead_contract
  run bash "$SUP" --once
  [ "$status" -eq 0 ]
  [ "$(pages)" = 1 ]
  run jq -r '.paged_state // "none"' "$CC_WAIT_CONTRACTS_DIR/dead.json"
  [ "$output" = "dead-waiter" ]
}

@test "the divergence page is ONCE across two sweeps, not once per sweep" {
  dead_contract
  bash "$SUP" --once >/dev/null 2>&1
  bash "$SUP" --once >/dev/null 2>&1
  [ "$(pages)" = 1 ]
  run jq -r '.page_count' "$CC_WAIT_CONTRACTS_DIR/dead.json"
  [ "$output" -ge 2 ]      # seen on both sweeps, paged on one
}

@test "the divergence is a supervisor FINDING, not a silent side effect" {
  # S-4: a sweep that found something must say so in its own heartbeat, or the watcher's record shows
  # an all-clear over a live orphaned wait.
  dead_contract
  bash "$SUP" --once >/dev/null 2>&1
  [ -f "$CC_IDL" ]
  run jq -rs '[.[] | select(.kind=="heartbeat")] | last | .findings' "$CC_IDL"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "CONTROL (green pre- and post-fix): a live in-window contract is never paged" {
  # Named as a control: pre-fix it passes vacuously (nothing sweeps at all). Its job is post-fix — the
  # wiring must not turn every OPEN contract into a page, which would be the wolf-cry inversion.
  printf '{"id":"live","waiter":"WL","waiter_pid":%s,"waiter_start":%s,"waitee":"X","expected_signal":"ping","deadline":%s,"deadline_s":3600,"on_timeout_action":"reobserve","status":"OPEN"}\n' \
    "$$" "$(jq -n --arg s "$(ps -o lstart= -p $$ | sed 's/^ *//;s/ *$//')" '$s')" "$(( $(date +%s) + 3600 ))" \
    > "$CC_WAIT_CONTRACTS_DIR/live.json"
  run bash "$SUP" --once
  [ "$status" -eq 0 ]
  [ "$(pages)" = 0 ]
}
