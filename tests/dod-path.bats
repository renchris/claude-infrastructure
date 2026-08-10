#!/usr/bin/env bats
# hooks/lib/dod-path.sh + its two consumers — the repo-keyed DoD (CLOSE_INTEGRITY W3, generator G2).
#
# THE PINNED INVARIANT: a fresh worktree of the SAME repo inherits the frozen scope (the pre-fix
# path-hash keying gave every successor a blank contract, and absent-DoD reads ✅-with-caveat, so
# the certificate could render over an unverifiable scope). Migration is lossless: legacy
# path-hash files keep answering for their own toplevel; new captures go to the repo-key store.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DP="$REPO_ROOT/hooks/dod-persist.sh"
  WL="$REPO_ROOT/scripts/wrap-ledger.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod"; mkdir -p "$WRAP_DOD_DIR"
  unset WRAP_DOD_FILE CLAUDE_SESSION_ID WRAP_SESSION_ID
  # One origin, two worktree-like clones — the succession hop under test.
  O="$BATS_TEST_TMPDIR/origin.git"; git init -q --bare "$O"
  A="$BATS_TEST_TMPDIR/wt-a"; B="$BATS_TEST_TMPDIR/wt-b"
  git clone -q "$O" "$A" 2>/dev/null
  ( cd "$A" && git checkout -q -b main && echo x > f && git add f \
    && git -c user.email=t@e.com -c user.name=t commit -q -m c && git push -q -u origin main ) >/dev/null 2>&1
  git clone -q "$O" "$B" 2>/dev/null
  # Hermeticity for wrap-ledger's other forks.
  BSTUB="$BATS_TEST_TMPDIR/b-stub"; printf '%s\n' '#!/usr/bin/env bash' 'echo []' > "$BSTUB"; chmod +x "$BSTUB"
  CSTUB="$BATS_TEST_TMPDIR/c-stub"; printf '%s\n' '#!/usr/bin/env bash' 'echo 0' > "$CSTUB"; chmod +x "$CSTUB"
  export CC_DECIDE_BIN="$BSTUB" CC_BACKLOG_BIN="$BSTUB" CC_CUSTODY_BIN="$CSTUB"
}

@test "G2 CLOSED: a scope frozen in worktree A is READ by a fresh worktree B of the same repo" {
  ( cd "$A" && "$DP" set "Scope (frozen): the wave's contract" ) >/dev/null
  run bash -c "cd '$B' && '$DP' get"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "the wave's contract"
}

@test "the write path is repo-keyed (repo-*.md), not path-hashed" {
  run bash -c "cd '$A' && '$DP' path"
  [ "$status" -eq 0 ]
  case "$output" in "$WRAP_DOD_DIR"/repo-*.md) : ;; *) echo "not repo-keyed: $output" >&2; false ;; esac
}

@test "LOSSLESS: a pre-W3 legacy file keeps answering for ITS toplevel when the repo store is empty" {
  local top hash legacy
  top="$(cd "$A" && pwd -P)"
  hash="$(printf '%s' "$top" | shasum | cut -c1-16)"
  legacy="$WRAP_DOD_DIR/$hash.md"
  printf '## old\nScope (frozen): the legacy contract\n' > "$legacy"
  run bash -c "cd '$A' && '$DP' get"
  printf '%s' "$output" | grep -q 'the legacy contract'
}

@test "precedence: a repo-store scope WINS over the legacy one at get" {
  local top hash
  top="$(cd "$A" && pwd -P)"; hash="$(printf '%s' "$top" | shasum | cut -c1-16)"
  printf '## old\nScope (frozen): the legacy contract\n' > "$WRAP_DOD_DIR/$hash.md"
  ( cd "$A" && "$DP" set "Scope (frozen): the new contract" ) >/dev/null
  run bash -c "cd '$A' && '$DP' get"
  printf '%s' "$output" | grep -q 'the new contract'
}

@test "wrap-ledger REMAINDER sums across BOTH stores; DOD=present if either exists" {
  local top hash
  top="$(cd "$A" && pwd -P)"; hash="$(printf '%s' "$top" | shasum | cut -c1-16)"
  printf -- '- [ ] legacy item\n' > "$WRAP_DOD_DIR/$hash.md"
  ( cd "$A" && "$DP" set "Scope (frozen): x" ) >/dev/null
  printf -- '- [ ] repo item one\n- [ ] repo item two\n' >> "$(cd "$A" && "$DP" path)"
  run bash -c "cd '$A' && WRAP_TRUNK=origin/main bash '$WL' --machine"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^DOD=present'
  printf '%s' "$output" | grep -q '^REMAINDER=3'
}

@test "a repo with NO origin keeps the legacy scheme outright" {
  local L="$BATS_TEST_TMPDIR/local-only"; mkdir -p "$L"
  ( cd "$L" && git init -q \
    && git -c user.email=t@e.com -c user.name=t commit -q --allow-empty -m c ) >/dev/null 2>&1
  run bash -c "cd '$L' && '$DP' path"
  case "$output" in "$WRAP_DOD_DIR"/repo-*.md) echo "repo-keyed a local-only repo: $output" >&2; false ;; *) : ;; esac
}

@test "SEAM: WRAP_DOD_FILE overrides both modes to one file (the producer↔consumer test contract)" {
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/one.md"
  ( cd "$A" && "$DP" set "Scope (frozen): pinned" ) >/dev/null
  [ -f "$WRAP_DOD_FILE" ]
  run bash -c "cd '$B' && '$DP' get"
  printf '%s' "$output" | grep -q 'pinned'
}
