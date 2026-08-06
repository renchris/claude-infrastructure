#!/usr/bin/env bats
# Guards scripts/unattended-path-lint.sh — the ratchet on bare-name binary resolution along the
# paths nobody watches (launchd jobs, settings.json hooks).
#
# WHY THIS SUITE IS THIN AND WHY THAT IS DELIBERATE. The lint carries its own --selftest with 18
# cases, and that selftest is what the gate runs; duplicating those cases here would create two
# oracles over one behaviour, which is the shape that goes stale asymmetrically (memory:
# sibling-auditors-must-share-the-state-model). So this suite asserts the things --selftest
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

@test "the lint is present and executable" {
  [ -x "$LINT" ]
}

@test "--selftest passes (the gate keys on this exit code)" {
  run "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "the real tree is clean under the shipped allowlist" {
  # If this goes red, either a new bare-name site landed or a grandfathered one was fixed without
  # deleting its allowlist line. Both are the ratchet working; neither is a reason to widen it.
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
  # It runs on /usr/bin/python3, /usr/bin/jq, /usr/libexec/PlistBuddy and /usr/bin/sed — all stock.
  # A lint that forbids a Homebrew dependency while carrying one could never run in the environment
  # it is describing.
  for b in /usr/bin/python3 /usr/bin/sed /usr/libexec/PlistBuddy; do
    [ -x "$b" ] || { echo "$b is missing — the lint's own dependency is not stock after all"; false; }
  done
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
