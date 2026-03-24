#!/bin/bash
# Claude Code shell integration — add to ~/.zshrc

# Main entrypoint: auto-update + task list persistence
claude() {
    CLAUDE_CODE_TASK_LIST_ID="$(basename "$(pwd)")" claude-latest "$@"
}

# Plan mode with extended thinking
alias claude-plan='claude --permission-mode plan --append-system-prompt "ultrathink"'

# Auto mode (research preview, March 2026)
# alias claude-auto='claude --permission-mode auto'

# Second isolated Claude instance
alias claude2="CLAUDE_CONFIG_DIR=$HOME/.claude-secondary claude"
alias claude-which='echo "Config: ${CLAUDE_CONFIG_DIR:-$HOME/.claude (default)}"'
alias claude-sync-mcp='cp ~/.claude/.mcp.json ~/.claude-secondary/.mcp.json && echo "MCP config synced"'

# PATH: Claude tools
export PATH="$HOME/.claude/bin:$PATH"
export PATH="$HOME/bin:$PATH"
