#!/usr/bin/env bats
# deploy-live.sh — green-stamp-gated advance of the live layer (+ the nightly postland-inertness
# guard). Fully isolated: a bare "origin" + a "shared" clone under BATS_TEST_TMPDIR, a fixture
# stamps dir, and an install.sh stub that records its invocation. No real checkout is touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DL="$REPO/scripts/deploy-live.sh"
  NIGHTLY="$REPO/scripts/nightly-regression.sh"
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  SHARED="$BATS_TEST_TMPDIR/shared"
  STAMPS="$BATS_TEST_TMPDIR/postland/stamps"
  PAGES="$BATS_TEST_TMPDIR/pages"
  INSTALL_LOG="$BATS_TEST_TMPDIR/install.invoked"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@x GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@x
  git init -q --bare "$ORIGIN"
  git init -q "$SHARED"; git -C "$SHARED" remote add origin "$ORIGIN"
  commit_push a
  git -C "$SHARED" branch -M main 2>/dev/null || true
  git -C "$SHARED" push -q -u origin main
  mkdir -p "$STAMPS"
  printf '#!/bin/bash\necho ran >> "%s"\n' "$INSTALL_LOG" > "$SHARED/install.sh"
  chmod +x "$SHARED/install.sh"
}

commit_push() { # <name> — commit in the shared clone (caller pushes when it wants origin ahead)
  echo "$1" > "$SHARED/$1.txt"; git -C "$SHARED" add -A; git -C "$SHARED" commit -q -m "$1"
}

stamp() { # <rev> [verdict]
  local tree; tree="$(git -C "$SHARED" rev-parse "$1^{tree}")"
  printf '{"verdict":"%s","tree":"%s"}\n' "${2:-green}" "$tree" > "$STAMPS/$tree.json"
}

dl() { env DEPLOY_REPO="$SHARED" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" \
           CC_PAGES_DIR="$PAGES" bash "$DL" "$@"; }

# advance origin/main by N commits while the clone's HEAD stays put (the deploy-lag shape)
advance_origin() { # <name...>
  local head; head="$(git -C "$SHARED" rev-parse HEAD)"
  for n in "$@"; do commit_push "$n"; done
  git -C "$SHARED" push -q origin main
  git -C "$SHARED" reset -q --hard "$head"
}

@test "ff stops at the newest STAMPED ancestor (two un-stamped commits on top)" {
  advance_origin b c d
  stamp "origin/main~2"                       # b is green; c,d un-stamped
  want="$(git -C "$SHARED" rev-parse origin/main~2)"
  run dl
  [ "$status" -eq 0 ]
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$want" ]
  echo "$output" | grep -q "2 un-stamped commit"
}

@test "already deployed: HEAD is the newest green — exit 0, no merge" {
  advance_origin b
  stamp HEAD                                   # the commit we are already on
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "already deployed"
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
}

@test "no green stamp within the scan window: refuses, writes an epoch-headed page, HEAD unmoved" {
  advance_origin b c
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "REFUSED"
  tip="$(git -C "$SHARED" rev-parse origin/main | cut -c1-12)"
  [ -f "$PAGES/deploy-blocked-$tip.page" ]
  head -1 "$PAGES/deploy-blocked-$tip.page" | grep -qE '^[0-9]+$'
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
}

@test "a RED-verdict stamp is not green — still refuses" {
  advance_origin b
  stamp origin/main red
  run dl
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "no GREEN stamp"
}

@test "stamps dir ABSENT: refuses without --bootstrap" {
  advance_origin b
  rm -rf "$BATS_TEST_TMPDIR/postland"
  run dl
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "verification net is not active"
}

@test "--bootstrap with no stamps dir deploys the tip under a loud UNSTAMPED banner" {
  advance_origin b
  rm -rf "$BATS_TEST_TMPDIR/postland"
  run dl --bootstrap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "UNSTAMPED bootstrap deploy"
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$(git -C "$SHARED" rev-parse origin/main)" ]
}

@test "--force overrides the gate when stamps exist but nothing is green" {
  advance_origin b c
  run dl --force
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "gate BYPASSED"
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$(git -C "$SHARED" rev-parse origin/main)" ]
}

@test "--dry-run mutates nothing (no merge, no install, no page)" {
  advance_origin b c
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl --dry-run                              # nothing green → decision is a refusal
  [ "$status" -eq 1 ]
  [ ! -e "$PAGES" ]
  stamp origin/main
  run dl --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "DRY RUN"
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
  [ ! -f "$INSTALL_LOG" ]
}

@test "refuses to roll back: newest green is BEHIND the live HEAD" {
  stamp HEAD                                    # the commit that is already live
  commit_push b; git -C "$SHARED" push -q origin main   # HEAD and origin both move past it
  before="$(git -C "$SHARED" rev-parse HEAD)"
  run dl
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ROLL BACK"
  [ "$(git -C "$SHARED" rev-parse HEAD)" = "$before" ]
}

@test "install.sh is invoked on a successful deploy" {
  advance_origin b
  stamp origin/main
  run dl
  [ "$status" -eq 0 ]
  [ -f "$INSTALL_LOG" ]
  echo "$output" | grep -q "install.sh ok"
}

@test "fetch failure is loud and fatal (bad remote)" {
  advance_origin b
  stamp origin/main
  git -C "$SHARED" remote set-url origin "$BATS_TEST_TMPDIR/does-not-exist.git"
  run dl
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "git fetch origin main FAILED"
}

@test "non-repo DEPLOY_REPO refuses" {
  run env DEPLOY_REPO="$BATS_TEST_TMPDIR/nope" CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland" \
      CC_PAGES_DIR="$PAGES" bash "$DL"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not a git checkout"
}

# ── nightly-regression postland_inertness (env-seam wired, stubbed check-set) ──────────────────
nightly() { # runs the nightly with every other check stubbed green
  mkdir -p "$BATS_TEST_TMPDIR/gt" "$BATS_TEST_TMPDIR/empty"
  printf '#!/usr/bin/env bats\n@test "ok" { true; }\n' > "$BATS_TEST_TMPDIR/gt/ok.bats"
  printf '<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>\n' \
    > "$BATS_TEST_TMPDIR/good.plist"
  env CC_NIGHTLY_NOTIFY=/usr/bin/true CC_NIGHTLY_NEVERSTUCK=/usr/bin/true CC_NIGHTLY_ABSTAIN=/usr/bin/true \
      CC_NIGHTLY_GATE_GLOB="$BATS_TEST_TMPDIR/empty/*.sh" CC_NIGHTLY_LINT_GLOB="$BATS_TEST_TMPDIR/empty/*.sh" \
      CC_NIGHTLY_BATS_DIR="$BATS_TEST_TMPDIR/gt" CC_NIGHTLY_PLIST_GLOB="$BATS_TEST_TMPDIR/good.plist" \
      CC_NIGHTLY_PAGEDIR="$PAGES" CC_NIGHTLY_LOG="$BATS_TEST_TMPDIR/reg.log" \
      CC_NIGHTLY_REPO="$SHARED" CC_NIGHTLY_POSTLAND_DIR="$1" CC_NIGHTLY_POSTLAND_AGE=0 \
      bash "$NIGHTLY"
}

@test "nightly postland-inertness: RED when the net exists but a settled trunk commit is unstamped" {
  advance_origin b
  run nightly "$BATS_TEST_TMPDIR/postland"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "RED  postland-inertness"
  grep -q "postland net INERT" "$PAGES/nightly-regression.page"   # the page carries WHY, not just the name
}

@test "nightly postland-inertness: green-abstains when the stamps dir does not exist" {
  advance_origin b
  run nightly "$BATS_TEST_TMPDIR/no-such-postland"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ok   postland-inertness"
}
