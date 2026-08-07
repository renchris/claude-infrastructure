#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 34-deploy-plist-fallback  —  put D4 (the advancer's exec fallback) into the job that actually runs
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: reload com.claude.deploy-live from the repo plist, then VERIFY BY CONTENT that the running
#   job's ProgramArguments carry the fallback. Four steps: lint · cp → ~/Library/LaunchAgents ·
#   bootout+bootstrap · read the fallback back out of `launchctl print`.
#
# WHY: DEPLOY_LANE_GROUND_UP.md §2.5 D4 says the advancer must not be undeployable by its own outage.
#   The launchd job execs $HOME/.claude/scripts/deploy-live.sh — a symlink that link_refresh, INSIDE
#   that same script, is responsible for creating. With the link absent the job cannot start at all:
#   measured 118 x `No such file or directory` in autonomy/postland/deploy.log. The fix (fall back to
#   the repo copy, which is what the symlink points AT) LANDED in `601908fe` and has never run.
#
#   Measured 2026-08-07, and this is the whole reason the script exists:
#     repo   launchd/com.claude.deploy-live.plist  → `D="$HOME/.claude/scripts/deploy-live.sh";
#                                                     [ -x "$D" ] || D="$HOME/Development/…"; exec "$D"`
#     LIVE   ~/Library/LaunchAgents/…plist (a COPY, mtime 2026-07-30) → `exec "$HOME/.claude/…"`
#     LOADED job (launchctl print)                                    → the same pre-fix form
#   27-deploy-lane-v2-activate.sh deployed the two SCRIPTS and says so in its own banner — "Neither
#   launchd job was modified. No plist was touched (C10 intact)." Correct and deliberate; the
#   consequence is that this half of the same change reached a committed file and no enforcing store.
#   A conclusion that never reaches the store that enforces behaviour has changed nothing.
#
# WHY C10 (agent stages; operator loads): rewriting a LaunchAgent and bootstrapping it is a machine
#   mutation on a job the whole fleet's freshness depends on. Landing the plist is the agent's;
#   loading it is the operator's.
#
# IDEMPOTENT: safe to re-run. cp is unconditional, bootout tolerates not-loaded, and the verify at
#   the end is a read. Running it twice costs one missed 600 s tick.
#
# Kill switch:  launchctl bootout gui/$(id -u)/com.claude.deploy-live
# Rollback:     git -C "$REPO" show 601908fe^:launchd/com.claude.deploy-live.plist > "$LA/$PLIST" \
#                 && launchctl bootout … && launchctl bootstrap …
# Mark done:    touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
LABEL="com.claude.deploy-live"
PLIST="$LABEL.plist"
LA="$HOME/Library/LaunchAgents"
SRC="$REPO/launchd/$PLIST"
UID_="$(id -u)"

echo "== 34-deploy-plist-fallback =="
[ -f "$SRC" ] || { echo "✗ missing plist in checkout: $SRC" >&2; exit 1; }

# THE PRECONDITION IS THE POINT, so it is asserted and not assumed. If the checkout predates
# 601908fe this script would cheerfully install a plist WITHOUT the fallback and report success —
# activating the very state it exists to cure. Grep the repo copy for the fallback before touching
# anything (memory: a checkout can be on a trunk that does not carry the commit you are deploying).
# shellcheck disable=SC2016  # $D must NOT expand — it is the literal text being searched FOR inside
# the plist's own shell fragment. Expanding it here would search for this script's (empty) $D.
if ! grep -q '\[ -x "$D" \] || D=' "$SRC"; then
  echo "✗ $SRC does NOT carry the D4 fallback — this checkout is behind 601908fe." >&2
  echo "  Nothing was changed. Fast-forward the checkout and re-run." >&2
  exit 1
fi

echo "Will do: [1] plutil -lint the repo plist (a malformed plist boots out and never comes back)"
echo "         [2] cp $SRC → $LA/$PLIST"
echo "         [3] launchctl bootout + bootstrap gui/$UID_/$LABEL"
echo "         [4] VERIFY BY CONTENT: the loaded job's ProgramArguments carry the fallback"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  _pfx=""; [ -n "${CC_REPO+set}" ] && _pfx="CC_REPO=$REPO "
  echo "    CONFIRM=1 ${_pfx}bash $HOME/.claude/autonomy/pending-activation/34-deploy-plist-fallback-activate.sh"
  echo
  echo "current LOADED exec target:"
  launchctl print "gui/$UID_/$LABEL" 2>/dev/null | grep -A6 'arguments' | sed 's/^/    /' || \
    echo "    (label not loaded)"
  exit 0
fi

echo "[1] lint"
plutil -lint "$SRC" || { echo "✗ plist lint failed — NOT installing" >&2; exit 1; }

echo "[2] install"
mkdir -p "$LA"
cp -f "$SRC" "$LA/$PLIST"
plutil -lint "$LA/$PLIST" || { echo "✗ installed copy fails lint" >&2; exit 1; }

echo "[3] reload"
# bootout on a not-loaded label is exit 3, not an error — the || true is the idempotence, not a
# swallowed failure. bootstrap's rc IS read, because a failed bootstrap leaves the lane UNSCHEDULED.
launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null || true
launchctl enable "gui/$UID_/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_" "$LA/$PLIST" || {
  echo "✗ bootstrap FAILED — the deploy lane is now UNSCHEDULED. Recover:" >&2
  echo "    launchctl bootstrap gui/$UID_ $LA/$PLIST" >&2
  exit 1
}

echo "[4] verify BY CONTENT (never by exit code — a bootstrap that 'worked' can still be running"
echo "    the old plist if the copy silently failed)"
# shellcheck disable=SC2016  # same reason: $HOME is literal text inside the loaded plist's argv, not
# a path to expand. Expanding it would search for /Users/<me>/… which is NOT what launchctl prints.
if launchctl print "gui/$UID_/$LABEL" 2>/dev/null | grep -q 'D="\$HOME/.claude/scripts/deploy-live.sh"'; then
  echo "  ✓ the LOADED job now carries the fallback"
else
  echo "✗ the loaded job does NOT carry the fallback — it did not take. Inspect:" >&2
  echo "    launchctl print gui/$UID_/$LABEL | grep -A6 arguments" >&2
  exit 1
fi
launchctl print "gui/$UID_/$LABEL" 2>/dev/null | grep -E 'state =|runs =|last exit' | sed 's/^/  · /' || true

echo
echo "DONE. The fallback is now in the job that actually runs, so a missing"
echo "\$HOME/.claude/scripts/deploy-live.sh symlink can no longer stop the lane from starting."
echo "Verify later:  grep -c 'No such file or directory' ~/.claude/autonomy/postland/deploy.log"
echo "               (frozen at its current count = the mode is closed; rising = it is not)"
echo "Then:  touch $HOME/.claude/autonomy/pending-activation/34-deploy-plist-fallback-activate.sh.done"
