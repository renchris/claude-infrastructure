#!/usr/bin/env bash
# handoff-alarm-polarity.sh — is ANY handoff alarm in the window being heard?
#
#   scripts/handoff-alarm-polarity.sh [--json]
#
# THE STATE IT CATCHES (RECYCLE_KEYSTROKELESS_DELIVERY §D3, 2026-10-09). hf_alarm writes a record and
# then pushes it, and keeps the push's outcome in a `<record>.verdict` sidecar: `reached` (a reader
# got it), `recorded` (it sits in a mailbox), `refused-rcN` (it went nowhere). All 24 verdicts ever
# recorded on this box were refused-rc3 — the `desk` role the push addressed did not exist — and
# nothing noticed, because each record was individually fine. Only the POPULATION shows that the
# channel is dead.
#
# POLARITY: this asks "is any of it green?", never "is it red?" (memory alarm-polarity-and-attention-
# budget, scripts/alarm-polarity-lint.sh). A record whose sidecar is missing or unreadable counts as
# NOT delivered — hf_alarm's own contract reads it as refused — so a new failure shape cannot hide in
# a state nobody named. RED = at least MIN records in the window and NONE of them reached a reader.
#
# Window and floor (env): CC_HANDOFF_ALARM_POLARITY_WINDOW_D (default 7 days, by the record's mtime),
# CC_HANDOFF_ALARM_POLARITY_MIN (default 5). Fewer records than the floor is an ABSTENTION, not green:
# four refusals are not yet a pattern, and an empty window says nothing about the channel.
#
# Exit: 0 green · 1 red · 3 abstain (too few records). One line on stdout carrying `verdict=`.
set -euo pipefail

dir="${CC_HANDOFF_ALARM_DIR:-$HOME/.claude/handoff-alarms}"
win_d="${CC_HANDOFF_ALARM_POLARITY_WINDOW_D:-7}"
min="${CC_HANDOFF_ALARM_POLARITY_MIN:-5}"
case "$win_d" in ''|*[!0-9]*|0) win_d=7 ;; esac
case "$min" in ''|*[!0-9]*|0) min=5 ;; esac
json=0
case "${1:-}" in
  --json) json=1 ;;
  '') ;;
  -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
  *) echo "handoff-alarm-polarity: unknown argument: $1" >&2; exit 2 ;;
esac

total=0 heard=0 refused=0 missing=0
if [ -d "$dir" ]; then
  # -mmin, not -mtime: -mtime rounds to whole 24 h units, which would widen the window by up to a day.
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    total=$((total + 1))
    v="$(head -1 "$rec.verdict" 2>/dev/null || true)"
    case "$v" in
      reached|recorded) heard=$((heard + 1)) ;;
      refused-*) refused=$((refused + 1)) ;;
      *) missing=$((missing + 1)) ;;
    esac
  done < <(find "$dir" -maxdepth 1 -type f -name 'alarm-*.json' -mmin "-$((win_d * 1440))" 2>/dev/null || true)
fi

if [ "$total" -lt "$min" ]; then verdict=abstain rc=3
elif [ "$heard" -eq 0 ]; then verdict=red rc=1
else verdict=green rc=0
fi

if [ "$json" = 1 ]; then
  printf '{"verdict":"%s","total":%s,"heard":%s,"refused":%s,"no_verdict":%s,"window_d":%s,"min":%s,"dir":"%s"}\n' \
    "$verdict" "$total" "$heard" "$refused" "$missing" "$win_d" "$min" "$dir"
else
  case "$verdict" in
    red)     what="NO handoff alarm in the last ${win_d}d reached a reader — the alarm channel is dead" ;;
    green)   what="$heard of $total handoff alarm(s) in the last ${win_d}d reached a reader" ;;
    abstain) what="only $total handoff alarm(s) in the last ${win_d}d (floor $min) — too few to judge the channel" ;;
  esac
  printf 'handoff-alarm-polarity verdict=%s total=%s heard=%s refused=%s no_verdict=%s window=%sd — %s\n' \
    "$verdict" "$total" "$heard" "$refused" "$missing" "$win_d" "$what"
fi
exit "$rc"
