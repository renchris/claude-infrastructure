#!/bin/bash
# W2 PROBE — the STOP hook body, declared with asyncRewake:true.
#
# Hypothesis under test (P-W2a/P-W2b): a Stop-declared asyncRewake hook is dispatched ASYNC — it does
# not block and does not delay the stop — and its exit 2 while the session is idle synthesizes a WAKE
# rather than being read as Stop's overloaded "block" code.
#
# Paths are hardcoded: a hook subprocess is not guaranteed to inherit our env.
P=/tmp/claude-0/-home-user-claude-infrastructure/c2fd69c8-bfa1-5c16-ad4b-aa2115a3feef/scratchpad/w2probe
LOG="$P/watch.log"
MAIL="$P/mail.txt"

ts() { date -u +%H:%M:%S; }

# START-time evidence, not exit-time (W0's rule): if the harness reaps this at stop-end, an
# exit-time-only log cannot distinguish "never started" from "started then reaped".
echo "$(ts) START pid=$$ ppid=$PPID cwd=$PWD" >> "$LOG"

# Consume stdin so the harness never SIGPIPEs us (same discipline as the real adapter).
cat >/dev/null 2>&1 &
_c=$!

touch "$MAIL" 2>/dev/null || true
nlines() { awk 'END{print NR+0}' "$1" 2>/dev/null || echo 0; }
base="$(nlines "$MAIL")"
echo "$(ts) baseline=$base" >> "$LOG"

i=0
while [ "$i" -lt 150 ]; do
  if [ $((i % 5)) -eq 0 ]; then echo "$(ts) alive poll=$i" >> "$LOG"; fi
  cur="$(nlines "$MAIL")"
  if [ "$cur" -gt "$base" ]; then
    body="$(tail -n +"$((base + 1))" "$MAIL" 2>/dev/null | tr '\n' ' ')"
    echo "$(ts) FIRE body=[$body] — exiting 2 now" >> "$LOG"
    echo "W2-PROBE-WAKE-STDOUT: $body"
    echo "W2-PROBE-WAKE-STDERR: $body" >&2
    kill "$_c" 2>/dev/null
    exit 2
  fi
  sleep 2
  i=$((i + 1))
done

echo "$(ts) TIMEOUT after $i polls — no mail arrived" >> "$LOG"
kill "$_c" 2>/dev/null
exit 0
