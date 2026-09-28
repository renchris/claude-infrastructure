#!/bin/bash
# SessionEnd Hook — Skill-Harvest Candidate Logger
#
# Appends a one-line candidate record for substantive sessions so the human can
# later run /harvest-skill to synthesize a draft SKILL.md. NO model interaction,
# NO autonomous skill write — the synthesis (the expensive, judgment-heavy part)
# stays human-gated and on-demand.
#
# Adapted from hermes-agent skill_manage / background_review, minus the autonomous
# fork (which writes skills unattended — out of scope by our human-in-the-loop policy).
#
# ORDERING, corrected 2026-09-27. This header used to say it "Runs AFTER
# session-index-end.sh in the SessionEnd chain, so the DB row is fresh". It does not:
# the two are separate SessionEnd groups and Claude Code runs every matching hook of an
# event concurrently, so the row read below may still be session-index-start's stub
# (source='session-start', message_count 0, no commands). Two consequences, both handled
# here rather than assumed away:
#   · the message count comes from the payload's transcript_path, not the row. The row's
#     message_count read 0 in 11,666 of 11,670 SessionEnd index lines, so the 12-message
#     gate never opened and the hook logged 20 candidates ever
#     (docs/research/truememory-2026-09-27.md §3.3);
#   · a stub row is re-read briefly, and if it is still a stub the hook says so as a BLIND
#     abstention instead of reporting "no commands", which would read as a quiet session.
#
# EVERY EXIT PATH WRITES ONE IDL ROW (hook `harvest-skill-end`). Before this, the hook's
# only output was the candidate file, so "every session was thin" and "the gate can never
# open" were the same silence. BLIND reasons (could not observe the session) are enrolled in
# scripts/idl-abstain-alarm.sh's blind list, and the alarm's expected-fires registry
# (scripts/idl-expected-fires.tsv) pages SILENT if these rows stop while SessionEnd keeps
# indexing sessions.
set -euo pipefail

# The lib path is DEREFERENCED first: live, this file is ~/.claude/hooks/harvest-skill-end.sh,
# a symlink into the checkout, so the checkout's lib is found even before a deploy links it
# (same pattern as backup-before-write.sh's _mib_deref). Unresolvable ⇒ a no-op logger, so
# telemetry can never break the hook.
_hse_self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
_hse_lib="$(dirname "$_hse_self")/lib/idl-log.sh"
[ -r "$_hse_lib" ] || _hse_lib="$(dirname "${BASH_SOURCE[0]}")/lib/idl-log.sh"
if [ -r "$_hse_lib" ]; then
  # shellcheck source=lib/idl-log.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$_hse_lib"
  idl_init "${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}" "harvest-skill-end" SID
else
  log_idl() { :; }
fi
SID=""
# skip <reason> [extra-json]: one abstained row, then exit. BLIND vs DORMANT is decided by the
# REASON token (the alarm's blind list), so the call sites below name which one they mean.
skip() { log_idl abstained "$1" "${2:-}"; exit 0; }

INPUT=$(cat)
[ -n "$INPUT" ] || skip no-stdin
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
[ -n "$SID" ] || skip no-session-id
case "$SID" in *[!a-zA-Z0-9_-]*) SID=""; skip bad-session-id ;; esac

# Message count from the transcript: user + assistant records, `fromjson?` so a line cut
# short by the session ending mid-write is skipped rather than failing the count.
TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
TMSGS="" TSTATE=ok
if [ -z "$TP" ]; then
  TSTATE=no-transcript-path
elif [ ! -r "$TP" ]; then
  TSTATE=transcript-missing
else
  TMSGS=$(jq -Rn 'reduce (inputs | fromjson? | select(type == "object")
                          | select(.type == "user" or .type == "assistant")) as $_ (0; . + 1)' \
            < "$TP" 2>/dev/null || echo "")
  case "$TMSGS" in ''|*[!0-9]*) TMSGS=""; TSTATE=transcript-unreadable ;; esac
fi

# Same default + env override as hooks/lib/session-index-helpers.sh, so a fixtured
# suite can point this hook at a throwaway DB instead of the operator's live index.
DB="${SESSION_INDEX_DB:-$HOME/.claude/session-index.db}"
[ -f "$DB" ] || skip index-db-missing

# PER-COLUMN extraction. The previous form joined the three columns with '|' and split
# them back with `cut -d'|'` — but `commands_run` is RAW SHELL TEXT and routinely holds
# pipes (one probed row carried 127), so -f2 was a fragment of the first command and -f3
# the next fragment, never the file list. The corruption is visible in every record the
# hook has ever written: _candidates.jsonl line 1 stores a ` head -30 && echo …` fragment
# in files_changed. There is no delimiter that is safe against arbitrary shell text, so
# the join is removed rather than re-delimited — same class as
# docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md, at a call site that sweep never reached.
# `.timeout` because a raw sqlite3 spawns with a 0 ms busy timeout and dies under the
# concurrent SessionEnd writers this hook runs alongside (session-index-helpers.sh:43).
# Sets ROW and ROW_RC in this shell. The exit code, not the output, separates "no such row"
# from "could not read the index": sqlite3 3.43 prints NOTHING for zero rows under -json (older
# builds printed '[]'), which is the same empty string a failed read leaves behind.
read_row() {
  ROW_RC=0
  ROW=$(sqlite3 -json "$DB" ".timeout ${SESSION_INDEX_BUSY_TIMEOUT:-5000}" \
    "SELECT message_count AS m, commands_run AS c, files_changed AS f, source AS s FROM sessions WHERE session_id='$SID' LIMIT 1;" \
    2>/dev/null) || ROW_RC=$?
}
read_row
# A stub means session-index-end has not written yet (the concurrency above). Re-read a few
# times; the bound stays well inside a SessionEnd hook's budget.
_tries="${HARVEST_STUB_RETRIES:-5}"; case "$_tries" in ''|*[!0-9]*) _tries=5 ;; esac
while [ "$_tries" -gt 0 ] && [ "$(printf '%s' "$ROW" | jq -r '.[0].s // empty' 2>/dev/null)" = "session-start" ]; do
  sleep 0.2; read_row; _tries=$(( _tries - 1 ))
done
[ "$ROW_RC" -eq 0 ] || skip index-unreadable
case "$ROW" in ''|'[]') skip no-index-row ;; esac

RMSGS=$(printf '%s' "$ROW" | jq -r '.[0].m // 0' 2>/dev/null || echo 0)
CMDS=$(printf '%s' "$ROW" | jq -r '.[0].c // ""' 2>/dev/null || echo "")
FILES=$(printf '%s' "$ROW" | jq -r '.[0].f // ""' 2>/dev/null || echo "")
RSRC=$(printf '%s' "$ROW" | jq -r '.[0].s // ""' 2>/dev/null || echo "")

if [ -n "$TMSGS" ]; then
  MSGS="$TMSGS" MSRC=transcript
else
  MSGS="$RMSGS" MSRC=index-row
  case "$MSGS" in ''|*[!0-9]*) MSGS=0 ;; esac
  # With no transcript to count, the row is the only reading, and a 0 there is the known
  # stale value rather than an empty session — never "below gate".
  [ "$MSGS" -gt 0 ] || skip stale-telemetry "$(jq -cn --arg t "$TSTATE" '{transcript:$t}')"
fi
EXTRA=$(jq -cn --argjson m "$MSGS" --arg src "$MSRC" --arg t "$TSTATE" '{msgs:$m,msgs_src:$src,transcript:$t}')

[ "$RSRC" != "session-start" ] || skip index-row-stub "$EXTRA"
# Gate: skip trivial sessions (need real back-and-forth + tool activity)
[ "$MSGS" -ge 12 ] || skip below-gate "$EXTRA"
[ -n "$CMDS" ] || skip no-cmds "$EXTRA"

STAGE_DIR="$HOME/.claude/skills-pending"
mkdir -p "$STAGE_DIR" 2>/dev/null || true
STAGE="$STAGE_DIR/_candidates.jsonl"

if jq -cn \
  --arg sid "$SID" \
  --arg msgs "$MSGS" \
  --arg cmds "$CMDS" \
  --arg files "$FILES" \
  '{ts: (now|todate), session_id: $sid, message_count: ($msgs|tonumber? // 0), commands_run: $cmds, files_changed: $files, status: "unreviewed"}' \
  >> "$STAGE" 2>/dev/null; then
  log_idl fired staged "$EXTRA"
else
  log_idl failed stage-write-failed "$EXTRA"
fi

exit 0
