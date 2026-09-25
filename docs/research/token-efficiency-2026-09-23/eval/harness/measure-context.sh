#!/bin/bash
# measure-context.sh <account-config-dir>... — run `/context` once per arm per account in a scratch
# git dir set up exactly as run.sh sets up a fixture, and print the Memory Files table. Proves the
# user memory files are excluded and the arm's files load as Project memory on every account.
set -u
G=${GATE_ROOT:-/tmp/tokeff-gate}
CLAUDE_BIN=${CLAUDE_BIN:-$HOME/.claude-280/node_modules/.bin/claude}
mkdir -p "$G/context"
MCP=(); [ "${GATE_NO_MCP:-0}" = 1 ] && MCP=(--strict-mcp-config --mcp-config '{"mcpServers":{}}')  # as run.sh
for CCD in "$@"; do
  acct=$(basename "$CCD")
  for ARM in ${GATE_ARMS:-full slim}; do
    D="$G/context/$acct-$ARM"
    rm -rf "${D:?}"; mkdir -p "$D/.claude/rules"; git init -q -b main "$D"
    cp "$G/arms/$ARM/CLAUDE.md" "$D/.claude/CLAUDE.md"
    cp "$G/arms/$ARM/rules/"*.md "$D/.claude/rules/"
    SETTINGS=$(python3 -c 'import json,sys; print(json.dumps({"claudeMdExcludes": sys.argv[1:]}))' \
      "$CCD/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "$HOME/.claude/rules/00-mission-board.md" \
      "$HOME/.claude/rules/agent-operating-lessons.md")
    ( cd "$D" && CLAUDE_CONFIG_DIR="$CCD" timeout 300 "$CLAUDE_BIN" -p --model claude-opus-5-5 ${MCP[@]+"${MCP[@]}"} \
        --settings "$SETTINGS" "/context" > "$D.context.txt" 2> "$D.context.err" )
    echo "== $acct $ARM: $(grep -m1 '| Memory files' "$D.context.txt")"
    sed -n '/### Memory Files/,/^### [^M]/p' "$D.context.txt" | grep '^| [UP]' | sed "s#/private$D#<fx>#; s#$D#<fx>#"
  done
done
