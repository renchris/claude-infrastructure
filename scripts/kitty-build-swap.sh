#!/usr/bin/env bash
# kitty-build-swap.sh — stage, adopt and roll back the patched kitty build, one verb per step.
#
# THE BUILD. ~/ktb carries docs/patches/kitty-window-title-band.patch (the one draggable,
# ⌘⇧B-toggled title band, text width by default) and docs/patches/kitty-upstream-defects.patch (the
# fonts_data and tick_lock guards) on v0.48.2; `make app` there gives a relocatable kitty.app.
#
# THE ADOPTION ORDER (2026-09-30 backlog master plan, tickets kitty.3-kitty.5):
#   stage     agent    copy the built bundle to $APPS/kitty.app.staged (not a .app name, so
#                      LaunchServices never registers a second net.kovidgoyal.kitty)
#   (sitting) operator answers yes or no on the patched build
#   arm       agent    after a yes: write the kitty-restart-pending marker that
#                      scripts/alarm-reboot-prep.sh prints at the next capacity-alarm reboot
#   swap      operator the LAST step before that reboot: rename kitty.app -> kitty.app.stock and
#                      kitty.app.staged -> kitty.app, and point ⌘⇧B's ON half at the band
#                      (config/kitty-title-band-on.conf). Renames only, so the running kitty keeps
#                      its open files and the swap takes effect when kitty next starts.
#   verify    agent    after login: the running kitty is the patched bundle, started after the swap
#   rollback  anyone   the exact inverse of swap; takes effect at the next kitty start
#
# 🚨 swap and rollback are the only verbs that touch the live app, and both refuse unless
# --confirm names the target bundle path. Neither restarts kitty: a restart closes every pane, so
# it rides a reboot the operator is already doing. --dry-run checks every precondition and prints
# the renames without making them.
#
# Usage: kitty-build-swap.sh status
#        kitty-build-swap.sh stage [--from <built kitty.app>]
#        kitty-build-swap.sh arm
#        kitty-build-swap.sh swap --confirm <apps>/kitty.app [--dry-run]
#        kitty-build-swap.sh rollback --confirm <apps>/kitty.app [--dry-run]
#        kitty-build-swap.sh verify [--clear-marker]
# Exit:  0 done / healthy · 1 refused or a check failed (nothing changed unless it says so) · 2 usage
# Env:   KITTY_SWAP_APPS (default /Applications) · KITTY_SWAP_CONF_DIR (default ~/.config/kitty)
#        KITTY_SWAP_REPO (default ~/Development/claude-infrastructure) · KITTY_SWAP_STATE
#        (default ~/.claude/autonomy) · KITTY_SWAP_FROM (default ~/ktb/kitty.app)
#        KITTY_SWAP_TRASH (default ~/.Trash — where a replaced staged bundle goes; never deleted)
set -uo pipefail

APPS="${KITTY_SWAP_APPS:-/Applications}"
CONF_DIR="${KITTY_SWAP_CONF_DIR:-$HOME/.config/kitty}"
REPO="${KITTY_SWAP_REPO:-$HOME/Development/claude-infrastructure}"
STATE="${KITTY_SWAP_STATE:-$HOME/.claude/autonomy}"
FROM="${KITTY_SWAP_FROM:-$HOME/ktb/kitty.app}"
TRASH="${KITTY_SWAP_TRASH:-$HOME/.Trash}"
LIVE="$APPS/kitty.app" STAGED="$APPS/kitty.app.staged" STOCK="$APPS/kitty.app.stock"
MARKER="$STATE/kitty-restart-pending" SWAPLOG="$STATE/kitty-swap.log"
TITLE_ON="$CONF_DIR/kitty-title-on.conf" TITLE_ON_PREV="$STATE/kitty-title-on.prev"
BAND_ON="$REPO/config/kitty-title-band-on.conf" STOCK_ON="$REPO/config/kitty-title-on.conf"
SELF="$HOME/.claude/scripts/kitty-build-swap.sh"

say() { printf '%s\n' "$*"; }

# probe <bundle>: "patched" if its own Python knows the band option, "stock" if it runs but does
# not, "absent"/"broken" otherwise. Runs the bundle's binary headless (+runpy), never a GUI.
probe() {
  local app="$1" out
  [ -x "$app/Contents/MacOS/kitty" ] || { echo absent; return; }
  out="$(env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID "$app/Contents/MacOS/kitty" +runpy \
    'from kitty.options.types import Options; print(getattr(Options, "window_title_bar_overlay_width", "STOCK"))' 2>/dev/null)"
  case "$out" in text|full) echo patched ;; STOCK) echo stock ;; *) echo broken ;; esac
}

version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null || echo '?'; }

need_confirm() {  # need_confirm <given>
  [ "${1:-}" = "$LIVE" ] && return 0
  say "refused: --confirm must name the target bundle exactly: --confirm $LIVE"
  exit 1
}

cmd_status() {
  say "live     $LIVE  $(probe "$LIVE")  v$(version "$LIVE")"
  say "staged   $STAGED  $(probe "$STAGED")"
  say "stock    $STOCK  $(probe "$STOCK")"
  say "⌘⇧B ON   $(readlink "$TITLE_ON" 2>/dev/null || echo "(not a link: $TITLE_ON)")"
  say "marker   $([ -s "$MARKER" ] && head -1 "$MARKER" || echo none)"
}

cmd_stage() {
  local src="$FROM" p
  [ "${1:-}" = --from ] && src="${2:-}"
  p="$(probe "$src")"
  [ "$p" = patched ] || { say "refused: $src probes '$p', not patched — build it with 'make app' in ~/ktb"; exit 1; }
  [ "$(version "$src")" = "$(version "$LIVE")" ] || say "note: staged version $(version "$src") differs from live $(version "$LIVE")"
  if [ -e "$STAGED" ]; then
    mkdir -p "$TRASH" && mv "$STAGED" "$TRASH/kitty.app.staged-$(date +%Y%m%d%H%M%S)" \
      || { say "could not move the old staged bundle aside"; exit 1; }
  fi
  cp -R "$src" "$STAGED.tmp" && mv "$STAGED.tmp" "$STAGED" || { say "copy failed"; exit 1; }
  p="$(probe "$STAGED")"
  [ "$p" = patched ] || { say "staged copy probes '$p'"; exit 1; }
  say "staged $STAGED (patched, v$(version "$STAGED")) from $src"
  say "verdict=STAGED"
}

cmd_arm() {
  [ "$(probe "$STAGED")" = patched ] || { say "refused: nothing patched is staged at $STAGED (run: stage)"; exit 1; }
  mkdir -p "$STATE"
  printf '%s\n' "kitty -> patched build: as the LAST step before rebooting run \`bash $SELF swap --confirm $LIVE\`; after login run \`bash $SELF verify --clear-marker\`; undo with \`bash $SELF rollback --confirm $LIVE\`." > "$MARKER"
  say "armed: $MARKER"
  say "verdict=ARMED"
}

cmd_swap() {
  local confirm="" dry=0
  while [ $# -gt 0 ]; do case "$1" in --confirm) confirm="${2:-}"; shift 2 ;; --dry-run) dry=1; shift ;; *) exit 2 ;; esac; done
  need_confirm "$confirm"
  local pl ps
  pl="$(probe "$LIVE")"; ps="$(probe "$STAGED")"
  if [ "$pl" = patched ] && [ "$(probe "$STOCK")" = stock ]; then say "already swapped: $LIVE is patched, stock kept at $STOCK"; say "verdict=ALREADY"; return 0; fi
  [ "$pl" = stock ]     || { say "refused: live $LIVE probes '$pl', expected stock"; exit 1; }
  [ "$ps" = patched ]   || { say "refused: staged $STAGED probes '$ps', expected patched"; exit 1; }
  [ ! -e "$STOCK" ]     || { say "refused: $STOCK already exists; resolve it first (status)"; exit 1; }
  [ -r "$BAND_ON" ]     || { say "refused: the ⌘⇧B band drop-in $BAND_ON is missing"; exit 1; }
  say "plan: mv $LIVE -> $STOCK"
  say "plan: mv $STAGED -> $LIVE"
  say "plan: ln -sfn $BAND_ON $TITLE_ON   (previous target saved to $TITLE_ON_PREV)"
  if [ "$dry" = 1 ]; then say "verdict=DRY-RUN-OK (nothing changed)"; return 0; fi
  mkdir -p "$STATE"
  mv "$LIVE" "$STOCK" || { say "rename 1 failed; nothing changed"; exit 1; }
  if ! mv "$STAGED" "$LIVE"; then
    mv "$STOCK" "$LIVE" && say "rename 2 failed; rename 1 undone, nothing changed" || say "rename 2 failed AND undo failed: run rollback"
    exit 1
  fi
  readlink "$TITLE_ON" > "$TITLE_ON_PREV" 2>/dev/null || :
  ln -sfn "$BAND_ON" "$TITLE_ON"
  printf '%s swap %s\n' "$(date +%s)" "$LIVE" >> "$SWAPLOG"
  # Read back with fresh probes, not the renames' exit codes.
  pl="$(probe "$LIVE")"; ps="$(probe "$STOCK")"
  say "read back: live=$pl stock-backup=$ps ⌘⇧B ON -> $(readlink "$TITLE_ON")"
  [ "$pl" = patched ] && [ "$ps" = stock ] || { say "verdict=SWAP-UNVERIFIED"; exit 1; }
  say "verdict=SWAPPED (takes effect when kitty next starts)"
}

cmd_rollback() {
  local confirm="" dry=0 prev
  while [ $# -gt 0 ]; do case "$1" in --confirm) confirm="${2:-}"; shift 2 ;; --dry-run) dry=1; shift ;; *) exit 2 ;; esac; done
  need_confirm "$confirm"
  [ "$(probe "$STOCK")" = stock ] || { say "refused: no stock backup at $STOCK — nothing to roll back to"; exit 1; }
  prev="$(cat "$TITLE_ON_PREV" 2>/dev/null)"; [ -n "$prev" ] || prev="$STOCK_ON"
  local aside="$STAGED"
  [ -e "$STAGED" ] && aside="$TRASH/kitty.app.patched-$(date +%Y%m%d%H%M%S)"
  say "plan: mv $LIVE -> $aside"
  say "plan: mv $STOCK -> $LIVE"
  say "plan: ln -sfn $prev $TITLE_ON"
  if [ "$dry" = 1 ]; then say "verdict=DRY-RUN-OK (nothing changed)"; return 0; fi
  mkdir -p "$(dirname "$aside")"
  mv "$LIVE" "$aside" || { say "rename 1 failed; nothing changed"; exit 1; }
  if ! mv "$STOCK" "$LIVE"; then
    mv "$aside" "$LIVE" && say "rename 2 failed; rename 1 undone, nothing changed" || say "rename 2 failed AND undo failed: $LIVE is missing, the stock app is at $STOCK"
    exit 1
  fi
  ln -sfn "$prev" "$TITLE_ON"
  printf '%s rollback %s\n' "$(date +%s)" "$LIVE" >> "$SWAPLOG"
  local pl; pl="$(probe "$LIVE")"
  say "read back: live=$pl ⌘⇧B ON -> $(readlink "$TITLE_ON")"
  [ "$pl" = stock ] || { say "verdict=ROLLBACK-UNVERIFIED"; exit 1; }
  say "verdict=ROLLED-BACK (takes effect when kitty next starts)"
}

cmd_verify() {
  local clear=0 swapped_at pid started ok=0
  [ "${1:-}" = --clear-marker ] && clear=1
  [ "$(probe "$LIVE")" = patched ] || { say "live $LIVE is not the patched build"; say "verdict=NOT-ADOPTED"; exit 1; }
  swapped_at="$(awk '$2 == "swap" { t = $1 } END { print t + 0 }' "$SWAPLOG" 2>/dev/null)"
  for pid in $(/bin/ps -axo pid=,comm= | awk -v k="$LIVE/Contents/MacOS/kitty" '$2 == k { print $1 }'); do
    started="$(date -j -f '%a %b %d %T %Y' "$(/bin/ps -o lstart= -p "$pid" | sed 's/  */ /g')" +%s 2>/dev/null || echo 0)"
    say "kitty pid $pid started $started (swap at ${swapped_at:-?})"
    [ "${started:-0}" -gt "${swapped_at:-0}" ] && ok=1
  done
  [ "$ok" = 1 ] || { say "verdict=NOT-RESTARTED (no kitty started from $LIVE after the swap)"; exit 1; }
  [ "$clear" = 1 ] && rm -f "$MARKER" && say "cleared $MARKER"
  say "verdict=ADOPTED"
}

case "${1:-}" in
  status)   cmd_status ;;
  stage)    shift; cmd_stage "$@" ;;
  arm)      cmd_arm ;;
  swap)     shift; cmd_swap "$@" ;;
  rollback) shift; cmd_rollback "$@" ;;
  verify)   shift; cmd_verify "$@" ;;
  -h|--help) sed -n '2,38p' "$0" ;;
  *) echo "usage: ${0##*/} status|stage|arm|swap|rollback|verify  (see --help)" >&2; exit 2 ;;
esac
