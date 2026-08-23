#!/usr/bin/env bats
# comms-safety — F3 payload-lint: a successor-fire payload missing the BACK-CHANNEL BLOCK (cc-notify +
# a resolvable target — a desk full-uuid OR role-indirection cc-roles/<role>|--role, the P0-15 form)
# lints RED — the W5 incident root; a terminal-announce via SendMessage lints RED (serves F2/a). The
# tool's --selftest RED-proves discrimination; these bats add CLI-level regression on the exit codes
# (0=GREEN, 1=RED, 2=LOUD), including the role-indirection acceptance the T-P2-5 pre-fire wiring needs.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  L="$REPO/scripts/payload-lint.sh"
  DESK='99261468-A46A-498A-AE9B-F39473E5E7AE'
  P="$BATS_TEST_TMPDIR/p.txt"
}

@test "selftest passes every check and never shrinks toward zero checks" {
  run "$L" --selftest
  [ "$status" -eq 0 ]
  # FLOOR + TALLY, not a literal count. The intent is unchanged and is the right one — the COUNT is
  # what stops a selftest silently shrinking to zero checks — but a LITERAL count cannot express it:
  # it reds on the suite's own GROWTH, so it is a tripwire on the next fix rather than a guard on a
  # regression, and it fired that way twice. 5→8 on 2026-08-08 (+ a kitty pane-id back-channel goes
  # GREEN, + a prose integer stays RED) needed an edit here; 8→10 on 2026-08-22 (the uuid rule
  # anchored to the cc-notify argument position, + the laundered and prefixed cases) needed another.
  # Both were additions, and neither was a defect this assertion could have caught.
  # So assert the two things actually meant: every check PASSED (both halves equal), and the total
  # never falls below the floor already reached.
  got="$(printf '%s\n' "$output" | sed -n 's|.*selftest: \([0-9][0-9]*\)/\([0-9][0-9]*\).*|\1|p' | head -1)"
  tot="$(printf '%s\n' "$output" | sed -n 's|.*selftest: \([0-9][0-9]*\)/\([0-9][0-9]*\).*|\2|p' | head -1)"
  [ -n "$got" ] || { echo "no N/M tally in selftest output: $output"; false; }
  [ -n "$tot" ] || { echo "no N/M tally in selftest output: $output"; false; }
  [ "$got" -eq "$tot" ] || { echo "selftest reported $got/$tot — not every check passed"; false; }
  [ "$tot" -ge 8 ] || { echo "selftest shrank to $tot checks (floor 8) — the zero-check trap"; false; }
}

@test "block-less payload → RED (exit 1) — the W5 drop" {
  printf 'SUCCESSOR FIRE — continue the build. Ship at a green boundary.\n' > "$P"
  run "$L" "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BACK-CHANNEL BLOCK missing"* ]]
}

@test "well-formed payload (cc-notify + desk uuid + prohibition) → GREEN (exit 0)" {
  { printf 'SUCCESSOR FIRE.\n'
    printf 'BACK-CHANNEL: announce to the desk via cc-notify %s VERIFIED.\n' "$DESK"
    printf 'NEVER SendMessage — the desk is NOT a teammate.\n'; } > "$P"
  run "$L" "$P"
  [ "$status" -eq 0 ]
}

@test "missing cc-notify line (uuid only) → RED" {
  printf 'FIRE. the desk is %s. carry on.\n' "$DESK" > "$P"
  run "$L" "$P"
  [ "$status" -eq 1 ]
}

@test "missing desk uuid (cc-notify + prose 'the desk', no cc-roles/ or --role) → RED" {
  printf 'FIRE. announce via cc-notify to the desk. carry on.\n' > "$P"
  run "$L" "$P"
  [ "$status" -eq 1 ]
}

@test "role-indirection (cc-notify + cc-roles/<role>, NO literal uuid) → GREEN — the P0-15 form" {
  # Every /goal fire resolves the desk via `cat ~/.claude/cc-roles/desk`; this MUST pass or the
  # T-P2-5 pre-fire wiring would wrongly BLOCK the desk's own /goal fires (role != frozen uuid).
  { printf 'FIRE. continue the build.\n'
    printf 'BACK-CHANNEL: cc-notify "$(cat ~/.claude/cc-roles/desk)" on completion, VERIFIED.\n'; } > "$P"
  run "$L" "$P"
  [ "$status" -eq 0 ]
}

@test "role-indirection via --role flag (cc-notify + --role desk, NO uuid) → GREEN" {
  { printf 'FIRE. continue the build.\n'
    printf 'BACK-CHANNEL: cc-notify --role desk "done" on completion.\n'; } > "$P"
  run "$L" "$P"
  [ "$status" -eq 0 ]
}

@test "terminal-announce via SendMessage (F3/a) → RED even with the block present" {
  { printf 'FIRE. cc-notify %s is the desk.\n' "$DESK"
    printf 'On ship, announce the ship-witness to the desk via SendMessage.\n'; } > "$P"
  run "$L" "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"F3/a"* ]]
}

@test "a PROHIBITION of SendMessage is tolerated (prescriptive vs proscriptive) — not false-RED" {
  { printf 'FIRE. cc-notify %s is the desk.\n' "$DESK"
    printf 'NEVER use SendMessage for the desk — it silently degrades to disk-truth.\n'; } > "$P"
  run "$L" "$P"
  [ "$status" -eq 0 ]
}

@test "missing file → LOUD (exit 2), never a silent pass" {
  run "$L" "$BATS_TEST_TMPDIR/does-not-exist.txt"
  [ "$status" -eq 2 ]
}

# ── ROLE_REF is the CLASS "a role", not three spellings (backlog f1a51344cb84, 2026-08-23) ─────────
# ROLE_REF enumerated desk|operator|orchestrator while cc-roles manages arbitrary roles. Measured the
# day of the fix, the list was ANTI-CORRELATED with reality: desk and operator had no role file at
# all, orchestrator read ABSENT/empty, and the only two roles that resolved — drain-lead (LIVE 102)
# and docs-lead (UNVERIFIED 450) — were the two it refused. A false-RED here is the unrecoverable
# direction: payload_lint_gate … enforce aborts the fire and fire_cleanup DELETES THE BRANCH.

@test "a role OUTSIDE the old three-name list (--role drain-lead) → GREEN — the f1a51344cb84 case" {
  { printf 'FIRE. continue the build.\n'
    printf 'BACK-CHANNEL: cc-notify --role drain-lead "HANDOFF-PING: done" on completion.\n'; } > "$P"
  run "$L" "$P"
  [ "$status" -eq 0 ] || { echo "false-RED on a LIVE role: $output"; false; }
}

@test "the cc-roles/<role> PATH form also takes any role, not just the old three" {
  { printf 'FIRE. continue the build.\n'
    printf 'BACK-CHANNEL: cc-notify "$(cat ~/.claude/cc-roles/drain-lead)" on completion.\n'; } > "$P"
  run "$L" "$P"
  [ "$status" -eq 0 ] || { echo "false-RED on the path form of a LIVE role: $output"; false; }
}

@test "prose mentioning --role, with cc-notify present but UNADDRESSED → RED (the anchor)" {
  # The widening is only safe because the flag form is anchored to a role-consuming SENDER's argument
  # position. Unanchored — as it shipped — this payload went GREEN carrying no back-channel at all.
  # It MUST mention cc-notify: has_cc is F3's FIRST condition, so a fixture without it REDs there and
  # proves nothing about the role arm (that vacuity is why the mutant arm below exists).
  { printf 'FIRE. continue the build.\n'
    printf 'cc-notify is available here, but never use --role desk — it is the wrong pane.\n'; } > "$P"
  run "$L" "$P"
  [ "$status" -eq 1 ] || { echo "prose laundered a back-channel through F3: $output"; false; }
  [[ "$output" == *"F3"* ]]
}

# ── MUTANT ARMS — the fix must be the reason the three clauses above pass ──────────────────────────
# Both mutants are `sed` over the WORKING TREE with the ROLE_REF site counted BEFORE and AFTER, so no
# moving ref is replayed (an arm that compares the fix to itself cannot occur) and a rename of the
# site REDS the anchor instead of silently yielding a mutant identical to the subject.

@test "MUTANT: restoring the three-name enumeration REDS the LIVE-role case" {
  [ "$(grep -c '^ROLE_REF=' "$L")" -eq 1 ]
  local m="$BATS_TEST_TMPDIR/m1.sh"
  sed "s@^ROLE_REF=.*@ROLE_REF='cc-roles/(desk|operator|orchestrator)|--role[[:space:]=]+(desk|operator|orchestrator)'@" "$L" > "$m"
  [ "$(grep -c 'cc-await-ping' "$m")" -eq 0 ]     # the fixed regex is gone
  chmod +x "$m"
  { printf 'FIRE.\n'
    printf 'BACK-CHANNEL: cc-notify --role drain-lead "done".\n'; } > "$P"
  run bash "$m" "$P"
  [ "$status" -eq 1 ] || { echo "the enumeration is UNGUARDED — reverting it changed nothing"; false; }
}

@test "MUTANT: deleting the sender anchor GREENS the prose payload" {
  # Without this arm the anchor could be removed tomorrow and every other test would stay green,
  # because the widened token alone still passes all the positive cases.
  [ "$(grep -c '^ROLE_REF=' "$L")" -eq 1 ]
  local m="$BATS_TEST_TMPDIR/m2.sh"
  sed "s@^ROLE_REF=.*@ROLE_REF='cc-roles/[a-z][a-z0-9-]*|--role[[:space:]=]+\"?[a-z][a-z0-9-]*'@" "$L" > "$m"
  [ "$(grep -c 'cc-await-ping' "$m")" -eq 0 ]     # the anchor is gone
  [ "$(grep -c 'a-z0-9-' "$m")" -ge 1 ]           # the widened token survives
  chmod +x "$m"
  { printf 'FIRE.\n'
    printf 'cc-notify is available here, but never use --role desk — it is the wrong pane.\n'; } > "$P"
  run bash "$m" "$P"
  [ "$status" -eq 0 ] || { echo "the ANCHOR is UNGUARDED — deleting it changed nothing"; false; }
}
