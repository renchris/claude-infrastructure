#!/usr/bin/env bats
# cc-premise `coverage` — how many LIVE rows CAN re-check themselves, split by ARM and by SOURCE.
#
# WHY THIS VERB EXISTS, and it is a measurement defect rather than a feature. `assess` composes THREE
# probe arms (stored · derived-plan · derived-postland) and records which one fired in
# `out["probe_kind"]`. The auditor that PUBLISHES coverage — scripts/backlog-ratchet.sh — computed
# its numerator as `select(.falsifier != "")`, the STORED field alone. So the two disagreed about the
# one question both claim to answer, over one population, and the ratchet's own header defines
# coverage as "what fraction of open items CAN re-check themselves".
#
# THE CONSEQUENCE INVERTED AN ALARM. `post-land RED:` rows store no probe ON PURPOSE — cc-premise
# derives that predicate, and postland-verify's `--falsify-red` header records that storing an equal
# probe there would "shadow a tested, documented arm and buy nothing but a second implementation to
# keep in sync". postland-verify is the fleet's highest-volume generator (one row per failing suite
# per red run), so those rows sat in the DENOMINATOR and could never reach the NUMERATOR: every red
# trunk mechanically depressed coverage while no row lost any ability to re-check itself, and
# `--assert` went RED on that, prescribing the one cure that population must not be given
# (MEMORY.md: alarm-polarity-and-attention-budget).
#
# THE TWO PROPERTIES UNDER TEST, and they are the ones a mutant can break silently:
#   1. CAPABILITY, NOT EXECUTION — the verb must run no probe (its only subprocess is the cc-backlog
#      fold), so a broken box lowers the never-validated number and never coverage.
#   2. ONE ARBITER PER FACT — the status fold is cc-backlog's. The first draft of this verb read
#      `build_index`, which folds no `status` at all, and counted closed rows as live; that is a
#      THIRD auditor invented inside the fix for two (MEMORY.md:
#      sibling-auditors-must-share-the-state-model).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PREMISE="$REPO/bin/cc-premise"
  # HERMETIC $HOME: every store this verb touches defaults under ~/.claude/autonomy, so an
  # unfixtured run would read the operator's live backlog and assert on whatever the desk did today.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  : > "$CC_BACKLOG_FILE"
}

# row <id> <source> [falsifier]
row() {
  local extra=""
  [ -n "${3:-}" ] && extra=", \"falsifier\":\"$3\""
  printf '{"id":"%s","ts":"2026-08-01T00:00:00Z","event":"add","project":"p","title":"t","source":"%s"%s}\n' \
    "$1" "$2" "$extra" >> "$CC_BACKLOG_FILE"
}
# postland_row <id> <suite> — the class that is DERIVED-covered and deliberately stores nothing.
postland_row() {
  printf '{"id":"%s","ts":"2026-08-01T00:00:00Z","event":"add","project":"claude-infrastructure","source":"postland-verify","title":"post-land RED: tests/%s.bats::a test @ abcdef1234567"}\n' \
    "$1" "$2" >> "$CC_BACKLOG_FILE"
}

@test "a STORED probe counts as covered, and the arm is named" {
  row a gen-x "true"
  run "$PREMISE" coverage --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"probeable": 1'
  printf '%s' "$output" | grep -q '"covered": 1'
  printf '%s' "$output" | grep -q '"stored": 1'
}

@test "a post-land RED row is DERIVED-covered — the defect this verb was built for" {
  # THE LOAD-BEARING CASE. Under the stored-only numerator this row read as uncovered forever.
  postland_row r1 alpha
  run "$PREMISE" coverage --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"derived-postland": 1'
  printf '%s' "$output" | grep -q '"uncovered": 0'
  printf '%s' "$output" | grep -q '"coverage_pct": 100'
}

@test "CAPABILITY, NOT EXECUTION: no last-green and no git repo still counts the row as covered" {
  # The derived arm cannot ANSWER here (no postland ledger, no repo) — and coverage must not care.
  # Whether a probe actually RAN is the separate never-validated number; folding an environment
  # failure into coverage would make the mark lurch on a broken box and re-baseline to it.
  export CC_PREMISE_REPO="$BATS_TEST_TMPDIR/not-a-repo"
  export CC_PREMISE_POSTLAND_DIR="$BATS_TEST_TMPDIR/no-postland"
  postland_row r1 alpha
  run "$PREMISE" coverage --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"derived-postland": 1'
}

@test "a row no arm speaks for is UNCOVERED, and its generator is named" {
  row a gen-x "true"
  row u1 sess-abc
  row u2 sess-abc
  run "$PREMISE" coverage --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"uncovered": 2'
  # by_source is what makes a ratchet RED actionable — it names the producer to fix.
  printf '%s' "$output" | grep -q '"sess-abc": {"total": 2, "covered": 0}'
}

@test "the STATUS fold is cc-backlog's — a closed row leaves the population" {
  # THE THIRD-AUDITOR REGRESSION. build_index folds no `status`, so reading it here counted every
  # closed row as live and reported 2 probeable where the ratchet's fold said 1.
  row a gen-x "true"
  row b gen-x
  printf '{"id":"b","ts":"2026-08-02T00:00:00Z","event":"done"}\n' >> "$CC_BACKLOG_FILE"
  run "$PREMISE" coverage --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"probeable": 1'
  printf '%s' "$output" | grep -q '"coverage_pct": 100'
}

@test "a BLOCKED row is not in the wave, so it is not in the population" {
  row a gen-x "true"
  row b gen-x
  printf '{"id":"b","ts":"2026-08-02T00:00:00Z","event":"block","needs":"an operator step"}\n' \
    >> "$CC_BACKLOG_FILE"
  run "$PREMISE" coverage --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"probeable": 1'
}

@test "the \`needs\` class is excluded — its --run PERFORMS the step it would be probing" {
  row a gen-x "true"
  printf '{"id":"n1","ts":"2026-08-01T00:00:00Z","event":"add","project":"p","title":"t","source":"needs"}\n' \
    >> "$CC_BACKLOG_FILE"
  run "$PREMISE" coverage --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"probeable": 1'
}

@test "a STORED probe outranks the derived arm, matching assess's precedence exactly" {
  # Two orders would be two answers to "which arm speaks for this row" — the same drift in a new
  # place. A postland-titled row that DOES carry a stored probe must classify as stored.
  printf '{"id":"r1","ts":"2026-08-01T00:00:00Z","event":"add","project":"claude-infrastructure","source":"postland-verify","title":"post-land RED: tests/alpha.bats::a test @ abcdef1234567","falsifier":"true"}\n' \
    >> "$CC_BACKLOG_FILE"
  run "$PREMISE" coverage --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"stored": 1'
  printf '%s' "$output" | grep -q '"derived-postland": 0'
}

@test "a cross-project post-land row is NOT claimed by the git arm, which speaks only about THIS repo" {
  printf '{"id":"r1","ts":"2026-08-01T00:00:00Z","event":"add","project":"some-other-repo","source":"postland-verify","title":"post-land RED: tests/alpha.bats::a test @ abcdef1234567"}\n' \
    >> "$CC_BACKLOG_FILE"
  run "$PREMISE" coverage --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"uncovered": 1'
}

@test "an UNREADABLE fold exits 2 rather than reporting over a partial population" {
  # A number computed from an unreadable store is not a weaker measurement, it is a wrong one. The
  # ratchet turns this rc into an explicit UNKNOWN that refuses to latch or judge
  # (MEMORY.md: sensor-default-off-makes-blindness-the-shipping-path).
  row a gen-x "true"
  export CC_PREMISE_BACKLOG_BIN="$BATS_TEST_TMPDIR/no-such-cc-backlog"
  run "$PREMISE" coverage --json
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q "cannot read the fold"
}

@test "the human render names every arm, including the ones reading zero" {
  # A census that prints only non-zero arms cannot be read as a POSITIVE control: a reader could not
  # tell "no derived-plan rows" from "this build has no derived-plan arm".
  row a gen-x "true"
  run "$PREMISE" coverage
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "stored"
  printf '%s' "$output" | grep -q "derived-plan"
  printf '%s' "$output" | grep -q "derived-postland"
}

@test "an EMPTY store reports zero rather than dividing by it" {
  run "$PREMISE" coverage --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"probeable": 0'
  printf '%s' "$output" | grep -q '"coverage_pct": 0'
}
