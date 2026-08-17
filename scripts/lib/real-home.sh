#!/bin/bash
# real-home.sh — one predicate: is $HOME the home the OS records for the user running me?
#
# WHY THIS EXISTS (measured 2026-08-11, backlog 61d8605a25fc). install.sh persisted a $HOME-DERIVED
# ABSOLUTE PATH into the operator's REAL global git config:
#
#     git config --global init.templateDir "$HOME/.git-template"
#
# The VALUE is $HOME-derived and the WRITE is `--global`, and those two are not bound to the same
# HOME. Under an isolated/ephemeral gate HOME, $HOME is a temp dir, so the value became
# /var/folders/.../T/gate-home.qhMxtm/.git-template — while the write destination can still be the
# operator's real global config, because git resolves `--global` through GIT_CONFIG_GLOBAL and
# XDG_CONFIG_HOME BEFORE it looks at $HOME/.gitconfig, and a harness that overrides HOME does not
# necessarily override those. The temp dir was then deleted. Every later `git init` on the box
# warned "templates not found" and created NO hooks/ directory, which redded tests/ship-land.bats
# 14/15/33 for every session on the box — three tests away from the cause, reading as a test bug.
#
# THE DISCRIMINATOR IS THE PASSWD DATABASE, NOT A PATH DENYLIST. "Is this HOME under /tmp or
# /var/folders" enumerates spellings of ephemerality and misses every other one (repo memory:
# denylist-enumerates-spellings-not-the-class). "Is this HOME the home the OS records for the user
# running me" is the actual question, and exactly one answer to it is the operator's real home.
#
# THE USERNAME COMES FROM `id -un`, NOT $USER. $USER is ordinary environment; a harness that
# rewrote HOME can have rewritten it too, and then the check would compare against a home we were
# handed rather than the one the kernel says we are running as.
#
# RESOLUTION LADDER, cheapest authoritative source first:
#   1. bash tilde expansion of ~<user> — getpwnam by definition, ignores $HOME entirely, and works
#      anywhere bash does. Verified on this box: with HOME=/tmp/fakehome it still yields
#      /Users/chrisren. This is the primary because it needs no external binary.
#   2. dscl (Darwin has no getent) / getent passwd (Linux) — the cross-check for a user that bash
#      cannot expand (absent from the local passwd file, directory-service-only accounts).
#
# FAIL DIRECTION. Provably-not-ours ⇒ 1 (callers skip the dangerous write). Resolvable and equal
# ⇒ 0. UNRESOLVABLE ⇒ 0, i.e. fail OPEN: a fresh machine or a container whose uid is not in any
# passwd db must still be installable, and on such a box there is no operator config to poison.
# That blind case is narrowed by one secondary read — unresolvable passwd home AND a HOME under a
# temp root is ephemeral enough to refuse. The name-match appears ONLY there, as the fallback's
# fallback, never as the discriminator.
#
# REJECTED: gating on GIT_CONFIG_GLOBAL alone ("write only when it is unset or points into the real
# home"). It guards the destination and leaves the VALUE unguarded, and it is blind to the
# XDG_CONFIG_HOME redirect that reaches the same real file. Refusing to derive anything at all from
# a HOME that is not ours closes both halves with one predicate.

# Print the passwd-database home for the running user, or nothing if it cannot be resolved.
cc_passwd_home() {
  local u h os
  u="$(id -un 2>/dev/null || true)"
  [[ -n "$u" ]] || return 0

  # Tilde expansion needs eval to see a variable username; ~"$u" is literal. $u is the kernel's
  # answer to `id -un`, not attacker-supplied input.
  h="$(eval "printf '%s' ~$u" 2>/dev/null || true)"

  if [[ "$h" != /* ]]; then
    os="$(uname -s 2>/dev/null || true)"
    if [[ "$os" == "Darwin" ]] && command -v dscl >/dev/null 2>&1; then
      h="$(dscl . -read "/Users/$u" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p')"
    elif command -v getent >/dev/null 2>&1; then
      h="$(getent passwd "$u" 2>/dev/null | cut -d: -f6)"
    fi
  fi

  [[ "$h" == /* ]] && printf '%s' "$h"
  return 0
}

# Physical form of a path. macOS hands out /var/folders/... homes that are really
# /private/var/folders/..., so a logical comparison would call one directory two directories.
cc_phys_path() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

# 0 = $HOME is (or cannot be shown not to be) the running user's real home.
# 1 = $HOME is provably not it; CC_HOME_NOT_OURS_WHY carries the one-line reason.
cc_home_is_passwd_home() {
  CC_HOME_NOT_OURS_WHY=""
  local real home_phys
  real="$(cc_passwd_home)"
  home_phys="$(cc_phys_path "$HOME")"

  if [[ -n "$real" ]]; then
    [[ "$home_phys" == "$(cc_phys_path "$real")" ]] && return 0
    CC_HOME_NOT_OURS_WHY="HOME=$HOME is not $(id -un 2>/dev/null || echo "$USER")'s home ($real)"
    return 1
  fi

  # Fallback's fallback — see FAIL DIRECTION above.
  case "$home_phys" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*)
      CC_HOME_NOT_OURS_WHY="HOME=$HOME is under a temp root and the passwd home could not be resolved"
      return 1 ;;
  esac
  if [[ -n "${TMPDIR:-}" && "$home_phys" == "$(cc_phys_path "${TMPDIR%/}")"/* ]]; then
    # shellcheck disable=SC2034  # read by the SOURCING script (install.sh), not in this file
    CC_HOME_NOT_OURS_WHY="HOME=$HOME is under \$TMPDIR and the passwd home could not be resolved"
    return 1
  fi
  return 0
}
