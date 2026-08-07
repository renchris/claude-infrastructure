#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 33-devserver-gc  —  SCHEDULE the idle dev-server reaper (hourly, OBSERVE-ONLY at first)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: installs launchd/com.claude.devserver-gc.plist into ~/Library/LaunchAgents and bootstraps it.
#   From then on, at :40 past every hour:
#
#     devserver-census.sh --reap --dry-run   →  one verdict= line + a per-server decision log
#
#   It logs which idle dev servers it WOULD collect and KILLS NOTHING until you arm it (below).
#
# WHY: measured 2026-08-07, 4 concurrent `next-server` processes held 6.2 GB, and
#   `grep -rl 'next-server|pnpm dev|next dev' scripts/ bin/ hooks/` returned NOTHING — no reaper, no
#   cap, no census. A commit gate is transient and self-terminating; a dev server is a permanent
#   per-worktree allocation nobody collects. This box has taken four kernel panics from
#   compressor-segment exhaustion, so resident memory nobody owns is not a cosmetic problem.
#
# ⚠️ READ THIS BEFORE ARMING — the yield is much smaller than the headline:
#   The backlog item that generated this asked to reap the BIGGEST server (5.82 GB, "still growing").
#   Measured, that server was the BUSIEST PROCESS ON THE BOX (+49 s CPU per sample window) and its
#   worktree held a LIVE claude session. Reaping by size would have killed the one server that was
#   provably working. What a SAFE reaper actually collects here is the unowned tail: 1 server,
#   ~450 MB of 6.2 GB. Arm it for the orphan hygiene, not for the 7 GB — that number was never
#   collectable.
#
# WHY C10 (agent stages; operator runs): this schedules a job that can SIGTERM processes holding the
#   operator's unsaved dev state. Every gate lives in devserver-census.sh (live-owner, browser-
#   attached, CPU-busy, birth-grace, plus a fail-closed refusal when lsof is inoperable), but arming
#   an autonomous killer is an operator decision, not an agent's.
#
# SAFETY: the module never reaps a server whose worktree holds a live claude session, whose dev port
#   has a browser attached, that burned CPU between samples, or that is younger than 30 minutes. It
#   sends TERM (never KILL — next dev flushes its build cache on TERM) to the whole
#   pnpm→next→next-server chain, and writes an outcome record for EVERY decision, reap and defer
#   alike. If lsof cannot report even this process's own cwd it REFUSES to decide and exits 3,
#   because a silently-empty liveness oracle is exactly how reso's reaper killed a live worktree in
#   2026-06.
#
# AFTER A FEW DAYS, TO ACTUALLY REAP: add DEVGC_ACT=1 to the plist's EnvironmentVariables, then
#   reload. Until then every run is a dry run.
#
# KILL SWITCH (no unload required):  touch ~/.claude/autonomy/devserver-gc.disabled
# LOOK FIRST, ANY TIME (read-only):  bash ~/.claude/scripts/devserver-census.sh census
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/33-devserver-gc-activate.sh
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
set -uo pipefail

LABEL="com.claude.devserver-gc"
REPO="/Users/chrisren/Development/claude-infrastructure"
SRC="$REPO/launchd/$LABEL.plist"
DST="$HOME/Library/LaunchAgents/$LABEL.plist"
RUNNER="$HOME/.claude/scripts/devserver-gc-run.sh"
UID_NUM="$(id -u)"

if [ "${CONFIRM:-0}" != 1 ]; then
  cat <<EOF
33-devserver-gc — DRY RUN (nothing written).
Would:
  cp $SRC
     $DST
  launchctl bootout  gui/$UID_NUM/$LABEL   (if already loaded)
  launchctl bootstrap gui/$UID_NUM $DST
  launchctl enable    gui/$UID_NUM/$LABEL

The job runs at :40 past every hour and, until you add DEVGC_ACT=1 to the plist,
logs what it WOULD reap and kills nothing.

Look at the current picture right now, without installing anything:
  bash $REPO/scripts/devserver-census.sh census

Re-run with CONFIRM=1 to install.
EOF
  exit 0
fi

[ -f "$SRC" ] || { echo "⛔ missing plist: $SRC"; exit 1; }
if [ ! -x "$RUNNER" ]; then
  echo "⚠️  runner not deployed at $RUNNER — run scripts/deploy-live.sh first, then re-run this."
  exit 1
fi

# Positive control BEFORE arming anything: the module must be able to answer at all. A reaper whose
# oracle is blind is worse than no reaper (it reads every server as unowned).
if ! "$REPO/scripts/devserver-census.sh" --selftest >/dev/null 2>&1; then
  echo "⛔ devserver-census.sh --selftest is RED — refusing to schedule a reaper that cannot prove its own gates."
  exit 1
fi
echo "✅ devserver-census --selftest green (14 checks)"

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.claude/logs" "$HOME/.claude/autonomy"
cp "$SRC" "$DST"
launchctl bootout   "gui/$UID_NUM/$LABEL"      2>/dev/null
launchctl bootstrap "gui/$UID_NUM" "$DST"      || { echo "⛔ bootstrap failed"; exit 1; }
launchctl enable    "gui/$UID_NUM/$LABEL"      2>/dev/null

echo "✅ $LABEL installed and enabled — hourly at :40, OBSERVE-ONLY (dry-run)."
echo
echo "Watch what it would collect:   tail -f ~/.claude/logs/devserver-gc.out.log"
echo "Last structured verdict:       cat ~/.claude/logs/devserver-gc.last"
echo "Stop it without unloading:     touch ~/.claude/autonomy/devserver-gc.disabled"
