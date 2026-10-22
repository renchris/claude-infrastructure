#!/usr/bin/env bats
# install.sh puts it2 and the qos-shim names behind cc-shim (docs/plans/KALLOC_TRIGGER_ELIMINATION_2026-10-22.md
# W4). macOS 15 keeps ~1.1 KiB of kernel memory per #! exec until reboot, and code we do not control runs
# ~/.claude/bin/it2 (Claude Code) and the qos-shim names (any agent command line) by path. With cc-shim
# built, bin/<name> → libexec/cc-shim and the real file sits at .bin-real/<name>; CC_SHIM_ENTRIES=0 is
# the rollback to the old layout, and a rollback must replace the shim link rather than cp THROUGH it.
#
# Hermetic: fixture $HOME, a fixture repo holding only what these legs read (install.sh refuses a
# global install from a linked worktree, so it cannot run from this checkout), a launchctl stub behind
# install.sh's own seam, and cc-shim compiled from the tracked source into the fixture $HOME's cache.
# The execs at the end go through that REAL compiled shim, which is the point of the test.

setup() {
  load helpers/cc-stub
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  command -v "${CC:-clang}" >/dev/null 2>&1 || skip "no C compiler: cc-shim cannot be built"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CLAUDE_CONFIG_DIR CC_SHIM_ENTRIES CC_SHIM_INSTALL
  CFG="$HOME/.claude"
  FX="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FX/bin" "$FX/config" "$FX/tools/cc-shim" "$FX/launchd"
  cp "$REPO/install.sh" "$FX/install.sh"
  printf '# fixture global instructions\n' > "$FX/CLAUDE.global.md"
  cp "$REPO/statusline.sh" "$FX/statusline.sh"
  cp "$REPO/bin/it2-wrapper" "$REPO/bin/cc-qos-exec" "$FX/bin/"
  cp "$REPO/config/qos-batch.patterns" "$FX/config/"
  printf 'shellcheck\n' > "$FX/config/qos-shim.names"
  cp "$REPO/tools/cc-shim/build.sh" "$REPO/tools/cc-shim/cc-shim.c" "$FX/tools/cc-shim/"
  git init -q "$FX"
  cc_stub "$BATS_TEST_TMPDIR/stub" launchctl $'#!/bin/sh\nexit 0'
  export CC_INSTALL_LAUNCHCTL_BIN="$BATS_TEST_TMPDIR/stub/launchctl"
}

install_run() { run bash "$FX/install.sh"; }

@test "with cc-shim built: bin/it2 and bin/shellcheck are trampoline links and both run through it" {
  install_run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -x "$CFG/libexec/cc-shim" ] || { echo "$output"; false; }
  [ -L "$CFG/bin/it2" ]
  [ "$CFG/bin/it2" -ef "$CFG/libexec/cc-shim" ]
  [ -f "$CFG/.bin-real/it2" ]
  [ ! -L "$CFG/.bin-real/it2" ]          # still a real COPY
  cmp -s "$REPO/bin/it2-wrapper" "$CFG/.bin-real/it2"
  [ "$CFG/bin/shellcheck" -ef "$CFG/libexec/cc-shim" ]
  [ "$(readlink "$CFG/.bin-real/shellcheck")" = "$FX/bin/cc-qos-exec" ]
  [ ! -e "$CFG/bin/it2.pre-link.bak" ]

  # it2 through the shim: the wrapper runs and execs the CLI it was told to (a stand-in).
  cc_stub "$BATS_TEST_TMPDIR/cli" it2 $'#!/bin/sh\necho "CLI $*"'
  IT2_WRAPPER_REAL="$BATS_TEST_TMPDIR/cli/it2" IT2_WRAPPER_NO_KITTY=1 run "$CFG/bin/it2" session list
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '^CLI session list')" -eq 1 ] || { echo "$output"; false; }

  # ShellCheck through the shim → .bin-real/shellcheck → cc-qos-exec → the real shellcheck, no loop.
  # The first shellcheck on the ambient PATH may itself be a qos-shim link (the operator's own
  # ~/.claude/bin), which cc-qos-exec rightly skips: find the first one that is not.
  local sc="" c
  while IFS= read -r c; do
    case "$(readlink "$c" 2>/dev/null)" in *cc-qos-exec|*cc-shim) continue ;; esac
    sc="$c"; break
  done < <(type -ap shellcheck)
  [ -n "$sc" ] || skip "no real shellcheck on PATH"
  PATH="$CFG/bin:${sc%/*}:/usr/bin:/bin" run shellcheck --version
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '^version:')" -eq 1 ] || { echo "$output"; false; }
}

# Claude Code's login-shell lookup finds scripts/kitty-setup.sh's shims/it2 → bin/it2 first. cc-shim
# derives its target from that UNRESOLVED path, so the route runs .shims-real/it2, which install.sh
# points at the .bin-real copy. Proven by running it, with the pre-fix state as the control.
@test "with cc-shim built: shims/it2 → bin/it2 runs the wrapper through .shims-real/it2" {
  install_run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$CFG/.shims-real/it2" -ef "$CFG/.bin-real/it2" ]
  mkdir -p "$CFG/shims"
  ln -s "$CFG/bin/it2" "$CFG/shims/it2"                   # what kitty-setup.sh step 3b creates
  cc_stub "$BATS_TEST_TMPDIR/cli" it2 $'#!/bin/sh\necho "CLI $*"'
  IT2_WRAPPER_REAL="$BATS_TEST_TMPDIR/cli/it2" IT2_WRAPPER_NO_KITTY=1 run "$CFG/shims/it2" session list
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '^CLI session list')" -eq 1 ] || { echo "$output"; false; }
  # Control: without .shims-real/it2 the same route cannot run, so the link above is what made it.
  rm "$CFG/.shims-real/it2"
  IT2_WRAPPER_REAL="$BATS_TEST_TMPDIR/cli/it2" IT2_WRAPPER_NO_KITTY=1 run "$CFG/shims/it2" session list
  [ "$status" -ne 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^CLI ')" -eq 0 ]
}

@test "a re-run is a no-op, and CC_SHIM_ENTRIES=0 rolls back to real copies without writing through the link" {
  install_run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local shim_bin; shim_bin="$(readlink "$CFG/libexec/cc-shim")"
  cp "$shim_bin" "$BATS_TEST_TMPDIR/shim-before"
  install_run
  [ "$status" -eq 0 ]
  [ "$CFG/bin/it2" -ef "$CFG/libexec/cc-shim" ]

  CC_SHIM_ENTRIES=0 install_run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$CFG/bin/it2" ]
  [ ! -L "$CFG/bin/it2" ]
  cmp -s "$REPO/bin/it2-wrapper" "$CFG/bin/it2"
  [ "$(readlink "$CFG/bin/shellcheck")" = "$FX/bin/cc-qos-exec" ]
  [ ! -e "$CFG/.bin-real/it2" ]
  [ ! -L "$CFG/.bin-real/shellcheck" ]
  # The hazard: a cp onto the shim link would have overwritten the shared cc-shim binary.
  cmp -s "$shim_bin" "$BATS_TEST_TMPDIR/shim-before"

  # And forward again from the old layout: the identical real copy is replaced, not backed up.
  install_run
  [ "$status" -eq 0 ]
  [ "$CFG/bin/it2" -ef "$CFG/libexec/cc-shim" ]
  [ ! -e "$CFG/bin/it2.pre-link.bak" ]
}

@test "CC_SHIM_INSTALL=0 keeps today's layout exactly" {
  CC_SHIM_INSTALL=0 install_run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$CFG/libexec/cc-shim" ]
  [ -f "$CFG/bin/it2" ]
  [ ! -L "$CFG/bin/it2" ]
  [ "$(readlink "$CFG/bin/shellcheck")" = "$FX/bin/cc-qos-exec" ]
  [ ! -e "$CFG/.bin-real" ]
  [ ! -e "$CFG/.shims-real" ]
}
