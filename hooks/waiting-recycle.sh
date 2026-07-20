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
#   1. ARMED — the desk opted in via `waiting-recycle.sh arm` (sentinel keyed by cwd, survives a
#      recycle) OR it HOLDS the monitoring-desk role (cc-roles/<desk> resolves to this pane's uuid/sid
#      ⇒ ARM-BY-DEFAULT, G-P11-7): deterministic arming kills the "arm step is itself model-diligence"
#      root (0/2419 prod fires decomposed as 1977 not-armed). A builder (no arm sentinel, not the desk
#      role) is still never touched. Role-arm defaults to SHADOW (the live_for sentinel still gates the
#      exec — damp-first). Kill-switch: `clear` (per-desk, writes a durable disarm marker that also
#      suppresses arm-by-default) / `kill` (global). An explicit `arm` removes a prior disarm.
#   2. NOT globally killed — the blanket opt-out file ($CC_WR_KILL) is absent.
#   3. NOT in cooldown — no advisory for this cwd within COOLDOWN_S. This is the anti-thrash pacer AND
#      the cross-session LOOP-BREAKER: a fresh recycled desk (same cwd) sees the predecessor's cooldown
#      stamp and stays quiet, so recycle→fresh→recycle can't spin.
#   4. TRIGGER — context used_pct ≥ eff_idle (the ADAPTIVE idle threshold: base T_IDLE=35, decaying toward
#      T_IDLE_FLOOR=25 the longer this SID sits idle below it — proactive; recycling an IDLE desk is a FREE
#      WIN, no work in hand to lose, so we don't wait for 55%), OR a behavioral ROT tell in the last message
#      that ALSO clears used_pct ≥ ROT_FLOOR on FRESH telemetry (an un-floored tell false-positives on
#      healthy watch narration — probe P1 2026-07-19; a floored tell can fire below the threshold).
#   5. SAFE vs BUSY — the desk is CLASSIFIED, not just gated. SAFE (idle, just-waiting) ⇒ recycle. BUSY
#      holds are split soft/hard (see §7): 5a clean git tree (dirty=SOFT) + no sequencer state (MERGE_HEAD/
#      rebase/cherry-pick=HARD, S1); 5b no open decision (HARD — anti-deference's GENUINE carve-out); 5c no
#      active COORDINATION — a peer contract-BLOCKED on this desk (S3, SOFT), a fresh inbound mailbox line
#      (S4, SOFT — dispatch workers notify without a contract), a live context-bound teammate (S5, HARD:
#      results route to the dying SID). The desk's OWN waiter-contracts do NOT hold (durable on disk).
#   6. Under the per-session advisory CAP (Stage 1 only; Stage 2 is cap-exempt, latch-bounded). WEDGE
#      ESCALATION (T-P1-8): a fire-worthy-and-just-waiting desk that has exhausted its recycle attempts
#      (advisory CAP reached, or a SHADOW would-fire already latched) does NOT silently ride to the 90%
#      auto-compact wall — it PAGES the operator out-of-band (osascript + push-critical + an `escalated`
#      IDL record + a decision:block advisory), page-once per ESCALATE_DEDUP_S. Paging is fleet-safe, so
#      the escalation ships LIVE (unlike the Stage-2 exec, which stays SHADOW until armed --live).
#   7. TIERED CONTEXT-REFRESH (operator 2026-07-19, cc-backlog 4ce6ffc0194f) — once fire-worthy, route on
#      desk STATE (the evidence: a desk sat low-context for hours then hit 74% MID-work, an awkward recycle):
#        • IDLE (SAFE)                       → recycle at the lowered ADAPTIVE T_IDLE (§4). Tiers 1–2.
#        • BUSY soft + HIGH ctx (≥ T_BUSY=75)→ FORCE-recycle, DRAINING the pending pings (mailbox + inbound
#          wait-contracts) into the successor brief so NONE are dropped (Tier 3). SHADOW-default: composes
#          the drained brief + PAGES (fleet-safe, ships LIVE); the EXEC is opt-in beyond --live (--busy-force).
#        • BUSY hard + HIGH ctx              → PAGE (a sequencer/teammate/open-decision recycle would lose
#          state or bury a decision — surface, never force).
#        • BUSY + medium/low                 → Tier 2: mark a refresh-queued intent + hold; the lowered idle
#          threshold fires it at the next idle gap (context grows monotonically, so it converges there).
#      All new aggressiveness is advisory or SHADOW+page by default — nothing auto-execs until armed
#      (idle: --live; busy: --live --busy-force). Damp-first, unchanged from the Stage-2 discipline.
#
# Delivery: {decision:"block"} + hookSpecificOutput.additionalContext (the MODEL-facing recycle
# advisory — confirmed delivered on PostToolUse @ 2.1.183) + systemMessage/reason (operator-facing).
# The tool has ALREADY run at PostToolUse, so a fire can NEVER break the recycle machinery it triggers
# (unlike a PreToolUse deny). Exit 0 ALWAYS — a PostToolUse hook must never cost a session.
#
# Agent/operator CLI (run from the desk's worktree):
#   waiting-recycle.sh arm      # opt IN this desk (keyed by cwd) — also removes a prior `clear` disarm
#   waiting-recycle.sh clear    # opt OUT this desk (per-desk kill-switch: writes a durable disarm marker
#                               #   that ALSO suppresses arm-by-default) + reset its cooldown/cap
#   waiting-recycle.sh status   # inspect this desk's arm/disarm/cooldown/cap + global kill state
#   waiting-recycle.sh kill      # GLOBAL blanket off (all sessions)
#   waiting-recycle.sh unkill    # remove the global kill-switch
# Claude Code calls it with NO args + the PostToolUse JSON on stdin → actuation mode.
#
# Agent/operator CLI (extended): arm [--brief <file>] [--live] [--busy-force]  — --brief seeds the Stage-2
#   successor prompt; --live enables the idle Stage-2 EXEC (requires a non-empty --brief; default SHADOW);
#   --busy-force ALSO enables the Tier-3 BUSY+HIGH mid-work forced-recycle EXEC (requires --live).
#
# Env seams (tests): CC_WR_T (alias→T_IDLE) · CC_WR_T_IDLE · CC_WR_T_BUSY · CC_WR_T_IDLE_FLOOR ·
#                    CC_WR_IDLE_DECAY_S · CC_WR_BUSY_FORCE · CC_TELEMETRY_DIR · CC_WR_AGE_MAX · CC_WR_IDL ·
#                    CC_WR_STATE_DIR · CC_WR_MAX · CC_WR_COOLDOWN_S · CC_WR_KILL · CC_WR_ROT_FLOOR ·
#                    CC_WR_GRACE_S · CC_WR_COORD_DIR · CC_WR_UUID · CC_WR_QUIET_S · CC_WR_FIRE_DIR ·
#                    CC_WR_HANDOFF_FIRE · CC_WR_DESK_ROLE · CC_WR_NOTIFY · CC_WR_PUSH · CC_WR_ESCALATE_DEDUP_S
#
# NOTE: deliberately NO `set -e` — a hook must fail SAFE (abstain), and a stray non-zero from a grep
# test must never become the script's exit code and suppress a legitimate abstain-log. -u/pipefail are
# on for hygiene; every path ends `exit 0`.
set -uo pipefail

# ── TIERED CONTEXT THRESHOLDS (operator 2026-07-19, cc-backlog 4ce6ffc0194f) ──────────────────────
# A monitoring desk fills with low-value watch noise; recycling at an IDLE (just-waiting) boundary is
# a FREE WIN — no work in hand to lose (state is disk-reconstructible), and it sheds the rot BEFORE it
# reaches the awkward busy-and-high case (the evidence: a desk sat low-context for hours, then hit 74%
# MID-conversation). So the single 55% gate is split into two state-keyed thresholds:
#   • IDLE (SAFE gate passes — just waiting)  → recycle at the LOWER, ADAPTIVE T_IDLE (proactive).
#   • BUSY (SAFE gate fails — mid-work/coord) → hold as before UNTIL context reaches the HIGH T_BUSY,
#     where a forced path drains the pending pings into the successor brief (never a silent ride to the
#     90% auto-compact wall). See the decision-routing block below.
# CC_WR_T stays a back-compat alias: if set, it seeds T_IDLE (old callers pinning 55 keep a 55 idle bar).
T_IDLE="${CC_WR_T_IDLE:-${CC_WR_T:-35}}"                     # IDLE recycle threshold (was 55; lowered — proactive)
T_BUSY="${CC_WR_T_BUSY:-75}"                                 # BUSY forced-recycle threshold (Tier 3; just above the observed-awkward 74%)
T_IDLE_FLOOR="${CC_WR_T_IDLE_FLOOR:-25}"                     # adaptive decay floor (== ROT_FLOOR: the two triggers converge here)
IDLE_DECAY_S="${CC_WR_IDLE_DECAY_S:-3600}"                   # T_IDLE decays to the floor over THIS long-idle window (0 ⇒ no decay)
ROT_FLOOR="${CC_WR_ROT_FLOOR:-25}"                          # rot-tell needs THIS much fill to be real
AGE_MAX="${CC_WR_AGE_MAX:-180}"                             # telemetry older than this can't be trusted
MAX="${CC_WR_MAX:-3}"                                       # per-session advisory cap (never nag forever)
COOLDOWN_S="${CC_WR_COOLDOWN_S:-600}"                       # cwd-keyed anti-thrash + cross-session loop-breaker
TEL_DIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"            # shared with boundary-handoff / statusline
IDL="${CC_WR_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
STATE_DIR="${CC_WR_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/waiting-recycle}"
KILL="${CC_WR_KILL:-$STATE_DIR/OFF}"                        # global blanket kill-switch
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DESK_ROLE="${CC_WR_DESK_ROLE:-desk}"                       # G-P11-7: role a monitoring desk holds → arm-by-default
NOTIFY_CMD="${CC_WR_NOTIFY:-}"                              # T-P1-8: empty → builtin osascript operator page
PUSH_BIN="${CC_WR_PUSH:-$CFG/hooks/push-critical.sh}"      # T-P1-8: Pushover break-through (INERT unless armed)
ESCALATE_DEDUP_S="${CC_WR_ESCALATE_DEDUP_S:-900}"          # T-P1-8: page-once cadence while a desk stays wedged

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
disarm_for()   { printf '%s/disarm-%s'   "$STATE_DIR" "$(key_cwd "$1")"; } # cwd-keyed: per-desk opt-out (suppresses arm-by-default, G-P11-7)
escalated_for(){ printf '%s/escalated-%s' "$STATE_DIR" "$1"; }             # SID-keyed: T-P1-8 wedge page-once pacer
# Tiered-refresh state (4ce6ffc0194f, 2026-07-19):
idlewatch_for(){ printf '%s/idlewatch-%s' "$STATE_DIR" "$1"; }             # SID-keyed: first sub-T_IDLE fresh poll (adaptive-decay clock)
queued_for()   { printf '%s/queued-%s'    "$STATE_DIR" "$1"; }             # SID-keyed: Tier-2 refresh-queued marker (busy@medium wants a refresh)
busyforce_for(){ printf '%s/busyforce-%s' "$STATE_DIR" "$(key_cwd "$1")"; } # cwd-keyed: Tier-3 forced-recycle EXEC opt-in (beyond --live; default OFF ⇒ shadow+page)

GRACE_S="${CC_WR_GRACE_S:-180}"                            # Stage-1 advisory → Stage-2 fire grace
# actuator (test seam): resolve next to this hook (repo hooks/../scripts + symlinked ~/.claude install)
_wrd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
HANDOFF_FIRE="${CC_WR_HANDOFF_FIRE:-$_wrd/../scripts/handoff-fire.sh}"
[ -f "$HANDOFF_FIRE" ] || HANDOFF_FIRE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/handoff-fire.sh"

# ---- Agent/operator CLI mode ---------------------------------------------------------------------
case "${1:-}" in
  arm)
    mkdir -p "$STATE_DIR" 2>/dev/null
    shift; _brief="" _live=0 _busyforce=0
    while [ $# -gt 0 ]; do case "$1" in
      --brief)      _brief="${2:?--brief needs a file}"; shift 2 ;;
      --live)       _live=1; shift ;;
      --busy-force) _busyforce=1; shift ;;
      *) echo "!! unknown arm arg: $1 (use: arm [--brief <file>] [--live] [--busy-force])" >&2; exit 2 ;;
    esac; done
    f="$(arm_for "$PWD")"; was_armed=0; [ -f "$f" ] && was_armed=1
    # ── FAIL-ATOMIC VALIDATION (durability, 2026-07-20) ────────────────────────────────────────────
    # Every refusal condition is checked BEFORE any marker is written, so a REFUSED arm changes
    # NOTHING on disk. The prior order wrote the arm sentinel first and only THEN refused `--live`
    # for a missing brief — exit 2, but the desk was left HALF-ARMED: `arm-<key>` present with
    # `live-<key>`/`brief-<key>` absent, i.e. armed-and-SHADOW *forever*. That state reads as "armed"
    # to `status` and to the hook's own opt-in gate, yet Stage 2 can never exec. Observed live under
    # .claude-quaternary (arm- written 01:03, no live-/brief-) — the desk polled for hours, passed the
    # arm gate, and shadow-logged instead of recycling. A half-success is the worst outcome for a
    # go-live actuator: it looks armed and is inert. Refuse whole, or apply whole.
    if [ -n "$_brief" ]; then
      { [ -f "$_brief" ] && [ -s "$_brief" ]; } || { echo "!! --brief file missing/empty: $_brief" >&2; exit 2; }
    fi
    if [ "$_live" = 1 ]; then
      # A usable brief must come from THIS invocation or from a prior arm of this cwd — checked here,
      # against the not-yet-written state, so the refusal leaves the previous state intact.
      { [ -n "$_brief" ] || [ -s "$(brief_for "$PWD")" ]; } || { echo "!! --live requires a non-empty --brief template first (no empty-payload fire)" >&2; exit 2; }
    fi
    # --busy-force: opt IN to the Tier-3 mid-work forced-recycle EXEC (beyond --live — a mid-work recycle is
    # riskier than an idle one). Without it, a busy+high desk still shadow-composes the drained brief + PAGES,
    # but does not exec. Requires --live (the busy exec gates on BOTH live + busyforce).
    if [ "$_busyforce" = 1 ]; then
      [ "$_live" = 1 ] || { echo "!! --busy-force requires --live (a mid-work forced recycle is opt-in beyond --live)" >&2; exit 2; }
    fi
    # ── all refusals cleared — every write below is unconditional ──────────────────────────────────
    rm -f "$(disarm_for "$PWD")" 2>/dev/null                # an explicit arm overrides a prior `clear` opt-out
    printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ) $PWD" > "$f"
    # brief template = the Stage-2 successor prompt seed; hard-required for LIVE (no empty-payload fire, FM-D)
    [ -n "$_brief" ] && cp "$_brief" "$(brief_for "$PWD")" 2>/dev/null
    if [ "$_live" = 1 ]; then
      : > "$(live_for "$PWD")"; mode="LIVE (deterministic recycle EXECS handoff-fire --recycle)"
    else
      rm -f "$(live_for "$PWD")" 2>/dev/null; mode="SHADOW (deterministic recycle LOGS would-fire, does NOT exec)"
    fi
    if [ "$_busyforce" = 1 ]; then
      : > "$(busyforce_for "$PWD")"; mode="$mode + BUSY-FORCE (busy+high mid-work recycle ALSO execs)"
    else
      rm -f "$(busyforce_for "$PWD")" 2>/dev/null
    fi
    # A fresh opt-in clears a stale cooldown; a RE-ARM of an already-armed desk does NOT — re-arming
    # would clear the cross-generation loop-breaker (panel landmine). Arm survives the in-place recycle,
    # so a SUCCESSOR must NEVER re-arm.
    [ "$was_armed" = 0 ] && rm -f "$(cooldown_for "$PWD")" 2>/dev/null
    echo "armed $mode → $f"; exit 0 ;;
  clear)
    rm -f "$(arm_for "$PWD")" "$(cooldown_for "$PWD")" "$(live_for "$PWD")" "$(brief_for "$PWD")" "$(busyforce_for "$PWD")" 2>/dev/null
    # Durable disarm marker — the per-desk kill-switch must ALSO suppress arm-by-default (a desk that
    # still HOLDS the monitoring-desk role would otherwise re-arm on the next poll). `arm` removes it.
    mkdir -p "$STATE_DIR" 2>/dev/null; date -u +%Y-%m-%dT%H:%M:%SZ > "$(disarm_for "$PWD")" 2>/dev/null
    echo "cleared (this desk opted out of monitoring auto-recycle; disarm marker set — run 'arm' to re-enable)"; exit 0 ;;
  status)
    a="$(arm_for "$PWD")"; c="$(cooldown_for "$PWD")"
    if [ -f "$KILL" ]; then echo "GLOBAL KILL active ($KILL) — no session recycles"; fi
    if [ -f "$(disarm_for "$PWD")" ]; then echo "DISARMED (this cwd) — 'clear' opt-out suppresses arm-by-default; run 'arm' to re-enable"; fi
    echo "thresholds: idle≥${T_IDLE}% (adaptive → floor ${T_IDLE_FLOOR}% over ${IDLE_DECAY_S}s idle) · busy-force≥${T_BUSY}% · rot-floor ${ROT_FLOOR}%"
    if [ -f "$a" ]; then
      echo "ARMED: $(cat "$a")"
      [ -f "$(live_for "$PWD")" ] && echo "  mode: LIVE (Stage-2 execs)" || echo "  mode: SHADOW (Stage-2 logs would-fire only)"
      [ -f "$(busyforce_for "$PWD")" ] && echo "  busy-force: ON (busy+high mid-work recycle also execs)" || echo "  busy-force: off (busy+high shadow-composes + pages, does NOT exec)"
      [ -s "$(brief_for "$PWD")" ] && echo "  brief: $(brief_for "$PWD") ($(wc -l < "$(brief_for "$PWD")" | tr -d ' ') lines)" || echo "  brief: none (LIVE blocked until set)"
    else echo "not armed by sentinel (this cwd) — a session HOLDING the '$DESK_ROLE' role is armed-by-default at poll time (SHADOW) unless disarmed"; fi
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
log_idl() { # $1=disposition $2=reason $3=extra JSON OBJECT (optional, jq-built {…}; default {})
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  local ts extra; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  extra="${3:-}"; [ -n "$extra" ] || extra='{}'
  # jq-encode EVERY field: a value carrying a " / backslash / newline then can NEVER emit a
  # malformed IDL line — one malformed line aborts the cc-audit four-zeros `jq -rs` slurp, which
  # reads as "no records" and silently flips D9/the alarm GREEN (defeats the un-gameable detector).
  jq -cn --arg ts "$ts" --arg sid "${SID:-?}" --arg disp "$1" --arg reason "$2" --argjson extra "$extra" \
    '{ts:$ts,hook:"waiting-recycle",sid:$sid,disposition:$disp,reason:$reason} + $extra' \
    >> "$IDL" 2>/dev/null || true
}
abstain() { log_idl abstained "$1"; exit 0; }

# T-P1-8 out-of-band operator pages (API-independent; BOTH are safe no-ops when unavailable/unarmed).
wr_os_notify() { # $1=title $2=msg — OS notification (osascript, or a stub in tests via CC_WR_NOTIFY)
  if [ -n "$NOTIFY_CMD" ]; then "$NOTIFY_CMD" "$1" "$2" >/dev/null 2>&1 || true; return 0; fi
  command -v osascript >/dev/null 2>&1 && \
    osascript -e "display notification \"${2//\"/}\" with title \"${1//\"/}\"" >/dev/null 2>&1 || true
}
wr_push_page() { # $1=msg — Pushover break-through; no-op (return 0) when the hook is missing/INERT
  [ -x "$PUSH_BIN" ] || return 0
  jq -cn --arg m "$1" --arg c "$CWD" '{message:$m,cwd:$c}' | "$PUSH_BIN" >/dev/null 2>&1 || true
}

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

# Desk-identity roots — shared by arm-by-default (below) + the S3/S4/S5 coordination holds. COORD is a
# FIXED path (cc-roles lives at $HOME/.claude, NOT $CLAUDE_CONFIG_DIR), so arm-by-default keys on the
# role regardless of which config dir the desk migrates to (unlike the (cfg,cwd) arm sentinel).
COORD="${CC_WR_COORD_DIR:-$HOME/.claude}"                    # root of wait-contracts/ mailbox/ cc-roles/
UUID="${CC_WR_UUID:-${ITERM_SESSION_ID:-}}"; UUID="${UUID##*:}"   # this desk's iTerm pane uuid (survives recycle)
# G-P11-7: is THIS session the monitoring desk? (cc-roles/<DESK_ROLE> resolves to its uuid or sid).
is_monitoring_desk() {
  local rf="$COORD/cc-roles/$DESK_ROLE" rv
  [ -f "$rf" ] || return 1
  rv="$(head -1 "$rf" 2>/dev/null | tr -d '[:space:]')"; [ -n "$rv" ] || return 1
  [ "$rv" = "$SID" ] || { [ -n "$UUID" ] && [ "$rv" = "$UUID" ]; }
}

# 1. OPT-IN (ARM-BY-DEFAULT, G-P11-7): a builder is never touched, but a MONITORING DESK is armed
# without the manual `arm` step. A per-desk `clear` disarm marker suppresses BOTH the sentinel and the
# role-arm (the kill-switch must still bite a role-holding desk). LIVE exec stays gated on live_for, so
# a role-armed desk is SHADOW by default (damp-first).
[ -f "$(disarm_for "$CWD")" ] && abstain "disarmed"
armed_by=""
if   [ -f "$(arm_for "$CWD")" ]; then armed_by="sentinel"
elif is_monitoring_desk;        then armed_by="desk-role"
fi
[ -n "$armed_by" ] || abstain "not-armed"

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
# yet fired.
escf="$(escalate_for "$SID")"; firedf="$(fired_for "$SID")"; stage2_pending=0
if [ -f "$escf" ] && [ ! -f "$firedf" ]; then
  est="$(cat "$escf" 2>/dev/null)"; case "$est" in ''|*[!0-9]*) est=0 ;; esac
  [ "$est" -gt 0 ] && [ "$(( $(date +%s) - est ))" -ge "$GRACE_S" ] && stage2_pending=1
fi

# T-P1-8 WEDGE — a desk that has exhausted its recycle attempts but is STILL fire-worthy must ESCALATE
# (page) not silently ride to auto-compaction. Two wedge shapes: the advisory CAP is reached, or a
# SHADOW would-fire already latched (already-fired recurs ONLY in shadow — a LIVE fire recycles to a
# fresh SID). The cwd COOLDOWN gates it (a recent advisory/fire ⇒ not yet wedged), and its own page-once
# pacer (escalated_for + ESCALATE_DEDUP_S) throttles the ongoing pages. Detected as a FLAG here; the
# page happens only AFTER the trigger+SAFE eval below confirms the desk is genuinely fire-worthy-and-
# just-waiting (never page a mid-work/holding desk).
shadow_fired=0; { [ "$stage2_pending" = 0 ] && [ -f "$firedf" ]; } && shadow_fired=1
wedged=0; escalation_paced=0
if [ "$stage2_pending" = 0 ] && [ "$cooled" = 0 ]; then
  { [ "$capped" = 1 ] || [ "$shadow_fired" = 1 ]; } && wedged=1
fi
if [ "$wedged" = 1 ] && [ -f "$(escalated_for "$SID")" ]; then
  ed_at="$(cat "$(escalated_for "$SID")" 2>/dev/null || echo 0)"; case "$ed_at" in ''|*[!0-9]*) ed_at=0 ;; esac
  [ "$(( $(date +%s) - ed_at ))" -lt "$ESCALATE_DEDUP_S" ] && { wedged=0; escalation_paced=1; }
fi
# Fast-path abstains (preserve the pre-restructure perf + reasons) — but NOT when a wedge must escalate:
# a wedged desk falls through to the trigger+SAFE eval so the escalate branch can page it.
if [ "$stage2_pending" = 0 ] && [ "$wedged" = 0 ]; then
  [ "$escalation_paced" = 1 ] && abstain "escalation-paced"
  [ "$cooled" = 1 ] && abstain "cooldown"
  [ "$capped" = 1 ] && abstain "capped:${N}>=${MAX}"    # defensive backstop (unreachable unless cooled/paced cleared the wedge)
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
# 4a-bis. ADAPTIVE IDLE THRESHOLD (4ce6ffc0194f): the base T_IDLE decays toward T_IDLE_FLOOR the longer
# this SID has sat below it on fresh polls — a desk idle for hours grows more eager to shed watch-rot
# (the "sat idle for hours then hit 74%" evidence). The clock is stamped on the FIRST sub-T_IDLE fresh
# poll and rides the SID; a recycle mints a fresh SID (clock resets) and the cwd cooldown still gates
# churn, so the decay cannot spin. IDLE_DECAY_S=0 disables it (eff_idle == T_IDLE). The decay lowers ONLY
# the IDLE bar; the BUSY forced path keys on T_BUSY, never eff_idle.
eff_idle="$T_IDLE"
if [ "$fresh" = 1 ]; then
  iwf="$(idlewatch_for "$SID")"
  { [ "$used" -lt "$T_IDLE" ] && [ ! -f "$iwf" ]; } && { date +%s > "$iwf" 2>/dev/null || true; }
  if [ -f "$iwf" ] && [ "$IDLE_DECAY_S" -gt 0 ] 2>/dev/null; then
    iw="$(cat "$iwf" 2>/dev/null || echo 0)"; case "$iw" in ''|*[!0-9]*) iw=0 ;; esac
    if [ "$iw" -gt 0 ]; then
      idle_age=$(( $(date +%s) - iw )); [ "$idle_age" -lt 0 ] && idle_age=0
      span=$(( T_IDLE - T_IDLE_FLOOR )); [ "$span" -lt 0 ] && span=0
      drop=$(( span * idle_age / IDLE_DECAY_S )); [ "$drop" -gt "$span" ] && drop="$span"
      eff_idle=$(( T_IDLE - drop )); [ "$eff_idle" -lt "$T_IDLE_FLOOR" ] && eff_idle="$T_IDLE_FLOOR"
    fi
  fi
fi
over_threshold=0; { [ "$fresh" = 1 ] && [ "$used" -ge "$eff_idle" ]; } && over_threshold=1

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

# 5. SAFE vs BUSY — we no longer abstain at the first hold: we CLASSIFY it and fall through to the
# decision-routing block (idle-fire vs busy-force vs busy-page vs Tier-2 hold). Every clause stays
# FALSE-NEGATIVE-safe (an unreadable/ambiguous signal HOLDS). First hold, in order, wins.
#   • class=soft — disk-DURABLE state (uncommitted tree, inbound wait-contract, mailbox ping): the
#     successor inherits it from disk, so at HIGH context the busy-force path recycles anyway and DRAINS
#     the pings into the successor brief (nothing dropped — the Tier-3 point).
#   • class=hard — would LOSE state or BURY a decision if recycled (git sequencer mid-merge, open operator
#     decision, live context-bound teammate): NEVER force — at high context it PAGES, it does not recycle.
SAFE=1; hold_class=""; hold_reason=""
hold() { if [ "$SAFE" = 1 ]; then SAFE=0; hold_class="$1"; hold_reason="$2"; fi; }

# 5a. Clean tree + no git SEQUENCER state. Dirty tree (SOFT): the working tree survives a pane recycle, so
# the successor inherits the uncommitted change (flagged in the brief). Live merge/rebase/cherry-pick
# (HARD): porcelain-CLEAN at step boundaries yet mid-active-work (the audit's "mid-merge between clean
# states", Fable panel S1) — fresh context mid-sequencer is error-prone, so page not force.
if [ "$SAFE" = 1 ] && git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ -z "$(git -C "$CWD" status --porcelain 2>/dev/null)" ] || hold soft "dirty-tree-hold"
  gd="$(git -C "$CWD" rev-parse --git-dir 2>/dev/null)"
  if [ "$SAFE" = 1 ] && [ -n "$gd" ]; then
    case "$gd" in /*) ;; *) gd="$CWD/$gd" ;; esac
    for seq in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
      [ -e "$gd/$seq" ] && { hold hard "sequencer-state-hold:$seq"; break; }
    done
  fi
fi
# 5b. Open decision/blocker in the last message (reuse anti-deference's GENUINE carve-out): a desk
# waiting on the operator's call must SURFACE, not silently recycle the question away (HARD).
GENUINE='your (credential|password|api.?key|secret|token|login|cookie)|need (your|the)[^.]{0,40}(credential|password|secret|token|key|access|permission|approval)|only you (can|have|know)|(don.?t|do not|no) [a-z ]{0,20}access|which account|you.?ll need to (provide|give|share|tell|run|log ?in)|i (don.?t|do not) have (access|the |your |permission)|can you (provide|share|tell me|give me|confirm which)|which (do you|would you|of (these|the)|option|approach|one)|(would|do) you prefer|your call|up to you|how would you like|which direction|your approval|requires? (your|sudo|approval|authentication)|run (this|it|the [a-z ]{0,20}) ?yourself|sudo|interactive login|auth login|pushing to (main|origin)|push (is|remains)[^.]{0,20}your call|won.?t push|will not push|not push(ing)? (to|without)|force.?push|destructive migration|drop table|delete[^.]{0,20}production|navigation pattern|(db|database) timeout'
[ "$SAFE" = 1 ] && [ -n "$MSG" ] && printf '%s' "$MSG" | grep -iqE "$GENUINE" && hold hard "open-decision-hold"

# 5c. Active-COORDINATION (Fable panel 2026-07-19 S3/S4/S5). S5 live teammate = HARD. S3 inbound wait +
# S4 mailbox = SOFT (durable on disk; the busy-force path DRAINS them into the successor brief). The
# desk's OWN waiter-contracts do NOT hold (durable — the successor resumes them). COORD/UUID resolved above.
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
mbx_active() { # $1=mailbox file → 0 if touched within QUIET_S
  [ -f "$1" ] || return 1
  local mt; mt="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0)"
  case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
  [ "$(( now_s - mt ))" -lt "$QUIET_S" ]
}
# S5 — live context-bound TEAMMATES (HARD HOLD — teammate/TaskOutput results route to THIS SID; a recycle
# or /compact kills them unrecoverably). Signal: a team dir created BY this session (existence ⇒ HOLD).
if [ "$SAFE" = 1 ]; then
  for td in "$CFG"/teams/session-"${SID:0:8}"*; do
    { [ -d "$td" ] && [ -f "$td/config.json" ]; } && { hold hard "live-team-hold"; break; }
  done
fi
# S3 — a peer is contract-BLOCKED on this desk: OPEN wait-contract, waitee names me, deadline future,
# waiter still ALIVE (a dead waiter's OPEN contract is a zombie — kill -0 filters it, panel S3). SOFT.
if [ "$SAFE" = 1 ] && [ -d "$COORD/wait-contracts" ]; then
  for wc in "$COORD"/wait-contracts/*.json; do
    [ -f "$wc" ] || continue
    [ "$(jq -r '.status // empty' "$wc" 2>/dev/null)" = "OPEN" ] || continue
    ident_is_me "$(jq -r '.waitee // empty' "$wc" 2>/dev/null)" || continue
    dl="$(jq -r '.deadline // 0' "$wc" 2>/dev/null)"; case "$dl" in ''|*[!0-9]*) dl=0 ;; esac
    [ "$dl" -gt "$now_s" ] || continue                        # past deadline ⇒ not a live block
    wp="$(jq -r '.waiter_pid // empty' "$wc" 2>/dev/null)"
    { [ -n "$wp" ] && ! kill -0 "$wp" 2>/dev/null; } && continue   # dead waiter ⇒ zombie, skip
    hold soft "inbound-wait-hold"; break
  done
fi
# S4 — a peer just reached for this desk (mailbox line fresher than QUIET_S). cc-notify ALWAYS
# mailbox-writes before injecting, and cc-dispatch workers notify the desk ROLE without a contract, so S3
# alone under-detects — S4 is load-bearing. Check the own-uuid mailbox + any role resolving to me. SOFT.
if [ "$SAFE" = 1 ]; then
  { [ -n "$UUID" ] && mbx_active "$COORD/mailbox/$UUID.md"; } && hold soft "inbox-active-hold"
fi
if [ "$SAFE" = 1 ] && [ -d "$COORD/cc-roles" ]; then
  for rf in "$COORD"/cc-roles/*; do
    [ -f "$rf" ] || continue
    rv="$(cat "$rf" 2>/dev/null)"
    { [ "$rv" = "$SID" ] || { [ -n "$UUID" ] && [ "$rv" = "$UUID" ]; }; } || continue
    mbx_active "$COORD/mailbox/$rv.md" && { hold soft "inbox-active-hold-role"; break; }
  done
fi

# drain_scan — print the desk's PENDING ping queue (mailbox tails + inbound OPEN contracts naming me), or
# nothing. Tier-3 busy-force embeds this in the successor brief so a mid-work recycle drops NO ping. It
# carries ALL pending content (not only QUIET_S-fresh) so a slightly-stale-but-unprocessed ping still rides.
drain_scan() {
  local rf rv wc
  if [ -n "$UUID" ] && [ -s "$COORD/mailbox/$UUID.md" ]; then
    printf '── mailbox %s ──\n' "$UUID"; tail -40 "$COORD/mailbox/$UUID.md" 2>/dev/null
  fi
  if [ -d "$COORD/cc-roles" ]; then
    for rf in "$COORD"/cc-roles/*; do
      [ -f "$rf" ] || continue
      rv="$(cat "$rf" 2>/dev/null)"
      { [ "$rv" = "$SID" ] || { [ -n "$UUID" ] && [ "$rv" = "$UUID" ]; }; } || continue
      [ -s "$COORD/mailbox/$rv.md" ] && { printf '── mailbox role:%s → %s ──\n' "$(basename "$rf")" "$rv"; tail -40 "$COORD/mailbox/$rv.md" 2>/dev/null; }
    done
  fi
  if [ -d "$COORD/wait-contracts" ]; then
    for wc in "$COORD"/wait-contracts/*.json; do
      [ -f "$wc" ] || continue
      [ "$(jq -r '.status // empty' "$wc" 2>/dev/null)" = "OPEN" ] || continue
      ident_is_me "$(jq -r '.waitee // empty' "$wc" 2>/dev/null)" || continue
      printf '── inbound wait-contract %s ──\n' "$(basename "$wc")"; jq -rc '{waiter,expected_signal,deadline,heartbeat}' "$wc" 2>/dev/null
    done
  fi
}

# ── DECISION ROUTING (tiered context-refresh, 4ce6ffc0194f) ──────────────────────────────────────────
# The desk is TRIGGER-worthy (over eff_idle, or a floored rot tell). Route on desk STATE:
#   SAFE (idle)                     → fire_mode=idle → the shared fire machine (Stage 1/2/wedge), unchanged.
#   BUSY soft + HIGH ctx (≥ T_BUSY) → fire_mode=busy → the shared fire machine, DRAINING the ping queue.
#   BUSY hard + HIGH ctx            → busy-page (cannot safely force — surface, never bury).
#   BUSY + medium/low               → Tier-2: mark a refresh-queued intent + hold (the lowered idle
#                                     threshold fires it at the next idle gap).
mkdir -p "$STATE_DIR" 2>/dev/null || true
high_ctx=0; { [ "$fresh" = 1 ] && [ "$used" -ge "$T_BUSY" ]; } && high_ctx=1
dod_carry="$("${DOD_PERSIST:-$(dirname "$0")/dod-persist.sh}" get 2>/dev/null || true)"
fire_mode=idle; drain_section=""

if [ "$SAFE" = 0 ]; then
  if [ "$high_ctx" = 1 ] && [ "$hold_class" = soft ]; then
    fire_mode=busy; drain_section="$(drain_scan)"             # Tier-3: force-recycle, carrying the pings
  elif [ "$high_ctx" = 1 ]; then
    # ── BUSY-PAGE — a HARD hold at high context. Forcing would lose state (sequencer/teammate) or bury a
    #    decision, so it will NOT recycle — page the operator OUT-OF-BAND (fleet-safe ⇒ ships LIVE),
    #    page-once per ESCALATE_DEDUP_S via escalated_for.
    if [ -f "$(escalated_for "$SID")" ]; then
      ep="$(cat "$(escalated_for "$SID")" 2>/dev/null || echo 0)"; case "$ep" in ''|*[!0-9]*) ep=0 ;; esac
      [ "$(( $(date +%s) - ep ))" -lt "$ESCALATE_DEDUP_S" ] && abstain "busy-page-paced:${hold_reason}"
    fi
    date +%s > "$(escalated_for "$SID")" 2>/dev/null || true
    log_idl escalated "busy-hard-hold:${hold_reason}" \
      "$(jq -cn --argjson used "$used" --arg hold "$hold_reason" --argjson busy 1 '{used_pct:$used,hold:$hold,busy:($busy==1),forceable:false}')"
    wr_os_notify "Claude desk BUSY+HIGH" "desk ${UUID:-$SID} at ${used}% mid-work (${hold_reason}) — can't safely auto-recycle"
    wr_push_page "BUSY+HIGH DESK (${DESK_ROLE}) ${used}% ctx, ${hold_reason} — resolve + /handoff; auto-recycle held (hard)"
    pmsg="⚠ BUSY + HIGH CONTEXT (${used}% ≥ ${T_BUSY}%) held by ${hold_reason} — a HARD hold: an auto-recycle would lose state or bury a decision, so it will NOT fire. You are climbing toward the 90% auto-compact wall. ACT NOW: resolve the ${hold_reason} (commit / finish the merge, answer the decision, or let the teammate finish), then run /handoff to recycle. Re-pages every ${ESCALATE_DEDUP_S}s. Kill-switch: \`waiting-recycle.sh clear\`."
    jq -nc --arg a "$pmsg" --arg s "$pmsg" \
      '{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'
    exit 0
  else
    # ── TIER 2 — BUSY at medium/low context. Don't interrupt the work; QUEUE a refresh (a soft hold marks
    #    intent; the lowered idle threshold fires it at the next idle gap) + hold with the specific reason.
    [ "$hold_class" = soft ] && { : > "$(queued_for "$SID")" 2>/dev/null || true; }
    log_idl abstained "$hold_reason" \
      "$(jq -cn --argjson used "$used" --arg cls "$hold_class" '{used_pct:$used,hold_class:$cls,refresh_queued:($cls=="soft")}')"
    exit 0
  fi
fi
# Reaching here: fire_mode=idle (SAFE) OR fire_mode=busy (BUSY soft + high ctx). The SHARED fire machine.

# trig label — honest to the actual gate (eff_idle for idle; T_BUSY for busy).
if   [ "$fire_mode" = busy ];                                then trig="context ${used}% ≥ ${T_BUSY}% while BUSY (${hold_reason})"
elif [ "$over_threshold" = 1 ] && [ "$rot_valid" = 1 ];     then trig="context ${used}% ≥ ${eff_idle}% AND a state-rot tell"
elif [ "$over_threshold" = 1 ];                             then trig="context ${used}% ≥ ${eff_idle}%"
else                                                             trig="a floored state-rot tell (re-deriving known state, ${used}% ≥ ${ROT_FLOOR}% floor)"
fi

# Already fired for THIS SID? one-fire-per-SID latch. A LIVE fire recycles to a fresh SID, so this only
# re-hits in SHADOW. If the desk is WEDGED (still fire-worthy) it routes to the escalate branch below
# (T-P1-8) instead of a silent already-fired; otherwise (cooled/paced — already handled in the fast-path
# above) stay quiet. Placed before Stage 2 so a re-poll never double-fires.
{ [ "$stage2_pending" = 0 ] && [ -f "$firedf" ] && [ "$wedged" = 0 ]; } && abstain "already-fired"

# ════ STAGE 2 — deterministic FIRE (cooldown+cap EXEMPT; bound = one-fire-per-SID latch) ════
if [ "$stage2_pending" = 1 ]; then
  : > "$firedf" 2>/dev/null                                   # latch FIRST — at-most-once per SID even on re-entry
  # Compose the successor brief ATOMICALLY (tmp+mv). NEVER empty/partial → no task-less successor (FM-D):
  #   standing --brief template (if armed) + frozen DoD + (busy) the drained ping queue + a re-derive directive.
  FIRE_DIR="${CC_WR_FIRE_DIR:-/tmp}"; pf="$FIRE_DIR/wr-fire-${SID}.txt"; tmpf="$pf.$$"
  {
    if [ -s "$(brief_for "$CWD")" ]; then cat "$(brief_for "$CWD")"
    elif [ "$fire_mode" = busy ]; then printf '%s\n' "You are the monitoring DESK, resumed by a deterministic self-recycle FORCED mid-work (predecessor context was ${used}% full — over the ${T_BUSY}% busy ceiling — and has been discarded to stop context rot)."
    else printf '%s\n' "You are the monitoring DESK, resumed by a deterministic self-recycle (predecessor context was ${used}% full and has been discarded to stop context rot)."; fi
    [ -n "$dod_carry" ] && printf '\nScope (frozen): %s\n' "$dod_carry"
    if [ "$fire_mode" = busy ]; then
      printf '\nNOTE — this recycle was FORCED while the desk was mid-work (%s). The working tree and any coordination state are on DISK; inspect git status / git diff and act on the drained pings below before assuming a clean slate.\n' "$hold_reason"
      [ -n "$drain_section" ] && printf '\nPENDING PINGS/REQUESTS TO CARRY (drained at recycle — do NOT drop; act on these after re-deriving state):\n%s\n' "$drain_section"
    fi
    printf '\nFIRST ACTION — re-derive live watch state from DISK (the predecessor context is GONE; do not assume): run cc-board for the fleet roster; read the live-session registry, ~/.claude/wait-contracts (owned waits), and your role mailbox; scan worktrees + git for wave/merge state. Then resume monitoring. Do NOT re-arm waiting-recycle (the arm survives the recycle; re-arming clears the loop-breaker).\n'
  } > "$tmpf" 2>/dev/null
  if [ -s "$tmpf" ]; then mv -f "$tmpf" "$pf" 2>/dev/null; else rm -f "$tmpf" 2>/dev/null; fi
  if [ ! -s "$pf" ]; then log_idl abstained "fire-compose-empty" "$(jq -cn --argjson used "$used" '{used_pct:$used}')"; exit 0; fi
  tk="$( [ "$over_threshold" = 1 ] && echo threshold || echo behavioral )"
  # EXEC gate: idle ⇒ armed --live. busy ⇒ armed --live AND the extra busy-force opt-in (a mid-work recycle
  # is qualitatively riskier than an idle one — it needs its own arm beyond --live). Else SHADOW.
  exec_ok=0
  if [ -f "$(live_for "$CWD")" ]; then
    if [ "$fire_mode" = idle ]; then exec_ok=1
    elif [ -f "$(busyforce_for "$CWD")" ] || [ "${CC_WR_BUSY_FORCE:-}" = on ]; then exec_ok=1; fi
  fi
  if [ "$exec_ok" = 1 ]; then
    date +%s > "$cf" 2>/dev/null || true                      # anchor the cross-generation loop-breaker on the FIRE
    log_idl fired "stage2-live" \
      "$(jq -cn --argjson used "$used" --arg trigger "$tk" --arg mode "$fire_mode" --arg prompt_file "$pf" --argjson grace_s "$GRACE_S" \
          '{used_pct:$used,trigger:$trigger,mode:$mode,prompt_file:$prompt_file,grace_s:$grace_s}')"
    # Sanctioned actuator: it arms a DETACHED watcher BEFORE typing /exit (order load-bearing), so the
    # recycle completes even when the /exit interrupt SIGKILLs this hook's process group.
    "$HANDOFF_FIRE" --recycle --prompt-file "$pf" ${UUID:+--session-id "$UUID"} </dev/null >/dev/null 2>&1 || true
    fmsg="⟳ DETERMINISTIC RECYCLE FIRED (${trig}) — the desk did not self-recycle within the ${GRACE_S}s grace, so waiting-recycle fired handoff-fire.sh --recycle. The successor is launching in this pane with the frozen DoD + a re-derive-from-disk brief. Do NOT run handoff-fire yourself."
    jq -nc --arg r "$fmsg" '{decision:"block",reason:$r,systemMessage:$r,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$r}}'
    exit 0
  fi
  # SHADOW (default): everything a live fire does EXCEPT the exec — ships the mechanism DAMPED so a gate
  # bug cannot strand the fleet before the operator reviews the shadow log and arms live (damp-first). A
  # BUSY shadow is more urgent than idle (mid-work AND high), so it ALSO pages out-of-band.
  log_idl fired "stage2-shadow" \
    "$(jq -cn --argjson used "$used" --arg trigger "$tk" --arg mode "$fire_mode" --arg prompt_file "$pf" --argjson grace_s "$GRACE_S" \
        '{used_pct:$used,would_fire:true,trigger:$trigger,mode:$mode,prompt_file:$prompt_file,grace_s:$grace_s}')"
  if [ "$fire_mode" = busy ]; then
    wr_os_notify "Claude desk BUSY+HIGH would-recycle" "desk ${UUID:-$SID} at ${used}% mid-work (${hold_reason}); drained brief at ${pf}"
    wr_push_page "BUSY+HIGH would-recycle (${DESK_ROLE}) ${used}%: drained brief at ${pf} — /handoff now or arm --busy-force"
    smsg="⟳ BUSY+HIGH RECYCLE WOULD FIRE — SHADOW (${trig}). The desk is mid-work (${hold_reason}) and did not self-recycle within ${GRACE_S}s. waiting-recycle composed a successor brief WITH the drained ping queue at ${pf} and logged a would-fire, but did NOT exec (a mid-work auto-recycle is opt-in beyond --live). Self-recycle now: run /handoff (it captures the same pings). To enable the exec: waiting-recycle.sh arm --brief <file> --live --busy-force. Kill-switch: waiting-recycle.sh clear."
  else
    smsg="⟳ RECYCLE WOULD FIRE — SHADOW (${trig}). The desk did not self-recycle within ${GRACE_S}s. waiting-recycle is armed SHADOW: it composed the successor brief at ${pf} and logged a would-fire, but did NOT exec (no fleet-stranding risk while soaking). You SHOULD still self-recycle now: run /handoff. To enable the exec after review: waiting-recycle.sh arm --brief <file> --live. Kill-switch: waiting-recycle.sh clear."
  fi
  jq -nc --arg a "$smsg" --arg s "$smsg" '{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'
  exit 0
fi

# ════ T-P1-8 ESCALATE — a WEDGED desk (advisory CAP reached / SHADOW would-fire latched) that is STILL
#     fire-worthy pages the operator OUT-OF-BAND rather than silently riding to the 90% auto-compact wall.
#     Paging is fleet-SAFE, so this ships LIVE. Page-once per ESCALATE_DEDUP_S via the escalated_for pacer. ═
if [ "$wedged" = 1 ]; then
  date +%s > "$(escalated_for "$SID")" 2>/dev/null || true   # stamp the page-once pacer FIRST (at-most-once/window)
  livearm="--live"; [ "$fire_mode" = busy ] && livearm="--live --busy-force"
  if [ "$capped" = 1 ]; then why="advisory budget exhausted (${N}/${MAX}), no recycle"
  else                        why="a SHADOW would-fire is latched but the exec is not armed ${livearm}"; fi
  state_phrase="clean tree + no open decision"; [ "$fire_mode" = busy ] && state_phrase="mid-work (${hold_reason})"
  log_idl escalated "wedge:${why}" \
    "$(jq -cn --argjson used "$used" --arg why "$why" --arg mode "$fire_mode" --argjson capped "$capped" --argjson shadow "$shadow_fired" \
        '{used_pct:$used,why:$why,mode:$mode,capped:($capped==1),shadow_fired:($shadow==1)}')"
  wr_os_notify "Claude desk WEDGED" "desk ${UUID:-$SID} at ${used}% can't self-recycle — ${why}"
  wr_push_page "WEDGED DESK (${DESK_ROLE}) ${used}% ctx: ${why} — /handoff now or arm ${livearm}"
  emsg="⚠ WEDGED — quiet monitoring boundary (${trig}), ${state_phrase}, but ${why}: you are RIDING toward the 90% auto-compact wall with NO recycle. ACT NOW: run /handoff to self-recycle, or (operator) arm the deterministic exec — desk-arm-live.sh (or waiting-recycle.sh arm --brief <file> ${livearm}). Re-pages every ${ESCALATE_DEDUP_S}s until resolved. Kill-switch: waiting-recycle.sh clear (this desk) / kill (global)."
  jq -nc --arg a "$emsg" --arg s "$emsg" \
    '{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'
  exit 0
fi

# ════ STAGE 1 — advisory (cooldown + cap already cleared above for this branch) ════
date +%s > "$cf" 2>/dev/null || true                         # stamp cooldown (anti-thrash + loop-breaker)
printf '%s' "$((N + 1))" > "$capf" 2>/dev/null || true       # bump advisory cap
[ -f "$escf" ] || date +%s > "$escf" 2>/dev/null || true     # set the Stage-2 grace clock on the FIRST advisory
log_idl fired "waiting-recycle" \
  "$(jq -cn --arg trigger "$( [ "$over_threshold" = 1 ] && echo threshold || echo behavioral )" --arg mode "$fire_mode" \
      --argjson used "$used" --argjson rot "$rot_valid" --argjson count "$((N+1))" --argjson max "$MAX" \
      '{trigger:$trigger,mode:$mode,used_pct:$used,rot:$rot,count:$count,max:$max}')"

if [ "$fire_mode" = busy ]; then
  # BUSY advisory — mid-work at high context. Urge a self-/handoff NOW (it captures the same pings); if
  # ignored, the shadow would-force (or, opted-in, the exec) escalates after grace.
  adv="⟳ BUSY + HIGH-CONTEXT AUTO-RECYCLE — you are mid-work (${hold_reason}) at ${used}% ≥ ${T_BUSY}%, climbing toward the 90% auto-compact wall. RECYCLE NOW while you still can cleanly: run /handoff — it captures the live state INCLUDING the pending pings/requests (mailbox + inbound wait-contracts) into the payload and fires handoff-fire.sh --recycle so the SUCCESSOR PANE IS THE CONTINUATION with nothing dropped. Commit any in-hand edit first (the working tree survives the recycle, but a fresh desk shouldn't inherit an unexplained diff). If you ignore this, the deterministic drain-and-recycle escalates in ${GRACE_S}s. Kill-switch: \`waiting-recycle.sh clear\` (this desk) / \`waiting-recycle.sh kill\` (global). (busy auto-recycle advisory $((N+1))/${MAX})"
else
  adv="⟳ MONITORING AUTO-RECYCLE — you are at a quiet monitoring boundary (${trig}). A watching desk accrues low-value context that rots your recall of the load-bearing orchestration state. RECYCLE NOW via your existing self-recycle path: run /handoff — it captures the live state (fired sessions, pending pings, wave/merge state, decisions) into the payload and fires handoff-fire.sh --recycle so the SUCCESSOR PANE IS THE CONTINUATION and this bloated context is discarded. Do it as this turn's next action. IF instead you actually hold in-hand write-work or a genuine open decision (you should not — the tree is clean and no blocker was detected), do NOT recycle: surface it. If you ignore this, the deterministic fire escalates in ${GRACE_S}s. Kill-switch: \`waiting-recycle.sh clear\` (this desk) / \`waiting-recycle.sh kill\` (global). (auto-recycle advisory $((N+1))/${MAX})"
fi
# ── carry the mission/DoD line so a recycle never loses purpose (T-P4-4; empty = none recorded) ──
[ -n "$dod_carry" ] && adv="${adv}

⟳ MISSION TO CARRY: ${dod_carry} — restate this verbatim as the successor's \`Scope (frozen):\` line in your /handoff payload so the recycle keeps its purpose (never drop or narrow it)."
sysmsg="⟳ waiting-recycle: desk at a quiet boundary (${trig}) — advising /handoff self-recycle ($((N+1))/${MAX}); deterministic fire in ${GRACE_S}s if ignored."

jq -nc --arg a "$adv" --arg s "$sysmsg" \
  '{decision:"block", reason:$s, systemMessage:$s, hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$a}}'
exit 0
