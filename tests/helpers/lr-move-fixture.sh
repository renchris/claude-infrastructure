# shellcheck shell=bash
# tests/helpers/lr-move-fixture.sh — the fixture world shared by the move-lane suites
# (lr-move-verdict, lr-move-worker, lr-move-concurrency). Sourced from a suite's setup().
#
# A "session" here is: one long-lived process (a `sleep`, standing in for the pane's claude), one
# registry row naming it, one transcript under a config dir, and one env file saying which config
# dir that process was started with (lr-move-lib.sh's LR_MOVE_ENV_DIR seam for `ps -E`). A "move" is
# what a completed in-place recycle leaves on disk: the transcript under the target, the row naming
# the target, the env file naming the target. Nothing here can reach a live session: HOME, the
# registry, the state dir and the debt ledger are all under $BATS_TEST_TMPDIR.

mvf_setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRD="$REPO/scripts/limit-recover"
  export LR_STATE_DIR="$HOME/.reso/limit-recover"; mkdir -p "$LR_STATE_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/penv"; mkdir -p "$LR_MOVE_ENV_DIR"
  export CC_RESUME_DEBT_DIR="$BATS_TEST_TMPDIR/debt"; mkdir -p "$CC_RESUME_DEBT_DIR/meta"
  SRC="$HOME/.claude-quaternary"; DST="$HOME/.claude-tertiary"   # next4 → next3
  mkdir -p "$SRC/projects/-x" "$DST/projects/-x"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  MVF_PIDS=""
  # Fast clocks: every wait in the lane is a poll with an env-set period. The PROOF bound stays
  # generous: on a loaded box one verdict read (a dozen jq forks) can take seconds, and a bound sized
  # on an idle bench reads a slow success as FAILED (memory: bound-must-fit-the-band-not-the-bench).
  export LR_MOVE_PROVE_POLL_S=0.2 LR_MOVE_STABLE_S=1 LR_MOVE_SLOT_POLL_S=0.2 LR_MOVE_WAIT_POLL_S=0.2
  export LR_MOVE_HELD_PROVE_S=2 LR_MOVE_PROVE_S=90 LR_MOVE_WATCH_POLL_S=0.3 LR_MOVE_SNAP_S=1
  export LR_MOVE_KERNEL_CHECK=off LR_MOVE_PRESEED=off
}
mvf_teardown() {
  local p
  for p in $MVF_PIDS; do kill "$p" 2>/dev/null || true; done
  return 0
}
mvf_acct() { local b="${1##*/}"; printf '%s' "${b#.}"; }
# mvf_session <pane> <sid> [config dir] → a live session on that store; its pid is MVF_PID
mvf_session() {
  local cfg="${3:-$SRC}"
  # fd 3 closed: bats waits on every process that still holds it.
  sleep 900 3>&- &
  MVF_PID=$!; MVF_PIDS="$MVF_PIDS $MVF_PID"
  printf '{"paneUUID":"%s","pid":%d,"session_id":"%s","account":"%s","cwd":"%s"}\n' \
    "$1" "$MVF_PID" "$2" "$(mvf_acct "$cfg")" "$BATS_TEST_TMPDIR" > "$CC_REGISTRY_DIR/$1.json"
  printf '%s\n' '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"idle"}]}}' \
    > "$cfg/projects/-x/$2.jsonl"
  printf '%s' "$cfg" > "$LR_MOVE_ENV_DIR/$MVF_PID"
}
# mvf_flip <pane> <sid> <from cfg> <to cfg> — the on-disk result of a completed move (same process)
mvf_flip() {
  local pid
  pid="$(jq -r .pid "$CC_REGISTRY_DIR/$1.json")"
  mv "$3/projects/-x/$2.jsonl" "$4/projects/-x/$2.jsonl"
  jq -c --arg a "$(mvf_acct "$4")" '.account = $a' "$CC_REGISTRY_DIR/$1.json" > "$CC_REGISTRY_DIR/$1.json.t"
  mv "$CC_REGISTRY_DIR/$1.json.t" "$CC_REGISTRY_DIR/$1.json"
  printf '%s' "$4" > "$LR_MOVE_ENV_DIR/$pid"
}
# mvf_plan <batch> <act> <pane:sid>… — plan.json plus one valid intent per row, as `cc-lr move` writes them
mvf_plan() {
  local batch="$1" act="$2" bdir rows="[]" ps p s
  shift 2
  bdir="$LR_STATE_DIR/move/$batch"; ( umask 077; mkdir -p "$bdir/intent" )
  for ps in "$@"; do
    p="${ps%%:*}"; s="${ps#*:}"
    rows="$(jq -c --arg p "$p" --arg s "$s" --arg cfg "$SRC" --arg cwd "$BATS_TEST_TMPDIR" --arg act "$act" \
      '. + [{pane:$p, sid:$s, account:"next4", config_dir:$cfg, cwd:$cwd, disposition:(if $act == "wait" then "wait:mid-turn" else "move" end), act:$act}]' <<<"$rows")"
    ( umask 077
      jq -nc --arg b "$batch" --arg sid "$s" --arg pane "$p" --argjson exp "$(( $(date +%s) + 900 ))" \
        '{kind:"cc-lr-move", batch:$b, sid:$sid, pane:$pane, from:"next4", to:"next3", requested_by:"999", ts:0, expires_epoch:$exp, plan_row_sha:"x"}' \
        > "$bdir/intent/$s.json" )
  done
  jq -nc --arg b "$batch" --arg tcfg "$DST" --argjson rows "$rows" --argjson until "${MVF_UNTIL:-0}" --argjson slots "${MVF_SLOTS:-4}" \
    '{batch:$b, from:"next4", to:"next3", to_config_dir:$tcfg, until_idle_s:$until, slots:$slots, requested_by:"999", target_unverified:false, ts:0, rows:$rows}' \
    > "$bdir/plan.json"
  BDIR="$bdir"
}
# The lr-handoff stand-in. STUB_MODE: move (default) · hold · strand · tomb (moves, but leaves a
# foreign tombstone in the target). It records its argv, its environment, the number of swap slots
# held while it runs, and one "typer" line per invocation.
mvf_handoff_stub() {
  export LR_MOVE_HANDOFF_BIN="$STUBS/lr-handoff"
  export STUB_LOG="$BATS_TEST_TMPDIR/handoff"; mkdir -p "$STUB_LOG"
  export STUB_SRC="$SRC" STUB_DST="$DST"
  cat > "$LR_MOVE_HANDOFF_BIN" <<'STUB'
#!/bin/bash
sid="" pane=""
args="$*"
while [ $# -gt 0 ]; do
  case "$1" in --sid) sid="$2"; shift 2 ;; --source-pane) pane="$2"; shift 2 ;; *) shift ;; esac
done
printf '%s\n' "$args" >> "$STUB_LOG/argv.log"
printf '%s admit=%s placed=%s bgwork=%s rec=%s\n' "$sid" "${LR_ADMIT_MODE:-}" "${LR_PLACED_BY:-}" "${CC_RECYCLE_BGWORK_ANSWER:-}" "${LR_RECORD_ID:-}" >> "$STUB_LOG/env.log"
printf '%s %s\n' "$sid" "$$" >> "$STUB_LOG/typers.log"
n=0; for d in "$LR_STATE_DIR"/locks/swap-slots/slot-*; do [ -s "$d/pid" ] && kill -0 "$(cat "$d/pid")" 2>/dev/null && n=$((n + 1)); done
printf '%s\n' "$n" >> "$STUB_LOG/slots.log"
case "${STUB_MODE:-move}" in
  hold) echo "lr-handoff: verdict: HELD:busy — held before the confirm"; exit 6 ;;
  strand)
    kill "$(jq -r .pid "$CC_REGISTRY_DIR/$pane.json")" 2>/dev/null
    sleep 0.3; exit 4 ;;
esac
sleep "${STUB_BOOT_S:-0.3}"
pid="$(jq -r .pid "$CC_REGISTRY_DIR/$pane.json")"
mv "$STUB_SRC/projects/-x/$sid.jsonl" "$STUB_DST/projects/-x/$sid.jsonl"
b="${STUB_DST##*/}"
jq -c --arg a "${b#.}" '.account = $a' "$CC_REGISTRY_DIR/$pane.json" > "$CC_REGISTRY_DIR/$pane.json.t" && mv "$CC_REGISTRY_DIR/$pane.json.t" "$CC_REGISTRY_DIR/$pane.json"
printf '%s' "$STUB_DST" > "$LR_MOVE_ENV_DIR/$pid"
if [ "${STUB_MODE:-move}" = tomb ]; then
  printf '{"handed_off_to":"%s","ts":"2026-10-03T02:28:00Z"}\n' "$STUB_SRC" > "$STUB_DST/projects/-x/$sid.HANDOFF.json"
fi
exit 0
STUB
  chmod +x "$LR_MOVE_HANDOFF_BIN"
}
