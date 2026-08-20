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
#
# 2026-08-20 (cc-backlog 38bddf30180c). The three preconditions above — nothing unmerged, no
# markers, a rebase in progress — turned out to be satisfied by two states that are NOT a rerere
# replay, and the guard misfired in OPPOSITE directions on them. Four more cases, again one per
# direction, because a fix for either half alone is exactly the too-permissive/too-strict pair:
#   5. pick emptied out       → MUST skip and succeed  (the reported FALSE STOP: `--continue`
#                                                       cannot commit an empty pick, `--skip` can)
#   6. unstaged work present  → MUST NOT skip          (too-strong half of 5: an empty INDEX also
#                                                       describes a hand resolution nobody `git
#                                                       add`ed — skipping would eat the author's
#                                                       work, so an unclean worktree refuses)
#   7. leftover onto STALE base → MUST refuse          (the FALSE SUCCESS: `git rebase` refuses to
#                                                       start over an existing state dir, so the
#                                                       loop was finishing SOMEONE ELSE's rebase
#                                                       onto a trunk that had moved)
#   8. leftover onto SAME base  → MUST adopt and finish (too-strong half of 7: a blanket refusal
#                                                       would pass 7 and strand every hand-resolved
#                                                       leftover an exit-5 deliberately leaves)

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

# ── 5-6: the pick that emptied out ──────────────────────────────────────────────────────────────
# Fixtures use the APPLY backend deliberately. Both backends can STOP on a pick that would commit
# nothing, but which one does so by DEFAULT moved across git versions (`--empty` drop/ask/stop), and
# a suite that pinned the merge backend's default would be pinning the git on the box rather than
# the subject. The apply backend reaches the state on every version, and its refusal is verbatim the
# one in the report: "No changes - did you forget to use 'git add'? ... something else already
# introduced the same changes; you might want to skip this patch." The helper's decision is read off
# the TREE (index == HEAD), not off that English, so pinning it here pins it for both backends.
mk_emptied_pick() {  # conflict, then resolve TO TRUNK'S SIDE — which is what a rerere replay does,
                     # and what leaves the commit with nothing left to say.
  git config rebase.backend apply
  mk_conflict trunkline topicline
  printf 'keeper\n' > keeper.txt; git add keeper.txt; git commit -qm "a second, REAL commit"
  run git rebase origin/main
  [ "$status" -ne 0 ]
  printf 'trunkline\n' > f.txt; git add f.txt      # resolution == trunk ⇒ this pick is now empty
}

@test "emptied pick: SKIPPED and the land proceeds — not refused as a conflict" {
  mk_emptied_pick
  # preconditions really are the guard's own, so the case is not vacuous
  run git diff --name-only --diff-filter=U
  [ -z "$output" ]
  git diff --cached --quiet HEAD                   # index == HEAD: the pick would commit nothing

  # shellcheck disable=SC1090
  source "$FN"
  run rebase_onto_trunk main
  [ "$status" -eq 0 ]
  [[ "$output" == *"EMPTY against the rebased tree"* ]] || false

  # the rebase really finished, and the branch's OTHER commit — the one that was never upstream —
  # survived. This is the half the false STOP was costing: a good land abandoned.
  [ ! -d "$(git rev-parse --git-path rebase-apply)" ]
  [ ! -d "$(git rev-parse --git-path rebase-merge)" ]
  git merge-base --is-ancestor origin/main HEAD
  run git log --oneline origin/main..HEAD
  [[ "$output" == *"a second, REAL commit"* ]]
}

@test "empty index but UNSTAGED work: REFUSED, never skipped (the author's resolution survives)" {
  mk_emptied_pick
  git reset -q                                     # unstage: index == HEAD, worktree still edited
  printf 'hand-resolved\n' > f.txt
  git diff --cached --quiet HEAD                   # the skip branch's first condition holds…
  run git diff --quiet
  [ "$status" -ne 0 ]                              # …but there IS unstaged work to lose

  # shellcheck disable=SC1090
  source "$FN"
  run rebase_onto_trunk main
  [ "$status" -eq 1 ]
  [[ "$output" != *"EMPTY against the rebased tree"* ]] || false
  [ "$(cat f.txt)" = "hand-resolved" ]             # not skipped away
}

# ── 7-8: the rebase that was never ours ─────────────────────────────────────────────────────────
mk_leftover() {  # the state an exit-5 deliberately leaves behind: rebase in progress, resolved,
                 # not continued — i.e. the state EVERY re-run of /ship on a failed land begins in.
  mk_conflict trunkline topicline
  run git rebase origin/main
  [ "$status" -ne 0 ]
  printf 'resolved-by-hand\n' > f.txt; git add f.txt
  [ -d "$(git rev-parse --git-path rebase-merge)" ]
}

@test "leftover rebase onto a STALE base: REFUSED, and the author's state is left intact" {
  mk_leftover
  # trunk moves on underneath the leftover rebase
  git update-ref refs/heads/origin-main "$(git commit-tree "$(git rev-parse 'origin/main^{tree}')" \
      -p "$(git rev-parse origin/main)" -m 'trunk moved on')"
  [ "$(cat "$(git rev-parse --git-path rebase-merge)/onto")" != "$(git rev-parse origin/main)" ]

  # shellcheck disable=SC1090
  source "$FN"
  run rebase_onto_trunk main
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT onto the current origin/main"* ]] || false

  # refusing is only safe if it costs the author nothing: their rebase and resolution are untouched
  [ -d "$(git rev-parse --git-path rebase-merge)" ]
  run git diff --cached --name-only
  [[ "$output" == *"f.txt"* ]]
}

@test "leftover rebase onto the SAME base: ADOPTED and finished, not refused" {
  mk_leftover
  [ "$(cat "$(git rev-parse --git-path rebase-merge)/onto")" = "$(git rev-parse origin/main)" ]

  # shellcheck disable=SC1090
  source "$FN"
  run rebase_onto_trunk main
  [ "$status" -eq 0 ]
  [[ "$output" == *"adopting the rebase already in progress"* ]] || false

  [ ! -d "$(git rev-parse --git-path rebase-merge)" ]
  git merge-base --is-ancestor origin/main HEAD
  [ "$(cat f.txt)" = "resolved-by-hand" ]          # the hand resolution is what landed
}
