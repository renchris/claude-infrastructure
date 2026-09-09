#!/usr/bin/env bats
# postland-verify-passfloor.bats — C31: the floor C30 probes against must not rot.
#
# THE CONTRACT CLAUSE THIS BINDS TO (scripts/postland-verify.sh, the C31 block beside $PASSES):
#   C31  A ladder conviction is exonerated when the SAME failure reproduces at a commit below the
#        tree under test at which THIS VERIFIER OBSERVED THAT FILE PASS. The control is no longer
#        only $LASTGREEN — a whole-tree green, advanced by the one outcome the mechanism exists to
#        make reachable — but a PER-FILE ledger written from every plan-complete corpus run, red
#        sweeps included. The probe's meaning is unchanged in every direction:
#            floor rc=1  => the failure predates the window => flake (recorded, NOT a red)
#            floor rc=0  => the conviction IS differential   => RED stands
#            anything else                                   => RED stands
#
# THE WEDGE IT CLOSES, and why a comment would not have been enough. $LASTGREEN advances ONLY on a
# green verdict, so during an outage the control drifts further from trunk every sweep while the
# abstention rate rises — a bootstrap circle. Measured on this box 2026-09-09 against the live
# $LASTGREEN 24c598bac1c7 (2026-09-03, 428 commits down), over the suites carrying the recent
# convictions: tests/drain-brief.bats does not EXIST at that floor, and cc-reaper (+22 test names),
# goal-inert-watch (+14), autonomy-sweep (+10) and deploy-parity (+9) have all grown names the
# floor's `-f` filter cannot match. Each of those is a guaranteed non-verdict, i.e. `conviction
# stands`, by floor_exonerates' own code — and they are precisely the chronic flakes C30 exists to
# exonerate. Test 2 below is that shape, minimally: a suite that does not exist at $LASTGREEN at all.
#
# RED-PROOF, and it is the point of tests 3 and 4 rather than a note in a comment. A mechanism that
# only ever turns reds into greens is a weakening, not a fix, so:
#   test 3  the SAME tree with CC_POSTLAND_PASS_FLOOR=off is the PRE-FIX behaviour and must be RED
#           — without it test 2 could pass against a fixture that never convicted anything
#   test 4  a suite that PASSES at its own per-file floor and fails at the tip is a real content red
#           and must STILL be RED. This is the assertion that says C31 did not buy its green by
#           lowering the bar.
#
# PROOF DISCIPLINE (inherited from postland-verify.bats / postland-band-floor.bats):
#   · every expected value is derived from the clause quoted above, never from running the SUT first
#   · non-final `[[ ]]` / `[ ]` are errexit-EXEMPT and DEAD as assertions — each one carries `|| false`
#   · the flake trigger lives OUTSIDE the repo, so the suite is non-deterministic with the TREE held
#     constant: that is the only property a floor probe can detect and a same-tree ladder cannot
#   · the fixture never pushes anything (POSTLAND_AUTOREVERT=off) and never touches the real state

SUT="${BATS_TEST_DIRNAME}/../scripts/postland-verify.sh"

setup() {
  # FIXTURED $HOME, first thing. The SUT's own defaults are rooted there ($HOME/.claude/autonomy/…),
  # and every one of them is overridden below — but "overridden below" is a claim about the code as it
  # is TODAY, and a suite that leaves the operator's live ~/ reachable is one refactor away from
  # writing into it. test-hermeticity-lint blocks exactly this, and it is right to: the whole point of
  # this fixture is that its verdicts come from a tree and a state dir nobody else can touch.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # git needs an identity it can find; the fixture repo also sets one per-repo below, and this is the
  # belt for any git invocation the SUT makes outside that repo (the disposable worktree cell).
  printf '[user]\n\tname = pv-selftest\n\temail = pv@selftest.local\n' > "$HOME/.gitconfig"
  D="$BATS_TEST_TMPDIR/f"
  mkdir -p "$D/src/tests" "$D/state" "$D/pages"
  git init -q --bare "$D/origin.git"
  git init -q "$D/src"
  git -C "$D/src" config user.email pv@selftest.local
  git -C "$D/src" config user.name pv-selftest
  git -C "$D/src" remote add origin "$D/origin.git"
  printf '#!/usr/bin/env bats\n@test "ok" { true; }\n' > "$D/src/tests/ok.bats"
  printf '#!/bin/bash\necho hi\n' > "$D/src/ok.sh"
}

land() { # <msg> — commit + publish to the fixture origin
  git -C "$D/src" add -A >/dev/null 2>&1
  git -C "$D/src" commit -qm "$1" >/dev/null 2>&1
  git -C "$D/src" push -q origin HEAD:main >/dev/null 2>&1
  git -C "$D/src" fetch -q origin >/dev/null 2>&1
}

# One sweep of the fixture. Extra env is passed as leading VAR=VAL words, exactly as the script's own
# --selftest harness does it. The identity seam is the same sealed one that harness uses: without it
# the fixture's pv@selftest.local is measured against the operator's real address and the run takes
# the identity DROP branch, which has nothing to do with anything asserted here.
#
# POSTLAND_BISECT_TIMEOUT_S=5 bounds `git bisect`, which a RED verdict arms. Nothing here asserts a
# culprit: write_stamp runs BEFORE red_actions, so every verdict this suite reads is already on disk
# when the walk starts, and an unbounded walk would only add minutes per RED to a suite that lands in
# the 593-suite corpus whose wall-clock this whole change exists to protect. Tests shrink this bound
# exactly as they shrink CONVICT_SPREAD.
#
# EVERY caller passes the C31 kill switch explicitly, even the ones that want the default. That is
# not ceremony: it makes each sweep state which side of the switch it is measuring, and it keeps the
# argument list non-empty so the env prefix is a real parameter rather than an unused one.
sweep() { # <VAR=VAL>... — leading env assignments for THIS sweep
  env POSTLAND_VERIFY=on POSTLAND_AUTOREVERT=off \
      CC_POSTLAND_DIR="$D/state" CC_POSTLAND_REPO="$D/src" \
      CC_POSTLAND_WT_ROOT="$D/cells" CC_PAGES_DIR="$D/pages" CC_IDL="$D/idl.jsonl" \
      CC_BACKLOG_BIN=/usr/bin/true CC_POSTLAND_NOTIFY=/usr/bin/true CC_POSTLAND_NOTIFY_BIN=/usr/bin/true \
      "CC_GIT_IDENTITY_TEST=1" "CC_GIT_IDENTITY_EMAIL=pv@selftest.local" \
      CC_POSTLAND_LANDLOG="$D/land.log" CC_POSTLAND_CONVICT_SPREAD_S=0 \
      POSTLAND_BISECT_TIMEOUT_S=5 \
      "$@" "$SUT" --run-if-needed
}

tree_now()   { git -C "$D/src" rev-parse 'origin/main^{tree}'; }
verdict_of() { grep -o '"verdict":"[a-z]*"' "$D/state/stamps/$1.json" 2>/dev/null | head -1; }

# Build the wedge and leave the fixture one conviction short. On return:
#   $LASTGREEN  = c0, the commit BEFORE flaky.bats existed  (so C30 alone can only abstain)
#   $PASSES     = flaky.bats observed passing at c1
#   HEAD        = c2, a tree where flaky.bats fails and nothing else does
build_rotted_floor() {
  land "c0: only ok.bats"
  sweep CC_POSTLAND_PASS_FLOOR=on >/dev/null 2>&1                                    # => GREEN, last-green = c0
  FLOOR0="$(git -C "$D/src" rev-parse HEAD)"

  # c1 introduces flaky.bats PASSING, alongside a deterministically failing suite. The red keeps
  # last-green pinned at c0 — which is the whole point: that is what an outage looks like — while the
  # corpus run still observes flaky.bats pass, which is the evidence C31 keeps and C30 discards.
  printf '#!/usr/bin/env bats\n@test "nondifferential" { [ ! -f "%s/flake-trigger" ]; }\n' "$D" \
    > "$D/src/tests/flaky.bats"
  printf '#!/usr/bin/env bats\n@test "temp red" { false; }\n' > "$D/src/tests/tempred.bats"
  # ONE sweep here, deliberately, and it is a COST decision with a correctness argument. One window
  # leaves tempred C29-PENDING, so the sweep ends in a CUT — which is all this step needs: last-green
  # stays at c0 (the rot), and passes_record still runs, because a C29 cut exits 1 with a complete
  # plan and no shortfall. A SECOND sweep here would corroborate tempred into a RED, and a RED arms
  # `git bisect` — measured at 3+ minutes per build in this fixture, on a suite that lands in a
  # 593-suite corpus whose wall-clock is the thing this whole change exists to protect.
  land "c1: flaky.bats passes here; tempred.bats holds the tree off green"
  sweep CC_POSTLAND_PASS_FLOOR=on >/dev/null 2>&1                                    # one window => CUT
  FLOOR1="$(git -C "$D/src" rev-parse HEAD)"

  # c2 removes the deterministic red and arms the out-of-tree trigger, so flaky.bats now fails at
  # EVERY commit — including the one where we watched it pass.
  rm -f "$D/src/tests/tempred.bats"
  touch "$D/flake-trigger"
  land "c2: tempred gone, flaky.bats now fails everywhere"
  TREE2="$(tree_now)"
}

@test "C31 control: last-green is the PRE-flaky commit and the pass ledger holds the LATER one" {
  build_rotted_floor
  # THE CONTROL FOR EVERY ASSERTION BELOW. If last-green had advanced past c0 the wedge would not
  # exist and test 2 would pass for a reason that has nothing to do with C31; if the ledger were
  # empty, C31 would be inert and test 2 would be measuring C30.
  [ "$(cat "$D/state/last-green")" = "$FLOOR0" ] || false
  run git -C "$D/src" cat-file -e "$FLOOR0:tests/flaky.bats"
  [ "$status" -ne 0 ] || false                             # the file is ABSENT at last-green
  run grep -cE "^tests/flaky\.bats	[0-9]+	$FLOOR1\$" "$D/state/passes"
  [ "$status" -eq 0 ] || false
}

@test "C31: a conviction whose file did not EXIST at last-green is exonerated by its own pass floor" {
  build_rotted_floor
  sweep CC_POSTLAND_PASS_FLOOR=on >/dev/null 2>&1                                    # window 1 => C29 pending => cut
  sweep CC_POSTLAND_PASS_FLOOR=on >/dev/null 2>&1                                    # window 2 => corroborated => floor probe
  # C31's whole claim, in one line: the tree is GREEN because the failure reproduces at a commit
  # where we watched this suite pass, so it says nothing about this tree.
  [ "$(verdict_of "$TREE2")" = '"verdict":"green"' ] || false
  run grep -c '"outcome":"floor-not-differential"' "$D/state/flakes.jsonl"
  [ "$status" -eq 0 ] || false
  # ...and the row names the PER-FILE floor, not last-green. A row asserting the wrong control is the
  # evidence a later reader re-derives from, so it is asserted rather than assumed.
  run grep -c "\"floor\":\"$FLOOR1\"" "$D/state/flakes.jsonl"
  [ "$status" -eq 0 ] || false
}

@test "C31 RED-PROOF: with the kill switch off, the identical tree is RED (the pre-fix behaviour)" {
  build_rotted_floor
  sweep CC_POSTLAND_PASS_FLOOR=off >/dev/null 2>&1
  sweep CC_POSTLAND_PASS_FLOOR=off >/dev/null 2>&1
  # C30 alone cannot reach this conviction: flaky.bats does not exist at last-green, so its probe is
  # a non-verdict by construction and the conviction stands. That is the state C31 was built to
  # change — and if this ever goes green, C31 is not what turned test 2 green.
  [ "$(verdict_of "$TREE2")" = '"verdict":"red"' ] || false
}

@test "C31 does NOT weaken the gate: a suite that PASSES at its own pass floor still REDs" {
  # The differential case, which must be untouched. flaky2.bats is observed passing at c1 exactly as
  # flaky.bats is above, and is then BROKEN IN THE TREE at c2 — a real content regression. Its floor
  # probe runs at c1, where the file is the passing version, so the probe returns rc 0 and the
  # conviction is differential. A green here would mean C31 bought its exoneration by lowering the bar.
  land "c0: only ok.bats"
  sweep CC_POSTLAND_PASS_FLOOR=on >/dev/null 2>&1
  printf '#!/usr/bin/env bats\n@test "content" { true; }\n' > "$D/src/tests/flaky2.bats"
  printf '#!/usr/bin/env bats\n@test "temp red" { false; }\n' > "$D/src/tests/tempred.bats"
  land "c1: flaky2 passes here"
  sweep CC_POSTLAND_PASS_FLOOR=on >/dev/null 2>&1                                    # one window => CUT
  FLOOR1="$(git -C "$D/src" rev-parse HEAD)"
  run grep -cE "^tests/flaky2\.bats	[0-9]+	$FLOOR1\$" "$D/state/passes"
  [ "$status" -eq 0 ] || false                             # the floor exists...

  rm -f "$D/src/tests/tempred.bats"
  printf '#!/usr/bin/env bats\n@test "content" { false; }\n' > "$D/src/tests/flaky2.bats"
  land "c2: flaky2 genuinely broken in the tree"
  TREE2="$(tree_now)"
  sweep CC_POSTLAND_PASS_FLOOR=on >/dev/null 2>&1
  sweep CC_POSTLAND_PASS_FLOOR=on >/dev/null 2>&1
  [ "$(verdict_of "$TREE2")" = '"verdict":"red"' ] || false   # ...and it still convicts
}
