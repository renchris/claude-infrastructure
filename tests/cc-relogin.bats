#!/usr/bin/env bats
# cc-relogin — the gate, the phase ladder, the CDP consent gate, and verify-by-effect.
#
# Hermetic: a stub claude-accounts, a scratch TMP for the lock/fifo, and a port-file path that
# does not exist. Nothing touches the real keychain, the real accounts, or Dia. The account
# identity in the stub uses a config_dir that cannot appear in a real `ps` line, so the live
# session count is genuinely 0 rather than mocked away.

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh — the ratchet that binds every NEW suite).
  # The header above already claims hermeticity, and every seam this suite KNOWS about is stubbed;
  # but bin/cc-relogin resolves its own state under ~, so unfixtured the subject still reads and
  # writes the operator's live layer. Free here — nothing below reads $HOME.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Hermeticity (scripts/test-hermeticity-lint.sh): cc-relogin resolves keychain/profile paths
  # and would otherwise read the live ~/. Every other path this suite touches is already
  # fixtured under $BATS_TEST_TMPDIR; $HOME was the one remaining leak.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export BIN="$REPO/bin/cc-relogin"
  export STUB="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_RELOGIN_ACCOUNTS_BIN="$STUB"
  export CC_RELOGIN_TMP="$BATS_TEST_TMPDIR"
  export CC_RELOGIN_DEVTOOLS_PORT_FILE="$BATS_TEST_TMPDIR/nonexistent-DevToolsActivePort"
  export ROWS="$BATS_TEST_TMPDIR/rows.json"
  export INFO="$BATS_TEST_TMPDIR/info.json"
  export STUB_ARGV="$BATS_TEST_TMPDIR/accounts-argv.log"

  cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${STUB_ARGV:-/dev/null}"
for a in "$@"; do
  case "$a" in
    --relogin-info) mode=relogin ;;
    *) : ;;
  esac
done
if [ "${mode:-}" = relogin ]; then cat "$INFO"; exit 0; fi
cat "$ROWS"; exit 0
STUBEOF
  chmod +x "$STUB"

  # A STUB websocket module, ahead of site-packages on PYTHONPATH. Two reasons, both about the
  # suite certifying something real:
  #   1. Hermeticity. `import websocket` resolved against whichever python3 the PATH gave us —
  #      every interpreter here has websocket-client EXCEPT /usr/bin/python3, so the consent-gate
  #      tests went RED with exit 4 under a minimal PATH (launchd's, notably). The suite's green
  #      was reporting the ambient environment, not the code.
  #   2. Determinism. The unreachable-port test previously depended on 127.0.0.1:59999 genuinely
  #      refusing a connection — a real network dependency, and silently vacuous the day anything
  #      binds that port. The stub raises on connect, which is the condition under test.
  # It records the URL it was handed, so a test can prove the port file was parsed and USED
  # rather than that some earlier error happened to produce the same verdict.
  export WS_STUB_DIR="$BATS_TEST_TMPDIR/wsstub"
  export WS_URL_LOG="$BATS_TEST_TMPDIR/ws-url.log"
  mkdir -p "$WS_STUB_DIR"
  cat > "$WS_STUB_DIR/websocket.py" <<'WSEOF'
import os


def create_connection(url, **kw):
    with open(os.environ["WS_URL_LOG"], "a") as f:
        f.write(url + "\n")
    raise ConnectionRefusedError("stub: nothing is listening")
WSEOF
  export PYTHONPATH="$WS_STUB_DIR${PYTHONPATH:+:$PYTHONPATH}"

  # default fixture: an account that genuinely needs a login, no live sessions
  rows '{"rows":[{"acct":"next3","auth":"login-required","k":0,"login_expires_at":"2026-08-08T01:07:00+00:00","login_expires_h":300.0}]}'
  info '{"config_dir":"/tmp/cc-relogin-test-nonexistent-xyz","claude_bin":"/nonexistent/claude","email":"t@example.com","mailbox":"t@example.com","dia_profile":"T","dia_profile_dir":"/nonexistent/Profile T","keychain_service":"svc","keychain_account":"tester","oauth_scopes":"a b","keychain_state":"present","has_refresh_token":false,"refresh_token_expired":false}'
}

rows() { printf '%s' "$1" > "$ROWS"; }
info() { printf '%s' "$1" > "$INFO"; }

LOAD='
import importlib.machinery, importlib.util, os
loader = importlib.machinery.SourceFileLoader("ccr", os.environ["BIN"])
ccr = importlib.util.module_from_spec(importlib.util.spec_from_loader("ccr", loader))
loader.exec_module(ccr)
'

# ---- read-only posture -----------------------------------------------------------------------

@test "every accounts READ carries --no-heal — a measurement must not move what it measures" {
  # claude-accounts heals a stale row on the way out (probe_account -> `stale and not no_heal`
  # -> heal() -> `claude auth login`). Two failures if a read omits --no-heal: a READ mutates
  # credentials (and can rotate a token out from under a live session, which the k>0 guard
  # exists to prevent), and — worse — verify() treats "refresh-token expiry moved FORWARD" as
  # the observable effect proving a real grant, which is exactly what `claude auth login` does.
  # A heal fired BY the measuring read would therefore manufacture a PROVEN verdict for work
  # the verification did itself. Pinned here because no other test would notice the regression.
  run "$BIN" next3 --dry-run
  [ -s "$STUB_ARGV" ]                       # positive control: reads actually happened
  local saw_read=0
  while IFS= read -r line; do
    case "$line" in
      *--relogin-info*) continue ;;         # identity lookup, not a status read
    esac
    saw_read=1
    case "$line" in
      *--no-heal*) ;;
      *) echo "accounts read WITHOUT --no-heal: $line" >&2; return 1 ;;
    esac
  done < "$STUB_ARGV"
  [ "$saw_read" -eq 1 ]                      # and at least one was a status read
}

# ---- the gate --------------------------------------------------------------------------------

@test "gate: a HEALTHY account is refused — never re-login what is not broken" {
  rows '{"rows":[{"acct":"next3","auth":"ok","k":0,"login_expires_h":500.0}]}'
  run "$BIN" next3 --json
  [ "$status" -eq 2 ]
  [[ "$output" == *'"result": "refused"'* ]]
  [[ "$output" == *"does not need a relogin"* ]]
}

@test "gate: an unknown account is refused, not crashed" {
  cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
echo "unknown account: nope" >&2; exit 1
EOF
  chmod +x "$STUB"
  run "$BIN" nope --json
  [ "$status" -eq 2 ]
  [[ "$output" == *'"result": "refused"'* ]]
}

@test "gate: live sessions block the relogin — that CC owns the token lifecycle" {
  run python3 -c "$LOAD"'
import json, os
# a ps line carrying this account'"'"'s CLAUDE_CONFIG_DIR = a live interactive owner
info = {"config_dir": "/x/.claude-tertiary", "claude_bin": "/x/bin/claude"}
ccr.run = lambda *a, **k: type("P", (), {
    "stdout": "/x/bin/claude --model opus CLAUDE_CONFIG_DIR=/x/.claude-tertiary\n",
    "stderr": "", "returncode": 0})()
assert ccr.live_sessions("next3", info) == 1
# a one-shot -p invocation is NOT an interactive owner of the token
ccr.run = lambda *a, **k: type("P", (), {
    "stdout": "/x/bin/claude -p hello CLAUDE_CONFIG_DIR=/x/.claude-tertiary\n",
    "stderr": "", "returncode": 0})()
assert ccr.live_sessions("next3", info) == 0
# another account'"'"'s sessions never count toward this one
ccr.run = lambda *a, **k: type("P", (), {
    "stdout": "/x/bin/claude CLAUDE_CONFIG_DIR=/x/.claude-secondary\n",
    "stderr": "", "returncode": 0})()
assert ccr.live_sessions("next3", info) == 0
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "gate: a held heal lock refuses — the SAME lock claude-accounts heal() takes" {
  # hold the exact lock path the driver will try
  python3 -c "
import fcntl, time, sys
f = open('$BATS_TEST_TMPDIR/claude-accounts-heal-next3.lock', 'w')
fcntl.flock(f, fcntl.LOCK_EX)
time.sleep(5)" &
  local holder=$!
  sleep 0.7
  run "$BIN" next3 --json
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 2 ]
  [[ "$output" == *"another heal/relogin is in flight"* ]]
}

@test "gate: --dry-run names the plan and mutates nothing" {
  run "$BIN" next3 --dry-run --json
  [ "$status" -eq 2 ]
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" == *"phase2 (phase 1 cannot succeed)"* ]]   # no refresh token in the fixture
  [ ! -e "$BATS_TEST_TMPDIR/cc-relogin-next3.in" ]         # no fifo created
  # the lock was probed and RELEASED, not left held
  run python3 -c "
import fcntl
f = open('$BATS_TEST_TMPDIR/claude-accounts-heal-next3.lock', 'w')
fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
print('lock free')"
  [ "$status" -eq 0 ] && [[ "$output" == *"lock free"* ]]
}

# ---- the need predicate ----------------------------------------------------------------------

@test "needs_relogin: fires on the fixable states and the cliff, stays quiet otherwise" {
  run python3 -c "$LOAD"'
i = {}
for s in ("logged-out", "token-invalid", "no-oauth-blob", "login-required"):
    assert ccr.needs_relogin({"auth": s}, i)[0] is True, s
# keychain-error is NOT a credential state — a relogin is the wrong action for it
assert ccr.needs_relogin({"auth": "keychain-error"}, i)[0] is False
assert ccr.needs_relogin({"auth": "probe-error"}, i)[0] is False
assert ccr.needs_relogin({"auth": "ok", "login_expired": True}, i)[0] is True
assert ccr.needs_relogin({"auth": "ok", "login_expires_h": 20.0}, i)[0] is True
assert ccr.needs_relogin({"auth": "ok", "login_expires_h": 500.0}, i)[0] is False
# an OLDER claude-accounts emits no login_* fields at all: absence is NOT "not expiring",
# so the keychain/identity signals still decide
assert ccr.needs_relogin({"auth": "ok"}, {"keychain_state": "no-keychain-item"})[0] is True
assert ccr.needs_relogin({"auth": "ok"}, {"refresh_token_expired": True})[0] is True
assert ccr.needs_relogin({"auth": "ok"}, {})[0] is False
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

# ---- verify by EFFECT ------------------------------------------------------------------------

@test "verify: a claimed success with no moved expiry is UNVERIFIED, not proven" {
  run python3 -c "$LOAD"'
before = {"login_expires_at": "2026-08-08T01:07:00+00:00"}
# auth ok, token present, but the expiry did NOT advance ⇒ the grant did not really happen
ccr.accounts_json = lambda fresh=False: {"rows": [{"acct": "a", "auth": "ok",
    "login_expires_at": "2026-08-08T01:07:00+00:00"}]}
ccr.relogin_info = lambda a: {"has_refresh_token": True}
ok, after, detail = ccr.verify("a", before)
assert ok is False and "did not advance" in detail, (ok, detail)
# expiry moved forward ⇒ proven
ccr.accounts_json = lambda fresh=False: {"rows": [{"acct": "a", "auth": "ok",
    "login_expires_at": "2026-09-01T00:00:00+00:00"}]}
assert ccr.verify("a", before)[0] is True
# auth not ok ⇒ never proven, whatever the binary said
ccr.accounts_json = lambda fresh=False: {"rows": [{"acct": "a", "auth": "stale",
    "login_expires_at": "2026-09-01T00:00:00+00:00"}]}
assert ccr.verify("a", before)[0] is False
# token vanished ⇒ never proven
ccr.accounts_json = lambda fresh=False: {"rows": [{"acct": "a", "auth": "ok",
    "login_expires_at": "2026-09-01T00:00:00+00:00"}]}
ccr.relogin_info = lambda a: {"has_refresh_token": False}
assert ccr.verify("a", before)[0] is False
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

# ---- phase ladder ----------------------------------------------------------------------------

@test "--no-browser: phase 1 impossible ⇒ HEADLESS-EXHAUSTED (3), never a silent browser fire" {
  run "$BIN" next3 --no-browser --json
  [ "$status" -eq 3 ]
  [[ "$output" == *'"result": "headless-exhausted"'* ]]
  [[ "$output" == *'"phase_reached": "phase1"'* ]]
}

@test "an EXPIRED refresh token skips phase 1 — it cannot succeed by construction" {
  info '{"config_dir":"/tmp/cc-relogin-test-nonexistent-xyz","claude_bin":"/nonexistent/claude","email":"t@e","mailbox":"t@e","dia_profile":"T","dia_profile_dir":"/nonexistent/P","keychain_service":"svc","keychain_account":"tester","oauth_scopes":"a b","keychain_state":"present","has_refresh_token":true,"refresh_token_expired":true}'
  run "$BIN" next3 --dry-run --json
  [ "$status" -eq 2 ]
  [[ "$output" == *"phase2 (phase 1 cannot succeed)"* ]]
  # ...whereas a LIVE refresh token plans phase 1 first (cheaper, browser-free)
  info '{"config_dir":"/tmp/cc-relogin-test-nonexistent-xyz","claude_bin":"/nonexistent/claude","email":"t@e","mailbox":"t@e","dia_profile":"T","dia_profile_dir":"/nonexistent/P","keychain_service":"svc","keychain_account":"tester","oauth_scopes":"a b","keychain_state":"present","has_refresh_token":true,"refresh_token_expired":false}'
  run "$BIN" next3 --dry-run --json
  [[ "$output" == *"phase1 then phase2"* ]]
}

# ---- the CDP consent gate --------------------------------------------------------------------

@test "CONSENT-GATE (7): a missing port file is distinct from a browser failure" {
  # phase 1 impossible + browser allowed ⇒ straight to phase 2, where CDP is unreachable.
  # It must NOT be reported as BROWSER-FAILED: the recovery is a human toggling dia://inspect,
  # and a wrong code sends the operator looking for the wrong problem.
  run "$BIN" next3 --json
  [ "$status" -eq 7 ]
  [[ "$output" == *'"result": "consent-gate"'* ]]
  [[ "$output" == *"dia://inspect"* ]]                     # the recovery is named, not implied
  [[ "$output" == *'"phase_reached": "phase2"'* ]]
}

@test "CONSENT-GATE (7): an unreachable port ALSO reads as consent, with the cycle recovery" {
  printf '59999\n/devtools/browser/deadbeef\n' > "$CC_RELOGIN_DEVTOOLS_PORT_FILE"
  run "$BIN" next3 --json
  [ "$status" -eq 7 ]
  [[ "$output" == *"consent-free"* ]]                      # names the toggle-cycle property
  # positive control: the verdict came from a REFUSED HANDSHAKE, not from some earlier error that
  # happens to land on the same code. The stub logs what it was asked to dial, so this also pins
  # that both lines of the port file were parsed into the address.
  [ -s "$WS_URL_LOG" ] || false
  grep -qx 'ws://127.0.0.1:59999/devtools/browser/deadbeef' "$WS_URL_LOG" || false
}

@test "a missing websocket-client is OUR dependency fault (1), never browser-failed (4)" {
  # The regression this pins: `import websocket` used to sit ABOVE the port-file check, so an
  # interpreter without websocket-client turned every phase-2 verdict into browser-failed —
  # including the two consent-gate cases above, whose real recovery is a human toggling
  # dia://inspect. That is the exact misdirection this file's own docstring argues against, and
  # it is not hypothetical: `#!/usr/bin/env python3` under launchd resolves /usr/bin/python3,
  # the one interpreter here WITHOUT the dep. So: remote-debugging-OFF still wins (it is the
  # operator's real blocker either way), and a genuinely absent dep reports as ERROR naming pip.
  local poison="$BATS_TEST_TMPDIR/wspoison"
  mkdir -p "$poison"
  printf 'raise ImportError("no websocket-client (test)")\n' > "$poison/websocket.py"

  # port file ABSENT ⇒ still the consent gate: a dep fault must not mask the cheaper verdict
  PYTHONPATH="$poison" run "$BIN" next3 --json
  [ "$status" -eq 7 ]
  [[ "$output" == *'"result": "consent-gate"'* ]]

  # port file PRESENT ⇒ the dep is now genuinely load-bearing, and it is reported as ours
  printf '59999\n/devtools/browser/deadbeef\n' > "$CC_RELOGIN_DEVTOOLS_PORT_FILE"
  PYTHONPATH="$poison" run "$BIN" next3 --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"result": "error"'* ]]
  [[ "$output" == *"websocket-client is not installed"* ]]
  [[ "$output" == *"pip install websocket-client"* ]]      # the remedy is runnable, not implied
  [[ "$output" == *"NOT a browser failure"* ]]             # and it refuses the wrong attribution
  [[ "$output" == *'"phase_reached": "phase2"'* ]]
}

# ---- the JSON contract -----------------------------------------------------------------------

@test "--json: every frozen contract field is present on a terminal verdict" {
  run "$BIN" next3 --json
  echo "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in ("acct", "result", "exit", "phase_reached", "before", "after", "detail"):
    assert k in d, k
assert d["exit"] in range(8), d["exit"]
assert d["result"] in ("proven","refused","headless-exhausted","browser-failed","unverified",
                       "fallback-required","consent-gate","error"), d["result"]
assert set(d["before"]) >= {"auth","has_refresh_token","login_expires_at"}, d["before"]
print("OK")'
}

@test "no path prints a traceback — a crash is exit 1 with a one-line reason" {
  cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
echo 'not json at all'
EOF
  chmod +x "$STUB"
  run "$BIN" next3 --json
  [ "$status" -eq 1 ]
  [[ "$output" != *"Traceback"* ]]
  [[ "$output" == *'"result": "error"'* ]]
}
