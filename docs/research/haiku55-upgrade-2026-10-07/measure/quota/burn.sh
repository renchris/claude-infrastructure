#!/usr/bin/env bash
# burn.sh <model> <effort> <seconds> <parallel> <index.jsonl> <config_dir>
# Each worker loops headless long-output calls until the deadline; one summary line per call.
model=$1 effort=$2 secs=$3 par=$4 idx=$5 cfgdir=$6
BIN=$HOME/.claude-293/node_modules/.bin/claude
end=$(( $(date +%s) + secs ))
worker() {
  local w=$1 n=0 d; d=$(mktemp -d /tmp/haiku55-burn.XXXX)
  while [ "$(date +%s)" -lt "$end" ]; do
    n=$((n+1))
    out=$(cd "$d" && CLAUDE_CONFIG_DIR="$cfgdir" CLAUDE_CODE_MAX_OUTPUT_TOKENS=32000 DISABLE_AUTOUPDATER=1 \
      "$BIN" -p "Seed $w-$n-$RANDOM. Write a long original encyclopedia-style article, at least 9000 words, on an invented island nation: geography, history by century, economy, cuisine, music, and 40 notable people with a paragraph each. Plain prose, no preamble, do not stop early." \
      --model "$model" ${effort:+--effort "$effort"} --tools "" --setting-sources "" --strict-mcp-config \
      --no-session-persistence --output-format json 2>/dev/null </dev/null)
    printf '%s' "$out" | grep '^{' | jq -c --arg w "$w" --arg arm "$model@$effort" '{arm:$arm, w:$w, t:now, is_error, stop_reason, duration_ms,
      served:(.modelUsage|keys), output_tokens:.usage.output_tokens, cache_create:.usage.cache_creation_input_tokens,
      cache_read:.usage.cache_read_input_tokens, input:.usage.input_tokens, cost_usd:.total_cost_usd}' >> "$idx" 2>/dev/null
  done
  rm -rf "$d"
}
for i in $(seq 1 "$par"); do worker "$i" & done
wait
