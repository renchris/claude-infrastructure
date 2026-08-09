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
#   B10-B11       the ENDPOINT CONFIRMATION — a THIRD, disjoint clause, and not a bound at all: it
#                 constrains what a bisect that FINISHES inside both bounds is allowed to name. Its
#                 own contract block sits with those tests below.
#   B13-B16       the same clause for the OTHER endpoint, the FLOOR. B10-B12 cover `bad`; a walk that
#                 converges on the first commit after `good` measured that end no better. Own block.
#   B17-B18       a FOURTH clause, and the first that looks at what a fired bound left BEHIND rather
#                 than at how the SUT returned from it: the kill must reach the wedged bats itself,
#                 and every $BATS_BIN call site must be under a bound at all. Own block below.
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

# <n> [bad_at=3] [late_file] — n linear commits on main; sets GOOD (first) and BAD (last). A file
# named BAD appears at commit <bad_at> so a bisect over the range has a real, KNOWN first-bad commit
# to find (B5). bad_at is a parameter because WHERE the first-bad sits relative to GOOD is the axis
# B13-B16 turn on: at the default 3 the walk earns a green probe of its own (c2), at 2 it earns none.
# <late_file>, when given, is BORN at that same commit — a suite that does not exist at the floor,
# which is the shape B16 pins.
mk_history() {
  local n="$1" bad_at="${2:-3}" late="${3:-}" i
  for i in $(seq 1 "$n"); do
    printf '%s\n' "$i" > "$R/seq.txt"
    [ "$i" -ge "$bad_at" ] && [ -n "$late" ] && printf '@test "late" { false; }\n' > "$R/$late"
    [ "$i" -ge "$bad_at" ] && printf 'bad\n' > "$R/BAD"
    git -C "$R" add -A >/dev/null
    git -C "$R" commit -qm "c$i" >/dev/null
    [ "$i" = 1 ] && GOOD="$(git -C "$R" rev-parse HEAD)"
    [ "$i" = 2 ] && SECOND="$(git -C "$R" rev-parse HEAD)"
    [ "$i" = "$bad_at" ] && FIRSTBAD="$(git -C "$R" rev-parse HEAD)"
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

# ── B10-B11 — THE ENDPOINT CONFIRMATION ───────────────────────────────────────────────────────────
# Not a bound. B1-B9 constrain how LONG a bisect may run; this constrains what a bisect that finished
# well inside both bounds is allowed to NAME.
#
# `git bisect` takes BOTH endpoints on trust and probes only until ONE candidate remains, which it
# then DECLARES without running. So when every interior probe returns GOOD the walk narrows onto the
# tip and reports it as "the first bad commit" having never executed one step there — a verdict of the
# ASSUMPTION about the single commit it did not measure. C20 REVERTS whatever a bisect names, so that
# verdict lands a revert on trunk with zero evidence behind it. (B10's 5-commit range is that shape;
# a range holding a single candidate probes it instead, which is why the guard keys on the VERDICT
# being the tip rather than on how the walk arrived there.)
#
#   B10 confirm   a walk that names the TIP must CONFIRM the tip reproduces red ALONE. Not red there
#                 ⇒ undecidable, no sha. This is the 2026-08-06 incident: a red that does not
#                 reproduce in isolation (tests/handoff-fire-kitty-daemon.bats, already red for 12h
#                 before the land) probed green through the interior and convicted e80c85aa2e47,
#                 whose entire diff is a DIFFERENT test file. Revert f323b427 re-opened the very red
#                 e80c85aa had just fixed.
#   B11 control   ...and a GENUINE tip regression is still named and still revertable. This is the
#                 clause an implementation that simply suppressed every tip verdict would fail, and
#                 without it B10 is satisfiable by never naming a tip at all — which would silently
#                 retire auto-revert for the commonest regression shape there is (the last commit
#                 broke it, the interior is clean).
#
# The pair is discriminated by ONE fact — whether the tip is really red — with the same stub, the same
# range length and the same verb, so nothing but the confirmation itself can separate them.

# <n> — n linear commits where the BAD marker appears ONLY at the LAST one, so the true first-bad
# commit IS the tip. mk_history puts it at commit 3 (interior) and cannot express this shape.
mk_history_tip_bad() {
  local n="$1" i
  for i in $(seq 1 "$n"); do
    printf '%s\n' "$i" > "$R/seq.txt"
    [ "$i" -eq "$n" ] && printf 'bad\n' > "$R/BAD"
    git -C "$R" add -A >/dev/null
    git -C "$R" commit -qm "c$i" >/dev/null
    [ "$i" = 1 ] && GOOD="$(git -C "$R" rev-parse HEAD)"
  done
  BAD="$(git -C "$R" rev-parse HEAD)"
  git -C "$R" push -q origin main
}

# A bats stub that PASSES everywhere — the faithful model of a corpus red that does not reproduce in
# isolation. Every interior probe says GOOD, which is precisely what walks a bisect onto the tip.
stub_bats_green() {
  printf '#!/bin/bash\ncase "${1:-}" in --version) echo "Bats 1.0.0"; exit 0;; esac\nexit 0\n' \
    > "$STUB/bats-stub"
  chmod +x "$STUB/bats-stub"
  export CC_POSTLAND_BATS="$STUB/bats-stub"
}

@test "B10: a walk that lands on the TIP must CONFIRM it — green there ⇒ undecidable, never a sha" {
  mk_history 5
  stub_bats_green                 # nothing is red anywhere ⇒ the interior probes green ⇒ tip named

  TMPDIR="$SUTTMP" run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"

  [ "$status" -eq 1 ]
  [[ "$output" == *"bisect undecidable"* ]] || false
  # THE clause: C20 reverts what a bisect names, and this walk measured nothing about the tip.
  ! [[ "$output" =~ [0-9a-f]{7,40}\ is\ the\ first\ bad\ commit ]] || false
  ! [[ "$output" =~ ^[0-9a-f]{7,40}$ ]] || false
  [[ "$output" != *"$BAD"* ]] || false
  # ...and the abstention came from the CONFIRMATION, not from a bound or a parse that happened to
  # come back empty. Without this the test passes for the wrong reason on any future cut.
  grep -q "bisect UNCONFIRMED" "$RUNLOG"
  grep -q "without ever running it" "$RUNLOG"
  ! grep -q "bisect CUT" "$RUNLOG"
}

@test "B11: CONTROL — a GENUINE tip regression is still named (the confirmation confirms, not suppresses)" {
  mk_history_tip_bad 5            # the true first-bad commit IS the tip this time...
  stub_bats_marker                # ...and it reproduces ALONE, which is the whole difference

  TMPDIR="$SUTTMP" run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"

  [ "$status" -eq 0 ]
  [[ "$output" == "$BAD" ]] || false
  ! grep -q "bisect UNCONFIRMED" "$RUNLOG"
}

@test "B12: the confirmation path unwinds too — no cell parked mid-bisect, no tempfile survives" {
  # B3/B9 pin the unwind for the two CUT paths; the confirmation adds a third exit (and it is the one
  # that runs `bisect reset` itself, before checking the tip out, so it must not leave a half-reset cell).
  mk_history 5
  stub_bats_green
  TMPDIR="$SUTTMP" run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"
  [ "$status" -eq 1 ]

  run bash -c "ls -1 '$SUTTMP'/postland-bisect.* 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
  run bash -c "find '$R/.git/worktrees' -name 'BISECT_*' 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
}

# ── B13-B16 — THE FLOOR ENDPOINT ──────────────────────────────────────────────────────────────────
# The mirror of B10-B12. Same premise — `git bisect` probes INTERIOR commits only, so both endpoints
# are asserted — applied to `good` (= $LASTGREEN) instead of `bad`. When the suite is ALREADY red at
# that floor every interior probe answers BAD, the walk converges on the FIRST COMMIT AFTER good, and
# names a commit innocent of everything: merely the earliest sha git was allowed to consider. C20
# reverts it. Measured against this git: an all-bad 4-commit range probes c3 then c2 and names c2,
# never once running at c1. The floor is real distance — the 2026-08-06 mis-revert's own last-green
# (29313ae4c35a) sat two days and ~130 commits below the tip.
#
#   B13 refuse    a suite already red AT the floor ⇒ UNDECIDABLE, and specifically NOT the first
#                 child of good. Pre-guard this named c2. The probe is SEEN to run, at good.
#   B14 scope     when the culprit is NOT the first child, the walk earned a green of its own below
#                 it, so the floor is never probed. This is what keeps the cost at one whole-file run
#                 on the one path with no evidence, and why B8's step accounting is untouched.
#   B15 control   a first-child culprit over a GENUINELY green floor is still NAMED. Negative control
#                 for B13, exactly as B11 is for B10: "abstain whenever the guard fires" passes B13
#                 and only this goes red.
#   B16 absence   the THIRD answer. A file that does not EXIST at the floor cannot have been red
#                 there, so the culprit that introduced it stands convicted and no run is spent.
#                 Without it the rule retires auto-revert for every newly-added red suite — which is
#                 postland's own C20 fixture, so it is the commonest shape, not an edge.
#
# B13/B15 are discriminated by ONE fact — whether the floor is really green — with the same stub, the
# same range and the same verb, so nothing but the confirmation itself can separate them.

# <marker|red> — logs the commit it ran AT (cwd is the bisect cell), then answers. WHERE a probe ran
# is the observable these need: a count cannot tell an extra floor probe from an extra walk step.
stub_bats_at_head() {
  HEADLOG="$BATS_TEST_TMPDIR/heads.log"; : > "$HEADLOG"
  { printf '#!/bin/bash\ncase "${1:-}" in --version) echo "Bats 1.0.0"; exit 0;; esac\n'
    printf 'git rev-parse HEAD >> "%s"\n' "$HEADLOG"
    case "$1" in
      red) printf 'exit 1\n' ;;                      # red EVERYWHERE, floor included
      *)   printf '[ -f BAD ] && exit 1\nexit 0\n' ;;
    esac
  } > "$STUB/bats-stub"
  chmod +x "$STUB/bats-stub"
  export CC_POSTLAND_BATS="$STUB/bats-stub"
}

@test "B13: a suite ALREADY RED at the last-green floor is undecidable — the first child of good is not a culprit" {
  mk_history 5
  stub_bats_at_head red

  TMPDIR="$SUTTMP" run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"

  # The walk itself DID converge — on c2, the earliest sha it was allowed to consider. Unguarded that
  # sha is printed, and C20 reverts whatever a bisect names.
  [ "$status" -eq 1 ]
  [[ "$output" == *"bisect undecidable"* ]] || false
  ! [[ "$output" == *"$SECOND"* ]] || false
  ! [[ "$output" =~ [0-9a-f]{7,40}\ is\ the\ first\ bad\ commit ]] || false
  ! [[ "$output" =~ ^[0-9a-f]{7,40}$ ]] || false
  # the floor was actually PROBED, and at the floor — the guard refuses on a measurement, not on a
  # topology check it could have made without running anything.
  /usr/bin/grep -q "$GOOD" "$HEADLOG"
  grep -q "bisect FLOOR NOT GREEN" "$RUNLOG"
  # ...and it is the FLOOR that decided, not a bound and not the tip confirmation
  ! grep -q "bisect CUT" "$RUNLOG" || false
  ! grep -q "bisect UNCONFIRMED" "$RUNLOG" || false
  # a further exit path out of do_bisect — the RETURN trap must cover it too (cf. B3/B9/B12)
  run bash -c "ls -1 '$SUTTMP'/postland-bisect.* 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
  run bash -c "find '$R/.git/worktrees' -name 'BISECT_*' 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
}

@test "B14: when the culprit is NOT the first child of good, the floor is never probed (the cost is scoped)" {
  mk_history 5                     # first-bad at c3 ⇒ the walk probes c2 and earns its own GREEN
  stub_bats_at_head marker

  TMPDIR="$SUTTMP" run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"

  [ "$status" -eq 0 ]
  [[ "$output" == "$FIRSTBAD" ]] || false
  # never checked out, never run: the extra whole-file run is spent ONLY where the evidence is zero.
  ! /usr/bin/grep -q "$GOOD" "$HEADLOG" || false
  ! grep -qi "floor" "$RUNLOG" || false
}

@test "B15: CONTROL — a first-child culprit over a MEASURED-green floor is still named" {
  mk_history 5 2                   # first-bad IS c2 ⇒ zero green probes, so the guard must fire...
  stub_bats_at_head marker         # ...and the floor (c1, no BAD file) is genuinely green

  TMPDIR="$SUTTMP" run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"

  [ "$status" -eq 0 ]
  [[ "$output" == "$FIRSTBAD" ]] || false
  [[ "$output" == "$SECOND" ]] || false            # fixture shape: culprit and first child are one sha
  /usr/bin/grep -q "$GOOD" "$HEADLOG"              # the probe ran...
  grep -q "bisect floor CONFIRMED green" "$RUNLOG" # ...and CONFIRMED, so it convicts
}

@test "B16: a file that does not EXIST at the floor still convicts — absence is evidence, not a non-verdict" {
  # THE COMMONEST REAL SHAPE, and what makes this a three-way rule rather than "green or abstain": a
  # commit that ADDS a red suite. postland's own C20 fixture is exactly it — green baseline, then one
  # commit carrying a new failing file — so a rule that abstained on anything but rc 0 would silently
  # retire auto-revert for every newly-added red test. Verified, not predicted: with that rule the
  # six C20 tests in tests/postland-verify.bats go red, and with this one they pass.
  #
  # The floor is not merely unmeasured here, it is INAPPLICABLE: the suite cannot have been red at a
  # commit where the file does not exist, so the assumption B13 guards has nothing to be wrong about.
  # Settled by `git cat-file -e`, so it costs no run at all. (The runner's rc could not decide it: it
  # returns 125 for an absent file AND for a bats that errored, and those must not share a verdict.)
  mk_history 5 2 tests/late.bats   # the failing FILE is born at c2, the culprit — absent at GOOD
  stub_bats_at_head marker

  TMPDIR="$SUTTMP" run "$SUT" bisect tests/late.bats "$GOOD" "$BAD"

  [ "$status" -eq 0 ]
  [[ "$output" == "$FIRSTBAD" ]] || false
  grep -q "bisect floor N/A" "$RUNLOG"
  # ...and it did NOT pay for a probe that could not have taught it anything
  ! /usr/bin/grep -q "$GOOD" "$HEADLOG" || false
}

# ── B17-B18: THE BOUND MUST REACH THE WEDGE, NOT MERELY RETURN FROM IT (2026-08-08) ───────────────
# WHAT B1-B16 DO NOT ASSERT. Every bound above is measured by the SUT's OWN return — rc, log line,
# wall clock. None of them looks at what the bound left BEHIND. That gap is the whole subject of
# backlog 36ed9b03e47a ("do_bisect's bats invocation is the ONLY unbounded one in the file"): the
# runner's bats genuinely carries no bound of its own, and what contains it is not the token
# `bounded` but the word MISSING from it — `--foreground`. Without that flag timeout(1) puts the
# child in its own PROCESS GROUP and signals the whole group, so the kill reaches a bats nested two
# levels down inside `git bisect run`.
#
# ONE TOKEN, AND THE TWO SITES FAIL DIFFERENTLY. Measured by mutating the real script at that one
# anchor and running this suite against it (2026-08-08):
#   walk site  `out="$(bounded "$BISECT_TO" git … bisect run "$runner")"` — the orphan inherits the
#              command-substitution pipe and holds it open, so the SUT hangs for the wedge's FULL
#              duration (401s against a 3s bound). LOUD: B1's `<60s` already goes red.
#   tip/floor  `bounded "$RETRY_TO" "$runner"` — called directly, no substitution, nothing to pin
#              the parent: the SUT returns in 4s, every one of the 15 assertions above stays GREEN,
#              and the wedged suite is reparented to PPID 1. SILENT — and it is the 2026-08-05
#              incident's exact shape (pid 57191, orphaned to PPID 1, still alive 12h53m later).
#              B17 is the only assertion in this file that sees it.
#
# A WALK-SITE SURVIVOR TEST WAS WRITTEN AND DROPPED — recorded so it does not get re-added as an
# obvious omission. It is unfalsifiable BY CONSTRUCTION: the same lost kill that orphans the wedge
# also pins the SUT past the wedge's own lifetime, so by the time the test regains control the
# wedge has exited of old age and the survivor count reads 0. It was green under the mutation it
# existed to catch. The walk site is covered by B1 (wall clock) and B18 (census) instead.
#
# THE OBSERVABLE is a uniquely-named wedge under $BATS_TEST_TMPDIR, so a survivor is attributable to
# THIS test and to nothing else running on the box — `pgrep -f sleep` would convict a sibling.

# A bats stub that WEDGES for <secs>, optionally answering GREEN for the first <green_first_n> calls
# so the walk converges before the wedge lands. The wedge is a uniquely-PATHED script (not a bare
# `sleep`) precisely so wedge_survivors cannot match anything but our own.
stub_bats_wedging() {
  local secs="$1" green="${2:-0}"
  WEDGE="$STUB/plv-wedge"
  # The wedge REAPS ITS OWN sleep(1) on the way out. Two rejected alternatives, both measured:
  # a bare `sleep "$1"` leaks the child (teardown's `pkill -f` matches the wrapper's argv, not the
  # forked sleep's, so a red test left a 400s process behind — observed); and `cp /bin/sleep` to get
  # a single unique-argv process does not run at all on arm64 macOS, which refuses an unsigned
  # Mach-O — the copy fails silently and the `&&` chain just stops. The trap keeps ONE process
  # carrying the unique path in argv, with nothing left over when it dies by signal.
  printf '#!/bin/bash\nsleep "$1" & c=$!\ntrap %s TERM EXIT\nwait "$c"\n' \
    "'kill -9 \"\$c\" 2>/dev/null; exit 143'" > "$WEDGE"; chmod +x "$WEDGE"
  WEDGE_CNT="$BATS_TEST_TMPDIR/wedge.calls"; : > "$WEDGE_CNT"
  { printf '#!/bin/bash\ncase "${1:-}" in --version) echo "Bats 1.0.0"; exit 0;; esac\n'
    printf 'n=$(( $(cat %q 2>/dev/null || echo 0) + 1 )); printf %%s "$n" > %q\n' "$WEDGE_CNT" "$WEDGE_CNT"
    printf '[ "$n" -le %s ] && exit 0\n' "$green"
    printf 'exec %q %s\n' "$WEDGE" "$secs"
  } > "$STUB/bats-stub"
  chmod +x "$STUB/bats-stub"
  export CC_POSTLAND_BATS="$STUB/bats-stub"
}
wedge_survivors() { pgrep -f "$WEDGE" 2>/dev/null | /usr/bin/grep -c . ; }
wedge_reaped_within() { # <secs> — 0 once nothing of ours is left alive
  local i=0
  while [ "$i" -lt "$1" ]; do
    [ "$(wedge_survivors)" = "0" ] && return 0
    sleep 1; i=$(( i + 1 ))
  done
  echo "SURVIVING WEDGE after ${1}s:"; pgrep -lf "$WEDGE" 2>/dev/null
  return 1
}
# A red B17/B18 must not leave a 400s process on the operator's box.
teardown() {
  [ -n "${WEDGE:-}" ] || return 0
  pkill -f "$WEDGE" 2>/dev/null || true; sleep 1; pkill -9 -f "$WEDGE" 2>/dev/null || true
  return 0
}

@test "B17: the TIP CONFIRMATION's bound kills the WEDGE, not just the bisect — the SILENT site" {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || skip "no timeout(1)"
  command -v pgrep >/dev/null 2>&1 || skip "no pgrep(1)"
  mk_history 6
  # GREEN for the two interior probes ⇒ the walk converges on the TIP without ever running it ⇒ the
  # confirmation invokes the runner DIRECTLY, and THAT call is the one that wedges.
  stub_bats_wedging 400 2

  TMPDIR="$SUTTMP" POSTLAND_BISECT_TIMEOUT_S=300 POSTLAND_RETRY_TIMEOUT_S=3 \
    run "$SUT" bisect tests/ok.bats "$GOOD" "$BAD"
  [ "$status" -eq 1 ]

  # It was the CONFIRMATION that cut, not the walk's wall — otherwise this measures the wrong site.
  grep -q "bisect UNCONFIRMED" "$RUNLOG"
  # The wedge was REACHED (2 green walk probes + the confirmation). Without this the survivor check
  # below passes vacuously on any run where the fixture never got as far as wedging at all.
  [ "$(cat "$WEDGE_CNT")" -ge 3 ]
  # ...and the process group went with it. 25s is generous past timeout's own `-k 10` SIGKILL grace.
  wedge_reaped_within 25
}

@test "B18: every \$BATS_BIN call site is under a bound — a census, which no runtime test can be" {
  local joined exempt exec_sites unbounded
  joined="$BATS_TEST_TMPDIR/joined.sh"
  # Join backslash-continuations FIRST: retry_once's `bats` sits on the line after its `bounded`, so
  # a per-line grep convicts a correctly-bounded site and the whole census reads as a false alarm.
  /usr/bin/sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$SUT" > "$joined"

  # THE ONE EXEMPTION — do_bisect's generated-runner template, bounded at its CALL SITES instead
  # (asserted below). Anchored to exactly one line: an exemption that silently widened would start
  # covering a site nobody ever looked at, which is the failure this census exists to prevent.
  exempt="$(/usr/bin/grep -c "printf 'TMPDIR=%q" "$joined")"
  [ "$exempt" = "1" ]

  unbounded="$(/usr/bin/grep -n '"\$BATS_BIN"' "$joined" \
      | /usr/bin/grep -v '^[0-9]*:[[:space:]]*#' \
      | /usr/bin/grep -v "printf 'TMPDIR=%q" \
      | /usr/bin/grep -v 'bounded ' \
      | /usr/bin/grep -v '"\$TIMEOUT_BIN"' || true)"
  [ -z "$unbounded" ] || { echo "UNBOUNDED \$BATS_BIN call site(s):"; echo "$unbounded"; false; }

  # ...and the exempted runner is EXECUTED only under a bound. The non-executing mentions are named
  # individually rather than pattern-guessed, so a genuinely new call site cannot hide among them.
  exec_sites="$(/usr/bin/grep -n '"\$runner"' "$joined" \
      | /usr/bin/grep -v 'rm -f\|chmod\|> "\$runner"\|bisect_floor_ok ' || true)"
  # FLOOR, deliberately not an exact tally (an exact count reds on legitimate GROWTH and catches no
  # regression): >=3 only so a renamed variable cannot make the emptiness below read as green.
  [ "$(printf '%s' "$exec_sites" | /usr/bin/grep -c .)" -ge 3 ]
  unbounded="$(printf '%s\n' "$exec_sites" | /usr/bin/grep -v 'bounded ' || true)"
  [ -z "$unbounded" ] || { echo "UNBOUNDED runner call site(s):"; echo "$unbounded"; false; }
}
