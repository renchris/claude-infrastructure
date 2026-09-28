#!/usr/bin/env bats
# cc-memory-search (TrueMemory #4, docs/research/truememory-2026-09-27.md §3.4) — the derived FTS5
# search substrate. Every case runs against fixture stores under a fixture $HOME, and either passes
# --store/--lessons/--rules (which REPLACE the default scope) or pins the default store through the
# MEMORY_INDEX_PATH seam, so no case reads the operator's real memory.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/bin/cc-memory-search"
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  mkdir -p "$HOME"
  unset CLAUDE_CONFIG_DIR MEMORY_INDEX_PATH CLAUDE_SESSION_ID CC_MEMORY_SEARCH_WEIGHTS
  export CC_IDL="$T/idl.jsonl"
  STATE="$HOME/.claude/state/memory-search.jsonl"
  A="$HOME/.claude/projects/proj-a/memory"
  B="$HOME/.claude/projects/proj-b/memory"
  mkdir -p "$A/archive" "$B" "$T/lessons" "$T/rules"
  printf -- '- [Kitty](kitty-drag-title.md) — index\n' > "$A/MEMORY.md"
  printf -- '- [Pyramid](pyramid-rule.md) — index\n' > "$B/MEMORY.md"
  topic "$A" kitty-drag-title "kitty drag title" "a draggable pane title outranks every other property" project
  topic "$A" drag-handles "drag handles" "resize handles on the kitty border are separate" project
  topic "$A" pgrep-briefs "pgrep briefs" "pgrep -f matches agent briefs" feedback
  topic "$B" pyramid-rule "pyramid rule" "answer first, then the supporting groups" feedback
  topic "$B" narwhal-project "narwhal project" "a project topic only --all may reach" project
  {
    printf '# cold tier\n\n'
    printf -- '- [Cold quagga](gone-quagga.md) — quagga stripes are archived here\n'
    printf -- '- [Kitty hook](kitty-drag-title.md) — zebu wording only the cold hook carries\n'
    printf 'wildebeest prose on a line that is not a link\n'
  } > "$A/archive/MEMORY_ARCHIVE_2026-H2-COLD.md"
  printf -- '- [Snapshot okapi](x.md) — okapi only in a snapshot\n' > "$A/archive/MEMORY_INDEX_PRE-COMPACT_COLD_2026.md"
  printf '# Gate invocation is contract\n\nThe land gate runs shellcheck bare, so read its literal line.\n' > "$T/lessons/gate-invocation.md"
  {
    printf '# rules\n\n'
    printf -- '- [Gate invocation](../lessons/gate-invocation.md) — read the literal command before a check\n'
    # shellcheck disable=SC2016  # the backticks are the literal hook markup, not an expansion
    printf -- '- `tapir-rule.md` — a tapir hook with no link target\n'
  } > "$T/rules/r.md"
}

topic() { # <store> <slug> <name-words> <description> <type> [modified]
  {
    printf -- '---\nname: %s\ndescription: "%s"\nmetadata:\n  type: %s\n' "$2" "$4" "$5"
    [ -z "${6:-}" ] || printf '  modified: %s\n' "$6"
    printf -- '---\n\n# %s\n\nBody text for %s.\n' "$3" "$3"
  } > "$1/$2.md"
}

ms_custom() { "$S" --store "$A" --lessons "$T/lessons" --rules "$T/rules/r.md" "$@"; }
ms_default() { MEMORY_INDEX_PATH="$A/MEMORY.md" "$S" "$@"; }
idl_last() { tail -1 "$CC_IDL" | jq -r "$1"; }
state_last() { tail -1 "$STATE" | jq -r "$1"; }

@test "an exact-title hit ranks first, as a pointer line tagged with its score space" {
  run ms_custom kitty drag title
  [ "$status" -eq 0 ]
  printf '%s\n' "${lines[0]}" | grep -qE '^-[0-9.]+ \[bm25 proj-a\] .*/kitty-drag-title\.md — kitty-drag-title: '
}

@test "stopwords are dropped: an all-stopword query has no terms, and stopwords do not dilute a real one" {
  run ms_custom the and of what
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'no search terms'
  [ "$(idl_last .reason)" = no-terms ]
  run ms_custom what is the pyramid of the kitty
  [ "$status" -eq 0 ]
  printf '%s\n' "${lines[0]}" | grep -q 'kitty-drag-title\.md'
}

@test "the query is injection-safe: quotes, stars, NEAR(, column filters and a leading dash stay terms" {
  local q
  for q in '"kitty' 'kitty*' 'NEAR(kitty drag)' 'title:kitty' 'kitty AND' '-kitty' 'kitty)' "kitty'"; do
    run ms_custom "$q"
    [ "$status" -eq 0 ] || { echo "query <$q> exited $status: $output"; false; }
    printf '%s' "$output" | grep -q 'kitty-drag-title\.md' || { echo "query <$q> lost the hit: $output"; false; }
  done
}

@test "--json prints the contracted keys with score_space bm25" {
  run ms_custom --json kitty
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -c '.[0] | keys')" = '["description","name","path","score","score_space","store"]' ]
  [ "$(printf '%s' "$output" | jq -r '[.[].score_space] | unique | join(",")')" = bm25 ]
  [ "$(printf '%s' "$output" | jq -r '.[0].score | type')" = number ]
}

@test "--all is opt-in for project topics, and labels each hit with its store" {
  run ms_default narwhal
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'narwhal-project' || false
  run ms_default --all narwhal
  [ "$status" -eq 0 ]
  printf '%s\n' "${lines[0]}" | grep -q '\[bm25 proj-b\] .*narwhal-project\.md'
}

@test "cold tier: only '- [' link lines of *COLD* archives, never a PRE-COMPACT snapshot" {
  run ms_custom --json quagga
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[0].store')" = proj-a/cold ]
  [ "$(printf '%s' "$output" | jq -r '.[0].name')" = 'Cold quagga' ]
  # A cold hook whose topic is still in the store is merged into that topic's row, not dropped.
  run ms_custom --json zebu
  [ "$(printf '%s' "$output" | jq -r '[.[].path] | join(",")')" = "$A/kitty-drag-title.md" ]
  run ms_custom okapi
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'bm25' || false
  printf '%s' "$output" | grep -q '^no match'
  run ms_custom wildebeest
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'bm25' || false
}

@test "default scope: a feedback topic in ANOTHER store is found without --all" {
  run ms_default pyramid answer first
  [ "$status" -eq 0 ]
  printf '%s\n' "${lines[0]}" | grep -q '\[bm25 proj-b\] .*pyramid-rule\.md'
}

@test "default scope resolves the store from the cwd slug, as memory-index-locate.sh does" {
  local work="$T/work.dir" slug
  mkdir -p "$work"
  slug="$(cd "$work" && pwd -P | tr '/.' '--')"
  mkdir -p "$HOME/.claude/projects/$slug/memory"
  printf 'x\n' > "$HOME/.claude/projects/$slug/memory/MEMORY.md"
  topic "$HOME/.claude/projects/$slug/memory" okapi-local "okapi local" "only the cwd store has this" project
  run bash -c 'cd "$1" && "$2" okapi' _ "$work" "$S"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'okapi-local\.md'
  [ "$(idl_last .scope)" = project ]
}

@test "rules files give one row per hook bullet; a linked hook folds into its lesson" {
  run ms_custom --json tapir
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[0].path + " " + .[0].store')" = "$T/rules/r.md:4 rules" ]
  # "command" appears only in the rules hook, which links to the lesson file.
  run ms_custom --json command
  [ "$(printf '%s' "$output" | jq -r '[.[].path] | join(",")')" = "$T/lessons/gate-invocation.md" ]
}

@test "over 12 terms the RAREST are kept, so a rare 14th term still finds its file" {
  local c="$T/cap/memory" i common=(alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike)
  mkdir -p "$c"
  for i in 1 2 3 4 5; do topic "$c" "common-$i" "common $i" "${common[*]}" project; done
  topic "$c" rare-target "rare target" "xylophone" project
  run "$S" --store "$c" --top 3 "${common[@]}" xylophone
  [ "$status" -eq 0 ]
  printf '%s\n' "${lines[0]}" | grep -q 'rare-target\.md'
}

@test "--since reads nested metadata.modified, and falls back to the file mtime" {
  local c="$T/since/memory"
  mkdir -p "$c"
  topic "$c" old-gnu "old gnu" "gnu herd" project 2026-01-01T00:00:00Z
  topic "$c" new-gnu "new gnu" "gnu herd" project 2026-09-01T00:00:00Z
  topic "$c" undated-gnu "undated gnu" "gnu herd" project
  touch -t 202001010000 "$c/undated-gnu.md"
  run "$S" --store "$c" --since 2026-06-01 --json gnu
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '[.[].name] | join(",")')" = new-gnu ]
  run "$S" --store "$c" --since 2026-13-45 gnu
  [ "$status" -eq 1 ]
}

@test "a hit writes one fired IDL row and one state row" {
  run env CLAUDE_SESSION_ID=sid-1 "$S" --store "$A" kitty
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CC_IDL" | tr -d ' ')" = 1 ]
  [ "$(idl_last '[.hook,.sid,.disposition,.reason,.scope] | join(" ")')" = 'cc-memory-search sid-1 fired hits custom' ]
  [ "$(idl_last '.hits > 0 and (.dur_ms | type) == "number" and (.ts | test("^[0-9-]+T[0-9:]+Z$"))')" = true ]
  [ "$(state_last '[.terms_n, .hits > 0, (.top_path | endswith(".md")), .scope] | map(tostring) | join(" ")')" = '1 true true custom' ]
}

@test "zero hits log abstained/zero-hit; a raised exception still logs failed from the finally" {
  run ms_custom qwertyuiop
  [ "$status" -eq 0 ]
  [ "$(idl_last '.disposition + " " + .reason')" = 'abstained zero-hit' ]
  run "$S" --store "$T/no-such-store" kitty
  [ "$status" -eq 1 ]
  [ "$(idl_last '.disposition + " " + .reason')" = 'failed exception:FileNotFoundError' ]
  [ "$(state_last .reason)" = 'exception:FileNotFoundError' ]
}

@test "a logging failure changes neither the exit code nor the output" {
  mkdir -p "$T/idl-is-a-dir"
  run env CC_IDL="$T/idl-is-a-dir" "$S" --store "$A" kitty
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'kitty-drag-title\.md'
}

@test "--canary finds each active store's newest topic, exits 0, and writes no IDL row" {
  touch "$B/pyramid-rule.md"
  run "$S" --canary --store "$A" --store "$B"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^CANARY store=proj-b rank=1$'
  printf '%s' "$output" | grep -q '^CANARY-VERDICT ok stores=2 miss=0$'
  [ ! -e "$CC_IDL" ]
  [ "$(state_last .reason)" = canary ]
}

@test "--canary exits 1 with a fail verdict when a newest topic does not come back" {
  topic "$B" zz-newest "of the" "an undiscoverable name" project
  sed -i.bak 's/^name: zz-newest$/name: of-the-and/' "$B/zz-newest.md"
  rm -f "$B/zz-newest.md.bak"
  touch "$B/zz-newest.md"
  run "$S" --canary --store "$B"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q '^CANARY store=proj-b rank=miss$'
  printf '%s' "$output" | grep -q '^CANARY-VERDICT fail stores=1 miss=1$'
}

@test "--stats reports the zero-hit share: unknown under 5, high over 50%, ok otherwise" {
  local now i
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$STATE")"
  row() { printf '{"ts":"%s","terms_n":2,"hits":%s,"top_path":"","scope":"project","reason":"%s","dur_ms":5}\n' "${3:-$now}" "$1" "$2" >> "$STATE"; }
  row 0 zero-hit; row 3 hits
  run "$S" --stats
  printf '%s' "$output" | grep -q '^ZERO-HIT-VERDICT unknown$'
  for i in 1 2 3; do row 0 zero-hit; done
  row 1 canary; row 0 zero-hit 2020-01-01T00:00:00Z
  run "$S" --stats --days 7
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^invocations=5 zero-hit=4 '
  printf '%s' "$output" | grep -q '^ZERO-HIT-VERDICT high$'
  for i in 1 2 3 4; do row 2 hits; done
  run "$S" --stats
  printf '%s' "$output" | grep -q '^ZERO-HIT-VERDICT ok$'
}

@test "CC_MEMORY_SEARCH_WEIGHTS overrides the bm25 column weights; a malformed value warns and falls back" {
  local d w b
  d="$(ms_custom --json kitty drag title | jq -r '.[0].score')"
  w="$(CC_MEMORY_SEARCH_WEIGHTS=1,1,1 ms_custom --json kitty drag title | jq -r '.[0].score')"
  [ "$d" != "$w" ]
  run env CC_MEMORY_SEARCH_WEIGHTS=nope "$S" --store "$A" --json kitty drag title
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'ignoring CC_MEMORY_SEARCH_WEIGHTS'
  b="$(CC_MEMORY_SEARCH_WEIGHTS=nope ms_custom --json kitty drag title 2>/dev/null | jq -r '.[0].score')"
  [ "$b" = "$d" ]
}

@test "both instruction variants name cc-memory-search (four of five roots load the slim one)" {
  grep -q 'run .cc-memory-search <terms>. first' "$REPO/CLAUDE.global.md"
  grep -q 'Run .cc-memory-search <terms>. first' "$REPO/CLAUDE.global.slim.md"
  grep -q 'cc-memory-search --json --top 3' "$REPO/commands/compact-memory.md"
}
