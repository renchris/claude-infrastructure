#!/usr/bin/env bats
# lr-reset-poller.sh § 2 — THE PARKED LOOP'S READ-ONLY GATES, CHEAPEST FIRST (decision e276a5e2fb63,
# option (c), 2026-10-11). A husk record that no registry row names must cost ONE `pgrep resume`
# per tick, not two, and its outcome must not change. The two projects/* globs the reorder also
# skips have no process to count; they are pinned by the comment beside them, not by a trace.
# Hermetic: fixture $HOME and stubs, as tests/lr-poller-stranded-husk.bats; a counting pgrep on PATH
# (the tests/lr-lib-registry-one-jq.bats:26-30 pattern) that then runs the real one.

setup() {
  export LR_UPGRADE_AUTO=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$STATE/locks" "$STATE/requests" "$BATS_TEST_TMPDIR/stubs"
  SID="e276a5e2-0000-4000-8000-0000000000cc"
  unset CLAUDE_CONFIG_DIR KITTY_WINDOW_ID CC_TERM_KITTY_TO LR_RQ_TEAMMATE_PREDICATE LR_PREDICATE_PY LR_CONFIG_DIRS LR_RQ_BG_HOLDER LR_SUCCESSOR_GATE LR_HUSK_RETIRE
  export LR_POLLER_NO_CENSUS=1
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_HANDOFF_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl"; : > "$CC_HANDOFF_LOG"
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/env"; mkdir -p "$LR_MOVE_ENV_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket"
  export LR_CC_TUI_LIB="$BATS_TEST_TMPDIR/absent-cc-tui.sh"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stubs/osascript"
  printf '#!/bin/bash\ncase " $* " in *" --rank "*) echo none; exit 0 ;; esac\necho %s\n' "'{\"rows\":[{\"acct\":\"next4\",\"session_pct\":12,\"weekly_pct\":40}]}'" > "$HOME/bin/claude-accounts"
  export PGREP_LOG="$BATS_TEST_TMPDIR/pgrep.log"; : > "$PGREP_LOG"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$PGREP_LOG"\nexec /usr/bin/pgrep "$@"\n' > "$BATS_TEST_TMPDIR/stubs/pgrep"
  chmod +x "$BATS_TEST_TMPDIR/stubs/osascript" "$BATS_TEST_TMPDIR/stubs/pgrep" "$HOME/bin/claude-accounts"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
  export LR_FLEET_BIN="$BATS_TEST_TMPDIR/stubs/lr-fleet" FLEET_LOG="$BATS_TEST_TMPDIR/fleet.log"; : > "$FLEET_LOG"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$FLEET_LOG"\nexit 0\n' > "$LR_FLEET_BIN"; chmod +x "$LR_FLEET_BIN"
  export LR_BACKLOG_BIN="$BATS_TEST_TMPDIR/stubs/cc-backlog"
  printf '#!/bin/bash\necho 0123456789ab\n' > "$LR_BACKLOG_BIN"; chmod +x "$LR_BACKLOG_BIN"
  : > "$STATE/autorecover.on"
  SRC="$HOME/.claude-secondary"; TGT="$HOME/.claude-quaternary"
  mkdir -p "$SRC/projects/-p" "$TGT/projects/-p"
}

tick() { LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once; }
plog() { cat "$STATE/poller.log" >&2 2>/dev/null || true; }
lim_rec() {
  printf '{"type":"assistant","timestamp":"2026-10-10T04:05:55Z","isApiErrorMessage":true,"error":"rate_limit","message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your weekly limit · resets 6am"}]}}\n'
}
# A moved session: .handed-off + /exit stub on the source, a confirm tombstone, the copy on the target.
# The target copy is aged past the 48 h § 1 window so § 1 never scans it: every `pgrep resume` counted
# below is § 2's.
husk_disk() {
  lim_rec > "$SRC/projects/-p/$SID.jsonl.handed-off"
  printf '{"type":"user","message":{"role":"user","content":"<local-command-stdout>(no content)</local-command-stdout>"}}\n' > "$SRC/projects/-p/$SID.jsonl"
  printf '{"handed_off_to":"%s","target_transcript":"%s/projects/-p/%s.jsonl","ts":"2026-10-10T04:18:07Z","confirm_len":1}\n' "$TGT" "$TGT" "$SID" > "$SRC/projects/-p/$SID.HANDOFF.json"
  lim_rec > "$TGT/projects/-p/$SID.jsonl"
  touch -t 202609010000 "$TGT/projects/-p/$SID.jsonl"
  printf '{"sid":"%s","from":"%s","to":"%s","cause":"limit"}\n' "$SID" "$SRC" "$TGT" > "$STATE/locks/$SID.lock"
}
holder() { # $1=pane $2=pid $3=account $4=cfg — a live registry row plus the pid's environment
  printf '{"session_id":"%s","pid":%s,"account":"%s","paneUUID":"%s","cwd":"/x"}\n' "$SID" "$2" "$3" "$1" > "$CC_REGISTRY_DIR/$1.json"
  printf '%s' "$4" > "$LR_MOVE_ENV_DIR/$2"
}
park_past() { # a record whose reset has passed, already noted as LEFT PARKED (the live census shape)
  printf '{"sid":"%s","acct":"next2","cfg":"%s","cwd":"/x","kind":"weekly","reset_at_utc":"2026-01-01T00:00:00Z","parked_at":"2025-12-31T04:15:46Z"}\n' \
    "$SID" "$SRC" > "$STATE/parked/$SID.json"
  : > "$STATE/parked/$SID.husk-noted"
}
resume_pgreps() { grep -c "resume $SID" "$PGREP_LOG" || true; }

@test "[RED] no registry row names the sid: ONE pgrep resume per tick (trunk: 2), and the record stays LEFT PARKED" {
  husk_disk; park_past
  tick
  [ "$status" -eq 0 ] || { plog; false; }
  [ "$(resume_pgreps)" -eq 1 ] || { cat "$PGREP_LOG"; plog; false; }
  [ -f "$STATE/parked/$SID.json" ] || { plog; false; }
  [ -e "$STATE/parked/$SID.husk-noted" ]
  [ ! -e "$STATE/requests/$SID.json" ] || { plog; false; }
  [ ! -e "$STATE/resumed/$SID.json" ] || { plog; false; }
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
}

@test "GUARD: a live source row still files the STRANDED-HUSK request and leaves the record parked" {
  husk_disk; park_past; holder 99168 "$$" claude-secondary "$SRC"
  tick
  [ "$status" -eq 0 ] || { plog; false; }
  [ "$(jq -r .requested_by "$STATE/requests/$SID.json")" = stranded-husk ] || { plog; false; }
  [ "$(jq -r .source_pane "$STATE/requests/$SID.json")" = 99168 ]
  grep -q "STRANDED-HUSK $SID" "$STATE/poller.log" || { plog; false; }
  [ -f "$STATE/parked/$SID.json" ] || { plog; false; }
  [ ! -e "$STATE/resumed/$SID.json" ] || { plog; false; }
}

@test "GUARD: a live row on the TARGET still retires the record as TRANSPLANTED" {
  husk_disk; park_past; holder 200 "$$" claude-quaternary "$TGT"
  tick
  [ "$status" -eq 0 ] || { plog; false; }
  grep -q "TRANSPLANTED $SID" "$STATE/poller.log" || { plog; false; }
  [ -f "$STATE/resumed/$SID.json" ] || { plog; false; }
  [ ! -e "$STATE/parked/$SID.json" ]
}

# ── option (g): a successor that RAN on the target and exited retires the record ─────────────────
turn_on_target() { # $1=timestamp → one content-bearing, non-error assistant turn on the target copy
  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"done, live on trunk"}]}}\n' "$1" >> "$TGT/projects/-p/$SID.jsonl"
  touch -t 202609010000 "$TGT/projects/-p/$SID.jsonl"
}

@test "[RED] (g) the successor took a turn on the target after the move and no pane holds the sid: retired TRANSPLANTED" {
  husk_disk; park_past; turn_on_target 2026-10-10T05:00:00.123Z
  tick
  [ "$status" -eq 0 ] || { plog; false; }
  grep -q "TRANSPLANTED $SID .*engaged-on-target after 2026-10-10T04:18:07Z" "$STATE/poller.log" || { plog; false; }
  [ -f "$STATE/resumed/$SID.json" ] || { plog; false; }
  [ ! -e "$STATE/parked/$SID.json" ]
  [ ! -e "$STATE/parked/$SID.husk-noted" ]
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
}

@test "(g) GUARD: a turn on the target from BEFORE the tombstone's ts is not the successor: left parked" {
  husk_disk; park_past; turn_on_target 2026-10-10T04:10:00Z
  tick
  [ -f "$STATE/parked/$SID.json" ] || { plog; false; }
  [ ! -e "$STATE/resumed/$SID.json" ] || { plog; false; }
}

@test "(g) GUARD: a live registry row on the source (a husk pane) keeps the record for the husk lane" {
  husk_disk; park_past; turn_on_target 2026-10-10T05:00:00Z; holder 99168 "$$" claude-secondary "$SRC"
  tick
  [ -f "$STATE/parked/$SID.json" ] || { plog; false; }
  [ ! -e "$STATE/resumed/$SID.json" ] || { plog; false; }
}

@test "(g) GUARD: an ADMIT-phase tombstone (the source was never retired) is never read as a carried session" {
  husk_disk; park_past; turn_on_target 2026-10-10T05:00:00Z
  printf '{"handed_off_to":"%s","target_transcript":"%s/projects/-p/%s.jsonl","ts":"2026-10-10T04:18:07Z","phase":"admit"}\n' "$TGT" "$TGT" "$SID" > "$SRC/projects/-p/$SID.HANDOFF.json"
  tick
  [ -f "$STATE/parked/$SID.json" ] || { plog; false; }
  [ ! -e "$STATE/resumed/$SID.json" ] || { plog; false; }
}
