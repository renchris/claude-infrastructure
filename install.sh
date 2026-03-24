#!/bin/bash
# Install Claude Code infrastructure — symlinks, copies, LaunchAgents
#
# Usage:
#   ./install.sh            # Install everything
#   ./install.sh --dry-run  # Preview without changes
#
# Idempotent: safe to run multiple times.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

installed=0
skipped=0

run() {
  if $DRY_RUN; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

link_file() {
  local src="$1" dest="$2"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    skipped=$((skipped + 1))
    return
  fi
  run ln -sf "$src" "$dest"
  echo "  ✓ $dest → $src"
  installed=$((installed + 1))
}

copy_file() {
  local src="$1" dest="$2"
  if [[ -f "$dest" ]] && diff -q "$src" "$dest" >/dev/null 2>&1; then
    skipped=$((skipped + 1))
    return
  fi
  run cp "$src" "$dest"
  run chmod +x "$dest" 2>/dev/null || true
  echo "  ✓ $dest"
  installed=$((installed + 1))
}

echo "Claude Code Infrastructure Installer"
echo "====================================="
$DRY_RUN && echo "(dry-run mode — no changes will be made)"
echo ""

# --- Hooks ---
echo "Hooks → ~/.claude/hooks/"
mkdir -p "$HOME/.claude/hooks/lib"
for hook in "$REPO_DIR"/hooks/*.sh; do
  [[ -f "$hook" ]] || continue
  link_file "$hook" "$HOME/.claude/hooks/$(basename "$hook")"
done
for lib in "$REPO_DIR"/hooks/lib/*.sh; do
  [[ -f "$lib" ]] || continue
  link_file "$lib" "$HOME/.claude/hooks/lib/$(basename "$lib")"
done

# --- Bin tools ---
echo ""
echo "Bin tools → ~/bin/"
mkdir -p "$HOME/bin"
for tool in claude-latest claude-update claude-versions browsermcp-wrapper.sh; do
  [[ -f "$REPO_DIR/bin/$tool" ]] || continue
  copy_file "$REPO_DIR/bin/$tool" "$HOME/bin/$tool"
done

# --- Scripts ---
echo ""
echo "Scripts → ~/.claude/scripts/"
mkdir -p "$HOME/.claude/scripts"
for script in "$REPO_DIR"/scripts/*.sh; do
  [[ -f "$script" ]] || continue
  copy_file "$script" "$HOME/.claude/scripts/$(basename "$script")"
done

# Convenience symlink
if [[ ! -L "$HOME/bin/restore-file" ]]; then
  run ln -sf "$HOME/.claude/scripts/restore-file.sh" "$HOME/bin/restore-file"
  echo "  ✓ ~/bin/restore-file → ~/.claude/scripts/restore-file.sh"
  installed=$((installed + 1))
fi

# --- Status line ---
echo ""
echo "Status line → ~/.claude/"
copy_file "$REPO_DIR/statusline.sh" "$HOME/.claude/statusline.sh"

# --- it2 wrapper ---
if [[ -f "$REPO_DIR/bin/it2-wrapper" ]]; then
  echo ""
  echo "iTerm2 wrapper → ~/.claude/bin/"
  mkdir -p "$HOME/.claude/bin"
  copy_file "$REPO_DIR/bin/it2-wrapper" "$HOME/.claude/bin/it2"
fi

# --- LaunchAgents ---
echo ""
echo "LaunchAgents → ~/Library/LaunchAgents/"
mkdir -p "$HOME/Library/LaunchAgents"
for plist in "$REPO_DIR"/launchd/*.plist; do
  [[ -f "$plist" ]] || continue
  name=$(basename "$plist")
  copy_file "$plist" "$HOME/Library/LaunchAgents/$name"
  if ! $DRY_RUN; then
    label="${name%.plist}"
    # Unload if already loaded (ignore errors)
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$name" 2>/dev/null || \
      launchctl load "$HOME/Library/LaunchAgents/$name" 2>/dev/null || true
  fi
done

# --- Version directory ---
echo ""
echo "Version management → ~/.claude-versions/"
mkdir -p "$HOME/.claude-versions"

# --- Validation ---
echo ""
echo "Validating..."
warnings=0

if ! grep -q "statusline" "$HOME/.claude/settings.json" 2>/dev/null; then
  echo "  ⚠ settings.json missing statusLine config"
  warnings=$((warnings + 1))
fi

if ! grep -q "hooks" "$HOME/.claude/settings.json" 2>/dev/null; then
  echo "  ⚠ settings.json missing hooks config — hooks won't fire without registration"
  warnings=$((warnings + 1))
fi

if ! command -v claude-latest &>/dev/null; then
  echo "  ⚠ ~/bin not in PATH — add 'export PATH=\"\$HOME/bin:\$PATH\"' to ~/.zshrc"
  warnings=$((warnings + 1))
fi

if [[ $warnings -eq 0 ]]; then
  echo "  ✓ All checks passed"
fi

# --- Summary ---
echo ""
echo "Done: $installed installed, $skipped already up-to-date"
[[ $warnings -gt 0 ]] && echo "     $warnings warning(s)"
