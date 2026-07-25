#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 09-postland-verify  —  load the ASYNC post-land full-suite net (every 5 min)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: two idempotent steps. (1) symlink scripts/postland-verify.sh into the live ~/.claude/scripts/
#   layer (per-file topology — the plist runs $HOME/.claude/scripts/postland-verify.sh). (2) load
#   com.claude.postland-verify (StartInterval 300, RunAtLoad=false, Nice 10).
# WHY: the pre-push gate is fast-and-partial and the FULL bats suite runs only at 04:00 — a red landed
#   at 09:00 sits unseen all day. Each tick asks "is origin/main's TREE already stamped green?"
#   (abstains in ~1s if so), else runs the suite in a DISPOSABLE detached worktree, bisects the culprit
#   on a reproducible red, and pages (autonomy/pages/ + cc-backlog + osascript).
# WHY C10 (agent stages; operator loads): loading a launchd job IS an activation. Kill switch after
#   load: POSTLAND_VERIFY=off, or bootout.  Mark done: touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
PLIST="com.claude.postland-verify.plist"
SRC="$REPO/scripts/postland-verify.sh"
DEST="$HOME/.claude/scripts/postland-verify.sh"

echo "== 09-postland-verify =="
[ -f "$SRC" ] || { echo "✗ missing in checkout: $SRC (is the checkout on a trunk with this commit?)" >&2; exit 1; }
echo "Will do: [0] $SRC --selftest (proves both verdict paths, side-effect-free)"
echo "         [1] symlink $SRC → $DEST"
echo "         [2] cp launchd/$PLIST ~/Library/LaunchAgents/ ; plutil -lint ; launchctl bootstrap gui/\$(id -u)"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/09-postland-verify-activate.sh"
  exit 0
fi

echo "[0] selftest"; bash "$SRC" --selftest || { echo "✗ selftest RED — NOT activating" >&2; exit 1; }
echo "[1] live symlink"; mkdir -p "$(dirname "$DEST")"
if [ -L "$DEST" ] && [ "$(readlink "$DEST")" = "$SRC" ]; then echo "  = $DEST (already linked)"
elif ln -sfn "$SRC" "$DEST"; then echo "  → $DEST"
else echo "  ✗ failed: $DEST" >&2; exit 1; fi

echo "[2] load the launchd job"
if cp "$REPO/launchd/$PLIST" "$HOME/Library/LaunchAgents/$PLIST" \
     && plutil -lint "$HOME/Library/LaunchAgents/$PLIST" \
     && launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$PLIST"; then
  echo "✓ postland-verify loaded (RunAtLoad=false → first tick within 5 min)."
else
  echo "✗ load failed — inspect above" >&2; exit 1
fi

echo "== verify =="
launchctl print "gui/$(id -u)/com.claude.postland-verify" 2>/dev/null | grep -E 'state|program' \
  || echo "  (not printable yet — re-check in a minute)"
echo "  status:    $DEST status"
echo "  mark done: touch $HOME/.claude/autonomy/pending-activation/09-postland-verify-activate.sh.done"
echo "ROLLBACK: launchctl bootout gui/\$(id -u)/com.claude.postland-verify ; rm ~/Library/LaunchAgents/$PLIST ; rm $DEST"
