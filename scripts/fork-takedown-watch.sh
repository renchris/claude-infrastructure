#!/bin/bash
# fork-takedown-watch.sh — the weekly check that a takedown ask about a pre-cutover copy of this repo
# actually worked (backlog a11a0b08ef8a; plan docs/plans/PUBLIC_REPO_HYGIENE.md, last section).
#
# ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────────────
# A public copy pushed before the 2026-09-27 cutover still serves the old, unredacted history. The
# fix is a request to a third party (the copy's owner, GitHub), and a request can be ignored. The
# proof of the operator's part is the SUBMISSION, not the third party's action, so without a watch
# nothing ever learns that the ask went nowhere. autonomy-sweep §2b-iii-f runs `--arm` at most once
# a week and pages the desk when it exits 0.
#
# The target (repo + probe SHAs) and the submission date live in the PRIVATE store, never in this
# public file: $CC_PRIVATE_DIR/docs/plans/public-presence/fork-watch.json. `submitted` stays null
# until the operator records the send; until then the arm abstains without touching the network.
#
# ── EXIT CODES (0 = SIGNAL · 1 = no signal · 2 = NON-VERDICT) ─────────────────────────────────────
#   --arm     0 = submitted >= CC_FORK_WATCH_DAYS (30) days ago AND at least one probe SHA still
#                 answers HTTP 200 — the ask was ignored; escalate.
#             1 = no signal: not yet submitted, still inside the window (no fetch made), or every
#                 probe answers gone (404/410/422/451).
#             2 = NON-VERDICT: the state file is unreadable, or no probe gave a 200 or a gone code
#                 (network down, rate limit, 5xx). Means "could not ask", never "gone".
#   --report  prints the verdict and the next step; exits like --arm.
#
# 🚨 NEVER store `--arm` as a backlog row's --falsifier: exit 0 means "the work is due", which
# cc-premise would read as "close it" (docs/lessons/arming-and-mootness-cannot-share-one-falsifier.md).
# It pages; it writes no store.
#
# Env (test seams): CC_FORK_WATCH_STATE=<file> overrides the state path; CC_FORK_WATCH_TODAY=YYYY-MM-DD
# pins today; CC_FORK_WATCH_CODE=<http code> replaces every fetch; CC_FORK_WATCH_API overrides the
# API base; CC_FORK_WATCH_FETCH_TIMEOUT_S bounds each fetch (10); CC_FORK_WATCH_DAYS the window (30).
set -uo pipefail

MODE="${1:---arm}"
case "$MODE" in --arm|--report) ;; *) echo "usage: fork-takedown-watch.sh --arm|--report" >&2; exit 2 ;; esac

PRIV="${CC_PRIVATE_DIR:-$HOME/Development/claude-private}"
STATE="${CC_FORK_WATCH_STATE:-$PRIV/docs/plans/public-presence/fork-watch.json}"
DAYS="${CC_FORK_WATCH_DAYS:-30}"
API="${CC_FORK_WATCH_API:-https://api.github.com}"
TODAY="${CC_FORK_WATCH_TODAY:-$(date -u +%Y-%m-%d)}"

# One python process computes the window: "<repo>\t<submitted>\t<elapsed days|->\t<sha> <sha>…".
# A parse failure prints nothing, which the caller reads as a non-verdict.
plan="$(python3 -c '
import json, sys, datetime
try:
    d = json.load(open(sys.argv[1]))
    repo = d["repo"]; shas = [s for s in d["probe_shas"] if s]
    if not repo or not shas:
        raise ValueError
    sub = d.get("submitted")
    today = datetime.date.fromisoformat(sys.argv[2])
    age = "-" if not sub else str((today - datetime.date.fromisoformat(sub)).days)
    print("%s\t%s\t%s\t%s" % (repo, sub or "-", age, " ".join(shas)))
except Exception:
    pass
' "$STATE" "$TODAY" 2>/dev/null)"

rc=2; word=""; repo="?"; served=""
if [ -z "$plan" ]; then
  word="NO VERDICT — state file unreadable or malformed: $STATE (this is not 'gone')"
else
  repo="$(printf '%s' "$plan" | cut -f1)"
  sub="$(printf '%s' "$plan" | cut -f2)"
  age="$(printf '%s' "$plan" | cut -f3)"
  shas="$(printf '%s' "$plan" | cut -f4)"
  case "$age" in -|*[!0-9-]*) age_n=-1 ;; *) age_n="$age" ;; esac
  if [ "$sub" = "-" ]; then
    rc=1; word="not yet submitted — the takedown ask has not been recorded, so no clock is running"
  elif [ "$age_n" -lt "$DAYS" ]; then
    rc=1; word="inside the window — submitted $sub, day $age of $DAYS; not probed"
  else
    gone=0; unknown=0
    for sha in $shas; do
      if [ -n "${CC_FORK_WATCH_CODE:-}" ]; then
        code="$CC_FORK_WATCH_CODE"
      else
        code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time "${CC_FORK_WATCH_FETCH_TIMEOUT_S:-10}" \
          -H 'Accept: application/vnd.github+json' "$API/repos/$repo/commits/$sha" 2>/dev/null)" || true
      fi
      case "$code" in
        200) served="$served ${sha:0:12}" ;;
        404|410|422|451) gone=$((gone + 1)) ;;
        *) unknown=$((unknown + 1)) ;;
      esac
    done
    if [ -n "$served" ]; then
      rc=0; word="STILL SERVED — $repo answers 200 for${served}, $age days after the ask of $sub"
    elif [ "$unknown" -eq 0 ]; then
      rc=1; word="GONE — $repo no longer serves any probe SHA ($gone of $gone gone)"
    else
      word="NO VERDICT — $unknown probe(s) gave neither 200 nor a gone code (network, rate limit or 5xx)"
    fi
  fi
fi

if [ "$MODE" = "--report" ]; then
  echo "fork-takedown-watch: $word"
  case "$rc" in
    0) echo "next: file the DMCA draft (Draft 2) in $PRIV/docs/plans/public-presence/README.md, then record it:"
       echo "      bash $PRIV/docs/plans/public-presence/record-submission.sh --dmca \$(date +%Y-%m-%d)" ;;
    1) case "$word" in GONE*) echo "next: the copy is down — fill the Record section of the private README and close the plan's last item." ;; esac ;;
  esac
fi
exit "$rc"
