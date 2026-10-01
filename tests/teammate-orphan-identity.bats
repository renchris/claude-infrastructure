#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell; per-test exports are the intent
# The SessionEnd orphan-pane closer finds its member and keeps a failed close (2026-09-30, husk
# panes after the reboot — docs/research/husk-panes-2026-09-30.md root cause 4, fix F-b).
# Subjects: the member arm in hooks/session-end.sh and scripts/teammate-orphan-pane-close.sh.
#
# THE INCIDENT. Five teammate panes stayed at a bare shell. The SessionEnd arm looked each member up
# in a team config.json the vendor had ALREADY rewritten (member removed), so it found nothing and
# detached no closer; the vendor's approval named panes 57/60 as `[invalid id]`; and every close
# that did run made one attempt, failed (rc 124) and was forgotten.
# Every case here fails against the pre-fix pair.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CLOSER="$REPO/scripts/teammate-orphan-pane-close.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  CFG="$BATS_TEST_TMPDIR/cfg"; TEAMD="$CFG/teams/session-aaaa1111"; mkdir -p "$TEAMD/inboxes"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  # it2: `session list` prints panes.txt and exits LIST_RC; `session close` exits CLOSE_RC. Every
  # non-list call is RECORDED, never run.
  # shellcheck disable=SC2016  # the stub's own $1/$2 must stay literal
  printf '#!/bin/bash\nif [ "$1 $2" = "session list" ]; then cat %s/panes.txt; exit "${LIST_RC:-0}"; fi\necho "$*" >> %s/it2.log\nexit "${CLOSE_RC:-0}"\n' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$STUBS/it2"; chmod +x "$STUBS/it2"
  printf '57\n60\n' > "$BATS_TEST_TMPDIR/panes.txt"
  # the shared queue lib (built by a sibling): pcq_add records its argv, one row per call
  printf 'pcq_add() { echo "$*" >> %s/pcq.log; }\n' "$BATS_TEST_TMPDIR" > "$STUBS/pcq.sh"
  export CC_PCQ_LIB="$STUBS/pcq.sh"
  export TOPC_IT2="$STUBS/it2" TOPC_GRACE_S=0 TOPC_NOW=1790151660 TOPC_LOG="$BATS_TEST_TMPDIR/topc.log"
  export TOPC_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$TOPC_REG_DIR"
  export TOPC_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$TOPC_PS_SNAPSHOT"
  : > "$BATS_TEST_TMPDIR/it2.log"
}

# approve <paneId> [backendType] — a fresh UNREAD shutdown_approved from member m in the lead's inbox
approve() {
  local body
  body="$(jq -cn --arg p "$1" --arg b "${2-iterm2}" '{type:"shutdown_approved",from:"m",timestamp:"2026-09-23T08:20:37.011Z",paneId:$p,backendType:$b}')"
  jq -n --arg t "$body" '[{from:"m",text:$t,timestamp:"2026-09-23T08:20:37.011Z",read:false}]' > "$TEAMD/inboxes/team-lead.json"
}
closer() { run bash "$CLOSER" --cfg "$CFG" --team session-aaaa1111 --name m --agent-id m@session-aaaa1111 "$@"; }

# ── the SessionEnd arm ────────────────────────────────────────────────────────────────────────────
hook_env() {
  export CLAUDE_CONFIG_DIR="$CFG" CC_TMP_SWEEP_DIRS="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$CC_TMP_SWEEP_DIRS"
  export SE_DETACH_LIB="$REPO/scripts/lib/detach.sh" SE_TOPC_BIN="$STUBS/closer" CC_TERM=kitty
  printf '#!/bin/bash\necho "$*" > %s/closer.args\n' "$BATS_TEST_TMPDIR" > "$SE_TOPC_BIN"; chmod +x "$SE_TOPC_BIN"
  # the vendor has ALREADY rewritten the config: only the lead is left
  printf '{"members":[{"name":"team-lead","agentId":"team-lead@session-aaaa1111","tmuxPaneId":"leader"}]}\n' > "$TEAMD/config.json"
  unset ITERM_SESSION_ID CC_PANE_ID
}
end_hook() { echo '{"session_id":"s1","reason":"other"}' | bash "$REPO/hooks/session-end.sh"; }
await_args() { local i=0; while [ ! -s "$BATS_TEST_TMPDIR/closer.args" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done; }

@test "1 member gone from config.json: the dying claude's own three-flag argv detaches the closer with --pane" {
  hook_env
  KITTY_WINDOW_ID=57 SE_TEAMMATE_ARGV="/x/.claude-280/claude --agent-id m@session-aaaa1111 --agent-name m --team-name session-aaaa1111 --parent-session-id p1" end_hook
  await_args
  [ "$(cat "$BATS_TEST_TMPDIR/closer.args" 2>/dev/null)" = "--cfg $CFG --team session-aaaa1111 --name m --agent-id m@session-aaaa1111 --pane 57" ] \
    || { cat "$BATS_TEST_TMPDIR/closer.args" 2>/dev/null; false; }
}

@test "2 an argv that only QUOTES the flags, or is not a claude, is not a member: nothing is detached" {
  hook_env
  KITTY_WINDOW_ID=57 SE_TEAMMATE_ARGV="/x/claude --model m brief: relaunch with --agent-id m@session-aaaa1111" end_hook
  KITTY_WINDOW_ID=57 SE_TEAMMATE_ARGV="/usr/bin/node --agent-id m@session-aaaa1111 --agent-name m --team-name session-aaaa1111" end_hook
  # all three present but the record disagrees with itself (prose, not a harness spawn)
  KITTY_WINDOW_ID=57 SE_TEAMMATE_ARGV="/x/claude --agent-id m@session-aaaa1111 --agent-name x --team-name session-aaaa1111" end_hook
  sleep 1
  [ ! -e "$BATS_TEST_TMPDIR/closer.args" ] || { cat "$BATS_TEST_TMPDIR/closer.args"; false; }
  # and the same arm DOES fire on the real spawn form, so the refusals above are not a dead arm
  KITTY_WINDOW_ID=57 SE_TEAMMATE_ARGV="/x/claude --agent-id m@session-aaaa1111 --agent-name m --team-name session-aaaa1111" end_hook
  await_args
  [ -s "$BATS_TEST_TMPDIR/closer.args" ]
}

# ── the closer ────────────────────────────────────────────────────────────────────────────────────
@test "3 approval paneId [invalid id] + --pane 57: the member's own pane is closed" {
  approve '[invalid id]'
  closer --pane 57
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'session close -f -s 57' "$BATS_TEST_TMPDIR/it2.log" || { cat "$TOPC_LOG"; false; }
  # an approval with NO backendType is driven through the it2 shim when --pane was measured
  : > "$BATS_TEST_TMPDIR/it2.log"; approve '' ''
  closer --pane 60
  grep -qx 'session close -f -s 60' "$BATS_TEST_TMPDIR/it2.log" || { cat "$TOPC_LOG"; false; }
}

@test "4 a pane listing that FAILS (rc 124) is unknown, not gone: no close, and a queue row" {
  approve 57
  LIST_RC=124 closer
  [ "$status" -eq 0 ]
  [ ! -s "$BATS_TEST_TMPDIR/it2.log" ] || { cat "$BATS_TEST_TMPDIR/it2.log"; false; }
  grep -q '^teammate 57 agent_id=m@session-aaaa1111 team=session-aaaa1111 reason=.* rc=124$' "$BATS_TEST_TMPDIR/pcq.log" \
    || { cat "$BATS_TEST_TMPDIR/pcq.log" "$TOPC_LOG" 2>/dev/null; false; }
}

@test "5 a close that times out (rc 124) is queued as orphan-close-failed, never retried inline" {
  approve 57
  CLOSE_RC=124 closer
  [ "$status" -eq 0 ]
  [ "$(grep -c 'session close' "$BATS_TEST_TMPDIR/it2.log")" -eq 1 ]
  grep -qx 'teammate 57 agent_id=m@session-aaaa1111 team=session-aaaa1111 reason=orphan-close-failed rc=124' "$BATS_TEST_TMPDIR/pcq.log" \
    || { cat "$BATS_TEST_TMPDIR/pcq.log" "$TOPC_LOG" 2>/dev/null; false; }
}

@test "6 no queue lib: the log says the failure was NOT queued, and the closer still exits 0" {
  approve 57
  CC_PCQ_LIB="$BATS_TEST_TMPDIR/absent.sh" CLOSE_RC=1 closer
  [ "$status" -eq 0 ]
  grep -q 'NOT queued' "$TOPC_LOG" || { cat "$TOPC_LOG"; false; }
}
