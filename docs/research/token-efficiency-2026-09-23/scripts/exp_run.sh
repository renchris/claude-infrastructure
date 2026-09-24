#!/bin/bash
# exp_run.sh <label> <dir> [extra claude args...]
# One bounded headless one-word run for the token-efficiency cache experiments.
# Flags: -p --output-format json --model claude-opus-5-5 --setting-sources project,local (suppresses user hooks/settings).
# Writes measure/exp/<label>.json and prints the usage block.
set -u
label=$1; dir=$2; shift 2
OUT=/Users/chrisren/Development/.worktrees/wt-feat-token-efficiency-2026-09-23/docs/research/token-efficiency-2026-09-23/measure/exp
mkdir -p "$OUT" "$dir"
cd "$dir" || exit 2
/Users/chrisren/.claude-280/node_modules/.bin/claude -p --output-format json --model claude-opus-5-5 \
    --setting-sources project,local "$@" > "$OUT/$label.json" 2> "$OUT/$label.stderr"
echo "rc=$? label=$label"
python3 - "$OUT/$label.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); u=d.get('usage',{})
print(json.dumps({'result':d.get('result'),'session_id':d.get('session_id'),'num_turns':d.get('num_turns'),
  'usage':{k:u.get(k) for k in ['input_tokens','cache_creation_input_tokens','cache_read_input_tokens','output_tokens','cache_creation']},
  'modelUsage':d.get('modelUsage')}))
PY
