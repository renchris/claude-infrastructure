#!/bin/bash
# teammate-reap-alarm.sh — does the teammate idle-close path still CLOSE anything?
#
# WHY THIS EXISTS. On 2026-07-25 15:45:49 the last automatic teammate pane close happened. For the
# nine days after it, every single close attempt refused, and nobody noticed — while four separate
# investigations each found a real defect, fixed it, verified the fix against the reason it was
# written for, and declared the class resolved. They were all honest and all wrong, because the
# thing being verified was a MECHANISM and the thing that had failed was the OUTCOME.
#
# The failure shape is specific and it is what this file watches for. teammate-auto-shutdown.sh is a
# chain of fail-closed gates over ONE question — "is this member's tree clean?" — which is
# unanswerable when the member has no resolvable tree of its own. Clearing any one gate's reason
# just hands the refusal to the next gate. So the log kept CHANGING (203 dirty-tree, then 128
# WORKTREE-unresolved, then 112 shared-cwd) while the outcome sat at zero the whole time. Reading
# reasons could not distinguish four fixes from no fix at all. Only `✓ closed pane` can.
#
# THIS IS AN ALARM, NOT A GATE. It never refuses a spawn, never closes a pane, never blocks a land.
# It reports and exits. The one thing it owes the operator is that a nine-day outage becomes
# visible on day two.
#
# THE DENOMINATOR IS THE WHOLE DESIGN (memory: alarm-polarity-and-attention-budget,
# positive-control-the-denominator). "Zero closes" is not evidence of anything on a machine that
# spawned no teams — an alarm that fires on a quiet week carries exactly as many bits as one that
# never fires. So the verdict is only ever asserted against the number of times the close path
# actually RAN. Below MIN_EVENTS the honest answer is NOT-EXERCISED, a distinct verdict, never a
# quiet OK.
#
# GETTING THAT DENOMINATOR RIGHT TOOK TWO TRIES, AND THE FIRST ONE PASSED ITS OWN TESTS.
# The obvious choice — `Auto-shutdown idle teammate:` — is WRONG. That line is logged at
# teammate-auto-shutdown.sh:837, i.e. AFTER every defer and SURFACE (:620-:823), so it is emitted
# only on the path that is about to succeed. It is a near-synonym for the numerator. Against the
# live log it read 3 attempts in a window holding 187 refusals, and the whole instrument reported
# NOT-EXERCISED while the fleet was in a nine-day outage — the failure mode it was built to detect.
# It went undetected by a self-test whose fixtures I had hand-written in the shape I ASSUMED, which
# is the vacuous-control trap (memory: control-must-replay-the-real-artifact): an approximation
# agrees with itself. The fixtures below are now cut to the real log's shape — refusals with no
# header line above them — so the control can fail the same way production does.
#
# The denominator is therefore attempts = closes + REFUSALS, where a refusal is a `defer`/`SURFACE`
# line EXCLUDING the two that mean the teammate is legitimately still working (`.teammate-busy
# marker present`, `tool in flight`). Deferring a busy teammate is the system working, not a
# refusal to close a finished one, and counting it would let a healthy fleet drift toward ALARM.
#
# FOUR VERDICTS, NEVER A BOOLEAN — "could not measure" must not render as "fine":
#   OK             the path ran and closed things.                        exit 0
#   NOT-EXERCISED  too few idle events in the window to assert anything.  exit 0
#   WARN           the path ran and closed almost nothing.                exit 1
#   ALARM          the path ran >=MIN_EVENTS times and closed NOTHING.    exit 2
#   NO-DATA        the log is absent or unreadable — nothing is asserted. exit 3
#
# Only /usr/bin + /bin tools (date, grep, awk, sed) — no jq, no Homebrew. This runs from launchd
# under PATH=/usr/bin:/bin:/usr/sbin:/sbin, where a bare Homebrew name does not exist at all
# (memory: path-resolved-dependency-in-daemon-code).
#
# Self-test: `teammate-reap-alarm.sh --selftest` drives synthetic logs through every verdict,
# including the two that matter most — a healthy fleet must read OK and a dead path must read
# ALARM on the SAME parser. A checker that cannot produce its own failing case is not evidence.

set -uo pipefail

LOG="${TEAMMATE_LIFECYCLE_LOG:-$HOME/.claude/logs/teammate-lifecycle.log}"
WINDOW_D="${REAP_ALARM_WINDOW_D:-3}"
MIN_EVENTS="${REAP_ALARM_MIN_EVENTS:-10}"
WARN_RATE_PCT="${REAP_ALARM_WARN_RATE_PCT:-10}"
WANT_JSON=0
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --json)     WANT_JSON=1 ;;
    --quiet|-q) QUIET=1 ;;
    --selftest) SELFTEST=1 ;;
    --log)      LOG="${2:-}"; shift ;;
    --window)   WINDOW_D="${2:-3}"; shift ;;
    -h|--help)  sed -n '2,60p' "$0"; exit 0 ;;
    *)          echo "unknown arg: $1" >&2; exit 64 ;;
  esac
  shift
done

# ── the measurement ──────────────────────────────────────────────────────────────────────────────
# Everything below is a pure function of ($LOG, $WINDOW_D) so --selftest can drive it with a
# fixture log and get the same arithmetic the live run gets. A self-test that exercises a DIFFERENT
# code path than production proves nothing about production.
measure() {
  local log="$1" window_d="$2"

  if [ ! -r "$log" ]; then
    VERDICT="NO-DATA"; RC=3
    DETAIL="log not readable: $log"
    EVENTS=0; CLOSES=0; SINCE_LAST=""; TOP_REASONS=""
    return
  fi

  # BSD date. A cutoff we cannot compute must not silently become "all of time" — that would turn
  # a broken date into a permanently-reassuring OK, the exact polarity this file exists to avoid.
  local cutoff
  if ! cutoff=$(date -v-"${window_d}"d +%Y-%m-%d 2>/dev/null) || [ -z "$cutoff" ]; then
    VERDICT="NO-DATA"; RC=3
    DETAIL="could not compute a ${window_d}d cutoff (date -v unavailable)"
    EVENTS=0; CLOSES=0; SINCE_LAST=""; TOP_REASONS=""
    return
  fi

  # Lines are `[YYYY-MM-DD HH:MM:SS] …`, so a lexical compare on the date field IS a chronological
  # one — no parsing per line, and no locale dependence.
  local win
  win=$(awk -v cut="$cutoff" '
    match($0, /^\[[0-9]{4}-[0-9]{2}-[0-9]{2}/) {
      d = substr($0, 2, 10)
      if (d >= cut) print
    }' "$log" 2>/dev/null)

  CLOSES=$(printf '%s\n' "$win" | grep -c "✓ closed pane" 2>/dev/null || true)
  # A refusal = the hook decided NOT to close a teammate it was asked about. The two exclusions are
  # not refusals at all: they mean the teammate is still working, and the hook is correct to leave
  # it alone. See the header — counting them would bias a healthy fleet toward ALARM.
  REFUSALS=$(printf '%s\n' "$win" \
    | grep -E "\] defer |⚑ SURFACE " 2>/dev/null \
    | grep -vcE "\.teammate-busy marker present|tool in flight" 2>/dev/null || true)
  CLOSES=${CLOSES:-0}; REFUSALS=${REFUSALS:-0}
  EVENTS=$(( CLOSES + REFUSALS ))

  # Days since the last close ANYWHERE in the log — the number an operator actually wants, and it
  # must look past the window or a long outage would report "0 in 3 days" forever with no scale.
  local last_close_date
  last_close_date=$(grep "✓ closed pane" "$log" 2>/dev/null | tail -1 | sed -n 's/^\[\([0-9-]\{10\}\).*/\1/p')
  if [ -n "$last_close_date" ]; then
    local last_epoch now_epoch
    last_epoch=$(date -j -f %Y-%m-%d "$last_close_date" +%s 2>/dev/null || echo "")
    now_epoch=$(date +%s)
    if [ -n "$last_epoch" ]; then
      SINCE_LAST=$(( (now_epoch - last_epoch) / 86400 ))
    else
      SINCE_LAST=""
    fi
    LAST_CLOSE="$last_close_date"
  else
    SINCE_LAST=""; LAST_CLOSE="never"
  fi

  # Name the reason, so the alarm is actionable rather than merely true. Paths are collapsed —
  # otherwise every distinct worktree reads as a distinct reason and the ranking is meaningless.
  TOP_REASONS=$(printf '%s\n' "$win" \
    | grep -oE "defer [a-zA-Z0-9_-]+ \([0-9]+/[0-9]+\): .*" 2>/dev/null \
    | sed -E 's|^defer [a-zA-Z0-9_-]+ \([0-9]+/[0-9]+\): ||; s|/[^ ]*|<path>|g' \
    | sort | uniq -c | sort -rn | head -3 \
    | awk '{ n=$1; $1=""; sub(/^ /,""); printf "%s× %s\n", n, $0 }')

  if [ "$EVENTS" -lt "$MIN_EVENTS" ]; then
    VERDICT="NOT-EXERCISED"; RC=0
    DETAIL="only $EVENTS decision(s) in ${window_d}d (need >=$MIN_EVENTS to assert) — nothing claimed"
    return
  fi

  local rate=$(( CLOSES * 100 / EVENTS ))
  if [ "$CLOSES" -eq 0 ]; then
    VERDICT="ALARM"; RC=2
    DETAIL="the close path ran $EVENTS times in ${window_d}d and closed NOTHING"
  elif [ "$rate" -lt "$WARN_RATE_PCT" ]; then
    VERDICT="WARN"; RC=1
    DETAIL="$CLOSES close(s) in $EVENTS attempts (${rate}%, floor ${WARN_RATE_PCT}%)"
  else
    VERDICT="OK"; RC=0
    DETAIL="$CLOSES close(s) in $EVENTS attempts (${rate}%)"
  fi
}

# ── self-test — the positive control ─────────────────────────────────────────────────────────────
# The point is not that the healthy case passes; it is that the SAME parser produces ALARM on a
# dead path and OK on a live one. A control that can only ever emit the passing verdict is the
# defect this whole file was written about.
if [ "${SELFTEST:-0}" = 1 ]; then
  fail=0
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/reapalarm.XXXXXX") || exit 70
  trap 'rm -rf "$tmp"' EXIT
  today=$(date +%Y-%m-%d)

  # Cut to the REAL log's shape, not an assumed one. A refusal is a bare `defer` line with NO
  # header above it — that asymmetry is exactly what the first version of this instrument got
  # wrong, so the fixture has to carry it or the control cannot fail the way production did.
  emit() { # emit <file> <n_refusals> <n_closes>
    local f="$1" ref="$2" cl="$3" i
    : > "$f"
    for ((i=0; i<ref; i++)); do
      echo "[$today 12:00:00]   ↳ m$i: worktree /w is SHARED by 5 members — gating on it, removal refused" >> "$f"
      echo "[$today 12:00:00] defer m$i (1/3): dirty tree" >> "$f"
    done
    for ((i=0; i<cl; i++)); do
      echo "[$today 12:00:01] Auto-shutdown idle teammate: c$i (team: t)" >> "$f"
      echo "[$today 12:00:01]   ✓ closed pane U$i (c$i)" >> "$f"
    done
  }
  check() { # check <label> <file> <want_verdict> <want_rc>
    measure "$2" "$WINDOW_D"
    if [ "$VERDICT" = "$3" ] && [ "$RC" = "$4" ]; then
      echo "ok   $1 → $VERDICT ($RC)"
    else
      echo "FAIL $1 → got $VERDICT ($RC), want $3 ($4)"; fail=1
    fi
  }

  emit "$tmp/dead.log"    20 0   ; check "dead path, exercised"      "$tmp/dead.log"    ALARM         2
  emit "$tmp/healthy.log" 20 18  ; check "healthy path"              "$tmp/healthy.log" OK            0
  emit "$tmp/thin.log"    20 1   ; check "closing almost nothing"    "$tmp/thin.log"    WARN          1
  emit "$tmp/quiet.log"    2 0   ; check "quiet fleet, not asserted" "$tmp/quiet.log"   NOT-EXERCISED 0
  check "unreadable log" "$tmp/does-not-exist.log" NO-DATA 3

  # The window must actually bound: events older than it cannot rescue a dead window, and must not
  # be counted as if they were recent.
  : > "$tmp/old.log"
  old=$(date -v-30d +%Y-%m-%d)
  for i in $(seq 1 20); do echo "[$old 12:00:00] defer m$i (1/3): dirty tree" >> "$tmp/old.log"; done
  for i in $(seq 1 20); do echo "[$old 12:00:01]   ✓ closed pane U$i (m$i)" >> "$tmp/old.log"; done
  check "old closes do not count as recent" "$tmp/old.log" NOT-EXERCISED 0

  # REGRESSION CONTROL for this file's own first defect. The live log's refusals carry NO
  # `Auto-shutdown idle teammate` header — that line is only written on the success path — so an
  # instrument keyed on it counts ~0 attempts during a total outage and reports NOT-EXERCISED.
  # This fixture is a nine-day outage with zero header lines, and it MUST read ALARM.
  : > "$tmp/headerless.log"
  for i in $(seq 1 30); do
    echo "[$today 09:0$((i%10)):00] defer m$i (2/3): reap-guard DEFER on a SHARED cwd (/w) — gates evaluated the wrong tree" >> "$tmp/headerless.log"
  done
  check "outage with no header lines still ALARMs" "$tmp/headerless.log" ALARM 2

  # The busy/in-flight exclusions must NOT be counted as refusals — a fleet whose teammates are
  # simply still working must never drift toward ALARM.
  : > "$tmp/busy.log"
  for i in $(seq 1 30); do
    echo "[$today 09:00:00] defer m$i (team=t): .teammate-busy marker present" >> "$tmp/busy.log"
    echo "[$today 09:00:01] defer m$i (team=t): tool in flight — teammate is live, not idle" >> "$tmp/busy.log"
  done
  check "busy teammates are not refusals" "$tmp/busy.log" NOT-EXERCISED 0

  [ "$fail" = 0 ] && echo "selftest: all pass" || echo "selftest: FAILURES"
  exit "$fail"
fi

# ── live run ─────────────────────────────────────────────────────────────────────────────────────
measure "$LOG" "$WINDOW_D"
TS=$(date +%Y-%m-%dT%H:%M:%S)

if [ "$WANT_JSON" = 1 ]; then
  printf '{"ts":"%s","verdict":"%s","window_d":%s,"idle_events":%s,"closes":%s,"last_close":"%s","days_since_last_close":%s,"detail":"%s"}\n' \
    "$TS" "$VERDICT" "$WINDOW_D" "${EVENTS:-0}" "${CLOSES:-0}" "${LAST_CLOSE:-never}" "${SINCE_LAST:-null}" "$DETAIL"
elif [ "$QUIET" != 1 ]; then
  echo "teammate-reap-alarm — $TS"
  echo "  window:              last ${WINDOW_D}d   (assert only at >=${MIN_EVENTS} decisions)"
  echo "  close path ran:      ${EVENTS:-0} time(s)"
  echo "  panes closed:        ${CLOSES:-0}"
  echo "  last close:          ${LAST_CLOSE:-never}${SINCE_LAST:+   (${SINCE_LAST}d ago)}"
  if [ -n "${TOP_REASONS:-}" ]; then
    echo "  it refused because:"
    printf '%s\n' "$TOP_REASONS" | sed 's/^/      /'
  fi
  echo "  VERDICT:             $VERDICT — $DETAIL"
  if [ "$VERDICT" = "ALARM" ] || [ "$VERDICT" = "WARN" ]; then
    echo
    echo "  This is an ALARM, not a gate — it never refuses a spawn and never closes a pane."
    echo "  The reasons above are downstream of ONE question the member usually cannot answer:"
    echo "  'is my tree clean?'. Clearing the top reason hands the refusal to the next one, which"
    echo "  is how nine days of zero closes survived four correct-looking fixes. See"
    echo "  docs/plans/TEAMMATE_SELFCLOSE_INVESTIGATION.md § REOPENED 2026-08-03."
  fi
fi

exit "${RC:-0}"
