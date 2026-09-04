#!/usr/bin/env bats
# memory-fleet-sweep.sh — the fleet-wide measurement the machine did not have.
#
# The defect this pins: hooks/memory-nudge.sh resolves the index from the SESSION'S OWN cwd, so
# only the project you happen to have open is ever measured — while cc-memory-rotate's header
# claims "the next prompt ANYWHERE rotates it back under budget". Measured 2026-09-03,
# doc-classifier sat 2,256 units over the cap for ELEVEN DAYS with its 9 newest memories loading
# in zero sessions, archive/ and .rotate.log both absent, and no launchd or cron job watching.
#
# RED-proof coverage: DARK is proven in BOTH directions on hand-built fixtures (a metric that only
# ever reads 0 proves nothing — the over-cap fixture must produce a non-zero DARK); report-only is
# proven by byte-comparison, not by absence of a message; the tmp-fixture exclusion is proven to be
# COUNTED rather than silent; and the dedupe is exercised through two config dirs pointing at one
# tree, which is the live shape (.claude and .claude-quaternary resolve together here).
#
# Assertions are simple commands only. bash exempts `[[ ]]` from errexit, so a non-final `[[ ]]`
# evaluates and DISCARDS its result (scripts/bats-assert-liveness.py).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO/scripts/memory-fleet-sweep.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { if printf '%s' "$1" | grep -qF -- "$2"; then return 1; fi; }

# mkidx <config-dir-name> <slug> <n-entries> <entry-pad> → an index with n entries of a given size
mkidx() {
  local cfg="$HOME/$1" slug="$2" n="$3" pad="$4" d i
  d="$cfg/projects/$slug/memory"; mkdir -p "$d"
  printf '# Project Memory\n' >"$d/MEMORY.md"
  i=0
  while [ "$i" -lt "$n" ]; do
    printf -- '- [e%02d %s](e%02d.md) — hook\n' "$i" "$(head -c "$pad" /dev/zero | tr '\0' x)" "$i" >>"$d/MEMORY.md"
    printf -- '---\nname: e%02d\nmetadata:\n  type: project\n---\nbody\n' "$i" >"$d/e$(printf '%02d' $i).md"
    i=$(( i + 1 ))
  done
  printf '%s' "$d/MEMORY.md"
}

@test "a healthy fleet reports ok and exits 0" {
  mkidx .claude proj-small 3 40 >/dev/null
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  has "$output" 'proj-small'
  has "$output" '0 over cap'
}

@test "DARK is non-zero for an over-cap index — the whole point of the tool" {
  # 40 entries × ~700 chars ≈ 28,000 > the 25,000 cap, so the tail entries start past the cut and
  # load in NO session. If DARK reported 0 here the metric would be decorative.
  mkidx .claude proj-over 40 700 >/dev/null
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  has "$output" 'OVER'
  has "$output" '1 over cap'
  # the DARK column for that row must be a positive integer
  dark="$(printf '%s' "$output" | awk '/proj-over/ {print $5}')"
  [ "$dark" -gt 0 ]
}

@test "DARK is zero for an index that fits — the negative control on the same metric" {
  mkidx .claude proj-fits 10 200 >/dev/null
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  dark="$(printf '%s' "$output" | awk '/proj-fits/ {print $5}')"
  [ "$dark" -eq 0 ]
}

@test "report-only by default: the index is byte-identical after a sweep of an OVER index" {
  idx="$(mkidx .claude proj-ro 40 700)"
  cp "$idx" "$BATS_TEST_TMPDIR/ro.before"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  cmp -s "$idx" "$BATS_TEST_TMPDIR/ro.before"
}

@test "the entries column is a single number — grep -c prints 0 AND exits 1" {
  # An index with a header and no entry bullets at all. `|| printf 0` on a grep -c that already
  # printed its own 0 rendered the column as two lines and shifted every column after it.
  d="$HOME/.claude/projects/proj-empty/memory"; mkdir -p "$d"
  printf '# Project Memory\n' >"$d/MEMORY.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'proj-empty')" -eq 1 ]
  [ "$(printf '%s' "$output" | awk '/proj-empty/ {print NF}')" -eq 6 ]
}

@test "tmp probe fixtures are skipped, and the skip is COUNTED not silent" {
  mkidx .claude -private-tmp-memprobe-row9 40 700 >/dev/null
  mkidx .claude proj-real 3 40 >/dev/null
  run "$SCRIPT"
  [ "$status" -eq 0 ]                      # the fixture must not make the fleet look breached
  hasnt "$output" 'memprobe-row9'
  has "$output" '1 tmp fixture(s) skipped'
}

@test "one tree reached through two config dirs is swept ONCE" {
  mkidx .claude proj-dup 3 40 >/dev/null
  ln -s "$HOME/.claude" "$HOME/.claude-quaternary"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'proj-dup')" -eq 1 ]
  has "$output" '1 index(es) swept'
}

@test "--rotate acts only on the OVER index, and leaves the healthy one alone" {
  over="$(mkidx .claude proj-hot 40 700)"
  fine="$(mkidx .claude proj-cool 3 40)"
  cp "$fine" "$BATS_TEST_TMPDIR/cool.before"
  before_hot="$(wc -c <"$over" | tr -d ' ')"
  run "$SCRIPT" --rotate
  has "$output" 'rotating'
  cmp -s "$fine" "$BATS_TEST_TMPDIR/cool.before"
  # The hot index may shrink (rotated) or hold (every entry protected), but a sweep must NEVER
  # grow one — and asserting that is what makes capturing the path meaningful rather than dead.
  after_hot="$(wc -c <"$over" | tr -d ' ')"
  [ "$after_hot" -le "$before_hot" ]
  # the rotor is the only thing that may have touched the hot one; either it rotated or it
  # reported a verdict, but the tool must not have silently rewritten anything itself
  has "$output" 'verdict='
}

@test "invoked THROUGH a symlink it still finds the real repo root" {
  # scripts/self-path-lint.sh ratchets this scar and caught this file on its first land attempt.
  # Reached as ~/.claude/scripts/memory-fleet-sweep.sh, a bare `dirname "$0"/..` derives ~/.claude
  # as the root and resolves the measure lib and the rotor to the wrong tree — silently, because
  # the symlink farm makes wrong-but-present the likely outcome rather than a clean failure.
  mkdir -p "$BATS_TEST_TMPDIR/farm"
  ln -sf "$SCRIPT" "$BATS_TEST_TMPDIR/farm/memory-fleet-sweep.sh"
  mkidx .claude proj-link 3 40 >/dev/null
  run bash "$BATS_TEST_TMPDIR/farm/memory-fleet-sweep.sh"
  [ "$status" -eq 0 ]
  has "$output" 'proj-link'
}
