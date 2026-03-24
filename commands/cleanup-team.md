---
name: Cleanup Team
description: Gracefully shutdown all active teammates and clean up resources (worktrees, branches, team state)
allowed-tools: SendMessage,Bash,Read,Glob
---

# Cleanup All Teammates

Shut down all active teammates in the current team and clean up their resources.

## Steps

1. **List all active teammates** from current team context
2. **Send shutdown_request** to each teammate (parallel — all at once, don't wait between)
3. **Wait for shutdown_approved** from each (5-10 seconds)
4. **Report results**: which shut down, which timed out
5. **Clean up worktrees** (if any):
   ```bash
   git worktree list | grep /tmp/worktree
   # For each: git worktree remove <path>
   ```
6. **Clean up team state** (if all teammates confirmed shutdown):
   ```bash
   # Only if TeamDelete is available and all teammates are down
   TeamDelete
   ```

## Shutdown Protocol

For EACH active teammate, send:
```json
SendMessage(to: "<name>", message: {"type": "shutdown_request", "reason": "User-initiated cleanup via /cleanup-team"})
```

Send ALL shutdown_requests in a single response (parallel tool calls). Then wait for all responses.

## If Teammates Don't Respond

If any teammate doesn't send `shutdown_approved` within 10 seconds:
1. Flag as potential orphan
2. Show the user: "Teammate X didn't respond. Manual cleanup options:"
   - `tmux kill-pane` (if pane visible)
   - `rm -rf ~/.claude/teams/<team-name>` (filesystem cleanup)
   - Check: `ps aux | grep claude-versions | grep -v grep`

## After Cleanup

- Verify: `git worktree list` shows only main repo
- Verify: `git status` is clean
- Report: "N teammates shut down, M worktrees removed, team cleaned up"
