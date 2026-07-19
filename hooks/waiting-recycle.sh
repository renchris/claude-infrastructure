#!/usr/bin/env bash
# waiting-recycle.sh — auto-recycle a MONITORING DESK when it is purely WAITING at MODERATE context.
#
# THE PROBLEM (operator, 2026-07-17): an orchestrator DESK that fires sessions and then WATCHES them
# fills with low-value watch noise. Context rot degrades instruction-following + state-recall well
# before the 90% auto-compact wall (noticeable ~40-50%, compounding past ~60-70%) and hits the
# "lost in the middle" load-bearing orchestration decisions. So a monitoring desk should recycle
# MORE AGGRESSIVELY than a builder — at a MODERATE threshold, at a quiet boundary, into a fresh
# successor that carries the state forward (the recycled pane IS the continuation).
#
# WHY A NEW HOOK, NOT boundary-handoff.sh (which already advises /handoff at a threshold):
#   boundary-handoff.sh fires on the **Stop** event. A watch-driven desk polling in a long turn (or
#   held open by session-continue's loose-ends loop) NEVER cleanly Stops, so that advisory never
#   lands and the desk OVER-ACCUMULATES (boundary-handoff's own B-1 header names this blind spot; the
#   out-of-session lead-supervisor.sh covers 'past-threshold ∧ not-Stopping' but can only PAGE — bash
#   cannot drive a live pane). This hook is the IN-SESSION carrier for exactly that case: it fires on
#   the desk's MONITORING CADENCE — PostToolUse:Bash, the heartbeat of a polling desk — so it reaches
#   the desk between polls, not only at a Stop it never hits. It ADVISES the desk's own model to run
#   its existing self-recycle path (/handoff → handoff-fire.sh --recycle); the hook never recycles
#   directly (only the model can capture the live orchestration state into the handoff payload).
#
# COMPOSES (reuse, not reinvent): boundary-handoff.sh's telemetry reader (used_pct freshness) ·
# anti-deference-nudge.sh's transcript-tell + genuine-carve-out + fail-safe + IDL discipline ·
# session-continue.sh's agent-armed-sentinel model (the agent declares intent; the hook is a dumb
# actuator) · the /handoff → handoff-fire.sh --recycle recycle path (unchanged).
#
# FIRE PREDICATE — ALL must hold (bias: FALSE-NEGATIVE over FALSE-POSITIVE; a missed recycle just
# waits for the threshold, a wrong recycle interrupts a healthy desk):
#   1. ARMED (opt-in) — the desk declared monitoring mode via `waiting-recycle.sh arm` (sentinel keyed
#      by cwd, so it survives a recycle: a monitoring desk stays one). OFF BY DEFAULT ⇒ a builder is
#      never touched. This IS the primary kill-switch (never arm / `clear`).
#   2. NOT globally killed — the blanket opt-out file ($CC_WR_KILL) is absent.
#   3. NOT in cooldown — no advisory for this cwd within COOLDOWN_S. This is the anti-thrash pacer AND
#      the cross-session LOOP-BREAKER: a fresh recycled desk (same cwd) sees the predecessor's cooldown
#      stamp and stays quiet, so recycle→fresh→recycle can't spin.
#   4. TRIGGER — context used_pct ≥ T (default 55, moderate; fresh telemetry), OR a behavioral ROT tell
#      (the desk re-deriving already-known orchestration state) in its last message — the rot tell
#      fires even BELOW threshold.
#   5. SAFE — genuinely just-WAITING: a CLEAN git tree (no uncommitted in-scope work) AND no open
#      decision/blocker in the last message (reuses anti-deference's GENUINE carve-out). Either ⇒ HOLD.
#   6. Under the per-session hard CAP (backstop against nagging a wedged session).
#
# Delivery: {decision:"block"} + hookSpecificOutput.additionalContext (the MODEL-facing recycle
# advisory — confirmed delivered on PostToolUse @ 2.1.183) + systemMessage/reason (operator-facing).
# The tool has ALREADY run at PostToolUse, so a fire can NEVER break the recycle machinery it triggers
# (unlike a PreToolUse deny). Exit 0 ALWAYS — a PostToolUse hook must never cost a session.
#
# Agent/operator CLI (run from the desk's worktree):
#   waiting-recycle.sh arm      # opt IN this desk to monitoring auto-recycle (keyed by cwd)
#   waiting-recycle.sh clear    # opt OUT this desk (per-desk kill-switch) + reset its cooldown/cap
#   waiting-recycle.sh status   # inspect this desk's arm/cooldown/cap + global kill state
#   waiting-recycle.sh kill      # GLOBAL blanket off (all sessions)
#   waiting-recycle.sh unkill    # remove the global kill-switch
# Claude Code calls it with NO args + the PostToolUse JSON on stdin → actuation mode.
#
# Env seams (tests): CC_WR_T · CC_TELEMETRY_DIR · CC_WR_AGE_MAX · CC_WR_IDL · CC_WR_STATE_DIR ·
#                    CC_WR_MAX · CC_WR_COOLDOWN_S · CC_WR_KILL
#
# NOTE: deliberately NO `set -e` — a hook must fail SAFE (abstain), and a stray non-zero from a grep
# test must never become the script's exit code and suppress a legitimate abstain-log. -u/pipefail are
# on for hygiene; every path ends `exit 0`.
set -uo pipefail

T="${CC_WR_T:-55}"                                          # moderate fire threshold, used_pct
ROT_FLOOR="${CC_WR_ROT_FLOOR:-25}"                          # rot-tell needs THIS much fill to be real
HARD_T="${CC_WR_HARD_T:-80}"                                # hard-zone: bias INVERTS above this (D-P2)
AGE_MAX="${CC_WR_AGE_MAX:-180}"                             # telemetry older than this can't be trusted
MAX="${CC_WR_MAX:-3}"                                       # per-session advisory cap (never nag forever)
COOLDOWN_S="${CC_WR_COOLDOWN_S:-600}"                       # cwd-keyed anti-thrash + cross-session loop-breaker
TEL_DIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"            # shared with boundary-handoff / statusline
IDL="${CC_WR_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
STATE_DIR="${CC_WR_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/waiting-recycle}"
KILL="${CC_WR_KILL:-$STATE_DIR/OFF}"                        # global blanket kill-switch
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Per-cwd key (arm + cooldown survive a recycle since cwd is stable across it); per-session key (cap
# resets on the fresh successor). Mirrors session-continue.sh's config-dir|path hash.
key_cwd() { printf '%s|%s' "$CFG" "$1" | shasum 2>/dev/null | cut -c1-16; }
arm_for()      { printf '%s/arm-%s'      "$STATE_DIR" "$(key_cwd "$1")"; }
cooldown_for() { printf '%s/cooldown-%s' "$STATE_DIR" "$(key_cwd "$1")"; }
cap_for()      { printf '%s/cap-%s'      "$STATE_DIR" "$1"; }               # keyed by session_id

# ---- Agent/operator CLI mode ---------------------------------------------------------------------
case "${1:-}" in
  arm)
    mkdir -p "$STATE_DIR" 2>/dev/null
    f="$(arm_for "$PWD")"; printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ) $PWD" > "$f"
    rm -f "$(cooldown_for "$PWD")" 2>/dev/null                              # fresh arm → clear stale cooldown
    echo "armed (monitoring auto-recycle) → $f"; exit 0 ;;
  clear)
    rm -f "$(arm_for "$PWD")" "$(cooldown_for "$PWD")" 2>/dev/null
    echo "cleared (this desk opted out of monitoring auto-recycle)"; exit 0 ;;
  status)
    a="$(arm_for "$PWD")"; c="$(cooldown_for "$PWD")"
    if [ -f "$KILL" ]; then echo "GLOBAL KILL active ($KILL) — no session recycles"; fi
    if [ -f "$a" ]; then echo "ARMED: $(cat "$a")"; else echo "not armed (this cwd)"; fi
    if [ -f "$c" ]; then
      cd_at="$(cat "$c" 2>/dev/null || echo 0)"; left=$(( COOLDOWN_S - ( $(date +%s) - ${cd_at:-0} ) ))
      [ "$left" -gt 0 ] 2>/dev/null && echo "cooldown: ${left}s remaining" || echo "cooldown: expired"
    fi
    exit 0 ;;
  kill)   mkdir -p "$STATE_DIR" 2>/dev/null; date -u +%Y-%m-%dT%H:%M:%SZ > "$KILL"; echo "GLOBAL KILL set → $KILL"; exit 0 ;;
  unkill) rm -f "$KILL" 2>/dev/null; echo "global kill removed"; exit 0 ;;
esac

# ---- PostToolUse actuation mode (no recognized arg; JSON on stdin) --------------------------------
input="$(cat 2>/dev/null || printf '{}')"

# ── B-3: one IDL line per invocation (fired|abstained). "didn't fire" ≠ "never evaluated". ──
log_idl() { # $1=disposition $2=reason $3=extra-json(optional, leading-comma-free)
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  printf '{"ts":"%s","hook":"waiting-recycle","sid":"%s","disposition":"%s","reason":"%s"%s}\n' \
    "$ts" "${SID:-?}" "$1" "$2" "${3:+,$3}" >> "$IDL" 2>/dev/null || true
}
abstain() { log_idl abstained "$1"; exit 0; }

command -v jq >/dev/null 2>&1 || { SID="?"; abstain "no-jq"; }

SID="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
TP="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
CWD="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
CMD="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"

[ -n "$SID" ] || abstain "no-session-id"

# 2. GLOBAL kill-switch — blanket opt-out for every session.
[ -f "$KILL" ] && abstain "global-kill"

# cwd is needed for the arm / cooldown / clean-tree checks — no cwd, nothing to reason about.
{ [ -n "$CWD" ] && [ -d "$CWD" ]; } || abstain "no-cwd"

# 1. OPT-IN: armed for this cwd? OFF by default ⇒ a builder is never recycled at 55%.
[ -f "$(arm_for "$CWD")" ] || abstain "not-armed"

# GUARD: never advise-recycle off the recycle/handoff machinery's OWN Bash calls (defense-in-depth;
# the cooldown set at fire-time also covers this, but an explicit guard removes any ordering risk).
case "$CMD" in
  *handoff-fire*|*/handoff*|*waiting-recycle*|*"self-close"*) abstain "recycle-machinery" ;;
esac

# 3. COOLDOWN (cwd-keyed): recently advised ⇒ quiet. Anti-thrash + cross-session loop-breaker.
cf="$(cooldown_for "$CWD")"
if [ -f "$cf" ]; then
  cd_at="$(cat "$cf" 2>/dev/null || echo 0)"; case "$cd_at" in ''|*[!0-9]*) cd_at=0 ;; esac
  [ "$(( $(date +%s) - cd_at ))" -lt "$COOLDOWN_S" ] && abstain "cooldown"
fi

# 6. Per-session hard CAP (backstop; a wedged session is never nagged past MAX).
capf="$(cap_for "$SID")"
N="$(cat "$capf" 2>/dev/null || echo 0)"; case "$N" in ''|*[!0-9]*) N=0 ;; esac
[ "$N" -ge "$MAX" ] && abstain "capped:${N}>=${MAX}"

# 4a. Context fill (telemetry) — fresh number only; an old % is not evidence of the current fill.
used=0; fresh=0
tel="$TEL_DIR/$SID.json"
if [ -f "$tel" ]; then
  ts="$(jq -r '.ts // 0' "$tel" 2>/dev/null || echo 0)"; ts="${ts%.*}"; case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
  age=$(( $(date +%s) - ts ))
  if [ "$age" -le "$AGE_MAX" ]; then
    fresh=1
    used="$(jq -r '.used_pct // 0' "$tel" 2>/dev/null || echo 0)"; used="${used%.*}"
    case "$used" in ''|*[!0-9]*) used=0 ;; esac
  fi
fi
over_threshold=0; { [ "$fresh" = 1 ] && [ "$used" -ge "$T" ]; } && over_threshold=1

# 4b. Behavioral ROT tell — the desk re-deriving already-known orchestration state (confusion /
# memory-loss markers a HEALTHY polling desk does not emit; NOT generic "let me check X"). Fires
# even below threshold. Read the LAST assistant text block (streaming tail — never slurp a big
# transcript). Corpus-validated in tests/waiting-recycle.bats.
rot=0; MSG=""
if [ -n "$TP" ]; then
  case "$TP" in "~"*) TP="$HOME${TP#\~}" ;; esac
  if [ -f "$TP" ]; then
    MSG="$(jq -c 'select(.type=="assistant")' "$TP" 2>/dev/null | tail -1 \
            | jq -r '[.message.content[]? | select(.type=="text") | .text] | join("\n")' 2>/dev/null || true)"
  fi
fi
# Bound grep input (a re-derivation tell is opening narration; this is a hang-safety backstop, not
# a correctness limit). Combined with the backtracking-SAFE regex below (≤1 bounded gap per branch,
# NO overlapping quantifiers — an earlier `[a-z]*[^.]{0,40}` form ReDoS-hung on near-miss inputs).
MSG="${MSG:0:4000}"
ROT_TELLS='(lost|losing) track|(remind|reorient|reacquaint) (myself|me)|(do(n.?t| not)|no longer|can.?t|cannot) (recall|remember)|(not sure|not certain|no longer sure|unsure)( any ?more|,? (which|what|where|how many|whether))|what was i (monitoring|watching|waiting|tracking|doing|supposed)|which (sessions?|ones?|teammates?|tasks?)[^.]{0,20}(did i|was i|were we|had i|do i)|(did|do) i (fire|launch|spawn|start|kick|have)[^.]{0,20}(again|already|so far)|(reconstruct|re-?establish|re-?derive|re-?orient|re-?build|re-?assemble)[^.]{0,15}(state|context|picture|status|situation|standing|where|what|which)|re-?(check|read|verify|confirm|examine|scan)[^.]{0,15}(which|what|the current|whether|where things|from scratch)|from scratch|starting over|(again|already),? (which|what|how many|who|whether)|(which|what|how many)[^.]{0,25}(again|already|so far)'
[ -n "$MSG" ] && printf '%s' "$MSG" | grep -iqE "$ROT_TELLS" && rot=1

# 4. TRIGGER gate — threshold OR FLOORED behavioral rot. A rot-tell needs FRESH telemetry AND
# used_pct ≥ ROT_FLOOR to count: rot physically requires accumulated context, and the shipped regex
# matches HEALTHY watch narration ("re-checking which sessions are still running") — an un-floored
# rot-tell at single-digit fill is by construction re-orientation narration, not rot (probe P1,
# 2026-07-19: the regex trips on 3/5 benign monitoring lines). The floor also closes the
# cross-generation rot-tell recycle-storm (a fresh successor's re-orientation narration can't re-fire
# below the floor). fresh=0 (telemetry writer dead) ⇒ rot cannot fire — FM-G is covered by a separate
# stale-telemetry alarm, not by firing blind on a lagging tell.
rot_valid=0; { [ "$rot" = 1 ] && [ "$fresh" = 1 ] && [ "$used" -ge "$ROT_FLOOR" ]; } && rot_valid=1
{ [ "$over_threshold" = 1 ] || [ "$rot_valid" = 1 ]; } || abstain "below-threshold-no-tell:used=${used},fresh=${fresh},rot=${rot},floor=${ROT_FLOOR}"

# 5. SAFE — genuinely just-WAITING, never mid-write-work or holding a decision.
# 5a. Clean tree: uncommitted changes = in-scope write work in hand ⇒ HOLD (never recycle over it).
if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ -z "$(git -C "$CWD" status --porcelain 2>/dev/null)" ] || abstain "dirty-tree-hold"
fi
# 5b. Open decision/blocker in the last message (reuse anti-deference's GENUINE carve-out): a desk
# waiting on the operator's call must SURFACE, not silently recycle the question away.
GENUINE='your (credential|password|api.?key|secret|token|login|cookie)|need (your|the)[^.]{0,40}(credential|password|secret|token|key|access|permission|approval)|only you (can|have|know)|(don.?t|do not|no) [a-z ]{0,20}access|which account|you.?ll need to (provide|give|share|tell|run|log ?in)|i (don.?t|do not) have (access|the |your |permission)|can you (provide|share|tell me|give me|confirm which)|which (do you|would you|of (these|the)|option|approach|one)|(would|do) you prefer|your call|up to you|how would you like|which direction|your approval|requires? (your|sudo|approval|authentication)|run (this|it|the [a-z ]{0,20}) ?yourself|sudo|interactive login|auth login|pushing to (main|origin)|push (is|remains)[^.]{0,20}your call|won.?t push|will not push|not push(ing)? (to|without)|force.?push|destructive migration|drop table|delete[^.]{0,20}production|navigation pattern|(db|database) timeout'
[ -n "$MSG" ] && printf '%s' "$MSG" | grep -iqE "$GENUINE" && abstain "open-decision-hold"

# ── FIRE: stamp cooldown (loop-breaker) + bump cap, log, advise the model to recycle NOW. ──
mkdir -p "$STATE_DIR" 2>/dev/null || true
date +%s > "$cf" 2>/dev/null || true
printf '%s' "$((N + 1))" > "$capf" 2>/dev/null || true
if [ "$over_threshold" = 1 ] && [ "$rot_valid" = 1 ]; then trig="context ${used}% ≥ ${T}% AND a state-rot tell"
elif [ "$over_threshold" = 1 ];                     then trig="context ${used}% ≥ ${T}%"
else                                                     trig="a floored state-rot tell (re-deriving known state, ${used}% ≥ ${ROT_FLOOR}% floor)"
fi
log_idl fired "waiting-recycle" "\"trigger\":\"$( [ "$over_threshold" = 1 ] && echo threshold || echo behavioral)\",\"used_pct\":${used},\"rot\":${rot_valid},\"count\":$((N+1)),\"max\":${MAX}"

adv="⟳ MONITORING AUTO-RECYCLE — you are at a quiet monitoring boundary (${trig}). A watching desk accrues low-value context that rots your recall of the load-bearing orchestration state. RECYCLE NOW via your existing self-recycle path: run /handoff — it captures the live state (fired sessions, pending pings, wave/merge state, decisions) into the payload and fires handoff-fire.sh --recycle so the SUCCESSOR PANE IS THE CONTINUATION and this bloated context is discarded. Do it as this turn's next action. IF instead you actually hold in-hand write-work or a genuine open decision (you should not — the tree is clean and no blocker was detected), do NOT recycle: surface it. Kill-switch: \`waiting-recycle.sh clear\` (this desk) / \`waiting-recycle.sh kill\` (global). (auto-recycle advisory $((N+1))/${MAX})"
# ── carry the mission/DoD line so a recycle never loses purpose (T-P4-4; empty = none recorded) ──
dod_carry="$("${DOD_PERSIST:-$(dirname "$0")/dod-persist.sh}" get 2>/dev/null || true)"
[ -n "$dod_carry" ] && adv="${adv}

⟳ MISSION TO CARRY: ${dod_carry} — restate this verbatim as the successor's \`Scope (frozen):\` line in your /handoff payload so the recycle keeps its purpose (never drop or narrow it)."
sysmsg="⟳ waiting-recycle: desk at a quiet boundary (${trig}) — advising /handoff self-recycle ($((N+1))/${MAX})."

jq -nc --arg a "$adv" --arg s "$sysmsg" \
  '{decision:"block", reason:$s, systemMessage:$s, hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$a}}'
exit 0
