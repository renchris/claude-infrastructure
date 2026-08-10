#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats: every @test body IS its own subshell, so an `export` inside one
#   is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are invoked from those test
#   subshells rather than from file scope (SC2329).
#
# scripts/cloud-create-api.py — the ENVIRONMENT axis (docs/plans/CLOUD_OBSERVABILITY.md §13.3/§13.4).
#
# WHAT THIS SUITE IS ACTUALLY GUARDING. The defect this file exists against is not a wrong answer,
# it is a HALF-RIGHT one. Sources and environment are two independent axes, and for three weeks
# every create got exactly one of them:
#
#   · `claude --cloud`            → a real VM, `sources: []`         → the work happens, the push 403s
#   · POST /v1/code/sessions      → `sources: 1`, `environment_kind: bridge` → the push would work,
#                                    but nothing ever runs: a bridge session executes on a CONNECTED
#                                    CLIENT, so it sits at `working / disconnected / 0 output tokens`
#                                    forever and that state does NOT look like an error.
#
# Both halves are individually plausible and individually shipped, so the tests below pin them
# SEPARATELY — one mutant per half [[per-site-mutation-attributes-coverage]]. A single "acceptance
# failed" test would go green if the tool started ignoring whichever half the fixture did not move.
#
# HERMETIC BY CONSTRUCTION: a stub HTTP server on 127.0.0.1 serves canned API responses and RECORDS
# every request (method, path, headers, body) to a log the tests assert against — so a test can
# convict the tool for asking the wrong endpoint, not merely for printing the wrong thing. No test
# reaches api.anthropic.com, a keychain, or a real account: credentials come from the documented
# CC_CLOUD_ORG_UUID / CC_CLOUD_ACCESS_TOKEN seam.
#
# POSITIVE CONTROLS: every refusal assertion is paired with the fixture that DOES pass, in the same
# suite and off the same server — a gate that refuses everything is not a gate.

setup() {
  SUT="${BATS_TEST_DIRNAME}/../scripts/cloud-create-api.py"
  [ -f "$SUT" ] || skip "cloud-create-api.py not present"
  command -v python3 >/dev/null 2>&1 || skip "python3 required"

  # FIXTURE $HOME FIRST. The subject expands `~/.claude/accounts.json` and, failing that, shells out
  # to `security find-generic-password` — so an unfixtured suite would read the OPERATOR'S account
  # map and poke the real keychain on the two credential tests below. Green on this box, red or
  # prompting on any other, for a reason no test names.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  export SRV_DIR="$BATS_TEST_TMPDIR/srv"
  mkdir -p "$SRV_DIR"
  export REQLOG="$SRV_DIR/requests.ndjson"
  export CC_CLOUD_ORG_UUID="org-fixture-0000"
  export CC_CLOUD_ACCESS_TOKEN="tok-fixture-0000"
}

teardown() {
  # `|| true` on the KILL ITSELF, not on the line's tail. A kill on an already-reaped child returns
  # 1, and `2>/dev/null` silences its noise but not its STATUS — under errexit that aborts the body
  # before the trailing `return 0` is ever reached, so a green test fails for tidying up
  # successfully, and only under load. [[kill-on-reaped-child-fails-fast-path-hides-it]]
  [ -n "${SRV_PID:-}" ] && { kill "$SRV_PID" 2>/dev/null || true; }
  return 0
}

# start_srv <envs-json> <session-post-json> <session-get-json>
#   Boots the stub and exports CC_CLOUD_API_BASE. The GET response is what the tool's acceptance
#   gate reads, and it is a SEPARATE fixture from the POST response on purpose: §13.3's whole
#   content is that the create's own echo and the built session diverged.
start_srv() {
  # STOP THE PREVIOUS ONE FIRST. A test that calls this twice (the minted-environment control does)
  # would otherwise overwrite SRV_PID and orphan the first server — teardown then kills only the
  # second, and bats blocks forever waiting on a child nothing will reap. That is not a slow test,
  # it is a hung suite, and it presents as a bare timeout with no failing assertion to read.
  [ -n "${SRV_PID:-}" ] && { kill "$SRV_PID" 2>/dev/null || true; }
  printf '%s' "$1" >"$SRV_DIR/envs.json"
  printf '%s' "$2" >"$SRV_DIR/post.json"
  printf '%s' "$3" >"$SRV_DIR/get.json"
  : >"$REQLOG"

  cat >"$SRV_DIR/server.py" <<'PY'
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

D = os.environ["SRV_DIR"]
LOG = os.environ["REQLOG"]


def canned(name):
    with open(os.path.join(D, name)) as fh:
        return fh.read()


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):  # the stub's own chatter is not evidence
        pass

    def _record(self, method, body):
        with open(LOG, "a") as fh:
            fh.write(json.dumps({
                "method": method,
                "path": self.path,
                "headers": {k.lower(): v for k, v in self.headers.items()},
                "body": body,
            }) + "\n")

    def _send(self, text, code=200):
        raw = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        self._record("GET", None)
        if self.path == "/v1/environment_providers":
            return self._send(canned("envs.json"))
        if self.path.startswith("/v1/code/sessions/"):
            return self._send(canned("get.json"))
        return self._send('{"error":"unrouted"}', 404)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode() if n else ""
        self._record("POST", body)
        if self.path == "/v1/environment_providers/cloud/create":
            return self._send('{"environment_id":"env_MINTED","kind":"anthropic_cloud"}')
        if self.path in ("/v1/sessions", "/v1/code/sessions"):
            return self._send(canned("post.json"))
        return self._send('{"error":"unrouted"}', 404)


srv = HTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PY

  local portfile="$SRV_DIR/port"
  : >"$portfile"
  python3 "$SRV_DIR/server.py" >"$portfile" 2>"$SRV_DIR/server.err" &
  SRV_PID=$!
  # Detach from job control, or every teardown's kill prints a "Terminated: 15" line into the TAP
  # stream — noise that reads like a failure in a green run and buries a real one in a red run.
  disown "$SRV_PID" 2>/dev/null || true
  # The server binds port 0 and PRINTS the port it got, so the wait is on that line appearing —
  # never on a fixed sleep, which is a race that goes red only on a loaded box (i.e. exactly when
  # the landing gate runs it).
  local waited=0
  while [ ! -s "$portfile" ] && [ "$waited" -lt 100 ]; do
    sleep 0.05
    waited=$((waited + 1))
  done
  [ -s "$portfile" ] || { cat "$SRV_DIR/server.err" >&2; return 1; }
  local port; port="$(cat "$portfile")"
  export CC_CLOUD_API_BASE="http://127.0.0.1:$port"
}

ENV_CLOUD='{"environments":[{"environment_id":"env_EXISTING","kind":"anthropic_cloud","name":"Default"}]}'
ENV_NONE='{"environments":[]}'
ENV_BRIDGE_ONLY='{"environments":[{"environment_id":"env_BR","kind":"bridge","name":"laptop"}]}'
POST_OK='{"id":"session_NEW","title":"t"}'
GET_ACCEPTED='{"id":"session_NEW","environment_kind":"anthropic_cloud","config":{"sources":[{"type":"git_repository"}]},"status_bucket":"working"}'
GET_BRIDGE='{"id":"session_NEW","environment_kind":"bridge","config":{"sources":[{"type":"git_repository"}]}}'
GET_NOSOURCES='{"id":"session_NEW","environment_kind":"anthropic_cloud","config":{"sources":[]}}'

run_create() {
  run python3 "$SUT" --account fixture --branch claude/fire-t --repo o/r "$@"
}

# ── the two axes, pinned one at a time ───────────────────────────────────────────────────────────

@test "acceptance passes ONLY when both halves hold — and then stdout is the bare id" {
  start_srv "$ENV_CLOUD" "$POST_OK" "$GET_ACCEPTED"
  run_create
  [ "$status" -eq 0 ]
  # STDOUT IS THE ID. The caller pipes this straight into `cc-cloud declare`, and a diagnostic that
  # leaked onto stdout once already became part of a session id.
  [ "$output" = "session_NEW" ]
}

@test "half one: environment_kind=bridge is REFUSED even with sources present (exit 5)" {
  start_srv "$ENV_CLOUD" "$POST_OK" "$GET_BRIDGE"
  run_create
  [ "$status" -eq 5 ]
  [[ "$output" == *"acceptance pair FAILED"* ]] || false
  [[ "$output" == *"bridge"* ]] || false
  # The id must be NAMED — the session exists and someone has to retire it — but on stderr, which
  # `run` merges here. The stdout-only contract is proven by the accepted case above.
  [[ "$output" == *"session_NEW"* ]]
}

@test "half two: sources=0 is REFUSED even on a real VM (exit 5)" {
  start_srv "$ENV_CLOUD" "$POST_OK" "$GET_NOSOURCES"
  run_create
  [ "$status" -eq 5 ]
  [[ "$output" == *"acceptance pair FAILED"* ]] || false
  [[ "$output" == *"config.sources=0"* ]]
}

@test "the verdict is read from the GET, not from the create's own echo" {
  # The POST claims a perfect session; the control plane says bridge. §13.3 exists because those
  # diverged, so a tool that trusted the echo would pass this fixture.
  start_srv "$ENV_CLOUD" "$GET_ACCEPTED" "$GET_BRIDGE"
  run_create
  [ "$status" -eq 5 ]
}

# ── the environment axis: reuse before create ────────────────────────────────────────────────────

@test "an existing anthropic_cloud environment is REUSED, and nothing is minted" {
  start_srv "$ENV_CLOUD" "$POST_OK" "$GET_ACCEPTED"
  run_create
  [ "$status" -eq 0 ]
  run grep -c '"path": "/v1/environment_providers/cloud/create"' "$REQLOG"
  [ "$output" = "0" ]
  run grep -c 'env_EXISTING' "$REQLOG"
  [ "$output" != "0" ]
}

@test "an environment IS minted when the list holds none — and again when it holds only a bridge" {
  # Positive control for the test above: the same assertion that reads 0 there must read non-zero
  # here, or it is pinning nothing. Both no-env and wrong-kind-env reach the create.
  start_srv "$ENV_NONE" "$POST_OK" "$GET_ACCEPTED"
  run_create
  [ "$status" -eq 0 ]
  run grep -c '"path": "/v1/environment_providers/cloud/create"' "$REQLOG"
  [ "$output" = "1" ]

  start_srv "$ENV_BRIDGE_ONLY" "$POST_OK" "$GET_ACCEPTED"
  run_create
  [ "$status" -eq 0 ]
  run grep -c '"path": "/v1/environment_providers/cloud/create"' "$REQLOG"
  [ "$output" = "1" ]
}

@test "the minted environment body is the vendor's literals, not an invented one" {
  start_srv "$ENV_NONE" "$POST_OK" "$GET_ACCEPTED"
  run_create
  [ "$status" -eq 0 ]
  run grep '"path": "/v1/environment_providers/cloud/create"' "$REQLOG"
  [[ "$output" == *'anthropic_cloud'* ]] || false
  [[ "$output" == *'Default - trusted network access'* ]] || false
  [[ "$output" == *'/home/user'* ]] || false
  [[ "$output" == *'3.11'* ]] || false
  [[ "$output" == *'allow_default_hosts'* ]]
}

@test "an explicit --environment is used verbatim and skips the list entirely" {
  start_srv "$ENV_CLOUD" "$POST_OK" "$GET_ACCEPTED"
  run_create --environment env_PINNED
  [ "$status" -eq 0 ]
  run grep -c '"path": "/v1/environment_providers"' "$REQLOG"
  [ "$output" = "0" ]
  run grep '"path": "/v1/sessions"' "$REQLOG"
  [[ "$output" == *'env_PINNED'* ]]
}

# ── the endpoint/header split: cloud and bridge are different requests, not a flag ───────────────

@test "cloud creates POST /v1/sessions with environment_id, session_context and the byoc beta" {
  start_srv "$ENV_CLOUD" "$POST_OK" "$GET_ACCEPTED"
  run_create
  [ "$status" -eq 0 ]
  run grep '"path": "/v1/sessions"' "$REQLOG"
  [ -n "$output" ]
  [[ "$output" == *'"anthropic-beta": "ccr-byoc-2025-07-29"'* ]] || false
  [[ "$output" == *'"anthropic-version": "2023-06-01"'* ]] || false
  [[ "$output" == *'session_context'* ]] || false
  [[ "$output" == *'environment_id'* ]] || false
  # `bridge:{}` in a cloud body is the ENTIRE §13.3 defect — it is what makes the session execute on
  # a connected client. Its absence is the assertion, spelled as a BARE token: the escaped `\"bridge\"`
  # is what the log actually holds, so a `*'"bridge"'*` pattern could never match and the guard would
  # be green forever. Test 10 below is its positive control — the same word, on the bridge create.
  [[ "$output" != *bridge* ]]
}

@test "bridge creates still POST /v1/code/sessions with bridge:{} — the landed path is not broken" {
  start_srv "$ENV_CLOUD" "$POST_OK" "$GET_ACCEPTED"
  run_create --kind bridge
  [ "$status" -eq 0 ]
  run grep '"path": "/v1/code/sessions"' "$REQLOG"
  [ -n "$output" ]
  [[ "$output" == *'bridge'* ]] || false
  [[ "$output" != *'environment_id'* ]]
}

@test "a cloud create sends NO events — the brief is not spent before acceptance is known" {
  # The vendor ships the initial message inside the create. Doing that here would brief a session
  # before anything checked what kind of session came back, which is the one ordering §13.3 forbids.
  start_srv "$ENV_CLOUD" "$POST_OK" "$GET_BRIDGE"
  run_create
  [ "$status" -eq 5 ]
  run grep '"path": "/v1/sessions"' "$REQLOG"
  # The request body is logged as a JSON *string*, so its own quotes arrive ESCAPED. Every body
  # assertion in this file therefore matches either a bare token or the escaped spelling — the
  # unescaped `"events": []` matches nothing here, and as a NEGATIVE assertion that would have been
  # a permanently-green guard. [[guard-proxy-fails-in-both-directions]]
  [[ "$output" == *'events\": []'* ]]
}

# ── read-only verbs ──────────────────────────────────────────────────────────────────────────────

@test "--verify prints BOTH halves of the pair, not just a verdict" {
  start_srv "$ENV_CLOUD" "$POST_OK" "$GET_BRIDGE"
  run python3 "$SUT" --account fixture --verify session_X
  [ "$status" -eq 5 ]
  [[ "$output" == *'"environment_kind": "bridge"'* ]] || false
  [[ "$output" == *'"sources": 1'* ]] || false
  [[ "$output" == *'"accepted": false'* ]] || false
  # …and it creates nothing.
  run grep -c '"method": "POST"' "$REQLOG"
  [ "$output" = "0" ]
}

@test "--verify exits 0 on an accepted session — the gate can say yes" {
  start_srv "$ENV_CLOUD" "$POST_OK" "$GET_ACCEPTED"
  run python3 "$SUT" --account fixture --verify session_X
  [ "$status" -eq 0 ]
  [[ "$output" == *'"accepted": true'* ]]
}

@test "--list-environments is read-only and renders the kind of every row" {
  start_srv "$ENV_BRIDGE_ONLY" "$POST_OK" "$GET_ACCEPTED"
  run python3 "$SUT" --account fixture --list-environments
  [ "$status" -eq 0 ]
  [[ "$output" == *'env_BR'* ]] || false
  [[ "$output" == *'bridge'* ]] || false
  run grep -c '"method": "POST"' "$REQLOG"
  [ "$output" = "0" ]
}

# ── the credential seam, in both directions ──────────────────────────────────────────────────────

@test "--dry-run reads no credential and names the environment as unresolved" {
  unset CC_CLOUD_ORG_UUID CC_CLOUD_ACCESS_TOKEN
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-tool"
  export CC_ACCOUNTS_JSON="$BATS_TEST_TMPDIR/no-such.json"
  run python3 "$SUT" --account fixture --branch claude/fire-t --repo o/r --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'/v1/sessions'* ]] || false
  [[ "$output" == *'resolved at create'* ]] || false
  # A body carrying a plausible-looking env id would make the preview a different object from the
  # request — the preview must not be able to lie about what will be sent. The dry run prints real
  # (unescaped) JSON, so this pattern is the one that can actually fire.
  [[ "$output" != *'"environment_id": "env_'* ]]
}

@test "half a credential from the environment is refused, never silently mixed" {
  unset CC_CLOUD_ACCESS_TOKEN
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-tool"
  export CC_ACCOUNTS_JSON="$BATS_TEST_TMPDIR/no-such.json"
  run python3 "$SUT" --account fixture --list-environments
  [ "$status" -eq 3 ]
  [[ "$output" == *"must be set together"* ]]
}

@test "a create needs a branch — the outcome branch is what authorizes the push" {
  start_srv "$ENV_CLOUD" "$POST_OK" "$GET_ACCEPTED"
  run python3 "$SUT" --account fixture --repo o/r
  [ "$status" -eq 2 ]
  [[ "$output" == *"--branch is required"* ]]
}
