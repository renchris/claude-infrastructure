#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 21-relogin-poll  —  load the hourly login-renewal poller (row 7, ACCOUNT_ROUTING_V2 M4)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: one step. Load com.claude.relogin (StartInterval 3600, RunAtLoad false, Background). The
#   executable it runs, bin/cc-relogin-poll, is ALREADY live — ~/.claude/bin is a per-file symlink
#   dir and that file has been linked since 2026-07-26. Nothing to copy; this is purely the load.
#
# WHY: the poller has existed and been tested since 2026-07-26 and has NEVER been scheduled. Its
#   log holds TWO lines, all-time, both from a hand invocation on 07-26. Its label was also absent
#   from launchd/fleet.manifest, so bin/cc-fleet never evaluated it and NOTHING reported the
#   inertness — the feature-durability-mechanism-not-memory failure, doubled. M4 declared the label
#   (expect=staged ⇒ exactly one UNDECIDED row, "declared, decision pending"); this script is the
#   decision.
#
# WHAT IT BUYS, measured 2026-07-30 (docs/plans/ACCOUNT_ROUTING_V2.md §2):
#   · A login cliff is a SCHEDULED certainty — an absolute stamp already in the keychain, ~30 d per
#     account. Six successful refreshes did not move next3's wall; it died anyway, 24 doomed grants
#     in 7.7 h and 93.5 h of outage, recovered only by an interactive login.
#   · `next` — the operator's #1 spend-priority account — cliffs 2026-08-02T20:21:49Z. That is the
#     next real window, three weeks EARLIER than RELOGIN_AUTOMATION_PLAN.md's "closed until roughly
#     2026-08-23" (falsified in §1).
#
# WHAT IT DOES **NOT** DO: it never auto-fires an interactive re-auth blind. cc-relogin keeps its
#   three non-negotiable guards (need-check, k == 0, the shared heal lock), and this poller only
#   hands it ONE account per tick. At T-48h it raises a class-C `relogin-blocked` row on the
#   operator board carrying the exact recovery command — loud BEFORE the deadline, never after.
#
# ⚠ THE FIRST REAL RUN IS A SUPERVISED TEST, NOT A ROUTINE ONE. cc-relogin's Phase 2 (the CDP
#   context→profile match, the Authorize click, the `code#state` scrape, the fifo hand-back) has
#   NEVER driven a live OAuth flow — no account has needed a real re-auth since the tool existed
#   (docs/plans/RELOGIN_AUTOMATION_PLAN.md:293). Watch ~/.claude/logs/cc-relogin-poll.log around
#   the `next` deadline above. Runbook: docs/runbooks/RELOGIN_ACTIVATION.md.
#
# WHY C10 (agent stages; operator loads): loading a launchd job IS an activation, and this one can
#   drive an authentication flow — the single most operator-owned surface in the repo.
#
# Kill switches after load, in increasing order of finality:
#   · leave it loaded but neutered:   launchctl unload / `launchctl bootout gui/$UID/com.claude.relogin`
#   · keep the cadence, act on nothing: the poller's own `--dry-run` (edit the plist's args)
#   · narrow the window:              `--trigger-days N` in the plist (default 7)
# Mark done:  touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
PLIST="com.claude.relogin.plist"
SRC="$REPO/launchd/staged/$PLIST"
LA="$HOME/Library/LaunchAgents"
LABEL="com.claude.relogin"

echo "== 21-relogin-poll =="
[ -f "$SRC" ] || { echo "✗ missing staged plist: $SRC (is the checkout on a trunk with this commit?)" >&2; exit 1; }
# The plist lives in launchd/staged/, NOT launchd/, ON PURPOSE (8a1e49ab): install.sh globs
# launchd/*.plist, so a plist there would be auto-installed by a routine install — i.e. credentials
# automation activated without an operator deciding. Structure, not a conditional.
[ -x "$HOME/.claude/bin/cc-relogin-poll" ] || {
  echo "✗ ~/.claude/bin/cc-relogin-poll is not present/executable — the plist would load a job that" >&2
  echo "  cannot run. Deploy the live layer first (the checkout must be at a trunk carrying it)." >&2
  exit 1; }

echo "Will do: [0] cc-relogin-poll --dry-run   (decides + reports, invokes NOTHING — proves the"
echo "             detection ladder and the deadline maths against the REAL fleet, side-effect-free)"
echo "         [1] cp launchd/staged/$PLIST → $LA/ ; plutil -lint ; launchctl enable ; bootstrap"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  _pfx=""; [ -n "${CC_REPO+set}" ] && _pfx="CC_REPO=$REPO "
  echo "    CONFIRM=1 ${_pfx}bash $HOME/.claude/autonomy/pending-activation/21-relogin-poll-activate.sh"
  exit 0
fi

echo "[0] poller dry-run against the real fleet (invokes nothing)"
"$HOME/.claude/bin/cc-relogin-poll" --dry-run --json || {
  echo "✗ dry-run failed — NOT activating. Read ~/.claude/logs/cc-relogin-poll.log." >&2; exit 1; }

echo "[1] install + load"
mkdir -p "$LA"
cp -f "$SRC" "$LA/$PLIST" || { echo "✗ cp failed" >&2; exit 1; }
plutil -lint "$LA/$PLIST" || { echo "✗ plutil -lint RED — removing and aborting" >&2; rm -f "$LA/$PLIST"; exit 1; }
launchctl enable "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$LA/$PLIST" 2>/dev/null || \
  launchctl load -w "$LA/$PLIST" 2>/dev/null || true

echo
echo "== verify (this is the axis-3 effect-read: a .done marker proves the SCRIPT ran, never that"
echo "   the JOB loaded — bin/cc-fleet reads launchctl, not the marker) =="
if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
  echo "✓ $LABEL is LOADED"
  echo "  next: flip its manifest row from 'staged' to 'run' so bin/cc-fleet evaluates it for real:"
  echo "        \$EDITOR $REPO/launchd/fleet.manifest    # com.claude.relogin | run | 3600 | …"
  echo "  then: touch $HOME/.claude/autonomy/pending-activation/21-relogin-poll-activate.sh.done"
else
  echo "✗ $LABEL did NOT load — do NOT mark this done. Diagnose:" >&2
  echo "    launchctl print-disabled gui/$UID | grep relogin" >&2
  echo "    plutil -p $LA/$PLIST" >&2
  exit 1
fi
