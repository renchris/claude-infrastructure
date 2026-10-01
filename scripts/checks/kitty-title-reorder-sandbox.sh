#!/usr/bin/env bash
# kitty-title-reorder-sandbox.sh — prove the ⌘⇧B title bars of e5116d0fb reorder panes, in a SEPARATE
# stock kitty process, without moving a single live pane. Backlog 5818e5aea957, ticket kitty.1.
#
# WHAT IT DOES
#   1. Records every running kitty's pid + start time (the operator's live kitty included).
#   2. Starts a second /Applications/kitty.app process on the live kitty.conf (the symlink into this
#      repo) with its OWN listen socket, config dir, cache dir and HOME, and three throwaway panes.
#   3. Raises the title bars by running the ⌘⇧B action itself — the `map cmd+shift+b …` line read out
#      of kitty.conf at run time, sent with `kitten @ action` — and checks that bars really came up.
#   4. Drops pane 1 on pane 3's title bar through kitty's own drop callback
#      (scripts/checks/kitty-title-reorder-drop.py, the remote-control path kitty-drag-window.py uses)
#      and logs `kitten @ ls` window order before and after.
#   5. Tears the sandbox down and checks every pre-existing kitty is still the same process.
#
# WHY THE SANDBOX HAS ITS OWN HOME. The ⌘⇧B action launches kitty-pane-title-overlay.py and
# kitty-pane-title-toggle.sh, which keep their state, lock and daemon socket under ~/.claude/autonomy.
# Run under the real HOME, the overlay's `off --all` would reach the LIVE overlay daemon and wipe the
# operator's pane titles. The sandbox HOME symlinks ~/.claude/scripts and the live kitty config files
# in, and gives every state directory a private copy, so the action is the real one and its effects
# stay inside the sandbox. No synthetic mouse or keyboard event is ever posted.
#
# Usage:  bash scripts/checks/kitty-title-reorder-sandbox.sh
# Exit:   0 the drop reordered the panes and every pre-existing kitty is unchanged · 1 any check failed
#         2 setup failed (no stock kitty, sandbox did not start)
# Env:    KITTY_APP (default /Applications/kitty.app) · KTRS_DIR (default /private/tmp/ktrs — outside the
#         /tmp/kitty-* glob the fleet's socket tooling scans)
set -uo pipefail

APP="${KITTY_APP:-/Applications/kitty.app}"
KITTY="$APP/Contents/MacOS/kitty"
KITTEN="$APP/Contents/MacOS/kitten"
SB="${KTRS_DIR:-/private/tmp/ktrs}"
SOCK="unix:$SB/sock"
REAL_HOME="$HOME"
_self="$0"
while [ -L "$_self" ]; do _d="$(cd "$(dirname "$_self")" && pwd)"; _self="$(readlink "$_self")"; case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac; done
SELF_DIR="$(cd "$(dirname "$_self")" && pwd)"
DROP_PY="$SELF_DIR/kitty-title-reorder-drop.py"
PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
k()   { env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID HOME="$SB/home" "$KITTEN" @ --to "$SOCK" "$@"; }

[ -x "$KITTY" ] && [ -x "$KITTEN" ] || { echo "no stock kitty at $APP"; exit 2; }
[ -r "$DROP_PY" ] || { echo "missing $DROP_PY"; exit 2; }
LIVE_CONF_DIR="$REAL_HOME/.config/kitty"
[ -e "$LIVE_CONF_DIR/kitty.conf" ] || { echo "no live kitty.conf at $LIVE_CONF_DIR"; exit 2; }

# pid + start time, so a crash-and-relaunch of a live kitty reads as a change, not a match.
kitty_census() { /bin/ps -axo pid=,lstart=,comm= | awk -v k="$KITTY" '$NF == k { $NF=""; print }' | sort; }
BEFORE_CENSUS="$(kitty_census)"
echo "== pre-existing kitty processes =="; printf '%s\n' "${BEFORE_CENSUS:-  (none)}"

echo "== sandbox setup: $SB =="
k action quit >/dev/null 2>&1   # a previous run may still own the socket
mkdir -p "$SB/home/.claude/autonomy" "$SB/home/.config/kitty" "$SB/cache" "$SB/logs"
ln -sfn "$REAL_HOME/.claude/scripts" "$SB/home/.claude/scripts"
for f in kitty.conf kitty-title-on.conf kitty-title-off.conf drag-arm.d; do
  [ -e "$LIVE_CONF_DIR/$f" ] && ln -sfn "$LIVE_CONF_DIR/$f" "$SB/home/.config/kitty/$f"
done
rm -f "$SB/home/.claude/autonomy/kitty-title-state" "$SB/sock"
printf 'new_tab reorder-sandbox\nlayout splits\nlaunch --title "PANE-1" sleep 86400\nlaunch --location=hsplit --title "PANE-2" sleep 86400\nlaunch --location=hsplit --title "PANE-3" sleep 86400\n' > "$SB/session"

( cd "$SB" && env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID HOME="$SB/home" \
    KITTY_CONFIG_DIRECTORY="$SB/home/.config/kitty" KITTY_CACHE_DIRECTORY="$SB/cache" \
    nohup "$KITTY" --config "$SB/home/.config/kitty/kitty.conf" --session "$SB/session" \
      --listen-on "$SOCK" --directory "$SB" > "$SB/logs/kitty.log" 2>&1 & )
# A sandbox OS window is still a terminal surface: leave the pane-spawn row, so the census's
# "no row ⇒ spawned outside this tree" inference stays true.
# shellcheck source=/dev/null
[ -r "$SELF_DIR/../lib/pane-spawn-log.sh" ] && . "$SELF_DIR/../lib/pane-spawn-log.sh" || true
command -v cc_log_pane_spawn >/dev/null 2>&1 && \
  cc_log_pane_spawn os-window kitty "" "$SB" "kitty-title-reorder-sandbox, 3 panes, sock:$SB/sock" || true
for _ in $(seq 1 30); do [ -S "$SB/sock" ] && k ls >/dev/null 2>&1 && break; sleep 1; done
sleep 2
SB_PID="$(k ls 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["tabs"][0]["windows"][0]["pid"])' 2>/dev/null)"
SB_KITTY="$(/bin/ps -o ppid= -p "${SB_PID:-0}" 2>/dev/null | tr -d ' ')"
case "${SB_KITTY:-}" in ''|*[!0-9]*) echo "  sandbox did not start (see $SB/logs/kitty.log)"; exit 2 ;; esac
echo "  sandbox kitty pid $SB_KITTY on $SOCK"

# VISUAL order, read off kitty's neighbors graph: start at the pane with no left and no top neighbour
# and walk right (then down). The window LIST order is the wrong instrument here — in the splits
# layout a swap moves panes in the split tree and leaves the list order alone (measured: a real swap
# read [1 2 3] -> [1 2 3] by list order).
order() { k ls 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
ws={w["id"]:(w.get("neighbors") or {}) for o in d for t in o["tabs"] for w in t["windows"]}
start=[i for i,n in ws.items() if not n.get("left") and not n.get("top")]
seq=[]; cur=start[0] if len(start)==1 else None
while cur is not None and cur not in seq:
    seq.append(cur); n=ws[cur]; nxt=(n.get("right") or n.get("bottom") or [None])[0]; cur=nxt
print(" ".join(str(i) for i in seq) if len(seq)==len(ws) else "UNREADABLE")'; }
titles() { k ls 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
print(" ".join(w["title"] for o in d for t in o["tabs"] for w in t["windows"]))'; }
rows() { k ls 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
print(",".join(str(w["lines"]) for o in d for t in o["tabs"] for w in t["windows"]))'; }

echo "== raise the title bars with the ⌘⇧B action =="
ACTION="$(awk '$1 == "map" && $2 == "cmd+shift+b" { $1=""; $2=""; sub(/^  /, ""); print; exit }' "$LIVE_CONF_DIR/kitty.conf")"
ACTION="${ACTION//\$\{HOME\}/$SB/home}"
[ -n "$ACTION" ] || { bad "no 'map cmd+shift+b' line in kitty.conf"; }
echo "  action: $ACTION"
R0="$(rows)"
# shellcheck disable=SC2086  # the action is a word list, exactly as kitty's own map parser splits it
k action $ACTION >/dev/null 2>&1
for _ in $(seq 1 10); do [ "$(cat "$SB/home/.claude/autonomy/kitty-title-state" 2>/dev/null)" = on ] && break; sleep 1; done
sleep 2
STATE="$(cat "$SB/home/.claude/autonomy/kitty-title-state" 2>/dev/null)"
R1="$(rows)"
printf '  toggle state=%s  rows %s -> %s\n' "${STATE:-unset}" "$R0" "$R1"
[ "$STATE" = on ] && ok "the ⌘⇧B action ran its toggle in the sandbox (state on)" || bad "the toggle never recorded state on"

echo "== drop PANE-1 on PANE-3's title bar =="
O0="$(order)"; T0="$(titles)"
read -r SRC _ DST <<< "$O0"
echo "  before: order [$O0]  titles [$T0]"
RES="$(k kitten "$DROP_PY" "$SRC" "$DST" 2>&1)"
sleep 1
O1="$(order)"; T1="$(titles)"
echo "  kitten: $RES"
echo "  after:  order [$O1]  titles [$T1]"
printf '%s\n' "$RES" > "$SB/logs/drop.json"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if d["show_title_bar"]["dst"] else 1)' "$RES" 2>/dev/null \
  && ok "the destination pane's title bar was up at the drop (the hit test needs it)" \
  || bad "the destination pane had no title bar at the drop"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if d.get("ok") else 1)' "$RES" 2>/dev/null \
  && ok "kitty's drop callback ran without error" || bad "drop callback failed: $RES"
if [ "$O0" = UNREADABLE ] || [ "$O1" = UNREADABLE ] || [ -z "$O0" ]; then
  bad "the visual order could not be read off the neighbors graph ([$O0] -> [$O1])"
elif [ "$(tr ' ' '\n' <<< "$O0" | sort | tr '\n' ' ')" != "$(tr ' ' '\n' <<< "$O1" | sort | tr '\n' ' ')" ]; then
  bad "the set of panes changed ([$O0] -> [$O1]); a set change is churn, not a reorder"
elif [ "$O0" != "$O1" ]; then
  ok "the panes reordered: [$O0] -> [$O1]"
else
  bad "the order did not change: [$O0]"
fi

echo "== teardown =="
for w in $O1; do k close-window --match "id:$w" >/dev/null 2>&1; done
k action quit >/dev/null 2>&1
for _ in $(seq 1 10); do kill -0 "$SB_KITTY" 2>/dev/null || break; sleep 1; done
kill -0 "$SB_KITTY" 2>/dev/null && kill -TERM "$SB_KITTY" 2>/dev/null   # our own pid only
HOME="$SB/home" python3 "$REAL_HOME/.claude/scripts/kitty-pane-title-overlay.py" stop >/dev/null 2>&1
sleep 1
kill -0 "$SB_KITTY" 2>/dev/null && bad "the sandbox kitty $SB_KITTY is still running" || ok "the sandbox kitty exited"

AFTER_CENSUS="$(kitty_census)"
if [ "$AFTER_CENSUS" = "$BEFORE_CENSUS" ]; then
  ok "every pre-existing kitty is the same process, same start time"
else
  bad "the kitty census changed:"; printf '    before: %s\n    after:  %s\n' "$BEFORE_CENSUS" "$AFTER_CENSUS"
fi

printf '\n== RESULT: %d passed, %d failed ==\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && echo "verdict=REORDERED" || echo "verdict=FAILED"
[ "$FAIL" -eq 0 ]
