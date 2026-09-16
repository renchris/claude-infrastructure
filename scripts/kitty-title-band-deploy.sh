#!/usr/bin/env bash
# Put the zero-shift pane title band into every kitty that is ALREADY RUNNING, and arm ⌘⇧B for it.
#
#   bash ~/.claude/scripts/kitty-title-band-deploy.sh            install, arm, verify
#   bash ~/.claude/scripts/kitty-title-band-deploy.sh --status    report, change nothing
#   bash ~/.claude/scripts/kitty-title-band-deploy.sh --revert    put everything back
#
# WHY THIS IS A SCRIPT THE OPERATOR RUNS. Every step here is reversible and none of it spends
# money, so an agent would normally just do it. It cannot: auto mode's classifier refuses an agent
# any write to a LIVE terminal session, which is the right rule -- the sessions in those panes are
# other agents doing real work. So the whole thing is driven here instead of handed over as steps.
#
# WHAT IT CHANGES, and how to undo each:
#   1. Injects scripts/kitty-title-band-watcher.py into each running kitty. That is a pure-Python
#      wrapper around Window.set_geometry; it is INERT until title bars are switched on, and
#      --revert restores the original method and relays out.
#   2. Writes two `map` lines and one `watcher` line into ~/.config/kitty/drag-arm.d/drag.conf,
#      a drop-in the main config already globincludes. kitty's own config watcher picks it up in
#      ~100 ms, so ⌘⇧B changes without a restart. --revert empties the file again.
#      🚨 It is EMPTIED, never deleted: a deletion does not fire kitty's config watcher, so a
#      deleted drop-in stays armed until something else touches the config.
#
# AFTER IT RUNS: ⌘⇧B raises a real, draggable title bar on every pane that costs no rows, does not
# move the content, does not scroll away, and shows a hand on hover. ⌘⌥B keeps the styled
# graphics-protocol glance. The band's text is the terminal font; the system sans face needs the
# patched kitty in docs/patches/kitty-window-title-band.patch, which needs a restart to take.
set -uo pipefail

SCRIPTS="${SCRIPTS:-$HOME/.claude/scripts}"
WATCHER="$SCRIPTS/kitty-title-band-watcher.py"
UNWATCHER="$SCRIPTS/kitty-title-band-unwatcher.py"
DROPIN="${DROPIN:-$HOME/.config/kitty/drag-arm.d/drag.conf}"
LOG=/tmp/kitty-title-band-watcher.log
MODE="${1:-install}"

# Every in-tree site that creates a terminal surface leaves ONE row, so the pane census's "a pane
# with no row was spawned by something outside this tree" inference stays true. The overlays below
# are transient -- they exist for 0.2s to carry a watcher module in -- but a pane is a pane.
# shellcheck source=/dev/null
for _c in "$SCRIPTS/lib/pane-spawn-log.sh" "$HOME/.claude/scripts/lib/pane-spawn-log.sh"; do
  [ -r "$_c" ] && { . "$_c"; break; }
done
_ktb_log_spawn() {  # _ktb_log_spawn <note>
  command -v cc_log_pane_spawn >/dev/null 2>&1 && \
    cc_log_pane_spawn overlay kitty "" "$PWD" "$1" || true
}

die() { printf '\033[31m✗\033[0m %s\n' "$1" >&2; exit 1; }
say() { printf '  %s\n' "$1"; }
ok()  { printf '\033[32m✓\033[0m %s\n' "$1"; }

kitty_bin() {
  for c in /Applications/kitty.app/Contents/MacOS/kitty "$(command -v kitty 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}
KITTY="$(kitty_bin)" || die "no kitty binary found"

# Live control sockets only. The glob also matches DIRECTORIES on this machine (the kitty source
# trees were once symlinked under /tmp), so the socket test is not decoration.
sockets() { for s in /tmp/kitty-*; do [ -S "$s" ] && printf '%s\n' "$s"; done; }

k() { env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID "$KITTY" @ --to "unix:$1" "${@:2}"; }
geom() { k "$1" ls 2>/dev/null | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: print('unreadable'); raise SystemExit
print(','.join('%dx%d' % (w['lines'], w['columns']) for o in d for t in o['tabs'] for w in t['windows']))"; }

ARMED_MARK='# --- kitty title band (scripts/kitty-title-band-deploy.sh) ---'
arming_lines() {
  cat <<EOF
$ARMED_MARK
# ⌘⇧B raises the zero-shift band: clear the graphics glance first so there is exactly ONE bar on
# screen and it is the one that answers the mouse, then flip window_title_bar_min_windows.
map cmd+shift+b combine : launch --type=background --allow-remote-control \${HOME}/.claude/scripts/kitty-pane-title-overlay.py off --all : launch --type=background --allow-remote-control \${HOME}/.claude/scripts/kitty-pane-title-toggle.sh toggle
# ⌘⌥B keeps the styled glance, and clears the real bars first for the same reason.
map cmd+opt+b combine : launch --type=background --allow-remote-control \${HOME}/.claude/scripts/kitty-pane-title-toggle.sh off : launch --type=background --allow-remote-control \${HOME}/.claude/scripts/kitty-pane-title-overlay.py toggle
# So a kitty started later installs the shim for itself.
watcher \${HOME}/.claude/scripts/kitty-title-band-watcher.py
EOF
}

shim_state() {  # shim_state <socket path> -> INSTALLED | not installed
  # kitty names its socket /tmp/kitty-<pid> (listen_on unix:/tmp/kitty-{kitty_pid}), so the owning
  # pid is in the path -- which is what lets one shared log give a PER-INSTANCE verdict. A bare
  # "installed" line in that log may have been written by a sandbox run against another kitty.
  # The LAST line naming this pid wins, because install and uninstall both append.
  local pid="${1##*/kitty-}" last
  case "$pid" in ''|*[!0-9]*) printf 'unknown (socket not named /tmp/kitty-<pid>)'; return ;; esac
  [ -f "$LOG" ] || { printf 'not installed'; return; }
  # ONE capture. `grep -c`/`grep` print a valid answer AND exit non-zero on no match, so appending
  # `|| echo 0` puts a second producer on the same stream and the caller reads "0\n0".
  last="$(grep -E "^(un)?installed pid=${pid}\$" "$LOG" 2>/dev/null | tail -1)" || true
  case "$last" in
    installed*) printf 'INSTALLED' ;;
    *)          printf 'not installed' ;;
  esac
}

status() {
  printf '\n\033[1mkitty title band — status\033[0m\n'
  local n=0
  while read -r s; do
    [ -n "$s" ] || continue
    n=$((n+1))
    say "socket $s  panes: $(geom "$s")  shim: $(shim_state "$s")"
  done < <(sockets)
  [ "$n" -gt 0 ] || say "no running kitty with a control socket"
  if [ -s "$DROPIN" ] && grep -q 'kitty-title-band' "$DROPIN" 2>/dev/null; then
    say "drop-in  $DROPIN: ARMED"
  else
    say "drop-in  $DROPIN: not armed"
  fi
  if [ -f "$LOG" ]; then say "watcher log: $LOG (shared with sandbox runs; the per-socket line above is the live verdict)"; fi
}

case "$MODE" in
  --status|status) status; exit 0 ;;
  --revert|revert)
    [ -f "$UNWATCHER" ] || die "missing $UNWATCHER — land and converge the repo first"
    n=0
    while read -r s; do
      [ -n "$s" ] || continue
      before="$(geom "$s")"
      tmp="/tmp/ktb-unwatch-$$-$RANDOM.py"; cp "$UNWATCHER" "$tmp"
      k "$s" launch --type=overlay --watcher "$tmp" sh -c 'sleep 0.2' >/dev/null 2>&1
      _ktb_log_spawn "kitty-title-band-deploy --revert: transient overlay carrying the unwatcher into $s"
      sleep 2
      say "$s: $before -> $(geom "$s")"
      n=$((n+1))
    done < <(sockets)
    # EMPTIED, not deleted: a deletion does not fire kitty's config watcher.
    [ -e "$DROPIN" ] && : > "$DROPIN"
    ok "reverted $n running kitty instance(s); drop-in emptied so ⌘⇧B is back to the glance"
    status
    exit 0 ;;
  install|--install) : ;;
  *) die "usage: $0 [--status|--revert]" ;;
esac

[ -f "$WATCHER" ] || die "missing $WATCHER — land the branch and run scripts/deploy-live.sh first"
[ -f "$SCRIPTS/kitty-pane-title-toggle.sh" ] || die "missing $SCRIPTS/kitty-pane-title-toggle.sh"

printf '\n\033[1mInstalling the zero-shift title band into running kitty instances\033[0m\n'
installed=0; failed=0
: > "$LOG" 2>/dev/null || true
while read -r s; do
  [ -n "$s" ] || continue
  before="$(geom "$s")"
  # A FRESH path per injection: kitty memoises watcher modules by path, so re-running this script
  # with the same filename would be a silent no-op.
  tmp="/tmp/ktb-watch-$$-$RANDOM.py"; cp "$WATCHER" "$tmp"
  k "$s" launch --type=overlay --watcher "$tmp" sh -c 'sleep 0.2' >/dev/null 2>&1
  _ktb_log_spawn "kitty-title-band-deploy: transient overlay carrying the title-band shim into $s"
  sleep 2
  after="$(geom "$s")"
  if [ "$before" = "$after" ]; then
    say "$s: installed, $before unchanged"
    installed=$((installed+1))
  else
    printf '  %s: \033[31mPANES MOVED\033[0m %s -> %s\n' "$s" "$before" "$after"
    failed=$((failed+1))
  fi
done < <(sockets)

if grep -q 'installed' "$LOG" 2>/dev/null || [ "$installed" -gt 0 ]; then
  ok "shim live in $installed instance(s)"
else
  die "the shim did not install in any instance (see $LOG)"
fi
[ "$failed" -eq 0 ] || die "$failed instance(s) resized on injection — run --revert"

mkdir -p "$(dirname "$DROPIN")"
if grep -q 'kitty-title-band' "$DROPIN" 2>/dev/null; then
  say "drop-in already armed, leaving it alone"
else
  arming_lines > "$DROPIN"
  sleep 1
  ok "armed ⌘⇧B via $DROPIN (kitty's own config watcher picks it up in ~100ms)"
fi

printf '\n\033[1mPress ⌘⇧B.\033[0m A title bar appears on every pane; nothing below it moves.\n'
printf 'Hover it for the hand cursor, drag a pane onto another pane'"'"'s bar to swap them.\n'
printf 'Undo everything: bash %s --revert\n' "$0"
status
