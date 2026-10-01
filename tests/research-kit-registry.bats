#!/usr/bin/env bats
# research-kit-registry — the registry gate.sh writes is the one wave A1's resolver reads
# (scripts/lib/research-program.sh; REPORT.md §10 items 1 and 10). In particular the freeze makes the
# program ACTIVE in state `certifying`, so the research block and the Stop check keyed on the resolver
# are on while the rehearsal's relay trials run (§10 item 1).

setup() {
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  G="$REPO/scripts/research-kit/gate.sh"
  RP="$REPO/scripts/lib/research-program.sh"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/home" CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/home/programs.json"
  export CC_NOW="2026-10-01T12:00:00Z" CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions" CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
}

resolve() { /bin/bash -c ". '$RP'; rp_resolve_cwd '$1'" 2>/dev/null; }
active() { /bin/bash -c ". '$RP'; rp_is_active '$1'" 2>/dev/null; }

@test "a registered program resolves from a subdirectory of its root and is active" {
  mkdir -p "$BATS_TEST_TMPDIR/repo/src"
  "$G" register --program demo --root "$BATS_TEST_TMPDIR/repo" --alias "the demo"
  [ "$(resolve "$BATS_TEST_TMPDIR/repo/src")" = "demo registered" ]
  active "$BATS_TEST_TMPDIR/repo/src"
}

@test "§10 item 1: after the freeze the resolver reads certifying, and the program stays active" {
  "$BATS_TEST_DIRNAME/fixtures/research-kit/build_good.py" "$BATS_TEST_TMPDIR" > /dev/null
  run "$G" freeze --program demo
  [ "$status" -eq 0 ]
  [ "$(resolve "$BATS_TEST_TMPDIR/repo")" = "demo certifying" ]
  active "$BATS_TEST_TMPDIR/repo"
}

@test "a closed program is not active" {
  mkdir -p "$BATS_TEST_TMPDIR/repo"
  "$G" register --program demo --root "$BATS_TEST_TMPDIR/repo"
  "$G" close --program demo
  run active "$BATS_TEST_TMPDIR/repo"
  [ "$status" -eq 1 ]
}

@test "registering a second program leaves the first entry untouched" {
  mkdir -p "$BATS_TEST_TMPDIR/a" "$BATS_TEST_TMPDIR/b"
  "$G" register --program one --root "$BATS_TEST_TMPDIR/a"
  "$G" register --program two --root "$BATS_TEST_TMPDIR/b"
  [ "$(resolve "$BATS_TEST_TMPDIR/a")" = "one registered" ]
  [ "$(resolve "$BATS_TEST_TMPDIR/b")" = "two registered" ]
}

@test "a relative root is refused rather than written into the registry" {
  run "$G" register --program demo --root relative/dir
  [ "$status" -eq 2 ]
  [ ! -e "$CC_RESEARCH_REGISTRY" ]
}
