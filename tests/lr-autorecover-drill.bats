#!/usr/bin/env bats
# THE AUTO-RECOVER DRILL (D3, 2026-09-28) — the plan's own condition for switching the hook lane on
# (docs/plans/LIMIT_RECOVER_100P.md § Open decisions 1): "a fixture drill that drains a mixed cohort —
# stale, teammate, limited — and acts only on the limited ones", passed twice.
#
# The cohort is the 2026-09-28 one in miniature: the held requests included sessions already
# recovered by hand (415a3aac, 55120708), and draining them would have transplanted healthy sessions.
# Every request here is re-checked against its transcript AT DRAIN TIME; only a still-LIMITED,
# un-moved, non-teammate session is dispatched, and a dispatched request stays queued until the
# session is seen recovered, so a driver that dies is retried rather than consumed.
#
# Hermetic: $HOME, the registry, the account stores and lr-fleet are fixtures. lr-fleet is a stub
# that records its argv and reproduces the --detach contract; nothing reaches a live pane.

setup() {
  export LR_UPGRADE_AUTO=off LR_POLLER_NO_CENSUS=1
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$STATE/locks" "$STATE/requests" "$BATS_TEST_TMPDIR/stubs"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket"
  export LR_CC_TUI_LIB="$BATS_TEST_TMPDIR/absent-cc-tui.sh"
  unset KITTY_WINDOW_ID CC_TERM_KITTY_TO
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stubs/osascript"
  printf '#!/bin/bash\necho %s\n' "'{\"rows\":[{\"acct\":\"next4\",\"session_pct\":12,\"weekly_pct\":40}]}'" > "$HOME/bin/claude-accounts"
  chmod +x "$BATS_TEST_TMPDIR/stubs/osascript" "$HOME/bin/claude-accounts"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
  export LR_FLEET_BIN="$BATS_TEST_TMPDIR/stubs/lr-fleet"
  cat > "$LR_FLEET_BIN" <<'STUB'
printf '%s\n' "$*" >> "${FLEET_LOG:?}"
echo "lr-fleet: DETACHED — driver pid ${FLEET_DRIVER_PID:?} is recovering; the verdict arrives as mail."
exit "${FLEET_DETACH_RC:-0}"
STUB
  chmod +x "$LR_FLEET_BIN"
  export FLEET_LOG="$BATS_TEST_TMPDIR/fleet.log"; : > "$FLEET_LOG"
  export FLEET_DRIVER_PID="$$"          # a driver that outlives the tick
  CFG="$HOME/.claude-tertiary"; SLUG="-Users-x-proj"; mkdir -p "$CFG/projects/$SLUG"
  LIM="11111111-0000-4000-8000-000000000001"     # still LIMITED → the only one acted on
  RECOV="22222222-0000-4000-8000-000000000002"   # recovered by hand since (the 415a3aac shape)
  MOVED="33333333-0000-4000-8000-000000000003"   # transplanted away (tombstone on this store)
  MATE="44444444-0000-4000-8000-000000000004"    # a teammate that hit the same cap
}
tx() { printf '%s' "$CFG/projects/$SLUG/$1.jsonl"; }
limit_rec() { printf '{"type":"assistant","timestamp":"2026-09-28T03:00:00Z","isApiErrorMessage":true,"error":"rate_limit","message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your weekly limit · resets Oct 1"}]}}\n' >> "$1"; }
normal_rec() { printf '{"type":"assistant","timestamp":"2026-09-28T03:30:00Z","message":{"role":"assistant","content":[{"type":"text","text":"back to work"}]}}\n' >> "$1"; }
request() { # $1=sid — the record hooks/stop-failure-marker.sh writes
  jq -cn --arg sid "$1" --arg tp "$(tx "$1")" \
    '{sid:$sid, target:"auto", source_pane:"", requested_by:"stop-failure-marker", account:"next3", transcript_path:$tp, error:"rate_limit"}' \
    > "$STATE/requests/$1.json"
}
cohort() {
  limit_rec "$(tx "$LIM")"
  limit_rec "$(tx "$RECOV")"; normal_rec "$(tx "$RECOV")"
  limit_rec "$(tx "$MOVED")"; mv "$(tx "$MOVED")" "$(tx "$MOVED").handed-off"
  printf '{"type":"user","agentName":"worker-1","message":{"role":"user","content":"brief"}}\n' > "$(tx "$MATE")"
  limit_rec "$(tx "$MATE")"
  for s in "$LIM" "$RECOV" "$MOVED" "$MATE"; do request "$s"; done
}
tick() { LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once; }
plog() { cat "$STATE/poller.log" >&2; }

@test "DRILL: lane ON, a mixed cohort — only the LIMITED session is dispatched; the rest retire, named" {
  cohort; touch "$STATE/autorecover.on"
  tick; [ "$status" -eq 0 ] || { echo "$output"; plog; false; }
  [ "$(grep -c . "$FLEET_LOG")" -eq 1 ] || { cat "$FLEET_LOG"; plog; false; }
  grep -q -- "--one $LIM " "$FLEET_LOG" || { cat "$FLEET_LOG"; false; }
  grep -q "REQUEST-RETIRED $RECOV — no longer LIMITED" "$STATE/poller.log" || { plog; false; }
  grep -q "REQUEST-RETIRED $MOVED — transplanted" "$STATE/poller.log" || { plog; false; }
  grep -q "REQUEST-RETIRED $MATE — a teammate" "$STATE/poller.log" || { plog; false; }
  for s in "$RECOV" "$MOVED" "$MATE"; do
    [ -f "$STATE/results/$s.retired.json" ] || { ls "$STATE/results"; false; }
    [ "$(jq -r .verdict "$STATE/results/$s.json")" = retired ]
  done
  # the acted-on request is KEPT, with its attempt recorded, until the session is seen recovered
  [ "$(jq -r .attempts "$STATE/requests/$LIM.json")" = 1 ]
}

@test "DRILL: lane OFF — stale requests still retire, the LIMITED one is HELD, nothing is dispatched" {
  cohort
  tick; [ "$status" -eq 0 ]
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
  grep -q "HOOK-HELD 1 hook-originated" "$STATE/poller.log" || { plog; false; }
  [ -f "$STATE/requests/$LIM.json" ]
  [ ! -e "$STATE/requests/$RECOV.json" ]
}

@test "RETRY: a driver that dies with the session still LIMITED is re-dispatched; recovery then retires it" {
  limit_rec "$(tx "$LIM")"; request "$LIM"; touch "$STATE/autorecover.on"
  export LR_REQUEST_RETRY_MIN=0
  tick; [ "$(grep -c . "$FLEET_LOG")" -eq 1 ]
  # while the driver lives, the request is in flight and KEPT — not dropped as a duplicate
  tick; [ "$(grep -c . "$FLEET_LOG")" -eq 1 ] || { cat "$FLEET_LOG"; false; }
  grep -q "REQUEST-IN-FLIGHT $LIM" "$STATE/poller.log" || { plog; false; }
  [ -f "$STATE/requests/$LIM.json" ]
  # the driver dies (its pid is gone) and the session is still LIMITED → attempt 2
  sleep 0 & dead=$!; wait "$dead" || true
  jq --argjson p "$dead" '.pid = $p' <<<"{}" >/dev/null
  printf '{"sid":"%s","pane":"-","pid":%d,"ts":"t","by":"x"}\n' "$LIM" "$dead" > "$STATE/runs/by-sid/$LIM.active/holder"
  tick; [ "$(grep -c . "$FLEET_LOG")" -eq 2 ] || { cat "$FLEET_LOG"; plog; false; }
  [ "$(jq -r .attempts "$STATE/requests/$LIM.json")" = 2 ]
  # the session recovers: the next drain retires the request and dispatches nothing
  normal_rec "$(tx "$LIM")"
  printf '{"sid":"%s","pane":"-","pid":%d,"ts":"t","by":"x"}\n' "$LIM" "$dead" > "$STATE/runs/by-sid/$LIM.active/holder"
  tick; [ "$(grep -c . "$FLEET_LOG")" -eq 2 ]
  grep -q "REQUEST-RETIRED $LIM — no longer LIMITED" "$STATE/poller.log" || { plog; false; }
}

@test "RETRY is bounded: past LR_REQUEST_MAX_ATTEMPTS the request is filed as exhausted, not re-driven" {
  limit_rec "$(tx "$LIM")"; request "$LIM"; touch "$STATE/autorecover.on"
  jq '.attempts = 3 | .last_attempt_epoch = 1' "$STATE/requests/$LIM.json" > "$BATS_TEST_TMPDIR/r" && mv "$BATS_TEST_TMPDIR/r" "$STATE/requests/$LIM.json"
  tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
  [ -f "$STATE/results/$LIM.exhausted.json" ]
  grep -q "REQUEST-EXHAUSTED $LIM" "$STATE/poller.log" || { plog; false; }
}

@test "RETRY waits out LR_REQUEST_RETRY_MIN between attempts" {
  limit_rec "$(tx "$LIM")"; request "$LIM"; touch "$STATE/autorecover.on"
  jq --argjson now "$(date +%s)" '.attempts = 1 | .last_attempt_epoch = $now' "$STATE/requests/$LIM.json" > "$BATS_TEST_TMPDIR/r" && mv "$BATS_TEST_TMPDIR/r" "$STATE/requests/$LIM.json"
  tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
  [ -f "$STATE/requests/$LIM.json" ]
}
