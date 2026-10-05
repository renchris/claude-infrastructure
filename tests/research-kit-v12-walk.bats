#!/usr/bin/env bats
# research-kit-v12-walk — wave E3c of docs/plans/RESEARCH_PROGRAM_BUILD.md: one dry walk of a
# method v1.2 program from intake to the Stage 9 built certificate through the kit's verbs only
# (tests/fixtures/research-kit/walk_v12.sh; fixture HOME, registry and records; stub courier; no
# vendor, no live pilot). The pieces were built in separate waves (E3a intake, E3b Stage 9 and the
# yield stop, E3c the ceiling, the briefs and the soak job); this is the one run that joins them.
# Wave E3d extends it through the implementation signature: refused for an agent ancestor, made by
# the fixture signer on the operator's path (bin/cc-signoff itself), and required before close.

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

@test "the walk exits 0, reaches build-certified, and ends closed by way of implementation-signed" {
  [ "$(cat "$BATS_FILE_TMPDIR/walk.rc")" = 0 ] || { tail -30 "$OUT"; false; }
  grep -qx 'registry: demo build-certified' "$OUT"
  grep -qx '## Walk end: demo is closed, by way of implementation-signed' "$OUT"
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
  grep -q '^Built: certified .* (BUILT-CERT-v1) · implementation not signed$' "$OUT"
  run grep -c 'Built –' "$OUT"
  [ "$output" = 0 ]
}

# ── wave E3d: the implementation signature ───────────────────────────────────────────────────────

@test "E3d: built signoff renders the certificate, the pinned path and hash, and the operator's command" {
  grep -qE '^Signing pins built/BUILT-CERT-v1\.json = [0-9a-f]{40} ' "$OUT"
  grep -qx 'Implementation: not signed' "$OUT"
  grep -qx '  cc-signoff research:demo/implementation --evidence <what you read>' "$OUT"
}

@test "E3d: unsigned, the gate refuses built-signed, close and a post-signoff wave" {
  grep -q '^gate.sh: built-signed refused: BUILT-CERT-v1 carries no operator signature' "$OUT"
  grep -q '^gate.sh: close refused: demo is build-certified and BUILT-CERT-v1 carries no operator signature' "$OUT"
  grep -q "this wave follows implementation signoff and the registry state is 'build-certified'" "$OUT"
}

@test "E3d: a signature attempted under a claude ancestor is refused with exit 3 and writes nothing" {
  grep -q '^REFUSED — this signing tool is descended from a claude process (.*claude-agent-shell at depth 1)' "$OUT"
  # the refusal's exit code is the line after the refusal text; 0 records and no registry move follow
  grep -A6 '^REFUSED — this signing tool' "$OUT" | grep -qx '(exit 3)'
  grep -qx 'implementation signatures on file: 0 · registry: demo build-certified' "$OUT"
}

@test "E3d: the fixture signer takes the operator path: one record, pinned, registry implementation-signed" {
  grep -qx 'SIGNED research:demo/implementation' "$OUT"
  grep -qE '^  pinned built/BUILT-CERT-v1\.json = [0-9a-f]{40} ' "$OUT"
  grep -q '^  IMPLEMENTATION-SIGNED demo: BUILT-CERT-v1 signed by the operator .*; registry -> implementation-signed$' "$OUT"
  grep -qx 'implementation signatures on file: 1 · registry: demo implementation-signed' "$OUT"
  # the signature pins the same hash the agent's render showed before it
  shown="$(sed -n 's/^Signing pins built\/BUILT-CERT-v1\.json = \([0-9a-f]*\) .*/\1/p' "$OUT")"
  pinned="$(sed -n 's/^  pinned built\/BUILT-CERT-v1\.json = \([0-9a-f]*\) .*/\1/p' "$OUT")"
  [ -n "$shown" ]
  [ "$shown" = "$pinned" ]
  grep -q '"fixture-signer"' "$BATS_FILE_TMPDIR/w/home/demo/signoff.jsonl"
}

@test "E3d: signed, the render says so, a post-signoff wave is clear and close passes" {
  grep -qE '^Built: certified .* \(BUILT-CERT-v1\) · implementation signed by the operator 20[0-9T:-]+Z$' "$OUT"
  grep -qx 'CLEAR demo every wave: CERT-v1 carries nothing that blocks it' "$OUT"
  grep -qx 'closed demo' "$OUT"
}
