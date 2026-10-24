#!/bin/bash
# One probe call on next3: static context on stdin, no tools, no settings/hooks/MCP, no
# session persistence. Appends the result JSON (one line) to /tmp/w2probe/calls.jsonl.
set -u
B=/Users/chrisren/.claude-293/node_modules/.bin/claude
cd /tmp/w2probe/cwd || exit 1
out=$(env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin \
  TERM=dumb LANG=en_US.UTF-8 CLAUDE_CONFIG_DIR="$HOME/.claude-tertiary" \
  "$B" -p --model claude-opus-5-5 --effort low --tools "" --setting-sources "" \
  --strict-mcp-config --disable-slash-commands --no-session-persistence \
  --system-prompt "You are a terse echo bot. Always reply with exactly one character." \
  --output-format json < /tmp/w2probe/context.txt 2>/tmp/w2probe/err.$$)
rc=$?
if [ $rc -ne 0 ] || [ -z "$out" ]; then
  printf '{"ts":"%s","rc":%d,"err":%s}\n' "$(date +%s)" "$rc" \
    "$(head -c 400 /tmp/w2probe/err.$$ | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    >> /tmp/w2probe/calls.jsonl
else
  printf '%s\n' "$out" | python3 -c 'import json,sys,time; d=json.loads(sys.stdin.read()); d["ts"]=time.time(); d["rc"]=0; print(json.dumps(d))' >> /tmp/w2probe/calls.jsonl
fi
rm -f /tmp/w2probe/err.$$
