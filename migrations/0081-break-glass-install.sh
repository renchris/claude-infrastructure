#!/bin/bash
# migration-class: mechanical
# migration-subject: scripts/break-glass/rescue.sh
# migration-verify: [ -L "$HOME/.claude/scripts/break-glass/rescue.sh" ] && [ -f "$HOME/.claude/scripts/break-glass/rescue.sh" ] && [ -f "$HOME/.claude/scripts/break-glass/rescue.bashrc" ] && grep -q '"cc-break-glass-rescue-0001"' "$HOME/Library/Application Support/iTerm2/DynamicProfiles/break-glass-rescue.json" && grep -q "rescue.bashrc" "$HOME/Library/Application Support/iTerm2/DynamicProfiles/break-glass-rescue.json"
#
# The verifier is config-dir-INVARIANT on purpose: registration-state.sh re-runs it once per config
# dir, and both artifacts are facts about the one live root (~/.claude) and the one iTerm2 install.
#
# ══ 0081 — install the no-tty break-glass kit (incident 2026-10-25, DESIGN.md C5) ════════════════
# WHAT. On 2026-10-25 one poisoned devfs node made every zsh and /usr/bin/login hang in ttyname(),
# so no terminal could start a shell. The kit that still works runs /bin/bash with no tty:
#   1. ~/.claude/scripts/break-glass/{rescue.sh,rescue.bashrc} — per-file symlinks into this checkout.
#      install.sh globs scripts/*.sh top level and named subdirs only, so this directory needs its
#      own link pass; the Hammerspoon chooser and the Rescue profile both call these paths.
#   2. ~/Library/Application Support/iTerm2/DynamicProfiles/break-glass-rescue.json — the "Rescue"
#      profile, rendered from config/iterm2/break-glass-rescue.json with this $HOME. Non-default, so it
#      stays dormant; it runs bash --noprofile --rcfile rescue.bashrc -i, never /usr/bin/login.
#   3. `hs -t 5 -c 'hs.reload()'` when the Hammerspoon config registers hsc.breakglass, so the
#      ⌃⌥⌘⇧B chooser and the lockwatch menubar load (hammerspoon-config holds the registry line).
#
# WHY MECHANICAL. README.md limits c10 to settings.json, a launchd plist or credentials; this touches
# none of them. The one human step is the TCC click "Hammerspoon wants to control iTerm2" the first
# time "Open Rescue terminal" runs (DESIGN.md §8 H6).
#
# SAFETY. A real (non-symlink) file at a link path, or a profile JSON that is not ours (no Guid
# cc-break-glass-rescue-0001), is refused, never clobbered. Idempotent: a re-run rewrites the same
# links and the same rendered profile. Revert: `bash migrations/0081-break-glass-install.sh --undo`
# removes exactly what this wrote (the links, our profile) and reloads Hammerspoon.
set -uo pipefail

REPO="${CC_MIGRATION_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LIVE="${CC_MIGRATION_LIVE_ROOT:-$HOME/.claude}"
PROF_DIR="${CC_ITERM_DYNPROFILES:-$HOME/Library/Application Support/iTerm2/DynamicProfiles}"
PROF="$PROF_DIR/break-glass-rescue.json"
GUID=cc-break-glass-rescue-0001
SRC_PROF="$REPO/config/iterm2/break-glass-rescue.json"
HS_INIT="${CC_HS_INIT:-$HOME/.hammerspoon/init.lua}"

die() { printf '0081: %s\n' "$*" >&2; exit 1; }

hs_bin() {
  local h
  for h in "${CC_HS_BIN:-}" /opt/homebrew/bin/hs /usr/local/bin/hs; do
    [ -n "$h" ] && [ -x "$h" ] && { printf '%s' "$h"; return 0; }
  done
  return 1
}

# hs_reload — only when the registry line is present, bounded by hs's own -t (never an outer timeout:
# hammerspoon-config 826a324). A reload that the IPC drops mid-call returns non-zero; that is normal.
hs_reload() {
  local h
  [ -z "${CC_MIGRATION_NO_HS:-}" ] || { printf '0081: hs reload skipped (CC_MIGRATION_NO_HS)\n'; return 0; }
  if ! grep -q 'hsc.breakglass' "$HS_INIT" 2>/dev/null; then
    printf '0081: Hammerspoon registry has no hsc.breakglass yet — reload skipped (it loads on the next reload)\n'
    return 0
  fi
  h="$(hs_bin)" || { printf '0081: hs CLI not found — Hammerspoon reloads the module on its next start\n'; return 0; }
  "$h" -t 5 -c 'hs.reload()' >/dev/null 2>&1 || true
  printf '0081: Hammerspoon reloaded (%s -t 5)\n' "$h"
}

link() { # <name>
  local src="$REPO/scripts/break-glass/$1" dst="$LIVE/scripts/break-glass/$1"
  [ -f "$src" ] || die "source missing: $src"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then die "$dst is a real file — refusing to replace it"; fi
  ln -sfn "$src" "$dst" || die "ln $dst failed"
  printf '0081: linked %s -> %s\n' "$dst" "$src"
}

ours() { [ -f "$PROF" ] && grep -q "\"$GUID\"" "$PROF"; }

case "${1:-}" in
  --verify)
    [ -L "$LIVE/scripts/break-glass/rescue.sh" ] && [ -f "$LIVE/scripts/break-glass/rescue.sh" ] \
      && [ -f "$LIVE/scripts/break-glass/rescue.bashrc" ] && ours && grep -q rescue.bashrc "$PROF"
    exit $? ;;
  --undo)
    for n in rescue.sh rescue.bashrc; do
      d="$LIVE/scripts/break-glass/$n"
      if [ -L "$d" ]; then rm -f "$d" && printf '0081: removed link %s\n' "$d"; fi
    done
    if ours; then rm -f "$PROF" && printf '0081: removed profile %s\n' "$PROF"; fi
    hs_reload
    exit 0 ;;
  '') ;;
  *) die "usage: 0081-break-glass-install.sh [--verify|--undo]" ;;
esac

mkdir -p "$LIVE/scripts/break-glass" "$LIVE/autonomy/break-glass" || die "cannot create $LIVE dirs"
link rescue.sh
link rescue.bashrc

[ -f "$SRC_PROF" ] || die "profile template missing: $SRC_PROF"
mkdir -p "$PROF_DIR" || die "cannot create $PROF_DIR"
if [ -e "$PROF" ] && ! ours; then die "$PROF exists and is not ours (no Guid $GUID) — refusing to replace it"; fi
home_esc="$(printf '%s' "$HOME" | sed -e 's/[\\|&]/\\&/g')"
sed "s|__HOME__|$home_esc|g" "$SRC_PROF" > "$PROF.tmp.$$" || die "render failed"
/usr/bin/jq -e .Profiles "$PROF.tmp.$$" >/dev/null 2>&1 || { rm -f "$PROF.tmp.$$"; die "rendered profile is not valid JSON"; }
mv -f "$PROF.tmp.$$" "$PROF" || die "mv $PROF failed"
printf '0081: profile "Rescue" written to %s\n' "$PROF"

hs_reload
bash "$0" --verify || die "verify failed after install"
printf '0081: break-glass kit installed\n'
exit 0
