#!/usr/bin/env bats
# THE RESTORE BUDGET (LIMIT_RECOVER_FLEET_V2, lr-reconciler) — CC_ADMIT_RESTORE_R replaces the active
# ceiling for a recovery wave, and an admission token minted but not yet redeemed counts as active:
# the session it admits is on its way in, and cc_sp_active cannot see it until it boots mid-turn.
# Without that, N probes in a row each see the same box and admit N sessions past the budget.
#
# HERMETICITY: the same stubbed box as capacity-admit-active.bats — sysctl/vm_stat stubbed, HOME,
# state, IDL, beats and notifier under BATS_TEST_TMPDIR, load and headroom pinned so only the ACTIVE
# term can refuse. The census is fed through CC_SP_ACTIVE_OVERRIDE.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/capacity-admit.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"; mkdir -p "$CC_BEAT_DIR"
  export CC_SP_BEAT_LIB="$REPO/hooks/lib/cc-beat.sh"
  export CC_ADMIT_PRESENCE_LIB="$REPO/scripts/lib/spawn-presence.sh"
  export CC_ADMIT_NOTIFY_BIN="$BATS_TEST_TMPDIR/notify"
  cat > "$CC_ADMIT_NOTIFY_BIN" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/pages.txt"
EOF
  chmod +x "$CC_ADMIT_NOTIFY_BIN"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  cat > "$BIN/sysctl" <<'EOF'
#!/bin/bash
case "$*" in
  *hw.ncpu*)                           echo 10 ;;
  *vm.loadavg*)                        echo "{ 1.00 1.00 1.00 }" ;;
  *vm.compressor_segment_limit*)       echo 262144 ;;
  *vm.compressor_segment_buffer_size*) echo 65536 ;;
  *vm.swapusage*)                      echo "total = 8192.00M  used = 0.00M  free = 8192.00M  (encrypted)" ;;
  *) exit 1 ;;
esac
EOF
  cat > "$BIN/vm_stat" <<'EOF'
#!/bin/bash
echo "Mach Virtual Memory Statistics: (page size of 16384 bytes)"
echo "Pages free:                          2000000."
echo "Pages speculative:                   0."
echo "Pages inactive:                      0."
echo "Pages purgeable:                     0."
echo "Pages occupied by compressor:        0."
EOF
  chmod +x "$BIN/sysctl" "$BIN/vm_stat"
  export CC_ADMIT_SYSCTL="$BIN/sysctl"
  export PATH="$BIN:$PATH"
  export CC_BEAT_NOW=1000000 CC_SP_NOW=1000000 CC_SP_HOUR=12
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0 CC_ADMIT_HEADROOM_OVERRIDE=64 CC_SP_TREES_OVERRIDE=3
  unset CC_ADMIT_RESTORE_R CC_ADMIT_ACTIVE_CEILING CC_ADMIT_TOKEN_TTL_S
  TOKDIR="$CC_ADMIT_STATE_DIR/tokens"
}

# The gate's rc is the subshell's rc — the last statement, so the reason print cannot mask a REFUSE.
admit() { # $1=caller → prints the reason, exits with the gate's rc
  bash -c '. "$1"; cc_capacity_admit "$2" spawn; rc=$?; cc_capacity_admit_reason; exit $rc' _ "$LIB" "$1"
}
probe() { # $1=caller
  bash -c '. "$1"; cc_capacity_probe "$2" spawn; rc=$?; cc_capacity_admit_reason; exit $rc' _ "$LIB" "$1"
}
lib() { bash -c 'set -euo pipefail; . "$1"; shift; "$@"' _ "$LIB" "$@"; }
tok() { # $1=name $2=issued epoch → one token record in the default token dir
  mkdir -p "$TOKDIR"
  printf '%s\t%s\t%s\t%s\n' "$2" "${1%%.*}" "$(id -u)" "load,headroom,segments,active" > "$TOKDIR/$1"
}

@test "R frozen: a later spawn is refused a restore" {
  CC_ADMIT_RESTORE_R=10 CC_SP_ACTIVE_OVERRIDE=9 run admit r-a
  [ "$status" -eq 0 ]
  [[ "$(jq -r 'select(.caller=="r-a") | .detail' "$CC_ADMIT_IDL")" == *"9 sessions mid-turn (restore budget R=10)"* ]] || false
  CC_ADMIT_RESTORE_R=10 CC_SP_ACTIVE_OVERRIDE=10 run admit r-b
  [ "$status" -eq 9 ]
  [[ "$output" == *"10 sessions mid-turn + 1 > restore budget R=10"* ]] || false
  [ "$(jq -r 'select(.caller=="r-b") | .term' "$CC_ADMIT_IDL")" = active ]
  # Unset R is today's gate, byte for byte.
  CC_SP_ACTIVE_OVERRIDE=7 run admit r-c
  [ "$status" -eq 0 ]
  CC_SP_ACTIVE_OVERRIDE=8 run admit r-d
  [ "$status" -eq 9 ]
  [[ "$output" == *"8 sessions mid-turn + 1 > active ceiling 8"* ]] || false
}

@test "tokens in flight are counted as active" {
  local now; now="$(date +%s)"
  tok sid-a.AAAA1111 "$now"
  tok sid-b.BBBB2222 "$((now - 5))"
  tok sid-c.CCCC3333 "$((now - 100000))"                    # expired: past any TTL
  tok sid-d.DDDD4444.claim.123.456 "$now"                   # mid-redemption: already claimed
  run lib cc_capacity_tokens_inflight
  [ "$status" -eq 0 ]
  [ "$output" = 2 ]
  # 8 active + 2 in flight + 1 > 10 — the same box admits with no tokens outstanding (8 + 1 ≤ 10).
  CC_ADMIT_RESTORE_R=10 CC_SP_ACTIVE_OVERRIDE=8 run admit t-a
  [ "$status" -eq 9 ]
  [[ "$output" == *"8 sessions mid-turn + 2 admission token(s) in flight + 1 > restore budget R=10"* ]] || false
  # Read-only: nothing was swept or consumed by the count.
  [ "$(find "$TOKDIR" -type f | wc -l | tr -d ' ')" = 4 ]
  rm -f "$TOKDIR"/sid-a.* "$TOKDIR"/sid-b.*
  CC_ADMIT_RESTORE_R=10 CC_SP_ACTIVE_OVERRIDE=8 run admit t-b
  [ "$status" -eq 0 ]
  # An absent token dir is 0, not an error, under the caller's errexit.
  rm -rf "$TOKDIR"
  run lib cc_capacity_tokens_inflight
  [ "$status" -eq 0 ]
  [ "$output" = 0 ]
}

@test "the probe does not spend the budget" {
  CC_ADMIT_RESTORE_R=10 CC_SP_ACTIVE_OVERRIDE=10 run probe p-a
  [ "$status" -eq 9 ]
  [[ "$output" == *"PROBE would REFUSE"*"restore budget R=10"* ]] || false
  [ ! -s "$CC_ADMIT_STATE_DIR/p-a.refusals" ]
  CC_ADMIT_RESTORE_R=10 CC_SP_ACTIVE_OVERRIDE=10 run probe p-a
  [ "$status" -eq 9 ]
  CC_ADMIT_RESTORE_R=10 CC_SP_ACTIVE_OVERRIDE=10 run admit p-a
  [ "$status" -eq 9 ]
  [[ "$output" == *"refusal 1 of 3"* ]] || false
}

@test "malformed R falls back to the active ceiling" {
  CC_ADMIT_RESTORE_R=ten CC_SP_ACTIVE_OVERRIDE=7 run admit m-a
  [ "$status" -eq 0 ]
  [[ "$(jq -r 'select(.caller=="m-a") | .blind' "$CC_ADMIT_IDL")" == *restore-r* ]] || false
  [[ "$(jq -r 'select(.caller=="m-a") | .detail' "$CC_ADMIT_IDL")" == *"(active ceiling 8)"* ]] || false
  CC_ADMIT_RESTORE_R=ten CC_SP_ACTIVE_OVERRIDE=8 run admit m-b
  [ "$status" -eq 9 ]
  [[ "$output" == *"8 sessions mid-turn + 1 > active ceiling 8"* ]] || false
}
