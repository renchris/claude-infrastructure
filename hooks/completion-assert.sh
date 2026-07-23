#!/usr/bin/env bash
# completion-assert.sh — Stop hook: catch the CONFIDENT / TELL-FREE false-done (FM1) that the
# phrasing-only anti-deference matcher structurally cannot see (p06 §thesis; a19 D-1/D-5/§KQ1).
#
# THE DEFECT (G-P6-6 / G-P11-3): a model can emit "✅ Complete — nothing to do" (or a tell-free
# scope-narrow like "that was the main ask") with in-scope work still uncommitted / unlanded /
# on the frozen-DoD remainder, and EVERY existing Stop layer waves it through — anti-deference
# needs a deference phrase, session-continue needs the model to have armed it, /goal's evaluator
# is tool-blind. Only a human re-asking "are you sure?" caught it — the literal FM1. In the 24/7
# no-human loop there is no re-ask. This hook IS the mechanical re-ask: it corroborates a done /
# soft-close assertion against the LIVE ledger and blocks-once when the facts contradict it.
#
# ── FIRE PREDICATE (P11 FM1 signature) ──
#   (done_assertion ∨ deference_tell) ∧ ledger-contradiction ∧ ¬genuine
#     ledger-contradiction := dirty ∨ unlanded-content ∨ DoD-remainder>0   (via wrap-ledger.sh)
#     genuine := credential/sudo/destructive-migration/external-info/value-fork ONLY.
#       ship/land of clean committed work is NOT genuine (2026-07-17 strengthening) → a
#       "park-and-ask-to-ship" close FIRES; the desk drives the land, it does not hold for it.
#   Because the matcher is broad but GATED on ground-truth facts, a TRUE-complete close (clean ∧
#   landed-by-content ∧ no remainder) abstains no matter how confidently it says "done".
#
# ── SAFETY (mirrors anti-deference-nudge.sh:26-41,90-104) ──
#   L one-shot latch (a fired MSG hash never re-fires) · C hard cap COMPLETION_MAX (default 3;
#   silent forever after) · F fail-safe: block ONLY via {decision:"block"}; EVERY path exits 0;
#   any read/jq/ledger failure → abstain. No `set -e` (a Stop hook exiting 2 false-blocks).
#   B-3 one IDL {fired|abstained:<reason>} line per invocation.
#
# Env seams (tests): COMPLETION_STATE_DIR · COMPLETION_IDL · COMPLETION_MAX · WRAP_LEDGER_BIN
set -uo pipefail

STATE_DIR="${COMPLETION_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/completion-assert}"
IDL="${COMPLETION_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
MAX="${COMPLETION_MAX:-3}"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SID="?"

input="$(cat 2>/dev/null || printf '{}')"

log_idl() { # $1=disposition $2=reason $3=extra JSON OBJECT (optional, jq-built {…}; default {})
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  local ts extra; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  extra="${3:-}"; [ -n "$extra" ] || extra='{}'
  # jq-encode EVERY field: a value carrying a " / backslash / newline then can NEVER emit a
  # malformed IDL line — one malformed line aborts the cc-audit four-zeros `jq -rs` slurp, which
  # reads as "no records" and silently flips D9/the alarm GREEN (defeats the un-gameable detector).
  jq -cn --arg ts "$ts" --arg sid "$SID" --arg disp "$1" --arg reason "$2" --argjson extra "$extra" \
    '{ts:$ts,hook:"completion-assert",sid:$sid,disposition:$disp,reason:$reason} + $extra' \
    >> "$IDL" 2>/dev/null || true
}
abstain() { log_idl abstained "$1"; exit 0; }

command -v jq >/dev/null 2>&1 || abstain "no-jq"

SID="$(printf '%s' "$input" | jq -r '.session_id // "?"' 2>/dev/null || echo '?')"
TP="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
CWD="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"

[ -n "$TP" ] || abstain "no-transcript-path"
case "$TP" in "~"*) TP="$HOME${TP#\~}" ;; esac
[ -f "$TP" ] || abstain "transcript-missing"
[ -n "$CWD" ] || abstain "no-cwd"

# ── Extract the LAST MAIN-agent text: skip sidechain (subagent) records, and walk back past a
#    tool_use-only / metadata tail to the last assistant record that actually carries text
#    (streaming; per-record compact-JSON keeps multi-line text on one line for tail -1). ──
LASTJSON="$(jq -c 'select(.type=="assistant" and (.isSidechain != true))
                   | ([.message.content[]? | select(.type=="text") | .text] | join("\n"))
                   | select(. != "")' "$TP" 2>/dev/null | tail -1 || true)"
MSG="$(printf '%s' "$LASTJSON" | jq -r '. // empty' 2>/dev/null || true)"
[ -n "$MSG" ] || abstain "no-assistant-text"

# ── A done-assertion or a soft/scope-narrow close (broad — the LEDGER is the discriminator). ──
CLOSE='(^|[^a-z])done([^a-z]|$)|complete([ds]|ly)?([^a-z]|$)|finished|nothing (left|more|else)?[a-z ]{0,12}to do|(^|[^a-z])landed([^a-z]|$)|shipped|pushed to (main|trunk|origin)|📦|✅|that (covers|wraps|completes|was the main ask)|main ask|remaining [a-z ]{0,20}items?|ready to implement|whenever you.?d? ?(like|want)|prioriti[sz]e|natural follow.?up|follow.?up|flagging (it|this)|for planning|larger effort|happy to (go|proceed|do|help)|either direction|let me know if|everything [a-z ]{0,20}is done|(^|[^a-z])remains?([^a-z]|$)|comes up'
printf '%s' "$MSG" | grep -iqE "$CLOSE" || abstain "no-close-tell"

# ── Genuine three (ship/land explicitly EXCLUDED — it is drivable, not a hold). ──
GENUINE='your (credential|password|api.?key|secret|token|login|cookie)|need (your|the)[^.]{0,40}(credential|password|secret|token|key|access|permission|approval)|only you (can|have|know)|which account|i (do ?n.?t|do not|dont) have (access|the |your |permission)|can you (provide|share|tell me|give me|confirm which)|(^|[^a-z])sudo([^a-z]|$)|interactive login|auth login|gcloud auth|destructive migration|drop table|delete[^.]{0,20}production|which (do you|would you|of (these|the)|option|approach|one)|(would|do) you prefer|which direction'
printf '%s' "$MSG" | grep -iqE "$GENUINE" && abstain "genuine-blocker"

# ── Ledger contradiction from LIVE reads (the ground-truth discriminator). ──
WRAP="${WRAP_LEDGER_BIN:-}"
if [ -z "$WRAP" ]; then
  for cand in "$(dirname "$0")/../scripts/wrap-ledger.sh" "$CFG/scripts/wrap-ledger.sh" "$HOME/.claude/scripts/wrap-ledger.sh"; do
    [ -f "$cand" ] && { WRAP="$cand"; break; }
  done
fi
[ -n "$WRAP" ] && [ -f "$WRAP" ] || abstain "no-wrap-ledger"

LED="$( cd "$CWD" 2>/dev/null && bash "$WRAP" --machine 2>/dev/null || true )"
[ -n "$LED" ] || abstain "no-ledger"
lfield() { printf '%s' "$LED" | grep -E "^$1=" | head -1 | cut -d= -f2- || true; }
RUNG="$(lfield RUNG)"
case "$RUNG" in ''|'?') abstain "ledger-uncomputable" ;; esac
DIRTY="$(lfield DIRTY)";     case "$DIRTY" in ''|*[!0-9]*) DIRTY=0 ;; esac
DIRTY_N="$(lfield DIRTY_N)"; case "$DIRTY_N" in ''|*[!0-9]*) DIRTY_N=0 ;; esac
UNLANDED="$(lfield UNLANDED)"; case "$UNLANDED" in ''|*[!0-9]*) UNLANDED=0 ;; esac
AHEAD="$(lfield AHEAD)";     case "$AHEAD" in ''|*[!0-9]*) AHEAD=0 ;; esac
REMAINDER="$(lfield REMAINDER)"; case "$REMAINDER" in ''|*[!0-9]*) REMAINDER=0 ;; esac

contra=0; facts=""
[ "$DIRTY" -eq 1 ]      && { contra=1; facts="${facts}dirty tree (${DIRTY_N} file(s)); "; }
[ "$UNLANDED" -eq 1 ]   && { contra=1; facts="${facts}${AHEAD} commit(s) committed-but-unlanded (/ship to land); "; }
[ "$REMAINDER" -gt 0 ]  && { contra=1; facts="${facts}${REMAINDER} frozen-DoD item(s) remain; "; }
[ "$contra" -eq 1 ] || abstain "ledger-clean"

# ── Latch-set + hard cap (RED-proofed L + C). ──
mkdir -p "$STATE_DIR" 2>/dev/null || true
# GC stale per-session .fired latch-sets — SKEY embeds SID, so each is per-session and otherwise
# never reaped (mirrors memory-nudge.sh:26). A live session recreates its own on the next fire.
find "$STATE_DIR" -name '*.fired' -mtime +7 -delete 2>/dev/null || true
SKEY="$(printf '%s|%s|%s' "$CFG" "$SID" "$CWD" | shasum 2>/dev/null | cut -c1-16)"
[ -n "$SKEY" ] || abstain "no-skey"
HASH="$(printf '%s' "$MSG" | shasum 2>/dev/null | cut -c1-16)"
[ -n "$HASH" ] || abstain "no-hash"
FIRED="$STATE_DIR/$SKEY.fired"
if [ -f "$FIRED" ] && grep -qxF "$HASH" "$FIRED" 2>/dev/null; then abstain "latched-already-fired"; fi
N="$(grep -c . "$FIRED" 2>/dev/null || echo 0)"; case "$N" in ''|*[!0-9]*) N=0 ;; esac
[ "$N" -ge "$MAX" ] && abstain "capped:${N}>=${MAX}"

# ── FIRE: record hash, log, block with the contradicting FACTS. ──
printf '%s\n' "$HASH" >> "$FIRED" 2>/dev/null || true
facts="${facts%; }"
log_idl fired "false-done" \
  "$(jq -cn --arg facts "$facts" --arg rung "$RUNG" --argjson count "$((N+1))" --argjson max "$MAX" \
      '{facts:$facts,rung:$rung,count:$count,max:$max}')"

reason="Completion-assert: your close reads as done/complete, but the LIVE ledger contradicts it — ${facts}. Ship/land of verified net-positive work is DRIVABLE (not a genuine blocker). Re-answer by DRIVING the remainder to done (📦 ⇒ /ship it; finish the open items; commit with explicit paths) — or name the ONE irreducible blocker (credential / sudo / destructive-migration / external-info only the operator has). (completion-assert $((N+1))/${MAX})"

jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
