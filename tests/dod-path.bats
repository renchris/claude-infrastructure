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

# Mint a real succession edge THROUGH THE LIB'S OWN WRITER — never by hand-writing lineage.tsv.
# A test that wrote the row itself would be a second copy of the format, and the reader agreeing
# with the test would then prove nothing about the reader agreeing with handoff-fire.sh.
_edge() {  # $1=firing cwd  $2=fired cwd
  bash -c ". '$REPO_ROOT/hooks/lib/dod-path.sh' && dod_lineage_record '$1' '$2' test"
}

@test "G2 CLOSED: a scope frozen in worktree A is READ by its SUCCESSOR worktree B of the same repo" {
  # THE EDGE IS PART OF THE SETUP NOW, AND THAT IS NOT A NARROWED FALSIFIER — it is the input this
  # case was always missing. This case and the crosstalk case below have the SAME setup (A freezes,
  # B reads) and OPPOSITE required answers (here B must inherit; there B must not). No function of
  # that setup can satisfy both, so "B inherits from A" was never derivable from the repo alone:
  # what distinguishes a successor from a concurrent sibling is whether a succession was RECORDED.
  # Minting it here is what makes this case state the invariant it always claimed to — a SUCCESSOR
  # inherits — rather than the weaker "any worktree of the repo inherits" it could only express
  # before. The un-recorded direction is pinned separately below, so neither answer is assumed.
  _edge "$A" "$B"
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
# CLOSED 2026-08-18 (row 4de3d0f9c0e1, prerequisite 2) — previously red-on-purpose and gated off,
# because the fix needed an input the tree did not record. It records one now: a succession edge
# (firing worktree → fired worktree) minted by handoff-fire.sh at the single site where LAUNCH_DIR
# resolves, `--recycle` included. The reader inherits along that lineage and drops a foreign wave's
# blocks. The gate and CC_DOD_CROSSTALK_REDPROOF are gone — a permanently-skipped case reports
# nothing, and these now run on every invocation like every other case in this file.
#
# BOTH waves below are RECORDED waves fired from a common lead L. That matters: it proves the
# filter DISCRIMINATES along lineage rather than merely doing "no record ⇒ inherit nothing", which
# a setup with no edges at all could not tell apart. The un-recorded direction is pinned in its own
# case further down.

@test "CROSSTALK: wave B's REMAINDER counts ONLY its own frozen items, not a concurrent wave A's" {
  local L="$BATS_TEST_TMPDIR/wt-lead"; git clone -q "$O" "$L" 2>/dev/null
  _edge "$L" "$A"; _edge "$L" "$B"        # one lead, two concurrent waves — neither descends the other
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
  local L="$BATS_TEST_TMPDIR/wt-lead"; git clone -q "$O" "$L" 2>/dev/null
  _edge "$L" "$A"; _edge "$L" "$B"
  ( cd "$A" && "$DP" set "Scope (frozen): wave A contract" ) >/dev/null
  ( cd "$B" && "$DP" set "Scope (frozen): wave B contract" ) >/dev/null
  run bash -c "printf '%s' '{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$B\"}' | '$DP'"
  [ "$status" -eq 0 ]
  local n
  n="$(printf '%s' "$output" | grep -cF 'wave A contract' || true)"
  if [ "$n" -ne 0 ]; then
    echo "wave B was handed a concurrent sibling's scope as binding ($n hit(s))" >&2; false
  fi
  # …and the injection is not merely EMPTY — B's own contract must still be there. A filter that
  # dropped everything would pass the assertion above while destroying the feature.
  printf '%s' "$output" | grep -qF 'wave B contract'
}

@test "LINEAGE: a predecessor's scope is inherited TRANSITIVELY (A → B → C)" {
  local C="$BATS_TEST_TMPDIR/wt-c"; git clone -q "$O" "$C" 2>/dev/null
  _edge "$A" "$B"; _edge "$B" "$C"
  ( cd "$A" && "$DP" set "Scope (frozen): the grandparent contract" ) >/dev/null
  run bash -c "cd '$C' && '$DP' get"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'the grandparent contract'
}

@test "LOSSLESS: a capture with NO toplevel stamp is inherited by any worktree (fail-open)" {
  # Every capture written before per-capture provenance landed is unattributable. The filter must
  # never guess at those — dropping them would turn this fix into the very blank-contract
  # regression the repo key exists to prevent.
  local f; f="$(cd "$A" && "$DP" path)"
  mkdir -p "$(dirname "$f")"
  printf '# hdr\n\n## 2026-01-01T00:00:00Z (pre-provenance)\nScope (frozen): the unattributed contract\n\n' > "$f"
  run bash -c "cd '$B' && '$DP' get"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'the unattributed contract'
}

@test "ISOLATION: an UN-RECORDED concurrent worktree does NOT inherit (the accepted cost, pinned)" {
  # A worktree nobody fired — a hand-made `claude -w` sibling — has no succession edge, so it is
  # treated as concurrent and re-freezes its own scope. This is the deliberate trade, recorded here
  # so it is a decision rather than an accident: see docs/research/dod-crosstalk-2026-08-18.md §5.
  ( cd "$A" && "$DP" set "Scope (frozen): wave A contract" ) >/dev/null
  run bash -c "cd '$B' && '$DP' get"
  [ "$status" -eq 0 ]
  local n; n="$(printf '%s' "$output" | grep -cF 'wave A contract' || true)"
  [ "$n" -eq 0 ]
}

@test "LINEAGE: a cycle (A→B and B→A) terminates and still inherits" {
  _edge "$A" "$B"; _edge "$B" "$A"
  ( cd "$A" && "$DP" set "Scope (frozen): the cyclic contract" ) >/dev/null
  run timeout 30 bash -c "cd '$B' && '$DP' get"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'the cyclic contract'
}

@test "LINEAGE: a same-dir succession records NO edge (a self-loop says nothing)" {
  _edge "$A" "$A"
  [ ! -s "$WRAP_DOD_DIR/lineage.tsv" ]
}

@test "SEAM: WRAP_DOD_FILE overrides both modes to one file (the producer↔consumer test contract)" {
  # This case's subject is PATH RESOLUTION — one file, both modes — so it mints the succession edge
  # for the same reason case 1 does, to keep lineage out of what it is actually measuring. The lib
  # deliberately carves NO exception for WRAP_DOD_FILE: an override that silently disabled the
  # filter would be a second, invisible set of rules for the surface tests run on.
  _edge "$A" "$B"
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/one.md"
  ( cd "$A" && "$DP" set "Scope (frozen): pinned" ) >/dev/null
  [ -f "$WRAP_DOD_FILE" ]
  run bash -c "cd '$B' && '$DP' get"
  printf '%s' "$output" | grep -q 'pinned'
}
