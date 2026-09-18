#!/bin/bash
# T9 arm-1 driver — HERMETIC. Throwaway CLAUDE_CONFIG_DIR holding ONLY the hook under test, a dummy
# API key, and a local endpoint. No credentials, no quota, and nothing but the hook under test can
# manufacture a turn — which is the property the merged --settings rig lacked.
#   $1 arm label · $2 mock mode (ok|error) · $3 port · $4 seconds to hold stdin open
P="$(cd "$(dirname "$0")" && pwd)"
arm="$1"; mode="$2"; port="$3"; hold="${4:-120}"
: > "$P/mail.$arm.txt"
sed "s|MAILPATH|$P/mail.$arm.txt|; s|LOGPATH|$P/watch.$arm.txt|" "$P/watcher.tmpl.sh" > "$P/watcher.$arm.sh"
chmod +x "$P/watcher.$arm.sh"
mkdir -p "$P/cfg.$arm"
cat > "$P/cfg.$arm/settings.json" <<EOF
{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command",
  "command": "$P/watcher.$arm.sh", "asyncRewake": true, "timeout": 300,
  "rewakeMessage": "T9 ARM-$arm — watcher fired:", "rewakeSummary": "T9 arm $arm wake" } ] } ] } }
EOF
python3 "$P/mockapi.py" "$port" "$mode" "$P/mock.$arm.txt" >/dev/null 2>&1 &
echo $! > "$P/mock.$arm.pid"
sleep 2
{ printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Say exactly: OK"}]}}\n'
  sleep "$hold"
} | ANTHROPIC_API_KEY=sk-ant-dummy-t9probe ANTHROPIC_BASE_URL="http://127.0.0.1:$port" \
    CLAUDE_CONFIG_DIR="$P/cfg.$arm" \
    timeout $((hold + 60)) "$HOME/.claude/bin/claude-latest" \
      -p --input-format stream-json --output-format stream-json --verbose \
      --model claude-haiku-4-5-20251001 --strict-mcp-config --max-turns 4 \
      > "$P/stream.$arm.jsonl" 2> "$P/stderr.$arm.txt"
rc=$?
kill "$(cat "$P/mock.$arm.pid")" 2>/dev/null
echo "arm $arm (mode=$mode) exited rc=$rc"
