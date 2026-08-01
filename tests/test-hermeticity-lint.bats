#!/usr/bin/env bats
# test-hermeticity-lint — the RATCHET that stops NEW test harnesses from running against AMBIENT
# STATE. Four rules, one mechanism: rule 1 is the operator's live ~/ ($HOME fixtured in setup()),
# rule 2 the machine's live LOAD (CC_FIRE_CAPACITY_GATE=off, for a suite that drives handoff-fire),
# rule 3 an operator-armed lever (LCW_ORPHAN_CLOSE, for a suite driving the orphan-close leg), and
# rule 4 a SIBLING RUN OF ITSELF — a tool's EMBEDDED selftest whose scratch path is the same string
# every time, so two concurrent runs collide. Rules 1-3 judge tests/*.bats; rule 4 judges the ~50
# tools in bin/, scripts/ and hooks/ that ship a selftest instead of a suite and were outside the
# ratchet entirely until it landed. Two properties matter for each and both are proved here: it
# discriminates (RED on a new violation, RED on an entry that stayed grandfathered after being
# fixed), and it is GREEN on the tree as it stands — a lint that ships standing-RED is the rot this
# repo is killing, and the nightly auto-runs every scripts/*lint*.sh, so a false RED here poisons
# the whole nightly signal.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/test-hermeticity-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"    # dogfood: this suite obeys its own rule 1
  export CC_FIRE_CAPACITY_GATE=off                         # dogfood rule 2 — this file names handoff-fire
  # Rule 4 OFF by default here, and switched back ON by name in the cases that mean to test it.
  # Every fixture-targeted case below passes a temp dir as the scan dir, but rule 4's population is
  # the REPO's tool dirs — it is driven off $ROOT, not off that argument, precisely so ship-land's
  # `lint tests` still gets its selftests judged. Left ambient, a rule-4 verdict about the checkout
  # would silently become the answer to a rule-1 or rule-2 assertion about a two-file fixture.
  export CC_HERM_SELFTEST_RULE=off
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

@test "the real tree is CLEAN (exit 0) — the embedded allowlist matches HEAD, nightly stays green" {
  CC_HERM_SELFTEST_RULE=on run bash "$LINT"          # ALL FOUR rules judge the tree here
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'test-hermeticity-lint: clean'
}

@test "--selftest is GREEN and every discriminating case is exercised" {
  run bash "$LINT" --selftest
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
  mk_suite leak 'REPO=x'
  CC_HERM_OWN="tests/zz-fixture.bats" CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/leak"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'LEAK' || false
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
  mk_suite herm 'export HOME="$BATS_TEST_TMPDIR/home"'
  CC_HERM_OWN="tests/other.bats" CC_HERM_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/herm"
  [ "$status" -eq 0 ] || false
  CC_HERM_OWN="tests/zz-fixture.bats" CC_HERM_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/herm"
  [ "$status" -eq 1 ] || false
}

@test "own-scope: ship-land passes its OWN diff and the kill switch restores strictness" {
  grep -q 'CC_HERM_OWN=' "$REPO/scripts/ship-land.sh" || false
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
  mk_suite fireleak 'export HOME="$BATS_TEST_TMPDIR/home"' 'run bash ./scripts/handoff-fire.sh --dry-run'
  CC_HERM_FIRE_ALLOWLIST="" CC_HERM_OWN="tests/something-else.bats" run bash "$LINT" "$FIX/fireleak"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'advisory, not blocking' || false
  CC_HERM_FIRE_ALLOWLIST="" CC_HERM_OWN="tests/zz-fixture.bats" run bash "$LINT" "$FIX/fireleak"
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
