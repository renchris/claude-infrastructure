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
# Overridable so a sandbox test cannot be forced to share — and therefore destroy — the one
# store that says whether the OPERATOR's kitty is still shimmed.
LOG="${KITTY_TITLE_BAND_LOG:-/tmp/kitty-title-band-watcher.log}"
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
  # THREE states, not two. A DESTROYED or truncated log must not read as "not installed" —
  # that is the healthy-looking answer, and it would be returned over a process that is STILL
  # PATCHED. This log is the only evidence of the live shim and two things erased it (this
  # script's own install truncation, and shim-verify's cleanup), so absence is genuinely UNKNOWN.
  [ -f "$LOG" ] || { printf 'unknown (no log)'; return; }
  # ONE capture. `grep -c`/`grep` print a valid answer AND exit non-zero on no match, so appending
  # `|| echo 0` puts a second producer on the same stream and the caller reads "0\n0".
  last="$(grep -E "^(un)?installed pid=${pid}\$" "$LOG" 2>/dev/null | tail -1)" || true
  case "$last" in
    installed*)   printf 'INSTALLED' ;;
    uninstalled*) printf 'not installed' ;;
    # The log exists but names nothing for THIS pid — what a truncation leaves behind. Report the
    # ignorance; do not manufacture an all-clear.
    *)            printf 'unknown (no record for pid %s)' "$pid" ;;
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
  # --shim-state <socket-path>: print this instance's verdict and nothing else. Reads the log,
  # touches no socket, changes nothing. Exists so the three-state logic has a red-proof.
  --shim-state) shim_state "${2:-}"; printf '\n'; exit 0 ;;
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
  *) die "usage: $0 [--status|--revert|--shim-state <socket-path>]" ;;
esac

# ── THE DISARM INTERLOCK, 2026-09-16 ─────────────────────────────────────────────────────────
# ⌘⇧B SIGSEGV'd kitty (pid 597, 2026-09-16 20:13:49): EXC_BAD_ACCESS KERN_INVALID_ADDRESS at
# 0x20 in kitty.fast_data_types.so+840952, via glfw-cocoa -> Python key dispatch. Every pane in
# the only OS window died with it; lr-select then found 55 resumable sessions across 16
# worktrees. Report ~/Library/Logs/DiagnosticReports/kitty-2026-09-16-201349.ips, filed as
# cc-backlog bf6af099a712.
#
# WHY THE INTERLOCK IS HERE AND NOT IN A COMMENT. Disarming the CHORD in kitty.conf does not
# disarm this script: `install` rewrites the drop-in with both map lines AND a `watcher` line,
# and that watcher is what makes every kitty started afterwards inject the shim INTO ITSELF.
# That is not hypothetical — it is exactly how the shim came back after the crash. kitty died at
# 20:13:49, the successor started at 20:13:53 while the drop-in was still armed, and the log's
# last record for the live process reads `installed pid=73832`. A doc that says "do not re-arm"
# advises; the enforcement has to live at the event that IS the act.
#
# SINGLE SOURCE OF TRUTH: the same `# DISARMED-` marker tests/kitty-conf-bindings.bats keys its
# polarity on, read from the config kitty ACTUALLY loads. Lift the disarm and this lifts with
# it — no second switch to remember, and no way to re-arm half of it.
KCONF="${KCONF:-$HOME/.config/kitty/kitty.conf}"
if [ "$MODE" != "--revert" ] && [ "$MODE" != "revert" ] \
   && grep -q '^# DISARMED-map cmd+' "$KCONF" 2>/dev/null; then
  printf '\n\033[31m\033[1mREFUSING TO INSTALL — the title band is DISARMED.\033[0m\n' >&2
  printf 'The chord it arms SIGSEGV\x27d kitty on 2026-09-16 and killed ~55 live sessions.\n' >&2
  printf 'Marker: %s carries a %s line.\n' "$KCONF" "'# DISARMED-map cmd+'" >&2
  printf 'Open row: cc-backlog bf6af099a712 — reproduce the fault in a sandbox and fix it FIRST.\n' >&2
  printf 'To lift: remove the two %s prefixes in config/kitty.conf, land it, converge.\n' "'# DISARMED-'" >&2
  printf '\nThis refusal is a VERDICT, not a bug. --revert and --status still work.\n' >&2
  exit 3
fi

[ -f "$WATCHER" ] || die "missing $WATCHER — land the branch and run scripts/deploy-live.sh first"
[ -f "$SCRIPTS/kitty-pane-title-toggle.sh" ] || die "missing $SCRIPTS/kitty-pane-title-toggle.sh"

printf '\n\033[1mInstalling the zero-shift title band into running kitty instances\033[0m\n'
installed=0; failed=0
# NOT truncated. shim_state()'s own contract is "the LAST line naming this pid wins, because
# install and uninstall both append" — i.e. an APPEND-ONLY log. Truncating here discarded the
# records of every OTHER live kitty, which is exactly the per-instance verdict it exists to give.
: >> "$LOG" 2>/dev/null || true
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
