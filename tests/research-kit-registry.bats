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

# ── A program covers more than one directory (audit 2026-10-04, REPORT.md §3 row 4e): its build
#    worktrees and sibling worktrees of the deliverable repo must resolve to it, or they run under
#    the standing rules. Planted input: a second root by repeated --root, by add-root, and by a
#    re-register, each checked through the resolver the rules and the Stop hook read. ──
@test "register takes --root more than once and every root resolves to the program" {
  mkdir -p "$BATS_TEST_TMPDIR/repo/src" "$BATS_TEST_TMPDIR/build-wt/src"
  run "$G" register --program demo --root "$BATS_TEST_TMPDIR/repo" --root "$BATS_TEST_TMPDIR/build-wt"
  [ "$status" -eq 0 ]
  [ "$(resolve "$BATS_TEST_TMPDIR/repo/src")" = "demo registered" ]
  [ "$(resolve "$BATS_TEST_TMPDIR/build-wt/src")" = "demo registered" ]
}

@test "add-root makes a sibling worktree resolve and leaves state and aliases untouched" {
  mkdir -p "$BATS_TEST_TMPDIR/repo" "$BATS_TEST_TMPDIR/wt-sibling/sub"
  "$G" register --program demo --root "$BATS_TEST_TMPDIR/repo" --alias "the demo" --alias "demo two"
  jq '.programs[0].state = "certified"' "$CC_RESEARCH_REGISTRY" > "$BATS_TEST_TMPDIR/reg.json"
  mv "$BATS_TEST_TMPDIR/reg.json" "$CC_RESEARCH_REGISTRY"
  [ -z "$(resolve "$BATS_TEST_TMPDIR/wt-sibling/sub")" ]
  before="$(jq -c '.programs[0] | {aliases, state}' "$CC_RESEARCH_REGISTRY")"
  run "$G" add-root --program demo --root "$BATS_TEST_TMPDIR/wt-sibling/"
  [ "$status" -eq 0 ]
  [ "$(resolve "$BATS_TEST_TMPDIR/wt-sibling/sub")" = "demo certified" ]
  [ "$(resolve "$BATS_TEST_TMPDIR/repo")" = "demo certified" ]
  [ "$(jq -c '.programs[0] | {aliases, state}' "$CC_RESEARCH_REGISTRY")" = "$before" ]
  # idempotent, and stored normalized (no trailing slash), so the duplicate is recognized
  run "$G" add-root --program demo --root "$BATS_TEST_TMPDIR/wt-sibling"
  [ "$status" -eq 0 ]
  [ "$(jq '.programs[0].cwd_roots | length' "$CC_RESEARCH_REGISTRY")" -eq 2 ]
  run jq -r '.programs[0].cwd_roots[] | select(endswith("/"))' "$CC_RESEARCH_REGISTRY"
  [ -z "$output" ]
}

@test "re-register keeps the roots already registered for the slug" {
  mkdir -p "$BATS_TEST_TMPDIR/repo" "$BATS_TEST_TMPDIR/later"
  "$G" register --program demo --root "$BATS_TEST_TMPDIR/repo"
  run "$G" register --program demo --root "$BATS_TEST_TMPDIR/later"
  [ "$status" -eq 0 ]
  [ "$(resolve "$BATS_TEST_TMPDIR/repo")" = "demo registered" ]
  [ "$(resolve "$BATS_TEST_TMPDIR/later")" = "demo registered" ]
}

@test "re-register keeps the aliases already registered and adds new ones" {
  mkdir -p "$BATS_TEST_TMPDIR/repo"
  "$G" register --program demo --root "$BATS_TEST_TMPDIR/repo" --alias "Demo One"
  run "$G" register --program demo --root "$BATS_TEST_TMPDIR/repo"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.programs[] | select(.slug=="demo") | .aliases' "$CC_RESEARCH_REGISTRY")" = '["Demo One"]' ]
  "$G" register --program demo --root "$BATS_TEST_TMPDIR/repo" --alias "demo2"
  [ "$(jq -c '.programs[] | select(.slug=="demo") | .aliases' "$CC_RESEARCH_REGISTRY")" = '["Demo One","demo2"]' ]
}

@test "add-root refuses a relative path, a missing directory and an unregistered program" {
  mkdir -p "$BATS_TEST_TMPDIR/repo" "$BATS_TEST_TMPDIR/other"
  "$G" register --program demo --root "$BATS_TEST_TMPDIR/repo"
  before="$(cat "$CC_RESEARCH_REGISTRY")"
  run "$G" add-root --program demo --root relative/dir
  [ "$status" -eq 2 ]
  run "$G" add-root --program demo --root "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$status" -eq 2 ]
  run "$G" add-root --program nosuch --root "$BATS_TEST_TMPDIR/other"
  [ "$status" -eq 2 ]
  [ "$(cat "$CC_RESEARCH_REGISTRY")" = "$before" ]
}
