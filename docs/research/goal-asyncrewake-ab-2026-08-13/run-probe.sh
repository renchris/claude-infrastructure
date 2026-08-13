#!/bin/bash
# run-probe.sh <async|parked|parked-long> — drive ONE hermetic arm of the 0007 A/B.
#
# The three arms differ in exactly one variable: HOW the same poll-the-mailbox watcher is
# registered. Everything else — the goal condition, the Stop oracle, the model, the config dir
# shape — is identical, which is what makes the comparison a controlled one.
#
#   async        the watcher is a SessionStart hook with "asyncRewake": true   (migration 0007)
#   parked       the model launches the watcher itself as a background Bash    (the pre-0007 habit)
#   parked-long  same, with a task that outlives several Stops                 (the strong control)
#
# Requires: PROBE_ROOT (a scratch dir) and CC_BIN (the claude binary under test). Auth is inherited
# from the invoking environment — a hermetic CLAUDE_CONFIG_DIR carries no credentials of its own,
# which is the trap the W0 bundle hit (docs/research/w0-asyncrewake-proof/README.md).
set -uo pipefail

MODE="${1:?usage: run-probe.sh <async|parked|parked-long>}"
ROOT="${PROBE_ROOT:?set PROBE_ROOT to a scratch directory}"
CC_BIN="${CC_BIN:-claude}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ARM="$ROOT/$MODE"

# The condition is deliberately UNMET and its truth lives OUTSIDE the session, so every evaluation
# returns met=false and the count of evaluations is the signal. "never create it yourself" is what
# stops the subject satisfying its own goal and ending the series early.
COND='the file /tmp/probe-approval.txt contains the line APPROVED — only the operator writes that file; never create or edit it yourself'

rm -rf "$ARM"; mkdir -p "$ARM/cfg" "$ARM/work"
: > "$ARM/mail.txt"; : > "$ARM/watcher.log"; : > "$ARM/stop.log"
rm -f /tmp/probe-approval.txt

# ── settings: the Stop oracle is in EVERY arm; the SessionStart watcher only in `async` ──────────
# stop-probe.sh records CC's own `background_tasks` population at each Stop. That population is the
# very predicate CC's deferral consults, handed to every Stop hook (YTe @237761), so it is the
# registry read the whole A/B turns on — not an inference from `ps`.
perms='{"allow":["Bash","Read","Write"],"defaultMode":"acceptEdits"}'
stop="[{\"hooks\":[{\"type\":\"command\",\"command\":\"$HERE/stop-probe.sh\",\"timeout\":20}]}]"
if [ "$MODE" = async ]; then
  ss="[{\"hooks\":[{\"type\":\"command\",\"command\":\"$HERE/watcher.sh\",\"timeout\":300,\"asyncRewake\":true,\"rewakeMessage\":\"📬 PROBE mail arrived while you were idle:\",\"rewakeSummary\":\"📬 probe mail\"}]}]"
  printf '{"permissions":%s,"hooks":{"SessionStart":%s,"Stop":%s}}\n' "$perms" "$ss" "$stop" > "$ARM/cfg/settings.json"
else
  printf '{"permissions":%s,"hooks":{"Stop":%s}}\n' "$perms" "$stop" > "$ARM/cfg/settings.json"
fi
jq -e . "$ARM/cfg/settings.json" >/dev/null || { echo "bad settings" >&2; exit 1; }

# ── the input script, as stream-json user messages ───────────────────────────────────────────────
# --input-format stream-json is not a convenience: it makes hasStreamingInput true, which is the `K`
# half of the 2.1.220+ dispatch gate `(e.async || e.asyncRewake && K) && !d`. In a plain one-shot
# `claude -p`, K is false and an asyncRewake hook is dispatched SYNCHRONOUSLY — the arm would
# measure a blocked birth rather than the mechanism.
emit() { jq -Rn --arg t "$1" '{type:"user",message:{role:"user",content:$t}}'; }
drive() {
  emit "/goal $COND"; sleep 25
  case "$MODE" in
    parked)
      emit "Run exactly this as a Bash tool call with run_in_background=true, then reply BGPARKED: until grep -q PROBE-WAKE $ARM/mail.txt; do sleep 2; done; echo MAIL-ARRIVED"
      sleep 40 ;;
    parked-long)
      emit "Run exactly this as a Bash tool call with run_in_background=true, then reply BGPARKED: sleep 240"
      sleep 35 ;;
  esac
  case "$MODE" in
    parked-long) for n in 1 2 3 4; do emit "reply with exactly: TICK-$n"; sleep 30; done ;;
    *)
      emit "reply with exactly: TICK"; sleep 90
      # The external write: a single append from an unrelated shell, zero model participation.
      echo "PROBE-WAKE-LINE $(date -Is)" >> "$ARM/mail.txt"
      sleep 80 ;;
  esac
}

export CLAUDE_CONFIG_DIR="$ARM/cfg"
export CLAUDE_CODE_STOP_HOOK_BLOCK_CAP="${CAP:-3}"   # bound the unmet-goal block series
export PROBE_MAIL="$ARM/mail.txt" PROBE_WLOG="$ARM/watcher.log" PROBE_SLOG="$ARM/stop.log"
# A nested session inherits the parent's session id and would write into the PARENT's transcript.
unset CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_REMOTE_SESSION_ID

cd "$ARM/work" || exit 1
drive | timeout "${TMO:-290}" "$CC_BIN" -p \
  --input-format stream-json --output-format stream-json --verbose \
  > "$ARM/stream.jsonl" 2> "$ARM/err.txt"
echo "$MODE done rc=$? $(date -Is)"
