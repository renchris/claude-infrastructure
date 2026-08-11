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
# ── 2026-08-11 · THE RATCHET WAS DEAD, AND HAD NEVER ONCE BEEN GREEN (READINESS W0) ──────────────
# Measured on the live store: `coverage_high_water` sat at **100.0%** while live coverage was 51.5%,
# so `--assert` returned rc=1 on EVERY run, and all 3 `ratchet_rc` values `autonomy-sweep` had ever
# journalled were `"1"` — which the sweep documents as "ratchet saw coverage FALL". The alarm this
# file exists to be had degenerated into the exact defect its own header warns about two paragraphs
# up: one that always fires carries as many bits as one that cannot. Backlog coverage decayed from
# 32.5% to 28.7% across a single day with nothing to show for it, because the only instrument
# watching had been red the whole time and nobody could tell that read from any other.
#
# Two independent causes, and BOTH had to be fixed for either to matter:
#
#   1. THE TARGET WAS UNREACHABLE. 100% coverage is not an attainable state of this population and
#      never was: the 2026-08-11 CURRENCY pass deliberately left 103 items unprobed (investigations,
#      design calls, multi-part conditions a single token would half-retract), and the `needs` class
#      has no machine oracle at all — its `--run` PERFORMS the operator step, so running it as a
#      probe would execute the thing it tests. A high-water the population cannot reach makes GREEN
#      structurally impossible, so the ratchet can only ever be red. Hence CEILING below: prove the
#      healthy event CAN happen before you let a number latch as the target
#      (MEMORY.md: cap-whose-population-is-empty).
#   2. THE TARGET WAS RECORDED FROM A POPULATION NOBODY VERSIONED. Whatever read produced 100.0%,
#      nothing in the state file said WHAT had been counted, so no later run could tell a genuine
#      regression from a change of denominator. `denominator_version` fixes that permanently.
#
# ⚠️ A THIRD CAUSE WAS PROPOSED HERE AND MEASURED FALSE — recorded because the mistake is the
# instructive part. The first draft of this fix asserted that "168 open `needs` rows sit in `live`
# and dilute a firing-readiness metric they are not part of", and added `$probeable` to remove them.
# Measured against the fold: **`needs` rows are born BLOCKED** (bin/cc-backlog:544 — the verb
# deliberately files them blocked and skips the dispatch kick), so `live` = open ∨ claimed had
# ALREADY excluded 167 of the 168; the exclusion removes **zero** rows today and the coverage number
# never moved. The 505-row figure that motivated it came from `cc-backlog list --open`, whose
# projection INCLUDES 198 blocked rows — so the denominator under suspicion was the analyst's, not
# this script's. Correct numbers: 304 open + 3 claimed = 307, of which 157 carry a probe.
# `$probeable` is KEPT as defence-in-depth — one `needs` row is currently open, proving a reopen can
# put the class back into `live` — but it is a guard against a future reclassification, NOT a fix for
# a present dilution, and the census prints the excluded count so it can never again be assumed
# non-zero (MEMORY.md: positive-control-the-denominator, committed here by the person invoking it).
#
# WHY A DENOMINATOR VERSION RATHER THAN A QUIET RE-BASELINE. Changing what is counted makes the old
# high-water incomparable, not merely stale — and silently re-baselining is the one thing a ratchet
# must never do (the very next paragraph of this header). `denominator_version` in the state file
# makes the reset an explicit, dated event: a version bump resets the mark and SAYS SO, while a fall
# under an unchanged version still reds exactly as before.
#
# Usage:
#   backlog-ratchet.sh              census to stdout, always exit 0
#   backlog-ratchet.sh --json       machine-readable, for a hook or a dashboard
#   backlog-ratchet.sh --assert     exit 1 iff coverage fell below the high-water mark
#
# Knobs (all defaulted; each exists because an unguarded latch is how this file died once):
#   CC_RATCHET_MAX_HW   ceiling on a recordable high-water   (default 95.0 — 100 is unreachable)
#   CC_RATCHET_MIN_N    floor on the denominator that may set one (default 20 — a degenerate
#                       read of 1-of-1 must never latch 100% as the fleet's target)
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
read -r open_n probe_n fals_n closed_n median_age p75_age <<EOF
$(jq -rs '
  # fold: id -> {status, falsifier, source, first_ts, last_ts}
  (reduce .[] as $r ({};
     .[$r.id] //= {first: ($r.ts // ""), falsifier: "", source: "", status: "open"}
   | .[$r.id].last = ($r.ts // .[$r.id].last)
   | (if ($r.falsifier // "") != "" then .[$r.id].falsifier = $r.falsifier else . end)
   # LAST-NON-EMPTY-WINS, matching the falsifier arm above and cc-premise build_index. `source` is
   # written by `add` and carried forward, but a later record may restate it; an empty one never
   # erases a known class, because that would silently move a row back INTO the denominator.
   | (if ($r.source // "") != "" then .[$r.id].source = $r.source else . end)
   | (if ($r.event // "") == "done"  then .[$r.id].status = "done"
      elif ($r.event // "") == "block" then .[$r.id].status = "blocked"
      elif ($r.event // "") == "reopen" then .[$r.id].status = "open"
      elif ($r.event // "") == "claim"  then .[$r.id].status = "claimed"
      else . end)
  )) as $f
  | ([$f[] | select(.status == "open" or .status == "claimed")]) as $live
  # THE DENOMINATOR IS $probeable, NOT $live. `needs` rows are operator steps with no machine oracle
  # by design (their --run PERFORMS the step), so they can never carry a probe and their presence
  # only dilutes a firing-readiness number they are not part of. Measured 2026-08-11: 168 open
  # `needs` rows, exactly 1 dispatchable. Both counts are emitted so the exclusion is auditable
  # rather than a silent narrowing that flatters the ratio.
  | ([$live[] | select(.source != "needs")]) as $probeable
  | ([$probeable[] | select(.falsifier != "")]) as $covered
  | ([$f[] | select(.status == "done")
        | (((.last // "" | if . == "" then 0 else (sub("\\..*Z$";"Z") | fromdateiso8601? // 0) end)
           - (.first // "" | if . == "" then 0 else (sub("\\..*Z$";"Z") | fromdateiso8601? // 0) end)) / 86400)
        | select(. >= 0)] | sort) as $ages
  | "\($live|length) \($probeable|length) \($covered|length) \($ages|length) \(if ($ages|length) == 0 then 0 else ($ages[($ages|length)/2|floor] * 10 | round / 10) end) \(if ($ages|length) == 0 then 0 else ($ages[($ages|length)*3/4|floor] * 10 | round / 10) end)"
' "$BACKLOG" 2>/dev/null || echo "0 0 0 0 0 0")
EOF

open_n=${open_n:-0}; probe_n=${probe_n:-0}; fals_n=${fals_n:-0}
closed_n=${closed_n:-0}; median_age=${median_age:-0}; p75_age=${p75_age:-0}
if [ "$probe_n" -gt 0 ]; then
  coverage=$(awk -v a="$fals_n" -v b="$probe_n" 'BEGIN{printf "%.1f", (a*100)/b}')
else
  coverage="0.0"
fi

# DENOM_VERSION is bumped whenever WHAT IS COUNTED changes. v2 (2026-08-11) excluded the `needs`
# class from the denominator; a mark recorded under v1 is a number about a different population, so
# comparing them would red or green for a reason unrelated to the store's health.
DENOM_VERSION=2
MAX_HW="${CC_RATCHET_MAX_HW:-95.0}"
MIN_N="${CC_RATCHET_MIN_N:-20}"

prev="0.0"; prev_ver=1
if [ -f "$STATE" ]; then
  prev="$(jq -r '.coverage_high_water // "0.0"' "$STATE" 2>/dev/null || echo "0.0")"
  prev_ver="$(jq -r '.denominator_version // 1' "$STATE" 2>/dev/null || echo 1)"
fi
case "${prev_ver:-1}" in ''|*[!0-9]*) prev_ver=1 ;; esac

reset_note=""
if [ "$prev_ver" -ne "$DENOM_VERSION" ]; then
  # An EXPLICIT, dated reset — never a quiet re-baseline. The old mark measured a different
  # population, so carrying it forward would make every future verdict incomparable rather than
  # strict. This is the ONE path on which the mark may fall, and it announces itself.
  reset_note=" · denominator v${prev_ver}→v${DENOM_VERSION}: high-water RESET from ${prev}% (different population)"
  prev="0.0"
fi

# The high-water mark only ever RISES here. A fall is what --assert reports; recording the fall
# would silently re-baseline the ratchet to the regression, which is the one thing a ratchet exists
# to prevent.
#
# TWO GUARDS ON WHAT MAY LATCH, and this file died for want of both (see header, READINESS W0):
#   CEILING — a mark above MAX_HW makes GREEN unreachable, because ~103 live items are deliberately
#             unprobed and never will be. Latching 100% converted this ratchet into an alarm that
#             could only ever be red, for 3-of-3 of every verdict it ever journalled.
#   FLOOR   — a denominator under MIN_N is a degenerate read (a fixture, a half-written store, a
#             transient). 1-of-1 is 100% and must never become the fleet's standing target.
hw_block=""
if awk -v c="$coverage" -v m="$MAX_HW" 'BEGIN{exit !(c > m)}'; then
  hw_block="ceiling ${MAX_HW}%"
elif [ "$probe_n" -lt "$MIN_N" ]; then
  hw_block="denominator ${probe_n} < floor ${MIN_N}"
fi

if [ -n "$hw_block" ]; then
  prev_note="high-water ${prev}% (NOT raised — ${hw_block})${reset_note}"
elif awk -v c="$coverage" -v p="$prev" 'BEGIN{exit !(c > p)}'; then
  mkdir -p "$(dirname "$STATE")" 2>/dev/null
  jq -nc --arg c "$coverage" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson v "$DENOM_VERSION" \
     '{coverage_high_water:$c, denominator_version:$v, recorded:$ts}' > "$STATE" 2>/dev/null || true
  prev_note="high-water RAISED to ${coverage}%${reset_note}"
else
  # A version reset with no rise still has to PERSIST the new version, or every subsequent run
  # re-announces the reset and the stale v1 mark never actually leaves the file.
  if [ -n "$reset_note" ]; then
    mkdir -p "$(dirname "$STATE")" 2>/dev/null
    jq -nc --arg c "$coverage" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson v "$DENOM_VERSION" \
       '{coverage_high_water:$c, denominator_version:$v, recorded:$ts}' > "$STATE" 2>/dev/null || true
  fi
  prev_note="high-water ${prev}% (unchanged)${reset_note}"
fi

case "$MODE" in
  json)
    jq -nc --arg open "$open_n" --arg probe "$probe_n" --arg cov "$coverage" --arg covered "$fals_n" \
       --arg closed "$closed_n" --arg med "$median_age" --arg p75 "$p75_age" --arg hw "$prev" \
       --argjson dv "$DENOM_VERSION" \
       '{live_items:($open|tonumber), probeable_items:($probe|tonumber),
         falsifier_covered:($covered|tonumber),
         falsifier_coverage_pct:($cov|tonumber), closed_items:($closed|tonumber),
         median_days_to_close:($med|tonumber), p75_days_to_close:($p75|tonumber),
         coverage_high_water:($hw|tonumber), denominator_version:$dv}'
    ;;
  assert)
    printf 'backlog-ratchet: coverage %s%% (%s of %s probeable; %s live) · close median %sd p75 %sd over %s · %s\n' \
      "$coverage" "$fals_n" "$probe_n" "$open_n" "$median_age" "$p75_age" "$closed_n" "$prev_note"
    if awk -v c="$coverage" -v p="$prev" 'BEGIN{exit !(c < p)}'; then
      printf 'backlog-ratchet: RED — falsifier coverage FELL from %s%% to %s%%.\n' "$prev" "$coverage" >&2
      printf '  Items are being filed that cannot re-check themselves, so the store is going back\n' >&2
      printf '  to being believed rather than measured. Add --falsifier to the generator that regressed.\n' >&2
      exit 1
    fi
    ;;
  *)
    printf 'backlog-ratchet — the two standing numbers\n'
    printf '  falsifier coverage : %s%% (%s of %s probeable items can re-check themselves)\n' "$coverage" "$fals_n" "$probe_n"
    # No backticks in this format string: shellcheck reads a backtick inside single quotes as an
    # unexpanded command substitution (SC2016), and the land gate treats that as RED.
    printf '  denominator         : %s live minus %s needs-class (no machine oracle by design) = %s probeable\n' \
      "$open_n" "$((open_n - probe_n))" "$probe_n"
    printf '  days to close       : median %s · p75 %s (over %s closed items)\n' "$median_age" "$p75_age" "$closed_n"
    printf '  %s\n' "$prev_note"
    if awk -v c="$coverage" 'BEGIN{exit !(c < 1)}'; then
      printf '\n  Coverage is near zero because --falsifier landed in a7bf7068 and no generator emits\n'
      printf '  one yet (master M2 wires that). This is a CENSUS until it does — see the header.\n'
    fi
    ;;
esac
exit 0
