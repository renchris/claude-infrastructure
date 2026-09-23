#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell; per-test exports are the intent
# A team member's pane when its lead cannot close it (2026-09-23, pane 545).
# Subjects: scripts/teammate-orphan-pane-close.sh (the closer) and the arm in hooks/session-end.sh
# that detaches it from the member's own SessionEnd.
#
# THE INCIDENT. Lead 513 was resumed in place (cc-lr upgrade), then shut its member down; the member
# wrote shutdown_approved {paneId:"545"} and exited rc 0. The vendor closes a member's pane from the
# LEAD's inbox poller, and only for a paneId in the lead's in-memory roster — which a resumed lead
# rebuilds with itself alone — so the approval sat unread and pane 545 stayed at a bare shell.
#
# [RED] cases fail with the subject absent (the closer is a new file; the hook arm a new block).
# The non-[RED] cases are the refusals that make the close safe, each falsifying ONE condition.
# Two of them were found the hard way: the member census and the member identity each first read
# argv TEXT, and the session writing this suite carried `--agent-id refute-reversals@…` in its own
# brief — so it read as the live member (closer) and as the member itself (hook).

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CLOSER="$REPO/scripts/teammate-orphan-pane-close.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  CFG="$BATS_TEST_TMPDIR/cfg"; TEAMD="$CFG/teams/session-aaaa1111"; mkdir -p "$TEAMD/inboxes"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  # it2: `session list` prints the ids in panes.txt; every other call is RECORDED, never run.
  printf '#!/bin/bash\nif [ "$1 $2" = "session list" ]; then cat %s/panes.txt; exit 0; fi\necho "$*" >> %s/it2.log\n' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$STUBS/it2"; chmod +x "$STUBS/it2"
  printf '545\n579\n' > "$BATS_TEST_TMPDIR/panes.txt"
  export TOPC_IT2="$STUBS/it2" TOPC_GRACE_S=0 TOPC_NOW=1790151660 TOPC_LOG="$BATS_TEST_TMPDIR/topc.log"
  export TOPC_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$TOPC_REG_DIR"
  export TOPC_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$TOPC_PS_SNAPSHOT"
  : > "$BATS_TEST_TMPDIR/it2.log"
}

# approve <read:true|false> <iso ts>   — the member's shutdown_approved in the lead's inbox
approve() {
  local body
  body="$(jq -cn --arg ts "$2" '{type:"shutdown_approved",requestId:"shutdown-1@m",from:"m",timestamp:$ts,paneId:"545",backendType:"iterm2"}')"
  jq -n --arg t "$body" --argjson r "$1" --arg ts "$2" '[{from:"m",text:$t,timestamp:$ts,read:$r}]' > "$TEAMD/inboxes/team-lead.json"
}
closer() { run bash "$CLOSER" --cfg "$CFG" --team session-aaaa1111 --name m --agent-id m@session-aaaa1111; }
closed() { grep -qx 'session close -f -s 545' "$BATS_TEST_TMPDIR/it2.log"; }

@test "1 [RED] a fresh UNREAD approval, member gone, pane listed: the member's pane is closed" {
  approve false 2026-09-23T08:20:37.011Z
  closer
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  closed || { cat "$TOPC_LOG"; false; }
  grep -q 'closed pane 545' "$TOPC_LOG" || { cat "$TOPC_LOG"; false; }
}

@test "2 an approval the lead READ is the lead's close: nothing is closed" {
  approve true 2026-09-23T08:20:37.011Z
  closer
  [ ! -s "$BATS_TEST_TMPDIR/it2.log" ] || { cat "$BATS_TEST_TMPDIR/it2.log"; false; }
  grep -q 'lead READ' "$TOPC_LOG" || { cat "$TOPC_LOG"; false; }
}

@test "3 an approval older than the window is not this exit's: nothing is closed" {
  approve false 2026-09-22T08:20:37Z
  closer
  [ ! -s "$BATS_TEST_TMPDIR/it2.log" ] || false
  grep -q 'window 300s' "$TOPC_LOG" || { cat "$TOPC_LOG"; false; }
}

@test "4 the pane's registered pid is a LIVE claude (relaunched in place): nothing is closed" {
  approve false 2026-09-23T08:20:37.011Z
  bash -c 'exec -a /x/.claude-280/node_modules/.bin/claude sleep 300' & LIVE=$!
  printf '{"paneUUID":"545","pid":%d}\n' "$LIVE" > "$TOPC_REG_DIR/545.json"
  sleep 0.3
  closer
  kill "$LIVE" 2>/dev/null || true
  [ ! -s "$BATS_TEST_TMPDIR/it2.log" ] || { cat "$BATS_TEST_TMPDIR/it2.log"; false; }
  grep -q 'is a live claude' "$TOPC_LOG" || { cat "$TOPC_LOG"; false; }
}

@test "5 a brief QUOTING the id is not the member; the vendor spawn form is" {
  approve false 2026-09-23T08:20:37.011Z
  echo "/x/claude --permission-mode auto --model m 'relaunch with --agent-id m@session-aaaa1111 --agent-name m'" > "$TOPC_PS_SNAPSHOT"
  closer
  closed || { echo "a quoting brief read as the live member:"; cat "$TOPC_LOG"; false; }
  : > "$BATS_TEST_TMPDIR/it2.log"
  echo "/x/claude.exe --agent-id m@session-aaaa1111 --agent-name m --team-name session-aaaa1111" > "$TOPC_PS_SNAPSHOT"
  closer
  [ ! -s "$BATS_TEST_TMPDIR/it2.log" ] || { echo "a live vendor-spawned member's pane was closed"; false; }
}

@test "6 a pane no longer listed, no approval at all, and the kill switch each close nothing" {
  approve false 2026-09-23T08:20:37.011Z
  printf '579\n' > "$BATS_TEST_TMPDIR/panes.txt"
  closer
  [ ! -s "$BATS_TEST_TMPDIR/it2.log" ] || false
  grep -q 'already gone' "$TOPC_LOG" || { cat "$TOPC_LOG"; false; }
  printf '545\n' > "$BATS_TEST_TMPDIR/panes.txt"
  echo '[]' > "$TEAMD/inboxes/team-lead.json"
  closer
  [ ! -s "$BATS_TEST_TMPDIR/it2.log" ] || false
  approve false 2026-09-23T08:20:37.011Z
  CC_TEAMMATE_ORPHAN_CLOSE=off closer
  [ ! -s "$BATS_TEST_TMPDIR/it2.log" ] || false
}

# ── the SessionEnd arm ────────────────────────────────────────────────────────────────────────────
hook_env() {
  export CLAUDE_CONFIG_DIR="$CFG" CC_TMP_SWEEP_DIRS="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$CC_TMP_SWEEP_DIRS"
  export SE_DETACH_LIB="$REPO/scripts/lib/detach.sh" SE_TOPC_BIN="$STUBS/closer" CC_TERM=kitty
  printf '#!/bin/bash\necho "$*" > %s/closer.args\n' "$BATS_TEST_TMPDIR" > "$SE_TOPC_BIN"; chmod +x "$SE_TOPC_BIN"
  printf '{"members":[{"name":"team-lead","agentId":"team-lead@session-aaaa1111","tmuxPaneId":"leader"},{"name":"m","agentId":"m@session-aaaa1111","tmuxPaneId":"545","backendType":"iterm2"}]}\n' > "$TEAMD/config.json"
  unset KITTY_WINDOW_ID
}
end_hook() { echo '{"session_id":"s1","reason":"other"}' | bash "$REPO/hooks/session-end.sh"; }
await_args() { local i=0; while [ ! -s "$BATS_TEST_TMPDIR/closer.args" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done; }

@test "7 [RED] the member's own SessionEnd detaches the closer with its team identity" {
  hook_env
  ITERM_SESSION_ID=w0t0p0:545 SE_TEAMMATE_ARGV="/x/claude --resume s1 --agent-id m@session-aaaa1111 --agent-name m" end_hook
  await_args
  [ "$(cat "$BATS_TEST_TMPDIR/closer.args" 2>/dev/null)" = "--cfg $CFG --team session-aaaa1111 --name m --agent-id m@session-aaaa1111" ] \
    || { cat "$BATS_TEST_TMPDIR/closer.args" 2>/dev/null; false; }
}

@test "8 identity is the PANE: a non-member pane whose argv QUOTES the id detaches nothing" {
  hook_env
  ITERM_SESSION_ID=w0t0p0:579 SE_TEAMMATE_ARGV="/x/claude 'brief: --agent-id m@session-aaaa1111 --agent-name m'" end_hook
  sleep 1
  [ ! -e "$BATS_TEST_TMPDIR/closer.args" ] || { echo "a quoting session in another pane was taken for the member"; false; }
  # the member's pane, but a claude that is NOT that member (argv lacks its id): nothing either
  ITERM_SESSION_ID=w0t0p0:545 SE_TEAMMATE_ARGV="/x/claude --model m" end_hook
  sleep 1
  [ ! -e "$BATS_TEST_TMPDIR/closer.args" ] || false
  CC_TEAMMATE_ORPHAN_CLOSE=off ITERM_SESSION_ID=w0t0p0:545 SE_TEAMMATE_ARGV="/x/claude --agent-id m@session-aaaa1111" end_hook
  sleep 1
  [ ! -e "$BATS_TEST_TMPDIR/closer.args" ] || { echo "the kill switch did not hold"; false; }
}
