#!/usr/bin/env bash
# backlog-flow-assert.sh — IS THE BACKLOG ACTUALLY DRAINING? (docs/plans/BACKLOG_DRAIN_24_7.md §6)
#
# ── THE INVARIANT, AND WHY IT WAS THE LAST ONE STILL WRITTEN IN PROSE ───────────────────────────
# §6's fourth and final operating invariant:
#
#     Weekly report: adds vs closes; net-positive week ⇒ the INFLOW list (C1-C4) gets the next fix,
#     not more drain horsepower.
#
# It is the invariant that decides what the program DOES NEXT, and it was implemented by nothing:
# no script, test or plist on trunk computed adds against closes over any window. Every figure this
# plan quotes for it — "+426 rows over 5 days (1,129 filed / 503 closed)", "21-day totals 1,530 adds
# vs 1,117 dones" (§1.3), and every recycle's `filed N / closed M` line in §2.1 — was HAND-COMPUTED
# by whichever session happened to be looking. A number that only exists when somebody derives it is
# not a measurement; it is a memory, and §1.1 is the record of what this store's memory is worth.
#
# That is the same state §6's THIRD invariant was in before scripts/drain-chain-assert.sh landed,
# and this file is deliberately its sibling: same four modes, same fail-open discipline, same
# condition-keyed self-retiring row, same caller (autonomy-sweep § 2b-v). The two answer the two
# halves of the same question — *is anything draining* (liveness) and *is the draining winning*
# (flow) — and a chain can be perfectly alive while losing, which is precisely the 5-day stretch
# §1.3 measured.
#
# ── STOCK vs FLOW: WHY THIS DOES NOT READ THE FOLD, AND IS NOT A SECOND STATE MODEL ─────────────
# Every other backlog reader in this repo asks a STOCK question — how many rows are open *now* — and
# answers it from cc-backlog's fold, which is last-event-wins per id. This asks a FLOW question:
# how many rows ENTERED and how many closings HAPPENED inside a window. The fold cannot answer it,
# by construction: it collapses a row's whole event history to one status and one clock, so a row
# filed Monday and closed Tuesday is indistinguishable from one filed and closed in the same second,
# and 1,500 closings across three weeks read as whatever the last record says today.
#
# So this reads the RECORD TRAIL, and that is a different question, not a rival answer to the same
# one (memory: sibling-auditors-must-share-the-state-model — the rule is that two readers must not
# disagree about the SAME question). Concretely it differs from bin/cc-value's `tasks_closed`, which
# is the stock reading and the right one for its own purpose: a row closed, reopened and closed
# again is ONE finished task to cc-value and TWO closings here, because two closings is what the
# drain actually did. `reopened` is reported beside them so the re-entry is visible rather than
# quietly netted — see the next section for why it is not folded into `added`.
#
# The only fields read are `event` and `ts`, the two the fold reinterprets least, plus `project`
# from `add` records for the optional filter. Anything the fold would have to adjudicate — status,
# wasDone, lastTs — is deliberately untouched.
#
# ── WHAT COUNTS AS AN ADD, MEASURED AGAINST cc-backlog RATHER THAN ASSUMED ──────────────────────
# `add` is appended AT MOST ONCE PER ID, ever. Ids are content-keyed (project+title+source, or
# project+condition), and cmd_add's known-id arm appends an `update` record, never a second `add`
# (bin/cc-backlog:1440-1452 — and it only writes when a field genuinely CHANGED, "an update that
# writes on every call turns an idempotent re-file into unbounded ledger growth"). So re-filing the
# same work does not inflate this count, which is exactly the property a filing-rate metric needs.
# Ids are `unique`d anyway: at most one add per id is cc-backlog's invariant, not this file's, and
# if a hand-edit or a bad compaction ever breaks it, the truthful count of rows filed is the
# distinct one.
#
# A `reopen` is NOT an add, and the reason is the remedy §6 prescribes rather than bookkeeping
# taste. The invariant routes a net-positive week to the INFLOW list (C1-C4), and every member of
# that list is a FILING generator: C1 the re-land minter, C2 find-plan's re-mint of finished plans,
# C3 evidence-less dones, C4 the premise pass. A reopen is produced by none of them, so folding
# reopens into `added` would point a real remedy at the wrong list. It is counted and reported on
# its own line instead, where a reopen storm is visible as itself.
#
# ── THE TWO FAILURE DIRECTIONS, WHICH ARE NOT SYMMETRIC ─────────────────────────────────────────
#   a FALSE DRAINING   is §1.3 happening again with an instrument in the room: inflow outruns the
#                      drain, the report says fine, and the program answers by adding more drain
#                      horsepower against a generator nobody is fixing.
#   a FALSE NET-POSITIVE files a standing row in the very store this program exists to drain, and
#                      condition-keyed, so it never ages out on its own — the same cost that makes
#                      drain-chain-assert's false-DEAD its forbidden direction.
#
# Hence four abstentions, each of which reports its figures and files nothing:
#
#   no-store / no-jq     ⇒ unknown:skipped. "I could not ask" is never "the answer was no".
#   unreadable fold      ⇒ unknown:read-failed. Same rule, one layer in.
#   history < window     ⇒ unknown:short-history. THE LOAD-BEARING ONE. The first week of any store
#                          is structurally net-positive — everything in it is new and nothing has
#                          had time to close — so an alarm that convicts there files a permanent row
#                          on a healthy new box on day one, and holds it open. This is the same trap
#                          as backlog-ratchet.sh's 100% high-water against a population that could
#                          not reach it (memory: cap-whose-population-is-empty), pointed the other
#                          way. The window must fit the history it is measured over.
#   unparsed > |net|     ⇒ unknown:unparsed-could-flip. A record with no readable `ts` is excluded
#                          from both sides, and excluded evidence is not absent evidence: if the
#                          pile of records this pass could not place is larger than the margin the
#                          verdict rests on, that pile alone could reverse the sign, and the honest
#                          answer is that we do not know (recycle #20's rule: an absence test
#                          inherits every hole in its input as a positive finding).
#
# `--assert` therefore exits 0 on every abstention. It is a falsifier — its rc-1 direction is the
# CONVICTION — so an unknown must read exactly like a healthy week to every consumer.
#
# ── WHY THE FILED ROW'S TITLE CARRIES NO FIGURES ────────────────────────────────────────────────
# The caller is autonomy-sweep at 300 s, and cc-backlog's update arm rewrites a known row's title
# whenever it CHANGED. A title carrying live counts therefore appends an `update` record on every
# tick whose figures moved — up to 288 records a day, into the store this row exists to shrink, from
# the detector that exists to name its generators. The title states the window, the verdict and the
# prescription, all of which are stable while the condition holds; the figures live in `--json`, in
# the sweep's own `backlog-health` IDL row, and one command away in the title itself. One filing,
# one record, however long the week stays red.
#
# Usage:
#   backlog-flow-assert.sh                report the window's figures and verdict (always prints)
#   backlog-flow-assert.sh --assert       exit 1 when the window is NET-POSITIVE (the falsifier)
#   backlog-flow-assert.sh --file         file/update ONE condition-keyed row when net-positive
#   backlog-flow-assert.sh --json         the whole reading as one JSON object
#   backlog-flow-assert.sh --project <p>  scope both sides to one project (default: whole store)
# Env:
#   CC_BACKLOG_FILE            the store — the SAME seam cc-backlog and every test use
#   CC_BACKLOG_BIN             cc-backlog, for the --file arm
#   CC_BACKLOG_FLOW_WINDOW_S   default 604800 (§6's "week")
#   CC_BACKLOG_FLOW_NOW        test clock (epoch seconds)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
BACKLOG_BIN="${CC_BACKLOG_BIN:-$REPO/bin/cc-backlog}"
STORE="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
NOW="${CC_BACKLOG_FLOW_NOW:-$(date +%s)}"
MODE="report"
PROJECT=""

# A garbage window falls back to the default rather than disabling the check. Polarity: this term
# RESTRAINS (it bounds what the verdict may look at), so ignoring a typo fails SAFE — the opposite
# of a term that authorises an action, where a typo must not silently arm anything (the
# CC_ROUTE_REPICK_RATIO=off lesson, recycle #20).
WINDOW="${CC_BACKLOG_FLOW_WINDOW_S:-604800}"
case "$WINDOW" in ''|*[!0-9]*) WINDOW=604800 ;; esac
case "$NOW"    in ''|*[!0-9]*) NOW="$(date +%s)" ;; esac

while [ $# -gt 0 ]; do
  case "$1" in
    --assert)  MODE="assert"; shift ;;
    --file)    MODE="file";   shift ;;
    --json)    MODE="json";   shift ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --help|-h) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *) printf 'backlog-flow-assert: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done

SINCE=$(( NOW - WINDOW ))
DAYS=$(( WINDOW / 86400 )); [ "$DAYS" -gt 0 ] || DAYS=0

# ONE verdict computed once and rendered by every arm, so the number a gate refuses on, the number a
# row is filed against and the number a human reads are the same read of the same store.
VERDICT="unknown"; WHY="skipped"
ADDED=0; CLOSED=0; REOPENED=0; NET=0; UNPARSED=0; TOTAL=0; HISTORY=-1; UNATTRIBUTED=0

TITLE="the backlog is taking in more work than it closes"

emit() { # render + exit, per mode. Called exactly once.
  case "$MODE" in
    json)
      jq -cn --arg v "$VERDICT" --arg w "$WHY" --arg p "$PROJECT" \
             --argjson a "$ADDED" --argjson c "$CLOSED" --argjson r "$REOPENED" \
             --argjson n "$NET" --argjson u "$UNPARSED" --argjson t "$TOTAL" \
             --argjson h "$HISTORY" --argjson x "$UNATTRIBUTED" \
             --argjson win "$WINDOW" --argjson since "$SINCE" --argjson now "$NOW" \
        '{verdict:$v, why:$w, project:(if $p=="" then null else $p end),
          window_s:$win, since_epoch:$since, now_epoch:$now,
          added:$a, closed:$c, reopened:$r, net:$n,
          unparsed:$u, records:$t, unattributed:$x,
          history_s:(if $h < 0 then null else $h end),
          note:"verdict draining|net-positive|unknown. FLOW, not stock: added counts distinct ids with an `add` record inside the window, closed counts `done` RECORDS (a row closed twice is two closings, which is what the drain did), reopened is reported beside them and never folded into added because BACKLOG_DRAIN_24_7 §6 routes a net-positive week to the INFLOW list C1-C4 and every member of that list is a FILING generator. net = added - closed; net > 0 is net-positive and is the state §6 says must be answered by fixing inflow, not by adding drain horsepower. unknown is always an abstention and never a conviction: skipped = no store or no jq, read-failed = the store would not parse, short-history = the store is younger than the window so the first-week-is-always-net-positive artefact cannot be ruled out, unparsed-could-flip = more records lack a readable ts than the margin the verdict rests on. --assert exits 0 on every unknown."}'
      exit 0 ;;
    assert)
      [ "$VERDICT" = net-positive ] || exit 0
      _line >&2; exit 1 ;;
    report)
      _line; exit 0 ;;
    file)
      [ "$VERDICT" = net-positive ] || exit 0
      [ -x "$BACKLOG_BIN" ] || { printf 'no cc-backlog at %s (fail-open)\n' "$BACKLOG_BIN" >&2; exit 0; }
      # `--falsifier` reaches a row only while CREATING it (cmd_add's update arm is a deliberate
      # no-op on a known id, and cc-backlog falsify is the only door to an existing one), so this
      # attaches once, at first filing, and the row retires itself the week the sign flips.
      "$BACKLOG_BIN" add --project claude-infrastructure \
        --condition backlog-inflow-net-positive \
        --title "$TITLE" \
        --source backlog-flow-assert \
        --falsifier "bash $HERE/backlog-flow-assert.sh --assert" \
        --dod-ref "origin/main:docs/plans/BACKLOG_DRAIN_24_7.md" >/dev/null 2>&1 \
        || { printf 'backlog-flow-assert: could not file the escalation row\n' >&2; exit 0; }
      exit 0 ;;
  esac
}

_line() {
  local scope; scope="$([ -n "$PROJECT" ] && printf ' · project %s' "$PROJECT" || printf '')"
  case "$VERDICT" in
    net-positive)
      printf 'backlog-flow: NET-POSITIVE over %sd — %s filed / %s closed (net +%s) · %s reopened%s. §6: the INFLOW list (C1-C4) gets the next fix, not more drain horsepower.\n' \
        "$DAYS" "$ADDED" "$CLOSED" "$NET" "$REOPENED" "$scope" ;;
    draining)
      printf 'backlog-flow: DRAINING over %sd — %s filed / %s closed (net %s) · %s reopened%s\n' \
        "$DAYS" "$ADDED" "$CLOSED" "$NET" "$REOPENED" "$scope" ;;
    *)
      printf 'backlog-flow: CANNOT TELL (%s) over %sd — %s filed / %s closed · %s unparsed of %s record(s)%s\n' \
        "$WHY" "$DAYS" "$ADDED" "$CLOSED" "$UNPARSED" "$TOTAL" "$scope" ;;
  esac
}

# ── guard 1: can we ask at all? ────────────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { WHY="skipped"; emit; }
[ -f "$STORE" ]               || { WHY="skipped"; emit; }

# ONE jq pass over the raw trail. `-n -R` makes `inputs` yield each LINE as a string, so a single
# process does both the per-line parse and the aggregation — the two-process `jq -R … | jq -s …`
# form costs a second jq startup per call on a ledger that is only ever appended to.
#
# The project map is built from `add` records because a transition record carries NO project field
# (cmd_transition writes id/ts/event and the verb's own operands, nothing else). Filtering adds by
# project while counting every project's closings would produce a net that is not about any project
# at all. `project` is part of the id hash, so an add's project is the row's project for life.
READ="$(jq -n -R --argjson since "$SINCE" --arg proj "$PROJECT" '
  def ep: (try fromdateiso8601 catch null);
  [ inputs | fromjson? // empty
    | select(type == "object" and has("id") and has("event")) ]
  | map(. + {e: ((.ts // "") | ep)})                                        as $rec
  | ( $rec | map(select(.event == "add")) | map({key: .id, value: (.project // "")}) | from_entries )
                                                                            as $pj
  | ( $rec | map(select(.e != null)) )                                      as $ok
  | ( $ok  | map(select(.e >= $since)) )                                    as $win
  # a record whose id has no `add` in the trail cannot be attributed to a project. With no filter
  # that is harmless (nothing is excluded); with one it is a hole, so it is counted and reported.
  | def keep: ($proj == "") or (($pj[.id] // null) == $proj);
    def orphan: ($proj != "") and (($pj[.id] // null) == null);
  {
    records:      ($rec | length),
    unparsed:     ($rec | map(select(.e == null)) | length),
    oldest:       ($ok  | map(.e) | min),
    added:        ($win | map(select(.event == "add"    and keep)) | map(.id) | unique | length),
    closed:       ($win | map(select(.event == "done"   and keep)) | length),
    reopened:     ($win | map(select(.event == "reopen" and keep)) | length),
    unattributed: ($win | map(select((.event == "done" or .event == "reopen") and orphan)) | length)
  }' "$STORE" 2>/dev/null)" || READ=""

printf '%s' "$READ" | jq -e 'type == "object"' >/dev/null 2>&1 || { WHY="read-failed"; emit; }

_num() { local v; v="$(printf '%s' "$READ" | jq -r --arg k "$1" '.[$k] // 0')"
         case "$v" in ''|*[!0-9-]*) printf '0' ;; *) printf '%s' "$v" ;; esac; }
TOTAL="$(_num records)"; UNPARSED="$(_num unparsed)"
ADDED="$(_num added)";   CLOSED="$(_num closed)"; REOPENED="$(_num reopened)"
UNATTRIBUTED="$(_num unattributed)"
NET=$(( ADDED - CLOSED ))

OLDEST="$(printf '%s' "$READ" | jq -r '.oldest // "null"')"
case "$OLDEST" in ''|null|*[!0-9]*) OLDEST="" ;; esac

# ── guard 2: an empty trail is not a draining week, it is no week at all ───────────────────────
[ "$TOTAL" -gt 0 ] && [ -n "$OLDEST" ] || { WHY="read-failed"; emit; }

# ── guard 3: the window must fit the history it is measured over ──────────────────────────────
HISTORY=$(( NOW - OLDEST )); [ "$HISTORY" -ge 0 ] || HISTORY=0
if [ "$HISTORY" -lt "$WINDOW" ]; then WHY="short-history"; emit; fi

# ── guard 4: excluded evidence is not absent evidence ─────────────────────────────────────────
_ABS=$NET; [ "$_ABS" -ge 0 ] || _ABS=$(( -_ABS ))
if [ "$UNPARSED" -gt "$_ABS" ]; then WHY="unparsed-could-flip"; emit; fi

# ── the verdict ───────────────────────────────────────────────────────────────────────────────
if [ "$NET" -gt 0 ]; then
  VERDICT="net-positive"; WHY="added-gt-closed"
  # No figures in the title, on purpose — see the header. The window and the prescription are
  # stable while the condition holds, so this row is written once and updated never.
  TITLE="$(printf 'the backlog took in more work than it closed over the last %sd — BACKLOG_DRAIN_24_7 §6 says a net-positive week means the INFLOW list (C1-C4) gets the next fix, not more drain horsepower. Current figures: scripts/backlog-flow-assert.sh --json' "$DAYS")"
else
  VERDICT="draining"; WHY="closed-ge-added"
fi
emit
