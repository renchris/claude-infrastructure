#!/usr/bin/env bats
# memory-index-measure.sh — the ONE measurement of "how big is MEMORY.md as the LOADER sees it",
# shared by the PreToolUse gate, the UserPromptSubmit advisory and the cc-memory-rotate actuator.
#
# The defect this pins (cc-backlog 7a56de4c54ab, 2026-08-15): all three measured RAW UTF-8 BYTES
# of the file on disk. Read out of the shipped bundle (2.1.233), the loader instead strips YAML
# frontmatter, strips block HTML comments, trims, and compares UTF-16 CODE UNITS against 25000
# plus a 200-LINE cap nothing here enforced. Every one of those four differences over-measures,
# so the gate refused appends the loader would take, the advisory announced breaches that had not
# happened, and the rotor archived entries that still fit.
#
# RED-proof coverage: each cap and each strip is asserted with a fixture whose RAW size and
# EFFECTIVE size are on OPPOSITE sides of the boundary, so a `wc -c`, a `utf8bytelength` and a
# codepoint `length` implementation each fail here rather than in production; the two
# deliberately-narrow approximations (column-0 comments only, no stripping inside a code fence)
# are pinned in the UNDER-strip direction, because under-stripping over-measures — annoying —
# while over-stripping blesses an index the loader silently truncates.
#
# Assertions are simple commands only. bash exempts `[[ ]]` from errexit, so a non-final `[[ ]]`
# in a bats body evaluates and DISCARDS its result (scripts/bats-assert-liveness.py).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/memory-index-measure.sh"
  # Fixture $HOME. Nothing in this subject reads it today — every fixture below lives under
  # $BATS_TEST_TMPDIR — but an unfixtured suite is one edit away from touching the operator's
  # live ~/, and the ratchet refuses the shape rather than the incident.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # shellcheck source=/dev/null
  . "$LIB"
}

# write <name> <content…> → path; content is passed to printf so \n works.
# shellcheck disable=SC2059  # the format string IS the argument: these fixtures are written as
# printf formats so \n, \t and \xNN escapes produce the bytes the loader would actually read.
write() { local f="$BATS_TEST_TMPDIR/$1"; shift; printf "$@" >"$f"; printf '%s' "$f"; }
units() { local m; m="$(mim_measure_file "$1")"; printf '%s' "${m%% *}"; }
lines() { local m; m="$(mim_measure_file "$1")"; printf '%s' "${m##* }"; }
raw()   { wc -c <"$1" | tr -d ' '; }

# ── the unit: UTF-16 code units, not bytes and not codepoints ────────────────

@test "an em-dash costs ONE unit and THREE bytes — a byte measure fails here" {
  f="$(write emdash 'a—b')"
  [ "$(raw "$f")" -eq 5 ]
  [ "$(units "$f")" -eq 3 ]
}

@test "an astral codepoint costs TWO units — a codepoint measure fails here" {
  f="$(write astral 'a\xF0\x9F\x9A\xA8b')"     # a🚨b
  [ "$(raw "$f")" -eq 6 ]
  [ "$(units "$f")" -eq 4 ]
}

# ── the strips: what the loader removes before it measures ───────────────────

@test "YAML frontmatter is stripped, exactly as the loader's own regex does" {
  f="$(write fm -- '---\nname: idx\ntype: reference\n---\nbody\n')"
  [ "$(units "$f")" -eq 4 ]                    # "body" — the header contributed nothing
  [ "$(raw "$f")" -gt 30 ]
}

@test "an UNTERMINATED frontmatter block is NOT stripped — the loader's regex needs the close" {
  f="$(write fmopen -- '---\nname: idx\nbody\n')"
  [ "$(units "$f")" -eq 18 ]                   # the whole thing, trimmed
}

@test "a block HTML comment is stripped, including the rotor's own cold-tier pointer" {
  f="$(write cmt '<!-- cold tier: archive/MEMORY_ARCHIVE_2026-H2-COLD.md -->\nbody\n')"
  [ "$(units "$f")" -eq 4 ]
}

@test "a MULTI-LINE block comment is stripped whole" {
  f="$(write cmt2 '<!-- line one\nline two\nline three -->\nbody\n')"
  [ "$(units "$f")" -eq 4 ]
}

@test "text after the closing --> survives — the loader keeps the residue" {
  f="$(write resid '<!-- c --> tail\n')"
  [ "$(units "$f")" -eq 4 ]                    # "tail"
}

# ── the two deliberate under-strips (safe direction: over-measure, never under) ──

@test "a comment INSIDE a code fence is not stripped — stripping it would UNDER-measure" {
  f="$(write fence '```\n<!-- kept -->\n```\nbody\n')"
  [ "$(units "$f")" -gt 10 ]
}

@test "an INDENTED comment is not stripped — column 0 only, by choice" {
  f="$(write indent '   <!-- kept -->\nbody\n')"
  [ "$(units "$f")" -gt 10 ]
}

# ── trim, line count, and the caps themselves ────────────────────────────────

@test "surrounding whitespace is trimmed before anything is counted" {
  f="$(write trim '\n\n  body  \n\n\n')"
  [ "$(units "$f")" -eq 4 ]
  [ "$(lines "$f")" -eq 1 ]
}

@test "lines are counted on the TRIMMED content, so a trailing newline is not a line" {
  f="$(write nl 'a\nb\n')"
  [ "$(lines "$f")" -eq 2 ]
}

@test "an empty index measures 0 units and 1 line, never an error" {
  f="$(write empty '')"
  [ "$(units "$f")" -eq 0 ]
  [ "$(lines "$f")" -eq 1 ]
}

@test "the caps are the loader's, and both are env-overridable knobs" {
  [ "$(mim_limit)" -eq 25000 ]
  [ "$(mim_line_limit)" -eq 200 ]
  MEMORY_INDEX_LIMIT=123 run mim_limit
  [ "$output" = "123" ]
  MEMORY_INDEX_LINE_LIMIT=7 run mim_line_limit
  [ "$output" = "7" ]
}

@test "a non-numeric cap FAILS rather than falling back to a guess" {
  MEMORY_INDEX_LIMIT=abc run mim_limit
  [ "$status" -ne 0 ]
  MEMORY_INDEX_LINE_LIMIT=-5 run mim_line_limit
  [ "$status" -ne 0 ]
}

# ── the overhead reading cc-memory-rotate shifts its byte thresholds by ──────

@test "overhead is exactly what the loader does not count" {
  f="$(write ovh -- '---\nk: v\n---\n<!-- c -->\n- [a](a.md) — h\n')"
  [ "$(mim_overhead "$f")" -eq "$(( $(raw "$f") - $(units "$f") ))" ]
  [ "$(mim_overhead "$f")" -gt 0 ]
}

# ── fail-closed here is fail-OPEN at the caller ──────────────────────────────

@test "an unreadable path returns non-zero rather than a number the caller would act on" {
  run mim_measure_file "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$status" -ne 0 ]
  run mim_overhead "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$status" -ne 0 ]
}

# ── the jq half is usable by a caller measuring a PROJECTED string, not a file ──

@test "MIM_JQ_DEFS composes into a caller's own program — the gate's actual use" {
  got="$(jq -nr --arg s '---
k: v
---
<!-- c -->
a—b
' "$MIM_JQ_DEFS"'($s | mim_effective) as $e | "\($e | mim_units) \($e | mim_lines)"')"
  [ "$got" = "3 1" ]
}
