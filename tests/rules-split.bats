#!/usr/bin/env bats
# The 2026-09-23 split of .claude/rules/agent-operating-lessons.md into a resident half and
# agent-operating-lessons-situational.md (docs/research/token-efficiency-2026-09-23/audit/C7.labels.md).
#
# The split must not change what loads by default: with no claudeMdExcludes set, both files load,
# so every line of the original has to be in exactly one of them. The live case replays the real
# pre-split blob from git; the fixture cases prove the checker can fail in both directions.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CHECK="$REPO/tests/helpers/rules-split-check.sh"
  RES="$REPO/.claude/rules/agent-operating-lessons.md"
  SIT="$REPO/.claude/rules/agent-operating-lessons-situational.md"
  # The last commit that touched the unsplit file (its blob is f0182948ce74).
  PRE_SPLIT=51ea44c9a
  TMP="$BATS_TEST_TMPDIR"
}

# Judged at the split commit, not on the working tree: once the split has landed, the two files are
# curated like any other (a duplicate removed, an over-budget hook rewritten, a lesson promoted),
# and this check must not go red on that. The split commit is the one that ADDED the situational
# file; its parent holds the unsplit original. Before that commit exists, the working tree is
# judged against the last commit that touched the unsplit file.
@test "every line of the pre-split rules file is in exactly one of the two files" {
  local rel=.claude/rules/agent-operating-lessons.md srel=.claude/rules/agent-operating-lessons-situational.md split
  split=$(git -C "$REPO" log --diff-filter=A --format=%H -- "$srel" 2>/dev/null | tail -1)
  if [ -n "$split" ]; then
    git -C "$REPO" cat-file -e "$split^:$rel" 2>/dev/null || skip "the split commit's parent is not in this clone"
    git -C "$REPO" show "$split^:$rel" > "$TMP/orig.md"
    git -C "$REPO" show "$split:$rel" > "$TMP/res.md"
    git -C "$REPO" show "$split:$srel" > "$TMP/sit.md"
  else
    git -C "$REPO" cat-file -e "$PRE_SPLIT:$rel" 2>/dev/null || skip "pre-split commit $PRE_SPLIT not in this clone"
    git -C "$REPO" show "$PRE_SPLIT:$rel" > "$TMP/orig.md"
    cp "$RES" "$TMP/res.md"; cp "$SIT" "$TMP/sit.md"
  fi
  run "$CHECK" "$TMP/orig.md" "$TMP/res.md" "$TMP/sit.md"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The unsplit file was append-only and held 208 bullet lines at $PRE_SPLIT, so any honest
  # original has at least that many; fewer means the wrong blob was compared.
  local b; b=$(printf '%s\n' "$output" | sed -nE 's/.*, ([0-9]+) of them bullets.*/\1/p')
  [ -n "$b" ] && [ "$b" -ge 208 ] || { echo "$output"; false; }
}

@test "the resident file points at the situational file" {
  [ -f "$SIT" ] || false
  grep -qF 'agent-operating-lessons-situational.md' "$RES" || false
  grep -qF 'grep that file for the symptom' "$RES" || false
}

@test "checker: a line in neither file is MISSING" {
  printf 'h\n- a\n- b\n' > "$TMP/o.md"; printf 'h\n- a\n' > "$TMP/r.md"; printf '# s\n' > "$TMP/s.md"
  run "$CHECK" "$TMP/o.md" "$TMP/r.md" "$TMP/s.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"MISSING (1 of 1): - b"* ]] || false
}

@test "checker: a line in both files is refused" {
  printf 'h\n- a\n- b\n' > "$TMP/o.md"; printf 'h\n- a\n- b\n' > "$TMP/r.md"; printf -- '- b\n' > "$TMP/s.md"
  run "$CHECK" "$TMP/o.md" "$TMP/r.md" "$TMP/s.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"IN BOTH: - b"* ]] || false
}

@test "checker: a clean split passes, indentation and added lines ignored" {
  printf 'h\n- a\n  - nested\n' > "$TMP/o.md"; printf 'h\n- nested\nPointer.\n' > "$TMP/r.md"
  printf '# s\n- a\n' > "$TMP/s.md"
  run "$CHECK" "$TMP/o.md" "$TMP/r.md" "$TMP/s.md"
  [ "$status" -eq 0 ] || false
}

@test "checker: an unreadable input is a NON-VERDICT" {
  run "$CHECK" "$TMP/nope.md" "$RES" "$SIT"
  [ "$status" -eq 2 ] || false
}
