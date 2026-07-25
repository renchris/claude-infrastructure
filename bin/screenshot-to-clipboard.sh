#!/bin/bash
# shellcheck disable=SC2034,SC2012  # verbatim live capture (repo=SSOT for the real ~/bin file) — pre-existing style kept byte-stable; only this directive line differs from the pre-capture original
# screenshot-to-clipboard — auto-copy a NEW screenshot to the clipboard so ⌘⇧4 (save-to-file)
# captures can be pasted directly (⌘V) into any app, with NO Finder-copy detour. Triggered by a
# launchd WatchPaths agent (com.chrisren.screenshot-clipboard) on the Screenshots dir. macOS only.
set -u
DIR="/Users/chrisren/Screenshots"
newest="$(ls -t "$DIR"/*.png 2>/dev/null | head -1)"
[ -n "$newest" ] || exit 0

# Recency guard: WatchPaths fires on ANY change (new file, delete, move) — only act on a screenshot
# created in the last 10s, else an unrelated change would re-copy a STALE image over the user's
# current clipboard.
age=$(( $(date +%s) - $(stat -f %m "$newest" 2>/dev/null || echo 0) ))
[ "$age" -le 10 ] || exit 0

sleep 0.5   # settle: let the capture finish writing the PNG before osascript reads it
osascript -e "set the clipboard to (read (POSIX file \"$newest\") as «class PNGf»)" 2>/dev/null
