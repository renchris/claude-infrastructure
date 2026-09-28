#!/usr/bin/env bats
# cc-memory-refs — report-only list of `[[slug]]` wikilinks that name no memory, with near-misses
# (docs/research/truememory-2026-09-27.md §3.13). Every case asserts the RENDERED lines, since the
# lines are the whole product: a human reads them and fixes misspellings by hand.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REFS="$REPO/bin/cc-memory-refs"
  M="$BATS_TEST_TMPDIR/memory"; mkdir -p "$M/archive"
  printf -- '---\nname: good\n---\nbody\n' > "$M/good.md"
  printf -- '---\nname: alias-name\n---\nbody\n' > "$M/topic-file.md"
  printf -- '- [Good](good.md) — index; see [[good]].\n' > "$M/MEMORY.md"
}

@test "a link to a file stem resolves and the store reads clean" {
  run "$REFS" "$M"
  [ "$status" -eq 0 ] || false
  [ "$output" = "REFS-VERDICT broken=0 near_miss=0 files=3" ] || false
}

@test "a link matching only a frontmatter name: resolves" {
  printf 'see [[alias-name]].\n' > "$M/archive/old.md"
  run "$REFS" "$M"
  [ "$status" -eq 0 ] || false
  [ "$output" = "REFS-VERDICT broken=0 near_miss=0 files=4" ] || false
}

@test "a misspelling is listed with its near-miss" {
  printf 'see [[goood]].\n' > "$M/a.md"
  run "$REFS" "$M"
  [ "$status" -eq 0 ] || false
  [ "${lines[0]}" = "[[goood]] — cited in a.md — near-miss: good" ] || false
  [ "${lines[1]}" = "REFS-VERDICT broken=1 near_miss=1 files=4" ] || false
}

@test "a link with no near-miss is listed as a possible placeholder, and archive/ is scanned" {
  printf 'see [[zzqqxx-not-written-yet|alias]].\n' > "$M/archive/b.md"
  run "$REFS" "$M"
  [ "$status" -eq 0 ] || false
  [ "${lines[0]}" = "[[zzqqxx-not-written-yet]] — cited in archive/b.md — no near-miss" ] || false
  [ "${lines[1]}" = "REFS-VERDICT broken=1 near_miss=0 files=4" ] || false
}

@test "wikilinks inside inline code and fenced blocks are quotes, not links" {
  # shellcheck disable=SC2016  # the backticks are markdown inline code, not a substitution
  printf 'the form is `[[name]]`.\n```\n[[also-quoted]]\n```\n' > "$M/c.md"
  run "$REFS" "$M"
  [ "$status" -eq 0 ] || false
  [ "$output" = "REFS-VERDICT broken=0 near_miss=0 files=4" ] || false
}

@test "it never writes: the store is byte-identical after a run" {
  printf 'see [[goood]].\n' > "$M/a.md"
  before="$(find "$M" -type f -exec cksum {} + | sort)"
  run "$REFS" "$M"
  [ "$status" -eq 0 ] || false
  [ "$(find "$M" -type f -exec cksum {} + | sort)" = "$before" ] || false
}

@test "a missing dir exits 2 with no verdict line" {
  run "$REFS" "$BATS_TEST_TMPDIR/no-such-dir"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"not a readable directory: $BATS_TEST_TMPDIR/no-such-dir"* ]] || false
  [[ "$output" != *"REFS-VERDICT"* ]] || false
}

@test "an unreadable dir exits 2, never an empty clean verdict" {
  chmod 000 "$M"
  run "$REFS" "$M"
  chmod 755 "$M"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"could not read $M"* ]] || false
  [[ "$output" != *"REFS-VERDICT"* ]] || false
}
