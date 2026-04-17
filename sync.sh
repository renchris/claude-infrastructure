#!/bin/bash
# Sync live ~/.claude/ configuration into this repo
#
# Usage:
#   ./sync.sh            # Show diff, copy files
#   ./sync.sh --commit   # Also commit changes
#   ./sync.sh --diff     # Only show diff, don't copy

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DIFF_ONLY=false
AUTO_COMMIT=false
[[ "${1:-}" == "--diff" ]] && DIFF_ONLY=true
[[ "${1:-}" == "--commit" ]] && AUTO_COMMIT=true

changed=0

sync_file() {
  local src="$1" dest="$2"
  # Resolve symlinks to get actual content
  local real_src
  real_src=$(readlink -f "$src" 2>/dev/null || echo "$src")

  if [[ ! -f "$real_src" ]]; then
    echo "  ⚠ Missing: $src"
    return
  fi

  if [[ -f "$dest" ]] && diff -q "$real_src" "$dest" >/dev/null 2>&1; then
    return  # Identical
  fi

  changed=$((changed + 1))
  if $DIFF_ONLY; then
    echo "  Changed: $(basename "$dest")"
    diff --color=auto -u "$dest" "$real_src" 2>/dev/null | head -20 || true
    echo ""
  else
    cp -L "$real_src" "$dest"
    echo "  ✓ $(basename "$dest")"
  fi
}

echo "Syncing live config → repo"
echo "=========================="
echo ""

# Hooks
echo "Hooks:"
for hook in "$HOME"/.claude/hooks/*.sh; do
  [[ -f "$hook" ]] || continue
  name=$(basename "$hook")
  sync_file "$hook" "$REPO_DIR/hooks/$name"
done
for lib in "$HOME"/.claude/hooks/lib/*.sh; do
  [[ -f "$lib" ]] || continue
  name=$(basename "$lib")
  sync_file "$lib" "$REPO_DIR/hooks/lib/$name"
done

# Commands
echo "Commands:"
for cmd in "$HOME"/.claude/commands/*.md; do
  [[ -f "$cmd" ]] || continue
  name=$(basename "$cmd")
  sync_file "$cmd" "$REPO_DIR/commands/$name"
done

# Bin tools
echo "Bin tools:"
for tool in claude-latest claude-update claude-versions browsermcp-wrapper.sh; do
  [[ -f "$HOME/bin/$tool" ]] || continue
  sync_file "$HOME/bin/$tool" "$REPO_DIR/bin/$tool"
done

# Scripts
echo "Scripts:"
for script in "$HOME"/.claude/scripts/*.sh; do
  [[ -f "$script" ]] || continue
  name=$(basename "$script")
  sync_file "$script" "$REPO_DIR/scripts/$name"
done

# Status line
echo "Status line:"
sync_file "$HOME/.claude/statusline.sh" "$REPO_DIR/statusline.sh"
[[ -f "$HOME/.claude/statusline-debug.sh" ]] && \
  sync_file "$HOME/.claude/statusline-debug.sh" "$REPO_DIR/statusline-debug.sh"

# LaunchAgents
echo "LaunchAgents:"
for plist in "$HOME"/Library/LaunchAgents/com.claude.*.plist; do
  [[ -f "$plist" ]] || continue
  name=$(basename "$plist")
  sync_file "$plist" "$REPO_DIR/launchd/$name"
done

# Summary
echo ""
if [[ $changed -eq 0 ]]; then
  echo "Everything in sync."
else
  echo "$changed file(s) changed."
  if $AUTO_COMMIT; then
    cd "$REPO_DIR"
    git add -A
    git commit -m "$(cat <<EOF
chore: sync from live config

$(git diff --cached --stat)
EOF
)"
    echo "Committed."
  elif ! $DIFF_ONLY; then
    echo "Run './sync.sh --commit' to commit, or 'git diff' to review."
  fi
fi
