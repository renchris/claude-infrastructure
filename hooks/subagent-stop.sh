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
# Env seams (tests): SUBAGENT_STOP_IDL · SUBAGENT_STOP_LOG · SUBAGENT_STOP_REPORTS ·
#                    SUBAGENT_STOP_STATE
set -uo pipefail

IDL="${SUBAGENT_STOP_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
LOG="${SUBAGENT_STOP_LOG:-$HOME/.claude/logs/subagent-stop.log}"
REPORTS="${SUBAGENT_STOP_REPORTS:-$HOME/.claude/research-artifacts/subagent-reports.log}"
STATE="${SUBAGENT_STOP_STATE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/subagent-stop}"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
SID="?"; AGENT="?"; TP=""; FINAL=""

# ── IDL ─────────────────────────────────────────────────────────────────────────────────────────
# jq-encoded so a value carrying a quote/backslash/newline can never emit a malformed line (one
# malformed line aborts the cc-audit `jq -rs` slurp, which reads as "no records" and silently
# flips the abstain alarm green).
log_idl() { # <disposition> <reason>
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$TS" --arg sid "$SID" --arg agent "$AGENT" --arg tp "$TP" \
           --arg disp "$1" --arg reason "$2" \
      '{ts:$ts,actor:"subagent-stop",kind:"subagent_end",hook:"subagent-stop",
        sid:$sid,agent:$agent,transcript:$tp,disposition:$disp,reason:$reason}' \
      >> "$IDL" 2>/dev/null || true
  else
    # constant-shape fallback: no untrusted interpolation, so it cannot be malformed
    printf '{"ts":"%s","actor":"subagent-stop","kind":"subagent_end","hook":"subagent-stop","sid":"?","agent":"?","transcript":"","disposition":"abstained","reason":"no-jq"}\n' \
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
AGENT="$(jqs '.agent_name // .agentName // .subagent_type // .subagentType // .agent_type // .agent.name // .agent.type // .name // "?"')"
TP="$(jqs '.agent_transcript_path // .transcript_path // .transcriptPath // .transcript // ""')"
FINAL="$(jqs '(.final_message // .finalMessage // .last_message // .lastMessage // .result // .response // "") | if type=="string" then . else tojson end')"
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
         --arg final "$FINAL" --arg exists "$([ -n "$TP" ] && [ -f "$TP" ] && echo yes || echo no)" \
    '{ts:$ts,sid:$sid,agent:$agent,transcript:$tp,transcript_exists:$exists,
      final_chars:($final|length),final_head:($final[0:200])}' \
    >> "$REPORTS" 2>/dev/null || true
  log_idl fired "report-pointer"
  exit 0
fi

log_idl passed "no-report-in-payload"
exit 0
