#!/bin/bash
# X6 delivery probe for the TOOL-event channels Wave B uses (#6, #10). Four arms, each a marker
# token the model is asked to report back:
#   ptu    PostToolUse(Bash) emitting updatedToolOutput AND additionalContext in ONE object (#6 combined case)
#   ptuf   PostToolUseFailure(Bash) additionalContext, hookEventName echoed from the payload (#6 log-bash arm)
#   pre    PreToolUse(Write) emitting updatedInput AND additionalContext in ONE object (#10 via _bbw_out)
#   sub    the ptu hook, but the Bash call is made by a SUBAGENT (does a subagent's tool result carry it?)
# Each hook also dumps its raw payload to $D/<arm>-payload.json (ptuf's shows what `.error` holds).
# Usage: bash tool-run.sh [claude-binary]. Haiku keeps it cheap. --setting-sources '' keeps the
# operator's own hooks out of the arm, so only the probe hook fires.
set -u
BIN=${1:-claude}
D=$(mktemp -d); N=$(date +%s)$$
cat > "$D/ptu.sh" <<H
#!/bin/bash
p=\$(cat); printf '%s' "\$p" > "$D/\${PROBE_ARM:-ptu}-payload.json"
printf '%s' "\$p" | jq -c --arg n "$N" '{hookSpecificOutput:{hookEventName:(.hook_event_name // "PostToolUse"),
  updatedToolOutput:(.tool_response + {stdout:("UPDATED-" + \$n + " " + (.tool_response.stdout // ""))}),
  additionalContext:("PROBE-PTU-" + \$n)}}'
H
cat > "$D/ptuf.sh" <<H
#!/bin/bash
p=\$(cat); printf '%s' "\$p" > "$D/ptuf-payload.json"
printf '%s' "\$p" | jq -c --arg n "$N" '{hookSpecificOutput:{hookEventName:.hook_event_name, additionalContext:("PROBE-PTUF-" + \$n)}}'
H
cat > "$D/pre.sh" <<H
#!/bin/bash
p=\$(cat); printf '%s' "\$p" > "$D/pre-payload.json"
printf '%s' "\$p" | jq -c --arg n "$N" '{hookSpecificOutput:{hookEventName:"PreToolUse", updatedInput:.tool_input, additionalContext:("PROBE-PRE-" + \$n)}}'
H
chmod +x "$D"/*.sh
printf '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s/ptu.sh"}]}]}}' "$D" > "$D/s-ptu.json"
printf '{"hooks":{"PostToolUseFailure":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s/ptuf.sh"}]}]}}' "$D" > "$D/s-ptuf.json"
printf '{"hooks":{"PreToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"%s/pre.sh"}]}]}}' "$D" > "$D/s-pre.json"
cp "$D/s-ptu.json" "$D/s-sub.json"
cd "$D" && git init -q
"$BIN" --version
ASK='Then, if any token starting with PROBE- or UPDATED- appears anywhere in your context (including tool results), reply with exactly those tokens separated by spaces, else reply NONE.'
run() { # <arm> <allowed-tools> <task>   (ARMS="ptu sub" limits the arms run)
  case " ${ARMS:-ptu ptuf pre sub} " in *" $1 "*) ;; *) return 0 ;; esac
  printf '%-5s ' "$1"
  "$BIN" -p --setting-sources '' --settings "$D/s-$1.json" --model claude-haiku-4-5-20251001 \
    --allowedTools "$2" --permission-mode acceptEdits "$3 $ASK" </dev/null 2>/dev/null | tail -1
}
run ptu  'Bash(echo:*)' 'Run the shell command: echo hello.'
run ptuf 'Bash(ls:*)'   'Run the shell command: ls /nonexistent-probe-dir-xyz (it will fail; that is expected).'
run pre  'Write'        "Use the Write tool to create $D/probe.txt containing the word hi."
run sub  'Bash(echo:*) Agent Task' 'Use the Agent tool to spawn a general-purpose subagent with this task: "Run the shell command: echo hello. Then list every token starting with PROBE- or UPDATED- that appears anywhere in your own context, including text attached after the tool result, and return exactly those tokens." Report exactly the tokens the subagent returned.'
echo "nonce=$N dir=$D"
for f in "$D"/*-payload.json; do [ -f "$f" ] && { printf '%s: ' "${f##*/}"; jq -c '{hook_event_name, error, tool_use_id, agent_id}' "$f" 2>/dev/null | cut -c1-300; }; done
