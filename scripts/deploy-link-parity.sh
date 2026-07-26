#!/bin/bash
# deploy-link-parity.sh — report checkout files that have NO live per-file symlink.
#
# Why: ~/.claude/{hooks,commands,scripts,bin,skills} are REAL directories of PER-FILE symlinks
# into the checkout. A fast-forward therefore updates every file that ALREADY has a link — and
# deploys nothing at all for a file the checkout gained. The new file is landed, current, and
# completely inert, with no signal anywhere:
#   - 2026-07-20 scripts/desk-arm-live.sh was in the checkout and in the ff, but
#     ~/.claude/scripts/desk-arm-live.sh did not exist. The desk-recycle-invariant's own
#     fix-command and the operator's command both died on "No such file or directory".
#   - 2026-07-21 the autofiring lr-reset-poller nearly shipped fail-closed for the same reason.
# `git rev-list HEAD..origin/main` reads 0 in both cases: landed ≠ deployed.
#
# REPORT-ONLY, BY DESIGN — it never creates, removes or repairs a link. A blanket "link every
# unlinked file" would be WRONG: a settings-wired hook is deliberately left unlinked until its
# staged activation script runs (that script does the symlink AND the settings.json wiring as one
# C10 operator step). Auto-linking would strip the only visible signal that the wiring is pending.
# Such files are classified PENDING and are NOT failures; everything else unlinked is.
#
# SCOPE: the per-file SYMLINK surfaces install.sh deploys. The COPY surfaces (~/bin launchers,
# statusline.sh, CLAUDE.md, rules/, launchd/) drift by CONTENT, not by topology, and belong to
# scripts/deploy-parity-assert.sh. The two scripts partition the deployed surface; neither
# duplicates the other.
#
# Usage:  deploy-link-parity.sh [--all] [--quiet]
#   --all     also list files that ARE correctly linked (default: only findings)
#   --quiet   print nothing when there is nothing actionable (for hooks/cron callers)
# Exit 0 = nothing actionable (PENDING-only still counts as clean) · 1 = actionable gap
#        · 3 = missing prerequisite.
#
# Covered by tests/deploy-link-parity.bats, whose fixtures drive it via CC_LINKPARITY_REPO /
# CC_LINKPARITY_CONFIG / CC_LINKPARITY_BINDIR / CC_LINKPARITY_PENDING (fully hermetic — no case
# reads the real ~/.claude or the real checkout).
set -uo pipefail

ALL=false
QUIET=false
while [ $# -gt 0 ]; do
  case "$1" in
    --all)   ALL=true; shift ;;
    --quiet) QUIET=true; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# Resolve a path through every symlink hop, then absolutise it. macOS ships bash 3.2 and a
# readlink with no -f, so this is hand-rolled. Load-bearing for BASH_SOURCE below: this script is
# itself deployed AS a symlink (~/.claude/scripts/deploy-link-parity.sh), so an unresolved
# BASH_SOURCE would put the repo root at ~/.claude — not a checkout — and every leg would compare
# against nothing and exit 0 vacuously.
_resolve() {
  local p="$1" t d n=0
  while [ -L "$p" ] && [ "$n" -lt 40 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$((n + 1))
  done
  d="$(cd "$(dirname "$p")" 2>/dev/null && pwd)" || { printf '%s\n' "$p"; return 0; }
  printf '%s/%s\n' "$d" "$(basename "$p")"
}

if [ -n "${CC_LINKPARITY_REPO:-}" ]; then
  REPO="$CC_LINKPARITY_REPO"
else
  # A linked worktree must compare the CANONICAL checkout (the live symlink source), never
  # itself — live links target the shared checkout, so a self-rooted comparison from a worktree
  # reads every correct link as a finding. --git-common-dir is ".git" in the main checkout and an
  # absolute main-.git path in a linked worktree; outside git, fall back to self.
  _self="$(_resolve "${BASH_SOURCE[0]}")"
  _self_root="$(cd "$(dirname "$_self")/.." && pwd)"
  _common="$(git -C "$_self_root" rev-parse --git-common-dir 2>/dev/null || true)"
  case "$_common" in
    "")  REPO="$_self_root" ;;
    /*)  REPO="$(cd "$_common/.." && pwd)" ;;
    *)   REPO="$(cd "$_self_root/$_common/.." && pwd)" ;;
  esac
fi
CFG="${CC_LINKPARITY_CONFIG:-$HOME/.claude}"
BINDIR="${CC_LINKPARITY_BINDIR:-$HOME/bin}"
# Activation scripts are staged in the repo AND mirrored live (the live dir is where the operator's
# .done markers land). Both are scanned: some staged scripts exist in only one of the two.
PENDING_DIRS="${CC_LINKPARITY_PENDING:-$REPO/docs/activation/pending-activation:$CFG/autonomy/pending-activation}"

[ -d "$REPO" ]  || { echo "deploy-link-parity: no checkout at $REPO" >&2; exit 3; }
[ -d "$CFG" ]   || { echo "deploy-link-parity: no config dir at $CFG" >&2; exit 3; }

findings=0
pending_n=0
linked_n=0
LINES=""
FIXES=""

note() { LINES="${LINES}$(printf '  %-9s %-44s %s' "$1" "$2" "$3")"$'\n'; }
fix()  { FIXES="${FIXES}  ▶ $1"$'\n'; }

# A file is PENDING — deliberately unlinked — when a staged activation script that has NOT been
# marked .done names it. Matched on the REPO-RELATIVE PATH, never the bare basename: an activation
# script must spell the path to build "$REPO/<path>", and loose basename matching would launder a
# genuinely-inert file into a false all-clear (the silent failure direction).
pending_owner() {
  local rel="$1" dir f base rest="$PENDING_DIRS"
  while [ -n "$rest" ]; do
    dir="${rest%%:*}"
    if [ "$rest" = "$dir" ]; then rest=""; else rest="${rest#*:}"; fi
    [ -d "$dir" ] || continue
    for f in "$dir"/*.sh; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"
      # Done-marked activations no longer excuse an unlinked file: the operator ran the script,
      # so a still-missing link is a real failure, not a pending step.
      [ -e "$f.done" ] && continue
      [ -e "$CFG/autonomy/pending-activation/$base.done" ] && continue
      if grep -qF -- "$rel" "$f" 2>/dev/null; then printf '%s\n' "$base"; return 0; fi
    done
  done
  return 0
}

check_one() {  # $1 = repo-relative path · $2 = absolute live destination
  local rel="$1" dest="$2" src tgt act
  src="$REPO/$rel"
  [ -f "$src" ] || return 0
  if [ -L "$dest" ]; then
    tgt="$(_resolve "$dest")"
    if [ "$tgt" = "$src" ]; then
      linked_n=$((linked_n + 1))
      $ALL && note "LINKED" "$rel" "→ live"
      return 0
    fi
    if [ ! -e "$dest" ]; then
      note "DANGLING" "$rel" "live link → $tgt, which does not exist"
    else
      note "MISLINKED" "$rel" "live link → $tgt (not this checkout)"
    fi
    fix "ln -sfn \"$src\" \"$dest\""
    findings=$((findings + 1))
    return 0
  fi
  if [ -e "$dest" ]; then
    note "SHADOW" "$rel" "live path is a REAL file, not a link — repo edits are NOT live"
    fix "ln -sfn \"$src\" \"$dest\"    # replaces a real file — inspect it first"
    findings=$((findings + 1))
    return 0
  fi
  act="$(pending_owner "$rel")"
  if [ -n "$act" ]; then
    note "PENDING" "$rel" "unlinked BY DESIGN — staged: $act"
    pending_n=$((pending_n + 1))
    return 0
  fi
  note "UNLINKED" "$rel" "landed in the checkout but NOT live — silently inert"
  fix "ln -sfn \"$src\" \"$dest\""
  findings=$((findings + 1))
}

# The mirror case: a live link whose checkout target was renamed or deleted. Unreachable by
# iterating repo files (the file is gone), and just as inert — a rename lands BOTH halves.
sweep_orphans() {
  local d="$1" l tgt
  [ -d "$d" ] || return 0
  for l in "$d"/*; do
    [ -L "$l" ] || continue
    [ -e "$l" ] && continue
    tgt="$(readlink "$l")"
    case "$tgt" in "$REPO"/*) ;; *) continue ;; esac
    note "ORPHAN" "${l#"$CFG"/}" "→ $tgt (gone from the checkout)"
    fix "rm \"$l\""
    findings=$((findings + 1))
  done
}

# --- the per-file symlink surfaces install.sh deploys (install.sh is the map of record) --------
for f in "$REPO"/hooks/*.sh;      do check_one "hooks/$(basename "$f")"     "$CFG/hooks/$(basename "$f")"; done
for f in "$REPO"/hooks/lib/*.sh;  do check_one "hooks/lib/$(basename "$f")" "$CFG/hooks/lib/$(basename "$f")"; done
for f in "$REPO"/commands/*.md;   do check_one "commands/$(basename "$f")"  "$CFG/commands/$(basename "$f")"; done
for f in "$REPO"/scripts/*.sh;    do check_one "scripts/$(basename "$f")"   "$CFG/scripts/$(basename "$f")"; done
for f in "$REPO"/scripts/limit-recover/*; do
  check_one "scripts/limit-recover/$(basename "$f")" "$CFG/scripts/limit-recover/$(basename "$f")"
done
for f in "$REPO"/bin/cc-*;        do check_one "bin/$(basename "$f")"       "$CFG/bin/$(basename "$f")"; done
for d in "$REPO"/skills/*/; do
  [ -d "$d" ] || continue
  n="$(basename "$d")"
  for f in "$d"*; do check_one "skills/$n/$(basename "$f")" "$CFG/skills/$n/$(basename "$f")"; done
done
# Single-file links install.sh makes by name rather than by glob.
check_one "accounts.json"       "$CFG/accounts.json"
check_one "bin/claude-accounts" "$BINDIR/claude-accounts"

for d in hooks hooks/lib commands scripts scripts/limit-recover bin; do sweep_orphans "$CFG/$d"; done
for d in "$CFG"/skills/*/; do [ -d "$d" ] && sweep_orphans "$d"; done

# --- report -------------------------------------------------------------------------------------
if [ "$findings" -eq 0 ] && $QUIET; then exit 0; fi

printf 'link parity: %s → %s\n' "$REPO" "$CFG"
[ -n "$LINES" ] && printf '%s' "$LINES"
printf '  %d linked · %d staged-pending · %d actionable\n' "$linked_n" "$pending_n" "$findings"

if [ "$findings" -gt 0 ]; then
  printf '\n  ✗ landed but NOT live — the checkout is current and this code still does not run.\n'
  printf '  Fix (review each — a link is never created blindly):\n%s' "$FIXES"
  printf '  Or deploy every surface at once:  ▶ %s/install.sh\n' "$REPO"
  exit 1
fi
if [ "$pending_n" -gt 0 ]; then
  printf '  ✓ every landed file is live (%d awaiting its staged activation script — not a gap).\n' "$pending_n"
else
  printf '  ✓ every landed file is live.\n'
fi
exit 0
