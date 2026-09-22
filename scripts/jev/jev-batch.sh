#!/usr/bin/env bash
# jev-batch.sh — the SCHEDULED entry point. launchd runs this; it calls Jev only when the operator
# has armed it, and it is inert in every other state.
#
# ── WHY A SENTINEL AND NOT JUST A TIMER ──────────────────────────────────────────────────────
# A launchd job is not bound by the session permission classifier — it runs as a daemon with no
# Claude Code process in the loop, and this machine already has precedent for scheduled egress
# (com.claude.dispatcher POSTs briefs to api.anthropic.com every 300s). So a bare timer WOULD
# work, and that is exactly the problem: it would convert "the operator typed one command" into
# "our lessons leave this machine on a clock, forever, under standard retention", and nobody
# decided that. Standing unattended egress is a real value fork and it belongs to the operator.
#
# The sentinel makes the schedule durable while leaving the CONSENT per-window. Three conditions,
# and all three are what stop this being consent-laundering:
#   1. It is CONSUMED BEFORE THE FIRST CALL, never after — a crash or a kill mid-run must not
#      leave a live authorisation behind for the next tick to re-use.
#   2. It EXPIRES on a clock, so an armed window that nobody used closes by itself.
#   3. It CARRIES the terms it consents to — corpus, per-file byte cap, call ceiling — and this
#      job refuses to exceed any of them. A token that authorises an unbounded act is not consent.
# An agent must never write this file. The whole point is that a human did.
set -uo pipefail

_resolve_self() {
  local p="$1" d
  while [ -L "$p" ]; do d="$(cd -P "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac; done
  printf '%s' "$p"
}
SELF="$(_resolve_self "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$SELF")/../.." && pwd)"

ARM="${CC_JEV_ARM_FILE:-$HOME/.claude/autonomy/jev-batch.arm}"
LOG="${CC_JEV_BATCH_LOG:-$HOME/.claude/autonomy/jev-batch.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null
_log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG"; }

# ── INERT BY DEFAULT ─────────────────────────────────────────────────────────────────────────
# Exit 0, not 1. A scheduled job that exits non-zero on its NORMAL state trains everyone to ignore
# its failures, and launchd would throttle it. "Not armed" is not an error; it is the resting state.
# ── UNATTENDED MODE ──────────────────────────────────────────────────────────────────────────
# Authorised by the operator on 2026-09-21, decision packet ea7a241bdf78: the job may call out on
# its own. Recorded as a FILE rather than an env var because launchd never sees this agent's
# environment, and absence means OFF — a lost or corrupted record must fail to the state that
# sends nothing, never to the one that sends.
#
# 🚨 IT IS GATED ON THE CORPUS HAVING CHANGED, and that gate is not optional. The timer fires every
# 1800s; the pass is 133 calls. Re-running a COMPLETED pass on every tick is ~6,384 calls/day over
# a population whose verdicts are already on disk — it would exhaust any budget within a day and
# learn nothing. The decision authorised unattended CALLS, not unattended WASTE, so the job asks
# "is there anything new to judge?" first: it compares the live corpus identity (orphans + anchors,
# hashed) against what the last completed pass recorded. Unchanged ⇒ one log line, no call.
UNATT="${CC_JEV_UNATTENDED_FILE:-$HOME/.claude/autonomy/jev-unattended.json}"
_unattended_ok() { [ -f "$UNATT" ] && [ "$(jq -r '.enabled // false' "$UNATT" 2>/dev/null)" = true ]; }

if [ ! -f "$ARM" ]; then
  if ! _unattended_ok; then
    _log "not-armed — no call made (arm with: cc-jev arm)"
    exit 0
  fi
  _live_sha="$("$ROOT/scripts/jev/promote-memory.sh" --corpus-sha 2>/dev/null)"
  if [ -z "$_live_sha" ]; then
    _log "unattended: cannot read the live corpus identity — no call made"
    exit 0
  fi
  # The newest COMPLETED pass, by its own recorded plan. An incomplete one is left to the resume
  # path below, which is the whole reason a partial run is not treated as "already done".
  _last_sha=""
  while IFS= read -r _c; do
    [ -n "$_c" ] || continue
    _p="$(jq -r 'select(.round=="meta")|.plan // empty' "$_c" 2>/dev/null | head -1)"
    _v="$(jq -r 'select(.round!="meta")|.id' "$_c" 2>/dev/null | wc -l | tr -d ' ')"
    case "$_p" in ''|*[!0-9]*) continue ;; esac
    if [ "$_v" -ge "$_p" ]; then
      _last_sha="$(jq -r 'select(.round=="meta")|.corpus_sha // empty' "$_c" 2>/dev/null | head -1)"
      break
    fi
  done <<EOF
$(find -H "$HOME/.claude/autonomy" -maxdepth 1 -name 'jev-promote-*.jsonl' -size +0c 2>/dev/null | sort -r)
EOF
  if [ -n "$_last_sha" ] && [ "$_last_sha" = "$_live_sha" ]; then
    _log "unattended: corpus unchanged since the last completed pass ($_live_sha) — no call made"
    exit 0
  fi
  # Synthesise the same bounded terms an arming would have carried, from the same source of truth.
  MAXC="$("$ROOT/scripts/jev/promote-memory.sh" --plan-calls 2>/dev/null)"
  case "$MAXC" in ''|*[!0-9]*) MAXC=133 ;; esac
  CAPB="${CC_JEV_PROMO_CAP_B:-1200}"; EXPIRES="n/a (unattended)"; CORPUS="memory-orphans"
  _log "UNATTENDED — corpus ${_live_sha} differs from last completed (${_last_sha:-none}); max_calls=${MAXC}"
  UNATTENDED_RUN=1
fi
UNATTENDED_RUN="${UNATTENDED_RUN:-0}"

if [ "$UNATTENDED_RUN" -eq 0 ]; then
_field() { jq -r --arg k "$1" '.[$k] // empty' "$ARM" 2>/dev/null; }
EXPIRES="$(_field expires)"; MAXC="$(_field max_calls)"; CAPB="$(_field cap_b)"; CORPUS="$(_field corpus)"
NOW="$(date -u +%s 2>/dev/null)"

# A malformed token is a REFUSAL, and the token is consumed anyway. An unparseable authorisation
# cannot be honoured, and leaving it on disk would make every subsequent tick re-read the same
# garbage — a permanent alarm nobody can clear.
if [ -z "$EXPIRES" ] || [ -z "$MAXC" ] || [ -z "$NOW" ]; then
  _log "REFUSED — arm file is malformed or the clock is unreadable; consuming it"
  rm -f "$ARM"; exit 0
fi
EXP_S="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$EXPIRES" +%s 2>/dev/null || date -u -d "$EXPIRES" +%s 2>/dev/null)"
if [ -z "$EXP_S" ] || [ "$NOW" -ge "$EXP_S" ]; then
  _log "EXPIRED at ${EXPIRES} — consuming, no call made"
  rm -f "$ARM"; exit 0
fi
fi

# ── LOCAL PRECONDITIONS ARE CHECKED BEFORE THE TOKEN IS SPENT ────────────────────────────────
# The consume-before-call rule is about CALLS: once bytes have left the machine the authorisation
# must already be gone, so a crash cannot leave a live one behind. It is NOT a reason to spend the
# token on a precondition that makes no call. Measured 2026-09-21: the first version consumed
# first, then exited 2 at `jev_available` because no key was present — the operator's armed window
# was gone, nothing had been sent, and the log said `run rc=2` over an empty rows file. An arming
# is a scarce human act; burning one on a missing env var is the cheapest possible waste.
# Both checks below are pure local reads — an env var, a secrets-store lookup, a date — and
# neither touches the network.
# 🚨 THESE TWO GATE **BOTH** PATHS, and that is why they sit outside the armed-only block.
# A first draft left them inside it, so the unattended path — the one the operator had just
# authorised — skipped the BILLING GUARD entirely and would have gone on calling past the free
# window on 2026-09-25 at 0.042 USD/MTok, unattended, with nothing in the loop to notice. The
# operator authorised unattended CALLS; they did not authorise unattended SPEND, and the whole
# point of jev_window_open is that the distinction is enforced rather than remembered.
# shellcheck source=/dev/null
. "$ROOT/hooks/lib/jev.sh"
# The message names what is actually at stake on THIS path: an arming is a scarce human act and
# saying it survived is the useful half, while on the unattended path there is no arm to preserve
# and claiming one would be false.
if [ "$UNATTENDED_RUN" -eq 0 ]; then _KEPT="arm PRESERVED, nothing spent"; else _KEPT="nothing spent"; fi
if ! jev_window_open 2>/dev/null; then
  _log "REFUSED — the free window has lapsed; $_KEPT (authorise with CC_JEV_PAID=1)"
  exit 0
fi
if ! jev_available; then
  _log "REFUSED — jev not available (no key, or CC_JEV=0); $_KEPT"
  exit 0
fi

# ── CONSUME, armed path only. Below this line no authorisation is left on disk. ──────────────
if [ "$UNATTENDED_RUN" -eq 0 ]; then
  rm -f "$ARM" || { _log "REFUSED — cannot consume the arm file; refusing to call"; exit 0; }
  _log "ARMED — expires=${EXPIRES} max_calls=${MAXC} cap_b=${CAPB:-default} corpus=${CORPUS:-memory-orphans}"
fi

# Both paths converge here, and the guards below are the ones that SURVIVE the operator's yes:
# the billing cliff, the call ceiling, the byte cap. Unattended changes who decides to call, not
# what a call is allowed to be.

# The call ceiling the token consented to, honoured by construction rather than by intention:
# heats and head-to-heads are 2 calls per challenger, plus the preflight and the bias sample.
BIAS=$(( MAXC / 10 )); [ "$BIAS" -lt 2 ] && BIAS=2
HEATS=$(( (MAXC - 1 - BIAS) / 2 )); [ "$HEATS" -lt 1 ] && HEATS=1

# ── RESUME AN UNFINISHED PASS RATHER THAN RE-BUYING IT ───────────────────────────────────────
# An arming is a scarce human act, and without this a second one starts the corpus over: the run
# is 133 calls and any abort — rate-limit exhaustion, a revoked key, a reboot — leaves it partial,
# so arming again would re-pay for every verdict already on disk and still not finish.
# The compatibility check lives in promote-memory.sh (the meta row stamps the population and the
# seed, and a mismatch REFUSES rather than splicing verdicts about other files into this run), so
# all that is needed here is to nominate a candidate: the newest promote rows that are recent
# enough to plausibly be the same corpus and that fall short of their own recorded plan.
# An ARRAY, not a string: two arguments must stay two arguments, and an unquoted string that
# happens to be empty would pass a stray empty arg. `${a[@]+"${a[@]}"}` is the expansion that is
# safe under `set -u` on bash 3.2, which is what launchd resolves via /usr/bin/env.
RESUME_ARG=()
_plan_of() { jq -r 'select(.round=="meta")|.plan // empty' "$1" 2>/dev/null | head -1; }
_verdicts_in() { jq -r 'select(.round!="meta")|.id' "$1" 2>/dev/null | wc -l | tr -d ' '; }
MAXAGE_H="${CC_JEV_BATCH_RESUME_MAX_AGE_H:-48}"
while IFS= read -r _c; do
  [ -n "$_c" ] || continue
  # find -mtime is coarse; compare stamps directly so the bound means what it says.
  _age=$(( ( $(date -u +%s) - $(stat -f %m "$_c" 2>/dev/null || echo 0) ) / 3600 ))
  [ "$_age" -le "$MAXAGE_H" ] || break          # older than the bound: everything below is older too
  # A mock run must never be resumed into a real one: the rows would be a real pass carrying
  # verdicts that were never about this repo's lessons, and every consumer downstream reads the
  # file as one artifact. The marker is written from the route at call time.
  if [ "$(jq -r 'select(.mock==true)|.id' "$_c" 2>/dev/null | head -1)" != "" ]; then continue; fi
  _plan="$(_plan_of "$_c")"; _have_n="$(_verdicts_in "$_c")"
  case "$_plan" in ''|*[!0-9]*) continue ;; esac   # unstamped: predates the meta row, cannot resume
  if [ "$_have_n" -lt "$_plan" ]; then
    RESUME_ARG=(--resume "$_c")
    _log "RESUMING $_c — $_have_n of $_plan verdict(s) already on disk (${_age}h old)"
    break
  fi
done <<EOF
$(find -H "$HOME/.claude/autonomy" -maxdepth 1 -name 'jev-promote-*.jsonl' -size +0c 2>/dev/null | sort -r)
EOF

OUTLOG="$HOME/.claude/autonomy/jev-batch-$(date -u +%Y%m%dT%H%M%SZ).out"
# CC_JEV_ZDR=0 is what the operator authorised by arming; the ceiling and cap ride with it.
# STREAM TO THE TERMINAL WHEN A HUMAN IS WATCHING, file-only when launchd runs it.
# The pass is 133 calls and ~9-27 minutes. Writing only to a file meant an operator who ran this
# by hand got a blank terminal for the whole run — and quiet is what every liveness surface on
# this box, and every person, reads as stuck. `[ -t 1 ]` is the discriminator that needs no flag:
# launchd hands the job a file descriptor that is not a terminal, so it keeps exactly today's
# behaviour there, and nothing about the scheduled path changes.
# PIPESTATUS, not $?, because with `| tee` the shell reports TEE's status — which is 0 whether the
# pass succeeded or died, and would have turned every failure into a clean `run rc=0`.
if [ -t 1 ]; then
  env CC_JEV_ZDR=0 ${CAPB:+CC_JEV_PROMO_CAP_B="$CAPB"} \
      "$ROOT/scripts/jev/promote-memory.sh" --heats "$HEATS" --bias-n "$BIAS" ${RESUME_ARG[@]+"${RESUME_ARG[@]}"} --yes \
      2>&1 | tee "$OUTLOG"
  rc=${PIPESTATUS[0]}
else
  env CC_JEV_ZDR=0 ${CAPB:+CC_JEV_PROMO_CAP_B="$CAPB"} \
      "$ROOT/scripts/jev/promote-memory.sh" --heats "$HEATS" --bias-n "$BIAS" ${RESUME_ARG[@]+"${RESUME_ARG[@]}"} --yes \
      > "$OUTLOG" 2>&1
  rc=$?
fi
ROWS="$(grep -o '/.*jev-promote-.*\.jsonl' "$OUTLOG" 2>/dev/null | tail -1)"
_log "run rc=$rc rows=${ROWS:-none} out=$OUTLOG"
exit 0
