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
# ── BYTES, NEVER CHARACTERS ──────────────────────────────────────────────────────────────────────
# The loader limit is a BYTE limit and this index is dense UTF-8: every entry carries `—`, `⇒`, `·`,
# `≠` (3 bytes each). jq's `length` on a string counts CODEPOINTS and would under-measure a typical
# index line by ~10%, which is precisely the margin that decides a breach. `utf8bytelength` is the
# only correct measure and `tests/memory-index-budget.bats` pins it with a fixture that is under the
# limit in characters and over it in bytes.

# mib_resulting_size <tool_name> <file_path> <tool_input_json>
#   Echoes the byte size the file would have AFTER this tool call, or nothing when it cannot be
#   determined. Applies the edit literally rather than estimating a delta, so replace_all and
#   MultiEdit are exact instead of approximated.
mib_resulting_size() {
  local tool="$1" file="$2" input="$3"
  [ -r "$file" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  jq -n --rawfile cur "$file" --arg tool "$tool" --argjson ti "$input" '
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
    | if ($result | type) != "string" then empty else ($result | utf8bytelength) end
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
  local limit cur new over

  limit="${MEMORY_INDEX_LIMIT:-24985}"   # 24.4 KiB — the same knob memory-nudge.sh reads
  case "$limit" in ''|*[!0-9]*) return 1 ;; esac

  mib_is_memory_index "$file" || return 1
  [ -f "$file" ] || return 1

  cur=$(wc -c <"$file" 2>/dev/null | tr -d ' ') || return 1
  case "$cur" in ''|*[!0-9]*) return 1 ;; esac

  new=$(mib_resulting_size "$tool" "$file" "$input") || return 1
  case "$new" in ''|*[!0-9]*) return 1 ;; esac

  # Under the limit, or shrinking/neutral: allowed. The second clause is what keeps every remedy
  # — and every recovery from an already-breached index — reachable through this gate.
  [ "$new" -le "$limit" ] && return 1
  [ "$new" -le "$cur" ] && return 1

  over=$(( new - limit ))
  printf '%s' "MEMORY INDEX WRITE REFUSED — this edit would put the auto-loaded index ${over} B over its read limit (now ${cur} B; after this write ${new} B; limit ${limit} B).

Past ${limit} B the loader SILENTLY DROPS THE TAIL — the NEWEST entries — so the line you are adding would very likely never load again, and no reader could tell. That has already happened; it is why this is a refusal and not another warning.

APPLY ONE-IN-ONE-OUT — make room in the SAME edit:
  1. Pick an entry to demote using the DURABILITY criterion (a one-time verdict or a closed incident, NEVER a live rule).
  2. Move that line VERBATIM into ${file%/*}/archive/MEMORY_ARCHIVE_<YEAR>-H<half>-COLD.md — append, never overwrite. The topic .md file stays on disk untouched, so this is reversible: paste the line back to restore it.
  3. Delete only that line from MEMORY.md, then re-apply your addition.

Run /compact-memory for the full procedure; its lossy half (shortening, dedupe) is PROPOSE-ONLY and stays human-gated.

Any write that SHRINKS or does not grow this file is always allowed, including while it is over the limit — so compaction, archiving and repair are never blocked by this gate."
  return 0
}
