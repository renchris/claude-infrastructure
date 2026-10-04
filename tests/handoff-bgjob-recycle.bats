#!/usr/bin/env bats
# A Claude Code BACKGROUND JOB recycles and self-closes through handoff-fire.sh (hf_bgjob_*).
#
# THE INCIDENT (2026-10-03, job 032aa97f on next4). A job has no pane: its daemon strips
# KITTY_WINDOW_ID/ITERM_SESSION_ID, so `--recycle` refused with "needs $ITERM_SESSION_ID…" and the
# agent could only ask the operator to /clear and paste. The job's mark is CLAUDE_JOB_DIR (measured:
# a job's tool env carries it and NOT CLAUDE_CODE_SESSION_KIND). The rail now starts a successor job
# with the job's own cwd/account/flags and the brief as its prompt, and stops the job from a detached
# process. Proven live in docs/research/bgjob-recycle-2026-10-03/probe-transcript.txt; this suite pins
# the decisions against a stub `claude` (HF_BGJOB_CLAUDE_BIN) that prints what the real one does —
# including the SGR-wrapped id a job's FORCE_COLOR=3 produces, which the first live probe misread.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_UNDER_TEST:-$REPO/scripts/handoff-fire.sh}"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/cc-registry" "$HOME/.claude/cc-fired"
  export CC_FIRED_DIR="$HOME/.claude/cc-fired"
  export CC_TERM_KITTY="$HOME/.claude/bin/no-such-kitty"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-such-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_HANDOFF_ALARM_DIR="$HOME/.claude/handoff-alarms"
  export CC_NOTIFY_BIN="$HOME/.claude/bin/cc-notify"
  printf '#!/bin/bash\nexit 0\n' > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"
  printf '#!/bin/bash\nexit 0\n' > "$HOME/.claude/bin/it2"; chmod +x "$HOME/.claude/bin/it2"

  # The job: <cfg>/jobs/<short>/state.json, shaped like the incident's (respawnFlags verbatim in kind).
  export CFG="$BATS_TEST_TMPDIR/.claude-quaternary"
  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"
  ( cd "$WORK" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
  export JOB="$CFG/jobs/abcd1234"; mkdir -p "$JOB"
  jq -n --arg cwd "$WORK" '{state:"working", sessionId:"abcd1234-0000-4000-8000-000000000000",
      resumeSessionId:"feed0000-0000-4000-8000-000000000000", cwd:$cwd, name:"bottle review",
      daemonShort:"abcd1234",
      respawnFlags:["--reply-on-resume","--settings","{\"autoMemoryDirectory\":\"/m\"}","--effort","high",
                    "--permission-mode","auto","--model","claude-opus-5-5","--name","old name"]}' > "$JOB/state.json"

  # The stub claude: logs argv (NUL-separated, so the prompt is checked byte-for-byte) and env.
  export STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  cat > "$STUB/claude" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB/calls.log"
case "$1" in
  --bg)
    printf '%s\0' "$@" > "$STUB/bg.argv"; env > "$STUB/bg.env"; pwd > "$STUB/bg.cwd"
    [ "${STUB_BG_FAIL:-0}" = 1 ] && { echo "Workspace not trusted."; exit 1; }
    mkdir -p "$CLAUDE_CONFIG_DIR/jobs/cafe0001"
    printf '{"sessionId":"cafe0001-0000-4000-8000-000000000001","state":"working"}\n' > "$CLAUDE_CONFIG_DIR/jobs/cafe0001/state.json"
    printf 'backgrounded · \033[36mcafe0001\033[39m · x\n'; exit 0 ;;
  stop) echo "stopped $2"; echo "$2" >> "$STUB/stopped"; exit 0 ;;
  agents)
    pid=4242; grep -qx abcd1234 "$STUB/stopped" 2>/dev/null && [ "${STUB_STOP_STICKS:-0}" = 0 ] && pid=null
    printf '[{"id":"abcd1234","state":"done","pid":%s},{"id":"cafe0001","state":"working","pid":5151}]\n' "$pid"; exit 0 ;;
esac
exit 0
SH
  chmod +x "$STUB/claude"
  export HF_BGJOB_CLAUDE_BIN="$STUB/claude" HF_BGJOB_STOP_GRACE_S=0 HF_BGJOB_STOP_PROOF_S=3
  PF="$BATS_TEST_TMPDIR/brief.txt"; printf 'Continue the bottle review.\nLine two of the brief.\n' > "$PF"
}

# Inside the job: no pane address, the job's own env marks, agent view OFF in the env (as some panes have).
injob() {
  run env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u CC_TERM -u CLAUDE_CODE_SESSION_KIND \
      CLAUDE_JOB_DIR="$JOB" CLAUDE_CODE_SESSION_ID=feed0000-0000-4000-8000-000000000000 \
      CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_DISABLE_AGENT_VIEW=1 \
      /bin/bash -c 'cd "$1" || exit 99; shift; exec /bin/bash "$@"' _ "$WORK" "$HF" "$@"
}
await_stop() { local n=0; until [ -s "$STUB/stopped" ] || [ "$n" -ge 100 ]; do /bin/sleep 0.1; n=$((n + 1)); done; }
bg_argv() { tr '\0' '\n' < "$STUB/bg.argv"; }

@test "--recycle in a background job starts a successor JOB with the job's own flags and the brief, then stops the job" {
  injob --recycle --prompt-file "$PF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"successor job cafe0001 is up"* ]] || { echo "$output"; false; }   # id read THROUGH the SGR codes
  # flags: the job's own, minus --reply-on-resume and its old --name; the name passed once
  run bg_argv
  [[ "$output" == *$'--settings\n{"autoMemoryDirectory":"/m"}'* ]] || { echo "$output"; false; }
  [[ "$output" == *$'--effort\nhigh'* ]] && [[ "$output" == *$'--permission-mode\nauto'* ]] && [[ "$output" == *$'--model\nclaude-opus-5-5'* ]]
  [[ "$output" != *"--reply-on-resume"* ]] && [[ "$output" != *"old name"* ]]
  [[ "$output" == *$'--name\nbottle review'* ]] || { echo "$output"; false; }
  # the prompt is the brief, byte for byte (last argv element)
  [ "$(tr '\0' '\n' < "$STUB/bg.argv" | tail -n 2)" = "$(cat "$PF")" ]
  # same cwd and account, outside this job's identity, agent view re-enabled for the CLI call
  [ "$(cat "$STUB/bg.cwd")" = "$(cd "$WORK" && pwd -P)" ] || [ "$(cat "$STUB/bg.cwd")" = "$WORK" ]
  grep -qx "CLAUDE_CONFIG_DIR=$CFG" "$STUB/bg.env"
  ! grep -q '^CLAUDE_JOB_DIR=' "$STUB/bg.env"
  ! grep -q '^CLAUDE_CODE_DISABLE_AGENT_VIEW=' "$STUB/bg.env"
  ! grep -q '^CLAUDE_CODE_SESSION_ID=' "$STUB/bg.env"
  # and THIS job is stopped by the detached stopper, proven by the roster's null worker pid
  await_stop
  grep -qx abcd1234 "$STUB/stopped"
  local n=0; until grep -q '"recycle-bgjob-stopped"' "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null || [ "$n" -ge 50 ]; do /bin/sleep 0.1; n=$((n + 1)); done
  grep -q '"recycle-bgjob-launched"' "$HOME/.claude/logs/handoffs.jsonl"
  grep -q '"recycle-bgjob-stopped"' "$HOME/.claude/logs/handoffs.jsonl"
}

@test "--model / --effort passed to the fire override the job's own" {
  injob --recycle --prompt-file "$PF" --model claude-sonnet-5-5 --effort medium
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bg_argv
  [[ "$output" == *$'--model\nclaude-sonnet-5-5'* ]] && [[ "$output" == *$'--effort\nmedium'* ]]
  [[ "$output" != *"claude-opus-5-5"* ]] && [[ "$output" != *$'--effort\nhigh'* ]]
}

@test "--dry-run launches nothing and stops nothing" {
  injob --recycle --prompt-file "$PF" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"dry run (background-job recycle)"* ]] || { echo "$output"; false; }
  [ ! -e "$STUB/calls.log" ]
}

@test "a successor that cannot be CONFIRMED stops NOTHING — the job keeps running" {
  STUB_BG_FAIL=1 injob --recycle --prompt-file "$PF"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"no successor job could be CONFIRMED"* ]] || { echo "$output"; false; }
  /bin/sleep 0.5
  [ ! -e "$STUB/stopped" ]
  ! grep -q '^stop ' "$STUB/calls.log"
}

@test "a stop the roster does not confirm is LOUD: stop-failed row and an alarm, never a quiet success" {
  STUB_STOP_STICKS=1 injob --recycle --prompt-file "$PF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local n=0; until grep -q '"recycle-bgjob-stop-failed"' "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null || [ "$n" -ge 100 ]; do /bin/sleep 0.1; n=$((n + 1)); done
  grep -q '"recycle-bgjob-stop-failed"' "$HOME/.claude/logs/handoffs.jsonl"
  ! grep -q '"recycle-bgjob-stopped"' "$HOME/.claude/logs/handoffs.jsonl"
}

@test "--worktree and a foreign --account are refused before anything starts" {
  injob --recycle --prompt-file "$PF" --worktree feat/x
  [ "$status" -eq 2 ] && [[ "$output" == *"pass --cwd"* ]] || { echo "$output"; false; }
  injob --recycle --prompt-file "$PF" --account next2
  [ "$status" -eq 2 ] && [[ "$output" == *"recycles on the account it lives on"* ]] || { echo "$output"; false; }
  [ ! -e "$STUB/calls.log" ]
}

@test "KILL SWITCH: HF_BGJOB=off brings back the pane refusal (nothing launched)" {
  HF_BGJOB=off injob --recycle --prompt-file "$PF"
  [ "$status" -ne 0 ]
  [[ "$output" == *'needs $ITERM_SESSION_ID'* ]] || { echo "$output"; false; }
  [ ! -e "$STUB/calls.log" ]
}

@test "CONTROL: the same command with NO job dir never takes the job path" {
  run env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u CC_TERM -u CLAUDE_JOB_DIR \
      /bin/bash -c 'cd "$1" && exec /bin/bash "$2" --recycle --prompt-file "$3"' _ "$WORK" "$HF" "$PF"
  [[ "$output" != *"BACKGROUND JOB"* ]] || { echo "$output"; false; }
  [ ! -e "$STUB/calls.log" ]
}

# ── self-close ──────────────────────────────────────────────────────────────────────────────────
@test "self-close in a background job: bare is refused, --terminal stops the job" {
  injob self-close
  [ "$status" -eq 2 ] && [[ "$output" == *"name what continues"* ]] || { echo "$output"; false; }
  [ ! -e "$STUB/calls.log" ]
  injob self-close --terminal
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"background job abcd1234 STOPS"* ]] || { echo "$output"; false; }
  await_stop
  grep -qx abcd1234 "$STUB/stopped"
}

@test "self-close in a background job refuses a dirty tree and a successor that is not a live job" {
  : > "$WORK/untracked.txt"
  injob self-close --terminal
  [ "$status" -eq 2 ] && [[ "$output" == *"the tree is dirty"* ]] || { echo "$output"; false; }
  rm -f "$WORK/untracked.txt"
  injob self-close --successor deadbeef
  [ "$status" -eq 2 ] && [[ "$output" == *"is not a live background job"* ]] || { echo "$output"; false; }
  /bin/sleep 0.3
  [ ! -e "$STUB/stopped" ]
}
