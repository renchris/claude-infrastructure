#!/bin/bash
# subagent-stop.sh — D-12 v1: the FIRST consumer of the SubagentStop event.
#
# WHY (audit 09 D-12): the harness supports SubagentStop (22 hits in claude.exe) and it was wired
# NOWHERE. That is the structural gap behind wave-report STRANDING (memory: named background
# subagents cannot SendMessage, so their final report dies in a transcript nobody harvests, and
# "idle" reads as "delivered"). A subagent ending is the ONE moment the system is guaranteed to know
# a report exists. This hook makes that moment leave a durable trace.
#
# WHAT IT DOES (v1 — deliberately small, because the payload SCHEMA IS NOT DOCUMENTED):
#   1. one IDL line per invocation  {actor:"subagent-stop", kind:"subagent_end", …}
#      — plus .hook/.disposition so scripts/idl-abstain-alarm.sh can see it (the ship-gate law:
#        a check that emits nothing cannot be distinguished from a check that is structurally blind)
#   2. SCHEMA DISCOVERY: the payload's leaf key paths, appended to ~/.claude/logs/subagent-stop.log
#      once per (day × distinct shape). v2 can then read real fields instead of guessing.
#   3. when the payload carries a transcript path and/or a final message, ONE pointer line to
#      ~/.claude/research-artifacts/subagent-reports.log — the harvest index, not a copy of the body.
#
# FAIL-OPEN BY CONSTRUCTION: no `set -e` (a hook that dies mid-way is a silent no-check, and a
# nonzero SubagentStop could interfere with the agent lifecycle). Every field is derived
# DEFENSIVELY across several plausible spellings; every write is `|| true`. Exit is always 0.
#
# 🚨 v2 (HOOK_SURFACE_100P W3-A): THE SCHEMA IS NO LONGER UNDOCUMENTED — it was MEASURED. The v1
# text above is kept because its reasoning still holds; what changed is that the guessing is over.
# Captured verbatim on 2.1.220 (/tmp/hs/log/sub3.tsv, W1 § 3a):
#   {"session_id":"…","transcript_path":"…","cwd":"…","prompt_id":"…","permission_mode":"auto",
#    "agent_id":"a98cd5803b06f1084","agent_type":"general-purpose","effort":{"level":"low"},
#    "hook_event_name":"SubagentStop","stop_hook_active":false,
#    "agent_transcript_path":"…/subagents/agent-a98cd5803b06f1084.jsonl",
#    "last_assistant_message":"ping","background_tasks":[],"session_crons":[]}
# Two defects in v1 fall straight out of that, and both made this hook quieter than it looked:
#   · the report body is `last_assistant_message`, which v1's chain does NOT contain — so `FINAL`
#     was ALWAYS "" and every pointer line recorded final_chars:0. The index existed and carried no
#     report. The measured key now leads the chain; v1's guesses stay behind it as fallbacks.
#   · `agent_id` was not read at all. It is the ONLY field joining this record to the SubagentStart
#     that opened the agent, and it names the transcript file — without it a harvester cannot tell
#     two concurrent agents of the same `agent_type` apart.
#
# STILL NON-BLOCKING, and now pinned by test rather than by intent: SubagentStop is Stop-family, so
# a `decision:"block"` or a `hookSpecificOutput.additionalContext` here does not merely misbehave —
# it extends the turn and increments the harness's consecutive-block counter (capped at 8). This
# hook therefore writes NOTHING to stdout on any path and always exits 0.
#
# Env seams (tests): SUBAGENT_STOP_IDL · SUBAGENT_STOP_LOG · SUBAGENT_STOP_REPORTS ·
#                    SUBAGENT_STOP_STATE
set -uo pipefail

IDL="${SUBAGENT_STOP_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
LOG="${SUBAGENT_STOP_LOG:-$HOME/.claude/logs/subagent-stop.log}"
REPORTS="${SUBAGENT_STOP_REPORTS:-$HOME/.claude/research-artifacts/subagent-reports.log}"
STATE="${SUBAGENT_STOP_STATE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/subagent-stop}"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
SID="?"; AGENT="?"; AGENT_ID=""; TP=""; FINAL=""

# ── IDL ─────────────────────────────────────────────────────────────────────────────────────────
# jq-encoded so a value carrying a quote/backslash/newline can never emit a malformed line (one
# malformed line aborts the cc-audit `jq -rs` slurp, which reads as "no records" and silently
# flips the abstain alarm green).
log_idl() { # <disposition> <reason>
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$TS" --arg sid "$SID" --arg agent "$AGENT" --arg tp "$TP" \
           --arg agent_id "$AGENT_ID" --arg disp "$1" --arg reason "$2" \
      '{ts:$ts,actor:"subagent-stop",kind:"subagent_end",hook:"subagent-stop",
        sid:$sid,agent:$agent,agent_id:$agent_id,transcript:$tp,disposition:$disp,reason:$reason}' \
      >> "$IDL" 2>/dev/null || true
  else
    # constant-shape fallback: no untrusted interpolation, so it cannot be malformed
    printf '{"ts":"%s","actor":"subagent-stop","kind":"subagent_end","hook":"subagent-stop","sid":"?","agent":"?","agent_id":"","transcript":"","disposition":"abstained","reason":"no-jq"}\n' \
      "$TS" >> "$IDL" 2>/dev/null || true
  fi
}
abstain() { log_idl abstained "$1"; exit 0; }

input="$(cat 2>/dev/null || printf '')"
[ -n "$input" ] || abstain "no-stdin"
command -v jq >/dev/null 2>&1 || abstain "no-jq"
printf '%s' "$input" | jq -e . >/dev/null 2>&1 || abstain "unparseable-payload"

jqs() { printf '%s' "$input" | jq -r "$1" 2>/dev/null || true; }   # never fatal

# ── defensive field derivation — the payload schema is UNDOCUMENTED, so try every plausible
#    spelling and fall back to "?" rather than guessing wrong or dying.
SID="$(jqs '.session_id // .sessionId // .session.id // "?"')"
# `.agent_type` is the MEASURED key and now leads; the v1 guesses stay as fallbacks so a future
# binary that renames it degrades to a wrong-but-present label rather than to "?".
AGENT="$(jqs '.agent_type // .agent_name // .agentName // .subagent_type // .subagentType // .agent.name // .agent.type // .name // "?"')"
AGENT_ID="$(jqs '.agent_id // .agentId // .agent.id // ""')"
TP="$(jqs '.agent_transcript_path // .transcript_path // .transcriptPath // .transcript // ""')"
# `.last_assistant_message` FIRST — measured. Its absence from v1's chain is why every pointer
# line this hook had ever written carried final_chars:0.
FINAL="$(jqs '(.last_assistant_message // .lastAssistantMessage // .final_message // .finalMessage // .last_message // .lastMessage // .result // .response // "") | if type=="string" then . else tojson end')"
[ -n "$SID" ] || SID="?"
[ -n "$AGENT" ] || AGENT="?"
case "$TP" in "~"*) TP="$HOME${TP#\~}" ;; esac

# ── SCHEMA DISCOVERY: leaf key paths, once per (day × distinct shape) ───────────────────────────
KEYS="$(jqs '[paths(scalars) | map(tostring) | join(".")] | sort | unique | join(",")')"
if [ -n "$KEYS" ]; then
  sig="$(printf '%s' "$KEYS" | cksum 2>/dev/null | awk '{print $1}' || echo 0)"
  marker="$STATE/schema-$(date -u +%Y%m%d 2>/dev/null || echo 0)-$sig"
  if [ ! -f "$marker" ]; then
    mkdir -p "$STATE" "$(dirname "$LOG")" 2>/dev/null || true
    printf '%s subagent-stop schema: keys=[%s]\n' "$TS" "$KEYS" >> "$LOG" 2>/dev/null || true
    : > "$marker" 2>/dev/null || true
    find "$STATE" -type f -name 'schema-*' -mtime +30 -delete 2>/dev/null || true
  fi
fi

# ── the harvest index: a POINTER, never a copy of the report body ───────────────────────────────
if [ -n "$TP" ] || [ -n "$FINAL" ]; then
  mkdir -p "$(dirname "$REPORTS")" 2>/dev/null || true
  jq -cn --arg ts "$TS" --arg sid "$SID" --arg agent "$AGENT" --arg tp "$TP" \
         --arg agent_id "$AGENT_ID" \
         --arg final "$FINAL" --arg exists "$([ -n "$TP" ] && [ -f "$TP" ] && echo yes || echo no)" \
    '{ts:$ts,sid:$sid,agent:$agent,agent_id:$agent_id,transcript:$tp,transcript_exists:$exists,
      final_chars:($final|length),final_head:($final[0:200])}' \
    >> "$REPORTS" 2>/dev/null || true
  log_idl fired "report-pointer"
  exit 0
fi

log_idl passed "no-report-in-payload"
exit 0
