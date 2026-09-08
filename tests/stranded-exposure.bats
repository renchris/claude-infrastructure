#!/usr/bin/env bats
# stranded-exposure.sh — the repo-wide census. Builds scratch repos (bare "origin" +
# working clone) in BATS_TEST_TMPDIR so origin/<trunk> resolves. No network, no real repo.
#
# The load-bearing case is REBASE-LANDED-BUT-STILL-AHEAD: this repo lands by rebase, so a
# fully-landed branch keeps SHAs trunk cannot reach and reads "ahead" forever. A census
# built on ahead-counts (the 290/342/164 figures this script replaces) reports that as
# exposure. Every assertion below is chosen so a patch-id -> ahead-count mutant goes RED.
#
# Identity is set with an explicit -C carrying a LITERAL path segment, never a bare
# `git config` and never an all-variable target: this repo is one bare repo whose ~100
# linked worktrees share a single .git/config, and `git -C ""` is a no-op that would drop
# the write into the real repo and re-author every session on the machine (2026-08-05).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CENSUS="$REPO/scripts/stranded-exposure.sh"

  # HERMETIC: git reads the operator's ~/.gitconfig for identity, template dir and
  # init.defaultBranch. Without this the fixtures inherit live state and the suite is
  # untrustworthy for everyone landing after it. Identity is set per-repo below, so a
  # HOME with no gitconfig is exactly what these fixtures want.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  git -C "$BATS_TEST_TMPDIR/work" config user.email tester@example.com
  git -C "$BATS_TEST_TMPDIR/work" config user.name tester
  cd "$WORK" || return 1
  git checkout -q -b main
  echo base > base.txt
  git add base.txt
  git commit -q -m base
  git push -q -u origin main
}

field() { echo "$output" | tr ' ' '\n' | grep "^$1=" | cut -d= -f2; }

@test "clean repo: census reports zero stranded and zero drop" {
  run bash "$CENSUS" --trunk origin/main --machine
  [ "$status" -eq 0 ]
  [ "$(field stranded_pids)" -eq 0 ]
  [ "$(field drop_pids)" -eq 0 ]
}

@test "REBASE-LANDED branch reads AHEAD but is NOT stranded (the 164-figure defect)" {
  # Land the content through a rebase so trunk carries the same patch under a new SHA,
  # exactly as ship-land does. The original branch stays unreachable from trunk forever.
  git checkout -q -b feature
  echo landed > landed.txt
  git add landed.txt
  git commit -q -m "feat: content that will land"

  git checkout -q main
  echo drift > drift.txt
  git add drift.txt
  git commit -q -m "chore: trunk moves under the branch"
  git cherry-pick "$(git rev-parse feature)"     # same patch, different SHA
  git push -q origin main

  run bash "$CENSUS" --trunk origin/main --machine
  [ "$status" -eq 0 ]
  # The instrument MUST see the branch as ahead — that is the trap it exists to defuse.
  [ "$(field ahead_shas)" -ge 1 ]
  # …and MUST NOT count it as stranded. An ahead-count mutant fails here.
  [ "$(field landed_pids)" -ge 1 ]
  [ "$(field stranded_pids)" -eq 0 ]
  [ "$(field drop_pids)" -eq 0 ]
}

@test "genuinely dropped file: counted once as STRANDED and as DROP" {
  git checkout -q -b dropped
  echo never > never-landed.txt
  git add never-landed.txt
  git commit -q -m "feat: a file that never reaches trunk"

  run bash "$CENSUS" --trunk origin/main --machine
  [ "$status" -eq 0 ]
  [ "$(field stranded_pids)" -eq 1 ]
  [ "$(field drop_pids)" -eq 1 ]
}

@test "cross-branch DEDUPE: one patch on three branches counts ONCE" {
  # This is the whole reason the script exists — the prose figure summed per-branch counts.
  git checkout -q -b copy-a
  echo shared > shared.txt
  git add shared.txt
  git commit -q -m "feat: shared patch"
  for b in copy-b copy-c; do
    git checkout -q main
    git checkout -q -b "$b"
    git cherry-pick "$(git rev-parse copy-a)"
  done

  run bash "$CENSUS" --trunk origin/main --machine
  [ "$status" -eq 0 ]
  # Three branches carry it; the census reports ONE distinct stranded patch.
  [ "$(field stranded_branches)" -eq 3 ]
  [ "$(field stranded_pids)" -eq 1 ]
}

@test "MODIFIED-not-added is stranded but NOT drop (content loss vs divergence)" {
  # base.txt exists on trunk, so changing it is divergence, never the 07-11 incident class.
  git checkout -q -b edit
  echo more >> base.txt
  git commit -q -am "chore: edit a path trunk already has"

  run bash "$CENSUS" --trunk origin/main --machine
  [ "$status" -eq 0 ]
  [ "$(field stranded_pids)" -eq 1 ]
  [ "$(field drop_pids)" -eq 0 ]
}

@test "BY-DESIGN stratum: a ship/backup-* snapshot is classed apart from named work" {
  git checkout -q -b ship/backup-deadbeef
  echo snap > snapshot.txt
  git add snapshot.txt
  git commit -q -m "chore: pre-rebase snapshot"

  run bash "$CENSUS" --trunk origin/main --machine
  [ "$status" -eq 0 ]
  [ "$(field design_pids)" -eq 1 ]
  [ "$(field design_only_pids)" -eq 1 ]
  [ "$(field named_pids)" -eq 0 ]
}

@test "unresolvable trunk is a NON-VERDICT (exit 2), never an empty census" {
  # Fail closed: resolving trunk to nothing would read every branch as fully stranded.
  run bash "$CENSUS" --trunk origin/no-such-ref --machine
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "NO VERDICT"
}

@test "no recovery recipe is printed — the peer-WIP ruling" {
  git checkout -q -b peer
  echo wip > peer-wip.txt
  git add peer-wip.txt
  git commit -q -m "feat: a peer session's WIP"

  run bash "$CENSUS" --trunk origin/main
  [ "$status" -eq 0 ]
  # The banned thing is a RUNNABLE RECIPE, not the word. The census states the ruling in
  # prose ("not yours to cherry-pick onto trunk"), so matching the bare verb asserts the
  # opposite of what is meant — it fired on the very sentence that carries the ruling.
  ! echo "$output" | grep -qE "git cherry-pick|git rebase|git push" || false
  echo "$output" | grep -q "not yours to cherry-pick"
}
