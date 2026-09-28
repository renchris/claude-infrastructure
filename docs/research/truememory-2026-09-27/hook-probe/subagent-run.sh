#!/bin/bash
# X6 subagent arm: does a PostToolUse additionalContext emitted for a SUBAGENT's Bash call land in
# that subagent's context? Instrument: the subagent's own transcript (<sid>/subagents/*.jsonl) must
# carry the marker in a hook-context attachment. The model's self-report is not used (Haiku refuses
# nested "list tokens in your context" asks as injection).
set -u
BIN=${1:-claude}
D=$(mktemp -d); N=$(date +%s)$$
cat > "$D/ptu.sh" <<H
#!/bin/bash
p=\$(cat); printf '%s\n' "\$p" >> "$D/payloads.jsonl"
printf '%s' "\$p" | jq -c --arg n "$N" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:("PROBE-SUB-" + \$n)}}'
H
chmod +x "$D/ptu.sh"
printf '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s/ptu.sh"}]}]}}' "$D" > "$D/s.json"
cd "$D" && git init -q
"$BIN" --version
"$BIN" -p --setting-sources '' --settings "$D/s.json" --model claude-haiku-4-5-20251001 --allowedTools 'Bash(echo:*) Agent Task' \
  --permission-mode acceptEdits --output-format stream-json --verbose \
  'Use the Agent tool to spawn a general-purpose subagent whose task is: run the shell command "echo hello" and report its output. Then tell me what it reported.' \
  </dev/null 2>/dev/null > "$D/out.jsonl"
SID=$(head -1 "$D/out.jsonl" | jq -r '.session_id')
echo "sid=$SID"
jq -c '{agent_id, tool_use_id}' "$D/payloads.jsonl"
find "$HOME"/.claude*/projects -path "*$SID*" -name '*.jsonl' 2>/dev/null | while IFS= read -r f; do
  printf '%s: marker-lines=%s\n' "${f#"$HOME"/}" "$(grep -c "PROBE-SUB-$N" "$f")"
  grep "PROBE-SUB-$N" "$f" | jq -c '{type, at:(.attachment.type // .message.role // null)}' 2>/dev/null | head -3
done
