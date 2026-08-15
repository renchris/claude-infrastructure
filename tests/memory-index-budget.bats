#!/usr/bin/env bats
# memory-index-budget.sh — the APPEND-TIME CHOKEPOINT for the MEMORY.md loader read limit,
# and its wiring inside the already-live hooks/backup-before-write.sh PreToolUse chain.
#
# The defect this pins: the index is auto-loaded with hard caps past which the loader SILENTLY
# DROPS ITS TAIL — the NEWEST entries. Two caps, and NEITHER is a byte count (corrected 2026-08-15,
# cc-backlog 7a56de4c54ab, read out of the 2.1.233 bundle): 25000 CHARS and 200 LINES, measured
# after YAML frontmatter and block HTML comments are stripped and the result trimmed. `hooks/memory-nudge.sh` has measured that
# budget correctly since 2026-07-31 and only ADVISES; between 07-25 and 08-06 the index was
# compacted twelve times (every pre-compaction snapshot is still in memory/archive/ with its size in
# the filename) and went back over every time, and the ledger opened FOUR items for one condition.
# Advisory text is exactly what a gate exists to not rely on.
#
# RED-proof coverage: the refusal is SELECTED by arithmetic on the resulting size, not asserted;
# the shrink-always-allowed asymmetry is proven from an already-over-limit fixture (a gate that
# refused its own cure would wedge the memory system); the MEASURE is pinned in all four directions
# it can be got wrong — frontmatter and block comments must NOT count, an em-dash must count ONE
# (a `utf8bytelength` implementation fails here rather than in production) and an astral emoji must
# count TWO (a codepoint `length` implementation fails here); every fail-open path is asserted to allow; and the end-to-end leg
# runs the host hook through a SYMLINK, because a lib the host cannot resolve fails open silently
# and reads as landed while inert (MEMORY.md self-deploying-fix-inert-for-its-own-deploy).
#
# Assertions are simple commands only. bash exempts `[[ ]]` from errexit, so a non-final `[[ ]]` in
# a bats body evaluates and DISCARDS its result — the test passes vacuously
# (scripts/bats-assert-liveness.py).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/memory-index-budget.sh"
  HOOK="$REPO/hooks/backup-before-write.sh"
  # Fixture $HOME: the host hook writes backups under $HOME/.claude/backups, and an unfixtured
  # suite would litter the operator's live config dir.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  LIMIT=25000        # hooks/lib/memory-index-measure.sh mim_limit default, in loader chars
  LINE_LIMIT=200
  # shellcheck source=../hooks/lib/memory-index-budget.sh
  . "$LIB"
}

has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { if printf '%s' "$1" | grep -qF -- "$2"; then return 1; fi; }

# An index fixture of exactly $1 chars (ASCII, so chars == bytes here), ending in a targetable
# `TAIL` marker.
# $2 names the fixture so several can coexist in one test.
mkindex() {
  local bytes="$1" name="${2:-idx}" d f pad
  d="$BATS_TEST_TMPDIR/$name/memory"; mkdir -p "$d"; f="$d/MEMORY.md"
  pad="$(head -c "$(( bytes - 4 ))" /dev/zero | tr '\0' x)"
  printf '%sTAIL' "$pad" >"$f"
  printf '%s' "$f"
}

# tool_input for an Edit that replaces the TAIL marker with TAIL + $2 extra bytes ($2 may be 0 or
# negative-by-construction via edit_raw below).
edit_grow() { jq -nc --arg f "$1" --arg n "TAIL$(head -c "$2" /dev/zero | tr '\0' y)" \
                '{file_path:$f, old_string:"TAIL", new_string:$n}'; }
edit_raw()  { jq -nc --arg f "$1" --arg o "$2" --arg n "$3" \
                '{file_path:$f, old_string:$o, new_string:$n}'; }

# ── the refusal, and that arithmetic selects it ───────────────────────────────

@test "an Edit that would cross the limit is REFUSED" {
  idx="$(mkindex $(( LIMIT - 50 )))"
  run mib_verdict Edit "$idx" "$(edit_grow "$idx" 100)"
  [ "$status" -eq 0 ]                       # 0 = deny
  has "$output" "MEMORY INDEX WRITE REFUSED"
}

@test "an Edit that stays under the limit is ALLOWED" {
  idx="$(mkindex $(( LIMIT - 500 )))"
  run mib_verdict Edit "$idx" "$(edit_grow "$idx" 100)"
  [ "$status" -eq 1 ]                       # 1 = allow
  [ -z "$output" ]
}

@test "the boundary is the limit itself: landing exactly ON it is allowed, one char past is not" {
  idx="$(mkindex $(( LIMIT - 10 )))"
  run mib_verdict Edit "$idx" "$(edit_grow "$idx" 10)"     # → exactly LIMIT
  [ "$status" -eq 1 ]
  run mib_verdict Edit "$idx" "$(edit_grow "$idx" 11)"     # → LIMIT + 1
  [ "$status" -eq 0 ]
}

@test "the reason states current, resulting, limit and overage — all four, computed" {
  idx="$(mkindex $(( LIMIT - 50 )))"
  run mib_verdict Edit "$idx" "$(edit_grow "$idx" 100)"
  has "$output" "now $(( LIMIT - 50 )) chars"
  has "$output" "after this write $(( LIMIT + 50 )) chars"
  has "$output" "limit $LIMIT chars"
  has "$output" "50 chars over its read limit"
}

@test "the reason hands over the ONE-IN-ONE-OUT remedy, not just a complaint" {
  idx="$(mkindex $(( LIMIT - 50 )))"
  run mib_verdict Edit "$idx" "$(edit_grow "$idx" 100)"
  has "$output" "ONE-IN-ONE-OUT"
  has "$output" "DURABILITY criterion"
  has "$output" "MEMORY_ARCHIVE_"
  has "$output" "reversible"
  has "$output" "/compact-memory"
  has "$output" "SILENTLY DROPS THE TAIL"
}

# ── the asymmetry that keeps the gate from wedging its own cure ───────────────

@test "an already-OVER-limit index still accepts a shrinking Write — compaction is never blocked" {
  idx="$(mkindex $(( LIMIT + 3000 )))"
  # The write must land STILL OVER the limit, or this passes on the under-limit rule and proves
  # nothing about the shrink rule it is named for — the real /compact-memory pass is often exactly
  # this shape (a partial reduction that has not yet cleared the cap), and a mutant that deletes the
  # shrink clause left the 900-byte version of this fixture green.
  smaller="$(jq -nc --arg f "$idx" --arg c "$(head -c $(( LIMIT + 1000 )) /dev/zero | tr '\0' z)" \
             '{file_path:$f, content:$c}')"
  run mib_verdict Write "$idx" "$smaller"
  [ "$status" -eq 1 ]
}

@test "an already-OVER-limit index still accepts a shrinking Edit" {
  idx="$(mkindex $(( LIMIT + 3000 )))"
  run mib_verdict Edit "$idx" "$(edit_raw "$idx" "TAIL" "")"
  [ "$status" -eq 1 ]
}

@test "a size-NEUTRAL edit on an over-limit index is allowed" {
  idx="$(mkindex $(( LIMIT + 3000 )))"
  run mib_verdict Edit "$idx" "$(edit_raw "$idx" "TAIL" "LIAT")"
  [ "$status" -eq 1 ]
}

@test "an already-OVER-limit index REFUSES a further-growing edit" {
  idx="$(mkindex $(( LIMIT + 3000 )))"
  run mib_verdict Edit "$idx" "$(edit_grow "$idx" 10)"
  [ "$status" -eq 0 ]
  has "$output" "MEMORY INDEX WRITE REFUSED"
}

# ── the MEASURE: UTF-16 code units of the STRIPPED, TRIMMED content ──────────
#
# Every one of these four fails a plausible wrong implementation, and each wrong implementation
# passes every other test in this file. This block is the whole point of the 2026-08-15 fix.

@test "the measure is CHARS, not bytes: 4 em-dashes cost 4, not 12" {
  idx="$(mkindex $(( LIMIT - 10 )))"
  # 4 em-dashes = 4 UTF-16 units (→ LIMIT-6, ALLOWED) but 12 UTF-8 bytes (→ LIMIT+2). The
  # pre-2026-08-15 `utf8bytelength` gate refused this write; the loader never would have.
  run mib_verdict Edit "$idx" "$(edit_raw "$idx" "TAIL" "TAIL————")"
  [ "$status" -eq 1 ]
  # ...and the same append 7 chars later DOES cross, so this passes on arithmetic, not on a
  # gate that has simply stopped refusing anything.
  idx2="$(mkindex $(( LIMIT - 3 )) idx2)"
  run mib_verdict Edit "$idx2" "$(edit_raw "$idx2" "TAIL" "TAIL————")"
  [ "$status" -eq 0 ]
  has "$output" "after this write $(( LIMIT + 1 )) chars"
}

@test "an astral codepoint costs TWO units, as UTF-16 counts it" {
  idx="$(mkindex $(( LIMIT - 1 )))"
  # One 🚨 = 1 codepoint, 2 UTF-16 units, 4 bytes. A jq `length` (codepoints) implementation
  # lands on the limit and allows; the loader counts 2 and truncates.
  run mib_verdict Edit "$idx" "$(edit_raw "$idx" "TAIL" "TAIL🚨")"
  [ "$status" -eq 0 ]
  has "$output" "after this write $(( LIMIT + 1 )) chars"
}

@test "YAML frontmatter does not count — the loader strips it before measuring" {
  d="$BATS_TEST_TMPDIR/fm/memory"; mkdir -p "$d"; f="$d/MEMORY.md"
  # 300 chars of frontmatter + a body that lands exactly ON the limit. Raw bytes are 300 over.
  { printf -- '---\n'; head -c 293 /dev/zero | tr '\0' k; printf -- '\n---\n'; \
    head -c $(( LIMIT - 4 )) /dev/zero | tr '\0' x; printf 'TAIL'; } >"$f"
  [ "$(wc -c <"$f" | tr -d ' ')" -gt "$LIMIT" ]        # over the limit on disk
  run mib_verdict Edit "$f" "$(edit_grow "$f" 1)"      # body → LIMIT+1: refused on the BODY alone
  [ "$status" -eq 0 ]
  has "$output" "after this write $(( LIMIT + 1 )) chars"
  has "$output" "now $LIMIT chars"                     # the header contributed nothing
}

@test "a block HTML comment does not count — including the rotor's own cold-tier pointer" {
  d="$BATS_TEST_TMPDIR/cm/memory"; mkdir -p "$d"; f="$d/MEMORY.md"
  { printf '<!-- cold tier: archive/MEMORY_ARCHIVE_2026-H2-COLD.md — auto-rotated -->\n\n'; \
    head -c $(( LIMIT - 4 )) /dev/zero | tr '\0' x; printf 'TAIL'; } >"$f"
  run mib_verdict Edit "$f" "$(edit_grow "$f" 1)"
  [ "$status" -eq 0 ]
  has "$output" "now $LIMIT chars"
}

# ── the OTHER cap: 200 lines, which binds first on an index of one-line entries ──

@test "an edit that crosses the 200-LINE cap is REFUSED even though the char budget is fine" {
  d="$BATS_TEST_TMPDIR/lc/memory"; mkdir -p "$d"; f="$d/MEMORY.md"
  for i in $(seq 1 "$LINE_LIMIT"); do printf -- '- [e%s](e%s.md) — h\n' "$i" "$i"; done >"$f"
  run mib_verdict Edit "$f" "$(edit_raw "$f" "- [e1](e1.md) — h" "- [e1](e1.md) — h"$'\n'"- [x](x.md) — h")"
  [ "$status" -eq 0 ]
  has "$output" "1 line(s) over its read limit"
  has "$output" "CARDINALITY cap"
  hasnt "$output" "chars over its read limit"
}

@test "the line cap keeps the same shrink asymmetry — an over-cap index can still be repaired" {
  d="$BATS_TEST_TMPDIR/lc2/memory"; mkdir -p "$d"; f="$d/MEMORY.md"
  for i in $(seq 1 $(( LINE_LIMIT + 40 ))); do printf -- '- [e%s](e%s.md) — h\n' "$i" "$i"; done >"$f"
  run mib_verdict Edit "$f" "$(edit_raw "$f" "- [e1](e1.md) — h"$'\n' "")"   # removes a line
  [ "$status" -eq 1 ]
  run mib_verdict Edit "$f" "$(edit_raw "$f" "- [e1](e1.md) — h" "- [e1](e1.md) — hh")"  # neutral
  [ "$status" -eq 1 ]
}

# ── the edit is APPLIED, not approximated ────────────────────────────────────

@test "replace_all counts every occurrence, not one" {
  d="$BATS_TEST_TMPDIR/ra/memory"; mkdir -p "$d"; f="$d/MEMORY.md"
  # 100 markers; +30 B each under replace_all = +3000 B, which crosses. One occurrence would not.
  { head -c $(( LIMIT - 2500 )) /dev/zero | tr '\0' x; for _ in $(seq 1 100); do printf 'M'; done; } >"$f"
  ti="$(jq -nc --arg f "$f" --arg n "M$(head -c 30 /dev/zero | tr '\0' y)" \
          '{file_path:$f, old_string:"M", new_string:$n, replace_all:true}')"
  run mib_verdict Edit "$f" "$ti"
  [ "$status" -eq 0 ]
  ti1="$(jq -nc --arg f "$f" --arg n "M$(head -c 30 /dev/zero | tr '\0' y)" \
          '{file_path:$f, old_string:"M", new_string:$n}')"
  run mib_verdict Edit "$f" "$ti1"
  [ "$status" -eq 1 ]
}

@test "MultiEdit accumulates its edits sequentially" {
  idx="$(mkindex $(( LIMIT - 50 )))"
  # Two edits of +30 B each = +60 B → crosses. Either one alone would not.
  ti="$(jq -nc --arg f "$idx" \
      --arg a "$(head -c 30 /dev/zero | tr '\0' a)" --arg b "$(head -c 30 /dev/zero | tr '\0' b)" '
      {file_path:$f, edits:[
        {old_string:"TAIL", new_string:("TAIL"+$a)},
        {old_string:"TAIL", new_string:("TAIL"+$b)}]}')"
  run mib_verdict MultiEdit "$idx" "$ti"
  [ "$status" -eq 0 ]
}

@test "a Write is measured from its own content, not from a delta" {
  idx="$(mkindex 100)"
  big="$(jq -nc --arg f "$idx" --arg c "$(head -c $(( LIMIT + 200 )) /dev/zero | tr '\0' z)" \
           '{file_path:$f, content:$c}')"
  run mib_verdict Write "$idx" "$big"
  [ "$status" -eq 0 ]
  has "$output" "after this write $(( LIMIT + 200 )) chars"
}

# ── scope: this gate touches the auto-loaded index and nothing else ───────────

@test "a file that is not MEMORY.md is untouched however large the write" {
  d="$BATS_TEST_TMPDIR/other/memory"; mkdir -p "$d"; f="$d/NOTES.md"; printf 'TAIL' >"$f"
  big="$(jq -nc --arg f "$f" --arg c "$(head -c $(( LIMIT + 5000 )) /dev/zero | tr '\0' z)" \
           '{file_path:$f, content:$c}')"
  run mib_verdict Write "$f" "$big"
  [ "$status" -eq 1 ]
}

@test "a MEMORY.md outside a memory/ dir is not the auto-loaded index and is untouched" {
  d="$BATS_TEST_TMPDIR/repo/docs"; mkdir -p "$d"; f="$d/MEMORY.md"; printf 'TAIL' >"$f"
  big="$(jq -nc --arg f "$f" --arg c "$(head -c $(( LIMIT + 5000 )) /dev/zero | tr '\0' z)" \
           '{file_path:$f, content:$c}')"
  run mib_verdict Write "$f" "$big"
  [ "$status" -eq 1 ]
}

# ── fail-open: a side-car must never fail wider than itself ──────────────────

@test "an absent file allows" {
  run mib_verdict Edit "$BATS_TEST_TMPDIR/nope/memory/MEMORY.md" '{"old_string":"a","new_string":"b"}'
  [ "$status" -eq 1 ]
}

@test "an unknown tool allows" {
  idx="$(mkindex $(( LIMIT + 3000 )))"
  run mib_verdict NotebookEdit "$idx" "$(edit_grow "$idx" 100)"
  [ "$status" -eq 1 ]
}

@test "a malformed tool_input allows" {
  idx="$(mkindex $(( LIMIT - 50 )))"
  run mib_verdict Edit "$idx" '{"old_string":null,"new_string":null}'
  [ "$status" -eq 1 ]
  run mib_verdict MultiEdit "$idx" '{"edits":"not-an-array"}'
  [ "$status" -eq 1 ]
  run mib_verdict Edit "$idx" 'not json at all'
  [ "$status" -eq 1 ]
}

@test "a non-numeric MEMORY_INDEX_LIMIT allows rather than guessing" {
  idx="$(mkindex $(( LIMIT + 3000 )))"
  MEMORY_INDEX_LIMIT=abc run mib_verdict Edit "$idx" "$(edit_grow "$idx" 100)"
  [ "$status" -eq 1 ]
}

@test "the limit is honoured, and its default is spelled in exactly ONE place" {
  idx="$(mkindex 5000)"
  MEMORY_INDEX_LIMIT=5050 run mib_verdict Edit "$idx" "$(edit_grow "$idx" 100)"
  [ "$status" -eq 0 ]
  # SSOT. Before 2026-08-15 the default was re-spelled in the gate, the nudge and the rotor, and
  # a fix to one of the three could silently leave the other two measuring a different index.
  n="$(grep -rc 'MEMORY_INDEX_LIMIT:-' "$REPO/hooks/lib/memory-index-measure.sh")"
  [ "$n" -eq 1 ]
  [ "$(grep -c 'MEMORY_INDEX_LIMIT:-' "$LIB")" -eq 0 ]
  [ "$(grep -c 'MEMORY_INDEX_LIMIT:-' "$REPO/hooks/memory-nudge.sh")" -eq 0 ]
}

# ── end-to-end through the host hook, invoked the way the harness invokes it ──

fire_hook() { # fire_hook <hook-path> <tool> <tool_input-json>
  jq -nc --arg t "$2" --argjson ti "$3" '{tool_name:$t, tool_input:$ti}' | bash "$1"
}

@test "the host hook emits a valid PreToolUse deny for a crossing write" {
  idx="$(mkindex $(( LIMIT - 50 )))"
  run fire_hook "$HOOK" Edit "$(edit_grow "$idx" 100)"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("ONE-IN-ONE-OUT")' >/dev/null
}

@test "the host hook does NOT deny an allowed write" {
  idx="$(mkindex $(( LIMIT - 500 )))"
  run fire_hook "$HOOK" Edit "$(edit_grow "$idx" 100)"
  [ "$status" -eq 0 ]
  hasnt "$output" '"deny"'
}

@test "the host hook resolves its lib THROUGH A SYMLINK — the inert-gate trap" {
  # Live, this hook is ~/.claude/hooks/backup-before-write.sh, a symlink into the checkout, while
  # hooks/lib/ is mirrored PER FILE — so a new lib has no mirror until a deploy runs. Resolution
  # must deref to the checkout, or the gate fails open silently and reads as landed while inert.
  linkdir="$BATS_TEST_TMPDIR/livehooks"; mkdir -p "$linkdir"
  ln -s "$HOOK" "$linkdir/backup-before-write.sh"
  [ ! -e "$linkdir/lib/memory-index-budget.sh" ]        # no mirror beside the symlink
  idx="$(mkindex $(( LIMIT - 50 )))"
  run fire_hook "$linkdir/backup-before-write.sh" Edit "$(edit_grow "$idx" 100)"
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
}
