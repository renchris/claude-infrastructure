#!/bin/bash
# 10-lead-crash-orphan-close-activate.sh — OPERATOR STEP (C10). Arms the lead-crash watchdog's
# orphaned-pane CLOSE leg (leg b of backlog 95281da714f0).
#
# WHAT IS ALREADY LIVE WITHOUT RUNNING THIS
#   Leg (a) HARVEST is unconditional and already active: when a lead dies, every assignee's final
#   report is recovered from its transcript into <team_dir>/HARVEST/ BEFORE anything is torn down.
#   That is the leg that stops reports being lost, and it needs no activation because it is
#   strictly non-destructive (it only creates files).
#
#   Leg (b) CLOSE is built, tested and DEFAULT-OFF. Unarmed it is NOT silent: it still enumerates
#   the orphaned panes, applies the eligibility gate and writes <team_dir>/HARVEST/close-plan.tsv
#   with a WOULD-CLOSE row per pane, and logs "N orphaned pane(s) left RUNNING". So you can see
#   exactly what it would have reaped before you let it reap anything.
#
# WHY THIS IS AN OPERATOR STEP AND NOT A DEFAULT
#   bin/cc-teardown's own header bars wiring it RAW into any hook / settings.json / launchd — that
#   fires it with no gate in front (C10). cc-reaper is the one sanctioned PRE-GATED autonomous
#   caller. The lead-crash watchdog is spawned FROM a SessionStart hook, so arming an automatic
#   pane-killer there by default is precisely the wiring that rule forbids. Separately, a
#   newly-wired MUTATING step defaults OFF as a standing rule.
#
# WHAT ARMING ACTUALLY ALLOWS (the gates that still apply — arming does NOT bypass them)
#   1. POSITIVE death evidence only — the watchdog acted because the lead pid failed kill -0.
#   2. HARVEST-FIRST — a member is closable only if its row in HARVEST/status.tsv is HARVESTED or
#      EMPTY. A NO-TRANSCRIPT member is NEVER closed: its pane is the last place its report could
#      still be found.
#   3. cc-teardown re-runs its OWN full gate (work-safe, positive-done, self-guard, tty-exclusive)
#      and re-observes both legs. Dirty or committed-not-pushed ⇒ DEFER (exit 10), left alone.
#      A surviving pane ⇒ FAIL LOUD (exit 5), never a false success.
#   So this is a triple gate: death verdict → harvest-complete → cc-teardown's own gate.
#
# NOTE ON MACHINE STATE: this adds NO launchd job and loads NOTHING. All 13 com.claude jobs remain
# deliberately disabled. This only sets an environment variable the existing watchdog reads.
#
# REVERSIBLE: to disarm, delete the exported line from the file below and restart affected sessions.

set -euo pipefail

ENVFILE="$HOME/.claude/autonomy/watchdog.env"

echo "== lead-crash orphaned-pane close — arming =="
echo

# 1. Show what the close leg WOULD have done, from real plans already on disk (if any exist yet).
echo "-- close-plans recorded so far (unarmed dry runs) --"
found=0
for p in "$HOME"/.claude/teams/*/HARVEST/close-plan.tsv \
         "$HOME"/.claude-secondary/teams/*/HARVEST/close-plan.tsv; do
  [ -f "$p" ] || continue
  found=1
  echo "  $p"
  sed 's/^/    /' "$p"
done
[ "$found" = 1 ] || echo "  (none yet — no lead has crashed with a team since leg (a) landed)"
echo

# 2. Arm it.
mkdir -p "$(dirname "$ENVFILE")"
if grep -q '^export LCW_ORPHAN_CLOSE=' "$ENVFILE" 2>/dev/null; then
  echo "already armed in $ENVFILE:"
  grep '^export LCW_ORPHAN_CLOSE=' "$ENVFILE"
else
  printf 'export LCW_ORPHAN_CLOSE=1   # arm lead-crash orphaned-pane close (backlog 95281da714f0)\n' \
    >> "$ENVFILE"
  echo "armed → $ENVFILE"
fi
echo

# 3. Make sure the env file is actually sourced by the shells that spawn sessions.
if ! grep -q 'autonomy/watchdog.env' "$HOME/.zshrc" 2>/dev/null; then
  echo "NOT YET SOURCED. Add this line to ~/.zshrc, then open a new terminal:"
  echo
  echo "  [ -f \"\$HOME/.claude/autonomy/watchdog.env\" ] && . \"\$HOME/.claude/autonomy/watchdog.env\""
  echo
else
  echo "Your .zshrc already sources the env file — new sessions will pick it up."
fi

echo "Done. Mark complete with:"
echo "  touch $HOME/.claude/autonomy/pending-activation/10-lead-crash-orphan-close-activate.sh.done"
