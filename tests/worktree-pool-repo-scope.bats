#!/usr/bin/env bats
# worktree-pool repo-scope — the canonical workflow doc must not sell RESO's pool as this repo's.
#
# WHY THIS SUITE EXISTS (2026-08-20, backlog 9a14c2ef8224, drain recycle #75).
# `scripts/worktree-pool.sh` has never existed in claude-infrastructure — `git log --all
# --diff-filter=A` on it is empty, positive-controlled against handoff-fire.sh which returns its
# add commit. It lives in reso (`~/Development/reso-management-app/scripts/worktree-pool.sh`, added
# by reso `fdbf0b2d5`) and at `~/.reso/bin/worktree-pool.sh`, and all ten slots at
# `~/Development/.worktrees/wt-pool-N` are live and reso-owned.
#
# An agent working IN this repo read the then-unqualified "10 pre-provisioned slots" claim in
# docs/WORKTREE_WORKFLOW.md § 5, found no such file, and filed a "PHANTOM — decide delete-or-build"
# item. It survived three recycles. BOTH of its prescribed remedies are harmful, which is what
# tests 3-5 pin:
#
#   * DELETE the references → removes the very gate that stops a cross-repo misfire.
#     handoff-fire.sh reaches the pool through a REPO-RELATIVE probe, `POOL="$REPO/scripts/
#     worktree-pool.sh"`, and then re-checks slot ownership by git-common-dir, because on
#     2026-07-24 all ten slots were reso's while the fire was claude-infrastructure's and `claim`
#     handed back a reso path without complaint. POOL_ELIGIBLE=0 in this repo is that gate
#     WORKING, not dead code.
#   * BUILD/cherry-pick a pool here → a second repo's pool contending for the same shared
#     `wt-pool-N` namespace, which the gate's own comment names as the hazard it defends against.
#
# The generalisable shape: an absent file reached through `$REPO/` is not a phantom, it is a
# capability this repo does not have — and a correction that lands only in a SECONDARY document
# does not retract the primary one. The correct reading was already recorded twice (docs/plans/
# WORKTREE_MANAGEMENT_V2.md, docs/research/repo-semantics.md) while the canonical workflow doc
# kept minting the false premise. Fixing the canonical doc is what removes the minting source.
#
# ARMS. Tests 1-2 are RED before the doc fix and green after — they are the regression proof.
# Tests 3-6 are GREEN ON BOTH ARMS BY DESIGN and are named as such: they do not prove the fix,
# they protect the mechanisms a future "clean up the phantom references" sweep would break, and
# they invalidate the doc note's own premise if this repo ever grows a real pool. Test 7 is the
# instrument's positive control.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DOC="$REPO/docs/WORKTREE_WORKFLOW.md"
  FIRE="$REPO/scripts/handoff-fire.sh"
  LAUNCHER="$REPO/lib/claude-launcher.zsh"
  # Fixture $HOME. Nothing here reads it today, but this suite greps paths that MENTION
  # ~/.reso and ~/Development/.worktrees, and a future assertion that resolved one of them
  # would otherwise read the operator's live pool. Hermetic by construction, not by luck.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # test-hermeticity-lint ratchet. This suite only ever READS handoff-fire.sh as text, but the
  # lint keys on naming it, and its refusal is the right default: fixturing $HOME does NOT
  # redirect an absolute /tmp default or a BARE NAME executed off the operator's PATH. Pinning
  # these is free here and keeps the suite honest if an assertion ever does resolve one. The
  # lint states explicitly: do NOT add to the fire or seam allowlists.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
}

# Fixed-string occurrence count that cannot be fooled by grep -c's exit 1 on zero matches
# (which prints a true "0" AND fails, so a bare `|| echo 0` emits TWO lines — the vacuous-pass
# trap this repo has met before). Callers assert the file exists separately, so an empty
# result here can only mean "no match", never "no file".
count_fixed() {
  local n
  n="$( { grep -cF -- "$1" "$2" || true; } | head -1 )"
  printf '%s' "${n:-0}"
}

@test "doc section 5 declares itself reso-scoped and names this repo's own land path" {
  [ -f "$DOC" ]
  [ "$(count_fixed 'this section describes RESO' "$DOC")" -ge 1 ]
  [ "$(count_fixed 'claude-infrastructure lands through' "$DOC")" -ge 1 ]
  [ "$(count_fixed 'scripts/ship-land.sh' "$DOC")" -ge 1 ]
}

@test "doc warm-pool claim carries a repo qualifier instead of a bare path" {
  [ -f "$DOC" ]
  # The paragraph that minted the item must now say whose pool it is AND what this repo does.
  [ "$(count_fixed 'this repo ships no pool and' "$DOC")" -ge 1 ]
  # And the exact unqualified opening that was read as a local capability is gone.
  # shellcheck disable=SC2016  # a literal doc substring, deliberately unexpanded
  [ "$(count_fixed '**Warm pool feeds the front** (`scripts/worktree-pool.sh`)' "$DOC")" -eq 0 ]
}

@test "green both arms by design - handoff-fire keeps the repo-relative pool probe" {
  # A "delete the phantom references" sweep would strip this line. The probe is the capability
  # test; without it the pool is either always-on or always-off for every repo.
  [ -f "$FIRE" ]
  # shellcheck disable=SC2016  # matching the literal `$REPO` in the probe, not its value
  [ "$(count_fixed 'POOL="$REPO/scripts/worktree-pool.sh"' "$FIRE")" -ge 1 ]
}

@test "green both arms by design - handoff-fire keeps the slot-ownership refusal" {
  # The second half of the gate: an executable pool proves a pool EXISTS, not that its slots
  # belong to $REPO. Removing this reinstates the 2026-07-24 cross-repo misfire.
  [ -f "$FIRE" ]
  [ "$(count_fixed 'pool refused, using the cold path' "$FIRE")" -ge 1 ]
  [ "$(count_fixed 'hf_git_owner' "$FIRE")" -ge 2 ]
}

@test "green both arms by design - launcher pool claim stays scoped to reso" {
  # lib/claude-launcher.zsh consults ~/.reso/bin/worktree-pool.sh FIRST and unconditionally,
  # which would claim reso slots for any repo were it not for this basename gate.
  [ -f "$LAUNCHER" ]
  [ "$(count_fixed 'reso-management-app' "$LAUNCHER")" -ge 1 ]
  [ "$(count_fixed '.reso/bin/worktree-pool.sh' "$LAUNCHER")" -ge 1 ]
}

@test "green both arms by design - this repo ships no worktree-pool.sh, the doc note's premise" {
  # If someone ever BUILDS a pool here, this reds and the SCOPE note above must be rewritten
  # before it can go green again — the note may not outlive the fact it asserts.
  [ ! -e "$REPO/scripts/worktree-pool.sh" ]
}

@test "positive control - the doc reader can both find and miss" {
  # Guards every count_fixed assertion above against a silently broken matcher: one phrase that
  # must be present, one that must not, read through the same helper and the same file.
  [ -f "$DOC" ]
  [ "$(count_fixed 'worktree-pool.sh' "$DOC")" -ge 1 ]
  [ "$(count_fixed 'a-phrase-that-must-never-appear-in-this-doc' "$DOC")" -eq 0 ]
}
