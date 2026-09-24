| event | matcher | script (repo `hooks/`) | emits to model | visible inj. 14d | inj. $ own / @5.5 | forced turns | forced $ own / @5.5 | timeouts |
|---|---|---|---|---:|---:|---:|---:|---:|
| PostToolUse | Write|Edit|MultiEdit | post-file-edit.sh | - |  |  |  |  |  |
| PostToolUse | Write|Edit|MultiEdit | plan-index-update.sh | - |  |  |  |  |  |
| PostToolUse | Write|Edit|MultiEdit | validate-plan-structure.sh | additionalContext,exit2 | 53 | 0.59 / 0.34 |  |  |  |
| PostToolUse | Write|Edit|MultiEdit | plan-version-commit.sh | - |  |  |  |  |  |
| PostToolUse | Bash | log-bash.sh | - |  |  |  |  |  |
| PostToolUse | Bash | waiting-recycle.sh | additionalContext,decision:block,systemMessage,exit2 | 43 | 0.47 / 0.25 | 12 | 21 / 9 |  |
| PostToolUse | Bash | relay-verbatim.sh | additionalContext | 244 | 1.94 / 1.13 |  |  |  |
| PostToolUse | TaskCreate|TaskUpdate | task-mutation-index.sh | - |  |  |  |  |  |
| PostToolUse | * | teammate-checkpoint.sh | - |  |  |  |  | 11 |
| PostToolUse | ExitPlanMode | plan-pin-session.sh | - |  |  |  |  |  |
| PostToolUse | * | cc-permission-beacon.sh | - |  |  |  |  | 1 |
| PostToolUse | * | mailbox-drain.sh | additionalContext,systemMessage | 4112 | 96.34 / 50.24 |  |  | 39 |
| PostToolUse | Bash|Write|Edit|MultiEdit | memory-index-drain.sh | additionalContext | 44 | 0.64 / 0.35 |  |  |  |
| PostToolUse | mcp__ms365__get-mail-message.* | mail-images-auto.sh | additionalContext |  |  |  |  |  |
| WorktreeCreate | * | worktree-setup.sh | - |  |  |  |  |  |
| TeammateIdle | * | teammate-auto-shutdown.sh | exit2 |  |  |  |  | 14 |
| FileChanged | /Users/chrisren/.claude/file-watch-pa… | file-changed.sh | - |  |  |  |  |  |
| FileChanged | * | file-changed.sh | - |  |  |  |  |  |
| PostToolBatch | * | post-tool-batch.sh | - |  |  |  |  | 12 |
| PermissionRequest | Bash | notify.sh | - |  |  |  |  | 30 |
| PermissionRequest | AskUserQuestion | notify.sh | - |  |  |  |  | 30 |
| PermissionRequest | ExitPlanMode | notify.sh | - |  |  |  |  | 30 |
| PermissionRequest | * | cc-permission-beacon.sh | - |  |  |  |  | 1 |
| PreCompact | auto | `date '+[%Y-%m-%d %H:%M:%S] Auto-compact triggere` | - |  |  |  |  |  |
| PreCompact | auto | dod-persist.sh | additionalContext,exit2 | 683 | 29.66 / 13.05 |  |  | 89 |
| PreCompact | manual | `date '+[%Y-%m-%d %H:%M:%S] Manual compact trigge` | - |  |  |  |  |  |
| PostToolUseFailure | Bash | log-bash.sh | - |  |  |  |  |  |
| PostToolUseFailure | * | mailbox-drain.sh | additionalContext,systemMessage | 4112 | 96.34 / 50.24 |  |  | 39 |
| PostToolUseFailure | * | cc-permission-beacon.sh | - |  |  |  |  | 1 |
| PreToolUse | Bash | smart-bash-allowlist.sh | - |  |  |  |  | 27 |
| PreToolUse | Bash | curl-gate-scope.sh | - |  |  |  |  | 16 |
| PreToolUse | Bash | validate-bash.sh | additionalContext,permissionDecision |  |  |  |  | 349 |
| PreToolUse | Bash | git-worktree-guard.sh | exit2 |  |  |  |  | 8 |
| PreToolUse | Bash | keychain-guard.sh | permissionDecision |  |  |  |  | 2 |
| PreToolUse | Bash | rm-safe-allowlist.sh | permissionDecision |  |  |  |  | 15 |
| PreToolUse | Bash | ship-rail-push-allow.sh | permissionDecision |  |  |  |  | 13 |
| PreToolUse | Bash | qos-rewrite.sh | permissionDecision |  |  |  |  | 9 |
| PreToolUse | Bash | coldcompile-admit.sh | permissionDecision |  |  |  |  | 6 |
| PreToolUse | Bash | pr-gate.sh | permissionDecision |  |  |  |  |  |
| PreToolUse | Write|Edit|MultiEdit | backup-before-write.sh | additionalContext,permissionDecision | 305 | 4.23 / 2.42 |  |  | 1 |
| PreToolUse | Write|Edit|MultiEdit | check-edit-boundary.sh | permissionDecision |  |  |  |  | 1 |
| PreToolUse | Write|Edit|MultiEdit | plan-agent-teams-default.sh | additionalContext,permissionDecision | 337 | 6.48 / 3.69 |  |  | 4 |
| PreToolUse | Agent | agent-teams-enforce.sh | additionalContext,permissionDecision | 483 | 8.50 / 4.43 |  |  | 56 |
| PreToolUse | Agent | frontier-spawn-gate.sh | exit2 |  |  |  |  |  |
| PreToolUse | mcp__ms365__send-mail|mcp__ms365__rep… | enforce-email-formatting.py | additionalContext,decision:block,permissionDecision | 34 | 4.09 / 2.29 |  |  |  |
| PreToolUse | AskUserQuestion | cc-unattended-ask-guard.sh | exit2 |  |  |  |  |  |
| PreToolUse | WebFetch|WebSearch | web-entrypoint-ladder.sh (NOT in repo: real file in ~/.claude/hooks) | additionalContext | 167 | 1.70 / 0.96 |  |  |  |
| Notification | permission_prompt | notify.sh | - |  |  |  |  | 30 |
| Notification | permission_prompt | push-critical.sh | - |  |  |  |  |  |
| Notification | elicitation_dialog | notify.sh | - |  |  |  |  | 30 |
| Notification | elicitation_dialog | push-critical.sh | - |  |  |  |  |  |
| Notification | idle_prompt | push-critical.sh | - |  |  |  |  |  |
| TaskCompleted | * | task-quality-gate.sh | exit2 |  |  |  |  |  |
| PermissionDenied | * | permission-denied.sh | - |  |  |  |  |  |
| CwdChanged | * | cwd-changed.sh | - |  |  |  |  |  |
| UserPromptSubmit | * | handed-off-session-guard.sh | exit2 |  |  |  |  | 5 |
| UserPromptSubmit | * | cache-expiry-warning.sh | additionalContext | 1186 | 6.30 / 3.16 |  |  |  |
| UserPromptSubmit | * | memory-nudge.sh | additionalContext | 434 | 26.67 / 13.86 |  |  | 31 |
| UserPromptSubmit | * | handoff-intent-nudge.sh | additionalContext,exit2 | 736 | 16.52 / 7.86 |  |  | 57 |
| UserPromptSubmit | * | research-precognition-nudge.sh | additionalContext | 419 | 7.81 / 3.93 |  |  |  |
| UserPromptSubmit | * | session-beat.sh | - |  |  |  |  | 11 |
| UserPromptSubmit | * | mailbox-drain.sh | additionalContext,systemMessage | 4112 | 96.34 / 50.24 |  |  | 39 |
| Stop | * | notify.sh | - |  |  |  |  | 30 |
| Stop | * | cache-expiry-tracker.sh | - |  |  |  |  | 1 |
| Stop | * | teammate-checkpoint.sh | - |  |  |  |  | 11 |
| Stop | * | session-continue.sh | additionalContext,decision:block,systemMessage,exit2 | 3682 | 154.46 / 67.50 | 1922 | 2403 / 1084 | 2509 |
| Stop | * | anti-deference-nudge.sh | decision:block | 359 | 6.58 / 3.44 | 154 | 244 / 120 | 54 |
| Stop | * | completion-assert.sh | decision:block,exit2 | 577 | 10.04 / 5.41 | 256 | 356 / 169 | 1439 |
| Stop | * | dispatch-assert.sh | decision:block | 44 | 0.89 / 0.47 | 21 | 37 / 19 | 20 |
| Stop | * | boundary-handoff.sh | additionalContext,decision:block,systemMessage,exit2 | 243 | 1.47 / 0.84 | 104 | 151 / 71 | 1395 |
| Stop | * | operator-readout.sh | decision:block,systemMessage,exit2 |  |  |  |  | 2731 |
| Stop | * | session-beat.sh | - |  |  |  |  | 11 |
| Stop | * | goal-inert-watch.sh | additionalContext,decision:block,systemMessage |  |  |  |  | 4 |
| Stop | * | handoff-claim-assert.sh | decision:block,exit2 |  |  |  |  |  |
| Stop | * | cc-permission-beacon.sh | - |  |  |  |  | 1 |
| StopFailure | * | stop-failure-marker.sh | - |  |  |  |  |  |
| SessionEnd | * | session-end.sh | - |  |  |  |  |  |
| SessionEnd | * | session-deregister.sh | - |  |  |  |  |  |
| SessionEnd | * | session-index-end.sh | - |  |  |  |  |  |
| SessionEnd | * | session-save-id.sh | - |  |  |  |  |  |
| SessionEnd | * | harvest-skill-end.sh | - |  |  |  |  |  |
| SessionEnd | * | live-session-registry.sh | - |  |  |  |  | 5 |
| SessionEnd | * | cc-permission-beacon.sh | - |  |  |  |  | 1 |
| SessionStart | * | session-start.sh | additionalContext | 961 | 2.48 / 1.12 |  |  | 20 |
| SessionStart | * | setup-plan-symlinks.sh | additionalContext | 927 | 2.75 / 1.23 |  |  | 6 |
| SessionStart | * | setup-task-symlinks.sh | additionalContext | 894 | 1.43 / 0.64 |  |  | 9 |
| SessionStart | * | pre-session-validate.sh | - |  |  |  |  | 9 |
| SessionStart | * | lead-crash-watchdog.sh | - |  |  |  |  | 2 |
| SessionStart | * | session-register.sh | - |  |  |  |  | 5 |
| SessionStart | * | activation-watch.sh | additionalContext | 848 | 4.19 / 1.91 |  |  | 16 |
| SessionStart | * | dod-persist.sh | additionalContext,exit2 | 683 | 29.66 / 13.05 |  |  | 89 |
| SessionStart | * | desk-brief-inject.sh | additionalContext | 5 | 1.75 / 0.70 |  |  | 9 |
| SessionStart | * | mailbox-wake-arm.sh | exit2 |  |  |  |  |  |
| SessionStart | * | escalation-watch.sh | additionalContext |  |  |  |  | 19 |
| SessionStart | * | accounts-board.sh | additionalContext,systemMessage |  |  |  |  |  |
| SessionStart | * | session-index-start.sh | additionalContext | 929 | 1.50 / 0.68 |  |  | 27 |
| SessionStart | * | config-mirror-assert.sh | additionalContext | 950 | 86.82 / 37.75 |  |  | 3 |
| SessionStart | * | frontier-status.sh | - | 892 | 4.92 / 2.20 |  |  | 7 |
| SessionStart | * | live-session-registry.sh | - |  |  |  |  | 5 |
| SessionStart | * | mailbox-drain.sh | additionalContext,systemMessage | 4112 | 96.34 / 50.24 |  |  | 39 |
| SessionStart | * | net-context-stamp.sh (NOT in repo: real file in ~/.claude/hooks) | additionalContext |  |  |  |  |  |
| InstructionsLoaded | session_start | instructions-loaded.sh | - |  |  |  |  |  |
| PostCompact | * | post-compact.sh | - |  |  |  |  |  |
| ConfigChange | * | config-change.sh | - |  |  |  |  |  |
