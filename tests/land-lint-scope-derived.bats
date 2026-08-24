#!/usr/bin/env bats
# land-lint-scope-derived.bats — ship-land's own-scope pathspec is DERIVED from each lint, never
# restated beside it (backlog 0be0bd2c0b65, then 5fc8ff411a7c).
#
# THE DEFECT THIS PINS. EIGHT ratchet arms in scripts/ship-land.sh build their own-set — the files
# allowed to BLOCK a land — and every one of them used to spell that set out in ship-land:
#     permission-gate     git diff --name-only "$range" -- 'install.sh' 'scripts/*'
#     tsv-pad             git diff --name-only "$range" -- 'bin/*' 'hooks/*' 'scripts/*'
#     utc-stamp           …                              -- 'bin/*' 'hooks/*' 'scripts/*'
#     pipefail-sigpipe    …    -- 'bin/*' 'hooks/*' 'scripts/*' 'tests/*' 'docs/*' '*.sh'
#     self-path           …                              -- 'bin/*' 'hooks/*' 'scripts/*'
#     pane-spawn          …                 -- 'bin/*' 'hooks/*' 'scripts/*' 'commands/*'
#     unattended-path     …    -- 'bin/*' 'hooks/*' 'scripts/*' 'launchd/*' 'tests/*'
#     chromium-bundle     …                 -- 'bin/*' 'hooks/*' 'scripts/*' 'tools/*'
# Each arm carried a COMMENT asking the next author to widen the pathspec in the same diff if the
# lint's population ever reached another directory. Nothing executes a comment.
#
# THE DRIFT IS SILENT IN THE DANGEROUS DIRECTION, which is why a test and not a comment. An own-set
# that MISSES a file does not error: it is the legitimate spelling of "this land touches nothing I
# judge", so the finding drops to advisory and the land proceeds. A widening that degrades every new
# finding to advisory therefore looks exactly like a clean land.
#
# AND AN ENV SEAM WAS NEVER REQUIRED FOR IT. The first two lints could move their population at
# RUNTIME (CC_PERMGATE_SET / CC_TSVPAD_DIRS), which is why they were closed first; the other six can
# move theirs only by a CODE edit to the lint's own scan set, which was read as a defence and is not
# one. TWO OF THE SIX HAD ALREADY DRIFTED, with no seam involved:
#   · pipefail-sigpipe judges `*.bats` ANYWHERE, and the restatement carried only `tests/*` — so a
#     .bats file outside tests/ could never enter the own-set (asserted below).
#   · unattended-path had `tests/*` grafted on by hand only AFTER a bare `md5` in cc-queue.bats C12
#     passed vacuously on every scheduled run: the lint gained a third population, the pathspec did
#     not move, and the gap was found by the failure rather than before it.
#
# WHAT IS ASSERTED, and the third arm is the one that keeps the others honest:
#   (1) each lint can NAME its population, and the name follows the env seam where one exists
#   (2) ship-land's derivation reaches a file the old hardcoded pathspec missed
#   (3) a lint that CANNOT answer is a NON-VERDICT (rc 2), never an empty own-set — the same defect
#       arriving by a new route, and the one a future `|| true` would reintroduce
#   (4) NO arm carries a hardcoded pathspec again (the copy-a-neighbour regression)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"      # hermeticity: never the operator's live ~
  mkdir -p "$HOME"
  PERMGATE="$REPO/scripts/permission-gate-lint.sh"
  TSVPAD="$REPO/scripts/tsv-pad-lint.sh"
  UTC="$REPO/scripts/utc-stamp-lint.sh"
  PIPEFAIL="$REPO/scripts/pipefail-sigpipe-lint.sh"
  SELFPATH="$REPO/scripts/self-path-lint.sh"
  PSPAWN="$REPO/scripts/pane-spawn-coverage-lint.sh"
  UNATTENDED="$REPO/scripts/unattended-path-lint.sh"
  CHROMIUM="$REPO/scripts/chromium-bundle-lint.sh"
}

# THE EIGHT ARMS, as `<own-var> <lint-var>` pairs — the single list every whole-set assertion below
# iterates. Kept here rather than repeated per test for exactly the reason this file exists: a
# population written down twice drifts, and a ninth arm added to ship-land must fail ONE list, not
# quietly satisfy eight hand-copied assertions.
ARMS='pgown:PERMGATE_LINT
tsvown:TSVPAD_LINT
uown:UTC_LINT
pown:PF_LINT
spown:SELFPATH_LINT
psown:PSPAWN_LINT
upown:UNATTENDED_LINT
cbown:CHROMIUM_LINT'

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

# ── (1b) the six lints with NO env seam — the ones held back from the first pass ─────────────────
# They are asserted the same way and for the same reason. Having no runtime seam is not what makes a
# restatement safe; it only makes the drift arrive by a code edit instead, in the same silent
# direction, which is what the two measured cases below actually did.

@test "utc-stamp-lint --print-scope prints its three scan layers" {
  run bash "$UTC" --print-scope
  [ "$status" -eq 0 ]
  [ "$output" = "bin/*
hooks/*
scripts/*" ]
}

@test "self-path-lint --print-scope prints \$LAYERS, the list lint_tree actually scans" {
  run bash "$SELFPATH" --print-scope
  [ "$status" -eq 0 ]
  [ "$output" = "scripts/*
hooks/*
bin/*" ]
}

@test "pane-spawn-coverage-lint --print-scope prints PSC_DIRS, commands/ included" {
  run bash "$PSPAWN" --print-scope
  [ "$status" -eq 0 ]
  [ "$output" = "bin/*
scripts/*
hooks/*
commands/*" ]
}

@test "chromium-bundle-lint --print-scope prints EMBEDDED_DIRS, tools/ included" {
  run bash "$CHROMIUM" --print-scope
  [ "$status" -eq 0 ]
  [ "$output" = "scripts/*
hooks/*
bin/*
tools/*" ]
}

# THE FIRST MEASURED DRIFT. The lint's own `case` judges `*.bats` under ANY directory; ship-land's
# restatement covered .bats only through `tests/*`. Asserting the pattern is present is asserting
# the closure — see the lint_own_scope case further down for the end-to-end half.
@test "pipefail-sigpipe-lint --print-scope carries *.bats, which the restatement never did" {
  run bash "$PIPEFAIL" --print-scope
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.bats"* ]] || false
  [[ "$output" == *"*.sh"* ]] || false
  [[ "$output" == *"bin/*"* ]] || false
  [[ "$output" == *"hooks/*"* ]] || false
  [[ "$output" == *"scripts/*"* ]]
}

# …and the patterns must survive as PATTERNS. `*.sh` unquoted is subject to pathname expansion as
# well as word splitting, so a `set -f` dropped from either the split or the print turns the scope
# into a list of whatever shell files happen to sit in the caller's CWD — a plausible-looking own-set
# that is silently a different population every time the gate runs from a different directory.
@test "pipefail-sigpipe-lint --print-scope does not glob against the caller's CWD" {
  local d="$BATS_TEST_TMPDIR/globtrap"
  mkdir -p "$d"; : >"$d/decoy.sh"; : >"$d/decoy.bats"
  run bash -c "cd '$d' && bash '$PIPEFAIL' --print-scope"
  [ "$status" -eq 0 ]
  [[ "$output" == *"*.sh"* ]] || false
  [[ "$output" != *"decoy.sh"* ]] || false
  [[ "$output" != *"decoy.bats"* ]]
}

# THE SECOND MEASURED DRIFT, from the other end. This lint judges THREE populations, and `launchd/*`
# was in the restatement while being unreachable: emit() names the TARGET script a plist executes,
# never the plist, so no finding and no allowlist key can carry a plist path. An own-set entry that
# can never match a finding is inert weight that reads as coverage.
@test "unattended-path-lint --print-scope names its three populations, and not launchd/" {
  run bash "$UNATTENDED" --print-scope
  [ "$status" -eq 0 ]
  [[ "$output" == *"hooks/*"* ]] || false
  [[ "$output" == *"tests/*"* ]] || false
  [[ "$output" == *"scripts/*"* ]] || false
  [[ "$output" == *"bin/*"* ]] || false
  [[ "$output" != *"launchd/"* ]]
}

# The scope is built from PLIST_TARGET_DIRS, the same alternation plist_target_scripts greps with, so
# the regex and the declared scope cannot name different sets of reachable targets. Pinned as a
# relation between the two, not as a copy of either.
@test "unattended-path-lint's declared scope covers every dir its plist-target regex can reach" {
  local dirs; dirs="$(sed -n "s/^PLIST_TARGET_DIRS='\(.*\)'\$/\1/p" "$UNATTENDED")"
  [ -n "$dirs" ] || false
  run bash "$UNATTENDED" --print-scope
  [ "$status" -eq 0 ]
  local d
  for d in ${dirs//|/ }; do
    [[ "$output" == *"$d/*"* ]] || { echo "plist targets may live in $d/, but --print-scope omits it" >&2; return 1; }
  done
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

# THE SAME ASSERTION FOR THE SEAMLESS SIX, end to end and without an env override to lean on — the
# mutant here is the REAL pre-fix pathspec, replayed verbatim, rather than a widened population.
# tools/probe.bats is judged by pipefail-sigpipe-lint (its case matches `*.bats` under any dir) and
# was unreachable from `-- 'bin/*' 'hooks/*' 'scripts/*' 'tests/*' 'docs/*' '*.sh'`: the finding
# would have printed as advisory and landed. Both halves must hold, or the test proves nothing —
# the old pathspec must MISS it and the derivation must FIND it.
@test "lint_own_scope reaches a .bats outside tests/ that the pipefail pathspec could not" {
  local d="$BATS_TEST_TMPDIR/drift"
  mkdir -p "$d/tools"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git init -q "$d"
  : >"$d/seed"; git -C "$d" add -A; git -C "$d" commit -qm base
  echo x >"$d/tools/probe.bats"; git -C "$d" add -A; git -C "$d" commit -qm work
  eval "$(extract_fn lint_own_scope)"
  cd "$d"
  # the RESTATEMENT that shipped, replayed exactly — it must come back empty
  run git diff --name-only HEAD~1..HEAD -- 'bin/*' 'hooks/*' 'scripts/*' 'tests/*' 'docs/*' '*.sh'
  [ -z "$output" ] || { echo "the old pathspec already reached it — this control proves nothing" >&2; return 1; }
  run lint_own_scope "$PIPEFAIL" HEAD~1..HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"tools/probe.bats"* ]]
}

# …and the converse, on the arm that restated too WIDE. A plist is in no finding this lint can emit,
# so an own-set carrying one is inert — it reads as coverage and buys nothing.
@test "lint_own_scope drops the launchd/ entry the unattended pathspec could never use" {
  local d="$BATS_TEST_TMPDIR/wide"
  mkdir -p "$d/launchd"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git init -q "$d"
  : >"$d/seed"; git -C "$d" add -A; git -C "$d" commit -qm base
  echo x >"$d/launchd/j.plist"; git -C "$d" add -A; git -C "$d" commit -qm work
  eval "$(extract_fn lint_own_scope)"
  cd "$d"
  run git diff --name-only HEAD~1..HEAD -- 'bin/*' 'hooks/*' 'scripts/*' 'launchd/*' 'tests/*'
  [[ "$output" == *"launchd/j.plist"* ]] || { echo "the old pathspec did not carry it — this control proves nothing" >&2; return 1; }
  run lint_own_scope "$UNATTENDED" HEAD~1..HEAD
  # SET-BUT-EMPTY (rc 0), never rc 2: a plist-only land legitimately blocks on nothing here.
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# EVERY arm's lint must ANSWER — a lint that cannot is routed to arm_nonverdict, so a silent
# regression here converts a whole ratchet into a retryable gate-kill on every land.
@test "all eight arms' lints answer --print-scope with a non-empty set" {
  local pair lint out
  for pair in $ARMS; do
    case "${pair#*:}" in
      PERMGATE_LINT)   lint="$PERMGATE" ;;   TSVPAD_LINT)     lint="$TSVPAD" ;;
      UTC_LINT)        lint="$UTC" ;;        PF_LINT)         lint="$PIPEFAIL" ;;
      SELFPATH_LINT)   lint="$SELFPATH" ;;   PSPAWN_LINT)     lint="$PSPAWN" ;;
      UNATTENDED_LINT) lint="$UNATTENDED" ;; CHROMIUM_LINT)   lint="$CHROMIUM" ;;
      *) echo "unmapped arm ${pair#*:} — add it to this case" >&2; return 1 ;;
    esac
    out="$(bash "$lint" --print-scope)" || { echo "$lint --print-scope exited non-zero" >&2; return 1; }
    [ -n "$out" ] || { echo "$lint --print-scope printed NOTHING — every consumer reads that as a non-verdict" >&2; return 1; }
  done
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

@test "no ratchet arm's own-set is built from a pathspec again" {
  # SCOPED TO THE EIGHT VARIABLES, not to a pathspec literal — and it must stay that way. Other arms
  # in ship-land legitimately pass a literal `-- 'tests/*.bats' …` (the gate-select, walltime,
  # assertion, memo, git-identity and kill-guard own-sets): those consume lints that have no
  # --print-scope, so a blanket literal-pathspec ban would red on innocents. It would also red on
  # this file's own header, which quotes the removed lines on purpose.
  #
  # WHY ALL EIGHT NOW (backlog 5fc8ff411a7c). This assertion used to cover pgown and tsvown alone,
  # under a comment reasoning that the other six lints had no env seam and so "cannot drift the way
  # these two could". The reasoning was wrong in the only way that matters: a code edit to a lint's
  # scan set moves the population just as silently as an env var, and TWO of the six had already
  # drifted when this was written — pipefail carried no `*.bats`, unattended had `tests/*` grafted
  # on by hand only after a bare `md5` passed vacuously on every scheduled run.
  local pair var lint
  for pair in $ARMS; do
    var="${pair%%:*}"; lint="${pair#*:}"
    run grep -E "^[[:space:]]*${var}=.*git diff" "$REPO/scripts/ship-land.sh"
    [ "$status" -ne 0 ] || { echo "$var is built from a hardcoded pathspec again — ask the lint" >&2; return 1; }
    # …and the arm DOES ask its lint. Without this half, deleting the arm outright would pass.
    run grep -c "lint_own_scope \"\\\$${lint}\"" "$REPO/scripts/ship-land.sh"
    [ "$output" = "1" ] || { echo "expected exactly 1 lint_own_scope call for \$$lint, found $output" >&2; return 1; }
  done
}

# THE LIST ITSELF MUST NOT GO STALE. A ninth arm wired to lint_own_scope and left out of $ARMS would
# be unpinned by every assertion above while the suite stayed green — the same "written down twice"
# failure this file exists to prevent, one level up (memory: control-must-replay-the-real-artifact).
@test "\$ARMS names every lint_own_scope call site in ship-land" {
  local actual expected
  actual="$(grep -oE 'lint_own_scope "\$[A-Z_]+"' "$REPO/scripts/ship-land.sh" \
            | sed -E 's/.*\$([A-Z_]+)".*/\1/' | sort -u)"
  expected="$(printf '%s\n' "$ARMS" | sed 's/.*://' | sort -u)"
  [ "$actual" = "$expected" ] || {
    echo "ship-land's lint_own_scope call sites and \$ARMS disagree:" >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
    return 1; }
}
