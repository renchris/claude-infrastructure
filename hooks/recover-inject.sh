#!/bin/bash
# recover-inject.sh — UserPromptSubmit. D3 of docs/plans/NONLIMIT_RESUME_LADDER.md (T6/W2-B).
#
# WHAT IT REPLACES: a paragraph the operator types by hand. On 2026-09-09 they typed it seven times
# in 93 seconds, once per blocked pane. That is a hand-off that makes the human the runtime, and it
# is the actual ask behind this plan — the trigger was never the problem, the agency was.
#
# WHY A HOOK AND NOT A COMMAND. `/limit-recover`'s description named only quota and auth-cliff
# triggers, so "(Reconnected to internet, continue)" loaded none of it and the model reconciled from
# CONTEXT — which still holds the pre-kill narrative, reads plausible, satisfices on the units it
# remembers, and smooths the gaps into the conclusion. A command has to be INVOKED to correct that;
# a UserPromptSubmit hook fires on the prompt the operator was going to type anyway, and on the
# harness's own `<task-notification>` wake, which is the majority wake in this fleet. So this makes
# the operator's paragraph correct if typed, and unnecessary if not.
#
# WHAT IT IS NOT. It emits CONTEXT. It fires nothing, re-runs nothing, spends nothing, and blocks no
# prompt. Every path here exits 0. The re-fire decision belongs to the model, gated on the audit and
# the probe, and this hook's text says so in the imperative.
#
# ── THE TRIGGER IS STRUCTURAL: no error text is enumerated anywhere in this file ─────────────────
# Two of Q3's three predicates (the third, `SessionStart source=resume`, is a different event and so
# a different hook — D4):
#   P2  the last assistant record is `isApiErrorMessage:true`, ANY `error` value. A cap and a network
#       drop share this envelope byte for byte; they differ only in which recovery MODE is legal.
#   P3  a `<task-notification>` whose `<status>` is not `completed` (failed · killed · stopped).
# Both live in scripts/limit-recover/lr-lib.sh, not here — three callers had already grown their own
# spelling of P2 before it had one home, which is the divergence that file exists to prevent.
#
# ── COST: TWO PHASES, and the reason ────────────────────────────────────────────────────────────
# This runs on EVERY prompt, so it may not read a whole transcript — they reach tens of MB.
#   Phase 1 (every prompt): a fixed-size TAIL answers both predicates exactly, because both ask only
#           about the most recent records. No hit ⇒ exit 0, having read 128 KB.
#   Phase 2 (only on a hit, and only once per death): `lr-audit.py --ledger-only`, one pass over the
#           file, for the population of OPEN delegations. A tail cannot answer that — a spawn 500
#           lines back with no result is exactly what must be listed — so it is paid once, when
#           something has actually died.
#
# ── THE LATCH ───────────────────────────────────────────────────────────────────────────────────
# Once per DEATH RECORD, keyed on its uuid (P2) or its task-id+status (P3). Not once per session:
# a second death must speak. Not once per prompt: that is a nag, and a nag gets ignored precisely
# when it matters. The key comes from lr-lib, which digests the record's own fields when the harness
# wrote no uuid rather than degrading to a constant — a constant key would latch the FIRST death for
# the life of the session and go silent on every later one.
#
# Seams: CC_RECOVER_INJECT=off kills it entirely · LR_STATE_DIR relocates the latch ·
# LR_TAIL_BYTES sizes the phase-1 tail (lr-lib) · CC_RECOVER_INJECT_LOG relocates the log.

# NOT `set -e`. This hook's contract is that it can never cost a prompt, and under errexit any
# nonzero — a refusing predicate, a missing binary, a full disk — exits mid-file at whatever point it
# happened. Explicit control flow, and one exit 0 at the end.
set -uo pipefail

[ "${CC_RECOVER_INJECT:-on}" = "off" ] && exit 0

STATE="${LR_STATE_DIR:-$HOME/.reso/limit-recover}"
LOG="${CC_RECOVER_INJECT_LOG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/logs/recover-inject.log}"

# EVERY REFUSAL IS LOGGED. An advisory hook must exit 0 when its instruments are missing — it cannot
# block a prompt to complain — but "exit 0 having said nothing" is byte-identical to "nothing was
# interrupted", which is the unfalsifiable fail-safe this whole plan is about. So the prompt stays
# silent and the refusal goes on the record, where a census can find it.
_rl() { # $1=reason
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || return 0
  printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ 2>/dev/null || echo '-')" "${SID:--}" "$1" >> "$LOG" 2>/dev/null || true
}

_stdin_json="$(cat 2>/dev/null || true)"   # fully consumed, so the writer never SIGPIPEs

command -v jq >/dev/null 2>&1 || { _rl "refused: jq absent"; exit 0; }

SID="$(printf '%s' "$_stdin_json" | jq -r '.session_id // empty' 2>/dev/null || true)"
TP="$(printf '%s' "$_stdin_json" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$TP" ] && [ -f "$TP" ] || { _rl "refused: no readable transcript_path"; exit 0; }

# The library ladder, in the same shape and order every other limit-recover caller uses. $0 is
# resolved through readlink because this file is deployed as a per-file SYMLINK into ~/.claude, and a
# $0-relative sibling lookup then resolves against the LINK's directory — where some siblings exist
# and some do not, so one invocation silently splits into a half that resolves and a half that dies.
_RI_SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
_RI_DIR="$(cd "$(dirname "$_RI_SELF")" && pwd 2>/dev/null || printf '%s' '.')"
LR_DIR=""
for _c in "$_RI_DIR/../scripts/limit-recover" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover" "$HOME/.claude/scripts/limit-recover"; do
  [ -f "$_c/lr-lib.sh" ] && { LR_DIR="$(cd "$_c" && pwd)"; break; }
done
[ -n "$LR_DIR" ] || { _rl "refused: lr-lib.sh not found from $_RI_DIR"; exit 0; }
# shellcheck source=../scripts/limit-recover/lr-lib.sh
# shellcheck disable=SC1091
. "$LR_DIR/lr-lib.sh" 2>/dev/null || { _rl "refused: lr-lib.sh unreadable"; exit 0; }
command -v lr_last_api_error >/dev/null 2>&1 || { _rl "refused: lr-lib too old — no lr_last_api_error (landed is not live)"; exit 0; }

# ── PHASE 1 — the tail ──────────────────────────────────────────────────────────────────────────
KEY="" HEAD="" DETAIL=""
if _ae="$(lr_last_api_error "$TP")"; then
  IFS=$'\t' read -r _uuid _err _kind _ts <<<"$_ae"
  KEY="ae:$_uuid"
  HEAD="This session's LAST assistant record is an API-ERROR record"
  DETAIL="record uuid \`$_uuid\` · error \`$_err\` · at $_ts"
  if [ "$_kind" = limit ]; then
    DETAIL="$DETAIL · the text carries a QUOTA message, so the \`limit\` mode may apply (headroom, reset, transplant)"
  else
    DETAIL="$DETAIL · NOT a quota message, so the account is probably fine and a transplant would spend an account move on a problem that no longer exists"
  fi
elif command -v lr_tail_nonsuccess_notification >/dev/null 2>&1 && _nn="$(lr_tail_nonsuccess_notification "$TP")"; then
  IFS=$'\t' read -r _task _tid _status <<<"$_nn"
  KEY="nn:$_task:$_status"
  HEAD="A background task settled NON-SUCCESSFULLY"
  DETAIL="task-id \`$_task\` · tool-use-id \`$_tid\` · status \`$_status\`"
else
  exit 0
fi

# ── THE LATCH ───────────────────────────────────────────────────────────────────────────────────
# Keyed per session AND per death record. The key is sanitised because it becomes a FILENAME and it
# comes from the transcript, i.e. from data this hook does not control.
LATCH_KEY="$(printf '%s' "$KEY" | tr -c 'A-Za-z0-9._:-' '_' | cut -c1-120)"
SID_SAFE="$(printf '%s' "${SID:-nosid}" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64)"
LATCH_DIR="$STATE/recover-inject/$SID_SAFE"
mkdir -p "$LATCH_DIR" 2>/dev/null || { _rl "refused: latch dir unwritable"; exit 0; }
LATCH="$LATCH_DIR/$LATCH_KEY"
# THE LATCH IS TAKEN BEFORE THE WORK, and atomically. Two prompts can race (a queued prompt and a
# notification wake land close together), and `mkdir` is the atomic test-and-set every shell has:
# `[ -e ] && exit` followed by `touch` is a check-then-act with a window between them.
mkdir "$LATCH.lock" 2>/dev/null || { _rl "latched: $LATCH_KEY"; exit 0; }

# ── PHASE 2 — the ledger, paid once ─────────────────────────────────────────────────────────────
OPEN_LINES=""
POP=""
if [ -f "$LR_DIR/lr-audit.py" ]; then
  _led="$(/usr/bin/python3 "$LR_DIR/lr-audit.py" --ledger-only --transcript "$TP" 2>/dev/null || true)"
  if [ -n "$_led" ]; then
    OPEN_LINES="$(printf '%s' "$_led" | jq -r '
      (.open_delegations // [])[]
      | "  - \(.tool//"?") `\(.tool_use_id)`\(if .description then " — \(.description)" else "" end)"
    ' 2>/dev/null || true)"
    POP="$(printf '%s' "$_led" | jq -r '
      [(.population_by_tool // {}) | to_entries[]
       | "\(.key) \(.value.total) (settled \(.value.settled), open \(.value.open))"] | join(" · ")
    ' 2>/dev/null || true)"
  else
    _rl "ledger: --ledger-only produced nothing for $TP"
  fi
else
  _rl "ledger: lr-audit.py absent beside $LR_DIR"
fi
# A ZERO NAMES ITS STRATA. "no open delegations" and "I could not read the population" are different
# facts and must not render as the same sentence — that collapse is how a fail-safe comes to mimic
# the healthy state.
if [ -z "$POP" ] || [ "$POP" = "" ]; then
  POP="UNREAD — the ledger could not be computed; do not read this as 'nothing was delegated'"
fi
if [ -z "$OPEN_LINES" ]; then
  OPEN_LINES="  - (none open by tool-use-id — every spawn has a tool_result or a task-notification)"
fi

BODY="$(cat <<EOF
⚠️ INTERRUPTED WORK DETECTED ON DISK — audit before anything else.

$HEAD.
$DETAIL

Delegation population (by tool): $POP
Open delegations (spawned, never settled by a tool_result or a task-notification):
$OPEN_LINES

WHY YOU ARE BEING TOLD: your context still holds the pre-kill narrative. It reads plausible, and
reconciling from it is the exact failure mode here — you will satisfice on the units you remember
and smooth the gaps into your conclusion. Disk is the only ground truth.

DO THIS FIRST, before answering the prompt and before re-firing anything:

  python3 ~/.claude/scripts/limit-recover/lr-audit.py \\
    --md ~/.reso/limit-recover/\$CLAUDE_CODE_SESSION_ID/audit-latest.md \\
    --salvage-dir ~/.reso/limit-recover/\$CLAUDE_CODE_SESSION_ID/salvage

Then run /recover (or /limit-recover) and execute its Verdict → action table. Four rules bind:

  1. An empty limit_events list is NOT an all-clear. It is the QUOTA subset, and it is empty on
     every network death, crash and stall — beside a fully correct gap ledger.
  2. Disk silence is NOT death. Read the audit's 'lead process' line: a network drop usually leaves
     the process alive, and one measured retry ladder ran 93 minutes with nothing written at all.
  3. NEVER re-run a unit a live process still holds. PENDING (wait for the notification),
     UNSETTLED-INFLIGHT (do not touch) and RUNNING (never respawn over a live member) are verdicts,
     not delays.
  4. Do NOT re-fire on a STALLED unit until an independent connectivity probe is green TWICE, 30s
     apart. The harness already exhausted its own retries; on the measured incident five identical
     re-fires into a live outage cost 85 minutes and produced nothing.

This notice fires ONCE per death record. It is context, not an instruction to spend anything.
EOF
)"

printf '%s' "$_stdin_json" | jq -n --arg ctx "$BODY" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}' 2>/dev/null \
  || { _rl "refused: could not emit context for $LATCH_KEY"; rmdir "$LATCH.lock" 2>/dev/null || true; exit 0; }

_rl "emitted: $LATCH_KEY"
exit 0
