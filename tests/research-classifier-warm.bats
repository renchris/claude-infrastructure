#!/usr/bin/env bats
# research-classifier-warm — the re-ask router's resident classifier (decision 4bf73c4e55d5 option 3;
# wave E1c of docs/plans/RESEARCH_PROGRAM_BUILD.md): the daemon, its launchd runner under /bin/bash
# 3.2, the staged plist, migration 0059, and router.py's use of it. The classifier process is a stub
# (CC_RESEARCH_WARM_CHILD); nothing here starts `claude`.
#
# Wave E1f replays the 2026-10-05 incident in three places below (`logged_out`): a daemon whose
# processes are ALIVE and answer every prompt "Not logged in". The router must make the cold call,
# the runner must serve under an account that answers or not at all, and `ping` must not say ready.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_ROUTER CC_RESEARCH_ROUTER_INNER CC_RESEARCH_WARM
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WARM="$REPO/scripts/research-kit/classifier-warm.py"
  RUNNER="$REPO/scripts/research-kit/jobs/classifier-warm.sh"
  ROUTER="$REPO/scripts/research-kit/router.py"
  MIG="$REPO/migrations/0059-research-classifier-warm.sh"
  PLIST="$REPO/launchd/staged/com.claude.research-classifier-warm.plist"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/rh" CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/rh/programs.json"
  # A unix socket path is capped near 100 bytes, and BATS_TEST_TMPDIR is longer than that.
  SOCKD="$(mktemp -d /tmp/ccw.XXXXXX)"
  export CC_RESEARCH_WARM_SOCK="$SOCKD/sock"
  SEEN="$BATS_TEST_TMPDIR/seen"; mkdir -p "$SEEN"
  DPID=""
}

teardown() {
  if [ -n "$DPID" ]; then kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; fi
  rm -rf "$SOCKD"
}

# child <label> — a stand-in classifier process: logs the one line it is given, answers <label>,
# then stays alive the way a real process would until the daemon ends it.
child() {
  printf 'read -r line; printf "%%s\\n" "$line" >> "%s/$$"; echo "{\\"type\\":\\"system\\"}"; echo "{\\"type\\":\\"result\\",\\"result\\":\\"%s\\"}"; sleep 30' "$SEEN" "$1"
}

# logged_out — the incident's process: alive, takes its one prompt, and answers the way a `claude`
# with no login does (an error result), then stays alive until the daemon ends it.
logged_out() {
  printf 'read -r line; echo "{\\"type\\":\\"result\\",\\"is_error\\":true,\\"result\\":\\"Not logged in · Please run /login\\"}"; sleep 30'
}

# serve <child command> [up] — start the daemon and wait until `ping` says a worker has ANSWERED
# (exit 0); with `up`, only until the daemon is on its socket (exit 0 or 2), for stubs that never
# answer. A caller that needs a failing daemon to stay up sets CC_RESEARCH_WARM_CANARY_RETRY high.
serve() {
  CC_RESEARCH_WARM_CHILD="$1" /usr/bin/python3 "$WARM" serve 2>"$BATS_TEST_TMPDIR/serve.err" &
  DPID=$!
  local i rc
  for i in $(seq 1 100); do
    rc=0; /usr/bin/python3 "$WARM" ping >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$rc" -eq 2 ] && [ "${2:-}" = up ] && return 0
    sleep 0.1
  done
  return 1
}

# exited — wait up to 30 s for the background process $DPID to end on its own, and leave its exit
# status in $rc. A process that never ends fails the test here instead of hanging it.
exited() {
  local i
  for i in $(seq 1 300); do kill -0 "$DPID" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$DPID" 2>/dev/null; then echo "process $DPID is still running after 30 s"; return 1; fi
  rc=0; wait "$DPID" || rc=$?
  DPID=""
}

@test "/bin/bash is 3.2, the interpreter launchd uses" {
  run /bin/bash --version
  [[ "$output" == *"version 3.2."* ]]
}

@test "the runner, under /bin/bash 3.2, execs the daemon's serve verb and takes no arguments" {
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "%s"\n' "$BATS_TEST_TMPDIR/args" > "$BATS_TEST_TMPDIR/py"
  chmod +x "$BATS_TEST_TMPDIR/py"
  accounts "a 1"
  CC_RESEARCH_PYTHON="$BATS_TEST_TMPDIR/py" run /bin/bash "$RUNNER"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/args")" = "$REPO/scripts/research-kit/jobs/../classifier-warm.py" ]
  [ "$(sed -n 2p "$BATS_TEST_TMPDIR/args")" = serve ]
  CC_RESEARCH_PYTHON="$BATS_TEST_TMPDIR/py" run /bin/bash "$RUNNER" extra
  [ "$status" -eq 2 ]
  CC_RESEARCH_WARM_DAEMON="$BATS_TEST_TMPDIR/absent.py" run /bin/bash "$RUNNER"
  [ "$status" -eq 1 ]
}

@test "the daemon answers a ping within 1 s and a prompt through a process started ahead of it" {
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 1 ]
  serve "$(child pushback)"
  start="$(/usr/bin/python3 -c 'import time; print(time.time())')"
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 0 ]
  [[ "$output" == "ready "* ]] || false
  /usr/bin/python3 -c "import sys, time; sys.exit(0 if time.time() - $start < 1.0 else 1)"
  run bash -c "printf 'label this' | /usr/bin/python3 '$WARM' ask"
  [ "$status" -eq 0 ]
  [ "$output" = pushback ]
  # the socket is the operator's alone
  [ "$(stat -f '%Lp' "$CC_RESEARCH_WARM_SOCK")" = 600 ]
}

@test "a process labels ONE prompt and is ended, so no prompt shares a context with another" {
  serve "$(child other)"
  for i in 1 2 3; do
    run bash -c "printf 'prompt number $i' | /usr/bin/python3 '$WARM' ask"
    [ "$status" -eq 0 ]
  done
  # three prompts, three processes, one line each (the daemon's own readiness round-trip is a
  # fourth process with its own one line)
  [ "$(cat "$SEEN"/* | grep -vc 'is the classifier answering')" -eq 3 ]
  for f in "$SEEN"/*; do [ "$(wc -l < "$f" | tr -d ' ')" -eq 1 ]; done
  [ "$(cat "$SEEN"/* | grep -c 'prompt number')" -eq 3 ]
}

@test "with no process ready the daemon declines at once (exit 3: make the cold call), it does not guess" {
  serve "exit 0" up
  start="$(/usr/bin/python3 -c 'import time; print(time.time())')"
  run bash -c "printf 'label this' | /usr/bin/python3 '$WARM' ask"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no warm classifier process is ready"* ]] || false
  /usr/bin/python3 -c "import sys, time; sys.exit(0 if time.time() - $start < 2.0 else 1)"
}

@test "a process that took the prompt and never answers fails at the deadline (exit 1), not as a decline" {
  serve "read -r line; sleep 30" up
  run bash -c "printf 'label this' | /usr/bin/python3 '$WARM' ask --timeout 1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not answer in 1 s"* ]]
}

@test "a second daemon on the same socket stands down, and SIGTERM removes the socket" {
  serve "$(child other)"
  CC_RESEARCH_WARM_CHILD="$(child other)" run /usr/bin/python3 "$WARM" serve
  [ "$status" -eq 0 ]
  [[ "$output" == *"already answers"* ]] || false
  kill "$DPID"; wait "$DPID" 2>/dev/null || true; DPID=""
  [ ! -e "$CC_RESEARCH_WARM_SOCK" ]
}

# ── readiness (wave E1f) ────────────────────────────────────────────────────────────────────────

@test "E1f ping: a daemon whose processes are alive but logged out is NOT ready (exit 2), and says why" {
  CC_RESEARCH_WARM_CANARY_RETRY=30 serve "$(logged_out)" up
  # the incident's reading: two live processes, which the old ping reported as "ready 2", exit 0
  for i in $(seq 1 50); do
    /usr/bin/python3 "$WARM" ping 2>&1 | grep -q 'Not logged in' && break
    sleep 0.1
  done
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 2 ]
  [[ "$output" == *"no worker has answered"* ]] || false
  [[ "$output" == *"Not logged in"* ]] || false
  [[ "$output" != "ready "* ]] || false
  [ ! -e "$SOCKD/answered" ]
}

@test "E1f ping: ready means a worker answered a real classification, and the answer is stamped for cc-fleet" {
  serve "$(child pushback)"
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 0 ]
  [[ "$output" == "ready "* ]] || false
  # the round-trip carried the router's own brief, not a liveness byte
  grep -l 'is the classifier answering' "$SEEN"/* | head -1 | xargs grep -q 'Answer with exactly ONE of these labels'
  [ -s "$SOCKD/answered" ]
}

@test "E1f ping: a daemon that answered and then starts failing prompts stops being ready at once" {
  # answers the readiness round-trip, then is logged out for every later process
  flip="read -r line; if [ -e '$BATS_TEST_TMPDIR/out' ]; then echo '{\"type\":\"result\",\"is_error\":true,\"result\":\"Not logged in\"}'; else echo '{\"type\":\"result\",\"result\":\"other\"}'; fi; sleep 30"
  CC_RESEARCH_WARM_POOL=1 CC_RESEARCH_WARM_CANARY_RETRY=30 serve "$flip"
  for i in $(seq 1 50); do [ "$(/usr/bin/python3 "$WARM" ping 2>/dev/null)" = "ready 1" ] && break; sleep 0.1; done
  touch "$BATS_TEST_TMPDIR/out"
  # the one waiting process started before the login lapsed, but it reads the lapse at its prompt
  run bash -c "printf 'label this' | /usr/bin/python3 '$WARM' ask"
  [ "$status" -eq 1 ]
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 2 ]
}

@test "E1f daemon: three failed round-trips in a row and it exits 1 and removes its socket, so launchd restarts the runner" {
  CC_RESEARCH_WARM_CANARY_RETRY=0.1 serve "$(logged_out)" up
  exited
  [ "$rc" -eq 1 ]
  [ ! -e "$CC_RESEARCH_WARM_SOCK" ]
  grep -q 'exiting so the runner picks an account again' "$BATS_TEST_TMPDIR/serve.err"
}

@test "E1f probe: one classification through one process, exit 0 when it answers and 1 when it is logged out" {
  CC_RESEARCH_WARM_CHILD="$(child completeness)" run /usr/bin/python3 "$WARM" probe
  [ "$status" -eq 0 ]
  [ "$output" = answering ]
  CC_RESEARCH_WARM_CHILD="$(logged_out)" run /usr/bin/python3 "$WARM" probe
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not logged in"* ]] || false
  CC_RESEARCH_WARM_CHILD="read -r line; sleep 30" run /usr/bin/python3 "$WARM" probe --timeout 1
  [ "$status" -eq 1 ]
}

# ── the runner picks a logged-in account (wave E1f) ─────────────────────────────────────────────

# accounts <rank line>... — an account map of three accounts under $HOME, and a claude-accounts at
# the ABSOLUTE path the runner uses (launchd's PATH has no ~/bin), printing the given ranking.
accounts() {
  mkdir -p "$HOME/.claude" "$HOME/Development/claude-infrastructure/bin" "$HOME/.claude-a" "$HOME/.claude-b" "$HOME/.claude-c"
  printf '{"accounts":[{"name":"a","config_dir":"~/.claude-a"},{"name":"b","config_dir":"~/.claude-b"},{"name":"c","config_dir":"~/.claude-c"}]}\n' > "$HOME/.claude/accounts.json"
  {
    printf '#!/bin/bash\n[ "$1 $2" = "--rank general" ] || exit 2\necho "route-meta: acct=b cached=1"\n'
    for l in "$@"; do printf 'echo "%s"\n' "$l"; done
  } > "$HOME/Development/claude-infrastructure/bin/claude-accounts"
  chmod +x "$HOME/Development/claude-infrastructure/bin/claude-accounts"
}

# by_login — a classifier process that is logged in exactly when its config dir holds `login`, the
# way a real `claude` reads its login from CLAUDE_CONFIG_DIR (and from ~/.claude when that is unset,
# which is the incident), and only when USER names the user, which is where a real one looks its
# login up in the keychain. It logs the config dir it ran under.
by_login() {
  printf 'read -r line; d="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; echo "$d" >> "%s"; if [ -e "$d/login" ] && [ "${USER:-}" = "$(/usr/bin/id -un)" ]; then echo "{\\"type\\":\\"result\\",\\"result\\":\\"pushback\\"}"; else echo "{\\"type\\":\\"result\\",\\"is_error\\":true,\\"result\\":\\"Not logged in · Please run /login\\"}"; fi; sleep 30' "$BATS_TEST_TMPDIR/dirs"
}

# launchd_run — the runner exactly as launchd starts it: /bin/bash 3.2, HOME and PATH and nothing
# else (no CLAUDE_CONFIG_DIR), plus the test's seams. `exec`, so a backgrounded call's pid is the
# daemon's own and teardown ends it.
launchd_run() {
  exec env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    CC_RESEARCH_HOME="$CC_RESEARCH_HOME" CC_RESEARCH_WARM_SOCK="$CC_RESEARCH_WARM_SOCK" \
    CC_RESEARCH_WARM_CHILD="$(by_login)" "$@" /bin/bash "$RUNNER"
}

@test "E1f runner, as launchd starts it: serves under the best-ranked account that is logged in, and a prompt is answered" {
  accounts "b 0.9" "c 0.5" "a 0.1"
  touch "$HOME/.claude-c/login" "$HOME/.claude-a/login"      # b, the top of the ranking, is logged out
  launchd_run 2>"$BATS_TEST_TMPDIR/serve.err" &
  DPID=$!
  for i in $(seq 1 100); do /usr/bin/python3 "$WARM" ping >/dev/null 2>&1 && break; sleep 0.1; done
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 0 ]
  run bash -c "printf 'label this' | /usr/bin/python3 '$WARM' ask"
  [ "$status" -eq 0 ]
  [ "$output" = pushback ]
  # b was tried first and refused; everything after ran under c; ~/.claude and a were never used
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/dirs")" = "$HOME/.claude-b" ]
  [ "$(sed 1d "$BATS_TEST_TMPDIR/dirs" | sort -u)" = "$HOME/.claude-c" ]
  grep -q 'account b did not answer: .*Not logged in' "$BATS_TEST_TMPDIR/serve.err"
  grep -q 'account c answered a classification' "$BATS_TEST_TMPDIR/serve.err"
}

@test "E1f runner, as launchd starts it: with no account logged in it exits 1 and serves nothing" {
  accounts "b 0.9" "c 0.5" "a 0.1"
  touch "$HOME/.claude/login"        # a login in the default dir is not an account's and must not count
  launchd_run 2>"$BATS_TEST_TMPDIR/serve.err" &
  DPID=$!
  exited
  [ "$rc" -eq 1 ]
  grep -q 'no account is logged in and answering; not serving' "$BATS_TEST_TMPDIR/serve.err"
  [ ! -e "$CC_RESEARCH_WARM_SOCK" ]
  [ "$(sort -u "$BATS_TEST_TMPDIR/dirs" | wc -l | tr -d ' ')" -eq 3 ]
  ! grep -qx "$HOME/.claude" "$BATS_TEST_TMPDIR/dirs"
}

@test "E1f runner: with no ranking it still tries every account in the map's order, and a hung ranking is bounded" {
  accounts
  touch "$HOME/.claude-b/login"
  printf '#!/bin/bash\nsleep 30\n' > "$HOME/Development/claude-infrastructure/bin/claude-accounts"
  launchd_run CC_RESEARCH_WARM_RANK_WAIT=1 2>"$BATS_TEST_TMPDIR/serve.err" &
  DPID=$!
  for i in $(seq 1 100); do /usr/bin/python3 "$WARM" ping >/dev/null 2>&1 && break; sleep 0.1; done
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 0 ]
  grep -q 'no ranking from' "$BATS_TEST_TMPDIR/serve.err"
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/dirs")" = "$HOME/.claude-a" ]
  [ "$(sed 1d "$BATS_TEST_TMPDIR/dirs" | sort -u)" = "$HOME/.claude-b" ]
}

# ── router.py ───────────────────────────────────────────────────────────────────────────────────

# The cold classifier stub logs that it ran and answers work-order, so a warm label is told apart.
cold() { printf 'cat >/dev/null; echo ran >> "%s"; echo work-order' "$BATS_TEST_TMPDIR/cold-calls"; }

@test "router: no daemon means the cold call, exactly as before" {
  CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = work-order ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/cold-calls" | tr -d ' ')" -eq 1 ]
}

@test "router: a running daemon gives the label and the cold call is not made; the brief reaches it whole" {
  serve "$(child pushback)"
  CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = pushback ]
  [ ! -e "$BATS_TEST_TMPDIR/cold-calls" ]
  grep -q 'PROMPT:.*are we done?' "$SEEN"/*
  grep -q 'If two labels fit, answer the earlier one in this list' "$SEEN"/*
}

@test "E1f router: a daemon alive but logged out costs nothing — the cold call is made and its label stands" {
  CC_RESEARCH_WARM_CANARY_RETRY=30 serve "$(logged_out)" up
  CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = work-order ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/cold-calls" | tr -d ' ')" -eq 1 ]
}

@test "E1f router: a warm process that dies on its prompt falls through to the cold call too" {
  serve "read -r line; exit 1" up
  CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = work-order ]
}

@test "E1f router: after a warm failure only a COLD failure is a fallback, and it is reported as the cold call's" {
  CC_RESEARCH_WARM_CANARY_RETRY=30 serve "$(logged_out)" up
  CC_RESEARCH_CLASSIFIER="cat >/dev/null; exit 7" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 1 ]
}

@test "router: a daemon with no process ready falls back to the cold call inside the same limit" {
  serve "exit 0" up
  CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = work-order ]
}

@test "router: a warm answer that is not one route label is unavailable, never a label and never a second try" {
  serve "$(child 'I think this is completeness')"
  CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/cold-calls" ]
}

@test "router: a warm process that outlasts the limit is unavailable at the limit" {
  serve "read -r line; sleep 30" up
  CC_RESEARCH_CLASSIFIER_TIMEOUT=1 CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/cold-calls" ]
}

@test "router: CC_RESEARCH_WARM=0 at launch skips the daemon" {
  serve "$(child pushback)"
  CC_RESEARCH_WARM=0 CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = work-order ]
}

# ── the staged plist and migration 0059 ─────────────────────────────────────────────────────────

@test "plist: lints, is staged not loaded, keeps the daemon alive, and runs /bin/bash on a runner install.sh links" {
  /usr/bin/plutil -lint "$PLIST" >/dev/null
  grep -q 'STAGED, NOT LOADED' "$PLIST"
  [ ! -e "$REPO/launchd/com.claude.research-classifier-warm.plist" ]
  [ "$(/usr/bin/plutil -extract Label raw "$PLIST")" = com.claude.research-classifier-warm ]
  [ "$(/usr/bin/plutil -extract ProgramArguments.0 raw "$PLIST")" = /bin/bash ]
  [ "$(/usr/bin/plutil -extract KeepAlive raw "$PLIST")" = true ]
  rel="$(/usr/bin/plutil -extract ProgramArguments.1 raw "$PLIST")"
  rel="${rel#*/.claude/}"
  [ -f "$REPO/$rel" ]
  [ -f "$REPO/$(dirname "$(dirname "$rel")")/classifier-warm.py" ]
  grep -Eq 'for sub in .*"/jobs"' "$REPO/install.sh"
  grep -Fq "cls='$(dirname "$rel")/*'" "$REPO/scripts/deploy-parity-assert.sh"
}

# A fake launchctl that records its calls; `print` succeeds only after a `bootstrap`.
fake_launchctl() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/launchctl" <<EOF
#!/bin/bash
echo "\$*" >> "$BATS_TEST_TMPDIR/launchctl-calls"
case "\$1" in
  bootstrap) touch "$BATS_TEST_TMPDIR/loaded" ;;
  print) [ -e "$BATS_TEST_TMPDIR/loaded" ] || exit 113 ;;
esac
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/launchctl"
}

# live_layer <ping exit> — the runner and a daemon whose ping exits as told, at their live paths.
live_layer() {
  mkdir -p "$HOME/.claude/scripts/research-kit/jobs"
  cp "$RUNNER" "$HOME/.claude/scripts/research-kit/jobs/classifier-warm.sh"
  printf 'import sys\nprint("ready 2")\nsys.exit(%s)\n' "$1" > "$HOME/.claude/scripts/research-kit/classifier-warm.py"
}

@test "migration --dry-run under /bin/bash names the label and writes nothing" {
  fake_launchctl
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" run /bin/bash "$MIG" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"com.claude.research-classifier-warm"* ]] || false
  [[ "$output" == *"LACKS"* ]] || false
  [ -z "$(find "$HOME" -mindepth 1)" ]
  [ ! -e "$BATS_TEST_TMPDIR/launchctl-calls" ]
  grep -q '^# migration-class: c10$' "$MIG"
  grep -q '^# migration-verify: ' "$MIG"
  grep -q '^# migration-run: ' "$MIG"
}

@test "migration refuses before the live layer carries the daemon, and loads nothing" {
  fake_launchctl
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" run /bin/bash "$MIG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"converge first"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/launchctl-calls" ]
  [ ! -e "$HOME/Library/LaunchAgents/com.claude.research-classifier-warm.plist" ]
}

@test "migration loads the job, reads the daemon's ping back, and a re-run is a no-op" {
  fake_launchctl
  live_layer 0
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" run /bin/bash "$MIG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the daemon answers (ready 2)"* ]] || false
  cmp "$PLIST" "$HOME/Library/LaunchAgents/com.claude.research-classifier-warm.plist"
  [ "$(grep -c '^bootstrap ' "$BATS_TEST_TMPDIR/launchctl-calls")" -eq 1 ]
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" run /bin/bash "$MIG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already loaded from the repo plist"* ]] || false
  [ "$(grep -c '^bootstrap ' "$BATS_TEST_TMPDIR/launchctl-calls")" -eq 1 ]
}

@test "migration fails when the job loads but the daemon never answers" {
  fake_launchctl
  live_layer 1
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" CC_MIGRATION_PING_TRIES=1 run /bin/bash "$MIG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no worker answered a classification"* ]]
}

@test "E1f migration: a job already loaded but not answering is restarted once, then read back as answering" {
  fake_launchctl
  live_layer 0
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" run /bin/bash "$MIG"
  [ "$status" -eq 0 ]
  # the incident's daemon: loaded from the same plist, on its socket, no worker answering (ping 2)
  # until it is restarted
  printf 'import os, sys\nif os.path.exists("%s"):\n    print("ready 2"); sys.exit(0)\nsys.exit(2)\n' "$BATS_TEST_TMPDIR/kicked" > "$HOME/.claude/scripts/research-kit/classifier-warm.py"
  printf '#!/bin/bash\necho "$*" >> "%s"\n[ "$1" = kickstart ] && touch "%s"\nexit 0\n' "$BATS_TEST_TMPDIR/launchctl-calls" "$BATS_TEST_TMPDIR/kicked" > "$BATS_TEST_TMPDIR/bin/launchctl"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" run /bin/bash "$MIG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"restarted on the live code"* ]] || false
  [[ "$output" == *"the daemon answers (ready 2)"* ]] || false
  [ "$(grep -c '^kickstart -k gui/.*/com.claude.research-classifier-warm$' "$BATS_TEST_TMPDIR/launchctl-calls")" -eq 1 ]
  [ "$(grep -c '^bootstrap ' "$BATS_TEST_TMPDIR/launchctl-calls")" -eq 1 ]
}

@test "shellcheck, bare, is clean on the runner and the migration" {
  run shellcheck "$RUNNER" "$MIG"
  [ "$status" -eq 0 ]
}
