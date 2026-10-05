#!/usr/bin/env bats
# research-classifier-warm — the re-ask router's resident classifier (decision 4bf73c4e55d5 option 3;
# wave E1c of docs/plans/RESEARCH_PROGRAM_BUILD.md): the daemon, its launchd runner under /bin/bash
# 3.2, the staged plist, migration 0059, and router.py's use of it. The classifier process is a stub
# (CC_RESEARCH_WARM_CHILD); nothing here starts `claude`.

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

# serve <child command> — start the daemon and wait until it answers a ping.
serve() {
  CC_RESEARCH_WARM_CHILD="$1" /usr/bin/python3 "$WARM" serve 2>"$BATS_TEST_TMPDIR/serve.err" &
  DPID=$!
  local i
  for i in $(seq 1 50); do
    /usr/bin/python3 "$WARM" ping >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

@test "/bin/bash is 3.2, the interpreter launchd uses" {
  run /bin/bash --version
  [[ "$output" == *"version 3.2."* ]]
}

@test "the runner, under /bin/bash 3.2, execs the daemon's serve verb and takes no arguments" {
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "%s"\n' "$BATS_TEST_TMPDIR/args" > "$BATS_TEST_TMPDIR/py"
  chmod +x "$BATS_TEST_TMPDIR/py"
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
  # three prompts, three processes, one line each
  [ "$(cat "$SEEN"/* | wc -l | tr -d ' ')" -eq 3 ]
  for f in "$SEEN"/*; do [ "$(wc -l < "$f" | tr -d ' ')" -eq 1 ]; done
  [ "$(cat "$SEEN"/* | grep -c 'prompt number')" -eq 3 ]
}

@test "with no process ready the daemon declines at once (exit 3: make the cold call), it does not guess" {
  serve "exit 0"
  start="$(/usr/bin/python3 -c 'import time; print(time.time())')"
  run bash -c "printf 'label this' | /usr/bin/python3 '$WARM' ask"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no warm classifier process is ready"* ]] || false
  /usr/bin/python3 -c "import sys, time; sys.exit(0 if time.time() - $start < 2.0 else 1)"
}

@test "a process that took the prompt and never answers fails at the deadline (exit 1), not as a decline" {
  serve "read -r line; sleep 30"
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

@test "router: a daemon with no process ready falls back to the cold call inside the same limit" {
  serve "exit 0"
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
  serve "read -r line; sleep 30"
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
  [[ "$output" == *"did not answer a ping"* ]]
}

@test "shellcheck, bare, is clean on the runner and the migration" {
  run shellcheck "$RUNNER" "$MIG"
  [ "$status" -eq 0 ]
}
