#!/usr/bin/env bats
# moving-ref-control-lint — the RATCHET that stops a pre-fix CONTROL being replayed from a git ref
# that advances past the fix it is supposed to predate.
#
# THE DIVISION OF LABOUR, and it is deliberate. `--selftest` owns the MECHANISM: fourteen synthetic
# fixtures, every discrimination in both directions, no history required. This suite owns what a
# synthetic fixture structurally cannot give — a verdict on the REAL corpus and on the REAL pre-fix
# artifacts, replayed from git at a pinned sha. Asking either to do the other's job yields a vacuous
# pass (memory: the union-arm split in scripts/unattended-path-lint.sh, same argument).
#
# THE TWO OUTCOMES THIS CLASS PRODUCES, both measured 2026-08-13 in this repo:
#   · LOUD  — tests/compressor-sentinel.bats cases 72/75/76 were RED ON TRUNK, and had been since
#             6dd3ea468 landed the fix its control replayed from origin/main.
#   · SILENT — tests/ignition-gate-census.bats was 9/9 GREEN replaying the POST-fix gate, because
#             `pregate` sets no CC_IGNITION_EXE_FILE, so the fixed gate's name table named none of
#             the fixture's synthetic pids and answered node_n=0 — the pre-fix defect's own number.
# The silent one is worse. A red control gets fixed; a vacuous one gets trusted.
#
# SELF-REFERENCE HAZARD, and why nothing below spells the phrase out. This suite's corpus scan reads
# tests/*.bats, which includes THIS FILE. A literal `show <moving-ref>:<path>` on an executed line
# here would make the suite violate the rule it is testing, and the only ways out are a
# self-exemption in the ratchet (how a ratchet rots into an exemption list) or a lint blind to its
# own corpus. So the violating shape is ASSEMBLED from parts, exactly as tests/test-afunix-path-lint
# .bats assembles its `.bind(`. Verified both directions — inline the literal and case 5 goes red.
# (memory: guard-refusal-fires-on-its-own-harness — scope to the dangerous EFFECT, not the file.)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/moving-ref-control-lint.sh"
  [ -x "$LINT" ] || false
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"    # dogfood: obey the sibling suites' rule
  export CC_FIRE_CAPACITY_GATE=off
  D="$BATS_TEST_TMPDIR"
  # The phrase, assembled. `SHOW` and `MOVING` are never adjacent as literals in this file.
  SHOW="sh""ow"; MOVING="origin/ma""in"
}

@test "--selftest passes: the mechanism discriminates in both directions" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || false
  # A floor on the case count, so a gutted --selftest cannot pass this by asserting nothing.
  n="$(printf '%s' "$output" | sed -n 's|.*--selftest: \([0-9]*\)/[0-9]*.*|\1|p')"
  [ -n "$n" ] || false
  [ "$n" -ge 20 ] || false
}

@test "the REAL tree is clean — a lint that ships standing-red is rot" {
  run bash "$LINT" "$REPO/tests"
  [ "$status" -eq 0 ] || false
  printf '%s' "$output" | grep -q 'clean —' || false
}

@test "POSITIVE CONTROL on the REAL artifacts: exactly 2 of the 3 corpus sites are flagged" {
  # An empty result from a matcher is not evidence of absence until the matcher has been shown able
  # to return a hit — and a synthetic fixture only shows it can hit a fixture. These are the three
  # real files, replayed from a PINNED sha (a385a2898 is the last commit before this repair):
  #   compressor-sentinel.bats   — a moving-ref control  ⇒ MUST flag
  #   ignition-gate-census.bats  — a moving-ref control  ⇒ MUST flag
  #   cc-dispatch-projects.bats  — the same phrase inside an asserted STRING on a fully executed
  #                                line ⇒ MUST NOT flag. This is the too-wide control: three of
  #                                three is exactly as wrong as zero of three.
  [ -n "$(command -v git)" ] || skip "git unavailable"
  local pre="$D/pre"; mkdir -p "$pre"
  local f
  for f in compressor-sentinel ignition-gate-census cc-dispatch-projects; do
    git -C "$REPO" show a385a2898:tests/"$f".bats > "$pre/$f.bats" 2>/dev/null \
      || skip "pre-repair commit a385a2898 unavailable (shallow clone?)"
  done
  # The replayed corpus must actually BE pre-repair, or this case passes for the wrong reason: the
  # repaired files carry a literal sha, the pre-repair ones carry the moving ref.
  grep -q "$SHOW $MOVING:scripts/compressor-sentinel.sh" "$pre/compressor-sentinel.bats" || false

  run bash "$LINT" "$pre"
  [ "$status" -eq 1 ] || false
  printf '%s' "$output" | grep -q 'MOVING-REF compressor-sentinel.bats' || false
  printf '%s' "$output" | grep -q 'MOVING-REF ignition-gate-census.bats' || false
  ! printf '%s' "$output" | grep -q 'cc-dispatch-projects' || false
  printf '%s' "$output" | grep -q '⛔ 2 suite(s)' || false
}

@test "BOTH HALVES are present at each repaired site — the pin AND the marker" {
  # The lint enforces the PIN. Nothing enforces the MARKER, and the pin alone re-goes-vacuous the
  # moment someone re-points the sha at a commit that already carries the fix — which is why the row
  # that ordered this work demanded both. Stated as a KNOWN LIMIT rather than hidden: this is a
  # per-site assertion, not a class rule; a third such control would need its own line here.
  local f
  for f in "$REPO/tests/compressor-sentinel.bats" "$REPO/tests/ignition-gate-census.bats"; do
    # a LITERAL sha, not a ref and not an expansion
    grep -qE "$SHOW +[0-9a-f]{7,40}:" "$f" || { echo "no literal-sha pin in $f"; false; }
    # …and a NEGATED grep for an identifier the fix introduced, so a re-pointed pin fails LOUDLY
    grep -qE '^[[:space:]]*! *grep -q .(exe_table|exe_rows).' "$f" || { echo "no pre-fix MARKER assertion in $f"; false; }
  done
}

@test "the marker really discriminates: the identifier is absent at the pin and present at HEAD" {
  # The measurement the marker rests on, re-run rather than recalled — a marker chosen from the
  # subject's VOCABULARY rather than its measured diff is the trap this repo has now hit twice. The
  # obvious spelling here (`pid=,etime=,comm=,args=`) greps 1 on BOTH sides, because the post-fix
  # file names it in the comment explaining the fix.
  [ -n "$(command -v git)" ] || skip "git unavailable"
  git -C "$REPO" show 808c09609:scripts/compressor-sentinel.sh > "$D/pre-cs" 2>/dev/null \
    || skip "pre-fix commit 808c09609 unavailable (shallow clone?)"
  git -C "$REPO" show 808c09609:bin/cc-ignition-gate > "$D/pre-ig" 2>/dev/null || false
  ! grep -q 'exe_table' "$D/pre-cs" || { echo "exe_table is present at the pin — the marker cannot discriminate"; false; }
  ! grep -q 'exe_rows'  "$D/pre-ig" || { echo "exe_rows is present at the pin — the marker cannot discriminate"; false; }
  grep -q 'exe_table' "$REPO/scripts/compressor-sentinel.sh" || false
  grep -q 'exe_rows'  "$REPO/bin/cc-ignition-gate" || false
  # and the vocabulary-derived marker that would NOT have worked, pinned so nobody re-derives it
  grep -q 'pid=,etime=,comm=,args=' "$D/pre-ig" || false
  grep -q 'pid=,etime=,comm=,args=' "$REPO/bin/cc-ignition-gate" || false
}

@test "SELF-HARNESS: this suite is in the scanned corpus and is NOT flagged" {
  # The scan above already covers tests/, so this asserts the specific thing that would break:
  # the file is present in the population, and clean. A lint exempting its own test file would be
  # a lint that cannot see its own corpus.
  [ -f "$REPO/tests/$(basename "$BATS_TEST_FILENAME")" ] || false
  run bash "$LINT" "$REPO/tests"
  [ "$status" -eq 0 ] || false
  ! printf '%s' "$output" | grep -q "$(basename "$BATS_TEST_FILENAME")" || false
}

@test "the land gate calls it, own-scoped — enforcement at the chokepoint, not in this suite" {
  # Enforced only here it is post-hoc DETECTION: gate-select maps this suite from exactly one edge
  # (the lint), so WRITING a new control never selects it. The gate arm is the enforcing surface.
  # (memory: enforcement-must-live-at-the-chokepoint, conclusion-must-reach-the-enforcing-store)
  grep -q 'MOVINGREF_LINT=' "$REPO/scripts/ship-land.sh" || false
  grep -q 'own_run MOVINGREF CC_MOVINGREF_OWN' "$REPO/scripts/ship-land.sh" || false
  # own-scope is what dissolved this work's two-day deferral ("it would block every concurrent
  # lander"); a gate arm that dropped it would re-create exactly that fleet-wide stop.
  grep -q 'SHIP_LAND_MOVINGREF_OWN_SCOPE' "$REPO/scripts/ship-land.sh" || false
  # and the NON-VERDICT arm: exit 2 must be GATE_KILLED (retryable), never gate_red (author-fixable)
  grep -q 'moving-ref-control-lint could not RUN (exit 2)' "$REPO/scripts/ship-land.sh" || false
}
