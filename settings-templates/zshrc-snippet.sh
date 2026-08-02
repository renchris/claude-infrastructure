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

# Cross-account / cross-directory `--resume <id>`. Claude resolves a session id only under
# $CLAUDE_CONFIG_DIR/projects/<hash-of-cwd>/, so the id it prints at the end of a session does
# NOT resume from a different directory or a second account — worth wiring the moment you have
# either. _cc_resume_pin finds the transcript and reports where to stand; it fails open, so the
# guard below means a machine without the lib simply keeps stock behaviour.
# shellcheck source=/dev/null
[[ -f "$HOME/.claude/lib/cc-resume-shell.sh" ]] && source "$HOME/.claude/lib/cc-resume-shell.sh"

claude() {
    local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" _wt=""
    if typeset -f _cc_resume_pin >/dev/null 2>&1; then
        _cc_resume_pin "$_cfg" "$@"
        set -- "${CC_RESUME_ARGS[@]}"
        [[ -n "$CC_RESUME_CFG" ]] && _cfg="$CC_RESUME_CFG"
        [[ -n "$CC_RESUME_CWD" ]] && _wt="$CC_RESUME_CWD"
    fi
    # Subshell, so a resolved cwd never moves the calling shell. A failed cd ABORTS rather than
    # launching here: resuming in the wrong directory is exactly the bug this whole thing closes.
    ( if [[ -n "$_wt" ]]; then cd "$_wt" || return 1; fi
      CLAUDE_CONFIG_DIR="$_cfg" CLAUDE_CODE_TASK_LIST_ID="$(basename "$(pwd)")" \
        claude-latest --effort "${CLAUDE_DEFAULT_EFFORT:-max}" "$@" )
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
