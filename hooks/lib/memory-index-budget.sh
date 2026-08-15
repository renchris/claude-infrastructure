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
# The byte cap is a BYTE limit and this index is dense UTF-8: every entry carries `—`, `⇒`, `·`,
# `≠` (3 bytes each). jq's `length` on a string counts CODEPOINTS and would under-measure a typical
# index line by ~10%, which is precisely the margin that decides a breach. `utf8bytelength` is the
# only correct measure and `tests/memory-index-budget.bats` pins it with a fixture that is under the
# limit in characters and over it in bytes.
#
# ── TWO CAPS, AND THE LOADER STOPS AT THE FIRST ONE ──────────────────────────────────────────────
# Anthropic documents the auto-memory load verbatim as "The first 200 lines or 25KB, whichever comes
# first, are loaded into the conversation context" (code.claude.com/docs/en/context-window, Auto
# memory event → /en/memory#auto-memory). This gate enforced ONLY the byte half until 2026-08-15,
# and `commands/compact-memory.md` asserted in its own description that "BYTES bind, not the
# 200-line cap".
#
# That assertion was an observation about ONE index at ONE density promoted to a law. It holds only
# while the mean line is longer than limit/line_limit = 24985/200 = 124 B. The live index sits near
# 244 B/line, so bytes did bind there — but the gate is generic and runs over every project's index,
# and a TERSE one inverts the binding cap: 200 lines at 100 B/line is 20 KB, which is under every
# byte threshold in this subsystem. Nudge, rotor and gate would all have read that index HEALTHY
# while the loader silently dropped everything past line 200 — the exact silent-tail-drop this whole
# subsystem exists to prevent, reached through the door nobody was watching. Density is a property of
# how sessions happen to write, not an invariant, so the cap that binds is not knowable in advance:
# both are enforced, and the breach is the union.
#
# The refusal stays PER-DIMENSION — a write is refused only where it crosses a cap AND makes that
# same dimension worse — so the no-wedge asymmetry above holds separately on each. A pure
# line-reducing write is allowed while the index is over on bytes, and vice versa, which keeps every
# remedy reachable on the cap it is aimed at.

# mib_resulting_metrics <tool_name> <file_path> <tool_input_json>
#   Echoes "<bytes> <lines>" for the file as it would be AFTER this tool call, or nothing when it
#   cannot be determined. Applies the edit literally rather than estimating a delta, so replace_all
#   and MultiEdit are exact instead of approximated — and both caps are read off the SAME applied
#   result, so they can never disagree about what the write produces.
mib_resulting_metrics() {
  local tool="$1" file="$2" input="$3"
  [ -r "$file" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  jq -nr --rawfile cur "$file" --arg tool "$tool" --argjson ti "$input" '
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
    # LINES the way a line READER counts them, which is how the loader takes its "first 200":
    # newline-terminated lines PLUS a final unterminated one. `wc -l` counts newlines and so
    # undercounts a file with no trailing newline by exactly the line the loader still reads.
    def linecount:
      if . == "" then 0
      else (split("\n") | length) - (if endswith("\n") then 1 else 0 end)
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
      else "\($result | utf8bytelength) \($result | linecount)"
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
  local limit line_limit cur_b cur_l new_b new_l metrics
  local over_b over_l over over_lines headline line_remedy

  limit="${MEMORY_INDEX_LIMIT:-24985}"   # 24.4 KiB — the same knob memory-nudge.sh reads
  line_limit="${MEMORY_INDEX_LINE_LIMIT:-200}"   # the co-equal line cap, same knob the nudge reads
  case "$limit" in ''|*[!0-9]*) return 1 ;; esac
  case "$line_limit" in ''|*[!0-9]*) return 1 ;; esac

  mib_is_memory_index "$file" || return 1
  [ -f "$file" ] || return 1

  cur_b=$(wc -c <"$file" 2>/dev/null | tr -d ' ') || return 1
  case "$cur_b" in ''|*[!0-9]*) return 1 ;; esac
  # awk's NR counts a final unterminated line; `wc -l` counts newlines and would not. Same measure
  # as the jq linecount above, so current and resulting are always compared in one unit.
  cur_l=$(LC_ALL=C awk 'END{print NR+0}' "$file" 2>/dev/null) || return 1
  case "$cur_l" in ''|*[!0-9]*) return 1 ;; esac

  metrics=$(mib_resulting_metrics "$tool" "$file" "$input") || return 1
  new_b="${metrics%% *}"; new_l="${metrics##* }"
  case "$new_b" in ''|*[!0-9]*) return 1 ;; esac
  case "$new_l" in ''|*[!0-9]*) return 1 ;; esac

  # PER-DIMENSION breach: a cap is breached only by a write that crosses it AND makes that same
  # dimension worse. Under the cap, or shrinking/neutral on it, is allowed — the clause that keeps
  # every remedy, and every recovery from an already-breached index, reachable through this gate.
  # Evaluating the two separately is what preserves that asymmetry on EACH cap rather than only on
  # whichever one happens to be binding today.
  over_b=0; over_l=0
  if [ "$new_b" -gt "$limit" ] && [ "$new_b" -gt "$cur_b" ]; then over_b=1; fi
  if [ "$new_l" -gt "$line_limit" ] && [ "$new_l" -gt "$cur_l" ]; then over_l=1; fi
  if [ "$over_b" -eq 0 ] && [ "$over_l" -eq 0 ]; then return 1; fi

  over=$(( new_b - limit ))
  over_lines=$(( new_l - line_limit ))
  line_remedy=""
  if [ "$over_b" -eq 1 ]; then
    headline="MEMORY INDEX WRITE REFUSED — this edit would put the auto-loaded index ${over} B over its read limit (now ${cur_b} B; after this write ${new_b} B; limit ${limit} B)."
    if [ "$over_l" -eq 1 ]; then
      headline="$headline The SAME write also crosses the line cap: ${over_lines} lines over (now ${cur_l} lines; after this write ${new_l} lines; limit ${line_limit} lines)."
    fi
  else
    headline="MEMORY INDEX WRITE REFUSED — this edit would put the auto-loaded index ${over_lines} lines over its read limit (now ${cur_l} lines; after this write ${new_l} lines; limit ${line_limit} lines). BYTES ARE NOT THE BINDING CAP HERE — ${new_b} B against ${limit} B is healthy, and the loader stops at whichever cap it reaches first."
  fi
  if [ "$over_l" -eq 1 ]; then
    line_remedy="
SHORTENING WILL NOT CLEAR THE LINE CAP — a shorter entry is still one line. Only removing an entry moves that number, so on this cap ONE-IN-ONE-OUT is not the polite option, it is the only lever.
"
  fi

  printf '%s' "${headline}

Past ${limit} B or ${line_limit} lines — the loader reads \"the first ${line_limit} lines or ${limit} B, WHICHEVER COMES FIRST\" — it SILENTLY DROPS THE TAIL — the NEWEST entries — so the line you are adding would very likely never load again, and no reader could tell. That has already happened; it is why this is a refusal and not another warning.
${line_remedy}
APPLY ONE-IN-ONE-OUT — make room in the SAME edit:
  1. Pick an entry to demote using the DURABILITY criterion (a one-time verdict or a closed incident, NEVER a live rule).
  2. Move that line VERBATIM into ${file%/*}/archive/MEMORY_ARCHIVE_<YEAR>-H<half>-COLD.md — append, never overwrite. The topic .md file stays on disk untouched, so this is reversible: paste the line back to restore it.
  3. Delete only that line from MEMORY.md, then re-apply your addition.

Run /compact-memory for the full procedure; its lossy half (shortening, dedupe) is PROPOSE-ONLY and stays human-gated.

If you file this as backlog work instead of fixing it here, it is ONE standing condition, not a new item per measurement: cc-backlog add --condition memory-index-over-budget --project <project> --title \"<the live size>\". The size belongs in the title; putting it in the key is what minted 21 items for this one condition.

Any write that SHRINKS or does not grow this file — in BYTES for the byte cap, in LINES for the line cap, judged separately — is always allowed, including while it is already over. So compaction, archiving and repair are never blocked by this gate on either cap."
  return 0
}
