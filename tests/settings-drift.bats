#!/usr/bin/env bats
# settings.json drift assertion across the 5 config dirs. The tool's --selftest RED-proves the
# detection mechanics; these bats drive it via CC_DRIFT_DIRS against fixture config dirs — the
# independent CLI-level regression on the exit contract (0 = agree, 1 = drift) and the report lines.

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh — the ratchet only shrinks, and it reached this
  # suite once siblings fixed theirs). The subject resolves config dirs under ~, so unfixtured this
  # suite reads the operator's LIVE settings and its verdict depends on the machine it runs on.
  # CC_DRIFT_DIRS already redirects what the tests assert; this closes the residue.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/settings-drift-assert.sh"
  D="$BATS_TEST_TMPDIR"
}
mkcfg() { # <dir> <deny-json-array> <stop-cmd>
  mkdir -p "$1"
  jq -n --argjson deny "$2" --arg cmd "$3" \
    '{permissions:{deny:$deny,ask:["Bash(git push:*)"]},hooks:{Stop:[{hooks:[{type:"command",command:$cmd}]}]}}' \
    > "$1/settings.json"
}

# CHANGED 2026-08-09 — was `-eq 6`, the class 404c832a retired for activation-watch (whose count had
# been bumped 7 → 14 → 18 → 26 by four commits that did nothing but ADD checks). An exact ok-count is
# a tripwire on the growth of the very suite it guards — the NUMBER, not a defect, is what gets
# "fixed" — and it never asserted the premise in its own name: `-eq 6` conflates "non-vacuous" with
# "exactly this many", so a reporter claiming 12 passed while rendering 6 `ok` lines sails through.
# What survives is that premise, as the two independent things that make a suite non-vacuous:
#   FLOOR — a DOWNWARD ratchet. Growth passes freely; a DELETED check reds, and lowering the floor has
#           to be a deliberate edit (memory: downward-ratchet-catches-the-over-scoped-marker).
#   TALLY — the summary's own `N passed` must equal the `  ok ` lines it actually rendered — the
#           vacuous-pass class this test is named for (memory: claimed-outcome-vs-checked-outcome).
# The count is environment-stable: 6 unconditional okp/badp sites, each emitting exactly one line.
@test "selftest passes, is non-vacuous (floor), and its tally matches what it rendered" {
  floor=6                         # raise when checks are added; LOWERING it is a deliberate act
  run "$S" --selftest
  [ "$status" -eq 0 ]
  # `|| true` normalizes grep's rc-1-on-zero-matches, which would otherwise abort the test HERE and
  # never reach the floor. It swallows no verdict — the count is data, the assertions are the verdict.
  ok_lines="$(printf '%s' "$output" | grep -c '^  ok ' || true)"
  claimed="$(printf '%s' "$output" | sed -n 's/^settings-drift-assert --selftest: \([0-9][0-9]*\) passed,.*/\1/p')"
  [ "$ok_lines" -ge "$floor" ]
  # Two statements, never `[ -n "$claimed" ] && [ ... ]`: in an `&&` list set -e sees only the command
  # after the FINAL `&&`, so a short-circuit on the left half is ABSORBED and an unparseable summary
  # would pass vacuously (tests/bats-assert-liveness.bats classifies that shape `and-absorbed`).
  [ -n "$claimed" ]
  [ "$claimed" = "$ok_lines" ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "unknown arg → exit 2" {
  run "$S" --bogus
  [ "$status" -eq 2 ]
}

@test "three agreeing config dirs → exit 0 (GREEN)" {
  mkcfg "$D/a" '["Bash(sudo:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  mkcfg "$D/b" '["Bash(sudo:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  mkcfg "$D/c" '["Bash(sudo:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  CC_DRIFT_DIRS="$D/a $D/b $D/c" run "$S" --assert
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'GREEN'
}

@test "a deny rule missing in one dir → exit 1, drift line names array + dir" {
  mkcfg "$D/a" '["Bash(sudo:*)","Bash(rm -rf /:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  mkcfg "$D/b" '["Bash(sudo:*)","Bash(rm -rf /:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  mkcfg "$D/c" '["Bash(sudo:*)"]'                     "~/.claude/hooks/anti-deference-nudge.sh"
  CC_DRIFT_DIRS="$D/a $D/b $D/c" run "$S" --assert
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -qE 'DRIFT \[deny\].*rm -rf'
  printf '%s' "$output" | grep -qE 'missing in:.* c'
}

@test "a Stop hook missing in one dir → exit 1 (the boundary-handoff-on-1/4-dirs class)" {
  mkcfg "$D/a" '["Bash(sudo:*)"]' "~/.claude/hooks/boundary-handoff.sh"
  mkcfg "$D/b" '["Bash(sudo:*)"]' "~/.claude/hooks/boundary-handoff.sh"
  jq -n '{permissions:{deny:["Bash(sudo:*)"],ask:["Bash(git push:*)"]},hooks:{Stop:[]}}' > "$D/x/settings.json" 2>/dev/null || { mkdir -p "$D/x"; jq -n '{permissions:{deny:["Bash(sudo:*)"],ask:["Bash(git push:*)"]},hooks:{Stop:[]}}' > "$D/x/settings.json"; }
  CC_DRIFT_DIRS="$D/a $D/b $D/x" run "$S" --assert
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -qE 'DRIFT \[hooks\].*boundary-handoff'
}

@test "path-spelling variants of the same hook are NOT drift (normalization)" {
  mkcfg "$D/a" '["Bash(sudo:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  mkcfg "$D/b" '["Bash(sudo:*)"]' "/Users/someone/.claude/hooks/anti-deference-nudge.sh"
  CC_DRIFT_DIRS="$D/a $D/b" run "$S" --assert
  [ "$status" -eq 0 ]
}

@test "fewer than 2 dirs with settings.json → nothing to compare (exit 0)" {
  mkcfg "$D/only" '["Bash(sudo:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  CC_DRIFT_DIRS="$D/only $D/nonexistent" run "$S" --assert
  [ "$status" -eq 0 ]
}
