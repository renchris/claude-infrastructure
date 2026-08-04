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
# ── AND ALL OF THAT IS STILL A LOG GREP, WHICH IS WHY THE COUNTS MOVED (2026-08-04) ──────────────
# Everything above counts OUR OWN CLAIMS. `✓ closed pane`, `defer` and `⚑ SURFACE` are lines this
# subsystem writes about itself, so the metric is satisfiable without a single pane going away — a
# gate change, a terminal-backend swap, or a close rerouted through another path all move it while
# the world stands still. Two blind spots, both measured on this box, not hypothesised:
#
#   1. Team session-57342265 had SIX members closed and de-registered from config.json with ZERO
#      `✓ closed pane` lines anywhere. Six real closes this instrument could not see.
#   2. The log's own last two lines assert `Pane NOT closed` for panes that were ALREADY GONE. The
#      denominator was counting refusals against members that had already left.
#
# So EVENTS and CLOSES now come from scripts/assignee-pane-residency.sh — a three-source join over
# the terminal's live window ids, every team config's integer (kitty) panes, and the process table.
# EVENTS = members resident past the staleness threshold + departures since the last sample.
# CLOSES = only those departures ATTRIBUTED to us by a `✓ closed pane <pane> (<name>)` line naming
# both the pane and the member. A departure nobody can attribute is a vendor close and never
# satisfies the OK arm — otherwise the first departure this alarm ever saw would read as proof the
# fix worked, which is the original error wearing a new coat.
#
# The log-grep pair is still computed and still PRINTED, one line under the world figures. It is no
# longer the verdict; it is the second opinion, and the GAP between the two is itself the finding.
# Where the join can see no world at all (no team ever recorded an integer pane, or every source is
# blind) the verdict falls back to the log arithmetic and SAYS so — a degraded reading, labelled,
# beats an instrument that goes quiet.
#
# FOUR VERDICTS, NEVER A BOOLEAN — "could not measure" must not render as "fine":
#   OK             the path ran and closed things.                        exit 0
#   NOT-EXERCISED  too few idle events in the window to assert anything.  exit 0
#   WARN           the path ran and closed almost nothing.                exit 1
#   ALARM          the path ran >=MIN_EVENTS times and closed NOTHING.    exit 2
#   NO-DATA        the log is absent or unreadable — nothing is asserted. exit 3
#
# This file itself uses only /usr/bin + /bin tools (date, grep, awk, sed) — no jq, no Homebrew — so
# a launchd PATH of /usr/bin:/bin:/usr/sbin:/sbin cannot break it (memory:
# path-resolved-dependency-in-daemon-code). The residency join it calls DOES need jq and it2; each
# of those is a NAMED degraded source in the token it returns, never a silent zero, and the plist
# that fires this job exports a PATH that carries both.
#
# Self-test: `teammate-reap-alarm.sh --selftest` drives synthetic logs through every verdict,
# including the two that matter most — a healthy fleet must read OK and a dead path must read
# ALARM on the SAME parser. A checker that cannot produce its own failing case is not evidence.

set -uo pipefail

LOG="${TEAMMATE_LIFECYCLE_LOG:-$HOME/.claude/logs/teammate-lifecycle.log}"
# The world-facing numerator. Defaults to the sibling beside this file so a deployed copy and a
# repo copy each find their own; CC_RESIDENCY_SH points it elsewhere (or at nothing, which forces
# the labelled log-grep fallback — that is how the self-test drives both sources).
RESIDENCY_SH="${CC_RESIDENCY_SH:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)/assignee-pane-residency.sh}"
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

  SOURCE="log"; RESIDENT_N=0; STALE_N=0; DEPARTED_N=0; OURS_N=0; VENDOR_N=0; RES_VERDICT="absent"

  if [ ! -r "$log" ]; then
    VERDICT="NO-DATA"; RC=3
    DETAIL="log not readable: $log"
    EVENTS=0; CLOSES=0; LOG_EVENTS=0; LOG_CLOSES=0; SINCE_LAST=""; TOP_REASONS=""
    return
  fi

  # BSD date. A cutoff we cannot compute must not silently become "all of time" — that would turn
  # a broken date into a permanently-reassuring OK, the exact polarity this file exists to avoid.
  local cutoff
  if ! cutoff=$(date -v-"${window_d}"d +%Y-%m-%d 2>/dev/null) || [ -z "$cutoff" ]; then
    VERDICT="NO-DATA"; RC=3
    DETAIL="could not compute a ${window_d}d cutoff (date -v unavailable)"
    EVENTS=0; CLOSES=0; LOG_EVENTS=0; LOG_CLOSES=0; SINCE_LAST=""; TOP_REASONS=""
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

  # ── the SECOND OPINION: the old log-grep pair, kept and printed, no longer the verdict ──────────
  LOG_CLOSES=$(printf '%s\n' "$win" | grep -c "✓ closed pane" 2>/dev/null || true)
  # A refusal = the hook decided NOT to close a teammate it was asked about. The two exclusions are
  # not refusals at all: they mean the teammate is still working, and the hook is correct to leave
  # it alone. See the header — counting them would bias a healthy fleet toward ALARM.
  REFUSALS=$(printf '%s\n' "$win" \
    | grep -E "\] defer |⚑ SURFACE " 2>/dev/null \
    | grep -vcE "\.teammate-busy marker present|tool in flight" 2>/dev/null || true)
  LOG_CLOSES=${LOG_CLOSES:-0}; REFUSALS=${REFUSALS:-0}
  LOG_EVENTS=$(( LOG_CLOSES + REFUSALS ))

  # ── the NUMERATOR: the world, via the residency join ────────────────────────────────────────────
  # `--no-state` is load-bearing. The periodic sampler owns the departure cursor; if this call
  # advanced it too, each of the two would only ever see the departures the other left behind, and
  # the alarm would consume the very evidence it exists to report.
  #
  # The `|| true` below cannot launder anything, and that is by construction on the OTHER side: the
  # residency script prints its verdict as a TOKEN on stdout, so the verdict survives an exit status
  # this call throws away (memory: claimed-outcome-vs-checked-outcome). Suppressing the rc here is
  # deliberate — ALARM exits 2, and a bare call would abort the read of its own finding.
  local rtok=""
  if [ -x "$RESIDENCY_SH" ]; then
    rtok="$("$RESIDENCY_SH" --quiet --no-state --log "$log" 2>/dev/null || true)"
  fi
  RES_VERDICT="$(printf '%s\n' "$rtok" | sed -n 's/.*verdict=\([A-Z-][A-Z-]*\).*/\1/p' | tail -1)"
  RES_VERDICT="${RES_VERDICT:-absent}"
  rfield() { printf '%s\n' "$rtok" | sed -n "s/.*[ ]$1=\([0-9][0-9]*\).*/\1/p" | tail -1; }
  RESIDENT_N="$(rfield resident)"; RESIDENT_N="${RESIDENT_N:-0}"
  STALE_N="$(rfield stale)";       STALE_N="${STALE_N:-0}"
  DEPARTED_N="$(rfield departed)"; DEPARTED_N="${DEPARTED_N:-0}"
  OURS_N="$(rfield ours)";         OURS_N="${OURS_N:-0}"
  VENDOR_N="$(rfield vendor)";     VENDOR_N="${VENDOR_N:-0}"

  case "$RES_VERDICT" in
    OK|WARN|ALARM)
      # The join saw a world AND had a previous sample to difference against. World figures rule.
      SOURCE="world"
      EVENTS=$(( STALE_N + DEPARTED_N ))
      CLOSES="$OURS_N"
      ;;
    *)
      # NOT-EXERCISED (no integer panes declared, or a first sample), NO-DATA (every source blind),
      # or the join is not deployed. There is no world reading to have — fall back to the log
      # arithmetic and LABEL it, because a degraded reading that says so is worth more than an
      # instrument that goes quiet. The label is what stops a reader trusting these two numbers as
      # if they were outcomes.
      SOURCE="log(no-world:$RES_VERDICT)"
      EVENTS="$LOG_EVENTS"
      CLOSES="$LOG_CLOSES"
      ;;
  esac

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

  # ── the verdict. ONE predicate over (EVENTS, CLOSES), whichever source supplied them, so the two
  # sources can never drift into two different definitions of "the close path is working".
  # The decision-line literals below are UNCHANGED — cc-blockers and tests/cc-blockers-teammate-
  # reap.bats read these verdict words, and a rewrite here would be a silent consumer break.
  if [ "$EVENTS" -lt "$MIN_EVENTS" ]; then
    VERDICT="NOT-EXERCISED"; RC=0
    DETAIL="only $EVENTS decision(s) in ${window_d}d (need >=$MIN_EVENTS to assert) — nothing claimed"
    qualify_detail
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
  qualify_detail
}

# The source is APPENDED, never substituted into the literals above. A reader must be able to tell a
# world-measured verdict from a log-measured one at a glance — a number whose provenance is implicit
# is how "the fix worked" and "our log stopped being written" came to look identical.
qualify_detail() {
  if [ "$SOURCE" = "world" ]; then
    DETAIL="$DETAIL — measured against the WORLD ($STALE_N stale resident + $DEPARTED_N departed; $OURS_N ours, $VENDOR_N unattributed)"
  else
    DETAIL="$DETAIL — log-grep only, no world reading ($RES_VERDICT)"
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
  check() { # check <label> <file> <want_verdict> <want_rc> [want_source]
    measure "$2" "$WINDOW_D"
    local ok=1
    [ "$VERDICT" = "$3" ] && [ "$RC" = "$4" ] || ok=0
    [ -n "${5:-}" ] && { case "$SOURCE" in ("$5"*) ;; (*) ok=0 ;; esac; }
    if [ "$ok" = 1 ]; then echo "ok   $1 → $VERDICT ($RC) via $SOURCE"
    else echo "FAIL $1 → got $VERDICT ($RC) via $SOURCE, want $3 ($4) via ${5:-*}"; fail=1; fi
  }

  # The residency join is STUBBED for the log-source arms below, and pointed at nothing at all for
  # most of them. Two reasons, and the second is the important one: (a) the embedded self-test runs
  # under the operator's REAL $HOME, so an unstubbed join would read the live fleet and this control
  # would report a different verdict on a Tuesday than on a Friday; (b) these arms exist to pin the
  # LOG arithmetic, and an arm whose input is the live world is not pinning anything.
  stub_res() { # stub_res <token-tail…>  → a residency script emitting exactly that token
    printf '#!/bin/bash\necho "verdict=%s"\nexit 0\n' "$*" > "$tmp/res.sh"
    chmod +x "$tmp/res.sh"; RESIDENCY_SH="$tmp/res.sh"
  }
  RESIDENCY_SH="$tmp/definitely-not-deployed"

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

  # ══ THE NUMERATOR SWAP — the arms that make this file worth re-landing ═══════════════════════════
  # A log stuffed with 18 `✓ closed pane` lines out of 20 attempts is the healthiest log this
  # instrument can be handed; on the old arithmetic it read OK, full stop. If the WORLD says twelve
  # members are sitting resident past the threshold and nothing has departed, the log is wrong and
  # the verdict must be ALARM. This is the exact shape the two proven blind spots produce — a close
  # rerouted so it stops writing our line, or a refusal logged against a pane that already left.
  stub_res "ALARM members=15 resident=12 stale=12 departed=0 ours=0 vendor=0"
  check "a healthy-looking LOG cannot launder a dead WORLD" "$tmp/healthy.log" ALARM 2 world

  # POSITIVE CONTROL, and the twin that makes the arm above mean something: the SAME healthy log,
  # the SAME stale pile — but now the world shows departures we can attribute. It must read OK off
  # the same parser. If these two ever agree, the world source is not being read at all.
  stub_res "OK members=15 resident=3 stale=3 departed=12 ours=12 vendor=0"
  check "the same log with a LIVE world reads OK"           "$tmp/healthy.log" OK    0 world

  # The mirror of the first arm: a log full of refusals and zero closes, where the world says the
  # panes actually left. A log-grep alarm would fire; the world says the close path is working, and
  # the world wins. (This is blind spot #1 — six real closes with zero `✓ closed pane` lines.)
  stub_res "OK members=8 resident=1 stale=1 departed=6 ours=6 vendor=0"
  check "a dead-looking LOG does not fire against a live WORLD" "$tmp/dead.log" NOT-EXERCISED 0 world

  # ATTRIBUTION carries all the way up. Six departures, none of them ours — that is the vendor
  # closing panes, not our chain working, so it must NOT reach OK. `ours` is the numerator, not
  # `departed`; if the wrong field were read this arm would go green.
  stub_res "WARN members=20 resident=14 stale=14 departed=6 ours=0 vendor=6"
  check "unattributed departures never satisfy OK"          "$tmp/dead.log"    ALARM 2 world

  # And a join that cannot see a world must fall back to the log arithmetic — LABELLED, never
  # silently. NOT-EXERCISED from the join is "no assignee panes exist", which is not evidence about
  # the close path at all.
  stub_res "NOT-EXERCISED members=0 resident=0 stale=0 departed=0 ours=0 vendor=0"
  check "no world ⇒ labelled log fallback"                  "$tmp/dead.log"    ALARM 2 "log(no-world"
  case "$DETAIL" in
    (*"log-grep only, no world reading"*) echo "ok   the fallback SAYS it is degraded" ;;
    (*) echo "FAIL the fallback did not label itself: $DETAIL"; fail=1 ;;
  esac

  [ "$fail" = 0 ] && echo "selftest: all pass" || echo "selftest: FAILURES"
  exit "$fail"
fi

# ── live run ─────────────────────────────────────────────────────────────────────────────────────
measure "$LOG" "$WINDOW_D"
TS=$(date +%Y-%m-%dT%H:%M:%S)

if [ "$WANT_JSON" = 1 ]; then
  # The original eight keys are unchanged and keep their meaning — cc-blockers:734 and
  # tests/cc-blockers-teammate-reap.bats read them. The world figures are ADDED, never substituted.
  printf '{"ts":"%s","verdict":"%s","window_d":%s,"idle_events":%s,"closes":%s,"last_close":"%s","days_since_last_close":%s,"detail":"%s","source":"%s","residency":"%s","resident":%s,"stale":%s,"departed":%s,"ours":%s,"vendor":%s,"log_events":%s,"log_closes":%s}\n' \
    "$TS" "$VERDICT" "$WINDOW_D" "${EVENTS:-0}" "${CLOSES:-0}" "${LAST_CLOSE:-never}" "${SINCE_LAST:-null}" "$DETAIL" \
    "${SOURCE:-log}" "${RES_VERDICT:-absent}" "${RESIDENT_N:-0}" "${STALE_N:-0}" "${DEPARTED_N:-0}" \
    "${OURS_N:-0}" "${VENDOR_N:-0}" "${LOG_EVENTS:-0}" "${LOG_CLOSES:-0}"
elif [ "$QUIET" != 1 ]; then
  echo "teammate-reap-alarm — $TS"
  echo "  window:              last ${WINDOW_D}d   (assert only at >=${MIN_EVENTS} decisions)"
  echo "  measured from:       ${SOURCE:-log}   (residency join: ${RES_VERDICT:-absent})"
  echo "  close path ran:      ${EVENTS:-0} time(s)"
  echo "  panes closed:        ${CLOSES:-0}"
  if [ "${SOURCE:-log}" = "world" ]; then
    echo "    · world:           ${RESIDENT_N:-0} resident (${STALE_N:-0} stale) · ${DEPARTED_N:-0} departed = ${OURS_N:-0} ours + ${VENDOR_N:-0} unattributed"
    # The second opinion, printed BESIDE the verdict rather than under it. Where these two disagree,
    # the gap IS the finding — that is what six closes with zero log lines looks like from here.
    echo "    · log-grep says:   ${LOG_CLOSES:-0} close(s) in ${LOG_EVENTS:-0} attempt(s)   ← claims, not outcomes"
  fi
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
