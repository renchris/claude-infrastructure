#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 01-reap-guard-insert  —  SEQUENCING LYNCHPIN, run FIRST (before 02/03 load the dispatcher)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHY FIRST: autonomous ship-land (which the dispatcher will drive) creates clean+landed states, which
#   REMOVES the accidental dirty-tree shield that today alone prevents wrongful reaps of working
#   sessions. reap-guard.sh is built + RED-green but the live TeammateIdle hook does NOT call it yet
#   (bare-idleness is still the live predicate). Engage reap-guard BEFORE the dispatcher goes live, or
#   the plan's own Sequencing Law (red-team V3) is violated.
#
# C10: this stages the wiring; YOU (operator) run it. It edits a LIVE hook — the hook insert (Step 2)
#   is a reviewed manual diff, NOT auto-applied. Authoritative source (exact diff + rationale):
#     docs/activation/reap-safety-activate-snippet.md
#
# Convention: after you complete BOTH steps, mark done:
#     touch ~/.claude/autonomy/pending-activation/01-reap-guard-insert-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
SNIP="$REPO/docs/activation/reap-safety-activate-snippet.md"

echo "== 01-reap-guard-insert (SEQUENCING FIRST) =="
echo "Step 1 (mechanical, safe): symlink reap-guard.sh into ~/.claude/scripts/"
echo "    ln -sfn $REPO/scripts/reap-guard.sh ~/.claude/scripts/reap-guard.sh"
echo "Step 2 (manual, live-hook edit — review the exact diff in the snippet):"
echo "    \$EDITOR $REPO/hooks/teammate-auto-shutdown.sh   # apply the reap-guard block per snippet Step 2"
echo "    (insert immediately after the Rule-3 dirty-tree defer 'fi', before 'Clear defer counter')"
echo "Snippet (authoritative): $SNIP"
echo

if [ "${CONFIRM:-0}" = 1 ]; then
  if ln -sfn "$REPO/scripts/reap-guard.sh" "$HOME/.claude/scripts/reap-guard.sh"; then
    echo "✓ Step 1 done: reap-guard.sh symlinked (Step 2 hook edit is still MANUAL — see above)."
  else
    echo "✗ Step 1 symlink failed" >&2; exit 1
  fi
else
  echo "(dry: re-run with CONFIRM=1 to perform Step 1's symlink; Step 2 stays manual regardless.)"
fi

echo
echo "ROLLBACK: rm ~/.claude/scripts/reap-guard.sh  (hook keeps working — the [ -x \$REAP_GUARD ] guard"
echo "          goes false and the live TeammateIdle hook reverts to its prior behavior, no errors);"
echo "          and revert the Step-2 block from hooks/teammate-auto-shutdown.sh."
