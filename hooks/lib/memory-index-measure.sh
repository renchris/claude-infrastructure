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

# mim_entry_limit → the PER-ENTRY cap, in the same loader unit as mim_limit. Not a loader limit:
# the loader has no per-line rule. It is the buffer-line budget the drain path arms on, and it is
# read from here rather than defined at each caller so the detector and the actuator can never
# disagree about which line is oversized. 300 units per the plan's §4.1c derivation.
mim_entry_limit() {
  local v="${MEMORY_ENTRY_LIMIT:-300}"
  case "$v" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$v"
}

# mim_oversized_lines <file> <cap> → one "<lineno><TAB><units>" record per line whose OWN unit
# length exceeds <cap>, or nothing. Non-zero only when the file or jq is unusable.
#
# LINENO IS 0-BASED OVER THE RAW FILE, DELIBERATELY, and that is not an inconsistency with the
# stripping the rest of this file does. The two strip steps remove WHOLE lines (a `--- … ---`
# header, a block `<!-- … -->`), so they change which lines the loader counts but never the unit
# length of a line that survives — and an entry line `- [x](y.md) — hook` can never sit inside
# frontmatter or a block comment. Reporting raw indices is what lets bin/cc-memory-rotate, which
# reads the raw file into an array, address the answer without a second coordinate system.
#
# One jq call for the whole file, not one per candidate: this runs on the PostToolUse path, which
# fires on every tool call in the fleet.
mim_oversized_lines() {
  local f="$1" cap="$2"
  [ -r "$f" ] || return 1
  case "$cap" in ''|*[!0-9]*) return 1 ;; esac
  command -v jq >/dev/null 2>&1 || return 1
  jq -nr --rawfile c "$f" --argjson cap "$cap" "$MIM_JQ_DEFS"'
    ($c | split("\n")) as $L
    | range(0; $L | length) as $i
    | ($L[$i] | mim_units) as $u
    | select($u > $cap)
    | "\($i)\t\($u)"' 2>/dev/null || return 1
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
# ⚠️ THIS QUANTITY IS ALSO THE SIZE OF THE PHANTOM BREACH, AND IT HAS BEEN REPORTED AS ONE THREE
# TIMES. `wc -c` and this file measure the same index in different units, so COMPARING A READING
# FROM ONE AGAINST A READING FROM THE OTHER yields a difference of exactly mim_overhead — and that
# difference reads as either an overage or a day's growth, depending on which way round it is put.
# Measured 2026-08-21 on the claude-infrastructure index (backlog 150c50055e1c, 7c266e16fc94,
# 0b3d53bcd1fd, all three closed on this): raw 25591 B · codepoints 25027 · effective 24287 units
# · mim_overhead 1304. The row read `wc -c` = 25591, called it "chars", compared it to the 25000
# cap and filed "591 over"; it then compared the same 25591 against the advisory hook's correctly
# measured 24287 from that morning and filed "+1304 in one day, so it crossed the cap TODAY". The
# file's mtime had not moved between the two readings. Truth: 713 units UNDER, nothing dropped.
#
# So when a size claim about this index disagrees with the hook, suspect the INSTRUMENT before the
# index, and check the disagreement against mim_overhead first — if it equals this number, there
# is no event. The index's own line 4 already carries the rule ("measure with
# memory-index-measure.sh, never wc -c") and could not prevent this, because that comment is a
# block comment: the loader strips it, and it is 739 of the 740-unit gap it warns about.
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
