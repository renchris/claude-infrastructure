#!/usr/bin/env bats
# kitty-setup.sh must refuse to link the operator's REAL live layer from a NON-CANONICAL tree.
#
# THE BUG THIS PINS (2026-08-05). The guard that preceded this suite enumerated two ephemeral
# SPELLINGS — ~/.claude/autonomy/postland/wt-run-* and wt-revert-* — rather than the CLASS. An
# ORDINARY session worktree matches neither, so it walked straight past and repointed the live
# layer at itself. Found that way: all six kitty pane-lifecycle tools in ~/.claude/bin (it2-kitty,
# kitty-split-launch.sh, kitty-pane-menu, kitty-split-cwd.sh, kitty-confirm-close, cc-in-kitty)
# pinned into ~/Development/.worktrees/wt-a19ab0fcf13a. deploy-live.sh fast-forwards the CHECKOUT,
# so a link into any other tree can never be moved by a land — and dangles when that tree is reaped.
#
# WHY A REAL WORKTREE AND NOT A STUB. The predicate under test is "--git-dir differs from
# --git-common-dir". Faking that with an env var or a stub `git` would assert the test's own model
# of git rather than git's behaviour, and would have passed against the buggy path-pattern guard
# too. So these tests build a throwaway repo, `git worktree add` a real linked worktree of it, and
# run a byte-for-byte COPY of the real scripts/kitty-setup.sh out of each tree.
#
# WHY THE TARGET IS A THROWAWAY DIR UNDER THE REAL $HOME. The guard is deliberately scoped to the
# dangerous EFFECT: it fires only when the target path lies under REAL_HOME, which the script reads
# from the passwd DB (not $HOME) precisely so a hermetic test cannot spoof it. A test that fixtured
# the target into BATS_TEST_TMPDIR could therefore never trigger the guard at all — it would pass
# vacuously. These tests instead aim at $HOME/.cc-kitty-guardtest-$$, which satisfies the
# effect-scope while touching nothing real, and assert the directory is never created.
#
# BLAST RADIUS IS ZERO BY CONSTRUCTION. The guard runs BEFORE the option parser (kitty-setup.sh:116)
# and before the kitty preflight (:141). So the "did NOT refuse" cases pass an unknown option: the
# script clears the guard, reaches the parser, and exits 2 having created nothing. That is what
# makes "the guard let this through" observable without ever letting the script mutate anything.
#
# Assertions are `[ ]` / `|| false`; `[[ ]]` and `(( ))` are errexit-EXEMPT in bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SETUP_SRC="$REPO/scripts/kitty-setup.sh"
  [ -f "$SETUP_SRC" ] || skip "scripts/kitty-setup.sh not present"
  command -v git >/dev/null 2>&1 || skip "git is required to build the worktree fixture"

  # $HOME is fixtured so every HOME-defaulted seam in the script (SHELL_RC, LOGIN_RC, SHIM_DIR,
  # settings_files) lands in the tmpdir even if a future edit stops honouring the CC_KITTY_* seams.
  # This does NOT weaken anything below: the guard derives REAL_HOME from the passwd DB precisely
  # so $HOME cannot spoof it, so fixturing $HOME leaves the effect-scope fully exercised. Do not
  # "simplify" REAL_HOME to "$HOME" — that would move the target into the tmpdir, the guard would
  # never fire, and all three regression tests would pass vacuously.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"

  # Same derivation the script uses — from the passwd DB, NOT $HOME.
  REAL_HOME="$(eval printf '%s' "~$(id -un)" 2>/dev/null || printf '%s' "$HOME")"
  [ -n "$REAL_HOME" ] || skip "cannot resolve the real home directory"
  LIVE_ISH="$REAL_HOME/.cc-kitty-guardtest-$$"

  # ── the canonical tree, and a REAL linked worktree of it ──────────────────────────────────────
  MAIN="$BATS_TEST_TMPDIR/canon"
  WT="$BATS_TEST_TMPDIR/linked-wt"
  mkdir -p "$MAIN/scripts"
  cp "$SETUP_SRC" "$MAIN/scripts/kitty-setup.sh"   # the REAL artifact, byte-for-byte
  chmod +x "$MAIN/scripts/kitty-setup.sh"
  # Identity is passed per-command, never written with a bare `git config`: an empty -C silently
  # targets the CURRENT repo, which is how a fixture once wrote its identity into the live checkout.
  git -C "$MAIN" init -q >/dev/null 2>&1 || skip "cannot git-init the fixture"
  git -C "$MAIN" add -A >/dev/null 2>&1
  git -C "$MAIN" -c user.name=t -c user.email=t@example.invalid \
      commit -qm fixture >/dev/null 2>&1 || skip "cannot commit the fixture"
  git -C "$MAIN" worktree add -q --detach "$WT" >/dev/null 2>&1 \
    || skip "cannot create a linked worktree here"

  # Seams that must never reach anything real, whichever branch the guard takes.
  export CC_KITTY_SHELL_RC="$BATS_TEST_TMPDIR/zshrc"
  export CC_KITTY_LOGIN_RC="$BATS_TEST_TMPDIR/zprofile"
  export CC_KITTY_SHIM_DIR="$BATS_TEST_TMPDIR/shims"
  export CC_KITTY_SETTINGS="$BATS_TEST_TMPDIR/settings.json"
  export CC_KITTY_NO_SPAWN_CHECK=1
  printf '{"teammateMode":"iterm2"}\n' > "$CC_KITTY_SETTINGS"
  : > "$CC_KITTY_SHELL_RC"; : > "$CC_KITTY_LOGIN_RC"
}

teardown() {
  # Belt and braces: only ever remove a path carrying this suite's own distinctive prefix.
  case "${LIVE_ISH:-}" in
    "${REAL_HOME:-/nonexistent}"/.cc-kitty-guardtest-*) rm -rf "$LIVE_ISH" ;;
  esac
}

# Point the two guarded seams at the throwaway dir under the REAL home.
aim_live() {
  export CC_KITTY_CONFIG_DIR="$LIVE_ISH/config"
  export CC_KITTY_BIN_DIR="$LIVE_ISH/bin"
}
# Point them somewhere fully hermetic — the fixtured-seam case the guard must NOT block.
aim_fixtured() {
  export CC_KITTY_CONFIG_DIR="$BATS_TEST_TMPDIR/kconf"
  export CC_KITTY_BIN_DIR="$BATS_TEST_TMPDIR/kbin"
}

# ── the regression itself ─────────────────────────────────────────────────────────────────────────

@test "refuses to link the real live layer from an ordinary linked worktree" {
  aim_live
  run bash "$WT/scripts/kitty-setup.sh"
  [ "$status" -eq 3 ] || { echo "expected exit 3, got $status"; echo "$output"; false; }
  echo "$output" | grep -q 'NON-CANONICAL' \
    || { echo "refusal did not name the class:"; echo "$output"; false; }
}

@test "the refusal happens BEFORE anything is written" {
  aim_live
  run bash "$WT/scripts/kitty-setup.sh"
  [ "$status" -eq 3 ] || { echo "expected exit 3, got $status"; false; }
  [ ! -e "$LIVE_ISH" ] \
    || { echo "guard refused but the target was created anyway:"; ls -la "$LIVE_ISH"; false; }
}

@test "the refusal names the canonical tree to run from" {
  aim_live
  run bash "$WT/scripts/kitty-setup.sh"
  # $MAIN is the canonical tree of this fixture; the hint must point the caller at it, not at
  # <unresolved>. Compare against the PHYSICAL path: on macOS BATS_TEST_TMPDIR lands under /var,
  # which is a symlink to /private/var, and the script reports `pwd -P` — correctly, since a hint
  # naming a symlinked alias would not match what git itself reports for the tree.
  main_phys="$(cd "$MAIN" && pwd -P)"
  echo "$output" | grep -q "canonical : $main_phys" \
    || { echo "expected the canonical hint to name $main_phys:"; echo "$output"; false; }
}

# ── the three things the guard must NOT break ─────────────────────────────────────────────────────

@test "the canonical tree is NOT refused for the same live target" {
  aim_live
  # --bogus clears the guard, then dies in the option parser (kitty-setup.sh:120) having created
  # nothing. Exit 2 is therefore positive evidence that the guard let this through.
  run bash "$MAIN/scripts/kitty-setup.sh" --bogus
  [ "$status" -eq 2 ] || { echo "expected exit 2 (option parser reached), got $status"; echo "$output"; false; }
  # `grep -q … && { …; false; }` is NOT usable here: when grep does not match, the && list returns
  # grep's 1 as the statement's status and errexit fails the test — the exact inverse of the intent.
  if echo "$output" | grep -q 'NON-CANONICAL'; then
    echo "canonical tree was wrongly refused:"; echo "$output"; false
  fi
  [ ! -e "$LIVE_ISH" ] || { echo "option-parse path wrote to the live target"; false; }
}

@test "a linked worktree with FIXTURED seams still sails past (the verifier-corpus case)" {
  # postland-verify runs the corpus from a throwaway worktree BY CONSTRUCTION. That is legitimate
  # so long as it has fixtured its seams, so the guard must key on the EFFECT, never the location.
  aim_fixtured
  run bash "$WT/scripts/kitty-setup.sh" --bogus
  [ "$status" -eq 2 ] || { echo "expected exit 2 (option parser reached), got $status"; echo "$output"; false; }
  if echo "$output" | grep -q 'NON-CANONICAL'; then
    echo "fixtured seams were wrongly refused:"; echo "$output"; false
  fi
}

@test "--check stays legal from a linked worktree even against the live layer" {
  aim_live
  run bash "$WT/scripts/kitty-setup.sh" --check
  [ "$status" -ne 3 ] || { echo "--check must never be refused:"; echo "$output"; false; }
  if echo "$output" | grep -q 'NON-CANONICAL'; then
    echo "--check was refused:"; echo "$output"; false
  fi
  [ ! -e "$LIVE_ISH" ] || { echo "--check is read-only but created $LIVE_ISH"; false; }
}
