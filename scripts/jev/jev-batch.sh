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
if [ ! -f "$ARM" ]; then
  _log "not-armed — no call made (arm with: cc-jev arm)"
  exit 0
fi

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

# ── LOCAL PRECONDITIONS ARE CHECKED BEFORE THE TOKEN IS SPENT ────────────────────────────────
# The consume-before-call rule is about CALLS: once bytes have left the machine the authorisation
# must already be gone, so a crash cannot leave a live one behind. It is NOT a reason to spend the
# token on a precondition that makes no call. Measured 2026-09-21: the first version consumed
# first, then exited 2 at `jev_available` because no key was present — the operator's armed window
# was gone, nothing had been sent, and the log said `run rc=2` over an empty rows file. An arming
# is a scarce human act; burning one on a missing env var is the cheapest possible waste.
# Both checks below are pure local reads — an env var, a secrets-store lookup, a date — and
# neither touches the network.
# shellcheck source=/dev/null
. "$ROOT/hooks/lib/jev.sh"
if ! jev_window_open 2>/dev/null; then
  _log "REFUSED — the free window has lapsed; arm PRESERVED (authorise with CC_JEV_PAID=1)"
  exit 0
fi
if ! jev_available; then
  _log "REFUSED — jev not available (no key, or CC_JEV=0); arm PRESERVED, nothing spent"
  exit 0
fi

# ── CONSUME. Everything below runs with no authorisation left on disk. ───────────────────────
rm -f "$ARM" || { _log "REFUSED — cannot consume the arm file; refusing to call"; exit 0; }
_log "ARMED — expires=${EXPIRES} max_calls=${MAXC} cap_b=${CAPB:-default} corpus=${CORPUS:-memory-orphans}"

# The call ceiling the token consented to, honoured by construction rather than by intention:
# heats and head-to-heads are 2 calls per challenger, plus the preflight and the bias sample.
BIAS=$(( MAXC / 10 )); [ "$BIAS" -lt 2 ] && BIAS=2
HEATS=$(( (MAXC - 1 - BIAS) / 2 )); [ "$HEATS" -lt 1 ] && HEATS=1

OUTLOG="$HOME/.claude/autonomy/jev-batch-$(date -u +%Y%m%dT%H%M%SZ).out"
# CC_JEV_ZDR=0 is what the operator authorised by arming; the ceiling and cap ride with it.
env CC_JEV_ZDR=0 ${CAPB:+CC_JEV_PROMO_CAP_B="$CAPB"} \
    "$ROOT/scripts/jev/promote-memory.sh" --heats "$HEATS" --bias-n "$BIAS" --yes \
    > "$OUTLOG" 2>&1
rc=$?
ROWS="$(grep -o '/.*jev-promote-.*\.jsonl' "$OUTLOG" 2>/dev/null | tail -1)"
_log "run rc=$rc rows=${ROWS:-none} out=$OUTLOG"
exit 0
