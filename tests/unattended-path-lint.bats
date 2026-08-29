#!/usr/bin/env bats
# Guards scripts/unattended-path-lint.sh — the ratchet on bare-name binary resolution along the
# paths nobody watches (launchd jobs, settings.json hooks).
#
# WHY THIS SUITE IS THIN AND WHY THAT IS DELIBERATE. The lint carries its own --selftest, and that
# selftest is what the gate runs; duplicating those cases here would create two
# oracles over one behaviour, which is the shape that goes stale asymmetrically (memory:
# sibling-auditors-must-share-the-state-model).
# (The case COUNT used to be restated here as "18 cases". It read 27 by the time anyone looked and is
# higher now — a resident restatement of a perishable fact has no path to learn it changed, so the
# number is deliberately gone rather than updated to one that will rot again.)
# So this suite asserts the things --selftest
# STRUCTURALLY CANNOT assert about itself:
#   · that --selftest exists, runs, and passes (the gate depends on that exit code)
#   · that the detector is not vacuous against the REAL corpus — the failure mode that actually
#     happened twice while building this file
#   · that the lint has no non-stock dependency of its own, which would be self-refuting
#   · that its populations are non-empty, since a lint over an empty set is a silent green

setup() {
  # Fixture $HOME before anything else. The lint expands `$HOME` in a plist's PATH string, so an
  # unfixtured suite reads the operator's live ~/ — the leak test-hermeticity-lint exists to catch,
  # and it caught this one at the gate. The lint's verdict is deliberately independent of what lives
  # under $HOME (the hook population is the tree's own hooks/ directory, never the live
  # settings.json), so fixturing it changes nothing except the ambient coupling.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/bin"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/unattended-path-lint.sh"
  STOCK="/usr/bin:/bin:/usr/sbin:/sbin"
}

# ── THE TREE ARMS ARE FACTS ABOUT THE BOX, AND OFF DARWIN THEY ARE NON-VERDICTS ──────────────────
# Two tests below scan the REAL repository and assert the shipped allowlist covers what comes back.
# What comes back depends on which binaries the box has and where, because that is the question this
# lint exists to ask — and the jobs it asks it FOR are launchd jobs, which exist only on macOS.
#
# Measured off Darwin on an untouched trunk checkout: 13 fabricated findings (`swift`, `swiftc`,
# `plutil`, `sqlite3`, `node`, `gtimeout` — present on the Mac, absent here) AND 23 stuck-ratchet
# rows (`timeout`, `lsof`, `sysctl`, `taskpolicy`, `gh`, `bun`, `cargo` — allowlisted because they
# are unreachable on the Mac, reachable at /usr/bin here). Wrong in both directions at once, from a
# tree nobody had touched: an inert sensor, and the repo's law is that one yields a NON-VERDICT.
#
# A `skip` is the honest spelling and a visible one — bats prints it, and it cannot be mistaken for
# a pass in the way a silently-deleted assertion can. The detector's own cases are unaffected: they
# are hermetic now (see --selftest's fixture-binary block) and they still run and still gate here.
darwin_only_tree_arm() {
  [ "$(uname -s 2>/dev/null || echo unknown)" = "Darwin" ] || \
    skip "tree-level arm: judges bare names against THIS box's binaries, for launchd jobs that exist only on macOS — a NON-VERDICT on $(uname -s 2>/dev/null || echo unknown), not a pass"
}

@test "the lint is present and executable" {
  [ -x "$LINT" ]
}

@test "--selftest passes (the gate keys on this exit code)" {
  run "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "--selftest's verdict does not move when the BOX gains a binary (backlog f85fce7c26f5)" {
  # THE DEFECT, STATED AS THE EXPERIMENT THAT FOUND IT. On a Linux box, `apt-get install shellcheck`
  # — which touches no file in this repository — moved --selftest from 11 failures to 14. Fourteen of
  # its 42 cases named a REAL binary (`shellcheck`, `tmux`, `yq`, `md5`), and a finding needs the name
  # to be installed somewhere AND unreachable on the job's PATH, so each case's polarity was set by
  # the invoker's tool inventory. ship-land.sh gate-reds on this exit code, so off Darwin the arm
  # refused every land — a docs-only one included — and eight cloud dispatches of f85fce7c26f5 pushed
  # eight branches that could not be landed.
  #
  # The fixtures now name binaries installed NOWHERE, so this asserts the property directly rather
  # than the instance: prepend a directory full of executables named after the words the fixtures
  # used to use, and the verdict must not move. It fails on the revision before the conversion.
  local shim="$BATS_TEST_TMPDIR/shim"
  mkdir -p "$shim"
  local b
  for b in shellcheck tmux yq md5 node jq swift plutil sqlite3; do
    printf '#!/bin/sh\nexit 0\n' > "$shim/$b"
    chmod +x "$shim/$b"
  done

  # Compare the FAILING-CASE COUNT as well as the exit status. The status alone is a one-bit oracle
  # and both arms were red together on the revision this pins: it would have read "invariant" while
  # the shim moved 14 failures to 17. The count is what actually names a case whose polarity flipped.
  run env PATH="$shim:$PATH" "$LINT" --selftest
  local shim_st="$status" shim_n
  shim_n="$(printf '%s\n' "$output" | grep -c 'SELFTEST FAIL' || true)"
  run "$LINT" --selftest
  local bare_st="$status" bare_n
  bare_n="$(printf '%s\n' "$output" | grep -c 'SELFTEST FAIL' || true)"

  # ONE ASSERTION PER FACT, each its own scannable AND-OR list. The obvious spelling
  # `[ a ] && [ b ] || { … }` is what bats-assert-liveness flags as and-absorbed, and its fixer
  # declines it by name rather than guessing — so it is written out instead of contracted.
  local diag="--selftest answered exit $bare_st / $bare_n failing case(s) bare, and exit $shim_st / $shim_n with a directory of stub binaries prepended. Some case is still spelled with a real binary name, so its verdict is a fact about the box."
  [ "$shim_st" -eq "$bare_st" ] || { echo "$diag"; false; }
  [ "$shim_n" -eq "$bare_n" ] || { echo "$diag"; false; }
  [ "$bare_st" -eq 0 ]
}

@test "the real tree is clean under the shipped allowlist" {
  # If this goes red, either a new bare-name site landed or a grandfathered one was fixed without
  # deleting its allowlist line. Both are the ratchet working; neither is a reason to widen it.
  darwin_only_tree_arm
  run env -u CC_UNATTENDED_OWN "$LINT" "$REPO"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "the detector is NOT vacuous: with the allowlist emptied, the real corpus reports findings" {
  # The one assertion that would have caught the two vacuousness bugs this file shipped with in
  # development — a settings.json-keyed hook population that selected nothing under a fixture root,
  # and a BSD-vs-GNU sed alternation that made the whole launchd half scan zero files while
  # reporting clean. A lint whose clean verdict is indistinguishable from "I looked at nothing" is
  # worth less than no lint, because it is believed.
  run env -u CC_UNATTENDED_OWN CC_UNATTENDED_ALLOWLIST="" "$LINT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unreachable"* ]]
}

@test "BOTH halves are non-vacuous — the emptied-allowlist run names a hook AND a launchd target" {
  # The generating item required a positive control for each half separately: the plist half was
  # near-vacuous by construction in its predecessor spec, and it was silently scanning nothing here
  # too. `hooks/` proves the hook half reached files; a scripts/ or bin/ finding attributed to a
  # plist's own PATH proves the launchd half did.
  run env -u CC_UNATTENDED_OWN CC_UNATTENDED_ALLOWLIST="" "$LINT" "$REPO"
  [[ "$output" == *"hooks/"* ]] || { echo "hook half found nothing:"; echo "$output"; false; }
  [[ "$output" == *"plist's own PATH"* ]] || { echo "launchd half found nothing:"; echo "$output"; false; }
}

@test "both populations are non-empty (an empty population is a silent green)" {
  run "$LINT" --list
  [ "$status" -eq 0 ]
  local hooks_n launchd_n
  hooks_n="$(printf '%s\n' "$output" | grep -c '^  hooks/')"
  launchd_n="$(printf '%s\n' "$output" | grep -c '^  com\.')"
  [ "$hooks_n" -gt 10 ] || { echo "hook population is $hooks_n — implausibly small"; false; }
  [ "$launchd_n" -gt 10 ] || { echo "launchd population is $launchd_n — implausibly small"; false; }
}

@test "the bats corpus is a NON-EMPTY population — 'scans 0 test files' is the bug, restated" {
  # This lint judged ZERO of tests/*.bats until 2026-08-06, and the corpus is what the two scheduled
  # runners actually execute. A zero here is not a clean corpus, it is the original defect returning,
  # and it would show up as a green gate — so it is asserted by COUNT, from --list's own census.
  run "$LINT" --list
  [ "$status" -eq 0 ]
  local corpus_n
  corpus_n="$(printf '%s\n' "$output" | sed -n 's/^BATS-CORPUS POPULATION (\([0-9]*\) file(s)).*/\1/p')"
  [ -n "$corpus_n" ] || { echo "--list printed no corpus census at all:"; echo "$output"; false; }
  [ "$corpus_n" -gt 100 ] || { echo "bats corpus population is $corpus_n — implausibly small"; false; }
}

@test "every plist in CORPUS_RUNNERS exists — a renamed runner must not silently empty the corpus" {
  # The runners are NAMED rather than inferred (both inferences were measured and rejected; see the
  # lint's header). A name is the one thing that can rot without anyone noticing, so it is checked
  # from the other end: --list resolves each runner to a PATH, and a runner that has gone missing
  # resolves to nothing. The lint's own answer to this is exit 2 on the real tree, which case 19 of
  # --selftest would catch; this asserts the census a reader actually looks at.
  run "$LINT" --list
  [ "$status" -eq 0 ]
  local runners_n
  runners_n="$(printf '%s\n' "$output" | grep -c '^  via com\.')"
  [ "$runners_n" -ge 2 ] || {
    echo "only $runners_n corpus runner(s) resolved — CORPUS_RUNNERS names a plist the tree no longer has:"
    printf '%s\n' "$output" | sed -n '/^BATS-CORPUS/,$p'
    false
  }
}

@test "the bats half is NOT vacuous: an emptied allowlist names a tests/ file against a runner PATH" {
  # The third positive control, matching the one each older half already has. Without it the corpus
  # could be scanned, judged, and report nothing for a reason nobody would ever see — which is the
  # state this whole half was added to end, and which looked exactly like a clean gate for months.
  run env -u CC_UNATTENDED_OWN CC_UNATTENDED_ALLOWLIST="" "$LINT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tests/"* ]] || { echo "bats half found nothing:"; echo "$output"; false; }
}

@test "the corpus runners' PATH really does omit /sbin — the premise this half rests on" {
  # If a runner's PATH ever gains /usr/sbin:/sbin, the /sbin-only class stops being reachable-by-
  # accident and this half quietly stops reporting it — a fine outcome, but one that must be a
  # DECISION rather than a drift nobody noticed. Assert the premise so widening the PATH shows up
  # here as a failing test with this comment attached, not as a silently narrower lint.
  run "$LINT" --list
  [ "$status" -eq 0 ]
  local n
  n="$(printf '%s\n' "$output" | grep '^  via com\.' | grep -c '/sbin' || true)"
  [ "$n" -eq 0 ] || {
    echo "$n corpus runner(s) now carry /sbin on PATH — the md5 class is no longer detectable there."
    echo "That may be correct. If it is, retire this test deliberately; do not delete it in passing."
    printf '%s\n' "$output" | grep '^  via com\.'
    false
  }
}

@test "the launchd census parses INLINE export PATH, not just the EnvironmentVariables key" {
  # (A) of the generating item: only ONE plist in this corpus uses the EnvironmentVariables dict, so
  # a lint reading that key alone judges 1 of 23 and calls the rest clean. If this regresses, every
  # inline-PATH job reads as "launchd default" and the half silently narrows to nothing.
  run "$LINT" --list
  [ "$status" -eq 0 ]
  local inline
  inline="$(printf '%s\n' "$output" | grep -c 'homebrew')"
  [ "$inline" -gt 5 ] || { echo "only $inline plists resolved a Homebrew-bearing PATH — inline parsing has regressed"; echo "$output"; false; }
}

@test "no plist is classified LOGIN_SHELL by its interpreter path alone" {
  # The login-shell escape hatch is keyed on the -l FLAG. An earlier spelling tested the shell NAME
  # and so matched the string "/bin/bash", which exempted every plain `/bin/bash -c` job — the
  # largest at-risk bucket — from the scan entirely. Fail-open, and invisible.
  run "$LINT" --list
  [ "$status" -eq 0 ]
  local n; n="$(printf '%s\n' "$output" | grep -c 'LOGIN_SHELL' || true)"
  [ "$n" -eq 0 ] || {
    echo "$n plist(s) read LOGIN_SHELL; each is skipped wholesale. Confirm each really passes -l:"
    printf '%s\n' "$output" | grep 'LOGIN_SHELL'
    false
  }
}

@test "the lint itself depends on no non-stock binary (it would be self-refuting)" {
  # It runs on /usr/bin/python3, /usr/bin/jq and /usr/bin/sed — all stock — plus a plist reader.
  # A lint that forbids a Homebrew dependency while carrying one could never run in the environment
  # it is describing.
  for b in /usr/bin/python3 /usr/bin/sed; do
    [ -x "$b" ] || { echo "$b is missing — the lint's own dependency is not stock after all"; false; }
  done
  # THE PLIST READER IS A PAIR, NOT A BINARY, and this test used to name only the macOS half. It
  # asserted /usr/libexec/PlistBuddy — stock on macOS and present on no other system — so on a
  # non-Darwin box the test that certifies "no non-stock dependency" was itself the thing failing
  # over one. The lint now reads a plist through PlistBuddy where it exists and python3's stdlib
  # `plistlib` where it does not, so the claim to assert is that AT LEAST ONE reader is available:
  # the disjunction is what makes the dependency stock everywhere rather than stock on one OS.
  [ -x /usr/libexec/PlistBuddy ] || [ -x /usr/bin/python3 ] || {
    echo "neither /usr/libexec/PlistBuddy nor /usr/bin/python3 is executable — the lint has no plist reader"
    false
  }
  # Assert only what that claim MEANS: the lint EXECUTES with no Homebrew on PATH. Deliberately not
  # "produces an identical verdict" — the corpus scan legitimately reports less when a binary is
  # absent from the box entirely, and conflating the two is what made an earlier version of this
  # test fail for a reason that had nothing to do with the lint's own dependencies.
  run env -i PATH="$STOCK" HOME="$HOME" bash "$LINT" --list
  [ "$status" -eq 0 ] || { echo "the lint could not RUN on a stock PATH:"; echo "$output"; false; }
  [[ "$output" == *"HOOK POPULATION"* ]]
}

@test "the ratchet is not environment-sensitive: a stripped PATH must not manufacture stuck entries" {
  # A stuck entry must mean "this site was FIXED", never "I could not see the binary from here". If
  # the allowlist were consulted after the is-it-installed filter, stripping Homebrew and fnm would
  # make every non-stock finding vanish, every allowlist line read as stuck, and the gate go RED over
  # a machine's tool inventory instead of over the land — fail-closed, on a fresh checkout.
  #
  # IT IS A TREE ARM DESPITE ITS NAME. It strips the PATH and then scans the REAL repository, so the
  # allowlist it asserts is the one written for the operator's Mac; off Darwin the stuck-entry set is
  # computed over a different box's binaries and the test reports a red that names no defect. The
  # property it guards — allowlist BEFORE the is-it-installed filter — is asserted hermetically by
  # --selftest case 9, which is why gating this arm costs no coverage of the ordering itself.
  darwin_only_tree_arm
  run env -i PATH="$STOCK" HOME="$HOME" bash "$LINT" "$REPO"
  [ "$status" -eq 0 ] || {
    echo "the shipped allowlist did not survive a stripped PATH:"; echo "$output"; false;
  }
}

@test "an unusable scan root is a NON-VERDICT (exit 2), never a clean bill" {
  run "$LINT" "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$status" -eq 2 ]
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  run "$LINT" "$BATS_TEST_TMPDIR/empty"
  [ "$status" -eq 2 ]
}

@test "the three hooks fixed by this land actually harden PATH" {
  # These are the sites whose failure had a consequence: a BLOCKING TaskCompleted gate that would
  # reject every task with a 127 body, a pane-close actuator that would no-op, and an SSOT read that
  # would silently fall through to a hardcoded model id. A revert of any one is a regression the
  # ratchet alone would not name, because the allowlist has no entry for them to become stuck.
  for f in hooks/task-quality-gate.sh hooks/teammate-auto-shutdown.sh hooks/agent-teams-enforce.sh; do
    grep -qE '^PATH="\$PATH:' "$REPO/$f" || { echo "$f no longer hardens PATH"; false; }
  done
}

@test "the hardening APPENDS — a prepend would change resolution order for every session" {
  # ~/.claude/bin must lead the appended segment so `bats` still lands on the cc-bats QoS chokepoint
  # rather than the raw Homebrew binary behind it.
  for f in hooks/task-quality-gate.sh hooks/teammate-auto-shutdown.sh hooks/agent-teams-enforce.sh; do
    run grep -E '^PATH="\$PATH:\$HOME/\.claude/bin:' "$REPO/$f"
    [ "$status" -eq 0 ] || { echo "$f does not append with ~/.claude/bin first"; false; }
  done
}

@test "the binary inventory COVERS the real corpus — a name it omits is a box-dependent finding" {
  # The staleness guard on EMBEDDED_BINARY_INVENTORY, and the half --selftest structurally cannot
  # assert: its fixtures are synthetic trees, so only a run against the REAL corpus can catch the
  # inventory drifting behind the tree it describes.
  #
  # WHY COVERAGE IS THE ASSERTABLE PROPERTY. `installed_somewhere` is `inventory OR live probe`, and
  # a NO drops the finding — so a binary the inventory omits is reported only on boxes that install
  # it. That is the defect the inventory exists to remove: a file in the AUTHOR'S OWN DIFF whose
  # finding exists only because the landing box has a binary the author's box lacks blocks that
  # author on a red they cannot reproduce. Every name in the corpus's finding set being IN the
  # inventory is exactly the condition under which the two boxes agree.
  #
  # This does NOT re-prove the union arm — that is selftest 20a/20b/20c, which own the mechanism and
  # die when the arm is reverted. Attempting to prove the arm here would be VACUOUS and was measured
  # to be: on the box that GENERATED the inventory, every name it vouches for is also live, so no
  # real-corpus run can distinguish the arm from its absence. The arm's value is cross-box; only its
  # coverage is local.
  run env -i PATH="$PATH" HOME="$HOME" CC_UNATTENDED_ALLOWLIST="" bash "$LINT" "$REPO"
  [ "$status" -eq 1 ] || { echo "expected findings with the allowlist emptied, got status $status"; echo "$output"; false; }

  local missing="" b
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    grep -qxF "$b" <(sed -n "/^EMBEDDED_BINARY_INVENTORY=/,/^INVENTORY\$/p" "$LINT") || missing="$missing $b"
  done <<< "$(printf '%s\n' "$output" | sed -n 's/.*`\([^`]*\)` is unreachable on.*/\1/p' | sort -u)"

  [ -z "$missing" ] || {
    echo "these binaries are reported by the real corpus but absent from EMBEDDED_BINARY_INVENTORY:"
    echo " $missing"
    echo "Their findings are therefore a function of the caller's PATH, not of the tree."
    echo "Fix: scripts/unattended-path-lint.sh --emit-inventory  (it unions; it never subtracts)"
    false;
  }

  # POSITIVE CONTROL: the loop above must actually have had names to check. An empty finding set
  # would satisfy the emptiness assertion above without testing anything.
  run bash -c "printf '%s\n' \"\$1\" | sed -n 's/.*\`\\([^\`]*\\)\` is unreachable on.*/\\1/p' | sort -u | grep -c ." _ "$output"
  [ "${output:-0}" -gt 0 ] || { echo "no binary names parsed out of the report — the parser is broken"; false; }
}

# ── the gate wiring: the TREE arm is Darwin-scoped, the SELFTEST arm is not ─────────────────────
# Enforced here rather than only in ship-land.sh for the reason the sibling suite states
# (tests/moving-ref-control-lint.bats, "the land gate calls it, own-scoped"): gate-select maps this
# suite from exactly one edge — the lint — so an edit to the GATE never selects it, and the wiring
# is the enforcing surface. (memory: enforcement-must-live-at-the-chokepoint)
@test "the land gate scopes the TREE arm to Darwin — and still BLOCKS there" {
  # WHY THE SCOPE EXISTS, in one line: reachable_on answers "is this binary on the PATH the job runs
  # with" by statting the INVOKING box, and the jobs it judges are launchd jobs, which exist only on
  # macOS. darwin_only_tree_arm() at the top of this file already declines to evaluate the real-tree
  # case off Darwin for exactly that reason; a gate may not BLOCK on a predicate this suite skips.
  grep -q 'SHIP_LAND_UNATTENDED_DARWIN_SCOPE' "$REPO/scripts/ship-land.sh" || false
  grep -q 'unattended-path findings above are ADVISORY on' "$REPO/scripts/ship-land.sh" || false

  # THE HALF THAT MATTERS MORE. An exemption that swallowed the arm entirely would satisfy the two
  # greps above and silently delete enforcement on the one platform that can judge. Both the RED
  # branch and its gate_red must survive, and the Darwin test must be a NEGATIVE match (`!= "Darwin"`)
  # so the advisory path is the exception and blocking stays the default.
  grep -q 'gate_red unattended-path$' "$REPO/scripts/ship-land.sh" || false
  grep -q '!= "Darwin"' "$REPO/scripts/ship-land.sh" || false

  # The SELFTEST arm is deliberately NOT scoped: c1904ed8 made it environment-independent instead
  # (the embedded binary inventory), so re-scoping it would discard that fix rather than use it.
  grep -q 'unattended-path-lint --selftest FAILED' "$REPO/scripts/ship-land.sh" || false
}

@test "own-scope and the NON-VERDICT arm are both still wired (neither is the Darwin scope's job)" {
  # Three independent narrowings guard this arm and they are not interchangeable: own-scope decides
  # WHOSE findings block, the Darwin scope decides WHERE the predicate can judge at all, and exit 2
  # is the could-not-RUN third state. Collapsing any pair would make one of the three unreachable.
  grep -q 'UNATTENDED_LINT=' "$REPO/scripts/ship-land.sh" || false
  grep -q 'own_run UNATTENDED CC_UNATTENDED_OWN' "$REPO/scripts/ship-land.sh" || false
  grep -q 'SHIP_LAND_UNATTENDED_OWN_SCOPE' "$REPO/scripts/ship-land.sh" || false
  # exit 2 must be GATE_KILLED (retryable), never gate_red (author-fixable) — the sibling's rule.
  grep -q 'arm_nonverdict "unattended-path-lint"' "$REPO/scripts/ship-land.sh" || false
}
