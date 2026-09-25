#!/bin/bash
# measure-context-f3.sh <account-config-dir>... — run `/context` once per F3 arm per account, in a fixture
# built exactly as run-f3.sh builds one (task S07, no plant), with the arm's exact --settings and no MCP.
# Prints the Memory Files table, which must list the situational lessons file in `control` only.
set -u
H=$(cd "$(dirname "$0")" && pwd)
G=${GATE_ROOT:-/tmp/tokeff-f3}
CLAUDE_BIN=${CLAUDE_BIN:-$HOME/.claude-280/node_modules/.bin/claude}
mkdir -p "$G/context"
CLAUDE_BIN=/usr/bin/true "$H/run-f3.sh" control S07-question 0 "${1:?config dir}" || exit 3
FX="$G/runs/S07-question/r0/fx"
for CCD in "$@"; do
  acct=$(basename "$CCD")
  for ARM in exclude control; do
    S=$(python3 -c 'import json,sys; s={} if sys.argv[1]=="control" else {"claudeMdExcludes":[sys.argv[2]]}; print(json.dumps(s))' \
      "$ARM" '**/.claude/rules/agent-operating-lessons-situational.md')
    out="$G/context/$acct-$ARM.context.txt"
    ( cd "$FX" && CLAUDE_CONFIG_DIR="$CCD" timeout 300 "$CLAUDE_BIN" -p --model claude-opus-5-5 \
        --strict-mcp-config --mcp-config '{"mcpServers":{}}' --settings "$S" "/context" > "$out" 2> "${out%.txt}.err" )
    echo "== $acct $ARM: $(grep -m1 '| Memory files' "$out")"
    sed -n '/### Memory Files/,/^### [^M]/p' "$out" | grep '^| [UP]' | sed "s#/private$FX#<fx>#; s#$FX#<fx>#"
  done
done
