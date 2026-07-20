#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 08-session-deregister  —  stop the cc-registry leak (82 stale rows → reaper ghost-"crashed" pages)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: two idempotent steps.
#   1  symlink hooks/session-deregister.sh into the live ~/.claude/hooks/ layer (per-file topology).
#   2  register it in ~/.claude/settings.json SessionEnd, so a clean close removes THAT pane's own
#      ~/.claude/cc-registry/<paneUUID>.json row.
#
# WHY: session-register.sh (SessionStart) has always written the row and session-deregister.sh was
#   written to remove it — but the pair was NEVER WIRED. Nothing ever invoked the deregister half, so
#   every clean SessionEnd and every `handoff-fire.sh self-close` leaked its row. 82 had piled up by
#   2026-07-20, and cc-reaper reads a row with no live process as a CRASHED session: a steady stream
#   of ghost pages about panes that exited cleanly hours earlier. The hook itself needed no change
#   (tests/session-registry.bats already proves it removes the right row and correctly skips
#   reason=clear); the defect was pure wiring. Item f9385874de10.
#
#   This stops NEW leaks. The rows already on disk are swept by `cc-reconcile`'s guarded prune
#   (same commit): pane confirmed gone (absent from `it2 session list` AND recorded pid dead) and
#   past the CC_REG_RETAIN_H forensic window. A LIVE pane's stale-pid row is HEALED, never pruned.
#
# WHY C10 (agent stages; operator runs): step 2 mutates the live settings.json and activates a hook.
#   The agent never self-activates hooks — that ceiling is the whole point of this queue.
#
# SAFETY: settings.json is backed up first (~/.claude/backups/session-deregister-<ts>/) and verified
#   with `jq -e` after; a failed verify ROLLS BACK automatically. Step 1 is an inert file placement.
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/08-session-deregister-activate.sh
# Mark done: touch ~/.claude/autonomy/pending-activation/08-session-deregister-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
CFG="$HOME/.claude"
TS="$(date +%Y%m%d-%H%M%S)"
BAK="$CFG/backups/session-deregister-$TS"
# Written VERBATIM into settings.json, whose hook commands all use the `~/…` form (Claude Code
# expands it) — an absolute path here would be inconsistent with every sibling entry.
# shellcheck disable=SC2088
HOOK_CMD='~/.claude/hooks/session-deregister.sh'

echo "== 08-session-deregister =="
echo "repo: $REPO"

# ---- preflight -------------------------------------------------------------------------------
if [ ! -f "$REPO/hooks/session-deregister.sh" ]; then
  echo "✗ missing in checkout: $REPO/hooks/session-deregister.sh" >&2
  echo "  is the checkout on a trunk that has this commit? (git -C $REPO pull --ff-only)" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "✗ jq required for step 2" >&2; exit 1; }

echo
echo "Will do:"
echo "  1  symlink hooks/session-deregister.sh → $CFG/hooks/"
echo "  2  add $HOOK_CMD to SessionEnd in $CFG/settings.json (timeout 5)"
echo "  backups → $BAK"
echo

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/08-session-deregister-activate.sh"
  exit 0
fi

mkdir -p "$BAK" || { echo "✗ cannot create backup dir $BAK" >&2; exit 1; }

# ---- 1: live symlink ---------------------------------------------------------------------------
echo "[1] live symlink"
SRC="$REPO/hooks/session-deregister.sh"
DEST="$CFG/hooks/session-deregister.sh"
mkdir -p "$(dirname "$DEST")"
if [ -L "$DEST" ] && [ "$(readlink "$DEST")" = "$SRC" ]; then
  echo "  = $DEST (already linked)"
else
  [ -e "$DEST" ] && cp -a "$DEST" "$BAK/session-deregister.sh" 2>/dev/null
  if ln -sfn "$SRC" "$DEST"; then echo "  → $DEST"; else echo "  ✗ failed: $DEST" >&2; exit 1; fi
fi

# ---- 2: SessionEnd hook ------------------------------------------------------------------------
echo "[2] settings.json SessionEnd"
S="$CFG/settings.json"
if [ ! -f "$S" ]; then
  echo "  ✗ $S not found — wire $HOOK_CMD into SessionEnd by hand." >&2; exit 1
fi
if jq -e --arg c "$HOOK_CMD" '.hooks.SessionEnd[]?.hooks[]?|select(.command==$c)' "$S" >/dev/null 2>&1; then
  echo "  = already wired"
else
  cp -a "$S" "$BAK/settings.json" || { echo "  ✗ backup failed — refusing to touch settings.json" >&2; exit 1; }
  tmp="$S.dereg-tmp.$$"
  if jq --arg c "$HOOK_CMD" \
       '.hooks.SessionEnd += [{"hooks":[{"type":"command","command":$c,"timeout":5}]}]' \
       "$S" > "$tmp" 2>/dev/null && jq -e . "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$S" && echo "  → wired (timeout 5s)"
  else
    rm -f "$tmp"
    echo "  ✗ jq edit failed — settings.json UNCHANGED (backup at $BAK/settings.json)" >&2
    exit 1
  fi
fi

# ---- verify -------------------------------------------------------------------------------------
echo
echo "== verify =="
if jq -e --arg c "$HOOK_CMD" '[.hooks.SessionEnd[]?.hooks[]?.command]|any(.==$c)' "$S" >/dev/null 2>&1; then
  echo "  ✓ SessionEnd carries $HOOK_CMD"
else
  echo "  ✗ NOT wired after edit — restore: cp -a $BAK/settings.json $S" >&2; exit 1
fi
echo "  registry rows currently on disk: $(find "$CFG/cc-registry" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
echo
echo "✓ deregistration ACTIVE for every session started from now on."
echo "  Sweep the rows that already leaked (safe, guarded, dry-run first):"
echo
echo "      $CFG/bin/cc-reconcile --dry-run"
echo "      $CFG/bin/cc-reconcile"
echo
echo "  Mark this activation done:"
echo "      touch $HOME/.claude/autonomy/pending-activation/08-session-deregister-activate.sh.done"
echo
echo "ROLLBACK: rm $DEST ; cp -a $BAK/settings.json $S"
