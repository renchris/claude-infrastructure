#!/bin/bash
# lr-recon-canary-hook.sh — HF_CANARY_HOOK for the W5b real canaries (handoff-fire hf_canary_hook).
#
#   <hook> <point> <pane> <sid> <caller pid>
#
# Acts only when the driver armed THIS sid at THIS point: $LR_CANARY_DIR/hook/<sid>.<point> exists.
# The arm is consumed (renamed .fired) before acting, so a retry of the same attempt never re-fires.
#   after-confirm    type a one-line draft (no Enter) into the canary's own kitty window: canary 2
#   before-relaunch  SIGKILL the calling watcher before it takes the launch lock: canary 3
# The window id comes from the driver ($LR_CANARY_DIR/win/<sid>), never from the pane argument, so the
# hook can only ever type into a window the canary driver created.
set -u
point="${1:-}" sid="${3:-}" caller="${4:-}"
dir="${LR_CANARY_DIR:-/tmp/lr-canary}"
arm="$dir/hook/$sid.$point"
[ -n "$sid" ] && [ -e "$arm" ] || exit 0
mv -f "$arm" "$arm.fired" 2>/dev/null || exit 0
log="$dir/hook.log"
case "$point" in
  after-confirm)
    win="$(cat "$dir/win/$sid" 2>/dev/null)"
    [ -n "$win" ] || { echo "$(date +%s) $point $sid: no window recorded" >> "$log"; exit 0; }
    "${LR_KITTEN_BIN:-/Applications/kitty.app/Contents/MacOS/kitten}" @ --to "$(cat "$dir/sock")" \
      send-text --match "id:$win" "canary draft $(date +%s)" >/dev/null 2>&1
    sleep 1.5   # the TUI renders the text before handoff-fire's last read looks
    echo "$(date +%s) $point $sid: draft typed into window $win" >> "$log" ;;
  before-relaunch)
    echo "$(date +%s) $point $sid: SIGKILL watcher pid $caller" >> "$log"
    kill -9 "$caller" 2>/dev/null ;;
  *) echo "$(date +%s) $point $sid: unknown point" >> "$log" ;;
esac
exit 0
