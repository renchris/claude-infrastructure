#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 27-worktree-gc-infra  —  SCHEDULE the worktree janitor for claude-infrastructure (04:15 daily)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: installs launchd/com.claude.worktree-gc-infra.plist into ~/Library/LaunchAgents and
#   bootstraps it. From then on, 04:15 daily:
#
#     git fetch origin main  →  scripts/worktree-gc.sh --prune-branches  →  one verdict= line
#
# WHY: the janitor has been complete and safe since 2026-07-25 and has NEVER been scheduled. The
#   only scheduled reaper on this box is gl.reso.worktree-gc, whose runner hardcodes
#   REPO=/Users/chrisren/Development/reso-management-app, so claude-infrastructure was swept by
#   nothing at all. Measured 2026-08-01: 126 worktrees, 1,193 branches. The gap was never the
#   janitor — it was the cron.
#
# WHY C10 (agent stages; operator runs): this schedules a job that DELETES worktrees and branches
#   on an unattended cadence. Every gate lives in worktree-gc.sh (never `--force`, never `branch -D`,
#   liveness + cleanliness + idle + patch-equivalence must all pass), but arming an autonomous
#   deleter is an operator decision, not an agent's.
#
# SAFETY: --prune-branches deletes ONLY landed, worktree-less, unprotected branches, via
#   `git branch -d` — git's own merge check is a second gate and a refusal is a KEEP.
#   --dispose-abandoned is NOT passed: that class needs a recorded ownership decision, and a
#   nightly cron is the wrong place to infer one. Excluded, always: the repo root (~/.claude
#   symlinks into it) and ~/.claude/autonomy/postland (the post-land verifier's own worktrees).
#
# KILL SWITCH (no unload required):  touch ~/.claude/autonomy/worktree-gc-infra.disabled
# OBSERVE ONLY (log decisions, remove nothing):
#   WTGC_OBSERVE=1 bash ~/.claude/scripts/worktree-gc-infra-run.sh
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/27-worktree-gc-infra-activate.sh
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
set -uo pipefail

LABEL="com.claude.worktree-gc-infra"
REPO="/Users/chrisren/Development/claude-infrastructure"
SRC="$REPO/launchd/$LABEL.plist"
DST="$HOME/Library/LaunchAgents/$LABEL.plist"
RUNNER="$HOME/.claude/scripts/worktree-gc-infra-run.sh"
UID_NUM="$(id -u)"

if [ "${CONFIRM:-0}" != 1 ]; then
  cat <<EOF
27-worktree-gc-infra — DRY RUN (nothing written).
Would:
  cp $SRC
     $DST
  launchctl bootstrap gui/$UID_NUM $DST      (then: enable + kickstart-free; RunAtLoad is false)

Schedule: 04:15 daily. Sweeps $REPO with --prune-branches.
Re-run with:  CONFIRM=1 bash \$0
EOF
  exit 0
fi

# ── Preflight: the runner must exist in the LIVE layer. It is a BRAND-NEW file, and per-file
#    symlink dirs never link a new file, so this is exactly the case where "landed" does not mean
#    "deployed" — the plist would bootstrap fine and then fail every single run.
missing=0
for f in "$SRC" "$RUNNER"; do
  [ -e "$f" ] || { echo "⛔ MISSING: $f"; missing=1; }
done
if [ "$missing" = 1 ]; then
  cat <<'EOF'
   The runner is landed on origin/main but NOT deployed into the live layer (or the plist is
   missing from the checkout). Fix first (installs the new symlinks), then re-run:
     bash /Users/chrisren/Development/claude-infrastructure/install.sh
EOF
  exit 2
fi
[ -x "$RUNNER" ] || chmod +x "$RUNNER" 2>/dev/null

plutil -lint "$SRC" >/dev/null || { echo "⛔ $SRC is not a valid plist — refusing to install"; exit 2; }

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.claude/autonomy" "$HOME/.claude/logs"

# Idempotent: an identical installed copy is a no-op, a DIFFERENT one is replaced (the committed
# plist is the SSOT; a drifted live copy is the thing cc-fleet --plist-parity exists to catch).
if [ -f "$DST" ] && cmp -s "$SRC" "$DST"; then
  echo "✓  $DST already matches the committed plist"
else
  cp -f "$SRC" "$DST" || { echo "⛔ copy failed"; exit 2; }
  echo "✓  installed $DST"
  launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null   # drop a stale registration before re-adding
fi

if launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
  echo "✓  $LABEL already bootstrapped"
else
  launchctl bootstrap "gui/$UID_NUM" "$DST" || { echo "⛔ bootstrap failed"; exit 2; }
  echo "✓  bootstrapped $LABEL"
fi
launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null

echo
echo "27-worktree-gc-infra: $LABEL is scheduled for 04:15 daily."
cat <<'EOF'

VERIFY (disk truth — run now, it does NOT need to wait for 04:15):
  WTGC_OBSERVE=1 bash ~/.claude/scripts/worktree-gc-infra-run.sh; \
    cat ~/.claude/autonomy/worktree-gc-infra.last

  Expect one line:  <ts>  verdict=ok observe=1 removed=… branches=… rc=0
  After the first real run, the same file carries observe=0.

FLIP THE MANIFEST: launchd/fleet.manifest declares this label `staged` (decision pending). Once
you have activated it, change that row to `run` so cc-fleet evaluates it instead of emitting a
permanent UNDECIDED row.
EOF
exit 0
