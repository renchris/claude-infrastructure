#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# The move worker clears a leftover `/exit` and never carries it; a wait that never changes pages
# once (lr-wake 2026-10-18, Wave G).
#
# Pane 384 (98e6f890): a recycle's read-back missed, `/exit` sat unsent in the composer, and the
# move lane's draft-carry retyped it into the successor's box at 16:51:54Z. Pane 350: the census read
# its bg-work modal as `composer-unknown` and the worker waited out three 3600 s budgets, silently.
# WHAT IS PINNED:
#   · a `draft` row whose box is exactly /exit (composer-intent rail-exit, Wave C K8) is cleared at
#     once with read-back, with no staleness wait, and the actuator gets no carry opt-in;
#   · a `move` row whose box reads /exit by the actuator is cleared too;
#   · a real draft is still carried and never cleared by the worker (CONTROL);
#   · a wait whose disposition never changed for the whole budget pages once; a second worker on
#     the same hold does not page again; a wait that changed does not page (CONTROL).
# [RED] cases fail on the tree before the fix.
#
# Hermetic: the registry, stores, `ps`, cc-tui, the pager and lr-handoff are fixtures.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json" CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue" CC_COMPOSER_DISCARD_LOG="$BATS_TEST_TMPDIR/discard.log"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  TUI="$BATS_TEST_TMPDIR/tui.sh"
  cat > "$TUI" <<EOF
cc_tui_composer() { [ -f "$BATS_TEST_TMPDIR/composer-\$1" ] || return 1; tr -d '[:space:]' < "$BATS_TEST_TMPDIR/composer-\$1"; }
cc_tui_composer_text() { cat "$BATS_TEST_TMPDIR/composer-\$1" 2>/dev/null; }
cc_tui_clear() { echo "\$1" >> "$BATS_TEST_TMPDIR/cleared.log"; : > "$BATS_TEST_TMPDIR/composer-\$1"; }
EOF
  # shellcheck source=/dev/null
  . "$REPO/tests/helpers/lr-move-fixture.sh"
  mvf_setup
  mvf_handoff_stub
  mv "$LR_MOVE_HANDOFF_BIN" "$STUBS/lr-handoff.real"
  cat > "$LR_MOVE_HANDOFF_BIN" <<EOF
#!/bin/bash
printf 'carry=%s\n' "\${LRH_CARRY_DRAFT:-}" >> "\$STUB_LOG/carry.log"
exec "$STUBS/lr-handoff.real" "\$@"
EOF
  chmod +x "$LR_MOVE_HANDOFF_BIN"
  # input idle 0 s: a box is never stale by the operator's idle time, so only rail-exit can skip the wait
  export LR_MOVE_TUI_LIB="$TUI" LR_HID_IDLE_S=0 LR_MOVE_DRAFT_WAIT_S=4 LR_MOVE_DRAFT_POLL_S=1
  SID="dddd4444-0000-4000-8000-000000000001"; PANE=61
  mvf_session "$PANE" "$SID"
  CLAIMS="$LR_STATE_DIR/runs/by-sid"
}
teardown() { [ -z "${MVF_PIDS:-}" ] || mvf_teardown; }

plan_disp() { # $1=batch $2=disposition [$3=act] [$4=until_idle_s]
  mvf_plan "$1" "${3:-move}" "$PANE:$SID"
  BDIR="$LR_STATE_DIR/move/$1"
  jq -c --arg d "$2" --argjson u "${4:-0}" '.rows[0].disposition = $d | .until_idle_s = $u' "$BDIR/plan.json" > "$BDIR/plan.t" && mv "$BDIR/plan.t" "$BDIR/plan.json"
  printf '{"admitted":true,"target":"next3","target_auth":"ok"}\n' > "$BDIR/admit.json"
}
worker() { # $1=batch
  bash "$LRD/lr-move-worker.sh" "$1" "$SID" > "$BATS_TEST_TMPDIR/worker.out" 2>&1 3>&- &
  WPID=$!
  mkdir -p "$CLAIMS/$SID.active"
  bash -c '. "$1/lr-lib.sh"; lr_claim_stamp "$2" "$3" "$4" lr-move-worker "$5"' _ "$LRD" "$CLAIMS/$SID.active" "$SID" "$WPID" "$PANE"
  wait "$WPID" || true
}
res() { jq -r ".$1" "$BDIR/$SID.json"; }

@test "1 [RED] a draft row whose box is exactly /exit is cleared at once and never carried" {
  plan_disp w1 draft
  printf '/exit\n' > "$BATS_TEST_TMPDIR/composer-$PANE"
  worker w1
  [ "$(res verdict)" = MOVED ] || { cat "$BDIR/$SID.json" "$BATS_TEST_TMPDIR/worker.out"; false; }
  [ "$(cat "$BATS_TEST_TMPDIR/cleared.log")" = "$PANE" ] || { cat "$BATS_TEST_TMPDIR/cleared.log"; false; }
  [ "$(cat "$STUB_LOG/carry.log")" = "carry=" ] || { cat "$STUB_LOG/carry.log"; false; }
  grep -q '"stage":"rail-exit-cleared"' "$BDIR/$SID.events.jsonl"
  if grep -q '"stage":"draft-wait"' "$BDIR/$SID.events.jsonl"; then false; fi
}

@test "2 [RED] a move row whose box reads /exit by the actuator is cleared before it" {
  plan_disp w2 move
  printf '/exit\n' > "$BATS_TEST_TMPDIR/composer-$PANE"
  worker w2
  [ "$(res verdict)" = MOVED ] || { cat "$BDIR/$SID.json" "$BATS_TEST_TMPDIR/worker.out"; false; }
  [ "$(cat "$BATS_TEST_TMPDIR/cleared.log")" = "$PANE" ] || { cat "$BATS_TEST_TMPDIR/worker.out"; false; }
  [ "$(cat "$STUB_LOG/carry.log")" = "carry=" ]
}

@test "3 CONTROL a real draft is still carried, and the worker clears nothing" {
  plan_disp w3 draft
  printf 'please also check the reaper\n' > "$BATS_TEST_TMPDIR/composer-$PANE"
  LR_HID_IDLE_S=999 worker w3
  [ "$(res verdict)" = MOVED ] || { cat "$BDIR/$SID.json" "$BATS_TEST_TMPDIR/worker.out"; false; }
  [ "$(cat "$STUB_LOG/carry.log")" = "carry=1" ]
  [ ! -e "$BATS_TEST_TMPDIR/cleared.log" ]
}

# shellcheck disable=SC2153  # MVF_PID is set by mvf_session (tests/helpers/lr-move-fixture.sh)
snap_disp() { # $1=disposition → the batch's shared census row, as lr-move-batch writes it
  # tmp + mv, as lr-move-batch writes it: a reader never sees a half-written census
  printf '%s\t%s\tnext4\t%s\t%s\t%s\t%s\n' "$PANE" "$SID" "$SRC" "$BATS_TEST_TMPDIR" "$MVF_PID" "$1" > "$BDIR/snap.tsv.t"
  mv -f "$BDIR/snap.tsv.t" "$BDIR/snap.tsv"
  printf '%s\n' "$RANDOM$RANDOM" > "$BDIR/snap.ts.t" && mv -f "$BDIR/snap.ts.t" "$BDIR/snap.ts"
}

# The batch runner re-censuses every few seconds; a refresher plays it for as long as the worker
# runs, so the worker reads many snapshots however slowly it starts on a loaded box.
# $1 $2 = the dispositions it alternates (the same twice = one that never changes)
refresh_start() {
  : > "$BATS_TEST_TMPDIR/refresh.on"
  ( while [ -e "$BATS_TEST_TMPDIR/refresh.on" ]; do snap_disp "$1"; sleep 0.3; snap_disp "$2"; sleep 0.3; done ) 3>&- &
  RPID=$!
}
refresh_stop() { rm -f "$BATS_TEST_TMPDIR/refresh.on"; wait "$RPID" 2>/dev/null || true; }

@test "4 [RED] a wait that never changed for the whole budget pages once, and only once" {
  plan_disp w4 wait:composer-unknown wait 25
  snap_disp composer-unknown
  refresh_start composer-unknown composer-unknown
  worker w4
  refresh_stop
  [ "$(res verdict)" = NOTMOVED ] || { cat "$BDIR/$SID.json"; false; }
  [[ "$(res reason)" == still-busy:composer-unknown* ]] || { cat "$BDIR/$SID.json"; false; }
  [ "$(wc -l < "$BATS_TEST_TMPDIR/pages.log" | tr -d ' ')" = 1 ] || { cat "$BDIR/$SID.events.jsonl" "$BDIR/$SID.page.log" "$BATS_TEST_TMPDIR/worker.out"; false; }
  grep -q "pane $PANE ${SID:0:8}: 'composer-unknown' did not change" "$BATS_TEST_TMPDIR/pages.log"
  # the next batch meets the same hold: silent
  plan_disp w4b wait:composer-unknown wait 25
  snap_disp composer-unknown
  refresh_start composer-unknown composer-unknown
  worker w4b
  refresh_stop
  [ "$(wc -l < "$BATS_TEST_TMPDIR/pages.log" | tr -d ' ')" = 1 ]
}

@test "5 CONTROL a wait whose disposition keeps changing does not page" {
  plan_disp w5 wait:mid-turn wait 25
  snap_disp mid-turn
  refresh_start mid-turn subagents-in-flight
  worker w5
  refresh_stop
  [ "$(res verdict)" = NOTMOVED ] || { cat "$BDIR/$SID.json"; false; }
  [ ! -s "$BATS_TEST_TMPDIR/pages.log" ] || { cat "$BATS_TEST_TMPDIR/pages.log"; false; }
}
