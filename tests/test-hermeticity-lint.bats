#!/usr/bin/env bats
# test-hermeticity-lint — the RATCHET that stops NEW bats suites from running against AMBIENT STATE.
# Two rules, one mechanism: rule 1 is the operator's live ~/ ($HOME fixtured in setup()), rule 2 is
# the machine's live LOAD (CC_FIRE_CAPACITY_GATE=off pinned in setup(), for any suite that drives
# handoff-fire). Two properties matter for each and both are proved here: it discriminates (RED on a
# new violation, RED on an entry that stayed grandfathered after being fixed), and it is GREEN on the
# tree as it stands — a lint that ships standing-RED is the rot this repo is killing, and the nightly
# auto-runs every scripts/*lint*.sh, so a false RED here poisons the whole nightly signal.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/test-hermeticity-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"    # dogfood: this suite obeys its own rule 1
  export CC_FIRE_CAPACITY_GATE=off                         # dogfood rule 2 — this file names handoff-fire
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX"
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
  run bash "$LINT"
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

@test "the real tree is clean under BOTH ratchets and the summary reports both counts" {
  run bash "$LINT"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'grandfathered (\$HOME)' || false
  echo "$output" | grep -q 'grandfathered (capacity gate)' || false
}
