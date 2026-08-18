#!/usr/bin/env bats
# backlog aa8aed0d713a — the desk role pointer and the liveness-free phone leg.
#
# Two DISCRIMINATOR PAIRS. Each pair is one KEEP assertion (the fixed behaviour) plus one REMOVE
# assertion that runs a deliberately-broken COPY of the subject — the same file with the one
# load-bearing line deleted — and proves the KEEP assertion goes RED against it. A green that was
# never consulted is indistinguishable from one that works.
#
#   PAIR 1 — a claim by a DEAD pid must read as ABSENT (never as a live address).
#            REMOVE half: delete the `kill -0` liveness check from cc-roles.
#   PAIR 2 — the phone leg must fire with NO desk claimed.
#            REMOVE half: re-gate phone_fallback behind the desk being live.
#
# Everything is hermetic: CC_ROLES_DIR / CC_MAILBOX_DIR / CC_NOTIFY_PUSH_BIN /
# CC_NOTIFY_PHONE_DAMP_DIR all point into BATS_TEST_TMPDIR, and the push binary is a STUB. No test
# here can read or write the operator's live ~/.claude/cc-roles, and none can send a real page.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROLES="$REPO/bin/cc-roles"
  NOTIFY="$REPO/bin/cc-notify"

  # $HOME fixtured too, not only the CC_* seams: the subject resolves several defaults out of
  # $HOME/.claude directly, so an unfixtured run reads the operator's live tree even when every
  # seam above is pointed at the tmpdir.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # A READABLE but EMPTY session registry. Without it the fixtured $HOME has no registry at all and
  # cc-notify answers resolver-unavailable (exit 4, "UNVERIFIED, not invalid") for every name — a
  # different verdict from "this name does not resolve" (exit 3). Seeding it keeps the distinction
  # the suite actually tests instead of borrowing the operator's live registry to supply it.
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"; mkdir -p "$CC_REGISTRY_DIR"

  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export CC_NOTIFY_PHONE_DAMP_DIR="$BATS_TEST_TMPDIR/damp"
  mkdir -p "$CC_ROLES_DIR" "$CC_MAILBOX_DIR"

  # THE PHONE IS A STUB. Left unresolved, cc-notify's probe order would find the real
  # scripts/push-send.sh and (with creds in the env) POST to Pushover for real.
  PUSHLOG="$BATS_TEST_TMPDIR/pushlog"
  export CC_NOTIFY_PUSH_BIN="$BATS_TEST_TMPDIR/push-stub"
  { printf '#!/bin/bash\n'; printf 'printf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$PUSHLOG"; } > "$CC_NOTIFY_PUSH_BIN"
  chmod +x "$CC_NOTIFY_PUSH_BIN"

  # cc-notify resolves cc-roles by probe order; pin it so the suite tests THIS checkout's copy and a
  # mutant can be substituted for it.
  export CC_ROLES_BIN="$ROLES"

  DEAD_PID=999999          # not a live pid on this box (checked by the guard test below)
}

# A live pid the test owns, so "alive" is a fact rather than an assumption.
start_holder() {
  sleep 30 &
  HOLDER=$!
}
stop_holder() { [ -n "${HOLDER:-}" ] && kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null || true; }

# ── PAIR 1 KEEP ──────────────────────────────────────────────────────────────────────────────────
@test "PAIR1-KEEP: a claim whose pid is DEAD reads as ABSENT, not as an address" {
  run bash -c "kill -0 $DEAD_PID 2>/dev/null"          # positive control on the fixture itself
  [ "$status" -ne 0 ]

  "$ROLES" claim desk --target 11111111-2222-3333-4444-555555555555 --pid "$DEAD_PID" --force
  run "$ROLES" read desk
  [ "$status" -eq 1 ]
  [ -z "$output" ] || [[ "$output" != *"11111111-2222-3333-4444-555555555555"* ]] || false
  [[ "$output" == *"ABSENT"* ]] || false
  [[ "$output" == *"dead-pid"* ]]
}

@test "PAIR1-KEEP: a claim whose pid is ALIVE reads LIVE and prints the target" {
  start_holder
  "$ROLES" claim desk --target LIVE-TARGET-0001 --pid "$HOLDER" --force
  run "$ROLES" read desk
  stop_holder
  [ "$status" -eq 0 ]
  [ "$output" = "LIVE-TARGET-0001" ]
}

# ── PAIR 1 REMOVE ────────────────────────────────────────────────────────────────────────────────
# The mutant deletes ONLY the liveness check. If PAIR1-KEEP still passed against it, the assertion
# would be proving something other than liveness.
@test "PAIR1-REMOVE: with the kill -0 liveness check deleted, the dead claim reads as an ADDRESS (KEEP would RED)" {
  mutant="$BATS_TEST_TMPDIR/cc-roles-nolive"
  sed 's/^    kill -0 "\$pid" 2>\/dev\/null || { echo "ABSENT dead-pid"; return; }$/    : # LIVENESS CHECK DELETED (mutant)/' "$ROLES" > "$mutant"
  chmod +x "$mutant"
  run bash -c "diff -q '$ROLES' '$mutant'"            # the mutation MUST have applied
  [ "$status" -ne 0 ]

  "$ROLES" claim desk --target 11111111-2222-3333-4444-555555555555 --pid "$DEAD_PID" --force
  run "$mutant" read desk
  [ "$status" -eq 0 ]
  [ "$output" = "11111111-2222-3333-4444-555555555555" ]   # exactly what PAIR1-KEEP forbids
}

# ── The state that must NOT be folded into ABSENT ────────────────────────────────────────────────
@test "a legacy pointer with no liveness evidence is UNVERIFIED (exit 4), never ABSENT" {
  printf 'LEGACY-UUID-0000\n' > "$CC_ROLES_DIR/desk"
  run "$ROLES" read desk
  [ "$status" -eq 4 ]
  [[ "$output" == *"LEGACY-UUID-0000"* ]]
}

@test "cc-notify still resolves a legacy pointer exactly as before (no regression on the main path)" {
  printf 'LEGACY-UUID-0000\n' > "$CC_ROLES_DIR/desk"
  run "$NOTIFY" --role desk "legacy page"
  [ "$status" -eq 0 ]
  [[ "$output" == *"enqueued=1"* ]] || false
  [ -f "$CC_MAILBOX_DIR/LEGACY-UUID-0000.md" ]
}

@test "a DEAD claim makes cc-notify REFUSE (rc 3) instead of enqueueing into a box nothing drains" {
  "$ROLES" claim desk --target 11111111-2222-3333-4444-555555555555 --pid "$DEAD_PID" --force
  run "$NOTIFY" --role desk "page to a dead desk"
  [ "$status" -eq 3 ]
  [[ "$output" == *"reason=role-unset"* ]] || false
  [ ! -f "$CC_MAILBOX_DIR/11111111-2222-3333-4444-555555555555.md" ]
}

# ── PAIR 2 KEEP ──────────────────────────────────────────────────────────────────────────────────
@test "PAIR2-KEEP: the phone leg fires with NO desk claimed at all" {
  [ ! -e "$CC_ROLES_DIR/desk" ]                        # the 2026-08-10 state: nothing claimed
  run "$NOTIFY" --role desk "overnight run finished"
  [ "$status" -eq 3 ]
  [[ "$output" == *"fallback=phoned"* ]] || false
  [ -f "$PUSHLOG" ]
  grep -q 'undeliverable page' "$PUSHLOG"
}

@test "PAIR2-KEEP: the phone leg also fires on the \`cat cc-roles/desk\` form (empty target)" {
  run "$NOTIFY" "" "overnight run finished"
  [ "$status" -eq 3 ]
  [[ "$output" == *"reason=empty-target"* ]] || false
  [[ "$output" == *"fallback=phoned"* ]] || false
  grep -q 'empty-target' "$PUSHLOG"
}

@test "PAIR2-KEEP: a DEAD desk claim phones too — absence and staleness reach the operator alike" {
  "$ROLES" claim desk --target 11111111-2222-3333-4444-555555555555 --pid "$DEAD_PID" --force
  run "$NOTIFY" --role desk "overnight run finished"
  [ "$status" -eq 3 ]
  [[ "$output" == *"fallback=phoned"* ]]
}

# ── PAIR 2 REMOVE ────────────────────────────────────────────────────────────────────────────────
# The mutant re-gates the leg behind the desk being live — the exact nesting that made the absence of
# a desk the absence of every channel. PAIR2-KEEP must RED against it.
@test "PAIR2-REMOVE: re-gated behind desk liveness, NO phone leg fires with no desk (KEEP would RED)" {
  mutant="$BATS_TEST_TMPDIR/cc-notify-gated"
  sed 's|^  \[ "\$PHONE_FALLBACK" = 1 \] .*$|  "$ROLES_BIN" read "${ROLE:-desk}" >/dev/null 2>\&1 \|\| { FALLBACK_OUTCOME=phone-skipped; echo "cc-notify: fallback=phone-skipped (mutant: gated behind the desk)" >\&2; return 0; }|' "$NOTIFY" > "$mutant"
  chmod +x "$mutant"
  run bash -c "diff -q '$NOTIFY' '$mutant'"
  [ "$status" -ne 0 ]

  [ ! -e "$CC_ROLES_DIR/desk" ]
  run "$mutant" --role desk "overnight run finished"
  [ "$status" -eq 3 ]
  # The mutant must be the GATED variant, not merely a broken file — a script that died for some
  # unrelated reason would also fail to phone, and would prove nothing about the gating.
  [[ "$output" == *"fallback=phone-skipped"* ]] || false
  [[ "$output" == *"reason=role-unset"* ]] || false   # it reached the same give-up site
  [[ "$output" != *"fallback=phoned"* ]] || false     # exactly what PAIR2-KEEP forbids
  [ ! -f "$PUSHLOG" ]                                  # the operator was told NOTHING
}

# ── The leg's own precondition, reported honestly ────────────────────────────────────────────────
@test "an UNWIRED phone reports push-send's exit 3 as phone-unwired — never as a role failure" {
  { printf '#!/bin/bash\nexit 3\n'; } > "$CC_NOTIFY_PUSH_BIN"; chmod +x "$CC_NOTIFY_PUSH_BIN"
  run "$NOTIFY" --role desk "overnight run finished"
  [ "$status" -eq 3 ]
  [[ "$output" == *"fallback=phone-unwired"* ]]
}

@test "the phone leg is DAMPED per (role,reason) so a 5-minute sweep rings once, not forever" {
  run "$NOTIFY" --role desk "first"
  [[ "$output" == *"fallback=phoned"* ]] || false
  run "$NOTIFY" --role desk "second"
  [[ "$output" == *"fallback=phone-damped"* ]] || false
  [ "$(grep -c 'undeliverable page' "$PUSHLOG")" -eq 1 ]
}

@test "a HUMAN addressing a pane by uuid never rings the phone (role-shaped give-ups only)" {
  run "$NOTIFY" "no-such-session-name" "hello"
  [ "$status" -eq 3 ]
  [ ! -f "$PUSHLOG" ]
}

@test "under bats with NO push seam, the real phone is never rung (hermeticity guard)" {
  # Exactly the state every OTHER suite in tests/ is in: bats vars exported, no CC_NOTIFY_PUSH_BIN.
  run env -u CC_NOTIFY_PUSH_BIN "$NOTIFY" --role desk "overnight run finished"
  [ "$status" -eq 3 ]
  [[ "$output" == *"fallback=phone-test-blocked"* ]]
}

@test "CC_NOTIFY_PHONE_FALLBACK=0 is a real kill switch" {
  CC_NOTIFY_PHONE_FALLBACK=0 run "$NOTIFY" --role desk "overnight run finished"
  [ "$status" -eq 3 ]
  [[ "$output" == *"fallback=phone-off"* ]] || false
  [ ! -f "$PUSHLOG" ]
}

# ── claim/release hygiene ────────────────────────────────────────────────────────────────────────
@test "claim refuses to steal a role held LIVE by someone else, unless --force" {
  start_holder
  "$ROLES" claim desk --target HOLDER-TARGET --pid "$HOLDER" --force
  run "$ROLES" claim desk --target THIEF-TARGET --pid "$HOLDER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to steal"* ]] || false
  run "$ROLES" claim desk --target THIEF-TARGET --pid "$HOLDER" --force
  stop_holder
  [ "$status" -eq 0 ]
}

@test "release removes the claim, and a released role reads as ABSENT" {
  "$ROLES" claim desk --target SOME-TARGET --pid "$DEAD_PID" --force
  run "$ROLES" release desk
  [ "$status" -eq 0 ]
  run "$ROLES" read desk
  [ "$status" -eq 1 ]
}

@test "line 1 of a claim stays the bare target, so every legacy head -n1 reader is unchanged" {
  "$ROLES" claim desk --target BARE-TARGET-1234 --pid "$DEAD_PID" --force
  run head -n1 "$CC_ROLES_DIR/desk"
  [ "$output" = "BARE-TARGET-1234" ]
}
