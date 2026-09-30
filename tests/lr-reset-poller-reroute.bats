#!/usr/bin/env bats
# lr-reset-poller.sh § 2 — A PARKED SESSION IS RE-PROBED EVERY TICK, NOT ONLY AT ITS RESET (2026-09-27).
#
# THE INCIDENT. poller.log 2026-09-26T20:55:27Z "PARKED ac0f0123 (next, weekly) resets
# 2026-09-27T04:00:00Z". Minutes later next2 fell below its concurrency cap and was routable, but the
# § 2 loop skips every record until `now >= reset_at_utc`, and nothing before the reset looks at any
# OTHER account — so the session stayed parked until an operator asked. The fix: before the reset,
# each tick asks the router's non-charging rank (`--rank <lane> --recovery`, the call lr-fleet makes)
# whether any account OTHER than the parked one routes, and if so dispatches the same detached
# `lr-fleet --one … --target auto` the request lane uses, under the same run claim.
#
# Hermetic: fixture $HOME and store, a stub router that records its argv, the lr-fleet stub that
# honours --detach. No census, no registry, no GUI.

setup() {
  export LR_UPGRADE_AUTO=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  mkdir -p "$HOME/bin" "$HOME/.claude" "$STATE/parked" "$STATE/resumed" "$STATE/locks" "$BATS_TEST_TMPDIR/stubs"
  SID="ac0f0123-1111-4000-8000-000000000001"
  export LR_POLLER_NO_CENSUS=1
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket"
  export LR_CC_TUI_LIB="$BATS_TEST_TMPDIR/absent-cc-tui.sh"
  unset KITTY_WINDOW_ID CC_TERM_KITTY_TO CC_ACCOUNTS_BIN LR_POLLER_REROUTE LR_REROUTE_EVERY_MIN
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stubs/osascript"
  chmod +x "$BATS_TEST_TMPDIR/stubs/osascript"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
  # The router: --rank answers $RANK_OUT with $RANK_RC; anything else is the headroom JSON.
  export RANK_LOG="$BATS_TEST_TMPDIR/rank.log"; : > "$RANK_LOG"
  cat > "$HOME/bin/claude-accounts" <<'STUB'
#!/bin/bash
case " $* " in
  *" --rank "*) printf '%s\n' "$*" >> "${RANK_LOG:?}"; printf '%b\n' "${RANK_OUT:-none}"; exit "${RANK_RC:-0}" ;;
esac
echo '{"rows":[{"acct":"next","session_pct":10,"weekly_pct":100},{"acct":"next2","session_pct":5,"weekly_pct":7}]}'
STUB
  chmod +x "$HOME/bin/claude-accounts"
  export LR_FLEET_BIN="$BATS_TEST_TMPDIR/stubs/lr-fleet"
  cat > "$LR_FLEET_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FLEET_LOG:?}"
echo "lr-fleet: DETACHED — driver pid 4242 is recovering; the verdict arrives as mail."
exit "${FLEET_DETACH_RC:-0}"
STUB
  chmod +x "$LR_FLEET_BIN"
  export FLEET_LOG="$BATS_TEST_TMPDIR/fleet.log"; : > "$FLEET_LOG"
  # The zero-human switch (ruling 1): reroute is an unattended move, so every case below that expects
  # a dispatch runs with it set — in this fixture $HOME, never the real one.
  : > "$STATE/autorecover.on"
}

park() { # $1=reset iso (default far future) — the § 1 record shape (lr-reset-poller.sh:1267)
  printf '{"sid":"%s","acct":"next","cfg":"%s","cwd":"%s","kind":"weekly","reset_at_utc":"%s","parked_at":"2026-09-26T20:55:27Z"}\n' \
    "$SID" "$HOME/.claude" "$BATS_TEST_TMPDIR" "${1:-2099-01-01T00:00:00Z}" > "$STATE/parked/$SID.json"
}
tick() { LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once; }
plog() { cat "$STATE/poller.log" >&2 2>/dev/null || true; }

@test "[RED] a parked session is dispatched as soon as ANOTHER account routes, before its own reset" {
  park
  RANK_OUT="next2 0.8" tick
  [ "$status" -eq 0 ] || { echo "$output"; plog; false; }
  grep -q -- "--rank general --recovery" "$RANK_LOG" || { echo "router not asked:"; cat "$RANK_LOG"; plog; false; }
  grep -q -- "--one $SID --target auto --from-daemon --detach" "$FLEET_LOG" || { echo "not dispatched:"; cat "$FLEET_LOG"; plog; false; }
  [ -f "$STATE/parked/$SID.json" ] || { echo "the parked record was retired on a dispatch, not on a recovery"; false; }
  grep -q "REROUTE $SID" "$STATE/poller.log" || { plog; false; }
}

@test "nothing routable: the router is asked, nothing is dispatched, the record stays" {
  park
  RANK_OUT="none" RANK_RC=2 tick
  [ -s "$RANK_LOG" ] || { plog; false; }
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
  [ -f "$STATE/parked/$SID.json" ]
}

@test "only the parked account itself routes: not a reroute, nothing dispatched" {
  park
  RANK_OUT="next 0.9" tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
}

@test "a second tick inside the backoff does not dispatch the same session again" {
  park
  RANK_OUT="next2 0.8" tick
  RANK_OUT="next2 0.8" tick
  [ "$(grep -c -- "--one $SID" "$FLEET_LOG")" -eq 1 ] || { cat "$FLEET_LOG"; false; }
}

@test "a run already holding the sid is not driven twice" {
  park
  mkdir -p "$STATE/runs/by-sid/$SID.active"
  printf '{"pid":%s}\n' "$$" > "$STATE/runs/by-sid/$SID.active/holder"
  RANK_OUT="next2 0.8" tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
}

@test "without AUTOFIRE, or with the kill switch, nothing is dispatched" {
  park
  RANK_OUT="next2 0.8" run bash "$POLLER" --once
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
  LR_POLLER_REROUTE=off RANK_OUT="next2 0.8" tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
}

@test "a session already transplanted elsewhere is left to the transplant arm, not re-driven" {
  park
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$HOME/.claude" "$HOME/.claude-secondary" > "$STATE/locks/$SID.lock"
  mkdir -p "$HOME/.claude-secondary/projects/-x"
  printf '%s\n' '{"type":"user","message":{"content":"hi"}}' > "$HOME/.claude-secondary/projects/-x/$SID.jsonl"
  RANK_OUT="next2 0.8" tick
  [ ! -s "$FLEET_LOG" ] || { echo "re-drove a transplanted session:"; cat "$FLEET_LOG"; plog; false; }
}

@test "the reroute runs under /bin/bash 3.2, the interpreter launchd gives the poller" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  park
  RANK_OUT="next2 0.8" LR_POLLER_AUTOFIRE=1 run /bin/bash "$POLLER" --once
  [ "$status" -eq 0 ] || { echo "$output"; plog; false; }
  grep -q -- "--one $SID --target auto --from-daemon --detach" "$FLEET_LOG" || { plog; false; }
}

# ══ W6b (LIMIT_RECOVER_FLEET_V2 resolutions 8, 9) ══════════════════════════════════════════════
@test "[R8] without autorecover.on nothing is rerouted, the router is not even asked, and ONE line says why" {
  rm -f "$STATE/autorecover.on"
  park; export RANK_OUT='next2 0.9'
  tick
  [ ! -s "$FLEET_LOG" ] || { echo "rerouted with the switch absent: $(cat "$FLEET_LOG")"; false; }
  [ ! -s "$RANK_LOG" ] || { cat "$RANK_LOG"; false; }
  [ "$(grep -c 'REROUTE-HELD 1 parked session' "$STATE/poller.log")" = 1 ] || { plog; false; }
  [ ! -e "$STATE/autorecover.on" ]
}

@test "[R9] a parked session whose reset is under 15 min away stays put, even with a routable account" {
  park "$(date -u -v+300S +%Y-%m-%dT%H:%M:%SZ)"; export RANK_OUT='next2 0.9'
  tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
  grep -q "REROUTE-STAY $SID (next) — its account resets in" "$STATE/poller.log" || { plog; false; }
}

@test "R9 CONTROL: 20 min before its reset the same session IS rerouted" {
  park "$(date -u -v+1200S +%Y-%m-%dT%H:%M:%SZ)"; export RANK_OUT='next2 0.9'
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { plog; false; }
}
