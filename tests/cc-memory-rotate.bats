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
  # HERMETICITY PIN (2026-09-05). Two of the subject's readers key on CLAUDE_PROJECT_DIR — the
  # widened hub scan and now the durability citation scan — so an inherited value makes every
  # fixture below a function of whichever repo the developer happens to be sitting in. Under
  # launchd it is unset and the suite is green and latent; run from a live session it ranks
  # fixture names against the real tree. Tests needing a project dir build their OWN and export it.
  unset CLAUDE_PROJECT_DIR
  # The unit fixture below used to measure itself with `wc -m`, which counts codepoints only
  # under a multibyte LC_CTYPE and degrades to BYTES under C/POSIX — so the one test whose
  # entire subject is the unit distinction was the one that could not survive
  # scripts/offbox-run.sh's LC_ALL=C. It now measures with the same library the subject reads,
  # which has no locale dependency at all, so no locale pin is needed here.
  # shellcheck source=/dev/null
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

# CONTRACT CHANGED 2026-09-03 — this test previously asserted the DEFECT. Its own name said so:
# "min-keep floor stops the rotation SHORT OF THE TARGET", and it pinned
# `verdict=rotated moved=2` on a fixture where two moves cannot reach TARGET. That is a partial
# loss reported as a success: the breach persists AND two durable lessons have left the hot
# surface for nothing. The selection loop decrements the projection by whatever each line weighs
# and stops on REMAIN<=MIN_KEEP, so on a skewed index it drains cheap entries and leaves the
# heavy ones. All-or-nothing replaces it; the floor is still pinned, by its effect on the verdict.
@test "min-keep floor: a rotation that cannot reach the target moves NOTHING and names the floor" {
  d="$(mkmem floor)"; mkbulk "$d"
  cp "$d/MEMORY.md" "$BATS_TEST_TMPDIR/floor.before"
  MEMORY_ROTATE_MIN_KEEP=8 run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 4 ]                            # 10 entries, floor 8 ⇒ at most 2 movable,
  has "$output" 'verdict=exhausted'              # and 2 × ~151 B cannot reach TARGET from 1668 B
  has "$output" 'bound=min_keep'                 # the diagnostic that sent three analyses wrong
  has "$output" 'entries=10'
  hasnt "$output" 'verdict=rotated'
  [ "$(grep -c '^- \[' "$d/MEMORY.md")" -eq 10 ]
  cmp -s "$d/MEMORY.md" "$BATS_TEST_TMPDIR/floor.before"
}

# POSITIVE CONTROL on the assertion above: all-or-nothing must not degrade into a blanket refusal.
@test "min-keep floor still permits a rotation it does not block" {
  d="$(mkmem floorok)"; mkbulk "$d"
  run "$SCRIPT" "$d/MEMORY.md"                   # setup floor is 2 ⇒ 8 movable ⇒ TARGET reached
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  [ "$(eff "$d/MEMORY.md")" -le 1000 ]
}

@test "hub protection counts BARE .md citations, not only [[wikilinks]]" {
  d="$(mkmem hubbare)"; mkbulk "$d"
  # Measured on reso's always-loaded project rules file: 0 wikilinks, 31 bare `name.md`
  # citations. Four sibling topic files cite a01 by bare filename ⇒ inb>=4 ⇒ hub ⇒ must SURVIVE
  # a rotation that succeeds around it (a01 is the oldest, so it would otherwise move first).
  local i
  for i in c1 c2 c3 c4; do
    printf -- '---\nname: %s\ndescription: d\nmetadata:\n  type: project\n---\nsee a01.md\n' "$i" >"$d/$i.md"
    touch -t "$OLD" "$d/$i.md"
  done
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  grep -qF '](a01.md)' "$d/MEMORY.md"
}

@test "the index and the demotion records never make an entry look like a hub" {
  d="$(mkmem hubexcl)"; mkbulk "$d"
  # MEMORY.md, MEMORY-ARCHIVE.md, the COLD file and every PRE-COMPACT snapshot carry a
  # `](name.md)` link for EVERY entry BY CONSTRUCTION. If the bare-filename scan counted them,
  # almost the whole index would cross the hub threshold in one step and this actuator would
  # become a permanent no-op — the exact failure mode it exists to end. a01 is the oldest entry,
  # so it moves first unless something wrongly protects it.
  mkdir -p "$d/archive"
  printf -- '- [a01](a01.md) — x\n- [a02](a02.md) — x\n' >"$d/MEMORY-ARCHIVE.md"
  printf -- '- [a01](a01.md) — x\n' >"$d/archive/MEMORY_ARCHIVE_2026-H2-COLD.md"
  printf -- '- [a01](a01.md) — x\n' >"$d/MEMORY_INDEX_PRE-COMPACT_2026-09-03.md"
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  hasnt "$(cat "$d/MEMORY.md")" '](a01.md)'
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
# ── the LINE cap: "the first 200 lines OR 25KB, whichever comes first" ───────────────────────
#
# Every fixture above is sized in BYTES, so none of them can tell whether this rotor watches lines
# at all — and until 2026-08-15 it did not. These pin the other cap: an index far under every byte
# threshold, pressured only by its line count. Budgets are shrunk to hand-countable values for the
# same reason the byte ones are.

line_env() {
  export MEMORY_INDEX_LINE_LIMIT=12
  export MEMORY_ROTATE_AT_LINES=10
  export MEMORY_ROTATE_TARGET_LINES=8
}

# Ten old eligible project entries with SHORT hooks: ~400 B total, so the byte thresholds
# (rotate_at 1500) can never be what fires — only the 11-line count can.
mkterse() {
  local d="$1" i
  for i in 01 02 03 04 05 06 07 08 09 10; do
    addentry "$d" "b$i.md" project old "$(pad 20)"
  done
}

@test "LINE pressure alone rotates: an index far under every byte threshold still comes down" {
  line_env
  d="$(mkmem terse)"; mkterse "$d"
  [ "$(wc -c <"$d/MEMORY.md" | tr -d ' ')" -lt "$MEMORY_ROTATE_AT" ]   # bytes CANNOT be the trigger
  [ "$(LC_ALL=C awk 'END{print NR}' "$d/MEMORY.md")" -ge 10 ]
  run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  [ "$(LC_ALL=C awk 'END{print NR}' "$d/MEMORY.md")" -le 8 ]           # reached the LINE target
  ls "$d"/archive/MEMORY_ARCHIVE_*-COLD.md >/dev/null
}

@test "polarity: the same terse index is a NOOP under the shipped 200-line cap" {
  # 11 lines against the real cap is nowhere near pressure. Without this control the test above
  # would pass just as well against a rotor that rotates unconditionally.
  d="$(mkmem terse2)"; mkterse "$d"
  run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=noop'
  has "$output" 'lines=11'
}

@test "a line target not below its rotate-at is refused, like the byte pair" {
  d="$(mkmem lcfg)"; mkterse "$d"
  MEMORY_ROTATE_AT_LINES=8 MEMORY_ROTATE_TARGET_LINES=8 run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 2 ]
  has "$output" 'line-target-not-below-rotate-at'
}

# ── DURABILITY ORDER: rank first, age only as the tiebreak (Phase 5 item 4) ──────────────────
#
# Measured 2026-09-04 on the live claude-infrastructure index: of the 25 entries age-ordering
# would have taken at the next breach, 24 are cited BY NAME in shipped executable code. Age there
# records when a lesson was LEARNED, and the oldest lessons are the most deeply wired in, so a
# 37.9-day spread makes age look like signal while pointing the wrong way. These fixtures make
# the two orders DISAGREE — under age alone the wired entry is the first thing out, under the
# shipped order it is the last — so a green here cannot be produced by either policy alone.

# mkproject <name> → a project dir whose bin/ cites the topic files named in argv[2..]
mkproject() {
  local p="$BATS_TEST_TMPDIR/$1" f
  shift
  mkdir -p "$p/bin"
  : >"$p/bin/consumer.sh"
  for f in "$@"; do
    printf '# see %s for why this branch exists\n' "$f" >>"$p/bin/consumer.sh"
  done
  printf '%s' "$p"
}

# The mutant used by both controls: the rotor with the durability key removed from BOTH selection
# sorts, i.e. exactly the age-ordered rotor that shipped until 2026-09-05.
mkageonly() {
  [ "$(grep -c -- '-k1,1n -k2,2n -k3,3nr -k5,5' "$SCRIPT")" -eq 2 ]   # anchor: stage 1 and stage 2
  local mut="$BATS_TEST_TMPDIR/mut-ageonly"
  sed 's/-k1,1n -k2,2n -k3,3nr -k5,5/-k2,2n -k3,3nr -k5,5/' "$SCRIPT" >"$mut"
  chmod +x "$mut"
  bash -n "$mut"                                  # a malformed mutant proves nothing
  printf '%s' "$mut"
}

@test "durability: a lesson cited by shipped code is demoted LAST, not first for being oldest" {
  CLAUDE_PROJECT_DIR="$(mkproject proj1 wired.md)"; export CLAUDE_PROJECT_DIR
  d="$(mkmem dur1)"
  addentry "$d" wired.md project old "a rule the tooling depends on $(pad 100)"
  addentry "$d" orphan.md project old "a rule nothing cites $(pad 100)"
  touch -t 202512011200 "$d/wired.md" "$d/orphan.md"   # the two OLDEST ⇒ age would take both first
  mkbulk "$d"
  run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  has "$output" 'durability=ok'
  has "$output" 'live=0'                          # no live rule had to be demoted
  grep -qF -- '(wired.md)' "$d/MEMORY.md"         # cited ⇒ ranked last ⇒ still hot
  if grep -qF -- '(orphan.md)' "$d/MEMORY.md"; then return 1; fi   # uncited, same age ⇒ gone
}

@test "mutation control: the age-ordered rotor eats the cited rule for being oldest" {
  mut="$(mkageonly)"
  CLAUDE_PROJECT_DIR="$(mkproject proj2 wired.md)"; export CLAUDE_PROJECT_DIR
  d="$(mkmem dur2)"
  addentry "$d" wired.md project old "a rule the tooling depends on $(pad 100)"
  addentry "$d" orphan.md project old "a rule nothing cites $(pad 100)"
  touch -t 202512011200 "$d/wired.md" "$d/orphan.md"
  mkbulk "$d"
  run "$mut" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  if grep -qF -- '(wired.md)' "$d/MEMORY.md"; then return 1; fi     # the defect this phase fixes
}

@test "durability: a superseded_by: entry is demoted FIRST despite being the newest eligible" {
  d="$(mkmem dur3)"
  mkbulk "$d"
  addentry "$d" dead.md project old "a verdict its own heir replaced $(pad 100)"
  # NEWER than every bulk entry and outside the 1-line tail guard, so age ordering puts it LAST
  # in the eligible pool and a partial drain would leave it hot.
  touch -t 202602011200 "$d/dead.md"
  addentry "$d" tailpad.md project old "keeps dead.md out of the tail guard $(pad 100)"
  printf -- '---\nname: dead\nsuperseded_by: heir-rule\ndescription: d\nmetadata:\n  type: project\n---\nbody\n' >"$d/dead.md"
  touch -t 202602011200 "$d/dead.md"
  run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  if grep -qF -- '(dead.md)' "$d/MEMORY.md"; then return 1; fi      # rank 0 ⇒ first out
  grep -qF -- '(a09.md)' "$d/MEMORY.md"           # an OLDER ordinary entry outlived it
}

@test "mutation control: the age-ordered rotor keeps the superseded entry and eats the older one" {
  mut="$(mkageonly)"
  d="$(mkmem dur4)"
  mkbulk "$d"
  addentry "$d" dead.md project old "a verdict its own heir replaced $(pad 100)"
  touch -t 202602011200 "$d/dead.md"
  addentry "$d" tailpad.md project old "keeps dead.md out of the tail guard $(pad 100)"
  printf -- '---\nname: dead\nsuperseded_by: heir-rule\ndescription: d\nmetadata:\n  type: project\n---\nbody\n' >"$d/dead.md"
  touch -t 202602011200 "$d/dead.md"
  run "$mut" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  # The discriminator is the dead entry alone: age puts the newest-eligible LAST, so a partial
  # drain never reaches it and the one entry the author declared replaceable is the one kept.
  # (Which OTHER entries the age-ordered mutant spends is not asserted — the drain stops at
  # TARGET, so naming a specific survivor would pin fixture arithmetic, not the policy.)
  grep -qF -- '(dead.md)' "$d/MEMORY.md"
}

@test "durability: the prose markers a correction leaves behind do NOT rank an entry dead" {
  # 26 of this store's topic files carry SUPERSEDED/CORRECTED/REFUTED and ZERO of them mark the
  # FILE as dead — every one marks a passage the same file then corrects, so matching the prose
  # would evict the most-corrected entries first. This pins that the rank ignores them.
  d="$(mkmem dur5)"
  mkbulk "$d"
  addentry "$d" corrected.md project old "a rule this file itself CORRECTED $(pad 100)"
  touch -t 202602011200 "$d/corrected.md"
  addentry "$d" tailpad.md project old "keeps corrected.md out of the tail guard $(pad 100)"
  printf -- '---\nname: corrected\ndescription: d\nmetadata:\n  type: project\n---\n**CORRECTED 2026-09-01 — the paragraph above is SUPERSEDED and REFUTED.**\n' >"$d/corrected.md"
  touch -t 202602011200 "$d/corrected.md"
  run "$SCRIPT" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  grep -qF -- '(corrected.md)' "$d/MEMORY.md"     # newest eligible, rank 1 ⇒ survives the drain
}

@test "durability: with no project dir the rank degrades to age and SAYS so" {
  d="$(mkmem dur6)"; mkbulk "$d"
  run "$SCRIPT" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  has "$output" 'durability=unavailable'          # never implies a ranking that did not run
  if grep -qF -- '(a01.md)' "$d/MEMORY.md"; then return 1; fi       # oldest-first, exactly as before
}

# ── CITATION ON DEMOTION (Phase 5 item 5) ────────────────────────────────────────────────────
#
# A routed line keeps its reader because both surfaces auto-load. A COLD one does not, so the
# demotion leaves a one-line pointer naming the topic file on the always-loaded rules file.
# Measured payoff 11x: cited demotions are re-read 30% of the time at 1.23 reads/file against
# 3% and 0.11 for archive-only. The fixture must reach the COLD path, which after routing shipped
# means a stage-2 breach: the entries stage 2 frees are type-stamped, so route_veto sends them to
# the cold record rather than to the rules file.

# 24 entries, not 20: at 20 this fixture measures 3041 raw bytes and the LIMIT it must exceed is
# shifted UP by mim_overhead (the loader strips frontmatter and block comments), so the breach it
# is built to create did not happen and the rotor correctly returned exhausted. Sized with margin
# and asserted below rather than assumed.
mkbreach() {
  local d="$1" i
  for i in $(seq -w 1 24); do addentry "$d" "lesson$i.md" feedback old "$(pad 120)"; done
  [ "$(eff "$d/MEMORY.md")" -ge 3000 ]
}

@test "citation on demotion: the rules file gains a pointer naming each demoted topic file" {
  d="$(mkmem cite1)"; mkbreach "$d"
  rules="$BATS_TEST_TMPDIR/rules/agent-operating-lessons.md"
  run "$SCRIPT" --rules-file "$rules" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'
  hasnt "$output" 'cited=0'
  hasnt "$output" ' cite='                        # no degradation reason ⇒ the pointers were written
  grep -qF 'demotion pointers written' "$rules"
  grep -qF 'lesson01.md' "$rules"                 # the topic file is NAMED
  grep -qF 'demoted' "$rules"
  # …and it is a POINTER, not the entry: the index line itself went to the cold record.
  cold="$(ls "$d"/archive/MEMORY_ARCHIVE_*-COLD.md)"
  grep -qF -- '(lesson01.md)' "$cold"
  if grep -qF -- '- [lesson01](lesson01.md)' "$rules"; then return 1; fi
  [ -f "$d/lesson01.md" ]                         # topic files are never touched
}

@test "citation on demotion: a second rotation does not duplicate an existing pointer" {
  d="$(mkmem cite2)"; mkbreach "$d"
  rules="$BATS_TEST_TMPDIR/rules2/agent-operating-lessons.md"
  run "$SCRIPT" --rules-file "$rules" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  line="$(grep -F 'lesson01.md' "$rules" | head -1)"
  local i
  for i in $(seq -w 21 40); do addentry "$d" "lesson$i.md" feedback old "$(pad 120)"; done
  printf '%s\n' "$(grep -F -- '(lesson01.md)' "$d"/archive/MEMORY_ARCHIVE_*-COLD.md | head -1)" >>"$d/MEMORY.md"
  run "$SCRIPT" --rules-file "$rules" "$d/MEMORY.md"
  has "$output" 'verdict=rotated'
  [ "$(grep -cxF -- "$line" "$rules")" -eq 1 ]
}

@test "citation on demotion: no destination degrades the pointer, never the rotation" {
  d="$(mkmem cite3)"; mkbreach "$d"
  cp "$d/MEMORY.md" "$BATS_TEST_TMPDIR/cite3.before"
  run "$SCRIPT" "$d/MEMORY.md"                    # no --rules-file, no CLAUDE_PROJECT_DIR
  [ "$status" -eq 0 ]
  has "$output" 'verdict=rotated'                 # the loader cap is still held
  has "$output" 'cite=no-rules-destination'       # and the reason is PRINTED, not swallowed
  has "$output" 'cited=0'
  cold="$(ls "$d"/archive/MEMORY_ARCHIVE_*-COLD.md)"
  grep -qF -- '(lesson01.md)' "$cold"
  if cmp -s "$d/MEMORY.md" "$BATS_TEST_TMPDIR/cite3.before"; then return 1; fi
}

