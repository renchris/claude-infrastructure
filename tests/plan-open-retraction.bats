#!/usr/bin/env bats
# BACKLOG_MASTER W0 ledger-retraction.3 — a finished plan retracts its plan-open row:
#   · find-plan.sh reads `status: done` as complete (it was UNKNOWN, i.e. open, forever)
#   · plan-phase-scan reads a complete frontmatter as DONE for a plan written as prose
#   · plan-frontmatter-lint requires frontmatter in docs/plans/*.md, design companions excluded
#   · an `advance <plan>` row over filed wave rows is a programme roster and closes with them

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_PLAN_INDEX="$BATS_TEST_TMPDIR/no-index.json"
  P="$BATS_TEST_TMPDIR/proj/docs/plans"; mkdir -p "$P/sub"
  printf -- '---\nstatus: done\n---\n\n# Finished prose plan\n\nAll of it shipped.\n\n## Wave one\n\nprose\n' > "$P/DONE_PLAN.md"
  printf -- '---\nstatus: open\n---\n\n# Open plan\n\n## Wave one\n\nprose\n' > "$P/OPEN_PLAN.md"
}

@test "find-plan: status done reads as complete, and --status says so" {
  run bash "$REPO/scripts/find-plan.sh" --status "$P/DONE_PLAN.md"
  [ "$status" -eq 0 ]
  [ "$output" = complete ]
  run bash "$REPO/scripts/find-plan.sh" --status "$P/OPEN_PLAN.md"
  [ "$output" = open ]
}

@test "find-plan: AUTONOMY_CORE_INSTALL (status: done) is not listed open" {
  run bash -c "bash '$REPO/scripts/find-plan.sh' --list-open 2>/dev/null | grep -c AUTONOMY_CORE_INSTALL"
  [ "$output" = 0 ]
}

@test "plan-phase-scan: a complete prose plan reports its sections DONE (frontmatter), an open one PENDING" {
  run bash "$REPO/scripts/plan-phase-scan.sh" "$P/DONE_PLAN.md" json
  [ "$status" -eq 0 ]
  [[ "$output" != *'"PENDING"'* ]]
  [[ "$output" == *'"frontmatter"'* ]]
  run bash "$REPO/scripts/plan-phase-scan.sh" "$P/OPEN_PLAN.md" json
  [[ "$output" == *'"PENDING"'* ]]
}

@test "plan-frontmatter-lint: a plan with no frontmatter is RED; a companion and a subdir note pass" {
  printf '# bare plan\n' > "$P/BARE.md"
  printf '<!-- plan-companion: OPEN_PLAN -->\n# design notes\n' > "$P/NOTES.md"
  printf '# wave notes\n' > "$P/sub/w1.md"
  run bash "$REPO/scripts/plan-frontmatter-lint.sh" --file "$P/BARE.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BARE.md has no frontmatter"* ]]
  run bash "$REPO/scripts/plan-frontmatter-lint.sh" --file "$P/NOTES.md" --file "$P/sub/w1.md" --file "$P/OPEN_PLAN.md"
  [ "$status" -eq 0 ]
  run bash "$REPO/scripts/plan-frontmatter-lint.sh" --selftest
  [ "$status" -eq 0 ]
}

@test "plan-frontmatter-lint: every plan in this repo's docs/plans carries frontmatter" {
  run bash "$REPO/scripts/plan-frontmatter-lint.sh"
  [ "$status" -eq 0 ]
}

@test "programme: an advance row rostered over its plan's wave rows cannot be claimed and closes with them" {
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl" CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off CC_BACKLOG_PROJECT_WARN=off CC_BACKLOG_COVERAGE_WARN=off CC_BACKLOG_PREMISE=off
  CB="$REPO/bin/cc-backlog"; cd "$BATS_TEST_TMPDIR"
  adv="$(bash "$CB" add --title "advance Open plan" --project p --dod-ref "$P/OPEN_PLAN.md" --source plan-open)"
  w1="$(bash "$CB" add --title "wave 1" --project p --dod-ref "$P/OPEN_PLAN.md")"
  w2="$(bash "$CB" add --title "wave 2" --project p --dod-ref "$P/OPEN_PLAN.md")"
  run bash "$CB" roster "$adv" --dod "$P/OPEN_PLAN.md"
  [ "$status" -eq 0 ]
  run bash "$CB" claim "$adv" --by w
  [ "$status" -eq 4 ]
  bash "$CB" done "$w1" --evidence one
  st() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.status'; }
  [ "$(st "$adv")" = open ]
  bash "$CB" done "$w2" --evidence two
  [ "$(st "$adv")" = done ]
}
