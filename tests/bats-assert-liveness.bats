#!/usr/bin/env bats
# bats-assert-liveness.py — the block-position analyzer for DEAD bats assertions, plus its
# companion fixer. A dead assertion is one whose failure cannot reach the test's exit status:
# bats runs bodies under `set -eET`, but bash exempts `[[ ]]`, `(( ))`, `! cmd`, and every
# NON-LAST element of an `&&` list from errexit — so in any position but last, those
# assertions are evaluated and then silently discarded.
#
# ShellCheck is NOT a substitute: it does not flag `[[ ]]`/`(( ))` deadness at all. Deadness
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

# `for ((…))` above is only ONE of the two ways a `((` is not an assertion. The other is
# arithmetic EXPANSION — `$(( … ))`, a value with no exit status of its own. RE_ARITH_OPEN's
# lookbehind exempts the expansion's own `((` (the `$` is adjacent) but is blind one level
# down: an inner `((` is preceded by `(`, which is neither `\w` nor `$`. So a nested
# expansion inside a plain ASSIGNMENT was reported `DEAD [arith]` — a false RED that blocked
# a real commit on 2026-08-08, whose only workaround was flattening correct arithmetic into
# two statements. Both directions are pinned here: the expansion must go quiet, and a bare
# `(( ))` assertion must keep being caught, because a lint that cannot fail is worth nothing.
@test "arithmetic NESTED inside a \$(( )) expansion is a value, not a dead assertion" {
  mkblock "$D/t.bats" 'averaged=$(( ((total - LIMIT) / (entry_b / n)) + 1 ))' nonfinal
  [ "$(findings "$D/t.bats")" -eq 0 ]

  # The oracle: it is an assignment, so it CANNOT fail — the fixture passes with the
  # arithmetic intact, and the value it produced is what a real assertion would judge.
  mkbats "$D/o.bats" '@test "x" {' \
    '  total=9 LIMIT=1 entry_b=4 n=1' \
    '  averaged=$(( ((total - LIMIT) / (entry_b / n)) + 1 ))' \
    '  [ "$averaged" -eq 3 ]' '}'
  run bats_passes "$D/o.bats"
  [ "$status" -eq 0 ]

  # Depth beyond one level, and an expansion sharing a line with other code, stay quiet too.
  mkblock "$D/d.bats" 'x=$(( (((a+b)*c) - (d/(e+1))) % 7 ))' nonfinal
  [ "$(findings "$D/d.bats")" -eq 0 ]
  mkblock "$D/e.bats" 'echo "$(( ((a - b) / c) + 1 ))" > "$D/out"' nonfinal
  [ "$(findings "$D/e.bats")" -eq 0 ]
}

@test "CONTROL — a genuine bare (( )) assertion is still flagged beside an expansion" {
  # Green before the fix and after it: masking must be aimed at the EXPANSION class only.
  mkblock "$D/t.bats" 'n=$(( ((a - b) / c) + 1 )) && (( n == 2 ))' nonfinal
  [ "$(findings "$D/t.bats")" -eq 1 ]

  # …and the plain bare form, cross-checked against the bats oracle: it asserts something
  # false, bats passes it anyway ⇒ discarded ⇒ dead, and the analyzer must say so.
  mkblock "$D/b.bats" '(( 1 == 2 ))' nonfinal
  run bats_passes "$D/b.bats"
  [ "$status" -eq 0 ]
  [ "$(findings "$D/b.bats")" -eq 1 ]
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

# ── the same family, brace-group spelling: `A && { …; false; }` ────────────────────────────────
# The bare `A && false` above is the RARE spelling. The one this corpus actually writes carries
# the author's diagnostic — 534 `|| { …; false; }` sites in tests/ against 2 bare `|| false` — and
# the classifier knew only the bare one, so every brace-group member fell through to the uniform
# append. That append is not a weaker repair, it is a destructive one: `A && { …; false; } || false`
# fails on BOTH branches, because A-matches and A-does-not-match now reach the same trailing
# `false`. It cost a real land — P2 of tests/handoff-fire-capacity-gate.bats went red against a
# WORKING fix (752024be) — and the fixer still printed "analyzer now reports 0 dead assertions",
# a false all-clear over a file it had just corrupted.
#
# BOTH directions are pinned for the same reason the bare pair is: against an already-false
# condition, "correctly revived" and "always fails" are the same observation.

@test "fixer: 'A && { …; false; }' with a NON-matching condition still PASSES after the rewrite" {
  mkblock "$D/t.bats" 'echo clean | grep -q NOPE && { echo DIAG; false; }' nonfinal
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]                                                    # correct BEFORE
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 0 ]
  grep -qF '! echo clean | grep -q NOPE || { echo DIAG; false; }' "$D/t.bats"
  [ "$(grep -cF '} || false' "$D/t.bats")" -eq 0 ]                       # the destructive form
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]                                                    # STILL correct AFTER
  [ "$(findings "$D/t.bats")" -eq 0 ]
}

@test "fixer: 'A && { …; false; }' with a MATCHING condition still FAILS after the rewrite" {
  mkblock "$D/t.bats" 'echo hit | grep -q hit && { echo DIAG; false; }' nonfinal
  run bats_passes "$D/t.bats"
  [ "$status" -ne 0 ]                                                    # already live BEFORE
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 0 ]
  grep -qF '! echo hit | grep -q hit || { echo DIAG; false; }' "$D/t.bats"
  run bats_passes "$D/t.bats"
  [ "$status" -ne 0 ]                                                    # still fails AFTER
  [ "$(findings "$D/t.bats")" -eq 0 ]
}

# The RHS is classified STRUCTURALLY, not by spelling — a spelling list is a list of the shapes
# you already got wrong. These three are the same family in three other clothes, and each one
# would have fallen through to the destructive append under a `&& false`-shaped regex.
@test "fixer: the never-succeeds RHS is recognised past its spelling" {
  local stmt
  for stmt in 'echo clean | grep -q NOPE && { echo DIAG; false; } || true' \
              'echo clean | grep -q NOPE && { echo DIAG; return 1; }' \
              'echo clean | grep -q NOPE && ( echo DIAG; false )'; do
    mkblock "$D/t.bats" "$stmt" nonfinal
    run bats_passes "$D/t.bats"
    [ "$status" -eq 0 ] || { echo "not green BEFORE: $stmt"; false; }
    run python3 "$FIX" "$D/t.bats"
    [ "$status" -eq 0 ] || { echo "fixer rc=$status on: $stmt"; false; }
    grep -qF '! echo clean | grep -q NOPE ||' "$D/t.bats" || { echo "not negated: $(sed -n 2p "$D/t.bats")"; false; }
    run bats_passes "$D/t.bats"
    [ "$status" -eq 0 ] || { echo "went RED after the rewrite: $stmt"; false; }
    [ "$(findings "$D/t.bats")" -eq 0 ] || { echo "still dead: $stmt"; false; }
  done
}

# The `;` before `}` is MANDATORY in bash, so a group's final segment is EMPTY. Reading that
# terminator as the group's last STATEMENT made every real-world member unclassifiable — the
# fixer declined instead of repairing. This case catches that where the two above cannot: it
# also plants a decoy `false` in a non-final statement, which a "contains the word" classifier
# would swallow and a structural one must ignore.
@test "fixer: a brace group's status is its last statement, not its terminator" {
  mkblock "$D/t.bats" 'echo clean | grep -q NOPE && { echo false-ish; echo DIAG; false; }' nonfinal
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 0 ]
  grep -qF '! echo clean | grep -q NOPE || { echo false-ish; echo DIAG; false; }' "$D/t.bats"
}

@test "fixer DECLINES a shape it cannot prove, rather than emitting a wrong repair" {
  # `!` negates ONE pipeline, so `! (X || Y)` is not `! X || Y`. There is no correct one-line
  # rewrite here, and the append is the destructive one — so the only safe answer is neither.
  mkblock "$D/t.bats" 'echo a | grep -q a || echo b | grep -q b && { echo DIAG; false; }' nonfinal
  before="$(cat "$D/t.bats")"
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 2 ]                                    # loud, not a silent skip
  [ "$before" = "$(cat "$D/t.bats")" ]                   # and it wrote NOTHING
  echo "$output" | grep -q 'DECLINED' || false
}

# The scanner must not read a construct's INNER `&&` as a list separator: splitting there would
# rewrite `[[ 1 -eq 1 && 1 -eq 2 ]]` into something that asserts a different thing entirely.
@test "fixer: '&&' inside [[ ]] is not a list separator" {
  mkblock "$D/t.bats" '[[ 1 -eq 1 && 1 -eq 2 ]]' nonfinal
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 0 ]
  grep -qF '[[ 1 -eq 1 && 1 -eq 2 ]] || false' "$D/t.bats"
  run bats_passes "$D/t.bats"
  [ "$status" -ne 0 ]                                    # live after
}

# ── line continuations: a finding names a LINE, the repair belongs to the STATEMENT ────────────
# `\` continuations are this corpus's norm — 201 of the suites use them — and both layers used to
# judge only the finding's FIRST physical line. That is wrong in both directions at once:
#
#     ! grep -q X "$F" \
#         || { echo diag; false; }
#
# reads as a bare dead negation on line 1, while the statement it heads is LIVE. The analyzer
# reported it, and the fixer then appended ` || false` AFTER the backslash — which escapes the
# SPACE instead of continuing the line, stranding `|| { … }` as a statement beginning with an
# operator. Measured 2026-08-03 on tests/teammate-auto-shutdown.bats: 30 ok → 0 ok, and the fixer
# exited 0 announcing "0 dead assertions" over the file it had just broken.
#
# `[ "$status" -eq 0 ]` cannot catch that: bats exits 0 on a file whose tests all vanished. The
# assertion below is `ok 1` in the TAP stream, because a corrupted body renders `1..0` — a
# NON-VERDICT that reads exactly like success.

@test "continued: a live '! A \\ || { …; false; }' is neither reported nor touched" {
  mkbats "$D/t.bats" '@test "x" {' \
    "  ! echo clean | grep -q NOPE \\" \
    '      || { echo DIAG; false; }' \
    '  echo tail' '}'
  [ "$(findings "$D/t.bats")" -eq 0 ]                    # the statement is live ⇒ nothing to report
  before="$(cat "$D/t.bats")"
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 0 ]
  [ "$before" = "$(cat "$D/t.bats")" ]                   # byte-identical: no ` \ || false`
  run bats "$D/t.bats"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^ok 1' || false              # the test still RAN — not `1..0`
}

# The fixture above asserts something that does NOT hold, so "live" and "never fires" look the
# same there. This is the other direction: the identical shape with a MATCHING condition must
# fail the test, which is what makes the pair above evidence rather than decoration.
@test "continued: the same statement with a MATCHING condition FAILS — the pair is not vacuous" {
  mkbats "$D/t.bats" '@test "x" {' \
    "  ! echo hit | grep -q hit \\" \
    '      || { echo DIAG; false; }' \
    '  echo tail' '}'
  run bats_passes "$D/t.bats"
  [ "$status" -ne 0 ]
  [ "$(findings "$D/t.bats")" -eq 0 ]
}

# A genuinely dead multi-line statement still gets repaired — the append lands on the statement's
# LAST physical line, where it joins the same AND-OR list. Both continuation spellings are pinned:
# a trailing `\`, and a trailing `&&` (which continues across the newline all by itself).
@test "continued: a DEAD multi-line statement is revived on its LAST line, not its head" {
  local pair
  for pair in '  [[ 1 -eq 1 ]] \|      && [[ 1 -eq 2 ]]' \
              '  [[ 1 -eq 1 ]] &&|      [[ 1 -eq 2 ]]'; do
    mkbats "$D/t.bats" '@test "x" {' "${pair%%|*}" "${pair##*|}" '  echo tail' '}'
    run bats_passes "$D/t.bats"
    [ "$status" -eq 0 ] || { echo "not dead BEFORE: $pair"; false; }
    [ "$(findings "$D/t.bats")" -eq 1 ] || { echo "not reported: $pair"; false; }
    run python3 "$FIX" "$D/t.bats"
    [ "$status" -eq 0 ] || { echo "fixer rc=$status on: $pair"; false; }
    grep -qF '[[ 1 -eq 2 ]] || false' "$D/t.bats" || { echo "not on the last line: $(cat "$D/t.bats")"; false; }
    [ "$(grep -c '\\ || false' "$D/t.bats")" -eq 0 ] || { echo "appended AFTER a continuation"; false; }
    run bats_passes "$D/t.bats"
    [ "$status" -ne 0 ] || { echo "still dead AFTER: $pair"; false; }
    [ "$(findings "$D/t.bats")" -eq 0 ] || { echo "still reported: $pair"; false; }
    before="$(cat "$D/t.bats")"
    run python3 "$FIX" "$D/t.bats"
    [ "$before" = "$(cat "$D/t.bats")" ] || { echo "not idempotent across the join"; false; }
  done
}

# The negation rewrite RE-FORMS the statement around a new `!`/`||`. Across lines there is no
# faithful re-flow of that onto a split the author chose, so it is reported for a hand-edit —
# with both usable forms printed — rather than guessed at. Declining is the whole point: the
# alternative to a repair this script cannot derive is a human, not a plausible-looking edit.
@test "continued: a repair that RE-FORMS the statement is DECLINED across lines, never guessed" {
  mkbats "$D/t.bats" '@test "x" {' \
    "  echo clean | grep -q NOPE \\" \
    '      && { echo DIAG; false; }' \
    '  echo tail' '}'
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]                                    # correct BEFORE
  before="$(cat "$D/t.bats")"
  run python3 "$FIX" "$D/t.bats"
  [ "$status" -eq 2 ]                                    # loud, not a silent skip
  [ "$before" = "$(cat "$D/t.bats")" ]                   # and it wrote NOTHING
  echo "$output" | grep -q 'DECLINED' || false
  echo "$output" | grep -qF '! echo clean | grep -q NOPE || { echo DIAG; false; }' || false
  echo "$output" | grep -qF 'if echo clean | grep -q NOPE; then' || false
  run bats_passes "$D/t.bats"
  [ "$status" -eq 0 ]                                    # STILL correct AFTER
}
