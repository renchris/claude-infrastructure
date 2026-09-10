#!/usr/bin/env bats
# Door-agnostic drain-on-detect — hooks/memory-index-drain.sh (PostToolUse) and the
# `cc-memory-rotate --drain-oversized` actuator it fires.
#
# THE DEFECT THIS PINS. The auto-loaded index has hard loader caps past which the tail — the NEWEST
# entries — is silently dropped. The PreToolUse gate (hooks/lib/memory-index-budget.sh) holds that
# line for Write/Edit/MultiEdit and is structurally blind to Bash: the observed appends are
# `cd <…>/memory && … >> MEMORY.md`, measured at 1 in 6 index writes, and the product's own
# PostToolUse memory-size callback does not register on Bash either. Detection today lives at
# UserPromptSubmit — a full turn after the write, advisory-only, with a twelve-hand-compaction
# failure record. This suite asserts the two properties that fix costs: the write is caught AT the
# write whatever door made it, and something ACTUATES.
#
# RED-PROOF COVERAGE, and the controls that make each direction non-vacuous:
#   · the tail guard is proven in BOTH directions ON ONE FIXTURE — bypassed by the drain for an
#     over-cap entry, still honoured by ordinary rotation on the same file — and the ordinary arm
#     asserts moved>0, so "honoured" can never be a rotation that did nothing;
#   · the drained line is compared BYTE-FOR-BYTE and then pasted back to reconstruct the original
#     index exactly, so "verbatim" is a diff, not an eyeball;
#   · the negative control writes a file that is NOT the session's index and asserts silence;
#   · the stamp-key case is a regression control for a bash-3.2-only bug: `${k: -120}` returns the
#     EMPTY STRING for a short k, which collapsed every short-path index onto one change detector.
#
# Assertions are simple commands only. bash exempts `[[ ]]` from errexit, so a non-final `[[ ]]` in
# a bats body evaluates and DISCARDS its result — the test passes vacuously
# (scripts/bats-assert-liveness.py).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROTOR="$REPO/bin/cc-memory-rotate"
  HOOK="$REPO/hooks/memory-index-drain.sh"
  T="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export HOME="$T/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$T/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export MEMORY_DRAIN_STATE_DIR="$T/state"; mkdir -p "$MEMORY_DRAIN_STATE_DIR"
  export MEMORY_ROTATE_BIN="$ROTOR"
  unset MEMORY_INDEX_PATH MEMORY_RULES_FILE CLAUDE_PROJECT_DIR MEMORY_ENTRY_LIMIT || true
}

has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { if printf '%s' "$1" | grep -qF -- "$2"; then return 1; fi; }

# n chars of filler
pad() { head -c "$1" /dev/zero | tr '\0' q; }

# A topic file with a frontmatter type. $1 dir, $2 file, $3 type
topic() { printf -- '---\nname: %s\ntype: %s\n---\nbody\n' "${2%.md}" "$3" >"$1/$2"; }

# mkmem <name> → echoes the memory dir of a standalone fixture index (no config-dir shape needed;
# the rotor's own discriminator is the `/memory/MEMORY.md` tail).
mkmem() {
  local d="$T/${1:-fix}/memory"
  mkdir -p "$d"
  printf '# Memory — fixture\n' >"$d/MEMORY.md"
  printf '%s' "$d"
}

# add_entry <memdir> <file> <hooklen> [type]
add_entry() {
  local d="$1" f="$2" n="$3" ty="${4:-project}"
  topic "$d" "$f" "$ty"
  printf -- '- [%s](%s) — %s\n' "${f%.md}" "$f" "$(pad "$n")" >>"$d/MEMORY.md"
}

rules_dest() { mkdir -p "$T/proj/.claude/rules"; printf '%s' "$T/proj/.claude/rules/agent-operating-lessons.md"; }

# The two-direction fixture. Five OLD entries that are fat but UNDER the 300-unit entry cap, then
# fourteen small ones, then a NEWEST entry that is over the cap. With TAIL_GUARD=15 the newest 15
# ordinals are tail-protected, so ordinary rotation can only reach the five old ones — and the
# over-cap newest is exactly the line the drain has to be able to take.
mkfix_tail() {
  local d i
  d="$(mkmem tailfix)"
  for i in 1 2 3 4 5; do add_entry "$d" "old0$i.md" 240; done
  for i in 6 7 8 9; do add_entry "$d" "mid0$i.md" 20; done
  for i in 10 11 12 13 14 15 16 17 18 19; do add_entry "$d" "mid$i.md" 20; done
  add_entry "$d" "newest.md" 700
  printf '%s' "$d"
}

# ── The actuator: cc-memory-rotate --drain-oversized ────────────────────────────────────────────

@test "1 drain moves an over-cap entry that ordinary rotation would refuse as tail" {
  d="$(mkfix_tail)"; dest="$(rules_dest)"
  run env MEMORY_ROTATE_TAIL_GUARD=15 MEMORY_ROTATE_MIN_AGE_DAYS=0 MEMORY_ROTATE_MIN_KEEP=0 \
      "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" "verdict=drained"
  has "$output" "moved=1"
  has "$output" "files=newest.md"
  # the over-cap newest line is GONE from the index and PRESENT in the always-loaded destination
  run grep -c 'newest.md' "$d/MEMORY.md"
  [ "$status" -ne 0 ]
  run grep -c 'newest.md' "$dest"
  [ "$status" -eq 0 ]
}

@test "2 the SAME fixture: ordinary rotation still honours the tail guard, and moves >0" {
  d="$(mkfix_tail)"
  # Thresholds sized so the five old (eligible) entries are exactly enough to reach TARGET; the
  # newest over-cap entry sits inside TAIL_GUARD and must survive.
  run env MEMORY_ROTATE_TAIL_GUARD=15 MEMORY_ROTATE_MIN_AGE_DAYS=0 MEMORY_ROTATE_MIN_KEEP=0 \
      MEMORY_ROTATE_AT=2500 MEMORY_ROTATE_TARGET=1600 \
      "$ROTOR" "$d/MEMORY.md" --verbose
  [ "$status" -eq 0 ]
  has "$output" "verdict=rotated"
  # NON-VACUOUS: rotation actually did something, so "the newest survived" is a guard and not a no-op
  hasnt "$output" "moved=0"
  has "$output" "tail"
  run grep -c 'newest.md' "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  # and the five old ones did leave
  run grep -c 'old01.md' "$d/MEMORY.md"
  [ "$status" -ne 0 ]
}

@test "3 the drained line lands VERBATIM and pasting it back reconstructs the index exactly" {
  d="$(mkmem verb)"; dest="$(rules_dest)"
  add_entry "$d" "small.md" 20
  add_entry "$d" "fat.md" 700
  cp "$d/MEMORY.md" "$T/before.md"
  line="$(grep -F 'fat.md' "$T/before.md")"
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  # byte-for-byte: the destination carries the line as a WHOLE LINE, unmodified
  run grep -qxF -- "$line" "$dest"
  [ "$status" -eq 0 ]
  # recoverable: paste it back where it was and the index is byte-identical to the original
  printf '%s\n' "$line" >>"$d/MEMORY.md"
  run diff -q "$T/before.md" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
}

@test "4 an UNDER-cap entry is never drained, however old or eligible" {
  d="$(mkmem under)"; dest="$(rules_dest)"
  add_entry "$d" "a.md" 100
  add_entry "$d" "b.md" 250
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" "verdict=noop"
  has "$output" "oversized=0"
  run grep -c 'b.md' "$d/MEMORY.md"
  [ "$status" -eq 0 ]
}

@test "5 the entry cap is the loader's UNIT, not a byte count" {
  # 200 em-dashes = 600 BYTES on disk and 200 UTF-16 units. A byte-based cap would drain this line;
  # the loader would not have counted it as over anything.
  d="$(mkmem units)"; dest="$(rules_dest)"
  topic "$d" "dash.md" project
  printf -- '- [dash](dash.md) — ' >>"$d/MEMORY.md"
  i=0; while [ "$i" -lt 200 ]; do printf -- '—' >>"$d/MEMORY.md"; i=$(( i + 1 )); done
  printf '\n' >>"$d/MEMORY.md"
  run env MEMORY_ENTRY_LIMIT=300 "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" "oversized=0"
  # control: the same line IS over a 150-unit cap, so the measure is live and not stuck at zero
  run env MEMORY_ENTRY_LIMIT=150 "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" "verdict=drained"
}

@test "6 operator voice vetoes the route: feedback-, user-, PINNED, and the type stamp" {
  d="$(mkmem veto)"; dest="$(rules_dest)"
  add_entry "$d" "feedback-loud.md" 700
  add_entry "$d" "user-said.md" 700
  add_entry "$d" "stamped.md" 700 feedback
  topic "$d" "pinned.md" project
  printf -- '- [pinned](pinned.md) — PINNED %s\n' "$(pad 700)" >>"$d/MEMORY.md"
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 4 ]
  has "$output" "verdict=exhausted"
  has "$output" "moved=0"
  has "$output" "oversized=4"
  has "$output" "type=3"
  has "$output" "pinned=1"
  # nothing was written anywhere
  run grep -c 'feedback-loud.md' "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  [ ! -s "$dest" ]
}

@test "7 an unparseable or dangling over-cap line is reported, never touched" {
  d="$(mkmem dang)"; dest="$(rules_dest)"
  # dangling: the index cites a topic file that is not on disk
  printf -- '- [gone](gone.md) — %s\n' "$(pad 700)" >>"$d/MEMORY.md"
  # unparseable: a wikilink in the LINK TITLE defeats the anchored first-group parse
  printf -- '- [[[wiki]] title](x) — %s\n' "$(pad 700)" >>"$d/MEMORY.md"
  cp "$d/MEMORY.md" "$T/dang-before.md"
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 4 ]
  has "$output" "dangling=1"
  has "$output" "unparseable=1"
  run diff -q "$T/dang-before.md" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
}

@test "8 no resolvable destination is an ERROR, not a silent archive" {
  d="$(mkmem nodest)"
  add_entry "$d" "fat.md" 700
  cp "$d/MEMORY.md" "$T/nodest-before.md"
  run env -u CLAUDE_PROJECT_DIR -u MEMORY_RULES_FILE "$ROTOR" "$d/MEMORY.md" --drain-oversized
  [ "$status" -eq 2 ]
  has "$output" "reason=no-rules-destination"
  run diff -q "$T/nodest-before.md" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
}

@test "9 a symlinked destination is RESOLVED and the real target receives the line" {
  d="$(mkmem symdest)"
  add_entry "$d" "fat.md" 700
  mkdir -p "$T/real" "$T/proj2/.claude/rules"
  printf '# real\n' >"$T/real/rules.md"
  ln -s "$T/real/rules.md" "$T/proj2/.claude/rules/agent-operating-lessons.md"
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$T/proj2/.claude/rules/agent-operating-lessons.md"
  [ "$status" -eq 0 ]
  has "$output" "verdict=drained"
  has "$output" "dest=$T/real/rules.md"
  run grep -c 'fat.md' "$T/real/rules.md"
  [ "$status" -eq 0 ]
}

@test "10 the destination append is idempotent and --dry-run touches nothing" {
  d="$(mkmem idem)"; dest="$(rules_dest)"
  add_entry "$d" "fat.md" 700
  cp "$d/MEMORY.md" "$T/idem-before.md"
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest" --dry-run
  [ "$status" -eq 0 ]
  has "$output" "verdict=dry-run"
  run diff -q "$T/idem-before.md" "$d/MEMORY.md"
  [ "$status" -eq 0 ]
  [ ! -e "$dest" ]
  # real run, then paste the line back and run again: the destination must not gain a duplicate
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  line="$(grep -F 'fat.md' "$T/idem-before.md")"
  printf '%s\n' "$line" >>"$d/MEMORY.md"
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  run grep -c -F 'fat.md' "$dest"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "11 a sibling write between read and commit is CONTENDED, never a clobber" {
  d="$(mkmem cont)"; dest="$(rules_dest)"
  add_entry "$d" "fat.md" 700
  run env MEMORY_ROTATE_TEST_PRE_COMMIT="printf 'sibling\n' >>'$d/MEMORY.md'" \
      "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 3 ]
  has "$output" "verdict=contended"
  run grep -c 'sibling' "$d/MEMORY.md"
  [ "$status" -eq 0 ]
}

@test "12 --rules-file with no value, and a non-index path, are refused" {
  d="$(mkmem args)"
  add_entry "$d" "fat.md" 700
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file
  [ "$status" -eq 2 ]
  has "$output" "reason=rules-file-needs-a-value"
  printf 'x\n' >"$T/NotAnIndex.md"
  run "$ROTOR" "$T/NotAnIndex.md" --drain-oversized --rules-file "$(rules_dest)"
  [ "$status" -eq 2 ]
  has "$output" "reason=not-a-memory-index"
}

# ── The detector: hooks/memory-index-drain.sh at PostToolUse ────────────────────────────────────

# Build a config-dir-shaped project the locator will resolve, and echo "<proj>|<memdir>".
mkproj() {
  local name="$1" proj memd slug
  proj="$T/$name"; mkdir -p "$proj/.claude/rules"
  proj="$(cd "$proj" && pwd -P)"
  slug="$(printf '%s' "$proj" | tr '/.' '--')"
  memd="$CLAUDE_CONFIG_DIR/projects/$slug/memory"; mkdir -p "$memd"
  printf '# Memory — %s\n' "$name" >"$memd/MEMORY.md"
  printf '%s|%s' "$proj" "$memd"
}

fire() { jq -nc --arg cwd "$1" '{session_id:"s1",cwd:$cwd,tool_name:"Bash",tool_input:{command:"true"},tool_response:{exitCode:0}}' | bash "$HOOK"; }

@test "13 a Bash >> append of an over-cap entry is detected and drained in the SAME turn" {
  p="$(mkproj p13)"; proj="${p%|*}"; memd="${p#*|}"
  topic "$memd" "big.md" project
  run fire "$proj"          # baseline turn: record the stat, say nothing
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # THE LEAK, in the exact relative form the PreToolUse gate cannot see
  ( cd "$memd" && printf -- '- [Big](big.md) — %s\n' "$(pad 700)" >>MEMORY.md )
  run fire "$proj"
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  has "$ctx" "MEMORY INDEX DRAINED"
  has "$ctx" "big.md"
  has "$ctx" "$proj/.claude/rules/agent-operating-lessons.md"
  # same turn: the line is already off the index and on the always-loaded surface
  run grep -c 'big.md' "$memd/MEMORY.md"
  [ "$status" -ne 0 ]
  run grep -c 'big.md' "$proj/.claude/rules/agent-operating-lessons.md"
  [ "$status" -eq 0 ]
}

@test "14 hookEventName is PostToolUse and the payload is one JSON object" {
  p="$(mkproj p14)"; proj="${p%|*}"; memd="${p#*|}"
  topic "$memd" "big.md" project
  run fire "$proj"
  ( cd "$memd" && printf -- '- [Big](big.md) — %s\n' "$(pad 700)" >>MEMORY.md )
  run fire "$proj"
  [ "$status" -eq 0 ]
  run jq -re '.hookSpecificOutput.hookEventName' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "PostToolUse" ]
}

@test "15 NEGATIVE CONTROL — a non-index file is untouched and nothing is emitted" {
  p="$(mkproj p15)"; proj="${p%|*}"; memd="${p#*|}"
  run fire "$proj"
  # a repo file that merely happens to be named MEMORY.md, plus a sibling inside the memory dir
  mkdir -p "$proj/docs"
  printf -- '- [Decoy](decoy.md) — %s\n' "$(pad 700)" >"$proj/docs/MEMORY.md"
  printf -- '- [Sib](sib.md) — %s\n' "$(pad 700)" >"$memd/NOTES.md"
  cp "$proj/docs/MEMORY.md" "$T/decoy-before.md"
  cp "$memd/NOTES.md" "$T/sib-before.md"
  run fire "$proj"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run diff -q "$T/decoy-before.md" "$proj/docs/MEMORY.md"
  [ "$status" -eq 0 ]
  run diff -q "$T/sib-before.md" "$memd/NOTES.md"
  [ "$status" -eq 0 ]
  [ ! -e "$proj/.claude/rules/agent-operating-lessons.md" ]
}

@test "16 an unchanged index is not measured and not acted on" {
  p="$(mkproj p16)"; proj="${p%|*}"; memd="${p#*|}"
  topic "$memd" "big.md" project
  ( cd "$memd" && printf -- '- [Big](big.md) — %s\n' "$(pad 700)" >>MEMORY.md )
  run fire "$proj"                     # drains
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')"
  has "$ctx" "MEMORY INDEX DRAINED"
  cp "$memd/MEMORY.md" "$T/quiet-before.md"
  run fire "$proj"                     # nothing changed since: silent, and no second drain
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run diff -q "$T/quiet-before.md" "$memd/MEMORY.md"
  [ "$status" -eq 0 ]
}

@test "17 two short-path indexes get DISTINCT change stamps" {
  # Regression control for a bash-3.2-only defect: `${k: -120}` returns the EMPTY string when k is
  # shorter than 120, so every short-path index collapsed onto one stamp file and each project's
  # write read as "already seen" for the other. Both must be seen.
  a="$(mkproj pa)"; aproj="${a%|*}"; amem="${a#*|}"
  b="$(mkproj pb)"; bproj="${b%|*}"; bmem="${b#*|}"
  topic "$amem" "ba.md" project; topic "$bmem" "bb.md" project
  run fire "$aproj"
  run fire "$bproj"
  ( cd "$amem" && printf -- '- [A](ba.md) — %s\n' "$(pad 700)" >>MEMORY.md )
  ( cd "$bmem" && printf -- '- [B](bb.md) — %s\n' "$(pad 700)" >>MEMORY.md )
  run fire "$aproj"
  has "$output" "MEMORY INDEX DRAINED"
  run fire "$bproj"
  has "$output" "MEMORY INDEX DRAINED"
  n=$(find "$MEMORY_DRAIN_STATE_DIR" -name 'memdrain-*.stat' | wc -l | tr -d ' ')
  [ "$n" = "2" ]
}

@test "18 an over-cap entry the operator vetoed is SURFACED, not silently left" {
  p="$(mkproj p18)"; proj="${p%|*}"; memd="${p#*|}"
  topic "$memd" "feedback-loud.md" project
  run fire "$proj"
  ( cd "$memd" && printf -- '- [Loud](feedback-loud.md) — %s\n' "$(pad 700)" >>MEMORY.md )
  run fire "$proj"
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  has "$ctx" "could NOT be routed automatically"
  has "$ctx" "verdict=exhausted"
  run grep -c 'feedback-loud.md' "$memd/MEMORY.md"
  [ "$status" -eq 0 ]
}

@test "19 a breached index is ALSO rotated in the same turn, not left for the next prompt" {
  p="$(mkproj p19)"; proj="${p%|*}"; memd="${p#*|}"
  i=1
  while [ "$i" -le 40 ]; do add_entry "$memd" "e$i.md" 60; i=$(( i + 1 )); done
  run fire "$proj"
  ( cd "$memd" && printf -- '- [Last](e1.md) — tiny\n' >>MEMORY.md )
  # A line cap this fixture is already past, so the whole-index arm has to fire.
  # PIN THE ROTOR BUDGET. This case runs the REAL rotor and asserts it REACHED a verdict, so with
  # MID_DEADLINE_S left at its 7s default the assertion silently becomes "was the box quiet enough",
  # not "did the whole-index arm actuate in this turn". Measured 2026-09-08: three consecutive runs
  # on an unmodified tree gave ok / not ok / ok, and three ship-land gates in a row were blocked by
  # it — including its double-run exoneration, which cannot clear a ~1-in-3 flake. Cases 21 and 22
  # already pin this seam (MID_DEADLINE_S=2 / =3) precisely because THEY test the cut; this one
  # tests the opposite outcome and has to pin it the other way for the same reason.
  run env MID_DEADLINE_S=120 \
      MEMORY_INDEX_LINE_LIMIT=20 MEMORY_ROTATE_AT_LINES=12 MEMORY_ROTATE_TARGET_LINES=8 \
      MEMORY_ROTATE_TAIL_GUARD=3 MEMORY_ROTATE_MIN_AGE_DAYS=0 MEMORY_ROTATE_MIN_KEEP=0 \
      bash -c 'jq -nc --arg cwd "$1" "{session_id:\"s1\",cwd:\$cwd,tool_name:\"Bash\",tool_input:{command:\"true\"},tool_response:{exitCode:0}}" | bash "$2"' _ "$proj" "$HOOK"
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')"
  has "$ctx" "AUTO-ROTATED"
  # CONTRACT CHANGED 2026-09-04 — this asserted `find … MEMORY_ARCHIVE_*-COLD.md | wc -l` = 1.
  # Ordinary rotation now ROUTES what route_veto permits to the project's always-loaded rules
  # file and cold-records only the rest, and this hook passes `--rules-file`, so these
  # `project`-typed entries land in the rules file and no cold record is written at all. The
  # test's real subject — the whole-index arm ACTUATED in this same turn, rather than being
  # left for the next prompt — is unchanged, so it is asserted at the new destination. Both
  # halves are kept live: the index must have shrunk AND the moved lines must be somewhere.
  before_lines=41
  [ "$(grep -c '^- \[' "$memd/MEMORY.md")" -lt "$before_lines" ]
  [ "$(grep -c '^- \[' "$proj/.claude/rules/agent-operating-lessons.md")" -gt 0 ]
}

@test "20 every failure surface exits 0 and emits nothing" {
  p="$(mkproj p20)"; proj="${p%|*}"; memd="${p#*|}"
  topic "$memd" "big.md" project
  run fire "$proj"
  ( cd "$memd" && printf -- '- [Big](big.md) — %s\n' "$(pad 700)" >>MEMORY.md )
  # no rotor on disk
  run env MEMORY_ROTATE_BIN="$T/nope" bash -c 'jq -nc --arg cwd "$1" "{session_id:\"s\",cwd:\$cwd}" | bash "$2"' _ "$proj" "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # cwd that resolves to no index at all
  run bash -c 'jq -nc "{session_id:\"s\",cwd:\"/\"}" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # empty stdin
  run bash -c ': | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── The rotor bound: a deadline that belongs to this hook, and can say why it fired ──────────────
# PRE-FIX BEHAVIOUR these three pin: the two `"$ROTOR" …` calls were unbounded under a DECLARED
# PostToolUse timeout of 10s, against an actuator measured at 118s on a forced breach. The harness
# kill is silent — stdout is discarded — so the operator got nothing in the one turn the index
# needed attention. Each case fails on the pre-fix hook: 21 on both the elapsed bound and the
# message, 22 on elapsed (two per-call bounds would multiply), 23 on the migration not existing.

@test "21 a slow rotor is CUT at the shared budget, and the cut is REPORTED not swallowed" {
  p="$(mkproj p21)"; proj="${p%|*}"; memd="${p#*|}"
  topic "$memd" "big.md" project
  stub="$T/slowrotor"; printf '#!/bin/bash\nsleep 60\n' >"$stub"; chmod +x "$stub"
  run fire "$proj"                      # baseline turn: record the stat
  [ "$status" -eq 0 ]
  ( cd "$memd" && printf -- '- [Big](big.md) — %s\n' "$(pad 700)" >>MEMORY.md )
  t0=$SECONDS
  run env MEMORY_ROTATE_BIN="$stub" MID_DEADLINE_S=2 \
      bash -c 'jq -nc --arg cwd "$1" "{session_id:\"s1\",cwd:\$cwd,tool_name:\"Bash\",tool_input:{command:\"true\"},tool_response:{exitCode:0}}" | bash "$2"' _ "$proj" "$HOOK"
  el=$(( SECONDS - t0 ))
  [ "$status" -eq 0 ]
  # the bound HELD: nowhere near the 60s the stub would have taken, and inside the declared timeout
  [ "$el" -lt 10 ]
  # and the operator is told, which is the half a harness kill can never do
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')"
  has "$ctx" "MEMORY INDEX DRAIN WAS CUT"
  hasnt "$ctx" "MEMORY INDEX DRAINED"
}

@test "22 the budget is SHARED across both call sites, so two slow calls cannot multiply it" {
  p="$(mkproj p22)"; proj="${p%|*}"; memd="${p#*|}"
  i=1
  while [ "$i" -le 40 ]; do add_entry "$memd" "e$i.md" 60; i=$(( i + 1 )); done
  run fire "$proj"
  [ "$status" -eq 0 ]
  # an over-cap entry (arms call site 1) on an index already past its LINE cap (arms call site 2)
  ( cd "$memd" && printf -- '- [Big](big.md) — %s\n' "$(pad 700)" >>MEMORY.md )
  stub="$T/slowrotor2"; printf '#!/bin/bash\nsleep 60\n' >"$stub"; chmod +x "$stub"
  t0=$SECONDS
  run env MEMORY_ROTATE_BIN="$stub" MID_DEADLINE_S=3 MEMORY_INDEX_LINE_LIMIT=20 \
      bash -c 'jq -nc --arg cwd "$1" "{session_id:\"s1\",cwd:\$cwd,tool_name:\"Bash\",tool_input:{command:\"true\"},tool_response:{exitCode:0}}" | bash "$2"' _ "$proj" "$HOOK"
  el=$(( SECONDS - t0 ))
  [ "$status" -eq 0 ]
  # NON-VACUOUS: both arms genuinely fired — the whole-index arm reports its own not-a-verdict,
  # so this is not a run in which only one call site was reached.
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')"
  has "$ctx" "MEMORY INDEX DRAIN WAS CUT"
  has "$ctx" "OVER ITS LOADER CAP"
  # NON-STARVATION: the whole-index arm RAN and was cut on its own share — it was not silently
  # zeroed by a slow first call, which a purely first-come budget would have done.
  has "$ctx" "Auto-rotation was CUT at its share"
  hasnt "$ctx" "did NOT run"
  # TOTAL, not per-call: two per-call bounds of 3s would put this at ~6s plus overhead.
  [ "$el" -lt 6 ]
}

@test "23 migration 0018 refuses to raise the declaration over an UNBOUNDED live hook" {
  MIG="$REPO/migrations/0018-memory-index-drain-rotor-budget.sh"
  [ -x "$MIG" ]
  live="$T/live0018"; mkdir -p "$live/hooks"
  # a live layer still holding a pre-fix copy: executable, and with no budget to spend
  printf '#!/bin/bash\nexit 0\n' >"$live/hooks/memory-index-drain.sh"
  chmod +x "$live/hooks/memory-index-drain.sh"
  cfg="$live/settings.json"
  jq -n '{hooks:{PostToolUse:[{matcher:"Bash|Write|Edit|MultiEdit",hooks:[{type:"command",command:"~/.claude/hooks/memory-index-drain.sh",timeout:10}]}]}}' >"$cfg"
  run env HOME="$live" CC_CLAUDE_DIR="$live" bash "$MIG"
  [ "$status" -ne 0 ]
  # the declaration is UNTOUCHED — raising it over an unbounded call would triple the stall
  run jq -r '.hooks.PostToolUse[0].hooks[0].timeout' "$cfg"
  [ "$output" = "10" ]
  # now the live copy carries the bound, and the same migration applies and self-verifies
  cp "$REPO/hooks/memory-index-drain.sh" "$live/hooks/memory-index-drain.sh"
  chmod +x "$live/hooks/memory-index-drain.sh"
  run env HOME="$live" CC_CLAUDE_DIR="$live" bash "$MIG"
  [ "$status" -eq 0 ]
  run jq -r '.hooks.PostToolUse[0].hooks[0].timeout' "$cfg"
  [ "$output" = "30" ]
  run jq -r '.env.MID_DEADLINE_S' "$cfg"
  [ "$output" = "24" ]
  # the budget must FIT the declaration it is spent under — that is the whole point of one edit
  run jq -e '(.env.MID_DEADLINE_S|tonumber) < .hooks.PostToolUse[0].hooks[0].timeout' "$cfg"
  [ "$status" -eq 0 ]
}

# ── The `already-cited` veto's own verdict (2026-09-09) ──────────────────────────────────────────
# `already-cited` landed in 5972228d5 with no counter arm and no verdict of its own, so it fell into
# `exhausted`/rc 4: the census printed every cause as zero, and the hook spent the `exhausted`
# branch — whose remedy is "append VERBATIM to the rules file" — on the one state where appending
# mints the duplicate the veto exists to prevent. Case 10 (rc 0 on an idempotent repeat) is the
# red-proof for the exit code; these three pin the parts it cannot see.

@test "24 every over-cap line vetoed already-cited is its OWN verdict, not exhausted" {
  d="$(mkmem cited24)"; dest="$(rules_dest)"
  add_entry "$d" "fat.md" 700
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" "verdict=drained"
  # paste it back: the destination now cites it, so the only veto in play is already-cited
  printf -- '- [fat](fat.md) — %s\n' "$(pad 700)" >>"$d/MEMORY.md"
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  has "$output" "verdict=already-cited"
  has "$output" "cited=1"
  hasnt "$output" "verdict=exhausted"
}

@test "25 a MIXED veto set stays exhausted, and its census NAMES the cited term" {
  d="$(mkmem cited25)"; dest="$(rules_dest)"
  add_entry "$d" "fat.md" 700
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 0 ]
  # one already-cited candidate + one the name convention vetoes absolutely
  printf -- '- [fat](fat.md) — %s\n' "$(pad 700)" >>"$d/MEMORY.md"
  add_entry "$d" "feedback-x.md" 700
  run "$ROTOR" "$d/MEMORY.md" --drain-oversized --rules-file "$dest"
  [ "$status" -eq 4 ]
  has "$output" "verdict=exhausted"
  has "$output" "oversized=2"
  has "$output" "type=1"
  # the term that stops this census pointing at the wrong line of code
  has "$output" "cited=1"
}

@test "26 the hook tells an already-cited operator to DELETE, never to append again" {
  p="$(mkproj p26)"; proj="${p%|*}"; memd="${p#*|}"
  topic "$memd" "twice.md" project
  run fire "$proj"
  ( cd "$memd" && printf -- '- [Twice](twice.md) — %s\n' "$(pad 700)" >>MEMORY.md )
  run fire "$proj"                       # drains it into the rules file
  [ "$status" -eq 0 ]
  ( cd "$memd" && printf -- '- [Twice](twice.md) — %s\n' "$(pad 700)" >>MEMORY.md )
  run fire "$proj"
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  has "$ctx" "ALREADY CITED"
  has "$ctx" "DELETE the MEMORY.md bullet"
  # the exhausted remedy must NOT be what this operator is handed
  hasnt "$ctx" "could NOT be routed automatically"
}

# ── the phantom second (2026-09-10) ──────────────────────────────────────────────────────────────
# `mid_charge` measures with `date +%s`, which is WHOLE-SECOND, so a call bounded at B returns after
# B and is charged B+1 whenever the pair straddles a tick — nothing overran, the clock ticked. On a
# 3s budget that single phantom second zeroes MID_LEFT and hands the second site rc=125, the silent
# zeroing MID_CAP exists to prevent, arriving through the MEASUREMENT rather than through the cap.
# Measured at the suite's own numbers (bound 2, SIGTERM-killable stub): charged 3 in 1/20 runs,
# which is case 22 failing 1-3/10 under load and 0/10 quiet — read as a flake for as long as it has
# existed, and blocking any land whose diff maps to this suite by basename.
#
# Driven as a UNIT with a forced t0 rather than by waiting for the race: the bug is arithmetic, so
# a test that sleeps for it would inherit the same 1-in-20 and be a flake about a flake.
_mid_units() {                        # the budget arithmetic, lifted with its real neighbours
  eval "$(sed -n '/^mid_charge() {/,/^}/p' "$HOOK")"
  MID_TB="${MID_TB_STUB:-/usr/bin/true}"     # "a bound WAS applied" — the clamp's precondition
}

@test "27 a bound call charged a phantom second does not zero its sibling's share" {
  _mid_units
  MID_LEFT=3; MID_CAP=2                       # MID_DEADLINE_S=3 ⇒ MID_CAP=(3+1)/2=2, as case 22
  mid_charge "$(( $(date +%s) - 3 ))"         # a 2s call whose clock read 3
  # RED PRE-FIX: charged 3, MID_LEFT=0, and site 2 gets rc=125 "rotor never invoked".
  [ "$MID_LEFT" -eq 1 ]
}

@test "28 CONTROL — a call that genuinely overran its bound is charged in FULL" {
  # The clamp must not become a licence to under-charge: with no timeout(1) mid_rotor runs
  # UNBOUNDED, so there is no bound to clamp to and the real spend is the only honest debit.
  _mid_units
  # Read by mid_charge, which _mid_units eval's in from the hook: shellcheck cannot see a consumer
  # it did not parse, and the alternative (export) would leak the fixture into every child. The
  # directive must be the LAST comment before the statement — an explanation BELOW it does not
  # attach, which is how the first attempt at this annotation still went red.
  # shellcheck disable=SC2034
  MID_TB="$T/no-such-timeout-binary"          # not executable ⇒ the call was never bounded
  MID_LEFT=10; MID_CAP=2
  mid_charge "$(( $(date +%s) - 7 ))"
  [ "$MID_LEFT" -eq 3 ]
}

@test "29 the clamp never lets one site spend more than the bound it was given" {
  _mid_units
  # Read by mid_charge, which _mid_units eval's in from the hook: shellcheck cannot see a consumer
  # it did not parse, and the alternative (export) would leak the fixture into every child. The
  # directive must be the LAST comment before the statement — an explanation BELOW it does not
  # attach, which is how the first attempt at this annotation still went red.
  MID_LEFT=24                                 # the post-0018 shape (declaration 30, budget 24)
  # shellcheck disable=SC2034
  MID_CAP=12
  mid_charge "$(( $(date +%s) - 99 ))"        # a wildly inflated reading
  [ "$MID_LEFT" -eq 12 ]                      # site 2 still holds its half, never zero
}
