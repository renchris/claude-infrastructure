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
  # THE ROUTER CALL, AS AN INVOCATION AND NOT AS A MENTION. This read `grep -- '--route general'`
  # over the whole block, comments included, and it stayed GREEN across the switch to `--rank`
  # purely because a new comment explains why `--rank`, not `--route`, is now called — a
  # mention-vs-use false pass in the one case whose entire job is to prove the extraction is real.
  # Comments are stripped before the match, so the token has to appear in code.
  grep -v '^[[:space:]]*#' "$BLOCK" | grep -q -- '--rank general'
  grep -q -- '--src recycle-repick' "$BLOCK"
  grep -q '^}$' "$BLOCK"
  grep -q 'recycle_repick()' "$BLOCK"
}

# ---- the ONE condition that re-picks -----------------------------------------------------------

@test "an excluded current account is re-picked onto the router's winner, charged and announced" {
  run_repick next3
  [ "$status" -eq 0 ]
  [ "$output" = "next2" ]                                   # stdout contract: the new account, alone
  called '--rank general'
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
  called '--rank general'
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
  printf '%s\n' "$output" | grep -q 'ACCOUNT="\$_repick"'
}

@test "a re-picked recycle pre-trusts its launch dir under the NEW account's config dir" {
  # Same-dir recycles skip pre_trust because the running session proves the dir is trusted — but
  # that proof lives in the OLD account's .claude.json, so a re-pick needs the write or the
  # successor stalls at the workspace-trust dialog with the brief unread behind it.
  #
  # 2026-08-15 — THIS ASSERTION WAS PINNING THE GUARD, NOT THE GUARANTEE. It grepped for
  # `[ "$RECYCLE_RELOC" = 1 ] || [ -n "${RECYCLE_REPICK_FROM:-}" ]` — the condition under which
  # pre_trust ran. That condition is gone, because the premise in the paragraph above was measured
  # FALSE: `.claude-tertiary` recorded ~/Development/personal as hasTrustDialogAccepted:false while
  # that same entry showed a 2.3 h session had run there on that account. The recycle branch now
  # pre-trusts UNCONDITIONALLY, and RECYCLE_REPICK_FROM — whose only reader was that guard — no
  # longer exists. Left as written, this test would have red-flagged the change that made its own
  # guarantee strictly stronger. The guarantee is unchanged and is what is asserted now.
  # Evidence: docs/research/mcp-modal-fire-stall-2026-08-15.md.
  run sed -n '/^elif \[ "\$RECYCLE" = 1 \]; then/,/^  recycle_fire$/p' "$REPO/scripts/handoff-fire.sh"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  printf '%s\n' "$output" | grep -qE '^  pre_trust "\$LAUNCH_DIR"'
}

@test "the M7 fire-time assign still skips recycles, so a re-pick is charged exactly once" {
  # Both blocks call --assign. If the M7 block ever stopped skipping RECYCLE=1 the re-picked
  # account would be charged twice — once as recycle-repick, once as handoff-fire.
  run sed -n '/^# ---- fire-time assignment feedback (ACCOUNT_ROUTING_V2 M7)/,/^fi$/p' "$REPO/scripts/handoff-fire.sh"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '\[ "\$RECYCLE" = 0 \]'
}

# ================================================================================================
# §14's SECOND HALF — re-pick on PRESSURE, not only on exclusion (backlog 2dc6906b6e0b)
#
# v1 kept a routable incumbent however hot, because the only input here was a boolean and the row
# insists the magnitude belongs in claude-accounts as an M7 scoring term. It now is: the magnitude
# is the router's own per-account score off `--rank`, and the THRESHOLD is declared by the router
# too and rides route-meta as `repick_ratio=`. These cases pin the one condition that moves a pane
# on pressure and the five that must not — same polarity as the exclusion half above, because the
# safe direction is always the byte-identical relaunch.
#
# RED-PROOF, STATED HONESTLY. Against pristine origin/main these eight run 1..25 with four not-ok:
# the cases that MOVE a pane (field-1 parse, pressured incumbent, zero-score incumbent) plus the
# static declaration check. The four RESTRAINT cases — below-threshold, kill switch, no route-meta,
# incumbent unranked — PASS pre-fix, and not because they are weak: v1 refuses every pressure
# re-pick unconditionally, so a case asserting "this one does not move" cannot fail against an
# engine where nothing moves. They are the negative half of a pair whose positive half is
# red-proved, and it is the PAIR that discriminates. Read them as regression guards on the new
# restraint, never as independent evidence that the restraint was ever absent.
# ================================================================================================

# A ranked fleet: $1 = the route-meta repick_ratio field (empty ⇒ no route-meta line at all).
_rank_fleet() {
  printf 'next2 0.005000\nnext3 0.000050\nnext4 0.000040\n' > "$ROUTE_OUT"
  if [ -n "${1:-}" ]; then
    printf 'route-meta: acct=next2 k_eff=2 repick_ratio=%s\n' "$1" > "$ROUTE_ERR"
  else
    : > "$ROUTE_ERR"
  fi
  printf '0\n' > "$ROUTE_RC"
}

@test "the winner is field 1 of a --rank line, never the whole line squashed" {
  # The v1 parse was `tr -d '[:space:]'` over line 1, correct for --route's bare name and silently
  # catastrophic for --rank: it yields `next20.005000`, a name the account map cannot declare, so
  # EVERY recycle would decline for a reason that looks like a routing nicety. Pinned as the
  # stdout contract because nothing else in this suite would notice.
  _rank_fleet 4
  run_repick next3
  [ "$status" -eq 0 ]
  [ "$output" = "next2" ]
}

@test "a routable but PRESSURED incumbent is re-picked, on the router's own score and threshold" {
  # next3 scores 0.000050 against next2's 0.005000 — 100x, well over the declared 4x. Nothing in
  # the exclusion map names next3, so v1 would have kept it.
  #
  # THIS CASE IS ALSO THE errf-LIFETIME PIN. The threshold is parsed from the same stderr file as
  # the exclusion map, and the first draft read it AFTER that file was removed: the parse returned
  # empty, the block fell through its own "unknown ⇒ keep the incumbent" guard, and the entire
  # pressure half was dead code that could never fire and would never have said so. If that
  # ordering regresses, this case is what goes red.
  _rank_fleet 4
  run_repick next3
  [ "$status" -eq 0 ]
  [ "$output" = "next2" ]
  called '--assign next2 --src recycle-repick'
  grep -q 'PRESSURE' "$ERRF"
  grep -q '0.000050' "$ERRF"    # the incumbent's measured score, not just a verdict
  grep -q '0.005000' "$ERRF"    # the winner's
  grep -q '4' "$ERRF"           # the threshold the decision was made against
}

@test "pressure BELOW the router's threshold keeps the pane where it is" {
  # 0.005000 / 0.004000 = 1.25x against a declared 4x. A re-pick here would be jitter between two
  # comparable accounts — the thing the threshold exists to refuse.
  printf 'next2 0.005000\nnext3 0.004000\n' > "$ROUTE_OUT"
  printf 'route-meta: acct=next2 repick_ratio=4\n' > "$ROUTE_ERR"
  printf '0\n' > "$ROUTE_RC"
  run_repick next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the router's kill switch (repick_ratio=off) restores v1 even at 100x pressure" {
  # The threshold is the ROUTER's to withdraw. `off` is what claude-accounts emits when
  # CC_ROUTE_REPICK is disabled, and it must read here as "never", not as a parse failure that
  # happens to fail the same way — so it is asserted against a fleet that would otherwise move.
  _rank_fleet off
  run_repick next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no route-meta line at all is an unknown threshold, so the pane stays" {
  # An older router, or a truncated stderr. Absence is not permission.
  _rank_fleet ""
  run_repick next3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an incumbent absent from the ranking is unmeasured, not pressured" {
  # The router did not score this account this pass. That is the same unknown as a missing
  # threshold — and critically NOT the exclusion case, which is handled earlier and would have
  # named the account in the exclusion map.
  _rank_fleet 4
  run_repick nextX
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a zero-scoring incumbent against a positive winner is unbounded pressure, and moves" {
  # best/0 is not a comparison to make in shell. The zero case is decided explicitly rather than
  # left to divide-by-zero, and it decides in favour of moving — a zero score IS the pile-up.
  printf 'next2 0.005000\nnext3 0\n' > "$ROUTE_OUT"
  printf 'route-meta: acct=next2 repick_ratio=4\n' > "$ROUTE_ERR"
  printf '0\n' > "$ROUTE_RC"
  run_repick next3
  [ "$status" -eq 0 ]
  [ "$output" = "next2" ]
}

@test "the threshold is DECLARED BY THE ROUTER, not carried as a constant in handoff-fire" {
  # The row's actual requirement: a measured magnitude as an M7 scoring term in claude-accounts,
  # "not a boolean in handoff-fire". A numeric threshold literal reappearing in the decision block
  # would be that policy re-authored outside the router and free to drift from the scoring it
  # thresholds — so the block may reference the ratio only as a value read off route-meta.
  grep -q 'repick_ratio' "$BLOCK"
  grep -q 'REPICK_RATIO_DEFAULT' "$REPO/bin/claude-accounts"
  grep -q 'repick_ratio=' "$REPO/bin/claude-accounts"
  # No bare numeric comparison against a literal threshold anywhere in the decision block.
  ! grep -vE '^[[:space:]]*#' "$BLOCK" | grep -qE '(>=|-ge)[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*(\)|\]|$)'
}
