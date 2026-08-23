#!/usr/bin/env bats
# CONTRACT REPAIR — scripts/payload-lint.sh ↔ bin/cc-notify (v3 D2, closing failure S-1).
#
# THE BREAK THIS EXISTS TO PREVENT: payload-lint.sh:50 has blessed `cc-notify --role <role>` as a
# sanctioned back-channel form since P0-15 — while cc-notify itself rejected `--role` as an unknown
# option (exit 2). Every brief written in the lint-approved form therefore linted GREEN and then FAILED
# at ping time. Two suites each passed in isolation: payload-lint.bats asserted the linter blesses the
# string, cc-notify.bats asserted the tool's own flags work. Nothing ran the linter's blessed string
# against the real tool, so the seam between them was untested by construction.
#
# The rule (memory: fixture-shape-parity-with-real-producer): when one component's fixture encodes a
# CLAIM about another component's interface, one test must exercise the LITERAL blessed form against
# the REAL binary. Every form asserted GREEN below is extracted from the linter's own contract.
#
# Isolation: CC_ROLES_DIR / CC_MAILBOX_DIR / CC_REGISTRY_DIR — never the live dirs.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  NOTIFY="$REPO/bin/cc-notify"
  LINT="$REPO/scripts/payload-lint.sh"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  mkdir -p "$CC_ROLES_DIR" "$CC_MAILBOX_DIR" "$CC_REGISTRY_DIR"
  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"
  P="$BATS_TEST_TMPDIR/payload.md"
}

# The roles payload-lint.sh's ROLE_REF regex sanctions. Anything the LINTER blesses, the TOOL must
# accept — that equivalence is the whole contract.
#
# 2026-08-23 (backlog f1a51344cb84): ROLE_REF used to enumerate exactly desk|operator|orchestrator,
# and this loop was that list transcribed. It now keys on the CLASS "a role reference", because
# cc-roles imposes no name validation and cc-notify --role (:556) just reads $CC_ROLES_DIR/<name> —
# so the blessed set is open-ended and a three-name loop would no longer cover it. drain-lead and
# docs-lead are the two roles that actually resolved on the box the day of the fix, and they are
# exactly the two the old list refused; they are in the loop so this contract is exercised against a
# role the enumeration would have rejected, not only against its incumbents.
@test "every role the linter blesses is a role the REAL cc-notify accepts (--role <role>)" {
  local r
  for r in desk operator orchestrator drain-lead docs-lead; do
    printf '%s\n' "$UUID" > "$CC_ROLES_DIR/$r"
    # BOTH halves, per role — the linter must bless it AND the tool must honour it. Asserting only
    # the tool half would leave the widened set untested on the side that actually changed.
    { printf 'FIRE.\n'
      printf 'BACK-CHANNEL: cc-notify --role %s "parity probe %s".\n' "$r" "$r"; } > "$P"
    run "$LINT" "$P"
    [ "$status" -eq 0 ] || { echo "the LINTER refused role '$r' (status $status): $output"; false; }
    run "$NOTIFY" --role "$r" "parity probe $r"
    [ "$status" -eq 0 ] || { echo "cc-notify REJECTED the lint-blessed role '$r' (status $status): $output"; false; }
    grep -q "parity probe $r" "$CC_MAILBOX_DIR/$UUID.md"
  done
}

@test "the --role=<role> form the linter's regex also matches is accepted by the real tool" {
  # ROLE_REF allows `--role[[:space:]=]+desk` — i.e. `--role=desk` lints GREEN, so it must also run.
  run "$NOTIFY" --role=desk "equals form"
  [ "$status" -eq 0 ]
  grep -q 'equals form' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "a payload the linter passes on --role is EXECUTABLE end to end (lint GREEN ⇒ tool works)" {
  # The exact shape a fired brief carries: lint it, then RUN the very command it blessed.
  { printf 'FIRE. continue the build.\n'
    printf 'BACK-CHANNEL: cc-notify --role desk "done" on completion.\n'; } > "$P"
  run "$LINT" "$P"
  [ "$status" -eq 0 ]                                   # linter says this brief is addressable…
  run "$NOTIFY" --role desk "done"
  [ "$status" -eq 0 ]                                   # …and the tool actually honours it
  grep -q '\] done' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "the OTHER blessed form — cc-notify \"\$(cat ~/.claude/cc-roles/desk)\" — also still runs" {
  # payload-lint.sh:50 blesses the cat-the-role-file shape too (every /goal fire uses it). Same
  # equivalence must hold: what lints GREEN must execute.
  { printf 'FIRE.\n'
    printf 'BACK-CHANNEL: cc-notify "$(cat ~/.claude/cc-roles/desk)" on completion, VERIFIED.\n'; } > "$P"
  run "$LINT" "$P"
  [ "$status" -eq 0 ]
  run "$NOTIFY" "$(cat "$CC_ROLES_DIR/desk")" "cat form"
  [ "$status" -eq 0 ]
  grep -q 'cat form' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "REGRESSION GUARD: --role is never silently swallowed as an unknown option (the original break)" {
  # The break's signature was exit 2 + "unknown option". Pin the ABSENCE of that specific failure, so
  # a future arg-parser refactor that drops --role fails loudly here rather than in production briefs.
  run "$NOTIFY" --role desk "guard"
  [ "$status" -ne 2 ]
  [[ "$output" != *"unknown option"* ]] || false
}
