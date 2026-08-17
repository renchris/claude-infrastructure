#!/usr/bin/env bats
# ship-land.sh `rebase_onto_trunk` — continue a rebase whose conflict git rerere ALREADY resolved.
#
# WHY THIS FILE EXISTS. `git rebase` exits non-zero the moment a conflict stops it, even when
# rerere.autoupdate has replayed a recorded resolution and staged every path. ship-land read only
# that exit code and called it "resolve it by hand" (exit 5), discarding a resolution git had
# already applied. Measured 2026-08-17: 789 refs/land/failed pins, the top branch retried 112
# times over 5 days, none ever diagnosed — and a retry can NEVER fix a discarded resolution, which
# is why the pin count grew instead of the queue draining.
#
# The function is extracted BY NAME from the real scripts/ship-land.sh (which has no sourced-guard
# and would run main() if sourced), so these cases execute the shipped bytes, not a copy that can
# drift (memory: control-must-replay-the-real-artifact).
#
# One case per DIRECTION, because the guard can fail two opposite ways and a suite that only
# proves the fix works credits nothing against a too-permissive one (memory:
# guard-proxy-fails-in-both-directions, per-site-mutation-attributes-coverage):
#   1. rerere replay        → MUST continue   (the defect this fixes)
#   2. real unmerged paths  → MUST refuse     (too-weak half: not everything was replayed)
#   3. staged markers       → MUST refuse     (too-strong half: never land `<<<<<<<` on trunk)
#   4. no conflict at all   → MUST succeed    (control: the happy path is untouched)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Fixture $HOME before any git call. Not ceremony here: rerere.enabled/autoupdate are GLOBAL
  # settings on this box, so a suite reading the live ~/.gitconfig would pass or fail on the
  # operator's config rather than on the subject. Every fixture below sets them per-repo instead.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"

  # Extract rebase_onto_trunk() from the real lander into a sourceable snippet.
  FN="$BATS_TEST_TMPDIR/fn.sh"
  awk '/^rebase_onto_trunk\(\) \{/{f=1} f{print} f&&/^\}$/{exit}' \
    "$REPO/scripts/ship-land.sh" > "$FN"
  # Positive control on the INSTRUMENT: an empty/!mismatched extraction would make every case
  # below vacuously pass (memory: verification-harness-vacuous-pass-traps).
  grep -q 'git rebase --continue' "$FN"
  grep -q '^rebase_onto_trunk() {' "$FN"

  WORK="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$WORK"
  cd "$WORK" || return 1
  git init -q -b main .
  git config user.email t@t.t; git config user.name t
  git config rerere.enabled true
  git config rerere.autoupdate true
  printf 'base\n' > f.txt
  git add f.txt; git commit -qm base
  # a bare "origin/main" the helper can name without a real remote
  git branch -f origin-main main
  git symbolic-ref refs/remotes/origin/main refs/heads/origin-main
}

# Build a topic branch that conflicts with trunk on the same line.
mk_conflict() {  # $1=trunk-content $2=topic-content
  git checkout -q origin-main
  printf '%s\n' "$1" > f.txt; git commit -qam trunkside
  git checkout -q -b topic main
  printf '%s\n' "$2" > f.txt; git commit -qam topicside
}

@test "rerere replay: a conflict git already resolved is CONTINUED, not refused" {
  mk_conflict trunkline topicline

  # Teach rerere the resolution once, by hand.
  run git rebase origin/main
  [ "$status" -ne 0 ]
  printf 'resolved\n' > f.txt
  git add f.txt
  GIT_EDITOR=true git rebase --continue

  # Rewind the topic branch and replay: rerere now auto-stages the same resolution.
  # (--continue leaves HEAD on topic, so the reset alone rewinds it.)
  git reset -q --hard main
  printf 'topicline\n' > f.txt; git commit -qam topicside2

  # shellcheck disable=SC1090
  source "$FN"
  run rebase_onto_trunk main
  [ "$status" -eq 0 ]

  # and it really landed the resolution: rebase finished, trunk is an ancestor, no markers
  [ ! -d "$(git rev-parse --git-path rebase-merge)" ]
  git merge-base --is-ancestor origin/main HEAD
  run grep -c '<<<<<<<' f.txt
  [ "$output" = "0" ]
}

@test "real conflict (nothing recorded): still REFUSES with rc 1, rebase left in progress" {
  mk_conflict trunkonly topiconly   # rerere has never seen this pair

  # shellcheck disable=SC1090
  source "$FN"
  run rebase_onto_trunk main
  [ "$status" -eq 1 ]

  # the author's recovery path is unchanged: rebase still in progress, path still unmerged
  [ -d "$(git rev-parse --git-path rebase-merge)" ]
  run git diff --name-only --diff-filter=U
  [ -n "$output" ]
}

@test "fully-staged content carrying conflict markers is REFUSED, never continued" {
  # NOT a rerere replay — measured 2026-08-17, rerere records ZERO postimages when the staged
  # resolution still contains markers, so git can never replay one and a test written that way
  # would pin an unreachable case (memory: cap-whose-population-is-empty). The REACHABLE
  # population is a non-rerere stager: an earlier aborted attempt or a merge driver that left
  # every path staged with markers still in it. That satisfies the helper's only precondition
  # ("nothing unmerged"), so this arm is what stops `<<<<<<<` reaching trunk.
  mk_conflict trunkmark topicmark

  run git rebase origin/main
  [ "$status" -ne 0 ]
  printf '<<<<<<< HEAD\ntrunkmark\n=======\ntopicmark\n>>>>>>> topic\n' > f.txt
  git add f.txt                      # every path now staged, nothing unmerged
  run git diff --name-only --diff-filter=U
  [ -z "$output" ]                   # precondition really is met — the case is not vacuous

  # shellcheck disable=SC1090
  source "$FN"
  run rebase_onto_trunk main
  [ "$status" -eq 1 ]
  [[ "$output" == *"staged conflict markers"* ]]
}

@test "control: a rebase with no conflict at all still returns 0" {
  git checkout -q -b topic main
  printf 'base\nextra\n' > other.txt
  git add other.txt; git commit -qm topiconly

  # shellcheck disable=SC1090
  source "$FN"
  run rebase_onto_trunk main
  [ "$status" -eq 0 ]
}
