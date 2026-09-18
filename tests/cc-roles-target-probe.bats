#!/usr/bin/env bats
# backlog c19d0aedce0f · gap G3 of docs/plans/CONTINUOUS_DELIVERY_TO_LIVE_KITTY.md — the alarm
# channel that could not convict the only role shape this box actually has.
#
# WHAT THIS PINS. `cc-roles read` convicted a dead claimant only when the role FILE carried
# pid=/pane= evidence. No automation on this box has ever written that evidence, so all four roles
# read UNVERIFIED and `cc-notify --role desk` exited 0/mailbox-only into a box nothing drains —
# 66/66 overnight pages at notify_rc:0 against a pane dead since 2026-09-09. The new arm probes the
# TARGET when it is pane-shaped, so the legacy population becomes checkable.
#
# THE SAFETY PROPERTY IS THE POINT, AND MOST CASES HERE GUARD IT RATHER THAN THE FEATURE:
# UNVERIFIED must never be folded into ABSENT. Conviction requires a POSITIVE refutation (probe
# exit 1). Every could-not-tell — abstain, unrunnable, timed out, no bound available, not
# pane-shaped, probe off — must still read UNVERIFIED, because a false ABSENT is what cc-notify
# turns into rc 3 and a phone page to the operator.
#
# HERMETIC BY CONSTRUCTION: CC_ROLES_DIR and $HOME are fixtured, and CC_ROLES_PANE_PROBE is pointed
# at a STUB in setup(). No case here may reach the real terminal — an unstubbed pane-shaped target
# would resolve the default probe (`cc-pane address`) and enumerate the operator's live panes.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROLES="$REPO/bin/cc-roles"
  NOTIFY="$REPO/bin/cc-notify"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export CC_NOTIFY_PHONE_DAMP_DIR="$BATS_TEST_TMPDIR/damp"
  mkdir -p "$CC_ROLES_DIR" "$CC_MAILBOX_DIR"
  export CC_ROLES_BIN="$ROLES"

  # The phone is a STUB — cc-notify's give-up legs page Pushover for real otherwise.
  PUSHLOG="$BATS_TEST_TMPDIR/pushlog"
  export CC_NOTIFY_PUSH_BIN="$BATS_TEST_TMPDIR/push-stub"
  { printf '#!/bin/bash\n'; printf 'printf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$PUSHLOG"; } > "$CC_NOTIFY_PUSH_BIN"
  chmod +x "$CC_NOTIFY_PUSH_BIN"

  # DEFAULT STUB: says "gone" for everything. Any test that forgets to choose a probe therefore
  # gets a deterministic local answer instead of the operator's real terminal.
  probe_stub 1
}

# Mint a probe stub with a fixed exit code (or a special behaviour) and point the seam at it.
probe_stub() { # <rc> — 0 live · 1 gone · 2 abstain · any other
  PROBE="$BATS_TEST_TMPDIR/probe-$1"
  { printf '#!/bin/bash\n'; printf 'echo "$@" >> "%s"\nexit %s\n' "$BATS_TEST_TMPDIR/probe-calls" "$1"; } > "$PROBE"
  chmod +x "$PROBE"
  export CC_ROLES_PANE_PROBE="$PROBE"
}

# A mutant copy of the subject with ONE load-bearing line changed. A green that was never consulted
# is indistinguishable from one that works, so every safety case below has a REMOVE half.
mutant() { # <sed-expr> → path to the broken copy
  local m="$BATS_TEST_TMPDIR/cc-roles-mutant-$RANDOM"
  sed "$1" "$ROLES" > "$m"; chmod +x "$m"; printf '%s' "$m"
}

# ── THE FEATURE: a pane-shaped legacy target is now checkable in BOTH directions ─────────────────

@test "a legacy pane-shaped target the probe says is GONE reads ABSENT dead-target" {
  probe_stub 1
  printf '672\n' > "$CC_ROLES_DIR/desk"
  run "$ROLES" read desk
  [ "$status" -eq 1 ]
  [[ "$output" == *"dead-target"* ]] || false
  # ABSENT prints NOTHING on stdout — a convicted role must not hand back an address.
  run bash -c "'$ROLES' read desk 2>/dev/null"
  [ -z "$output" ]
}

@test "a legacy pane-shaped target the probe says is LIVE reads LIVE and prints the target" {
  probe_stub 0
  printf '51\n' > "$CC_ROLES_DIR/desk"
  run "$ROLES" read desk
  [ "$status" -eq 0 ]
  [ "$output" = "51" ]
}

@test "the probe is handed the TARGET, not a pane= field that does not exist" {
  probe_stub 0
  printf '672\n' > "$CC_ROLES_DIR/desk"
  "$ROLES" read desk >/dev/null 2>&1
  run cat "$BATS_TEST_TMPDIR/probe-calls"
  [[ "$output" == *"672"* ]] || false
}

@test "a canonical UUID target is pane-shaped too (the iTerm2 address shape)" {
  probe_stub 1
  printf '208ADD40-B603-4690-8AAA-BBBBCCCCDDDD\n' > "$CC_ROLES_DIR/desk"
  run "$ROLES" read desk
  [ "$status" -eq 1 ]
  [[ "$output" == *"dead-target"* ]] || false
}

# ── THE SAFETY PROPERTY: every could-not-tell stays UNVERIFIED, never ABSENT ─────────────────────

@test "ABSTAIN (probe rc 2) stays UNVERIFIED — an unreadable enumeration is not a gone verdict" {
  probe_stub 2
  printf '672\n' > "$CC_ROLES_DIR/desk"
  run "$ROLES" read desk
  [ "$status" -eq 4 ]
  [ "${lines[0]}" = "672" ]
}

@test "an UNRUNNABLE probe (rc 127) abstains — a refusal is not a negative" {
  export CC_ROLES_PANE_PROBE="$BATS_TEST_TMPDIR/does-not-exist"
  printf '672\n' > "$CC_ROLES_DIR/desk"
  run "$ROLES" read desk
  [ "$status" -eq 4 ]
}

@test "a probe CUT AT THE BOUND (rc 124) abstains rather than convicting" {
  PROBE="$BATS_TEST_TMPDIR/probe-hang"
  { printf '#!/bin/bash\n'; printf 'sleep 30\n'; } > "$PROBE"; chmod +x "$PROBE"
  export CC_ROLES_PANE_PROBE="$PROBE"
  export CC_ROLES_PROBE_TIMEOUT_S=1
  printf '672\n' > "$CC_ROLES_DIR/desk"
  run "$ROLES" read desk
  [ "$status" -eq 4 ]
}

@test "the probe is BOUNDED — a wedged terminal cannot hang the pager" {
  PROBE="$BATS_TEST_TMPDIR/probe-hang2"
  { printf '#!/bin/bash\n'; printf 'sleep 30\n'; } > "$PROBE"; chmod +x "$PROBE"
  export CC_ROLES_PANE_PROBE="$PROBE"
  export CC_ROLES_PROBE_TIMEOUT_S=1
  printf '672\n' > "$CC_ROLES_DIR/desk"
  local t0 t1
  t0="$(date +%s)"
  run "$ROLES" read desk
  t1="$(date +%s)"
  [ "$((t1 - t0))" -lt 20 ]
}

@test "NO bounding binary available ⇒ abstain, never an unbounded call and never a convict" {
  probe_stub 1
  export CC_ROLES_TIMEOUT_BIN=/nonexistent/timeout
  printf '672\n' > "$CC_ROLES_DIR/desk"
  run "$ROLES" read desk
  [ "$status" -eq 4 ]
}

@test "CC_ROLES_PANE_PROBE=off is a real kill switch — the pane signal is not evaluated at all" {
  export CC_ROLES_PANE_PROBE=off
  printf '672\n' > "$CC_ROLES_DIR/desk"
  run "$ROLES" read desk
  [ "$status" -eq 4 ]
  [ "${lines[0]}" = "672" ]
}

@test "a target that is NOT pane-shaped is never probed, even when the probe would say GONE" {
  probe_stub 1
  printf 'LEGACY-UUID-0000\n' > "$CC_ROLES_DIR/desk"
  run "$ROLES" read desk
  [ "$status" -eq 4 ]
  [ "${lines[0]}" = "LEGACY-UUID-0000" ]
  # and the probe was never even called — a session NAME is not an address a pane enumerator knows
  [ ! -f "$BATS_TEST_TMPDIR/probe-calls" ]
}

@test "the existing pid= arm: an ABSTAINING pane probe must not convict a claim whose pid is ALIVE" {
  probe_stub 2
  sleep 30 & local holder=$!
  "$ROLES" claim desk --target SOME-TARGET --pid "$holder" --pane 672 --force
  run "$ROLES" read desk
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$output" = "SOME-TARGET" ]
}

# ── END TO END: the G3 outcome, and the main path it must not break ─────────────────────────────

@test "E2E: cc-notify --role REFUSES (rc 3) on a dead pane-shaped desk, and enqueues NOTHING" {
  probe_stub 1
  printf '672\n' > "$CC_ROLES_DIR/desk"
  run "$NOTIFY" --role desk "overnight escalation"
  [ "$status" -eq 3 ]
  [[ "$output" == *"reason=role-unset"* ]] || false
  [ ! -f "$CC_MAILBOX_DIR/672.md" ]
}

@test "E2E: a LIVE pane-shaped desk still delivers — the main path is untouched" {
  probe_stub 0
  printf '51\n' > "$CC_ROLES_DIR/desk"
  run "$NOTIFY" --role desk "a page to a live desk"
  [ "$status" -eq 0 ]
  [[ "$output" == *"enqueued=1"* ]] || false
  [ -f "$CC_MAILBOX_DIR/51.md" ]
}

@test "E2E: the refusal reaches the operator on the liveness-free phone leg" {
  probe_stub 1
  printf '672\n' > "$CC_ROLES_DIR/desk"
  "$NOTIFY" --role desk "overnight escalation" >/dev/null 2>&1 || true
  [ -f "$PUSHLOG" ]
  run cat "$PUSHLOG"
  [[ "$output" == *"desk"* ]] || false
}

# ── REMOVE HALVES — each proves a KEEP assertion above is actually consulted ─────────────────────

@test "REMOVE: with the pane_shaped guard deleted, a session NAME is convicted (the false-ABSENT bug)" {
  probe_stub 1
  printf 'LEGACY-UUID-0000\n' > "$CC_ROLES_DIR/desk"
  local m; m="$(mutant 's/^    if pane_shaped "\$t"; then$/    if true; then/')"
  run "$m" read desk
  [ "$status" -eq 1 ]            # the mutant convicts what the subject leaves UNVERIFIED
  [[ "$output" == *"dead-target"* ]] || false
}

@test "REMOVE: with abstain folded into dead, a could-not-tell probe convicts (safety case would RED)" {
  probe_stub 2
  printf '672\n' > "$CC_ROLES_DIR/desk"
  local m; m="$(mutant 's|^    \*) return 2 ;;   # 2 INDETERMINATE.*|    *) return 1 ;;|')"
  run "$m" read desk
  [ "$status" -eq 1 ]
  [[ "$output" == *"dead-target"* ]] || false
}

@test "REMOVE: with the target-probe arm deleted, the dead desk reads UNVERIFIED again (pre-fix state)" {
  probe_stub 1
  printf '672\n' > "$CC_ROLES_DIR/desk"
  local m; m="$(mutant '/^    if pane_shaped "\$t"; then$/,/^    fi$/d')"
  run "$m" read desk
  [ "$status" -eq 4 ]            # exactly what trunk did before this change
  [ "${lines[0]}" = "672" ]
}
