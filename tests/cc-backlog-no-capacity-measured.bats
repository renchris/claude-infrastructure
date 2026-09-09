#!/usr/bin/env bats
# cc-backlog add: the `no-capacity` impossibility class must be MEASURED, not asserted.
#
# THE DEFECT (measured 2026-09-08, A11 skeptic row 14 / R7). The class gate checked spelling only,
# and cmd_add's own refusal text defines the class as "MEASURED: `claude-accounts --rank general`
# routes nowhere AND the machine admission gate refuses the spawn". Nothing ran the router, and
# "routes nowhere" was read literally — the reading that fails in the wrong direction, because the
# router prints the literal `none` for two OPPOSITE worlds and separates them only by exit code
# (bin/claude-accounts:5429-5437):
#
#   exit 2 — every account excluded by POLICY, on data it could read      → a real, measured wall
#   exit 3 — DATA_UNAVAILABLE: `ps` AND the transcript walk both failed   → a BLIND instrument
#   exit 0 — an account routed (stdout is `acct score`, never `none`)     → there IS capacity
#
# `concurrency-unmeasured` sits in DATA_UNAVAILABLE by design (:3355-3361) and arrives under exactly
# the load that produces spawn refusals, so the blind reading and the real wall are CORRELATED: the
# class was mintable on an instrument failure precisely when the box was busiest. Same shape as
# memory fail-safe-default-mimics-the-healthy-state, pointed at the refuse direction.
#
# THE COMMISSIONING BRIEF ASKED FOR "rc 0 AND the literal `none`" — unsatisfiable by construction
# (rc 0 is the arm where a candidate was FOUND, so it never prints `none`); implementing it would
# have deleted the class rather than tightened it. Its stated red-proof is test 1 below and holds
# verbatim. Live measurement the day this landed: `--rank general` → rc 2, `none`, all four accounts
# `kmax-concurrency` — a genuine policy wall, i.e. the class is still legitimately mintable.
#
# Every router here is a STUB. The suite must never depend on the fleet's live occupancy, which is
# the very quantity under test and changes minute to minute.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  [ -f "$CB" ] || skip "bin/cc-backlog not found at $CB"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_PROJECT_WARN=off
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  CALLED="$BATS_TEST_TMPDIR/router.called"
}

# router <rc> <stdout> — a claude-accounts stand-in that records that it was asked.
router() {
  local bin="$BATS_TEST_TMPDIR/claude-accounts"
  cat > "$bin" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$CALLED"
printf '%s\n' '$2'
echo "claude-accounts: no routable account for general (stub)" >&2
exit $1
EOF
  chmod +x "$bin"
  export CC_BACKLOG_ACCOUNTS_BIN="$bin"
}

rows() { wc -l < "$CC_BACKLOG_FILE" 2>/dev/null || echo 0; }

# ── THE RED-PROOF: a blind instrument must not mint the class ──────────────────────────────────

@test "exit 3 (DATA_UNAVAILABLE) refuses the add" {
  router 3 none
  run "$CB" add --title 'blocked on the fleet' --why-not-now 'no-capacity: nothing routes'
  [ "$status" -eq 2 ]
  [ "$(rows)" -eq 0 ]
}

@test "the refusal NAMES the blind instrument, so the next action is obvious" {
  router 3 none
  run "$CB" add --title 'blocked on the fleet' --why-not-now 'no-capacity'
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'blind'
  echo "$output" | grep -q 'exit 3'
}

# ── the class survives where it is TRUE ────────────────────────────────────────────────────────

@test "exit 2 with the empty-set marker ACCEPTS the add" {
  router 2 none
  run "$CB" add --title 'the fleet is genuinely walled' --why-not-now 'no-capacity: all four kmax'
  [ "$status" -eq 0 ]
  [ "$(rows)" -eq 1 ]
  grep -q 'no-capacity' "$CC_BACKLOG_FILE"
}

# ── the other two worlds ───────────────────────────────────────────────────────────────────────

@test "exit 0 (an account routed) refuses — there is capacity" {
  router 0 'next 0.42'
  run "$CB" add --title 'claims no capacity' --why-not-now 'no-capacity'
  [ "$status" -eq 2 ]
  [ "$(rows)" -eq 0 ]
}

@test "exit 2 WITHOUT the empty-set marker refuses — the code alone is not the contract" {
  router 2 'next 0.42'
  run "$CB" add --title 'claims no capacity' --why-not-now 'no-capacity'
  [ "$status" -eq 2 ]
  [ "$(rows)" -eq 0 ]
}

@test "an unresolvable router refuses — an unasked question is not a measurement" {
  export CC_BACKLOG_ACCOUNTS_BIN=
  run "$CB" add --title 'claims no capacity' --why-not-now 'no-capacity'
  [ "$status" -eq 2 ]
  [ "$(rows)" -eq 0 ]
}

# ── SCOPE CONTROL: the gate belongs to ONE class ───────────────────────────────────────────────

@test "a not-yet-true add never asks the router" {
  router 3 none
  run "$CB" add --title 'waiting on an upstream flag' --why-not-now 'not-yet-true: flag off'
  [ "$status" -eq 0 ]
  [ "$(rows)" -eq 1 ]
  [ ! -e "$CALLED" ]
}

@test "a bare add never asks the router" {
  router 3 none
  run "$CB" add --title 'ordinary work'
  [ "$status" -eq 0 ]
  [ ! -e "$CALLED" ]
}

# ── CONTROL: the accepting path really did consult the router ──────────────────────────────────

@test "the accepted no-capacity add asked --rank general" {
  router 2 none
  run "$CB" add --title 'the fleet is genuinely walled' --why-not-now 'no-capacity'
  [ "$status" -eq 0 ]
  grep -q -- '--rank general' "$CALLED"
}
