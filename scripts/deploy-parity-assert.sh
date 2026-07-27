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
# SECOND LEG (2026-07-25) — EXISTENCE parity for ~/.claude. The "they are symlinked, so they
# cannot drift" assumption above is true only of files ALREADY linked, and silent about NEW
# ones: ~/.claude/{hooks,hooks/lib,commands,scripts,bin} are real dirs of PER-FILE symlinks, so
# a brand-new tracked file is never linked at all, however current the checkout. The operator's
# documented deploy step (ff-sync the shared checkout) cannot create the link — only
# ./install.sh can. That hole shipped live: hooks/lib/cc-interactive.sh landed and stayed
# unlinked, collapsing all three of bin/cc-classify's resolve candidates onto one missing path
# and silently disabling the operator-adoption hold — a reaper fail-OPEN that reclassified an
# operator-adopted pane as reapable. The leg below makes that FAIL LOUD and hands over the exact
# `ln -sf` per miss.
#
# READ-ONLY: compares and reports. It never installs, copies, or repairs anything.
# Exit 0 = parity · 1 = drift (actionable: re-run ./install.sh) · 3 = missing prerequisite.
# Covered by tests/deploy-parity.bats, whose fixtures drive it via CC_PARITY_REPO /
# CC_PARITY_BINDIR / CC_PARITY_STRICT / CC_PARITY_COPY / CC_PARITY_LIVE (fully hermetic — no
# host deps).
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

# ── EXISTENCE PARITY: every tracked runtime file has a RESOLVING live counterpart ───────────────
# The (subdir, glob) set below mirrors install.sh 1:1 — hooks/*.sh, hooks/lib/*.sh, commands/*.md,
# scripts/*.sh (top level only), scripts/limit-recover/* (all types), bin/cc-*. Anything install.sh
# does not link is deliberately NOT asserted, so this can never demand a link that install.sh would
# not create. Live path is always $LIVE/<same relative path> (install.sh preserves the subdir).
LIVE="${CC_PARITY_LIVE:-$HOME/.claude}"
missing=0
if [ -e "$REPO/.git" ]; then    # a tracked-file listing needs a real checkout; anything else skips
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    # NOTE: in a `case` pattern `*` also matches `/`, so each deeper-path exclusion must precede the
    # shallower pattern it would otherwise be swallowed by. Order here is load-bearing.
    case "$rel" in
      hooks/lib/*.sh)            want=1 ;;
      hooks/*/*)                 want=0 ;;   # no other hooks/ subdir is deployed
      hooks/*.sh)                want=1 ;;
      commands/*/*)              want=0 ;;
      commands/*.md)             want=1 ;;
      scripts/limit-recover/*/*) want=0 ;;
      scripts/limit-recover/*)   want=1 ;;
      scripts/*/*)               want=0 ;;   # scripts/ is globbed top-level only
      scripts/*.sh)              want=1 ;;
      bin/cc-*/*)                want=0 ;;
      bin/cc-*)                  want=1 ;;
      *)                         want=0 ;;
    esac
    [ "$want" = 1 ] || continue
    # -e follows symlinks on purpose: a link whose target is gone is as dead as no link at all.
    [ -e "$LIVE/$rel" ] && continue
    printf 'MISSING: ln -sf %s %s\n' "$REPO/$rel" "$LIVE/$rel"
    missing=$((missing + 1))
    drift=1
  done <<EOF
$(git -C "$REPO" ls-files -- hooks commands scripts bin 2>/dev/null)
EOF
fi
if [ "$missing" -ne 0 ]; then
  printf '\ndeploy-parity-assert: %s tracked runtime file(s) have NO live counterpart under %s.\n' "$missing" "$LIVE" >&2
  printf 'A bare ff-sync of the checkout can never create these links — run ./install.sh (or the ln -sf lines above).\n' >&2
fi

if [ "$drift" -ne 0 ]; then
  printf '\ndeploy-parity-assert: DRIFT — the code running is not the code in this checkout.\n' >&2
  exit 1
fi
exit 0
