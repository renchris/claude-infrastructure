#!/usr/bin/env bats
# Routing to the UNCAPPED surface — cc-memory-rotate's rules-file destination, its hard/soft
# ceilings, and the operator-voice veto on the path that did not exist before.
#
# WHAT THIS PINS, AND WHY EACH ONE NEEDS ITS OPPOSITE ARM.
#
#   · THE HARD CAP. The loader SKIPS a rules file at/over 4 MiB — it does not truncate, the file
#     VANISHES — so an append that crosses it is total, silent loss. The guard is judged on the
#     PROJECTION, not the current size, because a destination one byte under the cap is exactly
#     the case a current-size check waves through. Both directions are pinned on one fixture:
#     over ⇒ exit 2 with the index byte-identical, under ⇒ drained. A test that only asserted
#     the refusal would pass on a rotor that refused everything.
#     ⚠️ THE 4 MiB CONSTANT IS ENCODED, NOT MEASURED — see bin/cc-memory-rotate's own note. The
#     suite therefore drives the guard through MEMORY_RULES_HARD_CAP and asserts the MECHANISM,
#     never the number: if the true ceiling turns out to be elsewhere, these tests still hold.
#
#   · THE WARN CAP is a different KIND of thing and conflating them would be the defect: the
#     40,000-char figure is a cosmetic startup warning that truncates nothing. So it must WARN
#     AND WRITE, and the control is the same fixture under a high warn cap writing SILENTLY.
#
#   · THE VETO ON THE NEW PATH. route_veto is the operator's voice, and a protection implemented
#     downstream of the predicate that bypasses it is not a protection. The pairs here differ in
#     exactly ONE property — the frontmatter `type:` stamp, the name prefix, the PINNED token —
#     so a green "vetoed" arm cannot be a rotation that simply did nothing.
#
#   · VERBATIM means a diff, not an eyeball: the routed line is compared byte-for-byte and then
#     pasted back to reconstruct the original index exactly.
#
# Assertions are simple commands only. bash exempts `[[ ]]` from errexit, so a non-final `[[ ]]`
# in a bats body evaluates and DISCARDS its result — the test passes vacuously
# (scripts/bats-assert-liveness.py).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO/bin/cc-memory-rotate"
  T="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export HOME="$T/home"; mkdir -p "$HOME"
  export MEMORY_INDEX_LIMIT=3000
  export MEMORY_ROTATE_AT=1500
  export MEMORY_ROTATE_TARGET=1000
  export MEMORY_ROTATE_MIN_KEEP=2
  export MEMORY_ROTATE_TAIL_GUARD=1
  export MEMORY_ROTATE_MIN_AGE_DAYS=7
  unset MEMORY_RULES_FILE CLAUDE_PROJECT_DIR MEMORY_RULES_HARD_CAP MEMORY_RULES_WARN_CAP || true
  OLD=202601011200
}

has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { if printf '%s' "$1" | grep -qF -- "$2"; then return 1; fi; }
pad()   { head -c "$1" /dev/zero | tr '\0' x; }

mkmem() {
  local d="$T/$1/memory"
  mkdir -p "$d"
  printf '# Memory — fixture\n' >"$d/MEMORY.md"
  printf '%s' "$d"
}

# addentry <memdir> <file> <type> <old|young> <hook> [extra-frontmatter-line]
addentry() {
  local d="$1" f="$2" t="$3" age="$4" hook="$5" extra="${6:-}" nm="${2%.md}"
  printf -- '- [%s](%s) — %s\n' "$nm" "$f" "$hook" >>"$d/MEMORY.md"
  {
    printf -- '---\nname: %s\ndescription: d\n' "$nm"
    [ -n "$extra" ] && printf -- '%s\n' "$extra"
    printf -- 'metadata:\n  type: %s\n---\nbody\n' "$t"
  } >"$d/$f"
  if [ "$age" = old ]; then touch -t "$OLD" "$d/$f"; fi
}

# Ten old, eligible, project-typed entries: over ROTATE_AT, several moves needed to reach TARGET.
mkbulk() {
  local d="$1" i
  for i in 01 02 03 04 05 06 07 08 09 10; do
    addentry "$d" "a$i.md" project old "$(pad 140)"
  done
}

dest_path() { mkdir -p "$T/proj/.claude/rules"; printf '%s' "$T/proj/.claude/rules/agent-operating-lessons.md"; }

# A single over-cap entry for the drain path (the per-entry condition, independent of the
# whole-index thresholds), plus one small entry so the index is not a single line.
mkover() {
  local d
  d="$(mkmem "$1")"
  addentry "$d" small.md project old "tiny"
  addentry "$d" fat.md project old "$(pad 700)"
  printf '%s' "$d"
}

# ── The routing MOVE on ordinary rotation ───────────────────────────────────────────────────

@test "1 rotation ROUTES eligible entries to the always-loaded rules file, not to the cold record" {
  d="$(mkmem route1)"; mkbulk "$d"; dest="$(dest_path)"
  first="$(grep -F '(a01.md)' "$d/MEMORY.md")"
  run "$SCRIPT" "$d/MEMORY.md" --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  hasnt "$output" 'routed=0'
  has "$output" "dest=$dest"
  # BYTE-EQUAL, whole line, in the destination — and NOWHERE in a cold record.
  grep -qxF -- "$first" "$dest"
  hasnt "$(cat "$d/MEMORY.md")" '](a01.md)'
  [ ! -f "$d/archive/MEMORY_ARCHIVE_2026-H2-COLD.md" ]
  [ ! -f "$d/archive/MEMORY_ARCHIVE_2026-H1-COLD.md" ]
  has "$output" 'cold=-'          # and the verdict does not name a cold file that was never written
}

@test "2 CONTROL — with no destination resolvable the same fixture goes COLD, and says so" {
  # The opposite arm of test 1 on an identical fixture: the ONLY difference is that no rules
  # file can be resolved. Without this, "routed" could be an artifact of the fixture rather
  # than of the destination, and the legacy cold path could have silently died.
  d="$(mkmem route2)"; mkbulk "$d"
  first="$(grep -F '(a01.md)' "$d/MEMORY.md")"
  run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  has "$output" 'routed=0'
  has "$output" 'route=no-rules-destination'
  cold="$(ls "$d"/archive/MEMORY_ARCHIVE_*-COLD.md)"
  grep -qxF -- "$first" "$cold"
}

@test "3 a routed line is VERBATIM and RECOVERABLE — pasting it back reconstructs the index" {
  d="$(mkmem verb)"; mkbulk "$d"; dest="$(dest_path)"
  cp "$d/MEMORY.md" "$T/verb.before"
  run "$SCRIPT" "$d/MEMORY.md" --rules-file "$dest"
  has "$output" 'verdict=rotated'
  # Rebuild the original from the destination's own lines, in the order they left.
  cp "$d/MEMORY.md" "$T/verb.rebuilt"
  grep '^- \[a' "$dest" >"$T/verb.moved"
  { head -1 "$T/verb.rebuilt"; cat "$T/verb.moved"; tail -n +2 "$T/verb.rebuilt"; } >"$T/verb.out"
  run diff -u "$T/verb.before" "$T/verb.out"
  [ "$status" -eq 0 ]
}

@test "4 the cold-tier pointer is NOT written when nothing went cold" {
  # A pointer naming archive/MEMORY_ARCHIVE_*-COLD.md when this rotation created no such file
  # is a dangling pointer written into the always-loaded index.
  d="$(mkmem ptr1)"; mkbulk "$d"; dest="$(dest_path)"
  run "$SCRIPT" "$d/MEMORY.md" --rules-file "$dest"
  has "$output" 'verdict=rotated'
  hasnt "$(cat "$d/MEMORY.md")" 'archive/MEMORY_ARCHIVE'
}

@test "5 CONTROL — the pointer IS written when the cold record was used" {
  d="$(mkmem ptr2)"; mkbulk "$d"
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  grep -qF 'archive/MEMORY_ARCHIVE' "$d/MEMORY.md"
}

# ── route_veto on the NEW path ──────────────────────────────────────────────────────────────

@test "6 a frontmatter type: entry that stage 2 evicts is still VETOED from routing" {
  # At breach the unprefixed `type: feedback` stamp yields to EVICTION (two-stage pressure), and
  # route_veto has no stages — so those lines take the cold path and the rules file is untouched.
  d="$(mkmem veto1)"; dest="$(dest_path)"
  local i
  for i in $(seq -w 1 25); do addentry "$d" "lesson$i.md" feedback old "$(pad 120)"; done
  # Well clear of the LIMIT: the rotor shifts its thresholds by the loader-vs-disk overhead, so a
  # fixture sized to 3041 B sits UNDER the shifted 3000-char cap and stage 2 never arms — which
  # would make this test green for the wrong reason (exhausted, not vetoed).
  [ "$(wc -c <"$d/MEMORY.md" | tr -d ' ')" -ge 3600 ]
  run "$SCRIPT" "$d/MEMORY.md" --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  has "$output" 'routed=0'
  cold="$(ls "$d"/archive/MEMORY_ARCHIVE_*-COLD.md)"
  grep -qF -- '(lesson01.md)' "$cold"
  [ ! -f "$dest" ]
}

@test "7 CONTROL — the SAME fixture with a project type routes, so the veto is what bound test 6" {
  d="$(mkmem veto2)"; dest="$(dest_path)"
  local i
  for i in $(seq -w 1 25); do addentry "$d" "lesson$i.md" project old "$(pad 120)"; done
  [ "$(wc -c <"$d/MEMORY.md" | tr -d ' ')" -ge 3600 ]
  run "$SCRIPT" "$d/MEMORY.md" --rules-file "$dest"
  has "$output" 'verdict=rotated'
  hasnt "$output" 'routed=0'
  grep -qF -- '(lesson01.md)' "$dest"
}

@test "8 feedback-/user- names and PINNED are never routed and never leave the index" {
  d="$(mkmem veto3)"; dest="$(dest_path)"
  addentry "$d" feedback-real.md project old "operator directive $(pad 110)"
  addentry "$d" user-who.md project old "who they are $(pad 110)"
  addentry "$d" keepme.md project old "PINNED $(pad 110)"
  mkbulk "$d"
  run "$SCRIPT" "$d/MEMORY.md" --rules-file "$dest"
  has "$output" 'verdict=rotated'
  grep -qF -- '(feedback-real.md)' "$d/MEMORY.md"
  grep -qF -- '(user-who.md)' "$d/MEMORY.md"
  grep -qF -- '(keepme.md)' "$d/MEMORY.md"
  hasnt "$(cat "$dest")" '(feedback-real.md)'
  hasnt "$(cat "$dest")" '(user-who.md)'
  hasnt "$(cat "$dest")" '(keepme.md)'
}

# ── The HARD cap: fails closed, in both directions ──────────────────────────────────────────

@test "9 a destination AT the hard cap is REFUSED and the index is byte-identical" {
  d="$(mkover cap1)"; dest="$(dest_path)"
  head -c 4000 /dev/zero | tr '\0' z >"$dest"
  cp "$d/MEMORY.md" "$T/cap1.before"
  run env MEMORY_RULES_HARD_CAP=4000 MEMORY_ENTRY_LIMIT=300 \
      "$SCRIPT" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 2 ]
  has "$output" 'reason=dest-over-hard-cap'
  has "$output" 'hard_cap=4000'
  cmp -s "$d/MEMORY.md" "$T/cap1.before"
  [ "$(wc -c <"$dest" | tr -d ' ')" -eq 4000 ]
}

@test "10 a destination UNDER the cap whose append would CROSS it is refused too" {
  # The projection, not the current size, is the subject. A current-size check passes this.
  d="$(mkover cap2)"; dest="$(dest_path)"
  head -c 3900 /dev/zero | tr '\0' z >"$dest"
  cp "$d/MEMORY.md" "$T/cap2.before"
  run env MEMORY_RULES_HARD_CAP=4000 MEMORY_ENTRY_LIMIT=300 \
      "$SCRIPT" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 2 ]
  has "$output" 'reason=dest-over-hard-cap'
  cmp -s "$d/MEMORY.md" "$T/cap2.before"
  [ "$(wc -c <"$dest" | tr -d ' ')" -eq 3900 ]
}

@test "11 CONTROL — the same append against a destination that stays under the cap is ACCEPTED" {
  d="$(mkover cap3)"; dest="$(dest_path)"
  head -c 100 /dev/zero | tr '\0' z >"$dest"
  fat="$(grep -F '(fat.md)' "$d/MEMORY.md")"
  run env MEMORY_RULES_HARD_CAP=4000 MEMORY_ENTRY_LIMIT=300 \
      "$SCRIPT" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=drained'
  grep -qxF -- "$fat" "$dest"
}

@test "12 the hard cap degrades ordinary rotation to COLD instead of failing the rotation" {
  # Rotation is the actuator that holds the LOADER cap, past which the newest entries are
  # dropped. Refusing to rotate because the destination is full would trade a recoverable
  # surface change for live, silent loss — so it falls back, and PRINTS why.
  d="$(mkmem cap4)"; mkbulk "$d"; dest="$(dest_path)"
  head -c 4000 /dev/zero | tr '\0' z >"$dest"
  run env MEMORY_RULES_HARD_CAP=4000 "$SCRIPT" "$d/MEMORY.md" --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  has "$output" 'routed=0'
  has "$output" 'route=dest-over-hard-cap'
  cold="$(ls "$d"/archive/MEMORY_ARCHIVE_*-COLD.md)"
  grep -qF -- '(a01.md)' "$cold"
  [ "$(wc -c <"$dest" | tr -d ' ')" -eq 4000 ]
}

# ── The WARN cap: a different KIND of ceiling ───────────────────────────────────────────────

@test "13 a destination over the WARN cap warns and STILL WRITES" {
  d="$(mkover warn1)"; dest="$(dest_path)"
  head -c 600 /dev/zero | tr '\0' z >"$dest"
  fat="$(grep -F '(fat.md)' "$d/MEMORY.md")"
  run env MEMORY_RULES_WARN_CAP=500 MEMORY_ENTRY_LIMIT=300 \
      "$SCRIPT" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=drained'
  has "$output" 'warn=dest-over-warn-cap'
  grep -qxF -- "$fat" "$dest"
}

@test "14 CONTROL — under the warn cap the same write is SILENT" {
  d="$(mkover warn2)"; dest="$(dest_path)"
  head -c 600 /dev/zero | tr '\0' z >"$dest"
  run env MEMORY_RULES_WARN_CAP=1000000 MEMORY_ENTRY_LIMIT=300 \
      "$SCRIPT" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=drained'
  hasnt "$output" 'warn=dest-over-warn-cap'
}

# ── Volunteered `paths:` scoping — the optional half, and its default ────────────────────────

@test "15 a topic that VOLUNTEERS paths: routes to a scoped sibling carrying that paths: value" {
  d="$(mkmem scope1)"; dest="$(dest_path)"
  addentry "$d" small.md project old "tiny"
  addentry "$d" scoped.md project old "$(pad 700)" 'paths: ["src/**/*.ts"]'
  line="$(grep -F '(scoped.md)' "$d/MEMORY.md")"
  run env MEMORY_ENTRY_LIMIT=300 "$SCRIPT" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=drained'
  scoped="${dest%/*}/scoped-scoped.md"
  grep -qxF -- "$line" "$scoped"
  grep -qF 'paths: ["src/**/*.ts"]' "$scoped"
  [ ! -f "$dest" ]
}

@test "16 CONTROL — the same entry WITHOUT paths: goes to the always-loaded default" {
  # Default is always-loaded, unconditionally: nothing here infers a scope, so the ONLY
  # difference between this and test 15 is the line the author volunteered.
  d="$(mkmem scope2)"; dest="$(dest_path)"
  addentry "$d" small.md project old "tiny"
  addentry "$d" scoped.md project old "$(pad 700)"
  line="$(grep -F '(scoped.md)' "$d/MEMORY.md")"
  run env MEMORY_ENTRY_LIMIT=300 "$SCRIPT" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  grep -qxF -- "$line" "$dest"
  [ ! -f "${dest%/*}/scoped-scoped.md" ]
}

# ── NEGATIVE CONTROL: a file that is not a loader-read index ─────────────────────────────────

@test "17 a non-index file is refused and no destination is created" {
  mkdir -p "$T/notes"; dest="$(dest_path)"
  printf -- '- [x](x.md) — %s\n' "$(pad 700)" >"$T/notes/MEMORY.md"
  cp "$T/notes/MEMORY.md" "$T/notes.before"
  run env MEMORY_ENTRY_LIMIT=300 "$SCRIPT" "$T/notes/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 2 ]
  has "$output" 'reason=not-a-memory-index'
  cmp -s "$T/notes/MEMORY.md" "$T/notes.before"
  [ ! -f "$dest" ]
}

@test "18 the destination is resolved from CLAUDE_PROJECT_DIR when no flag is given" {
  d="$(mkmem envdest)"; mkbulk "$d"
  mkdir -p "$T/envproj"
  run env CLAUDE_PROJECT_DIR="$T/envproj" "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  has "$output" "dest=$T/envproj/.claude/rules/agent-operating-lessons.md"
  grep -qF -- '(a01.md)' "$T/envproj/.claude/rules/agent-operating-lessons.md"
}
