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
  # Sealed suite-wide (2026-10-10, C3): lr_pid_cfg would otherwise read `ps -E` of a fixture row's
  # pid — this bats process, carrying the running session's CLAUDE_CONFIG_DIR.
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
moved_dir() { local d; for d in "$LR_STATE_DIR"/move/*/; do case "$d" in */requests/) continue ;; esac; [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }; done; }
nfiles() { local f n=0; for f in "$1"/*; do [ -e "$f" ] && n=$((n + 1)); done; printf '%s' "$n"; }

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
  [ "$(nfiles "$d/intent")" -eq 1 ]
  [ "$(stat -f %Lp "$d/intent/$S1.json" 2>/dev/null || stat -c %a "$d/intent/$S1.json")" = 600 ]
  run bash -c '. "$1"; lr_intent_check "$2" "$3" 401 next3 next2; echo "rc=$? $LR_INTENT_WHY"' _ "$REPO/scripts/limit-recover/lr-intent.sh" "$d/intent/$S1.json" "$S1"
  [ "$output" = "rc=0 " ]
  [ "$(nfiles "$LR_STATE_DIR/move/requests")" -eq 1 ]
  [ "$(jq -r .to_config_dir "$d/plan.json")" = "$HOME/.claude-secondary" ]
  # The strict router check ranked the target, so admission may reuse that answer (LR_MOVE_ROUTE_REUSE_S).
  jq -e '.router_ranked_epoch | type == "number"' "$d/plan.json" >/dev/null
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
  # one row: no table — the verdict line names it, answer first (2026-10-19, lr-wake H2)
  [ "${lines[0]}" = "⟳ ${S1:0:8} move · next3 → next2 · DRY RUN: nothing was written or typed" ] || { echo "$output"; false; }
  [[ "${lines[1]}" == "  pane 401 · restart on next2"* ]] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -cE '^40[0-9] ')" -eq 0 ] || { echo "$output"; false; }
  # --verbose brings the table back
  run bash "$CCLR" move --sid "$S1" --to next2 --dry-run --verbose
  [ "$(printf '%s\n' "$output" | grep -cE '^40[0-9] ')" -eq 1 ] || { echo "$output"; false; }
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

# ── RULE 1 ON THIS LANE (2026-10-06). The census matches --sid by prefix, fleet-wide when no --from
# is given, and `plan`/`move` never counted the rows: a short prefix planned two sessions where the
# operator named one. `switch --sid` has always refused that.
@test "16 [RED] plan --sid / move --sid with a prefix that matches two sessions is REFUSED and writes nothing" {
  sess 401 "$S1"
  sess 402 "$S2"
  run bash "$CCLR" plan --sid aaaa000 --to next2
  # RED before the fix: rc 0 and a two-row plan.
  [ "$status" -eq 2 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"matched more than one live session"* ]] || { echo "$output"; false; }
  [[ "$output" == *"401"* && "$output" == *"402"* ]] || { echo "$output"; false; }
  run bash "$CCLR" move --sid aaaa000 --to next2 --wait 0
  [ "$status" -eq 2 ] || { echo "rc $status: $output"; false; }
  [ -z "$(moved_dir)" ]
  [ ! -e "$BATS_TEST_TMPDIR/launchctl.log" ]
  # an EMPTY sid is a prefix of every sid; with no --from it selected the whole fleet
  run bash "$CCLR" move --sid "" --to next2 --wait 0
  [ "$status" -eq 2 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"empty value"* ]] || { echo "$output"; false; }
  [ -z "$(moved_dir)" ]
  # control: a sid that names one session still plans it
  run bash "$CCLR" plan --sid "$S1" --to next2
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [ "$(disp "$S1")" = move ]
}

# ── EXIT 0 MEANS ALL MOVED, ON A DIRECTORY SHAPED LIKE A REAL ONE (2026-10-06). The recorded batch
# 20261006T060534Z-next3-next2-64630 holds, beside each <sid>.json, a <sid>.watcher.json and one
# request.claimed.json. The exit-code count read every *.json for `.verdict // "FAILED"`, so those
# files counted as failures and a fully moved batch exited 1; and its `case a|b)` inside `$( )` is
# the construct bash 3.2 cannot parse. No case reached that path: every other `move` here passes
# --wait 0 and returns before it. The lane is stood in for by the kick stub.
@test "17 [RED] move exits 0 after a fully moved batch whose directory holds what a real one holds, and states its bounds" {
  sess 401 "$S1"
  cat > "$STUBS/launchctl" <<STUB
#!/bin/bash
for d in "$LR_STATE_DIR"/move/*/; do
  [ -d "\${d}intent" ] || continue
  for i in "\${d}intent"/*.json; do
    s="\$(basename "\$i" .json)"
    printf '{"sid":"%s","verdict":"MOVED","reason":"pane 401 runs the session on the target, one copy"}\n' "\$s" > "\${d}\$s.json"
    printf '{"pid":17125,"pane":"401"}\n' > "\${d}\$s.watcher.json"
  done
  printf '{"kind":"move-batch"}\n' > "\${d}request.claimed.json"
  printf '{"admitted":true,"target_auth":"ok"}\n' > "\${d}admit.json"
done
STUB
  chmod +x "$STUBS/launchctl"
  run bash "$CCLR" move --sid "$S1" --to next2 --wait 30 --verbose
  # RED before the fix: rc 1.
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"MOVED — pane 401 runs the session on the target"* ]] || { echo "$output"; false; }
  [[ "$output" == *"bounds: move 4 at a time (LR_MOVE_SLOTS; a fixed count"*"not memory"* ]] || { echo "$output"; false; }
  # without --verbose: the verdict line first, the status command once, no bounds line
  run bash "$CCLR" move --sid "$S1" --to next2 --wait 30
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  local b; b="$(printf '%s\n' "${lines[0]}" | sed -n 's/^⏸ .* · batch //p')"
  [[ "${lines[0]}" == "⏸ ${S1:0:8} moves next3 → next2 when idle · batch "* ]] || { echo "$output"; false; }
  [ -n "$b" ] || { echo "no batch id on the verdict line: $output"; false; }
  [ "${lines[1]}" = "  ▶ cc-lr move --status $b" ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'cc-lr move --status')" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" != *"bounds:"* ]] || { echo "$output"; false; }
  [[ "$output" == *"MOVED — pane 401 runs the session on the target"* ]] || { echo "$output"; false; }
}

@test "18 --slots W is the width this batch was given, and the bounds line says so" {
  sess 401 "$S1"
  run bash "$CCLR" move --sid "$S1" --to next2 --slots 6 --dry-run --verbose
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"bounds: move 6 at a time (--slots;"* ]] || { echo "$output"; false; }
}

@test "[RED] C3: a FORWARD husk is hold:husk naming cc-lr recover — never the repair-markers loop" {
  # 186452ed: repair-markers rightly KEEPs a tombstone that names where the session went, so naming
  # it from here was a refusal loop. The source pane is alive (CC_REGISTRY_DIR, pid = this process).
  sess 405 "$S5"
  local T="$HOME/.claude-tertiary/projects/-x" Q="$HOME/.claude-quaternary/projects/-x"
  mkdir -p "$Q"; cp "$T/$S5.jsonl" "$T/$S5.jsonl.handed-off"; cp "$T/$S5.jsonl" "$Q/$S5.jsonl"
  printf '{"handed_off_to":"%s","ts":"2026-10-10T04:18:07Z"}\n' "$HOME/.claude-quaternary" > "$T/$S5.HANDOFF.json"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/ccreg"; mkdir -p "$CC_REGISTRY_DIR"
  printf '{"paneUUID":"405","session_id":"%s","pid":%d,"account":"claude-tertiary"}\n' "$S5" "$$" > "$CC_REGISTRY_DIR/405.json"
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/penv"; mkdir -p "$LR_MOVE_ENV_DIR"; printf '%s' "$HOME/.claude-tertiary" > "$LR_MOVE_ENV_DIR/$$"
  run bash "$CCLR" plan --from next3 --to next2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(disp "$S5")" = hold:husk ] || { echo "$output"; false; }
  [[ "$output" == *"cc-lr recover ${S5:0:8}"* ]] || { echo "$output"; false; }
  [[ "$output" != *"repair-markers --sid $S5"* ]] || { echo "$output"; false; }
}

# ── SEVERAL NAMED SESSIONS, ONE BATCH (2026-10-17T23:57Z). Asked to "move every session on
# next2/next3/next4 to next, highest-activity first", a session found that --sid took one value and
# launched five one-sid batches in parallel: five census runs, three router reads (~550 s) serialized
# on the admit lock, two batches refused. A repeated --sid, or --sids a,b,c, is one census and one
# batch, in the order named, across source accounts.
pane_order() { printf '%s\n' "$output" | awk '$1 ~ /^40[0-9]$/ { printf "%s ", $2 }'; }

@test "19 [RED] plan --sid A --sid B and plan --sids B,A list exactly the named rows, in the order named" {
  fleet
  run bash "$CCLR" plan --sid "$S1" --sid "$S2" --to next2
  # RED before the fix: the second --sid replaced the first, a one-row plan.
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [ "$(pane_order)" = "${S1:0:8} ${S2:0:8} " ] || { echo "$output"; false; }
  run bash "$CCLR" plan --sids "${S2:0:8},${S1:0:8}" --to next2 --json
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [ "$(printf '%s' "$output" | jq -r '[.rows[].sid] | join(" ")')" = "$S2 $S1" ] || { echo "$output"; false; }
}

@test "20 [RED] move --sids A,B: ONE plan whose rows are A then B, ONE request, two intents" {
  sess 401 "$S1"
  sess 405 "$S5"
  run bash "$CCLR" move --sids "$S5,$S1" --to next2 --wait 0
  [ "$status" -eq 1 ] || { echo "rc $status: $output"; false; }
  d="$(moved_dir)"
  [ "$(nfiles "$LR_STATE_DIR/move")" -eq 2 ] || { ls "$LR_STATE_DIR/move"; false; }   # the batch and requests/
  [ "$(jq -r '[.rows[].sid] | join(" ")' "$d/plan.json")" = "$S5 $S1" ] || { cat "$d/plan.json"; false; }
  [ "$(jq -r .from "$d/plan.json")" = next3 ]
  [ "$(nfiles "$d/intent")" -eq 2 ]
  [ "$(nfiles "$LR_STATE_DIR/move/requests")" -eq 1 ]
}

@test "21 [RED] sessions on two accounts: .from is mixed, the batch id says so, each intent keeps its own source" {
  sess 401 "$S1"
  sess 407 "$S2" rest claude-quaternary
  # control: with --from, a named session on another account is refused, and nothing is written
  run bash "$CCLR" move --from next3 --sids "$S1,$S2" --to next2 --wait 0
  [ "$status" -eq 2 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"no live session matched '$S2' on next3"* ]] || { echo "$output"; false; }
  [ -z "$(moved_dir)" ]
  run bash "$CCLR" move --sids "$S1,$S2" --to next2 --wait 0
  [ "$status" -eq 1 ] || { echo "rc $status: $output"; false; }
  d="$(moved_dir)"
  [ "$(jq -r .from "$d/plan.json")" = mixed ] || { cat "$d/plan.json"; false; }
  [[ "$(basename "$d")" == *-mixed-next2-* ]] || { echo "$d"; false; }
  [ "$(jq -r .from "$d/intent/$S1.json")" = next3 ]
  [ "$(jq -r .from "$d/intent/$S2.json")" = next4 ]
}

@test "22 [RED] a list with an ambiguous prefix, an empty element or a prefix matching nothing is refused rc 2, nothing written" {
  sess 401 "$S1"
  sess 402 "$S2"
  sess 403 "$S3"
  run bash "$CCLR" move --sids "$S3,aaaa000" --to next2 --wait 0
  [ "$status" -eq 2 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"'aaaa000' matched more than one live session"* ]] || { echo "$output"; false; }
  run bash "$CCLR" move --sids "$S1,,$S2" --to next2 --wait 0
  [ "$status" -eq 2 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"element 2 is empty"* ]] || { echo "$output"; false; }
  run bash "$CCLR" move --sid "$S1" --sid ffff0000 --to next2 --wait 0
  [ "$status" -eq 2 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"no live session matched 'ffff0000'"* ]] || { echo "$output"; false; }
  [ -z "$(moved_dir)" ]
  [ ! -e "$BATS_TEST_TMPDIR/launchctl.log" ]
  # --pane names one session and is not combined with a list
  run bash "$CCLR" plan --pane 401 --sids "$S1,$S2" --to next2
  [ "$status" -eq 3 ] || { echo "rc $status: $output"; false; }
}

@test "23 [RED] a mixed batch's WATCH census carries no --from, so every waiting worker finds its row" {
  [ -x /bin/bash ] || skip "/bin/bash absent"
  sess 401 "$S1"
  sess 407 "$S2" rest claude-quaternary
  run bash "$CCLR" move --sids "$S1,$S2" --to next2 --wait 0
  d="$(moved_dir)"
  [ "$(jq -r .from "$d/plan.json" 2>/dev/null)" = mixed ] || { echo "rc $status: $output"; false; }
  # The runner's own seams: a worker that waits for its session to go idle until the WATCH census has
  # run (bounded at 120 s), and a census recorder. A fixed 2 s wait ended before the watch loop's first
  # sample at load ~700 (2026-10-18), and the census was never asked.
  export CENSUS_LOG="$BATS_TEST_TMPDIR/census.log"
  cat > "$STUBS/worker" <<'STUB'
#!/bin/bash
d="$LR_STATE_DIR/move/$1"; : > "$d/$2.waiting"
i=0; while [ ! -s "$CENSUS_LOG" ] && [ "$i" -lt 600 ]; do sleep 0.2; i=$((i + 1)); done
printf '{"sid":"%s","verdict":"MOVED","reason":"stub worker"}\n' "$2" > "$d/$2.json"; rm -f "$d/$2.waiting"
STUB
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$CENSUS_LOG"\n' > "$STUBS/upgrade"
  chmod +x "$STUBS/worker" "$STUBS/upgrade"
  LR_MOVE_WORKER_BIN="$STUBS/worker" LR_MOVE_UPGRADE_BIN="$STUBS/upgrade" CC_NOTIFY_BIN="$LRU_NOTIFY_BIN" \
    LR_MOVE_GUARD_CHECK=off LR_MOVE_AUTH_RECHECK=off LR_MOVE_KERNEL_CHECK=off LR_MOVE_PRESEED=off \
    LR_MOVE_SNAP_S=1 LR_MOVE_WATCH_POLL_S=0.3 run /bin/bash "$REPO/scripts/limit-recover/lr-move-batch.sh" "$(basename "$d")"
  # the census ran (the seam is live), for the target, and without a source filter
  grep -q -- '^--switch-census .*--target next2' "$BATS_TEST_TMPDIR/census.log" || { echo "$output"; false; }
  ! grep -q -- '--from' "$BATS_TEST_TMPDIR/census.log" || { cat "$BATS_TEST_TMPDIR/census.log"; false; }
}

# watchbatch <waiting-sid> — run the batch runner over the current batch with stub seams: the worker
# for <waiting-sid> waits (until the WATCH census has run, bounded at 120 s); every other worker
# settles MOVED at once. The census stub records `self=[$LRU_SELF_SID] <argv>` per call.
watchbatch() {
  local d; d="$(moved_dir)"
  export CENSUS_LOG="$BATS_TEST_TMPDIR/census.log" WAIT_SID="$1"
  cat > "$STUBS/worker" <<'STUB'
#!/bin/bash
d="$LR_STATE_DIR/move/$1"
if [ "$2" = "$WAIT_SID" ]; then
  : > "$d/$2.waiting"
  i=0; while [ ! -s "$CENSUS_LOG" ] && [ "$i" -lt 600 ]; do sleep 0.2; i=$((i + 1)); done
fi
printf '{"sid":"%s","verdict":"MOVED","reason":"stub worker"}\n' "$2" > "$d/$2.json"; rm -f "$d/$2.waiting"
STUB
  printf '#!/bin/bash\nprintf "self=[%%s] %%s\\n" "${LRU_SELF_SID-unset}" "$*" >> "$CENSUS_LOG"\n' > "$STUBS/upgrade"
  chmod +x "$STUBS/worker" "$STUBS/upgrade"
  LR_MOVE_WORKER_BIN="$STUBS/worker" LR_MOVE_UPGRADE_BIN="$STUBS/upgrade" CC_NOTIFY_BIN="$LRU_NOTIFY_BIN" \
    LR_MOVE_GUARD_CHECK=off LR_MOVE_AUTH_RECHECK=off LR_MOVE_KERNEL_CHECK=off LR_MOVE_PRESEED=off \
    LR_MOVE_SNAP_S=1 LR_MOVE_WATCH_POLL_S=0.3 run /bin/bash "$REPO/scripts/limit-recover/lr-move-batch.sh" "$(basename "$d")"
}

@test "24 [RED] the WATCH census names only the waiting sids: 3 rows, 1 waits, the census asks for that one" {
  [ -x /bin/bash ] || skip "/bin/bash absent"
  sess 401 "$S1"
  sess 402 "$S2"
  sess 403 "$S3"
  run bash "$CCLR" move --sids "$S1,$S2,$S3" --to next2 --wait 0
  [ -n "$(moved_dir)" ] || { echo "rc $status: $output"; false; }
  watchbatch "$S2"
  [ -s "$CENSUS_LOG" ] || { echo "$output"; false; }
  # RED before: `--switch-census --from next3 --target next2` — every row on the source, no --sid.
  grep -q -- "--sid $S2" "$CENSUS_LOG" || { cat "$CENSUS_LOG"; false; }
  ! grep -q -- "$S1\|$S3" "$CENSUS_LOG" || { cat "$CENSUS_LOG"; false; }
  grep -q -- '--from next3 --target next2' "$CENSUS_LOG" || { cat "$CENSUS_LOG"; false; }
}

@test "25 [RED] the WATCH census runs with LRU_SELF_SID empty, whatever the requester exported" {
  [ -x /bin/bash ] || skip "/bin/bash absent"
  # The runner inherits the requester's env, and the census reads LRU_SELF_SID as "this row is me"
  # (disp=self, a hold): a batch moving the requester's own session would never see it `move`.
  sess 401 "$S1"
  sess 402 "$S2"
  run bash "$CCLR" move --sids "$S1,$S2" --to next2 --wait 0
  [ -n "$(moved_dir)" ] || { echo "rc $status: $output"; false; }
  export LRU_SELF_SID="$S2"
  watchbatch "$S2"
  [ -s "$CENSUS_LOG" ] || { echo "$output"; false; }
  # RED before: self=[<S2>].
  grep -q -- '^self=\[\] --switch-census ' "$CENSUS_LOG" || { cat "$CENSUS_LOG"; false; }
  ! grep -q -- "^self=\[$S2\]" "$CENSUS_LOG" || { cat "$CENSUS_LOG"; false; }
}

@test "26 [RED] the WATCH census runs unclamped by default: a waiting worker reads what it writes" {
  [ -x /bin/bash ] || skip "/bin/bash absent"
  # The workers waiting on `<sid>.waiting` read their row from the snap.tsv this census writes, so it
  # is on the critical path, and at load ~200 the utility band costs it 20-153x
  # (docs/research/lr-sustained-load-2026-10-20, axis 04 L5, axis 07 skeptic L1). A recorder stands
  # in for /usr/sbin/taskpolicy and runs the census it was handed.
  export TP_LOG="$BATS_TEST_TMPDIR/taskpolicy.log"
  printf '#!/bin/bash\necho "$*" >> "$TP_LOG"\nshift 2\nexec "$@"\n' > "$STUBS/taskpolicy"; chmod +x "$STUBS/taskpolicy"
  export LR_MOVE_TASKPOLICY_BIN="$STUBS/taskpolicy"
  unset LR_MOVE_CENSUS_CLAMP
  sess 401 "$S1"
  sess 402 "$S2"
  run bash "$CCLR" move --sids "$S1,$S2" --to next2 --wait 0
  [ -n "$(moved_dir)" ] || { echo "rc $status: $output"; false; }
  watchbatch "$S2"
  [ -s "$CENSUS_LOG" ] || { echo "$output"; false; }
  # RED before: `-c utility /bin/bash ... --switch-census` was recorded on every census.
  [ ! -s "$TP_LOG" ] || { cat "$TP_LOG"; false; }
}

@test "27 OPT-IN: LR_MOVE_CENSUS_CLAMP=on still clamps the WATCH census to the utility band" {
  [ -x /bin/bash ] || skip "/bin/bash absent"
  export TP_LOG="$BATS_TEST_TMPDIR/taskpolicy.log"
  printf '#!/bin/bash\necho "$*" >> "$TP_LOG"\nshift 2\nexec "$@"\n' > "$STUBS/taskpolicy"; chmod +x "$STUBS/taskpolicy"
  export LR_MOVE_TASKPOLICY_BIN="$STUBS/taskpolicy" LR_MOVE_CENSUS_CLAMP=on
  sess 401 "$S1"
  sess 402 "$S2"
  run bash "$CCLR" move --sids "$S1,$S2" --to next2 --wait 0
  [ -n "$(moved_dir)" ] || { echo "rc $status: $output"; false; }
  watchbatch "$S2"
  [ -s "$CENSUS_LOG" ] || { echo "$output"; false; }
  grep -q -- '^-c utility /bin/bash .*--switch-census ' "$TP_LOG" || { cat "$TP_LOG" 2>/dev/null; false; }
}
