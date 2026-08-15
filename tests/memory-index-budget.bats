#!/usr/bin/env bats
# memory-index-budget.sh — the APPEND-TIME CHOKEPOINT for the MEMORY.md loader read limit,
# and its wiring inside the already-live hooks/backup-before-write.sh PreToolUse chain.
#
# The defect this pins: the index is auto-loaded with a hard byte limit (24985 B) past which the
# loader SILENTLY DROPS ITS TAIL — the NEWEST entries. `hooks/memory-nudge.sh` has measured that
# budget correctly since 2026-07-31 and only ADVISES; between 07-25 and 08-06 the index was
# compacted twelve times (every pre-compaction snapshot is still in memory/archive/ with its size in
# the filename) and went back over every time, and the ledger opened FOUR items for one condition.
# Advisory text is exactly what a gate exists to not rely on.
#
# RED-proof coverage: the refusal is SELECTED by arithmetic on the resulting byte size, not asserted;
# the shrink-always-allowed asymmetry is proven from an already-over-limit fixture (a gate that
# refused its own cure would wedge the memory system); the byte measure is pinned by a fixture that
# is UNDER the limit in codepoints and OVER it in bytes, so a `length`-based implementation fails
# here rather than in production; every fail-open path is asserted to allow; and the end-to-end leg
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
  LIMIT=24985
  # shellcheck source=../hooks/lib/memory-index-budget.sh
  . "$LIB"
}

has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { if printf '%s' "$1" | grep -qF -- "$2"; then return 1; fi; }

# An index fixture of exactly $1 bytes, ending in a targetable `TAIL` marker.
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

# ── the LINE cap: the co-equal half of "the first 200 lines or 25KB, whichever comes first" ──
#
# Every fixture above is ONE line, so it can only ever exercise the byte cap — which is exactly how
# the line cap went unenforced. These fixtures invert it: short lines, so the byte cap is nowhere
# near, and the ONLY thing that can refuse them is the line count.

# An index fixture of exactly $1 LINES, each short, ending in a targetable `TAIL` line.
mklines() {
  local lines="$1" name="${2:-lidx}" d f i
  d="$BATS_TEST_TMPDIR/$name/memory"; mkdir -p "$d"; f="$d/MEMORY.md"
  : >"$f"
  i=1
  while [ "$i" -lt "$lines" ]; do
    printf -- '- [T%s](t%s.md) — h\n' "$i" "$i" >>"$f"
    i=$(( i + 1 ))
  done
  printf 'TAIL\n' >>"$f"
  printf '%s' "$f"
}

# tool_input for an Edit that replaces the final TAIL with TAIL plus $2 additional LINES.
edit_addlines() {
  local f="$1" n="$2" add="" i=0
  while [ "$i" -lt "$n" ]; do
    add="$add
- [N$i](n$i.md) — h"
    i=$(( i + 1 ))
  done
  jq -nc --arg f "$f" --arg n "TAIL$add" '{file_path:$f, old_string:"TAIL", new_string:$n}'
}

@test "a write that crosses the LINE cap is REFUSED while the byte cap is nowhere near" {
  # THE DEFECT THIS PINS. Anthropic documents the load as "The first 200 lines or 25KB, whichever
  # comes first"; this gate enforced only the byte half, so a terse index sailed past 200 lines
  # with the loader silently dropping its tail and every measurement in the subsystem reading
  # healthy. RED against the pre-fix gate, which allows this write.
  idx="$(mklines 200 linecap)"
  [ "$(wc -c <"$idx")" -lt 5000 ]                # bytes are not remotely the binding cap
  run mib_verdict Edit "$idx" "$(edit_addlines "$idx" 5)"
  [ "$status" -eq 0 ]                            # 0 = deny
  has "$output" "MEMORY INDEX WRITE REFUSED"
  has "$output" "5 lines over its read limit"
  has "$output" "BYTES ARE NOT THE BINDING CAP HERE"
}

@test "the line boundary is the cap itself: landing exactly ON 200 is allowed, 201 is not" {
  idx="$(mklines 199 lbound)"
  run mib_verdict Edit "$idx" "$(edit_addlines "$idx" 1)"     # → exactly 200 lines
  [ "$status" -eq 1 ]
  run mib_verdict Edit "$idx" "$(edit_addlines "$idx" 2)"     # → 201 lines
  [ "$status" -eq 0 ]
}

@test "the line cap hands over the remedy that can actually move it, not hook-shortening" {
  # Bytes are freed by shortening; LINES are not — a shorter entry is still one line. A refusal
  # that recites the byte remedy here would hand over a lever that provably cannot clear the cap.
  idx="$(mklines 205 lremedy)"
  run mib_verdict Edit "$idx" "$(edit_addlines "$idx" 1)"
  [ "$status" -eq 0 ]
  has "$output" "SHORTENING WILL NOT CLEAR THE LINE CAP"
  has "$output" "ONE-IN-ONE-OUT"
}

@test "an already-OVER-lines index still accepts a LINE-shrinking edit — the cure is never blocked" {
  # The no-wedge asymmetry has to hold on EACH cap separately, not just on whichever one is
  # binding today; otherwise an over-lines index could not be compacted back through this gate.
  idx="$(mklines 260 lshrink)"
  run mib_verdict Edit "$idx" "$(edit_raw "$idx" "- [T1](t1.md) — h
" "")"
  [ "$status" -eq 1 ]
}

@test "a line-NEUTRAL edit on an over-lines index is allowed" {
  idx="$(mklines 260 lneutral)"
  run mib_verdict Edit "$idx" "$(edit_raw "$idx" "TAIL" "LIAT")"
  [ "$status" -eq 1 ]
}

@test "the caps are judged SEPARATELY: growing bytes on an over-lines index is not refused for lines" {
  # A byte-growing, line-neutral write on an index that is already over on LINES must be allowed:
  # it worsens neither cap past its own threshold. Folding the two into one "is the file over?"
  # test would refuse it and wedge exactly the edits that shorten an over-lines index.
  idx="$(mklines 260 lsep)"
  run mib_verdict Edit "$idx" "$(edit_grow "$idx" 100)"
  [ "$status" -eq 1 ]
}

@test "a non-numeric MEMORY_INDEX_LINE_LIMIT allows rather than guessing" {
  idx="$(mklines 260 lbad)"
  MEMORY_INDEX_LINE_LIMIT=abc run mib_verdict Edit "$idx" "$(edit_addlines "$idx" 5)"
  [ "$status" -eq 1 ]
}

@test "the line cap is the same knob memory-nudge.sh and the rotor read, and it is honoured" {
  idx="$(mklines 50 lknob)"
  MEMORY_INDEX_LINE_LIMIT=52 run mib_verdict Edit "$idx" "$(edit_addlines "$idx" 5)"
  [ "$status" -eq 0 ]
  grep -q 'MEMORY_INDEX_LINE_LIMIT:-200' "$REPO/hooks/memory-nudge.sh"
  grep -q 'MEMORY_INDEX_LINE_LIMIT:-200' "$LIB"
  grep -q 'MEMORY_INDEX_LINE_LIMIT:-200' "$REPO/bin/cc-memory-rotate"
}

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

@test "the boundary is the limit itself: landing exactly ON it is allowed, one byte past is not" {
  idx="$(mkindex $(( LIMIT - 10 )))"
  run mib_verdict Edit "$idx" "$(edit_grow "$idx" 10)"     # → exactly LIMIT
  [ "$status" -eq 1 ]
  run mib_verdict Edit "$idx" "$(edit_grow "$idx" 11)"     # → LIMIT + 1
  [ "$status" -eq 0 ]
}

@test "the reason states current, resulting, limit and overage — all four, computed" {
  idx="$(mkindex $(( LIMIT - 50 )))"
  run mib_verdict Edit "$idx" "$(edit_grow "$idx" 100)"
  has "$output" "now $(( LIMIT - 50 )) B"
  has "$output" "after this write $(( LIMIT + 50 )) B"
  has "$output" "limit $LIMIT B"
  has "$output" "50 B over its read limit"
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

# ── BYTES, never codepoints (positive control on the measure itself) ──────────

@test "the measure is UTF-8 BYTES: an append under the limit in characters but over it in bytes is REFUSED" {
  idx="$(mkindex $(( LIMIT - 10 )))"
  # 4 em-dashes = 4 codepoints (→ LIMIT-6, allowed) but 12 bytes (→ LIMIT+2, refused).
  # A jq `length` implementation passes every other test in this file and fails exactly here.
  run mib_verdict Edit "$idx" "$(edit_raw "$idx" "TAIL" "TAIL————")"
  [ "$status" -eq 0 ]
  has "$output" "after this write $(( LIMIT + 2 )) B"
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
  has "$output" "after this write $(( LIMIT + 200 )) B"
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

@test "the limit is the same knob memory-nudge.sh reads, and it is honoured" {
  idx="$(mkindex 5000)"
  MEMORY_INDEX_LIMIT=5050 run mib_verdict Edit "$idx" "$(edit_grow "$idx" 100)"
  [ "$status" -eq 0 ]
  grep -q 'MEMORY_INDEX_LIMIT:-24985' "$REPO/hooks/memory-nudge.sh"
  grep -q 'MEMORY_INDEX_LIMIT:-24985' "$LIB"
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
