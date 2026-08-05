#!/usr/bin/env bats
# postland-verify.sh — THE BISECT WALL BOUND.
#
# WHY THIS FILE EXISTS. 2026-08-05: `postland-verify.sh --run-if-needed` (pid 57191) started at
# 00:51:28, was orphaned to PPID 1, and was still alive 12h53m later stuck inside a runaway
# `git bisect run`. Every bisect step wrote a fixture identity into the shared .git/config and
# committed fixture blobs into the real object store; a sibling session cleaned that config at
# 13:06:23 and the runaway undid it seconds later, which is why the first repair read as "did not
# hold". `bisect run` was the last unbounded call in the file. This suite pins the bound.
#
# CONTRACT (each assertion names its clause):
#   B1 bound      `git bisect run` is wall-bounded by POSTLAND_BISECT_TIMEOUT_S (default 900).
#   B2 non-verdict  the bound firing (rc 124) is UNDECIDABLE, never a verdict — `bisect` exits 1,
#                 says so on stderr, and prints NO sha. It must not be readable as success, and it
#                 must not name an innocent commit (C20 REVERTS whatever a bisect names).
#   B3 unwind     the RETURN trap runs on EVERY exit path incl. the cut: `bisect reset` + the
#                 runner tempfile removed. Observable: no $TMPDIR/postland-bisect.* survives.
#   B4 degrade    no timeout(1) ⇒ run UNBOUNDED and LOG it, never skip the bisect. A missing tool
#                 must not silently become a different behaviour.
#   B5 control    with a bound that fits, the bisect still names the first bad commit. This is the
#                 negative control for B1/B2: a bound wired to fire always would turn it red.
#
# POSITIVE CONTROL: B1/B2/B3 drive a fixture bats stub that sleeps far past a 3s bound, so the
# bound is SEEN to fire. A bound that has never been observed firing is not shipped.
#
# ISOLATION: scratch bare origin + clone under $BATS_TEST_TMPDIR, fresh $HOME, stubbed bats. No
# real repo, no real ~/.claude state, no network.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="${CC_POSTLAND_BIN:-$REPO_ROOT/scripts/postland-verify.sh}"
  [ -f "$SUT" ] || skip "postland-verify.sh not present in this worktree"

  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/state"
  export CC_POSTLAND_REPO="$BATS_TEST_TMPDIR/repo"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_POSTLAND_WT_ROOT="$BATS_TEST_TMPDIR/cells"
  export POSTLAND_AUTOREVERT=off
  STUB="$BATS_TEST_TMPDIR/bin"
  export CC_BACKLOG_BIN="$STUB/cc-backlog"
  # The SUT's own TMPDIR, separate from bats' — B3 reads it for the runner tempfile.
  SUTTMP="$BATS_TEST_TMPDIR/sut-tmp"
  RUNLOG="$CC_POSTLAND_DIR/runner.log"
  mkdir -p "$HOME" "$CC_PAGES_DIR" "$STUB" "$SUTTMP"
  local s
  for s in cc-backlog osascript cc-notify; do
    printf '#!/bin/bash\nexit 0\n' > "$STUB/$s"; chmod +x "$STUB/$s"
  done
  export PATH="$STUB:$PATH"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  R="$CC_POSTLAND_REPO"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$R" 2>/dev/null
  git -C "$R" symbolic-ref HEAD refs/heads/main
  # Identity pinned LOCALLY (never --global): this suite is the one that must not repeat the
  # 2026-08-05 shape of writing a fixture identity anywhere a real repo can see it.
  git -C "$R" config user.email tester@example.com
  git -C "$R" config user.name tester
  mkdir -p "$R/tests"
  printf '@test "p" { true; }\n' > "$R/tests/ok.bats"
}

# <n> — n linear commits on main; sets GOOD (first) and BAD (last). A file named BAD appears at
# commit 3 so a bisect over the range has a real, KNOWN first-bad commit to find (B5).
mk_history() {
  local n="$1" i
  for i in $(seq 1 "$n"); do
    printf '%s\n' "$i" > "$R/seq.txt"
    [ "$i" -ge 3 ] && printf 'bad\n' > "$R/BAD"
    git -C "$R" add -A >/dev/null
    git -C "$R" commit -qm "c$i" >/dev/null
    [ "$i" = 1 ] && GOOD="$(git -C "$R" rev-parse HEAD)"
    [ "$i" = 3 ] && FIRSTBAD="$(git -C "$R" rev-parse HEAD)"
  done
  BAD="$(git -C "$R" rev-parse HEAD)"
  git -C "$R" push -q origin main
}

# A bats stub that sleeps <secs> then exits 0. Each bisect STEP costs <secs>, so a bound below it
# is guaranteed to fire — this is the positive control's engine.
stub_bats_sleeping() {
  printf '#!/bin/bash\ncase "${1:-}" in --version) echo "Bats 1.0.0"; exit 0;; esac\nsleep %s\nexit 0\n' "$1" \
    > "$STUB/bats-stub"
  chmod +x "$STUB/bats-stub"
  export CC_POSTLAND_BATS="$STUB/bats-stub"
}

# A bats stub that FAILS exactly where the BAD marker exists — a decidable bisect (B5).
stub_bats_marker() {
  printf '#!/bin/bash\ncase "${1:-}" in --version) echo "Bats 1.0.0"; exit 0;; esac\n[ -f BAD ] && exit 1\nexit 0\n' \
    > "$STUB/bats-stub"
  chmod +x "$STUB/bats-stub"
  export CC_POSTLAND_BATS="$STUB/bats-stub"
}

@test "B1/B2: a bisect that runs past POSTLAND_BISECT_TIMEOUT_S is CUT and reports UNDECIDABLE, never a sha" {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || skip "no timeout(1)"
  mk_history 5
  stub_bats_sleeping 120          # one step alone is 40x the bound

  local t0 t1
  t0="$(date +%s)"
  TMPDIR="$SUTTMP" POSTLAND_BISECT_TIMEOUT_S=3 run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"
  t1="$(date +%s)"

  # B2 — undecidable: exit 1 (verb_bisect's undecidable arm), and NOT 0. A cut must not be readable
  # as success, and it must not be readable as a reproducible red that names a commit.
  [ "$status" -eq 1 ]
  [[ "$output" == *"bisect undecidable"* ]]
  # ...and NO sha anywhere on the output. This is the clause that matters: C20 reverts what a
  # bisect names, so a cut naming an innocent commit is worse than no bisect at all.
  ! [[ "$output" =~ [0-9a-f]{7,40}\ is\ the\ first\ bad\ commit ]]
  ! [[ "$output" =~ ^[0-9a-f]{7,40}$ ]]

  # B1 — the bound actually FIRED: 3s bound + 10s SIGKILL grace, against a 120s-per-step runner.
  # Without the bound this is 120s+ (and the incident's shape was 12h53m).
  [ "$(( t1 - t0 ))" -lt 60 ]
  # ...and it is OUR bound that fired, named with its knob, in the runner log.
  grep -q "bisect CUT at 3s (POSTLAND_BISECT_TIMEOUT_S)" "$RUNLOG"
}

@test "B3: the cut path still unwinds — bisect reset runs and the runner tempfile is removed" {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || skip "no timeout(1)"
  mk_history 5
  stub_bats_sleeping 120

  TMPDIR="$SUTTMP" POSTLAND_BISECT_TIMEOUT_S=3 run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"
  [ "$status" -eq 1 ]

  # (1) `bisect reset` RAN. A cut leaves the cell parked on a probe commit with BISECT_* state in
  # its per-worktree git dir; without the reset the next `bisect start` there fails and the cell's
  # git state is a lie. Asserted against the git dir rather than the cell, because verb_bisect
  # leaves the cell itself behind on EVERY path (true of the success path too — pre-existing, not
  # this bound's doing), which is exactly what makes the state file the discriminating observable.
  run bash -c "find '$R/.git/worktrees' -name 'BISECT_*' 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
  # (2) the runner tempfile is gone — the other half of the same trap line.
  run bash -c "ls -1 '$SUTTMP'/postland-bisect.* 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
}

@test "B4: with no timeout(1) the bisect runs UNBOUNDED and SAYS SO — a missing tool is not a silent skip" {
  mk_history 5
  stub_bats_marker                       # fast + decidable, so unbounded is safe to run here
  # Set-but-EMPTY disables bounding verbatim (the file's documented seam).
  TMPDIR="$SUTTMP" CC_POSTLAND_TIMEOUT_BIN= run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"

  grep -q "bisect UNBOUNDED — no timeout(1) resolved" "$RUNLOG"
  # It RAN — the degradation is "unbounded", not "skipped": it still decided.
  [ "$status" -eq 0 ]
  [[ "$output" == "$FIRSTBAD" ]]
}

@test "B5: with a bound that fits, the bisect still names the first bad commit (control)" {
  mk_history 5
  stub_bats_marker
  TMPDIR="$SUTTMP" POSTLAND_BISECT_TIMEOUT_S=300 run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"

  # If the bound were wired to fire unconditionally, B1/B2 would still pass and only THIS goes red.
  [ "$status" -eq 0 ]
  [[ "$output" == "$FIRSTBAD" ]]
  ! grep -q "bisect CUT at" "$RUNLOG"
}
