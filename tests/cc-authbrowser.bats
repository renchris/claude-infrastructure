#!/usr/bin/env bats
# cc-authbrowser — the dedicated per-account Chrome substrate. Hermetic: every test drives a FAKE
# chrome-bin stub (a python script that records its argv and optionally serves a stub CDP endpoint)
# via CC_AUTHBROWSER_CHROME_BIN, with state + profiles redirected into BATS_TEST_TMPDIR. Real Chrome
# is NEVER launched; ~/.claude/auth-profiles is NEVER touched; nothing authenticates anything.
#
# PORTS ARE ISOLATED TOO (backlog e280bbc8b6e4 / e5e102446d6c). A TCP port is machine-wide, so it
# was the ONE global the STATE_DIR / PROFILE_ROOT seams above could not cover: this file used to
# bind the frozen 127.0.0.1:9341-9344 directly, and since this box runs 5+ concurrent landers each
# gating the full tree, two copies of THIS FILE overlapped and fought. Proven on pristine main
# 2026-07-26 — two simultaneous copies went 20 ok/6 not ok and 21 ok/5 not ok, with a DIFFERENT
# failing subset each time, while a solo run was 26/26. That is a fleet-wide FALSE red: it burns
# ship-land's single exoneration re-run and blocks a land while proving nothing about the tree.
# It also collided with any REAL auth browser the operator had running on 9341.
#
# The header this replaces said the port was un-fakeable because contract §1 hardcodes it. True of
# the old code, but the conclusion was the wrong way round: the fix belonged in the SUBJECT, not in
# a lock. bin/cc-authbrowser now resolves its port block through CC_AUTHBROWSER_PORT_BASE (default
# 9341 ⇒ the frozen map is unchanged), so setup_file below leases this run a PRIVATE block and no
# two runs can meet. Never reintroduce a bare 934x literal here — use $P_NEXT..$P_NEXT4.
#
# This REPLACES the interim machine-wide mutex that landed for e5e102446d6c while the seam was
# being built (that commit named this seam as the proper fix). The two must not coexist: a mutex
# serializes every lander on the box behind one copy of this suite, which is the cost the lease
# exists to remove — and two `setup_file` definitions in one file silently resolve to whichever
# is defined last, so keeping both leaves a landmine that a reorder would arm.
#
# THE PORT WAS NOT THE ONLY GLOBAL — TIME IS ONE TOO (backlog 53e2fd9a8253, 2026-07-30). The
# paragraph above called the port "the ONE global the STATE_DIR / PROFILE_ROOT seams could not
# cover". Measurement says otherwise: with the lease provably working — 19 concurrent copies,
# 19 distinct blocks, verified live — this suite still went 5/19 RED, and a targeted re-run of
# the two failing tests went 8/16 RED on a clean box. Not one failure was a port collision.
# Every one was a fixed WALL-CLOCK BUDGET in the subject blowing under load: 6 exceeded the 15s
# CDP wait, and 2 exceeded the 10s lsof — and that second one is the nastier failure, because a
# timed-out lsof yields NO pids, so do_start's adoption check misses and cc-authbrowser reports
# the browser it JUST LAUNCHED as "held by a foreign process (pids=unknown)". Wall-clock is
# machine-wide exactly as a port is. setup() therefore pins CC_AUTHBROWSER_CDP_TIMEOUT_S and
# CC_AUTHBROWSER_PROC_TIMEOUT_S; production defaults are untouched. Never delete those pins:
# unpinned, this file measures the box's load average and calls the result a test result.

# Fork can transiently fail (EAGAIN) when this box is running dozens of concurrent bats suites,
# and a bare `cmd &` then aborts the whole test under errexit — a spurious RED that blocks a
# landing while proving nothing. Observed 2026-07-25: `sleep 45 &' failed at ~57 concurrent
# bats processes, then passed on the next gate round. Every one of these tests needs SOME pid,
# never a specific one, so retrying the spawn preserves the semantics exactly.
#
# The child's stdout MUST be redirected. Callers use `pid=$(spawn_bg ...)`, and a command
# substitution blocks until EVERY holder of its stdout pipe closes it — not merely until the
# function returns. A backgrounded child inherits that pipe, so without this redirect
# `FOREIGN=$(spawn_bg "$D/foreign-listener" "$P_NEXT")` blocks for the listener's full 600s sleep
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

# ── the CDP port lease ────────────────────────────────────────────────────────────────────────
# This run leases ONE private block of 4 consecutive ports and drives the subject onto it with
# CC_AUTHBROWSER_PORT_BASE. `mkdir` is the claim: it is atomic and macOS ships no flock(1), so two
# concurrent runs racing the same block index cannot both win. Deliberately an ALLOCATOR, not a
# mutex — a mutex serializes every lander behind one suite; a lease lets them all run at once,
# which is the actual goal. The range starts well above the frozen 9341-9344 so a lease can never
# disturb a REAL account browser.
#
# THE ROOT IS DELIBERATELY NOT UNDER $TMPDIR. An allocator only allocates if every contender
# shares ONE namespace, and the gate runners on this box re-point TMPDIR per run precisely so
# each gets a private scratch: scripts/postland-verify.sh hands the WHOLE corpus a fresh
# RUN_TMP (:940,:942 — launchd every 300s, plus a detached kick after every land), and
# scripts/ship-land.sh does the same for its one exoneration re-run (:949). A TMPDIR-derived
# root gives each of those its OWN lease dir, so both win "slot 0" and both land on 19341 —
# the original collision through a different door, and block_free() cannot see it because it
# probes once at setup_file time, before any test has bound anything. This was not theory:
# ~/.claude/autonomy/postland/flakes.jsonl records tests/cc-authbrowser.bats flaking at
# 2026-07-29T07:44:42Z on sha dc12c8db — which CONTAINS the port-lease fix ab8df95b — in
# phase=postland, i.e. on exactly that private-TMPDIR path. One box, one allocator.
cdp_lease_root() {   # keep as a FUNCTION so the TMPDIR-independence above is testable
  echo "/tmp/cc-authbrowser-cdp-lease.${UID:-$(id -u)}"
}
CDP_LEASE_ROOT="$(cdp_lease_root)"
CDP_LEASE_BASE0=19341      # echoes 9341; far from the 49152+ ephemeral range
CDP_LEASE_SPAN=4           # one port per frozen account (contract §1 has four)
CDP_LEASE_SLOTS=64         # 64 concurrent copies of this suite; the fleet runs ~5
CDP_LEASE_WAIT_S=600       # only ever reached if all 64 are held by LIVE holders

block_free() {  # <base> — true when every port in the block is unbound right now
  local b="$1" i
  for i in $(seq 0 $((CDP_LEASE_SPAN - 1))); do
    port_open $((b + i)) && return 1     # something (foreign or a peer) already has it
  done
  return 0
}

try_lease() {   # claim the first block that is both unclaimed and actually free; 0 on success
  local n claim holder base
  for n in $(seq 0 $((CDP_LEASE_SLOTS - 1))); do
    claim="$CDP_LEASE_ROOT/$n"
    if ! mkdir "$claim" 2>/dev/null; then
      holder="$(cat "$claim/pid" 2>/dev/null || echo '')"
      if [ -z "$holder" ]; then
        # EMPTY is not DEAD. The winner of `mkdir` writes its pid on the very next line, so
        # a pidless claim is almost always a peer that won the race microseconds ago —
        # reaping it here would hand the SAME block to two suites, which is exactly the
        # collision this lease exists to prevent. Only a pidless claim that has AGED is
        # garbage (a death inside that one-syscall window).
        [ -n "$(find "$claim" -maxdepth 0 -mmin +1 2>/dev/null)" ] || continue
      elif kill -0 "$holder" 2>/dev/null; then
        continue
      fi
      # A SIGKILLed run never reaches teardown_file, so a claim whose holder is gone is
      # garbage, not an owner. Reaping it is what stops one killed lander wedging a slot
      # forever. (A recycled pid only makes us SKIP a free block — the safe direction.)
      rm -rf "$claim" 2>/dev/null || true
      mkdir "$claim" 2>/dev/null || continue
    fi
    echo "${BATS_ROOT_PID:-$$}" > "$claim/pid" 2>/dev/null || true
    base=$((CDP_LEASE_BASE0 + n * CDP_LEASE_SPAN))
    if block_free "$base"; then
      export CC_AUTHBROWSER_PORT_BASE="$base"
      export CDP_LEASE_HELD="$claim"
      return 0
    fi
    rm -rf "$claim" 2>/dev/null || true   # a foreign process squats here — try the next slot
  done
  return 1
}

setup_file() {
  mkdir -p "$CDP_LEASE_ROOT" 2>/dev/null || true
  local waited=0
  until try_lease; do
    # Exhaustion means 64 LIVE copies of this one suite. Unreachable at fleet scale, and
    # transient by construction (every holder is a running suite that will finish), so WAIT
    # rather than fail — a lease that can turn a green tree red would be worse than the
    # collision it prevents. `>&3` is not guaranteed open here, hence the `|| true`.
    if [ "$waited" -ge "$CDP_LEASE_WAIT_S" ]; then
      echo "# cc-authbrowser: no free CDP block after ${waited}s across $CDP_LEASE_SLOTS slots" \
        >&3 2>/dev/null || true
      export CC_AUTHBROWSER_PORT_BASE=$((CDP_LEASE_BASE0 + (${BATS_ROOT_PID:-$$} % CDP_LEASE_SLOTS) * CDP_LEASE_SPAN))
      export CDP_LEASE_HELD=""
      return 0
    fi
    sleep 2; waited=$((waited + 2))
  done
}

teardown_file() {
  [ -n "${CDP_LEASE_HELD:-}" ] && rm -rf "$CDP_LEASE_HELD" 2>/dev/null
  return 0
}

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh — the ratchet that binds every NEW suite):
  # the subject resolves its own state under ~, so unfixtured this suite reads/writes the
  # operator's LIVE layer. Everything this suite asserts is already redirected elsewhere.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # never resolve ~ to the operator's tree
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  B="$REPO/bin/cc-authbrowser"
  D="$BATS_TEST_TMPDIR"
  export CC_AUTHBROWSER_STATE_DIR="$D/state"
  export CC_AUTHBROWSER_PROFILE_ROOT="$D/profiles"
  export STUB_ARGV_LOG="$D/argv.log"
  mkdir -p "$CC_AUTHBROWSER_STATE_DIR" "$CC_AUTHBROWSER_PROFILE_ROOT"

  # This run's leased ports, in contract §1 account order. A lease that failed to reach us
  # would leave the subject on its frozen 9341-9344 default — silently reinstating the exact
  # collision this file exists to prevent — so an absent lease is LOUD, never a fallback.
  [ -n "${CC_AUTHBROWSER_PORT_BASE:-}" ] || { echo "no CDP lease from setup_file" >&2; return 1; }
  # PIN THE SUBJECT'S WALL-CLOCK BUDGETS. Isolating the port was necessary and NOT sufficient:
  # with every copy provably on its own block, 8 of 16 concurrent copies still went RED
  # (measured 2026-07-30, load ~40) because the subject's fixed budgets are bets on an idle
  # box — 6 blew the 15s CDP wait, and 2 blew the 10s lsof, which returns no pids and so makes
  # do_start call the browser it JUST STARTED "foreign (pids=unknown)". Unpinned, this suite
  # measures ambient machine load, not cc-authbrowser: the same defect scripts/test-hermeticity
  # -lint.sh rule 2 exists to catch. These are CEILINGS, not sleeps — the happy path returns as
  # soon as the stub answers, so a generous value costs a passing run nothing. The one test that
  # WANTS the CDP wait to expire pins it back down locally; that is why the two knobs are split.
  export CC_AUTHBROWSER_CDP_TIMEOUT_S=180
  export CC_AUTHBROWSER_PROC_TIMEOUT_S=120

  P_NEXT=$((CC_AUTHBROWSER_PORT_BASE))
  P_NEXT2=$((CC_AUTHBROWSER_PORT_BASE + 1))
  P_NEXT3=$((CC_AUTHBROWSER_PORT_BASE + 2))
  P_NEXT4=$((CC_AUTHBROWSER_PORT_BASE + 3))

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

json_body() { # <$output> — the JSON object alone, for jq.
  # bats merges stderr into $output, and the fallback-port path deliberately warn()s to stderr
  # BEFORE printing its JSON, so feeding $output straight to jq is a parse error. Slice from the
  # first line that opens the object; the frozen shape is pretty-printed, so `^{` matches once.
  echo "$1" | sed -n '/^{/,$p'
}

port_map_of() { # <base>|--unset — the subject's OWN acct→port map, read without binding anything.
  # Loads bin/cc-authbrowser as a module (its `__main__` guard means nothing executes), so the
  # frozen map can be asserted against the REAL 9341-9344 while peers are running: no listener,
  # no race. Insertion order is ACCOUNTS order, so the joined string pins the ORDER too.
  local prog='import importlib.machinery as m, importlib.util as u, sys
ld = m.SourceFileLoader("ccab", sys.argv[1]); sp = u.spec_from_loader("ccab", ld)
mod = u.module_from_spec(sp); ld.exec_module(mod)
print(",".join("%s=%d" % kv for kv in mod.port_map().items()))'
  if [ "$1" = "--unset" ]; then
    env -u CC_AUTHBROWSER_PORT_BASE python3 -c "$prog" "$B"
  else
    CC_AUTHBROWSER_PORT_BASE="$1" python3 -c "$prog" "$B"
  fi
}

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
  [ "$(echo "$output" | jq -r '.port')" = "$P_NEXT" ]
  [ "$(echo "$output" | jq -r '.headless')" = "false" ]
  [ "$(echo "$output" | jq -r '.ws_url')" = "ws://127.0.0.1:$P_NEXT/devtools/browser/stub" ]
  [ "$(echo "$output" | jq -r '.user_agent')" = "Mozilla/5.0 StubChrome/999" ]
  echo "$output" | jq -e '.pid > 0'
}

@test "--start honours the frozen per-account port map (next2 -> base+1, not file order)" {
  run "$B" next2 --start
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.port')" = "$P_NEXT2" ]
  argv_has "--remote-debugging-port=$P_NEXT2"
}

@test "--start --json is accepted and still emits the frozen shape" {
  run "$B" next --start --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.port')" = "$P_NEXT" ]
}

# ------------------------------------------------------- CC_AUTHBROWSER_PORT_BASE (the seam)

@test "FROZEN SS1 MAP is unchanged: with no base set the map is exactly next=9341..next4=9344" {
  # The contract the seam must not break. Read from the subject itself, so it stays true even
  # if the default is ever refactored again.
  run port_map_of --unset
  [ "$status" -eq 0 ]
  [ "$output" = "next=9341,next2=9342,next3=9343,next4=9344" ]
}

@test "the seam shifts the WHOLE block: every account keeps its contract offset from the base" {
  run port_map_of 23456
  [ "$status" -eq 0 ]
  [ "$output" = "next=23456,next2=23457,next3=23458,next4=23459" ]
}

@test "SET-but-EMPTY base is REFUSED verbatim — never laundered into the frozen default" {
  # The load-bearing half of the convention. `os.environ.get(X) or DEFAULT` cannot tell unset
  # from set-empty, so it would silently serve 9341 here — and a run that believes it is
  # isolated would bind the REAL account port. Empty is a caller bug; it must say so.
  export CC_AUTHBROWSER_PORT_BASE=""
  run "$B" next --start
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "CC_AUTHBROWSER_PORT_BASE"
  [ ! -f "$STUB_ARGV_LOG" ]     # the chrome stub never ran ⇒ no port was bound anywhere
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json" ]
}

@test "a junk or out-of-range base is REFUSED (exit 2), never degraded to a bindable port" {
  export CC_AUTHBROWSER_PORT_BASE="${P_NEXT}x"
  run "$B" next --start
  [ "$status" -eq 2 ]
  export CC_AUTHBROWSER_PORT_BASE=" $P_NEXT"    # leading space — not a plain integer
  run "$B" next --start
  [ "$status" -eq 2 ]
  export CC_AUTHBROWSER_PORT_BASE=100           # privileged
  run "$B" next --start
  [ "$status" -eq 2 ]
  export CC_AUTHBROWSER_PORT_BASE=65535         # the 4-port block would run past 65535
  run "$B" next --start
  [ "$status" -eq 2 ]
  [ ! -f "$STUB_ARGV_LOG" ]
}

@test "an invalid base fails CLOSED on --stop and --status too, not just --start" {
  export CC_AUTHBROWSER_PORT_BASE="not-a-port"
  run "$B" next --stop
  [ "$status" -eq 2 ]
  run "$B" next --status
  [ "$status" -eq 2 ]
  # …but an UNKNOWN account still reports itself: membership is checked before the port
  run "$B" bogus --status
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "unknown account"
}

# The three below assert the CLAIM PROTOCOL, not port probing, so they stub block_free out.
# Left live they would probe real ports and could fail on whatever a peer happens to hold —
# a test for an anti-flake mechanism must not itself be a flake.

@test "LEASE RACE: a claim whose pid is not written YET is never stolen (the mkdir→echo window)" {
  block_free() { return 0; }
  CDP_LEASE_ROOT="$D/lease"; mkdir -p "$CDP_LEASE_ROOT/0"   # a peer won it microseconds ago
  try_lease
  [ "$CC_AUTHBROWSER_PORT_BASE" -ne "$CDP_LEASE_BASE0" ]    # we took a DIFFERENT slot
  [ -d "$CDP_LEASE_ROOT/0" ]                                # and left theirs standing
}

@test "LEASE: an AGED pidless claim IS reaped — a death in that window must not wedge a slot" {
  block_free() { return 0; }
  CDP_LEASE_ROOT="$D/lease"; mkdir -p "$CDP_LEASE_ROOT/0"
  touch -t 202601010000 "$CDP_LEASE_ROOT/0"                 # older than the grace window
  try_lease
  [ "$CC_AUTHBROWSER_PORT_BASE" -eq "$CDP_LEASE_BASE0" ]    # slot 0 reclaimed
}

@test "LEASE: a LIVE holder is skipped, a DEAD one is reclaimed" {
  block_free() { return 0; }
  CDP_LEASE_ROOT="$D/lease"
  mkdir -p "$CDP_LEASE_ROOT/0"; echo $$ > "$CDP_LEASE_ROOT/0/pid"          # us: alive
  mkdir -p "$CDP_LEASE_ROOT/1"; echo 999999 > "$CDP_LEASE_ROOT/1/pid"      # nobody: dead
  try_lease
  [ "$CC_AUTHBROWSER_PORT_BASE" -eq $((CDP_LEASE_BASE0 + CDP_LEASE_SPAN)) ]  # skipped 0, took 1
  [ -d "$CDP_LEASE_ROOT/0" ]
}

@test "POSITIVE CONTROL: this run really is leased off the frozen ports (isolation not inert)" {
  # If the lease ever silently stops working, every assertion above still passes while the
  # suite quietly returns to fighting peers on 9341. This is the test that notices.
  [ -n "${CC_AUTHBROWSER_PORT_BASE:-}" ]
  [ "$CC_AUTHBROWSER_PORT_BASE" -ge 19341 ]
  [ "$P_NEXT" -ne 9341 ]
  [ "$P_NEXT4" -ne 9344 ]
  run "$B" next --start
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.port')" = "$P_NEXT" ]
  argv_has "--remote-debugging-port=$P_NEXT"
  refute argv_has "--remote-debugging-port=9341"
}

@test "POSITIVE CONTROL: the lease root is TMPDIR-INDEPENDENT — one allocator per box" {
  # Without this, a refactor back to \${TMPDIR}/… passes every other test in the file while
  # silently handing postland-verify and ship-land's exoneration re-run their own private
  # allocator (see the header). The lease would look healthy and allocate collisions.
  a="$(export TMPDIR=/tmp/cdp-probe-aaa; cdp_lease_root)"
  b="$(export TMPDIR=/tmp/cdp-probe-bbb; cdp_lease_root)"
  c="$(unset TMPDIR; cdp_lease_root)"
  [ -n "$a" ]
  [ "$a" = "$b" ]
  [ "$a" = "$c" ]
  [ "${a#/}" != "$a" ]                        # absolute, so cwd cannot fork the namespace
  [ "${a#*cdp-probe}" = "$a" ]                # and carries no fragment of either TMPDIR
  [ "$CDP_LEASE_ROOT" = "$a" ]                # the LIVE root really is this function's value
}

@test "POSITIVE CONTROL: the wall-clock budgets are PINNED, and the subject honours them" {
  # Two halves, both load-bearing. (1) THIS run is pinned — an unpinned suite silently goes
  # back to measuring ambient load. (2) The subject actually reads the seam and fails CLOSED
  # on junk: without (2), a typo'd export would leave the suite on the 15s default while (1)
  # still passed, which is precisely how an isolation seam rots into decoration.
  [ -n "${CC_AUTHBROWSER_CDP_TIMEOUT_S:-}" ]
  [ -n "${CC_AUTHBROWSER_PROC_TIMEOUT_S:-}" ]

  for bad in "" "abc" " 15" "0" "-1"; do
    export CC_AUTHBROWSER_CDP_TIMEOUT_S="$bad"
    run "$B" next --start
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "CC_AUTHBROWSER_CDP_TIMEOUT_S"
    [ ! -f "$STUB_ARGV_LOG" ]                 # refused BEFORE any browser was launched
  done

  export CC_AUTHBROWSER_CDP_TIMEOUT_S=180     # restore, then prove the OTHER knob too
  export CC_AUTHBROWSER_PROC_TIMEOUT_S="junk"
  run "$B" next --start
  [ "$status" -eq 2 ]
  # …and it fails CLOSED on the read-only modes as well, never just on --start
  run "$B" next --status
  [ "$status" -eq 2 ]
  run "$B" next --stop
  [ "$status" -eq 2 ]
  export CC_AUTHBROWSER_PROC_TIMEOUT_S=120

  # EFFECT-READ, not just validation. Everything above still passes if the subject VALIDATES
  # both knobs and then uses its hardcoded 15/10 anyway — a seam that is checked but unwired
  # is decoration, and this file already learned that lesson once about the port. So drive
  # each knob to a budget no process on earth can meet and demand the corresponding verdict.
  export CC_AUTHBROWSER_CDP_TIMEOUT_S=0.001
  run "$B" next --start
  [ "$status" -eq 4 ]
  echo "$output" | grep -qi "CDP did not answer"      # ⇒ the CDP knob reaches the readiness wait
  export CC_AUTHBROWSER_CDP_TIMEOUT_S=180

  # With our OWN browser up, an unmeetable lsof budget must fall CLOSED to "pids=unknown" —
  # which is precisely the production failure observed under load, so this asserts the seam
  # reaches the listener lookup AND pins the shape of the failure it is there to prevent.
  run "$B" next --start
  [ "$status" -eq 0 ]
  export CC_AUTHBROWSER_PROC_TIMEOUT_S=0.001
  run "$B" next --start
  [ "$status" -eq 4 ]
  echo "$output" | grep -q "pids=unknown"
}

# ------------------------------------------------------------------- launch posture (argv)

@test "default posture is headed-offscreen: contract flags present, --headless ABSENT" {
  run "$B" next --start
  [ "$status" -eq 0 ]
  argv_has "--user-data-dir=$CC_AUTHBROWSER_PROFILE_ROOT/next"
  argv_has "--remote-debugging-port=$P_NEXT"
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
  # The ONE test that wants the CDP wait to EXPIRE, so it pins setup()'s load-immunity
  # ceiling back down: this stub never binds, so the deadline is always burned in full and
  # the suite-wide 180s would be spent as dead wall-clock on every single run. Any value
  # yields the same verdict here — a stub that never answers cannot answer late.
  export CC_AUTHBROWSER_CDP_TIMEOUT_S=5
  run "$B" next --start
  [ "$status" -eq 4 ]
  echo "$output" | grep -qi "CDP did not answer"
  run pgrep -f "$D/stub-chrome-silent"
  [ "$status" -ne 0 ]                       # the browser we launched was killed
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json" ]
  refute port_open "$P_NEXT"
}

# A FOREIGN holder on the frozen port used to be EXIT_BROWSER (exit 4). That assertion was not
# stale-but-harmless — it PINNED the defect: 9341-9344 is also inside the range this box hands to
# per-worktree Node --inspect debuggers, so on 2026-08-08 `pnpm dev` out of one reso worktree held
# 9341 (next) and 9342 (next2), `--start` refused, and cc-relogin's phase 2 -- the ONLY leg that
# moves the ~30-day login deadline -- had never once launched. The safety property was never the
# refusal; it is "never adopt or kill what we did not launch", and that is asserted BELOW, on the
# path that now succeeds. Reverting the subject reddens this test on its very first assertion.
@test "a FOREIGN process on the frozen port: browser STARTS on a fallback port, foreign untouched" {
  if port_open "$P_NEXT"; then skip "leased port $P_NEXT already in use on this machine"; fi
  FOREIGN=$(spawn_bg "$D/foreign-listener" "$P_NEXT")
  for _ in 1 2 3 4 5 6 7 8 9 10; do port_open "$P_NEXT" && break; sleep 0.2; done
  port_open "$P_NEXT"

  run "$B" next --start
  [ "$status" -eq 0 ]                        # the collision is survived, not fatal
  echo "$output" | grep -qi "foreign"        # ...and it is still REPORTED, never silent
  GOT="$(json_body "$output" | jq -r '.port')"
  [ "$GOT" != "$P_NEXT" ]                    # the discriminator: a DIFFERENT port was used
  [ "$GOT" -ge 1024 ]
  port_open "$GOT"                           # the browser really is listening there
  # ws_url must carry the fallback port — cc-relogin dials THIS string, not the frozen map.
  json_body "$output" | jq -r '.ws_url' | grep -q "127.0.0.1:$GOT/"
  [ "$(jq -r '.port' "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json")" = "$GOT" ]

  alive "$FOREIGN"                           # never kill a process we did not launch
  port_open "$P_NEXT"                        # never steal the port either

  { kill "$FOREIGN" && wait "$FOREIGN"; } 2>/dev/null || true
}

# The regression this fix could plausibly introduce. Idempotency USED to be keyed on the frozen
# port ("is our pid among that port's listeners"), which cannot see a browser living on a fallback
# port: a second --start would find the frozen port still foreign-held, fall back AGAIN, and leave
# a SECOND browser running for one account. Keying on the state file's own port is what prevents
# that, and same-pid is the assertion that proves it.
@test "IDEMPOTENT ON A FALLBACK PORT: a 2nd --start adopts our browser, never launches a 2nd" {
  if port_open "$P_NEXT"; then skip "leased port $P_NEXT already in use on this machine"; fi
  FOREIGN=$(spawn_bg "$D/foreign-listener" "$P_NEXT")
  for _ in 1 2 3 4 5 6 7 8 9 10; do port_open "$P_NEXT" && break; sleep 0.2; done

  run "$B" next --start
  [ "$status" -eq 0 ]
  PID1="$(json_body "$output" | jq -r '.pid')"; PORT1="$(json_body "$output" | jq -r '.port')"
  [ "$PORT1" != "$P_NEXT" ]

  run "$B" next --start
  [ "$status" -eq 0 ]
  [ "$(json_body "$output" | jq -r '.pid')"  = "$PID1" ]
  [ "$(json_body "$output" | jq -r '.port')" = "$PORT1" ]

  alive "$FOREIGN"
  { kill "$FOREIGN" && wait "$FOREIGN"; } 2>/dev/null || true
}

@test "--stop tears down a browser started on a FALLBACK port and leaves the foreign one alone" {
  if port_open "$P_NEXT"; then skip "leased port $P_NEXT already in use on this machine"; fi
  FOREIGN=$(spawn_bg "$D/foreign-listener" "$P_NEXT")
  for _ in 1 2 3 4 5 6 7 8 9 10; do port_open "$P_NEXT" && break; sleep 0.2; done

  run "$B" next --start
  [ "$status" -eq 0 ]
  PID="$(json_body "$output" | jq -r '.pid')"; PORT="$(json_body "$output" | jq -r '.port')"

  run "$B" next --stop
  [ "$status" -eq 0 ]
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json" ]
  refute alive "$PID"
  refute port_open "$PORT"                   # the fallback port is freed...
  alive "$FOREIGN"; port_open "$P_NEXT"      # ...and the foreign holder is still untouched

  { kill "$FOREIGN" && wait "$FOREIGN"; } 2>/dev/null || true
}

@test "free_port() returns a real, currently-unheld loopback port" {
  local prog='import importlib.machinery as m, importlib.util as u, socket, sys
ld = m.SourceFileLoader("ccab", sys.argv[1]); sp = u.spec_from_loader("ccab", ld)
mod = u.module_from_spec(sp); ld.exec_module(mod)
p = mod.free_port()
assert isinstance(p, int) and 1024 <= p <= 65535, p
s = socket.socket(); s.settimeout(0.5)
assert s.connect_ex(("127.0.0.1", p)) != 0, "free_port returned a port already in LISTEN"
print(p)'
  run python3 -c "$prog" "$B"
  [ "$status" -eq 0 ]
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
  port_open "$P_NEXT"

  run "$B" next --stop
  [ "$status" -eq 0 ]
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json" ]
  refute alive "$PID"
  refute port_open "$P_NEXT"
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
  [ "$(echo "$output" | jq -r '.port')" = "$P_NEXT" ]
  [ "$(echo "$output" | jq -r '.headless')" = "false" ]

  run "$B" next --status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "running pid=$PID port=$P_NEXT headless=false"
}

@test "--status reports not-running once the recorded pid is gone (stale state file)" {
  run "$B" next --start
  [ "$status" -eq 0 ]
  run "$B" next --stop
  printf '{"acct":"next","pid":999999,"port":'"$P_NEXT"',"chrome_bin":"%s"}\n' \
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

# THE PATH WAS A GLOBAL TOO — and it is the one that convicted the test above (backlog
# f4614d85ec2c, RED @ b3f728858a6f). The header's two isolation seams cover the port and the
# wall clock; neither covers WHICH BINARIES THE CALLER CAN RESOLVE. lsof(8) lives in /usr/sbin,
# and com.claude.postland-verify's plist exports
# PATH="$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" — no /usr/sbin. A
# bare-name `lsof` therefore raised FileNotFoundError under the verifier and NOWHERE ELSE:
# port_listener_pids() caught it as "unreadable", and the SECOND --start reported the browser it
# had just launched as "held by a foreign process (pids=unknown)". The test above is the ONLY one
# in this file that needs a NON-EMPTY lsof result, which is exactly why it convicted alone while
# 296/296 passed under an interactive PATH — and why the failure is DETERMINISTIC, so the retry
# ladder wrote it as a hard red with no flakes.jsonl entry to acquit it.
#
# scripts/postland-verify.sh refuses to normalize PATH ON PURPOSE (:119) so this class stays
# detectable, and names the remedy at :140: the artifact resolves its tools by ABSOLUTE PATH as
# well as PATH. This test is the RED-prover for that fix in bin/cc-authbrowser (tool_path()).
@test "PATH-INDEPENDENT: --start stays idempotent when the caller's PATH cannot resolve lsof" {
  # Build the hostile PATH by DELETION, never as a literal: /opt/homebrew/bin ships an lsof on
  # some boxes, and a hardcoded list would then silently stop hiding it and pass vacuously.
  MINPATH=""
  for d in /usr/bin /bin /opt/homebrew/bin /usr/local/bin; do
    [ -d "$d" ] || continue
    [ -x "$d/lsof" ] && continue
    MINPATH="${MINPATH:+$MINPATH:}$d"
  done

  # Two controls, both load-bearing. (1) the fixture really does hide lsof — else this test
  # asserts nothing. (2) it does NOT hide python3 or ps: the subject's shebang needs the first
  # and its pid-recycle guard the second, so without this a red here could mean "we broke the
  # shebang", and the test would go on "RED-proving" a fix it never exercised.
  run env PATH="$MINPATH" sh -c 'command -v lsof'
  [ "$status" -ne 0 ]
  run env PATH="$MINPATH" sh -c 'command -v python3 && command -v ps'
  [ "$status" -eq 0 ]

  run env PATH="$MINPATH" "$B" next --start
  [ "$status" -eq 0 ]
  PID="$(echo "$output" | jq -r '.pid')"

  # The load-bearing pair: exit 0 rules out the "foreign process" refusal (its only other exit
  # is 4), and the pid equality rules out the other way to reach 0 — a silent RELAUNCH.
  run env PATH="$MINPATH" "$B" next --start
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.pid')" = "$PID" ]
}

# ------------------------------------------------------------------------ TTL watchdog

@test "--start arms a DETACHED watchdog that outlives the caller" {
  run "$B" next --start --ttl 600
  [ "$status" -eq 0 ]
  WD="$(jq -r '.watchdog_pid' "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next.json")"
  [ -n "$WD" ] && [ "$WD" != "null" ] || false
  alive "$WD"
  # its own session => not in the caller's process group, so the caller's death cannot reap it
  [ "$(ps -o pgid= -p "$WD" | tr -d ' ')" != "$(ps -o pgid= -p $$ | tr -d ' ')" ]
}

@test "TTL expiry hard-kills the browser and frees the CDP port" {
  run "$B" next --start --ttl 1
  [ "$status" -eq 0 ]
  PID="$(echo "$output" | jq -r '.pid')"
  port_open "$P_NEXT"
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do alive "$PID" || break; sleep 0.5; done
  refute alive "$PID"
  refute port_open "$P_NEXT"
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
  printf '{"acct":"next3","pid":%d,"port":'"$P_NEXT3"',"chrome_bin":"sleep 47"}\n' "$VICTIM" \
    > "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next3.json"
  run "$B" next3 --watchdog --pid "$VICTIM" --ttl 0 --match "sleep 47"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next3.json" ]
  wait "$VICTIM" 2>/dev/null || true

  # a state file naming a DIFFERENT pid belongs to a newer session — leave it alone
  V2=$(spawn_bg sleep 49)
  printf '{"acct":"next4","pid":123456,"port":'"$P_NEXT4"',"chrome_bin":"sleep 49"}\n' \
    > "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next4.json"
  run "$B" next4 --watchdog --pid "$V2" --ttl 0 --match "sleep 49"
  [ "$status" -eq 0 ]
  [ -f "$CC_AUTHBROWSER_STATE_DIR/cc-authbrowser-next4.json" ]
  wait "$V2" 2>/dev/null || true
}
