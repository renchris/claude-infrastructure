#!/usr/bin/env bats
# The venue census that decides whether a cloud VM's own land path can render a verdict.
#
# WHAT THIS SUITE IS FOR, GIVEN THE SUBJECT ALREADY HAS A --selftest. The script's --selftest drives
# venue_verdict() with synthetic operands and proves it DISCRIMINATES. It cannot prove the two things
# that actually decide whether the file is useful: that the live probes reach those cells on a real
# box, and that the claim the script makes ABOUT ship-land.sh is still true of ship-land.sh. Both are
# pinned here. The second is the load-bearing one — the whole file is an argument about someone
# else's control flow, and an argument about code is a claim that rots when that code changes.
#
# THE ASYMMETRY UNDER TEST (measured on a cloud VM 2026-08-29, docs/plans/BACKLOG_DRAIN_24_7.md):
#   ShellCheck absent → bats-shellcheck-lint exits 2 → bats_sc_nonverdict → GATE_KILLED → exit 9.
#   bats absent       → suites exit 127 with zero TAP not-ok lines → CUT → smoke "partial" → exit 0.
# (Capitalised deliberately: a comment whose first word is the lower-case tool name parses as a
#  malformed directive and aborts analysis of this whole file — the lint above says so, and this
#  suite tripped it anyway, which is the third instance in one diff.)
# One is a lock; the other is a silent ungating. The plan's addendum called them "both locks".

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SUT="$REPO/scripts/cloud-venue-provision.sh"
  LAND="$REPO/scripts/ship-land.sh"
  # Hermetic $HOME: nothing in the subject reads it today, and the subject is a file that runs
  # before a land, which is the worst place to discover that changed.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # THE RUNNER WITNESS IS FORCED TO A ONE-FILE FIXTURE FOR EVERY CELL BUT ONE, AND THAT IS A COST
  # DECISION, NOT A CORRECTNESS ONE. The subject's real witness is a gather of all ~556 tests/*.bats
  # in one bats process — ~45s measured. Every `--check` cell below would pay it, and this suite is
  # DIRECTLY SELECTED by a scripts/ship-land.sh change, whose whole smoke budget is 420s. So the
  # cells that are about the checker, the horizon or the seams run against a trivial corpus, and the
  # ONE cell that is about the real corpus pays the real price, once, deliberately. The census output
  # prints "witness FORCED by CC_VENUE_RUNNER_WITNESS" whenever this is set, so a forced value can
  # never be read back as a measurement — the same rule CC_VENUE_HISTORY already follows.
  FASTC="$BATS_TEST_TMPDIR/fast-corpus"; mkdir -p "$FASTC"
  printf '@test "the fixture corpus loads" { true; }\n' > "$FASTC/trivial.bats"
  export CC_VENUE_RUNNER_WITNESS="$FASTC"
}

# ── the subject's own discrimination proof, run as a test so a regression in it is a red suite ────
@test "cloud-venue-provision --selftest passes and reports a full count" {
  run bash "$SUT" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" =~ --selftest:\ ([0-9]+)/([0-9]+)\  ]] || false
  [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ]
  [ "${BASH_REMATCH[1]}" -ge 12 ]
}

# ── the live probes reach the cells, on whatever box this runs on ─────────────────────────────────
@test "--check reads READY on a box that has both tools" {
  command -v shellcheck >/dev/null 2>&1 || skip "no shellcheck on this box — the positive control is unavailable"
  command -v bats >/dev/null 2>&1 || skip "no bats on this box (impossible: bats is running this)"
  run bash "$SUT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict: READY"* ]]
}

@test "--check reads LOCKED, and exits non-zero, when the checker is absent" {
  CC_VENUE_ABSENT="shellcheck" run bash "$SUT" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict: LOCKED"* ]] || false
  [[ "$output" == *"exits 9"* ]]
}

# THE THIRD LOCK, driven through the witness rather than by installing an old binary. The probe's
# whole claim is that it measures THIS BOX by RUNNING the checker, so pointing it at a file that is
# genuinely unclean must reach STALE-CHECKER — and pointing it at a clean one must not.
@test "--check reads STALE-CHECKER when the checker reds its witness" {
  command -v shellcheck >/dev/null 2>&1 || skip "no shellcheck on this box"
  printf '#!/bin/sh\nfoo=1\necho $foo | grep -q x && echo "$UNSET_VAR"\ncd /tmp/$foo\n' > "$BATS_TEST_TMPDIR/dirty.sh"
  # the fixture must actually be unclean, or this test proves nothing about the probe
  run shellcheck "$BATS_TEST_TMPDIR/dirty.sh"
  [ "$status" -ne 0 ]
  CC_VENUE_WITNESS="$BATS_TEST_TMPDIR/dirty.sh" run bash "$SUT" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict: STALE-CHECKER"* ]] || false
  [[ "$output" == *"witness stale"* ]]
}

@test "the witness probe abstains rather than convicting when there is no witness" {
  CC_VENUE_WITNESS="$BATS_TEST_TMPDIR/does-not-exist.sh" run bash "$SUT" --check
  [[ "$output" == *"witness ok"* ]] || false
  [[ "$output" != *"STALE-CHECKER"* ]]
}

@test "an absent checker outranks a stale one — the land meets them in that order" {
  printf '#!/bin/sh\ncd /tmp/$1\n' > "$BATS_TEST_TMPDIR/dirty2.sh"
  CC_VENUE_ABSENT="shellcheck" CC_VENUE_WITNESS="$BATS_TEST_TMPDIR/dirty2.sh" run bash "$SUT" --check
  [[ "$output" == *"verdict: LOCKED"* ]] || false
  [[ "$output" != *"STALE-CHECKER"* ]]
}

@test "--check reads UNGATED, and exits non-zero, when the runner is absent" {
  CC_VENUE_ABSENT="bats" run bash "$SUT" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict: UNGATED"* ]] || false
  [[ "$output" == *"PROCEEDS unrun"* ]]
}

@test "the hard lock takes precedence over the silent one when both are absent" {
  CC_VENUE_ABSENT="shellcheck bats" run bash "$SUT" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict: LOCKED"* ]] || false
  [[ "$output" != *"UNGATED"* ]]
}

# ── THE FIFTH LOCK: present is not loadable ───────────────────────────────────────────────────────
# The subject's --selftest drives STALE-RUNNER with a synthetic operand. These cells drive the LIVE
# probe, the same way the STALE-CHECKER cell above drives the checker's — by pointing the witness at
# a corpus that genuinely cannot be gathered, and (the half that makes it mean something) at one that
# genuinely can. A probe hard-wired to `stale` passes the first cell alone.
#
# 🚨 THE FIXTURE MUST BE CHOSEN BY PROBING, NOT WRITTEN DOWN — measured, and the reason is the whole
# finding one level down. NO SINGLE ungatherable corpus exists across bats versions, because the two
# versions disagree about what `-c` even does:
#     duplicate @test names   1.10.0 refuses (fatal, no TAP) · 1.13.0 ALLOWS  (disambiguates them)
#     a shell syntax error    1.10.0 ACCEPTS (prints a count; it never sources) · 1.13.0 refuses
# So a hard-coded bad fixture convicts this tree on whichever runner happens to tolerate it — the
# false-conviction direction the plan's addendum warns against buying to cure a silent ungating.
# This builds candidates and keeps the first one THIS runner actually refuses.
mk_unloadable() {   # $1 = dir → 0 and a populated dir, or 1 if this runner refuses nothing we can write
  local d="$1" c
  mkdir -p "$d"
  for c in syntax dup; do
    rm -f "$d"/*.bats
    printf '@test "fine" { true; }\n' > "$d/ok.bats"
    case "$c" in
      syntax) printf '@test "broken" {\n  if [ 1 = 1 ]; then\n}\n' > "$d/broken.bats" ;;
      dup)    printf '@test "x" { true; }\n@test "x" { true; }\n'  > "$d/broken.bats" ;;
    esac
    bats -c "$d"/*.bats >/dev/null 2>&1 || return 0
  done
  rm -f "$d"/*.bats
  return 1
}

@test "--check reads STALE-RUNNER when the runner cannot LOAD a suite in the corpus" {
  local d="$BATS_TEST_TMPDIR/badcorpus"
  mk_unloadable "$d" || skip "this bats gathers every malformed corpus we can write — the cell has no fixture"
  CC_VENUE_RUNNER_WITNESS="$d" run bash "$SUT" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict: STALE-RUNNER"* ]] || false
  [[ "$output" == *"corpus stale"* ]]
}

@test "…and a corpus it CAN load reads READY — the probe measures the corpus, not the flag" {
  command -v shellcheck >/dev/null 2>&1 || skip "no shellcheck on this box — READY is unreachable"
  run bash "$SUT" --check           # $CC_VENUE_RUNNER_WITNESS from setup(): one loadable suite
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict: READY"* ]] || false
  [[ "$output" == *"corpus ok"* ]]
}

@test "an absent runner and a stale one are DIFFERENT tokens — the cure differs" {
  local d="$BATS_TEST_TMPDIR/badcorpus2"
  mk_unloadable "$d" || skip "this bats gathers every malformed corpus we can write"
  CC_VENUE_RUNNER_WITNESS="$d" run bash "$SUT" --check
  [[ "$output" == *"STALE-RUNNER"* ]] || false
  [[ "$output" != *"UNGATED"* ]] || false
  CC_VENUE_ABSENT="bats" run bash "$SUT" --check
  [[ "$output" == *"UNGATED"* ]] || false
  [[ "$output" != *"STALE-RUNNER"* ]]
}

@test "a checker failure outranks a runner failure — the statics arm reds before the smoke runs" {
  local d="$BATS_TEST_TMPDIR/badcorpus3"
  mk_unloadable "$d" || skip "this bats gathers every malformed corpus we can write"
  CC_VENUE_ABSENT="shellcheck" CC_VENUE_RUNNER_WITNESS="$d" run bash "$SUT" --check
  [[ "$output" == *"verdict: LOCKED"* ]] || false
  [[ "$output" != *"STALE-RUNNER"* ]]
}

# THE RATCHET, and it is the cell this whole diff exists for: whatever runner is executing THIS suite
# must be able to gather EVERY suite in this repo. Measured 2026-08-29, the distro's 1.10.0 could not
# — 553 of 556, refusing bats-shellcheck-lint, git-identity-lint and qos-chokepoint over @test
# descriptions that mangle alike inside heredoc fixtures — and the land read each of them as a cut,
# attested "partial", and pushed. Nothing in the corpus asked this question, so nothing noticed.
# ~45s, deliberately: it is the real witness, and the reason every other cell above uses a fixture.
@test "RATCHET — the running bats can gather this repo's WHOLE corpus, not merely most of it" {
  run env -u CC_VENUE_RUNNER_WITNESS bash "$SUT" --check
  [[ "$output" == *"corpus ok"* ]] || {
    echo "$output"
    echo "The runner executing this suite cannot load part of tests/ — see the assert lines above."
    false
  }
  [[ "$output" != *"witness FORCED"* ]]
}

# THE SEAM'S ASYMMETRY, asserted rather than assumed. CC_VENUE_ABSENT exists only so the two failure
# cells are reachable from here; if it could ever manufacture PRESENCE it would let a suite certify a
# box that cannot land. Naming a tool that is already there must change nothing.
@test "CC_VENUE_ABSENT cannot manufacture presence" {
  command -v shellcheck >/dev/null 2>&1 || skip "no shellcheck on this box"
  run bash "$SUT" --check
  local plain="$output"
  CC_VENUE_ABSENT="curl git awk" run bash "$SUT" --check
  [ "$output" = "$plain" ]
}

# ── the NOT-APPLICABLE arm: the ratchet keys on the REPO, so a repo without suites is not locked ──
@test "a repo with no tests/*.bats abstains instead of convicting" {
  mkdir -p "$BATS_TEST_TMPDIR/other/scripts"
  cp "$SUT" "$BATS_TEST_TMPDIR/other/scripts/"
  CC_VENUE_ABSENT="shellcheck bats" run bash "$BATS_TEST_TMPDIR/other/scripts/cloud-venue-provision.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict: NOT-APPLICABLE"* ]] || false
  [[ "$output" != *"LOCKED"* ]]
}

@test "--check writes nothing and installs nothing" {
  local before; before="$(cd "$REPO" && git status --porcelain | sha256sum)"
  CC_VENUE_ABSENT="shellcheck bats" run bash "$SUT" --check
  local after; after="$(cd "$REPO" && git status --porcelain | sha256sum)"
  [ "$before" = "$after" ]
  [[ "$output" != *"installing"* ]]
}

@test "an unknown argument refuses rather than falling through to the install path" {
  run bash "$SUT" --wat
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
}

# ── the history horizon ───────────────────────────────────────────────────────────────────────────
# The subject's --selftest drives this cell with a synthetic operand. What it cannot show is that the
# LIVE probe reaches it from a real checkout, which is the only thing that matters: a cloud VM is
# handed a shallow clone by the harness, not by a flag. So the fixture here is an actual
# `git clone --depth 1`, and the positive control is the SAME clone after `--unshallow` — one repo,
# one difference, both directions. Without the second half a probe hard-wired to `shallow` passes.
#
# `$REPO` is cloned rather than a synthetic history, because the verdict's precedence has to be read
# against a repo that genuinely has tests/*.bats; a toy repo reads NOT-APPLICABLE and would prove
# nothing about the ordering.

# Builds a depth-1 clone of $REPO at $1 and installs THE VERSION UNDER TEST into it. The copy is not
# a shortcut: a clone carries $REPO's committed HEAD, so without it every cell here would exercise
# whatever `scripts/cloud-venue-provision.sh` last landed and pass against a subject that has none of
# this arm in it — a fixture testing the wrong file, silently. The clone supplies the two things that
# cannot be faked (a genuinely shallow `.git` and a tests/*.bats tree); the subject comes from here.
#
# Skips (never fails) where the venue cannot produce a clone — a file:// clone is refused under some
# `protocol.file.allow` policies, and a suite that FAILED there would be reporting the sandbox's
# policy as a defect in the subject.
_shallow_clone() {
  git clone --depth 1 --quiet "file://$REPO" "$1" 2>/dev/null \
    || skip "this venue cannot make a file:// clone (protocol.file.allow?)"
  [ "$(git -C "$1" rev-parse --is-shallow-repository 2>/dev/null)" = true ] \
    || skip "clone --depth 1 did not produce a shallow repo here"
  cp "$SUT" "$1/scripts/cloud-venue-provision.sh"
}

@test "a REAL shallow checkout reads TRUNCATED-HISTORY, and --check exits non-zero on it" {
  _shallow_clone "$BATS_TEST_TMPDIR/shallow"
  run bash "$BATS_TEST_TMPDIR/shallow/scripts/cloud-venue-provision.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict: TRUNCATED-HISTORY"* ]] || false
  [[ "$output" == *"history: shallow"* ]] || false
  # the sentence must name the DIRECTION of the wrong answer, which is the whole finding: a horizon
  # that merely "might be incomplete" reads as a caveat and gets ignored.
  [[ "$output" == *"reports landed work as never landed"* ]]
}

@test "…and the same clone, deepened, stops reading it — the probe measures the repo" {
  _shallow_clone "$BATS_TEST_TMPDIR/deepened"
  git -C "$BATS_TEST_TMPDIR/deepened" fetch --unshallow --quiet 2>/dev/null \
    || skip "this venue could not unshallow the fixture"
  run bash "$BATS_TEST_TMPDIR/deepened/scripts/cloud-venue-provision.sh" --check
  [[ "$output" == *"history: full"* ]] || false
  [[ "$output" != *"TRUNCATED-HISTORY"* ]]
}

@test "the horizon outranks the hard lock, live — fixing the gate alone leaves the wrong diff" {
  _shallow_clone "$BATS_TEST_TMPDIR/shallow-locked"
  CC_VENUE_ABSENT="shellcheck bats" run bash "$BATS_TEST_TMPDIR/shallow-locked/scripts/cloud-venue-provision.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict: TRUNCATED-HISTORY"* ]] || false
  [[ "$output" != *"verdict: LOCKED"* ]]
}

@test "a forced horizon is NAMED as forced and can never be mistaken for a measurement" {
  CC_VENUE_HISTORY=shallow run bash "$SUT" --check
  [[ "$output" == *"FORCED by CC_VENUE_HISTORY"* ]] || false
  [[ "$output" == *"verdict: TRUNCATED-HISTORY"* ]]
}

@test "provision REFUSES to fetch against a forced horizon rather than acting on a non-measurement" {
  local before; before="$(cd "$REPO" && git rev-list --count HEAD)"
  CC_VENUE_HISTORY=shallow run bash "$SUT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"refusing to fetch"* ]] || false
  [ "$(cd "$REPO" && git rev-list --count HEAD)" = "$before" ]
}


# ── the claims this file makes ABOUT ship-land.sh, pinned so they cannot rot silently ─────────────
# Both are greps for shapes, not for prose: a comment could be reworded without the routing changing,
# and the routing could change without the comment being touched. It is the routing that is pinned.

@test "ship-land still routes the checker's exit 2 to a NON-VERDICT that kills the gate" {
  grep -qE 'scrc -eq 2 \]\]; then bats_sc_nonverdict; return 1' "$LAND"
  # …and that handler must still set GATE_KILLED, which is what produces exit 9 rather than a red.
  sed -n '/^bats_sc_nonverdict()/,/^}/p' "$LAND" | grep -qE 'GATE_KILLED=1'
}

@test "ship-land still lets a CUT proceed — the polarity this venue script exists because of" {
  # `cut=1` ⇒ partial ⇒ return 0. If this ever becomes a refusal, the UNGATED verdict's sentence is
  # wrong (a missing runner would then be a second lock) and cloud-venue-provision.sh must be
  # re-read before this suite is made to pass again.
  run bash -c "sed -n '/if \[\[ \"\$cut\" -eq 1 \]\]; then/,/^  fi/p' '$LAND'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'SMOKE_STATE="partial"'* ]] || false
  [[ "$output" == *"return 0"* ]] || false
  # AND NOTHING IN THE BLOCK REFUSES. Asserting only that `return 0` is PRESENT is a vacuous pin: a
  # `return 1` added above it satisfies the substring test while inverting the behaviour the whole
  # finding rests on. Measured while writing this suite — the weak form passed against exactly that
  # mutant. Absence is the half that carries the claim.
  [[ "$output" != *"return 1"* ]] || false
  [[ "$output" != *"gate_red"* ]]
}

@test "ship-land's smoke runner still invokes bats bare, which is why an absent runner exits 127" {
  sed -n '/^gate_bats()/,/^}/p' "$LAND" | grep -qE '(^|[[:space:]])bats "\$@"'
}

@test "the .bats ratchet's entry condition is still a property of the repo, not of the diff" {
  # This is what makes a missing checker block a DOCS-ONLY land here, and it is the single most
  # surprising half of the finding. If it ever becomes diff-scoped, LOCKED's sentence overstates.
  grep -qE '\[\[ -d tests \]\] && ls tests/\*\.bats' "$LAND"
}
