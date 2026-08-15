#!/usr/bin/env bats
# cc-memory-rotate — the deterministic actuator for the MEMORY.md loader budget.
#
# The defect this pins: the auto-loaded index re-breached its read limit after
# TWELVE hand-compactions in 14 days, because insertion is machine-speed (Edit appends plus
# Bash `>>` appends the PreToolUse gate never sees) while removal was human-speed. The rotor
# mechanizes the operator-approved cold split (2026-07-30): oldest eligible lines move
# VERBATIM to archive/…-COLD.md until the index is back under target.
#
# RED-proof coverage: the noop/rotate decision is selected by arithmetic on small
# hand-countable fixtures, never asserted; every protection class (tail, type, prefix,
# PINNED, marker, hub, young, dangling) is pinned by an entry that must SURVIVE a rotation
# that succeeds around it; the UNIT is pinned by a fixture over the threshold in bytes and
# under it in loader chars, which must NOT rotate (see below); the contended path is
# exercised through a real seam that mutates the index between read and commit; and a
# mutation control proves the type-protection assertion has teeth (a mutant without it
# rotates the operator directive).
#
# THE UNIT WAS INVERTED HERE UNTIL 2026-08-15 (cc-backlog 7a56de4c54ab). This suite asserted
# "bytes bind, not codepoints" and pinned a fixture over the threshold in BYTES to rotate. The
# loader counts neither: it strips YAML frontmatter and block HTML comments, trims, and compares
# UTF-16 code units, so that fixture is UNDER its cap and rotating it archived entries that still
# fit. The test below is the same fixture with the verdict inverted, which is what makes it a
# control on the correction rather than on the bug.
#
# Assertions are simple commands only. bash exempts `[[ ]]` from errexit, so a non-final
# `[[ ]]` in a bats body evaluates and DISCARDS its result (scripts/bats-assert-liveness.py).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO/bin/cc-memory-rotate"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Small, exact budgets so every fixture is hand-countable.
  export MEMORY_INDEX_LIMIT=3000
  export MEMORY_ROTATE_AT=1500
  export MEMORY_ROTATE_TARGET=1000
  export MEMORY_ROTATE_MIN_KEEP=2
  export MEMORY_ROTATE_TAIL_GUARD=1
  export MEMORY_ROTATE_MIN_AGE_DAYS=7
  # The unit fixture below used to measure itself with `wc -m`, which counts codepoints only
  # under a multibyte LC_CTYPE and degrades to BYTES under C/POSIX — so the one test whose
  # entire subject is the unit distinction was the one that could not survive
  # scripts/offbox-run.sh's LC_ALL=C. It now measures with the same library the subject reads,
  # which has no locale dependency at all, so no locale pin is needed here.
  # shellcheck source=../hooks/lib/memory-index-measure.sh
  . "$REPO/hooks/lib/memory-index-measure.sh"
  OLD=202601011200   # touch -t stamp far past MIN_AGE_DAYS
}

# The size the LOADER checks, which is what every threshold in the subject is denominated in.
eff() { m="$(mim_measure_file "$1")"; printf '%s' "${m%% *}"; }

has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { if printf '%s' "$1" | grep -qF -- "$2"; then return 1; fi; }

# mkmem <name> → a memory dir (path shape the rotor requires) with a header-only index
mkmem() {
  local d="$BATS_TEST_TMPDIR/$1/memory"
  mkdir -p "$d"
  printf '# Memory — fixture\n' >"$d/MEMORY.md"
  printf '%s' "$d"
}

# addentry <memdir> <file> <type> <old|young> <hook>  — index line + typed topic file
addentry() {
  local d="$1" f="$2" t="$3" age="$4" hook="$5" nm="${2%.md}"
  printf -- '- [%s](%s) — %s\n' "$nm" "$f" "$hook" >>"$d/MEMORY.md"
  printf -- '---\nname: %s\ndescription: d\nmetadata:\n  type: %s\n---\nbody\n' "$nm" "$t" >"$d/$f"
  if [ "$age" = old ]; then touch -t "$OLD" "$d/$f"; fi
}

pad() { head -c "$1" /dev/zero | tr '\0' x; }

# Ten old eligible project entries (~150 B lines): 1668 B total — over ROTATE_AT (1500),
# and reaching TARGET (1000) forces several moves while MIN_KEEP (2) never binds.
mkbulk() {
  local d="$1" i
  for i in 01 02 03 04 05 06 07 08 09 10; do
    addentry "$d" "a$i.md" project old "$(pad 140)"
  done
}

@test "noop under the rotate threshold leaves the file byte-identical" {
  d="$(mkmem noop)"
  addentry "$d" one.md project old "small"
  cp "$d/MEMORY.md" "$BATS_TEST_TMPDIR/noop.before"
  run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=noop'
  cmp -s "$d/MEMORY.md" "$BATS_TEST_TMPDIR/noop.before"
}

@test "over threshold: rotates oldest-first to target, verbatim into COLD, tail intact" {
  d="$(mkmem basic)"; mkbulk "$d"
  first="$(grep -F '(a01.md)' "$d/MEMORY.md")"
  last="$(grep -F '(a10.md)' "$d/MEMORY.md")"
  run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  [ "$(wc -c <"$d/MEMORY.md" | tr -d ' ')" -le 1000 ]
  cold="$(ls "$d"/archive/MEMORY_ARCHIVE_*-COLD.md)"
  grep -qxF -- "$first" "$cold"                  # moved VERBATIM
  if grep -qF -- '(a01.md)' "$d/MEMORY.md"; then return 1; fi
  grep -qxF -- "$last" "$d/MEMORY.md"            # tail guard kept the newest line
  head -1 "$d/MEMORY.md" | grep -qF '# Memory — fixture'
  grep -qF 'cold tier' "$d/MEMORY.md"            # discoverability pointer added
  grep -qF 'verdict=rotated' "$d/archive/.rotate.log"
  [ -f "$d/a01.md" ]                             # topic files are never touched
}

@test "anchored parse: a hook containing parens and a ](decoy.md) span still resolves the real link" {
  d="$(mkmem parens)"
  addentry "$d" real-target.md project old "a rule (with parens) citing ](zz-decoy.md) in prose $(pad 100)"
  touch -t 202512011200 "$d/real-target.md"      # oldest ⇒ selected first
  mkbulk "$d"
  line="$(grep -F '(real-target.md)' "$d/MEMORY.md")"
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  cold="$(ls "$d"/archive/MEMORY_ARCHIVE_*-COLD.md)"
  grep -qxF -- "$line" "$cold"                   # whole line moved, keyed on the REAL link
  [ -f "$d/real-target.md" ]
}

@test "protected: feedback type, reference type, name prefix, PINNED, pending marker, dangling all survive" {
  d="$(mkmem prot)"
  addentry "$d" feedback-ops.md feedback old "operator directive $(pad 60)"
  addentry "$d" refy.md reference old "tooling entrypoint $(pad 60)"
  addentry "$d" pin.md project old "explicit opt-out PINNED $(pad 60)"
  addentry "$d" mark.md project old "still BLOCKED on the migration $(pad 60)"
  printf -- '- [dang](dangling-gone.md) — link with no topic file %s\n' "$(pad 60)" >>"$d/MEMORY.md"
  mkbulk "$d"
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  grep -qF -- '(feedback-ops.md)' "$d/MEMORY.md"
  grep -qF -- '(refy.md)' "$d/MEMORY.md"
  grep -qF -- '(pin.md)' "$d/MEMORY.md"
  grep -qF -- '(mark.md)' "$d/MEMORY.md"
  grep -qF -- '(dangling-gone.md)' "$d/MEMORY.md"
}

@test "protected: a graph hub (>=4 inbound [[links]]) survives; a 3-inbound sibling rotates" {
  d="$(mkmem hub)"
  addentry "$d" hub.md project old "load-bearing rule $(pad 60)"
  addentry "$d" spoke.md project old "leaf rule $(pad 60)"
  touch -t 202512011200 "$d/hub.md" "$d/spoke.md"   # oldest pair ⇒ both face selection first
  local i
  for i in 1 2 3 4; do printf 'cites [[hub]]\n' >"$d/sat$i.md"; done
  printf 'cites [[spoke]]\n' >"$d/sat5.md"
  printf 'cites [[spoke]]\n' >"$d/sat6.md"
  printf 'cites [[spoke]]\n' >"$d/sat7.md"
  mkbulk "$d"
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  grep -qF -- '(hub.md)' "$d/MEMORY.md"
  if grep -qF -- '(spoke.md)' "$d/MEMORY.md"; then return 1; fi
}

@test "protected: a young topic file survives even when eligible by every other rule" {
  d="$(mkmem young)"
  addentry "$d" fresh.md project young "written this week $(pad 60)"
  mkbulk "$d"
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  grep -qF -- '(fresh.md)' "$d/MEMORY.md"
}

@test "LOADER CHARS bind, not disk bytes: an index over threshold only in BYTES does NOT rotate" {
  d="$(mkmem utf8)"
  # 6 entries, hooks of 80 em-dashes: ~1560 B on disk, over the 1500 threshold — but 3x fewer
  # chars, so the loader sees it comfortably inside its budget and nothing is at risk. A rotor
  # measuring `wc -c` archives the operator's memories here for no reason at all.
  dashes="$(printf '%.0s—' $(seq 1 80))"
  local i
  for i in 1 2 3 4 5 6; do addentry "$d" "u$i.md" project old "$dashes"; done
  [ "$(wc -c <"$d/MEMORY.md" | tr -d ' ')" -ge 1500 ]
  [ "$(eff "$d/MEMORY.md")" -lt 1500 ]
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=noop'
  hasnt "$output" 'verdict=rotated'
}

@test "...and the SAME fixture in ASCII, where bytes and chars agree, DOES rotate" {
  # The polarity control for the test above: without it, a rotor that had simply stopped
  # rotating anything would pass. Identical shape, single-byte hooks.
  d="$(mkmem ascii)"
  local i
  for i in 1 2 3 4 5 6; do addentry "$d" "u$i.md" project old "$(pad 240)"; done
  [ "$(eff "$d/MEMORY.md")" -ge 1500 ]
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
}

@test "the cold-tier POINTER the rotor writes is free — the loader strips block comments" {
  # The rotor adds `<!-- cold tier: … -->` to the index and used to budget for its own
  # bookkeeping line. The loader removes it before measuring, so it must cost 0 chars.
  d="$(mkmem ptr)"; mkbulk "$d"
  before="$(eff "$d/MEMORY.md")"
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  grep -qF 'archive/MEMORY_ARCHIVE' "$d/MEMORY.md"
  after="$(eff "$d/MEMORY.md")"
  [ "$after" -lt "$before" ]
  [ "$after" -le 1000 ]
}

@test "exhausted: nothing eligible leaves the file byte-identical with the kept census" {
  d="$(mkmem exh)"
  local i
  for i in 01 02 03 04 05 06 07 08 09 10; do
    addentry "$d" "y$i.md" project young "$(pad 140)"
  done
  cp "$d/MEMORY.md" "$BATS_TEST_TMPDIR/exh.before"
  run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 4 ]
  has "$output" 'verdict=exhausted'
  has "$output" 'young=9'                        # 10 young minus 1 tail-guarded
  cmp -s "$d/MEMORY.md" "$BATS_TEST_TMPDIR/exh.before"
}

@test "min-keep floor stops the rotation short of the target" {
  d="$(mkmem floor)"; mkbulk "$d"
  MEMORY_ROTATE_MIN_KEEP=8 run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated moved=2'        # 10 entries, floor 8 ⇒ exactly 2 move
  [ "$(grep -c '^- \[' "$d/MEMORY.md")" -eq 8 ]
}

@test "a fresh lock refuses; a stale lock is reclaimed" {
  d="$(mkmem lock)"; mkbulk "$d"
  mkdir "$d/.rotate.lock.d"
  cp "$d/MEMORY.md" "$BATS_TEST_TMPDIR/lock.before"
  run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 3 ]
  has "$output" 'verdict=locked'
  cmp -s "$d/MEMORY.md" "$BATS_TEST_TMPDIR/lock.before"
  touch -t "$OLD" "$d/.rotate.lock.d"            # now stale (>180 s)
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
}

@test "contended: a sibling writing between read and commit is never clobbered" {
  d="$(mkmem cont)"; mkbulk "$d"
  MEMORY_ROTATE_TEST_PRE_COMMIT='printf -- "- [zz](zz.md) — sibling append\n" >>"$INDEX"' \
    run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 3 ]
  has "$output" 'verdict=contended'
  [ "$(grep -cF -- '(zz.md)' "$d/MEMORY.md")" -eq 3 ]   # every sibling append survived
  [ "$(grep -c '^- \[a' "$d/MEMORY.md")" -eq 10 ]       # and nothing of ours half-landed
}

@test "a path outside */memory/MEMORY.md is refused" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
  printf -- '- [x](x.md) — y\n' >"$BATS_TEST_TMPDIR/elsewhere/MEMORY.md"
  run "$SCRIPT" "$BATS_TEST_TMPDIR/elsewhere/MEMORY.md"
  [ "$status" -eq 2 ]
  has "$output" 'reason=not-a-memory-index'
}

@test "dry-run reports the plan and writes nothing" {
  d="$(mkmem dry)"; mkbulk "$d"
  cp "$d/MEMORY.md" "$BATS_TEST_TMPDIR/dry.before"
  run "$SCRIPT" --dry-run "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=dry-run'
  cmp -s "$d/MEMORY.md" "$BATS_TEST_TMPDIR/dry.before"
  [ ! -d "$d/archive" ]
}

@test "COLD is idempotent: a restored line rotated again is recorded once" {
  d="$(mkmem idem)"; mkbulk "$d"
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  cold="$(ls "$d"/archive/MEMORY_ARCHIVE_*-COLD.md)"
  line="$(grep -F -- '(a01.md)' "$cold" | head -1)"
  printf '%s\n' "$line" >>"$d/MEMORY.md"         # operator restores the line (paste back)
  local i
  for i in 11 12 13 14 15 16 17 18; do          # re-inflate past the threshold
    addentry "$d" "b$i.md" project old "$(pad 140)"
  done
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  [ "$(grep -cxF -- "$line" "$cold")" -eq 1 ]    # moved again, recorded once
}

@test "breach pressure: stage 2 rotates mis-stamped types, the name convention still survives" {
  # 2026-08-10 live finding: 76/105 entries carried type feedback/reference while only 12
  # bore the deliberate name convention — honoring the stamp absolutely made the rotor
  # exhausted on the exact index it was built to heal. At/over the LIMIT itself the
  # unprefixed stamp yields; the prefix convention never does.
  d="$(mkmem stage2)"
  addentry "$d" feedback-real.md feedback old "operator directive $(pad 120)"
  local i
  for i in $(seq -w 1 20); do
    addentry "$d" "lesson$i.md" feedback old "$(pad 120)"
  done
  [ "$(wc -c <"$d/MEMORY.md" | tr -d ' ')" -ge 3000 ]   # at/over the LIMIT itself
  run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  hasnt "$output" 'stage2=0'
  grep -qF -- '(feedback-real.md)' "$d/MEMORY.md"
  [ "$(wc -c <"$d/MEMORY.md" | tr -d ' ')" -le 1000 ]
}

@test "band pressure: the type stamp holds — stage 2 arms only at the LIMIT" {
  d="$(mkmem band)"
  local i
  for i in $(seq -w 1 12); do
    addentry "$d" "lesson$i.md" feedback old "$(pad 120)"
  done
  sz="$(wc -c <"$d/MEMORY.md" | tr -d ' ')"
  [ "$sz" -ge 1500 ]
  [ "$sz" -lt 3000 ]                                    # over ROTATE_AT, under LIMIT
  cp "$d/MEMORY.md" "$BATS_TEST_TMPDIR/band.before"
  run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 4 ]
  has "$output" 'verdict=exhausted'
  cmp -s "$d/MEMORY.md" "$BATS_TEST_TMPDIR/band.before"
}

@test "mutation control: a rotor without the type protection rotates the operator directive" {
  # Anchor the mutation site exactly once, so the mutant is the intended one.
  [ "$(grep -c 'feedback|reference) if' "$SCRIPT")" -eq 1 ]
  mut="$BATS_TEST_TMPDIR/mut-rotate"
  sed 's/feedback|reference) if/xyzzy-never) if/' "$SCRIPT" >"$mut"
  chmod +x "$mut"
  bash -n "$mut"                                 # a malformed mutant proves nothing
  # ops-call.md: typed feedback in frontmatter, name deliberately NOT prefix-protected,
  # and the OLDEST file in the fixture so an unprotected rotor selects it first.
  d="$(mkmem mut1)"
  addentry "$d" ops-call.md feedback old "an operator directive $(pad 100)"
  touch -t 202512011200 "$d/ops-call.md"
  mkbulk "$d"
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  grep -qF -- '(ops-call.md)' "$d/MEMORY.md"     # real rotor: protected by TYPE
  d2="$(mkmem mut2)"
  addentry "$d2" ops-call.md feedback old "an operator directive $(pad 100)"
  touch -t 202512011200 "$d2/ops-call.md"
  mkbulk "$d2"
  run "$mut" "$d2/MEMORY.md"
  has "$output" 'verdict=rotated'
  if grep -qF -- '(ops-call.md)' "$d2/MEMORY.md"; then return 1; fi   # mutant eats it
}
