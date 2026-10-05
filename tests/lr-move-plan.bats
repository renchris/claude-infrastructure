#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# bin/cc-lr plan · move — the operator's two verbs of the move lane (design-swap-v3 §4.1, 2026-10-04).
#
# THE INCIDENT BEHIND THEM: `cc-lr switch --from A --all-idle --target B` queued one request per
# idle subject for a serial drainer that asked each subject to move itself. A 12-request batch ran
# 36 m 51 s and moved 0 sessions; the table it printed listed only what it would act on.
#
# WHAT IS PINNED:
#   · `plan` shows EVERY session on the source account with exactly one disposition, and writes and
#     types nothing; `move --dry-run` prints the same rows and writes nothing;
#   · a real `move` writes plan.json, ONE intent per movable session (mode 0600, valid under
#     lr-intent.sh for exactly that session, pane, source and target) and one batch request, then
#     kicks the poller without -k. It never types: it has no kitty, no cc-tui, no lr-handoff call;
#   · a limit-blocked session, a stale-marker session and a busy session are never `move`;
#   · the router is strict: an excluded or unverifiable target refuses before anything is written;
#   · the driver form of `switch` now delegates here; CC_LR_SWITCH_LEGACY=on keeps the old drive.
# [RED] cases fail on the tree before these verbs existed (cc-lr: unknown subcommand).
#
# Hermetic: the registry, every store and `ps` are fixtures (lr-upgrade's own seams); launchctl and
# claude-accounts are recorders. Nothing can reach a live pane.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  CCLR="$REPO/bin/cc-lr"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LRU_STATE="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE"
  export LR_STATE_DIR="$LRU_STATE"
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$LRU_REG_DIR"
  export LRU_CFG_ROOT="$HOME"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_COMPOSER=off LRU_SELF_SID=""
  export LRU_LR_LIB="$BATS_TEST_TMPDIR/absent-lr-lib.sh"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export LRU_NOTIFY_BIN="$STUBS/cc-notify"
  printf '#!/bin/bash\nexit 0\n' > "$LRU_NOTIFY_BIN"; chmod +x "$LRU_NOTIFY_BIN"
  export LRU_SA_PROBE="$STUBS/sa-probe"
  printf '#!/bin/bash\necho "live_subagents: 0"\n' > "$LRU_SA_PROBE"; chmod +x "$LRU_SA_PROBE"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/launchctl.log" > "$STUBS/launchctl"; chmod +x "$STUBS/launchctl"
  export CC_ACCOUNTS_BIN="$STUBS/claude-accounts"
  cat > "$CC_ACCOUNTS_BIN" <<'STUB'
#!/bin/bash
case "${RANK_MODE:-ok}" in
  ok) printf 'next2 0.9\nnext3 0.4\n' ;;
  excluded) echo "ranked 1 of 2; excluded — next2=logged-out" >&2; echo "next3 0.4" ;;
  down) exit 3 ;;
esac
STUB
  chmod +x "$CC_ACCOUNTS_BIN"
  export PATH="$STUBS:$PATH"
  export CC_LR_UPGRADE_BIN="$LRU" CC_PANE_ID=999 CC_LR_MOVE_POLL_S=0
  unset CLAUDE_CODE_SESSION_ID ITERM_SESSION_ID KITTY_WINDOW_ID
  BIN="/opt/cc/.claude-280/node_modules/.bin/claude"; LST="Tue Sep 22 06:47:13 2026"; N=0
  S1=aaaa0001-0000-4000-8000-000000000001; S2=aaaa0002-0000-4000-8000-000000000002
  S3=aaaa0003-0000-4000-8000-000000000003; S4=aaaa0004-0000-4000-8000-000000000004
  S5=aaaa0005-0000-4000-8000-000000000005; S6=aaaa0006-0000-4000-8000-000000000006
}

# sess <pane> <sid> [rest|busy|limit] [account dir basename, default claude-tertiary = next3] [argv]
sess() {
  local pane="$1" sid="$2" shape="${3:-rest}" acct="${4:-claude-tertiary}" argv="${5:-$BIN --model claude-opus-5-5 --effort high}" pid tx
  N=$((N + 1)); pid=$((50000 + N))
  printf '{"paneUUID":"%s","pid":%d,"session_id":"%s","account":"%s","cwd":"%s","lstart":"%s"}\n' \
    "$pane" "$pid" "$sid" "$acct" "$BATS_TEST_TMPDIR" "$LST" > "$LRU_REG_DIR/$pane.json"
  printf '%d 1 %s %s\n' "$pid" "$LST" "$argv" >> "$LRU_PS_SNAPSHOT"
  tx="$HOME/.$acct/projects/-x/$sid.jsonl"; mkdir -p "$(dirname "$tx")"
  case "$shape" in
    rest) printf '%s\n' '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"idle"}]}}' > "$tx" ;;
    busy) printf '%s\n' '{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use"}]}}' > "$tx" ;;
    limit) printf '%s\n' '{"type":"assistant","timestamp":"2026-09-23T10:00:00.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit"}]}}' > "$tx" ;;
  esac
}
fleet() { # six sessions on next3, one of every kind the plan must name, plus one already on next2
  sess 401 "$S1"
  sess 402 "$S2" busy
  sess 403 "$S3" rest claude-tertiary "$BIN --agent-id w@session-x --agent-name w --model claude-opus-5-5"
  sess 404 "$S4" limit
  sess 405 "$S5"
  printf '{"handed_off_to":"%s","ts":"2026-10-03T02:28:00Z"}\n' "$HOME/.claude-quaternary" > "$HOME/.claude-tertiary/projects/-x/$S5.HANDOFF.json"
  sess 406 "$S6" rest claude-secondary
}
disp() { printf '%s\n' "$output" | awk -v s="${1:0:8}" '$2 == s { print $3 }'; }
moved_dir() { ls -d "$LR_STATE_DIR"/move/*/ 2>/dev/null | grep -v '/requests/$' | head -1; }

@test "1 [RED] plan: every session on the source account gets one row and one disposition" {
  fleet
  run bash "$CCLR" plan --from next3 --to next2
  [ "$status" -eq 0 ]
  [ "$(disp "$S1")" = move ]
  [ "$(disp "$S2")" = hold:mid-turn ]
  [ "$(disp "$S3")" = hold:teammate ]
  [ "$(disp "$S4")" = hold:limited ]
  [ "$(disp "$S5")" = hold:retired-source ]
  [ -z "$(disp "$S6")" ]
  [[ "$output" == *"1 to move · 0 waiting · 4 held · 0 on target"* ]] || false
  [[ "$output" == *"cc-lr recover --limited --account next3 --target next2"* ]] || false
  [[ "$output" == *"cc-lr repair-markers --sid $S5"* ]]
}

@test "2 [RED] plan is read-only: no move directory, no request, no kick" {
  fleet
  run bash "$CCLR" plan --from next3 --to next2
  [ ! -e "$LR_STATE_DIR/move" ]
  [ ! -e "$BATS_TEST_TMPDIR/launchctl.log" ]
}

@test "3 plan --until-idle turns a busy row into wait; --json carries the same rows" {
  fleet
  run bash "$CCLR" plan --from next3 --to next2 --until-idle 600
  [ "$(disp "$S2")" = wait:mid-turn ]
  run bash "$CCLR" plan --from next3 --to next2 --json
  [ "$(printf '%s' "$output" | jq -r '.rows | length')" -eq 5 ]
  [ "$(printf '%s' "$output" | jq -r --arg s "$S1" '.rows[] | select(.sid == $s) | .act')" = move ]
}

@test "4 [RED] move --dry-run prints one row per session and writes nothing" {
  fleet
  run bash "$CCLR" move --from next3 --to next2 --dry-run
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cE '^40[1-5] ')" -eq 5 ]
  [[ "$output" == *"DRY RUN: nothing was written or typed"* ]] || false
  [ ! -e "$LR_STATE_DIR/move" ]
  [ ! -e "$BATS_TEST_TMPDIR/launchctl.log" ]
}

@test "5 [RED] move writes the plan, ONE valid 0600 intent for the movable session, one request, and kicks without -k" {
  fleet
  run bash "$CCLR" move --from next3 --to next2 --wait 0
  [ "$status" -eq 1 ]
  d="$(moved_dir)"
  [ -s "$d/plan.json" ]
  [ "$(ls "$d/intent" | grep -c .)" -eq 1 ]
  [ "$(stat -f %Lp "$d/intent/$S1.json" 2>/dev/null || stat -c %a "$d/intent/$S1.json")" = 600 ]
  run bash -c '. "$1"; lr_intent_check "$2" "$3" 401 next3 next2; echo "rc=$? $LR_INTENT_WHY"' _ "$REPO/scripts/limit-recover/lr-intent.sh" "$d/intent/$S1.json" "$S1"
  [ "$output" = "rc=0 " ]
  [ "$(ls "$LR_STATE_DIR/move/requests" | grep -c .)" -eq 1 ]
  [ "$(jq -r .to_config_dir "$d/plan.json")" = "$HOME/.claude-secondary" ]
  grep -q '^kickstart gui/' "$BATS_TEST_TMPDIR/launchctl.log"
  ! grep -q -- '-k' "$BATS_TEST_TMPDIR/launchctl.log"
}

@test "6 move never types: the verbs hold no pane-typing call" {
  a="$(grep -n '^cl_move_lib() {' "$CCLR" | cut -d: -f1)"; b="$(grep -n '^cmd_switch() {' "$CCLR" | cut -d: -f1)"
  [ -n "$a" ]
  [ "$b" -gt "$a" ]
  ! sed -n "${a},${b}p" "$CCLR" | grep -q 'cc_tui_\|kitty @\|lr-handoff\|handoff-fire'
}

@test "7 [RED] a target the router excludes refuses the move before anything is written, and names the cure" {
  fleet
  RANK_MODE=excluded run bash "$CCLR" move --from next3 --to next2 --wait 0
  [ "$status" -eq 2 ]
  [[ "$output" == *"REFUSED — the router does not rank 'next2' (logged-out)"* ]] || false
  [ ! -e "$LR_STATE_DIR/move" ]
}

@test "8 [RED] a router that cannot answer refuses (fail closed) unless --target-unverified is passed" {
  fleet
  RANK_MODE=down run bash "$CCLR" move --from next3 --to next2 --wait 0
  [ "$status" -eq 2 ]
  [[ "$output" == *"target-unverified"* ]] || false
  [ ! -e "$LR_STATE_DIR/move" ]
  RANK_MODE=down run bash "$CCLR" move --from next3 --to next2 --wait 0 --target-unverified
  [ "$status" -eq 1 ]
  [ "$(jq -r .target_unverified "$(moved_dir)/plan.json")" = true ]
}

@test "9 KILL SWITCH: LR_MOVE_LANE=off refuses a real move and writes nothing; the dry run still reads" {
  fleet
  LR_MOVE_LANE=off run bash "$CCLR" move --from next3 --to next2 --wait 0
  [ "$status" -eq 2 ]
  [ ! -e "$LR_STATE_DIR/move" ]
  LR_MOVE_LANE=off run bash "$CCLR" move --from next3 --to next2 --dry-run
  [ "$status" -eq 0 ]
  [ "$(disp "$S1")" = move ]
}

@test "10 --cold-only holds a session whose cache is still warm, and moves one idle for over an hour" {
  fleet
  run bash "$CCLR" plan --from next3 --to next2 --cold-only
  [ "$(disp "$S1")" = hold:warm-cache ]
  touch -t 202601010000 "$HOME/.claude-tertiary/projects/-x/$S1.jsonl"
  run bash "$CCLR" plan --from next3 --to next2 --cold-only
  [ "$(disp "$S1")" = move ]
}

@test "11 a session another actuator has claimed is hold:in-flight" {
  fleet
  mkdir -p "$LR_STATE_DIR/runs/by-sid/$S1.active"
  printf '{"sid":"%s","pane":"401","pid":%d,"ts":"t","by":"other"}\n' "$S1" "$$" > "$LR_STATE_DIR/runs/by-sid/$S1.active/holder"
  run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S1")" = hold:in-flight ]
}

@test "12 one session by --sid: its row alone, the source account read off the row" {
  fleet
  run bash "$CCLR" move --sid "$S1" --to next2 --dry-run
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cE '^40[0-9] ')" -eq 1 ]
  [[ "$output" == *"from next3 → next2"* ]]
}

@test "13 usage: no target, the same account twice, or an unknown account is rc 3 and writes nothing" {
  fleet
  run bash "$CCLR" move --from next3
  [ "$status" -eq 3 ]
  run bash "$CCLR" move --from next3 --to next3
  [ "$status" -eq 3 ]
  run bash "$CCLR" move --from next3 --to nowhere9
  [ "$status" -eq 3 ]
  [ ! -e "$LR_STATE_DIR/move" ]
}

@test "14 [RED] the driver form of switch now runs the move lane; CC_LR_SWITCH_LEGACY=on keeps the old table" {
  fleet
  run bash "$CCLR" switch --from next3 --all-idle --target next2 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"the driver form now runs the move lane"* ]] || false
  [[ "$output" == *"DISPOSITION"*"IDLE"*"CACHE"* ]] || false
  [ "$(disp "$S4")" = hold:limited ]
  CC_LR_SWITCH_LEGACY=on run bash "$CCLR" switch --from next3 --all-idle --target next2 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACCOUNT → TARGET"* ]] || false
  [[ "$output" != *"the driver form now runs the move lane"* ]]
}

@test "15 move --abort marks the batch; move --status on an unknown batch is refused" {
  fleet
  run bash "$CCLR" move --from next3 --to next2 --wait 0
  d="$(moved_dir)"; b="$(basename "$d")"
  run bash "$CCLR" move --abort "$b"
  [ "$status" -eq 0 ]
  [ -e "$d/abort" ]
  run bash "$CCLR" move --status no-such-batch
  [ "$status" -eq 2 ]
}
