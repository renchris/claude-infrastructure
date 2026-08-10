#!/usr/bin/env bash
# backlog-ratchet.sh — the two standing numbers that make backlog rot VISIBLE before it is a pile.
#
# WHY THIS EXISTS. On 2026-08-09 a one-time triage adjudicated 460 open items and closed 161 of them
# as dead or absorbed — 35%. That pass cost ten agents and a night. The reason it was ever needed is
# that nothing measured the decay: no number moved as the store rotted, so the only signal was the
# operator eventually feeling the pain and asking for a heroic sweep. A sweep is not a mechanism.
# Without a standing measurement the next pile is invisible until it is the same size.
#
# THE TWO NUMBERS, and why exactly these:
#
#   falsifier coverage   — what fraction of open items can re-check themselves at claim time
#                          (`cc-backlog add --falsifier`, re-run by cc-premise). This is the ONLY
#                          property that makes an item self-validating rather than believed, so it
#                          is the leading indicator: coverage rising means future items cannot rot
#                          silently, whatever happens to the ones already filed.
#   age at close          — how long a closed item sat before somebody adjudicated it. The lagging
#                          indicator. Reported as MEDIAN **and p75**, and the pair is the point:
#                          measured on the live store 2026-08-10 the median is 0.1 days while p75 is
#                          2.2 and max is 19.7. A median-only report would have read "healthy" for
#                          exactly the population this script exists to catch, because most items
#                          are machine-generated and close within hours — they drown the human-filed
#                          tail where rot actually accumulates. Pick the statistic that can MOVE
#                          when the problem appears (MEMORY.md: alarm-polarity-and-attention-budget).
#
# WHY IT IS A CENSUS AND NOT (YET) A GATE. Coverage is currently near zero: the `--falsifier` field
# landed in a7bf7068 and no generator emits one yet (master M2 wires that). A gate armed today would
# red on every run, and an alarm that always fires carries exactly as many bits as one that never
# does (MEMORY.md: alarm-polarity-and-attention-budget) — it would be read past by the time it
# started meaning something. So: report always, and `--assert` blocks ONLY on a downward move
# against the recorded high-water mark. That arms itself the moment coverage becomes non-trivial,
# with no flag day and nothing to remember.
#
# NO COMMITTED BASELINE, deliberately. A checked-in expected-value file is a permanent exemption
# list wearing a number (the same failure test-hermeticity-lint's own comment warns a ratchet must
# never become). The high-water mark lives in a state file that is regenerated from the store, so
# losing it costs one run, never a wrong verdict.
#
# Usage:
#   backlog-ratchet.sh              census to stdout, always exit 0
#   backlog-ratchet.sh --json       machine-readable, for a hook or a dashboard
#   backlog-ratchet.sh --assert     exit 1 iff coverage fell below the high-water mark
set -uo pipefail

BACKLOG="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
STATE="${CC_RATCHET_STATE:-$HOME/.claude/autonomy/backlog-ratchet.json}"
MODE="census"
case "${1:-}" in
  --json)   MODE="json" ;;
  --assert) MODE="assert" ;;
  --help|-h) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
  "") : ;;
  *) printf 'backlog-ratchet: unknown arg %s\n' "$1" >&2; exit 2 ;;
esac

[ -f "$BACKLOG" ] || { printf 'backlog-ratchet: no store at %s — nothing to measure\n' "$BACKLOG" >&2; exit 0; }
command -v jq >/dev/null 2>&1 || { printf 'backlog-ratchet: jq missing — cannot measure (fail-open)\n' >&2; exit 0; }

# The FOLD, not the raw ledger: an item's current state is its last event, and `falsifier` is
# last-write-wins exactly as cc-premise reads it. Computing this from raw records would double-count
# every item that was ever touched twice.
read -r open_n fals_n closed_n median_age p75_age <<EOF
$(jq -rs '
  # fold: id -> {status, falsifier, first_ts, last_ts}
  (reduce .[] as $r ({};
     .[$r.id] //= {first: ($r.ts // ""), falsifier: "", status: "open"}
   | .[$r.id].last = ($r.ts // .[$r.id].last)
   | (if ($r.falsifier // "") != "" then .[$r.id].falsifier = $r.falsifier else . end)
   | (if ($r.event // "") == "done"  then .[$r.id].status = "done"
      elif ($r.event // "") == "block" then .[$r.id].status = "blocked"
      elif ($r.event // "") == "reopen" then .[$r.id].status = "open"
      elif ($r.event // "") == "claim"  then .[$r.id].status = "claimed"
      else . end)
  )) as $f
  | ([$f[] | select(.status == "open" or .status == "claimed")]) as $live
  | ([$live[] | select(.falsifier != "")]) as $covered
  | ([$f[] | select(.status == "done")
        | (((.last // "" | if . == "" then 0 else (sub("\\..*Z$";"Z") | fromdateiso8601? // 0) end)
           - (.first // "" | if . == "" then 0 else (sub("\\..*Z$";"Z") | fromdateiso8601? // 0) end)) / 86400)
        | select(. >= 0)] | sort) as $ages
  | "\($live|length) \($covered|length) \($ages|length) \(if ($ages|length) == 0 then 0 else ($ages[($ages|length)/2|floor] * 10 | round / 10) end) \(if ($ages|length) == 0 then 0 else ($ages[($ages|length)*3/4|floor] * 10 | round / 10) end)"
' "$BACKLOG" 2>/dev/null || echo "0 0 0 0 0")
EOF

open_n=${open_n:-0}; fals_n=${fals_n:-0}; closed_n=${closed_n:-0}; median_age=${median_age:-0}; p75_age=${p75_age:-0}
if [ "$open_n" -gt 0 ]; then
  coverage=$(awk -v a="$fals_n" -v b="$open_n" 'BEGIN{printf "%.1f", (a*100)/b}')
else
  coverage="0.0"
fi

prev="0.0"
[ -f "$STATE" ] && prev="$(jq -r '.coverage_high_water // "0.0"' "$STATE" 2>/dev/null || echo "0.0")"

# The high-water mark only ever RISES here. A fall is what --assert reports; recording the fall
# would silently re-baseline the ratchet to the regression, which is the one thing a ratchet exists
# to prevent.
if awk -v c="$coverage" -v p="$prev" 'BEGIN{exit !(c > p)}'; then
  mkdir -p "$(dirname "$STATE")" 2>/dev/null
  jq -nc --arg c "$coverage" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '{coverage_high_water:$c, recorded:$ts}' > "$STATE" 2>/dev/null || true
  prev_note="high-water RAISED to ${coverage}%"
else
  prev_note="high-water ${prev}% (unchanged)"
fi

case "$MODE" in
  json)
    jq -nc --arg open "$open_n" --arg cov "$coverage" --arg covered "$fals_n" \
       --arg closed "$closed_n" --arg med "$median_age" --arg p75 "$p75_age" --arg hw "$prev" \
       '{live_items:($open|tonumber), falsifier_covered:($covered|tonumber),
         falsifier_coverage_pct:($cov|tonumber), closed_items:($closed|tonumber),
         median_days_to_close:($med|tonumber), p75_days_to_close:($p75|tonumber), coverage_high_water:($hw|tonumber)}'
    ;;
  assert)
    printf 'backlog-ratchet: coverage %s%% (%s of %s live) · close median %sd p75 %sd over %s · %s\n' \
      "$coverage" "$fals_n" "$open_n" "$median_age" "$p75_age" "$closed_n" "$prev_note"
    if awk -v c="$coverage" -v p="$prev" 'BEGIN{exit !(c < p)}'; then
      printf 'backlog-ratchet: RED — falsifier coverage FELL from %s%% to %s%%.\n' "$prev" "$coverage" >&2
      printf '  Items are being filed that cannot re-check themselves, so the store is going back\n' >&2
      printf '  to being believed rather than measured. Add --falsifier to the generator that regressed.\n' >&2
      exit 1
    fi
    ;;
  *)
    printf 'backlog-ratchet — the two standing numbers\n'
    printf '  falsifier coverage : %s%% (%s of %s live items can re-check themselves)\n' "$coverage" "$fals_n" "$open_n"
    printf '  days to close       : median %s · p75 %s (over %s closed items)\n' "$median_age" "$p75_age" "$closed_n"
    printf '  %s\n' "$prev_note"
    if awk -v c="$coverage" 'BEGIN{exit !(c < 1)}'; then
      printf '\n  Coverage is near zero because --falsifier landed in a7bf7068 and no generator emits\n'
      printf '  one yet (master M2 wires that). This is a CENSUS until it does — see the header.\n'
    fi
    ;;
esac
exit 0
