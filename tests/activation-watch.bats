#!/usr/bin/env bats
# activation-watch (SessionStart) — the absence-is-loud re-page for the C10 activation queue (D-v).
# The tool's --selftest RED-proves the age/done/absent logic; these bats add independent CLI-level
# coverage via CC_ACTIVATION_DIR fixtures + the SessionStart additionalContext JSON contract.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/activation-watch.sh"
  Q="$BATS_TEST_TMPDIR/queue"
  mkdir -p "$Q"
  OLD="$(date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || echo 200001010000.00)"
  # Axis-2 isolation: mirror := the queue itself ⇒ trivially in parity, so the axis-1 tests measure
  # staleness alone. Without it they read the REAL repo mirror and every fixture (absent from it) is
  # correctly reported LIVE-ONLY — drift noise, not an axis-1 failure. Parity tests override this.
  export CC_ACTIVATION_MIRROR_DIR="$Q"
}
stage() { printf '#!/bin/bash\n' > "$Q/$1"; [ -n "${2:-}" ] && touch -t "$2" "$Q/$1"; return 0; }

@test "selftest passes and runs all 14 checks (a zero-check suite must not 'pass')" {
  run "$H" --selftest
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  ok ')" -eq 14 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "stale (>24h) un-run activation → named in the additionalContext" {
  stage "p0-14-activate.sh" "$OLD"
  CC_ACTIVATION_DIR="$Q" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'p0-14-activate.sh'
  printf '%s' "$output" | grep -q 'ACTIVATION QUEUE'
}

@test "output is valid SessionStart additionalContext JSON" {
  stage "x-activate.sh" "$OLD"
  CC_ACTIVATION_DIR="$Q" run "$H"
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("x-activate.sh")' >/dev/null
}

@test "fresh (<24h) un-run activation → NOT named" {
  stage "fresh-activate.sh"
  CC_ACTIVATION_DIR="$Q" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test ".done-marked stale activation → NOT named" {
  stage "ran-activate.sh" "$OLD"
  : > "$Q/ran-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "absent queue dir → silent, exit 0 (fail-open)" {
  CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/nope" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mixed queue: only the stale un-run one is named" {
  stage "stale-a.sh" "$OLD"
  stage "fresh-b.sh"
  stage "done-c.sh" "$OLD"; : > "$Q/done-c.sh.done"
  CC_ACTIVATION_DIR="$Q" run "$H"
  printf '%s' "$output" | grep -q 'stale-a.sh'
  ! printf '%s' "$output" | grep -q 'fresh-b.sh' || false
  ! printf '%s' "$output" | grep -q 'done-c.sh'
}

# ══════════════ axis 2 — SSOT parity: live queue vs the repo mirror ══════════════════════════
# Fixtures are FRESH (<24h) throughout, so axis 1 stays silent and every finding below is
# attributable to the parity axis alone.

@test "LIVE-ONLY: staged live but never committed → named (the unrecoverable class)" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  stage "12-only-live-activate.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '12-only-live-activate.sh'
  printf '%s' "$output" | grep -q 'LIVE-ONLY'
}

@test "REPO-ONLY: committed but never deployed → named (axis 1 is structurally blind to it)" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  printf '#!/bin/bash\n' > "$M/09-only-repo-activate.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '09-only-repo-activate.sh'
  printf '%s' "$output" | grep -q 'REPO-ONLY'
}

@test "CONTENT-DRIFT: same name, diverged bytes → named (the deploy-lag class)" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
  printf '#!/bin/bash\n# REPO\n' > "$M/07-drift-activate.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  printf '%s' "$output" | grep -q '07-drift-activate.sh'
  printf '%s' "$output" | grep -q 'CONTENT-DRIFT'
}

@test "a .local marker exempts an intentionally live-only script" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  stage "secret-activate.sh"; : > "$Q/secret-activate.sh.local"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "in-parity copies → silent (positive control: the firing path must also go quiet)" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  stage "01-agreed-activate.sh"
  cp "$Q/01-agreed-activate.sh" "$M/"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unresolvable mirror is REPORTED, never a silent vacuous pass" {
  stage "x-activate.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$BATS_TEST_TMPDIR/nope" \
    CC_ACTIVATION_REPO="$BATS_TEST_TMPDIR/nope" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'DID NOT RUN'
}

@test "invoked through a SYMLINK the mirror resolves to the CHECKOUT, never ~/.claude (816015ecb30b)" {
  # The live wiring is ~/.claude/hooks/activation-watch.sh → a symlink into the checkout. An
  # underefed BASH_SOURCE yields REPO=~/.claude, where docs/activation/ does not exist, and the
  # whole axis passes vacuously — exactly how the sibling deploy-parity assert stayed silent.
  ln -s "$H" "$BATS_TEST_TMPDIR/linked.sh"
  unset CC_ACTIVATION_MIRROR_DIR          # force the deref + .git-gate path under test
  CC_ACTIVATION_DIR="$Q" run "$BATS_TEST_TMPDIR/linked.sh" --parity
  # resolves to THIS checkout — not ~/.claude, and not the FALLBACK_REPO shared checkout
  printf '%s' "$output" | grep -q "$REPO/docs/activation/pending-activation"
  ! printf '%s' "$output" | grep -q '\.claude/docs/activation'
}

@test "--parity: rc 1 + named drift, rc 0 + GREEN once the copies agree" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  stage "only-live.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H" --parity
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'only-live.sh'
  cp "$Q/only-live.sh" "$M/"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H" --parity
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'GREEN'
}

@test "both axes compose into ONE valid SessionStart emit" {
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  stage "stale-and-uncommitted-activate.sh" "$OLD"      # stale (axis 1) AND live-only (axis 2)
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ACTIVATION QUEUE")' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ACTIVATION SSOT PARITY")' >/dev/null
}
