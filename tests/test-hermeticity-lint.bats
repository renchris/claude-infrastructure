#!/usr/bin/env bats
# test-hermeticity-lint — the RATCHET that stops NEW test harnesses from running against AMBIENT
# STATE. Six rules, one mechanism, each a different thing "ambient" can mean: rule 1 is the
# operator's live ~/ ($HOME fixtured in setup()), rule 2 the machine's live LOAD
# (CC_FIRE_CAPACITY_GATE=off, for a suite that drives handoff-fire), rule 3 an operator-armed lever
# (LCW_ORPHAN_CLOSE, for a suite driving the orphan-close leg), rule 4 a SIBLING RUN OF ITSELF — a
# tool's EMBEDDED selftest whose scratch path is the same string every time, so two concurrent runs
# collide — rule 5 state that does not resolve under $HOME at all (an absolute /tmp default, or a
# bare name executed off the operator's PATH), and rule 6 a value already IN THE ENVIRONMENT: a
# variable this repo injects into every pane it launches, which every descendant of a fired pane
# inherits, bats included. Rules 1-3, 5 and 6 judge tests/*.bats; rule 4 judges the ~50 tools in
# bin/, scripts/ and hooks/ that ship a selftest instead of a suite and were outside the ratchet
# entirely until it landed. Two properties matter for each and both are proved here: it
# discriminates (RED on a new violation, RED on an entry that stayed grandfathered after being
# fixed), and it is GREEN on the tree as it stands — a lint that ships standing-RED is the rot this
# repo is killing, and the nightly auto-runs every scripts/*lint*.sh, so a false RED here poisons
# the whole nightly signal.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/test-hermeticity-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"    # dogfood: this suite obeys its own rule 1
  export CC_FIRE_CAPACITY_GATE=off                         # dogfood rule 2 — this file names handoff-fire
  export CC_ADMIT_GATE=off                                 # dogfood rule 7 — it names capacity-admit's callers
  # Rule 4 OFF by default here, and switched back ON by name in the cases that mean to test it.
  # Every fixture-targeted case below passes a temp dir as the scan dir, but rule 4's population is
  # the REPO's tool dirs — it is driven off $ROOT, not off that argument, precisely so ship-land's
  # `lint tests` still gets its selftests judged. Left ambient, a rule-4 verdict about the checkout
  # would silently become the answer to a rule-1 or rule-2 assertion about a two-file fixture.
  export CC_HERM_SELFTEST_RULE=off
  # Dogfood RULE 5, the same way this file dogfoods rules 1 and 2 above. It names handoff-fire.sh
  # (rule 2's scope control) and the lint itself, and both carry non-$HOME seams — so without these
  # four pins this suite would have to be GRANDFATHERED under the very rule it proves. A lint's own
  # suite sitting on its own exemption list is the rot this repo is killing.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/absent-sweep.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/absent-heal-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HERM_SEAM_SELFPROBE="$BATS_TEST_TMPDIR/absent-seam-anchor"
  # Dogfood RULE 6 for the same reason, on the same file: the lint declares CC_HERM_ENV_SELFPROBE as
  # both an injection and a read, which is its inherited-value extractor's anchor — so this suite,
  # which names the lint's path, is in scope for it. Any position clears rule 6; a value is used
  # here rather than an unset only because it reads more obviously as deliberate.
  export CC_HERM_ENV_SELFPROBE=0
  # Rule 5 OFF by default here, for rule 4's reason verbatim: its seam table is derived from the
  # REPO's tool dirs, not from the two-file fixture each case below passes as its scan dir, so left
  # ambient a rule-5 verdict about the checkout would silently become the answer to a rule-1 or
  # rule-2 assertion about a fixture. The rule-5 cases switch it back on BY NAME, against a fixture
  # seam root of their own.
  export CC_HERM_SEAM_RULE=off
  # Rule 6 OFF by default here, for rules 4 and 5's reason verbatim: its table is derived from the
  # REPO's tool dirs, not from the fixture scan dir each case passes, so left ambient a rule-6
  # verdict about the checkout would silently become the answer to a rules-1-5 assertion about a
  # two-file fixture. The rule-6 cases switch it back on BY NAME, against a fixture tool root.
  export CC_HERM_ENV_RULE=off
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX"
  # A neutral, rule-1-clean bats dir for the rule-4 cases. They still have to pass a scan dir (the
  # two passes compose, and 2 dominates 1), so it must be one lint_dir returns 0 on — otherwise the
  # exit code under test would be lint_dir's verdict about a missing directory, not rule 4's.
  NEUTRAL="$FIX/neutral"; mkdir -p "$NEUTRAL"
  { echo '#!/usr/bin/env bats'; echo 'setup() {'; echo '  export HOME="$BATS_TEST_TMPDIR/home"'
    echo '}'; echo '@test "x" { true; }'; } > "$NEUTRAL/zz-neutral.bats"
}

# write a fixture TOOL into a fresh root $1 (rule 4 scans <root>/bin, <root>/scripts, <root>/hooks),
# named $2, whose body is $3. Rule 4's fixtures are tools, not suites, so they need their own maker.
mk_tool() {
  mkdir -p "$FIX/$1/bin"
  { echo '#!/bin/bash'; printf '%s\n' "$3"; } > "$FIX/$1/bin/$2"
}

# write a fixture suite into a fresh dir $1, whose setup() body is $2 and whose single @test body is
# $3 (default `true`). $3 is where a fixture's handoff-fire reference goes — rule 2's scope is
# textual and file-wide, while its PIN must be in setup(), so the two must be settable separately.
mk_suite() {
  mkdir -p "$FIX/$1"
  { echo '#!/usr/bin/env bats'; echo 'setup() {'; echo "  $2"; echo '}'; echo "@test \"x\" { ${3:-true}; }"; } \
    > "$FIX/$1/zz-fixture.bats"
}

# mk_suite_in_tests — the SAME suite, laid out under a directory really named `tests`, and the scan
# dir is that directory (callers pass "$FIX/<name>/tests").
#
# WHY IT HAS TO EXIST (backlog c1a29f8ee045). Every own-scope case below passes ship-land's real
# own-set form — a repo-relative path like `tests/zz-fixture.bats` — against a fixture that lived in
# `$FIX/leak/`. They passed because the matcher basenamed BOTH sides, so the directory in the entry
# was decoration and `scripts/zz-fixture.bats` would have passed identically. That is precisely the
# collapse: the control could not tell the two apart, so it could not catch a matcher that could
# not either. With a real `tests` directory the entry matches on a component boundary and the
# assertion means what its name says.
mk_suite_in_tests() {
  mkdir -p "$FIX/$1/tests"
  { echo '#!/usr/bin/env bats'; echo 'setup() {'; echo "  $2"; echo '}'; echo "@test \"x\" { ${3:-true}; }"; } \
    > "$FIX/$1/tests/zz-fixture.bats"
}

# THE THIRD STATE, for the two cases below that lint the REAL tree. The lint answers 0 (clean) and
# 1 (a leak / a stuck ratchet) — and 2, which is not an answer at all: "UNUSABLE — a predicate
# failed to run … Re-run when the box is quieter; do not 'fix' any suite on it." Asserting `-eq 0`
# collapses that third state onto the second, which is this repo's own gate-never-ran-is-not-
# gate-red rule broken by the suite that proves the ratchet.
#
# It is REACHED, not theoretical: deploy-live.sh runs this file post-deploy at `nice -n 19` beside a
# full corpus, and the lint's pure predicates lose forks there (scripts/host-suites.manifest § CAUSE
# — CORRECTED 2026-07-29, measured at loadavg 15-48; ed4e6c6a's 3x retry reserves exit 2 for a box
# that cannot fork a grep three times running). That is how backlog 1807b8c02c85 was filed: one
# `not ok`, over a tree measured clean at the same sha before and after, reported to the operator as
# "the LIVE layer is advanced and FAILING host suites". deploy-live already refuses to make this
# mistake about its OWN bound (rc 124 ⇒ CUT, never RED); so does the sibling host suite
# tests/deploy-parity-live.bats:50, which skips its exit 3 for the same reason in the same lane.
# This file was the one that never learned it.
#
# NARROW BY CONSTRUCTION — it keys on the machine-state REASON, never on exit 2. The lint's other
# exit-2 reasons are structural and must stay RED: a bad ROOT ("not a directory") is exactly how
# f37a84cf was caught — `dirname "$0"` resolved to ~/.claude, which has no tests/ — and this
# post-deploy wrapper is what caught it; a blind rule-4 extractor is the calibration-free control
# that stops a broken extractor reading as a clean bill. Abstaining on the whole non-zero class
# would retire both, so the match is an allowlist of the ONE retryable reason and every unknown
# reason still fails. Both halves are proved by the control case below.
skip_if_unrunnable() {
  [ "$status" -eq 2 ] || return 0
  printf '%s\n' "$output" | grep -q 'failed to run' || return 0
  skip "NON-VERDICT: the lint could not run a predicate on this box (exit 2) — a fact about the machine, not a claim about the tree"
}

# The --selftest twin of the above, and it exists because the three --selftest assertions below
# asserted `-eq 0` against a script that could only ever exit 0 or 1. Its case (e) lints the REAL
# tree, so a lost fork there set fails=1 and the whole selftest exited 1 — "the ratchet does not
# discriminate" — which THIS FILE then filed as a HOST RED about the operator's clean tree, and
# which postland-verify reads as INSTRUMENT-BROKEN (scan skipped, no green claimable). The lint now
# separates that case and exits 2 saying so (backlog 2c5ab136d63f).
#
# NARROW BY CONSTRUCTION, on the same argument as its sibling: exit 2 alone is not enough, because
# the selftest's OTHER exit-2 reason would be a structural one. It keys on the REMEDY's own marker
# — the line the fix ADDED — never on the defect's spelling, which is how backlog 57ff249657e0's
# probe died: it grepped `hits=`, the exact token its fix deleted, so it could never once retract.
#
# The DECISION is split out as a pure predicate so the control below can drive it on both shapes
# without a full (>2 min) --selftest run, and so that control drives THE SAME code the skip uses —
# a re-implemented predicate in the test would certify a rule production does not follow.
selftest_is_nonverdict() { # <status> <output> → 0 = abstain, 1 = judge it
  [ "$1" -eq 2 ] || return 1
  printf '%s\n' "$2" | grep -q 'SELFTEST NON-VERDICT'
}
skip_if_selftest_nonverdict() {
  selftest_is_nonverdict "$status" "$output" || return 0
  skip "NON-VERDICT: --selftest could not run a predicate on this box (exit 2) — a fact about the machine, not a claim about the tree"
}

@test "the --selftest abstain is TWO-SIDED: the marker abstains, every other exit-2 still judges" {
  # This guard only ever fires on a loaded box, so without a control it is dead code nobody has seen
  # fire — and a skip helper that has never fired is indistinguishable from one that always does.
  # Both halves matter: too narrow and the HOST RED this fixes comes back; too wide and it swallows
  # the structural exit-2 reasons (a bad ROOT is exactly how f37a84cf was caught), which is the
  # failure the lint's own --selftest cases (e2)/(e3) pin on the other side of the same split.
  # NOT `fail` — this suite loads no bats-assert, so `fail` is `command not found` (status 127) and
  # every diagnostic below would be replaced by that. Found by mutating the predicate: the control
  # went red for the right reason with entirely the wrong message.
  selftest_is_nonverdict 2 'test-hermeticity-lint: SELFTEST NON-VERDICT: a predicate could not RUN while scanning' \
    || { echo "a real machine non-verdict was not abstained on — the HOST RED is back" >&2; return 1; }
  selftest_is_nonverdict 2 'test-hermeticity-lint: ⛔ not a directory: /nope' \
    && { echo "a bad ROOT was abstained on — the guard has grown over the structural failure it must not hide" >&2; return 1; }
  selftest_is_nonverdict 1 'test-hermeticity-lint --selftest: FAILED — the ratchet does not discriminate.' \
    && { echo "a genuine FAILED selftest was abstained on — the instrument check is now unfalsifiable" >&2; return 1; }
  return 0
}

@test "the real tree is CLEAN (exit 0) — the embedded allowlist matches HEAD, nightly stays green" {
  # Rules 1-4 judge the tree here: 1-3 are on by default and rule 4 is switched on by name. Rules 5
  # and 6 stay OFF (setup() pins them, for the reason recorded there) — their real-tree guarantee is
  # proved in the lint's own --selftest case (e), where it costs nothing. Deliberately NOT widened:
  # backlog b59eb997d035 is the standing lesson that the one assertion here which lints the WHOLE
  # TREE mid-suite passes standalone, fails in-suite, and alone kept 14 green stamps red.
  CC_HERM_SELFTEST_RULE=on run bash "$LINT"
  skip_if_unrunnable
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'test-hermeticity-lint: clean'
}

@test "the third state DISCRIMINATES: a lost fork abstains, a bad ROOT still REDs" {
  # The control for skip_if_unrunnable, and it has to prove BOTH directions — a guard that only ever
  # widens is how detection disappears without anything naming the loss.
  #
  # (a) THE RETRYABLE FORM IS REACHABLE. A `grep` that cannot run is precisely what fork exhaustion
  # looks like to the lint's pure predicates, so stub one onto PATH for the length of one run.
  # Without this the guard is unfalsifiable: dead code nobody has ever seen fire, guarding the one
  # case that files a backlog packet against the operator's tree.
  mkdir -p "$FIX/stub"
  { echo '#!/bin/bash'; echo 'exit 2'; } > "$FIX/stub/grep"; chmod +x "$FIX/stub/grep"
  mk_suite quiet 'export HOME="$BATS_TEST_TMPDIR/home"'
  PATH="$FIX/stub:$PATH" run bash "$LINT" "$FIX/quiet"
  [ "$status" -eq 2 ] || false
  printf '%s\n' "$output" | grep -q 'failed to run' || false

  # (b) THE TOO-WIDE HALF. A bad ROOT also exits 2, but for a STRUCTURAL reason that must stay RED —
  # f37a84cf shipped a `dirname "$0"` that resolved to ~/.claude, which has no tests/, and this
  # post-deploy wrapper is what caught it. So the phrase the guard keys on must be ABSENT here; if
  # this assertion ever has to be relaxed, the guard has grown into the abstain that hides that bug.
  run bash "$LINT" "$FIX/definitely-absent"
  [ "$status" -eq 2 ] || false
  [ "$(printf '%s\n' "$output" | grep -c 'failed to run')" -eq 0 ] || false
}

@test "--selftest is GREEN and every discriminating case is exercised" {
  run bash "$LINT" --selftest
  skip_if_selftest_nonverdict
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE -e '--selftest: [0-9]+/[0-9]+'
}

@test "--selftest is GREEN through a SYMLINK to the script (the DEPLOYED ~/.claude path)" {
  # ~/.claude/scripts/test-hermeticity-lint.sh is a per-file symlink into this checkout, and that is
  # the path an agent naturally reaches for. Before $0 was resolved through symlinks, ROOT became
  # ~/.claude — which has no tests/ — so the real-tree case failed and reported it as "the embedded
  # allowlist is stale": a false RED on a self-evidencing proof, misnaming its own cause. Found
  # 2026-07-26 by running the deployed copy immediately after landing it.
  ln -s "$LINT" "$FIX/linked-lint.sh"
  run bash "$FIX/linked-lint.sh" --selftest
  skip_if_selftest_nonverdict
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE -e '--selftest: [0-9]+/[0-9]+'
}

@test "a bad ROOT is reported as a NON-VERDICT, never as a stale allowlist" {
  # The discrimination that makes the failure above self-explaining rather than misleading: exit 2
  # (could not scan) and exit 1 (allowlist really is stale) are different claims. CC_HERM_SELFTEST_ROOT
  # is not a seam the script has — so drive it the honest way, through a symlink whose parent has no
  # tests/ dir, which is exactly the real-world shape.
  mkdir -p "$FIX/noroot/scripts"
  ln -s "$LINT" "$FIX/noroot/scripts/test-hermeticity-lint.sh"
  # $FIX/noroot has no tests/ ⇒ case (e) gets exit 2. Resolution now follows the symlink to the real
  # checkout, so this must still be GREEN — the assertion is that we do not fabricate a stale-allowlist
  # verdict out of a path problem.
  run bash "$FIX/noroot/scripts/test-hermeticity-lint.sh" --selftest
  skip_if_selftest_nonverdict
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'allowlist is stale')" -eq 0 ]
}

@test "RED: a NEW non-hermetic suite fails (an unlisted suite must fixture \$HOME)" {
  mk_suite leak 'REPO="$(pwd)"'
  CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/leak"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'LEAK'
  echo "$output" | grep -q 'Do NOT add to the allowlist'
}

@test "RED: an allowlisted suite that is now hermetic fails (the ratchet only ever shrinks)" {
  mk_suite herm 'export HOME="$BATS_TEST_TMPDIR/home"'
  CC_HERM_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/herm"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'RATCHET'
  echo "$output" | grep -q 'delete their lines'
}

@test "GREEN: a hermetic, unlisted suite passes — and so does a grandfathered non-hermetic one" {
  mk_suite herm 'export HOME="$BATS_TEST_TMPDIR/home"'
  CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/herm"
  [ "$status" -eq 0 ]
  mk_suite leak 'REPO="$(pwd)"'
  CC_HERM_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/leak"
  [ "$status" -eq 0 ]
}

@test "a per-TEST \$HOME does not count as hermetic (every other test still hits the live ~/)" {
  mkdir -p "$FIX/pertest"
  { echo '#!/usr/bin/env bats'; echo 'setup() {'; echo '  REPO="$(pwd)"'; echo '}'
    echo '@test "a" { export HOME="$BATS_TEST_TMPDIR/home"; true; }'; echo '@test "b" { true; }'; } \
    > "$FIX/pertest/zz-fixture.bats"
  CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/pertest"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'LEAK'
}

@test "LOUD: an unusable scan dir exits 2, never a silent green" {
  CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/does-not-exist"
  [ "$status" -eq 2 ]
  CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX"                # exists, but holds zero .bats suites
  [ "$status" -eq 2 ]
}

@test "the nightly picks it up automatically (name matches *lint*.sh AND supports_selftest)" {
  case "$(basename "$LINT")" in *lint*.sh) ;; *) false ;; esac    # scripts/*lint*.sh glob
  grep -qE -- '--selftest|selftest\)' "$LINT"                     # nightly's supports_selftest() probe
}

# ── OWN-SCOPE: the ratchet binds on what YOU changed, not on what trunk happens to contain ────────
# Regression cover for the fleet-wide hard stop measured 2026-07-27 (GATE_ARCHITECTURE_PLAN §9):
# a docs-only land was refused by five leaking suites it does not touch. The rule "do not ADD a
# leak" is preserved exactly; only "answerable for everyone else's leak" is removed.

@test "own-scope: a leak OUTSIDE the lander's diff is advisory, not blocking" {
  mk_suite leak 'REPO=x'
  CC_HERM_OWN="tests/something-else.bats" CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/leak"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'advisory, not blocking' || false
}

@test "own-scope: the SAME leak INSIDE the lander's diff still blocks (the rule is intact)" {
  # Laid out under a real `tests` dir so the PATH form is genuinely exercised — see mk_suite_in_tests.
  mk_suite_in_tests leak 'REPO=x'
  CC_HERM_OWN="tests/zz-fixture.bats" CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/leak/tests"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'LEAK' || false
  # …and the collapse control it is paired with: the same basename under a DIFFERENT directory is a
  # different file, so it must NOT block (backlog c1a29f8ee045). RED before the fix.
  CC_HERM_OWN="scripts/zz-fixture.bats" CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/leak/tests"
  [ "$status" -eq 0 ] || false
  # …while a BARE entry stays deliberately wide and still blocks anywhere.
  CC_HERM_OWN="zz-fixture.bats" CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/leak/tests"
  [ "$status" -eq 1 ] || false
}

# THE case the fix exists for, and the one a `${VAR:-}` collapse silently breaks: a land that
# changes NO suite supplies an own-set that is SET BUT EMPTY. That must mean "nothing is mine",
# never "strict".
@test "own-scope: a docs-only land (CC_HERM_OWN set but EMPTY) is not blocked by a foreign leak" {
  mk_suite leak 'REPO=x'
  CC_HERM_OWN="" CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/leak"
  [ "$status" -eq 0 ] || false
}

@test "own-scope: UNSET CC_HERM_OWN keeps whole-tree strictness (postland + bare runs unchanged)" {
  mk_suite leak 'REPO=x'
  CC_HERM_ALLOWLIST="" run env -u CC_HERM_OWN bash "$LINT" "$FIX/leak"
  [ "$status" -eq 1 ] || false
}

@test "own-scope: a stuck ratchet entry outside the diff is advisory; inside it still blocks" {
  mk_suite_in_tests herm 'export HOME="$BATS_TEST_TMPDIR/home"'
  CC_HERM_OWN="tests/other.bats" CC_HERM_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/herm/tests"
  [ "$status" -eq 0 ] || false
  CC_HERM_OWN="tests/zz-fixture.bats" CC_HERM_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/herm/tests"
  [ "$status" -eq 1 ] || false
}

@test "own-scope: ship-land passes its OWN diff and the kill switch restores strictness" {
  # The anchor is the ROUTING, not the assignment spelling. This was `CC_HERM_OWN=` until the P2
  # own-scope work routed all thirteen arms through own_run(), which passes the variable NAME as an
  # ARGUMENT (`own_run HERM CC_HERM_OWN "$own" …`) so the `=` vanished and this went red over a
  # refactor that strengthened the very contract it pins. Keyed on the own_run pair it survives the
  # next re-spelling, and it still fails loudly if the arm is ever un-wired from own_run — which is
  # what would actually break the contract, since own_run is now the single reader of the kill
  # switch below. own_run's own three-state semantics are pinned in tests/gate-ownscope-leak.bats.
  grep -q 'own_run HERM CC_HERM_OWN' "$REPO/scripts/ship-land.sh" || false
  grep -q "SHIP_LAND_HERM_OWN_SCOPE" "$REPO/scripts/ship-land.sh" || false
  # the own-set must come from the landing RANGE, never from the working tree
  grep -q 'git diff --name-only "\$range" -- .tests/\*\.bats' "$REPO/scripts/ship-land.sh" || false
}

@test "CHOKEPOINT: ship-land's own-set covers every population the lint judges, incl. rule 4's" {
  # Own-scope makes a violation OUTSIDE the lander's diff advisory. So the pathspec that builds the
  # own-set IS the gate's scope: while it listed only tests/*.bats, a land ADDING a colliding
  # selftest to bin/ produced an own-set without it, the lint said `collides?` — advisory — and the
  # land went through. The rule would have been detection, never a gate. These three pins are the
  # regression cover for that, one per directory rule 4 walks.
  local spec; spec="$(grep -m1 'git diff --name-only "\$range" --' "$REPO/scripts/ship-land.sh")"
  [[ "$spec" == *"'bin/*'"* ]] || false
  [[ "$spec" == *"'scripts/*.sh'"* ]] || false
  [[ "$spec" == *"'hooks/*.sh'"* ]] || false
}

@test "CHOKEPOINT: ship-land routes the lint's exit 2 to GATE-KILLED, not to a RED about your tree" {
  # The lint has two non-zero codes and they are different CLAIMS: 1 names a file, 2 says a
  # predicate could not run (or the scan found nothing to judge) and ends "do not 'fix' any suite on
  # it". Rule 4 adds two more ways to reach 2 — the denominator floor and its own killed predicates
  # — so the gate must stop reporting a non-verdict as "✗ RED, fix the file named above" with no
  # file named. GATE_KILLED yields the retryable exit 9 that gate_nonzero_code() already exists for.
  grep -q 'herm_rc == 2' "$REPO/scripts/ship-land.sh" || false
  grep -A2 'herm_rc == 2' "$REPO/scripts/ship-land.sh" | grep -q 'NON-VERDICT' || false
  grep -A5 'herm_rc == 2' "$REPO/scripts/ship-land.sh" | grep -q 'GATE_KILLED=1' || false
}

# ── RULE 2: the capacity-gate ratchet — the SAME class as rule 1, a different ambient input ───────
# handoff-fire.sh's capacity_gate() reads live `sysctl vm.loadavg` and REFUSES a net-new fire above
# 2.0 load/core (exit 9); this box sits permanently at 3.4-7.3/core. So a suite that exercises a fire
# without pinning CC_FIRE_CAPACITY_GATE=off in setup() does not test its subject at all — it tests
# what the rest of the fleet happens to be doing. Proven two-sided at 3.39/core on
# tests/fire-engagement.bats: ambient -> `not ok 14`, pinned -> `ok 14`.

@test "RULE 2 RED: a suite that drives handoff-fire without pinning the gate in setup()" {
  mk_suite fireleak 'export HOME="$BATS_TEST_TMPDIR/home"' 'run bash ./scripts/handoff-fire.sh --dry-run'
  CC_HERM_FIRE_ALLOWLIST="" run bash "$LINT" "$FIX/fireleak"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'AMBIENT' || false
  echo "$output" | grep -q 'Do NOT add to the fire allowlist' || false
}

@test "RULE 2 SCOPE CONTROL: the same suite MINUS the handoff-fire reference is GREEN" {
  # The positive control that makes the RED above mean something. These two fixtures differ in
  # exactly one token; if this one also went RED the rule would be flagging every suite in the tree
  # and the RED would be evidence of nothing.
  mk_suite nofire 'export HOME="$BATS_TEST_TMPDIR/home"' 'run bash ./scripts/some-other-tool.sh --dry-run'
  CC_HERM_FIRE_ALLOWLIST="" run bash "$LINT" "$FIX/nofire"
  [ "$status" -eq 0 ] || false
  [ "$(echo "$output" | grep -c 'AMBIENT')" -eq 0 ] || false
}

@test "RULE 2 SCOPE: a PROSE mention is not a reference — and a real path still is (two-sided)" {
  # The third position the lever's name can occupy. strip_comments already ruled out what a suite
  # SAYS ABOUT ITSELF; this rules out a sentence the suite HANDLES AS DATA. Measured case:
  # tests/cc-eligible-history.bats, whose only code mention is a backlog-row TITLE naming the fire
  # as the specification of an item cc-eligible must REFUSE. It fires nothing, was convicted for a
  # sentence, and carried the prescribed pin as a permanent no-op — which is how a pin stops meaning
  # anything.
  #
  # BOTH HALVES IN ONE CASE, deliberately: the two fixtures differ ONLY in whether the identical
  # path sits inside a sentence or in a command. Split across two tests, the OUT half could pass
  # because the predicate matches nothing at all — the vacuity this file exists to prevent.
  mk_suite fireprose 'export HOME="$BATS_TEST_TMPDIR/home"' \
    "run classify 'patch scripts/handoff-fire.sh so the recycle inherits the goal'"
  CC_HERM_FIRE_ALLOWLIST="" run bash "$LINT" "$FIX/fireprose"
  [ "$status" -eq 0 ] || { echo "prose mention was read as a reference:"; echo "$output"; false; }
  [ "$(echo "$output" | grep -c 'AMBIENT')" -eq 0 ] || false

  # ...and the IN half over the SAME path token, so the GREEN above cannot be a dead predicate.
  mk_suite fireexec 'export HOME="$BATS_TEST_TMPDIR/home"' \
    'run bash ./scripts/handoff-fire.sh --dry-run'
  CC_HERM_FIRE_ALLOWLIST="" run bash "$LINT" "$FIX/fireexec"
  [ "$status" -eq 1 ] || { echo "prose-stripping swallowed a REAL reference:"; echo "$output"; false; }
  echo "$output" | grep -q 'AMBIENT' || false
}

@test "RULE 2 GREEN: the pin in setup() clears it — the prescribed fix actually works" {
  mk_suite firepin 'export HOME="$BATS_TEST_TMPDIR/home"; export CC_FIRE_CAPACITY_GATE=off' \
    'run bash ./scripts/handoff-fire.sh --dry-run'
  CC_HERM_FIRE_ALLOWLIST="" run bash "$LINT" "$FIX/firepin"
  [ "$status" -eq 0 ] || false
}

@test "RULE 2 RED: a suite that pins the gate but is STILL grandfathered (the ratchet only shrinks)" {
  mk_suite firepin 'export HOME="$BATS_TEST_TMPDIR/home"; export CC_FIRE_CAPACITY_GATE=off' \
    'run bash ./scripts/handoff-fire.sh --dry-run'
  CC_HERM_FIRE_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/firepin"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'RATCHET-CAP' || false
  echo "$output" | grep -q 'EMBEDDED_FIRE_ALLOWLIST' || false
}

@test "RULE 2 GREEN: an unpinned suite that IS grandfathered passes (today's list blocks nobody)" {
  mk_suite fireleak 'export HOME="$BATS_TEST_TMPDIR/home"' 'run bash ./scripts/handoff-fire.sh --dry-run'
  CC_HERM_FIRE_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/fireleak"
  [ "$status" -eq 0 ] || false
}

@test "RULE 2: a per-TEST capacity pin does not count (every OTHER test still reads ambient load)" {
  # Rule 1's reason verbatim. Four suites in the tree are grandfathered for precisely this shape:
  # they DO mention CC_FIRE_CAPACITY_GATE=off, but only inside individual @test bodies.
  mkdir -p "$FIX/firepertest"
  { echo '#!/usr/bin/env bats'; echo 'setup() {'; echo '  export HOME="$BATS_TEST_TMPDIR/home"'; echo '}'
    echo '@test "a" { CC_FIRE_CAPACITY_GATE=off run bash ./scripts/handoff-fire.sh; }'
    echo '@test "b" { run bash ./scripts/handoff-fire.sh; }'; } \
    > "$FIX/firepertest/zz-fixture.bats"
  CC_HERM_FIRE_ALLOWLIST="" run bash "$LINT" "$FIX/firepertest"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'AMBIENT' || false
}

@test "RULE 2 kill switch: CC_HERM_FIRE_RULE=off disables it — with the RED as its positive control" {
  mk_suite fireleak 'export HOME="$BATS_TEST_TMPDIR/home"' 'run bash ./scripts/handoff-fire.sh --dry-run'
  CC_HERM_FIRE_ALLOWLIST="" run bash "$LINT" "$FIX/fireleak"
  [ "$status" -eq 1 ] || false                          # control: the rule DOES fire on this fixture
  CC_HERM_FIRE_ALLOWLIST="" CC_HERM_FIRE_RULE=off run bash "$LINT" "$FIX/fireleak"
  [ "$status" -eq 0 ] || false
}

@test "RULE 2 own-scope: an AMBIENT violation outside the diff is advisory, inside it blocks" {
  mk_suite_in_tests fireleak 'export HOME="$BATS_TEST_TMPDIR/home"' 'run bash ./scripts/handoff-fire.sh --dry-run'
  CC_HERM_FIRE_ALLOWLIST="" CC_HERM_OWN="tests/something-else.bats" run bash "$LINT" "$FIX/fireleak/tests"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'advisory, not blocking' || false
  CC_HERM_FIRE_ALLOWLIST="" CC_HERM_OWN="tests/zz-fixture.bats" run bash "$LINT" "$FIX/fireleak/tests"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'AMBIENT' || false
}

@test "the two ratchets are INDEPENDENT — a \$HOME-grandfathered suite is still judged on the gate" {
  # Why two lists and not one: a shared list could only shrink when BOTH violations were fixed, so
  # fixing one would be unrewarded and the ratchet would ratchet half as often.
  mk_suite both 'REPO="$(pwd)"' 'run bash ./scripts/handoff-fire.sh --dry-run'
  CC_HERM_ALLOWLIST="zz-fixture.bats" CC_HERM_FIRE_ALLOWLIST="" run bash "$LINT" "$FIX/both"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'AMBIENT' || false
  [ "$(echo "$output" | grep -c 'LEAK')" -eq 0 ] || false     # rule 1 is satisfied; only rule 2 fired
  # …and the mirror image: grandfathered for rule 2, unlisted for rule 1 ⇒ LEAK only, no AMBIENT.
  CC_HERM_ALLOWLIST="" CC_HERM_FIRE_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/both"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'LEAK' || false
  [ "$(echo "$output" | grep -c 'AMBIENT')" -eq 0 ] || false
}

@test "the real tree is clean under ALL ratchets and the summary reports every count" {
  CC_HERM_SELFTEST_RULE=on run bash "$LINT"
  skip_if_unrunnable        # the other whole-tree case — same third state, same reason
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'grandfathered (\$HOME)' || false
  echo "$output" | grep -q 'grandfathered (capacity gate)' || false
  echo "$output" | grep -q 'grandfathered (orphan-close lever)' || false
  echo "$output" | grep -q 'grandfathered (scratch path)' || false
}

# ── RULE 4: the embedded-selftest ratchet — the population rules 1-3 are structurally blind to ────
# Their scan is `for f in "$dir"/*.bats`, so ~50 tools that RED-prove themselves via `<tool>
# selftest` and own no .bats file were never judged at all. Reported 2026-07-30 (backlog f7abcbdee98c
# spillover) after a selftest went RED in 2 of 4 CONCURRENT runs on a scratch path that was the same
# string both times — rule 1's failure with the seam moved from an inherited $HOME to a named path.

@test "RULE 4 RED: a selftest whose scratch dir is the same string on every run" {
  mk_tool s4red zz-tool 'selftest() {
  tmp=/tmp/zz-tool-selftest
  mkdir -p "$tmp"; echo ok > "$tmp/f"
}'
  CC_HERM_SELFTEST_RULE=on CC_HERM_SELFTEST_ROOT="$FIX/s4red" CC_HERM_SELFTEST_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$NEUTRAL"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'COLLIDES' || false
  echo "$output" | grep -q 'Do NOT add to the selftest allowlist' || false
}

@test "RULE 4 GREEN: mktemp clears it — the prescribed fix actually works" {
  mk_tool s4ok zz-tool 'selftest() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/zz-tool-selftest.XXXXXX")"
  mkdir -p "$tmp"; echo ok > "$tmp/f"
}'
  CC_HERM_SELFTEST_RULE=on CC_HERM_SELFTEST_ROOT="$FIX/s4ok" CC_HERM_SELFTEST_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$NEUTRAL"
  [ "$status" -eq 0 ] || false
  [ "$(echo "$output" | grep -c 'COLLIDES')" -eq 0 ] || false
}

@test "RULE 4 SCOPE CONTROL: a tool with NO embedded selftest is neither flagged nor counted" {
  # The positive control that makes the RED above mean something — and the COUNT is the half that
  # discriminates: with the scope predicate stubbed to match every file the verdict stays 0 (an
  # absent selftest body yields nothing for either probe to find), so only the denominator moves.
  mk_tool s4scope zz-ok 'selftest() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/zz-ok.XXXXXX")"
  echo ok > "$tmp/f"
}'
  { echo '#!/bin/bash'; echo 'main() {'; echo '  tmp=/tmp/zz-plain-state'; echo '  mkdir -p "$tmp"'; echo '}'; } \
    > "$FIX/s4scope/bin/zz-plain"
  CC_HERM_SELFTEST_RULE=on CC_HERM_SELFTEST_ROOT="$FIX/s4scope" CC_HERM_SELFTEST_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$NEUTRAL"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q '1 embedded selftest(s)' || false
}

@test "RULE 4: an extractor blind to its OWN anchor is a NON-VERDICT (exit 2), never a clean bill" {
  # The extractor control. The region extractor is textual: rename the convention and it matches
  # nothing, and a rule that inspected ZERO tools would otherwise print "clean" — an alarm carrying
  # the same zero bits as one that cannot fire. The lint ships an embedded selftest by
  # construction, so wherever its own file sits under the scanned root it MUST be detected; a file
  # at that path with no selftest is what a broken extractor looks like from the inside.
  #
  # NOT A COUNT, and that distinction was earned: the first version was `seen < 20`, calibrated on
  # the 45 selftests measured in this repo, and it made a NON-VERDICT of every smaller tree — the
  # fixture repos in tests/ship-land.bats included, whose scripts/ holds one file. Their suite
  # caught it. A tree must be judged by the ratchet it SHIPS, never condemned for being small.
  mk_tool s4anchor zz-tool 'selftest() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/zz.XXXXXX")"
  echo ok > "$tmp/f"
}'
  mkdir -p "$FIX/s4anchor/scripts"
  printf '#!/bin/bash\necho "a lint with no embedded selftest"\n' > "$FIX/s4anchor/scripts/$(basename "$LINT")"
  CC_HERM_SELFTEST_RULE=on CC_HERM_SELFTEST_ROOT="$FIX/s4anchor" CC_HERM_SELFTEST_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$NEUTRAL"
  [ "$status" -eq 2 ] || false
  echo "$output" | grep -q 'did not detect its own selftest' || false
  [ "$(echo "$output" | grep -c 'lint: clean — 1 embedded')" -eq 0 ] || false
}

@test "RULE 4: a SMALL tree with no anchor at all is CLEAN — never unlandable for being small" {
  # The paired case, and the regression cover for the calibration defect above. One compliant tool,
  # no copy of the lint anywhere under the root: `seen` is honestly 1 and the verdict is clean.
  mk_tool s4small zz-tool 'selftest() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/zz.XXXXXX")"
  echo ok > "$tmp/f"
}'
  CC_HERM_SELFTEST_RULE=on CC_HERM_SELFTEST_ROOT="$FIX/s4small" CC_HERM_SELFTEST_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$NEUTRAL"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q '1 embedded selftest(s)' || false
}

@test "RULE 4 kill switch: CC_HERM_SELFTEST_RULE=off disables it — with the RED as positive control" {
  mk_tool s4kill zz-tool 'selftest() {
  tmp=/tmp/zz-tool-selftest
  mkdir -p "$tmp"
}'
  CC_HERM_SELFTEST_RULE=on CC_HERM_SELFTEST_ROOT="$FIX/s4kill" CC_HERM_SELFTEST_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$NEUTRAL"
  [ "$status" -eq 1 ] || false                        # control: the rule DOES fire on this fixture
  CC_HERM_SELFTEST_RULE=off CC_HERM_SELFTEST_ROOT="$FIX/s4kill" CC_HERM_SELFTEST_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$NEUTRAL"
  [ "$status" -eq 0 ] || false
}

@test "RULE 4 is INDEPENDENT of rules 1-3 — a clean bats tree does not excuse a colliding selftest" {
  # Why a fourth pass and not a fourth check inside lint_dir(): the populations differ, so a land
  # whose suites are all hermetic must still be judged on the tools it ships.
  mk_tool s4indep zz-tool 'selftest() {
  tmp=/tmp/zz-tool-selftest
  mkdir -p "$tmp"
}'
  mk_suite herm 'export HOME="$BATS_TEST_TMPDIR/home"'
  CC_HERM_SELFTEST_RULE=on CC_HERM_SELFTEST_ROOT="$FIX/s4indep" CC_HERM_SELFTEST_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/herm"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'COLLIDES' || false
  [ "$(echo "$output" | grep -c 'LEAK')" -eq 0 ] || false      # rule 1 is satisfied; only rule 4 fired
}

# ── RULE 5 (the non-$HOME seam). EVERY case below is FIXTURE-based — a fixture seam root of tools
# plus a fixture scan dir of suites — and NONE asserts a property of the real checkout. That is
# deliberate and it is the standing lesson of backlog b59eb997d035: the one assertion in this file
# that lints the WHOLE TREE mid-suite passes standalone and fails in-suite, and it alone kept 14
# consecutive green stamps red with deploy-live fail-closed. Rule 5's real-tree guarantee (its
# embedded allowlist matches HEAD) is proved where it costs nothing — case (e) of the lint's own
# --selftest — not by widening the assertion that already causes that.
#
# mk_seam_tool <root> <name> <seam-line> — a fixture TOOL carrying one seam. Safe to spell the
# literal `${VAR:-/tmp/…}` here, unlike in the lint itself: rule 5's extractor scans bin/, scripts/
# and hooks/, never tests/, so this file can never be harvested as its own subject.
mk_seam_tool() {
  mkdir -p "$FIX/$1/bin"
  { echo '#!/bin/bash'; printf '%s\n' "$3"; } > "$FIX/$1/bin/$2"
}

@test "RULE 5 RED (5a): an ABSOLUTE /tmp default is not redirected by a fixtured \$HOME" {
  # a514d3b0's shape: tests/cc-relogin-status.bats fixtured $HOME from birth and still counted the
  # operator's live /tmp/cc-permission-pending rows. Rule 1 reported it clean throughout.
  mk_seam_tool r5a zz-seamtool 'DIR="${ZZ_SEAM_DIR:-/tmp/zz-seam-state}"
echo "$DIR"'
  mk_suite r5a_s 'export HOME="$BATS_TEST_TMPDIR/home"; T="$REPO/bin/zz-seamtool"' 'run bash "$T"'
  CC_HERM_SEAM_RULE=on CC_HERM_SEAM_ROOT="$FIX/r5a" CC_HERM_SEAM_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/r5a_s"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'SEAM ' || false
  echo "$output" | grep -q 'ZZ_SEAM_DIR (5a' || false
  echo "$output" | grep -q 'Do NOT add to' || false
}

@test "RULE 5 RED (5b): a BARE NAME the subject EXECUTES runs the operator's DEPLOYED tool" {
  mk_seam_tool r5b zz-seamtool 'echo target'
  mk_seam_tool r5b zz-exectool 'BIN="${ZZ_SEAM_BIN:-zz-seamtool}"
"$BIN" --probe'
  mk_suite r5b_s 'export HOME="$BATS_TEST_TMPDIR/home"; T="$REPO/bin/zz-exectool"' 'run bash "$T"'
  CC_HERM_SEAM_RULE=on CC_HERM_SEAM_ROOT="$FIX/r5b" CC_HERM_SEAM_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/r5b_s"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'ZZ_SEAM_BIN (5b' || false
}

@test "RULE 5 GREEN: assigning the seam in setup() clears it — the prescribed fix actually works" {
  mk_seam_tool r5ok zz-seamtool 'DIR="${ZZ_SEAM_DIR:-/tmp/zz-seam-state}"
echo "$DIR"'
  mk_suite r5ok_s 'export HOME="$BATS_TEST_TMPDIR/home"; export ZZ_SEAM_DIR="$BATS_TEST_TMPDIR/seam"; T="$REPO/bin/zz-seamtool"' 'run bash "$T"'
  CC_HERM_SEAM_RULE=on CC_HERM_SEAM_ROOT="$FIX/r5ok" CC_HERM_SEAM_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/r5ok_s"
  [ "$status" -eq 0 ] || false
  [ "$(echo "$output" | grep -c 'SEAM ')" -eq 0 ] || false
}

@test "RULE 5 SCOPE CONTROL: a suite naming only a SEAMLESS tool is never flagged" {
  # Without this the RED cases prove nothing about scoping — a rule that fires on every suite
  # satisfies every RED assertion above while carrying no information at all.
  mk_seam_tool r5sc zz-seamtool 'DIR="${ZZ_SEAM_DIR:-/tmp/zz-seam-state}"'
  mk_seam_tool r5sc zz-noseam 'echo no-seam'
  mk_suite r5sc_s 'export HOME="$BATS_TEST_TMPDIR/home"; T="$REPO/bin/zz-noseam"' 'run bash "$T"'
  CC_HERM_SEAM_RULE=on CC_HERM_SEAM_ROOT="$FIX/r5sc" CC_HERM_SEAM_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/r5sc_s"
  [ "$status" -eq 0 ] || false
}

@test "RULE 5 SCOPE: a tool named only in a COMMENT executes nothing, so it does not pull scope" {
  # The mirror of rules 2's and 4's prose-match regressions: there a comment must not satisfy a
  # POSITION test; here a comment must not trigger a SCOPE test.
  mk_seam_tool r5cm zz-seamtool 'DIR="${ZZ_SEAM_DIR:-/tmp/zz-seam-state}"'
  mkdir -p "$FIX/r5cm_s"
  { echo '#!/usr/bin/env bats'; echo 'setup() {'
    echo '  export HOME="$BATS_TEST_TMPDIR/home"'
    echo '  # the roster this suite asserts on is also read by $REPO/bin/zz-seamtool'
    echo '}'; echo '@test "x" { true; }'; } > "$FIX/r5cm_s/zz-fixture.bats"
  CC_HERM_SEAM_RULE=on CC_HERM_SEAM_ROOT="$FIX/r5cm" CC_HERM_SEAM_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/r5cm_s"
  [ "$status" -eq 0 ] || false
}

@test "RULE 5 kill switch: CC_HERM_SEAM_RULE=off disables it — with the RED as positive control" {
  mk_seam_tool r5ks zz-seamtool 'DIR="${ZZ_SEAM_DIR:-/tmp/zz-seam-state}"'
  mk_suite r5ks_s 'export HOME="$BATS_TEST_TMPDIR/home"; T="$REPO/bin/zz-seamtool"' 'run bash "$T"'
  CC_HERM_SEAM_RULE=on CC_HERM_SEAM_ROOT="$FIX/r5ks" CC_HERM_SEAM_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/r5ks_s"
  [ "$status" -eq 1 ] || false                       # the control: it DOES fire when armed
  CC_HERM_SEAM_RULE=off CC_HERM_SEAM_ROOT="$FIX/r5ks" CC_HERM_SEAM_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/r5ks_s"
  [ "$status" -eq 0 ] || false
}

@test "RULE 5 is INDEPENDENT of rules 1-4 — a \$HOME-hermetic suite is still judged on its seams" {
  # The whole point of the rule: rule 1 answers YES for this suite and it is still reading the
  # operator's machine. A shared allowlist could only shrink when BOTH rules were satisfied, which
  # is why rule 5 carries its own.
  mk_seam_tool r5ind zz-seamtool 'DIR="${ZZ_SEAM_DIR:-/tmp/zz-seam-state}"'
  mk_suite r5ind_s 'export HOME="$BATS_TEST_TMPDIR/home"; T="$REPO/bin/zz-seamtool"' 'run bash "$T"'
  CC_HERM_SEAM_RULE=on CC_HERM_SEAM_ROOT="$FIX/r5ind" CC_HERM_SEAM_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/r5ind_s"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'SEAM ' || false
  [ "$(echo "$output" | grep -c 'LEAK')" -eq 0 ] || false      # rule 1 is satisfied; only rule 5 fired
}

# ── RULE 6 (the INHERITED-VALUE seam). Rule 5 asks where a subject's state RESOLVES, so it can only
# see a seam whose DEFAULT betrays it; a default is irrelevant when a VALUE is already in the
# environment. 0588d255: two suites went 5-RED on a PRISTINE trunk tree because /Users/chrisren/.claude/bin/cc-bats was run from a
# pane the feature under test had launched, and `--env CC_PANE_CMD_INTERACTIVE=1` is inherited by
# every descendant of one. This lint reported both CLEAN throughout — rule 5 saw `:-0` and moved on.
#
# EVERY case below is FIXTURE-based — a fixture tool root plus a fixture scan dir — and NONE asserts
# a property of the real checkout, for the reason rule 5's block records (backlog b59eb997d035: the
# one assertion here that lints the WHOLE TREE mid-suite passes standalone and fails in-suite, and
# alone kept 14 consecutive green stamps red). Rule 6's real-tree guarantee is proved where it costs
# nothing — case (e) of the lint's own --selftest.
#
# mk_env_tool <root> <name> <body> — a fixture TOOL. Safe to spell both literal shapes here, unlike
# in the lint itself: rule 6's extractor scans bin/, scripts/ and hooks/, never tests/.
mk_env_tool() {
  mkdir -p "$FIX/$1/bin"
  { echo '#!/bin/bash'; printf '%s\n' "$3"; } > "$FIX/$1/bin/$2"
}
# the standard pair: an INJECTOR that never reads, and a READER of what it injects.
mk_env_pair() {
  mk_env_tool "$1" zz-launcher 'exec term --env "ZZ_ENV_MODE=1" --env "ZZ_ENV_MODE_DIR=/x" -- "$SHELL"'
  mk_env_tool "$1" zz-panetool 'MODE="${ZZ_ENV_MODE:-0}"
DIR="${ZZ_ENV_MODE_DIR:-/tmp/zz-env}"
echo "$MODE $DIR"'
}
r6run() {  # r6run <tool-root> <scan-dir>
  CC_HERM_ENV_RULE=on CC_HERM_ENV_ROOT="$FIX/$1" CC_HERM_ENV_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/$2"
}

@test "RULE 6 RED: a suite INHERITS a variable its subject reads and this repo puts on every pane" {
  mk_env_pair r6a
  mk_suite r6a_s 'export HOME="$BATS_TEST_TMPDIR/home"; T="$REPO/bin/zz-panetool"' 'run bash "$T"'
  r6run r6a r6a_s
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'INHERIT ' || false
  echo "$output" | grep -q 'ZZ_ENV_MODE' || false
}

@test "RULE 6 GREEN: an 'unset' clears it — the remedy rule 5's assignment-only predicate REJECTS" {
  # This is what makes rule 6 a RULE and not a shape of rule 5. 0588d255 fixed the real incident
  # with `unset`, and rule 5's is_seam_assigned() requires `VAR=` — so a bolted-on shape would
  # report the very fix that generated this rule as still violating, forever.
  mk_env_pair r6b
  mk_suite r6b_s 'export HOME="$BATS_TEST_TMPDIR/home"; unset ZZ_ENV_MODE ZZ_ENV_MODE_DIR; T="$REPO/bin/zz-panetool"' 'run bash "$T"'
  r6run r6b r6b_s
  [ "$status" -eq 0 ] || false
  [ "$(echo "$output" | grep -c 'INHERIT ')" -eq 0 ] || false
}

@test "RULE 6 GREEN: an ASSIGNMENT also clears it — any deterministic position counts" {
  # Rule 3's asymmetry: what is forbidden is INHERITING a value, not choosing the "wrong" one.
  mk_env_pair r6c
  mk_suite r6c_s 'export HOME="$BATS_TEST_TMPDIR/home"; export ZZ_ENV_MODE=0 ZZ_ENV_MODE_DIR="$BATS_TEST_TMPDIR/d"; T="$REPO/bin/zz-panetool"' 'run bash "$T"'
  r6run r6c r6c_s
  [ "$status" -eq 0 ] || false
}

@test "RULE 6 SCOPE CONTROL: a tool that INJECTS a variable it never READS is out of scope" {
  # The most load-bearing control rule 6 has, and the reason its table is an INTERSECTION. Drop this
  # half and scripts/handoff-fire.sh joins the table — it injects a runner variable it never reads —
  # and 49 suites that name it get grandfathered for a variable their subject does not read.
  mk_env_pair r6d
  mk_suite r6d_s 'export HOME="$BATS_TEST_TMPDIR/home"; T="$REPO/bin/zz-launcher"' 'run bash "$T"'
  r6run r6d r6d_s
  [ "$status" -eq 0 ] || false
}

@test "RULE 6 SCOPE CONTROL: a plain-valued seam that NOTHING injects cannot be inherited" {
  # The other half of the intersection. Without it the rule is the filing's naive version — "every
  # CC_* var a tool reads" — which measured 1047 seam assignments and most of 324 suites in scope.
  mk_env_pair r6e
  mk_env_tool r6e zz-plainseam 'LVL="${ZZ_ENV_UNPROP:-0}"
echo "$LVL"'
  mk_suite r6e_s 'export HOME="$BATS_TEST_TMPDIR/home"; T="$REPO/bin/zz-plainseam"' 'run bash "$T"'
  r6run r6e r6e_s
  [ "$status" -eq 0 ] || false
}

@test "RULE 6: pinning a variable that merely PREFIXES the unpinned one does not count" {
  # The real tree has this collision: CC_PANE_CMD strictly prefixes CC_PANE_CMD_DIR and
  # CC_PANE_CMD_INTERACTIVE, so without a boundary after the name one pin would excuse all three.
  mk_env_pair r6f
  mk_suite r6f_s 'export HOME="$BATS_TEST_TMPDIR/home"; export ZZ_ENV_MODE_DIR="$BATS_TEST_TMPDIR/d"; T="$REPO/bin/zz-panetool"' 'run bash "$T"'
  r6run r6f r6f_s
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'ZZ_ENV_MODE' || false
}

@test "RULE 6: a statement-terminated 'unset FOO;' IS a position — the fail direction is a false RED" {
  # Found by MUTATION, not review: rule 3's trailing class is `([[:space:]]|$)`, which misses the
  # LAST name in a `;`-terminated unset. Too narrow on a PIN test convicts a compliant suite.
  mk_env_pair r6g
  mkdir -p "$FIX/r6g_s"
  { echo '#!/usr/bin/env bats'; echo 'setup() {'
    echo '  export HOME="$BATS_TEST_TMPDIR/home"'
    echo '  unset ZZ_ENV_MODE ZZ_ENV_MODE_DIR;'
    echo '  T="$REPO/bin/zz-panetool"'
    echo '}'; echo '@test "x" { run bash "$T"; }'; } > "$FIX/r6g_s/zz-fixture.bats"
  r6run r6g r6g_s
  [ "$status" -eq 0 ] || false
}

@test "RULE 6 kill switch: CC_HERM_ENV_RULE=off disables it — with the RED as positive control" {
  mk_env_pair r6h
  mk_suite r6h_s 'export HOME="$BATS_TEST_TMPDIR/home"; T="$REPO/bin/zz-panetool"' 'run bash "$T"'
  r6run r6h r6h_s
  [ "$status" -eq 1 ] || false                       # the control: it DOES fire when armed
  CC_HERM_ENV_RULE=off CC_HERM_ENV_ROOT="$FIX/r6h" CC_HERM_ENV_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/r6h_s"
  [ "$status" -eq 0 ] || false
}

@test "RULE 6 is INDEPENDENT of rules 1-5 — a \$HOME-hermetic suite still inherits injected values" {
  # The whole point: rule 1 answers YES for this suite, rule 5 sees a `:-0` default and moves on,
  # and it is still reading whatever pane it was launched from.
  #
  # The reader here holds ONLY the PLAIN-VALUED seam — no /tmp default, no bare tool name — so rule 5
  # is blind to it BY CONSTRUCTION and the `SEAM` assertion below means what it says. The shared
  # mk_env_pair reader would not do: its second variable defaults to /tmp/zz-env, which is a genuine
  # shape-5a seam, so rule 5 fires on it and the independence claim is answered by the wrong rule.
  mk_env_tool r6i zz-launcher 'exec term --env "ZZ_ENV_MODE=1" -- "$SHELL"'
  mk_env_tool r6i zz-panetool 'MODE="${ZZ_ENV_MODE:-0}"
echo "$MODE"'
  mk_suite r6i_s 'export HOME="$BATS_TEST_TMPDIR/home"; T="$REPO/bin/zz-panetool"' 'run bash "$T"'
  CC_HERM_SEAM_RULE=on CC_HERM_SEAM_ROOT="$FIX/r6i" CC_HERM_SEAM_ALLOWLIST="" \
    CC_HERM_ENV_RULE=on CC_HERM_ENV_ROOT="$FIX/r6i" CC_HERM_ENV_ALLOWLIST="" \
    CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/r6i_s"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'INHERIT ' || false
  [ "$(echo "$output" | grep -c 'LEAK')" -eq 0 ] || false     # rule 1 is satisfied
  [ "$(echo "$output" | grep -c 'SEAM ')" -eq 0 ] || false    # rule 5 is blind to a plain default
}

@test "RULE 6: a SMALL tree that launches no panes is CLEAN — never unlandable for being small" {
  # Rule 4's standing property, applied to rule 6's extractor. Nothing here injects anything, so the
  # table is legitimately empty and "clean" is the honest answer — and the ANCHOR (not a count) is
  # what tells that apart from an extractor that has stopped working. A floor would have condemned
  # exactly the fixture repos ship-land lands, whose scripts/ holds a single file.
  mkdir -p "$FIX/r6small/bin" "$FIX/r6small/scripts" "$FIX/r6small/hooks"
  mk_suite r6small_s 'export HOME="$BATS_TEST_TMPDIR/home"'
  r6run r6small r6small_s
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'grandfathered (inherited value)' || false
}

# ── RULE 7 (the capacity-ADMIT gate). Rule 2's twin at the OTHER gate. Rule 2 knows exactly one
# lever, CC_FIRE_CAPACITY_GATE, because scripts/handoff-fire.sh's capacity_gate() is the only gate it
# was written against. scripts/lib/capacity-admit.sh is a SECOND gate with its own CC_ADMIT_*
# namespace and its own callers, and it refuses with exit 9 on live load, live memory headroom and —
# since 450a47c50 — a live `ps` census of session trees. Backlog 5ef0dcb22aec:
# tests/kitty-recovery-launch.bats (which drives scripts/boot-resume-launch.sh, a caller) went
# red-by-LOAD three times in a 228-test sweep and green in isolation, while this lint reported it
# clean throughout — it names no handoff-fire, so rule 2 never had it in scope.
#
# Every case below is FIXTURE-based, for the reason rules 5 and 6's blocks record (backlog
# b59eb997d035). Rule 7's real-tree guarantee is proved where it costs nothing — case (e) of the
# lint's own --selftest, which now judges EMBEDDED_ADMIT_ALLOWLIST alongside the other four.

@test "RULE 7 RED: a suite that drives a capacity-admit caller without closing the gate in setup()" {
  mk_suite admitleak 'export HOME="$BATS_TEST_TMPDIR/home"' 'run bash ./scripts/boot-resume-launch.sh --dry-run'
  CC_HERM_ADMIT_ALLOWLIST="" run bash "$LINT" "$FIX/admitleak"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'AMBIENT' || false
  echo "$output" | grep -q 'Do NOT add to the admit allowlist' || false
}

@test "RULE 7 SCOPE CONTROL: the same suite MINUS the caller reference is GREEN" {
  # The positive control that makes the RED above mean something — rule 2's argument verbatim. These
  # two fixtures differ in exactly one token; if this one also went RED the rule would be flagging
  # every suite in the tree and the RED would be evidence of nothing.
  mk_suite noadmit 'export HOME="$BATS_TEST_TMPDIR/home"' 'run bash ./scripts/some-other-tool.sh --dry-run'
  CC_HERM_ADMIT_ALLOWLIST="" run bash "$LINT" "$FIX/noadmit"
  [ "$status" -eq 0 ] || false
  [ "$(echo "$output" | grep -c 'AMBIENT')" -eq 0 ] || false
}

@test "RULE 7 SCOPE: a PROSE mention is not a reference — and a real path still is (two-sided)" {
  # rule 2's third-position case over the shared strip_prose, which THIS rule generalised from a
  # hardcoded `handoff-fire` to a parameter. Both halves in one test, deliberately: split apart, the
  # OUT half could pass because the predicate matches nothing at all.
  mk_suite admitprose 'export HOME="$BATS_TEST_TMPDIR/home"' \
    "run classify 'patch scripts/boot-resume-launch.sh so the resume inherits the goal'"
  CC_HERM_ADMIT_ALLOWLIST="" run bash "$LINT" "$FIX/admitprose"
  [ "$status" -eq 0 ] || { echo "prose mention was read as a reference:"; echo "$output"; false; }
  [ "$(echo "$output" | grep -c 'AMBIENT')" -eq 0 ] || false

  mk_suite admitexec 'export HOME="$BATS_TEST_TMPDIR/home"' \
    'run bash ./scripts/boot-resume-launch.sh --dry-run'
  CC_HERM_ADMIT_ALLOWLIST="" run bash "$LINT" "$FIX/admitexec"
  [ "$status" -eq 1 ] || { echo "prose-stripping swallowed a REAL reference:"; echo "$output"; false; }
  echo "$output" | grep -q 'AMBIENT' || false
}

@test "RULE 7 GREEN: FORM 1 (CC_ADMIT_GATE=off) clears it — the prescribed fix actually works" {
  mk_suite admitpin 'export HOME="$BATS_TEST_TMPDIR/home"; export CC_ADMIT_GATE=off' \
    'run bash ./scripts/boot-resume-launch.sh --dry-run'
  CC_HERM_ADMIT_ALLOWLIST="" run bash "$LINT" "$FIX/admitpin"
  [ "$status" -eq 0 ] || false
}

@test "RULE 7 GREEN: FORM 2 needs ALL THREE terms — a suite whose SUBJECT is the gate cannot use form 1" {
  mk_suite admitform2 'export HOME="$BATS_TEST_TMPDIR/home"
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0
  export CC_ADMIT_HEADROOM_OVERRIDE=64
  export CC_ADMIT_RESERVE_TERM=off' \
    'run bash ./scripts/lib/capacity-admit.sh'
  CC_HERM_ADMIT_ALLOWLIST="" run bash "$LINT" "$FIX/admitform2"
  [ "$status" -eq 0 ] || { echo "form 2 is unreachable:"; echo "$output"; false; }
}

@test "RULE 7 RED: the TWO-VARIABLE form 2 is NOT closed — the reserve term is a third ambient input" {
  # 🚨 The one case rule 2 has no analogue for, and the whole reason rule 7 is not a name-swap of
  # is_fire_pinned. Backlog 5ef0dcb22aec prescribed exactly this shape (CC_ADMIT_GATE plus rule 2's
  # two instrument overrides) and it was TRUE WHEN FILED. 450a47c50 landed two days later and added
  # the operator RESERVE, which runs over an otherwise-ADMITTING box and refuses on a live `ps`
  # census plus the operator's presence — neither of which either override touches, and neither of
  # which a fixtured $HOME absents (_cc_admit_load_presence resolves spawn-presence.sh relative to
  # capacity-admit.sh's OWN directory first, so it loads the real library).
  #
  # Measured two-sided on the gate's own suite, which is in exactly this state today:
  # `bats tests/capacity-admit.bats` is 20/20 green ambient and 17/20 under CC_SP_TREES_OVERRIDE=999
  # (tests 13, 14 and P3 flip on the census alone). Had form 2 been ported verbatim from rule 2, this
  # lint would have certified the one suite whose subject IS this gate as PINNED while it read the
  # live box — a false negative minted by the rule that exists to prevent it.
  mk_suite admitform2short 'export HOME="$BATS_TEST_TMPDIR/home"
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0
  export CC_ADMIT_HEADROOM_OVERRIDE=64' \
    'run bash ./scripts/lib/capacity-admit.sh'
  CC_HERM_ADMIT_ALLOWLIST="" run bash "$LINT" "$FIX/admitform2short"
  [ "$status" -eq 1 ] || { echo "the two-variable form counted as PINNED:"; echo "$output"; false; }
  echo "$output" | grep -q 'AMBIENT' || false
}

@test "RULE 7 GREEN: CC_SP_TREES_OVERRIDE is the OTHER reserve closure — it pins the live census" {
  # The second spelling, and it must work: tests/spawn-presence.bats is the presence library's own
  # suite and cannot turn the reserve term off without deleting what it tests. It pins the census
  # itself instead, which reaches the same property by the other route.
  mk_suite admitform2b 'export HOME="$BATS_TEST_TMPDIR/home"
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0
  export CC_ADMIT_HEADROOM_OVERRIDE=64
  export CC_SP_TREES_OVERRIDE=5' \
    'run bash ./scripts/lib/capacity-admit.sh'
  CC_HERM_ADMIT_ALLOWLIST="" run bash "$LINT" "$FIX/admitform2b"
  [ "$status" -eq 0 ] || { echo "the census pin was not accepted as a reserve closure:"; echo "$output"; false; }
}

@test "RULE 7: a per-TEST close does not count (every OTHER test still reads the live box)" {
  mkdir -p "$FIX/admitpertest"
  { echo '#!/usr/bin/env bats'; echo 'setup() {'
    echo '  export HOME="$BATS_TEST_TMPDIR/home"'
    echo '  S="./scripts/boot-resume-launch.sh"'
    echo '}'
    echo '@test "a" { CC_ADMIT_GATE=off run bash "$S"; }'
    echo '@test "b" { run bash "$S"; }'; } > "$FIX/admitpertest/zz-fixture.bats"
  CC_HERM_ADMIT_ALLOWLIST="" run bash "$LINT" "$FIX/admitpertest"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'AMBIENT' || false
}

@test "RULE 7 RED: a suite that closes the gate but is STILL grandfathered (the ratchet only shrinks)" {
  mk_suite admitpin 'export HOME="$BATS_TEST_TMPDIR/home"; export CC_ADMIT_GATE=off' \
    'run bash ./scripts/boot-resume-launch.sh --dry-run'
  CC_HERM_ADMIT_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/admitpin"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'RATCHET-ADM' || false
}

@test "RULE 7 GREEN: an unclosed suite that IS grandfathered passes (today's list blocks nobody)" {
  mk_suite admitleak 'export HOME="$BATS_TEST_TMPDIR/home"' 'run bash ./scripts/boot-resume-launch.sh --dry-run'
  CC_HERM_ADMIT_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/admitleak"
  [ "$status" -eq 0 ] || false
}

@test "RULE 7 kill switch: CC_HERM_ADMIT_RULE=off disables it — with the RED as its positive control" {
  mk_suite admitleak 'export HOME="$BATS_TEST_TMPDIR/home"' 'run bash ./scripts/boot-resume-launch.sh --dry-run'
  CC_HERM_ADMIT_ALLOWLIST="" run bash "$LINT" "$FIX/admitleak"
  [ "$status" -eq 1 ] || false                          # control: the rule DOES fire on this fixture
  CC_HERM_ADMIT_ALLOWLIST="" CC_HERM_ADMIT_RULE=off run bash "$LINT" "$FIX/admitleak"
  [ "$status" -eq 0 ] || false
}

@test "RULE 7 own-scope: an AMBIENT violation outside the diff is advisory, inside it blocks" {
  mk_suite_in_tests admitleak 'export HOME="$BATS_TEST_TMPDIR/home"' 'run bash ./scripts/boot-resume-launch.sh --dry-run'
  CC_HERM_ADMIT_ALLOWLIST="" CC_HERM_OWN="tests/something-else.bats" run bash "$LINT" "$FIX/admitleak/tests"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'advisory, not blocking' || false
  CC_HERM_ADMIT_ALLOWLIST="" CC_HERM_OWN="tests/zz-fixture.bats" run bash "$LINT" "$FIX/admitleak/tests"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'AMBIENT' || false
}

@test "RULE 7 is INDEPENDENT of rule 2 — the two gates' populations do not overlap" {
  # scripts/handoff-fire.sh SOURCES capacity-admit.sh but never calls cc_capacity_admit: it reuses
  # only the shared cc_hw_* terms and evaluates them under CC_FIRE_*. So a handoff-fire suite must be
  # in rule 2's scope and NOT rule 7's, and a boot-resume-launch suite the other way round. Without
  # this, rule 7 could be silently duplicating rule 2's population under a second remedy.
  mk_suite r7indep_fire 'export HOME="$BATS_TEST_TMPDIR/home"; export CC_ADMIT_GATE=off' \
    'run bash ./scripts/handoff-fire.sh --dry-run'
  CC_HERM_ADMIT_ALLOWLIST="" CC_HERM_FIRE_ALLOWLIST="" run bash "$LINT" "$FIX/r7indep_fire"
  [ "$status" -eq 1 ] || false                          # rule 2 still convicts it
  echo "$output" | grep -q 'CC_FIRE_CAPACITY_GATE' || false

  mk_suite r7indep_admit 'export HOME="$BATS_TEST_TMPDIR/home"; export CC_FIRE_CAPACITY_GATE=off' \
    'run bash ./scripts/boot-resume-launch.sh --dry-run'
  CC_HERM_ADMIT_ALLOWLIST="" CC_HERM_FIRE_ALLOWLIST="" run bash "$LINT" "$FIX/r7indep_admit"
  [ "$status" -eq 1 ] || false                          # rule 7 convicts it, and rule 2 does not
  echo "$output" | grep -q 'capacity-admit' || false
}
