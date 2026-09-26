#!/usr/bin/env bats
# tests/desk-assert-wiring.bats — T-P11-6: the LIVE-WIRING leg (design law #10) for bin/desk-assert.
#
# desk-assert (the FM2 grounding-triad guard, tests/desk-assert.bats) shipped with SELFTESTS ONLY and
# NO production caller — the plan's "capability-green ≠ active" gap. This suite asserts the wiring that
# makes the guard actually RUN in prod, so a future edit cannot silently regress it back to a dead
# capability or the discipline-only prose it replaces:
#
#   (1) INSTALL leg   — desk-assert lands on PATH via install.sh's PATH-tools pass (the bin/desk-*
#                       glob), so the resident rule's `desk-assert <sid>` resolves in prod (not
#                       command-not-found).
#   (2) GUARD leg     — bin/desk-assert exists, is executable, and is invocable (--help exits 0).
#   (3) RESIDENT-RULE — the canned boot brief the LIVE desk-invariant fires from (docs/templates/
#       leg             desk-boot-brief.md, per scripts/desk-invariant.sh:48) NAMES + INVOKES
#                       `desk-assert <sid> [--witnessed-ref <ref>]` as the executable grounding check
#                       the desk RUNS before any state/causal claim about another session (law #9),
#                       with the UNGROUNDED verdict = claim-not-earned. This is the leg that turns the
#                       prose triad ("keep two-way comms grounded") into a run-the-executable rule.
#
# RED-provable: revert the boot-brief invocation to bare prose and every RESIDENT-RULE test goes red;
# drop bin/desk-* from install.sh's PATH-tools glob and the INSTALL test goes red.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DA="$REPO/bin/desk-assert"
  BRIEF="$REPO/docs/templates/desk-boot-brief.md"
}

# ── (1) INSTALL leg ───────────────────────────────────────────────────────────────────────────
@test "install: install.sh's PATH-tools pass selects desk-assert (resolves on PATH in prod)" {
  # Prod ~/.claude/bin is populated by install.sh's PATH-tools loop, not by the run-by-hand
  # docs/activation/wiring-all.sh. EXTRACT that loop's own header and run it over the real bin/ with a
  # recording body in place of link_file, so a restated glob cannot drift from the one that ships.
  # shellcheck disable=SC2016  # the needle IS the literal header text, $REPO_DIR unexpanded
  [ "$(grep -cF 'for tool in "$REPO_DIR"/bin/' "$REPO/install.sh")" -eq 1 ]
  local hdr sel="$BATS_TEST_TMPDIR/selected.txt"; : > "$sel"
  # shellcheck disable=SC2016  # same literal needle
  hdr="$(grep -F 'for tool in "$REPO_DIR"/bin/' "$REPO/install.sh")"
  # shellcheck disable=SC2034  # read by the eval'd loop header below, which shellcheck cannot see
  REPO_DIR="$REPO"
  eval "$hdr
    [ -f \"\$tool\" ] || continue
    basename \"\$tool\" >> \"$sel\"
  done"
  [ "$(grep -cxF 'desk-assert' "$sel")" -eq 1 ]
  # NEG control: the pass is still selective, so "everything is linked" cannot satisfy the line above.
  [ -f "$REPO/bin/claude-accounts" ]
  [ "$(grep -cxF 'claude-accounts' "$sel")" -eq 0 ]
}

# ── (2) GUARD leg ─────────────────────────────────────────────────────────────────────────────
@test "guard: bin/desk-assert exists and is executable" {
  [ -f "$DA" ]
  [ -x "$DA" ]
}

@test "guard: desk-assert --help is invocable (exits 0 before any dependency check)" {
  run bash "$DA" --help
  [ "$status" -eq 0 ]
}

# ── (3) RESIDENT-RULE leg (the desk RUNS the guard before a session-state claim) ────────────────
@test "resident-rule: the boot brief INVOKES 'desk-assert <sid>' (a command, not a bare word)" {
  # require the invocation form with an argument placeholder — a mere mention of the word would pass a
  # naive grep, so anchor on 'desk-assert <sid' (the sid the rule tells the desk to ground).
  grep -qE 'desk-assert[[:space:]]+<sid' "$BRIEF"
}

@test "resident-rule: the invocation carries --witnessed-ref (the HEAD/landed-claim leg)" {
  grep -q -- '--witnessed-ref' "$BRIEF"
}

@test "resident-rule: the desk-assert invocation sits inside the state/causal-claim grounding rule (law #9)" {
  # pull the desk-assert invocation with its surrounding bullet (markdown wraps the command a few
  # lines below the rule's topic sentence) and require the grounding context in that block — proving
  # the invocation IS the grounding rule, not an unrelated aside.
  run bash -c "grep -B3 -A2 'desk-assert' '$BRIEF' | grep -iqE 'state/causal claim|before you make it|claim about another session'"
  [ "$status" -eq 0 ]
}

@test "resident-rule: UNGROUNDED is the actionable verdict (claim-not-earned), not just prose" {
  grep -q 'UNGROUNDED' "$BRIEF"
}

@test "resident-rule: the FM2 grounding-triad law is still named (provenance intact)" {
  grep -qiE 'grounding triad|law #9|FM2 triad' "$BRIEF"
}
