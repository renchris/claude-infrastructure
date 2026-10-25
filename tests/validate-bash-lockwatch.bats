#!/usr/bin/env bats
# hooks/validate-bash.sh LOCKWATCH guards (incident 2026-10-25, DESIGN.md C5):
#   (a) `kitten @` / `kitty @`, by any path, refused while lockwatch says kitty RC is dead and hb is fresh
#   (b) kill guard: SIGKILL of a pty session leader by pid is logged (observe) and refused once armed
#   (c) goal-loop guard: the 6th identical command in 10 min after 5 real failures is refused
# Hermetic: HOME, the lockwatch dir and the bash-execution log are fixtures.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home" CC_LOCKWATCH_DIR="$D/lw" CC_VB_DECISION_LOG="$D/decisions.jsonl"
  export CC_SHARED_CHECKOUT="$D/shared" CC_BASH_EXEC_LOG="$D/bash-execution.log"
  mkdir -p "$HOME" "$D/lw" "$D/shared"
  unset VALIDATE_BASH_LEGACY VALIDATE_BASH_DISABLED CC_KITTY_RC_BREAKER CC_KILLGUARD CC_GOAL_LOOP_GUARD KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  KG="$D/lw/kill-guard.jsonl"
}

probe() { # <command> [session id]
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" "{tool_name:\"Bash\", tool_input:{command:\$c}, session_id:\$s}" | /bin/bash "$0"' \
    "$HOOK" "$1" "${2:-sid-lw}"
}
decision() { [ -n "$output" ] && printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none; }
reason() { printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }
hb_fresh() { printf '1 tick 0 0 1 boot\n' > "$D/lw/hb"; }
hb_stale() { hb_fresh; touch -t 202601010000 "$D/lw/hb"; }
rc_state() { printf '{"v":1,"kitty_rc":"%s","level":2}\n' "$1" > "$D/lw/state.json"; }
leader() { printf '{"leaders":[{"pid":%s,"pgid":%s,"lstart":"Sun Oct 25 03:03:28 2026","tdev":"16/63","ppid":1,"state":"E"}]}\n' "$1" "$1" > "$D/lw/pty.json"; }
arm() { printf '{"pass_killguard":true,"pass_band":true,"pass_gate":false}\n' > "$D/lw/shadow-audit.json"; }

@test "(a) the absolute-path kitten @ ls is refused under a fresh dead verdict" {
  rc_state dead; hb_fresh
  probe '/Applications/kitty.app/Contents/MacOS/kitten @ ls'
  [ "$(decision)" = deny ]
  [[ "$(reason)" == *"kitty remote control is DEAD"* ]] || false
  probe 'kitty @ --to unix:/tmp/kitty-1 ls | jq length'
  [ "$(decision)" = deny ]
}

@test "(a) kitten @ is allowed under a stale hb, an ok verdict, a quoted mention, or the kill switch" {
  rc_state dead; hb_stale
  probe 'kitten @ ls'
  [ "$(decision)" = none ]
  rc_state ok; hb_fresh
  probe 'kitten @ ls'
  [ "$(decision)" = none ]
  rc_state dead; hb_fresh
  probe "grep -n 'kitten @ ls' notes.md"
  [ "$(decision)" = none ]
  CC_KITTY_RC_BREAKER=off probe 'kitten @ ls'
  [ "$(decision)" = none ]
}

@test "(b) a leader kill-by-pid is LOGGED in observe, with the unpoison cure, and not refused" {
  leader 68298; hb_fresh
  probe 'kill -KILL 94459 68298'
  [ "$(decision)" = none ]
  [ "$(wc -l < "$KG" | tr -d ' ')" -eq 1 ]
  jq -e '.pid == 68298 and .decision == "observe" and .armed == false and .sid == "sid-lw"
         and (.suggest | contains("rescue.sh unpoison 68298")) and (.ts | test("Z$"))' "$KG"
}

@test "(b) armed (pass_killguard + pass_band, hb fresh): refused; the pgid form and other pids pass" {
  leader 68298; hb_fresh; arm
  probe 'kill -KILL 94459 68298'
  [ "$(decision)" = deny ]
  [[ "$(reason)" == *"pty SESSION LEADER by pid"*"rescue.sh unpoison 68298"* ]] || false
  probe 'sleep 1 && kill -s KILL 68298'
  [ "$(decision)" = deny ]
  probe 'kill -KILL -- -68298'
  [ "$(decision)" = none ]
  probe 'kill -9 12345'
  [ "$(decision)" = none ]
  probe 'kill -TERM 68298'
  [ "$(decision)" = none ]
  CC_KILLGUARD=observe probe 'kill -9 68298'
  [ "$(decision)" = none ]
  jq -se 'map(.decision) == ["refuse", "refuse", "observe"]' "$KG"
}

@test "(b) armed but hb stale (pty.json may be old): logged, not refused; kill switch logs nothing" {
  leader 68298; hb_stale; arm
  probe 'kill -9 68298'
  [ "$(decision)" = none ]
  jq -e '.decision == "observe" and .hb_fresh == false' "$KG"
  rm -f "$KG"
  CC_KILLGUARD=off probe 'kill -9 68298'
  [ ! -e "$KG" ]
}

@test "(b) pkill -9 is resolved through pgrep and caught when it reaches a leader" {
  /bin/sleep 3071 & SP=$!
  leader "$SP"; hb_fresh; arm
  probe 'pkill -9 -f "sleep 3071"'
  kill "$SP" 2>/dev/null || true
  [ "$(decision)" = deny ]
  jq -e --argjson p "$SP" '.pid == $p and .decision == "refuse"' "$KG"
}

# exec_log <sid> <code> <command> — one bash-execution.log entry, as hooks/log-bash.sh writes it
exec_log() { printf '[%s] [%s] %s | Exit: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$3" "$2" >> "$CC_BASH_EXEC_LOG"; }

@test "(c) the goal-loop guard fires on the 6th identical command after 5 real failures" {
  C=$'curl -s http://127.0.0.1:9/x\necho second line'
  for i in 1 2 3 4 5; do
    probe "$C" sid-loop
    [ "$(decision)" = none ]
    exec_log sid-loop 7 "$C"
  done
  probe "$C" sid-loop
  [ "$(decision)" = deny ]
  [[ "$(reason)" == *"goal-loop guard"*"last 5 runs of it all FAILED"* ]] || false
  probe "$C" sid-other
  [ "$(decision)" = none ]
  CC_GOAL_LOOP_GUARD=off probe "$C" sid-loop
  [ "$(decision)" = none ]
}

@test "(c) not after a success among the last 5, and not for a merely repeated command" {
  for i in 1 2 3 4 5; do
    probe 'make test' sid-mix; exec_log sid-mix "$([ "$i" = 3 ] && echo 0 || echo 2)" 'make test'
  done
  probe 'make test' sid-mix
  [ "$(decision)" = none ]
  for i in 1 2 3 4 5 6 7; do probe 'git status' sid-ok; exec_log sid-ok 0 'git status'; done
  probe 'git status' sid-ok
  [ "$(decision)" = none ]
}
