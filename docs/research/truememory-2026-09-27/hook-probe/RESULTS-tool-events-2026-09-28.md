# X6 live delivery probe — tool-event channels (Wave B, 2026-09-28)

Binary: Claude Code 2.1.278, `claude -p --setting-sources ''`, Haiku 4.5. Scripts beside this file.

| Arm (script) | Hook output | Delivered to the model? |
|---|---|---|
| `tool-run.sh` ptu | PostToolUse(Bash), ONE object with `updatedToolOutput` + `additionalContext` | yes, both (model echoed `UPDATED-<n>` and `PROBE-PTU-<n>`) |
| `tool-run.sh` pre | PreToolUse(Write), ONE object with `updatedInput` + `additionalContext` | yes (`PROBE-PRE-<n>`) |
| `failure-run.sh` | PostToolUseFailure(Bash), `hookEventName` echoed from the payload | yes, on `ls /nonexistent` (exit 1) and `exit 3` |
| `subagent-run.sh` | PostToolUse(Bash) inside a subagent | yes: a `hook_additional_context` attachment in `<sid>/subagents/agent-<id>.jsonl`, none in the main transcript |

Payload facts the #6 hooks rely on:
- PostToolUseFailure keys: cwd, duration_ms, error, hook_event_name, is_interrupt, permission_mode, prompt_id,
  session_id, tool_input, tool_name, tool_use_id, transcript_path. No `tool_response`.
- `.error` is `Exit code N\n` followed by the command's stdout and stderr, so a scan of `.error` sees the output.
- A subagent's PostToolUse payload carries `agent_id`; the main thread's does not.
- Attachment shape for the delivery join: `{"type":"hook_additional_context","content":"[\"<text>\"]",
  "hookName":"PostToolUse:Bash","toolUseID":"toolu_…","hookEvent":"PostToolUse"}`.

The first `tool-run.sh` ptuf arm read NONE because its `--allowedTools 'Bash(ls:*)'` call never ran (no
payload was dumped); `failure-run.sh` with `--allowedTools Bash` is the valid arm.

**Re-run on Claude Code 2.1.280** (`~/.claude-280/node_modules/.bin/claude`, the binary #35 runs on because
2.1.278 refuses `claude-opus-5-5`): all four arms delivered the same way: ptu (`UPDATED-` + `PROBE-PTU-`),
pre (`PROBE-PRE-`), PostToolUseFailure (both commands), and the subagent attachment in `subagents/agent-*.jsonl`.
