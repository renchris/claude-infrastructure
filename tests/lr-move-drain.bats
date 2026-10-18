#!/usr/bin/env bats
# shellcheck disable=SC2016  # the fragment lines are single-quoted on purpose: they run in the fragment
# lr-reset-poller.sh — THE MID-TICK MOVE DRAIN (lr-inplace-immediacy, 2026-10-18).
#
# `cc-lr move` writes a request and kickstarts the poller, and launchd drops a kickstart while a tick
# runs. The tick looked at move/requests/ twice, at its top and as its last act, so a request written
# after the top waited for the END of the tick. Ticks are not short on a loaded box: on 2026-10-18 one
# ran 00:23:59Z → 01:50:07Z, and six batches written in that window started together at 01:50:07-16Z,
# 68 s to 85 min after they were asked for (docs/research/lr-inplace-immediacy-2026-10-18/REPORT.md).
# Four of those rows then refused as intent-invalid, their intents having expired in the queue.
#
# The tick now runs a drainer beside its arms: one look at move/requests/ every LR_MOVE_DRAIN_POLL_S
# (1 s) while the tick holds its lock, through the SAME lrp_move_kick (claim by hard link, so a batch
# is never started twice). It stops before the tick's own last look, and the tick waits for it, so a
# drainer is never cut down between its claim and its start.
#
# Every case builds its fixture; the live store is never read. Fragments are run under /bin/bash,
# the interpreter launchd starts the poller with (3.2 on this box).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRD="$REPO/scripts/limit-recover"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$LR_STATE_DIR/move/requests" "$LR_STATE_DIR/move/c1"
  echo '{"batch":"c1","rows":[]}' > "$LR_STATE_DIR/move/c1/plan.json"
  export LR_MOVE_BATCH_BIN="$BATS_TEST_TMPDIR/batch-rec"
  printf '#!/bin/bash\necho "$*" >> "%s/batch-rec.log"\n' "$BATS_TEST_TMPDIR" > "$LR_MOVE_BATCH_BIN"
  chmod +x "$LR_MOVE_BATCH_BIN"
  export LR_MOVE_DRAIN_POLL_S=0.2
  BASH_BIN=/bin/bash; [ -x "$BASH_BIN" ] || BASH_BIN=bash
}

# A tick in miniature: the lock, the poller's own EXIT trap and tick end, its kick, and the drainer —
# each lifted from the script itself, so this exercises the shipped text, not a copy of it.
tick_frag() { # $1=path → writes the preamble every case shares
  {
    echo 'STATE="$LR_STATE_DIR"; LR="$1"; DRY="${DRYRUN:-0}"; LOG="$STATE/poller.log"; LOCKD="$2"'
    echo 'mkdir "$LOCKD" || exit 9; echo $$ > "$LOCKD/pid"'
    printf '%s\n' 'log() { printf "%s\n" "$*" >> "$LOG"; }'
    sed -n '/^lrp_tick_end() {/,/^}/p' "$LRD/lr-reset-poller.sh"
    grep -E "^trap '[^']*' EXIT$" "$LRD/lr-reset-poller.sh"
    sed -n '/^lrp_move_kick() {/,/^}/p' "$LRD/lr-reset-poller.sh"
    sed -n '/^lrp_move_drain_start() {/,/^}/p' "$LRD/lr-reset-poller.sh"
    sed -n '/^lrp_move_drain_stop() {/,/^}/p' "$LRD/lr-reset-poller.sh"
    echo 'lrp_move_kick'                                   # the top of the tick: nothing queued yet
    echo 'lrp_move_drain_start'
    echo 'echo "${LRP_DRAIN_PID:-}" > "$STATE/drain.pid"'
  } > "$1"
}

@test "1 [RED] a move request that lands MID-TICK is started while the tick still runs, once, and the drainer dies with the tick" {
  frag="$BATS_TEST_TMPDIR/tick.sh"; tick_frag "$frag"
  {
    echo 'echo "{\"kind\":\"move-batch\",\"batch\":\"c1\"}" > "$STATE/move/requests/c1.json"'   # the request arrives mid-tick
    echo 'n=0; while [ ! -s "'"$BATS_TEST_TMPDIR"'/batch-rec.log" ] && [ "$n" -lt 150 ]; do sleep 0.2; n=$((n + 1)); done'
    echo '[ -s "'"$BATS_TEST_TMPDIR"'/batch-rec.log" ] && : > "$STATE/started-mid-tick"'
    echo 'exit 0'
  } >> "$frag"
  run "$BASH_BIN" "$frag" "$LRD" "$BATS_TEST_TMPDIR/tick.lock"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$LR_STATE_DIR/poller.log" 2>/dev/null; false; }
  # RED before the fix: only the tick's last look started it, after the arms (here: the wait) ended.
  [ -e "$LR_STATE_DIR/started-mid-tick" ] || { cat "$LR_STATE_DIR/poller.log" 2>/dev/null; false; }
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$BATS_TEST_TMPDIR/batch-rec.log" ] && break; sleep 0.2; done
  [ "$(cat "$BATS_TEST_TMPDIR/batch-rec.log")" = c1 ]
  grep -q 'MOVE-BATCH started pid [0-9]* (c1)' "$LR_STATE_DIR/poller.log"
  [ ! -e "$LR_STATE_DIR/move/requests/c1.json" ]
  [ -f "$LR_STATE_DIR/move/c1/request.claimed.json" ]
  [ ! -d "$BATS_TEST_TMPDIR/tick.lock" ]
  dp="$(cat "$LR_STATE_DIR/drain.pid")"
  [[ "$dp" =~ ^[0-9]+$ ]] || false
  if kill -0 "$dp" 2>/dev/null; then echo "drainer $dp outlived its tick"; false; fi
}

@test "2 a dry-run tick, and LR_MOVE_DRAIN=off, start no drainer" {
  frag="$BATS_TEST_TMPDIR/tick.sh"; tick_frag "$frag"; echo 'exit 0' >> "$frag"
  DRYRUN=1 run "$BASH_BIN" "$frag" "$LRD" "$BATS_TEST_TMPDIR/tick.lock"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$(cat "$LR_STATE_DIR/drain.pid")" ]
  LR_MOVE_DRAIN=off run "$BASH_BIN" "$frag" "$LRD" "$BATS_TEST_TMPDIR/tick.lock"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$(cat "$LR_STATE_DIR/drain.pid")" ]
}

@test "3 the drainer stops by itself when the tick's lock no longer names its tick (a signalled tick removes it)" {
  frag="$BATS_TEST_TMPDIR/tick.sh"; tick_frag "$frag"
  {
    echo 'rm -rf "$LOCKD"'                                # what the INT/TERM trap does
    echo 'n=0; while kill -0 "$LRP_DRAIN_PID" 2>/dev/null && [ "$n" -lt 150 ]; do sleep 0.2; n=$((n + 1)); done'
    echo 'kill -0 "$LRP_DRAIN_PID" 2>/dev/null && : > "$STATE/drainer-outlived-lock"'
    echo 'trap - EXIT; exit 0'
  } >> "$frag"
  run "$BASH_BIN" "$frag" "$LRD" "$BATS_TEST_TMPDIR/tick.lock"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$LR_STATE_DIR/drainer-outlived-lock" ]
}

@test "4 the drainer is started in the shipped tick right after the top-of-tick kick, and the tick end stops it before its own look" {
  grep -qE '^lrp_move_kick; lrp_move_drain_start$' "$LRD/lr-reset-poller.sh"
  body="$(sed -n '/^lrp_tick_end() {/,/^}/p' "$LRD/lr-reset-poller.sh")"
  stop_at="$(printf '%s\n' "$body" | grep -n 'lrp_move_drain_stop' | head -1 | cut -d: -f1)"
  kick_at="$(printf '%s\n' "$body" | grep -n 'lrp_move_kick' | head -1 | cut -d: -f1)"
  [ -n "$stop_at" ] && [ -n "$kick_at" ] && [ "$stop_at" -lt "$kick_at" ]
}
