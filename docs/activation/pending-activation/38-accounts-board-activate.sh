#!/bin/bash
# 38-accounts-board-activate.sh — wire hooks/accounts-board.sh into all FIVE config dirs.
#
# WHAT THIS TURNS ON (DESK_ROUTER_AND_STARTUP_V1 W3.6-7). A SessionStart hook that prints the
# /accounts board — which account you are on, what is left in each window, and which account the
# next bare `claude` will pick — at ZERO model tokens and ~65ms. The board is pre-rendered by the
# com.claude.accounts-keepwarm launchd job; the hook only reads the file.
#
# WHY IT NEEDS YOU (this is C10, migrations/0011). settings.json is not one file with four
# symlinks to it — it is FIVE SEPARATE REAL FILES, five distinct inodes (measured 2026-08-11:
# 452849547 · 452849554 · 464207462 · 452849551 · 453104257). The knowledge-layer mirror's safe
# mode REFUSES to touch a forked real file, which is correct and is also why it will never
# propagate this: a hook wired into the repo template reaches exactly zero live sessions on its
# own. Each dir needs its own merge pass, and merging hook rosters into five live operator configs
# is not something a 600s unattended converger should do.
#
# .claude-next IS ACCOUNT 1, THE DEFAULT, and it is the divergent one: 74 hook commands against
# 79 in the other four, and a FORKED REAL hooks/ dir (53 files vs 75) rather than the symlink the
# other three carry. So it is the dir most likely to silently miss this, and the one whose miss
# costs the most — it is where a bare `claude` lands.
#
# Idempotent: install.sh --wire-hooks is a UNION merge (append-at-tail, backup .pre-wire.bak), so
# re-running it against an already-wired dir changes nothing.
set -uo pipefail

REPO="${CC_ACTIVATE_REPO:-$HOME/Development/claude-infrastructure}"
DIRS=(
  "${CC_ACTIVATE_CONFIG_ROOT:-$HOME}/.claude"
  "${CC_ACTIVATE_CONFIG_ROOT:-$HOME}/.claude-next"
  "${CC_ACTIVATE_CONFIG_ROOT:-$HOME}/.claude-secondary"
  "${CC_ACTIVATE_CONFIG_ROOT:-$HOME}/.claude-tertiary"
  "${CC_ACTIVATE_CONFIG_ROOT:-$HOME}/.claude-quaternary"
)
HOOK_SRC="$REPO/hooks/accounts-board.sh"
HOOK_LIVE="$HOME/.claude/hooks/accounts-board.sh"

die() { echo "38-accounts-board: $*" >&2; exit 1; }

[ -f "$HOOK_SRC" ] || die "missing $HOOK_SRC — the wiring commit did not land intact"

if [ "${CONFIRM:-0}" != "1" ]; then
  cat <<EOF
38-accounts-board-activate.sh — DRY (set CONFIRM=1 to apply)

  Hook source  : $HOOK_SRC
  Must be live : $HOOK_LIVE   $( [ -e "$HOOK_LIVE" ] && echo "(present)" || echo "(ABSENT — run scripts/deploy-live.sh first)" )

  Would run, per config dir:
$(for d in "${DIRS[@]}"; do
    printf '    %-42s %s\n' "$(basename "$d")" \
      "$(grep -q 'accounts-board.sh' "$d/settings.json" 2>/dev/null && echo 'already wired' || echo 'WOULD WIRE')"
  done)

  Then: $REPO/scripts/settings-drift-assert.sh

  Apply with:  CONFIRM=1 bash $0
EOF
  exit 0
fi

# THE HOOK FILE FIRST, and it is a HARD refusal rather than a warning. Every one of the five
# settings.json files invokes the literal path ~/.claude/hooks/accounts-board.sh (checked: 0 of
# 79 hook commands reference a per-account hooks dir), so ~/.claude/hooks is the single place the
# file has to exist — but it is a NEW file, i.e. an ADD, and an ADD has no symlink until
# deploy-live.sh runs. Wiring five configs to a path that does not exist would leave every session
# silently skipping a hook that reads as installed.
[ -e "$HOOK_LIVE" ] || die "$HOOK_LIVE does not exist yet. It is a NEW file, so the trunk
      fast-forward alone does not create its symlink. Run:  bash $REPO/scripts/deploy-live.sh
      then re-run this script."

rc=0
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || { echo "  ⊘ $(basename "$d") — no such config dir, skipped"; continue; }
  echo "  → $(basename "$d")"
  "$REPO/install.sh" --config-dir "$d" --wire-hooks >/dev/null 2>&1 \
    || { echo "  ✗ $(basename "$d") — install.sh --wire-hooks failed" >&2; rc=1; }
  if grep -q 'accounts-board.sh' "$d/settings.json" 2>/dev/null; then
    echo "  ✓ $(basename "$d") — accounts-board.sh wired"
  else
    echo "  ✗ $(basename "$d") — STILL NOT WIRED after the merge" >&2; rc=1
  fi
done

echo
if [ -x "$REPO/scripts/settings-drift-assert.sh" ]; then
  "$REPO/scripts/settings-drift-assert.sh" || { echo "  ⚠ settings-drift-assert reported drift" >&2; rc=1; }
fi

[ "$rc" -eq 0 ] && echo "38-accounts-board: all five config dirs wired." \
                || echo "38-accounts-board: FINISHED WITH ERRORS — see above." >&2
exit "$rc"
