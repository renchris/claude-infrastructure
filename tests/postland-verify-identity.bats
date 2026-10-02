#!/usr/bin/env bats
# postland-verify.sh — the LANDED-IDENTITY SWEEP (row 8f4eae55a0c7).
#
# CONTRACT: each tick scans origin/main commits not yet scanned and pages when an AUTHOR or a
# COMMITTER email is not the sanctioned address (identity overlay git_identity.email). The first
# run seeds the scan state at the tip WITHOUT paging. A clean range pages nothing. A scanned range
# is never re-paged. No sanctioned address known ⇒ abstain, never page every commit.

setup() {
  T="$BATS_TEST_TMPDIR"
  SUT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/postland-verify.sh"
  export HOME="$T/home"; mkdir -p "$HOME"
  export CC_POSTLAND_DIR="$T/state" CC_PAGES_DIR="$T/pages" CC_IDL="$T/idl.jsonl"
  export CC_POSTLAND_NOTIFY="$T/notify"
  printf '#!/bin/sh\necho "$*" >> "%s/notified"\n' "$T" > "$CC_POSTLAND_NOTIFY"; chmod +x "$CC_POSTLAND_NOTIFY"
  export CC_GIT_IDENTITY_TEST=1 CC_IDENTITY_FILE="$T/identity.json"
  unset CC_GIT_IDENTITY_EMAIL
  printf '{"git_identity":{"email":"good@example.test"}}\n' > "$CC_IDENTITY_FILE"
  git init -q --bare "$T/origin.git"
  git -C "$T/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$T/origin.git" "$T/work" 2>/dev/null
  export CC_POSTLAND_REPO="$T/work"
  commit_as good@example.test good@example.test "seed"
}

# commit_as <author-email> <committer-email> <subject> — commits and pushes to origin main
commit_as() {
  GIT_AUTHOR_NAME=a GIT_AUTHOR_EMAIL="$1" GIT_COMMITTER_NAME=c GIT_COMMITTER_EMAIL="$2" \
    git -C "$T/work" -c commit.gpgsign=false commit -q --allow-empty --no-verify -m "$3"
  git -C "$T/work" push -q --no-verify origin HEAD:main 2>/dev/null
}
sweep() { bash "$SUT" identity-sweep </dev/null; }
npages() { find "$CC_PAGES_DIR" -name 'postland-identity-*.page' 2>/dev/null | grep -c . || true; }

@test "first run seeds the scan state at the tip and pages nothing" {
  commit_as noreply@anthropic.com noreply@anthropic.com "historical off-identity"
  run sweep
  [ "$status" -eq 0 ]
  [ "$(npages)" -eq 0 ]
  [ "$(cat "$CC_POSTLAND_DIR/identity-scan.sha")" = "$(git -C "$T/work" rev-parse HEAD)" ]
}

@test "an off-identity AUTHOR landed after the seed is paged, naming it and not the clean commit" {
  sweep
  commit_as good@example.test good@example.test "clean one"
  commit_as noreply@anthropic.com noreply@anthropic.com "cloud-authored one"
  run sweep
  [ "$status" -eq 0 ]
  [ "$(npages)" -eq 1 ]
  pf="$(find "$CC_PAGES_DIR" -name 'postland-identity-*.page')"
  grep -q 'cloud-authored one' "$pf"
  grep -q 'noreply@anthropic.com' "$pf"
  run ! grep -q 'clean one' "$pf"
  grep -q 'wrong commit identity' "$T/notified"
}

@test "a committer-only mismatch is paged too (a rebase keeps the author, rewrites the committer)" {
  sweep
  commit_as good@example.test t@e.com "rebased under a fixture identity"
  run sweep
  [ "$(npages)" -eq 1 ]
  grep -q 't@e.com' "$(find "$CC_PAGES_DIR" -name 'postland-identity-*.page')"
}

@test "a clean range pages nothing, and a scanned range is never re-paged" {
  sweep
  commit_as good@example.test good@example.test "clean"
  run sweep
  [ "$(npages)" -eq 0 ]
  commit_as other@example.test other@example.test "off"
  sweep
  [ "$(npages)" -eq 1 ]
  rm -f "$CC_PAGES_DIR"/postland-identity-*.page
  run sweep
  [ "$(npages)" -eq 0 ]
}

@test "no sanctioned address in the overlay ⇒ abstains (no page), even over an off-identity commit" {
  sweep
  commit_as other@example.test other@example.test "off"
  printf '{}\n' > "$CC_IDENTITY_FILE"
  run sweep
  [ "$status" -eq 0 ]
  [ "$(npages)" -eq 0 ]
  grep -q 'landed sweep abstained' "$CC_POSTLAND_DIR/runner.log"
}
