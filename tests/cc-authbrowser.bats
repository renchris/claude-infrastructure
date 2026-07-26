#!/usr/bin/env bats
# cc-authbrowser — the dedicated per-account Chrome substrate. Hermetic: every test drives a FAKE
# chrome-bin stub (a python script that records its argv and optionally serves a stub CDP endpoint)
# via CC_AUTHBROWSER_CHROME_BIN, with state + profiles redirected into BATS_TEST_TMPDIR. Real Chrome
# is NEVER launched; ~/.claude/auth-profiles is NEVER touched; nothing authenticates anything.
# The one un-fakeable resource is the frozen CDP port (contract §1 hardcodes it, so there is no
# override knob) — stubs bind 127.0.0.1:934x and teardown always frees it.

# Fork can transiently fail (EAGAIN) when this box is running dozens of concurrent bats suites,
# and a bare `cmd &` then aborts the whole test under errexit — a spurious RED that blocks a
# landing while proving nothing. Observed 2026-07-25: `sleep 45 &' failed at ~57 concurrent
# bats processes, then passed on the next gate round. Every one of these tests needs SOME pid,
# never a specific one, so retrying the spawn preserves the semantics exactly.
#
# The child's stdout MUST be redirected. Callers use `pid=$(spawn_bg ...)`, and a command
# substitution blocks until EVERY holder of its stdout pipe closes it — not merely until the
# function returns. A backgrounded child inherits that pipe, so without this redirect
# `FOREIGN=$(spawn_bg "$D/foreign-listener" 9341)` blocks for the listener's full 600s sleep
# (and each `spawn_bg sleep 4x` for its own lifetime) — ~825s box-wide, hanging the suite long
# before any assertion runs. The pre-retry form (`cmd &` then `PID=$!`) had no pipe and so no
# block; keeping the retry means keeping this redirect. No test reads a spawned child's stdout.
spawn_bg() {   # usage: pid=$(spawn_bg <cmd...>)
  local i pid
  for i in 1 2 3 4 5 6 7 8; do
    if { "$@" >/dev/null 2>&1 & } 2>/dev/null; then pid=$!; if [ -n "$pid" ]; then echo "$pid"; return 0; fi; fi
    sleep 0.25
  done
  return 1
}

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh — the ratchet that binds every NEW suite):
  # the subject resolves its own state under ~, so unfixtured this suite reads/writes the
  # operator's LIVE layer. Everything this suite asserts is already redirected elsewhere.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  B="$REPO/bin/cc-authbrowser"
  D="$BATS_TEST_TMPDIR"
  export CC_AUTHBROWSER_STATE_DIR="$D/state"
  export CC_AUTHBROWSER_PROFILE_ROOT="$D/profiles"
  export STUB_ARGV_LOG="$D/argv.log"
  mkdir -p "$CC_AUTHBROWSER_STATE_DIR" "$CC_AUTHBROWSER_PROFILE_ROOT"

  # --- account SSOT stub: `claude-accounts --relogin-info <acct>` ------------------------
  cat > "$D/accounts" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "--relogin-info" ] || exit 64
case "$2" in
  next|next2|next3|next4) echo "{\"name\":\"$2\"}" ;;
  *) echo "unknown account: $2" >&2; exit 1 ;;
esac
EOF
  chmod +x "$D/accounts"
  export CC_AUTHBROWSER_ACCOUNTS_BIN="$D/accounts"

  # --- chrome stub A: records argv, then SERVES /json/version and stays alive ------------
  cat > "$D/stub-chrome-ok" <<'EOF'
#!/usr/bin/env python3
import http.server, json, os, socketserver, sys
with open(os.environ["STUB_ARGV_LOG"], "w") as fh:
    fh.write("\n".join(sys.argv[1:]) + "\n")
port = 0
for a in sys.argv[1:]:
    if a.startswith("--remote-debugging-port="):
        port = int(a.split("=", 1)[1])
BODY = json.dumps({"Browser": "Chrome/999.0.0.0",
                   "webSocketDebuggerUrl": "ws://127.0.0.1:%d/devtools/browser/stub" % port,
                   "User-Agent": "Mozilla/5.0 StubChrome/999"}).encode()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/json/version":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(BODY)))
            self.end_headers()
            self.wfile.write(BODY)
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *a):
        pass
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("127.0.0.1", port), H).serve_forever()
EOF

  # --- chrome stub B: records argv, NEVER binds the port, stays alive (CDP timeout) ------
  cat > "$D/stub-chrome-silent" <<'EOF'
#!/usr/bin/env python3
import os, sys, time
with open(os.environ["STUB_ARGV_LOG"], "w") as fh:
    fh.write("\n".join(sys.argv[1:]) + "\n")
time.sleep(600)
EOF

  # --- chrome stub C: records argv, then dies immediately -------------------------------
  cat > "$D/stub-chrome-dies" <<'EOF'
#!/usr/bin/env python3
import os, sys
with open(os.environ["STUB_ARGV_LOG"], "w") as fh:
    fh.write("\n".join(sys.argv[1:]) + "\n")
sys.exit(1)
EOF

  # --- a FOREIGN listener: holds the port, is not a browser, must never be adopted/killed
  cat > "$D/foreign-listener" <<'EOF'
#!/usr/bin/env python3
import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen(8)
time.sleep(600)
EOF

  chmod +x "$D/stub-chrome-ok" "$D/stub-chrome-silent" "$D/stub-chrome-dies" "$D/foreign-listener"
  export CC_AUTHBROWSER_CHROME_BIN="$D/stub-chrome-ok"
}

teardown() {
  if [ -n "${B:-}" ]; then
    for a in next next2 next3 next4; do "$B" "$a" --stop >/dev/null 2>&1 || true; done
  fi
  # Scoped to THIS test's tmpdir — never a bare pattern that could match the runner.
  if [ -n "${D:-}" ]; then
    pkill -f "$D/stub-chrome" >/dev/null 2>&1 || true
    pkill -f "$D/foreign-listener" >/dev/null 2>&1 || true
  fi
}

alive() { # <pid> — true only when the pid exists AND is not a reaped zombie
  local st
  st="$(ps -o state= -p "$1" 2>/dev/null | tr -d ' ')"
  [ -n "$st" ] && [ "${st#Z}" = "$st" ]
}

port_open() { # <port> — true when something is accepting on 127.0.0.1:<port>
  python3 -c 'import socket,sys
s=socket.socket(); s.settimeout(0.5)
sys.exit(0 if s.connect_ex(("127.0.0.1", int(sys.argv[1]))) == 0 else 1)' "$1"
}

argv_has() { grep -qxF -- "$1" "$STUB_ARGV_LOG"; }

refute() { # <cmd…> — assert the command FAILS.
  # NEVER write a bare `! cmd` assertion: POSIX exempts `!`-prefixed pipelines from
  # errexit, so outside the FINAL line of a @test it is silently ignored and the
  # assertion is a no-op (shellcheck SC2314; verified here by breaking the impl and
  # watching a bare-`!` test still pass). `run` + an explicit status check always bites.
  run "$@"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------- start: shape + port map

@test "--start emits EXACTLY the frozen JSON keys, correct port, headless false by default" {
  run "$B" next --start
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r 'keys_unsorted|sort|join(",")')" = \
    "acct,headless,pid,port,profile_dir,user_agent,ws_url" ]
  [ "$(echo "$output" | jq -r '.acct')" = "next" ]
  [ "$(echo "$output" | jq -r '.port')" = "9341" ]
  [ "$(echo "$output" | jq -r '.headless')" = "false" ]
  [ "$(echo "$output" | jq -r '.ws_url')" = "ws://127.0.0.1:9341/devtools/browser/stub" ]
  [ "$(echo "$output" | jq -r '.user_agent')" = "Mozilla/5.0 StubChrome/999" ]
  echo "$output" | jq -e '.pid > 0'
}

@test "--start honours the frozen per-account port map (next2 -> 9342, not file order)" {
  run "$B" next2 --start
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.port')" = "9342" ]
  argv_has "--remote-debugging-port=9342"
}

@test "--start --json is accepted and still emits the frozen shape" {
  run "$B" next --start --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.port')" = "9341" ]
}

# ------------------------------------------------------------------- launch posture (argv)

@test "default posture is headed-offscreen: contract flags present, --headless ABSENT" {
  run "$B" next --start
  [ "$status" -eq 0 ]
  argv_has "--user-data-dir=$CC_AUTHBROWSER_PROFILE_ROOT/next"
  argv_has "--remote-debugging-port=9341"
  argv_has "--remote-debugging-address=127.0.0.1"
  argv_has "--window-position=-32000,-32000"
  argv_has "--no-first-run"
  argv_has "--no-default-browser-check"
  refute grep -q -- "--headless" "$STUB_ARGV_LOG"
  # the real profile root is never touched
  refute grep -q "auth-profiles" "$STUB_ARGV_LOG"
  [ -d "$CC_AUTHBROWSER_PROFILE_ROOT/next" ]
}

@test "--headless flips the posture: --headless=new reaches the launch argv" {
  run "$B" next --start --headless
  [ "$status" -eq 0 ]
  argv_has "--headless=new"
  [ "$(echo "$output" | jq -r '.headless')" = "true" ]
}

# --------------------------------------------------------------------------- REFUSED (2)

@test "unknown account is REFUSED (exit 2) on start, stop and status" {
  run "$B" bogus --start
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "unknown account"
  run "$B" bogus --stop
  [ "$status" -eq 2 ]
  run "$B" bogus --status
  [ "$status" -eq 2 ]
}

@test "bad args are REFUSED (exit 2): no mode, two modes, non-integer ttl" {
  run "$B" next
  [ "$status" -eq 2 ]
  run "$B" next --start --stop
  [ "$status" -eq 2 ]
  run "$B" next --start --ttl abc
  [ "$status" -eq 2 ]
}

@test "an account the SSOT refuses is REFUSED (exit 2) — identity is never assumed" {
  cat > "$D/accounts" <<'EOF'
#!/usr/bin/env bash
echo "unknown account" >&2; exit 1
EOF
  chmod +x "$D/accounts"
  run "$B" next --start
  [ "$status" -eq 2 ]
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json" ]
}

@test "a missing SSOT binary fails CLOSED (exit 2), never a silent degrade" {
  export CC_AUTHBROWSER_ACCOUNTS_BIN="$D/no-such-accounts-bin"
  run "$B" next --start
  [ "$status" -eq 2 ]
}

# --------------------------------------------------------------------- BROWSER-FAILED (4)

@test "missing chrome binary is BROWSER-FAILED (exit 4)" {
  export CC_AUTHBROWSER_CHROME_BIN="$D/no-such-chrome"
  run "$B" next --start
  [ "$status" -eq 4 ]
  echo "$output" | grep -qi "chrome binary missing"
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json" ]
}

@test "chrome that dies immediately is BROWSER-FAILED (exit 4), no state left" {
  export CC_AUTHBROWSER_CHROME_BIN="$D/stub-chrome-dies"
  run "$B" next --start
  [ "$status" -eq 4 ]
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json" ]
}

@test "CDP never coming up is BROWSER-FAILED (exit 4) and leaves NO orphan browser" {
  export CC_AUTHBROWSER_CHROME_BIN="$D/stub-chrome-silent"
  run "$B" next --start
  [ "$status" -eq 4 ]
  echo "$output" | grep -qi "CDP did not answer"
  run pgrep -f "$D/stub-chrome-silent"
  [ "$status" -ne 0 ]                       # the browser we launched was killed
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json" ]
  refute port_open 9341
}

@test "a FOREIGN process on the port is BROWSER-FAILED (exit 4) and is NOT killed" {
  if port_open 9341; then skip "port 9341 already in use on this machine"; fi
  FOREIGN=$(spawn_bg "$D/foreign-listener" 9341)
  for _ in 1 2 3 4 5 6 7 8 9 10; do port_open 9341 && break; sleep 0.2; done
  port_open 9341

  run "$B" next --start
  [ "$status" -eq 4 ]
  echo "$output" | grep -qi "foreign"
  alive "$FOREIGN"                           # never kill a browser/process we did not launch
  port_open 9341                             # never steal the port either
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json" ]

  { kill "$FOREIGN" && wait "$FOREIGN"; } 2>/dev/null || true
}

# ------------------------------------------------------------------------------ stop

@test "--stop is idempotent: exit 0 when nothing is running" {
  run "$B" next --stop
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "not running"
  run "$B" next --stop
  [ "$status" -eq 0 ]
}

@test "--start then --stop: state file gone, browser dead, NO listening port" {
  run "$B" next --start
  [ "$status" -eq 0 ]
  PID="$(echo "$output" | jq -r '.pid')"
  [ -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json" ]
  port_open 9341

  run "$B" next --stop
  [ "$status" -eq 0 ]
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json" ]
  refute alive "$PID"
  refute port_open 9341
}

@test "--stop also reaps the armed watchdog (no stale killer left behind)" {
  run "$B" next --start --ttl 600
  [ "$status" -eq 0 ]
  WD="$(jq -r '.watchdog_pid' "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json")"
  alive "$WD"
  run "$B" next --stop
  [ "$status" -eq 0 ]
  refute alive "$WD"
}

# ---------------------------------------------------------------------------- status

@test "--status when not running: exit 0, running=false, no browser keys" {
  run "$B" next --status --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.running')" = "false" ]
  [ "$(echo "$output" | jq -r '.acct')" = "next" ]
  run "$B" next --status
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "not running"
}

@test "--status when running: exit 0, running=true, carries the frozen browser keys" {
  run "$B" next --start
  [ "$status" -eq 0 ]
  PID="$(echo "$output" | jq -r '.pid')"

  run "$B" next --status --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.running')" = "true" ]
  [ "$(echo "$output" | jq -r '.pid')" = "$PID" ]
  [ "$(echo "$output" | jq -r '.port')" = "9341" ]
  [ "$(echo "$output" | jq -r '.headless')" = "false" ]

  run "$B" next --status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "running pid=$PID port=9341 headless=false"
}

@test "--status reports not-running once the recorded pid is gone (stale state file)" {
  run "$B" next --start
  [ "$status" -eq 0 ]
  run "$B" next --stop
  printf '{"acct":"next","pid":999999,"port":9341,"chrome_bin":"%s"}\n' \
    "$CC_AUTHBROWSER_CHROME_BIN" > "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json"
  run "$B" next --status --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.running')" = "false" ]
}

# ------------------------------------------------------------------- idempotent re-start

@test "--start twice does not relaunch and does not mistake our own browser for foreign" {
  run "$B" next --start
  [ "$status" -eq 0 ]
  PID="$(echo "$output" | jq -r '.pid')"
  run "$B" next --start
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.pid')" = "$PID" ]
}

# ------------------------------------------------------------------------ TTL watchdog

@test "--start arms a DETACHED watchdog that outlives the caller" {
  run "$B" next --start --ttl 600
  [ "$status" -eq 0 ]
  WD="$(jq -r '.watchdog_pid' "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json")"
  [ -n "$WD" ] && [ "$WD" != "null" ]
  alive "$WD"
  # its own session => not in the caller's process group, so the caller's death cannot reap it
  [ "$(ps -o pgid= -p "$WD" | tr -d ' ')" != "$(ps -o pgid= -p $$ | tr -d ' ')" ]
}

@test "TTL expiry hard-kills the browser and frees the CDP port" {
  run "$B" next --start --ttl 1
  [ "$status" -eq 0 ]
  PID="$(echo "$output" | jq -r '.pid')"
  port_open 9341
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do alive "$PID" || break; sleep 0.5; done
  refute alive "$PID"
  refute port_open 9341
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json" ]
}

@test "watchdog KILLS a pid whose command line still matches the browser we launched" {
  VICTIM=$(spawn_bg sleep 41)
  run "$B" next --watchdog --pid "$VICTIM" --ttl 0 --match "sleep 41"
  [ "$status" -eq 0 ]
  refute alive "$VICTIM"
  wait "$VICTIM" 2>/dev/null || true
}

@test "PID-RECYCLE GUARD: a pid whose command line no longer matches is NOT killed" {
  STRANGER=$(spawn_bg sleep 43)
  run "$B" next --watchdog --pid "$STRANGER" --ttl 0 \
    --match "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [ "$status" -eq 0 ]
  alive "$STRANGER"                          # the recycled pid survives — the load-bearing case
  kill "$STRANGER" 2>/dev/null || true
  wait "$STRANGER" 2>/dev/null || true
}

@test "PID-RECYCLE GUARD: an already-dead pid is a no-op, not an error" {
  DEAD=$(spawn_bg sleep 45)
  kill "$DEAD" 2>/dev/null || true
  wait "$DEAD" 2>/dev/null || true
  run "$B" next --watchdog --pid "$DEAD" --ttl 0 --match "sleep 45"
  [ "$status" -eq 0 ]
}

@test "watchdog clears the state file only when it still names the pid it killed" {
  VICTIM=$(spawn_bg sleep 47)
  printf '{"acct":"next3","pid":%d,"port":9343,"chrome_bin":"sleep 47"}\n' "$VICTIM" \
    > "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next3.json"
  run "$B" next3 --watchdog --pid "$VICTIM" --ttl 0 --match "sleep 47"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next3.json" ]
  wait "$VICTIM" 2>/dev/null || true

  # a state file naming a DIFFERENT pid belongs to a newer session — leave it alone
  V2=$(spawn_bg sleep 49)
  printf '{"acct":"next4","pid":123456,"port":9344,"chrome_bin":"sleep 49"}\n' \
    > "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next4.json"
  run "$B" next4 --watchdog --pid "$V2" --ttl 0 --match "sleep 49"
  [ "$status" -eq 0 ]
  [ -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next4.json" ]
  wait "$V2" 2>/dev/null || true
}
