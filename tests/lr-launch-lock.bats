#!/usr/bin/env bats
# lr-fire-resume.sh — W2c: the launch lock, the H(sid) holder re-check, and the git lock.
#
# THE DEFECT CLASS. The tombstone guard refuses a sid that was TRANSPLANTED away; nothing refused a
# sid that is simply still OPEN — a live claude holding it, or a second launcher racing the first.
# Either way the session runs twice and both copies write one transcript. The contract (plan Phase 0):
# a `mkdir` lock per sid whose holder is re-taken only when it is ours or stale (rc 10 otherwise), then
# a census of live holders from ps, the registry and the account session files (rc 11 on any), then,
# after the spawn, the holder handed to the spawned claude's pid.
#
# Each case runs the WHOLE script with stubs, because what matters is where the guard sits: after
# every cheap validation and immediately before the spawn. FIRE may point at another copy of the
# script (the red-proof run against the pre-change file).

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIRE="${FIRE:-$REPO/scripts/limit-recover/lr-fire-resume.sh}"
  [ -f "$FIRE" ] || skip "lr-fire-resume.sh not found"
  command -v expect >/dev/null || skip "expect(1) not installed"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfgdir"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_ADMIT_GATE=off LR_PRESEED_DONE=bats LR_QUIET_S=1
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state" LR_RUN_DIR="$BATS_TEST_TMPDIR/run"
  export LR_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry" LR_CFG_DIRS="$BATS_TEST_TMPDIR/cfgs"
  mkdir -p "$LR_REGISTRY_DIR" "$LR_CFG_DIRS/sessions"
  unset LR_RUN LR_RECORD_ID LR_ATTEMPT LR_SUBMIT_TOKEN LR_ADMIT_TOKEN CC_PANE_ID ITERM_SESSION_ID \
        LR_LAUNCH_LOCK LR_LAUNCH_GUARD LR_RECR_SCHEDULE LR_PS_BIN
  ACCT="$BATS_TEST_TMPDIR/acct"; WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$ACCT"
  # Unique on this box, so the ps census can only ever find the processes this file starts.
  SID="b2c0ffee-ll-$$-$RANDOM"
  LOCK="$LR_STATE_DIR/locks/$SID.launch"
  TRIP="$BATS_TEST_TMPDIR/tripwire"   # the real claude must never run (see the noprompt suite)
  printf '#!/bin/bash\necho TRIPPED >> "%s.hit"\nexit 97\n' "$TRIP" > "$TRIP"; chmod +x "$TRIP"
  export CC_CLAUDE_BIN="$TRIP"
  STUB="$BATS_TEST_TMPDIR/claude-stub"; export STUB_OUT="$BATS_TEST_TMPDIR/out"
  printf '#!/bin/bash\necho $$ > "$STUB_OUT.pid"\nprintf "booted\\r\\n"\nsleep 2\n' > "$STUB"
  chmod +x "$STUB"
  export LR_CLAUDE_BIN="$STUB"
  BG_PIDS=""
}

teardown() {
  local p
  for p in $BG_PIDS; do pkill -P "$p" 2>/dev/null || true; kill "$p" 2>/dev/null || true; done
}

fire() { mkdir -p "$WT"; bash "$FIRE" "$ACCT" "$WT" "$SID" --model m --effort high --no-prompt "$@" </dev/null; }
lstart() { TZ=UTC LC_ALL=C ps -o lstart= -p "$1" | tr -s ' ' | sed 's/^ //;s/ $//'; }
holder() { # $1=dir $2=pid $3=record → a holder file in the contract shape
  mkdir -p "$1"
  jq -cn --arg r "$3" --argjson pid "$2" --arg l "$(lstart "$2" 2>/dev/null)" \
    '{record_id:$r,attempt:"1",role:"lr-fire-resume",pid:$pid,lstart:$l,at:"2026-09-29T00:00:00Z"}' > "$1/holder"
}
dead_pid() { sh -c 'echo $$' ; }

@test "refused, rc 10, when the launch lock is held by a live foreign process" {
  sleep 30 & BG_PIDS="$BG_PIDS $!"
  holder "$LOCK" "$!" "someone-else"
  LR_RECORD_ID=me LR_ATTEMPT=1 run fire
  [ "$status" -eq 10 ] || { echo "rc=$status"; echo "$output"; false; }
  [[ "$output" == *"REFUSED — launch lock held by pid $!"* ]] || { echo "$output"; false; }
  [ "$(cat "$LR_RUN_DIR/relaunch.rc")" = 10 ]
  [ ! -e "$STUB_OUT.pid" ] || { echo "the stub was spawned over a held lock"; false; }
}

@test "refused, rc 11, when a live process named claude holds --resume <sid>" {
  # A process whose OWN argv[0] is claude (exec -a), not a shell script: a shebang stub would show as
  # `/bin/bash …/claude`, which the census rightly ignores as a shell string.
  bash -c "exec -a '$BATS_TEST_TMPDIR/claude' /bin/bash -c 'sleep 30; :' x --resume $SID" &
  BG_PIDS="$BG_PIDS $!"
  sleep 0.3
  run fire
  [ "$status" -eq 11 ] || { echo "rc=$status"; echo "$output"; false; }
  [[ "$output" == *"pid $! (process: --resume $SID)"* ]] || { echo "$output"; false; }
  [ "$(cat "$LR_RUN_DIR/relaunch.rc")" = 11 ]
  [ ! -e "$STUB_OUT.pid" ] || { echo "the stub was spawned over a live holder"; false; }
}

@test "refused, rc 11, when a registry row or an account session file names a live pid for the sid" {
  sleep 30 & BG_PIDS="$BG_PIDS $!"
  jq -cn --arg s "$SID" --argjson p "$!" --arg l "$(lstart "$!")" '{session_id:$s,pid:$p,lstart:$l}' \
    > "$LR_REGISTRY_DIR/row.json"
  printf 'not json' > "$LR_REGISTRY_DIR/broken.json"   # fail-open per file: skipped, never fatal
  run fire
  [ "$status" -eq 11 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"(registry: "* ]] || { echo "rc=$status $output"; false; }
  rm -f "$LR_REGISTRY_DIR/row.json"
  jq -cn --arg s "$SID" --argjson p "$!" '{sessionId:$s,pid:$p}' > "$LR_CFG_DIRS/sessions/1.json"
  rm -rf "$LOCK" "$LR_RUN_DIR"
  run fire
  [ "$status" -eq 11 ] && [[ "$output" == *"(sessions: "* ]] || { echo "rc=$status $output"; false; }
}

@test "after the spawn the lock holder is the spawned claude's pid" {
  run fire
  [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output"; false; }
  [ -s "$STUB_OUT.pid" ] || { echo "the stub never ran"; false; }
  [ "$(jq -r .pid "$LOCK/holder")" = "$(cat "$STUB_OUT.pid")" ] \
    || { echo "holder: $(cat "$LOCK/holder") stub pid: $(cat "$STUB_OUT.pid")"; false; }
  [ "$(jq -r .role "$LOCK/holder")" = claude ]
}

@test "a dead holder is stolen and the run proceeds" {
  holder "$LOCK" "$(dead_pid)" "someone-else"
  LR_RECORD_ID=me run fire
  [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output"; false; }
  [ "$(jq -r .pid "$LOCK/holder")" = "$(cat "$STUB_OUT.pid")" ]
}

@test "a holder with the same record and attempt is ours, and is re-taken" {
  sleep 30 & BG_PIDS="$BG_PIDS $!"
  holder "$LOCK" "$!" "rec-7"
  LR_RECORD_ID=rec-7 LR_ATTEMPT=1 run fire
  [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output"; false; }
  [ "$(jq -r .record_id "$LOCK/holder")" = rec-7 ]
}

@test "LR_LAUNCH_GUARD=off skips the lock AND the holder re-check, with one stderr line" {
  sleep 30 & BG_PIDS="$BG_PIDS $!"
  holder "$LOCK" "$!" "someone-else"
  bash -c "exec -a '$BATS_TEST_TMPDIR/claude' /bin/bash -c 'sleep 30; :' x --resume $SID" &
  BG_PIDS="$BG_PIDS $!"
  sleep 0.3
  LR_LAUNCH_GUARD=off run fire
  [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'LR_LAUNCH_GUARD=off')" = 1 ] || { echo "$output"; false; }
  [ -s "$STUB_OUT.pid" ]
  [ "$(jq -r .role "$LOCK/holder")" = lr-fire-resume ] || { echo "the handover ran with the guard off"; false; }
}

# ── the git lock around `worktree add` ───────────────────────────────────────────────────────────────
git_repo() {
  GR="$BATS_TEST_TMPDIR/repo"
  git init -q "$GR"; git -C "$GR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$GR" branch br
  GLOCK="$LR_STATE_DIR/locks/git-$(printf '%s' "$(git -C "$GR" rev-parse --path-format=absolute --git-common-dir)" | shasum | cut -c1-40)"
}

@test "the file no longer prunes worktrees" {
  run grep -c 'worktree prune' "$FIRE"
  [ "$output" = 0 ] || { echo "still present: $output"; false; }
}

@test "a stale git-lock holder is stolen, the worktree is recreated, and the lock is released" {
  git_repo
  holder "$GLOCK" "$(dead_pid)" "someone-else"
  run bash "$FIRE" "$ACCT" "$WT" "$SID" --model m --effort high --no-prompt --branch br --repo "$GR" </dev/null
  [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output"; false; }
  [[ "$output" == *"stealing a stale git lock"* ]] || { echo "$output"; false; }
  [ -d "$WT" ] && [ ! -e "$GLOCK" ]
}

@test "a live git-lock holder times out after LR_GIT_LOCK_WAIT_S, rc 2" {
  git_repo
  sleep 30 & BG_PIDS="$BG_PIDS $!"
  holder "$GLOCK" "$!" "someone-else"
  LR_GIT_LOCK_WAIT_S=1 run bash "$FIRE" "$ACCT" "$WT" "$SID" --model m --effort high --no-prompt --branch br --repo "$GR" </dev/null
  [ "$status" -eq 2 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"git lock"*"still held"* ]] || { echo "rc=$status $output"; false; }
  [ ! -d "$WT" ]
}

@test "a missing-but-registered worktree is re-added with -f when the branch lives nowhere else" {
  git_repo
  git -C "$GR" worktree add -q "$WT" br
  rm -rf "$WT"
  run bash "$FIRE" "$ACCT" "$WT" "$SID" --model m --effort high --no-prompt --branch br --repo "$GR" </dev/null
  [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output"; false; }
  [[ "$output" == *"re-adding it with -f"* ]] || { echo "$output"; false; }
  [ -d "$WT" ]
}
