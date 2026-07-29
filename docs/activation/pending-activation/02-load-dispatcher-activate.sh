#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 02-load-dispatcher  —  run AFTER 01 (reap-guard) is engaged
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: loads com.claude.dispatcher (RunAtLoad=false, StartInterval 300) — the cron dispatcher spine
#   that pulls cc-backlog → cc-wave-plan quota-places → claims + spawns sessions. Loading this plist IS
#   the "autonomous-operator-goes-live" ratification (operator decisions #5/#6).
# PRECONDITION: 01-reap-guard-insert must be .done (Sequencing Law). cc-dispatch is symlinked live.
# C10: agent staged; operator loads. Sanity-run `cc-dispatch --once --dry-run` by hand first.
# Authoritative: docs/activation/dispatcher-activate-snippet.md
# Mark done: touch ~/.claude/autonomy/pending-activation/02-load-dispatcher-activate.sh.done
#
# 2026-07-29 (AUTONOMY_DISPATCH_V2 §9). This step was marked .done on 2026-07-19 and the label sat
# `=> disabled` and unloaded ever since, with no log file and no dispatch decision for ~3 days — a
# bootstrap against a label in launchd's disabled DB fails with a bare EIO naming neither cause nor
# cure, and the marker records that the script RAN, never that the job LOADED. Two consequences,
# both encoded below: `enable` must precede `bootstrap` (it is not optional tidiness — it is the
# whole failure), and the step now ends in an A11 VERIFY that reads the three facts which actually
# distinguish "loaded" from "looked loaded": the label resolves in this domain, it is no longer in
# print-disabled, and it has produced a log. Re-running this script is safe and idempotent, so a
# stale .done marker is not a reason to skip it. StartInterval is now 300s: the poll is the BACKSTOP
# for `cc-backlog`'s add-time kick and is what guarantees the 5-minute decision bound (§7 A2).
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
PLIST="com.claude.dispatcher.plist"
LABEL="${PLIST%.plist}"
# Absolute, never PATH-resolved: this file is also the paste-source for commands that run in launchd
# and root-ish contexts, where PATH is minimal and `~` does not expand.
LAUNCHCTL="/bin/launchctl"
PLUTIL="/usr/bin/plutil"
LOG="/tmp/claude-dispatcher.stdout.log"
UID_="$(id -u)"

echo "== 02-load-dispatcher =="
if [ ! -f "$HOME/.claude/autonomy/pending-activation/01-reap-guard-insert-activate.sh.done" ]; then
  echo "⚠ PRECONDITION: 01-reap-guard-insert is NOT marked .done. Engage reap-guard FIRST (Sequencing Law)." >&2
fi
echo "Pre-flight (do by hand first): cc-dispatch --once --dry-run"
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
    echo "✓ dispatcher bootstrapped (RunAtLoad=false → first pass in one StartInterval = 5 min)."
  else
    echo "✗ load failed — inspect above" >&2; exit 1
  fi

  # A11 — activation is only REAL if all three reads agree. A green bootstrap alone is what the
  # 2026-07-19 run had, and the job never ran once.
  echo
  echo "== verify (A11) =="
  if "$LAUNCHCTL" print "gui/$UID_/$LABEL" >/dev/null 2>&1; then echo "  ✓ label resolves in gui/$UID_"
  else echo "  ✗ label does NOT resolve — the bootstrap did not take" >&2; fi
  if "$LAUNCHCTL" print-disabled "gui/$UID_" 2>/dev/null | grep -q "\"$LABEL\" => disabled"; then
    echo "  ✗ still in the DISABLED database — it will never fire; re-run the enable above" >&2
  else echo "  ✓ not in the disabled database"; fi
  if [ -s "$LOG" ]; then echo "  ✓ $LOG is non-empty"
  else echo "  … $LOG not written yet — expected; re-check after one interval (5 min)"; fi
else
  echo "(dry: re-run with CONFIRM=1 to cp+lint+enable+bootstrap+verify.)"
fi

echo
echo "VERIFY BY HAND (the three A11 reads — a bootstrap that 'worked' is not evidence):"
echo "    $LAUNCHCTL print gui/$UID_/$LABEL | grep -E 'state|program'"
echo "    $LAUNCHCTL print-disabled gui/$UID_ | grep $LABEL      # must NOT say => disabled"
echo "    ls -l $LOG                                             # non-empty within 5 min"
echo
echo "ROLLBACK: $LAUNCHCTL bootout gui/$UID_/$LABEL ; rm $HOME/Library/LaunchAgents/$PLIST"
