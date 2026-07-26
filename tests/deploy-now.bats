#!/usr/bin/env bats
# deploy-now.sh — the operator's deploy entrypoint (`bash ~/.claude/DEPLOY-NOW.sh`).
#
# The crux this suite exists for: the ff is NOT the deployment. ~/.claude is a tree of per-file
# symlinks, so a fast-forward updates already-linked files and deploys nothing for a file the
# checkout gained. The old script made that permanent by exiting 0 at "already current — nothing to
# deploy" — the exact state a SIBLING session's ff leaves behind, with the new file still unlinked.
# So link parity must run on BOTH paths, and a ff that leaves files unlinked must not report ✓✓.
#
# HERMETIC: each case builds a bare origin + a clone in BATS_TEST_TMPDIR and drives the script via
# CC_DEPLOY_REPO, with the reporter pinned to a fixture config dir via CC_LINKPARITY_CONFIG.
# Nothing here fetches a network remote, touches the real checkout, or reads the real ~/.claude.
#
# ASSERTION FORM: non-final `[[ ]]` and bare `!` are silently DEAD under bats+set -e (bats 1.13.0).
# Every assertion below is a `[ ]`, a helper call, or a pipeline.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DN="$REPO_ROOT/scripts/deploy-now.sh"

  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  export CC_DEPLOY_REPO="$BATS_TEST_TMPDIR/checkout"
  export CC_LINKPARITY_CONFIG="$BATS_TEST_TMPDIR/cfg"
  export CC_LINKPARITY_BINDIR="$BATS_TEST_TMPDIR/bin"
  export CC_LINKPARITY_PENDING="$BATS_TEST_TMPDIR/pending"
  mkdir -p "$CC_LINKPARITY_CONFIG"/{hooks,scripts} "$CC_LINKPARITY_BINDIR" "$CC_LINKPARITY_PENDING"

  git init --quiet --bare --initial-branch=main "$ORIGIN"
  git clone --quiet "$ORIGIN" "$CC_DEPLOY_REPO"
  git -C "$CC_DEPLOY_REPO" symbolic-ref HEAD refs/heads/main

  # the checkout carries the reporter, exactly as the real one does
  mkdir -p "$CC_DEPLOY_REPO/scripts" "$CC_DEPLOY_REPO/hooks"
  cp "$REPO_ROOT/scripts/deploy-link-parity.sh" "$CC_DEPLOY_REPO/scripts/"
  printf 'x\n' > "$CC_DEPLOY_REPO/hooks/established.sh"
  ln -sfn "$CC_DEPLOY_REPO/hooks/established.sh" "$CC_LINKPARITY_CONFIG/hooks/established.sh"
  ln -sfn "$CC_DEPLOY_REPO/scripts/deploy-link-parity.sh" "$CC_LINKPARITY_CONFIG/scripts/deploy-link-parity.sh"
  git -C "$CC_DEPLOY_REPO" add -A
  git -C "$CC_DEPLOY_REPO" commit --quiet -m base
  git -C "$CC_DEPLOY_REPO" push --quiet origin main
}

has()   { printf '%s' "$output" | grep -qF -- "$1"; }
lacks() { if printf '%s' "$output" | grep -qF -- "$1"; then return 1; fi; return 0; }

# land a file on origin/main WITHOUT deploying a live link for it — the real-world shape:
# another session pushed, some session ff'd this checkout, the link was never created.
land_on_origin() {
  local work="$BATS_TEST_TMPDIR/pusher"
  rm -rf "$work"
  git clone --quiet "$ORIGIN" "$work"
  mkdir -p "$work/$(dirname "$1")"
  printf 'new\n' > "$work/$1"
  git -C "$work" add -A
  git -C "$work" commit --quiet -m "land $1"
  git -C "$work" push --quiet origin main
}

@test "already current + everything linked ⇒ exit 0" {
  run "$DN"
  [ "$status" -eq 0 ]
  has "already current"
  has "every landed file is live"
}

@test "ALREADY CURRENT but a landed file is unlinked ⇒ exit 1 (the bug: old script exited 0 here)" {
  land_on_origin "scripts/desk-arm-live.sh"
  git -C "$CC_DEPLOY_REPO" fetch --quiet origin main
  git -C "$CC_DEPLOY_REPO" merge --quiet --ff-only origin/main   # a sibling session's ff
  run "$DN"
  [ "$status" -eq 1 ]
  has "already current"
  has "UNLINKED"
  has "scripts/desk-arm-live.sh"
}

@test "the ff path runs link parity too, and reports ✓✓ only when every file is live" {
  land_on_origin "docs/note.md"     # docs/ is not a symlink surface — nothing to link
  run "$DN"
  [ "$status" -eq 0 ]
  has "fast-forward"
  has "DEPLOYED"
  has "every landed file is live"
}

@test "a ff that leaves a new hook unlinked never reports ✓✓ DEPLOYED" {
  land_on_origin "hooks/brand-new.sh"
  run "$DN"
  [ "$status" -eq 1 ]
  has "DEPLOY INCOMPLETE"
  has "UNLINKED"
  has "hooks/brand-new.sh"
  lacks "✓✓ DEPLOYED"
}

@test "the report hands back an exact ln -sfn command, not a description" {
  land_on_origin "hooks/brand-new.sh"
  run "$DN"
  [ "$status" -eq 1 ]
  has "ln -sfn \"$CC_DEPLOY_REPO/hooks/brand-new.sh\" \"$CC_LINKPARITY_CONFIG/hooks/brand-new.sh\""
}

@test "a landed file awaiting its staged activation is NOT a deploy failure" {
  land_on_origin "hooks/dispatch-assert.sh"
  printf '#!/bin/bash\nSRC="$REPO/hooks/dispatch-assert.sh"\n' \
    > "$CC_LINKPARITY_PENDING/11-dispatch-assert-activate.sh"
  run "$DN"
  [ "$status" -eq 0 ]
  has "PENDING"
  has "DEPLOYED"
}

@test "an unexpected dirty tracked file aborts before the ff" {
  land_on_origin "docs/note.md"
  printf 'local edit\n' >> "$CC_DEPLOY_REPO/hooks/established.sh"
  run "$DN"
  [ "$status" -eq 1 ]
  has "ABORT"
  has "hooks/established.sh"
  # the ff must not have happened
  run git -C "$CC_DEPLOY_REPO" rev-list --count HEAD..origin/main
  [ "$output" = "1" ]
}

@test "a checkout with no reporter warns but still completes the ff (bootstrap tolerance)" {
  rm -f "$CC_DEPLOY_REPO/scripts/deploy-link-parity.sh"
  git -C "$CC_DEPLOY_REPO" add -A
  git -C "$CC_DEPLOY_REPO" commit --quiet -m "drop reporter"
  git -C "$CC_DEPLOY_REPO" push --quiet origin main
  land_on_origin "docs/note.md"
  run "$DN"
  [ "$status" -eq 0 ]
  has "cannot verify"
}

@test "a missing checkout fails loudly instead of deploying nothing quietly" {
  export CC_DEPLOY_REPO="$BATS_TEST_TMPDIR/no-such-checkout"
  run "$DN"
  [ "$status" -eq 1 ]
  has "repo not found"
}
