#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 35-auth-timeseries  —  put the per-account auth recorder on a 5-min cadence
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: three idempotent steps. (0) hand-run ONE --once batch and REFUSE to arm unless it produced
#   readable credential rows. (1) symlink tools/auth/auth-timeseries.sh into the live
#   ~/.claude/scripts/ layer — `tools/` is not a deployed directory at all, so this file has no
#   symlink and the plist's exec target does not exist until this step runs. (2) load
#   com.claude.auth-timeseries (StartInterval 300, RunAtLoad false, Background/Nice 10).
#
# WHY: tools/auth/auth-timeseries.sh is the only instrument that can see a refresh-token ROTATION
#   or the moment a credential goes EMPTY — which is what a forced logout looks like from outside.
#   But it was manual and time-bounded (a 6h ad-hoc run to a caller-supplied path), nothing
#   scheduled it, and no durable store accumulated. So every observation died with the session
#   that made it, and the forced-logout investigation could only ever run in retrospect on an
#   event that had left no trace. MASTER M6 (backlog b22e519e06cb), DoD 2.
#
# 🚨 WHY STEP 0 IS A GATE AND NOT A SMOKE TEST. `security find-generic-password -w` is subject to
#   the keychain item's ACL, and under launchd there is no interactive session to answer an
#   "allow access" dialog. The sampler deliberately swallows per-item errors (one unreadable item
#   must not abort a batch), so an ACL denial renders as a clean run of NO_ITEM rows — a FALSE
#   "the credential is gone" on every account at once, which is precisely the signal this
#   instrument exists to detect. A recorder that lies in exactly its own subject is worse than no
#   recorder. So: run it first, and arm only on OK.
#
# WHY C10 (agent stages; operator loads): loading a launchd job IS an activation, and only a human
#   can settle the ACL question above.
# Kill after load: launchctl bootout gui/$UID/com.claude.auth-timeseries
# Mark done:  touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
LABEL="com.claude.auth-timeseries"
PLIST="$LABEL.plist"
SRC="$REPO/tools/auth/auth-timeseries.sh"
DEST="$HOME/.claude/scripts/auth-timeseries.sh"
STORE="${AUTH_TS_OUT:-$HOME/.claude/logs/auth-timeseries.jsonl}"
LA="$HOME/Library/LaunchAgents"

echo "== 35-auth-timeseries =="
[ -f "$SRC" ] || { echo "✗ missing in checkout: $SRC (is the checkout on a trunk with this commit?)" >&2; exit 1; }
[ -f "$REPO/launchd/$PLIST" ] || { echo "✗ missing plist: $REPO/launchd/$PLIST" >&2; exit 1; }

echo "Will do: [0] run $SRC --once to a SCRATCH path with no controlling tty, and refuse to arm"
echo "             unless it produced readable rows (the keychain-ACL gate)"
echo "         [1] symlink $SRC → $DEST (tools/ is NOT a deployed dir — no link exists today)"
echo "         [2] cp launchd/$PLIST → $LA/ ; plutil -lint ; launchctl enable ; launchctl bootstrap"
echo "         store: $STORE  (rotated by rotate-autonomy-logs.sh, bounded by store-bounds.manifest)"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  _pfx=""; [ -n "${CC_REPO+set}" ] && _pfx="CC_REPO=$REPO "
  echo "    CONFIRM=1 ${_pfx}bash $REPO/docs/activation/pending-activation/35-auth-timeseries-activate.sh"
  exit 0
fi

echo "[0] keychain-ACL gate — one --once batch, detached from this terminal"
probe="$(mktemp -t auth-ts-probe)" || { echo "✗ mktemp failed" >&2; exit 1; }
# `setsid` is not on macOS; `</dev/null` plus a background job is the portable way to run this
# without a controlling tty, which is the condition launchd will impose.
AUTH_TS_OUT="$probe" bash "$SRC" --once </dev/null >/dev/null 2>"$probe.err" &
wait $! ; rc=$?
if [ "$rc" = 3 ]; then
  echo "✗ NO-DATA: the sampler appended zero rows with no tty. This is the ACL denial the header" >&2
  echo "  describes. Grant /usr/bin/security access to the 'Claude Code-credentials-*' items in" >&2
  echo "  Keychain Access, or run this script from a session that can answer the dialog once." >&2
  echo "  stderr: $(cat "$probe.err" 2>/dev/null)" >&2
  rm -f "$probe" "$probe.err"; exit 1
fi
ok=$(grep -c '"state":"OK"' "$probe" 2>/dev/null || echo 0)
noitem=$(grep -c '"state":"NO_ITEM"' "$probe" 2>/dev/null || echo 0)
rows=$(wc -l < "$probe" 2>/dev/null || echo 0)
echo "  · $rows rows, $ok OK, $noitem NO_ITEM (exit $rc)"
if [ "$ok" -lt 1 ]; then
  echo "✗ not one readable credential without a tty — refusing to arm a recorder that would" >&2
  echo "  report every account as logged-out. See the ACL note above." >&2
  rm -f "$probe" "$probe.err"; exit 1
fi
rm -f "$probe" "$probe.err"

echo "[1] symlink"
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "✗ $DEST exists and is NOT a symlink — refusing to clobber a real file" >&2; exit 1
fi
mkdir -p "$(dirname "$DEST")"
ln -sfn "$SRC" "$DEST"
echo "  · $DEST → $(readlink "$DEST")"
[ -x "$DEST" ] || { echo "✗ $DEST is not executable — the plist would fail every tick" >&2; exit 1; }

echo "[2] launchd"
mkdir -p "$LA"
cp -f "$REPO/launchd/$PLIST" "$LA/$PLIST"
plutil -lint "$LA/$PLIST" || { echo "✗ plist lint failed" >&2; exit 1; }
launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LA/$PLIST" || { echo "✗ bootstrap failed" >&2; exit 1; }
launchctl print "gui/$(id -u)/$LABEL" | grep -E 'state|last exit' | head -3 || true

echo
echo "DONE. Verify in ~10 min:  tail -6 $STORE   (6 rows every ~300 s)"
echo "Then flip launchd/fleet.manifest's row for $LABEL from 'staged' to 'run', so cc-fleet"
echo "starts holding it to the full state function instead of reporting it UNDECIDED."
echo "Then:  touch $REPO/docs/activation/pending-activation/35-auth-timeseries-activate.sh.done"
