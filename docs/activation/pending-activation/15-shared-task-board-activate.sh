#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 15-shared-task-board  —  make the Claude Code task board SHARED across all four accounts
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: five idempotent steps, in an order that is load-bearing.
#   [1] link lib/config-mirror.zsh into the live layer (it un-isolates tasks/ + tasks-index.json)
#   [2] link bin/cc-tlid + bin/cc-task-store into ~/bin
#   [3] MERGE board CONTENT from the three isolated account stores into ~/.claude/tasks
#   [4] CONVERT each account's tasks/ dir to a symlink (the mirror's --convert)
#   [5] point ~/.zshrc's _cc_tlid at bin/cc-tlid  ← the one hand-edit; C10
#
# WHY: Claude Code stores a board at $CLAUDE_CONFIG_DIR/tasks/<listId>/, and this fleet runs four
#   accounts as four config dirs, so the same board name resolved to four DIFFERENT directories. A
#   board is WORK state, not ACCOUNT state — the accounts are quota pools for one operator. Measured
#   before the change: claude-infrastructure-main existed as four divergent boards (15/0/3/23 tasks)
#   whose ids collided while carrying different work.
#
# WHY THE ORDER CANNOT BE CHANGED: step [4] is `mv -f <dir> <dir>.premirror-bak`. Run before [3] it
#   strands 245/251/186 boards. [3] is additive, idempotent and never modifies a source, so running
#   [3] again after [4] is harmless — but [4] before [3] is not recoverable without the backup.
#
# WHY C10 (agent stages; operator runs): step [5] edits ~/.zshrc and step [4] mutates live account
#   config dirs. Both are operator-owned by policy.
#
# SAFE UNDER LIVE SESSIONS? [1]-[3] yes, by construction. [4] should run with that account's panes
#   closed — a session holding an open board while its directory is moved will keep writing to the
#   moved-aside inode. The script REFUSES [4] for any account with a live session unless FORCE=1.
#
# Kill switch: git revert the lib/config-mirror.zsh commit and re-run install.sh; restore boards from
#   the backup this script prints.  Mark done: touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
MIRROR_SRC="$REPO/lib/config-mirror.zsh"
MIRROR_DEST="$HOME/.claude/lib/config-mirror.zsh"
ACCTS="$HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary"

echo "== 15-shared-task-board =="
[ -f "$MIRROR_SRC" ] || { echo "✗ missing in checkout: $MIRROR_SRC (is the checkout on a trunk with this commit?)" >&2; exit 1; }
[ -x "$REPO/bin/cc-task-store" ] || { echo "✗ missing: $REPO/bin/cc-task-store" >&2; exit 1; }

echo "Will do: [1] symlink $MIRROR_SRC → $MIRROR_DEST"
echo "         [2] symlink bin/cc-tlid + bin/cc-task-store → ~/bin/"
echo "         [3] cc-task-store merge   (content; additive, backs up first)"
echo "         [4] mirror --convert for: $ACCTS   (linkage; refuses on live sessions)"
echo "         [5] print the one-line ~/.zshrc edit for you to apply"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo ""
  echo "(dry run — showing what the merge WOULD do, then exiting)"
  "$REPO/bin/cc-task-store" plan || true
  echo ""
  echo "(re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/15-shared-task-board-activate.sh"
  exit 0
fi

# ── [1] mirror into the live layer ────────────────────────────────────────────────────────────────
echo "[1] mirror"
mkdir -p "$(dirname "$MIRROR_DEST")"
if [ -L "$MIRROR_DEST" ] && [ "$(readlink "$MIRROR_DEST")" = "$MIRROR_SRC" ]; then
  echo "  = already linked"
else
  # The live copy was a REAL file for months — keep it before replacing it with the link.
  [ -f "$MIRROR_DEST" ] && [ ! -L "$MIRROR_DEST" ] && cp "$MIRROR_DEST" "$MIRROR_DEST.prelink-bak" \
    && echo "  kept previous real file → $MIRROR_DEST.prelink-bak"
  ln -sfn "$MIRROR_SRC" "$MIRROR_DEST" && echo "  → $MIRROR_DEST"
fi

# ── [2] tools onto PATH ───────────────────────────────────────────────────────────────────────────
echo "[2] tools"
mkdir -p "$HOME/bin"
for t in cc-tlid cc-task-store; do
  ln -sfn "$REPO/bin/$t" "$HOME/bin/$t" && echo "  → ~/bin/$t"
done

# ── [3] merge CONTENT (must precede [4]) ──────────────────────────────────────────────────────────
echo "[3] merge board content"
"$REPO/bin/cc-task-store" merge --yes || { echo "✗ merge failed — NOT converting. Sources untouched." >&2; exit 1; }
"$REPO/bin/cc-task-store" verify   || { echo "✗ verify failed — NOT converting. Sources untouched." >&2; exit 1; }

# ── [4] convert LINKAGE ───────────────────────────────────────────────────────────────────────────
echo "[4] convert account stores to symlinks"
for cfg in $ACCTS; do
  [ -d "$cfg" ] || { echo "  - $cfg absent, skipping"; continue; }
  if [ -L "$cfg/tasks" ]; then echo "  = ${cfg##*/} already shared"; continue; fi
  # Liveness: any claude process whose CWD or argv names this config dir. Deliberately conservative
  # — a false "live" costs a re-run, a false "idle" costs a session writing into a moved-aside dir.
  live=$(pgrep -fl "CLAUDE_CONFIG_DIR=$cfg" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$live" -gt 0 ] && [ "${FORCE:-0}" != 1 ]; then
    echo "  ⚠ ${cfg##*/}: $live live session(s) — SKIPPED. Close its panes and re-run, or FORCE=1."
    continue
  fi
  zsh -fc "source '$MIRROR_DEST'; _cc_sync_config_mirror --convert '$cfg'" \
    && echo "  → ${cfg##*/}/tasks $( [ -L "$cfg/tasks" ] && echo 'is now a symlink' || echo 'NOT converted — check *.premirror-bak' )"
done

# ── [5] the one hand-edit ─────────────────────────────────────────────────────────────────────────
cat <<'EDIT'

[5] ONE hand-edit left — ~/.zshrc line ~88. Replace the _cc_tlid definition:

      OLD:  _cc_tlid() { echo "$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo nogit)"; }
      NEW:  _cc_tlid() { "$HOME/bin/cc-tlid"; }

    Why a delegating one-liner rather than editing the logic in place: ~/.zshrc is not
    version-controlled, so every future change to the sharing key would be invisible. This is the
    last unversioned line; bin/cc-tlid carries the rest and is covered by tests/cc-tlid.bats.

    Then:  exec zsh    (new sessions pick it up; running sessions keep their current board)

EDIT
echo "Done. Verify with:  cc-tlid --explain  &&  cc-task-store verify"
