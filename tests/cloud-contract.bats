#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats: every @test body IS its own subshell, so an `export` inside one
#   is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are invoked from those test
#   subshells rather than from file scope (SC2329).
#
# scripts/lib/cloud-contract.sh — THE ABSENCE CONTRACT, as code.
#
# WHAT IS ACTUALLY UNDER TEST, and why it is a text function rather than a state machine.
# CLOUD_OBSERVABILITY.md §4.1 is the load-bearing sentence of the whole cloud instrument: a
# declared session that has pushed nothing is indistinguishable from one that never started, one
# that died at boot and one that was refused entitlement — all four read as "no ref" — and there is
# no inbound channel to a cloud VM, so it cannot be resolved by asking. It can only be resolved by
# CONTRACT: the brief requires the session's FIRST act to be pushing the branch, empty commit and
# all. Absence then means something: inside the boot budget it is BOOTING, past it NOT-STARTED.
#
# That contract was PROSE ONLY for the life of the document. The CLI leg appended a return block
# whose push was the LAST act; the API leg — the default leg — appended nothing at all. So C1
# NOT-STARTED, the one row this instrument emits as actionable, never meant "never booted": it
# meant "no ref", which a session that worked for an hour and ended at a question produces
# identically (bin/cc-cloud's `inbox` note: 222 of 262 live sessions on 2026-08-27).
#
# The defect class is therefore ORDER, not presence, and the assertions below are positional:
# "instructs a push" was already true and was not enough. Every test that asserts a string is
# present also asserts WHERE it is relative to the work.
#
# NO NETWORK, NO FIRE, NO $HOME: the subject is a pure function from a branch name to text.

setup() {
  # Fixture $HOME even though the subject never reads it: the rule is structural (every suite, no
  # exceptions), and a suite that is hermetic only because today's implementation happens not to
  # touch $HOME stops being hermetic the first time it does — silently.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$ROOT/scripts/lib/cloud-contract.sh"
  [ -f "$LIB" ] || skip "scripts/lib/cloud-contract.sh is missing"
  BR="claude/fire-20260827T000000Z-12345"

  # Line number of the first line matching $1 in $2 (empty when absent).
  lineno() { grep -n -- "$1" "$2" | head -1 | cut -d: -f1; }
}

emit() {  # → the contract for $BR, in $BATS_TEST_TMPDIR/out
  bash -c '. "$1"; cc_cloud_return_contract "$2"' _ "$LIB" "$BR" > "$BATS_TEST_TMPDIR/out"
}

@test "the seed commit is INSTRUCTED at all — the contract is no longer prose in a plan file" {
  emit
  grep -q -- '--allow-empty' "$BATS_TEST_TMPDIR/out"
  grep -q -- 'git push -u origin HEAD' "$BATS_TEST_TMPDIR/out"
}

@test "the seed push PRECEDES the work — the ordering IS the contract, not the push itself" {
  # The pre-fix payload contained a push too. It came after "push whatever you have before you
  # finish", which is a LAST act, and a last-act push cannot separate "never booted" from "booted
  # and produced nothing" — the exact conflation §4.1 exists to remove.
  emit
  local seed work
  seed="$(lineno '--allow-empty' "$BATS_TEST_TMPDIR/out")"
  work="$(lineno 'THEN do the work' "$BATS_TEST_TMPDIR/out")"
  [ -n "$seed" ] || { echo "no seed commit instruction at all"; false; }
  [ -n "$work" ] || { echo "the contract never hands over to the work"; false; }
  [ "$seed" -lt "$work" ] || { echo "the seed push must precede the work (seed=$seed work=$work)"; false; }
}

@test "the branch is CREATED before it is pushed, and the spelling survives it already existing" {
  # The two legs disagree about whether the branch exists on the VM: the CLI leg invents the name
  # and nothing holds it, while the API leg authorises it in the create body's
  # `outcomes.git_info.branches` and may materialise it. `switch -c` alone FAILS in the second
  # case, and a failed first line takes the seed push with it.
  emit
  local sw push
  sw="$(lineno 'git switch -c ' "$BATS_TEST_TMPDIR/out")"
  push="$(lineno 'git push -u origin HEAD' "$BATS_TEST_TMPDIR/out")"
  [ -n "$sw" ] || { echo "the contract never creates the branch"; false; }
  [ "$sw" -lt "$push" ] || { echo "switch must precede push (sw=$sw push=$push)"; false; }
  grep -q -- '|| git switch ' "$BATS_TEST_TMPDIR/out"
}

@test "the branch name it was handed is the branch name it prints — every time it names one" {
  # A contract that names a DIFFERENT branch than the one declared is worse than no contract: the
  # VM pushes somewhere nothing watches and the board reads NOT-STARTED over a completed session.
  emit
  grep -q "$BR" "$BATS_TEST_TMPDIR/out"
  # No other claude/* name may appear — a hardcoded example would be copied by a literal-minded VM.
  local other
  other="$(grep -o 'claude/[A-Za-z0-9._/-]*' "$BATS_TEST_TMPDIR/out" | sort -u | grep -vx "$BR" || true)"
  [ -z "$other" ] || { echo "the contract names branches it was not given: $other"; false; }
}

@test "the push target is HEAD, never a bare ref name this side invented" {
  # backlog 7c6ff16259a0: `git push origin HEAD:<branch>` pushes a detached HEAD at a ref name the
  # firing side made up, which is not the session's working branch. Re-introducing it here would
  # re-open that defect in the one place both legs read from.
  emit
  ! grep -q "HEAD:$BR" "$BATS_TEST_TMPDIR/out" || { echo "the invented-ref push spelling is back"; false; }
  true
}

@test "a missing branch is a REFUSAL, never a contract naming nothing" {
  # An empty branch would emit `git switch -c ` — a syntax error the VM would report as its own
  # confusion, on a session that then pushes nowhere.
  run bash -c '. "$1"; cc_cloud_return_contract' _ "$LIB"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "the seed message names the branch, and the reconciler does NOT depend on it" {
  # The message is a convenience for a human reading `git log`. The consumer that must recognise a
  # boot marker tests CONTENT (scripts/cloud-reconcile.sh's seed_only: an empty range diff), so a
  # VM that reworded it still gets classified correctly. Asserted here as a PAIR so the two facts
  # cannot drift into "the message is the contract".
  run bash -c '. "$1"; cc_cloud_seed_message "$2"' _ "$LIB" "$BR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$BR"* ]] || false
  [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" -eq 0 ]   # one line, no trailing newline
  grep -q 'diff --quiet' "$ROOT/scripts/cloud-reconcile.sh"
  ! grep -q 'cloud session boot marker' "$ROOT/scripts/cloud-reconcile.sh" \
    || { echo "the reconciler matches the seed MESSAGE — content is the test, not the wording"; false; }
}

@test "the contract says what a FAILED seed push should do — silence there is the worst case" {
  # If the three lines fail, the operator sees exactly what they would see if the VM never booted.
  # The VM is the only witness, and its final message is the only channel that carries it.
  emit
  grep -q 'FAILS' "$BATS_TEST_TMPDIR/out"
}
