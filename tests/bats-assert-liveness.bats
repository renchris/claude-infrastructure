#!/usr/bin/env bats
# bats-assert-liveness.py — the block-position analyzer for DEAD bats assertions, plus its
# companion fixer. A dead assertion is one whose failure cannot reach the test's exit status:
# bats runs bodies under `set -eET`, but bash exempts `[[ ]]`, `(( ))`, `! cmd`, and every
# NON-LAST element of an `&&` list from errexit — so in any position but last, those
# assertions are evaluated and then silently discarded.
#
# shellcheck is NOT a substitute: it does not flag `[[ ]]`/`(( ))` deadness at all. Deadness
# is a property of BLOCK POSITION, which is why this analyzer exists.
#
# The oracle for every liveness claim below is bats ITSELF: each fixture asserts something
# false, so a fixture that PASSES proves the assertion was discarded (dead) and one that
# FAILS proves it was honoured (live). Fixtures are built with printf, never a heredoc —
# bats' preprocessor strips `@test` inside a heredoc, which yields a vacuously green suite.
# Positive AND negative controls are asserted on every run.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AN="$REPO/scripts/bats-assert-liveness.py"
  FIX="$REPO/scripts/bats-assert-liveness-fix.py"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never touch the live ~/
  D="$BATS_TEST_TMPDIR"
}

# Write $2.. as lines of a bats file at $1.
mkbats() {
  local out="$1"; shift
  : > "$out"
  local line
  for line in "$@"; do printf '%s\n' "$line" >> "$out"; done
}

# A one-assertion @test block; $2 = the statement, $3 = "final" or "nonfinal".
mkblock() {
  local out="$1" stmt="$2" pos="$3"
  if [ "$pos" = final ]; then
    mkbats "$out" '@test "subject" {' "  $stmt" '}'
  else
    mkbats "$out" '@test "subject" {' "  $stmt" '  echo tail' '}'
  fi
}

# Count analyzer findings for a file.
findings() { python3 "$AN" --format count "$1"; }

# Does bats PASS the fixture? 0 = passed (⇒ assertion discarded ⇒ dead).
bats_passes() { bats "$1" >/dev/null 2>&1; }

# ── controls: the oracle itself must be trustworthy ─────────────────────────────
@test "CONTROL positive — a plainly false body FAILS under bats" {
  mkbats "$D/c.bats" '@test "x" {' '  false' '}'
  run bats_passes "$D/c.bats"
  [ "$status" -ne 0 ]
}

@test "CONTROL negative — a true body PASSES, and is not flagged" {
  mkbats "$D/c.bats" '@test "x" {' '  true' '}'
  run bats_passes "$D/c.bats"
  [ "$status" -eq 0 ]
  [ "$(findings "$D/c.bats")" -eq 0 ]
}

# ── the dead classes, each cross-checked against the bats oracle ────────────────
@test "non-final [[ ]] is dead — bats passes it, analyzer flags it" {
  mkblock "$D/t.bats" '[[ 1 -eq 2 ]]' nonfinal
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]                    # passed despite a false assertion ⇒ dead
  [ "$(findings "$D/t.bats")" -eq 1 ]
}

@test "non-final (( )) is dead — bats passes it, analyzer flags it" {
  mkblock "$D/t.bats" '(( 0 ))' nonfinal
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]
  [ "$(findings "$D/t.bats")" -eq 1 ]
}

@test "non-final bare-! is dead — bats passes it, analyzer flags it" {
  mkblock "$D/t.bats" '! true' nonfinal
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]
  [ "$(findings "$D/t.bats")" -eq 1 ]
}

@test "non-final assertion absorbed by && is dead, for ANY left-hand command" {
  # POSIX exempts every non-last element of an AND-OR list, so even `[ ]` dies here —
  # the class the shellcheck-based survey missed entirely.
  mkblock "$D/t.bats" '[ 1 -eq 2 ] && echo hi' nonfinal
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]
  [ "$(findings "$D/t.bats")" -eq 1 ]
}

@test "a pipeline-shaped && left side is caught too" {
  mkblock "$D/t.bats" 'echo hay | grep -q needle && echo hi' nonfinal
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]
  [ "$(findings "$D/t.bats")" -eq 1 ]
}

# ── the LIVE forms: must never be flagged (false positives cost real edits) ─────
@test "non-final [ ] is LIVE — bats fails it, analyzer stays silent" {
  mkblock "$D/t.bats" '[ 1 -eq 2 ]' nonfinal
  run bats_passes "$D/t.bats"
  [ "$status" -ne 0 ]                    # honoured ⇒ live
  [ "$(findings "$D/t.bats")" -eq 0 ]
}

@test "FINAL [[ ]] / (( )) / bare-! are LIVE — position is what kills them" {
  for stmt in '[[ 1 -eq 2 ]]' '(( 0 ))' '! true'; do
    mkblock "$D/t.bats" "$stmt" final
    run bats_passes "$D/t.bats"
    [ "$status" -ne 0 ] || false
    [ "$(findings "$D/t.bats")" -eq 0 ] || false
  done
}

@test "the || false idiom is LIVE and is never re-flagged (idempotence)" {
  for stmt in '[[ 1 -eq 2 ]] || false' '! true || false'; do
    mkblock "$D/t.bats" "$stmt" nonfinal
    run bats_passes "$D/t.bats"
    [ "$status" -ne 0 ] || false
    [ "$(findings "$D/t.bats")" -eq 0 ] || false
  done
}

@test "condition position is not an assertion — if/while/until/for are exempt" {
  mkbats "$D/t.bats" '@test "x" {' \
    '  if [[ 1 -eq 2 ]]; then echo no; fi' \
    '  while [[ 1 -eq 2 ]]; do break; done' \
    '  until [[ 1 -eq 1 ]]; do break; done' \
    '  for ((i = 0; i < 2; i++)); do :; done' \
    '  true' '}'
  [ "$(findings "$D/t.bats")" -eq 0 ]
}

@test "a heredoc body is never analyzed as this file's own assertions" {
  # A fixture that WRITES bats source must not be mistaken for source.
  mkbats "$D/t.bats" '@test "x" {' '  cat > "$BATS_TEST_TMPDIR/gen.bats" <<EOF' \
    '  [[ 1 -eq 2 ]]' '  ! true' 'EOF' '  true' '}'
  [ "$(findings "$D/t.bats")" -eq 0 ]
}

# The test above used `<<EOF`. The repo's DOMINANT form is `<<'EOF'` (60 of 189 suites), and it
# was BROKEN while that test passed — a fixture-shape parity gap, not a missing test. The opener
# was detected on `strip_quoted(raw)`, which blanks the CONTENTS of quoted spans; `<<'EOS'` became
# `<<'   '`, no delimiter matched, and the skip never started. Every quoted-heredoc body was then
# analyzed as this file's own assertions — 4 live false positives in tests/alarm-polarity-lint.bats,
# whose ` || false` remedy would have edited the FIXTURE, changing the subject a lint-under-test is
# asked about. Both delimiter forms are pinned from here on, in both directions.
@test "a QUOTED-delimiter heredoc body is never analyzed either (<<'EOF' is the common form)" {
  mkbats "$D/t.bats" '@test "x" {' "  cat > \"\$D/gen.sh\" <<'EOS'" \
    '  [[ 1 -eq 2 ]]' '  ! true' 'EOS' '  true' '}'
  [ "$(findings "$D/t.bats")" -eq 0 ]
  # …and the real shape that regressed: an && whose RHS is a command, inside a quoted heredoc.
  mkbats "$D/r.bats" '@test "x" {' "  cat > \"\$D/ok.sh\" <<'EOS'" \
    '[ "$notgreen" -eq "$seen" ] && echo ALARM' 'EOS' '  true' '}'
  [ "$(findings "$D/r.bats")" -eq 0 ]
}

@test "a <<-'EOF' (tab-stripped, quoted) body is skipped, and its indented terminator closes it" {
  mkbats "$D/t.bats" '@test "x" {' "  cat > \"\$D/gen.sh\" <<-'EOS'" \
    '  [[ 1 -eq 2 ]]' "$(printf '\tEOS')" '  [[ 1 -eq 3 ]]' '  true' '}'
  # The body is skipped; the [[ ]] AFTER the terminator is real code and must still be reported —
  # a skip that never terminates would swallow it and read as a clean file.
  [ "$(findings "$D/t.bats")" -eq 1 ]
  python3 "$AN" --format tsv "$D/t.bats" | grep -q '1 -eq 3' || false
}

@test "a <<EOF inside a QUOTED STRING opens nothing — string data is not syntax" {
  # The other direction, and the reason the opener cannot simply be matched on the raw line: a
  # fixture that PRINTS shell source contains `<<EOF` as data. Treating it as an opener starts a
  # skip that never terminates and silently swallows the rest of the block (the original defect).
  mkbats "$D/t.bats" '@test "x" {' "  printf 'cat <<EOF\\n' > \"\$D/w.sh\"" \
    '  [[ 1 -eq 2 ]]' '  true' '}'
  [ "$(findings "$D/t.bats")" -eq 1 ]
}

@test "a herestring is not a heredoc — <<< opens no skip" {
  mkbats "$D/t.bats" '@test "x" {' '  grep -q x <<< "$output"' '  [[ 1 -eq 2 ]]' '  true' '}'
  [ "$(findings "$D/t.bats")" -eq 1 ]
}

@test "[[ A && B ]] is ONE conditional, not an AND-OR list" {
  mkblock "$D/t.bats" '[[ 1 -eq 1 && 1 -eq 2 ]]' nonfinal
  [ "$(findings "$D/t.bats")" -eq 1 ]
  python3 "$AN" --format tsv "$D/t.bats" | grep -q 'cond-keyword' || false
}

# ── the fixer ──────────────────────────────────────────────────────────────────
@test "fixer revives a dead assertion — the test then FAILS as intended" {
  mkblock "$D/t.bats" '[[ 1 -eq 2 ]]' nonfinal
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]                    # dead before
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 0 ]
  grep -q '\[\[ 1 -eq 2 \]\] || false' "$D/t.bats"
  run bats_passes "$D/t.bats"
  [ "$status" -ne 0 ]                    # live after
  [ "$(findings "$D/t.bats")" -eq 0 ]
}

@test "fixer preserves \$output — the run+status rewrite would not" {
  mkbats "$D/t.bats" 'helper(){ return 1; }' '@test "x" {' \
    '  run echo MARKER' '  ! helper' '  echo "$output" | grep -q MARKER' '}'
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 0 ]
  # The later $output assertion still sees the ORIGINAL run output ⇒ test passes.
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]
  grep -q '! helper || false' "$D/t.bats"
}

@test "fixer keeps a trailing comment, and is idempotent" {
  mkbats "$D/t.bats" '@test "x" {' '  ! true          # must not fire' '  echo tail' '}'
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 0 ]
  grep -q '! true || false' "$D/t.bats"
  grep -q '# must not fire' "$D/t.bats"
  before="$(cat "$D/t.bats")"
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 0 ]
  [ "$before" = "$(cat "$D/t.bats")" ]
}

@test "--dry-run reports without writing" {
  mkblock "$D/t.bats" '! true' nonfinal
  before="$(cat "$D/t.bats")"
  run python3 "$FIX" --dry-run "$D/t.bats"
  [ "$status" -eq 0 ]
  [ "$before" = "$(cat "$D/t.bats")" ]
  [ "$(findings "$D/t.bats")" -eq 1 ]
}

# ── the ratchet: the real suite must stay at zero ───────────────────────────────
@test "RATCHET — tests/ contains no dead assertions" {
  cd "$REPO"
  run python3 "$AN" --summary
  [ "$status" -eq 0 ] || {
    printf 'dead assertions reintroduced:\n%s\n' "$output"
    printf 'fix with: python3 scripts/bats-assert-liveness-fix.py\n'
    return 1
  }
}

# ── the negative-assertion family: `A && false` ───────────────────────────────────────────────
# `A && false` means "fail if A matches", and in NON-FINAL position it ALREADY WORKS: `false` is
# the command following the final `&&`, so errexit is NOT exempt for it. Verified directly:
#     bash -ec 'echo hit   | grep -q hit  && false; echo TAIL'  → exit 1, TAIL unreached
#     bash -ec 'echo clean | grep -q NOPE && false; echo TAIL'  → exit 0, TAIL reached
# The analyzer flags it `and-absorbed` anyway — a FALSE POSITIVE, because it reads `A` as the
# assertion being swallowed, which is true for `A && <cmd>` but inverted when the RHS is `false`.
# That made the uniform ` || false` append actively destructive: `A && false || false` fails on
# BOTH paths, turning a passing test permanently red (it blocked a real land, 2026-07-26).
# The rewrite `! A || false` is equivalent for a match, correct for a non-match, and — unlike the
# original — also correct in FINAL position, where `A && false` returns A's non-zero status.
#
# These fixtures pin BOTH directions. A one-directional test is what let the defect through: the
# revival test above uses an already-FALSE condition, under which "correct" and "always fails"
# are the same observation.

@test "fixer: 'A && false' with a NON-matching condition still PASSES after the rewrite" {
  mkblock "$D/t.bats" 'echo clean | grep -q NOPE && false' nonfinal
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]                                                    # correct BEFORE
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 0 ]
  grep -qF '! echo clean | grep -q NOPE || false' "$D/t.bats"            # negation, not an append
  [ "$(grep -cF '&& false || false' "$D/t.bats")" -eq 0 ]                # the destructive form
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]                                                    # STILL correct AFTER
  [ "$(findings "$D/t.bats")" -eq 0 ]
}

@test "fixer: 'A && false' with a MATCHING condition still FAILS after the rewrite" {
  mkblock "$D/t.bats" 'echo hit | grep -q hit && false' nonfinal
  run bats_passes "$D/t.bats"
  [ "$status" -ne 0 ]                                                    # already live BEFORE
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 0 ]
  grep -qF '! echo hit | grep -q hit || false' "$D/t.bats"
  run bats_passes "$D/t.bats"
  [ "$status" -ne 0 ]                                                    # still fails AFTER
  [ "$(findings "$D/t.bats")" -eq 0 ]
}
