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
#   the desk between polls, not only at a Stop it never hits.
#
# TWO-STAGE ACTUATION (Fable design panel 2026-07-19 — was advisory-ONLY, which fired 0/2419 in prod
# because the fire depended on the model NOTICING + complying):
#   STAGE 1 (advisory) — the FIRST fire-worthy poll ADVISES the model to run /handoff →
#     handoff-fire.sh --recycle (the model authors the richest payload) and starts a grace clock.
#   STAGE 2 (deterministic fire) — if the desk is STILL fire-worthy after GRACE_S (the model ignored
#     the advisory — i.e. it rotted past acting on it), the hook FIRES handoff-fire.sh --recycle
#     ITSELF with a composed brief (standing --brief template + frozen DoD + a re-derive-from-disk
#     directive; a MONITORING desk's watch-state is disk-reconstructible, so the successor is never
#     task-less). Stage 2 is cap+cooldown EXEMPT (bounded instead by a one-fire-per-SID latch — a
#     non-exempt Stage 2 would be silenced by the MAX-advisory cap: the panel's cap-trap).
#   SHADOW by default (arm) — Stage 2 LOGS a would-fire but does NOT exec until `arm --live`. Ships
#     the mechanism DAMPED so a gate bug cannot strand the fleet before the operator soaks the log.
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
#      in the last message that ALSO clears used_pct ≥ ROT_FLOOR on FRESH telemetry (an un-floored tell
#      false-positives on healthy watch narration — probe P1 2026-07-19; a floored tell can fire below T).
#   5. SAFE — genuinely just-WAITING, never mid-work / mid-merge / mid-coordination:
#        5a clean git tree AND no sequencer state (MERGE_HEAD/rebase/cherry-pick — S1);
#        5b no open decision/blocker in the last message (anti-deference's GENUINE carve-out);
#        5c no active COORDINATION — no peer contract-BLOCKED on this desk (S3, waiter-liveness-filtered),
#           no fresh inbound mailbox line (S4, load-bearing: dispatch workers notify without a contract),
#           no live context-bound teammate (S5, HARD hold: results route to the dying SID). Any ⇒ HOLD.
#      The desk's OWN waiter-contracts do NOT hold — durable on disk, the successor resumes them.
#   6. Under the per-session advisory CAP (Stage 1 only; Stage 2 is cap-exempt, latch-bounded).
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
# Agent/operator CLI (extended): arm [--brief <file>] [--live]  — --brief seeds the Stage-2 successor
#   prompt; --live enables the Stage-2 EXEC (requires a non-empty --brief; default is SHADOW/log-only).
#
# Env seams (tests): CC_WR_T · CC_TELEMETRY_DIR · CC_WR_AGE_MAX · CC_WR_IDL · CC_WR_STATE_DIR ·
#                    CC_WR_MAX · CC_WR_COOLDOWN_S · CC_WR_KILL · CC_WR_ROT_FLOOR · CC_WR_GRACE_S ·
#                    CC_WR_COORD_DIR · CC_WR_UUID · CC_WR_QUIET_S · CC_WR_FIRE_DIR · CC_WR_HANDOFF_FIRE
#
# NOTE: deliberately NO `set -e` — a hook must fail SAFE (abstain), and a stray non-zero from a grep
# test must never become the script's exit code and suppress a legitimate abstain-log. -u/pipefail are
# on for hygiene; every path ends `exit 0`.
set -uo pipefail

T="${CC_WR_T:-55}"                                          # moderate fire threshold, used_pct
ROT_FLOOR="${CC_WR_ROT_FLOOR:-25}"                          # rot-tell needs THIS much fill to be real
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
# Stage-2 deterministic-fire state (Fable panel 2026-07-19):
escalate_for() { printf '%s/escalate-%s' "$STATE_DIR" "$1"; }              # SID-keyed: first-advisory time (grace clock)
fired_for()    { printf '%s/fired-%s'    "$STATE_DIR" "$1"; }              # SID-keyed: one-fire-per-SID latch (Stage-2 bound)
live_for()     { printf '%s/live-%s'     "$STATE_DIR" "$(key_cwd "$1")"; } # cwd-keyed: live-fire opt-in (else SHADOW/log-only)
brief_for()    { printf '%s/brief-%s'    "$STATE_DIR" "$(key_cwd "$1")"; } # cwd-keyed: standing successor-brief template

GRACE_S="${CC_WR_GRACE_S:-180}"                            # Stage-1 advisory → Stage-2 fire grace
# actuator (test seam): resolve next to this hook (repo hooks/../scripts + symlinked ~/.claude install)
_wrd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
HANDOFF_FIRE="${CC_WR_HANDOFF_FIRE:-$_wrd/../scripts/handoff-fire.sh}"
[ -f "$HANDOFF_FIRE" ] || HANDOFF_FIRE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/handoff-fire.sh"

# ---- Agent/operator CLI mode ---------------------------------------------------------------------
case "${1:-}" in
  arm)
    mkdir -p "$STATE_DIR" 2>/dev/null
    shift; _brief="" _live=0
    while [ $# -gt 0 ]; do case "$1" in
      --brief) _brief="${2:?--brief needs a file}"; shift 2 ;;
      --live)  _live=1; shift ;;
      *) echo "!! unknown arm arg: $1 (use: arm [--brief <file>] [--live])" >&2; exit 2 ;;
    esac; done
    f="$(arm_for "$PWD")"; was_armed=0; [ -f "$f" ] && was_armed=1
    printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ) $PWD" > "$f"
    # brief template = the Stage-2 successor prompt seed; hard-required for LIVE (no empty-payload fire, FM-D)
    if [ -n "$_brief" ]; then
      { [ -f "$_brief" ] && [ -s "$_brief" ]; } || { echo "!! --brief file missing/empty: $_brief" >&2; exit 2; }
      cp "$_brief" "$(brief_for "$PWD")" 2>/dev/null
    fi
    if [ "$_live" = 1 ]; then
      [ -s "$(brief_for "$PWD")" ] || { echo "!! --live requires a non-empty --brief template first (no empty-payload fire)" >&2; exit 2; }
      : > "$(live_for "$PWD")"; mode="LIVE (deterministic recycle EXECS handoff-fire --recycle)"
    else
      rm -f "$(live_for "$PWD")" 2>/dev/null; mode="SHADOW (deterministic recycle LOGS would-fire, does NOT exec)"
    fi
    # A fresh opt-in clears a stale cooldown; a RE-ARM of an already-armed desk does NOT — re-arming
    # would clear the cross-generation loop-breaker (panel landmine). Arm survives the in-place recycle,
    # so a SUCCESSOR must NEVER re-arm.
    [ "$was_armed" = 0 ] && rm -f "$(cooldown_for "$PWD")" 2>/dev/null
    echo "armed $mode → $f"; exit 0 ;;
  clear)
    rm -f "$(arm_for "$PWD")" "$(cooldown_for "$PWD")" "$(live_for "$PWD")" "$(brief_for "$PWD")" 2>/dev/null
    echo "cleared (this desk opted out of monitoring auto-recycle)"; exit 0 ;;
  status)
    a="$(arm_for "$PWD")"; c="$(cooldown_for "$PWD")"
    if [ -f "$KILL" ]; then echo "GLOBAL KILL active ($KILL) — no session recycles"; fi
    if [ -f "$a" ]; then
      echo "ARMED: $(cat "$a")"
      [ -f "$(live_for "$PWD")" ] && echo "  mode: LIVE (Stage-2 execs)" || echo "  mode: SHADOW (Stage-2 logs would-fire only)"
      [ -s "$(brief_for "$PWD")" ] && echo "  brief: $(brief_for "$PWD") ($(wc -l < "$(brief_for "$PWD")" | tr -d ' ') lines)" || echo "  brief: none (LIVE blocked until set)"
    else echo "not armed (this cwd)"; fi
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

# 3. COOLDOWN (cwd-keyed) + 6. CAP (SID-keyed) pace the ADVISORY (Stage 1) ONLY. The deterministic
# FIRE (Stage 2) is EXEMPT from both: it must escalate after grace even though the first advisory
# stamped the cooldown, and a non-exempt Stage 2 would be permanently silenced after MAX ignored
# advisories (the panel's cap-trap). So compute them as FLAGS; apply them only on the Stage-1 branch.
cf="$(cooldown_for "$CWD")"; cooled=0
if [ -f "$cf" ]; then
  cd_at="$(cat "$cf" 2>/dev/null || echo 0)"; case "$cd_at" in ''|*[!0-9]*) cd_at=0 ;; esac
  [ "$(( $(date +%s) - cd_at ))" -lt "$COOLDOWN_S" ] && cooled=1
fi
capf="$(cap_for "$SID")"
N="$(cat "$capf" 2>/dev/null || echo 0)"; case "$N" in ''|*[!0-9]*) N=0 ;; esac
capped=0; [ "$N" -ge "$MAX" ] && capped=1

# Stage-2 PENDING? (cheap; decides whether the expensive trigger+SAFE eval must run even when
# cooled/capped): a prior advisory left an escalate stamp, grace has elapsed, and this SID has not
# yet fired. If Stage-2 is NOT pending and the advisory is cooled/capped, nothing to do → abstain
# early (preserves the pre-restructure perf and the "cooldown"/"capped" abstain reasons).
escf="$(escalate_for "$SID")"; firedf="$(fired_for "$SID")"; stage2_pending=0
if [ -f "$escf" ] && [ ! -f "$firedf" ]; then
  est="$(cat "$escf" 2>/dev/null)"; case "$est" in ''|*[!0-9]*) est=0 ;; esac
  [ "$est" -gt 0 ] && [ "$(( $(date +%s) - est ))" -ge "$GRACE_S" ] && stage2_pending=1
fi
if [ "$stage2_pending" = 0 ]; then
  [ "$cooled" = 1 ] && abstain "cooldown"
  [ "$capped" = 1 ] && abstain "capped:${N}>=${MAX}"
fi

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

# 5. SAFE — genuinely just-WAITING, never mid-write-work, mid-merge, mid-coordination, or holding
# a decision. Every clause below is FALSE-NEGATIVE-safe: an unreadable/ambiguous signal HOLDS (a
# missed recycle just waits for the next poll; a wrong recycle strands the fleet).
# 5a. Clean tree + no git SEQUENCER state: uncommitted changes = in-scope work in hand ⇒ HOLD; a live
# merge/rebase/cherry-pick is porcelain-CLEAN at step boundaries yet mid-active-work (the audit's
# "mid-merge between clean states", Fable panel S1) ⇒ HOLD on the sequencer files.
if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ -z "$(git -C "$CWD" status --porcelain 2>/dev/null)" ] || abstain "dirty-tree-hold"
  gd="$(git -C "$CWD" rev-parse --git-dir 2>/dev/null)"
  if [ -n "$gd" ]; then
    case "$gd" in /*) ;; *) gd="$CWD/$gd" ;; esac
    for seq in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
      [ -e "$gd/$seq" ] && abstain "sequencer-state-hold:$seq"
    done
  fi
fi
# 5b. Open decision/blocker in the last message (reuse anti-deference's GENUINE carve-out): a desk
# waiting on the operator's call must SURFACE, not silently recycle the question away.
GENUINE='your (credential|password|api.?key|secret|token|login|cookie)|need (your|the)[^.]{0,40}(credential|password|secret|token|key|access|permission|approval)|only you (can|have|know)|(don.?t|do not|no) [a-z ]{0,20}access|which account|you.?ll need to (provide|give|share|tell|run|log ?in)|i (don.?t|do not) have (access|the |your |permission)|can you (provide|share|tell me|give me|confirm which)|which (do you|would you|of (these|the)|option|approach|one)|(would|do) you prefer|your call|up to you|how would you like|which direction|your approval|requires? (your|sudo|approval|authentication)|run (this|it|the [a-z ]{0,20}) ?yourself|sudo|interactive login|auth login|pushing to (main|origin)|push (is|remains)[^.]{0,20}your call|won.?t push|will not push|not push(ing)? (to|without)|force.?push|destructive migration|drop table|delete[^.]{0,20}production|navigation pattern|(db|database) timeout'
[ -n "$MSG" ] && printf '%s' "$MSG" | grep -iqE "$GENUINE" && abstain "open-decision-hold"

# 5c. Active-COORDINATION holds (Fable panel 2026-07-19 S3/S4/S5). A monitoring desk can be clean-tree
# yet mid-coordination; a recycle would strand state that lives ONLY in this SID's context. The desk's
# OWN waiter-contracts do NOT hold (durable on disk, the successor resumes them) — only a peer BLOCKED
# ON this desk, an unprocessed inbound ping, or a live teammate do. Roots are seam-overridable for tests.
COORD="${CC_WR_COORD_DIR:-$HOME/.claude}"                    # root of wait-contracts/ mailbox/ cc-roles/
UUID="${CC_WR_UUID:-${ITERM_SESSION_ID##*:}}"               # this desk's iTerm pane uuid (survives recycle)
QUIET_S="${CC_WR_QUIET_S:-180}"                             # S4: a mailbox line fresher than this = active
now_s="$(date +%s)"
# identity set a peer addresses THIS desk by: session_id, pane uuid, or a role file resolving to either.
ident_is_me() { # $1=addressee → 0 if it names this desk
  local w="$1"; [ -n "$w" ] || return 1
  { [ "$w" = "$SID" ] || { [ -n "$UUID" ] && [ "$w" = "$UUID" ]; }; } && return 0
  if [ -f "$COORD/cc-roles/$w" ]; then
    local rv; rv="$(cat "$COORD/cc-roles/$w" 2>/dev/null)"
    { [ "$rv" = "$SID" ] || { [ -n "$UUID" ] && [ "$rv" = "$UUID" ]; }; } && return 0
  fi
  return 1
}
# S5 — live context-bound TEAMMATES (HARD HOLD — teammate/TaskOutput results route to THIS SID; a
# recycle or /compact kills them unrecoverably). Signal: a team dir created BY this session. Conservative
# (existence ⇒ HOLD): a lingering post-teardown dir over-holds, which is FALSE-NEGATIVE-safe and visible
# in the shadow log for teardown-hygiene follow-up.
for td in "$CFG"/teams/session-"${SID:0:8}"*; do
  { [ -d "$td" ] && [ -f "$td/config.json" ]; } && abstain "live-team-hold"
done
# S3 — a peer is contract-BLOCKED on this desk: OPEN wait-contract, waitee names me, deadline future,
# waiter still ALIVE (a dead waiter's OPEN contract is a zombie — kill -0 filters it, panel S3).
if [ -d "$COORD/wait-contracts" ]; then
  for wc in "$COORD"/wait-contracts/*.json; do
    [ -f "$wc" ] || continue
    [ "$(jq -r '.status // empty' "$wc" 2>/dev/null)" = "OPEN" ] || continue
    ident_is_me "$(jq -r '.waitee // empty' "$wc" 2>/dev/null)" || continue
    dl="$(jq -r '.deadline // 0' "$wc" 2>/dev/null)"; case "$dl" in ''|*[!0-9]*) dl=0 ;; esac
    [ "$dl" -gt "$now_s" ] || continue                        # past deadline ⇒ not a live block
    wp="$(jq -r '.waiter_pid // empty' "$wc" 2>/dev/null)"
    { [ -n "$wp" ] && ! kill -0 "$wp" 2>/dev/null; } && continue   # dead waiter ⇒ zombie, skip
    abstain "inbound-wait-hold"
  done
fi
# S4 — a peer just reached for this desk (mailbox line fresher than QUIET_S). cc-notify ALWAYS
# mailbox-writes before injecting, and cc-dispatch workers notify the desk ROLE without a contract,
# so S3 alone under-detects — S4 is load-bearing. Check the own-uuid mailbox + any role resolving to me.
mbx_active() { # $1=mailbox file → 0 if touched within QUIET_S
  [ -f "$1" ] || return 1
  local mt; mt="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0)"
  case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
  [ "$(( now_s - mt ))" -lt "$QUIET_S" ]
}
{ [ -n "$UUID" ] && mbx_active "$COORD/mailbox/$UUID.md"; } && abstain "inbox-active-hold"
if [ -d "$COORD/cc-roles" ]; then
  for rf in "$COORD"/cc-roles/*; do
    [ -f "$rf" ] || continue
    rv="$(cat "$rf" 2>/dev/null)"
    { [ "$rv" = "$SID" ] || { [ -n "$UUID" ] && [ "$rv" = "$UUID" ]; }; } || continue
    mbx_active "$COORD/mailbox/$rv.md" && abstain "inbox-active-hold-role"
  done
fi

# ── FIRE-worthy: trigger AND safe. Stage 2 (deterministic fire) if the grace since the first advisory
#    has elapsed; else Stage 1 (advisory). ──────────────────────────────────────────────────────────
mkdir -p "$STATE_DIR" 2>/dev/null || true
if [ "$over_threshold" = 1 ] && [ "$rot_valid" = 1 ]; then trig="context ${used}% ≥ ${T}% AND a state-rot tell"
elif [ "$over_threshold" = 1 ];                     then trig="context ${used}% ≥ ${T}%"
else                                                     trig="a floored state-rot tell (re-deriving known state, ${used}% ≥ ${ROT_FLOOR}% floor)"
fi
dod_carry="$("${DOD_PERSIST:-$(dirname "$0")/dod-persist.sh}" get 2>/dev/null || true)"

# Already escalated to a fire for THIS SID? one-fire-per-SID latch. A LIVE fire recycles to a new SID
# (so this only re-hits in SHADOW, where it correctly goes quiet after logging one would-fire);
# prevents advisory-spam after the escalation. Placed before Stage 2 so a re-poll never double-fires.
{ [ "$stage2_pending" = 0 ] && [ -f "$firedf" ]; } && abstain "already-fired"

# ════ STAGE 2 — deterministic FIRE (cooldown+cap EXEMPT; bound = one-fire-per-SID latch) ════
if [ "$stage2_pending" = 1 ]; then
  : > "$firedf" 2>/dev/null                                   # latch FIRST — at-most-once per SID even on re-entry
  # Compose the successor brief ATOMICALLY (tmp+mv). NEVER empty/partial → no task-less successor (FM-D):
  #   standing --brief template (if armed) + frozen DoD + a re-derive-from-disk directive.
  FIRE_DIR="${CC_WR_FIRE_DIR:-/tmp}"; pf="$FIRE_DIR/wr-fire-${SID}.txt"; tmpf="$pf.$$"
  {
    if [ -s "$(brief_for "$CWD")" ]; then cat "$(brief_for "$CWD")"
    else printf '%s\n' "You are the monitoring DESK, resumed by a deterministic self-recycle (predecessor context was ${used}% full and has been discarded to stop context rot)."; fi
    [ -n "$dod_carry" ] && printf '\nScope (frozen): %s\n' "$dod_carry"
    printf '\nFIRST ACTION — re-derive live watch state from DISK (the predecessor context is GONE; do not assume): run cc-board for the fleet roster; read the live-session registry, ~/.claude/wait-contracts (owned waits), and your role mailbox; scan worktrees + git for wave/merge state. Then resume monitoring. Do NOT re-arm waiting-recycle (the arm survives the recycle; re-arming clears the loop-breaker).\n'
  } > "$tmpf" 2>/dev/null
  if [ -s "$tmpf" ]; then mv -f "$tmpf" "$pf" 2>/dev/null; else rm -f "$tmpf" 2>/dev/null; fi
  if [ ! -s "$pf" ]; then log_idl abstained "fire-compose-empty" "\"used_pct\":${used}"; exit 0; fi
  tk="$( [ "$over_threshold" = 1 ] && echo threshold || echo behavioral )"
  if [ -f "$(live_for "$CWD")" ]; then
    date +%s > "$cf" 2>/dev/null || true                      # anchor the cross-generation loop-breaker on the FIRE
    log_idl fired "stage2-live" "\"used_pct\":${used},\"trigger\":\"${tk}\",\"prompt_file\":\"${pf}\",\"grace_s\":${GRACE_S}"
    # Sanctioned actuator: it arms a DETACHED watcher BEFORE typing /exit (order load-bearing), so the
    # recycle completes even when the /exit interrupt SIGKILLs this hook's process group.
    "$HANDOFF_FIRE" --recycle --prompt-file "$pf" ${UUID:+--session-id "$UUID"} </dev/null >/dev/null 2>&1 || true
    fmsg="⟳ DETERMINISTIC RECYCLE FIRED (${trig}) — the desk did not self-recycle within the ${GRACE_S}s grace, so waiting-recycle fired handoff-fire.sh --recycle. The successor is launching in this pane with the frozen DoD + a re-derive-from-disk brief. Do NOT run handoff-fire yourself."
    jq -nc --arg r "$fmsg" '{decision:"block",reason:$r,systemMessage:$r,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$r}}'
    exit 0
  fi
  # SHADOW (default): everything a live fire does EXCEPT the exec — ships the mechanism DAMPED so a gate
  # bug cannot strand the fleet before the operator reviews the shadow log and arms --live (damp-first).
  log_idl fired "stage2-shadow" "\"used_pct\":${used},\"would_fire\":true,\"trigger\":\"${tk}\",\"prompt_file\":\"${pf}\",\"grace_s\":${GRACE_S}"
  smsg="⟳ RECYCLE WOULD FIRE — SHADOW (${trig}). The desk did not self-recycle within ${GRACE_S}s. waiting-recycle is armed SHADOW: it composed the successor brief at ${pf} and logged a would-fire, but did NOT exec (no fleet-stranding risk while soaking). You SHOULD still self-recycle now: run /handoff. To enable the exec after review: waiting-recycle.sh arm --brief <file> --live. Kill-switch: waiting-recycle.sh clear."
  jq -nc --arg a "$smsg" --arg s "$smsg" '{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'
  exit 0
fi

# ════ STAGE 1 — advisory (cooldown + cap already cleared above for this branch) ════
date +%s > "$cf" 2>/dev/null || true                         # stamp cooldown (anti-thrash + loop-breaker)
printf '%s' "$((N + 1))" > "$capf" 2>/dev/null || true       # bump advisory cap
[ -f "$escf" ] || date +%s > "$escf" 2>/dev/null || true     # set the Stage-2 grace clock on the FIRST advisory
log_idl fired "waiting-recycle" "\"trigger\":\"$( [ "$over_threshold" = 1 ] && echo threshold || echo behavioral)\",\"used_pct\":${used},\"rot\":${rot_valid},\"count\":$((N+1)),\"max\":${MAX}"

adv="⟳ MONITORING AUTO-RECYCLE — you are at a quiet monitoring boundary (${trig}). A watching desk accrues low-value context that rots your recall of the load-bearing orchestration state. RECYCLE NOW via your existing self-recycle path: run /handoff — it captures the live state (fired sessions, pending pings, wave/merge state, decisions) into the payload and fires handoff-fire.sh --recycle so the SUCCESSOR PANE IS THE CONTINUATION and this bloated context is discarded. Do it as this turn's next action. IF instead you actually hold in-hand write-work or a genuine open decision (you should not — the tree is clean and no blocker was detected), do NOT recycle: surface it. If you ignore this, the deterministic fire escalates in ${GRACE_S}s. Kill-switch: \`waiting-recycle.sh clear\` (this desk) / \`waiting-recycle.sh kill\` (global). (auto-recycle advisory $((N+1))/${MAX})"
# ── carry the mission/DoD line so a recycle never loses purpose (T-P4-4; empty = none recorded) ──
[ -n "$dod_carry" ] && adv="${adv}

⟳ MISSION TO CARRY: ${dod_carry} — restate this verbatim as the successor's \`Scope (frozen):\` line in your /handoff payload so the recycle keeps its purpose (never drop or narrow it)."
sysmsg="⟳ waiting-recycle: desk at a quiet boundary (${trig}) — advising /handoff self-recycle ($((N+1))/${MAX}); deterministic fire in ${GRACE_S}s if ignored."

jq -nc --arg a "$adv" --arg s "$sysmsg" \
  '{decision:"block", reason:$s, systemMessage:$s, hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$a}}'
exit 0
