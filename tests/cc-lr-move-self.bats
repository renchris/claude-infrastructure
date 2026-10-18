#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# bin/cc-lr move — a session moving ITSELF (R4, R5 in docs/plans/LIMIT_RECOVER_SELF_INPLACE.md
# § W0/W1).
#
# THE INCIDENT: `cc-lr move --sid <own sid>` planned the caller as terminal hold:self, `cc-lr rotate`
# sent it to `cc-lr switch`, and `switch` under a live reconciler refused and sent it back to
# `move`: a session had no lane to move itself. The lane that works already existed — the batch
# worker waits on a `wait:*` row until two censuses call it at rest, then moves it from outside.
#
# WHAT IS PINNED:
#   · a `self` row plans as wait:self (never plain `move`), the batch gets a non-zero budget, and
#     `move` returns at once instead of blocking the caller's own tool call on its own row;
#   · the holds still bind a self row: a live /goal is hold:goal-live, and the kill switch restores
#     hold:self;
#   · `rotate --list` shows the self row as a wait and names `cc-lr move --sid`.
#   · the self-wait budget scales with load per core (two censuses must fit in it), and
#     CC_LR_MOVE_SELF_WAIT_S stays the exact budget when set.
#
# Hermetic: the same seams as tests/lr-move-plan.bats (registry, stores, `ps` as fixtures);
# launchctl and claude-accounts are recorders. Nothing can reach a live pane.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  CCLR="$REPO/bin/cc-lr"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/penv"; mkdir -p "$LR_MOVE_ENV_DIR"
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
  printf '#!/bin/bash\nprintf "next2 0.9\\nnext3 0.4\\n"\n' > "$CC_ACCOUNTS_BIN"; chmod +x "$CC_ACCOUNTS_BIN"
  export PATH="$STUBS:$PATH"
  export CC_LR_UPGRADE_BIN="$LRU" CC_PANE_ID=999 CC_LR_MOVE_POLL_S=0
  export CC_LR_LOAD_PER_CORE=0   # the self-wait budget scales with load; pinned so this box's load never reaches it
  unset CLAUDE_CODE_SESSION_ID ITERM_SESSION_ID KITTY_WINDOW_ID CC_LR_MOVE_SELF_WAIT CC_LR_MOVE_SELF_WAIT_S CC_LR_MOVE_DEDUP
  BIN="/opt/cc/.claude-280/node_modules/.bin/claude"; LST="Tue Sep 22 06:47:13 2026"; N=0
  S1=aaaa0001-0000-4000-8000-000000000001
}

# sess <pane> <sid> — a session at rest on next3 (claude-tertiary)
sess() {
  local pane="$1" sid="$2" pid tx
  N=$((N + 1)); pid=$((50000 + N))
  printf '{"paneUUID":"%s","pid":%d,"session_id":"%s","account":"claude-tertiary","cwd":"%s","lstart":"%s"}\n' \
    "$pane" "$pid" "$sid" "$BATS_TEST_TMPDIR" "$LST" > "$LRU_REG_DIR/$pane.json"
  printf '%d 1 %s %s\n' "$pid" "$LST" "$BIN --model claude-opus-5-5 --effort high" >> "$LRU_PS_SNAPSHOT"
  tx="$HOME/.claude-tertiary/projects/-x/$sid.jsonl"; mkdir -p "$(dirname "$tx")"
  printf '%s\n' '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"idle"}]}}' > "$tx"
}
disp() { printf '%s\n' "$output" | awk -v s="${1:0:8}" '$2 == s { print $3 }'; }
moved_dir() { local d; for d in "$LR_STATE_DIR"/move/*/; do case "$d" in */requests/) continue ;; esac; [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }; done; }
nreq() { local f n=0; for f in "$LR_STATE_DIR"/move/requests/*.json; do [ -e "$f" ] && n=$((n + 1)); done; printf '%s' "$n"; }

@test "1 [RED] a self row plans wait:self, queues with a >= 900 s budget, and move returns at once" {
  sess 401 "$S1"
  export LRU_SELF_SID="$S1"
  run bash "$CCLR" plan --sid "$S1" --to next2
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  # RED before the fix: hold:self.
  [ "$(disp "$S1")" = wait:self ] || { echo "$output"; false; }
  [[ "$output" == *"once THIS session's turn has ended"* ]] || { echo "$output"; false; }
  t0="$(date +%s)"
  # --wait 600 and a 0 s poll: a loop that waited on the self row would spin for the full bound.
  run bash "$CCLR" move --sid "$S1" --to next2 --wait 600
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [ $(( $(date +%s) - t0 )) -lt 60 ] || { echo "move blocked on its own row: $output"; false; }
  [[ "$output" == *"queued THIS session (${S1:0:8}) in batch "*"end your turn now"*"(<= 900s)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"session-continue.sh clear"* ]] || { echo "$output"; false; }
  d="$(moved_dir)"
  [ -s "$d/plan.json" ]
  [ "$(jq -r '.until_idle_s' "$d/plan.json")" -ge 900 ]
  [ "$(jq -r --arg s "$S1" '.rows[] | select(.sid == $s) | .disposition' "$d/plan.json")" = wait:self ]
  [ "$(jq -r --arg s "$S1" '.rows[] | select(.sid == $s) | .act' "$d/plan.json")" = wait ]
  [ -s "$d/intent/$S1.json" ]
  [ "$(jq -r '.expires_epoch - .ts' "$d/intent/$S1.json")" -ge 1800 ]
  [ "$(nreq)" -eq 1 ]
  grep -q 'kickstart' "$BATS_TEST_TMPDIR/launchctl.log"
  run grep -c -- ' -k ' "$BATS_TEST_TMPDIR/launchctl.log"
  [ "$output" = 0 ]
}

@test "2 the self budget is a floor: a larger --until-idle is kept, and CC_LR_MOVE_SELF_WAIT_S moves the floor" {
  sess 401 "$S1"
  export LRU_SELF_SID="$S1"
  run bash "$CCLR" move --sid "$S1" --to next2 --until-idle 2400 --wait 0
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [ "$(jq -r '.until_idle_s' "$(moved_dir)/plan.json")" -eq 2400 ]
  CC_LR_MOVE_SELF_WAIT_S=1200 run bash "$CCLR" move --sid "$S1" --to next2 --wait 0
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"(<= 1200s)"* ]] || { echo "$output"; false; }
  [ "$(jq -s -r '[.[].until_idle_s] | sort | map(tostring) | join(",")' "$LR_STATE_DIR"/move/*/plan.json)" = 1200,2400 ]
}

@test "3 CONTROL: a self row with a live /goal is still hold:goal-live, says to clear the goal, and nothing is queued" {
  sess 401 "$S1"
  export LRU_SELF_SID="$S1"
  goal_live_condition() { echo "a live goal"; return 0; }
  export -f goal_live_condition
  run bash "$CCLR" plan --sid "$S1" --to next2
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [ "$(disp "$S1")" = hold:goal-live ] || { echo "$output"; false; }
  [[ "$output" == *"clear the goal first"* ]] || { echo "$output"; false; }
  run bash "$CCLR" move --sid "$S1" --to next2 --wait 0
  [ "$status" -eq 1 ] || { echo "rc $status: $output"; false; }
  [ -z "$(moved_dir)" ]
  [ "$(nreq)" -eq 0 ]
}

@test "4 CONTROL: a self row is never plain move; CC_LR_MOVE_SELF_WAIT=off restores hold:self" {
  sess 401 "$S1"
  export LRU_SELF_SID="$S1"
  run bash "$CCLR" plan --sid "$S1" --to next2 --until-idle 600
  [ "$(disp "$S1")" != move ] || { echo "$output"; false; }
  CC_LR_MOVE_SELF_WAIT=off run bash "$CCLR" plan --sid "$S1" --to next2
  [ "$(disp "$S1")" = hold:self ] || { echo "$output"; false; }
  CC_LR_MOVE_SELF_WAIT=off run bash "$CCLR" move --sid "$S1" --to next2 --wait 0
  [ "$status" -eq 1 ] || { echo "rc $status: $output"; false; }
  [ -z "$(moved_dir)" ]
}

@test "5 [RED] rotate --list shows a self row as wait and points at cc-lr move --sid" {
  sess 401 "$S1"
  export LRU_SELF_SID="$S1"
  # next3 is capped (weekly 100%); nothing is limit-blocked; the router picks next2.
  cat > "$CC_ACCOUNTS_BIN" <<'SH'
#!/bin/bash
case " $* " in
  *" --json "*) printf '{"rows":[{"acct":"next","weekly_pct":5,"session_pct":1},{"acct":"next2","weekly_pct":7,"session_pct":1},{"acct":"next3","weekly_pct":100,"session_pct":1},{"acct":"next4","weekly_pct":2,"session_pct":1}]}\n' ;;
  *) printf 'next2 0.9\nnext4 0.5\n' ;;
esac
SH
  export CC_LR_FIND_BIN="$STUBS/cc-find"
  printf '#!/bin/bash\nexit 1\n' > "$CC_LR_FIND_BIN"; chmod +x "$CC_LR_FIND_BIN"
  run bash "$CCLR" rotate --list --account next3 --to next2
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  row="$(printf '%s\n' "$output" | awk -v s="${S1:0:8}" '$3 == s')"
  # RED before the fix: hold:self … cc-lr switch --target next2.
  [[ "$row" == *"wait:self"*"wait"*"next2"*"cc-lr move --sid $S1 --to next2"* ]] || { echo "$output"; false; }
  [ -z "$(moved_dir)" ]
}

@test "6 [RED] the self-wait budget scales with load: 3240 s at 13/core, capped at 3600, an explicit budget wins" {
  sess 401 "$S1"
  export LRU_SELF_SID="$S1"
  # RED before the fix: a flat 900 s, which cannot hold two ~11 min censuses at 13/core
  # (batch 20261018T131324Z-next3-next2-94791: NOTMOVED still-busy:move after 900s).
  CC_LR_LOAD_PER_CORE=13 run bash "$CCLR" move --sid "$S1" --to next2 --wait 0
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"(<= 3240s)"* ]] || { echo "$output"; false; }
  CC_LR_LOAD_PER_CORE=40 run bash "$CCLR" move --sid "$S1" --to next2 --wait 0
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"(<= 3600s)"* ]] || { echo "$output"; false; }
  CC_LR_LOAD_PER_CORE=13 CC_LR_MOVE_SELF_WAIT_S=1200 run bash "$CCLR" move --sid "$S1" --to next2 --wait 0
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"(<= 1200s)"* ]] || { echo "$output"; false; }
  [ "$(jq -s -r '[.[].until_idle_s] | sort | map(tostring) | join(",")' "$LR_STATE_DIR"/move/*/plan.json)" = 1200,3240,3600 ]
}
