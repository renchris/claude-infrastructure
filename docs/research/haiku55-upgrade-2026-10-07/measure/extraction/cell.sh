#!/usr/bin/env bash
# cell.sh <arm> <file> <rep> <out.jsonl>
arm=$1 f=$2 rep=$3 out=$4
C=/tmp/haiku55-measure/retr/corpus3b3; BIN=$HOME/.claude-293/node_modules/.bin/claude
model=${arm%@*}; effort=${arm#*@}
prompt="Extract every environment variable that the file below reads WITH A DEFAULT, in exactly these two forms only: the shell form \${NAME:-default} and the Python form os.environ.get(\"NAME\", \"default\"). Give one entry per distinct (name, default) pair; if the same name appears with two different defaults, give both. Copy each default verbatim, exactly as written between ':-' and the matching closing brace (for Python, the string literal's contents). Ignore every other form (\${NAME}, \${NAME-x}, \${NAME:=x}, \${NAME:+x}, plain \$NAME). Reply with ONLY a JSON array of objects {\"name\": ..., \"default\": ...}.

FILE: $f
-----
$(cat "$C/$f")
-----"
t0=$(date +%s)
res=$(cd /tmp && CLAUDE_CONFIG_DIR=$HOME/.claude-quaternary DISABLE_AUTOUPDATER=1 perl -e 'alarm 900; exec @ARGV' "$BIN" -p "$prompt" \
  --model "$model" ${effort:+--effort "$effort"} --tools "" --setting-sources "" --strict-mcp-config \
  --no-session-persistence --output-format json 2>/dev/null </dev/null | grep '^{')
printf '%s' "$res" | jq -c --arg arm "$arm" --arg f "$f" --arg rep "$rep" --argjson wall "$(( $(date +%s) - t0 ))" '
  {arm:$arm, file:$f, rep:$rep, result:.result, is_error, stop_reason, wall:$wall, served:(.modelUsage|keys),
   output_tokens:.usage.output_tokens, input_tokens:.usage.input_tokens, cache_read:.usage.cache_read_input_tokens,
   cache_create:.usage.cache_creation_input_tokens, cost_usd:.total_cost_usd}' >> "$out" \
  || echo "{\"arm\":\"$arm\",\"file\":\"$f\",\"rep\":\"$rep\",\"failed\":true}" >> "$out"
