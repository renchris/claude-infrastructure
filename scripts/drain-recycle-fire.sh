#!/usr/bin/env bash
# drain-recycle-fire.sh — FIRE THE NEXT LINK OF THE 24/7 DRAIN CHAIN, WITH ITS GOAL ATTACHED.
#
# ── THE DEFECT THIS CLOSES ──────────────────────────────────────────────────────────────────────
# BACKLOG_DRAIN_24_7 §4.1 is the SSOT the drain chain regenerates its brief from, and its fire
# command has carried a `--goal` since the template was written. The live chain does not. Measured
# 2026-08-31 over ~/.claude/logs/handoffs.jsonl, which records `goal_requested` on the fire's OWN
# row: **183 recycle-intent fires with `goal_requested:false` against 46 true**, and every one of
# the last forty is false. So for 279 links nothing mechanically bound a recycle to closing a
# backlog row, and the measured result is what DRAIN_CIRCUIT_2026-09-01 §1.4 names: over 7 days,
# **304 trunk commits against 30 backlog closures** — ~10 commits per closure — with the entire file
# footprint being the drain machinery itself. Each recycle audits the recycle before it.
#
# WHY THE TEMPLATE ALONE COULD NOT HOLD, AND WHY THIS IS A SCRIPT. §4.1's fire command is prose a
# session retypes each cycle, and the chain has DIVERGED from it: the brief outgrew a promptable
# payload, so the chain invented a 152-byte pointer (`fire-pointer-<N>.txt`) and fires that instead.
# The divergence was correct; what went with it was the `--goal`, because a hand-retyped command
# loses whatever the retyper does not think of. `handoff-fire.sh --recycle` also INHERITS the
# predecessor's live goal when none is passed (scripts/handoff-fire.sh §GOAL INHERITANCE), so a
# single link that dropped the goal makes every link after it goal-less by construction — which is
# exactly the 183-to-46 shape. A rule that is retyped is a rule that decays; a rule that is a
# CHOKEPOINT does not (memory `enforcement-must-live-at-the-chokepoint`). This file is that
# chokepoint: the goal is not an argument the caller may forget, it is what the caller invokes.
#
# ── THE CLOSURE FLOOR, AND WHY IT LIVES IN THE GOAL RATHER THAN IN THIS SCRIPT ───────────────────
# §4.1 invariant 4 already says "Conservation: close >= file, printed in the close", and §4.1
# invariant 6 says "THE CHAIN IS THE DELIVERABLE: firing recycle #N+1 outranks finishing one more
# row". Read together, a link that files three rows, closes none, and fires its successor has obeyed
# the ranked invariant and merely skipped the unranked one. Over 278 cycles it did.
#
# The floor therefore goes into the GOAL CONDITION, which is the only surface on this box that can
# refuse to let a session stop: the evaluator re-judges after every turn and blocks the Stop until
# the condition is met. It is NOT enforced by this script refusing to fire — that would be the one
# failure mode the chain cannot survive, a link that ends with no successor. Firing stays
# unconditional; what the goal changes is that the session cannot reach the fire having discharged
# nothing.
#
# THE CHECK IS PRINTED, NOT ASSERTED IN PROSE. The goal evaluator is a separate TOOL-LESS model that
# sees only what the session SURFACES, so a condition naming state nobody prints is unreachable and
# can never clear. `--closure-report` is that surface: it prints its own predicate and a
# `floor=MET|UNMET` token computed from the ledger, so the evaluator judges a tool's output rather
# than the session's self-report (memory `claimed-outcome-vs-checked-outcome`).
#
# Usage:
#   drain-recycle-fire.sh --num <N+1> --prompt-file <pointer> [handoff-fire args...]
#                                     fire the next link with the goal attached
#   drain-recycle-fire.sh --num <N+1> --print-goal
#                                     print the condition and exit — no side effect, and the way
#                                     to read back what a fire WOULD arm
#   drain-recycle-fire.sh --closure-report <ISO-8601-Z>
#                                     closed/filed since that instant, with the predicate and the
#                                     floor verdict. THE COMMAND THE GOAL CONDITION NAMES.
# Env:
#   CC_BACKLOG_FILE   the ledger (default $CLAUDE_CONFIG_DIR/autonomy/backlog.jsonl)
#   CC_DRAIN_PROJECT  default claude-infrastructure — the project the floor is counted over
#   CC_DRAIN_FIRE_BIN default $REPO/scripts/handoff-fire.sh — the fire path, injectable for tests
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
CFG="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
LEDGER="${CC_BACKLOG_FILE:-$CFG/autonomy/backlog.jsonl}"
PROJECT="${CC_DRAIN_PROJECT:-claude-infrastructure}"
FIRE_BIN="${CC_DRAIN_FIRE_BIN:-$REPO/scripts/handoff-fire.sh}"

die() { printf 'drain-recycle-fire: %s\n' "$1" >&2; exit 2; }

# ── the closure report — the goal condition's printed check ─────────────────────────────────────
# Counts DISTINCT ids, not events: a row closed, reopened and closed again inside one recycle is one
# closure, and counting events would let a single row satisfy the floor twice. `add` is the filing
# verb; cc-backlog's own update arm re-emits `add` for a known id, so the same distinct-id fold is
# what keeps a title refresh from reading as a new filing.
closure_report() {
  local since="$1" out
  case "$since" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*Z) : ;;
    *) die "--closure-report needs an ISO-8601 Z timestamp (e.g. 2026-09-01T07:00:00Z), got '$since'" ;;
  esac
  command -v jq >/dev/null 2>&1 || die "jq is required"
  [ -r "$LEDGER" ] || die "no readable ledger at $LEDGER"

  out="$(jq -rs --arg since "$since" --arg proj "$PROJECT" '
    ( [ .[] | select((.ts // "") >= $since) ] ) as $w
    | ( [ $w[] | select(.event == "done")             | .id ] | unique | length ) as $closed
    | ( [ $w[] | select(.event == "add")              | .id ] | unique | length ) as $filed
    | ( [ $w[] | select(.event == "block")            | .id ] | unique | length ) as $blocked
    | "closed=\($closed) filed=\($filed) blocked=\($blocked) floor=" +
      (if $closed >= 1 and $closed >= $filed then "MET" else "UNMET" end)
  ' "$LEDGER" 2>/dev/null)" || out=""
  [ -n "$out" ] || die "could not fold the ledger at $LEDGER"

  printf 'DRAIN CLOSURE REPORT — %s --closure-report %s\n' "${BASH_SOURCE[0]}" "$since"
  printf 'predicate: DISTINCT ids per event since the instant above, over the whole ledger.\n'
  printf '           closed = ids with a done event · filed = ids with an add event\n'
  printf '           (cc-backlog re-emits add on a title refresh, so distinct-id is what keeps a\n'
  printf '           refresh from reading as a new filing) · blocked = ids routed to the operator.\n'
  printf 'floor:     MET requires closed >= 1 AND closed >= filed. A recycle that discharges nothing\n'
  printf '           is UNMET however much it committed — DRAIN_CIRCUIT_2026-09-01 §1.4.\n'
  printf 'ledger:    %s\n' "$LEDGER"
  printf '%s\n' "$out"
  case "$out" in *floor=MET*) return 0 ;; *) return 1 ;; esac
}

# ── the goal condition ──────────────────────────────────────────────────────────────────────────
# ONE LINE, no leading slash, well under the harness's 4000-char cap — all three are refused by
# handoff-fire.sh's check_goal_arm, and a refusal here would cost the chain a link.
#
# THE ORDER OF CLAUSES IS THE FIX. §4.1 records that #124 skipped its ping because the ping had "no
# position in the sequence at all" while the fire did — a duty with no position ahead of the fire is
# unreachable the moment the session takes the goal at its word. The closure floor is that same
# lesson applied to invariant 4: it is stated FIRST and the fire LAST, so invariant 6 is subordinate
# by position and not merely by prose.
goal_condition() {
  local n="$1" since="$2"
  printf '%s' "recycle #${n} of the 24/7 backlog drain chain has DISCHARGED BACKLOG ROWS, not audited its own machinery — proven by this session RUNNING and PRINTING \`bash scripts/drain-recycle-fire.sh --closure-report ${since}\` and that output reading floor=MET (closed >= 1 AND closed >= filed) for work done THIS recycle; then the close line \`<effort>: N open / M blocked (K operator-gated)\` is printed with its blocked tail, never a bare zero; then the HANDOFF-PING to the lead is SENT and its enqueued=1 printed; then recycle #$((n+1)) is FIRED with this same wrapper as the LAST action and its engagement line printed. Constraints: do not close a row without same-moment content evidence; do not satisfy the floor by filing rows, by editing the drain machinery, or by counting another lane's closures; if a full falsifier pass over the claimed effort genuinely closes nothing, print the per-row evidence for that before firing rather than ending silently net-negative."
}

# ── argv ────────────────────────────────────────────────────────────────────────────────────────
NUM=""; PROMPT=""; MODE="fire"; SINCE=""
PASS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --num)              NUM="${2:?--num needs the recycle number being FIRED}"; shift 2 ;;
    --prompt-file)      PROMPT="${2:?--prompt-file needs a path}"; shift 2 ;;
    --print-goal)       MODE="print"; shift ;;
    --closure-report)   MODE="closure"; SINCE="${2:?--closure-report needs an ISO-8601 Z timestamp}"; shift 2 ;;
    --since)            SINCE="${2:?--since needs an ISO-8601 Z timestamp}"; shift 2 ;;
    --help|-h)          sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *)                  PASS+=("$1"); shift ;;      # everything else is handoff-fire's
  esac
done

if [ "$MODE" = closure ]; then closure_report "$SINCE"; exit $?; fi

case "${NUM:-}" in ''|*[!0-9]*) die "--num must be the recycle number being fired (digits only)" ;; esac
# The window opens NOW by default: a link measures the rows IT discharged, never its predecessor's.
# An explicit --since lets a session that started earlier pin its own true start instant.
[ -n "$SINCE" ] || SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COND="$(goal_condition "$NUM" "$SINCE")"

# Fail fast on the three shapes handoff-fire refuses, so a malformed condition costs a message here
# rather than a link that fires without its goal.
case "$COND" in /*) die "the condition must not start with '/'" ;; esac
[ "$(printf '%s' "$COND" | wc -l | tr -d ' ')" = 0 ] || die "the condition must be ONE line"
[ "${#COND}" -lt 4000 ] || die "the condition is ${#COND} chars; the harness caps it at 4000"

if [ "$MODE" = print ]; then printf '%s\n' "$COND"; exit 0; fi

[ -n "$PROMPT" ] || die "--prompt-file is required to fire (the pointer the brief lives behind)"
[ -r "$PROMPT" ] || die "--prompt-file $PROMPT is not readable — refusing to fire a link with no brief"
[ -r "$FIRE_BIN" ] || die "no handoff-fire at $FIRE_BIN"

exec bash "$FIRE_BIN" --recycle --prompt-file "$PROMPT" --goal "$COND" "${PASS[@]+"${PASS[@]}"}"
