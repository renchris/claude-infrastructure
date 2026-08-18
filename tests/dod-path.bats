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


# ── CROSSTALK (row 4de3d0f9c0e1) — the flip side of the hop above ────────────────────────────────
# The repo key is byte-equal across every worktree of the repo. That is what makes the SUCCESSION
# hop work (test 1). It is also what makes two CONCURRENT waves of the same repo share one scope
# file: wave B reads wave A's frozen scope as binding and REMAINDER sums both waves' boxes.
# The axis is pinned INERT on the legacy side: neither worktree has a legacy path-hash file here,
# so anything these cases observe comes from the repo-key store alone.
#
# THESE TWO CASES ARE RED ON PURPOSE AND ARE GATED OFF BY DEFAULT. They are the reproducible
# red-proof for a defect that CANNOT be fixed from state this tree records — see
# docs/research/dod-crosstalk-2026-08-18.md. Nothing in the store attributes a capture to a wave,
# and the DEFAULT succession (`handoff-fire.sh --recycle`) writes no lineage record at all
# (handoff-fire.sh:7358 — `RECYCLE=0` is a precondition of the fired-peer stamp), so every read-side
# rule buildable today either keeps the crosstalk or re-breaks the hop test 1 pins. Reproduce with:
#     CC_DOD_CROSSTALK_REDPROOF=1 bats tests/dod-path.bats
# UNSKIP the day per-capture provenance + a lineage token exist; that is the fix, not a read-side
# heuristic.
_crosstalk_gate() {
  [ "${CC_DOD_CROSSTALK_REDPROOF:-0}" = 1 ] \
    || skip "known-red: no wave identity exists to fix it — docs/research/dod-crosstalk-2026-08-18.md"
}

@test "CROSSTALK: wave B's REMAINDER counts ONLY its own frozen items, not a concurrent wave A's" {
  _crosstalk_gate
  ( cd "$A" && "$DP" set "Scope (frozen): wave A contract" ) >/dev/null
  printf -- '- [ ] alpha (wave A)\n' >> "$(cd "$A" && "$DP" path)"
  ( cd "$B" && "$DP" set "Scope (frozen): wave B contract" ) >/dev/null
  printf -- '- [ ] beta (wave B)\n' >> "$(cd "$B" && "$DP" path)"
  run bash -c "cd '$B' && WRAP_TRUNK=origin/main bash '$WL' --machine"
  [ "$status" -eq 0 ]
  local got; got="$(printf '%s\n' "$output" | grep '^REMAINDER=' || true)"
  if [ "$got" != "REMAINDER=1" ]; then
    echo "wave B summed a concurrent sibling's boxes: $got (want REMAINDER=1)" >&2; false
  fi
}

@test "CROSSTALK: a concurrent wave A's frozen scope is not injected into wave B as binding" {
  _crosstalk_gate
  ( cd "$A" && "$DP" set "Scope (frozen): wave A contract" ) >/dev/null
  run bash -c "printf '%s' '{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$B\"}' | '$DP'"
  [ "$status" -eq 0 ]
  if grep -q 'wave A contract' <<<"$output"; then
    echo "wave B was handed a concurrent sibling's scope as binding" >&2; false
  fi
}

@test "SEAM: WRAP_DOD_FILE overrides both modes to one file (the producer↔consumer test contract)" {
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/one.md"
  ( cd "$A" && "$DP" set "Scope (frozen): pinned" ) >/dev/null
  [ -f "$WRAP_DOD_FILE" ]
  run bash -c "cd '$B' && '$DP' get"
  printf '%s' "$output" | grep -q 'pinned'
}
