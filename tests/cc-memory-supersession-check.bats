#!/usr/bin/env bats
# cc-memory-supersession-check (TrueMemory #12, docs/research/truememory-2026-09-27.md §3.12) — the
# report-only audit /compact-memory step 4b runs. One fixture store per finding kind, a clean store,
# and an unreadable one; every case asserts the exact rendered lines. Fixture stores live under
# $BATS_TEST_TMPDIR, so no case reads a live memory store.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/bin/cc-memory-supersession-check"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  M="$BATS_TEST_TMPDIR/memory"
  mkdir -p "$M"
}

# topic <name> [superseded_by value] — a frontmatter topic file, marked inside lines 1-12 when a
# value is given (the placement the rule prescribes and the rotor reads)
topic() {
  {
    printf -- '---\nname: %s\ndescription: fixture\n' "$1"
    [ -n "${2:-}" ] && printf 'superseded_by: %s\n' "$2"
    printf -- '---\n\nbody of %s\n' "$1"
  } > "$M/$1.md"
}

@test "clean store: an honest marker pointing at a live heir is no finding" {
  topic old heir
  topic heir
  printf -- '- [Heir](heir.md) — the current rule\n' > "$M/MEMORY.md"
  run "$C" "$M"
  [ "$status" -eq 0 ]
  [ "$output" = "SUPERSESSION-VERDICT findings=0 files=2" ]
}

@test "the dated form the rule prescribes resolves its heir by the first token" {
  topic old 'heir (2026-09-28)'
  topic heir
  run "$C" "$M"
  [ "$status" -eq 0 ]
  [ "$output" = "SUPERSESSION-VERDICT findings=0 files=2" ]
}

@test "dangling heir: no <heir> or <heir>.md in the store" {
  topic old 'ghost (2026-09-28)'
  run "$C" "$M"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "dangling-heir old.md -> ghost (no ghost or ghost.md in the store)" ]
  [ "${lines[1]}" = "SUPERSESSION-VERDICT findings=1 files=1" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "cycle: A -> B -> A is reported once, from its smallest member" {
  topic b a.md
  topic a b
  run "$C" "$M"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "cycle a.md -> b.md -> a.md" ]
  [ "${lines[1]}" = "SUPERSESSION-VERDICT findings=1 files=2" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "key beyond line 12: the rotor cannot see it, so it is a finding" {
  topic heir
  {
    printf -- '---\nname: late\n'
    for i in 1 2 3 4 5 6 7 8 9 10 11; do printf 'k%s: v\n' "$i"; done
    printf 'superseded_by: heir (2026-09-28)\n---\n'
  } > "$M/late.md"
  [ "$(grep -n '^superseded_by:' "$M/late.md" | cut -d: -f1)" = 14 ]
  run "$C" "$M"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "key-beyond-line-12 late.md:14 (cc-memory-rotate reads lines 1-12 only)" ]
  [ "${lines[1]}" = "SUPERSESSION-VERDICT findings=1 files=2" ]
}

@test "index line linking a superseded file is a finding naming the heir" {
  topic old heir
  topic heir
  printf -- '# Memory\n- [Old](old.md) — the replaced rule\n' > "$M/MEMORY.md"
  run "$C" "$M"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "index-links-superseded MEMORY.md:2 -> old.md (superseded_by heir)" ]
  [ "${lines[1]}" = "SUPERSESSION-VERDICT findings=1 files=2" ]
}

@test "prose and fenced mentions of the key are not markers" {
  {
    printf -- '---\nname: lesson\n---\n'
    # shellcheck disable=SC2016  # the backticks are literal markdown, not an expansion
    printf 'Write `superseded_by: <heir>` in the old file.\n'
    # shellcheck disable=SC2016  # a literal code fence
    printf '```\nsuperseded_by: ghost\n```\n'
  } > "$M/lesson.md"
  run "$C" "$M"
  [ "$status" -eq 0 ]
  [ "$output" = "SUPERSESSION-VERDICT findings=0 files=1" ]
}

@test "unreadable dir is a NON-VERDICT, exit 2, never a zero-finding pass" {
  run "$C" "$BATS_TEST_TMPDIR/no-such-store"
  [ "$status" -eq 2 ]
  [ "$output" = "SUPERSESSION-VERDICT non-verdict reason=unreadable dir=$BATS_TEST_TMPDIR/no-such-store" ]
}

@test "the check never writes: the store is byte-identical after a run with findings" {
  topic old ghost
  printf -- '- [Old](old.md) — x\n' > "$M/MEMORY.md"
  before="$(cat "$M"/*.md | shasum)"
  run "$C" "$M"
  [ "$status" -eq 0 ]
  [ "${lines[2]}" = "SUPERSESSION-VERDICT findings=2 files=1" ]
  [ "$(cat "$M"/*.md | shasum)" = "$before" ]
}

@test "rank 0 of cc-memory-rotate reads the dated form the rule prescribes" {
  topic old 'heir (2026-09-28)'
  # the rotor's own predicate (bin/cc-memory-rotate durability_rank), pinned verbatim by grep
  grep -qF "awk 'NR<=12 && /^[[:space:]]*superseded_by:[[:space:]]*[^[:space:]]/" "$REPO/bin/cc-memory-rotate"
  [ "$(awk 'NR<=12 && /^[[:space:]]*superseded_by:[[:space:]]*[^[:space:]]/ {print "y"; exit}' "$M/old.md")" = y ]
}

@test "the supersession clause is in both CLAUDE variants and in the rendered nudge" {
  for f in "$REPO/CLAUDE.global.md" "$REPO/CLAUDE.global.slim.md"; do
    grep -qF 'CORRECTED (YYYY-MM-DD):' "$f"
    grep -qF 'superseded_by: <heir> (YYYY-MM-DD)' "$f"
    grep -qF 'Replaces: <practice> — ruling pending' "$f"
  done
  grep -qF 'cc-memory-supersession-check <memdir>' "$REPO/commands/compact-memory.md"
  # the nudge as the model receives it: interval 1 fires on every prompt, into hermetic state
  export MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/state" CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  printf -- '- [x](x.md) — y\n' > "$M/MEMORY.md"
  ctx="$(printf '{"session_id":"s-pin","cwd":"/nonexistent-cwd-xyz"}' \
    | MEMORY_NUDGE_INTERVAL=1 MEMORY_INDEX_PATH="$M/MEMORY.md" bash "$REPO/hooks/memory-nudge.sh" \
    | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"dated CORRECTED (YYYY-MM-DD): line"* ]] || false
  [[ "$ctx" == *"superseded_by: <heir> (YYYY-MM-DD)"* ]] || false
  [[ "$ctx" == *"Replaces: <practice> — ruling pending"* ]] || false
}
