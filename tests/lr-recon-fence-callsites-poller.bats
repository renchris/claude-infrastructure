#!/usr/bin/env bats
# lr-reset-poller.sh × lr-recon-fence.sh — every poller arm that touches a sid asks the fence first
# (LIMIT_RECOVER_FLEET_V2 W4, § C10). Four arms, the same four cases each:
#   (a) recon.on + owned/<sid> + fresh heartbeat      → the arm does NOT act
#   (b) stale heartbeat + an owned proc still alive  → does NOT act
#   (c) stale heartbeat + owned proc dead ("lapsed") → acts, under locks/<sid>.launch held by the
#       poller (the stub actuator sees LR_LAUNCH_LOCK and its holder pid is one of its ancestors),
#       and the lock is gone after the tick
#   (d) recon.on absent                              → acts exactly as before, no lock
# plus the cc-lr.json lane, SUPERSEDED-BY-LIVE-RUN filed to claimed/, the backup watchdog, and the
# upgrade drainer's defer.
#
# HERMETIC: HOME is BATS_TEST_TMPDIR; every actuator (lr-fleet, it2, tmux, osascript, launchctl,
# pgrep, claude-accounts) is a stub; the only real processes are the `sleep`s this file starts.

SID="7a1e0000-1111-4000-8000-000000000001"

setup() {
  export LR_UPGRADE_AUTO=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  CWD="$BATS_TEST_TMPDIR/cwd"
  S="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$STATE/locks" "$STATE/recon/owned" "$S" "$CWD"
  unset LR_STATE_DIR LR_RECON_ROOT LR_RECORD_ID LR_LAUNCH_LOCK LR_RECON_FENCE_FRESH_S
  unset KITTY_WINDOW_ID CC_TERM_KITTY_TO CC_ACCOUNTS_BIN LR_POLLER_REROUTE LR_REROUTE_EVERY_MIN
  NOW="$(date +%s)"; export LR_RECON_NOW="$NOW" LR_RECON_WAKETIME=0
  export LR_POLLER_NO_CENSUS=1 IT2_WRAPPER_NO_KITTY=1
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket"
  export LR_CC_TUI_LIB="$BATS_TEST_TMPDIR/absent-cc-tui.sh"
  export LR_NUDGE_ENGAGE_S=4 LR_NUDGE_IVL=1
  export ACT_LOG="$BATS_TEST_TMPDIR/act.log" OSA_LOG="$BATS_TEST_TMPDIR/osa.log" LC_LOG="$BATS_TEST_TMPDIR/lc.log"
  : > "$ACT_LOG"; : > "$OSA_LOG"; : > "$LC_LOG"

  # Every actuator stub appends ONE line: who it is, its argv, the lock it inherited, the lock's
  # holder pid and role, and its own ancestor pids — so case (c) can prove the holder is the poller.
  cat > "$S/record-act" <<'STUB'
#!/bin/bash
who="$1"; shift
hp=""; hr=""
if [ -n "${LR_LAUNCH_LOCK:-}" ] && [ -f "$LR_LAUNCH_LOCK/holder" ]; then
  hp="$(sed -n 's/.*"pid":\([0-9]*\).*/\1/p' "$LR_LAUNCH_LOCK/holder")"
  hr="$(sed -n 's/.*"role":"\([^"]*\)".*/\1/p' "$LR_LAUNCH_LOCK/holder")"
fi
p=$$; anc=""
for _ in 1 2 3 4 5 6; do p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"; [ -n "$p" ] || break; anc="$anc $p"; done
printf '%s\targv=%s\tlock=%s\tholder=%s\trole=%s\tanc=%s\n' "$who" "$*" "${LR_LAUNCH_LOCK:-}" "$hp" "$hr" "$anc" >> "${ACT_LOG:?}"
STUB
  export LR_FLEET_BIN="$S/lr-fleet"
  cat > "$LR_FLEET_BIN" <<STUB
#!/bin/bash
"$S/record-act" fleet "\$@"
echo "lr-fleet: DETACHED — driver pid \$\$ is recovering; the verdict arrives as mail."
exit 0
STUB
  # § 2's wake types through cc-tui.sh's cc_tui_submit (W6b, resolution 3), so the actuator stub is
  # a cc-tui library, recorded under the name `tui`. Nudge cases set LR_CC_TUI_LIB to it.
  cat > "$S/cc-tui-stub.sh" <<STUB
cc_tui_submit() {
  "$S/record-act" tui "\$@"
  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"resumed"}]}}\n' \
    "\$(date -u -v+5S +%FT%T.000Z 2>/dev/null || date -u +%FT%T.000Z)" >> "\${IT2_TX:?}"
  return 0
}
STUB
  cat > "$S/tmux" <<STUB
#!/bin/bash
"$S/record-act" tmux "\$@"
exit 0
STUB
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "${OSA_LOG:?}"; exit 1\n' > "$S/osascript"
  printf '#!/bin/bash\nexit 1\n' > "$S/pgrep"
  export LR_LAUNCHCTL_BIN="$S/launchctl"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "${LC_LOG:?}"; exit 0\n' > "$LR_LAUNCHCTL_BIN"
  export LR_SELECT_PGREP_BIN="$S/pgrep"
  cat > "$HOME/bin/claude-accounts" <<'STUB'
#!/bin/bash
case " $* " in *" --rank "*) printf '%b\n' "${RANK_OUT:-none}"; exit 0 ;; esac
echo '{"rows":[{"acct":"next4","session_pct":12,"weekly_pct":40},{"acct":"next2","session_pct":5,"weekly_pct":7}]}'
STUB
  chmod +x "$S"/* "$HOME/bin/claude-accounts"
  export PATH="$S:$PATH"
  SLEEP_PID=""
}

teardown() {
  if [ -n "$SLEEP_PID" ]; then kill "$SLEEP_PID" 2>/dev/null || true; wait "$SLEEP_PID" 2>/dev/null || true; fi
  return 0
}

tick() { LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once; }
plog() { cat "$STATE/poller.log" >&2; cat "$ACT_LOG" >&2; }
acted() { grep -c "^$1	" "$ACT_LOG" || true; }

# ── fence fixtures (the shapes tests/lr-recon-fence.bats builds) ────────────────────────────────
lstart_of() { TZ=UTC LC_ALL=C ps -o lstart= -p "$1" | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//'; }
recon_on() { : > "$STATE/recon.on"; }
owned() { # $1=pid $2=lstart
  printf '{"record_id":"r1","procs":[{"role":"actuator","pid":%s,"lstart":"%s"}]}' "$1" "$2" > "$STATE/recon/owned/$SID"
}
heartbeat() { printf '{"pid":1,"progress":7,"progress_wall":%s}' "$1" > "$STATE/recon/heartbeat"; }
fence_fresh() { recon_on; owned 1 "Thu Jan 1 00:00:00 1970"; heartbeat "$((NOW - 10))"; }
fence_alive() {
  recon_on; sleep 300 3>&- & SLEEP_PID=$!
  owned "$SLEEP_PID" "$(lstart_of "$SLEEP_PID")"; heartbeat "$((NOW - 3600))"
}
fence_lapsed() {
  local p l; recon_on; sleep 300 3>&- & p=$!; l="$(lstart_of "$p")"
  kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true
  owned "$p" "$l"; heartbeat "$((NOW - 3600))"
}
# (c): the actuator ran under the lock, the holder is the poller (an ancestor of the stub, named
# as the taker in launch.log), the role names the arm, and the lock is gone after the tick.
assert_locked_act() { # $1=stub $2=arm
  local line hp
  line="$(grep "^$1	" "$ACT_LOG" | head -1)"
  [ -n "$line" ] || { echo "the $1 stub was never called"; plog; false; }
  [[ "$line" == *"lock=$STATE/locks/$SID.launch	"* ]] || { echo "no launch lock: $line"; false; }
  [[ "$line" == *"role=poller-$2	"* ]] || { echo "wrong role: $line"; false; }
  hp="$(printf '%s' "$line" | sed -n 's/.*holder=\([0-9]*\).*/\1/p')"
  [ -n "$hp" ] || { echo "no holder pid: $line"; false; }
  [[ " $(printf '%s' "$line" | sed -n 's/.*anc=//p') " == *" $hp "* ]] || { echo "holder $hp is not the stub's ancestor: $line"; false; }
  grep -q "$SID	poller-$2	taken	pid=$hp" "$STATE/recon/launch.log" || { cat "$STATE/recon/launch.log"; false; }
  [ ! -e "$STATE/locks/$SID.launch" ] || { echo "lock left behind"; false; }
}
assert_unlocked_act() { # $1=stub
  local line; line="$(grep "^$1	" "$ACT_LOG" | head -1)"
  [ -n "$line" ] || { echo "the $1 stub was never called"; plog; false; }
  [[ "$line" == *"lock=	"* ]] || { echo "a lock with recon.on absent: $line"; false; }
}

# ── arm fixtures ─────────────────────────────────────────────────────────────────────────────────
request() { # $1=file basename (default $SID) — a cc-lr-origin recovery (no hook policy gate)
  mkdir -p "$STATE/requests"
  printf '{"sid":"%s","requested_by":"cc-lr","target":"auto"}\n' "$SID" > "$STATE/requests/${1:-$SID}.json"
}
park_future() {
  # § 2a is an unattended move, so it runs only under the zero-human switch (ruling 1, resolution 8):
  # the fixture sets it in its own $HOME, never the real one.
  : > "$STATE/autorecover.on"
  printf '{"sid":"%s","acct":"next4","cfg":"%s","cwd":"%s","kind":"weekly","reset_at_utc":"2099-01-01T00:00:00Z","parked_at":"2026-09-26T20:55:27Z"}\n' \
    "$SID" "$HOME/.claude-quaternary" "$CWD" > "$STATE/parked/$SID.json"
}
park_ready() { # a reset that has passed, with the transcript §2 and lr-select read
  local proj ts
  proj="$HOME/.claude-quaternary/projects/$(printf '%s' "$CWD" | tr '/' '-')"; mkdir -p "$proj"
  # The death precedes its reset (records 3 h back, reset 10 min back): a turn stamped AFTER the
  # reset is what § 2's wake reads as "it continued on its own", and it would then type nothing.
  ts="$(date -u -v-3H +%FT%T.000Z)"
  {
    printf '{"type":"user","cwd":"%s","gitBranch":"main","timestamp":"%s"}\n' "$CWD" "$ts"
    printf '{"type":"assistant","timestamp":"%s"}\n' "$ts"
    printf '{"type":"assistant","timestamp":"%s","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"limit"}]}}\n' "$ts"
  } > "$proj/$SID.jsonl"
  export IT2_TX="$proj/$SID.jsonl"
  printf '{"sid":"%s","acct":"next4","cfg":"%s","cwd":"%s","kind":"session","reset_at_utc":"%s","parked_at":"2026-01-01T00:00:00Z"}\n' \
    "$SID" "$HOME/.claude-quaternary" "$CWD" "$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ)" > "$STATE/parked/$SID.json"
}
live_row() { # the original pane is alive (pid = this bats process) ⇒ §2 takes the nudge arm
  printf '{"paneUUID":"616","session_id":"%s","pid":%d,"account":"claude-quaternary","cwd":"%s"}\n' "$SID" "$$" "$CWD" > "$CC_REGISTRY_DIR/616.json"
  export LR_CC_TUI_LIB="$S/cc-tui-stub.sh"
}

# ══ § 0 REQUEST ══════════════════════════════════════════════════════════════════════════════════
@test "§0 (a) fresh heartbeat: the request is not dispatched and stays queued" {
  fence_fresh; request; tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  [ -f "$STATE/requests/$SID.json" ]
  grep -q "RECON-DEFER request $SID" "$STATE/poller.log" || { plog; false; }
}
@test "§0 (b) stale heartbeat, owned proc alive: not dispatched" {
  fence_alive; request; tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  [ -f "$STATE/requests/$SID.json" ]
}
@test "§0 (c) lapsed: dispatched under the poller's launch lock, lock released after" {
  fence_lapsed; request; tick
  assert_locked_act fleet request
  [ -f "$STATE/claimed/$SID.json" ]
}
@test "§0 (d) recon.on absent: dispatched as before, no lock" {
  request; tick
  assert_unlocked_act fleet
  [ -f "$STATE/claimed/$SID.json" ]
}

# ══ § 2a REROUTE ═════════════════════════════════════════════════════════════════════════════════
@test "§2a (a) fresh heartbeat: no reroute dispatch, record stays parked" {
  fence_fresh; park_future; RANK_OUT="next2 0.8" tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  [ -f "$STATE/parked/$SID.json" ]
  grep -q "RECON-DEFER reroute $SID" "$STATE/poller.log" || { plog; false; }
}
@test "§2a (b) stale heartbeat, owned proc alive: no reroute dispatch" {
  fence_alive; park_future; RANK_OUT="next2 0.8" tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
}
@test "§2a (c) lapsed: rerouted under the launch lock, lock released after" {
  fence_lapsed; park_future; RANK_OUT="next2 0.8" tick
  assert_locked_act fleet reroute
}
@test "§2a (d) recon.on absent: rerouted as before, no lock" {
  park_future; RANK_OUT="next2 0.8" tick
  assert_unlocked_act fleet
}

# ══ § 2 RESUME ═══════════════════════════════════════════════════════════════════════════════════
@test "§2 (a) fresh heartbeat: no launcher minted, nothing spawned" {
  fence_fresh; park_ready; LR_POLLER_SPAWN=tmux tick
  [ "$(acted tmux)" -eq 0 ] || { plog; false; }
  [ -z "$(ls "$LR_POLLER_LAUNCH_DIR")" ]
  [ -f "$STATE/parked/$SID.json" ]
  grep -q "RECON-DEFER resume $SID" "$STATE/poller.log" || { plog; false; }
}
@test "§2 (b) stale heartbeat, owned proc alive: nothing spawned" {
  fence_alive; park_ready; LR_POLLER_SPAWN=tmux tick
  [ "$(acted tmux)" -eq 0 ] || { plog; false; }
}
@test "§2 (c) lapsed: spawned under the launch lock, lock released after" {
  fence_lapsed; park_ready; LR_POLLER_SPAWN=tmux tick
  assert_locked_act tmux resume
}
@test "§2 (d) recon.on absent: spawned as before, no lock" {
  park_ready; LR_POLLER_SPAWN=tmux tick
  assert_unlocked_act tmux
}

# ══ § 2 NUDGE (the original pane is live) ════════════════════════════════════════════════════════
@test "nudge (a) fresh heartbeat: nothing typed" {
  fence_fresh; park_ready; live_row; tick
  [ "$(acted tui)" -eq 0 ] || { plog; false; }
  grep -q "RECON-DEFER nudge $SID" "$STATE/poller.log" || { plog; false; }
}
@test "nudge (b) stale heartbeat, owned proc alive: nothing typed" {
  fence_alive; park_ready; live_row; tick
  [ "$(acted tui)" -eq 0 ] || { plog; false; }
}
@test "nudge (c) lapsed: typed under the launch lock, lock released after" {
  fence_lapsed; park_ready; live_row; tick
  assert_locked_act tui nudge
}
@test "nudge (d) recon.on absent: typed as before, no lock" {
  park_ready; live_row; tick
  assert_unlocked_act tui
}

# ══ the cc-lr.json lane ══════════════════════════════════════════════════════════════════════════
@test "cc-lr.json: left for a LIVE reconciler; drained when the reconciler is not live" {
  recon_on; heartbeat "$((NOW - 10))"; request "$SID.cc-lr"
  tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  [ -f "$STATE/requests/$SID.cc-lr.json" ]
  grep -q "RECON-OWNED 1 cc-lr request" "$STATE/poller.log" || { plog; false; }
  heartbeat "$((NOW - 3600))"
  tick
  [ "$(acted fleet)" -eq 1 ] || { plog; false; }
  [ ! -e "$STATE/requests/$SID.cc-lr.json" ]
}

# ══ SUPERSEDED-BY-LIVE-RUN ═══════════════════════════════════════════════════════════════════════
@test "superseded: a request whose sid a live run holds is filed to claimed/, never deleted" {
  request
  mkdir -p "$STATE/runs/by-sid/$SID.active"
  printf '{"pid":%s}\n' "$$" > "$STATE/runs/by-sid/$SID.active/holder"
  tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  [ ! -e "$STATE/requests/$SID.json" ]
  [ -f "$STATE/claimed/$SID.superseded.json" ] || { ls -R "$STATE" >&2; plog; false; }
  grep -q "SUPERSEDED-BY-LIVE-RUN $SID" "$STATE/poller.log"
}

# ══ the backup watchdog (§ C9) ═══════════════════════════════════════════════════════════════════
@test "watchdog: stale heartbeat pages once per 15 min and kickstarts bare every tick" {
  recon_on; heartbeat "$((NOW - 3600))"
  tick; tick
  [ "$(grep -c 'reconciler heartbeat stale' "$OSA_LOG")" -eq 1 ] || { cat "$OSA_LOG"; plog; false; }
  [ "$(grep -c . "$LC_LOG")" -eq 2 ] || { cat "$LC_LOG"; false; }
  grep -qx "kickstart gui/$(id -u)/com.reso.lr-reconciler" "$LC_LOG" || { cat "$LC_LOG"; false; }
  if grep -q -- '-k' "$LC_LOG"; then echo "kickstart carried -k"; false; fi
  touch -t "$(date -v-20M +%Y%m%d%H%M)" "$STATE/recon-backup.page"
  tick
  [ "$(grep -c 'reconciler heartbeat stale' "$OSA_LOG")" -eq 2 ] || { cat "$OSA_LOG"; false; }
}
@test "watchdog: a fresh heartbeat neither pages nor kickstarts" {
  recon_on; heartbeat "$((NOW - 10))"
  tick
  [ ! -s "$LC_LOG" ]; [ ! -s "$OSA_LOG" ]
}
@test "watchdog: recon.on absent ⇒ nothing (no page, no kickstart, no stamp)" {
  heartbeat "$((NOW - 3600))"
  tick
  [ ! -s "$LC_LOG" ]; [ ! -s "$OSA_LOG" ]
  [ ! -e "$STATE/recon-backup.page" ]
}

# ══ the upgrade drainer ══════════════════════════════════════════════════════════════════════════
@test "upgrade kick: every queued sid defers ⇒ UPGRADE-DEFER, drainer not started" {
  fence_fresh
  mkdir -p "$STATE/upgrade-queue"
  printf '{"sid":"%s","kind":"upgrade"}\n' "$SID" > "$STATE/upgrade-queue/$SID.json"
  export LR_UPGRADE_BIN="$S/lr-upgrade"; printf '#!/bin/bash\nexit 0\n' > "$LR_UPGRADE_BIN"; chmod +x "$LR_UPGRADE_BIN"
  tick
  grep -q "UPGRADE-DEFER all 1 queued" "$STATE/poller.log" || { plog; false; }
  if grep -q "UPGRADE-DRAIN started" "$STATE/poller.log"; then plog; false; fi
}
