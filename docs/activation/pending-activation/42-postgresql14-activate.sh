#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 42-postgresql14  —  bring homebrew.mxcl.postgresql@14 back to its DECLARED running state
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHY THIS EXISTS (backlog fa2aa0f5e535): postgresql@14 was silently DOWN from 2026-08-05 to
#   2026-08-13 — eight days, zero starts in its own log, launchd retrying every 10s invisibly, and
#   it self-healed on a reboot rather than on anyone noticing. Nothing on this box could have said
#   so: bin/cc-fleet is the launchd fleet's absence reader, but its unit of coverage is A LINE IN
#   launchd/fleet.manifest, and this label had no line. A daemon nothing declares is a daemon
#   nothing can report.
#
# WHAT LANDED: the manifest row. `homebrew.mxcl.postgresql@14 | run | 0 | - | 12 | <this file>`.
#   From that row cc-fleet reads launchd's own counters and reports S4 FAILING the moment
#   `last exit code` is non-zero — which is exactly what an every-10s retry loop looks like — and
#   cc-blockers folds that row onto the operator board. `evidence = -` is deliberate: the manifest's
#   own header spells out why a job with no artifact touched on EVERY run must never be S5 STALLED
#   claimed, and postgres writes to its log only on start and on error, so `auto` would fire
#   STALLED on a perfectly healthy database after one quiet day.
#
# WHEN YOU WILL SEE THIS SCRIPT: only when the board carries a `fleet-inert` row naming this label.
#   It is a RECOVERY, not a wiring step — the service is brew-managed and was already running when
#   the row landed (launchctl print: state = running, runs = 1, last exit code = (never exited)).
#
# C10: this STAGES the command; YOU (operator) run it. Starting a database is a state change on a
#   store, so it is never auto-applied.
#
# Convention: after you complete the steps, mark done:
#     touch ~/.claude/autonomy/pending-activation/42-postgresql14-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
LABEL="homebrew.mxcl.postgresql@14"
UID_N="$(id -u)"

echo "== 42-postgresql14 =="
echo
echo "Step 1 (read-only — what launchd currently thinks):"
echo "    launchctl print gui/$UID_N/$LABEL | grep -E 'state =|runs =|last exit code|program ='"
echo
launchctl print "gui/$UID_N/$LABEL" 2>/dev/null \
  | grep -E 'state =|runs =|last exit code|program =' | sed 's/^/    /' \
  || echo "    (label not loaded — Step 2 is the fix)"
echo
echo "Step 2 (restart the service — brew owns the plist, so brew is the actuator):"
echo "    brew services restart postgresql@14"
echo
echo "Step 3 (verify by reading it back through a DIFFERENT call than the one that changed it):"
echo "    launchctl print gui/$UID_N/$LABEL | grep -E 'state =|last exit code'"
echo "    bash \$HOME/.claude/bin/cc-fleet --table | grep postgresql"
echo
echo "Step 4 (if it will not stay up, its own log is the next read — NOT this script):"
echo "    tail -60 /opt/homebrew/var/log/postgresql@14.log"
