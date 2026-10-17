#!/usr/bin/env bats
# One shared ms365 server (DESIGN row X4, docs/research/load-root-cause-2026-10-17/DESIGN.md).
#
# 🚨 STAGING IS THE SAFETY PROPERTY UNDER TEST. mcp-servers.json is rendered into every live account
# config at every converge, so the DEFAULT render must stay today's stdio entry. The http form exists
# only behind ~/.claude/state/ms365-shared.active, which migrations/0066 alone writes, after the gate.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WIRE="$REPO/scripts/mcp-ssot-wire.sh"
  PROXY="$REPO/scripts/mcp-ms365-proxy.sh"
  GUARD="$REPO/hooks/ms365-shared-guard.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/state" "$HOME/.claude-secondary"
  export CC_MCP_WIRE_NO_INSTALL=1
  # No launchctl may run from a test; the renderer's restart hook goes through this seam.
  export CC_MS365_LAUNCHCTL=/usr/bin/false
  echo '{"accounts":[{"name":"next","config_dir":"~/.claude-secondary","launcher":"claude"}]}' > "$HOME/.claude/accounts.json"
  for f in "$HOME/.claude-secondary/.claude.json" "$HOME/.claude/.claude.json" "$HOME/.claude.json"; do echo '{}' > "$f"; done
  CFG="$HOME/.claude-secondary/.claude.json"
}

ms365() { python3 -c "import json,sys;print(json.dumps(json.load(open('$CFG'))['mcpServers']['ms365'],sort_keys=True))"; }
activate() { touch "$HOME/.claude/state/ms365-shared.active"; printf 'k3y\n' > "$HOME/.claude/state/ms365-proxy.key"; chmod 600 "$HOME/.claude/state/ms365-proxy.key"; }

# --- render: staged, never default ---------------------------------------------------------------

@test "no marker: ms365 renders as the stdio form, exactly as before" {
  run bash "$WIRE"; [ "$status" -eq 0 ]
  run ms365
  [[ "$output" == *'"type": "stdio"'* ]] || false
  [[ "$output" != *127.0.0.1* ]] || false
}

@test "marker + key: ms365 renders as the loopback http form carrying the key, and --check is green" {
  activate
  run bash "$WIRE"; [ "$status" -eq 0 ]
  run ms365
  [[ "$output" == *'"type": "http"'* ]] || false
  [[ "$output" == *'"url": "http://127.0.0.1:'* ]] || false
  [[ "$output" == *'"X-API-Key": "k3y"'* ]] || false
  run bash "$WIRE" --check
  [ "$status" -eq 0 ]
  # …and --check against the OTHER form is red: it agrees only with the selected one.
  rm "$HOME/.claude/state/ms365-shared.active"
  run bash "$WIRE" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *drift* ]] || false
}

@test "marker without a readable key: FAIL-OPEN to the stdio form, with a warning" {
  touch "$HOME/.claude/state/ms365-shared.active"
  run bash "$WIRE"; [ "$status" -eq 0 ]
  [[ "$output" == *"no key"* ]] || false
  run ms365
  [[ "$output" != *127.0.0.1* ]] || false
}

@test "the guard, the renderer and the SSOT name one marker path" {
  m="$(python3 -c "import json;print(json.load(open('$REPO/mcp-servers.json'))['shared']['ms365']['marker'])")"
  [ "$m" = "~/.claude/state/ms365-shared.active" ]
  grep -qF '.claude/state/ms365-shared.active' "$GUARD"
}

# --- the guard -----------------------------------------------------------------------------------

call() { printf '{"session_id":"%s","tool_name":"mcp__ms365__%s","tool_input":%s}' "$1" "$2" "$3" | bash "$GUARD"; }

@test "guard is inert without the marker: no output, exit 0, no state written" {
  run call s1 select-account '{"account":"a@x.com"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -e "$HOME/.claude/state/ms365-account/s1" ]
}

@test "select-account: per-session state file and a deny that says it was selected" {
  activate
  run call s1 select-account '{"account":"a@x.com"}'
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/state/ms365-account/s1")" = "a@x.com" ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.permissionDecision)" = deny ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.permissionDecisionReason)" = "selected a@x.com for this session" ]
}

@test "a later call with no account gets the session's account through updatedInput; other sessions do not" {
  activate
  call s1 select-account '{"account":"a@x.com"}' >/dev/null
  run call s1 list-mail-folders '{"top":5}'
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -c .hookSpecificOutput.updatedInput)" = '{"top":5,"account":"a@x.com"}' ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "none"')" = none ]
  run call s2 list-mail-folders '{"top":5}'
  [ -z "$output" ]
  # an explicit account is never overridden
  run call s1 list-mail-folders '{"account":"b@x.com"}'
  [ -z "$output" ]
}

@test "login, verify-login and logout pass through untouched, even with a session account" {
  activate
  call s1 select-account '{"account":"a@x.com"}' >/dev/null
  for t in login verify-login logout; do
    run call s1 "$t" '{}'
    [ "$status" -eq 0 ]; [ -z "$output" ]
  done
}

# --- the cutover gate ----------------------------------------------------------------------------

# Writes a tools/list result of $1 Graph tools (+ the 6 auth tools) to $2; $3=noacct drops `account`.
tools() {
  python3 - "$1" "$2" "${3:-}" <<'PY'
import json, sys
n, out, mode = int(sys.argv[1]), sys.argv[2], sys.argv[3]
props = {"top": {"type": "number"}}
if mode != "noacct": props["account"] = {"type": "string"}
g = [{"name": "download-bytes-to-file" if i == 0 else "graph-%d" % i,
      "inputSchema": {"type": "object", "properties": dict(props)}} for i in range(n)]
a = [{"name": x, "inputSchema": {"type": "object", "properties": {}}} for x in
     ("login", "logout", "verify-login", "list-accounts", "select-account", "remove-account")]
json.dump({"tools": g + a}, open(out, "w"))
PY
}
gate() { CC_MS365_GATE_DIRECT_JSON="$1" CC_MS365_GATE_PROXY_JSON="$2" bash "$PROXY" gate; }

@test "gate PASSES on identical 188-tool lists that all carry account" {
  tools 182 "$BATS_TEST_TMPDIR/d.json"; tools 182 "$BATS_TEST_TMPDIR/p.json"
  run gate "$BATS_TEST_TMPDIR/d.json" "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS 188 tools"* ]] || false
}

@test "gate FAILS on an inputSchema diff, naming the tool" {
  tools 182 "$BATS_TEST_TMPDIR/d.json"; tools 182 "$BATS_TEST_TMPDIR/p.json"
  python3 -c "
import json;p='$BATS_TEST_TMPDIR/p.json';d=json.load(open(p))
d['tools'][3]['inputSchema']['properties']['top']['type']='string';json.dump(d,open(p,'w'))"
  run gate "$BATS_TEST_TMPDIR/d.json" "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"schema differs"*graph-3* ]] || false
}

@test "gate FAILS on a single-account start (no account property), and on a wrong count" {
  tools 182 "$BATS_TEST_TMPDIR/d.json" noacct; cp "$BATS_TEST_TMPDIR/d.json" "$BATS_TEST_TMPDIR/p.json"
  run gate "$BATS_TEST_TMPDIR/d.json" "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no account property"* ]] || false
  tools 181 "$BATS_TEST_TMPDIR/d.json"; cp "$BATS_TEST_TMPDIR/d.json" "$BATS_TEST_TMPDIR/p.json"
  run gate "$BATS_TEST_TMPDIR/d.json" "$BATS_TEST_TMPDIR/p.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"187 tools, expected 188"* ]] || false
}

@test "the launchd launcher and the guard parse under /bin/bash 3.2" {
  /bin/bash -n "$PROXY"
  /bin/bash -n "$GUARD"
  run /bin/bash "$PROXY" bogus
  [ "$status" -eq 2 ]
}

@test "the label is staged, not in launchd/, and declared staged in the fleet manifest" {
  [ -f "$REPO/launchd/staged/com.claude.mcp-ms365.plist" ]
  [ ! -e "$REPO/launchd/com.claude.mcp-ms365.plist" ]
  plutil -lint "$REPO/launchd/staged/com.claude.mcp-ms365.plist"
  grep -qE '^com\.claude\.mcp-ms365 +\| staged ' "$REPO/launchd/fleet.manifest"
}
