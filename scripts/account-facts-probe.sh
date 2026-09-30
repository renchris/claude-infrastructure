#!/bin/bash
# account-facts-probe.sh — falsifiers that let the RECORDERS settle master-account-facts rows
# (BACKLOG_MASTER W0 ledger-retraction.9).
#
# Rows about accounts carry PROJECTED numbers ("a losing racer logs out ~37 sessions at once") that
# nothing re-measured, while two recorders have run for weeks: cc-relogin-poll (RESULT … PROVEN
# lines) and com.claude.auth-timeseries (one JSON line per account per tick since 2026-08-24). Each
# mode below is a cc-premise falsifier: exit 0 means the condition the row was filed for is GONE.
#
#   relogin-proven <acct> [--since <ISO-8601>]
#       exit 0 iff cc-relogin logged `RESULT <acct> … PROVEN` at or after --since.
#   herd --min-live <N> [--days <D>]
#       exit 0 iff the auth recorder covers at least D days (default 14) and, in that window, NO
#       account went from state OK to a non-OK state while it had N or more live sessions — i.e. the
#       projected herd never happened. Exit 1 when one did; exit 2 when the recorder cannot answer
#       (missing, or shorter than the window) — never a verdict made out of an absent store.
#
# Seams: CC_AUTH_TIMESERIES (default ~/.claude/logs/auth-timeseries.jsonl),
#        CC_RELOGIN_LOG     (default ~/.claude/logs/cc-relogin-poll.log), CC_PROBE_NOW (epoch).
set -uo pipefail
TS="${CC_AUTH_TIMESERIES:-$HOME/.claude/logs/auth-timeseries.jsonl}"
RL="${CC_RELOGIN_LOG:-$HOME/.claude/logs/cc-relogin-poll.log}"
usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

mode="${1:-}"; [ $# -gt 0 ] && shift
case "$mode" in
  relogin-proven)
    acct="${1:-}"; [ -n "$acct" ] || usage; shift
    since=""
    while [ $# -gt 0 ]; do
      case "$1" in --since) since="${2:-}"; shift 2 ;; *) usage ;; esac
    done
    [ -r "$RL" ] || exit 2
    # lines look like: 2026-07-30T20:36:27Z RESULT next attempt=1 exit=0 PROVEN — …
    awk -v a="$acct" -v s="$since" '
      $2 == "RESULT" && $3 == a && / PROVEN/ && (s == "" || $1 >= s) { found = 1 }
      END { exit(found ? 0 : 1) }' "$RL"
    ;;
  herd)
    minlive=""; days=14
    while [ $# -gt 0 ]; do
      case "$1" in
        --min-live) minlive="${2:-}"; shift 2 ;;
        --days)     days="${2:-}"; shift 2 ;;
        *) usage ;;
      esac
    done
    case "$minlive$days" in ''|*[!0-9]*) usage ;; esac
    [ -r "$TS" ] || exit 2
    python3 - "$TS" "$minlive" "$days" "${CC_PROBE_NOW:-}" <<'PY'
import datetime, json, sys
path, minlive, days, now = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
def ep(s):
    return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()
now = float(now) if now else datetime.datetime.now(datetime.timezone.utc).timestamp()
cut = now - days * 86400
first, prev, herd = None, {}, []
with open(path, encoding="utf-8") as fh:
    for line in fh:
        try:
            r = json.loads(line)
            t = ep(r["ts"])
        except (ValueError, KeyError, TypeError):
            continue
        first = t if first is None else min(first, t)
        a, st, nl = r.get("acct"), r.get("state"), r.get("n_live") or 0
        p = prev.get(a)
        if t >= cut and p and p[0] == "OK" and st != "OK" and max(p[1], nl) >= minlive:
            herd.append((r["ts"], a, max(p[1], nl)))
        prev[a] = (st, nl)
if first is None or first > cut:
    sys.exit(2)                       # the recorder does not cover the window: no verdict
if herd:
    print("herd: %d OK->non-OK transition(s) with >= %d live, e.g. %s" % (len(herd), minlive, herd[0]))
    sys.exit(1)
print("no herd: 0 OK->non-OK transitions with >= %d live sessions in %d days" % (minlive, days))
sys.exit(0)
PY
    ;;
  *) usage ;;
esac
