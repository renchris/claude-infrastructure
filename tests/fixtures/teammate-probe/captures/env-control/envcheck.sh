#!/bin/bash
{ echo "KITTY_WINDOW_ID=${KITTY_WINDOW_ID:-UNSET}"
  echo "ITERM_SESSION_ID_before=${ITERM_SESSION_ID:-UNSET}"
  if [ -n "${KITTY_WINDOW_ID:-}" ] && [ -x "$HOME/.claude/bin/cc-in-kitty" ] && "$HOME/.claude/bin/cc-in-kitty"; then
    export ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"
  fi
  echo "ITERM_SESSION_ID_after=${ITERM_SESSION_ID:-UNSET}"
} > /tmp/claude-501/p1-envcheck.txt 2>&1
