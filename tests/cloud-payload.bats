#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats: every @test body IS its own subshell, so an `export` inside one
#   is meant to be test-local (SC2030/SC2031), and setup()'s helpers are invoked from those test
#   subshells rather than from file scope (SC2329).
#
# scripts/lib/cloud-payload.sh — the off-box BRIEF contract, CLOUD_OBSERVABILITY.md §4.1.
#
# WHAT THIS SUITE DEFENDS, and it is one property with two halves. §4.3's state function reads
# exactly ONE observable — does the declared ref exist, and has it advanced — so the meaning of its
# arms is fixed entirely by WHEN the session is told to push:
#
#   · told to push FIRST   → "no ref past the boot budget" means the VM never reached a shell,
#                            and C1 NOT-STARTED is actionable (re-fire).
#   · told to push LAST    → "no ref" also covers a healthy session three hours into its brief, so
#                            NOT-STARTED is a disjunction and re-firing it spends a second VM's
#                            rate limit duplicating work already in progress.
#
# The contract was PROSE ONLY until backlog 0c8b39b67665: the CLI lane's block ended "push whatever
# you have before you finish" (the inversion), and the API lane sent the brief verbatim with no
# return instruction at all. So the cases below assert ORDER and IMPERATIVE, not the presence of
# words — a suite that only grepped for "git push" passes on both the fixed and the broken text.
#
# RED-PROOF (re-runnable): this file cannot run at all against a tree without the library, which is
# the honest control here — the predecessor had no seam to replay. The ordering assertions in
# tests/handoff-fire-cloud.bats case 20 and tests/cc-offload.bats are the ones that go RED against
# `git show <pre-fix sha>` in a scratch tree, because both lanes existed there and both got it wrong.

setup() {
  LIB="${BATS_TEST_DIRNAME}/../scripts/lib/cloud-payload.sh"
  [ -f "$LIB" ] || { echo "missing $LIB"; return 1; }
  # shellcheck disable=SC1090
  . "$LIB"
  BR="claude/fire-20260826T000000Z-1234"
  BRIEF="$BATS_TEST_TMPDIR/brief.txt"
  printf 'TASK — do the thing.\nSecond line of the brief.\n' >"$BRIEF"
}

# ── the first act ────────────────────────────────────────────────────────────────────────────────

@test "1 the boot block instructs an EMPTY COMMIT, not merely a push" {
  run cc_cloud_boot_block "$BR"
  [ "$status" -eq 0 ]
  # The empty commit is the whole mechanism: a branch cannot be pushed before there is a commit to
  # push, and a session that has not written a file yet has none. Without --allow-empty the "first
  # act" is unsatisfiable until the work starts, which is the failure with an extra step.
  [[ "$output" == *"git commit --allow-empty"* ]] || false
  [[ "$output" == *"git push -u origin HEAD"* ]] || false
}

@test "2 the boot block ORDERS switch → commit → push, and each is on the assigned branch" {
  local out sw ci push
  out="$(cc_cloud_boot_block "$BR")"
  sw="$(printf '%s\n' "$out"   | grep -n "git switch -c $BR" | head -1 | cut -d: -f1)"
  ci="$(printf '%s\n' "$out"   | grep -n 'git commit --allow-empty' | head -1 | cut -d: -f1)"
  push="$(printf '%s\n' "$out" | grep -n 'git push -u origin HEAD' | head -1 | cut -d: -f1)"
  [ -n "$sw" ] && [ -n "$ci" ] && [ -n "$push" ] || { echo "a step is missing: sw=$sw ci=$ci push=$push"; false; }
  [ "$sw" -lt "$ci" ] || { echo "the branch must exist before the commit (sw=$sw ci=$ci)"; false; }
  [ "$ci" -lt "$push" ] || { echo "the commit must exist before the push (ci=$ci push=$push)"; false; }
}

@test "3 the boot block SAYS FIRST, and says why — an unexplained step is the first one dropped" {
  local out
  out="$(cc_cloud_boot_block "$BR")"
  [[ "$out" == *"FIRST ACT"* ]] || { echo "nothing marks this as the first act"; false; }
  # The reason has to travel with the instruction. A cloud session is a peer running this repo's
  # standards; "run this first" with no stated consequence loses to a brief that got interesting.
  [[ "$out" == *"NOT-STARTED"* ]] || { echo "the block never says what absence is read as"; false; }
}

@test "4 the boot block survives a branch name it did not choose" {
  # cc-offload's API lane names branches `claude/fire-<ts>-<pid>-<i>`; handoff-fire's has no -<i>.
  # The library takes the name as data and must never re-derive or validate it.
  run cc_cloud_boot_block "claude/fire-20260826T010203Z-999-3"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git switch -c claude/fire-20260826T010203Z-999-3"* ]] || false
}

@test "5 a missing branch is a REFUSAL, never a block naming an empty branch" {
  # A block that renders `git switch -c ` tells the session to push nowhere, and the declaration
  # would then watch a ref that can never appear — §11.2's "permanent false verdict", re-created.
  run cc_cloud_boot_block
  [ "$status" -ne 0 ]
  run cc_cloud_return_block
  [ "$status" -ne 0 ]
}

# ── the return block ─────────────────────────────────────────────────────────────────────────────

@test "6 the return block names the same branch and the local reconciler" {
  local out
  out="$(cc_cloud_return_block "$BR")"
  [[ "$out" == *"$BR"* ]] || false
  [[ "$out" == *"cloud-reconcile.sh"* ]] || { echo "the session is not told what picks the branch up"; false; }
  [[ "$out" == *"even if the work is incomplete"* ]] || false
}

# ── the whole payload ────────────────────────────────────────────────────────────────────────────

@test "7 the payload leads with the FIRST ACT and only then the brief" {
  local out boot brief
  out="$(cc_cloud_payload "$BRIEF" "$BR")"
  boot="$(printf '%s\n' "$out"  | grep -n 'FIRST ACT' | head -1 | cut -d: -f1)"
  brief="$(printf '%s\n' "$out" | grep -n 'TASK — do the thing' | head -1 | cut -d: -f1)"
  [ -n "$boot" ] && [ -n "$brief" ] || { echo "boot=$boot brief=$brief"; false; }
  # Position is the mechanism, not the styling. A model reads top-down, and this is the one
  # instruction whose entire value is in being executed before anything else in the message.
  [ "$boot" -lt "$brief" ] || { echo "the boot contract must precede the brief (boot=$boot brief=$brief)"; false; }
}

@test "8 the payload carries the brief VERBATIM — every line of it" {
  local out
  out="$(cc_cloud_payload "$BRIEF" "$BR")"
  [[ "$out" == *"TASK — do the thing."* ]] || false
  [[ "$out" == *"Second line of the brief."* ]] || false
}

@test "9 the payload ends with the return block — the push order is boot, work, return" {
  local out boot brief ret
  out="$(cc_cloud_payload "$BRIEF" "$BR")"
  boot="$(printf '%s\n' "$out"  | grep -n 'FIRST ACT' | head -1 | cut -d: -f1)"
  brief="$(printf '%s\n' "$out" | grep -n 'TASK — do the thing' | head -1 | cut -d: -f1)"
  ret="$(printf '%s\n' "$out"   | grep -n 'HOW TO RETURN YOUR WORK' | head -1 | cut -d: -f1)"
  [ "$boot" -lt "$brief" ] && [ "$brief" -lt "$ret" ] || { echo "boot=$boot brief=$brief ret=$ret"; false; }
}

@test "10 an unreadable brief is a REFUSAL, not a payload of pure boilerplate" {
  # A brief that failed to read must not become "here is how to push" with no task — that session
  # would boot, push an empty commit, read ALIVE, and do nothing for its whole life budget.
  run cc_cloud_payload "$BATS_TEST_TMPDIR/nope.txt" "$BR"
  [ "$status" -ne 0 ]
}

@test "11 double-sourcing is a no-op — the CLI lane sources it beside cloud-create.sh" {
  # shellcheck disable=SC1090
  . "$LIB"
  # shellcheck disable=SC1090
  . "$LIB"
  run cc_cloud_boot_block "$BR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git commit --allow-empty"* ]] || false
}
