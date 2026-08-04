#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 30-teammate-reap-alarm  —  put the assignee-close outcome alarm on a 10-min cadence (row 4)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: three idempotent steps. (1) symlink BOTH scripts into the live ~/.claude/scripts/ layer if
#   absent — a BRAND-NEW file is never auto-linked by a per-file symlink dir (memory
#   deploy-lag-checkout-behind-origin), and this ships two of them. (2) smoke-run the alarm,
#   tolerating its designed verdict exits. (3) load com.claude.teammate-reap-alarm
#   (StartInterval 600, RunAtLoad false, Background/Nice 10).
#
# WHY: the alarm already existed and already worked. Its only caller was bin/cc-blockers:161, a board
#   rendered on PULL when an agent happens to run /ship, and the label was in no launchctl list at
#   all. Ten days of zero closes with twelve assignee panes resident went unreported because nothing
#   ever asked. A sensor with no cadence is a function somebody could call.
#
# WHY BOTH SCRIPTS: the alarm's numerator now comes from scripts/assignee-pane-residency.sh — a join
#   over the live window ids, the team configs' integer panes, and the process table — because the
#   old numerator counted our own log lines and had two proven blind spots (six real closes with
#   zero `✓ closed pane` lines; refusals logged against panes that had already gone). Linking only
#   one of the two would leave the alarm permanently in its labelled log-grep fallback: honest, but
#   exactly as blind as before.
#
# WHY C10 (agent stages; operator loads): loading a launchd job IS an activation.
# Kill after load:  launchctl bootout gui/$UID/com.claude.teammate-reap-alarm.
# Mark done:  touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
PLIST="com.claude.teammate-reap-alarm.plist"
ALARM="$REPO/scripts/teammate-reap-alarm.sh"
RESID="$REPO/scripts/assignee-pane-residency.sh"
LA="$HOME/Library/LaunchAgents"

echo "== 30-teammate-reap-alarm =="
for f in "$ALARM" "$RESID"; do
  [ -f "$f" ] || { echo "✗ missing in checkout: $f (is the checkout on a trunk with this commit?)" >&2; exit 1; }
done
[ -f "$REPO/launchd/$PLIST" ] || { echo "✗ missing plist: $REPO/launchd/$PLIST" >&2; exit 1; }

echo "Will do: [0] run both --selftest (each must pass; they are the positive controls)"
echo "         [1] symlink both scripts → \$HOME/.claude/scripts/ (if not already linked)"
echo "         [2] smoke-run the alarm (exits 0/1/2/3 are all DESIGNED verdicts; only a crash blocks)"
echo "         [3] cp launchd/$PLIST → $LA/ ; plutil -lint ; launchctl enable ; launchctl bootstrap"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  _pfx=""; [ -n "${CC_REPO+set}" ] && _pfx="CC_REPO=$REPO "
  echo "    CONFIRM=1 ${_pfx}bash $HOME/.claude/autonomy/pending-activation/30-teammate-reap-alarm-activate.sh"
  exit 0
fi

# [0] The self-tests, BEFORE anything is linked or loaded. Each drives its own parser to both its
# passing and its failing verdict off one code path — activating an instrument whose control cannot
# fail is how the previous four fixes each shipped green and moved nothing.
echo "[0] self-tests"
bash "$RESID" --selftest || { echo "✗ residency selftest FAILED — NOT activating" >&2; exit 1; }
bash "$ALARM" --selftest || { echo "✗ alarm selftest FAILED — NOT activating" >&2; exit 1; }

echo "[1] symlinks"
for src in "$ALARM" "$RESID"; do
  dest="$HOME/.claude/scripts/$(basename "$src")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "✗ $dest exists and is NOT a symlink — refusing to clobber a real file" >&2; exit 1
  fi
  ln -sfn "$src" "$dest"
  echo "  · $dest → $(readlink "$dest")"
done

# [2] Verdict-tolerant, and deliberately so. ALARM is exit 2 and is very likely what a first run
# returns on this box — that is the job doing its job, not the job being broken. Only a code outside
# the declared verdict set means the script itself failed (memory: daemon-fleet-v2 — a non-zero exit
# can be the DESIGNED verdict; do not "fix" it to always exit 0).
echo "[2] smoke run (verdict-tolerant)"
bash "$ALARM"; rc=$?
case "$rc" in
  0|1|2|3) echo "  · verdict exit $rc — a valid alarm outcome, proceeding" ;;
  *)       echo "✗ alarm crashed (exit $rc) — NOT activating" >&2; exit 1 ;;
esac

echo "[3] launchd"
mkdir -p "$LA"
cp -f "$REPO/launchd/$PLIST" "$LA/$PLIST"
plutil -lint "$LA/$PLIST" || { echo "✗ plist lint failed" >&2; exit 1; }
launchctl enable "gui/$(id -u)/com.claude.teammate-reap-alarm" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.claude.teammate-reap-alarm" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LA/$PLIST" || { echo "✗ bootstrap failed" >&2; exit 1; }
launchctl print "gui/$(id -u)/com.claude.teammate-reap-alarm" | grep -E 'state|last exit' | head -3 || true

echo
echo "DONE. Flip launchd/fleet.manifest's row from \`staged\` to \`run\` — leaving it staged after"
echo "activating makes cc-fleet emit a permanent UNDECIDED row for a job that IS scheduled."
echo "Verify later:  tail -20 ~/.claude/logs/teammate-reap-alarm.out.log   (a report every ~600 s)"
echo "The FIRST tick will read NOT-EXERCISED 'first sample' — the residency cursor has to be seated"
echo "before departures can be differenced. The second tick is the first real verdict."
echo "Then:  touch $HOME/.claude/autonomy/pending-activation/30-teammate-reap-alarm-activate.sh.done"
