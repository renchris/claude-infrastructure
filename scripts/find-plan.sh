#!/bin/bash
# find-plan.sh — resolve a plan name or path to a plan file + print its content.
#
# Usage:
#   find-plan.sh <name-or-path>
#
# Resolution order (first match wins):
#   1. Literal path (absolute or relative to cwd)
#   2. ~/.claude/plans/<name>
#   3. ~/.claude/plans/<name>.md
#   4. $PWD/.claude-plans/<name>(.md)
#   5. $PWD/docs/plans/<name>(.md)
#   6. Every Development/*/(.claude-plans|docs/plans)/<name>(.md)
#
# On success: prints file content to stdout, exit 0.
# On miss:    prints usage + searched paths to stderr, exit 1.

set -uo pipefail

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  cat >&2 <<EOF
usage: find-plan.sh <plan-name-or-path>

Searches common plan directories for <name>.md or <name>:
  ~/.claude/plans/
  \$PWD/.claude-plans/
  \$PWD/docs/plans/
  ~/Development/*/.claude-plans/
  ~/Development/*/docs/plans/

Or accepts an absolute/relative path directly.
EOF
  exit 1
fi

# 1. Literal path (absolute or relative to cwd)
if [[ -f "$NAME" ]]; then
  cat "$NAME"
  exit 0
fi

# Build search list. Order matters: user's home first, then project-local.
declare -a DIRS=(
  "$HOME/.claude/plans"
  "$PWD/.claude-plans"
  "$PWD/docs/plans"
)

# Add other Development project plan dirs (non-fatal if glob doesn't match).
for d in "$HOME"/Development/*/.claude-plans; do
  [[ -d "$d" ]] && DIRS+=("$d")
done
for d in "$HOME"/Development/*/docs/plans; do
  [[ -d "$d" ]] && DIRS+=("$d")
done

# 2-N. Search each directory for name + name.md
for dir in "${DIRS[@]}"; do
  for suffix in "" ".md"; do
    f="$dir/$NAME$suffix"
    if [[ -f "$f" ]]; then
      cat "$f"
      exit 0
    fi
  done
done

# Not found — emit helpful error
{
  echo "Plan not found: $NAME"
  echo ""
  echo "Searched:"
  for dir in "${DIRS[@]}"; do
    echo "  $dir/$NAME.md"
  done
} >&2
exit 1
