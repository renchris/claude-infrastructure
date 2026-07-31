#!/usr/bin/env bats
# limit-reset poller — LR-a..LR-n proofs (scripts/limit-reset-safety-gate.sh registers the criteria).
# LR-j..LR-n (2026-07-19, P0-8 agent half) prove the headless resume spawn path (tmux, no GUI) and
# the monthly-spend → class-B decision-packet path (no reset ⇒ never silent-park).
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

  # osascript stub — records every invocation, opens/notifies NOTHING. OSA_FAIL=1 makes the
  # window-open FAIL (exit 1) AFTER recording — simulates a no-GUI context for the auto→tmux fallback.
  cat > "$BATS_TEST_TMPDIR/stubs/osascript" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${OSA_LOG:?}"
[ "${OSA_FAIL:-0}" = 1 ] && exit 1
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/osascript"
  export OSA_LOG="$BATS_TEST_TMPDIR/osascript.log"; : > "$OSA_LOG"

  # tmux stub — records argv (headless spawn path); TMUX_FAIL=1 makes new-session fail.
  cat > "$BATS_TEST_TMPDIR/stubs/tmux" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${TMUX_LOG:?}"
[ "${TMUX_FAIL:-0}" = 1 ] && exit 1
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/tmux"
  export TMUX_LOG="$BATS_TEST_TMPDIR/tmux.log"; : > "$TMUX_LOG"

  # cc-decide stub — records argv, echoes a fixed packet id (the decision-queue writer).
  cat > "$BATS_TEST_TMPDIR/stubs/cc-decide" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${CCD_LOG:?}"
echo "deadbeefcafe"
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/cc-decide"
  export CCD_LOG="$BATS_TEST_TMPDIR/cc-decide.log"; : > "$CCD_LOG"

  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"

  # launcher dir seam — production now mints the resume launcher with mktemp under the per-uid
  # $TMPDIR (CWE-377/CWE-59), so the shared-/tmp collision this seam was added for is gone; the
  # seam stays because a per-test dir is what lets launchers_for() glob a known-empty directory.
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"

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
# $1=sid $2=reset-iso-utc [$3=cwd, default $CWD — distinct cwds model distinct worktrees]
# Emits BOTH halves of what the real producer leaves behind: the ledger row AND the transcript it
# was derived from. Section 1 only ever parks a session it just read a transcript for, so a ledger
# row without one is a shape the producer cannot emit — and since 2026-07-21 the consolidation
# selector ranks candidates BY that transcript, a ledger-only fixture would silently rank as
# unresumable while production works (memory: fixture-shape-parity-with-real-producer).
# The transcript deliberately carries NO limit line, so section 1 will not re-park it.
mk_parked() {
  local sid="$1" reset="$2" cwd="${3:-$CWD}" proj ts
  mkdir -p "$cwd"
  proj="$HOME/.claude-quaternary/projects/$(printf '%s' "$cwd" | tr '/' '-')"
  mkdir -p "$proj"
  ts="$(python3 -c "from datetime import datetime,timezone;print(datetime.now(timezone.utc).isoformat().replace('+00:00','Z'))")"
  {
    printf '{"type":"user","cwd":"%s","gitBranch":"main","timestamp":"%s"}\n' "$cwd" "$ts"
    printf '{"type":"assistant","timestamp":"%s"}\n' "$ts"
  } > "$proj/$sid.jsonl"
  printf '{"sid":"%s","acct":"next4","cfg":"%s","cwd":"%s","kind":"session","reset_at_utc":"%s","parked_at":"2026-07-15T00:00:00Z"}\n' \
    "$sid" "$HOME/.claude-quaternary" "$cwd" "$reset" > "$STATE/parked/$sid.json"
}
# Seed a resumed-ledger row (recurrence tests). $1=sid $2=reset-iso-utc of the HANDLED event
mk_resumed() {
  printf '{"sid":"%s","acct":"next4","cfg":"%s","cwd":"%s","kind":"session","reset_at_utc":"%s","parked_at":"2026-07-15T00:00:00Z"}\n' \
    "$1" "$HOME/.claude-quaternary" "$CWD" "$2" > "$STATE/resumed/$1.json"
}
# Future reset display time (+2h) in RESET_RE shape, e.g. "3:45pm"
future_disp() { python3 -c "from datetime import datetime,timezone,timedelta;d=datetime.now(timezone.utc)+timedelta(hours=2);h=d.hour%12 or 12;print(f\"{h}:{d.minute:02d}{'pm' if d.hour>=12 else 'am'}\")"; }

# The poller mints its launcher with mktemp now (CWE-377/CWE-59 — a predictable name under the
# mode-1777 /tmp is pre-creatable by another uid), so the filename carries a random suffix and can
# no longer be derived from the sid. Resolve it by its readability prefix instead of predicting it.
# `nullglob` is load-bearing: without it a no-match glob expands to the LITERAL pattern, so a
# `[ ! -e ]`-style assertion would pass against a path that never existed — vacuously green.
launchers_for() {
  local g=()
  shopt -s nullglob
  g=("$LR_POLLER_LAUNCH_DIR"/lr-poller-launch-"$1"-*.sh)
  shopt -u nullglob
  (( ${#g[@]} )) && printf '%s\n' "${g[@]}"
  return 0
}
launcher_for()   { launchers_for "$1" | head -1; }
launcher_count() { launchers_for "$1" | wc -l | tr -d ' '; }

past_iso()   { python3 -c "from datetime import datetime,timezone,timedelta;print((datetime.now(timezone.utc)-timedelta(hours=1)).isoformat().replace('+00:00','Z'))"; }
future_iso() { python3 -c "from datetime import datetime,timezone,timedelta;print((datetime.now(timezone.utc)+timedelta(hours=3)).isoformat().replace('+00:00','Z'))"; }

# A REAL-shape MONTHLY-SPEND kill: the billing-plane isApiErrorMessage carries the verbatim
# "You've hit your monthly spend limit" text and NO reset time. $1=sid $2=event-epoch.
# The `"error":"rate_limit"` field and the "· raise it at claude.ai/settings/usage?from=…" suffix are
# NOT decoration — they are the real producer's bytes, captured from session e0bd7f43 on 2026-07-25.
# lr-audit.py gates limit_events on `obj.get("error") == "rate_limit"`, so the earlier fixture (which
# omitted it) was a shape-mismatched contract claim: it stayed green only because the poller trusted
# a bare text grep, and it went red the moment the poller started confirming via lr-audit — which is
# exactly the failure this fixture is supposed to catch (memory: fixture-shape-parity-with-real-producer).
mk_spend_transcript() {
  local sid="$1" ev_epoch="$2"
  local proj="$HOME/.claude-quaternary/projects/-test-proj"
  mkdir -p "$proj"
  local ev_iso; ev_iso="$(python3 -c "from datetime import datetime,timezone;import sys;print(datetime.fromtimestamp(int(sys.argv[1]),tz=timezone.utc).isoformat().replace('+00:00','Z'))" "$ev_epoch")"
  {
    printf '{"type":"user","cwd":"%s","timestamp":"%s","message":{"role":"user","content":"go"}}\n' "$CWD" "$ev_iso"
    printf '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","timestamp":"%s","message":{"role":"assistant","model":"claude-opus-4-8","content":[{"type":"text","text":"You'\''ve hit your monthly spend limit \\u00b7 raise it at claude.ai/settings/usage?from=cc_cli_limit_message"}]}}\n' "$ev_iso"
  } > "$proj/$sid.jsonl"
}
# Same, but a TEAMMATE (agentName in an early record) — recovery is lead-owned, so no packet.
mk_spend_teammate_transcript() {
  local sid="$1" ev_epoch="$2"
  local proj="$HOME/.claude-quaternary/projects/-test-proj"
  mkdir -p "$proj"
  local ev_iso; ev_iso="$(python3 -c "from datetime import datetime,timezone;import sys;print(datetime.fromtimestamp(int(sys.argv[1]),tz=timezone.utc).isoformat().replace('+00:00','Z'))" "$ev_epoch")"
  {
    printf '{"type":"user","cwd":"%s","agentName":"worker-3","timestamp":"%s","message":{"role":"user","content":"go"}}\n' "$CWD" "$ev_iso"
    printf '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","timestamp":"%s","message":{"role":"assistant","model":"claude-opus-4-8","content":[{"type":"text","text":"You'\''ve hit your monthly spend limit \\u00b7 raise it at claude.ai/settings/usage?from=cc_cli_limit_message"}]}}\n' "$ev_iso"
  } > "$proj/$sid.jsonl"
}

@test "LR-a: genuine limit transcript (real bytes, reset-bearing) → PARKED ledger row with kind+reset" {
  # event 30 min ago; reset display = a time strictly between event and now would race midnight math —
  # a FUTURE reset keeps LR-a pure detection (no fire path entered).
  local now; now=$(date +%s)
  mk_transcript "aaaaaaaa-1111-2222-3333-444444444444" "$((now-1800))" "$(future_disp)"
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ -f "$STATE/parked/aaaaaaaa-1111-2222-3333-444444444444.json" ]
  run jq -r '.kind + " " + .reset_at_utc' "$STATE/parked/aaaaaaaa-1111-2222-3333-444444444444.json"
  [[ "$output" == session\ 20*Z ]] || false
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
  [ "$(launcher_count dddddddd)" -eq 0 ]
  grep -q "READY dddddddd" "$STATE/poller.log"
}

@test "LR-e: AUTOFIRE=1 → launcher + window-open + parked→resumed; second tick never double-fires" {
  mk_parked "eeeeeeee-1111-2222-3333-444444444444" "$(past_iso)"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ "$(grep -c 'create window' "$OSA_LOG")" -eq 1 ]
  [ "$(launcher_count eeeeeeee)" -eq 1 ]
  [ -x "$(launcher_for eeeeeeee)" ]
  grep -q "lr-fire-resume.sh" "$(launcher_for eeeeeeee)"
  [ -f "$STATE/resumed/eeeeeeee-1111-2222-3333-444444444444.json" ]
  [ ! -e "$STATE/parked/eeeeeeee-1111-2222-3333-444444444444.json" ]
  grep -q "RESUMED eeeeeeee" "$STATE/poller.log"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once                     # idempotency: ledger moved ⇒ no re-fire
  [ "$(grep -c 'create window' "$OSA_LOG")" -eq 1 ]
  rm -f "$LR_POLLER_LAUNCH_DIR"/lr-poller-launch-eeeeeeee-*.sh
}

@test "LR-f: 5 ready rows, MAX_PER_RUN=4 → exactly 4 fire, CAP logged, 5th deferred" {
  # DISTINCT cwds — five independent worktrees, which is what "5 ready rows" always meant. Five
  # rows sharing ONE worktree is the sprawl case and is covered by lr-reset-poller-consolidate.bats;
  # here the bound under test is the RUN ceiling, and a total-ceiling loser must DEFER (stay parked
  # for the next tick), never be retired — nothing else covers its worktree.
  local i
  for i in 1 2 3 4 5; do
    mk_parked "ffffff0${i}-1111-2222-3333-444444444444" "$(past_iso)" "$CWD/wt$i"
  done
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ "$(grep -c 'create window' "$OSA_LOG")" -eq 4 ]
  grep -q "CAP " "$STATE/poller.log"
  [ "$(ls "$STATE/parked" | grep -c '^ffffff0.*\.json$')" -eq 1 ]    # exactly one deferred to next tick
  rm -f "$LR_POLLER_LAUNCH_DIR"/lr-poller-launch-ffffff0*.sh
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
  rm -f "$LR_POLLER_LAUNCH_DIR"/lr-poller-launch-hhhhhhhh-*.sh
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

# ── P0-8 agent half: headless resume (tmux) + monthly-spend → class-B packet ──────────────────────

@test "LR-j: LR_POLLER_SPAWN=tmux → headless resume via tmux (no GUI window), ledger parked→resumed" {
  mk_parked "aaaa000j-1111-2222-3333-444444444444" "$(past_iso)"
  LR_POLLER_AUTOFIRE=1 LR_POLLER_SPAWN=tmux run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  # a DETACHED tmux session ran the SAME launcher — a headless PTY, no Aqua session needed
  grep -q 'new-session' "$TMUX_LOG"
  grep -q "lr-poller-launch-aaaa000j-" "$TMUX_LOG"
  # and NO iTerm2 window was opened (the GUI path was never taken)
  [ "$(grep -c 'create window' "$OSA_LOG")" -eq 0 ]
  [ "$(launcher_count aaaa000j)" -eq 1 ]
  [ -x "$(launcher_for aaaa000j)" ]
  grep -q "lr-fire-resume.sh" "$(launcher_for aaaa000j)"
  [ -f "$STATE/resumed/aaaa000j-1111-2222-3333-444444444444.json" ]
  [ ! -e "$STATE/parked/aaaa000j-1111-2222-3333-444444444444.json" ]
  grep -qE 'RESUMED aaaa000j.*tmux' "$STATE/poller.log"              # mechanism recorded in the outcome
  rm -f "$LR_POLLER_LAUNCH_DIR"/lr-poller-launch-aaaa000j-*.sh
}

@test "LR-k: monthly-spend kill (no reset) → class-B decision packet opened, NEVER silent-parked" {
  local now; now=$(date +%s)
  mk_spend_transcript "aaaa000k-1111-2222-3333-444444444444" "$((now-1800))"
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  # cc-decide opened a class-B packet whose default is cross-account continuation (operator decision #3)
  grep -q 'open --class B' "$CCD_LOG"
  grep -q 'cross-account' "$CCD_LOG"
  grep -q -- '--session-sid aaaa000k-1111-2222-3333-444444444444' "$CCD_LOG"
  # the silent-park gap is CLOSED: a no-reset billing kill is surfaced, never parked and never dropped
  [ ! -e "$STATE/parked/aaaa000k-1111-2222-3333-444444444444.json" ]
  [ -f "$STATE/spend-packet/aaaa000k-1111-2222-3333-444444444444" ]  # idempotency marker
  grep -q "SPEND aaaa000k" "$STATE/poller.log"                       # greppable outcome (abstention law)
}

@test "LR-l: monthly-spend packet opened exactly ONCE across ticks (marker-keyed, no per-tick spam)" {
  local now; now=$(date +%s)
  mk_spend_transcript "aaaa000l-1111-2222-3333-444444444444" "$((now-1800))"
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ "$(grep -c 'open --class B' "$CCD_LOG")" -eq 1 ]                 # cc-decide invoked once, not per-tick
  [ "$(grep -c 'SPEND aaaa000l' "$STATE/poller.log")" -eq 1 ]
}

@test "LR-m: LR_POLLER_SPAWN=auto with no GUI (osascript fails) → falls back to tmux, never silent-fails a resume" {
  mk_parked "aaaa000m-1111-2222-3333-444444444444" "$(past_iso)"
  OSA_FAIL=1 LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once          # default LR_POLLER_SPAWN=auto
  [ "$status" -eq 0 ]
  grep -q 'create window' "$OSA_LOG"                                 # GUI attempted first...
  grep -q 'new-session' "$TMUX_LOG"                                  # ...then tmux carried it headlessly
  grep -q "lr-poller-launch-aaaa000m-" "$TMUX_LOG"
  [ -f "$STATE/resumed/aaaa000m-1111-2222-3333-444444444444.json" ]
  grep -qE 'RESUMED aaaa000m.*tmux' "$STATE/poller.log"
  rm -f "$LR_POLLER_LAUNCH_DIR"/lr-poller-launch-aaaa000m-*.sh
}

@test "LR-n: teammate monthly-spend session → NO packet (lead-owned recovery), teammate-skip logged" {
  local now; now=$(date +%s)
  mk_spend_teammate_transcript "aaaa000n-1111-2222-3333-444444444444" "$((now-1800))"
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ ! -s "$CCD_LOG" ]                                                # cc-decide never called for a teammate
  [ ! -e "$STATE/spend-packet/aaaa000n-1111-2222-3333-444444444444" ]
  grep -q "SKIP  aaaa000n" "$STATE/poller.log"
}

# ── LR-o/LR-p (2026-07-25): TEXT IS NOT EVIDENCE ────────────────────────────────────────────────
# A HEALTHY session that merely LISTS the limit-recover skill. That skill's own description quotes
# BOTH limit strings as usage examples — "You've hit your session/weekly limit" and "Teammate @x
# failed - You've hit your monthly spend limit" — and rides in the skill_listing attachment of EVERY
# session, with NO isApiErrorMessage envelope. This is the real producer's literal emission (memory:
# fixture-shape-parity-with-real-producer), captured from incident 2026-07-25: sessions fb1d3fc8 and
# a402c9f3 on next4 each got a FALSE class-B "monthly spend limit" packet off this text alone, while
# lr-audit read limit_events:[] for both. Measured discriminator on that incident — genuine session:
# 3 text-matching lines, 1 carrying the envelope; both false sessions: 1 text line, 0 envelope.
mk_skill_listing_transcript() {
  local sid="$1" extra="${2:-}"
  local proj="$HOME/.claude-quaternary/projects/-test-proj"
  mkdir -p "$proj"
  python3 - "$proj/$sid.jsonl" "$CWD" "$extra" <<'PY'
import json, sys
from datetime import datetime, timezone
out, cwd, extra = sys.argv[1], sys.argv[2], sys.argv[3]
ts = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
desc = ("- limit-recover: Recover perfectly from a usage-limit interruption (5-hour / weekly / "
        "model-scoped Fable / monthly-spend cap) — disk-truth audit of every Dynamic Workflow slot, "
        "subagent, task, AND Agent-Team assignee session. Use when: a session was killed by "
        "\"You've hit your session/weekly limit\", when teammates died mid-wave (\"Teammate @x "
        "failed - You've hit your monthly spend limit\"), when resuming after a limit (\"continue, "
        "we hit our limit\"), or when the reset is too far away.")
recs = [{"type": "user", "cwd": cwd, "timestamp": ts,
         "message": {"role": "user", "content": "go"}},
        {"parentUuid": "p1", "isSidechain": False,
         "attachment": {"type": "skill_listing", "content": desc}},
        {"type": "assistant", "timestamp": ts,
         "message": {"role": "assistant", "model": "claude-opus-4-8",
                     "content": [{"type": "text", "text": "done"}]}}]
if extra:   # a GENUINE reset-bearing session kill, appended AFTER the skill listing
    recs.append({"type": "assistant", "isApiErrorMessage": True, "error": "rate_limit",
                 "timestamp": ts, "message": {"role": "assistant", "model": "claude-opus-4-8",
                 "content": [{"type": "text",
                              "text": "You've hit your session limit · resets %s (UTC)" % extra}]}})
# compact separators — Claude Code writes transcripts WITHOUT spaces after ':'. json.dumps' default
# ("key": true) silently defeated a `"isApiErrorMessage":true` grep here, so the fixture must carry
# the producer's real encoding, not merely its real fields. (The poller's own predicate was hardened
# to tolerate either spacing at the same time — a guard whose failure mode is fail-CLOSED on the
# session|weekly branch must not hinge on a writer's whitespace.)
with open(out, "w") as f:
    for r in recs:
        f.write(json.dumps(r, separators=(",", ":")) + "\n")
PY
}

@test "LR-o: skill-listing text WITHOUT the isApiErrorMessage envelope → NO packet, NO park (false-positive guard)" {
  mk_skill_listing_transcript "aaaa000o-1111-2222-3333-444444444444"
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  # the whole point: a session that never hit anything must not reach the operator's decision queue
  [ ! -s "$CCD_LOG" ]
  [ ! -e "$STATE/spend-packet/aaaa000o-1111-2222-3333-444444444444" ]
  [ ! -e "$STATE/parked/aaaa000o-1111-2222-3333-444444444444.json" ]
  # and it must not be misfiled as a teammate either (the only other silencing path)
  ! grep -q "aaaa000o" "$STATE/poller.log"
}

@test "LR-p: skill-listing text AND a genuine session kill → still PARKED (spend branch must not shadow it)" {
  # The pre-fix spend branch matched the skill-listing text and then `continue`d unconditionally,
  # so a real reset-bearing kill in the same tail was never evaluated. Parking here proves the
  # fall-through: the spend text is present, the spend envelope is not, the session kill still lands.
  mk_skill_listing_transcript "aaaa000p-1111-2222-3333-444444444444" "$(future_disp)"
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ ! -s "$CCD_LOG" ]                                                # not a spend event
  [ ! -e "$STATE/spend-packet/aaaa000p-1111-2222-3333-444444444444" ]
  [ -f "$STATE/parked/aaaa000p-1111-2222-3333-444444444444.json" ]    # the real kill was still seen
  grep -q "PARKED aaaa000p" "$STATE/poller.log"
}

# ── LR-q..LR-s: parked-record fields are DATA, never code (sec fix 2026-07-30) ───────────
# Codex-security finding 1 (medium): §2 read the parked record with `eval "$(python3 … json.dumps …)"`
# and built the resume launcher with `printf '"%s"'`. Neither is shell quoting: json.dumps escapes
# `"` and `\` but NOT `$`/backtick, and a %s inside literal double quotes in GENERATED bash source
# re-expands when that source runs. `cwd` is a directory NAME, and `proj$(…)` is a legal one — and a
# record carrying it is valid JSON, so it passes the §1 writer unmangled. The daemon is LOADED
# (com.reso.lr-reset-poller), so the payload ran unattended, every ~10 min.
#
# The payload is `touch <canary>`: it needs NO quote character, which is the whole point — a `"`
# would have made the record malformed JSON and been skipped. Canary absent = the field stayed data.
# Proven RED against the pre-fix poller (both sites fire their canary) before being recorded green.
PAYLOAD_CWD() { printf '%s/proj$(touch %s)' "$CWD" "$1"; }

@test "LR-q: parked-record cwd carrying \$(…) is DATA — the reader never executes it" {
  local canary="$BATS_TEST_TMPDIR/PWNED-q" pay; pay="$(PAYLOAD_CWD "$canary")"
  mk_parked "aaaa000q-1111-2222-3333-444444444444" "$(past_iso)" "$pay"
  # the record must be VALID JSON — otherwise this proves only that malformed input is skipped
  run jq -e -r '.cwd' "$STATE/parked/aaaa000q-1111-2222-3333-444444444444.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$pay" ]
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ ! -e "$canary" ]                                  # ← the finding: pre-fix this file EXISTS
}

@test "LR-r: a malformed/unreadable parked record is SKIPPED, never half-assigned" {
  # Fail-closed leg of the same fix: the eval it replaced would assign whatever fields parsed and
  # carry stale loop values for the rest. A short read must abandon the record, not proceed.
  printf '{"sid":"aaaa000r","acct":"next4",NOT-JSON\n' > "$STATE/parked/aaaa000r-1111-2222-3333-444444444444.json"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  grep -q "SKIP  aaaa000r" "$STATE/poller.log"
  [ "$(launcher_count aaaa000r)" -eq 0 ]                             # nothing was fired off it
}

@test "LR-s: the generated launcher passes cwd VERBATIM as one argv element (no re-expansion)" {
  # The launcher is bash SOURCE that runs later, so quoting there is a second, independent site.
  # Executing it is the only assertion that can actually fail — a content grep would pass
  # vacuously. The poller is run from a byte-identical `cp -R` of the real directory so that
  # $LR/lr-fire-resume.sh resolves to a recorder instead of really spawning a session; the
  # artifact under test is unmodified (memory: control-must-replay-the-real-artifact).
  local lrcopy="$BATS_TEST_TMPDIR/lr" canary="$BATS_TEST_TMPDIR/PWNED-s" pay
  cp -R "$REPO/scripts/limit-recover" "$lrcopy"
  cat > "$lrcopy/lr-fire-resume.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "${FIRE_ARGV:?}"          # one line per argv element — a split is visible
STUB
  chmod +x "$lrcopy/lr-fire-resume.sh"
  pay="$(PAYLOAD_CWD "$canary")"
  mk_parked "aaaa000s-1111-2222-3333-444444444444" "$(past_iso)" "$pay"
  LR_POLLER_AUTOFIRE=1 run bash "$lrcopy/lr-reset-poller.sh" --once
  [ "$status" -eq 0 ]
  local launcher
  [ "$(launcher_count aaaa000s)" -eq 1 ]
  launcher="$(launcher_for aaaa000s)"
  [ -x "$launcher" ]
  export FIRE_ARGV="$BATS_TEST_TMPDIR/fire-argv.txt"
  run bash "$launcher"                              # ← expansion happens HERE, before exec
  [ "$status" -eq 0 ]
  [ ! -e "$canary" ]                                # pre-fix: the substitution fired
  # argv = acct, cwd, sid, --prompt, /limit-recover → cwd is line 2, intact and unsplit
  run sed -n '2p' "$FIRE_ARGV"
  [ "$output" = "$pay" ]
  run wc -l < "$FIRE_ARGV"
  [ "$(echo "$output" | tr -d ' ')" = 5 ]           # not split into extra words
}

# ── LR-t: the dry-run hint must not advise setting a variable that is already set ────────────────
# The notify branch is reached for TWO different reasons — autofire off, or autofire ON with
# --dry-run suppressing the fire — and until 2026-07-30 it emitted one hint for both: "Set
# LR_POLLER_AUTOFIRE=1 to auto-resume". On the production box (AUTOFIRE=1) that told the operator to
# set a variable already set to 1, i.e. it reported auto-resume as OFF while it was ON. Same
# understatement class as the plist/header drift LR-v guards, so it is pinned in the same commit.
@test "LR-t: --dry-run with AUTOFIRE=1 says autofire IS on (never 'set LR_POLLER_AUTOFIRE=1')" {
  mk_parked "rrrrrrrr-1111-2222-3333-444444444444" "$(past_iso)"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once --dry-run
  [ "$status" -eq 0 ]
  # nothing fired: --dry-run must still suppress the resume
  [ "$(grep -c 'create window' "$OSA_LOG")" -eq 0 ]
  [ ! -e "$LR_POLLER_LAUNCH_DIR/lr-poller-launch-rrrrrrrr.sh" ]
  # and the reason given must match the actual reason
  grep -q 'READY rrrrrrrr.*dry-run' "$STATE/poller.log"
  grep -q 'autofire IS on' "$STATE/poller.log"
  ! grep -q 'set LR_POLLER_AUTOFIRE=1 to auto-resume' "$STATE/poller.log"
  # the user-facing notification carries the same corrected hint, not the stale advice
  grep -q 'autofire IS on' "$OSA_LOG"
  ! grep -q 'Set LR_POLLER_AUTOFIRE=1' "$OSA_LOG"

  # CONTROL — the autofire-OFF path must STILL give the actionable advice (the fix must not delete
  # the hint that is correct in the branch where it applies).
  mk_parked "rrrr0000-1111-2222-3333-444444444444" "$(past_iso)"
  run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  grep -q 'READY rrrr0000.*notify-only' "$STATE/poller.log"
  grep -q 'set LR_POLLER_AUTOFIRE=1 to auto-resume' "$STATE/poller.log"
}

# ── LR-u: --dry-run is positional-INDEPENDENT (found by LR-t, 2026-07-30) ─────────────────────────
# The parser read only `$1`, so `--once --dry-run` silently ran FOR REAL — the resume fired while the
# operator had asked for a preview. LR-t caught it as a side effect; LR-u pins the parser itself, in
# BOTH orders, plus the refusal that replaced the silent ignore.
@test "LR-u: --dry-run suppresses the fire in ANY argument position; unknown args are refused" {
  # position 2 — the order that silently fired before the fix
  mk_parked "ssss0002-1111-2222-3333-444444444444" "$(past_iso)"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once --dry-run
  [ "$status" -eq 0 ]
  [ "$(grep -c 'create window' "$OSA_LOG")" -eq 0 ]
  [ ! -e "$LR_POLLER_LAUNCH_DIR/lr-poller-launch-ssss0002.sh" ]
  [ -f "$STATE/parked/ssss0002-1111-2222-3333-444444444444.json" ]     # still parked: nothing resumed

  # position 1 — the order that always worked, so the fix must not have broken it
  mk_parked "ssss0001-1111-2222-3333-444444444444" "$(past_iso)"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --dry-run --once
  [ "$status" -eq 0 ]
  [ "$(grep -c 'create window' "$OSA_LOG")" -eq 0 ]
  [ -f "$STATE/parked/ssss0001-1111-2222-3333-444444444444.json" ]

  # a real fire is still reachable — this test must not pass merely because nothing ever fires
  mk_parked "ssss0003-1111-2222-3333-444444444444" "$(past_iso)"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ "$(grep -c 'create window' "$OSA_LOG")" -eq 1 ]
  rm -f "$LR_POLLER_LAUNCH_DIR/lr-poller-launch-ssss0003.sh"

  # unknown args are refused, never silently ignored (the silence is what hid the bug)
  run bash "$POLLER" --dry-runn
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
  # and a bare run (how launchd invokes it) still parses
  run bash "$POLLER"
  [ "$status" -eq 0 ]
}

# ── LR-v: the SSOT PAIR — plist posture == script-header posture ─────────────────────────────────
# This is a REPO-FACT assertion, not a behaviour one, and it exists because of a 12-day drift:
# autofire went live 2026-07-18, the plist was reconciled 2026-07-25 (4b0efff2), and the poller's own
# header STILL read "auto-spawn is OFF by default … set LR_POLLER_AUTOFIRE=1 ONLY after eyeballing a
# live cycle" until 2026-07-30. A 2026-07-29 security scan read that pair and could not tell which
# side was authoritative.
#
# scripts/launchd-parity-lint.sh already chains live == plist (normalized plutil compare, nightly).
# It is structurally blind to PROSE in a sibling file, so it could never have caught this half. LR-v
# closes the chain: live == plist (parity lint) == header marker (here). Both links are needed —
# neither alone would have surfaced the drift.
#
# Read with plistlib, NOT `plutil -extract`: without `-o` that rewrites its input IN PLACE, which is
# the exact incident launchd-parity-lint.sh was written to make unrepeatable. plistlib is a pure
# reader and ignores XML comments, so a commented-out block correctly reads as ABSENT (verified: the
# pre-4b0efff2 shape yields None, so re-commenting the block fails this test rather than passing it).
@test "LR-v: committed plist and poller header declare the SAME shipped autofire posture" {
  local plist="$REPO/scripts/limit-recover/com.reso.lr-reset-poller.plist"
  [ -f "$plist" ]

  # ACTIVE value in the plist — absent (commented out / removed) reads as the empty string.
  local from_plist
  from_plist=$(python3 - "$plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
print(d.get('EnvironmentVariables', {}).get('LR_POLLER_AUTOFIRE', ''))
PY
)
  # Declared value in the daemon's own header marker — absent reads as the empty string.
  local from_header
  from_header=$(sed -n 's/^# SHIPPED-POSTURE: LR_POLLER_AUTOFIRE=\([0-9][0-9]*\).*/\1/p' "$POLLER" | head -1)

  # Render both sides BEFORE asserting: on failure the TAP output must show which side moved.
  echo "plist LR_POLLER_AUTOFIRE  = '${from_plist}'"
  echo "header SHIPPED-POSTURE    = '${from_header}'"

  # (a) the plist must ACTIVELY set autofire — re-commenting the block is the original incident
  #     (it would silently kill unattended auto-resume on the next reinstall).
  [ -n "$from_plist" ]
  # (b) the header must carry the marker at all — deleting it must not silently pass.
  [ -n "$from_header" ]
  # (c) and the two must agree, so neither file can drift away from the other unnoticed.
  [ "$from_plist" = "$from_header" ]

  # The header must not simultaneously assert the pre-activation posture as the SHIPPED one. The
  # exact sentence that was false for 12 days; keyed on the claim, not on incidental wording.
  ! grep -q '^# SAFETY — auto-spawn is OFF by default' "$POLLER"
}
