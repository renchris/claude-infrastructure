# 05 · CC client-side MCP transports — capability matrix, config shapes, failure semantics

**Scope:** Claude Code CLIENT side only (server/daemon multiplexing = sibling agent 07).
**Subject binary:** `~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`,
**v2.1.220** (`--version`, measured), Mach-O arm64, 245 MB, Bun-compiled single file (no `cli.js`;
string evidence extracted via `strings -n 6` → `/tmp/cc220-strings.txt`, 394,254 lines).
Every claim below is labeled **[M]** measured on this box today, **[B]** binary string evidence,
**[D]** stated in official docs, **[GH]** GitHub issue.

---

## VERDICT (answer first)

**An unreachable or hung localhost HTTP MCP daemon is SAFE for a 100-session fleet at session
start — it costs ~0.2 s, not 30 s — because CC connects MCP servers non-blocking by default.
The real hazard is not startup latency; it is that a daemon which is down at session start is
never retried again after ~6 s, for the entire life of that session.** [M]

| | Measured cost at session start |
|---|---|
| baseline, zero MCP servers | **8.897 s** (this box; SessionStart hooks dominate) |
| + a **hung** localhost HTTP daemon (accepts, never replies) | **9.120 s** — **+0.22 s** |
| + a **dead** (refused) daemon *and* a hung daemon marked `alwaysLoad` | **11.621 s** — **+2.72 s** |

And three client-side costs that are **zero**, which is the case for the whole design:

- **Zero child processes.** An `http`/`sse` server is serviced by CC's in-process fetch client. No
  `node`, no `npx`, no 4-proc stdio stack — including per subagent. [M/B]
- **Zero idle sockets** — *provided the daemon answers `GET /mcp` with 405*. This is a
  server-side design lever, measured both ways below. [M]
- **Zero auth setup.** A no-auth `http://127.0.0.1:PORT/mcp` connects silently. [M]

---

## 1 · Capability matrix — transports CC 2.1.220 speaks

Transport dispatch table, verbatim from the binary [B] (`nSs`, offset 17008387):

```js
nSs = { stdio:s4r, sse:cLi, http:J5n, "streamable-http":J5n, ws:uLi, sdk:dLi, "claudeai-proxy":pLi }
```

| `type` | Status | Child proc? | Persistent socket? | OAuth | `claude mcp add -t` |
|---|---|---|---|---|---|
| `http` | **recommended** [D] | no | only if server serves `GET` SSE | yes | `http` |
| `streamable-http` | **alias → `http`**, normalized at parse [B] | no | same | yes | `streamable-http`→`http` [B] |
| `sse` | **deprecated** [D] | no | yes (SSE is the transport) | yes | `sse` |
| `ws` | supported, **no** `--transport` flag; header-auth only [D] | no | yes (bidirectional) | **no** | — |
| `stdio` | default when `type` omitted | **yes** | n/a | no | `stdio` |
| `sdk`, `sse-ide`, `ws-ide`, `claudeai-proxy` | internal/IDE | — | — | — | — |

Alias proof [B] (`J5n`, offset 11939419) — and note the transform collapses the alias:

```js
J5n = E.object({ type: E.enum(["http","streamable-http"]).transform(()=>"http"), url: E.string(), ... })
```

**[M]** `claude mcp add-json livelocal '{"type":"streamable-http","url":"http://127.0.0.1:54855/mcp"}'`
→ `Added http MCP server livelocal to user config` (alias accepted, stored as `http`), then
`claude mcp list` → `livelocal: http://127.0.0.1:54855/mcp (HTTP) - ✔ Connected` in **0.598 s**.

**[M] Wire sequence** CC issues against a live Streamable-HTTP daemon (captured by an instrumented
Python daemon, `/tmp/mcpprobe/mcpd.log`):

```
POST /mcp  initialize                 accept="application/json, text/event-stream"  authz=None
POST /mcp  notifications/initialized  mcp-session-id=<from initialize response header>  MCP-Protocol-Version: 2025-11-25
GET  /mcp  Accept: text/event-stream  Connection: keep-alive        ← the listening stream
POST /mcp  tools/list
```

Negotiated protocol version: **2025-11-25** [M]. Client UA: `claude-code/2.1.220 (sdk-cli)`,
`Accept-Encoding: identity` [M]. CC honors the `Mcp-Session-Id` response header and echoes it. [M]

---

## 2 · Config shapes — full field set, from the binary schema

The binary's zod schemas are the authoritative shape (docs enumerate a subset). [B] offsets
11938574 (`cLi`=sse), 11939419 (`J5n`=http), 11937875 (`s4r`=stdio), 11939849 (`uLi`=ws):

```js
// http / streamable-http  (J5n)
{ type: "http"|"streamable-http",   // → "http"
  url: string,
  headers?: Record<string,string>,
  headersHelper?: string,            // shell cmd emitting JSON headers; 10 s timeout [D]
  oauth?: { clientId?, callbackPort?, authServerMetadataUrl? (https only), scopes? },
  timeout?: positive int (ms),
  tools?: [{ name, permission_policy?: "always_allow"|"always_ask"|"always_deny" }],
  alwaysLoad?: boolean,
  toolPermissions?: Record<string, "allow"|"ask"|"block">,
  discoveryCache?: boolean,          // per-server opt-out of the v2.1.221 discovery cache
  role?, request_timeout_ms?         // @internal
}
// sse (cLi): identical field set, type:"sse"
// ws  (uLi): url, headers?, headersHelper?, timeout?, alwaysLoad?  — NO oauth
// stdio (s4r): type?:"stdio", command (min 1), args=[], env?, timeout?, alwaysLoad?
```

Two fields worth flagging because they are **absent from the docs page** but present in the shipped
schema: `toolPermissions` and per-server `discoveryCache`. [B]

### Scopes and their files

**[B]** `aSs = ["enterprise","local","user","project"]` — **four** scopes; the docs page enumerates
only three (`local`/`project`/`user`) [D]. `enterprise` is a managed-policy scope.

| Scope | File | Notes |
|---|---|---|
| `local` (default) | `~/.claude.json` → `projects["<cwd>"].mcpServers` | per-project, private [D] |
| `project` | `<repo>/.mcp.json` → `mcpServers` | prompts for approval **only in interactive**; `claude -p`, Agent SDK, and cloud sessions **load it without asking** [D] |
| `user` | `~/.claude.json` (top level) | all projects [D] |
| `enterprise` | managed settings | [B] |

Precedence, highest first: local → project → user → plugin → claude.ai connector. Whole entry wins;
**fields are not merged across scopes**. Scopes match by *name*; plugins/connectors match by
*endpoint*. [D]

### CLI + flags

```bash
claude mcp add --transport http  <name> <url> [--header "K: V"] [--scope user|project|local]
claude mcp add --transport sse   <name> <url>
claude mcp add-json <name> '{"type":"http","url":"http://127.0.0.1:9000/mcp"}' --scope user
claude --mcp-config <file.json|inline-json> [--mcp-config <2nd>] --strict-mcp-config
```

`--transport`/`--header` accept `-t`/`-H`. `--mcp-config` is variadic and accepts files **or** inline
JSON. `--strict-mcp-config` uses *only* `--mcp-config` servers. [D, and **[B]** arg parser `NNn`,
offset 10619951: `mcpConfig:[]`, `strictMcpConfig:!1`]

**Config-error trap [D]:** an entry with a `url` but **no `type`** is read as a *stdio* server and
skipped, with `MCP server "<name>" has a "url" but no "type"; add "type": "http" ...`. Before
v2.1.202 this surfaced as the useless `command: expected string, received undefined`. In
`--output-format stream-json`, a *skipped* entry is reported in the init event's `mcp_server_errors`
(v2.1.219+). **Always write `type` explicitly.**

### `env` expansion in `.mcp.json` [D]

`${VAR}` and `${VAR:-default}`, expanded in `command`, `args`, `env`, **`url`**, and **`headers`**.
An unset var with no default does **not** fail the load — the literal `${VAR}` is used and a
missing-variable warning appears in `claude mcp list`. For a fleet that templates a per-session port
into a URL, that failure mode is a *silent wrong URL*, not an error.

---

## 3 · Failure semantics — the decisive section (all [M])

### 3a · Session startup is NON-BLOCKING by default

**[B]** the orchestrator, `PCm` (offset ~31257000):

```js
let o = !su(process.env.MCP_CONNECTION_NONBLOCKING);          // unset ⇒ o=true ⇒ nonblocking
let s = ex(t, u=>u.alwaysLoad===!0), a = ex(t, u=>u.alwaysLoad!==!0);
Promise.all([ ...l?[ j_l(!1, ()=>W_l(s,"regular-required",n), "--mcp-config alwaysLoad servers") ]:[],
              j_l(o,  ()=>W_l(a,"regular",n,i),               "--mcp-config servers") ])
```

Note the hardcoded `!1` on the `alwaysLoad` group: **`alwaysLoad` servers are always on the blocking
path regardless of `MCP_CONNECTION_NONBLOCKING`.** Everything else is fire-and-forget.

**[M]** debug trace (`-d mcp --debug-file`), hung-daemon run:

```
05:52:13.928 [MCP] --mcp-config servers running fully async (nonblocking)
05:52:13.951 MCP server "hunglocal": Initializing HTTP transport to http://127.0.0.1:51373/mcp
05:52:13.951 HTTP transport options: {"url":...,"headers":{"User-Agent":"claude-code/2.1.220 (sdk-cli)",
             "Accept-Encoding":"identity"},"hasAuthProvider":true,"timeoutMs":60000}
05:52:13.953 Starting connection with timeout of 30000ms
05:52:13.953 Testing basic HTTP connectivity to http://127.0.0.1:51373/mcp
05:52:13.953 Using loopback address: 127.0.0.1
05:52:13.953 No token data found
```

Session result: `{"type":"result","subtype":"success","duration_ms":2158,"result":"ok"}`, wall
**9.120 s** vs **8.897 s** baseline. Init event: `mcp_servers:[{"name":"hunglocal","status":"pending"}]`.
The session ran and answered while the daemon was still hanging.

### 3b · The `alwaysLoad` blocking path is capped at 5 s and PROCEEDS (does not fail)

**[M]** the single most decision-relevant log line, from the mixed run:

```
05:53:20.824 (connect begins)
05:53:25.824 [MCP] --mcp-config alwaysLoad servers: 1/1 not ready after 5000ms — proceeding; background connection continues
```

Exactly **5000 ms**, then startup proceeds anyway. It does **not** wait for the 30 s connect timeout.
**[B]** `function rVu(){ let e=Z.MCP_CONNECT_TIMEOUT_MS; return e&&e>0?e:5000 }` — env
`MCP_CONNECT_TIMEOUT_MS` overrides, default 5000.
The message is group-shaped (`N/M not ready`), implying **one 5 s budget for the whole alwaysLoad
group**, not 5 s per server — but with N=1 I cannot fully discriminate group-wide from per-server.
*Uncertainty named.*

### 3c · Startup retry ladder — 3 retries over ~6 s, then permanent for the session

**[B]** `JlT=[500,1500,4000]` (offset 31259981) inside `G_l`, which loops the ladder, re-discards the
memoized connect result, and retries only servers whose state is transient-failed.

**[M]** observed end-to-end against a connection-refused localhost port:

```
20.847 deadlocal: HTTP Connection failed after 18ms (ConnectionRefused)
21.351 [MCP] Retry: 1 transiently-failed remote server(s) after 500ms backoff   → failed after 10ms
22.865 [MCP] Retry: 1 transiently-failed remote server(s) after 1500ms backoff  → failed after 4ms
26.871 [MCP] Retry: 1 transiently-failed remote server(s) after 4000ms backoff  → failed after 3ms
26.876 [MCP] Retry: 1 remote server(s) still failed after all retries: deadlocal
```

Total window from first attempt to give-up: **~6.05 s**. **Nothing is scheduled after that** — the
loop returns. Corroborated by [GH] anthropics/claude-code
[#31198 "MCP: Support lazy/retry connection for HTTP MCP servers"](https://github.com/anthropics/claude-code/issues/31198):
a server not available at startup leaves its tools unavailable *for the whole session*.

🚨 **Fleet consequence.** Restarting a shared localhost daemon takes >6 s of downtime → **every
session that starts during the restart window loses those tools permanently**, and the only recovery
affordance is the manual retry in the interactive `/mcp` panel [D] — which a headless `-p` fleet
session does not have. Mitigation is server-side: the daemon must be up *before* any session starts,
and restarts must be socket-preserving or fast enough to fall inside 6.05 s.

### 3d · Measured failure-mode table

Instrument: `claude mcp list` (health-checks every configured server, **no model call — free**),
scratch `CLAUDE_CONFIG_DIR=/tmp/mcpprobe/cfg`. Times are whole-CLI wall clock.

| Daemon state | Wall | Status line CC printed |
|---|---|---|
| **live** (valid MCP responses) | **0.598 s** | `✔ Connected` |
| **dead** (nothing listening → ECONNREFUSED) | **0.499 s** | `✘ Failed to connect — ConnectionRefused: Unable to connect. Is the computer able to access the url?` |
| **hung** (accepts TCP, never replies) | **30.454 s** | `✘ Failed to connect — MCP server "hunglocal" connection timed out after 30000ms` |
| **port collision** (a *non-MCP* HTTP 200 on that port) | **0.640 s** | `✘ Failed to connect — -1: Streamable HTTP error: Unexpected content type: text/html` |

The 30 s is `MCP_TIMEOUT`. **[B]** `function L2(){ let e=Z.MCP_TIMEOUT; return e&&e>0?e:30000 }` —
default 30000; this box also sets `MCP_TIMEOUT=30000` in settings `env`, so default and effective
value coincide and the measurement is valid for both.

**Port collision is the sharpest operational finding here**: a fleet that assigns daemon ports
dynamically can land a session on a port owned by an unrelated HTTP service. CC does **not** hang or
misbehave — it fails in 0.64 s with an unambiguous `Unexpected content type` error. Cheap to detect.

### 3e · Mid-session death and reconnection

**[B]** `bxr = 5` (offset 27106865); the reconnect loop lives in the client's `onclose` handler and
is gated `if (Y!=="stdio" && Y!=="sdk")` — i.e. **stdio servers are never auto-reconnected**, HTTP/SSE/WS are:

```js
_t(name, `${transport} transport closed/disconnected, attempting automatic reconnection`);
for (let se=1; se<=bxr; se++) { ... I({...L, type:"pending", reconnectAttempt:se, maxReconnectAttempts:bxr});
  ... if (se===bxr) _t(name, `Max reconnection attempts (${bxr}) reached, giving up`) }
```

Confirms [D] "up to five attempts". Also **[B]** `clearServerCache(name, config)` runs on close.
Separately, the SDK's own SSE-stream reconnection has its own defaults **[B]** (`am_`, offset 16551179):
`{initialReconnectionDelay:1000, maxReconnectionDelay:30000, reconnectionDelayGrowFactor:1.5, maxRetries:2}`
— note **1.5×, 2 retries**, not the doc page's "doubling, five attempts" (that sentence describes the
CC server-level layer above, not this one).

### 3f · How a failure is REPORTED to automation

**[M]** In `--output-format stream-json`, the mixed run's `system/init` event:

```json
"mcp_servers":[{"name":"hungalways","status":"pending"},{"name":"deadlocal","status":"failed"}]
"mcp_server_errors": null
```

**A connection failure surfaces in `mcp_servers[].status` = `"failed"`, and `mcp_server_errors`
stays `null`.** `mcp_server_errors` is for *config-shape* errors (a skipped entry) [D], not
connection errors. A fleet health-check that watches only `mcp_server_errors` is blind to every
down daemon. Watch `mcp_servers[].status ∈ {failed, pending}` instead.
Note `pending` is ambiguous: it means *still connecting* at init time, which for a hung daemon is
indistinguishable from healthy-but-slow at that instant.

Since v2.1.205 CC also tells the model which server failed, including inside `ToolSearch` results —
so the model reports the failure rather than acting as if the tools were never configured [D]. This
requires tool search (default on; disabled under a non-first-party `ANTHROPIC_BASE_URL`,
`ENABLE_TOOL_SEARCH=false`, Bedrock/Vertex/Foundry) [D].

---

## 4 · Tool listing: per-session or cached?

**On 2.1.220 (the pinned binary): every session re-connects and re-lists. There is no cross-session
tool cache.** [M — the hung/dead probes show a full `initialize`+`tools/list` on every invocation,
including on the free `claude mcp list` path.]

**The cross-session cache exists but ships in v2.1.221+, which is NOT installed here** [D]:

> a remote (HTTP or SSE) server you've used before can show a `cached` status such as
> `cached 2h ago · connects on first use · 5 tools` … To make every server connect at startup
> instead, set `MCP_DISCOVERY_CACHE=0`. The discovery cache and its `cached` status require
> Claude Code v2.1.221 or later.

Binary corroboration of the version boundary: the 220 binary registers the env names
`MCP_DISCOVERY_CACHE`, `MCP_DISCOVERY_CACHE_TTL_S`, `MCP_DISCOVERY_CACHE_MAX_STALE_S` and accepts
`discoveryCache?: boolean` in the per-server schema, but the user-facing string
`connects on first use` is **absent** (0 hits) while `discoveryCache` appears only 3× — consistent
with a partially-landed feature. **[B]** Installed tracks max out at 2.1.220 (`~/.claude-219`,
`~/.claude-220`; `~/.claude-versions` holds 2.1.113/114/183) — **no 221 on this box**. [M]

**Why this matters to the design:** on 221+, a remote daemon with a valid cache entry supplies its
tools *without connecting*, and `alwaysLoad` then no longer holds startup [D]. That converts the
6.05 s dead-daemon window from "tools lost for the session" into "tools present from cache, daemon
dialed on first tool call" — a materially better failure posture. **Upgrading to ≥2.1.221 is the
single highest-leverage client-side change for this design.** Also `list_changed` refresh failures
now keep the previously-discovered tools instead of blanking them (v2.1.214+) [D].

---

## 5 · Socket accounting for ×100 sessions (Q4)

### The measurement

**[M] Zero.** `lsof -nP -iTCP -sTCP:ESTABLISHED` across the live fleet: **15 `claude.exe` processes,
99 established sockets, 0 of them to `mcp.motion.dev`** (resolved: `104.26.6.52`, `104.26.7.52`,
`172.67.69.36`, `2606:4700:20::…`). All 99 go to Anthropic/telemetry infra
(`[2607:6bc0::10]`×64, `160.79.104.10`×17, `[2600:1901:0:9e23::]`×14). Two remote HTTP MCP servers
configured fleet-wide, **no idle socket held for either**.

### The mechanism — and the design lever

The zero is **not** because CC declines to hold a stream. CC *asks* for one:
**[M]** immediately after `notifications/initialized`, CC sends
`GET /mcp` with `Accept: text/event-stream`, `Connection: keep-alive`.

Both branches measured:

| Daemon's answer to `GET /mcp` | Result |
|---|---|
| **405** (my first probe daemon; **and the real `mcp.motion.dev`** — `curl` → `HTTP 405` in 0.187 s) | **no persistent socket.** Spec-legal; this is why the fleet reads 0. |
| **200 `text/event-stream`** (second probe daemon) | **CC opens and HOLDS it.** Daemon logged `GET-SSE OPEN`, then `GET-SSE CLOSED after 0.507s :: BrokenPipeError` — closed only when the CC process exited. |

🚨 **Design rule: a localhost MCP daemon should answer `GET /mcp` with 405** unless it genuinely
needs server→client push. Serving the stream costs **one held TCP socket + one server-side
connection/thread per session per daemon** — at 100 sessions × N daemons that is 100N idle
connections the daemon must carry, and it is entirely avoidable. Returning 405 costs nothing and CC
handles it without complaint (`✔ Connected`, 0.598 s).

### Process accounting

**[M]** `ps -eo pid,ppid` over `claude.exe`: every process has a distinct **non-claude** parent
(a shell/pane) — no `claude.exe` is a child of another. So MCP client state scales with **session
processes**, not with subagents: in-process subagents add no new OS process, and an `http` server
adds **no child process at all**, versus the 4-proc stdio stack that `09-adversarial-premise.md:33`
records each subagent spawning in an MCP-configured project. **That per-subagent multiplication is
exactly what an HTTP transport deletes on the client side.**

### Batching knobs (not yet defaulted here)

**[B]** `MCP_SERVER_CONNECTION_BATCH_SIZE` and `MCP_REMOTE_SERVER_CONNECTION_BATCH_SIZE` exist as
env-var levers over connection concurrency. I did not pin their default values (the accessor
functions resisted the minified-name walk). *Gap named* — relevant only if a config carries many
servers; at 1-3 daemons it is moot.

---

## 6 · Auth for a localhost daemon (Q5)

**No-auth localhost is accepted silently. [M]**

```
HTTP transport options: {..., "hasAuthProvider":true, "timeoutMs":60000}
MCP server "hunglocal": No token data found
MCP server "hunglocal": Using loopback address: 127.0.0.1
```

CC always attaches an OAuth provider, finds no stored token, and proceeds unauthenticated. My live
probe daemon saw `authz=None` on every request and CC reported `✔ Connected`. There is no localhost
`http://` prohibition in CC — unlike Claude Desktop, which rejects `http` URLs even on localhost
([GH] [anthropics/claude-ai-mcp#9](https://github.com/anthropics/claude-ai-mcp/issues/9)). CC also
explicitly logs `Using loopback address: 127.0.0.1`, i.e. loopback is a recognized path, not a
tolerated accident.

If a daemon *does* want auth, the options are static `headers`, `headersHelper` (a shell command run
per connect with a **10 s** timeout, from the session cwd; re-run and retried once on a 401/403 tool
call, v2.1.193+) [D], or full OAuth. One trap [D]: **if `headers.Authorization` is set and the server
rejects it, CC reports the connection failed and does *not* fall back to OAuth.**

For this design: **a bearer token in `headers` is the right shape** if the daemon needs to
distinguish callers — it is one static string, costs nothing at connect, and avoids the OAuth
callback-port machinery entirely.

---

## 7 · Adversarial pass — where docs and binary disagree, and what I nearly missed

1. **Startup retry backoff: docs are WRONG.** [D] says *"Claude Code retries the initial connection
   up to three times … starting at a one-second delay and doubling each time."* **[B/M]** the startup
   ladder is `JlT=[500,1500,4000]` and the debug log prints exactly `500ms → 1500ms → 4000ms`. Not
   1 s, not doubling. Count (3) is right; the schedule is not. Practical effect: the dead-daemon
   window is **6.05 s**, not the ~7 s the docs imply — and anyone sizing a daemon-restart budget off
   the doc sentence sizes it wrong.
2. **The docs conflate three different retry layers.** CC's *startup* ladder (3 × [500,1500,4000]),
   CC's *server-level* mid-session reconnect (`bxr=5`), and the SDK's *SSE-stream* reconnect
   (`{1000 ms, ×1.5, maxRetries:2}`) are three distinct mechanisms with three different schedules.
   The doc page presents the first two as "the same backoff". They are not.
3. **`mcp_server_errors` is the wrong field to monitor** (§3f) — I would have reported "CC surfaces
   errors to automation" from the docs alone; measuring showed `null` over a genuinely failed server.
4. **`--strict-mcp-config` does not suppress the claude.ai connector *fetch*.** [M] Both strict runs
   logged `[claudeai-mcp] Fetching from https://api.anthropic.com/v1/mcp_servers?limit=1000` →
   `Fetched 2 servers`, even though the init event listed only the `--mcp-config` server. The
   connectors are not *connected* under strict mode, but a network round-trip to Anthropic still
   happens at every session start. Not a blocker; do not budget "strict = zero MCP network work".
5. **A raw TCP pre-probe runs before the POST.** [M] `Testing basic HTTP connectivity to …` produces
   a separate connect (my hang daemon logged a 0-byte connection ahead of the 560-byte POST). On a
   *refused* port this is what fails in 18 ms. On a **blackholed** port (packets dropped rather than
   refused — a firewall, not a dead process) this probe would wait on TCP connect, and the governing
   bound becomes `MCP_TIMEOUT` (30 s) again. I did **not** measure the blackhole case — for pure
   loopback it cannot occur, so it is out of scope for this design, but it would bind if a daemon
   were ever addressed across a host boundary. *Gap named.*
6. **`alwaysLoad` is the one way to reintroduce blocking**, and it is the field a designer would
   reach for (it exempts a daemon's tools from ToolSearch deferral). It caps at 5 s and proceeds, so
   the damage is bounded — but it is **+5 s per session × 100 sessions** whenever the daemon is
   down. Combined with §4: on ≥2.1.221 a cached entry removes even that. Prefer **no `alwaysLoad`**
   until 221 is installed.
7. **Version-pin fragility.** Every failure-semantics number here is 2.1.220's. The docs page carries
   at least ten "before v2.1.NNN" behavior-change notes in the MCP section alone (162, 187, 191, 193,
   195, 202, 203, 205, 206, 211, 212, 214, 219, 221) — this surface changes almost every release.
   Re-measure after any binary bump; do not carry these constants forward on faith.

---

## 8 · Recommended client-side configuration for the candidate design

```json
{ "mcpServers": {
    "<daemon>": {
      "type": "http",
      "url": "http://127.0.0.1:<PORT>/mcp"
    } } }
```

- **Always write `type` explicitly** — omitting it makes CC read the entry as stdio and skip it (§2).
- **Do not set `alwaysLoad`** on ≤2.1.220 — it is the only path that blocks startup (5 s × 100).
- **Do not set `MCP_CONNECTION_NONBLOCKING=0`** — that converts every daemon outage into a startup stall.
- **Leave `MCP_TIMEOUT` at 30000.** It bounds the hung case; it never blocks a non-`alwaysLoad` start.
- **Serve `405` on `GET /mcp`** unless push is needed (§5) — this is the zero-idle-socket lever.
- **Daemon must be up before sessions start**; a restart longer than **6.05 s** permanently strands
  every session launched inside it (§3c).
- **Monitor** `system/init` → `mcp_servers[].status`, not `mcp_server_errors` (§3f).
- **Upgrade to ≥ 2.1.221** to get the discovery cache — it is the difference between "daemon down at
  start ⇒ tools gone for the session" and "tools from cache, connect on first use" (§4).

---

## 9 · Method, reproduction, and honesty notes

- Probe artifacts: `/tmp/mcpprobe/` — `dead.json`, `hung.json`, `mixed.json`, `hang.py`, `mcpd.py`
  (live MCP daemon), `mcpd2.py` (SSE-serving variant), `wrong.py` (non-MCP HTTP), debug logs
  `hung-debug.log`, `mixed-debug.log`, daemon logs `mcpd.log`, `mcpd2.log`.
- Scratch config dir `/tmp/mcpprobe/cfg` for all free `claude mcp list` health checks. **No real
  config, repo, or live process was modified**; all probe daemons killed at exit (`pgrep -f
  mcpprobe` → 0). `lsof`/`ps` reads were read-only.
- **Model-call budget honored: 3 haiku `-p` runs** (baseline, hung, mixed). Every other measurement —
  the four-row failure table, the wire sequence, the SSE-hold experiment, the port-collision verdict —
  used `claude mcp list`, which health-checks servers with **no model call**. That instrument is the
  reason this file has measurements rather than doc quotes.
- **Baseline caveat:** the 8.897 s floor is dominated by this box's many `SessionStart` hooks, not by
  CC. The *deltas* (+0.22 s, +2.72 s) are the transferable numbers, and the 5000 ms `alwaysLoad` cap
  is read directly off a timestamped log line rather than inferred from wall clock.
- **Single-trial timings.** Each wall-clock figure is one run; I did not repeat for variance. The
  conclusions rest on log-line constants (5000 ms, 500/1500/4000, 30000 ms) that are deterministic,
  not on the wall-clock deltas — so trial count does not threaten the verdicts.

**Sources:** [Connect Claude Code to tools via MCP](https://code.claude.com/docs/en/mcp) ·
[anthropics/claude-code#31198](https://github.com/anthropics/claude-code/issues/31198) ·
[anthropics/claude-code#8322](https://github.com/anthropics/claude-code/issues/8322) ·
[anthropics/claude-code#1611](https://github.com/anthropics/claude-code/issues/1611) ·
[anthropics/claude-ai-mcp#9](https://github.com/anthropics/claude-ai-mcp/issues/9)
