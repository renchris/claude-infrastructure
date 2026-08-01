#!/bin/sh
# Working-directory chooser for new kitty split panes (⌘D / ⌘⇧D).
#
# WHY THIS EXISTS
# kitty's `launch --cwd=current` inherits the cwd of the source pane's foreground
# process. In this setup that pane is usually running Claude Code, and the
# always-isolate `claude()` zsh function cd's into a pool worktree
# (~/Development/.worktrees/wt-pool-N) before exec'ing — so every new split
# inherited the WORKTREE, not the primary checkout.
#
# None of kitty's other special values fix it (measured on kitty 0.48.2, all four
# returned the worktree from a pane running Claude Code):
#   current       -> worktree   (newest foreground process = claude)
#   oldest        -> worktree
#   root          -> worktree
#   last_reported -> worktree   (the zsh chpwd hook OSC-7-reported the worktree)
# The login shell itself still sits in the primary checkout, but kitty exposes no
# --cwd value that reaches it. Hence resolving the path here instead.
#
# BEHAVIOUR
# kitty invokes this with --cwd=current, so $PWD is the source pane's cwd.
#   - source pane in a LINKED git worktree -> cd to the repo's MAIN worktree
#   - anywhere else (main checkout, a subdir of it, a non-git dir) -> stay put
# The "stay put" half is deliberate: it preserves the iTerm2 inherit-cwd feel that
# makes ⌘D usable mid-task. Only the worktree case is redirected.
#
# Then hand off to an interactive login shell, which is what the pane would have
# started anyway.

main=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')
top=$(git rev-parse --show-toplevel 2>/dev/null)

# Non-empty, different, and real => we are in a linked worktree; hop to the main one.
if [ -n "$main" ] && [ -n "$top" ] && [ "$main" != "$top" ] && [ -d "$main" ]; then
    cd "$main" || :
fi

exec "${SHELL:-/bin/zsh}" -l
