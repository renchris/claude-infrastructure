#!/usr/bin/env bats
# scripts/lib/cloud-brief.sh — THE BOOT CONTRACT and its detector.
#
# WHY THIS FILE EXISTS. CLOUD_OBSERVABILITY.md §4.1 is the load-bearing paragraph of the whole
# cloud-observability stack: absence is ambiguous, there is no inbound channel to a cloud VM, and
# the ONLY thing that makes `no ref` informative is a contract requiring the session's first act to
# be a push. That contract was prose and nothing else (backlog 0c8b39b67665) — measurable on trunk
# as zero occurrences of the instruction in any payload, and as an API leg that shipped the
# operator's brief verbatim without so much as naming the branch. This file is the contract's
# coverage, and it is written against EFFECTS (the emitted text, the verdict over a real git range)
# rather than against the source, for the same reason cases 9-19 of tests/handoff-fire-cloud.bats
# are: the previous version of this contract passed review as prose for months.
#
# THE DETECTOR IS THE HALF THAT COULD SILENTLY OVER-REACH. Making the first push mandatory means a
# branch now exists for a session's whole working life, so scripts/cloud-return.sh's completion
# conjunction can be satisfied by a session that has produced nothing (§13.6: `worker_status: idle`
# is the between-turns state, and three minutes of thinking is three minutes of quiet).
# `cc_cloud_boot_only` is what stops that becoming a false completion — and a false completion is
# strictly worse than the stranding the contract exists to end, so its two halves are pinned
# SEPARATELY. Cases 4 and 5 are that pair: neither the tree test nor the token test may carry the
# verdict alone.
#
# RED-PROOF, and it is MUTATION rather than replay. Replayed against the pre-change tree every case
# here SKIPS — `scripts/lib/cloud-brief.sh` is absent, and setup() names that absence rather than
# dying on 127 — so a replay proves the subject is new and nothing about whether these assertions
# discriminate. The four cases that DO go red on the pre-change tree live in the callers
# (tests/handoff-fire-cloud.bats 20-21, tests/cc-offload.bats' two boot-contract cases). What pins
# this file is per-site mutation, RUN 2026-08-24, each convicting the case that names it:
#   · drop `--allow-empty` from the block        → cases 2 AND 3 (3 anchors the ordering on that
#                                                  same line, so it is a co-signer here, not a
#                                                  second detector — case 2 is the attribution)
#   · drop the tree test from cc_cloud_boot_only → case 4 only
#   · drop the token test                        → case 5 only
#   · treat an EMPTY range as boot-only          → case 7 only
#   · return 0 instead of 2 when it cannot look  → case 8 only

setup() {
  # Fixture $HOME even though the subject reads nothing under it: git itself does (~/.gitconfig,
  # and the fixture repo below would otherwise inherit the operator's identity, hooks path and
  # template dir), and a suite that is hermetic only because of what its subject happens not to
  # read today is hermetic by luck. scripts/test-hermeticity-lint.sh runs in the land gate.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1
  LIB="${BATS_TEST_DIRNAME}/../scripts/lib/cloud-brief.sh"
  [ -f "$LIB" ] || skip "scripts/lib/cloud-brief.sh not present"
  # shellcheck disable=SC1090
  . "$LIB"
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R"
  git -C "$R" init -q
  git -C "$R" config user.email t@t
  git -C "$R" config user.name t
  git -C "$R" config commit.gpgsign false
  echo base > "$R/base.txt"
  git -C "$R" add base.txt
  git -C "$R" commit -q -m "chore: base"
  git -C "$R" branch trunkref
}

# The branch under test always starts from trunkref, so `merge-base trunkref <ref>` is the base
# commit and the range is exactly what the helper writes into it.
on_branch() { git -C "$R" checkout -q -b "$1" trunkref; }

@test "1 the block names the branch it was handed, and nothing else" {
  run cc_cloud_return_block "claude/fire-ABC123"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git switch -c claude/fire-ABC123"* ]] || false
  [[ "$output" == *"git push -u origin HEAD"* ]] || false
  # A block that renders a literal placeholder is worse than one that fails: it fires, and the VM
  # pushes to a branch nothing watches.
  [[ "$output" != *'$branch'* ]] || false
  [[ "$output" != *'<branch>'* ]] || false
}

@test "2 the prescribed boot commit is EMPTY and carries the token the detector greps for" {
  local msg tok
  msg="$(cc_cloud_boot_commit_message)"
  tok="$(cc_cloud_boot_token)"
  [[ "$msg" == *"$tok"* ]] || { echo "the message does not carry its own token"; false; }
  run cc_cloud_return_block "claude/fire-ABC123"
  # --allow-empty is the contract's own words ("an empty commit is enough"), and without it a VM
  # with a clean tree cannot obey the instruction at all: `git commit` refuses, and the session's
  # FIRST act becomes an error.
  [[ "$output" == *"git commit --allow-empty -m \"$msg\""* ]] || false
  # ONE spelling. The payload and the detector agreeing by coincidence is the failure that a shared
  # library exists to prevent, so the emitted text must contain the detector's own token verbatim.
  [[ "$output" == *"$tok"* ]] || false
}

@test "3 the boot push comes FIRST — before the work push, which is the entire contract" {
  local out boot work
  out="$(cc_cloud_return_block "claude/fire-ABC123")"
  boot="$(printf '%s\n' "$out" | grep -n -- '--allow-empty' | head -1 | cut -d: -f1)"
  work="$(printf '%s\n' "$out" | grep -n 'Then do the work' | head -1 | cut -d: -f1)"
  [ -n "$boot" ] || { echo "the block never prescribes the boot commit"; false; }
  [ -n "$work" ] || { echo "the block never tells the session to push its actual work"; false; }
  [ "$boot" -lt "$work" ] || { echo "the boot push must PRECEDE the work (boot=$boot work=$work)"; false; }
  # And it must say so in words, not merely by ordering: a session that reads the block as a
  # finishing checklist obeys the order and still pushes nothing for twenty minutes.
  [[ "$out" == *"FIRST ACT"* ]] || false
}

@test "4 a token commit that CHANGES A FILE is not boot-only — the tree test is binding" {
  on_branch work
  echo hi > "$R/real.txt"
  git -C "$R" add real.txt
  git -C "$R" commit -q -m "$(cc_cloud_boot_commit_message)"
  run cc_cloud_boot_only "$R" trunkref refs/heads/work
  [ "$status" -eq 1 ] || { echo "a range carrying real work was called boot-only (status $status)"; false; }
}

@test "5 an empty commit WITHOUT the token is not boot-only — the token test is binding too" {
  on_branch empty
  git -C "$R" commit -q --allow-empty -m "chore: something else entirely"
  run cc_cloud_boot_only "$R" trunkref refs/heads/empty
  [ "$status" -eq 1 ] || { echo "someone else's empty commit was claimed by this contract (status $status)"; false; }
}

@test "6 the boot marker alone IS boot-only, and a marker plus work is NOT" {
  on_branch boot
  git -C "$R" commit -q --allow-empty -m "$(cc_cloud_boot_commit_message)"
  run cc_cloud_boot_only "$R" trunkref refs/heads/boot
  [ "$status" -eq 0 ] || { echo "the boot marker was not recognised (status $status)"; false; }

  # The transition this whole design turns on: the same branch, one real commit later, must stop
  # being boot-only — otherwise the contract would convert "returns empty" into "never returns".
  echo hi > "$R/real.txt"
  git -C "$R" add real.txt
  git -C "$R" commit -q -m "feat: the actual work"
  run cc_cloud_boot_only "$R" trunkref refs/heads/boot
  [ "$status" -eq 1 ] || { echo "a booted session that then did work still reads boot-only (status $status)"; false; }
}

@test "7 an EMPTY range is NOT boot-only — nothing at all is a different state, with its own report" {
  on_branch nothing
  run cc_cloud_boot_only "$R" trunkref refs/heads/nothing
  [ "$status" -eq 1 ] || { echo "a range with no commits was renamed after this contract (status $status)"; false; }
}

@test "8 a range it CANNOT READ is 2, never 0 — an unmeasurable range is not an empty one" {
  run cc_cloud_boot_only "$BATS_TEST_TMPDIR/no-such-repo" trunkref refs/heads/boot
  [ "$status" -eq 2 ] || { echo "a missing repo did not abstain (status $status)"; false; }
  # A ref that does not exist has no merge-base, so there is no range to judge. Reading that as
  # boot-only would make every unresolvable branch skippable — the sensor-failure-as-absence defect
  # this stack refuses everywhere else (cc-cloud's ls-remote rc, cloud-reconcile's exit 69).
  run cc_cloud_boot_only "$R" trunkref refs/heads/does-not-exist
  [ "$status" -eq 2 ] || { echo "an unresolvable ref did not abstain (status $status)"; false; }
}
