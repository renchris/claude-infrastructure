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
# launchd/staged/, NOT launchd/ — and the subdirectory is the whole safety property, so it is spelled
# out here rather than left as a path. install.sh globs `launchd/*.plist`; a plist there would let a
# routine install ARM this standing deleting job with no operator decision, which is the same reason
# com.claude.relogin is staged out of that glob. Step 3 below is the only path that loads it.
PLIST_SRC="launchd/staged/com.claude.cc-gc.plist"
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
echo "        needs loading. MEASURED on the real box 2026-08-13: EVERY ASSERT row read 'ok' and"
echo "        inert-owners=0 — including session-index, which this script previously predicted"
echo "        would read 'inert' and PERSIST. It does not: session-index-sweep.sh had run within"
echo "        24h, so that leg is healthy and its parked retention branch (park/gc-session-index,"
echo "        decision packet shipland-esc-ab66db8) blocks nothing here. So treat ANY inert row as"
echo "        real news rather than an expected reading — there is no longer a known-benign one."
echo
echo "Step 3 (class-C — a standing DELETING job):"
echo "    cp $REPO/$PLIST_SRC ~/Library/LaunchAgents/"
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
