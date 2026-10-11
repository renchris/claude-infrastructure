#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent; stub bodies expand in the stub
# scripts/limit-recover/lr-move-batch.sh — the operator's abort, and what the summary keeps
# (lr-reliability REPORT D9 / rank 14, 2026-10-11).
#
# Batch 20261011T032613Z: `cc-lr move --abort` wrote the abort file at 03:40:58Z; the runner was
# admitted at 03:41:16Z, read the router, took 7 claims and started 7 workers, because only the
# workers read the file. Its summary and mail then said "done: NOTMOVED=7" — the words a failure
# earns — and dropped the one row whose reason said "Recover it: cc-lr recover e582464c".
#
# Every case runs the runner under /bin/bash, as the poller's lrp_move_kick starts it: bash 3.2
# ends a `$( )` at a bare case pattern's `)`, and summary() is exactly that kind of code.
# Hermetic: sessions are `sleep`s; lr-handoff, claude-accounts and cc-notify are recorders.

setup() {
  command -v jq >/dev/null || skip "jq required"
  [ -x /bin/bash ] || skip "/bin/bash absent"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_GATE=off CC_FIRE_CAPACITY_GATE=off
  # shellcheck source=/dev/null
  . "$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/helpers/lr-move-fixture.sh"
  mvf_setup
  mvf_handoff_stub
  export STUB_BOOT_S=0.3
  export CC_ACCOUNTS_BIN="$STUBS/claude-accounts" RANK_LOG="$BATS_TEST_TMPDIR/rank.log"; : > "$RANK_LOG"
  # ABORT_ON_RANK=1: the operator's abort lands while the router is being read (inside admission).
  cat > "$CC_ACCOUNTS_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$RANK_LOG"
[ -z "${ABORT_ON_RANK:-}" ] || : > "$BDIR_ABORT"
printf 'next3 0.9\nnext2 0.4\n'
STUB
  chmod +x "$CC_ACCOUNTS_BIN"
  export CC_NOTIFY_BIN="$STUBS/cc-notify" NOTIFY_LOG="$BATS_TEST_TMPDIR/notify.log"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$NOTIFY_LOG"\n' > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"
  : > "$NOTIFY_LOG"
  export LR_MOVE_GUARD_CHECK=off
  N=4; ROWS=()
  for i in $(seq 1 "$N"); do
    sid="$(printf 'dddd%04d-0000-4000-8000-000000000001' "$i")"
    mvf_session "$((600 + i))" "$sid"
    ROWS+=("$((600 + i)):$sid")
  done
  MVF_SLOTS=2 mvf_plan a1 move "${ROWS[@]}"
  export BDIR_ABORT="$BDIR/abort"
}
teardown() { mvf_teardown; }

batch() { run /bin/bash "$LRD/lr-move-batch.sh" a1; }
claims() { local n=0 d; for d in "$LR_STATE_DIR/runs/by-sid"/*; do [ -e "$d" ] && n=$((n + 1)); done; echo "$n"; }

@test "[RED] an abort written before the runner starts: no router read, no claim, no worker; summary and mail say aborted" {
  : > "$BDIR/abort"
  batch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"syntax error"* ]] || { echo "$output"; false; }
  [ ! -s "$RANK_LOG" ] || { cat "$RANK_LOG"; false; }
  [ "$(claims)" -eq 0 ]
  [ ! -s "$STUB_LOG/typers.log" ]
  [ ! -s "$BDIR/workers.tsv" ]
  [ "$(jq -r .status "$BDIR/summary.json")" = aborted ] || { cat "$BDIR/summary.json"; false; }
  [ "$(jq -r .verdicts "$BDIR/summary.json")" = "NOTMOVED=$N" ]
  [ "$(jq -r .reasons "$BDIR/summary.json")" = "NOTMOVED/aborted=$N" ] || { cat "$BDIR/summary.json"; false; }
  [ "$(jq -r .admitted "$BDIR/admit.json")" = false ]
  grep -q "^999 cc-lr move a1 (next4 -> next3) aborted: NOTMOVED=$N (NOTMOVED/aborted=$N);" "$NOTIFY_LOG" || { cat "$NOTIFY_LOG"; false; }
  [ "$(grep -c . "$NOTIFY_LOG")" -eq 1 ]
}

@test "[RED] an abort that lands during admission stops the batch before any claim is taken" {
  export ABORT_ON_RANK=1
  batch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c . "$RANK_LOG")" -eq 1 ] || { cat "$RANK_LOG"; false; }
  [ "$(claims)" -eq 0 ]
  [ ! -s "$STUB_LOG/typers.log" ]
  [ "$(jq -r .status "$BDIR/summary.json")" = aborted ]
  [[ "$(jq -r .reason "$BDIR/admit.json")" == "aborted by the operator during admission"* ]] || { cat "$BDIR/admit.json"; false; }
  [ ! -d "$LR_STATE_DIR/locks/move-admit.lock" ]
}

@test "[RED] a row's own instruction (became-limited → cc-lr recover <sid8>) reaches summary.json and the mail" {
  # The record's shape at close: every row already has its result, so this run is the roll-up only.
  local s p i=0 ps
  for ps in "${ROWS[@]}"; do
    p="${ps%%:*}"; s="${ps#*:}"; i=$((i + 1))
    if [ "$i" -eq 1 ]; then
      jq -nc --arg s "$s" --arg p "$p" '{sid:$s, pane:$p, verdict:"NOTMOVED", reason:("became-limited: its last record is now a limit error, so it owes a turn this lane does not type; nothing touched. Recover it: cc-lr recover " + $s[0:8])}' > "$BDIR/$s.json"
    else
      jq -nc --arg s "$s" --arg p "$p" '{sid:$s, pane:$p, verdict:"MOVED", reason:("pane " + $p + " runs the session on the target, one copy")}' > "$BDIR/$s.json"
    fi
  done
  batch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .status "$BDIR/summary.json")" = "done" ]
  # the verdict roll-up is unchanged; the classes and the instruction are new fields beside it
  [ "$(jq -r .verdicts "$BDIR/summary.json")" = "MOVED=3 NOTMOVED=1" ] || { cat "$BDIR/summary.json"; false; }
  [ "$(jq -r .reasons "$BDIR/summary.json")" = "NOTMOVED/became-limited=1" ] || { cat "$BDIR/summary.json"; false; }
  [ "$(jq -r .actions "$BDIR/summary.json")" = "dddd0001: cc-lr recover dddd0001" ] || { cat "$BDIR/summary.json"; false; }
  grep -q "^999 cc-lr move a1 (next4 -> next3) done: MOVED=3 NOTMOVED=1 (NOTMOVED/became-limited=1);.* Still to do: dddd0001: cc-lr recover dddd0001\. Details:" "$NOTIFY_LOG" \
    || { cat "$NOTIFY_LOG"; false; }
}

@test "CONTROL: an all-MOVED batch with no abort keeps its old summary and mail words" {
  batch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .status "$BDIR/summary.json")" = "done" ]
  [ "$(jq -r .verdicts "$BDIR/summary.json")" = "MOVED=$N" ] || { cat "$BDIR/summary.json"; for f in "$BDIR"/dddd*.json; do cat "$f"; done; false; }
  [ "$(jq -r .reasons "$BDIR/summary.json")" = "" ]
  [ "$(jq -r .actions "$BDIR/summary.json")" = "" ]
  grep -q "^999 cc-lr move a1 (next4 -> next3) done: MOVED=$N; target auth after the batch: ok\. *Details:" "$NOTIFY_LOG" || { cat "$NOTIFY_LOG"; false; }
}
