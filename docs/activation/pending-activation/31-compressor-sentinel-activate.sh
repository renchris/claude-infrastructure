#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 31-compressor-sentinel  —  put a guard on the axis that has panicked this box three times in six days
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: four idempotent steps. (1) bounded smoke run against a /tmp log — three ticks, real sysctls,
#   nothing written to the operator's live telemetry. (2) symlink the script into the live
#   ~/.claude/scripts/ layer if absent — a BRAND-NEW file is never auto-linked by a per-file symlink
#   dir (memory deploy-lag-checkout-behind-origin). (3) load com.claude.compressor-sentinel
#   (KeepAlive, RunAtLoad, NO ProcessType). (4) VERIFY a real row lands in the live JSONL within 30 s.
#
# WHY STEP 4 IS NOT OPTIONAL. Every previous sensor on this axis shipped green and moved nothing:
#   capacity-alarm ran for weeks with three rungs dead because its launchd PATH omitted /usr/sbin, and
#   nothing ever asked whether a row had actually landed. `launchctl bootstrap` returning 0 proves
#   launchd accepted a plist, not that the daemon can read the machine. The 30 s wait is the only step
#   here that can distinguish those two, and this daemon's first tick is immediate (RunAtLoad, no
#   StartInterval), so 30 s against a 10 s cadence is ~3 chances — a failure at 30 s is real.
#
# WHY THE ACTUATOR IS NOT ARMED HERE. CC_SENTINEL_ACT stays unset, so the job is detection-only:
#   JSONL rows, a snapshot log, and a page on trip. Arming it (SIGSTOP of the burst cohort, research
#   §7.2) means a daemon acting on live processes unasked — an operator decision made by adding
#   CC_SENTINEL_ACT=stop to the plist's wrapper, deliberately not folded into activation.
#
# WHY C10 (agent stages; operator loads): loading a launchd job IS an activation.
# Kill after load:  launchctl bootout gui/$UID/com.claude.compressor-sentinel.
# Mark done:  touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
PLIST="com.claude.compressor-sentinel.plist"
LABEL="com.claude.compressor-sentinel"
SENTINEL="$REPO/scripts/compressor-sentinel.sh"
LA="$HOME/Library/LaunchAgents"
LIVE_LOG="$HOME/.claude/logs/compressor-sentinel.jsonl"

echo "== 31-compressor-sentinel =="
[ -f "$SENTINEL" ] || { echo "✗ missing in checkout: $SENTINEL (is the checkout on a trunk with this commit?)" >&2; exit 1; }
[ -f "$REPO/launchd/$PLIST" ] || { echo "✗ missing plist: $REPO/launchd/$PLIST" >&2; exit 1; }

echo "Will do: [0] 3-tick smoke against a /tmp log (must emit 3 parseable rows; live log untouched)"
echo "         [1] symlink the script → \$HOME/.claude/scripts/ (if not already linked)"
echo "         [2a] REFUSE if the interim v1 sentinel is still writing $LIVE_LOG"
echo "         [2] cp launchd/$PLIST → $LA/ ; plutil -lint ; launchctl enable ; launchctl bootstrap"
echo "         [3] VERIFY a row of THIS daemon's shape lands in $LIVE_LOG within 30 s"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  _pfx=""; [ -n "${CC_REPO+set}" ] && _pfx="CC_REPO=$REPO "
  echo "    CONFIRM=1 ${_pfx}bash $HOME/.claude/autonomy/pending-activation/31-compressor-sentinel-activate.sh"
  exit 0
fi

# [0] The smoke, BEFORE anything is linked or loaded — and pointed at /tmp, because the sentinel's
# default log IS the artifact step 3 verifies. Smoking into the live log would seed the very file the
# verification reads, and the check would then pass on its own side effect.
echo "[0] smoke (3 ticks, /tmp log, live telemetry untouched)"
SMOKE="$(mktemp -t compressor-sentinel-smoke).jsonl"
if ! CC_SENTINEL_LOG="$SMOKE" CC_SENTINEL_INTERVAL=2 bash "$SENTINEL" --ticks 3; then
  echo "✗ smoke run exited non-zero — NOT activating (exit 3 means it could not read the machine)" >&2
  rm -f "$SMOKE"; exit 1
fi
SMOKE_ROWS="$(wc -l < "$SMOKE" | tr -d ' ')"
if [ "${SMOKE_ROWS:-0}" -lt 3 ]; then
  echo "✗ smoke emitted $SMOKE_ROWS rows, expected 3 — NOT activating" >&2
  rm -f "$SMOKE"; exit 1
fi
# A row that is not parseable JSON is the defect this daemon's own smoke already caught once (a census
# field emitted three bare values under one key). Assert the DOCUMENT parses, never just a field grep.
if command -v python3 >/dev/null 2>&1; then
  if ! python3 -c 'import json,sys
[json.loads(l) for l in open(sys.argv[1]) if l.strip()]' "$SMOKE"; then
    echo "✗ smoke rows are not parseable JSON — NOT activating" >&2
    rm -f "$SMOKE"; exit 1
  fi
  echo "  · $SMOKE_ROWS rows, all parse as JSON"
else
  echo "  · $SMOKE_ROWS rows (python3 absent — JSON parse check SKIPPED, not passed)"
fi
rm -f "$SMOKE"

echo "[1] symlink"
DEST="$HOME/.claude/scripts/$(basename "$SENTINEL")"
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "✗ $DEST exists and is NOT a symlink — refusing to clobber a real file" >&2; exit 1
fi
mkdir -p "$HOME/.claude/scripts"
ln -sfn "$SENTINEL" "$DEST"
echo "  · $DEST → $(readlink "$DEST")"

# [2a] THE INTERIM v1 MUST BE GONE FIRST, and this check is not housekeeping — it is what stops
# step 3 from passing on someone else's rows. Research §7.1 shipped a hand-run interim sentinel this
# session (observed live at activation-authoring time: pid 81989, `compressor-sentinel-v1.sh` out of
# a session scratchpad, appending to THIS SAME PATH every 10 s with a different, 5-key schema). Two
# writers on one JSONL is a corrupt series for every consumer — and a line-count-based verification
# would have read v1's heartbeat as proof that the new daemon works. Refuse, do not race.
echo "[2a] checking for a foreign writer on $LIVE_LOG"
# shellcheck disable=SC2009  # pgrep cannot do this: the ARGV is what discriminates our own daemon
# from a foreign one, and macOS pgrep -f matches a TRUNCATED argv (capacity-alarm.sh:231 measured it
# returning 0 against a real 8) — so the path prefixes excluded below would never match.
FOREIGN="$(ps -Awwo pid=,args= 2>/dev/null | grep -i 'compressor-sentinel' \
           | grep -v -e 'grep' -e "$SENTINEL" -e "$HOME/.claude/scripts/compressor-sentinel.sh" || true)"
if [ -n "$FOREIGN" ]; then
  echo "✗ another compressor-sentinel is already running and writing that log:" >&2
  printf '    %s\n' "$FOREIGN" >&2
  echo "  Stop it first (it is the interim v1 from research §7.1; this daemon supersedes it), then" >&2
  echo "  re-run. Do NOT run both: one JSONL with two schemas is unreadable, and the verification" >&2
  echo "  in step 3 cannot tell whose row it is looking at." >&2
  exit 1
fi
echo "  · none"

echo "[2] launchd"
mkdir -p "$LA"
cp -f "$REPO/launchd/$PLIST" "$LA/$PLIST"
plutil -lint "$LA/$PLIST" || { echo "✗ plist lint failed" >&2; exit 1; }
launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LA/$PLIST" || { echo "✗ bootstrap failed" >&2; exit 1; }
launchctl print "gui/$(id -u)/$LABEL" | grep -E 'state|last exit' | head -3 || true

# [3] The step that separates "launchd accepted a plist" from "the daemon can read this machine".
echo "[3] verifying a live row within 30 s"
BEFORE=0
[ -f "$LIVE_LOG" ] && BEFORE="$(wc -l < "$LIVE_LOG" | tr -d ' ')"
# A GROWN LINE COUNT IS NOT PROOF. Any writer on this path grows it, which is exactly how the
# interim v1 would have certified this activation without the new daemon emitting anything at all.
# So the check is on the row's SHAPE: `segi` (in-core segments) is this daemon's schema and appears
# in no other writer's. Parse the document too — a field grep passes against a row no consumer can read.
LANDED=0
for _ in $(seq 1 30); do
  sleep 1
  [ -f "$LIVE_LOG" ] || continue
  AFTER="$(wc -l < "$LIVE_LOG" | tr -d ' ')"
  [ "${AFTER:-0}" -gt "${BEFORE:-0}" ] || continue
  if tail -1 "$LIVE_LOG" | grep -q '"segi":'; then LANDED=1; break; fi
done
if [ "$LANDED" = 1 ] && command -v python3 >/dev/null 2>&1; then
  if ! tail -1 "$LIVE_LOG" | python3 -c 'import json,sys; json.loads(sys.stdin.read())'; then
    echo "✗ a row landed but is NOT parseable JSON — NOT activated" >&2; exit 1
  fi
fi
if [ "$LANDED" != 1 ]; then
  echo "✗ NO row of THIS daemon's shape landed in $LIVE_LOG within 30 s (a row from another writer" >&2
  echo "  does not count). The job is loaded but BLIND — do not treat this as" >&2
  echo "  activated. First place to look: /tmp/claude-compressor-sentinel.stderr.log (a SKIP line names" >&2
  echo "  the unreadable sysctl; silence there means the wrapper's PATH is wrong — /usr/sbin holds sysctl)." >&2
  exit 1
fi
echo "  · row landed:"
tail -1 "$LIVE_LOG" | sed 's/^/    /'

echo
echo "DONE. Flip launchd/fleet.manifest's row from \`staged\` to \`run\` — leaving it staged after"
echo "activating makes cc-fleet emit a permanent UNDECIDED row for a job that IS scheduled."
echo "Verify later:  tail -3 $LIVE_LOG            (a row every ~10 s)"
echo "               tail -40 ${LIVE_LOG%.jsonl}-snap.log   (only ever written on a TRIP)"
echo "The actuator is DISARMED. To arm it, add CC_SENTINEL_ACT=stop to the plist wrapper and reload;"
echo "it then SIGSTOPs (never SIGKILLs) the burst cohort on trip, excluding claude.exe and anything"
echo "claude/mcp-shaped. That is a real behaviour change on live processes — read research §7.2 first."
echo "Then:  touch $HOME/.claude/autonomy/pending-activation/31-compressor-sentinel-activate.sh.done"
