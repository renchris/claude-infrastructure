#!/usr/bin/env bash
# Per-file reads/edits/tests, derived from the agent's OWN tool calls in the stream-json log.
# This is why the evidence block cannot be fabricated by the model: the harness reads the log.
set -euo pipefail
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
       | [.name, (.input.file_path // .input.path // "")] | @tsv' \
  "/workspace/logs/${RUN_TOKEN}-${SLUG}.jsonl" |
awk -F'\t' '$2!=""{ if($1=="Read")r[$2]++; else if($1~/Edit|Write/)e[$2]++; else if($1=="Bash")t[$2]++ }
  END{ printf "%-55s %6s %6s %6s\n","file","reads","edits","tests";
       for(f in r) printf "%-55s %6d %6d %6d\n", f, r[f], e[f], t[f] }'
