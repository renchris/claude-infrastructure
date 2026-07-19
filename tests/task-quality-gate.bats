#!/usr/bin/env bats
# task-quality-gate.sh — TaskCompleted hook. G-P6-10 coverage: the repo-aware branch that runs
# shellcheck + bash -n + bound bats for claude-infrastructure's OWN work (shell scripts, no
# node_modules), which previously fell through the TypeScript-only path and silently skipped.
# Exit 2 rejects the task; exit 0 allows. Deletions are excluded from the shell-file set (the
# ship-land deletion-bug class: a removed .sh must not be handed to shellcheck).
#
# The git-worktree-list search is bypassed via the TASK_QUALITY_GATE_WORKTREE_OVERRIDE seam so the
# gate can be exercised against a hermetic temp repo. Infra detection keys on the repo basename
# (claude-infrastructure), so the fixture repo is created under that name — real detection runs.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/task-quality-gate.sh"
}

mkinfra() {  # a fresh git repo whose basename is claude-infrastructure → infra detection fires
  local w="$BATS_TEST_TMPDIR/claude-infrastructure"
  rm -rf "$w"; git init -q "$w"
  ( cd "$w"; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > README.md; git add README.md; git commit -qm base ) >/dev/null 2>&1
  printf '%s' "$w"
}

run_tqg() {  # $1=worktree  $2=team_name
  jq -n --arg tm "$2" '{task_subject:"do work",teammate_name:"tm",team_name:$tm}' \
    | TASK_QUALITY_GATE_WORKTREE_OVERRIDE="$1" bash "$HOOK"
}

@test "non-team task → exit 0 (gate skips standalone tasks)" {
  local w; w="$(mkinfra)"
  printf '#!/bin/bash\necho $BAD\n' > "$w/x.sh"        # would fail IF it ran — proves the skip
  run run_tqg "$w" ""
  [ "$status" -eq 0 ]
}

@test "infra: clean shell file → exit 0 (pass)" {
  local w; w="$(mkinfra)"
  printf '#!/bin/bash\necho hi\n' > "$w/good.sh"
  run run_tqg "$w" "team-x"
  [ "$status" -eq 0 ]
}

@test "infra: shellcheck-failing shell file → exit 2 (reject)" {
  local w; w="$(mkinfra)"
  printf '#!/bin/bash\necho $UNQUOTED\n' > "$w/bad.sh"
  run run_tqg "$w" "team-x"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q "QUALITY GATE FAILED"
}

@test "infra: bash -n syntax error → exit 2" {
  local w; w="$(mkinfra)"
  printf '#!/bin/bash\nif [ ; then\n' > "$w/broken.sh"
  run run_tqg "$w" "team-x"
  [ "$status" -eq 2 ]
}

@test "infra: only a non-shell file changed → exit 0 (nothing to check)" {
  local w; w="$(mkinfra)"
  echo notes > "$w/notes.md"
  run run_tqg "$w" "team-x"
  [ "$status" -eq 0 ]
}

@test "infra: shebang-detected shell file with no .sh extension → exit 2 on SC error" {
  local w; w="$(mkinfra)"
  printf '#!/bin/bash\necho $X\n' > "$w/tool"          # no extension, shell shebang
  run run_tqg "$w" "team-x"
  [ "$status" -eq 2 ]
}

@test "infra: deleted shell file is not sent to shellcheck → exit 0 (deletion-bug class)" {
  local w; w="$(mkinfra)"
  printf '#!/bin/bash\necho ok\n' > "$w/todelete.sh"
  ( cd "$w"; git add todelete.sh; git commit -qm addsh; git rm -q todelete.sh ) >/dev/null 2>&1
  run run_tqg "$w" "team-x"
  [ "$status" -eq 0 ]
}

@test "infra: changed bats test that PASSES → exit 0 (bats branch)" {
  local w; w="$(mkinfra)"
  mkdir -p "$w/tests"
  printf '#!/usr/bin/env bats\n@test "ok" { true; }\n' > "$w/tests/pass.bats"
  run run_tqg "$w" "team-x"
  [ "$status" -eq 0 ]
}

@test "infra: changed bats test that FAILS → exit 2 (bats branch)" {
  local w; w="$(mkinfra)"
  mkdir -p "$w/tests"
  printf '#!/usr/bin/env bats\n@test "boom" { false; }\n' > "$w/tests/fail.bats"
  run run_tqg "$w" "team-x"
  [ "$status" -eq 2 ]
}

@test "non-infra repo without node_modules → falls through, exit 0 (tsc path skips, unchanged)" {
  local w="$BATS_TEST_TMPDIR/some-app"; rm -rf "$w"; git init -q "$w"
  ( cd "$w"; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo x > a.txt; git add a.txt; git commit -qm base; echo y > b.txt ) >/dev/null 2>&1
  run run_tqg "$w" "team-x"
  [ "$status" -eq 0 ]
}
