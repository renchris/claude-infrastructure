#!/usr/bin/env bats
# lead-supervisor — VERSION-ASSERTING SELF-RESTART (wave W1g).
#
# THE DEFECT THIS PINS. The supervisor is a launchd daemon that runs for days, and bash holds the
# script's INODE open while a land REPLACES the file (write-new + rename). Measured 2026-09-08: commit
# 10348ff6a landed the permission-pending escalation ladder at 14:45Z, pid 31716 had started at 15:17Z,
# and the ladder produced 0 `permission_pending_escalate` records in 5,155 IDL rows while 11 sessions sat
# 5.7-7.9 h at a permission prompt with ONE notice each (114/114 markers in the pre-ladder bare-ts form).
#
# RED-PROOF SHAPE. These cases drive the REAL daemon loop over a COPY of the script, so the only thing
# under test is whether a tick notices its own bytes changed. Case 1 is red on origin/main (the pre-fix
# loop never exits, so the wait times out); case 2 is the control that must stay green on BOTH sides —
# without it, "always restart" would pass case 1 and take the watchdog off the box.
#
# The on-disk copy is replaced by RENAME, never by appending: appending would mutate the inode the
# running bash is still reading from and could feed it the new text as input, which is not what a land
# does and would test the harness instead of the subject.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$BATS_TEST_TMPDIR"
  SUT="$T/lead-supervisor.sh"
  cp "$REPO/scripts/lead-supervisor.sh" "$SUT"
  mkdir -p "$T/tel" "$T/permpend" "$T/registry" "$T/wc" "$T/fired" "$T/pages"
  # HERMETIC: the subject resolves several helpers under $HOME (the wait-contract lint, the
  # dispatched-ness oracle, the desk role file) and every store below defaults there too. A suite that
  # ran against the operator's live ~/ would both read real state and write into it.
  export HOME="$T/home"; mkdir -p "$HOME"
  # Every store seamed into the test dir, and every OPERATOR-FACING path disarmed: a test must never
  # notify a real desk. PANE_DELTA_TOL is the one that matters — self_check compares LIVE claude panes
  # (real, on this box) against the 0 rows this empty telemetry dir enumerates, and would otherwise page.
  export CC_TELEMETRY_DIR="$T/tel" CC_IDL="$T/idl.jsonl" CC_SUPERVISOR_LOG="$T/sup.log" \
         CC_SUPERVISOR_PAGEDIR="$T/pages" CC_PAGE_TO="" CC_PAGE_TO_FILE=/dev/null \
         CC_PERMPEND_DIR="$T/permpend" CC_REGISTRY_DIR="$T/registry" \
         CC_WAIT_CONTRACTS_DIR="$T/wc" CC_FIRED_DIR="$T/fired" \
         CC_SUP_PANE_DELTA_TOL=1000000 SUPERVISOR_SWEEP=1
  DPID=""
}

teardown() {
  [ -n "${DPID:-}" ] && kill -9 "$DPID" 2>/dev/null || true
}

start_daemon() {
  bash "$SUT" --daemon >"$T/daemon.out" 2>&1 &
  DPID=$!
  wait_for_sweeps 1 60      # the loop must be PROVEN ticking before a case acts, so that on a slow box
}                           # "it exited" can never quietly mean "it never started"

# Wait for $1 recorded heartbeats, up to $2 seconds. Counting SWEEPS rather than sleeping a fixed span
# is what keeps the control honest under load: this box has run at load 175, where a 1 s sweep interval
# still yields fewer than one sweep per second and a wall-clock assertion goes red for the wrong reason.
wait_for_sweeps() {
  local want="$1" secs="$2" i=0
  while [ "$i" -lt $(( secs * 10 )) ]; do
    [ "$(grep -c 'swept=' "$T/sup.log" 2>/dev/null || echo 0)" -ge "$want" ] && return 0
    i=$(( i + 1 )); sleep 0.1
  done
  return 1
}

land_a_new_version() {   # replace the on-disk copy the way a land does: write-new, then rename over
  sed 's|^# lead-supervisor.sh —|# lead-supervisor.sh (NEW BYTES ON DISK) —|' "$SUT" > "$T/staged.sh"
  # the edit must actually change the bytes, else the whole case is vacuous. Spelled as an `if`, not a
  # leading `!`: a non-final negation is unreachable under errexit and would always "pass"
  # (memory: negated-assertion-dead-unless-final).
  if cmp -s "$T/staged.sh" "$SUT"; then
    echo "vacuous: the staged copy is byte-identical to the running one" >&2
    return 1
  fi
  mv "$T/staged.sh" "$SUT"
}

wait_for_exit() {        # $1=seconds — 0 iff the daemon is gone within the budget
  local i=0
  while [ "$i" -lt $(( ${1} * 10 )) ]; do
    kill -0 "$DPID" 2>/dev/null || return 0
    i=$(( i + 1 )); sleep 0.1
  done
  return 1
}

@test "a tick over a CHANGED on-disk copy exits 0 for launchd to respawn (RED on origin/main)" {
  start_daemon
  land_a_new_version
  wait_for_exit 25
  # exit 0 specifically: KeepAlive is unconditional in the plist, but a non-zero exit is how a CRASH
  # looks, and this path is a deliberate handover, not a fault.
  run wait "$DPID"
  [ "$status" -eq 0 ]
  grep -q 'self-restart: on-disk sha256 changed' "$T/sup.log"
  grep -q '"kind":"supervisor_self_restart"' "$T/idl.jsonl"
  # the record must carry BOTH digests — an operator reading the IDL has to be able to tell which
  # version was running, and a restart record with no shas cannot be told from a crash-and-respawn.
  grep -q '"running_sha":"[0-9a-f]\{64\}"' "$T/idl.jsonl"
  grep -q '"disk_sha":"[0-9a-f]\{64\}"' "$T/idl.jsonl"
}

@test "a tick over an UNCHANGED on-disk copy keeps running (the control that stops always-restart)" {
  start_daemon
  wait_for_sweeps 4 60      # the assertion has now been evaluated on several ticks, not just one
  kill -0 "$DPID"
  ! grep -q 'self-restart' "$T/sup.log" || false
  ! grep -q 'supervisor_self_restart' "$T/idl.jsonl"
}

@test "no usable hasher ⇒ ABSTAIN (keep supervising) and SAY SO — never a restart loop" {
  # CC_SUP_SHA_BIN set-but-EMPTY disables the assertion verbatim; the daemon must then survive a change
  # it cannot see, and must declare the blindness rather than render like the healthy case.
  export CC_SUP_SHA_BIN=""
  start_daemon
  grep -q '"kind":"supervisor_self_sha_unavailable"' "$T/idl.jsonl"
  local before
  before="$(grep -c 'swept=' "$T/sup.log")"
  land_a_new_version
  wait_for_sweeps $(( before + 3 )) 60
  kill -0 "$DPID"
  ! grep -q 'self-restart' "$T/sup.log"
}
