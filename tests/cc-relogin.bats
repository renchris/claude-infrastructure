#!/usr/bin/env bats
# cc-relogin — the unattended OAuth re-auth executor. These tests are HERMETIC by construction:
# every external surface is a stub (claude-accounts, ps, /usr/bin/security, the claude binary,
# cc-authbrowser) and the heal lock lives under CC_RELOGIN_TMP. Nothing here ever performs a real
# sign-in, reads a real keychain item, or launches a real browser — that is a human-gated step.

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh — the ratchet that binds every NEW suite).
  # The header above already claims hermeticity, and every seam this suite KNOWS about is stubbed;
  # but bin/cc-relogin resolves its own state under ~, so unfixtured the subject still reads and
  # writes the operator's live layer. Free here — nothing below reads $HOME.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/bin/cc-relogin"

  # bin/cc-relogin is `#!/usr/bin/env python3`, so its interpreter is whatever PATH resolves —
  # and that makes any test of a POST-import code path silently PATH-dependent. Under a minimal
  # (launchd/hook) PATH, /usr/bin comes before Homebrew and wins: /usr/bin/python3 is the one
  # interpreter here WITHOUT websocket-client, so the lazy import fails first and the subject
  # exits 1 (dependency fault) before it can ever reach the CDP leg. A test asserting the CDP
  # verdict then measured the dep-fault leg instead — a dead assertion in exactly the environment
  # it exists to protect. The undeclared dependency is the TEST's, so the TEST resolves it, by
  # ABSOLUTE PATH as well as PATH (the pattern scripts/handoff-fire.sh uses for timeout(1)).
  # Empty ⇒ no such interpreter on this box ⇒ those tests skip loudly rather than mis-measure.
  # The dep-fault case itself is asserted separately and deliberately runs on the bare PATH.
  PY_WS=""
  for _c in "$(command -v python3 2>/dev/null || true)" \
            /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    [ -n "$_c" ] && [ -x "$_c" ] && "$_c" -c 'import websocket' 2>/dev/null \
      && { PY_WS="$_c"; break; }
  done
  D="$BATS_TEST_TMPDIR"
  CFG="$D/cfg-next3"
  LOCK="$D/claude-accounts-heal-next3.lock"
  export CC_RELOGIN_TMP="$D"
  export CC_RELOGIN_WARN_H=72
  export CC_RELOGIN_LOG="$D/cc-relogin.log"
  export CC_RELOGIN_ACCOUNTS_BIN="$D/stub-accounts"
  export CC_RELOGIN_PS_BIN="$D/stub-ps"
  export CC_RELOGIN_SECURITY_BIN="$D/stub-security"
  export CC_RELOGIN_AUTHBROWSER_BIN="$D/stub-authbrowser"

  # --- stubs: each serves a per-CALL fixture (foo.1.json, foo.2.json, …) so a "before" and an
  # --- "after" sweep can differ, falling back to foo.json when no per-call file exists.
  hdr() { { echo '#!/usr/bin/env bash'; echo "FIX=\"$D\""; } > "$1"; }

  # A bare `! cmd` is a SILENT NO-OP in bats unless it is the last line of the @test (POSIX
  # exempts !-inverted pipelines from errexit; shellcheck SC2314). Verified on bats 1.13.0.
  # Every negative assertion goes through this helper instead.
  refute() { run "$@"; [ "$status" -ne 0 ]; }

  hdr "$D/stub-accounts"
  cat >> "$D/stub-accounts" <<'STUB'
echo "accounts $*" >> "$FIX/accounts-calls"
bump() { local f="$FIX/n-$1" n; n=$(cat "$f" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$f"; echo "$n"; }
if [[ "$*" == *--relogin-info* ]]; then
  n=$(bump info)
  if [ -f "$FIX/info.rc" ]; then echo "unknown account: bogus (next|next2|next3|next4)" >&2; exit "$(cat "$FIX/info.rc")"; fi
  p="$FIX/info.$n.json"; [ -f "$p" ] || p="$FIX/info.json"; cat "$p"; exit 0
fi
if [[ "$*" == *--fresh* ]]; then
  n=$(bump fresh); p="$FIX/fresh.$n.json"; [ -f "$p" ] || p="$FIX/fresh.json"; cat "$p"; exit 0
fi
exit 1
STUB

  hdr "$D/stub-ps"
  cat >> "$D/stub-ps" <<'STUB'
n=$(cat "$FIX/n-ps" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FIX/n-ps"
p="$FIX/ps.$n"; [ -f "$p" ] || p="$FIX/ps"
if [ -f "$p" ]; then cat "$p"; fi
exit 0
STUB

  hdr "$D/stub-security"
  cat >> "$D/stub-security" <<'STUB'
echo "security $*" >> "$FIX/security-calls"
[ -f "$FIX/creds.json" ] || exit 44
cat "$FIX/creds.json"
STUB

  hdr "$D/stub-claude"
  cat >> "$D/stub-claude" <<'STUB'
{ echo "argv=$*"; echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"
  echo "CLAUDE_CODE_OAUTH_SCOPES=$CLAUDE_CODE_OAUTH_SCOPES"
  echo "RT_LEN=${#CLAUDE_CODE_OAUTH_REFRESH_TOKEN}"; } >> "$FIX/claude-calls"
echo "Login successful."
if [ -f "$FIX/claude.out" ]; then cat "$FIX/claude.out"; fi
# `exec` so the recorded pid IS the long-lived process — killing it must kill the whole child
if [ -f "$FIX/claude.sleep" ]; then echo $$ > "$FIX/claude.pid"; exec sleep 60; fi
exit "$(cat "$FIX/claude.rc" 2>/dev/null || echo 0)"
STUB

  hdr "$D/stub-authbrowser"
  cat >> "$D/stub-authbrowser" <<'STUB'
echo "authbrowser $*" >> "$FIX/authbrowser-calls"
case "$*" in
  *--start*)
    if [ -f "$FIX/ab.start.json" ]; then cat "$FIX/ab.start.json"; fi
    exit "$(cat "$FIX/ab.start.rc" 2>/dev/null || echo 0)" ;;
esac
exit 0
STUB
  chmod +x "$D"/stub-*

  # --- python unit-test harness: loads bin/cc-relogin as module `ccr` and drives its pure
  # --- seams (drive/click_authorize/await_oauth_url) with a duck-typed fake CDP. No socket,
  # --- no browser, no keychain — the CDP client is a constructor arg precisely so this works.
  cat > "$D/prelude.py" <<'PY'
import importlib.util, os, sys
from importlib.machinery import SourceFileLoader
# cc-relogin is extensionless (shebang-dispatched), so spec_from_file_location cannot infer a
# loader from the suffix and returns None — name SourceFileLoader explicitly.
spec = importlib.util.spec_from_file_location(
    "ccr", sys.argv[1], loader=SourceFileLoader("ccr", sys.argv[1]))
ccr = importlib.util.module_from_spec(spec); spec.loader.exec_module(ccr)
ccr.CALLBACK_TIMEOUT_S, ccr.POLL_S = 2.0, 0.02

class FakeChild:
    def __init__(self, rc=None): self._rc = rc; self.returncode = rc
    def poll(self): return self._rc
    def wait(self, timeout=None): self._rc = self.returncode = 0; return 0

class FakeCDP:
    def __init__(self, states=(), boxmodel=True, has_el=True):
        self.states, self.sent = list(states), []
        self.boxmodel, self.has_el = boxmodel, has_el
    def send(self, method, params=None, session=None):
        self.sent.append((method, params or {}))
        if method == "Runtime.evaluate":
            if "location.href" in (params or {}).get("expression", ""):
                return {"result": {"value": self.states.pop(0) if self.states else ""}}
            return {"result": {"objectId": "OID"} if self.has_el else {}}
        if method == "DOM.getBoxModel":
            if not self.boxmodel: raise RuntimeError("not rendered")
            return {"model": {"content": [10, 20, 30, 20, 30, 40, 10, 40]}}
        return {}
    def methods(self): return [m for m, _ in self.sent]
PY
  pyt() {  # body on stdin -> run against the loaded module; nonzero exit fails the test
    { cat "$D/prelude.py"; cat; } > "$D/t.py"
    run python3 "$D/t.py" "$C"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  }

  # --- fixture writers -------------------------------------------------------------------------
  mk_info() { # <n|all> <has_refresh_token> [keychain_state] [config_dir]
    local f="$D/info.$1.json"; [ "$1" = all ] && f="$D/info.json"
    cat > "$f" <<EOF
{"name":"next3","config_dir":"${4:-$CFG}","launcher":"claude3","email":"e@example.test",
 "dia_profile":"Claude3","dia_profile_dir":"/p",
 "keychain_service":"Claude Code-credentials-deadbeef","keychain_state":"${3:-present}",
 "claude_bin":"$D/stub-claude","oauth_scopes":"user:profile user:inference",
 "has_refresh_token":$2}
EOF
  }
  mk_fresh() { # <n|all> <auth> [login_expires_at] [login_expires_h]
    local f="$D/fresh.$1.json" extra=""
    [ "$1" = all ] && f="$D/fresh.json"
    [ -n "${3:-}" ] && extra="$extra,\"login_expires_at\":\"$3\""
    [ -n "${4:-}" ] && extra="$extra,\"login_expires_h\":$4"
    cat > "$f" <<EOF
{"window":{},"cached":false,"rows":[{"acct":"next3","email":"e@example.test",
 "launcher":"claude3","k":0,"auth":"$2"$extra}]}
EOF
  }
  mk_creds() { echo '{"claudeAiOauth":{"refreshToken":"rt-FIXTURE-not-a-real-token"}}' > "$D/creds.json"; }
  ps_live() { printf '%s\n' "/opt/c/bin/claude --resume  CLAUDE_CONFIG_DIR=$CFG" > "$D/ps.$1"; }
  # The common "needs a relogin, phase 1 available, no live sessions" fixture set.
  needy() { mk_info all true; mk_fresh 1 logged-out "2026-08-01T00:00:00Z"; mk_creds; }
  hold_lock() { # background holder of the heal lock -> pid in $HOLDER. NOT via $(…): a command
                # substitution would block on the backgrounded child's inherited stdout pipe.
    python3 -c 'import fcntl,sys,time;f=open(sys.argv[1],"w");fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB);time.sleep(30)' \
      "$LOCK" >/dev/null 2>&1 &
    HOLDER=$!
    sleep 0.5
  }
}

# ---- arg surface ----------------------------------------------------------------------------

@test "--help exits 0 and documents the CLI" {
  run "$C" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q -- '--no-browser'
  echo "$output" | grep -q 'PROVEN'
}

@test "no account name → REFUSED (2)" {
  run "$C"
  [ "$status" -eq 2 ]
}

@test "unexpected argument → REFUSED (2)" {
  run "$C" next3 --wat
  [ "$status" -eq 2 ]
}

# ---- the gate -------------------------------------------------------------------------------

@test "unknown account → REFUSED (2)" {
  echo 1 > "$D/info.rc"
  run "$C" bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi 'unknown account'
}

@test "healthy account (deadline far away) → REFUSED (2), nothing attempted" {
  mk_info all true; mk_fresh all ok "2027-01-01T00:00:00Z" 900
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'no re-auth needed'
  [ ! -f "$D/claude-calls" ]
}

@test "login_expires_h inside the warn window → NOT refused (proceeds past the need gate)" {
  mk_info all true; mk_fresh 1 ok "2026-08-01T00:00:00Z" 10; mk_creds
  run "$C" next3 --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .need_reason)" = "login_expires_h=10 <= warn 72.0" ]
}

@test "§2 degraded detection: no login_* fields and nothing else wrong → REFUSED, loudly" {
  mk_info all true; mk_fresh all ok
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'UNAVAILABLE'
}

@test "k>0 at the pre-lock snapshot → REFUSED (2), never touches the token" {
  needy; ps_live 1
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'live session'
  [ ! -f "$D/claude-calls" ]
}

@test "heal lock already held → REFUSED (2)" {
  needy
  hold_lock
  run "$C" next3
  kill "$HOLDER" 2>/dev/null || true
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'heal lock busy'
  [ ! -f "$D/claude-calls" ]
}

@test "under-lock re-check: k==0 at snapshot, k>0 under the lock → REFUSED (2)" {
  needy; ps_live 2                      # first ps call clean, second (under the lock) live
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'under the lock'
  [ ! -f "$D/claude-calls" ]
}

@test "headless one-shots (claude -p) are NOT live sessions — mirrors concurrency()" {
  needy
  printf '%s\n' "/opt/c/bin/claude -p hello  CLAUDE_CONFIG_DIR=$CFG" > "$D/ps"
  run "$C" next3 --dry-run
  [ "$status" -eq 0 ]
}

@test "attribution uses the LAST CLAUDE_CONFIG_DIR= on the line (ps -E appends env after argv)" {
  needy
  printf '%s\n' "/opt/c/bin/claude --resume CLAUDE_CONFIG_DIR=/decoy  CLAUDE_CONFIG_DIR=$CFG" > "$D/ps"
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'live session'
}

@test "bare claude counts toward the ~/.claude-next account (~/.claude mirrors it)" {
  mk_info all true "present" "$D/.claude-next"; mk_fresh 1 logged-out; mk_creds
  printf '%s\n' "/opt/c/bin/claude --resume" > "$D/ps"
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'live session'
}

@test "ps unavailable → live count UNKNOWN → REFUSED, never assumed idle" {
  needy
  export CC_RELOGIN_PS_BIN="$D/no-such-ps"
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'UNKNOWN'
}

# ---- --dry-run ------------------------------------------------------------------------------

@test "--dry-run: gate + plan, exit 0, mutates nothing, releases the lock" {
  needy
  run "$C" next3 --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'nothing mutated'
  [ ! -f "$D/claude-calls" ]            # no `claude auth login`
  [ ! -f "$D/security-calls" ]          # no keychain read
  [ ! -f "$D/authbrowser-calls" ]       # no browser
  run python3 -c 'import fcntl,sys;f=open(sys.argv[1],"w");fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)' "$LOCK"
  [ "$status" -eq 0 ]                   # the lock was released on exit
}

@test "--dry-run --json: result is 'dry-run', never a false 'proven'" {
  needy
  run "$C" next3 --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .result)" = "dry-run" ]
  [ "$(echo "$output" | jq -r .dry_run)" = "true" ]
  [ "$(echo "$output" | jq -r '.plan | length')" -eq 2 ]
}

# ---- phase 1 + verify-by-effect ---------------------------------------------------------------

@test "phase 1 + moved deadline → PROVEN (0)" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"
  mk_fresh 2 ok         "2026-09-01T00:00:00Z"
  run "$C" next3
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'deadline moved'
}

@test "phase 1 passes the account's scopes VERBATIM and its own config dir" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"; mk_fresh 2 ok "2026-09-01T00:00:00Z"
  run "$C" next3
  [ "$status" -eq 0 ]
  grep -q 'argv=auth login' "$D/claude-calls"
  grep -qx "CLAUDE_CODE_OAUTH_SCOPES=user:profile user:inference" "$D/claude-calls"
  grep -qx "CLAUDE_CONFIG_DIR=$CFG" "$D/claude-calls"
  grep -q 'RT_LEN=2[0-9]' "$D/claude-calls"
}

@test "report-only success (deadline did NOT move) with --no-browser → UNVERIFIED (5)" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"
  mk_fresh 2 ok         "2026-08-01T00:00:00Z"     # binary said "Login successful." — deadline stuck
  run "$C" next3 --no-browser
  [ "$status" -eq 5 ]
  echo "$output" | grep -q 'did NOT move'
}

@test "report-only success while auth is still broken → UNVERIFIED (5)" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"; mk_fresh 2 token-invalid "2026-09-01T00:00:00Z"
  run "$C" next3 --no-browser
  [ "$status" -eq 5 ]
  echo "$output" | grep -q "expected 'ok'"
}

@test "phase 1 never substitutes for phase 2: unmoved deadline escalates (→ 4, not 0/5)" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"; mk_fresh 2 ok "2026-08-01T00:00:00Z"
  run "$C" next3
  [ "$status" -eq 4 ]                   # reached phase 2 rather than declaring victory
  [ "$(echo "$output" | grep -c .)" -ge 1 ]
}

@test "§2 tolerance: no login_expires_at anywhere → PROVEN but the gap is named" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out; mk_fresh 2 ok
  run "$C" next3
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'UNVERIFIABLE'
}

@test "phase 1 binary failure + --no-browser → HEADLESS-EXHAUSTED (3)" {
  needy; echo 1 > "$D/claude.rc"
  run "$C" next3 --no-browser
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'phase 1 failed'
}

@test "no refresh token + --no-browser → HEADLESS-EXHAUSTED (3)" {
  mk_info all false; mk_fresh 1 logged-out
  run "$C" next3 --no-browser
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'no refresh token'
  [ ! -f "$D/claude-calls" ]
}

@test "keychain item unreadable + --no-browser → HEADLESS-EXHAUSTED (3), no login attempted" {
  mk_info all true; mk_fresh 1 logged-out          # no creds.json → stub-security exits 44
  run "$C" next3 --no-browser
  [ "$status" -eq 3 ]
  [ ! -f "$D/claude-calls" ]
}

# ---- phase 2 + error + shape -------------------------------------------------------------------

@test "phase 2 is reached when phase 1 is impossible and a browser is allowed → 4" {
  mk_info all false; mk_fresh 1 logged-out
  run "$C" next3
  [ "$status" -eq 4 ]
  echo "$output" | grep -q 'no OAuth URL printed'
}

# ---- phase 2 seams (real subprocesses; stub browser, never a real one) --------------------------

@test "phase 2: no OAuth URL printed → BROWSER-FAILED (4), transcript kept and named" {
  mk_info all false; mk_fresh 1 logged-out
  run "$C" next3 --url-timeout 2
  [ "$status" -eq 4 ]
  echo "$output" | grep -q 'login transcript kept'
  [ -f "$D/cc-relogin-next3.out" ]
  [ ! -e "$D/cc-relogin-next3.in" ]            # the fifo never outlives the run
}

@test "phase 2: cc-authbrowser --start failing → 4, and --stop is NOT called (never started)" {
  mk_info all false; mk_fresh 1 logged-out
  echo 'https://claude.ai/oauth/authorize?code_challenge=xyz' > "$D/claude.out"
  echo 4 > "$D/ab.start.rc"
  run "$C" next3 --url-timeout 5
  [ "$status" -eq 4 ]
  echo "$output" | grep -q 'cc-authbrowser --start exit 4'
  grep -q -- '--start' "$D/authbrowser-calls"
  refute grep -q -- '--stop' "$D/authbrowser-calls"
}

@test "phase 2: --start emitting no ws_url → 4, and teardown still stops the browser" {
  mk_info all false; mk_fresh 1 logged-out
  echo 'https://claude.ai/oauth/authorize?code_challenge=xyz' > "$D/claude.out"
  echo '{"acct":"next3","pid":123,"port":9343}' > "$D/ab.start.json"
  run "$C" next3 --url-timeout 5
  [ "$status" -eq 4 ]
  echo "$output" | grep -q 'no ws_url'
  grep -q -- '--stop' "$D/authbrowser-calls"
}

@test "phase 2: CDP unreachable → 4, and the browser is STILL stopped (teardown is unconditional)" {
  [ -n "$PY_WS" ] || skip "no python3 with websocket-client — this case needs the CDP leg reachable"
  mk_info all false; mk_fresh 1 logged-out
  echo 'https://claude.ai/oauth/authorize?code_challenge=xyz' > "$D/claude.out"
  echo '{"ws_url":"ws://127.0.0.1:1/devtools/browser/dead"}' > "$D/ab.start.json"
  run "$PY_WS" "$C" next3 --url-timeout 5
  [ "$status" -eq 4 ]
  grep -q -- '--stop' "$D/authbrowser-calls"
  [ ! -e "$D/cc-relogin-next3.in" ]
}

@test "a missing websocket-client is OUR dependency fault (1), never browser-failed (4)" {
  # Regression, carried over from trunk's b6961d5 when this executor replaced the Dia-CDP
  # driver. launchd's PATH has neither Homebrew nor the Framework, so the staged poller runs
  # on /usr/bin/python3 — the one interpreter here WITHOUT websocket-client. Reported as a 4
  # it sends the operator to fix a browser that started perfectly, for a pip problem.
  # The dep is stubbed ABSENT on PYTHONPATH (never skipped on) so this is machine-independent.
  mkdir -p "$D/pystub"
  echo 'raise ImportError("stubbed absent for this test")' > "$D/pystub/websocket.py"
  mk_info all false; mk_fresh 1 logged-out
  echo 'https://claude.ai/oauth/authorize?code_challenge=xyz' > "$D/claude.out"
  echo '{"ws_url":"ws://127.0.0.1:9341/devtools/browser/live"}' > "$D/ab.start.json"
  PYTHONPATH="$D/pystub" run "$C" next3 --url-timeout 5
  [ "$status" -eq 1 ]                        # ERROR — ours; NOT 4 BROWSER-FAILED
  echo "$output" | grep -q 'websocket-client is not installed'
  echo "$output" | grep -q 'NOT a browser failure'
  echo "$output" | grep -q 'pip install websocket-client'
  grep -q -- '--stop' "$D/authbrowser-calls"   # teardown is unconditional even on a dep fault
}

@test "phase 2: the login child is killed on teardown, never left running" {
  mk_info all false; mk_fresh 1 logged-out
  echo 'https://claude.ai/oauth/authorize?code_challenge=xyz' > "$D/claude.out"
  : > "$D/claude.sleep"
  echo 4 > "$D/ab.start.rc"
  run "$C" next3 --url-timeout 5
  [ "$status" -eq 4 ]
  [ -s "$D/claude.pid" ]
  refute kill -0 "$(cat "$D/claude.pid")"
}

@test "phase 2 never branches on cc-authbrowser --status exit code" {
  refute grep -qE '(if|&&|\|\|).*--status' "$C"
  grep -q 'NEVER branch on .*--status' "$C"
}

# ---- phase 2 driver unit tests (fake CDP — no socket, no browser) -------------------------------

@test "drive(): child already exited 0 (warm session, localhost callback) → PROVEN" {
  pyt <<'PY'
code, detail = ccr.drive(FakeCDP(), "s", FakeChild(0), 1, {"email": "e@x"})
assert code == 0, (code, detail)
PY
}

@test "drive(): code#state on the page is scraped and written to the fifo → PROVEN" {
  pyt <<'PY'
r, w = os.pipe()
page = "https://claude.ai/oauth/authorize\x00Your code:\nABCDEFGHIJKLMNOP1234#statevalue1\n"
code, detail = ccr.drive(FakeCDP([page]), "s", FakeChild(None), w, {"email": "e@x"})
assert code == 0, (code, detail)
os.close(w)
got = os.read(r, 400).decode()
assert "ABCDEFGHIJKLMNOP1234#statevalue1\n" in got, got
PY
}

@test "drive(): landing on /login → FALLBACK-REQUIRED (6) naming the exact human step + mailbox" {
  pyt <<'PY'
page = "https://claude.ai/login?return=1\x00Sign in to continue"
info = {"email": "acct@example.test", "mailbox": "mbox@example.test"}
code, detail = ccr.drive(FakeCDP([page]), "s", FakeChild(None), 1, info)
assert code == 6, (code, detail)
assert "mbox@example.test" in detail and "acct@example.test" in detail, detail
assert "claude.ai/login" in detail, detail
PY
}

@test "drive(): no outcome before the callback deadline → BROWSER-FAILED (4)" {
  pyt <<'PY'
ccr.CALLBACK_TIMEOUT_S = 0.3
code, detail = ccr.drive(FakeCDP(), "s", FakeChild(None), 1, {"email": "e@x"})
assert code == 4, (code, detail)
assert "callback timeout" in detail, detail
PY
}

@test "click_authorize(): dispatches a real press/release at the box-model centre" {
  pyt <<'PY'
cdp = FakeCDP()
assert ccr.click_authorize(cdp, "s") is True
kinds = [p["type"] for m, p in cdp.sent if m == "Input.dispatchMouseEvent"]
assert kinds == ["mousePressed", "mouseReleased"], kinds
pressed = [p for m, p in cdp.sent if m == "Input.dispatchMouseEvent"][0]
assert (pressed["x"], pressed["y"]) == (20.0, 30.0), pressed   # centre of the fixture quad
PY
}

@test "click_authorize(): falls back to el.click() when the box model is unavailable" {
  pyt <<'PY'
cdp = FakeCDP(boxmodel=False)
assert ccr.click_authorize(cdp, "s") is True
assert "Runtime.callFunctionOn" in cdp.methods(), cdp.methods()
assert "Input.dispatchMouseEvent" not in cdp.methods(), cdp.methods()
PY
}

@test "click_authorize(): no Authorize control → False (caller keeps polling, never claims a click)" {
  pyt <<'PY'
cdp = FakeCDP(has_el=False)
assert ccr.click_authorize(cdp, "s") is False
assert "DOM.getBoxModel" not in cdp.methods(), cdp.methods()
PY
}

@test "await_oauth_url(): takes the MANUAL url and ignores the auto-opened localhost variant" {
  pyt <<'PY'
import tempfile
p = os.path.join(tempfile.mkdtemp(), "out")
# Both loopback decoys come FIRST, so a driver that failed to skip them would return one.
# The https ones matter: an http:// decoy is excluded by the https-only regex rather than by
# the loopback filter, so it alone would leave that filter untested (caught by mutation P4).
open(p, "w").write(
    "Opening http://localhost:45123/oauth/authorize?code_challenge=plain in your browser\n"
    "Callback https://localhost:45123/oauth/authorize?code_challenge=loop1\n"
    "Callback https://127.0.0.1:45123/oauth/authorize?code_challenge=loop2\n"
    "Or visit: https://claude.ai/oauth/authorize?code_challenge=MANUAL&state=s1\n")
url = ccr.await_oauth_url(p, 2.0, FakeChild(None))
assert url == "https://claude.ai/oauth/authorize?code_challenge=MANUAL&state=s1", url
PY
}

@test "await_oauth_url(): child dies without printing a url → None (no 30s stall)" {
  pyt <<'PY'
import tempfile
p = os.path.join(tempfile.mkdtemp(), "out")
open(p, "w").write("error: could not reach the auth service\n")
assert ccr.await_oauth_url(p, 30.0, FakeChild(1)) is None
PY
}

@test "malformed --fresh --json → ERROR (1)" {
  mk_info all true; echo 'not json' > "$D/fresh.json"
  run "$C" next3
  [ "$status" -eq 1 ]
}

@test "--json emits the frozen result object" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"; mk_fresh 2 ok "2026-09-01T00:00:00Z"
  run "$C" next3 --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .acct)" = "next3" ]
  [ "$(echo "$output" | jq -r .result)" = "proven" ]
  [ "$(echo "$output" | jq -r .exit)" = "0" ]
  [ "$(echo "$output" | jq -r .phase_reached)" = "verify" ]
  [ "$(echo "$output" | jq -r .before.auth)" = "logged-out" ]
  [ "$(echo "$output" | jq -r .after.auth)" = "ok" ]
  [ "$(echo "$output" | jq -r .before.login_expires_at)" = "2026-08-01T00:00:00Z" ]
  [ "$(echo "$output" | jq -r .after.login_expires_at)" = "2026-09-01T00:00:00Z" ]
  [ -n "$(echo "$output" | jq -r .detail)" ]
}

@test "both measurement reads are --fresh --no-heal: a read that can heal is not independent" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"; mk_fresh 2 ok "2026-09-01T00:00:00Z"
  run "$C" next3
  [ "$status" -eq 0 ]
  # before + after, and NEITHER may re-enter probe_account's heal() -> `claude auth login`
  [ "$(grep -c -- '--fresh' "$D/accounts-calls")" -eq 2 ]
  [ "$(grep -- '--fresh' "$D/accounts-calls" | grep -c -- '--no-heal')" -eq 2 ]
  refute grep -e '--fresh --json' -e '--fresh$' "$D/accounts-calls"
}

@test "--json on a refusal carries the same shape" {
  mk_info all true; mk_fresh all ok "2027-01-01T00:00:00Z" 900
  run "$C" next3 --json
  [ "$status" -eq 2 ]
  [ "$(echo "$output" | jq -r .result)" = "refused" ]
  [ "$(echo "$output" | jq -r .phase_reached)" = "gate" ]
}

@test "a token in the child's output is redacted out of the result object and the log" {
  mk_info all true; mk_creds; echo 1 > "$D/claude.rc"
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"
  echo 'oauth failed for sk-ant-oat01-AAAAAAAAAAAAAAAAAAAAAAAA' > "$D/claude.out"
  run "$C" next3 --no-browser --json
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'REDACTED'
  echo "$output" > "$D/out.txt"
  refute grep -q 'sk-ant-oat01-A' "$D/out.txt"
  refute grep -q 'sk-ant-oat01-A' "$CC_RELOGIN_LOG"
}

@test "exit 7 CONSENT-GATE is retained for consumers but no code path emits it" {
  [ "$(grep -c 'EXIT_CONSENT_GATE' "$C")" -eq 1 ]     # the definition only — never passed to emit()
  grep -q '7: "consent-gate"' "$C"
}
