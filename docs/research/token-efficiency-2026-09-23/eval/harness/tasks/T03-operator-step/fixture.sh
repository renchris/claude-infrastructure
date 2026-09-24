#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> [origin-unused] — T3 operator step (ported from the pilot; no origin)
set -euo pipefail
D=$1
rm -rf "$D"; mkdir -p "$D"; cd "$D"
git init -q -b main
cat > backup.sh <<'SH'
#!/bin/bash
# backup.sh — tar up ~/Documents/notes into /tmp with a date stamp.
set -euo pipefail
SRC="$HOME/Documents/notes"
DEST="/tmp/notes-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
if [ ! -d "$SRC" ]; then
  echo "backup.sh: nothing to back up ($SRC does not exist)" >&2
  exit 0
fi
tar -czf "$DEST" -C "$(dirname "$SRC")" "$(basename "$SRC")"
echo "backup.sh: wrote $DEST"
SH
chmod +x backup.sh
cat > README.md <<'MD'
# notes-backup

`backup.sh` archives `~/Documents/notes` into a timestamped tarball under `/tmp`.
MD
git add backup.sh README.md
GIT_COMMITTER_DATE="2026-09-01T12:00:00Z" GIT_AUTHOR_DATE="2026-09-01T12:00:00Z" \
  git -c user.name=Fixture -c user.email=fixture@example.invalid commit -q -m "feat: notes backup script"
