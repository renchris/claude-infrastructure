#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# scripts/limit-recover/lr-move-batch.sh + lr-move-worker.sh — one batch of 15 sessions, admitted
# once and moved in parallel under a slot semaphore (design-swap-v3 §4.2, §5 P2; 2026-10-04).
#
# THE LANE THIS REPLACES was one global lock and a 10 s gap: 15 sessions took 20-24 minutes, each
# paid a model turn, and one busy subject blocked the queue (762a6daa held it for 202 s). What a
# parallel lane must not buy with that speed is asserted here, on 15 stub sessions:
#   · ONE router read at admission (plus the one fresh re-read at close), never one per session;
#   · concurrent moves never exceed the slot width, and the width is actually reached;
#   · at most one actuator per session, on every path, including a re-run and a dead runner's claims;
#   · every row ends with a verdict, and `cc-lr move --status` reproduces each from disk;
#   · no mail to a moved pane (a mailed no-prompt resume takes a turn) and at most one to the requester;
#   · the two close checks can FAIL: a target the router drops, a moved session the guard blocks.
# What this suite cannot see, and says so: kitty RPC, secd, real TUI boots. Those are the live ramp's.
#
# Hermetic: sessions are `sleep`s, lr-handoff / claude-accounts / cc-notify are recorders.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_GATE=off
  export CC_FIRE_CAPACITY_GATE=off
  # shellcheck source=/dev/null
  . "$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/helpers/lr-move-fixture.sh"
  mvf_setup
  mvf_handoff_stub
  export STUB_BOOT_S=1
  export CC_ACCOUNTS_BIN="$STUBS/claude-accounts"
  cat > "$CC_ACCOUNTS_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$RANK_LOG"
[ -z "${RANK_FAIL_AFTER:-}" ] || [ "$(grep -c . "$RANK_LOG")" -le "$RANK_FAIL_AFTER" ] || { echo "ranked 1 of 2; excluded — next3=logged-out" >&2; echo "next2 0.4"; exit 0; }
case "${RANK_MODE:-ok}" in
  ok) printf 'next3 0.9\nnext2 0.4\n' ;;
  excluded) echo "ranked 1 of 2; excluded — next3=kmax-concurrency" >&2; echo "next2 0.4" ;;
  down) exit 3 ;;
esac
STUB
  chmod +x "$CC_ACCOUNTS_BIN"
  export RANK_LOG="$BATS_TEST_TMPDIR/rank.log"; : > "$RANK_LOG"
  export CC_NOTIFY_BIN="$STUBS/cc-notify" NOTIFY_LOG="$BATS_TEST_TMPDIR/notify.log"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$NOTIFY_LOG"\n' > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"
  : > "$NOTIFY_LOG"
  export LR_MOVE_GUARD_BIN="$REPO/hooks/handed-off-session-guard.sh"
  ROWS=()
  # FIFTEEN SESSIONS ONCE, FOUR ELSEWHERE. Case 1 is the N=15 batch the design is judged on. Every
  # other case asserts a property that does not depend on the count, and a suite that forks 15
  # workers thirteen times took 25 minutes on a loaded box and is the kind of burst the machine's
  # compressor sentinel signals. Width 2 over 4 sessions still makes the semaphore bind.
  case "$BATS_TEST_DESCRIPTION" in
    "1 "*) N=15; W=4 ;;
    *) N=4; W=2 ;;
  esac
  for i in $(seq 1 "$N"); do
    sid="$(printf 'cccc%04d-0000-4000-8000-000000000001' "$i")"
    mvf_session "$((500 + i))" "$sid"
    ROWS+=("$((500 + i)):$sid")
  done
  MVF_SLOTS="$W" mvf_plan c1 move "${ROWS[@]}"
}
teardown() { mvf_teardown; }

batch() { run bash "$LRD/lr-move-batch.sh" c1; }
verdicts() { for f in "$BDIR"/cccc*.json; do jq -r .verdict "$f"; done | sort | uniq -c | awk '{ printf "%s=%s ", $2, $1 }'; }
# On a mismatch, show every row that is not MOVED with its reason (the diagnosis, not a second assertion).
all_moved() { [ "$(verdicts)" = "MOVED=$N " ] || { verdicts; for f in "$BDIR"/cccc*.json; do jq -r 'select(.verdict != "MOVED") | "\(.sid) \(.verdict): \(.reason)"' "$f"; done; for r in "$CC_REGISTRY_DIR"/50[12].json; do cat "$r"; p="$(jq -r .pid "$r")"; if kill -0 "$p" 2>/dev/null; then echo "pid $p alive"; else echo "pid $p DEAD"; fi; done; false; }; }

@test "1 [RED] 15 sessions: all MOVED, slots never above the width and the width reached, one actuator each" {
  batch
  [ "$status" -eq 0 ]
  all_moved
  max="$(sort -n "$STUB_LOG/slots.log" | tail -1)"
  [ "$max" -le 4 ]
  [ "$max" -ge 2 ]
  [ "$(cut -d' ' -f1 "$STUB_LOG/typers.log" | sort | uniq -d | grep -c . || true)" -eq 0 ]
  [ "$(grep -c . "$STUB_LOG/typers.log")" -eq "$N" ]
  [ -z "$(ls -A "$LR_STATE_DIR/runs/by-sid" 2>/dev/null)" ]
  [ -z "$(ls -A "$LR_STATE_DIR/locks/swap-slots" 2>/dev/null)" ]
  [ ! -d "$LR_STATE_DIR/locks/move-admit.lock" ]
}

@test "2 [RED] the router is read ONCE at admission and once fresh at close — never per session" {
  batch
  [ "$(grep -c . "$RANK_LOG")" -eq 2 ]
  [ "$(grep -c -- '--fresh' "$RANK_LOG")" -eq 1 ]
  [ "$(jq -r .target_auth "$BDIR/admit.json")" = ok ]
  [ "$(jq -r .target_auth_after "$BDIR/summary.json")" = ok ]
}

@test "3 [RED] no mail reaches a moved pane, and the requester gets exactly one summary" {
  batch
  [ "$(grep -c . "$NOTIFY_LOG")" -eq 1 ]
  grep -q '^999 cc-lr move c1 ' "$NOTIFY_LOG"
  ! grep -qE '^50[0-9]|^51[0-9]' "$NOTIFY_LOG" || false
  ! grep -q 'cc_tui_submit\|cc_tui_type' "$LRD/lr-move-batch.sh" "$LRD/lr-move-worker.sh" "$LRD/lr-move-lib.sh"
}

@test "4 [RED] cc-lr move --status re-derives every verdict from disk, and it matches the recorded one" {
  batch
  export CC_ACCOUNT_MAP="$BATS_TEST_TMPDIR/absent-map.sh"
  run bash "$REPO/bin/cc-lr" move --status c1 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '[.rows[] | select(.verdict == "MOVED" and .recorded == "MOVED")] | length')" -eq "$N" ]
  [ "$(printf '%s' "$output" | jq -r '.summary.status')" = "done" ]
}

@test "5 a re-run of the same batch drives nothing a second time" {
  batch
  before="$(grep -c . "$STUB_LOG/typers.log")"
  batch
  [ "$(grep -c . "$STUB_LOG/typers.log")" -eq "$before" ]
  all_moved
}

@test "6 [RED] a runner that died mid-admit left claims behind: the next run takes them over and drives each once" {
  sleep 900 3>&- &
  dead=$!; kill "$dead"; wait "$dead" 2>/dev/null || true
  for ps in "${ROWS[@]}"; do
    s="${ps#*:}"; mkdir -p "$LR_STATE_DIR/runs/by-sid/$s.active"
    printf '{"sid":"%s","pane":"-","pid":%d,"ts":"t","by":"cc-lr-move","lstart":"Thu Jan 1 00:00:00 1970"}\n' "$s" "$dead" > "$LR_STATE_DIR/runs/by-sid/$s.active/holder"
  done
  batch
  all_moved
  [ "$(cut -d' ' -f1 "$STUB_LOG/typers.log" | sort | uniq -d | grep -c . || true)" -eq 0 ]
}

@test "7 a session another LIVE actuator has claimed is NOTMOVED claim-held and is never driven" {
  s="${ROWS[0]#*:}"; mkdir -p "$LR_STATE_DIR/runs/by-sid/$s.active"
  bash -c '. "$1/lr-lib.sh"; lr_claim_stamp "$2" "$3" "$4" other -' _ "$LRD" "$LR_STATE_DIR/runs/by-sid/$s.active" "$s" "$$"
  batch
  [ "$(jq -r .verdict "$BDIR/$s.json")" = NOTMOVED ]
  [[ "$(jq -r .reason "$BDIR/$s.json")" == claim-held:* ]] || false
  ! grep -q "^$s " "$STUB_LOG/typers.log" || false
  [ "$(grep -c . "$STUB_LOG/typers.log")" -eq "$((N - 1))" ]
  [ -d "$LR_STATE_DIR/runs/by-sid/$s.active" ]
}

@test "8 [RED] a target the router excludes refuses the WHOLE batch: every row NOTMOVED, nothing claimed or driven" {
  export RANK_MODE=excluded
  batch
  [ "$status" -eq 2 ]
  [ "$(verdicts)" = "NOTMOVED=$N " ]
  [ "$(jq -r .admitted "$BDIR/admit.json")" = false ]
  [[ "$(jq -r .reason "$BDIR/admit.json")" == "target-unroutable: kmax-concurrency"* ]] || false
  [ ! -s "$STUB_LOG/typers.log" ]
  [ -z "$(ls -A "$LR_STATE_DIR/runs/by-sid" 2>/dev/null)" ]
}

@test "9 [RED] a router that cannot answer refuses the batch (fail closed); the operator's --target-unverified admits it" {
  export RANK_MODE=down
  batch
  [ "$status" -eq 2 ]
  [[ "$(jq -r .reason "$BDIR/admit.json")" == target-unverified:* ]] || false
  [ ! -s "$STUB_LOG/typers.log" ]
  rm -f "$BDIR"/cccc*.json "$BDIR/admit.json" "$BDIR/summary.json"
  jq -c '.target_unverified = true' "$BDIR/plan.json" > "$BDIR/plan.json.t"; mv "$BDIR/plan.json.t" "$BDIR/plan.json"
  batch
  [ "$(grep -c . "$STUB_LOG/typers.log")" -eq "$N" ]
  [ "$(jq -r .target_auth "$BDIR/admit.json")" = unverified-accepted ]
  all_moved
  [[ "$(jq -r .target_auth_after "$BDIR/summary.json")" == unverified:* ]]
}

@test "10 [RED] the close check can fail: a target the router drops during the batch is reported LOST" {
  export RANK_FAIL_AFTER=1
  batch
  [[ "$(jq -r .target_auth_after "$BDIR/summary.json")" == "LOST: logged-out"* ]] || false
  grep -q 'target auth after the batch: LOST' "$NOTIFY_LOG"
}

@test "11 [RED] the close check can fail: a moved session the prompt guard blocks is rewritten FAILED guard-blocks" {
  batch
  s="${ROWS[0]#*:}"
  [ "$(jq -r .verdict "$BDIR/$s.json")" = MOVED ]
  # the guard, run on a second batch's close, against a moved session that has since gained a
  # foreign tombstone (the round-trip shape): the recorded MOVED does not survive it
  printf '{"handed_off_to":"%s","ts":"2026-10-03T02:28:00Z"}\n' "$SRC" > "$DST/projects/-x/$s.HANDOFF.json"
  rm -f "$BDIR/summary.json"
  batch
  [ "$(jq -r .verdict "$BDIR/$s.json")" = FAILED ]
  [[ "$(jq -r .reason "$BDIR/$s.json")" == guard-blocks:* ]] || false
  # control: with the check off the stale MOVED stands
  jq -c '.verdict = "MOVED" | .reason = "x"' "$BDIR/$s.json" > "$BDIR/$s.json.t"; mv "$BDIR/$s.json.t" "$BDIR/$s.json"
  LR_MOVE_GUARD_CHECK=off batch
  [ "$(jq -r .verdict "$BDIR/$s.json")" = MOVED ]
}

@test "12 KILL SWITCH: LR_MOVE_LANE=off — the batch is refused, every row NOTMOVED, nothing driven" {
  export LR_MOVE_LANE=off
  batch
  [ "$status" -eq 2 ]
  [ "$(verdicts)" = "NOTMOVED=$N " ]
  [ ! -s "$STUB_LOG/typers.log" ]
}

@test "13 the poller's kick claims a request by link and starts the runner once; a claimed batch is not started again" {
  export LR_POLLER_NO_CENSUS=1 LR_UPGRADE_AUTO=off LR_POLLER_LOCK_DIR="$BATS_TEST_TMPDIR/poller.lock"
  export LR_MOVE_BATCH_BIN="$STUBS/batch-rec"
  printf '#!/bin/bash\necho "$*" >> "%s/batch-rec.log"\n' "$BATS_TEST_TMPDIR" > "$LR_MOVE_BATCH_BIN"; chmod +x "$LR_MOVE_BATCH_BIN"
  frag="$BATS_TEST_TMPDIR/kick.sh"
  {
    echo 'STATE="$LR_STATE_DIR"; LR="$1"; DRY="${DRYRUN:-0}"; LOG="$STATE/poller.log"'
    printf '%s\n' 'log() { printf "%s\n" "$*" >> "$LOG"; }'
    sed -n '/^lrp_move_kick() {/,/^}/p' "$LRD/lr-reset-poller.sh"
    echo 'lrp_move_kick'
  } > "$frag"
  mkdir -p "$LR_STATE_DIR/move/requests"
  echo '{"kind":"move-batch","batch":"c1"}' > "$LR_STATE_DIR/move/requests/c1.json"
  DRYRUN=1 bash "$frag" "$LRD"
  [ -f "$LR_STATE_DIR/move/requests/c1.json" ]
  [ ! -e "$BATS_TEST_TMPDIR/batch-rec.log" ]
  LR_MOVE_LANE=off bash "$frag" "$LRD"
  [ -f "$LR_STATE_DIR/move/requests/c1.json" ]
  bash "$frag" "$LRD"
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$BATS_TEST_TMPDIR/batch-rec.log" ] && break; sleep 0.3; done
  [ "$(cat "$BATS_TEST_TMPDIR/batch-rec.log")" = c1 ]
  [ ! -e "$LR_STATE_DIR/move/requests/c1.json" ]
  [ -f "$BDIR/request.claimed.json" ]
  echo '{"kind":"move-batch","batch":"c1"}' > "$LR_STATE_DIR/move/requests/c1.json"
  bash "$frag" "$LRD"
  sleep 0.5
  [ "$(grep -c . "$BATS_TEST_TMPDIR/batch-rec.log")" -eq 1 ]
  grep -q 'MOVE-SKIP c1 was already claimed' "$LR_STATE_DIR/poller.log"
}

# ── REPLAY OF A REAL RUN: batch 20261006T060534Z-next3-next2-64630 (7 idle sessions, next3 → next2).
# What the record holds at close: plan.json with 7 `move` rows and 2 held rows, one result per moved
# session (all MOVED), one <sid>.watcher.json per moved session, and request.claimed.json. Its
# batch.log reads `command substitution: line 84: syntax error near unexpected token 'newline'`,
# its summary.json `"verdicts":"none"`, and the one mail "done: no rows". The cause is the
# interpreter: launchd starts the runner with /bin/bash (3.2), which ends a `$( )` at the `)` of a
# bare `case` pattern, and every other case in this file runs it under PATH bash (5.x), so the
# defect was invisible here. The pane numbers and sid prefixes below are the record's own.
replay_20261006() { # → RB (batch id) and RD (its dir), holding the record's shape at close
  RB="20261006T060534Z-next3-next2-64630"; RD="$LR_STATE_DIR/move/$RB"; mkdir -p "$RD/intent"
  local ps p s rows="[]"
  for ps in 2:7f5deb68:move 3:1c0f7f90:move 4:893204d3:move 8:4e9949e0:hold 11:4ad354fc:hold \
            12:840ca76c:move 14:4d059264:move 15:deaa242a:move 16:404651b1:move; do
    p="${ps%%:*}"; s="${ps#*:}"; act="${s#*:}"; s="${s%%:*}-0000-4000-8000-000000000001"
    rows="$(jq -c --arg p "$p" --arg s "$s" --arg act "$act" --arg cfg "$HOME/.claude-tertiary" \
      '. + [{pane:$p, sid:$s, account:"next3", config_dir:$cfg, cwd:"/x", disposition:(if $act == "move" then "move" else "hold:mid-turn" end), act:$act}]' <<<"$rows")"
    [ "$act" = move ] || continue
    jq -nc --arg s "$s" --arg p "$p" '{sid:$s, pane:$p, verdict:"MOVED", reason:("pane " + $p + " runs the session on the target, one copy"), conjuncts:"1111111", from:"next3", to:"next2", wall_s:176}' > "$RD/$s.json"
    jq -nc --arg p "$p" '{pid:17125, lstart:"Tue Oct  6 06:08:40 2026", pane:$p, armed_at:"2026-10-06T06:08:41Z"}' > "$RD/$s.watcher.json"
  done
  jq -nc --arg b "$RB" --arg tcfg "$HOME/.claude-secondary" --argjson rows "$rows" \
    '{batch:$b, from:"next3", to:"next2", to_config_dir:$tcfg, until_idle_s:0, requested_by:"999", target_unverified:false, ts:1791266734, rows:$rows}' > "$RD/plan.json"
  jq -nc --arg b "$RB" '{kind:"move-batch", batch:$b, ts:1791266734}' > "$RD/request.claimed.json"
}

@test "14 [RED] replay 20261006T060534Z under /bin/bash: the roll-up counts the 7 MOVED rows, and the mail says so" {
  [ -x /bin/bash ] || skip "/bin/bash absent"
  replay_20261006
  # /bin/bash explicitly, as lr-reset-poller.sh's lrp_move_kick starts it. Every driven row already
  # has its result, so nothing is claimed or actuated: this run is the admit, the close and the roll-up.
  run /bin/bash "$LRD/lr-move-batch.sh" "$RB"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"syntax error"* ]] || { echo "$output"; false; }
  # RED before the fix (and in the record): "none".
  [ "$(jq -r .verdicts "$RD/summary.json")" = "MOVED=7" ] || { cat "$RD/summary.json"; echo "$output"; false; }
  grep -q "^999 cc-lr move $RB (next3 -> next2) done: MOVED=7" "$NOTIFY_LOG" || { cat "$NOTIFY_LOG"; false; }
  [ ! -s "$STUB_LOG/typers.log" ]
}

# ── THE LOST KICK (2026-10-06). `cc-lr move` kickstarts the poller, and launchd does not start a
# second instance of a running job, so a request written while a tick runs was seen only by the
# NEXT tick: 89 s for the recorded batch (request 06:05:34Z, a tick in flight since 06:05:16Z,
# started 06:07:03Z), 629-820 s for 7 of 30 switch and upgrade requests. The tick now looks again
# as its last act.
@test "16 [RED] a move request that lands DURING a tick is started when that tick ends, and the tick lock is still released" {
  export LR_MOVE_BATCH_BIN="$STUBS/batch-rec"
  printf '#!/bin/bash\necho "$*" >> "%s/batch-rec.log"\n' "$BATS_TEST_TMPDIR" > "$LR_MOVE_BATCH_BIN"; chmod +x "$LR_MOVE_BATCH_BIN"
  frag="$BATS_TEST_TMPDIR/tick.sh"
  {
    echo 'STATE="$LR_STATE_DIR"; LR="$1"; DRY=0; LOG="$STATE/poller.log"; LOCKD="$2"; mkdir -p "$LOCKD"'
    printf '%s\n' 'log() { printf "%s\n" "$*" >> "$LOG"; }'
    sed -n '/^lrp_tick_end() {/,/^}/p' "$LRD/lr-reset-poller.sh"
    grep -E "^trap '[^']*' EXIT$" "$LRD/lr-reset-poller.sh"
    sed -n '/^lrp_move_kick() {/,/^}/p' "$LRD/lr-reset-poller.sh"
    echo 'lrp_move_kick'                                             # the top of the tick: nothing queued yet
    echo 'echo "{\"kind\":\"move-batch\",\"batch\":\"c1\"}" > "$STATE/move/requests/c1.json"'   # the request arrives mid-tick
    echo 'exit 0'
  } > "$frag"
  mkdir -p "$LR_STATE_DIR/move/requests"
  bash "$frag" "$LRD" "$BATS_TEST_TMPDIR/tick.lock"
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$BATS_TEST_TMPDIR/batch-rec.log" ] && break; sleep 0.3; done
  # RED before the fix: the request is still queued and the runner never started.
  [ "$(cat "$BATS_TEST_TMPDIR/batch-rec.log" 2>/dev/null)" = c1 ] || { cat "$frag"; cat "$LR_STATE_DIR/poller.log" 2>/dev/null; false; }
  [ ! -e "$LR_STATE_DIR/move/requests/c1.json" ]
  [ -f "$BDIR/request.claimed.json" ]
  [ ! -d "$BATS_TEST_TMPDIR/tick.lock" ]
}

@test "17 a whole dry-run tick looks at the move requests twice (top and end), starts nothing, and exits 0" {
  export LR_POLLER_NO_CENSUS=1 LR_UPGRADE_AUTO=off LR_POLLER_LOCK_DIR="$BATS_TEST_TMPDIR/poller.lock"
  unset KITTY_WINDOW_ID; export IT2_WRAPPER_NO_KITTY=1
  export LR_MOVE_BATCH_BIN="$STUBS/batch-rec"
  printf '#!/bin/bash\necho "$*" >> "%s/batch-rec.log"\n' "$BATS_TEST_TMPDIR" > "$LR_MOVE_BATCH_BIN"; chmod +x "$LR_MOVE_BATCH_BIN"
  mkdir -p "$LR_STATE_DIR/move/requests"
  echo '{"kind":"move-batch","batch":"c1"}' > "$LR_STATE_DIR/move/requests/c1.json"
  run bash "$LRD/lr-reset-poller.sh" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c 'DRY   move batch c1 would start' "$LR_STATE_DIR/poller.log")" -eq 2 ] || { cat "$LR_STATE_DIR/poller.log"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/batch-rec.log" ]
  [ -f "$LR_STATE_DIR/move/requests/c1.json" ]
  [ ! -d "$LR_POLLER_LOCK_DIR" ]
}

@test "15 the same replay under PATH bash agrees with /bin/bash (the roll-up is interpreter-independent)" {
  replay_20261006
  run bash "$LRD/lr-move-batch.sh" "$RB"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .verdicts "$RD/summary.json")" = "MOVED=7" ]
}
