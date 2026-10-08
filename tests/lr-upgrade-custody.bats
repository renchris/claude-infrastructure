#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # stubs are written verbatim; each @test is its own subshell; per-test exports are the intent
# lr-upgrade × the resume-debt ledger (docs/plans/CLOSE_RESUME_CUSTODY.md §2 D2-D4).
# Subject: scripts/limit-recover/lr-upgrade.sh — THE MOVER of the 2026-09-28 incident. It /exit'd
# pane 405, the relaunch failed (the window was gone), it retyped blind into the dead pane, accepted
# an unrelated out-of-pane `--resume` process as proof, wrote `upgraded`, and mailed the literal
# address `poller-auto`. Each case pins one of those shut, with cc-resume-debt stubbed through
# CC_RESUME_DEBT_BIN (its surface/prove/settle rcs come from files; every call is logged).
#
# Hermetic: every store is a fixture, `ps` for the census is a snapshot FILE, handoff-fire, it2,
# cc-notify and cc-resume-debt are recorders; no real terminal, registry, backlog or mailbox is touched.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LRU_STATE="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE"
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$LRU_REG_DIR"
  export LRU_CFG_ROOT="$BATS_TEST_TMPDIR/cfgroot"; mkdir -p "$LRU_CFG_ROOT"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_COMPOSER=off
  export LRU_SELF_SID=""
  export LRU_LR_LIB="$BATS_TEST_TMPDIR/absent-lr-lib.sh"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  printf '#!/bin/bash\necho "$*" >> %s\n' "$BATS_TEST_TMPDIR/it2.log" > "$STUBS/it2"; chmod +x "$STUBS/it2"
  export LRU_IT2_BIN="$STUBS/it2" LRU_RETYPE_MAX=0 LRU_RETYPE_GAP_S=0 LRU_ENGAGE_S=0 LRU_GAP_S=0
  export LRU_PROVE_GAP_S=0 LRU_PROVE_HOLD_S=0
  # cc-notify: a recorder; a target named in $BATS_TEST_TMPDIR/notify-unknown exits 3 (target unknown).
  export LRU_NOTIFY_BIN="$STUBS/cc-notify"
  printf '#!/bin/bash
echo "$*" >> %s/notify.log
[ "$1" != --role ] && grep -qx -- "$1" %s/notify-unknown 2>/dev/null && exit 3
exit 0
' "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$LRU_NOTIFY_BIN"; chmod +x "$LRU_NOTIFY_BIN"
  # cc-resume-debt: rc of surface/prove/settle read from $BATS_TEST_TMPDIR/<verb>-rc (default 0).
  export CC_RESUME_DEBT_BIN="$STUBS/cc-resume-debt"
  printf '#!/bin/bash
echo "$*" >> %s/rd.log
case "$1" in surface|prove|settle) exit "$(cat "%s/$1-rc" 2>/dev/null || echo 0)" ;; esac
exit 0
' "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$CC_RESUME_DEBT_BIN"; chmod +x "$CC_RESUME_DEBT_BIN"
  NEW="/opt/cc/.claude-280/node_modules/.bin/claude"
  OLD="/opt/cc/.claude-260/node_modules/.bin/claude"
  printf '#!/bin/bash\necho %s\n' "$NEW" > "$STUBS/cc-claude-bin"; chmod +x "$STUBS/cc-claude-bin"
  export LRU_CLAUDE_BIN_CMD="$STUBS/cc-claude-bin"
  export LRU_SA_PROBE="$STUBS/sa-probe"
  printf '#!/bin/bash\necho "live_subagents: 0"\n' > "$LRU_SA_PROBE"; chmod +x "$LRU_SA_PROBE"
  export LRU_MODEL_CONFIG="$BATS_TEST_TMPDIR/model-config.yaml"
  cat > "$LRU_MODEL_CONFIG" <<'Y'
versions:
  frontier_latest: claude-fable-5-1
  opus_latest: claude-opus-5-5
  opus_prior: claude-opus-5
frontier_access:
  active: true
  model: claude-fable-5-1
Y
  export LRU_CA_LIB="$BATS_TEST_TMPDIR/ca.sh"
  cat > "$LRU_CA_LIB" <<'EOF'
cc_capacity_probe() { return 0; }
cc_capacity_admit_reason() { echo admitted; }
cc_capacity_token_mint() { echo tok; }
EOF
  export LRU_HF_BIN="$STUBS/hf"
  printf '#!/bin/bash\necho "hf $*" >> %s/hf.log\nexit 1\n' "$BATS_TEST_TMPDIR" > "$LRU_HF_BIN"; chmod +x "$LRU_HF_BIN"
  N=0
}

teardown() {
  if [ -n "${LIVE_PID:-}" ]; then kill "$LIVE_PID" 2>/dev/null || true; fi
  if [ -f "$BATS_TEST_TMPDIR/new.pid" ]; then kill "$(cat "$BATS_TEST_TMPDIR/new.pid")" 2>/dev/null || true; fi
}

LST="Tue Sep 22 06:47:13 2026"
sess() { # sess <pane> <sid> <argv>  — registry row + ps line + an at-rest transcript
  local pane="$1" sid="$2" argv="$3" pid
  N=$((N + 1)); pid="${SESS_PID:-$((50000 + N))}"
  printf '{"paneUUID":"%s","pid":%d,"session_id":"%s","account":"claude-t","cwd":"%s","lstart":"%s"}\n' \
    "$pane" "$pid" "$sid" "$BATS_TEST_TMPDIR" "$LST" > "$LRU_REG_DIR/$pane.json"
  printf '%d 1 %s %s\n' "$pid" "$LST" "$argv" >> "$LRU_PS_SNAPSHOT"
  local tx="$LRU_CFG_ROOT/.claude-t/projects/-x/$sid.jsonl"; mkdir -p "$(dirname "$tx")"
  printf '%s\n' '{"type":"user","message":{"content":"hi"}}' \
    '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}' > "$tx"
}
result() { printf '%s' "$LRU_STATE/results/upgrade-$1.json"; }

# A handoff-fire whose /exit landed and whose relaunch write failed: the old session dies, and the
# terminal destroys the window (the surface flips absent), exactly as pane 405 on 2026-09-28.
hf_exit_then_window_gone() {
  cat > "$LRU_HF_BIN" <<STUB
#!/bin/bash
echo "hf \$*" >> "$BATS_TEST_TMPDIR/hf.log"
kill $LIVE_PID
echo 1 > "$BATS_TEST_TMPDIR/surface-rc"
exit 1
STUB
  chmod +x "$LRU_HF_BIN"
}

@test "the mover refuses to /exit without a verified relaunch surface" {
  SID=31313131-0000-4000-8000-000000000001
  sess 601 "$SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  echo 1 > "$BATS_TEST_TMPDIR/surface-rc"
  run bash "$LRU" --drive "$SID" 601
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$(jq -r .verdict "$(result "$SID")")" = skipped ] || { cat "$(result "$SID")"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == "relaunch-surface-unverified: pane 601 is not enumerated"* ]] || { cat "$(result "$SID")"; false; }
  grep -qx 'surface --pane 601' "$BATS_TEST_TMPDIR/rd.log"
  [ ! -s "$BATS_TEST_TMPDIR/hf.log" ] || { echo "handoff-fire ran (it types /exit) without a surface"; cat "$BATS_TEST_TMPDIR/hf.log"; false; }
}

@test "an UNKNOWN relaunch surface is refused too: only a positive answer proceeds" {
  SID=31313131-0000-4000-8000-000000000002
  sess 602 "$SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  echo 3 > "$BATS_TEST_TMPDIR/surface-rc"
  run bash "$LRU" --drive "$SID" 602
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$(jq -r .verdict "$(result "$SID")")" = skipped ]
  [[ "$(jq -r .reason "$(result "$SID")")" == "relaunch-surface-unverified: relaunch surface unknown"* ]] || { cat "$(result "$SID")"; false; }
  [ ! -s "$BATS_TEST_TMPDIR/hf.log" ]
}

@test "a stranded relaunch is settled into a new window with the same session id" {
  SID=31313131-0000-4000-8000-000000000003
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 603 "$SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  hf_exit_then_window_gone
  echo 0 > "$BATS_TEST_TMPDIR/settle-rc"
  LRU_RETYPE_MAX=2 run bash "$LRU" --drive "$SID" 603
  [ "$status" -eq 0 ] || { echo "$output"; cat "$(result "$SID")"; false; }
  [ ! -s "$BATS_TEST_TMPDIR/it2.log" ] || { echo "retyped into a pane the terminal no longer enumerates"; cat "$BATS_TEST_TMPDIR/it2.log"; false; }
  grep -qx "settle --sid $SID" "$BATS_TEST_TMPDIR/rd.log" || { cat "$BATS_TEST_TMPDIR/rd.log"; false; }
  [ "$(jq -r .verdict "$(result "$SID")")" = upgraded ] || { cat "$(result "$SID")"; false; }
  # The in-pane relaunch is --relaunch-at-shell's alone now (2026-10-08); with no pane identity it is
  # never attempted, and the session goes to the ledger's new window.
  [[ "$(jq -r .reason "$(result "$SID")")" == "relaunched in a NEW window by cc-resume-debt (pane 603 "* ]] || { cat "$(result "$SID")"; false; }
}

@test "a second failure reports the escalated backlog row" {
  SID=31313131-0000-4000-8000-000000000004
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 604 "$SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  hf_exit_then_window_gone
  echo 1 > "$BATS_TEST_TMPDIR/settle-rc"
  run bash "$LRU" --drive "$SID" 604
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(jq -r .verdict "$(result "$SID")")" = failed ] || { cat "$(result "$SID")"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"escalated to cc-backlog needs"* ]] || { cat "$(result "$SID")"; false; }
}

@test "a process-only match without proof is NOT upgraded" {
  export LRU_LR_LIB="$REPO/scripts/limit-recover/lr-lib.sh"
  SID=31313131-0000-4000-8000-000000000005
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 605 "$SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  # The incident's shape: some --resume <sid> process on the target binary + model exists (argv
  # matches), but the registry never proves it LIVE — cc-resume-debt prove refuses.
  cat > "$LRU_HF_BIN" <<STUB
#!/bin/bash
kill $LIVE_PID
( exec -a "$NEW" perl -e 'sleep 300' -- --permission-mode auto --model claude-opus-5-5 --effort high --resume $SID ) &
echo \$! > "$BATS_TEST_TMPDIR/new.pid"
sleep 1; exit 0
STUB
  chmod +x "$LRU_HF_BIN"
  echo 1 > "$BATS_TEST_TMPDIR/prove-rc"
  echo 3 > "$BATS_TEST_TMPDIR/settle-rc"
  run bash "$LRU" --drive "$SID" 605
  [ "$(jq -r .verdict "$(result "$SID")")" != upgraded ] || { echo "an unproven argv match was reported upgraded"; cat "$(result "$SID")"; false; }
  [ "$(jq -r .verdict "$(result "$SID")")" = failed ]
  [[ "$(jq -r .reason "$(result "$SID")")" == *"resume-debt undecided"* ]] || { cat "$(result "$SID")"; false; }
  grep -q "^prove --sid $SID" "$BATS_TEST_TMPDIR/rd.log"
  grep -qx "settle --sid $SID" "$BATS_TEST_TMPDIR/rd.log"
}

@test "poller-auto results mail --role desk, never the literal requester name" {
  SID=31313131-0000-4000-8000-000000000006
  sess 606 "$SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  echo 1 > "$BATS_TEST_TMPDIR/surface-rc"
  run bash "$LRU" --drive "$SID" 606 --requested-by poller-auto
  grep -q '^--role desk CC-LR-UPGRADE pane 606' "$BATS_TEST_TMPDIR/notify.log" || { cat "$BATS_TEST_TMPDIR/notify.log"; false; }
  ! grep -q '^poller-auto ' "$BATS_TEST_TMPDIR/notify.log" || { echo "mailed the literal poller-auto"; false; }
}

@test "a requester cc-notify reports unknown (exit 3) falls back to the desk role" {
  SID=31313131-0000-4000-8000-000000000007
  sess 607 "$SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  echo 1 > "$BATS_TEST_TMPDIR/surface-rc"
  echo some-gone-pane > "$BATS_TEST_TMPDIR/notify-unknown"
  run bash "$LRU" --drive "$SID" 607 --requested-by some-gone-pane
  grep -q '^some-gone-pane CC-LR-UPGRADE' "$BATS_TEST_TMPDIR/notify.log"
  grep -q '^--role desk CC-LR-UPGRADE pane 607' "$BATS_TEST_TMPDIR/notify.log" || { cat "$BATS_TEST_TMPDIR/notify.log"; false; }
}
