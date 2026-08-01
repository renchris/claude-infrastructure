#!/bin/bash
# Claude Code shell integration — add to ~/.zshrc
#
# This is the PORTABLE starter: the auto-updating `claude-latest` track, which needs nothing pinned
# on the machine. It is deliberately not a copy of this repo's own ~/.zshrc, where `claude` is the
# pinned Opus-5 eval entrypoint and this body's track is named `claude-prev` (README § Shell
# launchers). Names below are the post-2026-08-01 set — no claude-next / claude-opus5 / claude-fable.

# Main entrypoint: auto-update + task list persistence + max effort default.
# Effort rides the --effort flag injected BEFORE "$@" (Commander last-wins → an
# explicit `claude --effort low` overrides; /effort stays adjustable in-session).
# NEVER `export CLAUDE_CODE_EFFORT_LEVEL` — the env var is re-read every turn,
# outranks /effort for the whole session, and cannot be unset from inside.
CLAUDE_DEFAULT_EFFORT="${CLAUDE_DEFAULT_EFFORT:-max}"
claude() {
    CLAUDE_CODE_TASK_LIST_ID="$(basename "$(pwd)")" claude-latest --effort "${CLAUDE_DEFAULT_EFFORT:-max}" "$@"
}

# Plan mode with extended thinking
alias claude-plan='claude --permission-mode plan --append-system-prompt "ultrathink"'

# Auto mode (research preview, March 2026)
# alias claude-auto='claude --permission-mode auto'

# Second isolated Claude instance
# Single-quoted so $HOME expands at USE time, not definition time (SC2139) — and so this template
# matches how the live ~/.zshrc spells its account aliases.
alias claude2='CLAUDE_CONFIG_DIR=$HOME/.claude-secondary claude'
alias claude-which='echo "Config: ${CLAUDE_CONFIG_DIR:-$HOME/.claude (default)}"'
alias claude-sync-mcp='cp ~/.claude/.mcp.json ~/.claude-secondary/.mcp.json && echo "MCP config synced"'

# PATH: Claude tools
export PATH="$HOME/.claude/bin:$PATH"
export PATH="$HOME/bin:$PATH"
