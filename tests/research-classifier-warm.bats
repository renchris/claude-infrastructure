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
  for i in $(seq 1 50); do [ "$(/usr/bin/python3 "$WARM" ping 2>/dev/null)" = "ready 2" ] && break; sleep 0.1; done   # one of each kind
  touch "$BATS_TEST_TMPDIR/out"
  # the one waiting process started before the login lapsed, but it reads the lapse at its prompt
  run bash -c "printf 'label this' | /usr/bin/python3 '$WARM' ask"
  [ "$status" -eq 1 ]
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 2 ]
}

@test "E1f daemon: three failed round-trips in a row and it exits 1 and removes its socket, so launchd restarts the runner" {
  # `|| true`: at load the daemon can fail three times and exit before the helper's first ping
  # sees it on its socket, and its exit is what this test is about.
  CC_RESEARCH_WARM_CANARY_RETRY=0.1 serve "$(logged_out)" up || true
  exited
  [ "$rc" -eq 1 ]
  [ ! -e "$CC_RESEARCH_WARM_SOCK" ]
  grep -q 'exiting so the runner picks an account again' "$BATS_TEST_TMPDIR/serve.err"
}

@test "E1f probe: one classification through one process of each kind, exit 0 when they answer and 1 when logged out" {
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
  # (a probe is one process of each kind, so an account tried is two lines)
  [ "$(sed -n 1,2p "$BATS_TEST_TMPDIR/dirs" | sort -u)" = "$HOME/.claude-b" ]
  [ "$(sed 1,2d "$BATS_TEST_TMPDIR/dirs" | sort -u)" = "$HOME/.claude-c" ]
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
  [ "$(sed -n 1,2p "$BATS_TEST_TMPDIR/dirs" | sort -u)" = "$HOME/.claude-a" ]
  [ "$(sed 1,2d "$BATS_TEST_TMPDIR/dirs" | sort -u)" = "$HOME/.claude-b" ]
}

@test "E1k runner, as launchd starts it under /bin/bash 3.2: every classifier process gets CLAUDE_CODE_CERT_STORE=bundled" {
  # The workers run --setting-sources local, so the user settings' env block (settings.json:13, which
  # every interactive session has) never reaches them; under the default store a `claude` start can
  # block on a starved keychain query. RED-proof: before wave E1k the variable is absent here.
  accounts "a 0.9"
  touch "$HOME/.claude-a/login"
  launchd_run CC_RESEARCH_WARM_CHILD="echo \"\${CLAUDE_CODE_CERT_STORE:-unset}\" >> '$BATS_TEST_TMPDIR/certs'; $(by_login)" 2>"$BATS_TEST_TMPDIR/serve.err" &
  DPID=$!
  for i in $(seq 1 100); do /usr/bin/python3 "$WARM" ping >/dev/null 2>&1 && break; sleep 0.1; done
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/certs" ]
  [ "$(sort -u "$BATS_TEST_TMPDIR/certs")" = bundled ]
}

# ── router.py ───────────────────────────────────────────────────────────────────────────────────

# The cold classifier stub logs that it ran and answers work-order, so a warm label is told apart.
cold() { printf 'cat >/dev/null; echo ran >> "%s"; echo work-order' "$BATS_TEST_TMPDIR/cold-calls"; }

@test "router: no daemon means the cold calls, one of each kind" {
  CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = work-order ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/cold-calls" | tr -d ' ')" -eq 2 ]   # one per kind of call (E1g)
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
  [ "$(wc -l < "$BATS_TEST_TMPDIR/cold-calls" | tr -d ' ')" -eq 2 ]   # one per kind of call (E1g)
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
  # With the hedge off (wave E1k's switch), as the router was before it: the hedge's own cases below.
  serve "read -r line; sleep 30" up
  CC_RESEARCH_HEDGE=0 CC_RESEARCH_CLASSIFIER_TIMEOUT=1 CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/cold-calls" ]
}

@test "router: CC_RESEARCH_WARM=0 at launch skips the daemon" {
  serve "$(child pushback)"
  CC_RESEARCH_WARM=0 CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = work-order ]
}

# ── two calls per prompt (wave E1g) ─────────────────────────────────────────────────────────────
# The router asks a fast classifier (E1b's brief, thinking off) and a careful one (the brief as
# built, thinking on) at once, inside the one limit. Rule: a relay label from the fast call ends it;
# else a relay label from the careful call; else the fast call's label; unavailable only when neither
# answered. The stubs read CC_RESEARCH_CLASSIFIER_KIND, which names the call they stand in for.

# two <fast script> <careful script> — a cold classifier stub that behaves by kind and logs the kind.
two() {
  printf 'cat > "%s/in.$CC_RESEARCH_CLASSIFIER_KIND"; echo "$CC_RESEARCH_CLASSIFIER_KIND" >> "%s/kinds"; if [ "$CC_RESEARCH_CLASSIFIER_KIND" = fast ]; then %s; else %s; fi' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" "$1" "$2"
}

# timed <limit s> <stub> — classify one prompt the way heldout.py does (a `bash -c` child, its whole
# wall measured from outside); leaves the label in $output, the exit in $status, the wall in $wall.
timed() {
  local t0
  t0="$(/usr/bin/python3 -c 'import time; print(time.time())')"
  CC_RESEARCH_CLASSIFIER_TIMEOUT="$1" CC_RESEARCH_CLASSIFIER="$2" run bash -c "printf 'is that everything?' | python3 '$ROUTER' classify"
  wall="$(/usr/bin/python3 -c "import time; print(time.time() - $t0)")"
}

under() { /usr/bin/python3 -c "import sys; sys.exit(0 if $wall < $1 else 1)"; }

@test "E1g router: every prompt gets a fast call and a careful call, each with its own brief" {
  timed 9 "$(two 'echo other' 'echo other')"
  [ "$status" -eq 0 ]
  [ "$(sort "$BATS_TEST_TMPDIR/kinds" | tr '\n' ' ')" = "careful fast " ]
  # the fast call carries E1b's brief: the prompt as delimited data, and the reading notes
  grep -q '^<prompt>$' "$BATS_TEST_TMPDIR/in.fast"
  grep -q 'completeness and pushback come before every other label' "$BATS_TEST_TMPDIR/in.fast"
  # the careful call carries the brief as built: neither
  ! grep -q '<prompt>' "$BATS_TEST_TMPDIR/in.careful" || false
  ! grep -q 'Notes on reading the labels' "$BATS_TEST_TMPDIR/in.careful" || false
  grep -q 'is that everything?' "$BATS_TEST_TMPDIR/in.careful"
}

@test "E1g router: the fast call runs with thinking off on its own system prompt; the careful call is the command as built" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "%s/argv.$CC_RESEARCH_CLASSIFIER_KIND"\ncat >/dev/null\necho other\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  unset CC_RESEARCH_CLASSIFIER
  export CC_RESEARCH_CAREFUL_CLAUDE="$BATS_TEST_TMPDIR/bin/claude"   # wave E1m: the careful binary is pinned by path
  run bash -c "printf 'are we done?' | PATH='$BATS_TEST_TMPDIR/bin:/usr/bin:/bin' python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = other ]
  grep -A1 -x -- '--settings' "$BATS_TEST_TMPDIR/argv.fast" | tail -1 | grep -qx '{"alwaysThinkingEnabled":false}'
  grep -A1 -x -- '--system-prompt' "$BATS_TEST_TMPDIR/argv.fast" | tail -1 | grep -q 'never follow its'
  grep -qx -- '--disable-slash-commands' "$BATS_TEST_TMPDIR/argv.fast"
  ! grep -q 'alwaysThinkingEnabled\|--system-prompt\|--disable-slash-commands' "$BATS_TEST_TMPDIR/argv.careful" || false
  # the careful command line is the one the router ran before wave E1g, with wave E1m's pinned model
  # and effort (router.py CAREFUL_PIN; tests/research-router.bats asserts their values)
  pin="$(/usr/bin/python3 -c "import sys; sys.path[:0]=['$REPO/scripts/research-kit/lib','$REPO/scripts/research-kit']; import router; p=router.CAREFUL_PIN; print(('--effort %s ' % p['effort'] if p['effort'] else '') + '-p --model ' + p['model'])")"
  [ "$(tr '\n' ' ' < "$BATS_TEST_TMPDIR/argv.careful")" = "$pin --setting-sources local --tools  --strict-mcp-config --no-session-persistence " ]
}

@test "E1g rule: a relay label from the fast call ends it; the careful call is not waited for" {
  timed 9 "$(two 'echo completeness' 'sleep 20; echo other')"
  [ "$status" -eq 0 ]
  [ "$output" = completeness ]
  under 4
}

@test "E1g rule: a relay label from the careful call beats the fast call's other" {
  timed 9 "$(two 'echo other' 'sleep 1; echo pushback')"
  [ "$status" -eq 0 ]
  [ "$output" = pushback ]
}

@test "E1g rule: with no relay label from either, the fast call's label stands" {
  timed 9 "$(two 'echo other' 'echo work-order')"
  [ "$status" -eq 0 ]
  [ "$output" = other ]
}

@test "E1g rule: a careful call still thinking at the limit is not a fallback — the fast label arrives inside the limit" {
  # heldout.py stops a router call at the limit of ITS clock, which includes starting Python, so a
  # label handed back AT the router's limit was scored a fallback (E1e: 45 of 232 at 9.00-9.01 s).
  # Run at the real limit, and read the router's own clock (its trace): this test's clock adds two
  # interpreter starts, which at load is most of the margin. The router must hand the fast label
  # back DELIVER_MARGIN_S (0.5 s) before 9 s; a router that waits out the limit reads 9.0 here.
  export CC_RESEARCH_CLASSIFY_TRACE="$BATS_TEST_TMPDIR/trace"
  timed 9 "$(two 'echo other' 'sleep 20; echo completeness')"
  [ "$status" -eq 0 ]
  [ "$output" = other ]
  # the classify verb's own row (wave E1k adds a `held` row before it, the careful call still pending)
  [ "$(jq -r 'select(.row == null) | .label' "$BATS_TEST_TMPDIR/trace")" = other ]
  jq -e 'select(.row == null) | .wall_s >= 8.4 and .wall_s < 8.9' "$BATS_TEST_TMPDIR/trace"
  jq -e 'select(.row == null) | .why | test("fast call, cold.*careful call: had not answered")' "$BATS_TEST_TMPDIR/trace"
}

@test "E1g rule: the careful call's label stands when the fast call fails, and unavailable needs both to fail" {
  timed 9 "$(two 'exit 7' 'echo new-idea')"
  [ "$status" -eq 0 ]
  [ "$output" = new-idea ]
  timed 9 "$(two 'echo I think it is other' 'exit 7')"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  timed 1 "$(two 'sleep 20' 'sleep 20')"
  [ "$status" -eq 1 ]
  under 3
}

# ── the stall trace (wave E1j) ──────────────────────────────────────────────────────────────────
# E1i's read lost 105 items to 9 s fallbacks, and heldout.py killed each router before the classify
# verb wrote its trace row, so no fallback left a reason. With no label in hand STALL_TRACE_MARGIN_S
# before the limit, the router now writes a `stall` row naming each call's path, what the resident
# classifier said and whether it answered. RED-proof: on the router before this wave both cases below
# find no stall row.

@test "E1j trace: a router killed at the caller's 9 s limit has already left a stall row naming each call's path" {
  local stub
  stub="$(two 'sleep 20' 'sleep 20')"
  # exactly as gate row 15 calls it: heldout.route, its own 9 s clock, the router killed at the limit
  run env CC_RESEARCH_CLASSIFY_TRACE="$BATS_TEST_TMPDIR/trace" CC_RESEARCH_CLASSIFIER="$stub" /usr/bin/python3 -c "import sys; sys.path[:0]=['$REPO/scripts/research-kit/lib','$REPO/scripts/research-kit']; import heldout; print(heldout.route(\"python3 '$ROUTER' classify\", 'is that everything?'))"
  [ "$status" -eq 0 ]
  [ "$output" = None ]
  [ "$(head -1 "$BATS_TEST_TMPDIR/trace" | jq -r '.row')" = stall ]
  head -1 "$BATS_TEST_TMPDIR/trace" | jq -e '.at_s >= 8.5 and .at_s < 8.9 and (.load | type) == "number"'
  for k in fast careful; do
    head -1 "$BATS_TEST_TMPDIR/trace" | jq -e --arg k "$k" '.[$k].path == "cold" and .[$k].answered == false
      and (.[$k].warm | startswith("cold: no resident classifier")) and .[$k].reason == "had not answered"
      and (.[$k].cold_s | type) == "number"'
  done
  ! grep -q 'is that everything' "$BATS_TEST_TMPDIR/trace" || false   # never the prompt
}

@test "E1j trace: a resident worker that took the prompt and stalls reads as warm and waiting; a label in hand writes no stall row" {
  serve "read -r line; sleep 30" up
  # the hedge off (wave E1k's switch), or its cold twins would answer: the stall row's shape is the subject
  CC_RESEARCH_HEDGE=0 CC_RESEARCH_CLASSIFY_TRACE="$BATS_TEST_TMPDIR/trace" CC_RESEARCH_CLASSIFIER_TIMEOUT=2 CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.row // "final"' "$BATS_TEST_TMPDIR/trace" | tr '\n' ' ')" = "stall final " ]
  for k in fast careful; do
    head -1 "$BATS_TEST_TMPDIR/trace" | jq -e --arg k "$k" '.[$k].path == "warm" and .[$k].answered == false
      and .[$k].warm == "waiting on the resident classifier" and .[$k].warm_s == null'
  done
  [ ! -e "$BATS_TEST_TMPDIR/cold-calls" ]
  rm "$BATS_TEST_TMPDIR/trace"
  CC_RESEARCH_CLASSIFY_TRACE="$BATS_TEST_TMPDIR/trace" CC_RESEARCH_WARM=0 CC_RESEARCH_CLASSIFIER_TIMEOUT=2 CC_RESEARCH_CLASSIFIER="$(two 'echo other' 'sleep 20')" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = other ]
  # no stall row; the careful call still pending when the hold fired leaves a `held` row (wave E1k)
  [ "$(jq -r '.row // "final"' "$BATS_TEST_TMPDIR/trace" | tr '\n' ' ')" = "held final " ]
}

# ── the cold hedge (wave E1k) ───────────────────────────────────────────────────────────────────
# E1j's trace: every live fallback was a resident worker that took the prompt and went silent, holding
# its call to the limit, so no cold call ever ran. At HEDGE_AFTER_S (4 s of 9, scaled) a cold twin now
# starts for each kind still waiting on the resident classifier; the first label of each kind counts,
# and with no label the router gives up before the caller's 9 s kill so it can end its twins. Assertions
# are on labels, trace fields and processes, never on short wall times. RED-proof: on the router before
# this wave every case here fails (no twin, no `hedge` field, killed before its own row).

# stalls_unless_fast <label> — a resident process: the fast kind answers <label> at once, the careful
# kind takes the prompt and never answers.
stalls_unless_fast() {
  printf 'read -r line; if [ "$CC_RESEARCH_CLASSIFIER_KIND" = fast ]; then echo "{\\"type\\":\\"result\\",\\"result\\":\\"%s\\"}"; fi; sleep 30' "$1"
}

final() { jq -c 'select(.row == null)' "$BATS_TEST_TMPDIR/trace"; }

@test "E1k hedge: a resident worker that took the prompt and never answers no longer costs the label" {
  serve "read -r line; sleep 30" up
  CC_RESEARCH_CLASSIFY_TRACE="$BATS_TEST_TMPDIR/trace" CC_RESEARCH_CLASSIFIER_TIMEOUT=4.5 CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = work-order ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/cold-calls" | tr -d ' ')" -eq 2 ]   # one twin per kind
  final | jq -e '.hedge_on == true and .hedge.fast == {"fired": true, "won": true}
    and .hedge.careful == {"fired": true, "won": true} and (.why | test("cold hedge"))'
}

@test "E1k hedge: CC_RESEARCH_HEDGE=0 is the router as E1j left it — no twin, a fallback, and the trace says the hedge was off" {
  serve "read -r line; sleep 30" up
  CC_RESEARCH_HEDGE=0 CC_RESEARCH_CLASSIFY_TRACE="$BATS_TEST_TMPDIR/trace" CC_RESEARCH_CLASSIFIER_TIMEOUT=4.5 CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/cold-calls" ]
  final | jq -e '.hedge_on == false and .hedge.fast == {"fired": false, "won": false}
    and .hedge.careful == {"fired": false, "won": false}'
}

@test "E1k hedge: one kind stalled on the resident path while the other holds a non-relay label — the stalled kind's cold vote counts" {
  serve "$(stalls_unless_fast other)" up
  CC_RESEARCH_CLASSIFY_TRACE="$BATS_TEST_TMPDIR/trace" CC_RESEARCH_CLASSIFIER_TIMEOUT=4.5 CC_RESEARCH_CLASSIFIER="$(two 'echo other' 'echo completeness')" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = completeness ]   # the union: the careful twin's relay label beats the fast call's other
  [ "$(cat "$BATS_TEST_TMPDIR/kinds")" = careful ]   # only the stalled kind got a twin
  final | jq -e '.hedge.fast == {"fired": false, "won": false} and .hedge.careful == {"fired": true, "won": true}'
}

@test "E1k hedge: the hold firing with one kind still pending leaves a held row naming it" {
  serve "$(stalls_unless_fast other)" up
  CC_RESEARCH_CLASSIFY_TRACE="$BATS_TEST_TMPDIR/trace" CC_RESEARCH_CLASSIFIER_TIMEOUT=4.5 CC_RESEARCH_CLASSIFIER="$(two 'echo other' 'sleep 20; echo completeness')" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = other ]
  [ "$(jq -r '.row // "final"' "$BATS_TEST_TMPDIR/trace" | tr '\n' ' ')" = "held final " ]
  head -1 "$BATS_TEST_TMPDIR/trace" | jq -e '(.load | type) == "number" and .fast.answered == true
    and .careful.answered == false and .careful.path == "warm" and .careful.hedge == {"fired": true, "won": false}
    and .careful.twin.path == "cold" and .careful.twin.answered == false'
}

@test "E1k hedge: a resident answer at 5 s beats a slow cold twin, and the resident call was never dropped" {
  serve "read -r line; sleep 5; echo '{\"type\":\"result\",\"result\":\"pushback\"}'; sleep 30" up
  CC_RESEARCH_CLASSIFY_TRACE="$BATS_TEST_TMPDIR/trace" CC_RESEARCH_CLASSIFIER="cat >/dev/null; echo ran >> '$BATS_TEST_TMPDIR/cold-calls'; sleep 20; echo work-order" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = pushback ]
  [ -s "$BATS_TEST_TMPDIR/cold-calls" ]   # the hedge fired at 4 s ...
  final | jq -e '(.why | test("resident")) and ([.hedge[] | select(.fired)] | length) >= 1
    and ([.hedge[] | select(.won)] | length) == 0'   # ... and lost to the resident answer
}

@test "E1k hedge: a row with no label returns before 9 s, ahead of the caller's kill, and leaves no twin alive" {
  serve "read -r line; sleep 30" up
  local stub="cat >/dev/null; echo \$\$ >> '$BATS_TEST_TMPDIR/pids'; sleep 30"
  # Run directly, not under heldout.route: the subject is the router's own give-up point (8.7 s of
  # its clock), read from its own row. Under heldout at load ~200 the harness's process starts alone
  # can push the router past heldout's outside 9 s, and that kill leaves no row to read.
  CC_RESEARCH_CLASSIFY_TRACE="$BATS_TEST_TMPDIR/trace" CC_RESEARCH_CLASSIFIER="$stub" run bash -c "printf 'is that everything?' | python3 '$ROUTER' classify"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  final | jq -e '.label == null and .wall_s < 9 and .hedge.fast.fired and .hedge.careful.fired'
  [ "$(wc -l < "$BATS_TEST_TMPDIR/pids" | tr -d ' ')" -eq 2 ]
  local pid i alive
  for i in $(seq 1 20); do
    alive=""
    while read -r pid; do
      if pgrep -g "$pid" >/dev/null 2>&1 || kill -0 "$pid" 2>/dev/null; then alive="$alive $pid"; fi
    done < "$BATS_TEST_TMPDIR/pids"
    [ -z "$alive" ] && break
    sleep 0.1
  done
  [ -z "$alive" ]
}

# by_kind — a resident classifier process that answers with the kind it was started as.
by_kind() {
  printf 'read -r line; printf "%%s\\n" "$line" >> "%s/$CC_RESEARCH_CLASSIFIER_KIND.$$"; echo "{\\"type\\":\\"result\\",\\"result\\":\\"$CC_RESEARCH_CLASSIFIER_KIND\\"}"; sleep 30' "$SEEN"
}

@test "E1g daemon: it keeps processes of each kind, and a prompt is answered by the kind it names" {
  serve "$(by_kind)"
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 0 ]
  [ "$output" = "ready 4" ] || [ "$output" = "ready 3" ] || [ "$output" = "ready 2" ]   # refilling
  run bash -c "printf 'label this' | /usr/bin/python3 '$WARM' ask --kind fast"
  [ "$status" -eq 0 ]
  [ "$output" = fast ]
  run bash -c "printf 'label this' | /usr/bin/python3 '$WARM' ask --kind careful"
  [ "$status" -eq 0 ]
  [ "$output" = careful ]
  # each kind's readiness round-trip carried that kind's brief
  cat "$SEEN"/fast.* | grep 'is the classifier answering' | grep -q 'Notes on reading the labels'
  ! cat "$SEEN"/careful.* | grep -q 'Notes on reading the labels'
}

@test "E1g ping: ready needs an answered round-trip of EACH kind; one kind logged out is not ready and leaves no stamp" {
  half="read -r line; if [ \"\$CC_RESEARCH_CLASSIFIER_KIND\" = fast ]; then echo '{\"type\":\"result\",\"is_error\":true,\"result\":\"Not logged in\"}'; else echo '{\"type\":\"result\",\"result\":\"other\"}'; fi; sleep 30"
  CC_RESEARCH_WARM_CANARY_RETRY=30 serve "$half" up
  for i in $(seq 1 50); do
    /usr/bin/python3 "$WARM" ping 2>&1 | grep -q 'fast call: .*Not logged in' && break
    sleep 0.1
  done
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 2 ]
  [[ "$output" == *"fast call: "*"Not logged in"* ]] || false
  [[ "$output" != *"careful call:"* ]] || false
  [ ! -e "$SOCKD/answered" ]
}

# old_daemon — the daemon as it answered before wave E1g, on this test's socket: one kind of worker,
# `ping` with no per-kind report, `ask` answered, any other op declined at once as `cold`.
old_daemon() {
  /usr/bin/python3 -c '
import json, os, socket, sys
d, b = os.path.split(os.path.abspath(sys.argv[1]))
os.chdir(d)   # bind the basename: sun_path is capped at 104 bytes
s = socket.socket(socket.AF_UNIX); s.bind(b); s.listen(8)
while True:
    c, _ = s.accept()
    op = json.loads(c.makefile().readline() or "{}").get("op")
    out = ({"ok": True, "ready": 2, "answering": True, "why": ""} if op == "ping"
           else {"ok": True, "text": "pushback"} if op == "ask"
           else {"ok": False, "cold": True, "why": "not an ask or a ping"})
    c.sendall(json.dumps(out).encode() + b"\n"); c.close()
' "$CC_RESEARCH_WARM_SOCK" &
  DPID=$!
  for i in $(seq 1 50); do [ -S "$CC_RESEARCH_WARM_SOCK" ] && break; sleep 0.1; done
}

@test "E1g ping: a daemon still running the code from before this wave is NOT ready (exit 2: restart it)" {
  old_daemon
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 2 ]
  [[ "$output" == *"runs older code; restart it"* ]] || false
}

@test "E1g ping: a daemon whose workers were started with another classifier configuration is NOT ready" {
  # (wave E1m pinned the careful call, so the fast call's model key is the one model-config still moves)
  printf 'versions:\n  sonnet_latest: claude-sonnet-old\n' > "$BATS_TEST_TMPDIR/old-models.yaml"
  CC_MODEL_CONFIG="$BATS_TEST_TMPDIR/old-models.yaml" serve "$(child other)" up
  for i in $(seq 1 50); do
    /usr/bin/python3 "$WARM" ping 2>&1 | grep -q 'older classifier configuration' && break
    sleep 0.1
  done
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 2 ]
  [[ "$output" == *"older classifier configuration"* ]] || false
  CC_MODEL_CONFIG="$BATS_TEST_TMPDIR/old-models.yaml" run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 0 ]
}

@test "E1g router: a daemon from before this wave is not asked to stand in — both cold calls are made" {
  old_daemon
  CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = work-order ]            # the cold stub's label, not the old daemon's pushback
  [ "$(wc -l < "$BATS_TEST_TMPDIR/cold-calls" | tr -d ' ')" -eq 2 ]
}

@test "E1g router + daemon: a resident fast relay label ends it, and the careful process holding the prompt is ended" {
  # (the fast answer takes half a second, so the careful process is surely holding the prompt by then)
  stub="read -r line; if [ \"\$CC_RESEARCH_CLASSIFIER_KIND\" = fast ]; then sleep 0.5; echo '{\"type\":\"result\",\"result\":\"completeness\"}'; else case \"\$line\" in *'are we done?'*) echo \$\$ > '$BATS_TEST_TMPDIR/careful.pid';; *) echo '{\"type\":\"result\",\"result\":\"other\"}';; esac; fi; sleep 30"
  serve "$stub"
  CC_RESEARCH_CLASSIFIER="$(cold)" run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = completeness ]
  [ ! -e "$BATS_TEST_TMPDIR/cold-calls" ]
  # the careful worker took the prompt; the router hung up on it, so the daemon ended it at once
  # instead of holding a thinking process for the rest of the limit
  for i in $(seq 1 30); do [ -s "$BATS_TEST_TMPDIR/careful.pid" ] && break; sleep 0.1; done
  pid="$(cat "$BATS_TEST_TMPDIR/careful.pid")"
  for i in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  ! kill -0 "$pid" 2>/dev/null || false
  # and a hang-up is not a failed worker: the daemon is still ready
  run /usr/bin/python3 "$WARM" ping
  [ "$status" -eq 0 ]
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

@test "E1g migration: a job loaded and ANSWERING on the code from before this wave is restarted onto the live code, end to end" {
  # The E1f test above stubs the daemon's ping. Here the live layer is the real daemon script, the
  # loaded job is a daemon that answers the way the pre-E1g one does, and `kickstart -k` does what
  # launchd does: ends it and starts the live code. Before this wave a re-run left such a job alone
  # (its ping said "ready 2"), so the operator's one step would have restarted nothing.
  fake_launchctl
  mkdir -p "$HOME/.claude/scripts" "$HOME/Library/LaunchAgents"
  ln -s "$REPO/scripts/research-kit" "$HOME/.claude/scripts/research-kit"
  cp "$PLIST" "$HOME/Library/LaunchAgents/com.claude.research-classifier-warm.plist"
  touch "$BATS_TEST_TMPDIR/loaded"
  old_daemon
  cat > "$BATS_TEST_TMPDIR/bin/launchctl" <<EOF
#!/bin/bash
echo "\$*" >> "$BATS_TEST_TMPDIR/launchctl-calls"
if [ "\$1" = kickstart ]; then
  kill "$DPID"; rm -f "$CC_RESEARCH_WARM_SOCK"
  CC_RESEARCH_WARM_CHILD='$(child other)' /usr/bin/python3 "$WARM" serve >/dev/null 2>&1 &
  echo \$! > "$BATS_TEST_TMPDIR/new.pid"
fi
exit 0
EOF
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" run /bin/bash "$MIG"
  [ -s "$BATS_TEST_TMPDIR/new.pid" ] && DPID="$(cat "$BATS_TEST_TMPDIR/new.pid")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"restarted on the live code"* ]] || false
  [[ "$output" == *"the daemon answers (ready "* ]] || false
  [ "$(grep -c '^kickstart -k gui/.*/com.claude.research-classifier-warm$' "$BATS_TEST_TMPDIR/launchctl-calls")" -eq 1 ]
  ! grep -q '^bootstrap ' "$BATS_TEST_TMPDIR/launchctl-calls"
}

@test "E1m plist: the job runs as ProcessType Interactive, so its workers are not starved below the interactive sessions" {
  # E1k's real-load A/B: the launchd workers ran at PRI 20 (no ProcessType) against the sessions' 31
  # and held prompts to the router's limit under load; the key moves them to the interactive band.
  /usr/bin/plutil -lint "$PLIST" >/dev/null
  [ "$(/usr/bin/plutil -extract ProcessType raw "$PLIST")" = Interactive ]
}

@test "E1m migration: a job loaded from a plist whose bytes differ from the repo's is booted out and re-installed from the repo plist" {
  # The ProcessType change reaches launchd only if 0059 replaces a loaded job whose plist is older.
  fake_launchctl
  live_layer 0
  mkdir -p "$HOME/Library/LaunchAgents"
  sed 's/<key>ProcessType<\/key>.*//' "$PLIST" > "$HOME/Library/LaunchAgents/com.claude.research-classifier-warm.plist"
  ! cmp -s "$PLIST" "$HOME/Library/LaunchAgents/com.claude.research-classifier-warm.plist" || false
  touch "$BATS_TEST_TMPDIR/loaded"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" run /bin/bash "$MIG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"loaded"* ]] || false
  [[ "$output" != *"already loaded from the repo plist"* ]] || false
  grep -q '^bootout gui/.*/com.claude.research-classifier-warm$' "$BATS_TEST_TMPDIR/launchctl-calls"
  [ "$(grep -c '^bootstrap ' "$BATS_TEST_TMPDIR/launchctl-calls")" -eq 1 ]
  cmp "$PLIST" "$HOME/Library/LaunchAgents/com.claude.research-classifier-warm.plist"
}

@test "shellcheck, bare, is clean on the runner and the migration" {
  run shellcheck "$RUNNER" "$MIG"
  [ "$status" -eq 0 ]
}
