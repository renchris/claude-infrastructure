#!/bin/bash
# P-W2d — an ORDINARY (synchronous) Stop hook that blocks EXACTLY ONCE, declared in the same Stop
# group as the asyncRewake watcher. The spec flagged one open question: does a same-Stop
# decision:"block" interact with the backgrounded rewake hook (swallow it, delay it, or be swallowed
# by it)? Marker-guarded so it can never loop.
P=/tmp/claude-0/-home-user-claude-infrastructure/c2fd69c8-bfa1-5c16-ad4b-aa2115a3feef/scratchpad/w2probe
cat >/dev/null 2>&1
if [ -f "$P/.blocked-once" ]; then
  exit 0
fi
: > "$P/.blocked-once"
echo "$(date -u +%H:%M:%S) BLOCKER fired (first stop only)" >> "$P/watch.log"
printf '{"decision":"block","reason":"W2-PROBE-BLOCK: say exactly PROBE-TURN-2 and nothing else."}\n'
exit 0
