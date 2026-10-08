#!/usr/bin/env bash
# cell.sh <arm> <qid> <rep> <out.jsonl>   arm = model@effort (effort may be empty)
arm=$1 qid=$2 rep=$3 out=$4
D=/tmp/haiku55-measure/retr; C=$D/corpus3b3; BIN=$HOME/.claude-293/node_modules/.bin/claude
model=${arm%@*}; effort=${arm#*@}
line=$(awk -F'\t' -v q="$qid" '$1==q' "$D/questions.tsv"); q=$(printf '%s' "$line" | cut -f2); truth=$(printf '%s' "$line" | cut -f3)
prompt="You are a codebase retrieval agent. The current directory is a repository. Find the exact location that answers the question, using the search and read tools; do not guess. Question: $q
End your reply with one final line exactly of the form: ANSWER: <relative/path>:<line>"
t0=$(date +%s)
res=$(cd "$C" && CLAUDE_CONFIG_DIR=$HOME/.claude-quaternary DISABLE_AUTOUPDATER=1 perl -e 'alarm 600; exec @ARGV' "$BIN" -p "$prompt" \
  --model "$model" ${effort:+--effort "$effort"} --tools "Read,Grep,Glob" --setting-sources "" --strict-mcp-config \
  --no-session-persistence --output-format json 2>/dev/null </dev/null | grep '^{')
printf '%s' "$res" | jq -c --arg arm "$arm" --arg qid "$qid" --arg rep "$rep" --arg truth "$truth" --argjson wall "$(( $(date +%s) - t0 ))" '
  (.result // "") as $r | ($r | [scan("ANSWER:\\s*`?([^\\s`]+):([0-9]+)")] | last) as $a |
  {arm:$arm, qid:$qid, rep:$rep, truth:$truth, answer:(if $a then ($a[0]+":"+$a[1]) else null end),
   is_error, stop_reason, num_turns, wall:$wall, served:(.modelUsage|keys),
   output_tokens:.usage.output_tokens, input_tokens:.usage.input_tokens,
   cache_read:.usage.cache_read_input_tokens, cache_create:.usage.cache_creation_input_tokens, cost_usd:.total_cost_usd}' >> "$out" \
  || echo "{\"arm\":\"$arm\",\"qid\":\"$qid\",\"rep\":\"$rep\",\"truth\":\"$truth\",\"answer\":null,\"failed\":true}" >> "$out"
