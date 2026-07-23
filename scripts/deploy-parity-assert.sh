#!/bin/bash
# deploy-parity-assert.sh — assert the ~/bin tools actually RUNNING match this checkout.
#
# Why: ~/bin/ is the one deployed surface install.sh populates by COPY (hooks, commands,
# scripts and ~/.claude/bin/cc-* are all symlinked, so they cannot drift). A copy silently
# rots the moment the repo advances without a re-install, and nothing detected it:
#   - 2026-07-17→19 bin/claude-accounts gained the last-good quota ledger in the repo while
#     ~/bin stayed two days behind. Every consumer (cc-board, cc-context --quota, cc-route,
#     handoff-fire, lr-*) ran the OLD code, so handoff-fire read a `stale_quota` field the
#     deployed binary never emitted and silently reported "weekly n/a" forever.
#   - sync.sh copies ~/bin BACK into the repo with no direction guard, so one ./sync.sh in
#     that state would have clobbered the newer repo file with the stale copy.
# claude-accounts is therefore SYMLINKED (install.sh) and asserted STRICTLY here; the
# remaining ~/bin tools are self-updating launchers that may legitimately diverge, so they
# are asserted by CONTENT only and a difference is reported as drift, never as a hard error.
#
# READ-ONLY: compares and reports. It never installs, copies, or repairs anything.
# Exit 0 = parity · 1 = drift (actionable: re-run ./install.sh) · 3 = missing prerequisite.
# Covered by tests/deploy-parity.bats, whose fixtures drive it via CC_PARITY_REPO /
# CC_PARITY_BINDIR / CC_PARITY_STRICT / CC_PARITY_COPY (fully hermetic — no host deps).
set -uo pipefail

if [ -n "${CC_PARITY_REPO:-}" ]; then
  REPO="$CC_PARITY_REPO"
else
  # A linked worktree must assert the CANONICAL checkout (the live symlink source),
  # not itself: live ~/bin links target the shared checkout, so a self-rooted
  # comparison from a worktree reads every correct link as drift (gate red on
  # every worktree land). --git-common-dir is ".git" in the main checkout and an
  # absolute main-.git path in a linked worktree; outside git, fall back to self.
  _self_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  _common="$(git -C "$_self_root" rev-parse --git-common-dir 2>/dev/null || true)"
  case "$_common" in
    "")  REPO="$_self_root" ;;
    /*)  REPO="$(cd "$_common/.." && pwd)" ;;
    *)   REPO="$(cd "$_self_root/$_common/.." && pwd)" ;;
  esac
fi
BINDIR="${CC_PARITY_BINDIR:-$HOME/bin}"

# Tools that MUST be symlinks into the repo (drift is structurally impossible once linked).
STRICT_TOOLS="${CC_PARITY_STRICT:-claude-accounts}"
# Tools deployed as copies — compared by content; a difference is drift, not an error.
COPY_TOOLS="${CC_PARITY_COPY:-claude-latest claude-update claude-versions browsermcp-wrapper.sh claude-kimi}"

drift=0
report() { printf '  %-9s %-22s %s\n' "$1" "$2" "$3"; }

for tool in $STRICT_TOOLS; do
  src="$REPO/bin/$tool"; dest="$BINDIR/$tool"
  if [ ! -f "$src" ]; then
    report "SKIP" "$tool" "not in this checkout"
    continue
  fi
  if [ ! -e "$dest" ]; then
    report "MISSING" "$tool" "not deployed → run ./install.sh"
    drift=1
  elif [ -L "$dest" ] && [ "$(cd "$(dirname "$(readlink "$dest")")" && pwd)/$(basename "$(readlink "$dest")")" = "$src" ]; then
    report "LINKED" "$tool" "→ repo (cannot drift)"
  elif diff -q "$src" "$dest" >/dev/null 2>&1; then
    # Content matches today, but it is a COPY where a symlink is required: it will drift
    # again on the next repo edit. Actionable now, before the divergence appears.
    report "UNLINKED" "$tool" "copy matches but must be a symlink → run ./install.sh"
    drift=1
  else
    report "STALE" "$tool" "copy DIFFERS from repo — repo edits are NOT live → run ./install.sh"
    drift=1
  fi
done

for tool in $COPY_TOOLS; do
  src="$REPO/bin/$tool"; dest="$BINDIR/$tool"
  [ -f "$src" ] || continue
  if [ ! -e "$dest" ]; then
    report "MISSING" "$tool" "not deployed → run ./install.sh"
    drift=1
  elif diff -q "$src" "$dest" >/dev/null 2>&1; then
    report "OK" "$tool" "copy identical to repo"
  else
    report "STALE" "$tool" "copy differs from repo → run ./install.sh"
    drift=1
  fi
done

# The binary actually resolved from PATH is the one every consumer runs — a matching
# ~/bin file is worthless if an earlier PATH entry shadows it.
for tool in $STRICT_TOOLS; do
  [ -f "$REPO/bin/$tool" ] || continue
  onpath="$(command -v "$tool" 2>/dev/null || true)"
  if [ -z "$onpath" ]; then
    report "NOPATH" "$tool" "not on PATH — add $BINDIR to PATH"
    drift=1
  elif ! diff -q "$REPO/bin/$tool" "$onpath" >/dev/null 2>&1; then
    report "SHADOWED" "$tool" "PATH resolves to $onpath, which differs from the repo"
    drift=1
  fi
done

if [ "$drift" -ne 0 ]; then
  printf '\ndeploy-parity-assert: DRIFT — the code running is not the code in this checkout.\n' >&2
  exit 1
fi
exit 0
