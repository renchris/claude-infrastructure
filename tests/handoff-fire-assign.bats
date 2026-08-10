#!/usr/bin/env bats
# handoff-fire × claude-accounts M7 — the fire-time assignment call-site.
#
# The mechanism (phantom working sessions, TTL, ranking effect) is pinned in
# claude-accounts-core.bats; THIS suite pins the WIRING: handoff-fire's post-pick block calls
# `--assign <chosen> --src handoff-fire` exactly when a real fire commits to an account, and
# stays silent on every path that launches nothing new (dry-run, recycle, explicit launcher)
# or that runs inside a hermetic harness without an opt-in stub. The block is extracted by its
# own marker comment and executed directly: driving the full fire path here would need the it2
# stack stubbed end-to-end, and the block's inputs are four scalars.
#
# Hermetic: the extracted block's only external call is $CC_ACCOUNTS_BIN, pointed at a
# recording stub in BATS_TEST_TMPDIR. Nothing touches the real ledger, cache, or network.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Hermeticity pins (test-hermeticity ratchet). The extracted block reads none of these TODAY —
  # it consumes four scalars and $CC_ACCOUNTS_BIN — but the ratchet cannot know that, and the
  # pins keep this suite inert against the live ~/ , machine load, and the operator's deployed
  # tools if the block ever grows a wider read. ABSENT paths are correct: these sensors fail
  # open on absence.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep-stamp.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  FIRE="$REPO/scripts/handoff-fire.sh"
  BLOCK="$BATS_TEST_TMPDIR/assign-block.sh"
  # marker → first closing `fi` at column 0. A renamed marker yields an EMPTY block, which the
  # control test below turns into a hard red — never a vacuous pass.
  sed -n '/^# ---- fire-time assignment feedback (ACCOUNT_ROUTING_V2 M7)/,/^fi$/p' "$FIRE" > "$BLOCK"
  STUB_LOG="$BATS_TEST_TMPDIR/stub-calls.log"
  STUB="$BATS_TEST_TMPDIR/claude-accounts-stub"
  printf '#!/bin/bash\necho "$@" >> "%s"\n' "$STUB_LOG" > "$STUB"
  chmod +x "$STUB"
  # Bare-name seam pin: run_block passes the stub explicitly, but the ratchet (rightly) treats
  # an inherited bare `claude-accounts` as the operator's deployed binary — pin it shut.
  export CC_ACCOUNTS_BIN="$STUB"
}

run_block() { # $1=DRY $2=RECYCLE $3=CHOSEN $4=CC_ACCOUNTS_BIN_EXPLICIT [$5=bin override]
  DRY="$1" RECYCLE="$2" CHOSEN="$3" CC_ACCOUNTS_BIN_EXPLICIT="$4" \
    CC_ACCOUNTS_BIN="${5:-$STUB}" bash -e "$BLOCK"
}

@test "extraction control: the marker found a non-empty block that calls --assign" {
  [ -s "$BLOCK" ]
  grep -q -- '--assign' "$BLOCK"
  grep -q '^fi$' "$BLOCK"
}

@test "a committed auto-pick fire charges the chosen account, tagged with its source" {
  run run_block 0 0 next3 1
  [ "$status" -eq 0 ]
  run cat "$STUB_LOG"
  [ "$output" = "--assign next3 --src handoff-fire" ]
}

@test "paths that launch nothing new stay silent: dry-run, recycle, explicit launcher" {
  run run_block 1 0 next3 1
  [ "$status" -eq 0 ]
  run run_block 0 1 next3 1
  [ "$status" -eq 0 ]
  run run_block 0 0 "(explicit launcher)" 1
  [ "$status" -eq 0 ]
  run run_block 0 0 "" 1
  [ "$status" -eq 0 ]
  [ ! -e "$STUB_LOG" ]
}

@test "under bats without an opt-in stub the ledger is never touched (pre_fire_account_sweep's own rule)" {
  # BATS_TEST_TMPDIR is live in this process by construction — the guard's harness arm is real
  run run_block 0 0 next3 0
  [ "$status" -eq 0 ]
  [ ! -e "$STUB_LOG" ]
}

@test "the assign is advisory: a failing router never fails the fire path" {
  FAIL="$BATS_TEST_TMPDIR/failing-stub"
  printf '#!/bin/bash\nexit 5\n' > "$FAIL"
  chmod +x "$FAIL"
  run run_block 0 0 next3 1 "$FAIL"
  [ "$status" -eq 0 ]
}
