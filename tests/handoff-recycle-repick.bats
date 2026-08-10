#!/usr/bin/env bats
# handoff-fire --recycle × claude-accounts — the W2-A account re-pick (ACCOUNT_ROUTING_V2 §14).
#
# A recycle relaunches the pane with the pane's OWN launcher by construction, so the commonest
# succession on this box could never shrink a pile-up. W2-A lets a recycle move the pane when the
# router says its current account is NOT ROUTABLE — and, far more importantly, refuses to move it
# in every other case. This suite pins BOTH halves: the one condition that re-picks, and the eight
# that fail soft to a byte-identical relaunch.
#
# The decision block is extracted by its own marker comment and sourced directly, the way
# tests/handoff-fire-assign.bats drives the M7 --assign block: driving the full recycle path would
# need the it2 stack stubbed end-to-end, while the function's inputs are one argument and four
# environment scalars. The call-site wiring the extraction cannot see is pinned by the static
# assertions at the bottom.
#
# Hermetic: the block's only external calls are $CC_ACCOUNTS_BIN (a recording stub in
# BATS_TEST_TMPDIR) and mktemp under a fixture $TMPDIR. Nothing reads the real router, cache,
# ledger, account map or network.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Hermeticity pins (test-hermeticity ratchet). The block consumes scalars and $CC_ACCOUNTS_BIN
  # today; the pins keep the suite inert against the live ~/ and the operator's deployed tools if
  # it ever grows a wider read. ABSENT paths are correct — these sensors fail open on absence.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep-stamp.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"

  FIRE="$REPO/scripts/handoff-fire.sh"
  BLOCK="$BATS_TEST_TMPDIR/repick-block.sh"
  # marker → the first closing `}` at column 0. A renamed marker yields an EMPTY block, which the
  # extraction control below turns into a hard red — never a vacuous pass.
  sed -n '/^# ---- W2-A: recycle account re-pick/,/^}$/p' "$FIRE" > "$BLOCK"

  STUB_LOG="$BATS_TEST_TMPDIR/stub-calls.log"
  ROUTE_OUT="$BATS_TEST_TMPDIR/route.out"
  ROUTE_ERR="$BATS_TEST_TMPDIR/route.err"
  ROUTE_RC="$BATS_TEST_TMPDIR/route.rc"
  ASSIGN_RC="$BATS_TEST_TMPDIR/assign.rc"
  ERRF="$BATS_TEST_TMPDIR/repick.err"
  STUB="$BATS_TEST_TMPDIR/claude-accounts-stub"
  # Paths are BAKED into the stub rather than passed through the environment: the block invokes the
  # router through `perl -e 'alarm 25; exec @ARGV'`, and a stub that depended on inherited env would
  # be pinning the harness's plumbing rather than the block's behaviour.
  printf '%s\n' \
    '#!/bin/bash' \
    "printf '%s\\n' \"\$*\" >> $STUB_LOG" \
    "if [ \"\$1\" = --assign ]; then exit \"\$(cat $ASSIGN_RC 2>/dev/null || echo 0)\"; fi" \
    "[ -f $ROUTE_ERR ] && cat $ROUTE_ERR >&2" \
    "[ -f $ROUTE_OUT ] && cat $ROUTE_OUT" \
    "exit \"\$(cat $ROUTE_RC 2>/dev/null || echo 0)\"" > "$STUB"
  chmod +x "$STUB"
  # Bare-name seam pin: run_repick passes the stub explicitly, but the ratchet (rightly) treats an
  # inherited bare `claude-accounts` as the operator's deployed binary — pin it shut.
  export CC_ACCOUNTS_BIN="$STUB"

  # Default fleet state: next3 is 5h-cut, the router routes to next2.
  printf 'next2\n' > "$ROUTE_OUT"
  printf 'claude-accounts: general excluded — next3=5h-cutoff; next4=kmax-concurrency\n' > "$ROUTE_ERR"
  printf '0\n' > "$ROUTE_RC"
}

run_repick() { # $1 = the pane's current account. stdout → $output, stderr → $ERRF.
  run env CC_ACCOUNTS_BIN="$STUB" CC_ACCOUNTS_BIN_EXPLICIT="${EXPLICIT:-1}" ERRF="$ERRF" \
      bash -c 'set -euo pipefail; . "$1"; recycle_repick "$2" 2>"$ERRF"' _ "$BLOCK" "$1"
}

called() { # $1 = a substring of an expected invocation
  [ -f "$STUB_LOG" ] && grep -qF -- "$1" "$STUB_LOG"
}

# ---- the extraction control ------------------------------------------------------------------

@test "extraction control: the marker found a non-empty block that routes and assigns" {
  [ -s "$BLOCK" ]
  grep -q -- '--route general' "$BLOCK"
  grep -q -- '--src recycle-repick' "$BLOCK"
  grep -q '^}$' "$BLOCK"
  grep -q 'recycle_repick()' "$BLOCK"
}

# ---- the ONE condition that re-picks -----------------------------------------------------------

@test "an excluded current account is re-picked onto the router's winner, charged and announced" {
  run_repick next3
  [ "$status" -eq 0 ]
  [ "$output" = "next2" ]                                   # stdout contract: the new account, alone
  called '--route general'
  called '--assign next2 --src recycle-repick'
  grep -q 'recycle RE-PICK' "$ERRF"
  grep -q 'next3' "$ERRF"                                   # old
  grep -q 'next2' "$ERRF"                                   # new
  grep -q '5h-cutoff' "$ERRF"                               # the exclusion REASON, not just a verdict
  grep -q 'CC_RECYCLE_REPICK=off' "$ERRF"                   # the kill switch is in the announcement
}

# ---- the eight that must NOT re-pick -----------------------------------------------------------

@test "a routable current account stays put even when it is not the router's top pick" {
  # next is absent from the exclusion map: the router prefers next2, but pressure short of
  # exclusion is deliberately out of v1's scope.
  run_repick next
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! called '--assign'
}

@test "a prefix of an excluded name is not an excluded name" {
  # THE parse defect this shape invites: `next` is a prefix of `next3`, and a substring test would
  # convict a perfectly routable pane on its sibling's exclusion.
  printf 'claude-accounts: general excluded — next3=5h-cutoff\n' > "$ROUTE_ERR"
  run_repick next
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! called '--assign'
}

@test "the router naming the account we are already on is not a re-pick" {
  printf 'next3\n' > "$ROUTE_OUT"
  run_repick next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! called '--assign'
}

@test "exit 2 (nothing routable by policy) and exit 3 (data unreadable) both keep the launcher" {
  printf 'none\n' > "$ROUTE_OUT"; printf '2\n' > "$ROUTE_RC"
  run_repick next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf 'next2\n' > "$ROUTE_OUT"; printf '3\n' > "$ROUTE_RC"
  run_repick next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! called '--assign'
}

@test "the kill switch is not a filter — the router is never consulted at all" {
  export CC_RECYCLE_REPICK=off
  run_repick next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$STUB_LOG" ]
}

@test "a frontier recycle is left alone: the general lane cannot answer for Fable entitlement" {
  export MODEL=claude-fable-5
  run_repick next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$STUB_LOG" ]
}

@test "under bats without an opt-in stub the real router is never polled" {
  EXPLICIT=0 run_repick next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$STUB_LOG" ]
}

@test "an account the map does not declare is DECLINED, not fired at" {
  # cc_acct_dir_for_name is the generated SSOT map. When it is loaded and disagrees, the router's
  # answer loses — launcher_for()/cfg_dir() would otherwise HALT the fire on `!! unknown account`,
  # turning a routing nicety into a dead recycle.
  run env CC_ACCOUNTS_BIN="$STUB" CC_ACCOUNTS_BIN_EXPLICIT=1 ERRF="$ERRF" \
      bash -c 'set -euo pipefail; cc_acct_dir_for_name() { return 1; }; . "$1"; recycle_repick "$2" 2>"$ERRF"' \
      _ "$BLOCK" next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q 'DECLINED' "$ERRF"
  ! called '--assign'
}

# ---- the re-pick's own fail-soft edges ---------------------------------------------------------

@test "a dry run re-picks but charges nothing — it launches nothing to charge for" {
  export DRY=1
  run_repick next3
  [ "$status" -eq 0 ]
  [ "$output" = "next2" ]
  called '--route general'
  ! called '--assign'
}

@test "the assign is advisory: a failing ledger write never costs the re-pick" {
  printf '5\n' > "$ASSIGN_RC"
  run_repick next3
  [ "$status" -eq 0 ]
  [ "$output" = "next2" ]
  called '--assign next2 --src recycle-repick'
}

@test "an absent router is a keep, not a crash" {
  # AMBIENT ARM, stated so a future reader does not over-read the green: two independent mechanisms
  # produce this outcome, so no single-site mutant can red it. Deleting the `command -v $bin` guard
  # leaves the test passing because `perl -e 'alarm N; exec @ARGV' /no/such/bin` exits 0 with EMPTY
  # stdout and EMPTY stderr (measured on this box) — which the block's own `[ -z "$out" ]` arm then
  # catches. What this test pins is the OUTCOME (an absent router never costs a recycle its
  # relaunch); the `command -v` guard is defence-in-depth on top of it, not its sole cause.
  run env CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-binary" CC_ACCOUNTS_BIN_EXPLICIT=1 ERRF="$ERRF" \
      bash -c 'set -euo pipefail; . "$1"; recycle_repick "$2" 2>"$ERRF"' _ "$BLOCK" next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a winner with no exclusion line at all is a keep" {
  # `--route` prints the exclusion map only when something was excluded. Nothing excluded means
  # the current account is routable by construction.
  : > "$ROUTE_ERR"
  run_repick next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! called '--assign'
}

# ---- call-site wiring the extraction cannot see ------------------------------------------------

@test "the re-pick is wired into the recycle pre-pass, inside the auto-account arm only" {
  # An explicit --account/--launcher is the operator's choice and must never be second-guessed:
  # the call has to sit under the `auto` arm that INFERRED the account from CLAUDE_CONFIG_DIR.
  run sed -n '/^if \[ "\$RECYCLE" = 1 \]; then/,/^fi$/p' "$REPO/scripts/handoff-fire.sh"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  printf '%s\n' "$output" | grep -q 'ACCOUNT="\$(env_account)"'
  printf '%s\n' "$output" | grep -q '_repick="\$(recycle_repick "\$ACCOUNT" || true)"'
  printf '%s\n' "$output" | grep -q 'RECYCLE_REPICK_FROM="\$ACCOUNT"; ACCOUNT="\$_repick"'
}

@test "a re-picked recycle pre-trusts its launch dir under the NEW account's config dir" {
  # Same-dir recycles skip pre_trust because the running session proves the dir is trusted — but
  # that proof lives in the OLD account's .claude.json, so a re-pick needs the write or the
  # successor stalls at the workspace-trust dialog with the brief unread behind it.
  run grep -n 'RECYCLE_RELOC" = 1 \] || \[ -n "\${RECYCLE_REPICK_FROM:-}" \]' "$REPO/scripts/handoff-fire.sh"
  [ "$status" -eq 0 ]
}

@test "the M7 fire-time assign still skips recycles, so a re-pick is charged exactly once" {
  # Both blocks call --assign. If the M7 block ever stopped skipping RECYCLE=1 the re-picked
  # account would be charged twice — once as recycle-repick, once as handoff-fire.
  run sed -n '/^# ---- fire-time assignment feedback (ACCOUNT_ROUTING_V2 M7)/,/^fi$/p' "$REPO/scripts/handoff-fire.sh"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '\[ "\$RECYCLE" = 0 \]'
}
