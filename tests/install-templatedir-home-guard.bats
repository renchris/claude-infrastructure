#!/usr/bin/env bats
# install-templatedir-home-guard.bats — install.sh must never persist a path derived from an
# EPHEMERAL HOME into the operator's global git config (backlog 61d8605a25fc).
#
# THE DEFECT (measured 2026-08-11). install.sh ran, unconditionally:
#
#     git config --global init.templateDir "$HOME/.git-template"
#
# The VALUE is $HOME-derived; the WRITE is `--global`; the two are not bound to the same HOME. Under
# an isolated gate HOME the value became /var/folders/.../T/gate-home.qhMxtm/.git-template, while
# the destination can still be the operator's real global config — git resolves `--global` through
# GIT_CONFIG_GLOBAL / XDG_CONFIG_HOME before it ever consults $HOME/.gitconfig, and a harness that
# overrides HOME need not override those. The temp dir was then deleted; every later `git init` on
# the box warned "templates not found" and created NO hooks/ dir, which redded tests/ship-land.bats
# 14/15/33 for every session on the box — three tests away from the cause, reading as a test bug.
#
# RED-PROOF (measured while authoring, not asserted): against the real pre-fix artifact — `git show
# <pre-fix>:install.sh` dropped into a scratch tree beside this file and the new lib — this suite
# reads `not ok` on tests 6, 7 and 10 and `ok` on the rest. Pre-fix install.sh writes the fixture's
# temp path straight into the probe config, so both skip tests and the missing-lib test fail there.
# Tests 1-5 pin the predicate (a file that did not exist pre-fix) and 8/9 are the positive arms —
# all five must pass on BOTH sides, which is what attributes 6/7/10 to the guard itself.
#
# ANTI-VACUITY, per site. A guard that ALWAYS skips would silently retire a load-bearing setting,
# so each site carries its own positive arm:
#   * the predicate  — "the passwd home IS ours" (test 2) reds a `return 1` mutant;
#   * install.sh     — "predicate says ours ⇒ install.sh DOES write" (test 7) reds an `if false`
#                      mutant at the call site, using a known-answer double for the predicate;
#   * the instrument — the pre-fix line replayed under this fixture DOES land in the probe config
#                      (test 8), so "nothing was written" cannot pass because nothing could be.
#
# Hermeticity: fixture $HOME in setup(); every install runs --config-dir into a throwaway dir; the
# global git config is redirected to a probe file, so no arm of this suite can reach ~/.gitconfig
# even if the subject is broken. `launchctl`/`defaults` are PATH-stubbed, as in the neighbouring
# install-*.bats, because install.sh reaches real machine state through both.
#
# THE FIXTURE IS ITSELF UNDER TEST, as of 2026-09-11 (backlog e7bdbf4f8343, tests 11-12 — APPENDED,
# so the positions cited above stay true). 367e42f2 renamed the repo-side global-instructions SSOT
# CLAUDE.md → CLAUDE.global.md; install.sh followed and this fixture did not, so `cp` stat-failed
# under `set -e` and tests 6/7/8/10 went red on `[ "$status" -eq 0 ]` — four reds, none of them
# about the guard, none naming the file. That is the same "three tests away from the cause, reading
# as a test bug" shape recorded at the top of this header, turned on the suite that recorded it.
# Test 11 pins the fixture's NAMES against the repo, test 12 pins the SET's sufficiency, and
# install_fixture puts install.sh's own error on stderr so the red says why.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never the operator's live ~
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/real-home.sh"

  # The observation point AND a second belt: `--global` can only reach this file.
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/probe-gitconfig"

  # Minimal but REAL fixture checkout. install.sh reads exactly TWO repo-root files with no
  # existence guard in front of them — every other `$REPO_DIR/<file>` read sits behind an
  # `[[ -f ]]`/`[[ -d ]]` — so under `set -e` an absent one aborts the whole install. Those two are
  # FIXTURE_UNCONDITIONAL below, which test 11 pins against the repo; agents/ gives the link legs
  # something to link.
  #
  # 🚨 THE GLOBAL-INSTRUCTIONS FILE IS `CLAUDE.global.md`, NOT `CLAUDE.md` (367e42f2). The repo root
  # deliberately carries NO `CLAUDE.md` — Claude Code would load one as PROJECT memory on top of the
  # byte-identical user-memory copy — so a fixture doubling that name doubles a file the repo is
  # pinned not to have, and install.sh's `cp "$REPO_DIR/CLAUDE.global.md"` then dies on a stat.
  FIXTURE_UNCONDITIONAL=(CLAUDE.global.md statusline.sh)
  FIX="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FIX/agents" "$FIX/scripts/lib"
  cp "$REPO/install.sh" "$FIX/install.sh"
  cp "$LIB" "$FIX/scripts/lib/real-home.sh"
  printf '# fixture global instructions\n' > "$FIX/CLAUDE.global.md"
  printf '#!/bin/bash\necho fixture-statusline\n' > "$FIX/statusline.sh"
  printf 'fixture agent\n' > "$FIX/agents/fixture-agent.md"

  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  printf '#!/bin/sh\nexit 0\n' > "$STUB/launchctl"
  printf '#!/bin/sh\nexit 0\n' > "$STUB/defaults"
  chmod +x "$STUB/launchctl" "$STUB/defaults"
  export PATH="$STUB:$PATH"
}

has()   { printf '%s' "$output" | grep -qF -- "$1"; }
lacks() { if printf '%s' "$output" | grep -qF -- "$1"; then return 1; fi; return 0; }

# No "$@" passthrough: every call site below passes nothing, and an unused forward reads as a
# dropped argument at each bare `install_fixture` call (SC2119/SC2120).
# NB: no line of this comment may BEGIN with the linter's name — a comment opening that way is
# parsed as a malformed directive and aborts the whole file, which the lint's own selftest catches.
install_fixture() {
  run bash "$FIX/install.sh" --config-dir "$BATS_TEST_TMPDIR/cfg"
  # A stale fixture reds EVERY install.sh arm below on the same `[ "$status" -eq 0 ]` line with the
  # cause nowhere in sight — the "three tests away from the cause, reading as a test bug" shape this
  # suite was written about, and the shape it fell into itself when the global-instructions file was
  # renamed. Put install.sh's own words on stderr so the red names its reason. Diagnostic only: the
  # verdict stays with each caller's own assertion, so this never decides a test.
  [ "$status" -eq 0 ] || printf 'install.sh exited %s under the fixture:\n%s\n' "$status" "$output" >&2
}
probe_templatedir() { git config --global --get init.templateDir 2>/dev/null || true; }

# ---- the predicate (scripts/lib/real-home.sh) -------------------------------------------------

@test "a temp HOME is NOT the passwd home, and the reason names both" {
  run bash -c ". '$LIB'; HOME=/tmp/definitely-not-my-home; cc_home_is_passwd_home; \
                 rc=\$?; printf '%s' \"\$CC_HOME_NOT_OURS_WHY\"; exit \$rc"
  [ "$status" -eq 1 ]
  has "/tmp/definitely-not-my-home"
  has "$(bash -c ". '$LIB'; cc_passwd_home")"
}

@test "POSITIVE ARM: the passwd home IS the passwd home (an always-skip guard reds here)" {
  # Without this, the whole guard could be `return 1` — init.templateDir would never be set on any
  # machine and every clone would land unguarded, which is the failure the setting exists to stop.
  run bash -c ". '$LIB'; HOME=\"\$(cc_passwd_home)\"; cc_home_is_passwd_home"
  [ "$status" -eq 0 ]
}

@test "the user comes from id -un, not \$USER (a rewritten \$USER cannot flip the verdict)" {
  # A harness that overrode HOME can have overridden USER too. Reading \$USER would resolve
  # ~nobody (/var/empty), mismatch the real home, and turn a legitimate install into a skip.
  run bash -c ". '$LIB'; export USER=nobody; HOME=\"\$(cc_passwd_home)\"; cc_home_is_passwd_home"
  [ "$status" -eq 0 ]
}

@test "an UNRESOLVABLE passwd home fails OPEN on an ordinary path" {
  # A fresh machine / a container whose uid is in no passwd db must still be installable.
  idstub="$BATS_TEST_TMPDIR/idstub"; mkdir -p "$idstub"
  printf '#!/bin/sh\nexit 1\n' > "$idstub/id"; chmod +x "$idstub/id"
  run env PATH="$idstub:$PATH" bash -c ". '$LIB'; [ -z \"\$(cc_passwd_home)\" ] || exit 3; \
                                          HOME=/opt/somewhere; cc_home_is_passwd_home"
  [ "$status" -eq 0 ]
}

@test "an UNRESOLVABLE passwd home still refuses a HOME under a temp root" {
  # The fallback's fallback: with no authoritative answer available, an obviously ephemeral HOME
  # is still refused. This is the ONLY name-match in the design, and it is never the discriminator.
  idstub="$BATS_TEST_TMPDIR/idstub"; mkdir -p "$idstub"
  printf '#!/bin/sh\nexit 1\n' > "$idstub/id"; chmod +x "$idstub/id"
  run env PATH="$idstub:$PATH" bash -c ". '$LIB'; HOME='$BATS_TEST_TMPDIR/home'; \
                                          cc_home_is_passwd_home; rc=\$?; \
                                          printf '%s' \"\$CC_HOME_NOT_OURS_WHY\"; exit \$rc"
  [ "$status" -eq 1 ]
  has "could not be resolved"
}

# ---- install.sh at the call site ---------------------------------------------------------------

@test "install.sh under a fixture HOME SKIPS the git config write entirely" {
  install_fixture
  [ "$status" -eq 0 ]
  [ -z "$(probe_templatedir)" ]
  [ ! -e "$GIT_CONFIG_GLOBAL" ]
}

@test "the skip is not silent — one stderr line naming the reason, and the install still succeeds" {
  install_fixture
  [ "$status" -eq 0 ]
  has "init.templateDir NOT set"
  has "$HOME"
  # The install must not be failed by it: every gate/bats caller legitimately runs an isolated HOME.
  [ -e "$BATS_TEST_TMPDIR/cfg/agents/fixture-agent.md" ]
}

@test "POSITIVE ARM: when the predicate says the HOME is ours, install.sh DOES write it" {
  # Known-answer double for the predicate (which tests 1-5 cover on its own), so this arm attributes
  # coverage to install.sh's CALL SITE: an `if false` there reds here and nowhere else.
  printf 'cc_home_is_passwd_home() { CC_HOME_NOT_OURS_WHY=""; return 0; }\n' \
    > "$FIX/scripts/lib/real-home.sh"
  install_fixture
  [ "$status" -eq 0 ]
  has "git config --global init.templateDir"
  [ "$(probe_templatedir)" = "$HOME/.git-template" ]
}

@test "INSTRUMENT CONTROL: the pre-fix line DOES land the temp path in this probe config" {
  # Proves the two skip tests above are not vacuous: the channel they assert is empty is a channel
  # a write reaches. This is the pre-fix install.sh statement, verbatim.
  run git config --global init.templateDir "$HOME/.git-template"
  [ "$status" -eq 0 ]
  [ "$(probe_templatedir)" = "$HOME/.git-template" ]
}

@test "a MISSING real-home.sh skips the write rather than writing a path it cannot vouch for" {
  rm "$FIX/scripts/lib/real-home.sh"
  install_fixture
  [ "$status" -eq 0 ]
  has "real-home.sh is missing"
  [ -z "$(probe_templatedir)" ]
}

# ---- the fixture itself ------------------------------------------------------------------------
# Appended, not inserted: tests 1-10 keep the numbering the RED-PROOF block at the top of this file
# cites by position.

@test "FIXTURE CONTRACT: each repo-root file the fixture doubles still exists in the repo" {
  # WHY (measured 2026-09-11, backlog e7bdbf4f8343). 367e42f2 renamed the repo-side global-instructions
  # SSOT CLAUDE.md → CLAUDE.global.md. install.sh followed; this fixture did not, so `cp
  # "$REPO_DIR/CLAUDE.global.md"` stat-failed under `set -e` and tests 6/7/8/10 all went red on
  # `[ "$status" -eq 0 ]` — four reds, none of them about the guard under test, none naming the file.
  #
  # A fixture double is a claim that the repo has a file by that name. This test asserts the claim
  # directly, so the NEXT rename reds here, by name, one test instead of four. It cannot catch an
  # unconditional input install.sh ADDS (nothing here enumerates install.sh's reads) — that case is
  # covered by install_fixture surfacing install.sh's own stat error.
  local f missing=0
  # ${a[@]+…}: bash 3.2 treats an empty array as UNBOUND under `set -u` (the idiom cc-common.sh
  # uses for the same reason). This box's bash32-parse-lint is a NON-VERDICT — no bash 3.2 here —
  # so the construct is made safe by shape rather than certified by the lint.
  for f in ${FIXTURE_UNCONDITIONAL[@]+"${FIXTURE_UNCONDITIONAL[@]}"}; do
    if [ ! -e "$REPO/$f" ]; then
      echo "fixture doubles '$f', but the repo has no such file — install.sh's unconditional" >&2
      echo "repo-root inputs were renamed and this fixture was not updated with them." >&2
      missing=1
    fi
    if [ ! -e "$FIX/$f" ]; then
      echo "setup() did not create '$f' in the fixture checkout" >&2
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || return 1
}

@test "FIXTURE CONTROL: the fixture is sufficient — install.sh completes under it" {
  # The positive arm for the test above: it proves the NAMES are right, this proves the SET is
  # complete. An unconditional read added to install.sh with no fixture double reds here with
  # install.sh's own error on stderr (see install_fixture), not three tests away.
  install_fixture
  [ "$status" -eq 0 ] || return 1
}
