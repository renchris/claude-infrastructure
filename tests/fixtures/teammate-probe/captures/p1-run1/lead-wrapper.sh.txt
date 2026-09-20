#!/bin/bash
cd "/Users/chrisren/Development/.worktrees/probe/teammate-lifecycle-controls/tests/fixtures/teammate-probe" || exit 9
# Claude Code gates its iTerm2 pane backend on ITERM_SESSION_ID (~/.zshrc:678-696); the ~/.claude/bin/it2
# shim then translates each backend call into 'kitty @'. A non-interactive shell never reads .zshrc, so
# without this the lead cannot create a named teammate AT ALL. This is the fleet's own synthesis,
# reproduced verbatim — it is NOT a teammateMode change (that is forbidden for this wave).
if [ -n "160" ] && [ -x "/Users/chrisren/.claude/bin/cc-in-kitty" ] && "/Users/chrisren/.claude/bin/cc-in-kitty"; then
  export ITERM_SESSION_ID="w0t0p0:160"
fi
echo $$ > "/tmp/claude-501/teammate-probe/run1/lead.shpid"
"/Users/chrisren/.claude-260/node_modules/.bin/claude" --permission-mode auto --model claude-opus-5 "$(cat '/Users/chrisren/Development/.worktrees/probe/teammate-lifecycle-controls/tests/fixtures/teammate-probe/lead-brief-p1.txt')"
echo "EXIT=$? at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "/tmp/claude-501/teammate-probe/run1/lead.exit"
