#!/usr/bin/env bash
# backlog-telemetry.sh — the standing readout of BACKLOG PROGRESS across both 24/7 drains.
#
# WHY THIS EXISTS. The store (~/.claude/autonomy/backlog.jsonl) is append-only and complete, and
# nothing rendered it as a TREND. `cc-backlog list` answers "what is open right now"; backlog-ratchet
# answers "is falsifier coverage decaying". Neither answers the operator's actual question — *is the
# pile going down, and which lane is doing the work* — so a lane could stop producing entirely and no
# number would move. Measured at build time (2026-08-23): the cloud lane closed 61 rows on Aug 16-17
# and 7 in the six days since, while `launchd com.claude.dispatcher` reported loaded, pid live, last
# exit 0. Loaded but not producing is invisible to every existing instrument.
#
# THE STATE FOLD IS NOT RE-INVENTED HERE, it is REUSED — and getting it wrong is the whole risk:
#   · State lives in the `event` field. There is NO `status` field in the STORE. (`cc-backlog list
#     --all --json` synthesizes one; that is a different surface and the two are never mixed here.)
#   · Six state verbs only: add|reopen|unblock → open · done → done · block → blocked · claim →
#     CLAIMED, which is NOT open. Mapping claim→open inflates store-wide counts.
#   · link / venue / falsify / update are ANNOTATIONS, not state. A fold that lets them win as
#     "last event" reads open=86 where the truth is 260.
#   · Fold on the `id` FIELD, never a raw grep of the line: a row's id appears inside OTHER rows'
#     evidence prose, so `grep '<id>'` over-counts (measured OWN=5 / CITE=2 on 8740c03e428c).
#
# 🚨 CLOSE ATTRIBUTION IS READ FROM THE `lane` FIELD ON THE `done` RECORD, AND FROM NOTHING ELSE.
# Not `venue`, and not the folded `by`. Both are traps this file refuses by construction:
#   · `venue` records where a row was ROUTED (413 cloud / 88 local at build time), never who CLOSED
#     it. Presenting it as attribution is the false-corroboration shape — a true metric standing
#     beside the wrong question reads as though the question were answered.
#   · the FOLDED `by` carries forward (`$r.by // $p.by` in cc-backlog's fold), so a row CLAIMED by a
#     worker and closed by a sweep folds to the claimer's name. Only the `done` record's OWN fields
#     say who closed it.
# A `done` with no `lane` is `unattributed`, is COUNTED AS SUCH, and is never guessed at. Historical
# rows stay unattributed forever: retroactively inferring a lane would manufacture exactly the
# certainty this readout exists to measure the absence of.
#
# ROUTING ACTIVITY is rendered too, in its own section, under a header that says what it is not.
# Omitting it entirely was the first draft and it was worse: on the day attribution lands, EVERY lane
# reads `lane-unattributed` and the operator learns nothing at all about the cloud drain — including
# that it has stopped. The routing series is the only pre-attribution signal that exists, so it is
# shown, fenced, and given verdict tokens that cannot be confused with the lane-health ones.
#
# BSD/DARWIN CONSTRAINTS honoured here, each of which has already bitten this repo:
#   · This box's awk is BSD awk: `asorti` is UNDEFINED. All sorting is done by `sort`, never in awk.
#     (This file does its arithmetic in jq and its ordering in `sort`, so it uses no awk at all.)
#   · `find` here is bfs: `-newermt '-3 hours'` ERRORS; `-mtime -1` works. (Not used here — noted so
#     a future edit does not reach for it.)
#   · `stat -f %Sm` renders LOCAL time. Every clock in this file is pinned TZ=UTC on BOTH sides.
#   · NEVER `probe 2>/dev/null | wc -l` — that renders a FAILED command as a clean 0.
#   · Under `pipefail`, `producer | grep -q X` FAILS on the input it just matched (SIGPIPE). This
#     file COUNTS, never `-q`.
#
# Usage:
#   backlog-telemetry.sh [--days N] [--json] [--assert]
#     --days N   how many days of the daily series to print (default 14; the fold always walks the
#                WHOLE store, so open/blocked are correct on the first printed day).
#     --json     emit the computed model instead of the rendered tables (one JSON object).
#     --assert   rc 1 if any roster lane renders `verdict=lane-stalled`. Never rc 1 for
#                `lane-unattributed` — see THE POLARITY RULE below.
#
# THE POLARITY RULE. `--assert` is deliberately blind to `lane-unattributed`, which is the state
# EVERY lane is in until attributed closes accumulate. An alarm that fires on every run from the day
# it ships carries exactly as many bits as one that cannot fire at all, and it would be read past by
# the time it started meaning something. It arms itself as attribution accrues, with no flag day.
#
# Store: ${CC_BACKLOG_FILE:-~/.claude/autonomy/backlog.jsonl} — the same variable bin/cc-backlog
# reads, so a fixtured store reaches both halves of this mechanism.

set -o errexit -o nounset -o pipefail
export TZ=UTC   # pinned on BOTH sides of every comparison; `date`/`stat` render LOCAL otherwise.

BACKLOG="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"

# The ROSTER — the lanes that are always rendered even at zero, with the cadence each is expected to
# beat. A lane that produced nothing must render a NAMED verdict, never a silent absence: a missing
# row and a healthy row are indistinguishable to a reader, and the missing one is the emergency.
# `local-drain` and `cloud` are the operator's two 24/7 drains; `session` is every other agent close.
ROSTER="cloud local-drain session"

# Cadence in HOURS, per lane. A `case` rather than an associative array on purpose: /bin/bash on
# Darwin is 3.2 and has no `declare -A`, and this script must not depend on which bash won the PATH.
lane_cadence_h() {
  case "$1" in
    cloud)       printf '%s' "${CC_BLTM_CADENCE_CLOUD_H:-24}" ;;
    local-drain) printf '%s' "${CC_BLTM_CADENCE_LOCAL_H:-24}" ;;
    session)     printf '%s' "${CC_BLTM_CADENCE_SESSION_H:-72}" ;;
    *)           printf '%s' "${CC_BLTM_CADENCE_OTHER_H:-168}" ;;
  esac
}

DAYS=14
MODE=render
ASSERT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --days)   DAYS="${2:-}"; shift 2 || true ;;
    --json)   MODE=json; shift ;;
    --assert) ASSERT=1; shift ;;
    -h|--help) sed -n '2,60p' "$0"; exit 0 ;;
    *) printf 'backlog-telemetry: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done
case "$DAYS" in ''|*[!0-9]*) printf 'backlog-telemetry: --days wants an integer, got "%s"\n' "$DAYS" >&2; exit 2 ;; esac

command -v jq >/dev/null 2>&1 || { printf 'backlog-telemetry: jq is required and is not on PATH\n' >&2; exit 2; }

if [ ! -f "$BACKLOG" ]; then
  printf 'backlog-telemetry: ⛔ no store at %s\n' "$BACKLOG" >&2
  printf '  This is an ABSENT INSTRUMENT, not an empty backlog — the two read identically in any\n' >&2
  printf '  summary that treats a missing file as zero, so this one refuses instead.\n' >&2
  exit 2
fi

# ── READ THE STORE ───────────────────────────────────────────────────────────────────────────────
# Well-formed records to stdout, malformed ones COUNTED (never silently dropped, and never rendered
# as a clean 0 by a suppressed stderr). Same G/E/B tagging shape as cc-backlog's valid_records, kept
# structurally identical so the two readers cannot disagree about what a record is.
RAW_LINES="$(grep -c '' "$BACKLOG" || true)"
case "$RAW_LINES" in ''|*[!0-9]*) RAW_LINES=0 ;; esac

RECORDS_FILE="$(mktemp -t bltm-records.XXXXXX)"
TAGGED_FILE="$(mktemp -t bltm-tagged.XXXXXX)"
trap 'rm -f "$RECORDS_FILE" "$TAGGED_FILE"' EXIT

# rc is checked explicitly: a jq that DIES here would otherwise deliver an empty record set, which
# renders as a backlog with no history — the one failure this readout must never present as data.
if ! jq -Rr 'if . == "" then "E"
             elif (try (fromjson | (has("id") and has("event"))) catch false) then "G" + .
             else "B" end' "$BACKLOG" > "$TAGGED_FILE"; then
  printf 'backlog-telemetry: ⛔ the record scan FAILED on %s — refusing to report a partial store\n' "$BACKLOG" >&2
  exit 2
fi

# `grep -c` on a pattern that may match nothing exits 1 — `|| true` keeps errexit off our back, and
# the count is validated rather than assumed. Counting, never `grep -q`: under pipefail a `-q` closes
# the pipe and convicts the producer of the very input it just matched.
N_GOOD="$(grep -c '^G' "$TAGGED_FILE" || true)"; case "$N_GOOD" in ''|*[!0-9]*) N_GOOD=0 ;; esac
N_BLANK="$(grep -c '^E' "$TAGGED_FILE" || true)"; case "$N_BLANK" in ''|*[!0-9]*) N_BLANK=0 ;; esac
N_BAD="$(grep -c '^B' "$TAGGED_FILE" || true)"; case "$N_BAD" in ''|*[!0-9]*) N_BAD=0 ;; esac
N_SEEN=$(( N_GOOD + N_BLANK + N_BAD ))

sed -e '/^G/!d' -e 's/^G//' "$TAGGED_FILE" > "$RECORDS_FILE"

SCAN_VERDICT=ok
if [ "$N_SEEN" -ne "$RAW_LINES" ]; then SCAN_VERDICT=incomplete; fi
if [ "$N_BAD" -gt 0 ] && [ "$SCAN_VERDICT" = ok ]; then SCAN_VERDICT=malformed; fi

NOW_EPOCH="$(date -u +%s)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── THE MODEL ────────────────────────────────────────────────────────────────────────────────────
# One jq pass produces every number this file prints. Doing the arithmetic in ONE place is what keeps
# --json and the rendered tables from ever disagreeing: they are the same object, formatted twice.
MODEL="$(jq -s \
  --argjson now "$NOW_EPOCH" \
  --arg nowIso "$NOW_ISO" \
  --arg roster "$ROSTER" \
  --argjson rawLines "$RAW_LINES" \
  --argjson nSeen "$N_SEEN" \
  --argjson nGood "$N_GOOD" \
  --argjson nBad "$N_BAD" \
  --arg scan "$SCAN_VERDICT" '
  # ── the six STATE verbs, and only those. Everything else is an annotation. ──────────────────────
  def state_of($e):
    if   $e == "add"     then "open"
    elif $e == "reopen"  then "open"
    elif $e == "unblock" then "open"
    elif $e == "done"    then "done"
    elif $e == "block"   then "blocked"
    elif $e == "claim"   then "claimed"
    else null end;

  ( $roster | split(" ") | map(select(length > 0)) ) as $ROSTER
  | ( sort_by(.ts // "") ) as $recs

  # ── the running fold: state per id + incremental bucket counters ────────────────────────────────
  # Counters are adjusted on TRANSITION rather than recounted per event: recounting is O(events x
  # ids) and this store is 13k x 2.6k. The day snapshot is written on EVERY event, so what survives
  # is the last-of-day value, which is the definition of the series.
  | ( reduce $recs[] as $r (
        { st: {}, open: 0, blocked: 0, claimed: 0, done: 0,
          day: {}, peakLive: -1, peakDate: "", firstTs: "", lastTs: "" };
        ( ($r.ts // "")[0:10] ) as $d
        | ( state_of($r.event) ) as $new
        | .firstTs = (if .firstTs == "" then ($r.ts // "") else .firstTs end)
        | .lastTs  = ($r.ts // .lastTs)
        | .day[$d] = ( .day[$d] // { filed: 0, closed: 0, open: 0, blocked: 0 } )
        | (if $r.event == "add"  then .day[$d].filed  += 1 else . end)
        | (if $r.event == "done" then .day[$d].closed += 1 else . end)
        | ( if $new == null then .
            else
              ( .st[$r.id] // null ) as $old
              | if $old == $new then .
                else
                  ( if   $old == "open"    then .open    -= 1
                    elif $old == "blocked" then .blocked -= 1
                    elif $old == "claimed" then .claimed -= 1
                    elif $old == "done"    then .done    -= 1
                    else . end )
                  | ( if   $new == "open"    then .open    += 1
                      elif $new == "blocked" then .blocked += 1
                      elif $new == "claimed" then .claimed += 1
                      elif $new == "done"    then .done    += 1
                      else . end )
                  | .st[$r.id] = $new
                end
            end )
        | .day[$d].open    = .open
        | .day[$d].blocked = .blocked
        # PEAK LIVE is tracked per EVENT, not per day: a pile that spiked and drained inside one day
        # is a real peak, and a last-of-day snapshot cannot see it.
        | ( (.open + .blocked) as $live
            | if $live > .peakLive then (.peakLive = $live | .peakDate = $d) else . end )
      ) ) as $F

  # ── the daily series, oldest first ──────────────────────────────────────────────────────────────
  | ( $F.day | to_entries | sort_by(.key)
      | map({ date: .key,
              filed:   .value.filed,
              closed:  .value.closed,
              net:     (.value.filed - .value.closed),
              open:    .value.open,
              blocked: .value.blocked,
              live:    (.value.open + .value.blocked) }) ) as $series

  # ── CLOSE ATTRIBUTION: the `lane` field on the `done` record, and nothing else ───────────────────
  | ( $recs | map(select(.event == "done")) ) as $closes
  | ( $closes | map(.lane // "unattributed") | unique ) as $seenLanes
  | ( ($ROSTER + $seenLanes) | unique | map(select(. != "unattributed")) ) as $laneNames
  | ( $closes | map(select((.lane // "") == "")) | length ) as $unattributed

  | ( $laneNames | map(
        . as $ln
        | ( $closes | map(select(.lane == $ln)) ) as $mine
        | { lane: $ln,
            closes: ($mine | length),
            last:   ( $mine | map(.ts // "") | sort | last // "" ),
            closedBy: ( $mine | map(.closedBy // "") | map(select(. != "")) | unique ) } ) ) as $lanes

  # ── ROUTING ACTIVITY — venue, which is WHERE A ROW WAS ROUTED and NEVER who closed it ───────────
  # Kept in its own object so no consumer can pick it up believing it is attribution.
  | ( $recs | map(select((.venue // "") != "")) ) as $venued
  | ( ($venued | map(.venue) | unique) | map(
        . as $v
        | ( $venued | map(select(.venue == $v)) ) as $mine
        | { venue: $v,
            events: ($mine | length),
            last:   ( $mine | map(.ts // "") | sort | last // "" ) } ) ) as $routing

  | ( $series | map(.closed) ) as $allClosed
  | ( $series[-7:] ) as $last7

  | { now: $nowIso, nowEpoch: $now,
      scan: { rawLines: $rawLines, seen: $nSeen, good: $nGood, malformed: $nBad, verdict: $scan },
      span: { first: $F.firstTs, last: $F.lastTs, days: ($series | length) },
      current: { open: $F.open, blocked: $F.blocked, claimed: $F.claimed, done: $F.done,
                 live: ($F.open + $F.blocked) },
      peak: { live: $F.peakLive, date: $F.peakDate },
      series: $series,
      window7: { filed:  ($last7 | map(.filed)  | add // 0),
                 closed: ($last7 | map(.closed) | add // 0),
                 net:    ($last7 | map(.net)    | add // 0),
                 days:   ($last7 | length) },
      closes: { total: ($closes | length), attributed: (($closes | length) - $unattributed),
                unattributed: $unattributed },
      lanes: $lanes,
      routing: $routing }
  ' "$RECORDS_FILE")"

if [ "$MODE" = json ]; then
  printf '%s\n' "$MODEL"
  exit 0
fi

# ── RENDER ───────────────────────────────────────────────────────────────────────────────────────
jqm() { printf '%s' "$MODEL" | jq -r "$1"; }

printf 'BACKLOG TELEMETRY  ·  %s  ·  store=%s\n' "$NOW_ISO" "$BACKLOG"
printf 'scan: %s line(s), %s record(s), %s malformed  verdict=scan-%s\n' \
  "$(jqm '.scan.rawLines')" "$(jqm '.scan.good')" "$(jqm '.scan.malformed')" "$(jqm '.scan.verdict')"
printf 'span: %s → %s  (%s day(s) with events)\n' \
  "$(jqm '.span.first')" "$(jqm '.span.last')" "$(jqm '.span.days')"
printf '\n'

printf 'DAILY SERIES  (last %s day(s) with events; open/blocked are the LAST-OF-DAY fold)\n' "$DAYS"
printf '%-12s %7s %7s %7s %7s %8s %7s\n' date filed closed net open blocked LIVE
printf '%s\n' '------------ ------- ------- ------- ------- -------- -------'
jqm ".series[-${DAYS}:][] | [.date, .filed, .closed, .net, .open, .blocked, .live] | @tsv" \
  | while IFS="$(printf '\t')" read -r d f c n o b l; do
      printf '%-12s %7s %7s %7s %7s %8s %7s\n' "$d" "$f" "$c" "$n" "$o" "$b" "$l"
    done
printf '\n'

W7F="$(jqm '.window7.filed')"; W7C="$(jqm '.window7.closed')"; W7N="$(jqm '.window7.net')"
W7D="$(jqm '.window7.days')"
printf 'ROLLING 7-DAY  filed=%s closed=%s net=%s over %s active day(s)\n' "$W7F" "$W7C" "$W7N" "$W7D"
printf 'NOW            open=%s blocked=%s claimed=%s LIVE=%s\n' \
  "$(jqm '.current.open')" "$(jqm '.current.blocked')" "$(jqm '.current.claimed')" "$(jqm '.current.live')"
printf 'PEAK LIVE      %s on %s\n' "$(jqm '.peak.live')" "$(jqm '.peak.date')"
printf '\n'

# ── the per-lane table. `unattributed` is a FIRST-CLASS ROW and a header token, both deliberately:
# a reader who skims the rows must not be able to conclude the lanes account for the closes.
TOT="$(jqm '.closes.total')"; ATT="$(jqm '.closes.attributed')"; UNATT="$(jqm '.closes.unattributed')"
COV="$(printf '%s' "$MODEL" | jq -r 'if .closes.total == 0 then "n/a"
  else ((.closes.attributed * 1000 / .closes.total | floor) / 10 | tostring) + "%" end')"
# No backticks in these two banners. ShellCheck reads a backtick inside a single-quoted string as an
# intended command substitution that will not expand (SC2016, severity INFO) — and the land gate runs
# at INFO, so a local "-S warning" repro is structurally blind to it and exonerates a file the gate
# then refuses. The backticks were decoration in terminal output and bought nothing.
#   (Two lessons, both paid for here: match the HARNESS's invocation, not a milder one; and never
#    begin a comment with the bare tool name — ShellCheck parses that as a directive, SC1072/SC1073,
#    which aborts analysis of the whole file and blocks the land on its own.)
printf 'CLOSE ATTRIBUTION BY LANE  (source: the lane field on the done record — NOT venue, NOT the folded by)\n'
printf 'closes=%s attributed=%s unattributed=%s coverage=%s\n' "$TOT" "$ATT" "$UNATT" "$COV"
printf '%-14s %8s %8s %-22s\n' lane closes share last-close
printf '%s\n' '-------------- -------- -------- ----------------------'
printf '%s' "$MODEL" | jq -r '
  (.closes.total) as $t
  | ( .lanes[] | [ .lane, .closes,
                   (if $t == 0 then "n/a" else ((.closes * 1000 / $t | floor) / 10 | tostring) + "%" end),
                   (if .last == "" then "never" else .last end) ] | @tsv ),
    ( [ "unattributed", .closes.unattributed,
        (if $t == 0 then "n/a" else ((.closes.unattributed * 1000 / $t | floor) / 10 | tostring) + "%" end),
        "-" ] | @tsv )' \
  | while IFS="$(printf '\t')" read -r ln cl sh la; do
      printf '%-14s %8s %8s %-22s\n' "$ln" "$cl" "$sh" "$la"
    done
printf '\n'

# ── LANE HEALTH. One NAMED verdict token per roster lane, always — a lane that produced nothing
# renders a token, never a blank. `lane-unattributed` is its own verdict rather than a stalled one:
# before any close carries a lane, "this lane produced nothing" and "nothing records lanes yet" are
# different facts, and collapsing them would convict a working lane of being dead.
printf 'LANE HEALTH\n'
STALLED=0
SEEN_LANES=""   # declared before use: `set -u` makes an unset var in the dedupe test a hard error.
# The roster comes FIRST so a lane that has never closed anything still gets its verdict line; the
# store-observed lanes follow, so a lane nobody declared still cannot render as a silent absence.
for lane in $ROSTER $(printf '%s' "$MODEL" | jq -r '.lanes[].lane' | sort); do
  case " $SEEN_LANES " in *" $lane "*) continue ;; esac
  SEEN_LANES="$SEEN_LANES $lane"
  cad="$(lane_cadence_h "$lane")"
  n="$(printf '%s' "$MODEL" | jq -r --arg l "$lane" '[.lanes[] | select(.lane == $l) | .closes] | first // 0')"
  last="$(printf '%s' "$MODEL" | jq -r --arg l "$lane" '[.lanes[] | select(.lane == $l) | .last] | first // ""')"
  if [ "$ATT" -eq 0 ]; then
    printf '  verdict=lane-unattributed lane=%-12s closes=0 cadence=%sh — no close in this store carries a lane yet\n' \
      "$lane" "$cad"
    continue
  fi
  if [ "$n" -eq 0 ] || [ -z "$last" ]; then
    printf '  verdict=lane-silent       lane=%-12s closes=0 cadence=%sh age=never\n' "$lane" "$cad"
    STALLED=$(( STALLED + 1 ))
    continue
  fi
  # TZ is pinned UTC at the top of this file, so both sides of this subtraction are UTC — a
  # LOCAL-rendered `last` against a UTC `now` is off by the offset and flips a verdict at the margin.
  # BOTH dialects, BSD first. `-j -f` is BSD-only, so on Linux this parsed nothing and every lane
  # rendered `lane-unreadable` — a verdict that is fail-closed and therefore looked deliberate, which
  # is why it survived. GNU's `-d` is the fallback and never the probe: on macOS `-d` means "daylight
  # saving", so a GNU-first order would succeed there and mis-date the subtraction below.
  last_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$last" +%s 2>/dev/null \
                || date -u -d "$last" +%s 2>/dev/null || printf '')"
  if [ -z "$last_epoch" ]; then
    printf '  verdict=lane-unreadable   lane=%-12s closes=%s last=%s — timestamp did not parse; NOT read as healthy\n' \
      "$lane" "$n" "$last"
    STALLED=$(( STALLED + 1 ))
    continue
  fi
  age_h=$(( (NOW_EPOCH - last_epoch) / 3600 ))
  if [ "$age_h" -gt "$cad" ]; then
    printf '  verdict=lane-stalled      lane=%-12s closes=%s cadence=%sh age=%sh last=%s\n' \
      "$lane" "$n" "$cad" "$age_h" "$last"
    STALLED=$(( STALLED + 1 ))
  else
    printf '  verdict=lane-ok           lane=%-12s closes=%s cadence=%sh age=%sh last=%s\n' \
      "$lane" "$n" "$cad" "$age_h" "$last"
  fi
done
printf '\n'

# ── ROUTING ACTIVITY — fenced, and named for what it is NOT. ─────────────────────────────────────
printf 'ROUTING ACTIVITY  🚨 the venue field records where a row was ROUTED. It is NOT close attribution:\n'
printf '   a routed row may have been closed by any lane, or by nobody. Read it as lane LIVENESS only.\n'
printf '%-14s %8s %-22s\n' venue events last-event
printf '%s\n' '-------------- -------- ----------------------'
printf '%s' "$MODEL" | jq -r '.routing[] | [.venue, .events, (if .last == "" then "never" else .last end)] | @tsv' \
  | while IFS="$(printf '\t')" read -r v e la; do
      printf '%-14s %8s %-22s\n' "$v" "$e" "$la"
    done

if [ "$ASSERT" -eq 1 ]; then
  if [ "$STALLED" -gt 0 ]; then
    printf '\nbacklog-telemetry: ⛔ %s lane(s) stalled or silent — verdict=assert-red\n' "$STALLED" >&2
    exit 1
  fi
  printf '\nbacklog-telemetry: verdict=assert-green\n'
fi
exit 0
