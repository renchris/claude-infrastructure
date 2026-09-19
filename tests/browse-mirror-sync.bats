#!/usr/bin/env bats
# browse-mirror-sync — the cadence that keeps a human-browsable checkout at its upstream ref.
#
# WHAT THIS SUITE IS FOR. The subject's whole value is that it CANNOT WEDGE: the two failures that
# left ~/Development/reso-management-app showing 1,948-commit-old files (a diverged local branch,
# and a tracked file that `next dev` regenerates) must be absorbed rather than blocking, while the
# one case that SHOULD stop it — an untracked file a human wrote sitting where the target ref wants
# to write one — must stop it loudly and without deleting that file. Those are the assertions here.
#
# WHY REAL REPOSITORIES AND NOT A GIT STUB. Every interesting regime in this subject is one of git's
# own REFUSALS — `checkout` declining an untracked collision, `merge-base --is-ancestor` declining a
# diverged branch. A stub reproduces the refusals it was written to reproduce, which is exactly the
# set that would already have been thought of; the collision case would then be decorative. So each
# test builds a throwaway origin + mirror pair and lets real git decide.
#
# Assertions use the explicit `|| { …; false; }` form throughout: a non-final `[[ ]]` is
# errexit-EXEMPT under bats and would be a DEAD assertion that can never fail
# (memory: bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJECT="$REPO/scripts/browse-mirror-sync.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BROWSE_MIRROR_STATE="$BATS_TEST_TMPDIR/state"
  export CC_BROWSE_MIRROR_DISABLED="$BATS_TEST_TMPDIR/disabled"
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  SEED="$BATS_TEST_TMPDIR/seed"
  MIRROR="$BATS_TEST_TMPDIR/mirror"

  git init --quiet --bare "$ORIGIN"
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
  git clone --quiet "$ORIGIN" "$SEED"
  echo one > "$SEED/tracked.txt"
  git -C "$SEED" add tracked.txt
  git -C "$SEED" commit --quiet -m c1
  git -C "$SEED" push --quiet origin HEAD:main
  C1="$(git -C "$SEED" rev-parse HEAD)"

  git clone --quiet "$ORIGIN" "$MIRROR"
  export CC_BROWSE_MIRRORS="$MIRROR|origin/main"
  export CC_BROWSE_MIRROR_FETCH_MIN=0
}

# Add a commit on origin/main. $1 = file to write, $2 = contents.
advance_origin() {
  echo "$2" > "$SEED/$1"
  git -C "$SEED" add "$1"
  git -C "$SEED" commit --quiet -m "add $1"
  git -C "$SEED" push --quiet origin HEAD:main
  C2="$(git -C "$SEED" rev-parse HEAD)"
}

@test "1: a stale mirror is advanced to the target ref and left DETACHED" {
  advance_origin two.txt two
  git -C "$MIRROR" checkout --quiet --detach "$C1"

  run bash "$SUBJECT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'verdict=advanced' || { echo "$output"; false; }
  [ "$(git -C "$MIRROR" rev-parse HEAD)" = "$C2" ] || { echo "HEAD not at target"; false; }
  # Detached is the property that makes divergence impossible; a mirror back on a branch has lost it.
  run git -C "$MIRROR" symbolic-ref -q HEAD
  [ "$status" -ne 0 ] || { echo "mirror is on a branch, not detached"; false; }
  [ -f "$MIRROR/two.txt" ] || { echo "the new file is not in the working tree"; false; }
}

@test "2: an already-current mirror reports current and does not churn" {
  git -C "$MIRROR" checkout --quiet --detach origin/main
  run bash "$SUBJECT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'verdict=current' || { echo "$output"; false; }
}

@test "3: a tracked modification is ARCHIVED to refs/mirror-rescue and does not block the advance" {
  # This is the `next dev` regenerating AGENTS.md regime: tooling dirties a tracked file, and no
  # human discipline can stop it, so blocking on it means never advancing again.
  advance_origin two.txt two
  git -C "$MIRROR" checkout --quiet --detach "$C1"
  echo "locally-modified" > "$MIRROR/tracked.txt"

  run bash "$SUBJECT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'verdict=advanced' || { echo "$output"; false; }
  echo "$output" | grep -q 'rescued=refs/mirror-rescue/' || { echo "no rescue ref reported: $output"; false; }

  rescue="$(git -C "$MIRROR" for-each-ref --format='%(refname)' refs/mirror-rescue/ | awk 'NR<=1')"
  [ -n "$rescue" ] || { echo "no rescue ref created"; false; }
  # The bytes must be RECOVERABLE, not merely referenced — a ref to the wrong tree is a lost file
  # wearing a receipt.
  [ "$(git -C "$MIRROR" show "$rescue:tracked.txt")" = "locally-modified" ] \
    || { echo "rescue ref does not hold the modification"; false; }
}

@test "4: an untracked collision BLOCKS, and the human's file survives untouched" {
  advance_origin collide.txt from-origin
  git -C "$MIRROR" checkout --quiet --detach "$C1"
  echo "mine-do-not-delete" > "$MIRROR/collide.txt"

  run bash "$SUBJECT"
  [ "$status" -ne 0 ] || { echo "a blocked mirror must exit non-zero: $output"; false; }
  echo "$output" | grep -q 'verdict=blocked' || { echo "$output"; false; }
  [ "$(cat "$MIRROR/collide.txt")" = "mine-do-not-delete" ] \
    || { echo "the untracked file was clobbered"; false; }
  [ "$(git -C "$MIRROR" rev-parse HEAD)" = "$C1" ] || { echo "HEAD moved despite blocking"; false; }
}

@test "5: a local branch that is an ancestor is fast-forwarded; a diverged one is left alone" {
  advance_origin two.txt two

  # Ancestor arm: local main still at C1, which is an ancestor of the target.
  git -C "$MIRROR" checkout --quiet --detach "$C1"
  git -C "$MIRROR" update-ref refs/heads/main "$C1"
  run bash "$SUBJECT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git -C "$MIRROR" rev-parse refs/heads/main)" = "$C2" ] \
    || { echo "an ancestor local branch was not fast-forwarded"; false; }

  # Diverged arm: a commit only on the local branch. This is the wedge that rotted the real folder;
  # the mirror must advance anyway, and must NOT rewrite the branch holding that work.
  git -C "$MIRROR" checkout --quiet -B side "$C1"
  echo diverged > "$MIRROR/tracked.txt"
  git -C "$MIRROR" commit --quiet -am "local-only"
  local_only="$(git -C "$MIRROR" rev-parse HEAD)"
  git -C "$MIRROR" update-ref refs/heads/main "$local_only"
  git -C "$MIRROR" checkout --quiet --detach "$C1"

  run bash "$SUBJECT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'verdict=advanced' || { echo "$output"; false; }
  [ "$(git -C "$MIRROR" rev-parse refs/heads/main)" = "$local_only" ] \
    || { echo "a diverged local branch was rewritten — that destroys work"; false; }
  echo "$output" | grep -q "has diverged" || { echo "divergence was not reported: $output"; false; }
}

@test "6: --dry-run reports the advance and changes nothing" {
  advance_origin two.txt two
  git -C "$MIRROR" checkout --quiet --detach "$C1"

  run bash "$SUBJECT" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'verdict=would-advance' || { echo "$output"; false; }
  [ "$(git -C "$MIRROR" rev-parse HEAD)" = "$C1" ] || { echo "dry-run moved HEAD"; false; }
}

@test "7: the fetch rate-limiter actually gates the network read, in both directions" {
  # The limiter is what keeps a WatchPaths firing free. If it silently never gated, the job would
  # fetch on every ref change; if it never expired, a quiet fleet would leave the mirror pinned to a
  # stale ref while reporting itself current. Both directions are pinned here.
  git -C "$MIRROR" checkout --quiet --detach origin/main

  # PRIME the stamp. With no stamp at all the subject fetches unconditionally, whatever FETCH_MIN
  # says — a fresh install must be allowed to learn where origin is, and that arm is asserted here
  # rather than assumed, because it is the one state in which the limiter deliberately does not hold.
  run bash "$SUBJECT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -n "$(find "$CC_BROWSE_MIRROR_STATE" -name 'fetch.*' 2>/dev/null)" ] \
    || { echo "the first run wrote no fetch stamp, so the limiter can never engage"; false; }

  advance_origin two.txt two          # origin moved; the mirror has not fetched it yet

  CC_BROWSE_MIRROR_FETCH_MIN=99999 run bash "$SUBJECT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'verdict=current' \
    || { echo "the limiter did not gate the fetch: $output"; false; }
  [ "$(git -C "$MIRROR" rev-parse HEAD)" != "$C2" ] || { echo "fetched despite the limiter"; false; }

  CC_BROWSE_MIRROR_FETCH_MIN=0 run bash "$SUBJECT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git -C "$MIRROR" rev-parse HEAD)" = "$C2" ] \
    || { echo "an expired limiter did not let the fetch through"; false; }
}

@test "8: the kill switch stops it, and a missing mirror is reported rather than ignored" {
  advance_origin two.txt two
  git -C "$MIRROR" checkout --quiet --detach "$C1"

  touch "$CC_BROWSE_MIRROR_DISABLED"
  run bash "$SUBJECT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'verdict=disabled' || { echo "$output"; false; }
  [ "$(git -C "$MIRROR" rev-parse HEAD)" = "$C1" ] || { echo "ran despite the kill switch"; false; }
  rm -f "$CC_BROWSE_MIRROR_DISABLED"

  # A mirror directory that has gone away must be LOUD. Silence here is the failure mode the whole
  # subject exists to end — a folder that quietly stops being updated.
  CC_BROWSE_MIRRORS="$BATS_TEST_TMPDIR/not-a-repo|origin/main" run bash "$SUBJECT"
  [ "$status" -ne 0 ] || { echo "a missing mirror must exit non-zero: $output"; false; }
  echo "$output" | grep -q 'verdict=missing' || { echo "$output"; false; }
}

@test "9: the plist and the migration agree with the subject" {
  plist="$REPO/launchd/com.claude.browse-mirror.plist"
  [ -r "$plist" ] || { echo "missing $plist"; false; }
  plutil -lint "$plist" >/dev/null || { echo "plist does not parse"; false; }
  # A cron pointing at the wrong path is a loaded job that mirrors nothing.
  grep -q 'browse-mirror-sync.sh' "$plist" || { echo "plist does not invoke the subject"; false; }
  # WatchPaths is the fast path; without it the folder lags by a whole StartInterval.
  grep -q 'WatchPaths' "$plist" || { echo "plist lost its WatchPaths trigger"; false; }
  # packed-refs must be watched beside the loose refs: git gc moves a ref between the two
  # representations, and a watch on only one goes quiet at an unpredictable moment.
  grep -q 'packed-refs' "$plist" || { echo "plist does not watch packed-refs"; false; }
  grep -q 'migration-class: c10' "$REPO/migrations/0032-browse-mirror.sh" \
    || { echo "the migration must be c10 — it installs a launchd plist"; false; }
}

@test "10: a branch CHECKED OUT in a worktree is never fast-forwarded" {
  # WHAT THIS CASE IS, STATED HONESTLY — it is an EQUIVALENCE GUARD, not a red-proof, and the
  # difference was measured rather than assumed.
  #
  # The property: ff_local_branch must never move a branch that a worktree has checked out. It is
  # the one write in the subject that can disturb someone else's worktree.
  #
  # The bug that motivated it was `git worktree list --porcelain | grep -qx …`. Under pipefail, -q
  # exits on the match, the producer takes SIGPIPE, and the PIPELINE's status is that failure — so
  # the guard reads FALSE on a MATCH and moves the branch anyway. The ship-land
  # pipefail-sigpipe-lint ratchet caught it; this suite did not.
  #
  # AND THIS CASE STILL DOES NOT CATCH IT. Restoring `grep -qx` and running this case was tried:
  # the mutant SURVIVED. `git worktree list --porcelain` emits ~120 bytes per worktree, so any
  # fixture small enough to build in a test writes its whole output into the 64 KiB pipe buffer and
  # exits before grep ever reads — no blocked write, no SIGPIPE, no failure. Reaching the regime
  # needs ~550 worktrees, which is not a test. Adding a handful was tried and bought nothing
  # measurable, so they are not here: a fixture that merely LOOKS like production, while provably
  # not reaching the defect, is worse than none, because it reads as coverage.
  #
  # So the guard for the SIGPIPE class is the STATIC ratchet at the land gate, which is the right
  # chokepoint for a pattern that is cheap to see in source and expensive to reach at runtime. What
  # this case is worth: it pins the OUTCOME property against the reachable ways a future refactor
  # could break it (an inverted condition, a dropped guard, a wrong branch name).
  advance_origin two.txt two
  git -C "$MIRROR" checkout --quiet --detach "$C1"
  git -C "$MIRROR" update-ref refs/heads/main "$C1"
  git -C "$MIRROR" worktree add --quiet "$BATS_TEST_TMPDIR/wt-main" main

  run bash "$SUBJECT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'verdict=advanced' || { echo "$output"; false; }
  [ "$(git -C "$MIRROR" rev-parse refs/heads/main)" = "$C1" ] \
    || { echo "fast-forwarded a branch that a worktree has checked out"; false; }
}

