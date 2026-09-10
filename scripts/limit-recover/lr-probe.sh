#!/usr/bin/env bash
# lr-probe.sh — the CONNECTIVITY CONTROL that gates every re-fire. D5 of
# docs/plans/NONLIMIT_RESUME_LADDER.md (T6/W2-C, the probe half).
#
# WHY IT EXISTS, in one measurement. On 2026-09-09 the harness re-issued ONE workflow journal key
# five times into a live outage: six attempts, ~17 minutes apart, 85 minutes, and nothing produced.
# A re-fire is not free and it is not evidence — and the stall's own TEXT can never say whether it
# will clear, because the watchdog writes the same words either way. Only a control can:
#
#   1. the FLEET arm    — any real-model assistant record from ANY session in the stall window proves
#                         the API path was live, which convicts the REQUEST rather than the network
#   2. THIS PROBE       — a request-independent reachability check: DNS + TCP + TLS + HTTP, no auth,
#                         no quota, two greens spaced apart
#   3. the re-fire itself — at most ONE under a green control; a second stall under a green control
#                         convicts the request (size, a blocking tool, a headless permission prompt)
#                         and the remedy is to change the request, never a third fire
#
# This file is arm 2. It is a NECESSARY and NOT a sufficient condition for a re-fire: it says the
# path is reachable, never that re-firing is correct. The verdict table's PENDING /
# UNSETTLED-INFLIGHT / RUNNING rows still forbid touching a unit a live process holds, and a green
# probe does not soften any of them.
#
# ── WHY *ANY* HTTP STATUS IS GREEN, AND 200 WOULD BE A BUG ──────────────────────────────────────
# The request is deliberately UNAUTHENTICATED, so the server's correct answer is 401 (or 403/404/405
# depending on route and method). A 3-digit status — any 3-digit status — means DNS resolved, TCP
# connected, TLS completed and an HTTP response came back from the real host. That is the entire
# question. Keying green on 200 would build a gate WITH NO ACCEPTING PATH: it could never pass, the
# stall policy above would be unreachable by construction, and the failure would read as "the network
# is still down" forever. curl reports `000` when no response was received at all, and that — plus a
# non-zero curl exit — is the only RED.
#
# MEASURED, not merely argued (2026-09-10): a live unauthenticated HEAD on this endpoint returns
# **405 Method Not Allowed**, `curl rc=0`. So the production answer is not 200 and not even 401 — a
# 200-keyed gate would have been red on every sample forever, and the two most obvious "surely it
# should be 2xx or 401" repairs are both wrong. The rule is: a 3-digit code at curl rc 0 is green.
# Re-measure with `lr-probe.sh --once --json` rather than trusting this number; what does not change
# is the criterion.
#
# ── IT SPENDS NOTHING ───────────────────────────────────────────────────────────────────────────
# No Authorization header, no API key, no body, HEAD by default. It cannot consume quota, cannot
# count against a 5-hour or weekly window, and cannot appear in usage. That independence from the
# account is the whole point: a quota wall and an unreachable network are different problems, and an
# instrument that needed the account could not tell them apart.
#
# ── HYSTERESIS, AND WHY IT IS ASYMMETRIC ────────────────────────────────────────────────────────
# Recovery needs two greens spaced apart: a link coming back flaps, and one green is a coin flip.
# But a RED needs no second sample — it already answers the question, so the first red returns
# immediately rather than sleeping out the gap. The asymmetry is deliberate: waiting on a known-red
# link costs the caller the gap for no information.
#
# Usage:
#   lr-probe.sh                 two greens $LR_PROBE_GAP_S apart ⇒ rc 0; anything else rc 1
#   lr-probe.sh --once          a single sample ⇒ rc 0 green / 1 red (no hysteresis)
#   lr-probe.sh --json          the same verdict as JSON on stdout
#   lr-probe.sh --samples N     N greens instead of 2 (N>=1)
#
# Exit: 0 = GREEN (the control is satisfied) · 1 = RED · 2 = usage error.
#
# Seams (VALUE seams take ${VAR+set} so a set-but-empty value is honoured verbatim; a seam that
# cannot turn a thing off is not a seam):
#   LR_PROBE_URL        the endpoint (default https://api.anthropic.com/v1/messages)
#   LR_PROBE_GAP_S      seconds between samples (default 30)
#   LR_PROBE_TIMEOUT_S  per-sample hard timeout (default 8)
#   LR_PROBE_SAMPLES    greens required (default 2)
#   LR_PROBE_CURL       the curl binary (test seam)
#   LR_PROBE_LOG        the sample log (default $CLAUDE_CONFIG_DIR/logs/lr-probe.log)
set -uo pipefail

URL="${LR_PROBE_URL-https://api.anthropic.com/v1/messages}"
GAP="${LR_PROBE_GAP_S-30}"
TMO="${LR_PROBE_TIMEOUT_S-8}"
NEED="${LR_PROBE_SAMPLES-2}"
LOG="${LR_PROBE_LOG-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/logs/lr-probe.log}"
CURL="${LR_PROBE_CURL-curl}"
JSON=0 ONCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --once) ONCE=1; shift ;;
    --json) JSON=1; shift ;;
    --samples) NEED="${2:?--samples needs a number}"; shift 2 ;;
    --gap) GAP="${2:?--gap needs seconds}"; shift 2 ;;
    --url) URL="${2:?--url needs a url}"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "lr-probe: unknown arg $1" >&2; exit 2 ;;
  esac
done
case "$NEED" in ''|*[!0-9]*) echo "lr-probe: --samples must be a number" >&2; exit 2 ;; esac
[ "$NEED" -ge 1 ] || { echo "lr-probe: --samples must be >= 1" >&2; exit 2; }
[ "$ONCE" -eq 1 ] && NEED=1
case "$GAP" in ''|*[!0-9]*) echo "lr-probe: --gap must be a number" >&2; exit 2 ;; esac

_log() { # $1=line — EVERY SAMPLE IS RECORDED, green and red alike.
  # A control whose firings are invisible cannot have its precision computed later: a ledger that
  # holds only the passes can never answer "how often did this gate refuse, and was it right?"
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || return 0
  printf '%s\t%s\n' "$(date -u +%FT%TZ 2>/dev/null || echo '-')" "$1" >> "$LOG" 2>/dev/null || true
}

# One sample. Prints "<http_code> <curl_rc> <seconds>"; rc 0 green / 1 red.
probe_once() {
  local out code crc t0 t1 dur
  command -v "$CURL" >/dev/null 2>&1 || {
    # THE INSTRUMENT IS MISSING, WHICH IS NOT A RED LINK. Reporting "red" here would tell the caller
    # the network is down when what is actually true is that we cannot look — and red is the SAFE
    # direction for this gate (it withholds a re-fire), so the verdict stands, but it must not be
    # reported as a fact about the network.
    printf '000 127 0\n'; return 1
  }
  t0="$(date +%s 2>/dev/null || echo 0)"
  # -I HEAD: no body either way. --max-time bounds a hung TLS handshake, which is exactly what an
  # outage looks like from inside one. No -H, no --user, no netrc: nothing authenticating.
  out="$("$CURL" -sS -I --max-time "$TMO" -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null)"; crc=$?
  t1="$(date +%s 2>/dev/null || echo 0)"
  dur=$(( t1 - t0 )); [ "$dur" -ge 0 ] || dur=0
  code="$(printf '%s' "$out" | tr -dc '0-9' | tail -c 3)"; [ -n "$code" ] || code=000
  printf '%s %s %s\n' "$code" "$crc" "$dur"
  # GREEN = a real HTTP response arrived. Its STATUS is irrelevant (see the header): an
  # unauthenticated request is supposed to be refused, and a refusal that travelled the whole path
  # is proof the path works.
  [ "$crc" -eq 0 ] && [ "$code" != "000" ] && [ "$code" -gt 0 ] 2>/dev/null
}

greens=0 n=0 last_code=000 last_crc=0 detail=""
while [ "$greens" -lt "$NEED" ]; do
  n=$(( n + 1 ))
  # ONE GREEN PREDICATE, AND IT LIVES IN probe_once. This loop used to re-derive
  # green from the printed fields (`crc == 0 && code != 000`), which made
  # probe_once's return code DEAD CODE for the verdict — two spellings of one
  # predicate inside a single file, with only one of them live. Caught by a
  # mutant: tightening probe_once's test to `code == 200` (the
  # gate-with-no-accepting-path bug this file's header warns about) changed no
  # behaviour and no test went red, because nothing read that rc. So the rc IS
  # the branch now, and the fields are only for reporting.
  _sample=""
  if _sample="$(probe_once)"; then _green=1; else _green=0; fi
  read -r last_code last_crc _dur <<<"$_sample" || true
  : "${_dur:=0}"
  if [ "$_green" -eq 1 ]; then
    greens=$(( greens + 1 ))
    detail="${detail}${detail:+,}green:$last_code"
    _log "sample=$n verdict=green http=$last_code url=$URL"
  else
    detail="${detail}${detail:+,}red:$last_code/curl$last_crc"
    _log "sample=$n verdict=RED http=$last_code curl_rc=$last_crc url=$URL"
    # A RED ANSWERS THE QUESTION — do not sleep out the gap for a link already known to be down.
    if [ "$JSON" -eq 1 ]; then
      printf '{"verdict":"red","greens":%s,"needed":%s,"samples":%s,"http_code":"%s","curl_rc":%s,"url":"%s","detail":"%s"}\n' \
        "$greens" "$NEED" "$n" "$last_code" "$last_crc" "$URL" "$detail"
    else
      if [ "$last_crc" -eq 127 ]; then
        echo "lr-probe: RED — the probe binary ($CURL) is unavailable, so reachability is UNMEASURED." >&2
        echo "          Withholding the green is the safe direction, but do not read this as 'the network is down'." >&2
      else
        echo "lr-probe: RED after $n sample(s) — no HTTP response from $URL (http=$last_code curl_rc=$last_crc)." >&2
      fi
    fi
    _log "verdict=RED greens=$greens/$NEED samples=$n"
    exit 1
  fi
  # Sleep only BETWEEN greens, never after the last one: the gap buys hysteresis, and a trailing
  # sleep would just delay the caller by $GAP for nothing.
  if [ "$greens" -lt "$NEED" ]; then
    sleep "$GAP" 2>/dev/null || true
  fi
done

_log "verdict=green greens=$greens/$NEED samples=$n gap=${GAP}s"
if [ "$JSON" -eq 1 ]; then
  printf '{"verdict":"green","greens":%s,"needed":%s,"samples":%s,"http_code":"%s","gap_s":%s,"url":"%s","detail":"%s"}\n' \
    "$greens" "$NEED" "$n" "$last_code" "$GAP" "$URL" "$detail"
else
  echo "lr-probe: GREEN — $greens/$NEED reachability sample(s) ${GAP}s apart (last http=$last_code, unauthenticated, zero quota)."
  echo "          This is arm 2 of 3. It is NECESSARY and NOT SUFFICIENT: it says the path is reachable,"
  echo "          never that re-firing is correct. A unit a live process still holds (PENDING /"
  echo "          UNSETTLED-INFLIGHT / RUNNING) is not re-fired on a green probe."
fi
exit 0
