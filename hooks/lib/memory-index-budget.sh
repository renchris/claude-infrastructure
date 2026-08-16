#!/usr/bin/env bash
# memory-index-budget.sh — the APPEND-TIME CHOKEPOINT that turns the MEMORY.md read limit
# from an advisory into an INVARIANT: no tool write may push the index past the byte at
# which the loader starts silently dropping its tail.
#
# ── WHY A GATE AND NOT ANOTHER NUDGE ─────────────────────────────────────────────────────────────
# `hooks/memory-nudge.sh` already MEASURES this exactly right (2026-07-31): it computes the live
# index size, the per-entry prefix cost, the cardinality ceiling, and it hands the model a byte
# budget plus the ONE-IN-ONE-OUT remedy. It is a good measurement and it has not worked. Between
# 2026-07-25 and 2026-08-06 the index was compacted TWELVE times — every pre-compaction snapshot is
# still in `memory/archive/` with its size in the name — and it went back over the limit every time.
# The ledger has now opened FOUR separate items for one condition (f71311d9ad79, b0d889846885,
# efd9cc3c7c6e, 07b0cbf4905a), each closed by another manual pass.
#
# The reason is structural, not motivational. `memory-nudge.sh` fires on UserPromptSubmit, every
# 12th prompt; the append happens inside an Edit tool call, in an arbitrary later turn, in a session
# that may have seen the budget when the index was still healthy — or never seen it at all. A rule
# enforced somewhere other than where the act happens is detection, not a gate
# (MEMORY.md enforcement-must-live-at-the-chokepoint). The chokepoint for "the index grew" is the
# PreToolUse on the write itself, and that is the only place this can be made true by construction.
#
# ── THE INVARIANT, AND WHY IT CANNOT WEDGE ───────────────────────────────────────────────────────
# Exactly one thing is refused: a write whose RESULT exceeds the limit AND is larger than what is
# there now. Every shrinking or size-neutral write is allowed unconditionally, including while the
# index is already over. That asymmetry is the whole safety argument:
#
#   · compaction always works — /compact-memory, the cold-tier move, and any hand repair are
#     net-negative writes, so the gate is transparent to every remedy it asks for;
#   · an over-limit index can never be locked out of being fixed, which is the failure mode a naive
#     "deny all writes over the limit" would create — the gate would refuse its own cure
#     (MEMORY.md deployed-layer-bootstrap-circle);
#   · the ONLY act refused is the one that makes the situation worse, and at that moment the model
#     is holding the content it wanted to add, so ONE-IN-ONE-OUT is a local edit away.
#
# ── FAIL-OPEN IS THE CORRECT DIRECTION HERE ──────────────────────────────────────────────────────
# Every unreadable, unparseable, jq-less, unknown-tool or non-memory path ALLOWS. This is a side-car
# on the memory system; a side-car must never fail wider than itself
# (MEMORY.md addon-failure-exceeds-its-blast-radius). The cost of a false allow is one oversized
# index that the next pass fixes; the cost of a false deny is a session that cannot write memory at
# all. Those are not symmetric, so the default is not a concession — it is the sized one.
#
# ── MEASURE WHAT THE LOADER MEASURES, NOT WHAT THE FILE WEIGHS ───────────────────────────────────
# This section used to read "BYTES, NEVER CHARACTERS — the loader limit is a BYTE limit … jq's
# `length` counts CODEPOINTS and would under-measure … `utf8bytelength` is the only correct
# measure", and a test pinned it with a fixture under the limit in characters and over it in bytes.
# The reasoning was sound; its premise is not. Read out of the shipped binary (2.1.233, 2026-08-15,
# cc-backlog 7a56de4c54ab), the loader strips YAML frontmatter and block HTML comments, trims, and
# then compares `String.length` — UTF-16 CODE UNITS — against 25000, plus a 200-LINE cap this gate
# did not know about at all. So `—` costs 1 against the cap and 3 on disk, a `---` header and the
# rotor's own `<!-- cold tier … -->` pointer cost NOTHING, and a raw-byte read of the file
# over-measures in three independent directions at once.
#
# The whole derivation, the safe-direction argument for each approximation, and the version
# boundary live in hooks/lib/memory-index-measure.sh, which is now the single measurement for this
# gate, hooks/memory-nudge.sh and bin/cc-memory-rotate — three measurers that must never disagree
# about whether the same file is over budget.
_mib_here="${BASH_SOURCE[0]}"
# Deref like backup-before-write.sh's _mib_deref: live, this lib is reached through a per-file
# symlink into the checkout, and an underefed dirname would miss a newly-ADDED sibling until a
# deploy links it — failing open silently while reading as landed (LIVE_ADDS).
if command -v readlink >/dev/null 2>&1; then
  _mib_real="$(readlink -f "$_mib_here" 2>/dev/null || printf '%s' "$_mib_here")"
else
  _mib_real="$_mib_here"
fi
# shellcheck source=/dev/null   # SC1091 suppression: this gate calls shellcheck without -x
. "$(dirname "$_mib_real")/memory-index-measure.sh"
unset _mib_here _mib_real

# mib_resulting_measure <tool_name> <file_path> <tool_input_json>
#   Echoes "<units> <lines>" — the size the loader would check AFTER this tool call — or nothing
#   when it cannot be determined. Applies the edit literally rather than estimating a delta, so
#   replace_all and MultiEdit are exact instead of approximated, and measures the RESULT through
#   the same strip/trim the loader applies.
mib_resulting_measure() {
  local tool="$1" file="$2" input="$3"
  [ -r "$file" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  jq -nr --rawfile cur "$file" --arg tool "$tool" --argjson ti "$input" "$MIM_JQ_DEFS"'
    # split/1 is a LITERAL split in jq (split/2 is the regex form), so these do a literal
    # find-and-replace with no metacharacter surprises from a hook or a code span in the index.
    def apply($old; $new; $all):
      if ($old | length) == 0 then .
      elif $all then (split($old) | join($new))
      else (split($old)) as $p
           | if ($p | length) < 2 then .
             else ($p[0] + $new + ($p[1:] | join($old)))
             end
      end;
    ( if $tool == "Write" then
        $ti.content
      elif $tool == "Edit" then
        ( if ($ti.old_string == null) or ($ti.new_string == null) then null
          else ($cur | apply($ti.old_string; $ti.new_string; ($ti.replace_all // false)))
          end )
      elif $tool == "MultiEdit" then
        ( if ($ti.edits | type) != "array" then null
          else reduce $ti.edits[] as $e ($cur;
                 apply(($e.old_string // ""); ($e.new_string // ""); ($e.replace_all // false)))
          end )
      else null end
    ) as $result
    | if ($result | type) != "string" then empty
      else ($result | mim_effective) as $e | "\($e | mim_units) \($e | mim_lines)"
      end
  ' 2>/dev/null
}

# mib_is_memory_index <file_path>
#   True only for a Claude project-memory index. The auto-loaded file lives at
#   <config-dir>/projects/<slug>/memory/MEMORY.md, and the knowledge-layer mirrors
#   (.claude-secondary … .claude-quaternary) reproduce that shape, so the `/memory/` parent is the
#   discriminator that covers every mirror without enumerating any of them. A repo file that merely
#   happens to be called MEMORY.md is NOT in scope — this gate exists for the loader limit, and a
#   file the loader never reads has no limit to breach.
mib_is_memory_index() {
  case "$1" in */memory/MEMORY.md) return 0 ;; *) return 1 ;; esac
}

# mib_verdict <tool_name> <file_path> <tool_input_json>
#   DENY  → prints the reason on stdout, returns 0
#   ALLOW → prints nothing, returns 1   (every fail-open path lands here)
mib_verdict() {
  local tool="$1" file="$2" input="$3"
  local limit line_limit curm newm cur curl new newl over dim

  # Both caps are the same knobs memory-nudge.sh and cc-memory-rotate read. Either one
  # non-numeric is a fail-open: a gate that cannot read its own limit must not guess one.
  limit=$(mim_limit) || return 1
  line_limit=$(mim_line_limit) || return 1

  mib_is_memory_index "$file" || return 1
  [ -f "$file" ] || return 1

  curm=$(mim_measure_file "$file") || return 1
  cur="${curm%% *}"; curl="${curm##* }"

  newm=$(mib_resulting_measure "$tool" "$file" "$input") || return 1
  case "$newm" in ''|*[!0-9\ ]*) return 1 ;; esac
  new="${newm%% *}"; newl="${newm##* }"
  case "$new$newl" in ''|*[!0-9]*) return 1 ;; esac

  # TWO caps, one asymmetry. The loader truncates on EITHER (units > 25000 OR lines > 200), and
  # on a dense index of one-line entries the LINE cap binds first — so a gate that watched only
  # size would bless an index whose tail is already being dropped. Each cap is judged on its own
  # dimension, and each keeps the shrink clause: under the cap, or not growing THAT dimension, is
  # allowed. That is what keeps every remedy — and every recovery from an already-breached index
  # — reachable through this gate.
  dim=""
  if [ "$new" -gt "$limit" ] && [ "$new" -gt "$cur" ]; then
    dim=size
  elif [ "$newl" -gt "$line_limit" ] && [ "$newl" -gt "$curl" ]; then
    dim=lines
  fi
  [ -n "$dim" ] || return 1

  if [ "$dim" = lines ]; then
    over=$(( newl - line_limit ))
    printf '%s' "MEMORY INDEX WRITE REFUSED — this edit would put the auto-loaded index ${over} line(s) over its read limit (now ${curl} lines; after this write ${newl} lines; limit ${line_limit} lines).

Past ${line_limit} lines the loader SILENTLY DROPS THE TAIL — the NEWEST entries — so the line you are adding would very likely never load again, and no reader could tell. That has already happened; it is why this is a refusal and not another warning.

Note the unit: this is the CARDINALITY cap, not the size one (the index is ${cur}/${limit} chars, so shortening hooks cannot reach it — only removing a line can)."
  else
    over=$(( new - limit ))
    printf '%s' "MEMORY INDEX WRITE REFUSED — this edit would put the auto-loaded index ${over} chars over its read limit (now ${cur} chars; after this write ${new} chars; limit ${limit} chars).

Past ${limit} chars the loader SILENTLY DROPS THE TAIL — the NEWEST entries — so the line you are adding would very likely never load again, and no reader could tell. That has already happened; it is why this is a refusal and not another warning.

Note the unit: the loader counts the index AFTER stripping YAML frontmatter and block HTML comments, and it counts CHARACTERS, not bytes — so ${file##*/} is larger on disk than this figure, and trimming multibyte punctuation buys nothing."
  fi
  printf '%s' "

APPLY ONE-IN-ONE-OUT — make room in the SAME edit:
  1. Pick an entry to demote using the DURABILITY criterion (a one-time verdict or a closed incident, NEVER a live rule).
  2. Move that line VERBATIM into ${file%/*}/archive/MEMORY_ARCHIVE_<YEAR>-H<half>-COLD.md — append, never overwrite. The topic .md file stays on disk untouched, so this is reversible: paste the line back to restore it.
  3. Delete only that line from MEMORY.md, then re-apply your addition.

Run /compact-memory for the full procedure; its lossy half (shortening, dedupe) is PROPOSE-ONLY and stays human-gated.

If you file this as backlog work instead of fixing it here, it is ONE standing condition, not a new item per measurement: cc-backlog add --condition memory-index-over-budget --project <project> --title \"<the live size>\". The size belongs in the title; putting it in the key is what minted 21 items for this one condition.

Any write that SHRINKS the index — or leaves the breached dimension no larger than it already is — is always allowed, including while it is over the limit, so compaction, archiving and repair are never blocked by this gate."
  return 0
}
