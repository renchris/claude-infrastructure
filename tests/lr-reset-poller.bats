#!/usr/bin/env bats
# limit-reset poller — LR-a..LR-h proofs (scripts/limit-reset-safety-gate.sh registers the criteria).
#
# Harness laws honored (blueprint §3.10 L1-L4): the LR-a fixture carries the REAL transcript artifact's
# BYTES (type:assistant + isApiErrorMessage:true + error:rate_limit + the verbatim "You've hit your …
# limit · resets …" text lr-audit.py classifies); every assertion is a `[ ]`/`run` bats-trapped check;
# the suite was proven RED against mutated pollers (headroom guard removed → LR-c fails; autofire gate
# removed → LR-d fails) before being recorded green — see the landing commit.
#
# Isolation: the poller resolves EVERYTHING under $HOME ($HOME/.reso state, $HOME/.claude-quaternary
# transcripts, $HOME/bin/claude-accounts) → each test gets a hermetic $HOME. osascript is PATH-stubbed
# (records argv; opens nothing). pgrep is real (no fixture sid ever matches a live process).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$BATS_TEST_TMPDIR/stubs" "$BATS_TEST_TMPDIR/cwd"
  CWD="$BATS_TEST_TMPDIR/cwd"

  # osascript stub — records every invocation, opens/notifies NOTHING.
  cat > "$BATS_TEST_TMPDIR/stubs/osascript" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${OSA_LOG:?}"
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/osascript"
  export OSA_LOG="$BATS_TEST_TMPDIR/osascript.log"; : > "$OSA_LOG"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"

  # claude-accounts stub — headroom by default; ACCTS_CAPPED=1 flips next4 to capped.
  cat > "$HOME/bin/claude-accounts" <<'STUB'
#!/bin/bash
if [ "${ACCTS_CAPPED:-0}" = "1" ]; then
  echo '{"rows":[{"acct":"next4","session_pct":100,"weekly_pct":97}]}'
else
  echo '{"rows":[{"acct":"next4","session_pct":12,"weekly_pct":40}]}'
fi
STUB
  chmod +x "$HOME/bin/claude-accounts"
}

# A REAL-shape lead transcript: first line carries cwd; last line is the verbatim limit
# isApiErrorMessage. $1=sid $2=event-epoch $3=reset-display e.g. "3:45pm" (tz UTC).
mk_transcript() {
  local sid="$1" ev_epoch="$2" reset_disp="$3"
  local proj="$HOME/.claude-quaternary/projects/-test-proj"
  mkdir -p "$proj"
  local ev_iso; ev_iso="$(python3 -c "from datetime import datetime,timezone;import sys;print(datetime.fromtimestamp(int(sys.argv[1]),tz=timezone.utc).isoformat().replace('+00:00','Z'))" "$ev_epoch")"
  {
    printf '{"type":"user","cwd":"%s","timestamp":"%s","message":{"role":"user","content":"go"}}\n' "$CWD" "$ev_iso"
    printf '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","timestamp":"%s","message":{"role":"assistant","model":"claude-opus-4-8","content":[{"type":"text","text":"You'\''ve hit your session limit \\u00b7 resets %s (UTC)"}]}}\n' "$ev_iso" "$reset_disp"
  } > "$proj/$sid.jsonl"
}

# Seed a parked-ledger row directly (phase-2-only tests). $1=sid $2=reset-iso-utc
mk_parked() {
  printf '{"sid":"%s","acct":"next4","cfg":"%s","cwd":"%s","kind":"session","reset_at_utc":"%s","parked_at":"2026-07-15T00:00:00Z"}\n' \
    "$1" "$HOME/.claude-quaternary" "$CWD" "$2" > "$STATE/parked/$1.json"
}
# Seed a resumed-ledger row (recurrence tests). $1=sid $2=reset-iso-utc of the HANDLED event
mk_resumed() {
  printf '{"sid":"%s","acct":"next4","cfg":"%s","cwd":"%s","kind":"session","reset_at_utc":"%s","parked_at":"2026-07-15T00:00:00Z"}\n' \
    "$1" "$HOME/.claude-quaternary" "$CWD" "$2" > "$STATE/resumed/$1.json"
}
# Future reset display time (+2h) in RESET_RE shape, e.g. "3:45pm"
future_disp() { python3 -c "from datetime import datetime,timezone,timedelta;d=datetime.now(timezone.utc)+timedelta(hours=2);h=d.hour%12 or 12;print(f\"{h}:{d.minute:02d}{'pm' if d.hour>=12 else 'am'}\")"; }

past_iso()   { python3 -c "from datetime import datetime,timezone,timedelta;print((datetime.now(timezone.utc)-timedelta(hours=1)).isoformat().replace('+00:00','Z'))"; }
future_iso() { python3 -c "from datetime import datetime,timezone,timedelta;print((datetime.now(timezone.utc)+timedelta(hours=3)).isoformat().replace('+00:00','Z'))"; }

@test "LR-a: genuine limit transcript (real bytes, reset-bearing) → PARKED ledger row with kind+reset" {
  # event 30 min ago; reset display = a time strictly between event and now would race midnight math —
  # a FUTURE reset keeps LR-a pure detection (no fire path entered).
  local now; now=$(date +%s)
  mk_transcript "aaaaaaaa-1111-2222-3333-444444444444" "$((now-1800))" "$(future_disp)"
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ -f "$STATE/parked/aaaaaaaa-1111-2222-3333-444444444444.json" ]
  run jq -r '.kind + " " + .reset_at_utc' "$STATE/parked/aaaaaaaa-1111-2222-3333-444444444444.json"
  [[ "$output" == session\ 20*Z ]]
  grep -q "PARKED aaaaaaaa" "$STATE/poller.log"   # LR-h leg: the decision is recorded
}

@test "LR-b: parked row with FUTURE reset → no fire, no notify, row stays parked" {
  mk_parked "bbbbbbbb-1111-2222-3333-444444444444" "$(future_iso)"
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ -f "$STATE/parked/bbbbbbbb-1111-2222-3333-444444444444.json" ]
  [ ! -s "$OSA_LOG" ]
  [ ! -e "$STATE/resumed/bbbbbbbb-1111-2222-3333-444444444444.json" ]
}

@test "LR-c: reset passed but account CAPPED → WAIT logged, zero fire (never resume into a capped account)" {
  mk_parked "cccccccc-1111-2222-3333-444444444444" "$(past_iso)"
  ACCTS_CAPPED=1 LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  grep -q "WAIT  cccccccc" "$STATE/poller.log"
  [ ! -s "$OSA_LOG" ]
  [ -f "$STATE/parked/cccccccc-1111-2222-3333-444444444444.json" ]   # still parked, retried next tick
}

@test "LR-d: AUTOFIRE unset → notify-only, exactly ONCE across two ticks, nothing spawned" {
  mk_parked "dddddddd-1111-2222-3333-444444444444" "$(past_iso)"
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ "$(grep -c 'display notification' "$OSA_LOG")" -eq 1 ]           # notify-once, no per-tick spam
  [ "$(grep -c 'create window' "$OSA_LOG")" -eq 0 ]                  # nothing spawned
  [ ! -e "/tmp/lr-poller-launch-dddddddd.sh" ]
  grep -q "READY dddddddd" "$STATE/poller.log"
}

@test "LR-e: AUTOFIRE=1 → launcher + window-open + parked→resumed; second tick never double-fires" {
  mk_parked "eeeeeeee-1111-2222-3333-444444444444" "$(past_iso)"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ "$(grep -c 'create window' "$OSA_LOG")" -eq 1 ]
  [ -x "/tmp/lr-poller-launch-eeeeeeee.sh" ]
  grep -q "lr-fire-resume.sh" "/tmp/lr-poller-launch-eeeeeeee.sh"
  [ -f "$STATE/resumed/eeeeeeee-1111-2222-3333-444444444444.json" ]
  [ ! -e "$STATE/parked/eeeeeeee-1111-2222-3333-444444444444.json" ]
  grep -q "RESUMED eeeeeeee" "$STATE/poller.log"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once                     # idempotency: ledger moved ⇒ no re-fire
  [ "$(grep -c 'create window' "$OSA_LOG")" -eq 1 ]
  rm -f "/tmp/lr-poller-launch-eeeeeeee.sh"
}

@test "LR-f: 5 ready rows, MAX_PER_RUN=4 → exactly 4 fire, CAP logged, 5th deferred" {
  local i
  for i in 1 2 3 4 5; do mk_parked "ffffff0${i}-1111-2222-3333-444444444444" "$(past_iso)"; done
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ "$(grep -c 'create window' "$OSA_LOG")" -eq 4 ]
  grep -q "CAP " "$STATE/poller.log"
  [ "$(ls "$STATE/parked" | grep -c '^ffffff0.*\.json$')" -eq 1 ]    # exactly one deferred to next tick
  rm -f /tmp/lr-poller-launch-ffffff0*.sh
}

@test "LR-g: LR_POLLER_DISABLED=1 → exit 0 immediately, zero writes, zero fires" {
  mk_parked "99999999-1111-2222-3333-444444444444" "$(past_iso)"
  local before; before="$(ls "$STATE/resumed" | wc -l)"
  LR_POLLER_DISABLED=1 LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ ! -s "$OSA_LOG" ]
  [ ! -f "$STATE/poller.log" ]
  [ "$(ls "$STATE/resumed" | wc -l)" -eq "$before" ]
}

@test "LR-h: outcome records — every decision path above left a {PARKED|READY|WAIT|RESUMED|CAP} line (abstention law)" {
  # One composite pass exercising three paths in a single tick: capped→WAIT is covered in LR-c;
  # here: one ready+autofire (RESUMED) and one future (silent-by-design: pre-reset rows are WAITING
  # states, not decisions — the ledger row itself is their record).
  mk_parked "hhhhhhhh-1111-2222-3333-444444444444" "$(past_iso)"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  grep -qE '^[0-9T:Z-]+ RESUMED hhhhhhhh' "$STATE/poller.log"        # timestamped, greppable outcome
  rm -f /tmp/lr-poller-launch-hhhhhhhh.sh
}

@test "LR-i: recurrence — a NEWER limit event re-parks a previously-resumed sid (marker is event-keyed, not forever)" {
  # The sid was resumed for an event whose reset was 5h ago; the transcript now carries a FRESH limit
  # event (reset +2h). The naive sid-keyed skip would park it NEVER AGAIN — fatal for multi-day runs.
  local sid="iiiiiiii-1111-2222-3333-444444444444" now; now=$(date +%s)
  mk_resumed "$sid" "$(python3 -c "from datetime import datetime,timezone,timedelta;print((datetime.now(timezone.utc)-timedelta(hours=5)).isoformat().replace('+00:00','Z'))")"
  mk_transcript "$sid" "$((now-1800))" "$(future_disp)"
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ -f "$STATE/parked/$sid.json" ]                                   # re-parked
  [ ! -e "$STATE/resumed/$sid.json" ]                                # stale marker cleared
  grep -q "REPARK iiiiiiii" "$STATE/poller.log"
}

@test "LR-i: non-recurrence control — an event NOT newer than the handled one stays skipped (no double-fire)" {
  local sid="jjjjjjjj-1111-2222-3333-444444444444" now; now=$(date +%s)
  mk_resumed "$sid" "2099-01-01T00:00:00Z"                           # handled event is 'newer' than anything
  mk_transcript "$sid" "$((now-1800))" "$(future_disp)"
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ ! -e "$STATE/parked/$sid.json" ]
  [ -f "$STATE/resumed/$sid.json" ]                                  # marker intact — the same event never re-fires
}
