#!/bin/bash
# post-tool-batch.sh — the ALL-TOOL-CALL CENSUS, one line per BATCH (HOOK_SURFACE_100P § 3 row 4).
#
# WHY THIS EVENT AND NOT PostToolUse. `PostToolBatch` fires ONCE PER BATCH, not once per tool call,
# and its payload carries every call's `tool_name`, `tool_input` AND `tool_response`, plus
# `permission_mode` and `effort` — fields our PostToolUse payloads do not have. Measured on 2.1.220:
# three parallel Bash calls produced 3 PreToolUse · 3 PostToolUse · 1 PostToolBatch whose
# `tool_calls[]` held all three (HOOK_SURFACE_100P § 3a row 4). So the census this writes costs ONE
# invocation where the per-call chain pays its full cost N times.
#
# WHAT IT IS FOR. HOOK_CHAIN_COST.md R-7 (`f6cc5c79885b`) records the gap: there is no all-tool-call
# census, so no match-all hook's cost can be stated per-hour — `bash-execution.log` covers Bash and
# nothing else. That row was the ORIGINAL HOLD on this event, and HOOK_SURFACE_100P § 3 discharges
# it: the ratio does not have to be measured before wiring, because the event IS the measurement.
# Each line below carries `n` (the batch size = the per-call chain's amplification for that batch)
# and the tool breakdown, so the rate and the ratio both fall out of the same log.
#
# ⚠️ 220-ONLY, AND SILENTLY SO. `PostToolBatch` is absent from the 2.1.114 enum — 0 occurrences in
# that binary, against 7 in 2.1.220 (tests/post-tool-batch.bats measures both). An unknown hook
# event name is SILENTLY ACCEPTED by the harness: no error, no warning, no log line
# (HOOK_SURFACE_100P § 5). So a registration here is a no-op on 114, never a breakage — but the
# corollary is the real hazard: the same handler pointed at an event 114 DOES dispatch would mint a
# bogus n=1 row for every single tool call. Hence the `hook_event_name` gate below, which is not
# defensive decoration: it is what makes a mis-registration inert instead of wrong.
#
# FAIL-OPEN BY CONSTRUCTION: no `set -e`. Empty stdin, malformed JSON, an absent `tool_calls`, a
# missing jq — every one of them exits 0 and writes no census row. A hook on this path must never
# be able to fail a tool batch.
#
# COST: two forks in the steady state (jq, and `stat` for the rotation check). The timestamp is
# produced INSIDE the jq program (`now|todate`) rather than by a `date` fork, and stdin is read with
# the `read` builtin rather than `$(cat)` — both for the reason HOOK_CHAIN_COST § 2.1 measures:
# process creation, not interpretation, is what the chain costs.
#
# Env seams (tests): POST_TOOL_BATCH_LOG · POST_TOOL_BATCH_MAX_BYTES
set -uo pipefail

LOG="${POST_TOOL_BATCH_LOG:-$HOME/.claude/logs/tool-batch-census.jsonl}"
MAX_BYTES="${POST_TOOL_BATCH_MAX_BYTES:-4194304}"   # 4 MiB, one generation kept

# Builtin read, NOT `$(cat)`: a command substitution forks AND execs /bin/cat. `read -d ''` returns
# non-zero at EOF — the normal case — hence `|| true`.
IFS= read -r -d '' INPUT || true
[ -n "$INPUT" ] || exit 0                            # missing args / empty stdin ⇒ inert, exit 0

# `${LOG%/*}` not `$(dirname)`, and the mkdir only when the directory is genuinely missing: both
# are command substitutions on a path that runs once per batch and usually writes into a directory
# that already exists. `[ -d ]` is a builtin and costs nothing.
LOGDIR="${LOG%/*}"
ensure_dir() { [ -d "$LOGDIR" ] || mkdir -p "$LOGDIR" 2>/dev/null || true; }

abstain() { # <reason> — a blind census must be distinguishable from an empty one (idl-abstain law).
  local ts
  ensure_dir
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '?')"
  # constant shape, no untrusted interpolation, so this line can never itself be malformed
  printf '{"ts":"%s","hook":"post-tool-batch","abstain":"%s"}\n' "$ts" "$1" >> "$LOG" 2>/dev/null || true
  exit 0
}

command -v jq >/dev/null 2>&1 || abstain "no-jq"

# ONE jq call does all of it: the event gate, the shape gate, the timestamp, and the census row.
# The shape gate is `length > 0` and nothing else. A `type == "array"` guard stood beside it and was
# deleted after mutation testing showed it un-falsifiable: `null|length` is 0, and every non-array
# that survives `length` makes the following `map` raise, which empties ROW by the same path. Two
# gates producing one outcome means no test can credit either, so the redundant one was dead code
# wearing a guard's clothes (memory: one mutant per SITE — a green suite credits NO site).
# jq-encoded end to end, so a command carrying a quote, a backslash or a newline can never shred
# the line — one malformed line aborts a `jq -s` slurp downstream, which reads as "no records".
ROW="$(printf '%s' "$INPUT" | jq -c '
    select(.hook_event_name == "PostToolBatch")
  | select((.tool_calls | length) > 0)
  | { ts:        (now | todate),
      hook:      "post-tool-batch",
      sid:       (.session_id  // "-"),
      prompt_id: (.prompt_id   // "-"),
      n:         (.tool_calls | length),
      tools:     (.tool_calls | map(.tool_name // "?") | group_by(.)
                              | map({key: .[0], value: length}) | from_entries),
      mode:      (.permission_mode // "-"),
      effort:    (.effort.level    // "-") }
' 2>/dev/null)" || ROW=""

# Nothing to say is a legitimate outcome for EVERY gate above — a wrong event name, a payload with
# no tool_calls, or unparseable JSON. Only the last of those is an anomaly worth a marker; the other
# two ARE what inertness looks like, and marking them would turn a mis-registration on a live event
# from a silent no-op into a marker per tool call — the very flood the gate exists to prevent.
if [ -z "$ROW" ]; then
  if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then abstain "malformed-json"; fi
  exit 0
fi
case "$ROW" in '{'*) ;; *) exit 0 ;; esac       # never append anything that is not an object line

# R-5 (HOOK_CHAIN_COST): bash-execution.log is unbounded and that is a live defect. Do not mint a
# second one. Single-generation rotation, checked BEFORE the append so the live file cannot exceed
# the cap by more than one line.
ensure_dir
SIZE="$(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null || echo 0)"
case "$SIZE" in ''|*[!0-9]*) SIZE=0 ;; esac
if [ "$SIZE" -ge "$MAX_BYTES" ]; then mv -f "$LOG" "$LOG.1" 2>/dev/null || true; fi

printf '%s\n' "$ROW" >> "$LOG" 2>/dev/null || true
exit 0
