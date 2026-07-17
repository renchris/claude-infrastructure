#!/usr/bin/env bash
# anti-deference-nudge.sh — Stop hook: catch the DEFERENCE REFLEX at the harness level.
#
# THE DEFECT (operator's #1 behavioral flag, 2026-07-17, flagged 4×): the model finishes
# DRIVABLE, pre-authorized work and then, instead of just DOING the obvious next step,
# presents it as a question/hold — "say the word", "want me to", "shall I", "should I
# proceed", "otherwise I'll hold", "your steer". Under the Session Close Protocol that work
# should AUTO-CONTINUE (G1-G4 hold); pausing to ask is the defect. A memory note kept
# slipping, so this is the STRUCTURAL fix: a Stop hook that reads the last assistant message,
# detects the tell, and blocks the stop with a corrective nudge — DRIVE it, don't defer.
#
# ── WHAT IT STRUCTURALLY CANNOT SEE / THE THREE-GENUINE CARVE-OUT ──
#   The hook must NEVER fire on a LEGITIMATE surface. Three asks are genuine and pre-authorized
#   to STOP the model (Session Close Protocol ⛔ / G2-G3): (1) external-info only the operator
#   has (credentials, which-account, no-access); (2) a value-fork the standing values do not
#   settle (which-do-you-prefer, your-call); (3) a C10 permission the model cannot self-execute
#   (push/land/deploy, sudo, interactive login, destructive migration, force-push). So the fire
#   predicate is  has_tell AND NOT has_genuine  — a tell that CO-OCCURS with any genuine marker
#   abstains. Bias is deliberately toward FALSE-NEGATIVE (miss a soft defer) over FALSE-POSITIVE
#   (nag a real blocker): a nagging hook trains the model to route around it. Both regexes were
#   corpus-validated (tests/anti-deference-nudge.bats + scratchpad probe): 15 positives fire,
#   16 negatives — clean answers, genuine-STOP-ASK-with-tell, and substring traps ("should i
#   download", "want to", "otherwise the code…") — stay silent.
#
# ── SAFETY (a runaway blocking hook is worse than the disease — RED-proofed) ──
#   L  ONE-SHOT LATCH-SET: the hash of every FIRED message is appended to a per-session set; a
#      message whose hash is already in the set NEVER re-fires (kills the block→identical-reply→
#      block infinite loop — the banned unlatched-block anti-pattern). Re-arm is a genuinely NEW
#      message (new hash) that still carries a tell.
#   C  HARD CAP (ANTIDEF_MAX, default 3): the set's size IS the session fire-count; at N fires the
#      hook goes silent forever this session — so even a model that PARAPHRASES its defer every
#      turn (new hash each time, latch can't catch it) is bounded and never wedges the session.
#   F  FAIL-SAFE: block is emitted ONLY via {decision:"block"} on stdout; EVERY path exits 0. Any
#      transcript-read / jq / parse failure → abstain → exit 0. No `set -e` (a Stop hook exiting 2
#      would FALSE-BLOCK; -e turning a stray grep-exit-2 into the script's exit code is exactly the
#      landmine the task bans). -u/pipefail are on for hygiene: a -u violation exits 1 = a
#      NON-blocking error (stop proceeds) = the safe direction; all vars are defaulted so it can't
#      misfire in normal operation.
#   B-3  Every invocation emits ONE {fired|abstained:<reason>} line to the IDL, so "didn't fire"
#      and "never evaluated" are distinguishable (boundary-handoff B-3 discipline). Alarm on
#      abstained==100% over a long window would mean the tells stopped matching reality.
#
# Env seams (tests): ANTIDEF_STATE_DIR · ANTIDEF_IDL · ANTIDEF_MAX
set -uo pipefail

STATE_DIR="${ANTIDEF_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/anti-deference}"
IDL="${ANTIDEF_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
MAX="${ANTIDEF_MAX:-3}"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

input="$(cat 2>/dev/null || printf '{}')"

# ── B-3: one IDL line per invocation. Never fails the hook. ──
log_idl() { # $1=disposition $2=reason $3=extra-json(optional)
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  printf '{"ts":"%s","hook":"anti-deference-nudge","sid":"%s","disposition":"%s","reason":"%s"%s}\n' \
    "$ts" "${SID:-?}" "$1" "$2" "${3:+,$3}" >> "$IDL" 2>/dev/null || true
}
abstain() { log_idl abstained "$1"; exit 0; }   # evaluated-but-did-not-fire (LOGGED, not silent)

command -v jq >/dev/null 2>&1 || { SID="?"; abstain "no-jq"; }

SID="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
TP="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
CWD="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"

[ -n "$TP" ] || abstain "no-transcript-path"
case "$TP" in "~"*) TP="$HOME${TP#\~}" ;; esac      # expand a leading ~ if present
[ -f "$TP" ] || abstain "transcript-missing"

# ── Extract the LAST assistant message's text (streaming: keep only the last matching line,
#    never slurp a large transcript into memory). tool_use-only / empty last turn → abstain. ──
MSG="$(jq -c 'select(.type=="assistant")' "$TP" 2>/dev/null | tail -1 \
        | jq -r '[.message.content[]? | select(.type=="text") | .text] | join("\n")' 2>/dev/null || true)"
[ -n "$MSG" ] || abstain "no-assistant-text"

# ── High-confidence deference tells on DRIVABLE work (corpus-validated; boundaries guard the
#    substring traps: "should i (do)" won't match "should i download"; the "otherwise" tell
#    requires a first-person hold, so "otherwise the code…" stays silent). ──
TELLS='say the word|on your word|want me to|shall i|should i (proceed|do|go)([^a-z0-9]|$)|let me know if you|holding for your|otherwise (i.?ll|i will|i.?d) (hold|wait|leave|hang|pause|stand)|your steer|do you want me to|awaiting your|i can [a-z]+ (it|this)( (next|now))?[[:space:]]*[—–-]+[[:space:]]*otherwise[[:space:]]+i'

printf '%s' "$MSG" | grep -iqE "$TELLS" || abstain "no-tell"

# ── The three-genuine carve-out: a tell co-occurring with a REAL blocker is legitimate. ──
GENUINE='your (credential|password|api.?key|secret|token|login|cookie)|need (your|the)[^.]{0,40}(credential|password|secret|token|key|access|permission|approval)|only you (can|have|know)|(don.?t|do not|no) [a-z ]{0,20}access|which account|you.?ll need to (provide|give|share|tell|run|log ?in)|i (don.?t|do not) have (access|the |your |permission)|can you (provide|share|tell me|give me|confirm which)|which (do you|would you|of (these|the)|option|approach|one)|(would|do) you prefer|your call|up to you|how would you like|which direction|your approval|requires? (your|sudo|approval|authentication)|run (this|it|the [a-z ]{0,20}) ?yourself|sudo|interactive login|auth login|pushing to (main|origin)|push (is|remains)[^.]{0,20}your call|won.?t push|will not push|not push(ing)? (to|without)|force.?push|destructive migration|drop table|delete[^.]{0,20}production|navigation pattern|(db|database) timeout'

printf '%s' "$MSG" | grep -iqE "$GENUINE" && abstain "genuine-blocker"

# ── Latch-set + hard cap (RED-proofed L + C). ──
mkdir -p "$STATE_DIR" 2>/dev/null || true
SKEY="$(printf '%s|%s|%s' "$CFG" "$SID" "$CWD" | shasum 2>/dev/null | cut -c1-16)"
[ -n "$SKEY" ] || abstain "no-skey"
HASH="$(printf '%s' "$MSG" | shasum 2>/dev/null | cut -c1-16)"
[ -n "$HASH" ] || abstain "no-hash"
FIRED="$STATE_DIR/$SKEY.fired"     # newline-separated set of already-fired message hashes

# L: identical (or any previously-fired) content → never re-fire.
if [ -f "$FIRED" ] && grep -qxF "$HASH" "$FIRED" 2>/dev/null; then
  abstain "latched-already-fired"
fi
# C: the set's size is the session fire-count; at the cap, go silent (never wedge).
N="$(grep -c . "$FIRED" 2>/dev/null || echo 0)"; case "$N" in ''|*[!0-9]*) N=0 ;; esac
[ "$N" -ge "$MAX" ] && abstain "capped:${N}>=${MAX}"

# ── FIRE: record the hash (re-arm baseline + cap increment), log, block with the corrective. ──
printf '%s\n' "$HASH" >> "$FIRED" 2>/dev/null || true
TELL="$(printf '%s' "$MSG" | grep -ioE "$TELLS" 2>/dev/null | head -1 | tr -d '\n')"
log_idl fired "deference-tell" "\"tell\":\"${TELL//\"/}\",\"count\":$((N+1)),\"max\":${MAX}"

reason="Anti-deference: you presented drivable work as a question/hold (matched: \"${TELL}\"). If it's drivable + pre-authorized, DRIVE it now — only surface the genuine three (external-info the operator alone has / a value-fork the standing values don't settle / a C10 permission you can't self-execute like push·land·deploy·sudo·destructive-migration). Re-answer by DOING it, or by naming the ONE specific irreducible blocker. (anti-deference nudge $((N+1))/${MAX})"

jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
