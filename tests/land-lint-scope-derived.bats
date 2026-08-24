#!/usr/bin/env bats
# land-lint-scope-derived.bats — ship-land's own-scope pathspec is DERIVED from each lint, never
# restated beside it (backlog 0be0bd2c0b65).
#
# THE DEFECT THIS PINS. All EIGHT own-scope ratchet arms in scripts/ship-land.sh used to build their
# own-set — the files allowed to BLOCK a land — from a pathspec hardcoded in ship-land:
#     permission-gate   git diff --name-only "$range" -- 'install.sh' 'scripts/*'
#     tsv-pad           git diff --name-only "$range" -- 'bin/*' 'hooks/*' 'scripts/*'
#     utc-stamp         …'bin/*' 'hooks/*' 'scripts/*'
#     self-path         …'bin/*' 'hooks/*' 'scripts/*'
#     pane-spawn        …'bin/*' 'hooks/*' 'scripts/*' 'commands/*'
#     chromium-bundle   …'bin/*' 'hooks/*' 'scripts/*' 'tools/*'
#     pipefail-sigpipe  …'bin/*' 'hooks/*' 'scripts/*' 'tests/*' 'docs/*' '*.sh'
#     unattended-path   …'bin/*' 'hooks/*' 'scripts/*' 'launchd/*' 'tests/*'
# and each arm carried a COMMENT asking the next author to widen the pathspec in the same diff.
# Nothing executes a comment.
#
# TWO DRIFT ROUTES, CLOSED IN TWO PASSES. The first two lints' populations are env-overridable one
# file over — CC_PERMGATE_SET and CC_TSVPAD_DIRS — so they could move at RUNTIME, with no diff at
# all; 0be0bd2c0b65 closed those. The other six have no env seam, and that was the whole of their
# defence: they could still drift by a CODE edit to the lint's own scan set, in the same silent
# direction, from an author with no reason to open ship-land.sh. 5fc8ff411a7c closed those, and found
# one of the restatements ALREADY drifted (pipefail-sigpipe: `docs/*` and `tests/*` present though
# that lint judges neither as such, `*.bats` absent though it judges it at every depth) and another
# that had already needed the comment honoured by hand once (unattended-path, when the bats corpus
# became a third population). A defence that depends on nobody editing the lint is not a defence.
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
  # Commit identity, HOISTED HERE from mk_repo. mk_repo sets the same four variables, but every
  # caller invokes it as `d="$(mk_repo)"` — a COMMAND SUBSTITUTION — so its `export` happens in a
  # subshell and is gone by the time the test body runs. That was invisible while no test committed
  # after mk_repo returned; the first one that did failed with "Author identity unknown". Env vars
  # rather than `git config`: a bare `git config user.email` is denied by hooks/validate-bash.sh
  # across this machine's ~100 shared worktrees (see mk_repo).
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
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

# ── (1b) THE OTHER SIX LINTS NAME THEIR POPULATIONS TOO (backlog 5fc8ff411a7c) ───────────────────
# These six were left out of 0be0bd2c0b65 on a MEASURED distinction: none of them has an env seam
# that can move its judged population at RUNTIME, so their restated pathspecs could not drift the way
# CC_PERMGATE_SET / CC_TSVPAD_DIRS could. That was the whole of their defence, and it only ever
# covered one of the two drift routes — a CODE edit to the lint's own scan set moves the population
# just as silently, in the same degrade-to-advisory direction, from an author with no reason to open
# ship-land.sh. Each now answers --print-scope from the SAME declaration its scan walks.
#
# ASSERTED AS A SET, from one table, because the failure this file exists to catch is one arm being
# forgotten: a per-lint @test is a list someone can add a lint to without noticing.

# lint · the pathspecs --print-scope must print. Space-separated, and every entry must appear.
SCOPE_TABLE='utc-stamp-lint|bin/* hooks/* scripts/*
self-path-lint|scripts/* hooks/* bin/*
pane-spawn-coverage-lint|bin/* scripts/* hooks/* commands/*
chromium-bundle-lint|scripts/* hooks/* bin/* tools/*
pipefail-sigpipe-lint|*.sh *.bats bin/* hooks/* scripts/*
unattended-path-lint|scripts/* bin/* hooks/* hooks/*.sh tests/*.bats'

@test "all six remaining ratchet lints answer --print-scope with their judged population" {
  local lint want p
  # GLOBBING OFF FOR THE WHOLE CASE. `for p in $want` with globbing on PATHNAME-EXPANDS every entry
  # against the test's cwd — `bin/*` becomes the repo's actual bin/ contents — so the assertion stops
  # being about pathspecs and starts being about the tree. Caught here on the first run, and it is
  # the same expansion that dropped six sites from pipefail-sigpipe-lint's census while exiting 0.
  set -f
  while IFS='|' read -r lint want; do
    [ -n "$lint" ] || continue
    run bash "$REPO/scripts/$lint.sh" --print-scope
    [ "$status" -eq 0 ] || { echo "$lint: --print-scope exited $status (want 0): $output"; false; }
    [ -n "$output" ] || { echo "$lint: --print-scope printed NOTHING — that is lint_own_scope's rc-2 non-verdict wearing a success code"; false; }
    for p in $want; do
      # Whole-LINE match. A substring test would let `bin/*` be satisfied by `bin/*.sh`, which is a
      # NARROWER population and exactly the silent degradation being pinned.
      grep -qxF -- "$p" <<<"$output" || { echo "$lint: --print-scope is missing '$p'; got: $output"; false; }
    done
    # …and nothing EXTRA: a scope wider than the lint judges makes the flag's contract false, and it
    # is how `launchd/*` (which unattended-path-lint never judges) survived in the restated pathspec.
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      grep -qF -- " $p " <<<" $want " || { echo "$lint: --print-scope prints '$p', which is not in its judged population"; false; }
    done <<<"$output"
  done <<<"$SCOPE_TABLE"
  set +f
}

# THE ONE NARROWING WORTH ITS OWN CASE. unattended-path-lint's restated pathspec carried `launchd/*`,
# and dropping it is the only entry this change REMOVES from any own-set — so it has to be provably
# inert rather than merely argued. It is: the launchd half reads a plist to learn the PATH a job runs
# with and then scans the SCRIPTS that plist executes, so `emit` is only ever called with a
# hooks/*.sh, a plist_target_scripts result (scripts/ bin/ hooks/) or a tests/*.bats. A plist path can
# never match a finding, so a plist in the own-set could never have made anything block.
@test "unattended-path-lint does not claim launchd/ — no finding of its can name a plist" {
  run bash "$REPO/scripts/unattended-path-lint.sh" --print-scope
  [ "$status" -eq 0 ]
  [[ "$output" != *"launchd/"* ]] || false
  # The proof, from the lint's own text rather than from this comment: every emit() call site names a
  # path variable sourced from one of the three populations, and none reads the plist path itself.
  # `$pl` is the plist; it reaches emit only through `basename` in the MESSAGE, never as the path.
  run grep -nE '^[[:space:]]*emit ' "$REPO/scripts/unattended-path-lint.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *'emit "$pl"'* ]] || false
  [[ "$output" != *'emit "$(basename "$pl")"'* ]]
}

# THE ONE WIDENING WORTH ITS OWN CASE, and the live drift this item was filed on. ship-land restated
# pipefail-sigpipe's population as `bin/* hooks/* scripts/* tests/* docs/* *.sh` — which MISSES
# `*.bats`, a shape that lint judges at every depth. Latent only because every .bats file sits under
# tests/ today, which is a property of the tree and not of the rule.
@test "the derived pipefail own-set reaches a .bats file outside tests/, which the old pathspec missed" {
  local d; d="$(mk_repo)"
  eval "$(extract_fn lint_own_scope)"
  cd "$d"
  mkdir -p suites
  echo x >suites/x.bats
  git -C "$d" add -A; git -C "$d" commit -qm bats
  run lint_own_scope "$REPO/scripts/pipefail-sigpipe-lint.sh" HEAD~1..HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"suites/x.bats"* ]] || false
  # …and the old pathspec provably did NOT reach it. Without this half the assertion above could pass
  # against a pathspec that was fine all along.
  run git diff --name-only HEAD~1..HEAD -- 'bin/*' 'hooks/*' 'scripts/*' 'tests/*' 'docs/*' '*.sh'
  [[ "$output" != *"suites/x.bats"* ]]
}

# ── (4) no arm may restate a pathspec again ──────────────────────────────────────────────────────

@test "not one of the eight own-scope arms is built from a pathspec again" {
  # ALL EIGHT own-set variables, by name. The scope used to be the two env-seam arms only, because
  # the other six legitimately passed literal pathspecs; 5fc8ff411a7c routed those six through
  # lint_own_scope, so the exemption is spent and the ban is now total. Still scoped to the VARIABLES
  # rather than to a pathspec literal — a blanket ban would red on this file's own header, which
  # quotes the removed lines on purpose, and on the legitimate `git diff` calls elsewhere in the gate.
  run grep -E '^\s*(pgown|tsvown|uown|pown|spown|psown|upown|cbown)=.*git diff' "$REPO/scripts/ship-land.sh"
  [ "$status" -ne 0 ] || { echo "an own-set is built from a restated pathspec again: $output"; false; }
  # …and every arm DOES ask its lint, exactly once. Without this half, deleting an arm outright would
  # pass — a gate that judges nothing restates nothing.
  local v
  for v in PERMGATE TSVPAD UTC SELFPATH PSPAWN CHROMIUM PF UNATTENDED; do
    run grep -c "lint_own_scope \"\$${v}_LINT\"" "$REPO/scripts/ship-land.sh"
    [ "$output" = "1" ] || { echo "expected exactly 1 lint_own_scope call for ${v}_LINT, got $output"; false; }
  done
}

# A DERIVED own-set that cannot be derived must stay a NON-VERDICT in every arm, not just the two
# that had it first. Six new `|| { arm_nonverdict …; return 1; }` blocks were written by hand, and a
# copy-paste pair is how one of them ends up saying `|| true` — which is precisely the empty-own-set
# defect this file exists to prevent, arriving by the newest route available.
@test "every arm routes an underivable scope into arm_nonverdict, never into an empty own-set" {
  local n
  n="$(grep -c 'lint_own_scope "\$[A-Z_]*_LINT" "\$range")" || {' "$REPO/scripts/ship-land.sh")"
  [ "$n" = "8" ] || { echo "expected 8 arms guarding lint_own_scope with a || block, found $n"; false; }
  # and not one of them swallows the rc
  run grep -E 'lint_own_scope "\$[A-Z_]*_LINT".*\|\| *true' "$REPO/scripts/ship-land.sh"
  [ "$status" -ne 0 ] || { echo "an arm collapses the non-verdict with '|| true': $output"; false; }
}
