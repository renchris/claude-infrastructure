#!/bin/bash
# X6 probe for PostToolUseFailure specifically: does a failing Bash call fire PostToolUseFailure
# (or PostToolUse), what does its payload carry, and does its additionalContext reach the model?
# The same dump hook is registered on BOTH events so whichever fires is recorded.
set -u
BIN=${1:-claude}
D=$(mktemp -d)
cat > "$D/dump.sh" <<H
#!/bin/bash
p=\$(cat); printf '%s\n' "\$p" >> "$D/all.jsonl"
printf '%s' "\$p" | jq -c '{hookSpecificOutput:{hookEventName:.hook_event_name, additionalContext:("PROBE-" + .hook_event_name + "-77")}}'
H
chmod +x "$D/dump.sh"
printf '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s/dump.sh"}]}],"PostToolUseFailure":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s/dump.sh"}]}]}}' "$D" "$D" > "$D/s.json"
cd "$D" && git init -q
"$BIN" --version
for cmd in 'ls /nonexistent-probe-dir-xyz' 'bash -c "echo some-stdout-text; echo some-stderr-text >&2; exit 3"'; do
  echo "== $cmd"
  "$BIN" -p --setting-sources '' --settings "$D/s.json" --model claude-haiku-4-5-20251001 --allowedTools Bash \
    --permission-mode acceptEdits --output-format stream-json --verbose \
    "Run exactly this shell command once: $cmd . It is expected to fail. Then if any token starting with PROBE- appears anywhere in your context, reply with exactly that token, else NONE." \
    </dev/null 2>/dev/null > "$D/out.jsonl"
  jq -c 'select(.type=="user") | .message.content[]? | select(.type=="tool_result") | {is_error, c:(.content|tostring|.[0:160])}' "$D/out.jsonl"
  printf 'model: '; tail -1 "$D/out.jsonl" | jq -r '.result'
done
echo '--- hook payloads'
jq -c '{hook_event_name, error:(.error|tostring|.[0:300]), keys:(keys)}' "$D/all.jsonl" 2>/dev/null
echo "dir=$D"
