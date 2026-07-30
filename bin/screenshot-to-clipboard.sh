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

# BOUNDED. This runs from a launchd WatchPaths agent, so a hung osascript is a launchd job that never
# exits — and WatchPaths keeps firing, so wedged copies ACCUMULATE rather than replace each other.
#
# Sourced through $0's PHYSICAL location: ~/bin and ~/.claude/bin hold per-file SYMLINKS into the
# checkout, and a directory of per-file symlinks never gains a NEW file, so following the link chain
# first is what makes a freshly-added lib reachable at all. The inline fallback keeps the call working
# if the lib is genuinely unreadable — losing every clipboard copy would be worse than the hang.
_src="$0"
while [ -L "$_src" ]; do
  _t="$(readlink "$_src")"
  case "$_t" in /*) _src="$_t" ;; *) _src="$(dirname "$_src")/$_t" ;; esac
done
_here="$(cd "$(dirname "$_src")" && pwd -P)"
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if   [ -r "$_here/../hooks/lib/osa.sh" ];      then . "$_here/../hooks/lib/osa.sh"
elif [ -r "$HOME/.claude/hooks/lib/osa.sh" ];  then . "$HOME/.claude/hooks/lib/osa.sh"
else osa_bounded() { timeout 10 "$@"; }
fi

osa_bounded osascript -e "set the clipboard to (read (POSIX file \"$newest\") as «class PNGf»)" 2>/dev/null
