#!/bin/bash
# T9 INSTRUMENT 2 — the asyncRewake Stop hook, copied in shape from
# docs/research/w2-stop-rewake-proof/watcher.sh (which proved this mechanism at a NORMAL Stop).
LOG="/private/tmp/claude-501/-Users-chrisren-Development--worktrees-wt-4236edc78a72/23a9a12e-c3c9-4672-b8a8-92e6831618e7/scratchpad/t9probe/watch.log"; MAIL="/private/tmp/claude-501/-Users-chrisren-Development--worktrees-wt-4236edc78a72/23a9a12e-c3c9-4672-b8a8-92e6831618e7/scratchpad/t9probe/mail.txt"
ts() { date -u +%H:%M:%S; }
echo "$(ts) WATCHER-START pid=$$ ppid=$PPID arm=${T9_ARM:-unset}" >> "$LOG"
cat >/dev/null 2>&1 & _c=$!
touch "$MAIL" 2>/dev/null || true
nlines() { awk 'END{print NR+0}' "$1" 2>/dev/null || echo 0; }
base="$(nlines "$MAIL")"
i=0
while [ "$i" -lt 40 ]; do
  cur="$(nlines "$MAIL")"
  if [ "$cur" -gt "$base" ]; then
    body="$(tail -n +"$((base + 1))" "$MAIL" 2>/dev/null | tr '\n' ' ')"
    echo "$(ts) WATCHER-FIRE body=[$body] exiting 2" >> "$LOG"
    echo "T9-PROBE-WAKE: $body" >&2
    kill "$_c" 2>/dev/null; exit 2
  fi
  sleep 2; i=$((i + 1))
done
echo "$(ts) WATCHER-TIMEOUT" >> "$LOG"; kill "$_c" 2>/dev/null; exit 0
