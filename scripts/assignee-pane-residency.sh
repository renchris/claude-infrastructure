#!/bin/bash
# assignee-pane-residency.sh — do assignee panes actually LEAVE, measured against the world.
#
# WHY THIS EXISTS. Four consecutive fixes to the assignee self-close chain each went green on the
# mechanism they named and moved the real outcome by exactly zero. Every one of them was verified
# against a defer-reason or an internal predicate — never against the world. Ten days produced zero
# closes while a dozen assignee panes sat resident, and the only instrument watching
# (scripts/teammate-reap-alarm.sh) counted our own log lines, so a rerouted close, a backend swap or
# a gate change could satisfy it without a single pane going away.
#
# So this file measures ONE thing and takes it from three sources that do not depend on each other:
#
#   WIN   `it2 session list` — the terminal's own live window ids (integers under the kitty
#         backend; bin/it2 diverts to bin/it2-kitty inside kitty).
#   MEM   every ~/.claude*/teams/*/config.json member carrying an INTEGER tmuxPaneId. Integer ⇒
#         kitty window; "leader" is the in-process lead and a UUID is an iTerm2 session, neither of
#         which is the population this alarm is about.
#   PROC  `ps -ax -o command=` filtered on the assignee's own argv (`--agent-id name@team`,
#         `--agent-name name`). This is the one source that needs no terminal, no socket and no
#         cooperation from anything we wrote.
#
# RESIDENCY IS THE UNION, NOT THE INTERSECTION, AND THAT DIRECTION IS DELIBERATE. A member counts as
# resident if EITHER the window list still holds its pane OR the process table still holds its
# argv. Requiring both would report a departure the moment either source went blind — and a false
# departure in this instrument reads as "the fix worked", which is precisely the mistake that cost
# ten days. Over-counting residency can only ever push toward ALARM, i.e. toward looking.
#
# DEPARTURE IS A SET DIFFERENCE, NEVER A COUNT DIFFERENCE. The previous sample's resident set is
# persisted under $CC_RESIDENCY_STATE_DIR and `departed` = prev \ now, keyed on team/name/pane. A
# count delta is not the same measurement: it silently cancels a true departure against a newly
# spawned member, so a fleet that closes one pane and opens one reads as "nothing happened". That
# exact bug is live today at bin/cc-reaper:639, where a self-check compares two counts and a
# compensating pair of errors reads as agreement.
#
# 🚨 ATTRIBUTION — A DEPARTURE IS NOT AUTOMATICALLY OURS. Team session-57342265 had six members
# closed and de-registered from config.json with ZERO lines in teammate-lifecycle.log while its lead
# stayed alive: the vendor closed them, not our chain. If this instrument counted those six, the
# first departure it ever saw would have been read as proof the fix worked — the same error in a new
# coat. So a departure is attributed to US only when the lifecycle log carries a `✓ closed pane
# <pane> (<name>)` line naming BOTH that pane id and that member, timestamped at or after the
# previous sample. Anything else is reported as vendor/unattributed, and unattributed departures
# never satisfy the OK arm.
#
# READ-ONLY BY CONSTRUCTION. The only thing this script writes is its own state file. It closes no
# pane, edits no team config, touches no worktree, and never calls it2 with anything but
# `session list`. tests/assignee-pane-residency.bats pins the absence of every actuator verb.
#
# FIVE VERDICTS, and "could not measure" must never render as "fine":
#   OK             panes departed by OUR hand since the last sample.            exit 0
#   NOT-EXERCISED  nothing to assert: no assignee panes, no prior sample, or
#                  too few stale residents. A DISTINCT verdict, never a quiet
#                  OK — "the fix worked" and "no teams ran" reading identically
#                  is half the reason nine days passed in silence.              exit 0
#   WARN           panes departed but none of them by our hand, or our share
#                  of the pile is below the floor.                              exit 1
#   ALARM          >=MIN_EVENTS members resident past the staleness threshold
#                  and NOTHING departed.                                        exit 2
#   NO-DATA        every source is blind — nothing is asserted.                 exit 3
#
# THE VERDICT TOKEN. Every run prints exactly one line of the form
#   verdict=<V> members=… resident=… stale=… departed=… ours=… vendor=… …
# on stdout. A consumer must be able to `grep -o 'verdict=[A-Z-]*'` without re-deriving anything,
# and because the token carries the verdict independently of the exit status, a `|| true` in a
# caller cannot launder it (memory: claimed-outcome-vs-checked-outcome).
#
# Self-test: `--selftest` drives the SAME join and the SAME arithmetic through fixtures for every
# verdict, including the two that matter — a dead path must read ALARM and a live one OK off one
# parser. A checker that cannot produce its own failing case is not evidence.

set -uo pipefail

STATE_DIR="${CC_RESIDENCY_STATE_DIR:-$HOME/.claude/watchdog}"
STATE_FILE="$STATE_DIR/assignee-residency.state"
LIFECYCLE="${TEAMMATE_LIFECYCLE_LOG:-$HOME/.claude/logs/teammate-lifecycle.log}"
TEAM_GLOB="${CC_RESIDENCY_TEAM_GLOB:-$HOME/.claude*/teams/*/config.json}"
IT2_BIN="${CC_RESIDENCY_IT2_BIN:-it2}"
PS_BIN="${CC_RESIDENCY_PS_BIN:-/bin/ps}"
JQ_BIN="${CC_RESIDENCY_JQ_BIN:-jq}"
# How long a member may sit resident before it counts toward the pile. Anchored on the vendor's own
# `joinedAt`, not on anything we log — see stale_residents() for why that matters.
STALE_H="${CC_RESIDENCY_STALE_H:-4}"
MIN_EVENTS="${CC_RESIDENCY_MIN_EVENTS:-5}"
WARN_RATE_PCT="${CC_RESIDENCY_WARN_RATE_PCT:-10}"
WANT_JSON=0
QUIET=0
NO_STATE=0
SELFTEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --json)      WANT_JSON=1 ;;
    --quiet|-q)  QUIET=1 ;;
    # Read the cursor, do not advance it. The reap alarm calls this script and MUST NOT consume the
    # departures the periodic sampler is there to observe — two writers to one cursor means each
    # one sees only what the other left behind.
    --no-state)  NO_STATE=1 ;;
    --selftest)  SELFTEST=1 ;;
    --state-dir) STATE_DIR="${2:-}"; STATE_FILE="$STATE_DIR/assignee-residency.state"; shift ;;
    --log)       LIFECYCLE="${2:-}"; shift ;;
    -h|--help)   sed -n '2,70p' "$0"; exit 0 ;;
    *)           echo "unknown arg: $1" >&2; exit 64 ;;
  esac
  shift
done

# Scratch for the source reads. Each source function writes its DATA to a file and returns only a
# status word, because a function whose output is captured with `$( )` runs in a subshell — any
# status it assigned to a variable is discarded the moment the substitution closes, and the caller
# would read the initialised value forever. That is not a stylistic point: the first cut of this
# file did exactly that and every source reported `unreachable` on a healthy box, which is the
# NO-DATA arm firing on perfect evidence.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/residency-work.XXXXXX")" || exit 70
trap 'rm -rf "$WORK"' EXIT

# ── source 1: the terminal's live window ids ─────────────────────────────────────────────────────
# Only integer ids are kept. On an iTerm2 box `session list` answers with UUIDs, which are simply
# not the population this file tracks — that is `empty`, not `unreachable`, and PROC still carries
# the join. Distinguishing the two matters: `unreachable` must never be read as "they all left".
win_ids() { # <outfile> → echoes the status word
  local out rc=0
  : > "$1"
  out="$("$IT2_BIN" session list 2>/dev/null)" || rc=$?
  if [ "$rc" -ne 0 ]; then echo "unreachable"; return; fi
  printf '%s\n' "$out" | grep -E '^[0-9]+$' > "$1" 2>/dev/null || true
  if [ -s "$1" ]; then echo "ok"; else echo "empty"; fi
}

# ── source 2: the process table ──────────────────────────────────────────────────────────────────
# Emits `name@team` keys plus bare `name` keys. Both are only ever tested for MEMBERSHIP of the
# known member set, which is what keeps a brief that merely MENTIONS `--agent-id` from inventing a
# member (memory: pgrep-f-matches-agent-briefs — argv carries whole briefs, so a substring match
# over the process table counts sessions that merely talk about the thing). A spurious match here
# can only make a member look resident, i.e. push toward ALARM, never toward a false all-clear.
proc_ids() { # <outfile> → echoes the status word
  local out rc=0
  : > "$1"
  out="$("$PS_BIN" -ax -o command= 2>/dev/null)" || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then echo "unreachable"; return; fi
  printf '%s\n' "$out" \
    | grep -oE -- '--agent-(id|name) [A-Za-z0-9_@.-]+' 2>/dev/null \
    | sed -E 's/^--agent-(id|name) //' | sort -u > "$1" 2>/dev/null || true
  echo "ok"
}

# ── source 3: the declared members ───────────────────────────────────────────────────────────────
# team<TAB>name<TAB>pane<TAB>joinedAt_ms, one line per member with an INTEGER tmuxPaneId.
# jq is required and its absence is NO-DATA, never zero members: reading zero members would render
# NOT-EXERCISED, which is exactly the conflation of "nothing to close" with "nothing broke" that
# this instrument exists to end.
members() { # <outfile> → echoes the status word
  : > "$1"
  if ! command -v "$JQ_BIN" >/dev/null 2>&1; then echo "no-jq"; return; fi
  local cfg team out raw=""
  # shellcheck disable=SC2086
  # TEAM_GLOB is a seam holding a GLOB — it must word-split and expand, which is the whole point.
  for cfg in $TEAM_GLOB; do
    [ -r "$cfg" ] || continue
    team="$(basename "$(dirname "$cfg")")"
    # shellcheck disable=SC2016  # $t is a jq variable bound by --arg — single quotes are REQUIRED
    #
    # PAD AT THE EMITTER. Tab is an IFS-*whitespace* character, so the `IFS=$'\t' read -r team name
    # pane _joined` in the render below collapses a RUN of delimiters into one: an empty cell does
    # NOT produce an empty variable, it shifts every LATER column one position LEFT, silently, at
    # exit status 0. `.name // "?"` looks like it already prevents that and does NOT: jq's `//`
    # fires on null/false ONLY, and "" is TRUTHY in jq — so a member declaring `"name": ""` passes
    # straight through the default and emits an empty cell 2. The row then reads
    # team=<team> name=<paneId> pane=<joinedAt>, i.e. the render names the member after its own
    # pane id, on the instrument whose whole job is telling a resident member from a departed one.
    # `def cell` keys on emptiness rather than on null, which is the distinction `//` cannot make.
    out="$("$JQ_BIN" -r --arg t "$team" '
      def cell: (if . == null or . == "" then "?" else . end) | tostring;
      .members[]?
      | select(((.tmuxPaneId // "") | tostring) | test("^[0-9]+$"))
      | [($t|cell), (.name|cell), (.tmuxPaneId|tostring),
         (.joinedAt | if . == null or . == "" then 0 else . end | tostring)]
      | @tsv' "$cfg" 2>/dev/null)" || continue
    [ -n "$out" ] || continue
    raw="$raw$out
"
  done
  printf '%s' "$raw" | grep . | sort -u > "$1" 2>/dev/null || true
  if [ -s "$1" ]; then echo "ok"; else echo "empty"; fi
}

# ── the join ─────────────────────────────────────────────────────────────────────────────────────
# Everything below is a pure function of (MEMBERS, WIN, PROC, PREV, LIFECYCLE, now) so --selftest
# drives the same arithmetic production does. A self-test on a different code path proves nothing.
#
# Every multi-line set travels between these helpers as a FILE, never as `awk -v`. BSD awk rejects a
# newline inside a -v assignment ("awk: newline in string …") and then runs the program with the
# variable EMPTY — so the set-membership tables silently come up empty and every member reads as
# departed. It fails on stderr while still exiting 0, which is the worst possible shape here: the
# verdict quietly inverts toward "they all left" while the run looks successful.
nlines() { [ -r "$1" ] && awk 'END { print NR }' "$1" || echo 0; }

join_resident() { # <members-file> <wins-file> <procs-file> <outfile>
  awk -F'\t' '
    FILENAME == ARGV[1] { if ($0 != "") W[$0] = 1; next }
    FILENAME == ARGV[2] { if ($0 != "") P[$0] = 1; next }
    NF >= 3 {
      # Union: the window list OR the process table. Either one still holding it means it is here.
      if (($3 in W) || (($2 "@" $1) in P) || ($2 in P)) print
    }' "$2" "$3" "$1" > "$4" 2>/dev/null || true
}

# Last lifecycle DECISION timestamp per member name, in one pass. The four shapes the close path
# writes: `defer <n> (`, `⚑ SURFACE <n> (`, `✓ closed pane <pane> (<n>)`, and the `  ↳ <n>: ` notes.
#
# ⚠ NOT ONE `RSTART + <literal length>` ANYWHERE, AND THAT IS THE POINT. `✓`, `⚑` and `↳` are
# three-byte UTF-8 characters, and BSD awk indexes match() in BYTES — so `RSTART + 14` for the
# 14-CHARACTER prefix "✓ closed pane " lands two bytes short and silently yields a garbage name.
# It was worth an hour: the attribution arm read zero every time, the departures fell through to
# "unattributed", and the self-test still went green because the vendor arm produces the same
# verdict. Every extraction below is therefore regex-anchored sub(), which cannot drift.
last_decisions() { # <log> → name\tepoch_seconds
  [ -r "$1" ] || return 0
  awk '
    match($0, /^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]/) {
      ts = substr($0, 2, 19); rest = $0; sub(/^\[[^]]*\] ?/, "", rest)
      name = ""
      if (match(rest, /^defer [A-Za-z0-9_.-]+/)) {
        name = substr(rest, RSTART, RLENGTH); sub(/^defer +/, "", name)
      } else if (match(rest, /⚑ SURFACE [A-Za-z0-9_.-]+/)) {
        name = substr(rest, RSTART, RLENGTH); sub(/^.*SURFACE +/, "", name)
      } else if (match(rest, /✓ closed pane [0-9A-Za-z-]+ \([A-Za-z0-9_.-]+\)/)) {
        name = substr(rest, RSTART, RLENGTH); sub(/^.*\(/, "", name); sub(/\)$/, "", name)
      } else if (match(rest, /↳ [A-Za-z0-9_.-]+:/)) {
        name = substr(rest, RSTART, RLENGTH); sub(/^.*↳ +/, "", name); sub(/:$/, "", name)
      }
      if (name != "") LAST[name] = ts
    }
    END { for (k in LAST) printf "%s\t%s\n", k, LAST[k] }' "$1" 2>/dev/null
}

# Departures the lifecycle log CLAIMS, at or after <since-epoch>, as `pane\tname` keys. Both fields
# are required: a close line that names one but not the other cannot attribute a departure, and an
# unattributable departure is the loud verdict, not the quiet one.
our_closes_since() { # <log> <since_epoch> → pane\tname
  [ -r "$1" ] || return 0
  local since_str
  since_str="$(date -r "$2" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" || return 0
  [ -n "$since_str" ] || return 0
  awk -v since="$since_str" '
    match($0, /^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]/) {
      ts = substr($0, 2, 19)
      if (ts < since) next
      # Lexical compare on `YYYY-MM-DD HH:MM:SS` IS chronological — no per-line parsing, no locale.
      if (match($0, /✓ closed pane [0-9A-Za-z-]+ \([A-Za-z0-9_.-]+\)/)) {
        s = substr($0, RSTART, RLENGTH); sub(/^.*closed pane +/, "", s)
        p = s; sub(/ .*$/, "", p)
        n = s; sub(/^[^(]*\(/, "", n); sub(/\)$/, "", n)
        if (p != "" && n != "") printf "%s\t%s\n", p, n
      }
    }' "$1" 2>/dev/null | sort -u
}

read_prev() { # → sets PREV_TS (epoch, "" if none) and echoes prev resident keys team\tname\tpane
  PREV_TS=""
  [ -r "$STATE_FILE" ] || return 0
  PREV_TS="$(sed -n 's/^ts //p' "$STATE_FILE" 2>/dev/null | tail -1)"
  case "$PREV_TS" in (*[!0-9]*|"") PREV_TS="" ;; esac
  sed -n 's/^r //p' "$STATE_FILE" 2>/dev/null
}

write_state() { # <now_epoch> <resident-file>
  [ "$NO_STATE" = 1 ] && { STATE_WRITE="skipped"; return 0; }
  mkdir -p "$STATE_DIR" 2>/dev/null || { STATE_WRITE="failed"; return 0; }
  local tmp="$STATE_FILE.$$"
  {
    echo "# assignee-pane-residency state v1 — the PREVIOUS sample's resident set."
    echo "ts $1"
    awk -F'\t' 'NF>=3 { printf "r %s\t%s\t%s\n", $1, $2, $3 }' "$2" 2>/dev/null || true
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$STATE_FILE" 2>/dev/null && STATE_WRITE="ok" || STATE_WRITE="failed"
  rm -f "$tmp" 2>/dev/null
  return 0
}

measure() {
  local now now_ms
  now="$(date +%s)"; now_ms=$(( now * 1000 ))
  STATE_WRITE="n/a"
  SRC_WIN="unreachable"; SRC_PROC="unreachable"; SRC_MEM="empty"

  SRC_MEM="$(members "$WORK/members")"
  MEMBER_N="$(nlines "$WORK/members")"

  if [ "$SRC_MEM" = "no-jq" ]; then
    VERDICT="NO-DATA"; RC=3
    DETAIL="jq is not on PATH — the member set cannot be read, so nothing is asserted"
    RESIDENT=""; RESIDENT_N=0; STALE_N=0; DEPARTED_N=0; OURS_N=0; VENDOR_N=0; PREV_TS=""
    return
  fi

  # Short-circuit BEFORE touching the terminal or the process table: with no declared assignee panes
  # there is no join to make, and a box that never ran a team must not pay for an it2 probe (nor
  # make a hermetic suite depend on one).
  if [ "$MEMBER_N" -eq 0 ]; then
    VERDICT="NOT-EXERCISED"; RC=0
    DETAIL="no team config on this box records an integer (kitty) assignee pane — nothing to close"
    SRC_MEM="empty"
    RESIDENT=""; RESIDENT_N=0; STALE_N=0; DEPARTED_N=0; OURS_N=0; VENDOR_N=0; PREV_TS=""
    return
  fi

  SRC_WIN="$(win_ids "$WORK/wins")"
  SRC_PROC="$(proc_ids "$WORK/procs")"

  # Every source blind ⇒ we are not looking at the world at all. Reporting zero residents here would
  # manufacture "everything departed", the single most dangerous false reading this file can make.
  if [ "$SRC_WIN" != "ok" ] && [ "$SRC_PROC" != "ok" ]; then
    VERDICT="NO-DATA"; RC=3
    DETAIL="both the window list ($SRC_WIN) and the process table ($SRC_PROC) are blind — residency is UNKNOWN, not zero"
    RESIDENT=""; RESIDENT_N=0; STALE_N=0; DEPARTED_N=0; OURS_N=0; VENDOR_N=0; PREV_TS=""
    return
  fi

  join_resident "$WORK/members" "$WORK/wins" "$WORK/procs" "$WORK/resident"
  RESIDENT="$(cat "$WORK/resident")"
  RESIDENT_N="$(nlines "$WORK/resident")"

  # Staleness is anchored on the vendor's own joinedAt, NOT on anything we logged. That is the whole
  # point of the rewrite: an age derived from our log would go quiet in exactly the failure where
  # our log stops being written, which is one of the two proven blind spots.
  local stale_ms=$(( STALE_H * 3600 * 1000 ))
  awk -F'\t' -v now="$now_ms" -v lim="$stale_ms" \
    'NF>=4 && $4+0 > 0 && (now - $4) >= lim { print }' "$WORK/resident" > "$WORK/stale" 2>/dev/null || true
  STALE_N="$(nlines "$WORK/stale")"

  read_prev > "$WORK/prev"

  # FIRST SAMPLE. There is no previous resident set, so `departed` is UNKNOWN — and a lookup miss is
  # not an absence (memory: lookup-miss-is-not-absence). Reading it as zero would let the very first
  # run ALARM on a fleet that is closing panes perfectly well.
  if [ -z "${PREV_TS:-}" ]; then
    write_state "$now" "$WORK/resident"
    VERDICT="NOT-EXERCISED"; RC=0
    DETAIL="first sample — no previous resident set, so departures are UNKNOWN (not zero); $RESIDENT_N resident, $STALE_N stale"
    DEPARTED=""; DEPARTED_N=0; OURS_N=0; VENDOR_N=0
    return
  fi

  # A real set difference on team/name/pane. Not a count delta: a count delta cancels a genuine
  # departure against a fresh spawn and reports "nothing happened" (bin/cc-reaper:639).
  awk -F'\t' '
    FILENAME == ARGV[1] { if (NF>=3) C[$1 "\t" $2 "\t" $3] = 1; next }
    NF>=3 { k = $1 "\t" $2 "\t" $3; if (!(k in C)) print k }' \
    "$WORK/resident" "$WORK/prev" | sort -u > "$WORK/departed" 2>/dev/null || true
  DEPARTED="$(cat "$WORK/departed")"
  DEPARTED_N="$(nlines "$WORK/departed")"

  # Attribution. Strict on purpose: a close line must name BOTH the pane and the member, at or after
  # the previous sample. Anything looser would let the vendor's six silent closes (team
  # session-57342265) be read as ours, and the first departure this alarm ever saw would have been
  # mistaken for proof the fix worked.
  our_closes_since "$LIFECYCLE" "$PREV_TS" > "$WORK/claims"
  awk -F'\t' '
    FILENAME == ARGV[1] { if ($0 != "") K[$0] = 1; next }
    NF>=3 { if (($3 "\t" $2) in K) print }' \
    "$WORK/claims" "$WORK/departed" > "$WORK/ours" 2>/dev/null || true
  OURS_N="$(nlines "$WORK/ours")"
  VENDOR_N=$(( DEPARTED_N - OURS_N ))

  write_state "$now" "$WORK/resident"

  # ── the verdict. One predicate, five outcomes, MECE. ───────────────────────────────────────────
  if [ "$OURS_N" -gt 0 ]; then
    local denom=$(( OURS_N + STALE_N )) rate=100
    [ "$denom" -gt 0 ] && rate=$(( OURS_N * 100 / denom ))
    if [ "$rate" -lt "$WARN_RATE_PCT" ]; then
      VERDICT="WARN"; RC=1
      DETAIL="we closed $OURS_N pane(s) but $STALE_N stale resident(s) remain (${rate}%, floor ${WARN_RATE_PCT}%)"
    else
      VERDICT="OK"; RC=0
      DETAIL="$OURS_N pane(s) departed BY OUR HAND since the last sample ($STALE_N stale resident(s) remain)"
    fi
  elif [ "$STALE_N" -lt "$MIN_EVENTS" ]; then
    VERDICT="NOT-EXERCISED"; RC=0
    DETAIL="only $STALE_N member(s) resident past ${STALE_H}h (need >=$MIN_EVENTS to assert) — nothing claimed"
  elif [ "$VENDOR_N" -gt 0 ]; then
    VERDICT="WARN"; RC=1
    DETAIL="$DEPARTED_N pane(s) departed but NONE by our hand — $VENDOR_N unattributed (vendor/manual); $STALE_N still resident past ${STALE_H}h"
  else
    VERDICT="ALARM"; RC=2
    DETAIL="$STALE_N member(s) resident past ${STALE_H}h and NOTHING departed — the close path is not moving the world"
  fi
}

# ── self-test — the positive control ─────────────────────────────────────────────────────────────
# The point is not that a healthy fleet passes. It is that ONE parser emits ALARM on a dead path and
# OK on a live one, and that a vendor departure does not read as ours.
if [ "$SELFTEST" = 1 ]; then
  fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/residency.XXXXXX")" || exit 70
  trap 'rm -rf "$tmp" "$WORK"' EXIT
  mkdir -p "$tmp/teams/session-aa" "$tmp/state"
  export CC_RESIDENCY_STATE_DIR="$tmp/state"
  STATE_DIR="$tmp/state"; STATE_FILE="$STATE_DIR/assignee-residency.state"
  TEAM_GLOB="$tmp/teams/*/config.json"
  LIFECYCLE="$tmp/lifecycle.log"; : > "$LIFECYCLE"

  # Stub sources. The stubs replace only the two EXTERNAL reads; the join, the set difference, the
  # attribution and the verdict are the production code paths verbatim.
  printf '#!/bin/bash\ncat "%s/wins"\n' "$tmp" > "$tmp/it2"; chmod +x "$tmp/it2"
  printf '#!/bin/bash\ncat "%s/procs"\n' "$tmp" > "$tmp/ps";  chmod +x "$tmp/ps"
  IT2_BIN="$tmp/it2"; PS_BIN="$tmp/ps"
  : > "$tmp/procs"

  old_ms=$(( ($(date +%s) - 86400) * 1000 ))
  seed() { # seed <n> — n members, all joined a day ago, panes 401..
    local n="$1" i j=""
    for ((i=0; i<n; i++)); do
      j="$j$([ -n "$j" ] && echo ,)"'{"name":"m'"$i"'","tmuxPaneId":"'"$((401+i))"'","joinedAt":'"$old_ms"'}'
    done
    printf '{"name":"session-aa","members":[%s]}\n' "$j" > "$tmp/teams/session-aa/config.json"
  }
  live() { local i; : > "$tmp/wins"; for ((i=0; i<$1; i++)); do echo $((401+i)) >> "$tmp/wins"; done; }
  check() { # check <label> <want_verdict> <want_rc> [want_ours] [want_vendor]
    measure
    local ok=1
    [ "$VERDICT" = "$2" ] && [ "$RC" = "$3" ] || ok=0
    # The counts are asserted, not just the verdict. WARN is reachable two ways — "we closed some but
    # not enough" and "things left but none by our hand" — so a verdict-only assertion on the
    # attribution arm passes while attribution is returning zero. It did exactly that here.
    [ -n "${4:-}" ] && { [ "${OURS_N:-0}" = "$4" ] || ok=0; }
    [ -n "${5:-}" ] && { [ "${VENDOR_N:-0}" = "$5" ] || ok=0; }
    if [ "$ok" = 1 ]; then echo "ok   $1 → $VERDICT ($RC) ours=${OURS_N:-0} vendor=${VENDOR_N:-0}"
    else echo "FAIL $1 → got $VERDICT ($RC) ours=${OURS_N:-0} vendor=${VENDOR_N:-0}, want $2 ($3) ours=${4:-*} vendor=${5:-*}"; fail=1; fi
  }

  seed 12; live 12
  check "first sample asserts nothing"            NOT-EXERCISED 0
  check "12 resident, nothing departed"           ALARM         2

  # A vendor departure: six panes vanish with ZERO lifecycle lines. It must NOT read as OK, and the
  # six must land in `vendor`, never in `ours` — this is the arm that stops the FIRST departure this
  # instrument ever sees from being mistaken for proof the fix worked.
  live 6
  check "silent vendor departure is WARN, not OK" WARN          1 0 6

  # POSITIVE CONTROL for the arm above — the SAME six departures, now with a `✓ closed pane <pane>
  # (<name>)` line each. Identical world, opposite attribution: if these two ever agree, the
  # attribution is not reading the log at all.
  rm -f "$STATE_FILE"; live 12; measure >/dev/null   # re-seat the cursor with all 12 resident
  for i in 0 1 2 3 4 5; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')]   ✓ closed pane $((401+i)) (m$i)" >> "$LIFECYCLE"
  done
  live 12; sed -i '' '1,6d' "$tmp/wins" 2>/dev/null || true
  check "the SAME six, attributed to us, read OK"  OK            0 6 0

  # A quiet fleet: too few stale residents to assert. Never a silent OK.
  : > "$LIFECYCLE"; seed 2; live 2; rm -f "$STATE_FILE"; measure >/dev/null
  check "quiet fleet is NOT-EXERCISED"            NOT-EXERCISED 0

  # No teams at all — distinct from OK, and it must not fire an it2 probe.
  rm -f "$tmp/teams/session-aa/config.json"; rm -f "$STATE_FILE"
  check "no assignee panes is NOT-EXERCISED"      NOT-EXERCISED 0

  # Both sources blind is NO-DATA. Residency UNKNOWN must never render as "they all left".
  seed 12; printf '#!/bin/bash\nexit 1\n' > "$tmp/it2"; printf '#!/bin/bash\nexit 1\n' > "$tmp/ps"
  check "every source blind is NO-DATA"           NO-DATA       3

  [ "$fail" = 0 ] && echo "selftest: all pass" || echo "selftest: FAILURES"
  exit "$fail"
fi

# ── live run ─────────────────────────────────────────────────────────────────────────────────────
measure
TS="$(date +%Y-%m-%dT%H:%M:%S)"

if [ "$QUIET" != 1 ] && [ "$WANT_JSON" != 1 ]; then
  echo "assignee-pane-residency — $TS"
  echo "  sources:             windows=$SRC_WIN  procs=$SRC_PROC  members=$SRC_MEM  cursor=${STATE_WRITE:-n/a}"
  echo "  declared members:    ${MEMBER_N:-0}   (integer/kitty panes only)"
  echo "  resident now:        ${RESIDENT_N:-0}   (${STALE_N:-0} past ${STALE_H}h)"
  echo "  departed since prev: ${DEPARTED_N:-0}   (ours ${OURS_N:-0} · unattributed ${VENDOR_N:-0})"
  if [ -n "${RESIDENT:-}" ]; then
    DEC="$(last_decisions "$LIFECYCLE")"
    NOW_S="$(date +%s)"
    echo "  resident members:"
    printf '%s\n' "$RESIDENT" | while IFS=$'\t' read -r team name pane _joined; do
      [ -n "${name:-}" ] || continue
      dts="$(printf '%s\n' "$DEC" | awk -F'\t' -v k="$name" '$1==k{v=$2} END{print v}')"
      if [ -n "$dts" ]; then
        de="$(date -j -f '%Y-%m-%d %H:%M:%S' "$dts" +%s 2>/dev/null || echo "")"
        if [ -n "$de" ]; then age="$(( (NOW_S - de) / 3600 ))h since last decision"
        else age="last decision unparseable"; fi
      else
        age="NO lifecycle decision ever — the close path has never looked at it"
      fi
      echo "      ${team##*-}/${name} pane=${pane}  ${age}"
    done
  fi
  if [ -n "${DEPARTED:-}" ]; then
    echo "  departures:"
    awk -F'\t' '
      FILENAME == ARGV[1] { if ($0 != "") K[$0] = 1; next }
      NF>=3 { printf "      %s/%s pane=%s  %s\n", $1, $2, $3, (($0 in K) ? "OURS (✓ closed pane)" : "UNATTRIBUTED — vendor or manual, NOT proof our chain works") }' \
      "$WORK/ours" "$WORK/departed"
  fi
  echo "  VERDICT:             $VERDICT — $DETAIL"
fi

if [ "$WANT_JSON" = 1 ]; then
  printf '{"ts":"%s","verdict":"%s","members":%s,"resident":%s,"stale":%s,"departed":%s,"ours":%s,"vendor":%s,"stale_h":%s,"min_events":%s,"src_win":"%s","src_proc":"%s","src_mem":"%s","prev_ts":"%s","detail":"%s"}\n' \
    "$TS" "$VERDICT" "${MEMBER_N:-0}" "${RESIDENT_N:-0}" "${STALE_N:-0}" "${DEPARTED_N:-0}" \
    "${OURS_N:-0}" "${VENDOR_N:-0}" "$STALE_H" "$MIN_EVENTS" "$SRC_WIN" "$SRC_PROC" "$SRC_MEM" \
    "${PREV_TS:-none}" "$DETAIL"
fi

# THE TOKEN — always, on every path, including --quiet. A consumer greps this; it never re-derives
# the verdict, and because the verdict travels in the text a `|| true` on the call cannot launder it.
#
# `state=` is in the token because a cursor write that FAILED is not a cosmetic detail: the next
# sample would then difference against a stale resident set and report departures that already
# happened, or none at all. A silent `failed` here would corrupt the one measurement this file
# exists to make, one tick later, with nothing in the output to say why.
printf 'verdict=%s members=%s resident=%s stale=%s departed=%s ours=%s vendor=%s stale_h=%s min_events=%s src_win=%s src_proc=%s src_mem=%s prev=%s state=%s rc=%s\n' \
  "$VERDICT" "${MEMBER_N:-0}" "${RESIDENT_N:-0}" "${STALE_N:-0}" "${DEPARTED_N:-0}" \
  "${OURS_N:-0}" "${VENDOR_N:-0}" "$STALE_H" "$MIN_EVENTS" "$SRC_WIN" "$SRC_PROC" "$SRC_MEM" \
  "${PREV_TS:-none}" "${STATE_WRITE:-n/a}" "${RC:-0}"

exit "${RC:-0}"
