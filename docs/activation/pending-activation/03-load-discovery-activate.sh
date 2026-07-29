#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 03-load-discovery  —  run AFTER 02 (dispatcher)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: loads com.claude.discovery (RunAtLoad=false, hourly) — the 4 standing critics (C1 frontier-hole /
#   C2 plan-open / C3 wiring-inert-D9 / C4 gate-red) that refill cc-backlog idempotently. Absent-source →
#   ABSTAIN, never fabricate. Feeds the dispatcher's future waves.
# C10: agent staged; operator loads. cc-discover is symlinked live; run `cc-discover --once --dry-run` first.
# Authoritative: docs/activation/discovery-activate-snippet.md
# Mark done: touch ~/.claude/autonomy/pending-activation/03-load-discovery-activate.sh.done
#
# 2026-07-29 (AUTONOMY_DISPATCH_V2 §9). Same correction as 02: this step was marked .done on
# 2026-07-20 and the label sat `=> disabled` and unloaded ever since. A bootstrap against a label in
# launchd's disabled DB fails with a bare EIO, and the .done marker records that the SCRIPT ran, not
# that the JOB loaded — so `enable` must precede `bootstrap`, and the step ends in the A11 verify
# reads that separate "loaded" from "looked loaded". Re-running is safe and idempotent; a stale
# .done is not a reason to skip it. StartInterval stays 3600 (the dispatcher's, not this one's,
# dropped to 300 — this is the SUPPLY side and the backlog is already 121 deep, §2/F15).
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
PLIST="com.claude.discovery.plist"
LABEL="${PLIST%.plist}"
# Absolute, never PATH-resolved (launchd expands neither `~` nor PATH).
LAUNCHCTL="/bin/launchctl"
PLUTIL="/usr/bin/plutil"
LOG="/tmp/claude-discovery.stdout.log"
UID_="$(id -u)"

echo "== 03-load-discovery =="
echo "Pre-flight (by hand): cc-discover --once --dry-run"
echo "Load:"
echo "    cp $REPO/launchd/$PLIST $HOME/Library/LaunchAgents/$PLIST"
echo "    $PLUTIL -lint $HOME/Library/LaunchAgents/$PLIST"
echo "    $LAUNCHCTL enable gui/$UID_/$LABEL && $LAUNCHCTL bootstrap gui/$UID_ $HOME/Library/LaunchAgents/$PLIST"
echo

if [ "${CONFIRM:-0}" = 1 ]; then
  # A label in launchd's DISABLED database refuses bootstrap with a bare EIO naming neither cause
  # nor cure; all 13 com.claude.* labels are disabled on this host (legacy `unload -w` sets that
  # bit and `bootout` never clears it). `enable` clears it, no-ops otherwise, and stays OUT of the
  # && chain so bootstrap remains the verdict. ORDER IS THE WHOLE FIX: enable BEFORE bootstrap.
  "$LAUNCHCTL" enable "gui/$UID_/$LABEL" \
    || echo "  (enable rc=$? — continuing; the bootstrap below is the verdict)"
  if cp "$REPO/launchd/$PLIST" "$HOME/Library/LaunchAgents/$PLIST" \
       && "$PLUTIL" -lint "$HOME/Library/LaunchAgents/$PLIST" \
       && "$LAUNCHCTL" bootstrap "gui/$UID_" "$HOME/Library/LaunchAgents/$PLIST"; then
    echo "✓ discovery bootstrapped (RunAtLoad=false → first pass in one StartInterval = 1 h)."
  else
    echo "✗ load failed — inspect above" >&2; exit 1
  fi

  # A11 — same three reads as 02: a green bootstrap alone is not evidence the job will ever fire.
  echo
  echo "== verify (A11) =="
  if "$LAUNCHCTL" print "gui/$UID_/$LABEL" >/dev/null 2>&1; then echo "  ✓ label resolves in gui/$UID_"
  else echo "  ✗ label does NOT resolve — the bootstrap did not take" >&2; fi
  if "$LAUNCHCTL" print-disabled "gui/$UID_" 2>/dev/null | grep -q "\"$LABEL\" => disabled"; then
    echo "  ✗ still in the DISABLED database — it will never fire; re-run the enable above" >&2
  else echo "  ✓ not in the disabled database"; fi
  if [ -s "$LOG" ]; then echo "  ✓ $LOG is non-empty"
  else echo "  … $LOG not written yet — expected; re-check after one interval (1 h)"; fi
else
  echo "(dry: re-run with CONFIRM=1 to cp+lint+enable+bootstrap+verify.)"
fi

echo
echo "VERIFY BY HAND (the three A11 reads — a bootstrap that 'worked' is not evidence):"
echo "    $LAUNCHCTL print gui/$UID_/$LABEL | grep -E 'state|program'"
echo "    $LAUNCHCTL print-disabled gui/$UID_ | grep $LABEL      # must NOT say => disabled"
echo "    ls -l $LOG                                             # non-empty within 1 h"
echo
echo "ROLLBACK: $LAUNCHCTL bootout gui/$UID_/$LABEL ; rm $HOME/Library/LaunchAgents/$PLIST"
