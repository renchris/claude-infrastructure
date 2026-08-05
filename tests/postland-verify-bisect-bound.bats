#!/usr/bin/env bats
# postland-verify.sh — THE BISECT BOUNDS: a wall (B1-B5) and a STEP-COUNT cap (B6-B9).
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
#   B6-B9         the STEP-COUNT cap — the second, DISJOINT bound. Its own contract block sits with
#                 those tests below; B7 is the clause a wall-only implementation cannot satisfy.
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
  R="${CC_POSTLAND_REPO:?bisect-bound: fixture repo required}"
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
  [[ "$output" == *"bisect undecidable"* ]] || false
  # ...and NO sha anywhere on the output. This is the clause that matters: C20 reverts what a
  # bisect names, so a cut naming an innocent commit is worse than no bisect at all.
  ! [[ "$output" =~ [0-9a-f]{7,40}\ is\ the\ first\ bad\ commit ]] || false
  ! [[ "$output" =~ ^[0-9a-f]{7,40}$ ]] || false

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
  # Set-but-EMPTY disables bounding verbatim (the file's documented seam). The empty value IS the
  # signal, so the `VAR= cmd` form is deliberate — a quoted '' would test a different seam.
  # shellcheck disable=SC1007
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
  # It is the control for BOTH bounds: the step cap's cut message also begins "bisect CUT at".
  [ "$status" -eq 0 ]
  [[ "$output" == "$FIRSTBAD" ]] || false
  ! grep -q "bisect CUT at" "$RUNLOG"
}

# ── THE STEP-COUNT CAP (B6-B9) ────────────────────────────────────────────────────────────────────
# WHY A SECOND BOUND, when the wall above already stops a runaway. Because the wall caps the DAMAGE
# without addressing the measured CAUSE. The 12h41m walk was not made of slow steps — every step was
# fast and the RANGE GREW: the bisected suite committed into the cell on every invocation, so new
# revisions kept entering the interval and the walk had no fixed point. A per-step bound would never
# have fired at all, and a wall bound cannot tell that shape apart from one slow suite.
#
# This block REPRODUCES that mechanism rather than describing it — stub_bats_committing drives the
# identical shape, and it is the positive control for the cap: a 5-commit range that converges in 2
# steps was measured running 41+ steps under it (2026-08-05, this git).
#
#   B6 cap        a NON-CONVERGING bisect is cut by POSTLAND_BISECT_MAX_STEPS: undecidable, no sha.
#   B7 disjoint   the two bounds share NO failure mode. With no timeout(1) the WALL IS INERT — and
#                 the cap, being plain bash inside the runner, still fires. This is the clause a
#                 wall-only implementation structurally cannot satisfy, and the reason the cap is
#                 not redundant with the wall.
#   B8 off-by-one a bisect finishing in exactly the cap's worth of steps STILL names its culprit.
#                 Pins `-gt` over `-ge`: the runner refuses only on the step AFTER the cap, so the
#                 counter exceeds it iff the cap actually fired. Self-calibrating — it MEASURES the
#                 real step count first, so it cannot rot if the fixture's range changes.
#   B9 unwind     the step-counter tempfile is removed too — the other half of B3's trap line.

# A bats stub that COMMITS into its cwd (= the bisect cell) every invocation and reports bad. This
# is the incident's exact shape: new revisions keep entering the interval and the walk never reaches
# a fixed point. Identity comes from the fixture repo's LOCAL config, never --global.
stub_bats_committing() {
  cat > "$STUB/bats-stub" <<'EOS'
#!/bin/bash
case "${1:-}" in --version) echo "Bats 1.0.0"; exit 0;; esac
date +%s%N >> grew.txt
git add -A >/dev/null 2>&1
git commit -qm "suite-commit" >/dev/null 2>&1
exit 1
EOS
  chmod +x "$STUB/bats-stub"
  export CC_POSTLAND_BATS="$STUB/bats-stub"
}

# The marker stub plus a step counter THE TEST owns. The SUT deletes its own counter on unwind, so
# B8 cannot read it — and a control that measured the subject's bookkeeping instead of the real
# invocation count would decay with the implementation.
stub_bats_marker_counting() {
  STEPLOG="$BATS_TEST_TMPDIR/steps.$1"
  printf '#!/bin/bash\ncase "${1:-}" in --version) echo "Bats 1.0.0"; exit 0;; esac\nprintf x >> "%s"\n[ -f BAD ] && exit 1\nexit 0\n' \
    "$STEPLOG" > "$STUB/bats-stub"
  chmod +x "$STUB/bats-stub"
  export CC_POSTLAND_BATS="$STUB/bats-stub"
}

@test "B6: a bisect whose RANGE GROWS is cut by the step cap — undecidable, never a sha" {
  mk_history 5
  stub_bats_committing            # converges in 2 steps normally; runs away under this stub

  TMPDIR="$SUTTMP" POSTLAND_BISECT_MAX_STEPS=6 run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"

  [ "$status" -eq 1 ]
  [[ "$output" == *"bisect undecidable"* ]] || false
  # C20 REVERTS whatever a bisect names, so a cut must name nothing at all.
  ! [[ "$output" =~ [0-9a-f]{7,40}\ is\ the\ first\ bad\ commit ]] || false
  ! [[ "$output" =~ ^[0-9a-f]{7,40}$ ]] || false
  # ...and it is the CAP that fired, named with its own knob and its own diagnosis.
  grep -q "bisect CUT at the 6-step cap (POSTLAND_BISECT_MAX_STEPS)" "$RUNLOG"
  grep -q "range is NOT SHRINKING" "$RUNLOG"
}

@test "B7: with NO timeout(1) the wall is INERT and the cap still fires — the bounds are disjoint" {
  mk_history 5
  stub_bats_committing
  # Set-but-EMPTY disables bounding verbatim (the file's documented seam), so BISECT_TO CANNOT fire:
  # whatever stops this run is the step cap alone. This is the box the 12h41m runaway ran on, and a
  # wall-only implementation has nothing to stop it here.
  # shellcheck disable=SC1007  # set-but-EMPTY is the seam being tested; a quoted '' is not it
  TMPDIR="$SUTTMP" CC_POSTLAND_TIMEOUT_BIN= POSTLAND_BISECT_MAX_STEPS=6 \
    run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"

  [ "$status" -eq 1 ]
  [[ "$output" == *"bisect undecidable"* ]] || false
  # the degradation is ANNOUNCED, and it names which bound survived
  grep -q "wall is INERT this run" "$RUNLOG"
  grep -q "only the 6-step cap bounds it" "$RUNLOG"
  # the cap did the stopping; the wall demonstrably did not
  grep -q "bisect CUT at the 6-step cap" "$RUNLOG"
  ! grep -q "bisect CUT at 900s" "$RUNLOG"
}

@test "B8: a bisect finishing in exactly the cap's worth of steps still names its culprit (-gt, not -ge)" {
  mk_history 5

  # (1) MEASURE the real step count, with a cap far too large to interfere.
  stub_bats_marker_counting a
  TMPDIR="$SUTTMP" POSTLAND_BISECT_MAX_STEPS=99 run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"
  [ "$status" -eq 0 ]
  [[ "$output" == "$FIRSTBAD" ]] || false
  local n; n="$(wc -c < "$BATS_TEST_TMPDIR/steps.a" | tr -d ' ')"
  [ "$n" -ge 1 ]

  # (2) re-run with the cap set to EXACTLY that count. The runner refuses only on the step AFTER the
  # cap, so this must still DECIDE. Under `-ge` the culprit is suppressed and this test goes red —
  # which is the whole point: an off-by-one here silently converts good bisects into non-verdicts.
  stub_bats_marker_counting b
  TMPDIR="$SUTTMP" POSTLAND_BISECT_MAX_STEPS="$n" run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"
  [ "$status" -eq 0 ]
  [[ "$output" == "$FIRSTBAD" ]] || false
  ! grep -q "step cap" "$RUNLOG"
}

@test "B9: the cap's cut path unwinds too — no runner and no step-counter tempfile survive" {
  mk_history 5
  stub_bats_committing
  TMPDIR="$SUTTMP" POSTLAND_BISECT_MAX_STEPS=6 run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"
  [ "$status" -eq 1 ]

  # the glob covers BOTH halves — postland-bisect.XXXXXX and its .steps sidecar
  run bash -c "ls -1 '$SUTTMP'/postland-bisect.* 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
  # and the cell is not left parked mid-bisect
  run bash -c "find '$R/.git/worktrees' -name 'BISECT_*' 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
}
