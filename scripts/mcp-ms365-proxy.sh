#!/usr/bin/env bash
# mcp-ms365-proxy.sh — ONE shared ms365 MCP server for every session (DESIGN row X4,
# docs/research/load-root-cause-2026-10-17/DESIGN.md). punkpeye `mcp-proxy` on 127.0.0.1 wraps ONE
# unchanged stdio ms-365-mcp-server: 29 stdio children (~857 MB RSS) become 1-2 processes.
#
#   run               the launchd job's body (com.claude.mcp-ms365, KeepAlive): exec mcp-proxy
#   gate              the cutover gate; exit 0 only if the proxy is indistinguishable from stdio
#   restart-if-stale  kickstart -k the job when either package version moved since `run` started
#
# WHY mcp-proxy AND NOT THE SERVER'S OWN --http: --http drops the auth tools (server.js:77) and the
# stdioOnly download-bytes-to-file (graph-tools.js:1151), which enforce-email-formatting.py and
# ms365-reply-splice.py depend on. mcp-proxy keeps ONE upstream Client for every HTTP session
# (mcp-proxy.mjs:5356-5373, 6.7.20), so the stdio server really is shared, not respawned per session.
#
# THE KEY never reaches argv: mcp-proxy reads every flag from MCP_PROXY_* too (yargs .env), so
# MCP_PROXY_API_KEY carries it, and `env -u` strips it again before the stdio child starts.
# HOST CHECK — A STATED GAP: mcp-proxy 6.7.20 has no flag for one (its transport's
# enableDnsRebindingProtection is never switched on). The defence against a DNS-rebinding page is
# the 127.0.0.1 bind plus the X-API-Key it cannot know; `gate` proves a keyless request is refused.
#
# VERSION RESTART. `run` records "ms365=<v> mcp-proxy=<v>" before it execs. Under KeepAlive a dead
# proxy restarts by itself; a version change kills nothing, so mcp-ssot-wire.sh calls
# `restart-if-stale` on every converge (the only sanctioned path that installs either package),
# which compares the record with the installed package.json files and kickstarts -k on a change.
#
# Bash 3.2-safe: launchd runs this under /bin/bash.
set -uo pipefail

_self() {
  local p="${BASH_SOURCE[0]}" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  cd "$(dirname "$p")/.." && pwd
}
REPO_ROOT="$(_self)"
SSOT="$REPO_ROOT/mcp-servers.json"
[ -f "$SSOT" ] || SSOT="$HOME/.claude/mcp-servers.json"
VERSION_FILE="$HOME/.claude/state/ms365-proxy.version"
LC="${CC_MS365_LAUNCHCTL:-launchctl}"

# Sets BIN PKG PORT KEYFILE MARKER LABEL, the server env (exported) and ARGS, from the SSOT.
load_cfg() {
  local out
  out="$(python3 - "$SSOT" <<'PY'
import json, os, shlex, sys, urllib.parse
d = json.load(open(sys.argv[1]))
s, sh = d["mcpServers"]["ms365"], d["shared"]["ms365"]
x = lambda p: os.path.expanduser(os.path.expandvars(p))
q = shlex.quote
print("BIN=" + q(x(s["command"])))
print("PKG=" + q(d.get("resolve", {}).get("ms365", {}).get("npm_package", "")))
print("PORT=" + q(str(urllib.parse.urlparse(sh["server"]["url"]).port)))
for k in ("key_file", "marker", "label"):
    print(k.upper().replace("_", "") + "=" + q(x(sh[k])))
for k, v in sorted((s.get("env") or {}).items()):
    print("export " + k + "=" + q(v))
print("ARGS=(" + " ".join(q(a) for a in s.get("args") or []) + ")")
PY
)" || { echo "mcp-ms365-proxy: cannot read the ms365 entry from $SSOT" >&2; return 1; }
  eval "$out"
  PROXY_BIN="${CC_MS365_PROXY_BIN:-$(dirname "$BIN")/mcp-proxy}"
}

# The version of the npm package that owns executable $1 (symlinks resolved, nearest package.json).
pkg_version() {
  python3 -c '
import json, os, sys
p = os.path.realpath(sys.argv[1])
while p != "/":
    p = os.path.dirname(p)
    f = os.path.join(p, "package.json")
    if os.path.isfile(f):
        print(json.load(open(f)).get("version", "?")); break
else:
    print("absent")' "$1" 2>/dev/null || echo absent
}
versions() { echo "ms365=$(pkg_version "$BIN") mcp-proxy=$(pkg_version "$PROXY_BIN")"; }

cmd_run() {
  load_cfg || exit 1
  [ -x "$PROXY_BIN" ] || { echo "mcp-ms365-proxy: no mcp-proxy at $PROXY_BIN (migrations/0067 installs it)" >&2; exit 1; }
  [ -x "$BIN" ] || { echo "mcp-ms365-proxy: no ms-365-mcp-server at $BIN" >&2; exit 1; }
  local mode; mode="$(stat -f %Lp "$KEYFILE" 2>/dev/null)"
  [ "$mode" = 600 ] || { echo "mcp-ms365-proxy: $KEYFILE must exist with mode 600 (is: ${mode:-absent})" >&2; exit 1; }
  MCP_PROXY_API_KEY="$(tr -d '\n' < "$KEYFILE")"; export MCP_PROXY_API_KEY
  mkdir -p "$(dirname "$VERSION_FILE")" && versions > "$VERSION_FILE"
  echo "mcp-ms365-proxy: $(date -u +%FT%TZ) starting $(cat "$VERSION_FILE") on 127.0.0.1:$PORT"
  exec "$PROXY_BIN" --host 127.0.0.1 --port "$PORT" --server stream \
    -- /usr/bin/env -u MCP_PROXY_API_KEY "$BIN" ${ARGS[@]+"${ARGS[@]}"}
}

cmd_restart_if_stale() {
  load_cfg || return 0
  [ -e "$MARKER" ] || return 0
  local now; now="$(versions)"
  [ "$now" = "$(cat "$VERSION_FILE" 2>/dev/null)" ] && return 0
  if "$LC" kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    echo "  ✓ ms365 shared server restarted for $now"
  else
    echo "  ⚠ ms365 shared server is on an old version and kickstart failed — launchctl kickstart -k gui/$(id -u)/$LABEL" >&2
  fi
}

cmd_gate() {
  load_cfg || exit 1
  if [ -z "${CC_MS365_GATE_PROXY_JSON:-}" ] && [ ! -x "$PROXY_BIN" ]; then
    echo "gate: FAIL — no mcp-proxy at $PROXY_BIN (set CC_MS365_PROXY_BIN)"; exit 1
  fi
  GATE_PORT="${CC_MS365_GATE_PORT:-$((PORT + 1))}" PROXY_BIN="$PROXY_BIN" BIN="$BIN" \
    EXPECT="${CC_MS365_GATE_EXPECT:-188}" python3 - ${ARGS[@]+"${ARGS[@]}"} <<'PY'
import hashlib, json, os, secrets, select, signal, subprocess, sys, time, urllib.error, urllib.request
E = os.environ
# Tools that make no Graph call and so carry no `account`: the auth tools (auth-tools.js) and the one
# local utility (parse-teams-url, graph-tools.js:95, openWorldHint false). A NEW unlisted one fails
# the gate on purpose: someone has to look at it.
AUTH = {"login", "logout", "verify-login", "list-accounts", "select-account", "remove-account", "parse-teams-url"}
INIT = {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "ms365-gate", "version": "1"}}
SERVER = [E["BIN"]] + sys.argv[1:]
DEADLINE = 90

def rpc(i, m, p=None):
    r = {"jsonrpc": "2.0", "method": m, "params": p or {}}
    if i is not None: r["id"] = i
    return r

def direct():
    p = subprocess.Popen(SERVER, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    def send(r): p.stdin.write((json.dumps(r) + "\n").encode()); p.stdin.flush()
    def recv(i):
        end = time.time() + DEADLINE
        while time.time() < end:
            if select.select([p.stdout], [], [], 1)[0]:
                line = p.stdout.readline()
                if not line: raise RuntimeError("direct server exited")
                m = json.loads(line)
                if m.get("id") == i: return m["result"]
        raise RuntimeError("direct server: no answer to id %s in %ss" % (i, DEADLINE))
    try:
        send(rpc(1, "initialize", INIT)); recv(1); send(rpc(None, "notifications/initialized"))
        tools, cur, i = [], None, 2
        while True:
            send(rpc(i, "tools/list", {"cursor": cur} if cur else {})); r = recv(i); i += 1
            tools += r["tools"]; cur = r.get("nextCursor")
            if not cur: return tools
    finally:
        p.stdin.close(); p.terminate()
        try: p.wait(10)
        except subprocess.TimeoutExpired: p.kill()

def post(url, body, key, sid=None):
    h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    if key: h["X-API-Key"] = key
    if sid: h["mcp-session-id"] = sid
    with urllib.request.urlopen(urllib.request.Request(url, json.dumps(body).encode(), h), timeout=60) as r:
        raw, sid = r.read().decode(), r.headers.get("mcp-session-id") or sid
    for line in raw.splitlines():
        if line.startswith("data:"): raw = line[5:]
    return (json.loads(raw) if raw.strip() else None), sid

def proxied():
    key, url = secrets.token_hex(16), "http://127.0.0.1:%s/mcp" % E["GATE_PORT"]
    env = dict(os.environ, MCP_PROXY_API_KEY=key)
    p = subprocess.Popen([E["PROXY_BIN"], "--host", "127.0.0.1", "--port", E["GATE_PORT"], "--server", "stream",
                          "--", "/usr/bin/env", "-u", "MCP_PROXY_API_KEY"] + SERVER, env=env,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        end = time.time() + DEADLINE
        while True:
            try: _, sid = post(url, rpc(1, "initialize", INIT), key); break
            except (urllib.error.URLError, ConnectionError):
                if time.time() > end or p.poll() is not None: raise RuntimeError("proxy never answered initialize")
                time.sleep(0.5)
        try: post(url, rpc(1, "initialize", INIT), None); keyless = "ACCEPTED"
        except urllib.error.HTTPError as e: keyless = "refused (%d)" % e.code
        post(url, rpc(None, "notifications/initialized"), key, sid)
        tools, cur, i = [], None, 2
        while True:
            r, _ = post(url, rpc(i, "tools/list", {"cursor": cur} if cur else {}), key, sid); i += 1
            tools += r["result"]["tools"]; cur = r["result"].get("nextCursor")
            if not cur: return tools, keyless
    finally:
        try: os.killpg(p.pid, signal.SIGTERM); p.wait(10)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try: os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError: pass

def load(f): return json.load(open(f))["tools"]
canon = lambda ts: json.dumps(sorted(({"name": t["name"], "inputSchema": t.get("inputSchema")} for t in ts),
                                     key=lambda t: t["name"]), sort_keys=True)
fails = []
try:
    d = load(E["CC_MS365_GATE_DIRECT_JSON"]) if E.get("CC_MS365_GATE_DIRECT_JSON") else direct()
    if E.get("CC_MS365_GATE_PROXY_JSON"): p, keyless = load(E["CC_MS365_GATE_PROXY_JSON"]), "not tested (fixture)"
    else: p, keyless = proxied()
except Exception as e:
    print("gate: FAIL — %s" % e); sys.exit(1)
if canon(d) != canon(p):
    dn, pn = {t["name"]: t for t in d}, {t["name"]: t for t in p}
    for n in sorted(set(dn) ^ set(pn)): fails.append("only %s: %s" % ("direct" if n in dn else "proxy", n))
    for n in sorted(set(dn) & set(pn)):
        if json.dumps(dn[n].get("inputSchema"), sort_keys=True) != json.dumps(pn[n].get("inputSchema"), sort_keys=True):
            fails.append("schema differs: " + n)
if len(d) != int(E["EXPECT"]): fails.append("%d tools, expected %s" % (len(d), E["EXPECT"]))
names = {t["name"] for t in d}
fails += ["missing tool: " + n for n in ("download-bytes-to-file", "verify-login") if n not in names]
noacct = sorted(t["name"] for t in d if t["name"] not in AUTH
                and "account" not in ((t.get("inputSchema") or {}).get("properties") or {}))
if noacct: fails.append("%d Graph tools have no account property (single-account start?): %s" % (len(noacct), ", ".join(noacct[:5])))
if keyless == "ACCEPTED": fails.append("the proxy answered a request with no X-API-Key")
if fails:
    for f in fails[:20]: print("gate: FAIL — " + f)
    sys.exit(1)
print("gate: PASS %d tools, direct == proxy (sha256 %s), account on all %d Graph tools, keyless request %s"
      % (len(d), hashlib.sha256(canon(d).encode()).hexdigest()[:12], len(d) - len(names & AUTH), keyless))
PY
}

case "${1:-}" in
  run) cmd_run ;;
  gate) cmd_gate ;;
  restart-if-stale) cmd_restart_if_stale ;;
  *) echo "usage: $(basename "$0") run|gate|restart-if-stale" >&2; exit 2 ;;
esac
