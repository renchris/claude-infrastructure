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
WIRE_HOOKS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    --wire-hooks) WIRE_HOOKS=true; shift ;;   # additively merge the settings.example.json hook/deny/ask roster
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
  for tool in claude-latest claude-update claude-versions browsermcp-wrapper.sh claude-accounts claude-kimi; do
    [[ -f "$REPO_DIR/bin/$tool" ]] || continue
    copy_file "$REPO_DIR/bin/$tool" "$HOME/bin/$tool"
  done

  # Accounts SSOT — symlink (repo = source of truth; the knowledge-layer mirror
  # shares ~/.claude/accounts.json into every alt config dir automatically).
  echo ""
  echo "Accounts SSOT → $CONFIG_DIR/accounts.json"
  link_file "$REPO_DIR/accounts.json" "$CONFIG_DIR/accounts.json"
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

# --- Skills ---
# Same symlink model as hooks/commands: version each repo skill dir and deploy it live.
# Only touches skill NAMES present in the repo — other ~/.claude/skills are left untouched.
if [[ -d "$REPO_DIR/skills" ]]; then
  echo ""
  echo "Skills → $CONFIG_DIR/skills/"
  for skilldir in "$REPO_DIR"/skills/*/; do
    [[ -d "$skilldir" ]] || continue
    name="$(basename "$skilldir")"
    ensure_real_dir "$CONFIG_DIR/skills/$name"
    for f in "$skilldir"*; do
      [[ -f "$f" ]] || continue
      link_file "$f" "$CONFIG_DIR/skills/$name/$(basename "$f")"
    done
  done
fi

# --- Global instructions (CLAUDE.md + rules/) — repo is the source of truth ---
# The lean resident knowledge layer. CLAUDE.md is COPIED as a real file (CC reads ~/.claude/CLAUDE.md
# as user memory; a symlink into the repo would break across branch switches). rules/ is kept in sync:
# stale live rule files no longer tracked in the repo are removed (agent-teams.md + research-subagents.md
# were relocated to skills). PROJECT-only memory stays in the repo at .claude/CLAUDE.md and is NEVER
# deployed globally — ~/.claude/CLAUDE.md remains the pure global core.
echo ""
echo "Global instructions → $CONFIG_DIR/CLAUDE.md + rules/"
if ! diff -q "$REPO_DIR/CLAUDE.md" "$CONFIG_DIR/CLAUDE.md" >/dev/null 2>&1; then
  [[ -L "$CONFIG_DIR/CLAUDE.md" ]] && run rm "$CONFIG_DIR/CLAUDE.md"
  run cp "$REPO_DIR/CLAUDE.md" "$CONFIG_DIR/CLAUDE.md"
  echo "  ✓ CLAUDE.md ($(wc -l < "$REPO_DIR/CLAUDE.md" | tr -d ' ') lines)"
  installed=$((installed + 1))
else
  skipped=$((skipped + 1))
fi
ensure_real_dir "$CONFIG_DIR/rules"
for live in "$CONFIG_DIR"/rules/*.md; do
  [[ -f "$live" ]] || continue
  base="$(basename "$live")"
  [[ -f "$REPO_DIR/rules/$base" ]] || { run rm -f "$live"; echo "  ✓ removed stale rule $base (relocated to a skill)"; installed=$((installed + 1)); }
done
if [[ -d "$REPO_DIR/rules" ]]; then
  for rf in "$REPO_DIR"/rules/*.md; do
    [[ -f "$rf" ]] || continue
    copy_file "$rf" "$CONFIG_DIR/rules/$(basename "$rf")"
  done
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

# --- Cross-session comms tools (global only) → ~/.claude/bin/ ---
# cc-notify / cc-sessions / cc-await-ping — the two-way session-comms CLIs.
# SYMLINKED (like scripts/) so live edits land in the repo and can't drift out of
# version control. ~/.claude/bin is on PATH and holds it2, beside which these sit —
# the /handoff --notify-back back-channel trailer references $HOME/.claude/bin/cc-notify
# by absolute path, so this location is load-bearing.
if $IS_GLOBAL; then
  echo ""
  echo "Comms tools → $CONFIG_DIR/bin/"
  mkdir -p "$CONFIG_DIR/bin"
  for tool in "$REPO_DIR"/bin/cc-*; do
    [[ -f "$tool" ]] || continue
    link_file "$tool" "$CONFIG_DIR/bin/$(basename "$tool")"
  done
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

# --- Settings hooks (merge-wire + post-install assert) ---
# The FULL live hook roster lives in settings-templates/settings.example.json (G-P6-7): the
# anti-premature-done Stop hooks (session-continue, anti-deference, teammate-checkpoint, boundary-handoff)
# MUST survive a settings reset. This ADDITIVELY merges the template's .hooks (adds missing EVENTS only —
# never clobbers a populated event) + unions .permissions.deny/.ask into $CONFIG_DIR/settings.json.
# --wire-hooks opts in; a config with NO .hooks is auto-wired (fresh install). A read-only ASSERT always
# reports template hooks not present in the target. (Merging settings.json is the OPERATOR's hand via
# this installer — never an agent Write; the C10 ceiling holds.)
warnings=0
echo ""
echo "Settings hooks → $CONFIG_DIR/settings.json"
TEMPLATE="$REPO_DIR/settings-templates/settings.example.json"
target_settings="$CONFIG_DIR/settings.json"
if ! command -v jq >/dev/null 2>&1; then
  echo "  ⚠ jq not found — skipping settings merge/assert"
  warnings=$((warnings + 1))
elif [[ ! -f "$TEMPLATE" ]]; then
  echo "  ⚠ template missing: $TEMPLATE"
  warnings=$((warnings + 1))
else
  # clean template = strip every _-prefixed annotation key (recursively) so no _comment/_stagedHooks leak in
  clean_tmpl="$(jq 'walk(if type=="object" then with_entries(select(.key|startswith("_")|not)) else . end)' "$TEMPLATE")"
  do_merge=false
  if [[ ! -f "$target_settings" ]]; then do_merge=true
  elif $WIRE_HOOKS; then do_merge=true
  elif ! jq -e '.hooks' "$target_settings" >/dev/null 2>&1; then do_merge=true   # fresh/reset config → auto-wire
  fi

  if $do_merge; then
    if $DRY_RUN; then
      echo "  [dry-run] would merge-wire hooks + deny/ask union into $target_settings"
    else
      base="$clean_tmpl"; [[ -f "$target_settings" ]] && base="$(cat "$target_settings")"
      [[ -f "$target_settings" ]] && cp "$target_settings" "$target_settings.pre-wire.bak"
      if printf '%s' "$base" | jq --argjson t "$clean_tmpl" '
            .hooks = ($t.hooks + (.hooks // {}))                                    # add missing events; keep present
            | .permissions = (.permissions // {})
            | .permissions.deny = (((.permissions.deny // []) + ($t.permissions.deny // [])) | unique)
            | .permissions.ask  = (((.permissions.ask  // []) + ($t.permissions.ask  // [])) | unique)
          ' > "$target_settings.tmp" && mv "$target_settings.tmp" "$target_settings"; then
        # Merge is ADDITIVE + order-preserving: it wires missing EVENTS in full and unions deny/ask,
        # but never reorders a populated event (the Stop FM1 chain order is load-bearing). Any remaining
        # WITHIN-event gaps are order-sensitive and reported by the assert below for manual placement.
        echo "  ✓ merged: missing hook events + deny/ask union (backup .pre-wire.bak; within-event gaps, if any, listed below)"
        installed=$((installed + 1))
      else
        rm -f "$target_settings.tmp"
        echo "  ⚠ jq merge failed — settings.json left unchanged"
        warnings=$((warnings + 1))
      fi
    fi
  else
    echo "  · assert-only ($(basename "$target_settings") already has hooks; pass --wire-hooks to merge)"
  fi

  # post-install ASSERT (read-only): which template hooks are NOT wired in the target (by basename+args)
  if [[ -f "$target_settings" ]]; then
    norm='s#\|[^ ]*/#|#'
    tmpl_h="$(printf '%s' "$clean_tmpl" | jq -r '.hooks|to_entries[]|.key as $e|(.value//[])[]?|(.hooks//[])[]?|"\($e)|\(.command)"' 2>/dev/null | sed -E "$norm" | sort -u)"
    live_h="$(jq -r '.hooks|to_entries[]|.key as $e|(.value//[])[]?|(.hooks//[])[]?|"\($e)|\(.command)"' "$target_settings" 2>/dev/null | sed -E "$norm" | sort -u)"
    missing_h="$(comm -23 <(printf '%s\n' "$tmpl_h") <(printf '%s\n' "$live_h"))"
    if [[ -n "$missing_h" ]]; then
      echo "  ⚠ template hooks NOT wired in $(basename "$target_settings") (run with --wire-hooks to add):"
      printf '%s\n' "$missing_h" | sed 's/^/      /'
      warnings=$((warnings + 1))
    else
      echo "  ✓ all template hooks present in $(basename "$target_settings")"
    fi
  fi
fi

# --- Validation ---
echo ""
echo "Validating..."

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

# --- macOS: pre-establish the iTerm2 clear-scrollback pref -------------------
# So an autonomous /limit-recover resume never blocks on the "control sequence attempted
# to clear scrollback history" GUI modal (a sheet above the PTY that expect cannot answer).
# Setting it at SETUP (not just per-resume) closes the cold-machine first-resume race where
# iTerm2, launched before the pref was ever written, hasn't yet processed the change.
# See scripts/limit-recover/lr-preseed-env.sh.
if [[ "$(uname)" == "Darwin" ]] && command -v defaults >/dev/null 2>&1; then
  if [[ "$(defaults read com.googlecode.iterm2 PreventEscapeSequenceFromClearingHistory 2>/dev/null)" != "1" ]]; then
    defaults write com.googlecode.iterm2 PreventEscapeSequenceFromClearingHistory -bool true 2>/dev/null \
      && echo "  ✓ iTerm2 clear-scrollback modal suppressed (autonomous-resume prereq)"
  fi
fi

# --- Summary ---
echo ""
echo "Done: $installed installed, $skipped already up-to-date"
if [[ $warnings -gt 0 ]]; then
  echo "     $warnings warning(s)"
fi
