#!/usr/bin/env bash
# memory-index-measure.sh — the ONE place that answers "how big is MEMORY.md as the LOADER sees
# it". Sourced by the gate (hooks/lib/memory-index-budget.sh), the advisory
# (hooks/memory-nudge.sh) and the actuator (bin/cc-memory-rotate), so those three can never
# disagree about whether the index is over budget.
#
# ── WHY THIS FILE EXISTS: RAW BYTES ARE NOT WHAT THE LOADER MEASURES ──────────────────────────
# All three measurers used to read the index with `wc -c` — raw UTF-8 bytes of the file on disk.
# That was right when it was written and is now wrong in three independent directions, every one
# of them an OVER-measure: the gate refuses appends the loader would have accepted, the advisory
# announces a breach that has not happened, and the rotor archives entries that still fit.
#
# Read out of the shipped binary (`strings`/carve of the bundled JS, Claude Code 2.1.233,
# 2026-08-15). The auto-loaded index reaches the prompt through the CLAUDE.md-include path:
# `CHa(<memoryRoot>/MEMORY.md, "AutoMem")` → the include reader, which does, in order:
#
#   1. STRIP YAML FRONTMATTER.  `tf()` matches /^---\s*\n([\s\S]*?)---\s*\n?/ and returns the
#      BODY. Every byte of a `--- … ---` header is gone before anything is counted.
#   2. STRIP BLOCK HTML COMMENTS.  When the body contains `<!--` it is run through the markdown
#      lexer and every block-level `<!-- … -->` token is dropped (residue on the line is kept).
#      Note what this means for us: the `<!-- cold tier: … -->` pointer line cc-memory-rotate
#      writes into the index is FREE — the rotor was budgeting for its own bookkeeping.
#   3. TRIM, then CHECK.  `mCr()` compares the TRIMMED result against two caps and truncates:
#         · 25000  — and it is `String.length`, i.e. UTF-16 CODE UNITS, not bytes. Every slice
#                    in that function is character-indexed (`a.slice(0, 25000)`).
#         · 200    — lines. A cap nothing in this repo enforced before, and the one that binds
#                    FIRST on a dense index of one-line entries.
#      Over either cap the tail is dropped and a `> WARNING:` line is appended in its place.
#
# So the em-dash this index is full of (`—`, `⇒`, `·`, `≠`) costs 3 bytes on disk and ONE unit
# against the cap. The previous header of memory-index-budget.sh argued the exact opposite
# ("BYTES, NEVER CHARACTERS … utf8bytelength is the only correct measure") and pinned it with a
# test. That reasoning was sound for a byte limit; the limit is not one.
#
# Version boundary: the stripping landed in 2.1.211 (cc-backlog 7a56de4c54ab); the numbers above
# are read from 2.1.233. On an older client the effective size is the raw size, and measuring it
# this way UNDER-counts — which is the dangerous direction. That is priced in deliberately: the
# fleet auto-updates, 2.1.211 shipped months before this file, and the alternative is a
# permanent over-measure on every current client.
#
# ── SAFE DIRECTION, AND WHERE WE DELIBERATELY STOP SHORT ──────────────────────────────────────
# Under-stripping over-measures (the gate is stricter than the loader — annoying, never lossy).
# Over-stripping under-measures (the gate blesses an index the loader silently truncates — the
# exact defect the gate exists to prevent). So every approximation here leans to under-strip:
#   · block comments are recognised only at COLUMN 0, never the ` {0,3}` indent CommonMark also
#     allows, and never an inline comment inside a paragraph;
#   · a document containing a ``` fence gets NO comment stripping at all, because a `<!--` inside
#     a fence is code to the lexer and stripping it would under-count.
# Codepoints ≥ U+10000 (emoji) count 2, exactly as UTF-16 does — a `length`-style codepoint count
# would under-measure an index carrying 🚨.
#
# Fail-closed here is fail-OPEN at the caller: every function returns non-zero rather than a
# guess, and each caller's own contract says an unmeasurable index allows.

# The jq half, exported as a string so callers can splice it in front of their own program (the
# gate measures a PROJECTED post-edit string, not a file, so it cannot just call a helper here).
#
#   <content> | mim_effective          → the string the loader actually checks
#   <effective> | mim_units            → its size against the 25000 cap (UTF-16 code units)
#   <effective> | mim_lines            → its size against the 200 cap
# shellcheck disable=SC2034
MIM_JQ_DEFS='
def mim_strip_frontmatter:
  sub("^---\\s*\\n[\\s\\S]*?---\\s*\\n?"; "");
def mim_strip_block_comments:
  if test("```") then .
  else gsub("(?m)^<!--[\\s\\S]*?-->[ \\t]*\\n?"; "")
  end;
def mim_trim:
  sub("^\\s+"; "") | sub("\\s+\\z"; "");
def mim_effective:
  mim_strip_frontmatter | mim_strip_block_comments | mim_trim;
def mim_units:
  if . == "" then 0 else ([explode[] | if . > 65535 then 2 else 1 end] | add) end;
def mim_lines:
  if . == "" then 1 else (split("\n") | length) end;
'

# mim_limit → the UNIT cap (env-overridable, same knob all three callers read). Non-numeric is a
# failure, never a fallback: a caller that cannot read its own limit must not act on a guess.
mim_limit() {
  local v="${MEMORY_INDEX_LIMIT:-25000}"
  case "$v" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$v"
}

# mim_line_limit → the LINE cap.
mim_line_limit() {
  local v="${MEMORY_INDEX_LINE_LIMIT:-200}"
  case "$v" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$v"
}

# mim_measure_file <file> → "<units> <lines>" for the content the loader checks, or non-zero.
mim_measure_file() {
  local out
  [ -r "$1" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  out=$(jq -nr --rawfile c "$1" "$MIM_JQ_DEFS"'
    ($c | mim_effective) as $e | "\($e | mim_units) \($e | mim_lines)"' 2>/dev/null) || return 1
  case "$out" in ''|*[!0-9\ ]*) return 1 ;; esac
  printf '%s' "$out"
}

# mim_effective_file <file> → the effective content itself, for a caller that needs to walk the
# lines the loader will actually see (the advisory's per-entry economics).
mim_effective_file() {
  [ -r "$1" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -nr --rawfile c "$1" "$MIM_JQ_DEFS"'$c | mim_effective' 2>/dev/null || return 1
}

# mim_overhead <file> → raw-bytes-on-disk MINUS effective units, i.e. everything the loader does
# not count: frontmatter, block comments, surrounding whitespace, and the multibyte delta.
#
# This exists for bin/cc-memory-rotate, whose per-line arithmetic is byte-based and internally
# consistent. Rather than convert that arithmetic (and risk a unit-mixed projection), the rotor
# shifts its byte THRESHOLDS up by this constant, which makes every decision effective-sized
# while leaving the accounting alone. The overhead shrinks slightly as lines are removed, so
# holding it fixed over a rotation over-estimates the projected size — it archives a touch more
# than strictly needed, never less.
mim_overhead() {
  local raw m units
  raw=$(wc -c <"$1" 2>/dev/null | tr -d ' ') || return 1
  case "$raw" in ''|*[!0-9]*) return 1 ;; esac
  m=$(mim_measure_file "$1") || return 1
  units="${m%% *}"
  [ "$raw" -ge "$units" ] 2>/dev/null || return 1
  printf '%s' "$(( raw - units ))"
}
