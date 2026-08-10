#!/usr/bin/env bats
# `run --separate-stderr` is a 1.5.0+ flag; without this declaration bats 1.13 still runs the case
# but warns BW02 on every use, which turns a green suite into a wall of noise.
bats_require_minimum_version 1.5.0
# deploy-now.sh — the operator's deploy entrypoint (`bash ~/.claude/DEPLOY-NOW.sh`).
#
# THE CRUX THIS SUITE EXISTS FOR, RESTATED. It used to be "the ff is NOT the deployment": ~/.claude
# is a tree of per-file symlinks, so a fast-forward updates already-linked files and deploys nothing
# for a file the checkout gained, and the script's own step 5 reported that gap without ever closing
# it. The resolution was not a better report — it was deleting the raw ff. deploy-now.sh is now a
# THIN FRONT-END onto scripts/deploy-live.sh, the only sanctioned advance, which both gates the
# content and creates the links. So the contract under test moved with it, from "does the ff report
# honestly" to "does this entrypoint still refuse to advance the checkout ITSELF".
#
# THE LOAD-BEARING CASE is `deploy-now advances nothing itself` — the regression guard for backlog
# c50158434c7a. It is paired with a MUTATION CONTROL that re-inserts a raw ff into a copy and
# requires the same assertion to FAIL, because a "no forbidden string" grep over a file whose own
# header quotes the forbidden strings in prose is exactly the shape that passes vacuously.
#
# HERMETIC: each case drives the script against a fixture checkout via CC_DEPLOY_REPO and a
# RECORDING STAND-IN for deploy-live.sh via CC_DEPLOY_LIVE. Nothing here fetches a network remote,
# touches the real checkout, runs the real deploy-live, or reads the real ~/.claude.
#
# ASSERTION FORM: non-final `[[ ]]` and bare `!` are silently DEAD under bats+set -e (bats 1.13.0).
# Every assertion below is a `[ ]`, a helper call, or a pipeline.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never touch the live ~/

  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DN="$REPO_ROOT/scripts/deploy-now.sh"

  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  export CC_DEPLOY_REPO="$BATS_TEST_TMPDIR/checkout"

  git init --quiet --bare --initial-branch=main "$ORIGIN"
  git clone --quiet "$ORIGIN" "$CC_DEPLOY_REPO"
  git -C "$CC_DEPLOY_REPO" symbolic-ref HEAD refs/heads/main
  mkdir -p "$CC_DEPLOY_REPO/scripts"
  printf 'x\n' > "$CC_DEPLOY_REPO/hooks-placeholder"
  git -C "$CC_DEPLOY_REPO" add -A
  git -C "$CC_DEPLOY_REPO" commit --quiet -m base
  git -C "$CC_DEPLOY_REPO" push --quiet origin main

  # RECORDING STAND-IN for deploy-live.sh. Records argv one-per-line and the two env vars the
  # delegation contract must carry, then exits with whatever STUB_RC says. Never touches git.
  STUB="$BATS_TEST_TMPDIR/deploy-live-stub.sh"
  ARGV_LOG="$BATS_TEST_TMPDIR/argv.log"
  ENV_LOG="$BATS_TEST_TMPDIR/env.log"
  cat > "$STUB" <<'STUBEOF'
#!/bin/bash
# `printf '%s\n' "$@"` with ZERO args still runs the format once and emits a bare newline, so a
# no-arg invocation would log a 1-byte file and read as "one empty argument". Branch instead.
if [ "$#" -gt 0 ]; then printf '%s\n' "$@" > "$ARGV_LOG"; else : > "$ARGV_LOG"; fi
{ printf 'DEPLOY_REPO=%s\n' "${DEPLOY_REPO:-<unset>}"
  printf 'CC_DEPLOY_REPO=%s\n' "${CC_DEPLOY_REPO:-<unset>}"; } > "$ENV_LOG"
echo "STUB-STDOUT-MARKER"
exit "${STUB_RC:-0}"
STUBEOF
  chmod +x "$STUB"
  export CC_DEPLOY_LIVE="$STUB" ARGV_LOG ENV_LOG
}

has()   { printf '%s' "$output" | grep -qF -- "$1"; }
lacks() { if printf '%s' "$output" | grep -qF -- "$1"; then return 1; fi; return 0; }

# Does $1 (a shell script) advance a checkout ITSELF? Comments are DELETED before matching, not
# excluded by a smarter pattern: deploy-now.sh's own header quotes every forbidden spelling in
# prose, so a match against the raw file reports the documentation and can never go green. Returns
# 0 when a real advancing command is present — i.e. `run advances_head_itself X` gives status 0 for
# a violating file and 1 for a clean one.
advances_head_itself() {
  sed 's/[[:space:]]*#.*$//' "$1" \
    | grep -qE 'git[^|;&]*(merge[[:space:]]+--ff-only|pull[^|;&]*--ff-only|reset[[:space:]]+--hard|checkout[[:space:]]+-B)'
}

@test "deploy-now advances nothing itself — no raw ff/pull/reset survives in the body (c50158434c7a)" {
  run advances_head_itself "$DN"
  [ "$status" -eq 1 ]
}

@test "MUTATION CONTROL: the same check FAILS when a raw ff is re-inserted" {
  local mutant="$BATS_TEST_TMPDIR/mutant.sh"
  cp "$DN" "$mutant"
  printf 'git merge --ff-only origin/main\n' >> "$mutant"   # the deleted line, restored
  run advances_head_itself "$mutant"
  [ "$status" -eq 0 ]
}

@test "MUTATION CONTROL: a commented-out ff is NOT a violation (the check reads code, not prose)" {
  local mutant="$BATS_TEST_TMPDIR/prose.sh"
  cp "$DN" "$mutant"
  printf '# git merge --ff-only origin/main -- discussed, deliberately not done\n' >> "$mutant"
  run advances_head_itself "$mutant"
  [ "$status" -eq 1 ]
}

@test "it delegates to deploy-live and propagates its exit code" {
  STUB_RC=0 run "$DN"
  [ "$status" -eq 0 ]
  has "STUB-STDOUT-MARKER"
  STUB_RC=7 run "$DN"
  [ "$status" -eq 7 ]
}

@test "every flag reaches deploy-live verbatim — the --force escape hatch still works" {
  run "$DN" --force
  [ "$status" -eq 0 ]
  [ "$(cat "$ARGV_LOG")" = "--force" ]
}

@test "multi-flag argv is passed through in order, not re-quoted or collapsed" {
  run "$DN" --dry-run --offline
  [ "$status" -eq 0 ]
  printf '%s' "$(cat "$ARGV_LOG")" | grep -qx -- '--dry-run'
  printf '%s' "$(cat "$ARGV_LOG")" | grep -qx -- '--offline'
  [ "$(wc -l < "$ARGV_LOG" | tr -d ' ')" = "2" ]
}

@test "no args ⇒ deploy-live is invoked with NO args (never a synthesised default)" {
  run "$DN"
  [ "$status" -eq 0 ]
  [ ! -s "$ARGV_LOG" ]
}

@test "CC_DEPLOY_REPO is bridged to the DEPLOY_REPO that deploy-live actually reads" {
  run "$DN"
  [ "$status" -eq 0 ]
  grep -qx "DEPLOY_REPO=$CC_DEPLOY_REPO" "$ENV_LOG"
}

@test "the delegation banner goes to stderr, never stdout (the platter parses stdout)" {
  run --separate-stderr "$DN"
  [ "$status" -eq 0 ]
  printf '%s' "$stderr" | grep -qF "delegates to the sanctioned advance"
  printf '%s' "$output" | grep -qF "STUB-STDOUT-MARKER"
  if printf '%s' "$output" | grep -qF "delegates to the sanctioned advance"; then return 1; fi
}

@test "--auto is silent: the 600s launchd tick must not gain a line per run" {
  run --separate-stderr "$DN" --auto
  [ "$status" -eq 0 ]
  if printf '%s' "$stderr" | grep -qF "delegates to the sanctioned advance"; then return 1; fi
}

@test "--offline is silent too: the operator platter reads its verdict" {
  run --separate-stderr "$DN" --offline
  [ "$status" -eq 0 ]
  if printf '%s' "$stderr" | grep -qF "delegates to the sanctioned advance"; then return 1; fi
}

@test "a missing deploy-live fails LOUD and never falls back to a raw ff" {
  export CC_DEPLOY_LIVE="$BATS_TEST_TMPDIR/no-such-deploy-live.sh"
  local before; before="$(git -C "$CC_DEPLOY_REPO" rev-parse HEAD)"
  run "$DN"
  [ "$status" -eq 1 ]
  has "ABORT"
  has "will NOT fall back to a raw fast-forward"
  # the checkout must be untouched — a silent fallback is the whole hole this guards
  [ "$(git -C "$CC_DEPLOY_REPO" rev-parse HEAD)" = "$before" ]
}

@test "a non-executable deploy-live is refused, not sourced or ignored" {
  local dud="$BATS_TEST_TMPDIR/dud.sh"
  printf '#!/bin/bash\ntrue\n' > "$dud"; chmod -x "$dud"
  export CC_DEPLOY_LIVE="$dud"
  run "$DN"
  [ "$status" -eq 1 ]
  has "not executable"
}

@test "a missing checkout fails loudly instead of deploying nothing quietly" {
  export CC_DEPLOY_REPO="$BATS_TEST_TMPDIR/no-such-checkout"
  run "$DN"
  [ "$status" -eq 1 ]
  has "repo not found"
}
