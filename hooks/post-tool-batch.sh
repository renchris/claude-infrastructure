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
# COST: two execs in the steady state (jq, and `stat` for the rotation check), plus the one fork that
# slurps stdin. The timestamp is produced INSIDE the jq program (`now|todate`) rather than by a
# `date` fork, for the reason HOOK_CHAIN_COST § 2.1 measures: process creation, not interpretation,
# is what the chain costs. stdin is the one place a fork beats the builtin — see the read below.
#
# Env seams (tests): POST_TOOL_BATCH_LOG · POST_TOOL_BATCH_MAX_BYTES
set -uo pipefail

LOG="${POST_TOOL_BATCH_LOG:-$HOME/.claude/logs/tool-batch-census.jsonl}"
MAX_BYTES="${POST_TOOL_BATCH_MAX_BYTES:-4194304}"   # 4 MiB, one generation kept

# `$(</dev/stdin)`, NOT the `read -d ''` builtin (2026-10-04, docs/research/concurrency-scale-2026-10-04
# fix row 12). The builtin forks nothing, but on a pipe it reads ONE BYTE PER SYSCALL, so its cost
# grows with the payload: measured at load ~98, a 64 KB payload took ~30 ms and 256 KB ~150 ms.
# `$(<file)` is the shell's own block read: one fork, no exec (so not `$(cat)` either), ~7 ms at any
# size, and the same under /bin/bash 3.2. Break-even is near 10 KB. This hook receives the WHOLE batch,
# every call's input and result: over one sampled hour a single Read result ran p50 24 KB, p90
# 234 KB, max 341 KB, and this hook was being cancelled at its 10 s budget. `bytes` in the census
# row below records what actually arrives, so the next reading is a measurement.
# Guarded on fd 0 being open: with stdin CLOSED the substitution's own pipe lands on fd 0, so
# /dev/stdin would name that pipe and the read would wait on itself forever. `[ -e /dev/fd/0 ]`
# is the probe that works (`: <&0` reports success on a closed fd in bash 3.2).
INPUT=""
if [ -e /dev/fd/0 ]; then INPUT="$(</dev/stdin)" || INPUT=""; fi
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
#
# THE AGENT JOIN (fix row 11, docs/research/concurrency-scale-2026-10-04/d-telemetry-gaps.md §2.5-2.6),
# in the same jq call, so it adds 0 forks. `tuids` are the batch's tool_use_ids (each one greps to its
# subagent transcript offline; no match = the lead's own call). `cmd_h` is a hash of each Bash call's
# command: scripts/lib/capacity-attrib.py computes the SAME `len:poly31` value from the eval body of
# every live tool shell it samples, so a CPU sample joins to a tool_use_id and from there to an agent.
# jq has no sha builtin, hence the polynomial over the first 4096 code points plus the length.
# `agent_id` is present in payloads from inside in-process subagents (measured on validate-bash's
# decision log); a lead's own batch reads "-".
ROW="$(printf '%s' "$INPUT" | jq -c --argjson bytes "${#INPUT}" '
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
      effort:    (.effort.level    // "-"),
      bytes:     $bytes,
      agent_id:  (.agent_id // "-"),
      tuids:     (.tool_calls | map(.tool_use_id // "-")),
      cmd_h:     [ .tool_calls[] | select(.tool_name == "Bash")
                   | (.tool_input.command // "" | tostring | explode) as $e
                   | "\($e | length):\($e[:4096] | reduce .[] as $c (0; (. * 31 + $c) % 4294967296))" ] }
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
