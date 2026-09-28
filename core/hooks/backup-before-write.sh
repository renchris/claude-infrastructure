#!/bin/bash
# backup-before-write.sh — PreToolUse(Write) hook: copy a file before a Write replaces it.
#
# The Write tool replaces a whole file. On a plan, a doc or a CLAUDE.md that has gathered decisions
# over many sessions, one careless rewrite loses them. This keeps a copy of every file a Write is about
# to replace, under <install>/backups/<date>/, for 14 days (AUTONOMY_BACKUP_DAYS).
# Restore the newest copy with: ~/.claude/autonomy-core/bin/autonomy restore <path>
#
# It never blocks a write: every path exits 0, and a backup failure is only reported.

# shellcheck disable=SC1091  # lib.sh sits beside this hook
. "$(dirname "$0")/lib.sh"
input="$(cat)"
path="$(ac_json_get "$input" tool_input.file_path)"
[ -n "$path" ] && [ -f "$path" ] || exit 0

root="$AC_HOME/backups"
day="$root/$(date +%Y%m%d)"
mkdir -p "$day" 2>/dev/null || exit 0
# The whole path, flattened, so the same name in two directories never collides.
flat="$(printf '%s' "$path" | sed 's#/#%#g')"
# Named by time; a second copy within the same second gets -01, -02, … so none is overwritten and the
# names still sort oldest to newest.
base="$day/$flat.$(date +%H%M%S)"
dest="$base"
n=0
while [ -e "$dest" ]; do n=$((n + 1)); dest="$base-$(printf '%02d' "$n")"; done
cp -p "$path" "$dest" 2>/dev/null \
  || echo "autonomy-core: could not back up $path before the write" >&2

# Prune whole days older than the retention window (find -mtime works on GNU and BSD alike).
find "$root" -mindepth 1 -maxdepth 1 -type d -mtime +"${AUTONOMY_BACKUP_DAYS:-14}" -exec rm -rf {} + 2>/dev/null
exit 0
