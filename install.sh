#!/bin/bash
# Install Claude Code infrastructure — symlinks, copies, LaunchAgents
#
# Usage:
#   ./install.sh                                    # Install everything (default config dir)
#   ./install.sh --dry-run                           # Preview without changes
#   ./install.sh --config-dir ~/.claude-secondary    # Install to alternate config dir
#                                                    # (skips global items: bin/, LaunchAgents)
#
# Idempotent: safe to run multiple times.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.claude"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    *)            echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Global items (bin/, LaunchAgents, versions) only for default config dir
IS_GLOBAL=false
[[ "$CONFIG_DIR" == "$HOME/.claude" ]] && IS_GLOBAL=true

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
  if [[ -L "$dest" ]]; then
    # Replace symlink with real copy (breaks dependency on primary)
    run rm "$dest"
  elif [[ -f "$dest" ]] && diff -q "$src" "$dest" >/dev/null 2>&1; then
    skipped=$((skipped + 1))
    return
  fi
  run cp "$src" "$dest"
  run chmod +x "$dest" 2>/dev/null || true
  echo "  ✓ $dest"
  installed=$((installed + 1))
}

ensure_real_dir() {
  local dir="$1"
  if [[ -L "$dir" ]]; then
    echo "  ⚠ $dir is a directory symlink — replacing with real directory"
    run rm "$dir"
  fi
  run mkdir -p "$dir"
}

echo "Claude Code Infrastructure Installer"
echo "====================================="
echo "Config dir: $CONFIG_DIR"
$DRY_RUN && echo "(dry-run mode — no changes will be made)"
$IS_GLOBAL || echo "(non-default config — skipping global items)"
echo ""

# --- Hooks ---
echo "Hooks → $CONFIG_DIR/hooks/"
ensure_real_dir "$CONFIG_DIR/hooks"
ensure_real_dir "$CONFIG_DIR/hooks/lib"
for hook in "$REPO_DIR"/hooks/*.sh; do
  [[ -f "$hook" ]] || continue
  link_file "$hook" "$CONFIG_DIR/hooks/$(basename "$hook")"
done
for lib in "$REPO_DIR"/hooks/lib/*.sh; do
  [[ -f "$lib" ]] || continue
  link_file "$lib" "$CONFIG_DIR/hooks/lib/$(basename "$lib")"
done

# --- Commands ---
echo ""
echo "Commands → $CONFIG_DIR/commands/"
ensure_real_dir "$CONFIG_DIR/commands"
for cmd in "$REPO_DIR"/commands/*.md; do
  [[ -f "$cmd" ]] || continue
  link_file "$cmd" "$CONFIG_DIR/commands/$(basename "$cmd")"
done

# --- Bin tools (global only) ---
if $IS_GLOBAL; then
  echo ""
  echo "Bin tools → ~/bin/"
  mkdir -p "$HOME/bin"
  for tool in claude-latest claude-update claude-versions browsermcp-wrapper.sh; do
    [[ -f "$REPO_DIR/bin/$tool" ]] || continue
    copy_file "$REPO_DIR/bin/$tool" "$HOME/bin/$tool"
  done
fi

# --- Scripts ---
# Primary ~/.claude → SYMLINK (same as hooks/commands above) so edits to the live
# scripts land in the repo directly and can't silently drift out of version control —
# the failure mode observed 2026-07-03, when handoff-fire.sh drifted +198 lines in the
# deployment and was one `install.sh` (copy_file clobber) away from being lost.
# Alt config dirs → COPY, to stay independent of the primary (copy_file's rationale).
echo ""
echo "Scripts → $CONFIG_DIR/scripts/"
ensure_real_dir "$CONFIG_DIR/scripts"
for script in "$REPO_DIR"/scripts/*.sh; do
  [[ -f "$script" ]] || continue
  if $IS_GLOBAL; then
    link_file "$script" "$CONFIG_DIR/scripts/$(basename "$script")"
  else
    copy_file "$script" "$CONFIG_DIR/scripts/$(basename "$script")"
  fi
done

# Convenience symlink (global only)
if $IS_GLOBAL && [[ ! -L "$HOME/bin/restore-file" ]]; then
  run ln -sf "$HOME/.claude/scripts/restore-file.sh" "$HOME/bin/restore-file"
  echo "  ✓ ~/bin/restore-file → ~/.claude/scripts/restore-file.sh"
  installed=$((installed + 1))
fi

# --- Status line ---
echo ""
echo "Status line → $CONFIG_DIR/"
copy_file "$REPO_DIR/statusline.sh" "$CONFIG_DIR/statusline.sh"

# --- it2 wrapper ---
if [[ -f "$REPO_DIR/bin/it2-wrapper" ]]; then
  echo ""
  echo "iTerm2 wrapper → $CONFIG_DIR/bin/"
  mkdir -p "$CONFIG_DIR/bin"
  copy_file "$REPO_DIR/bin/it2-wrapper" "$CONFIG_DIR/bin/it2"
fi

# --- LaunchAgents (global only) ---
if $IS_GLOBAL; then
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
fi

# --- Validation ---
echo ""
echo "Validating..."
warnings=0

if ! grep -q "statusline" "$CONFIG_DIR/settings.json" 2>/dev/null; then
  echo "  ⚠ settings.json missing statusLine config"
  warnings=$((warnings + 1))
fi

if ! grep -q "hooks" "$CONFIG_DIR/settings.json" 2>/dev/null; then
  echo "  ⚠ settings.json missing hooks config — hooks won't fire without registration"
  warnings=$((warnings + 1))
fi

if $IS_GLOBAL; then
  if ! command -v claude-latest &>/dev/null; then
    echo "  ⚠ ~/bin not in PATH — add 'export PATH=\"\$HOME/bin:\$PATH\"' to ~/.zshrc"
    warnings=$((warnings + 1))
  fi
fi

if [[ $warnings -eq 0 ]]; then
  echo "  ✓ All checks passed"
fi

# --- Summary ---
echo ""
echo "Done: $installed installed, $skipped already up-to-date"
if [[ $warnings -gt 0 ]]; then
  echo "     $warnings warning(s)"
fi
