#!/bin/bash
# probe watcher — the asyncRewake hook body. Polls MAIL; on a new line prints it to STDERR and
# exits 2 (the asyncRewake wake code). stdin is fully consumed first so the harness never SIGPIPEs.
set -uo pipefail
MAIL="${PROBE_MAIL:?}"; LOG="${PROBE_WLOG:?}"
cat >/dev/null 2>&1 || true
nlines() { c=$(grep -c '' "$1" 2>/dev/null); case "$c" in ''|*[!0-9]*) c=0;; esac; printf '%s' "$c"; }
base="$(nlines "$MAIL")"
printf 'START pid=%s base=%s %s\n' "$$" "$base" "$(date -Is)" >> "$LOG"
i=0
while [ "$i" -lt "${PROBE_POLLS:-240}" ]; do
  i=$(( i + 1 ))
  n="$(nlines "$MAIL")"
  if [ "$n" -gt "$base" ]; then
    printf 'FIRE poll=%s %s\n' "$i" "$(date -Is)" >> "$LOG"
    tail -n +$(( base + 1 )) "$MAIL" >&2
    exit 2
  fi
  [ $(( i % 10 )) -eq 0 ] && printf 'alive poll=%s %s\n' "$i" "$(date -Is)" >> "$LOG"
  sleep 1
done
printf 'TIMEOUT %s\n' "$(date -Is)" >> "$LOG"
exit 0
