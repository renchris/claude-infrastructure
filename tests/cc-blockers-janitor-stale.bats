#!/usr/bin/env bats
# shellcheck shell=bash
#   bats files are bash with @test sugar and shellcheck has no bats mode, so the shell is declared
#   explicitly (SC1008). Without it shellcheck ABORTS on the file and reports zero findings — a lint
#   that cannot parse its subject is SILENT, not clean (memory: lint-blindness-composes).
# cc-blockers × janitor-stale — the READING half of `worktree-gc-infra-run.sh --assert`.
#
# WHY THIS ROW EXISTS. --assert was built to answer three questions on demand (true population ·
# age of the last verdict · what that verdict was) and to exit 3 when the population breached its
# ceiling or the janitor itself went stale. Measured 2026-08-10, a repo-wide grep found its ONLY
# callers were its own bats file: the sensor was built and nothing read it. A janitor that silently
# stops is invisible precisely while the population it bounds keeps growing — the same
# sensor-built-never-read shape this board already carries two instances of.
#
# What these tests pin is POLARITY and FAIL-OPEN, not the verdict logic: the subject's own suite
# (tests/worktree-gc-infra.bats) owns whether a population is breached, and two implementations of
# one predicate would be two answers. An alarm that fires in every state carries exactly as many
# bits as one that never fires (memory: alarm-polarity-and-attention-budget), and — the load-bearing
# case — an UNKNOWN exit code must land in the no-premise arm, never be read as a breach
# (memory: new-enum-member-falls-into-fail-closed-default).
#
# Assertion style: `[ ]` throughout — a non-final `[[ ]]` is errexit-EXEMPT under bats and therefore
# a DEAD assertion.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  B="$REPO/bin/cc-blockers"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude"
  # Fixturing $HOME does not redirect an ABSOLUTE /tmp default, nor a BARE NAME the subject then
  # EXECUTES off the operator's PATH. Left unpinned, this suite would count the operator's real
  # pending approvals and run their deployed claude-accounts once per test. ABSENT paths are the
  # right fixture here — every one of these sensors fails open on a missing path, which is exactly
  # the silence these tests want from everything that is not the janitor.
  export CC_BLOCKERS_ACCOUNTS_BIN="$D/absent-claude-accounts"
  export CC_DISPATCH_LOG="$D/absent-dispatcher.log"
  export CC_PERMPEND_DIR="$D/absent-permission-pending"
  # A stub subject, so these tests pin the WIRING and never re-measure the live worktree population.
  stub_assert() { # $1 = stdout body, $2 = exit code
    { printf '#!/bin/bash\ncat <<'\''BODY'\''\n%s\nBODY\nexit %s\n' "$1" "$2"; } > "$D/wtgc"
    chmod +x "$D/wtgc"
    export CC_WTGC_ASSERT_SH="$D/wtgc"
  }
  BREACHED='population=281 (ours=240 foreign=41) ceiling=150 last_verdict_age_h=97
last_row=<none>
BREACH our worktrees 240 > ceiling 150
BREACH last verdict is 97h old (stale > 48h) — the janitor is not running'
  HEALTHY='population=100 (ours=40 foreign=60) ceiling=150 last_verdict_age_h=3
last_row=2026-08-10 04:15:05  verdict=ok
OK bounded and fresh'
}

@test "rc 3 with BREACH lines renders the JANITOR-STALE section" {
  stub_assert "$BREACHED" 3
  run "$B"
  echo "$output" | grep -q "JANITOR-STALE"
  echo "$output" | grep -q "janitor-stale"
}

@test "the row RELAYS the subject's own BREACH wording — the board cannot disagree with the sensor" {
  stub_assert "$BREACHED" 3
  run "$B" --json
  echo "$output" | grep -q "our worktrees 240 > ceiling 150"
}

@test "last_verdict_age_h is carried into the row (the field the rung is named for)" {
  stub_assert "$BREACHED" 3
  run "$B" --json
  [ "$(echo "$output" | jq -r '[.[] | select(.kind=="janitor-stale")][0].last_verdict_age_h')" = "97" ]
}

@test "RED-PROOF of polarity: rc 0 'bounded and fresh' is SILENT — no row, no section" {
  stub_assert "$HEALTHY" 0
  run "$B"
  ! echo "$output" | grep -q "JANITOR-STALE" || false
  ! echo "$output" | grep -q "janitor-stale" || false
}

@test "an UNKNOWN exit code asserts NOTHING — a new enum member is not a breach" {
  # rc 1 is not in the documented {0,3} contract. Reading it as a breach would invent a blocker
  # the sensor never claimed; reading it as OK would launder one. The only honest answer is silence.
  stub_assert "$BREACHED" 1
  run "$B"
  ! echo "$output" | grep -q "janitor-stale" || false
}

@test "rc 3 with NO BREACH line is incoherent — the row abstains rather than invent a detail" {
  stub_assert 'population=1 (ours=1 foreign=0) ceiling=150 last_verdict_age_h=1' 3
  run "$B"
  ! echo "$output" | grep -q "janitor-stale" || false
}

@test "empty output asserts nothing, whatever the exit code" {
  stub_assert '' 3
  run "$B"
  ! echo "$output" | grep -q "janitor-stale" || false
}

@test "a NON-EXECUTABLE sensor is no premise — silence, never a row" {
  stub_assert "$BREACHED" 3
  chmod -x "$D/wtgc"
  run "$B"
  ! echo "$output" | grep -q "janitor-stale" || false
}

@test "an ABSENT sensor is no premise either — the add-on fails no wider than itself" {
  export CC_WTGC_ASSERT_SH="$D/does-not-exist"
  run "$B"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]      # the board still renders; it does not crash
  ! echo "$output" | grep -q "janitor-stale" || false
}
