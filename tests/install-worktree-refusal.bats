#!/usr/bin/env bats
# install-worktree-refusal.bats — install.sh must refuse a GLOBAL install from a linked worktree.
#
# The defect (latent, closed 2026-07-30): install.sh:14 derives REPO_DIR from $0 alone and has
# never been git-aware, so link_file points every ~/.claude/** entry at whatever checkout the
# script happens to live in. Run from a linked worktree, the entire live layer targets a directory
# that `git worktree remove` / scripts/worktree-gc.sh may delete — every hook, command, skill and
# cc-* tool dangles at once, and deploy-live.sh cannot repair it (it only reaches its install.sh
# call after a green stamp, which the dead hooks can no longer produce). Measured while authoring:
# one --config-dir run from a worktree produced 120 worktree-pointing symlinks.
#
# Red-proof (measured, not asserted): against `git show HEAD:install.sh` recovered into place, this
# suite reads `not ok` on tests 1, 2, 3 and 5 and `ok` on 4, 6, 7, 8. Tests 4/6/7 are the
# false-positive guards — each pins a lane a BLANKET refusal would have broken, so they must pass
# both before and after. Test 8 is the positive control: it asserts the guarded mechanism is real
# (links really do land in the worktree), so 1/2/3/5 cannot pass vacuously.
#
# Hermeticity: fixture $HOME first; every install runs against a fixture repo + fixture config dir.
# `launchctl` and `defaults` are PATH-stubbed because the global leg calls both against real
# machine state (LaunchAgents; the com.googlecode.iterm2 pref) regardless of $HOME.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"     # hermetic: never touch the live ~/
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

  # Physical paths throughout: macOS mktemp -d returns /var/... (a symlink to /private/var/...),
  # and git reports the physical form — so a logical fixture path would not match the message.
  TDIR="$(cd "$(mktemp -d)" && pwd -P)"
  export TDIR
  PRIMARY="$TDIR/primary"
  WT="$TDIR/wt"

  # Minimal but REAL repo: install.sh aborts under `set -e` if CLAUDE.md or statusline.sh are
  # absent (both are unconditional cp targets), and agents/ gives the link legs something to link.
  mkdir -p "$PRIMARY/agents"
  cp "$REPO/install.sh" "$PRIMARY/install.sh"
  printf '# fixture global instructions\n' > "$PRIMARY/CLAUDE.md"
  printf '#!/bin/bash\necho fixture-statusline\n' > "$PRIMARY/statusline.sh"
  printf 'fixture agent\n' > "$PRIMARY/agents/fixture-agent.md"
  git init -q "$PRIMARY"
  git -C "$PRIMARY" -c user.email=t@t -c user.name=t add -A
  git -C "$PRIMARY" -c user.email=t@t -c user.name=t commit -q -m base
  git -C "$PRIMARY" worktree add -q "$WT" -b wt-fixture

  # launchctl/defaults reach real machine state from the global leg — stub both.
  STUB="$TDIR/stub"; mkdir -p "$STUB"
  printf '#!/bin/sh\nexit 0\n' > "$STUB/launchctl"
  printf '#!/bin/sh\nexit 0\n' > "$STUB/defaults"
  chmod +x "$STUB/launchctl" "$STUB/defaults"
  export PATH="$STUB:$PATH"
}

teardown() {
  git -C "$TDIR/primary" worktree remove --force "$TDIR/wt" 2>/dev/null || true
  rm -rf "$TDIR"
}

has()   { printf '%s' "$output" | grep -qF -- "$1"; }
lacks() { if printf '%s' "$output" | grep -qF -- "$1"; then return 1; fi; return 0; }

# ---- the refusal ------------------------------------------------------------------------------

@test "global install from a linked worktree is REFUSED and writes nothing" {
  run bash "$WT/install.sh"
  [ "$status" -eq 1 ]
  has "REFUSING a global install from a linked worktree"
  has "$WT"
  # refuses BEFORE any filesystem work — the config dir must not exist at all
  [ ! -e "$HOME/.claude" ]
}

@test "the refusal names the primary checkout and hands over an exact re-run command" {
  run bash "$WT/install.sh"
  [ "$status" -eq 1 ]
  has "$PRIMARY"
  has "Re-run from the primary checkout"
  has "$PRIMARY/install.sh"
}

@test "the refusal survives --dry-run (a preview of the catastrophe is not a safe preview)" {
  run bash "$WT/install.sh" --dry-run
  [ "$status" -eq 1 ]
  has "REFUSING a global install from a linked worktree"
  [ ! -e "$HOME/.claude" ]
}

# ---- false-positive guards: each pins a lane a blanket refusal would have broken --------------

@test "--config-dir from a linked worktree is NOT refused (postland + /ship run the suite there)" {
  # postland-verify.sh mints wt-run-\$\$ per run and ship-land.sh refuses to land from the shared
  # checkout, so tests/install-wire-hooks.bats executes from a linked worktree BY CONSTRUCTION.
  # Refusing it would red every postland run ⇒ no green stamp ⇒ deploy-live.sh stops advancing.
  run bash "$WT/install.sh" --config-dir "$BATS_TEST_TMPDIR/altcfg"
  [ "$status" -eq 0 ]
  lacks "REFUSING"
  [ -e "$BATS_TEST_TMPDIR/altcfg/agents/fixture-agent.md" ]
}

@test "--config-dir from a worktree still WARNS (an alt config dir inherits the dangling links)" {
  run bash "$WT/install.sh" --config-dir "$BATS_TEST_TMPDIR/altcfg"
  [ "$status" -eq 0 ]
  has "installing from a linked worktree"
}

@test "global install from the PRIMARY checkout is NOT refused (deploy-live.sh runs exactly this)" {
  # deploy-live.sh:283-284 invokes "\$DEPLOY_REPO/install.sh" globally from the fixed primary
  # checkout. A guard that fired here would kill the very lane it exists to protect.
  run bash "$PRIMARY/install.sh"
  [ "$status" -eq 0 ]
  lacks "REFUSING"
  [ -L "$HOME/.claude/agents/fixture-agent.md" ]
}

@test "a non-git checkout still installs — detection fails OPEN for tarballs / fresh machines" {
  plain="$TDIR/plain"
  mkdir -p "$plain"
  cp -R "$PRIMARY/install.sh" "$PRIMARY/CLAUDE.md" "$PRIMARY/statusline.sh" "$PRIMARY/agents" "$plain/"
  run bash "$plain/install.sh"
  [ "$status" -eq 0 ]
  lacks "REFUSING"
}

# ---- positive control: the guarded mechanism is real ------------------------------------------

@test "POSITIVE CONTROL: with the guard overridden, a worktree install DOES point links at it" {
  # Without this, tests 1/2/3 could pass vacuously against a refusal that guards nothing.
  # CC_INSTALL_ALLOW_WORKTREE=1 is the documented escape hatch AND the red-proof lever: it
  # reproduces the pre-fix behaviour exactly.
  run env CC_INSTALL_ALLOW_WORKTREE=1 bash "$WT/install.sh"
  [ "$status" -eq 0 ]
  lacks "REFUSING"
  [ -L "$HOME/.claude/agents/fixture-agent.md" ]
  run readlink "$HOME/.claude/agents/fixture-agent.md"
  has "$WT"
}
