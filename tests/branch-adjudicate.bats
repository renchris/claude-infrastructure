#!/usr/bin/env bats
# branch-adjudicate.bats — the suite for the instrument that decides whether an unlanded
# branch's work reached the trunk RE-DERIVED, or is genuinely absent.
#
# WHY THE CONTROLS ARE THE POINT. This script exists because two earlier spellings of the same
# question passed casual inspection and were refuted by their own controls: a line-identity test
# convicted 12 of 66 known-patch-landed branches, and its history-aware successor still convicted
# cloud-g5-create at ratio 0.04 while every file that branch names sits on trunk. So the cases
# that matter here are not "it runs" — they are the two poles (cases 1 and 2) and, above all,
# cases 7 and 8, which MUTATE the classifier and require the self-check to go RED. Without those,
# every other case in this file would pass just as well against a script that reported
# LANDED-REWORKED unconditionally, and would prove nothing.
#
# HERMETIC: every case builds its own git repo inside $BATS_TEST_TMPDIR under a fixture $HOME and
# a fixture git identity. Nothing reads or writes the real repo, and no case has a remote.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"; : > "$GIT_CONFIG_GLOBAL"
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/branch-adjudicate.py"
  R="$BATS_TEST_TMPDIR/r"; mkdir -p "$R"
  git -C "$R" init -q -b main
  printf '#!/bin/sh\nBASE_CONST=1\n' > "$R/base.sh"
  git -C "$R" add -A; git -C "$R" commit -q -m base
}

# Put <body> at <path> on the current branch and commit it.
put() { mkdir -p "$(dirname "$R/$1")"; printf '%s' "$2" > "$R/$1"; git -C "$R" add -A; git -C "$R" commit -q -m "$3"; }

verdict_of() { # <branch> — the verdict column for one branch
  python3 "$SCRIPT" --repo "$R" --trunk main --json 2>/dev/null \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print(next((r['verdict'] for r in d if r['branch']=='$1'),'NOROW'))"
}

# ── THE TWO POLES ───────────────────────────────────────────────────────────────────────────
@test "1 POSITIVE: work re-derived on trunk reads LANDED-REWORKED, sharing not one line" {
  git -C "$R" checkout -q -b landed-reworked
  put feature.sh '#!/bin/sh
FEATURE_LIMIT=10
feature_apply() { echo apply; }
' "feat: apply"
  git -C "$R" checkout -q main
  put feature.sh '#!/bin/sh
# rewritten by hand on trunk: different bytes, same capability
FEATURE_LIMIT=20
feature_apply() { printf "apply\n"; }
' "feat: apply, re-derived"

  # The control that makes this case mean something: no ADDED LINE of the branch survives on
  # trunk, so a line-identity test convicts here. Assert that premise rather than trusting it.
  run git -C "$R" diff main landed-reworked -- feature.sh
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  [ "$(verdict_of landed-reworked)" = "LANDED-REWORKED" ]
}

@test "2 NEGATIVE: a file trunk never carried reads ABSENT-FILE" {
  git -C "$R" checkout -q -b genuinely-absent
  put orphan.sh '#!/bin/sh
ORPHAN_TIMEOUT=5
orphan_reap() { echo reap; }
' "feat: orphan"
  git -C "$R" checkout -q main
  [ "$(verdict_of genuinely-absent)" = "ABSENT-FILE" ]
}

@test "3 NEGATIVE: a symbol trunk never saw, in a file trunk DOES carry, reads ABSENT-SYMBOLS" {
  # The harder half of loss: the path exists on trunk, so a path-presence test is blind to it.
  git -C "$R" checkout -q -b sym-absent
  put base.sh '#!/bin/sh
BASE_CONST=1
UNSEEN_BOUND=9
unseen_helper() { echo x; }
' "feat: bound"
  git -C "$R" checkout -q main
  [ "$(verdict_of sym-absent)" = "ABSENT-SYMBOLS" ]
}

# ── AGREEMENT WITH THE INSTRUMENT THIS ONE EXTENDS ─────────────────────────────────────────
@test "4 a cherry-picked branch reads PATCH-LANDED — the pruner's own class, reported not re-judged" {
  git -C "$R" checkout -q -b picked
  put picked.sh '#!/bin/sh
PICKED_CONST=3
' "feat: picked"
  git -C "$R" checkout -q main
  # main must DIVERGE first. With a fixed identity and timestamp, cherry-picking a commit
  # straight onto its own parent reproduces a byte-identical sha, so the branch reads
  # ANCESTOR-LANDED and the case would prove nothing about patch equivalence.
  put unrelated.sh '#!/bin/sh
UNRELATED_CONST=7
' "chore: unrelated"
  git -C "$R" cherry-pick picked >/dev/null
  [ "$(verdict_of picked)" = "PATCH-LANDED" ]
}

@test "5 a branch with no unique commits reads ANCESTOR-LANDED" {
  git -C "$R" branch anc main
  [ "$(verdict_of anc)" = "ANCESTOR-LANDED" ]
}

# ── REFUSALS AND SCOPE ──────────────────────────────────────────────────────────────────────
@test "6 backup-named branches are excluded by default and included on demand" {
  git -C "$R" checkout -q -b backup/snap
  put snap.sh '#!/bin/sh
SNAP_ONLY=1
' "chore: snap"
  git -C "$R" checkout -q main
  run python3 "$SCRIPT" --repo "$R" --trunk main
  [ "$status" -eq 0 ]
  ! grep -q 'backup/snap' <<< "$output" || false
  run python3 "$SCRIPT" --repo "$R" --trunk main --include-backups
  [ "$status" -eq 0 ]
  grep -q 'backup/snap' <<< "$output"
}

@test "7 MUTANT: a line-identity classifier must REFUTE the positive control" {
  # This is the exact test the shipped v1 failed. If this case ever passes green against the
  # mutant, the positive control has stopped discriminating and case 1 is decoration.
  m="$BATS_TEST_TMPDIR/m1.py"
  sed 's/^        introduced |= new - old$/        introduced |= {l.strip() for l in run(repo,"show",f"{branch}:{p}").split(chr(10)) if len(l.strip())>=20} - old/' "$SCRIPT" > "$m"
  run python3 "$m" --self-check
  [ "$status" -eq 1 ]
  grep -q 'REFUTED positive control' <<< "$output$stderr" || grep -q 'REFUTED positive control' <<< "$output"
}

@test "8 MUTANT: a classifier that never reports absence must REFUTE the negative control" {
  m="$BATS_TEST_TMPDIR/m2.py"
  sed 's/^    missing = sorted(s for s in introduced if s not in tokens)$/    missing = []/; s/^    missing_paths = \[p for p in added$/    missing_paths = [] or [p for p in [] if p/' "$SCRIPT" > "$m"
  run python3 "$m" --self-check
  [ "$status" -eq 1 ]
  grep -q 'REFUTED negative control' <<< "$output"
}

@test "9 the shipped self-check passes on the shipped classifier" {
  run python3 "$SCRIPT" --self-check
  [ "$status" -eq 0 ]
  grep -q 'self-check ok' <<< "$output"
}

@test "10 a branch held by a live worktree is REFUSED, never adjudicated" {
  # The hazard this closes is not a wrong verdict, it is a wrong ACTION. In the wave that built
  # this script, drain/lane-infra read as the single genuine RECOVER out of 38 signatures and was
  # nine hours old with a worktree holding it: recovering it would have duplicated a peer's open
  # work. A branch somebody is standing on is not stranded.
  git -C "$R" checkout -q -b in-flight
  put live.sh '#!/bin/sh
INFLIGHT_ONLY=1
inflight_fn() { echo x; }
' "feat: in flight"
  git -C "$R" checkout -q main
  # Without a worktree it convicts -- that is the premise this case rests on.
  [ "$(verdict_of in-flight)" = "ABSENT-FILE" ]
  git -C "$R" worktree add -q "$BATS_TEST_TMPDIR/wt" in-flight
  [ "$(verdict_of in-flight)" = "HELD-WORKTREE" ]
}

@test "11 one non-UTF-8 byte in the tree does not stop the census" {
  # Measured: `text=True` raised UnicodeDecodeError on the first binary blob and the whole run
  # printed NOTHING -- a scan that dies silently mid-tree is worse than one that reports a gap.
  printf '\x89PNG\r\n\x1a\n\x96\x00binary' > "$R/logo.png"
  git -C "$R" add -A; git -C "$R" commit -q -m "chore: binary asset"
  git -C "$R" checkout -q -b after-binary
  put later.sh '#!/bin/sh
LATER_CONST=2
' "feat: later"
  git -C "$R" checkout -q main
  run python3 "$SCRIPT" --repo "$R" --trunk main
  [ "$status" -eq 0 ]
  grep -q 'after-binary' <<< "$output"
}

@test "12 a missing trunk ref is a usage error, never a verdict over zero branches" {
  # Fail-closed: the dangerous failure here is exiting 0 with an empty report, which a caller
  # reads as "nothing to adjudicate" (repo memory: suppressed stderr turns a failed command
  # into a clean 0).
  run python3 "$SCRIPT" --repo "$R" --trunk origin/nope
  [ "$status" -eq 2 ]
}
