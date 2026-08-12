#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 40-cc-gc  —  activate the GC franchise sweep
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT LANDED: scripts/cc-gc.sh, the one sweeping reaper the infra-reliability audit asked for
#   (roadmap item 4). The two per-store reapers it delegates to — scratchpad-reaper.sh and
#   worktree-gc.sh — landed separately (2026-07-25 / 2026-08-11) and are ALREADY live symlinks in
#   ~/.claude/scripts, verified 2026-08-12, so Step 1 below covers cc-gc.sh only. The session-index
#   retention leg is NOT here: it is parked whole on branch park/gc-session-index (see Step 2).
#
# WHY THIS SCRIPT EXISTS AT ALL: root cause 1 of that same audit is that fixes land and then never
#   take effect. ~/.claude/scripts/ is a real directory of PER-FILE symlinks, so a brand-new tracked
#   file is never linked no matter how current the checkout (K26) — cc-gc.sh would sit in the repo,
#   inert, exactly like com.claude.log-rotation did while idl.jsonl grew to 85 MB. Step 1 is that
#   symlink. Skipping it means nothing here runs.
#
# C10: this STAGES the wiring; YOU (operator) run it. Step 3 loads a standing DELETING job, which is
#   a class-C decision and is never auto-applied.
#
# Convention: after you complete the steps, mark done:
#     touch ~/.claude/autonomy/pending-activation/40-cc-gc-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
PLIST="com.claude.cc-gc.plist"
NEW_SCRIPTS="cc-gc.sh"

echo "== 40-cc-gc =="
echo
echo "Step 1 (mechanical, safe — closes the K26 deploy-symlink gap):"
for s in $NEW_SCRIPTS; do
  echo "    ln -sfn $REPO/scripts/$s ~/.claude/scripts/$s"
done
echo
echo "Step 2 (rehearse — deletes NOTHING; cc-gc is dry-run by default):"
echo "    ~/.claude/scripts/cc-gc.sh --verbose"
echo "    Read the table before Step 3. Two things are worth checking by eye:"
echo "      · scratchpad reaped=N — this is the 11 GB store; confirm the kept_live count looks sane."
echo "      · any ASSERT row reading 'inert' — that store's OWNER is not running. cc-gc will not"
echo "        fix that (it deliberately does not race another reaper); it is telling you a job"
echo "        needs loading. 'events inert' clears once this deploys. 'session-index inert' is"
echo "        EXPECTED and will persist: that store's retention leg is parked on branch"
echo "        park/gc-session-index awaiting your ratification (it deletes index rows, so"
echo "        ship-land refused to auto-land it — decision packet shipland-esc-ab66db8)."
echo
echo "Step 3 (class-C — a standing DELETING job):"
echo "    cp $REPO/launchd/$PLIST ~/Library/LaunchAgents/"
echo "    launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/$PLIST"
echo "    launchctl list | grep cc-gc        # verify it registered"
echo
echo "  NOTE: load THIS job, not com.claude.scratchpad-reaper as well — cc-gc already drives the"
echo "  scratchpad store by delegation, so loading both just double-drives it."
echo
echo "Rollback:  launchctl bootout gui/\$(id -u)/com.claude.cc-gc"
echo

if [ "${CONFIRM:-0}" = 1 ]; then
  rc=0
  for s in $NEW_SCRIPTS; do
    if [ ! -f "$REPO/scripts/$s" ]; then
      echo "✗ Step 1: $REPO/scripts/$s missing — is the checkout current? (git -C $REPO log --oneline -1)" >&2
      rc=1; continue
    fi
    if ln -sfn "$REPO/scripts/$s" "$HOME/.claude/scripts/$s"; then
      echo "✓ linked ~/.claude/scripts/$s"
    else
      echo "✗ link failed: $s" >&2; rc=1
    fi
  done
  [ "$rc" -eq 0 ] && echo "✓ Step 1 done. Now run Step 2 (rehearse), then Step 3 (load) yourself."
  exit "$rc"
else
  echo "(dry: re-run with CONFIRM=1 to perform Step 1's symlinks; Steps 2 and 3 stay yours.)"
fi
