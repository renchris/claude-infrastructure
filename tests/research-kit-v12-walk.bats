#!/usr/bin/env bats
# research-kit-v12-walk — wave E3c of docs/plans/RESEARCH_PROGRAM_BUILD.md: one dry walk of a
# method v1.2 program from intake to the Stage 9 built certificate through the kit's verbs only
# (tests/fixtures/research-kit/walk_v12.sh; fixture HOME, registry and records; stub courier; no
# vendor, no live pilot). The pieces were built in separate waves (E3a intake, E3b Stage 9 and the
# yield stop, E3c the ceiling, the briefs and the soak job); this is the one run that joins them.

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS CC_RESEARCH_HOME CC_RESEARCH_REGISTRY CC_NOW
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  set +e
  /bin/bash "$REPO/tests/fixtures/research-kit/walk_v12.sh" "$BATS_FILE_TMPDIR/w" > "$BATS_FILE_TMPDIR/walk.out" 2>&1
  echo "$?" > "$BATS_FILE_TMPDIR/walk.rc"
  set -e
}

setup() {
  OUT="$BATS_FILE_TMPDIR/walk.out"
}

@test "the walk exits 0 and ends with the program build-certified" {
  [ "$(cat "$BATS_FILE_TMPDIR/walk.rc")" = 0 ] || { tail -30 "$OUT"; false; }
  grep -qx '## Walk end: demo is build-certified' "$OUT"
}

@test "stage 1: a fresh program is stamped 1.2 and its contract page carries the v1.2 ceiling" {
  grep -qx 'frame.json method_version: 1.2' "$OUT"
  grep -q 'ceiling with the v1.2 additions about 18.75 days (12 + 5.25 + 1.5)' "$OUT"
  grep -q 'about 18.75 days (lite profile, §6.1, plus the v1.2 yield ceiling 5.25 d and Stage 9 1.5 d)' "$OUT"
}

@test "stage 3: an unexplained failure keeps it open and budget end refuses; quiet probes stop it" {
  grep -q 'cc-research: stage 3 cannot end yet' "$OUT"
  grep -q '^stage 3: stop: the stage is quiet' "$OUT"
  grep -q '^stage 3 ended at ' "$OUT"
}

@test "stage 9: the finding's test failed before the fix and passed after; the no-repro one is not material" {
  grep -qx 'BF-1: material open' "$OUT"
  grep -qx 'BF-1: still failing, stays open' "$OUT"
  grep -qx 'BF-1: fixed, its repro passes' "$OUT"
  grep -q '^BF-2: material rejected-no-repro' "$OUT"
}

@test "stage 9: the soak job sampled hourly and the built gate passes rows 20-25 and certifies" {
  [ "$(grep -c 'cc-research job soak → job soak demo: ok — 1 sample(s), all pass' "$OUT")" -eq 4 ]
  [ "$(grep -cE '^2[0-5]\. .* PASS$' "$OUT")" -eq 6 ]
  grep -q '25 sample(s) over 24.0h after 0 restart(s)' "$OUT"
  grep -q '^BUILD-CERTIFIED demo: ' "$OUT"
  grep -q '^After implementation signoff: forecast about' "$OUT"
}

@test "the render relays the built certificate and never says 'Built –' beside it" {
  grep -q '^Built: certified .* (BUILT-CERT-v1)$' "$OUT"
  run grep -c 'Built –' "$OUT"
  [ "$output" = 0 ]
}
