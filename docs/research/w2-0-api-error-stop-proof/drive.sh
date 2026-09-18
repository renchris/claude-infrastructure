#!/bin/bash
# T9 driver — the INTERACTIVE shape the plan actually asked for: streaming-json stdin held OPEN
# across the turn end, so the session is idle-with-a-live-input-stream rather than a one-shot that
# exits. $1 = arm label, $2 = seconds to hold stdin open after the prompt.
P="$(cd "$(dirname "$0")" && pwd)"
arm="$1"; hold="${2:-45}"
{
  printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Say exactly: OK"}]}}\n'
  sleep "$hold"
} | T9_ARM="$arm" CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude-tertiary}" \
    timeout $((hold + 60)) "$HOME/.claude/bin/claude-latest" \
      -p --input-format stream-json --output-format stream-json --verbose \
      --model claude-haiku-4-5-20251001 --strict-mcp-config --max-turns 1 \
      --settings "$P/cfg/settings.json" > "$P/stream.$arm.jsonl" 2> "$P/stderr.$arm.txt"
echo "arm $arm exited rc=$?"
