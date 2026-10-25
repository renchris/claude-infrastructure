#!/usr/bin/env bats
# bin/cc-husk-sweep — LINEAGE (lr-wake incident 2026-10-18, REPORT §4 Wave F; h defect 2).
# Pane 332 read `2e9ed9f2 … dirty RESUME`, but 2e9ed9f2 had re-registered in pane 442 and recycled
# there into fad30cb7 (live). `--resume` would have started a second copy. The sweep now consults
# handoff-fire's recycle-engaged rows (successor proven by its HANDOFF-RECYCLE- brief marker),
# claimed pane-successor stages, and later registrations elsewhere before any row says RESUME.
# Every source is fixtured through the tool's seams. RED on origin/main (7dc482f24), measured: the
# four lineage cases read RESUME there; the two CONTROL cases pass on both.
# shellcheck disable=SC2030,SC2031

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SWEEP="${CC_HUSK_SWEEP_UNDER_TEST:-$REPO/bin/cc-husk-sweep}"
  T="$BATS_TEST_TMPDIR"
  export CC_REGISTRY_DIR="$T/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_HUSK_CRASH_LOG="$T/crashes.jsonl"; : > "$CC_HUSK_CRASH_LOG"
  export CC_HUSK_LOG="$T/husk-sweep.jsonl" CC_HUSK_STORES="$T/.claude-tertiary"
  export CC_HUSK_PANES_JSON="$T/panes.json" CC_HUSK_PS_FILE="$T/ps.txt" CC_HUSK_IT2="$T/it2"
  export CC_HUSK_WATCHDOG_LOG="$T/watchdog.log" CC_HUSK_LIVE_SIDS="$T/live.txt"
  export CC_HUSK_HANDOFFS_LOG="$T/handoffs.jsonl" CC_PANE_SUCCESSOR_DIR="$T/pane-successor"
  export LR_STATE_DIR="$T/lr"
  NOW=$(date +%s); export CC_HUSK_KITTY_START_EPOCH=$((NOW - 86400))
  printf '#!/bin/bash\necho "$*" >> "%s"\nexit 0\n' "$T/it2.log" > "$CC_HUSK_IT2"; chmod +x "$CC_HUSK_IT2"
  CWD="$T/wt"; mkdir -p "$CWD"
  # pane 332: a husk (login + zsh, no claude)
  printf '[{"id":"332","pid":100,"cwd":"%s"}]\n' "$CWD" > "$CC_HUSK_PANES_JSON"
  printf '%s\n' "100 1 login -fp chris" "101 100 -zsh" > "$CC_HUSK_PS_FILE"
  SID="2e9ed9f2-9e21-4161-a0f7-10b329ade8f0"; SUCC="fad30cb7-0000-4000-8000-000000000001"
  : > "$T/live.txt"; : > "$T/watchdog.log"; mkdir -p "$CC_PANE_SUCCESSOR_DIR"
  R0=$((NOW - 40000))                        # the session registers in pane 332
  register "$SID" 332 "$R0"
  tx "$SID" '{"type":"user","cwd":"'"$CWD"'","message":{"role":"user","content":"find a flat"}}' \
             '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Good to close: no — searching"}]}}'
  # It was killed mid-task: RESUME needs a crash (husk-history FIX-DESIGN §2), so the crash log says so.
  printf '{"sid":"%s","class":"CRASH","cause":"external-sigterm"}\n' "$SID" > "$CC_HUSK_CRASH_LOG"
}
register() { printf '[%s] registered session=%s pid=1 tty=ttys0%s pane=%s\n' "$(date -r "$3" '+%Y-%m-%d %H:%M:%S')" "$1" "$2" "$2" >> "$T/watchdog.log"; }
tx() { local s="$1"; shift; mkdir -p "$T/.claude-tertiary/projects/p"; printf '%s\n' "$@" > "$T/.claude-tertiary/projects/p/$s.jsonl"; }
engaged() { printf '{"ts":"%s","class":"recycle-engaged","target_pane":"%s","prev_sid":"%s"}\n' "$(date -u -r "$2" +%FT%TZ)" "$1" "$SID" >> "$T/handoffs.jsonl"; }
verdict() { "$SWEEP" --json | jq -r 'select(.pane == "332") | .verdict'; }

@test "pane 332 replay: re-registered in 442, recycled there into a successor whose brief carries HANDOFF-RECYCLE — RECYCLED, never resumed" {
  register "$SID" 442 $((R0 + 30000))
  register "$SUCC" 442 $((R0 + 37000))
  tx "$SUCC" '{"type":"user","message":{"role":"user","content":"## Recycle brief\nHANDOFF-RECYCLE-46715-1792333171-645"}}'
  engaged 442 $((R0 + 37010)); printf '%s\n' "$SUCC" > "$T/live.txt"
  run verdict
  [ "$output" = "RECYCLED→fad30cb7" ] || { echo "got: $output"; false; }
  run "$SWEEP" --resume --all --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to resume"* ]] || { echo "$output"; false; }
  ! grep -q -- "--resume $SID" "$T/it2.log" 2>/dev/null || false
}

@test "a claimed pane-successor stage whose predecessor is this sid — RECYCLED→pane, never resumed" {
  printf '{"pane":"442","pane_tty":"ttys086","pred_sid":"%s","nonce":"n"}\n' "$SID" > "$CC_PANE_SUCCESSOR_DIR/ttys086.json"
  : > "$CC_PANE_SUCCESSOR_DIR/ttys086.claimed.4242"
  run verdict
  [ "$output" = "RECYCLED→pane 442" ] || { echo "got: $output"; false; }
}

@test "the sid registered later in another pane, no successor proven — MOVED→pane, never resumed" {
  register "$SID" 442 $((R0 + 30000))
  run verdict
  [ "$output" = "MOVED→pane 442" ] || { echo "got: $output"; false; }
}

# Wave C2 (husk-panes round 2, RC2): the later registration is a teammate's, so its line ends
# ` teammate=<id>`; the `pane=([0-9]+)\s*$` regex never saw it. RED on 67b74ef87 (reads RESUME).
@test "wave C2: the sid registered later in another pane AS A TEAMMATE (trailing ' teammate=<id>') — MOVED→pane" {
  printf '[%s] registered session=%s pid=1 tty=ttys0442 pane=442 teammate=tm2-H11@session-x\n' "$(date -r $((R0 + 30000)) '+%Y-%m-%d %H:%M:%S')" "$SID" >> "$T/watchdog.log"
  run verdict
  [ "$output" = "MOVED→pane 442" ] || { echo "got: $output"; false; }
}

@test "pane-end-of-life A5: a later tty=none registration (a headless resume) is NOT a move — pane 85's MOVED→pane 16" {
  # lane K's `claude -p --resume 570d3917`, run from lead 666022fd's Bash tool, registered as
  # `tty=none pane=16` because it inherited the lead's KITTY_WINDOW_ID. The session never left 85.
  printf '[%s] registered session=%s pid=23549 tty=none pane=%s\n' "$(date -r $((R0 + 30000)) '+%Y-%m-%d %H:%M:%S')" "$SID" 442 >> "$T/watchdog.log"
  run verdict
  [ "$output" != "MOVED→pane 442" ] || { echo "pre-fix: the headless run read as a move"; false; }
}

@test "a successor in another pane WITHOUT a HANDOFF-RECYCLE marker is not proven: MOVED, not RECYCLED" {
  register "$SUCC" 442 $((R0 + 37000))
  tx "$SUCC" '{"type":"user","message":{"role":"user","content":"hello"}}'
  engaged 442 $((R0 + 37010))
  run verdict
  [ "$output" = "MOVED→pane 442" ] || { echo "got: $output"; false; }
}

@test "CONTROL: lineage from BEFORE this pane's registration (its own earlier history) does not convict — RESUME stands" {
  register "$SID" 442 $((R0 - 9000))
  engaged 442 $((R0 - 8000))
  printf '{"pane":"442","pred_sid":"%s"}\n' "$SID" > "$CC_PANE_SUCCESSOR_DIR/ttys086.json"
  touch -t "$(date -r $((R0 - 8000)) +%Y%m%d%H%M.%S)" "$CC_PANE_SUCCESSOR_DIR/ttys086.json"
  : > "$CC_PANE_SUCCESSOR_DIR/ttys086.claimed.1"; touch -t "$(date -r $((R0 - 8000)) +%Y%m%d%H%M.%S)" "$CC_PANE_SUCCESSOR_DIR/ttys086.claimed.1"
  run verdict
  [ "$output" = "RESUME" ] || { echo "got: $output"; false; }
}

@test "CONTROL: an in-place recycle row for THIS pane with no different successor is no lineage — RESUME stands" {
  engaged 332 $((R0 + 600))
  run verdict
  [ "$output" = "RESUME" ] || { echo "got: $output"; false; }
}
