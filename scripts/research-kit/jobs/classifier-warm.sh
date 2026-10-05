#!/bin/bash
# classifier-warm.sh — the launchd runner for the re-ask router's resident classifier (decision
# 4bf73c4e55d5 option 3; wave E1c of docs/plans/RESEARCH_PROGRAM_BUILD.md). The staged plist
# launchd/staged/com.claude.research-classifier-warm.plist runs `/bin/bash <this>`; it pins PATH to
# what launchd can resolve plus the directories `claude` installs to, and execs the daemon
# (`classifier-warm.py serve`), which keeps classifier processes started ahead of the prompt.
#
#   classifier-warm.sh            (no arguments)
#
# The daemon's exit is this script's exit. CC_RESEARCH_PYTHON overrides the interpreter and
# CC_RESEARCH_WARM_DAEMON the daemon script (tests). bash 3.2-safe.
set -u

export PATH="$HOME/.claude/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

if [ "$#" -ne 0 ]; then
  echo "classifier-warm: takes no arguments" >&2
  exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"
daemon="${CC_RESEARCH_WARM_DAEMON:-$here/../classifier-warm.py}"
if [ ! -f "$daemon" ]; then
  echo "classifier-warm: no daemon script at $daemon" >&2
  exit 1
fi

exec "${CC_RESEARCH_PYTHON:-/usr/bin/python3}" "$daemon" serve
