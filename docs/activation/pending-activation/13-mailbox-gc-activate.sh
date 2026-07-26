#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 13-mailbox-gc  —  turn ON the v3 D6 mailbox lifecycle sweep inside the cc-reaper launchd job
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: sets CC_REAPER_MBXGC=1 in com.chrisren.cc-reaper's command, so each --reap sweep also runs
#   `cc-mailbox-gc sweep --apply`: dead-owner boxes → mailbox/archive/YYYY-MM/, dead letters →
#   mailbox/quarantine/, orphan cursors → mailbox/archive/orphan-cursors/. It also drops a repo SSOT
#   copy of the plist under launchd/, which this job has never had.
#
# WHY IT IS OFF BY DEFAULT (and why the flag exists at all): this is the only reaper-driven step that
#   MUTATES a shared store outside whatever sandbox its caller set up. Every other wired step
#   (reconcile, backlog-reap, inbox-guard) is stubbed in the suites via CC_REAPER_*_BIN — but a step
#   nobody has stubbed YET falls straight through to the real binary against the real store. That is
#   not hypothetical: wiring the GC in un-gated made a single `bats tests/cc-reaper.bats` run sweep
#   the operator's LIVE mailbox (46 boxes archived/quarantined), because that suite sets no
#   CC_MAILBOX_DIR. Opting IN here means only the launchd loop ever sweeps for real.
#
# WHAT IT WILL DO ON FIRST RUN — look before you enable. Preview it, exactly, with:
#       cc-mailbox-gc sweep            # DRY RUN by default: prints every WOULD-ARCHIVE / WOULD-QUARANTINE
#   Nothing is ever deleted: every disposition is a collision-safe `mv`, the `.forward` tombstones stay
#   put, and archived threads stay readable via `cc-thread --archive` / `cc-thread --quarantine`.
#
# WHY C10 (agent staged; operator runs): this edits a live launchd job.
#
# SAFETY: backup to ~/Library/LaunchAgents/com.chrisren.cc-reaper.plist.pre-mbxgc.bak BEFORE any
#   write · plutil-validated · bootout+bootstrap (never a bare `launchctl load`) · --rollback restores.
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/13-mailbox-gc-activate.sh
# Rollback: bash ~/.claude/autonomy/pending-activation/13-mailbox-gc-activate.sh --rollback
# Mark done: touch ~/.claude/autonomy/pending-activation/13-mailbox-gc-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
LABEL="com.chrisren.cc-reaper"
PLIST="${CC_MBXGC_PLIST:-$HOME/Library/LaunchAgents/$LABEL.plist}"
BAK="$PLIST.pre-mbxgc.bak"
UID_N="$(id -u)"

echo "== 13-mailbox-gc =="
command -v plutil >/dev/null 2>&1 || { echo "✗ plutil required" >&2; exit 1; }

# NOTE: `plutil -extract <k> json <file>` WITHOUT -o REWRITES THE PLIST IN PLACE (destroyed 5 calendar
# LaunchAgents on 2026-07-25). Every read below goes to stdout via `-o -`. Never drop that flag.
read_args() { plutil -extract ProgramArguments json -o - "$1" 2>/dev/null; }

if [ "${1:-}" = "--rollback" ]; then
  if [ -f "$BAK" ] && plutil -lint "$BAK" >/dev/null 2>&1; then
    cp -a "$BAK" "$PLIST" && rm -f "$BAK" && echo "  ← $PLIST restored"
    launchctl bootout "gui/$UID_N/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_N" "$PLIST" 2>/dev/null && echo "  ✓ job reloaded from the restored plist"
  else
    echo "· nothing to roll back (no valid $BAK)"
  fi
  exit 0
fi

[ -f "$PLIST" ] || { echo "✗ not found: $PLIST (is the cc-reaper job installed?)" >&2; exit 1; }
[ -x "$REPO/bin/cc-mailbox-gc" ] || { echo "✗ $REPO/bin/cc-mailbox-gc missing — deploy the checkout first:" >&2
                                      echo "    git -C $REPO fetch origin && git -C $REPO merge --ff-only origin/main" >&2; exit 1; }

CUR="$(read_args "$PLIST")"
if printf '%s' "$CUR" | grep -q 'CC_REAPER_MBXGC=1'; then
  echo "· already enabled — nothing to do."; exit 0
fi

echo
echo "Will do:"
echo "  0  copy the live plist into the repo as SSOT ($REPO/launchd/$LABEL.plist) — it has never had one"
echo "  1  backup  → $BAK"
echo "  2  set CC_REAPER_MBXGC=1 in the job's command"
echo "  3  bootout + bootstrap $LABEL"
echo
echo "Preview what the first sweep will move (DRY RUN, moves nothing):"
echo "    $REPO/bin/cc-mailbox-gc sweep"
echo

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/13-mailbox-gc-activate.sh"
  exit 0
fi

# ---- 0: repo SSOT copy (every live plist needs one; this job never had one) -------------------------
mkdir -p "$REPO/launchd" 2>/dev/null
if [ ! -f "$REPO/launchd/$LABEL.plist" ]; then
  cp -a "$PLIST" "$REPO/launchd/$LABEL.plist" && echo "[0] → $REPO/launchd/$LABEL.plist (SSOT copy; commit it)"
else
  echo "[0] = $REPO/launchd/$LABEL.plist already present"
fi

# ---- 1: backup -------------------------------------------------------------------------------------
cp -a "$PLIST" "$BAK" || { echo "✗ backup failed — refusing to touch the plist" >&2; exit 1; }
echo "[1] → $BAK"

# ---- 2: edit the command string --------------------------------------------------------------------
# The job runs `/bin/zsh -lc "<command>"`; prefix the export onto that command string. Done in python
# via plistlib (a structured rewrite), never sed over XML.
python3 - "$PLIST" <<'PY' || { echo "✗ edit failed — restoring backup" >&2; cp -a "$BAK" "$PLIST"; exit 1; }
import plistlib, sys
p = sys.argv[1]
with open(p, 'rb') as f: d = plistlib.load(f)
args = d.get('ProgramArguments') or []
if not args:
    print("no ProgramArguments", file=sys.stderr); sys.exit(1)
cmd = args[-1]
if 'CC_REAPER_MBXGC' not in cmd:
    args[-1] = 'export CC_REAPER_MBXGC=1; ' + cmd
    d['ProgramArguments'] = args
    with open(p, 'wb') as f: plistlib.dump(d, f)
PY

if ! plutil -lint "$PLIST" >/dev/null 2>&1 || ! read_args "$PLIST" | grep -q 'CC_REAPER_MBXGC=1'; then
  echo "✗ VALIDATION FAILED — restoring $BAK" >&2; cp -a "$BAK" "$PLIST"; exit 1
fi
echo "[2] ✓ CC_REAPER_MBXGC=1 set + plist validates"

# ---- 3: reload -------------------------------------------------------------------------------------
launchctl bootout "gui/$UID_N/$LABEL" 2>/dev/null || true
if launchctl bootstrap "gui/$UID_N" "$PLIST" 2>/dev/null; then
  echo "[3] ✓ $LABEL reloaded"
else
  echo "[3] ✗ bootstrap FAILED — the job is now UNLOADED. Restore + reload with:" >&2
  echo "        bash $HOME/.claude/autonomy/pending-activation/13-mailbox-gc-activate.sh --rollback" >&2
  exit 1
fi

echo
echo "✓ the mailbox lifecycle sweep is ACTIVE (runs with each 300 s cc-reaper --reap)."
echo "  Watch it:   tail -f ~/.claude/logs/cc-reaper.out.log | grep mailbox-gc"
echo "  Read what it archived:   cc-thread --archive   ·   cc-thread --quarantine"
echo
echo "  Mark this activation done:"
echo "      touch $HOME/.claude/autonomy/pending-activation/13-mailbox-gc-activate.sh.done"
echo
echo "ROLLBACK: bash $HOME/.claude/autonomy/pending-activation/13-mailbox-gc-activate.sh --rollback"
