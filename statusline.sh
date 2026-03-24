#!/bin/bash
# Ultra-Minimal Actionable Status Line
#
# Shows context usage based on remaining_percentage (per-conversation INPUT tokens).
#
# LIMITATION: Claude's red warning counts INPUT + OUTPUT tokens, but the statusline
# JSON only exposes INPUT tokens per-conversation. This means:
# - Heavy OUTPUT sessions (lots of code generation) may trigger warning earlier
#   than this statusline predicts
# - The warning % and statusline % may diverge in output-heavy sessions
#
# Offset approximation (48%) accounts for:
# - Output token buffer: ~32% (64k/200k)
# - Auto-compact buffer: ~6.5% (13k/200k)
# - Warning threshold: ~10% (20k/200k)
#
# See: docs/reference/CLAUDE_CODE_CONTEXT_CALCULATION.md
#
# Color thresholds:
#   - <60% used: gray (healthy)
#   - 60-90% used: default (approaching)
#   - >90% used: red (warning likely visible)

GRAY='\033[38;5;245m'
MUTED_RED='\033[38;5;167m'
RESET='\033[0m'

# Approximate offset to convert INPUT-only % to effective %
# This is an approximation - see docs for exact formula limitations
BUFFER_OFFSET=48

INPUT=$(cat)
OUTPUT=""

# Directory + Commit ID
DIR=$(basename "$(pwd)")
COMMIT=$(git rev-parse --short HEAD 2>/dev/null)
if [ -n "$COMMIT" ]; then
    OUTPUT="${DIR} (${COMMIT})"
else
    OUTPUT="${DIR}"
fi

# Git branch (only if not on main)
BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
    DIRTY=""
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        DIRTY="*"
    fi
    OUTPUT="${OUTPUT}  ${BRANCH}${DIRTY}"
fi

# Context % - Using remaining_percentage (per-conversation INPUT only)
if [ -n "$INPUT" ] && command -v jq &>/dev/null; then
    REMAINING=$(echo "$INPUT" | jq -r '.context_window.remaining_percentage // empty' 2>/dev/null)

    if [ -n "$REMAINING" ] && [ "$REMAINING" != "null" ]; then
        # Apply offset to approximate effective remaining
        # (accounts for output buffer + auto-compact buffer)
        EFFECTIVE_REMAINING=$((REMAINING - BUFFER_OFFSET))
        [ "$EFFECTIVE_REMAINING" -lt 0 ] && EFFECTIVE_REMAINING=0
        [ "$EFFECTIVE_REMAINING" -gt 100 ] && EFFECTIVE_REMAINING=100

        # Convert to "used %" for display
        PCT=$((100 - EFFECTIVE_REMAINING))
    fi

    if [ -n "$PCT" ] && [ "$PCT" -gt 0 ] 2>/dev/null; then
        if [ "$PCT" -ge 90 ]; then
            OUTPUT="${GRAY}${OUTPUT} ·${RESET} ${MUTED_RED}${PCT}%${RESET}"
        elif [ "$PCT" -ge 60 ]; then
            OUTPUT="${GRAY}${OUTPUT} ·${RESET} ${PCT}%"
        else
            OUTPUT="${GRAY}${OUTPUT} · ${PCT}%${RESET}"
        fi
    fi
fi

echo -e "$OUTPUT"
