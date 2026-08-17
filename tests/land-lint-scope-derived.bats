#!/usr/bin/env bats
# land-lint-scope-derived.bats — ship-land's own-scope pathspec is DERIVED from each lint, never
# restated beside it (backlog 0be0bd2c0b65).
#
# THE DEFECT THIS PINS. Two ratchet arms in scripts/ship-land.sh build their own-set — the files
# allowed to BLOCK a land — from a pathspec hardcoded in ship-land:
#     permission-gate   git diff --name-only "$range" -- 'install.sh' 'scripts/*'
#     tsv-pad           git diff --name-only "$range" -- 'bin/*' 'hooks/*' 'scripts/*'
# Each lint's judged population is env-overridable one file over — CC_PERMGATE_SET and
# CC_TSVPAD_DIRS — so the two can move apart, and each arm carried a COMMENT asking the next author
# to widen the pathspec in the same diff. Nothing executes a comment.
#
# THE DRIFT IS SILENT IN THE DANGEROUS DIRECTION, which is why a test and not a comment. An own-set
# that MISSES a file does not error: it is the legitimate spelling of "this land touches nothing I
# judge", so the finding drops to advisory and the land proceeds. A widening that degrades every new
# finding to advisory therefore looks exactly like a clean land.
#
# WHAT IS ASSERTED, and the third arm is the one that keeps the other two honest:
#   (1) each lint can NAME its population, and the name follows the env seam
#   (2) ship-land's derivation reaches a file the old hardcoded pathspec missed
#   (3) a lint that CANNOT answer is a NON-VERDICT (rc 2), never an empty own-set — the same defect
#       arriving by a new route, and the one a future `|| true` would reintroduce
#   (4) neither arm carries a hardcoded pathspec again (the copy-a-neighbour regression)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"      # hermeticity: never the operator's live ~
  mkdir -p "$HOME"
  PERMGATE="$REPO/scripts/permission-gate-lint.sh"
  TSVPAD="$REPO/scripts/tsv-pad-lint.sh"
}

# extract_fn <name> — the function's REAL shipped text, lifted out of ship-land.sh and evaluated
# here. Not a re-implementation: a test that restated the derivation would be the very defect this
# file is about, one level up (memory: control-must-replay-the-real-artifact).
extract_fn() {
  sed -n "/^$1() {/,/^}/p" "$REPO/scripts/ship-land.sh"
}

# mk_repo — a fixture git repo with one commit as the base and a second touching THREE files, one in
# each of scripts/ hooks/ and docs/. Identity comes from the environment: `git config user.email`
# with no -C is denied by hooks/validate-bash.sh across this machine's ~100 shared worktrees.
mk_repo() {
  local d="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$d/scripts" "$d/hooks" "$d/docs"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git -C "$d" init -q 2>/dev/null || { git init -q "$d"; }
  : >"$d/seed"; git -C "$d" add -A; git -C "$d" commit -qm base
  echo x >"$d/scripts/a.sh"; echo x >"$d/hooks/b.sh"; echo x >"$d/docs/c.md"
  git -C "$d" add -A; git -C "$d" commit -qm work
  printf '%s' "$d"
}

# ── (1) each lint NAMES the population it judges, and the name follows the env seam ──────────────

@test "permission-gate-lint --print-scope prints its actuation globs" {
  run bash "$PERMGATE" --print-scope
  [ "$status" -eq 0 ]
  [[ "$output" == *"install.sh"* ]] || false
  [[ "$output" == *"scripts/ship-"* ]]
}

@test "permission-gate-lint --print-scope follows CC_PERMGATE_SET" {
  run env CC_PERMGATE_SET="install.sh hooks/*" bash "$PERMGATE" --print-scope
  [ "$status" -eq 0 ]
  [[ "$output" == *"hooks/*"* ]] || false
  # the embedded default must be GONE, or the override is additive and the seam is not the seam
  [[ "$output" != *"scripts/ship-"* ]]
}

@test "tsv-pad-lint --print-scope prints its scan dirs as pathspecs" {
  run bash "$TSVPAD" --print-scope
  [ "$status" -eq 0 ]
  [[ "$output" == *"bin/*"* ]] || false
  [[ "$output" == *"hooks/*"* ]] || false
  [[ "$output" == *"scripts/*"* ]]
}

@test "tsv-pad-lint --print-scope follows CC_TSVPAD_DIRS" {
  run env CC_TSVPAD_DIRS="commands" bash "$TSVPAD" --print-scope
  [ "$status" -eq 0 ]
  [ "$output" = "commands/*" ]
}

# An unset-or-EMPTY override falls back to the embedded default, because the lints spell it `:-` and
# --print-scope uses the SAME operator. Pinned so the two can never disagree about what empty means:
# if one ever became `-` (empty is a value) the other would still be `:-`, and the own-set would
# silently become the whole embedded set — or nothing — depending on which one moved.
@test "an EMPTY env override falls back to the embedded set, in both lints" {
  run env CC_PERMGATE_SET= bash "$PERMGATE" --print-scope
  [[ "$output" == *"scripts/ship-"* ]] || false
  run env CC_TSVPAD_DIRS= bash "$TSVPAD" --print-scope
  [[ "$output" == *"scripts/*"* ]]
}

# ── (2) ship-land's derivation reaches what the hardcoded pathspec missed ────────────────────────

@test "lint_own_scope reaches a file the old hardcoded pathspec missed" {
  local d; d="$(mk_repo)"
  eval "$(extract_fn lint_own_scope)"
  cd "$d"
  # THE MUTANT. hooks/ is outside permission-gate's old `-- 'install.sh' 'scripts/*'`. With the
  # lint's population widened to it, the own-set MUST carry hooks/b.sh — pre-fix it could not,
  # because the pathspec was a constant in ship-land and knew nothing about this variable.
  # `export`, not an `env` prefix: env(1) execs a BINARY and cannot see a shell function, so the
  # whole assertion would pass on a 127 that proves nothing (observed while writing this).
  export CC_PERMGATE_SET="install.sh hooks/*"
  run lint_own_scope "$PERMGATE" HEAD~1..HEAD
  unset CC_PERMGATE_SET
  [ "$status" -eq 0 ]
  [[ "$output" == *"hooks/b.sh"* ]] || false
  # …and it stays SCOPED: docs/c.md is in the same diff and in no lint's population.
  [[ "$output" != *"docs/c.md"* ]]
}

@test "a land touching none of the population is SET-BUT-EMPTY, not a non-verdict" {
  local d; d="$(mk_repo)"
  eval "$(extract_fn lint_own_scope)"
  cd "$d"
  # docs-only is the common case own-scope exists for: rc 0 with empty output, so nothing blocks.
  export CC_PERMGATE_SET="install.sh does-not-exist/*"
  run lint_own_scope "$PERMGATE" HEAD~1..HEAD
  unset CC_PERMGATE_SET
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── (3) THE POSITIVE CONTROL — the mechanism must be able to FAIL, and fail as a NON-VERDICT ─────

@test "a lint that cannot name its scope is rc 2, never an empty own-set" {
  local d; d="$(mk_repo)"
  local stub="$BATS_TEST_TMPDIR/oldlint"
  # An OLDER copy of a lint: it does not know --print-scope, so it treats the flag as a root, fails,
  # and exits 2 with nothing on stdout. This is the real shape of the failure, not an invented one.
  printf '#!/bin/bash\necho "not a directory: $1" >&2\nexit 2\n' >"$stub"
  chmod +x "$stub"
  eval "$(extract_fn lint_own_scope)"
  cd "$d"
  run lint_own_scope "$stub" HEAD~1..HEAD
  # rc 2 and rc 0-with-empty-output are DIFFERENT ANSWERS here. Collapsing them (a `|| true` on the
  # call site) reinstates exactly the silent-advisory defect this file exists to prevent.
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

# ── (4) neither arm may restate a pathspec again ─────────────────────────────────────────────────

@test "neither the permission-gate nor the tsv-pad own-set is built from a pathspec again" {
  # SCOPED TO THE TWO VARIABLES, not to a pathspec literal. Six OTHER arms in this file legitimately
  # pass `-- 'bin/*' 'hooks/*' 'scripts/*'` (utc-stamp · pipefail-sigpipe · self-path ·
  # payload · unattended-path · chromium-bundle), and MEASURED 2026-08-17 none of those five lints
  # has an env seam that can move its judged population at runtime — so their restatement cannot
  # drift the way these two could, and a literal-pathspec ban would red on innocents. It would also
  # red on this file's own header, which quotes the removed lines on purpose.
  run grep -E '^\s*(pgown|tsvown)=.*git diff' "$REPO/scripts/ship-land.sh"
  [ "$status" -ne 0 ]
  # …and both arms DO ask the lint. Without this half, deleting the arms outright would pass.
  run grep -c 'lint_own_scope "\$PERMGATE_LINT"' "$REPO/scripts/ship-land.sh"
  [ "$output" = "1" ]
  run grep -c 'lint_own_scope "\$TSVPAD_LINT"' "$REPO/scripts/ship-land.sh"
  [ "$output" = "1" ]
}
