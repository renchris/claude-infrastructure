#!/bin/bash
# chime-player.sh — launchd entry point for scripts/chime-player.js (com.claude.chime-player).
#
# Two jobs, both things the .js cannot do for itself:
#   1. FIND THE .js. install.sh deploys scripts/*.sh and scripts/*.py into ~/.claude/scripts as
#      per-file symlinks and never a .js, so the player is reached through THIS file's resolved path:
#      ~/.claude/scripts/chime-player.sh -> <checkout>/scripts/chime-player.sh, sibling .js beside it.
#      `dirname "$0"` unresolved would be ~/.claude/scripts, where no .js exists.
#   2. PIN THE SPOOL DIR to the one hooks/notify.sh computes: `getconf DARWIN_USER_TEMP_DIR` + cc-chime,
#      from confstr rather than $TMPDIR (launchd injects none; a harness run can carry its own). The
#      producer and the consumer must agree on this path or every chime falls back to afplay.
# Runs under /bin/bash 3.2 (launchd): no bash-4 constructs.
# The osascript below is unbounded ON PURPOSE and is not the hazard tests/osa-bounds.bats polices: that
# suite bounds AppleEvents into another app, which can wait forever on a wedged target. This is a
# resident interpreter that sends no AppleEvent at all (no Application() in the .js); living forever
# is its job, and launchd's KeepAlive is what restarts it.
set -u
self="$0"
while [ -L "$self" ]; do
  link="$(/usr/bin/readlink "$self")"
  case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
dir="$(cd "$(dirname "$self")" && pwd)"
if [ -z "${CC_CHIME_DIR:-}" ]; then
  base="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
  if [ -z "$base" ]; then echo "chime-player: getconf DARWIN_USER_TEMP_DIR failed" >&2; exit 1; fi
  CC_CHIME_DIR="${base%/}/cc-chime"
fi
export CC_CHIME_DIR
exec /usr/bin/osascript -l JavaScript "$dir/chime-player.js"
