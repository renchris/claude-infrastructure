#!/bin/bash
# W0 PROBE — the SessionStart hook body, declared with asyncRewake:true.
#
# Hypothesis under test: the harness runs this in the background at session birth
# (asyncRewake "implies async"), it outlives the birth turn, and when it exits 2 the
# harness WAKES the model — i.e. an external file write reaches a genuinely idle
# session with ZERO model participation. If true, the wake path becomes mechanical
# and the "only the model can arm its own watcher" premise is false.
#
# Paths are hardcoded: a hook subprocess is not guaranteed to inherit our env.
P=/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/a78e659d-921a-49ca-9357-b67791e3aee3/scratchpad/w0probe
LOG="$P/watch.log"
MAIL="$P/mail.txt"

ts() { date -u +%H:%M:%S; }

# START-time evidence, not exit-time: if the harness SIGKILLs this watcher at turn
# end, an exit-time-only log would be absent for exactly the death we most need to
# see, and "never started" would be indistinguishable from "started then reaped".
echo "$(ts) START pid=$$ ppid=$PPID cwd=$PWD" >> "$LOG"

touch "$MAIL" 2>/dev/null || true
# `grep -c ''` prints 0 AND exits 1 on an empty file, so `|| echo 0` appends a SECOND
# zero and base becomes "0\n0" — after which every `-gt` is an "integer expression
# expected" error and the watcher can never fire. awk gives one line and exit 0 always.
nlines() { awk 'END{print NR+0}' "$1" 2>/dev/null || echo 0; }
base="$(nlines "$MAIL")"
echo "$(ts) baseline=$base" >> "$LOG"

i=0
while [ "$i" -lt 150 ]; do
  # Liveness breadcrumb every ~10 polls so a reap is visible as a STOPPED heartbeat,
  # separating "watcher died silently" from "watcher alive but wake never delivered".
  if [ $((i % 10)) -eq 0 ]; then echo "$(ts) alive poll=$i" >> "$LOG"; fi

  cur="$(nlines "$MAIL")"
  if [ "$cur" -gt "$base" ]; then
    body="$(tail -n +"$((base + 1))" "$MAIL" 2>/dev/null | tr '\n' ' ')"
    echo "$(ts) FIRE body=[$body] — exiting 2 now" >> "$LOG"
    # Emit on BOTH streams: the schema says the hook output is appended after the
    # rewakeMessage prefix but does not say which stream carries it.
    echo "W0-PROBE-WAKE-STDOUT: $body"
    echo "W0-PROBE-WAKE-STDERR: $body" >&2
    exit 2
  fi
  sleep 2
  i=$((i + 1))
done

echo "$(ts) TIMEOUT after $i polls — no mail arrived" >> "$LOG"
exit 0
