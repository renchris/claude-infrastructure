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

# The jq half of "what would this tool call leave on disk". Exported as a string and spliced in
# front of a caller's own program, exactly as MIM_JQ_DEFS is, so the size question and the
# per-entry question apply the SAME edit rather than two lookalike copies of it.
#
# split/1 is a LITERAL split in jq (split/2 is the regex form), so these do a literal
# find-and-replace with no metacharacter surprises from a hook or a code span in the index.
#
#   <current content> | mib_project($tool; $ti)   -> the projected content, or null
# SC2016 is the POINT here, not a slip: these `$old`/`$new`/`$tool`/`$ti` are jq's own
# variables, bound by --arg/--argjson at the call site, and expanding them in the shell
# would substitute the empty string into the program.
# shellcheck disable=SC2034,SC2016
_MIB_JQ_PROJECT='
def apply($old; $new; $all):
  if ($old | length) == 0 then .
  elif $all then (split($old) | join($new))
  else (split($old)) as $p
       | if ($p | length) < 2 then .
         else ($p[0] + $new + ($p[1:] | join($old)))
         end
  end;
def mib_project($tool; $ti):
  . as $cur
  | if $tool == "Write" then
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
    else null end;
'

# mib_resulting_measure <tool_name> <file_path> <tool_input_json>
#   Echoes "<units> <lines>" — the size the loader would check AFTER this tool call — or nothing
#   when it cannot be determined. Applies the edit literally rather than estimating a delta, so
#   replace_all and MultiEdit are exact instead of approximated, and measures the RESULT through
#   the same strip/trim the loader applies.
#
# THE PROJECTION ITSELF is spliced from _MIB_JQ_PROJECT below rather than written inline, because
# this gate now judges the projected content on TWO unrelated questions — how big the whole index
# becomes, and how long its longest ADDED entry line is. Two copies of "apply this edit" would be
# two implementations of the same semantics, and the one that drifted would be the one nobody ran.
mib_resulting_measure() {
  local tool="$1" file="$2" input="$3"
  [ -r "$file" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  jq -nr --rawfile cur "$file" --arg tool "$tool" --argjson ti "$input" \
     "$MIM_JQ_DEFS$_MIB_JQ_PROJECT"'
    ($cur | mib_project($tool; $ti)) as $result
    | if ($result | type) != "string" then empty
      else ($result | mim_effective) as $e | "\($e | mim_units) \($e | mim_lines)"
      end
  ' 2>/dev/null
}

# mib_entry_delta <tool_name> <file_path> <tool_input_json> <cap>
#   ONE tab-separated line, four fields:
#       <longest_added>  the longest entry line this edit ADDS, in loader units; 0 when it adds
#                        none — so a purely shrinking or line-neutral edit reports 0
#       <breach_units>   0 when nothing breaches; else the units of the offending added line
#       <replaced_units> the units of the line that added line REPLACES; 0 = a genuinely NEW line
#       <breach_line>    the offending line itself, or empty
#   Non-zero and silent when the projection cannot be computed (the caller fails OPEN on that).
#
# ── WHY A MULTISET DIFF AND NOT "IS ANY LINE OVER THE CAP" ───────────────────────────────────────
# Every one of reso's 28 entry lines is over the 300-unit cap today (27 are over 400; the SHORTEST
# is 358). A gate that asked "does the result contain an over-cap line" would refuse every write to
# that index forever, and — this is the part that makes it a trap rather than an inconvenience —
# the deny text's own remedy CANNOT clear it: archiving some other entry leaves the offending line
# exactly as long as it was. That is a non-terminating loop, and the only escape from the last one
# was the ungated `Bash >>` door that hooks/memory-index-drain.sh just closed. So the question this
# gate asks is not "is a line over" but "did THIS EDIT make an over-cap line longer".
#
# The answer needs the line an edit REPLACED, and a projected string does not carry that pairing.
# A multiset diff recovers it: cancel the lines the two versions share, and what is left is exactly
# what this edit added and what it removed. Pair them largest-to-largest — the i-th longest added
# line against the i-th longest removed one, 0 when there is nothing at that rank — and refuse only
# where an added line is over the cap AND longer than the line it stands in for.
#
# Largest-to-largest is not a convenience; it is the pairing that cannot be gamed. A plain
# max-vs-max comparison would bless an edit that shortens one 500-unit line to 450 while smuggling
# in a NEW 400-unit line, because 450 < 500 answers for the whole write. Ranked pairwise, that
# second line is compared against rank 1 of the removed set — nothing — and is correctly refused.
#
# ── ENTRY LINES ONLY, AND OVER THE RAW SPLIT ─────────────────────────────────────────────────────
# `- [` anchors the same definition bin/cc-memory-rotate uses for a routable line (ENTRY_RX there,
# `case "$_ln" in "- ["*)` in its drain loop). Matching the actuator matters more than breadth: a
# line this gate refuses but the drain path cannot route is a refusal with no remedy behind it. A
# long header sentence or a prose paragraph is over the per-entry cap by the same arithmetic and is
# not a rule with a home to move to.
#
# Split over the RAW content rather than mim_effective, exactly as mim_oversized_lines does. Both
# strip steps remove WHOLE lines (a `--- … ---` header, a block `<!-- … -->`), and an entry line
# can never sit inside frontmatter or a block comment, so the two agree on every line that exists.
mib_entry_delta() {
  local tool="$1" file="$2" input="$3" cap="$4"
  [ -r "$file" ] || return 1
  case "$cap" in ''|*[!0-9]*) return 1 ;; esac
  command -v jq >/dev/null 2>&1 || return 1

  jq -nr --rawfile cur "$file" --arg tool "$tool" --argjson ti "$input" \
     --argjson cap "$cap" "$MIM_JQ_DEFS$_MIB_JQ_PROJECT"'
    def cmap: reduce .[] as $x ({}; .[$x] = ((.[$x] // 0) + 1));
    def entries: split("\n") | map(select(startswith("- [")));

    ($cur | mib_project($tool; $ti)) as $result
    | if ($result | type) != "string" then empty
      else
        ($cur    | entries | cmap) as $c
      | ($result | entries | cmap) as $n
      | [ $n | to_entries[] | . as $e | range(0; $e.value - ($c[$e.key] // 0)) | $e.key ] as $add
      | [ $c | to_entries[] | . as $e | range(0; $e.value - ($n[$e.key] // 0)) | $e.key ] as $del
      | ($add | map({u: mim_units, l: .}) | sort_by(-.u))          as $A
      | ($del | map(mim_units) | sort | reverse)                   as $R
      | (if ($A | length) == 0 then 0 else $A[0].u end)            as $longest
      | [ range(0; $A | length)
          | select($A[.].u > $cap and $A[.].u > ($R[.] // 0)) ]    as $bad
      | if ($bad | length) == 0 then "\($longest)\t0\t0\t"
        else ($bad[0] as $i | "\($longest)\t\($A[$i].u)\t\($R[$i] // 0)\t\($A[$i].l)")
        end
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
#
# 🚨 NORMALIZE FIRST (2026-09-03). The bare glob below is a match over SPELLINGS, not over files,
# so three ways of naming the very same index SILENTLY SKIPPED the gate while the plain spelling
# denied the identical edit:
#     <dir>/memory/./MEMORY.md     the `/./` breaks the literal `/memory/MEMORY.md` tail
#     <dir>/memory//MEMORY.md      the doubled separator breaks it the same way
#     memory/MEMORY.md             RELATIVE — `*/memory/MEMORY.md` needs a component BEFORE
#                                  `/memory/`, and a leading `*` cannot supply one
# The third is not hypothetical: the observed `Bash >>` appends use a `cd .../memory && … >>`
# relative form, which is exactly the spelling that skips. A denylist over spellings is the defect;
# normalizing the path to one canonical form and matching that is the fix.
#
# RESOLUTION BASE, STATED EXPLICITLY: a relative path is resolved against the CALLER'S $PWD, which
# for a PreToolUse hook is the session cwd. This is pure string normalization on purpose — no
# `readlink -f`, because the file may not exist yet (a first Write creates it) and BSD readlink
# fails on a missing path, which would fail this discriminator OPEN on exactly the create case.
mib_norm_path() {
  local p="$1"
  case "$p" in /*) : ;; *) p="$PWD/$p" ;; esac
  while :; do case "$p" in *//*) p="${p//\/\///}" ;; *) break ;; esac; done
  while :; do case "$p" in */./*) p="${p//\/.\///}" ;; *) break ;; esac; done
  printf '%s' "$p"
}

mib_is_memory_index() {
  case "$(mib_norm_path "$1")" in */memory/MEMORY.md) return 0 ;; *) return 1 ;; esac
}

# mib_verdict <tool_name> <file_path> <tool_input_json>
#   DENY  → prints the reason on stdout, returns 0
#   ALLOW → prints nothing, returns 1   (every fail-open path lands here)
mib_verdict() {
  local tool="$1" file="$2" input="$3"
  local limit line_limit curm newm cur curl new newl over dim
  local entry_limit edelta ebreach ereplaced eline efile eover ewas dest

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
  #
  # THIRD dimension, and it is not a loader cap. `entry` is the per-LINE budget: the index is a
  # buffer whose lines are POINTERS, and a pointer that has grown into a rule is a rule stored
  # behind the only capped door on the machine. It is judged LAST because the two above are silent
  # data loss and this one is curation cadence — a write that breaches a loader cap should be told
  # about that cap, not about line length.
  #
  # Its limit is read HERE rather than beside the other two on purpose. A non-numeric
  # MEMORY_ENTRY_LIMIT must cost this dimension only; failing the whole verdict open over an
  # unreadable third knob would surrender the loader-cap protection that has nothing to do with it.
  dim=""
  if [ "$new" -gt "$limit" ] && [ "$new" -gt "$cur" ]; then
    dim=size
  elif [ "$newl" -gt "$line_limit" ] && [ "$newl" -gt "$curl" ]; then
    dim=lines
  else
    entry_limit=$(mim_entry_limit) || entry_limit=""
    if [ -n "$entry_limit" ]; then
      edelta=$(mib_entry_delta "$tool" "$file" "$input" "$entry_limit") || edelta=""
      if [ -n "$edelta" ]; then
        # Field 1 is longest_added — the delta's negative control, read by the suite and not by
        # the verdict, so it is discarded here rather than bound to a name nothing consults.
        IFS="$(printf '\t')" read -r _ ebreach ereplaced eline <<EOFDELTA
$edelta
EOFDELTA
        case "${ebreach:-0}" in ''|*[!0-9]*) ebreach=0 ;; esac
        [ "$ebreach" -gt 0 ] && dim=entry
      fi
    fi
  fi
  [ -n "$dim" ] || return 1

  # ── dim=entry gets its OWN text, and the ONE-IN-ONE-OUT epilogue below MUST NOT follow it ──────
  # That epilogue ends "Any write that SHRINKS the index … is always allowed", which is TRUE of the
  # two loader caps and FALSE here: shrinking the index does not necessarily shorten its longest
  # line, and the epilogue's remedy — archive some OTHER entry — leaves the offending line exactly
  # as long as it was. Printing it under this dimension would hand the model a remedy that cannot
  # clear the refusal, which is the non-terminating loop this whole dimension is built to avoid.
  if [ "$dim" = entry ]; then
    eover=$(( ebreach - entry_limit ))
    if [ "${ereplaced:-0}" -gt 0 ]; then
      ewas="the line it replaces is ${ereplaced} units, so this edit LENGTHENS it"
    else
      ewas="it is a NEW line, replacing nothing"
    fi
    # Same destination the actuator resolves (bin/cc-memory-rotate route_dest_for / RULES_FILE), in
    # the same precedence, so the remedy this gate prescribes and the file cc-memory-rotate would
    # drain to are never two different files.
    dest="${MEMORY_RULES_FILE:-}"
    if [ -z "$dest" ]; then
      if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
        dest="$CLAUDE_PROJECT_DIR/.claude/rules/agent-operating-lessons.md"
      else
        dest="<project>/.claude/rules/agent-operating-lessons.md"
      fi
    fi
    # The rotor's ENTRY_RX, so "the topic file" names the same file both sides would name.
    #
    # 🚨 IN A VARIABLE, NOT INLINE — and this file learned it the same way cc-memory-rotate did.
    # Written inline, the `\ ` (backslash-space) is accepted by bash 3.2 (the macOS system bash
    # this was authored against) and REJECTED by 5.x, which reports `[[: invalid regular
    # expression … parentheses not balanced` on stderr the caller never sees and evaluates false.
    # Measured 2026-09-05 on 3.2.57 vs 5.3.15 with the identical pattern: inline matched `alpha.md`
    # on 3.2 and matched NOTHING on 5.3, while the hoisted form matched on both. The failure is
    # silent and degrades the operator's deny text to a `<the entry's topic>.md` placeholder — it
    # cannot name the file the writer must edit, on every host whose bash is not 3.2, which is
    # every Linux box in the fleet including the cloud session containers.
    entry_rx='^- \[[^]]*\]\(([A-Za-z0-9][A-Za-z0-9._-]*\.md)\)'
    efile=""
    if [[ "$eline" =~ $entry_rx ]]; then
      efile="${file%/*}/${BASH_REMATCH[1]}"
    else
      efile="${file%/*}/<the entry's topic>.md"
    fi
    printf '%s' "MEMORY INDEX WRITE REFUSED — this edit would push one index line ${eover} unit(s) past the ${entry_limit}-unit per-entry cap (that line would be ${ebreach} units; ${ewas}).

  ${eline}

The index is a BUFFER and its lines are POINTERS. A line this long is a RULE being kept on the one surface the loader caps — ${limit} units and ${line_limit} lines, past which it silently drops the NEWEST entries. The rule's own text belongs in its topic file, and its firing one-liner belongs in the always-loaded project rules file, which the loader does not cap at all.

SHORTEN THE LINE WITHOUT LOSING A WORD — try these in order:
  1. WRITE THE RULE TO THE RULES FILE, keep the hook here. Append it to ${dest} (create it if absent) and leave this index line as a short pointer. That surface is always loaded and has NO ${limit}-unit cap, so nothing goes dark by moving there.
  2. SPLIT IT INTO TWO ENTRIES if the line is carrying two rules — each gets its own topic file and its own index line, and each line is then under the cap.
  3. MOVE THE DETAIL INTO THE TOPIC FILE ${efile} and leave the index line naming it. A topic file is read on demand and has no cap either.

🚨 DO NOT CUT WORDS OUT OF THE LINE TO MAKE IT FIT. Character-truncating an index line is FORBIDDEN — it is R15 in the plan's rejected-approaches table (\"character-truncate index lines\"), rejected on measurement and not on taste: the rule vanished and the index still looked healthy, so no reader could tell. All three remedies above are non-lossy. Truncation is the one that is not.

Lines already over the cap are GRANDFATHERED. An edit that leaves this line no longer than it is now is always allowed — including a correcting clause paid for by words you remove from the same line — and so is any edit that shortens it. The ONLY act refused here is making an already-over line LONGER."
    return 0
  fi

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
