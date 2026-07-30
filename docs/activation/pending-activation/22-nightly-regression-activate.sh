#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 22-nightly-regression  —  ENABLE + load the standing regression signal (04:00 nightly)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: two idempotent steps against com.claude.nightly-regression.
#   (1) `launchctl enable`  — the label is currently in this user's DISABLED list, and bootstrap alone
#       will NOT run a disabled job. This step is the one that is actually missing.
#   (2) `launchctl bootstrap` — load it into the gui domain (StartCalendarInterval 04:00,
#       RunAtLoad=false, LowPriorityIO, Nice 10, ProcessType Background).
#
# WHY: the job has NEVER run from launchd. Evidence (2026-07-30 triage of cc-backlog 5fb957ffb085):
#   - `launchctl print-disabled gui/501` lists "com.claude.nightly-regression" => disabled
#   - `launchctl print gui/501/com.claude.nightly-regression` => "Could not find service"
#   - NO /tmp/claude-nightly-regression.std{out,err}.log exists — the plist's own log paths, which
#     launchd creates on the first run. They were never created.
#   - autonomy/regression.log's 8 entries (07-19..26) are stamped 11:07, 12:35, 16:16, 15:22, 13:39,
#     16:25, 20:33, 14:27 UTC — scattered across the working day, never 04:00. Those were MANUAL runs.
#   So "the nightly" has been a hand-run script that happened to get run some days. The whole premise
#   of P0-18 — "a deliberately-broken detector pages by MORNING" — has never held.
#
# PRECONDITION (checked below, fail-closed): the plist runs the script out of the SHARED CHECKOUT
#   $HOME/Development/claude-infrastructure. The 2026-07-30 fix that stops the runner manufacturing
#   false REDs (step-4 LIBRARY / UNSAFE / READINESS-BAR classification + the rc 124/137/143
#   non-verdict) must be present THERE, not merely landed on origin/main — landed != deployed.
#   Activating before it is deployed re-pages the same unreadable RED (12) the triage just dismantled.
#
# WHY C10 (agent stages; operator runs): `launchctl enable`/`bootstrap` IS an activation, and agents
#   are classifier-blocked from it. Kill switch after load:
#     launchctl bootout gui/$(id -u)/com.claude.nightly-regression
#   Mark done:  touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
LABEL="com.claude.nightly-regression"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC="$REPO/scripts/nightly-regression.sh"
UID_N="$(id -u)"

echo "== 22-nightly-regression =="

[ -f "$PLIST" ] || { echo "✗ missing live plist: $PLIST" >&2; exit 1; }
[ -x "$SRC" ]   || { echo "✗ missing/not-executable in the checkout: $SRC" >&2; exit 1; }

# Fail-closed precondition: is the false-RED fix actually DEPLOYED in the checkout the plist runs?
if ! grep -q 'NGR_BAR_BASELINE' "$SRC" 2>/dev/null; then
  echo "✗ REFUSING to activate: $SRC predates the step-4 classification fix." >&2
  echo "  The readiness-bar/library/unsafe classification is absent, so the first 04:00 run would" >&2
  echo "  page RED (12) again — 9 of which are not regressions. Deploy the fix first:" >&2
  echo "    git -C $REPO fetch origin main && git -C $REPO status   # then fast-forward the checkout" >&2
  echo "  Re-run this script once 'grep NGR_BAR_BASELINE $SRC' matches." >&2
  exit 1
fi
echo "  ✓ precondition: step-4 classification present in $SRC"

# Prove both verdict paths before arming anything — side-effect-free (page/log go to a temp dir).
echo "Will do: [0] $SRC --selftest   (proves the red-path pages and the green-path clears)"
if ! "$SRC" --selftest >/tmp/nightly-reg-activate-selftest.log 2>&1; then
  echo "✗ selftest FAILED — not arming. See /tmp/nightly-reg-activate-selftest.log" >&2
  tail -15 /tmp/nightly-reg-activate-selftest.log >&2
  exit 1
fi
echo "  ✓ selftest green ($(grep -c '^  ok' /tmp/nightly-reg-activate-selftest.log) assertions)"

# (1) enable — the missing step. Idempotent; a not-disabled label is a no-op.
echo "Will do: [1] launchctl enable gui/$UID_N/$LABEL"
launchctl enable "gui/$UID_N/$LABEL" 2>/dev/null || true

# (2) bootstrap — load it. Idempotent enough: an already-loaded label returns EEXIST(5), treated as ok.
echo "Will do: [2] launchctl bootstrap gui/$UID_N $PLIST"
rc=0; launchctl bootstrap "gui/$UID_N" "$PLIST" 2>/dev/null || rc=$?
case "$rc" in
  0) echo "  ✓ bootstrapped" ;;
  5) echo "  ✓ already loaded (EEXIST)" ;;
  *) echo "  ⚠ bootstrap returned $rc — check the verification below before assuming failure" ;;
esac

# ── verification: the job must be RESOLVABLE in the domain and no longer disabled ──
echo "── verify ──"
if launchctl print "gui/$UID_N/$LABEL" >/tmp/nightly-reg-activate-print.log 2>&1; then
  grep -E '^\s*(state|program|run interval|last exit code)' /tmp/nightly-reg-activate-print.log | head -6
  echo "  ✓ $LABEL is loaded in gui/$UID_N"
else
  echo "  ✗ still NOT loaded — read /tmp/nightly-reg-activate-print.log" >&2; exit 1
fi
if launchctl print-disabled "gui/$UID_N" 2>/dev/null | grep -q "\"$LABEL\" => disabled"; then
  echo "  ✗ still marked DISABLED — the enable in step 1 did not take" >&2; exit 1
fi
echo "  ✓ no longer in the disabled list"

echo
echo "✓ 22-nightly-regression ACTIVE — first run at the next 04:00 local."
echo "  It will create /tmp/claude-nightly-regression.stdout.log on that first run; the ABSENCE of"
echo "  that file after an 04:00 has passed is the tell that this activation silently did not hold."
echo "  Result line appends to ~/.claude/autonomy/regression.log ; a RED also writes"
echo "  ~/.claude/autonomy/pages/nightly-regression.page (cleared automatically on a green night)."
echo
echo "Mark done:  touch ${BASH_SOURCE[0]}.done"
