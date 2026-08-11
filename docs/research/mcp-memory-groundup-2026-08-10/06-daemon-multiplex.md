# 06 — One daemon per MCP server-type, many CC sessions: server-side semantics + supervision

Scope: daemon/server side only. Client side (does CC reconnect on 404, does it tolerate a daemon
that exits between uses) is the sibling's — dependencies named in §8.
All process/memory numbers labelled **MEASURED** were read off this Mac on 2026-08-10; everything
else is **STATED** (source/spec) and cited to file:line or URL.

---

## 1. Verdict

1. **A shared daemon is not an optimisation here, it is a precondition.** MEASURED right now: 3
   live `chrome-devtools-mcp` chains = **1,155 MB of node** + **468 MB of Chrome**, ≈1.62 GB for
   *three* sessions. Linear extrapolation to 100 sessions is 38 GB of node plus one Chrome each;
   64 GB cannot hold it. Per-session stdio for browser-class servers has no path to 150 sessions.
2. **Exactly one bridge multiplexes.** `punkpeye/mcp-proxy` (TypeScript) runs the stdio child
   **once** and fans N downstream sessions onto it — MEASURED. `supergateway` spawns a child **per
   session** (`--stateful`) or **per HTTP request** (stateless, its streamableHttp default) —
   MEASURED. `sparfenyuk/mcp-proxy` (python) also runs it once — source-verified.
   `supergateway --outputTransport sse` shares one child but **broadcasts every upstream message to
   every connected session** — a correctness break, not a memory win.
3. **The transport layer is the easy half; the server's own singleton state is the hard half.**
   `chrome-devtools-mcp` holds a process-global `#selectedPage` (`src/McpContext.ts:91`) and a
   process-global `toolMutex` (`src/index.ts:166`). Sharing one daemon therefore (a) lets session A
   change what session B's next snapshot sees, and (b) converts N independent tool calls into one
   **globally serialised queue**. Upstream ships a mitigation for (a) —
   `--experimentalPageIdRouting`, documented for exactly this case — and none for (b).
4. **Supervision: KeepAlive, not socket activation.** launchd socket activation is *viable in
   principle* but needs `launch_activate_socket(3)`, which node cannot call without a 2019-vintage
   NAN addon. Recommend an always-on `KeepAlive` agent with `ProcessType Interactive`,
   `SoftResourceLimits.NumberOfFiles ≥ 8192` (MEASURED: launchd jobs inherit **256** here), and a
   scheduled restart window — with an idle-exit variant available via a ctypes activation shim
   (§5.3) if resident memory ever justifies it.
5. **Biggest unforced win, independent of all of the above:** every live chain is
   `npm exec chrome-devtools-mcp@latest` → `chrome-devtools-mcp` → `node …/build/…`, i.e. **three
   processes where one would do**. The `npm exec` wrapper alone is MEASURED at 46 / 110 / 156 MB.
   Pinning the version and invoking the resolved binary directly removes ~1/3 of the node footprint
   with no architectural change.

---

## 2. MEASURED baseline (this Mac, 2026-08-10)

| chain | `npm exec` wrapper | `chrome-devtools-mcp` | server node | chain total |
|---|---|---|---|---|
| pid 88728 → 95531 → 95588 | 46 MB | 48 MB | 50 MB | **144 MB** |
| pid 7217 → 14014 → 14588 | 156 MB | 255 MB | 170 MB | **581 MB** |
| pid 36921 → 48346 → 49988 | 110 MB | 170 MB | 150 MB | **430 MB** |

- All three launched with `--isolated` (read from argv) → each would get its **own temp Chrome
  profile and its own browser**.
- Only one has actually launched Chrome: root pid 27180, parent 14014, **family RSS 468 MB**.
  README: *"The MCP server will start the browser automatically once the MCP client uses a tool
  that requires a running browser instance"* (`README.md:515`) — so the other two are pre-browser
  and their 144/430 MB will grow by ~470 MB each on first browser tool call.
- Spread (144 vs 581 MB) tracks lifetime + work done, not configuration.

**Implication for the design:** the memory being multiplexed away is mostly **Chrome**, not node.
One daemon ⇒ one browser. That is a ~470 MB saving *per session that would otherwise touch a page*,
against a ~40–50 MB per-session cost if a stdio shim is still needed (§8).

---

## 3. Q1 — Streamable HTTP sessioning: what isolates, what is shared

### 3.1 Two protocol eras, and the newer one deletes the problem

- **2025-03-26 … 2025-11-25** (incl. 2025-06-18): sessions exist. *"A server using the Streamable
  HTTP transport **MAY** assign a session ID at initialization time, by including it in an
  `Mcp-Session-Id` header on the HTTP response containing the `InitializeResult`."* … *"The server
  **MAY** terminate the session at any time, after which it **MUST** respond to requests containing
  that session ID with HTTP 404 Not Found."* … *"When a client receives HTTP 404 in response to a
  request containing an `Mcp-Session-Id`, it **MUST** start a new session by sending a new
  `InitializeRequest` without a session ID attached."*
  — <https://modelcontextprotocol.io/specification/2025-06-18/basic/transports> §Session Management 1,3,4.
- **2026-07-28 removes protocol-level sessions outright**: *"Revision 2026-07-28 changed the
  behavior of Streamable HTTP … **Removal of the GET stream endpoint. Removal of protocol-level
  sessions.**"* and, for a modern-only server receiving legacy traffic: *"An `Mcp-Session-Id` header
  on a request: ignore it, and do not mint or echo session IDs."*
  — <https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http>.
  Also: *"The server **MUST NOT** send independent JSON-RPC *requests* on this stream"* — sampling /
  elicitation / roots move into `InputRequiredResult` (MRTR, SEP-2322), i.e. they come back as the
  *result of the caller's own request*, which is precisely what makes them attributable to a caller.

Both eras state the enabling premise verbatim: *"the server operates as an independent process that
can handle multiple client connections."* Neither imposes any client-count ceiling.

### 3.2 What the TypeScript SDK actually isolates

`packages/server/src/server/streamableHttp.ts` (SDK HEAD `cc4b416`, 2026-07-28):

- **One `StreamableHTTPServerTransport` instance = one session.** `sessionId` is a scalar field
  (`:260`), minted once on initialize (`:809 this.sessionId = this.sessionIdGenerator?.()`), and
  every non-initialize request is checked against it: `:1018 if (sessionId !== this.sessionId)` →
  404. There is no map of sessions *inside* a transport.
- **Per-session state lives in the transport**: `_streamMapping` (`:244`), `_requestToStreamMapping`
  (`:245`), `_requestResponseMap` (`:246`), `_standaloneSseStreamId` (`:249`).
- **Stateless mode**: `sessionIdGenerator: undefined` ⇒ *"session management is disabled (stateless
  mode)"* (`:87`, `:999`).
- Therefore **the multiplexing is the host application's job, not the SDK's**: the host keeps
  `{sessionId → transport}` and routes. That is exactly what supergateway does
  (`stdioToStatefulStreamableHttp.ts:93`) and what the python SDK's
  `StreamableHTTPSessionManager` does (`_server_instances: dict[str, StreamableHTTPServerTransport]`,
  `streamable_http_manager.py:107`).
- **Concurrent initialize from 30+ clients is fine** — each POST without a session id builds its own
  transport; there is no shared mutable structure other than the router map.

### 3.3 What is *not* isolated — the part that decides this design

Everything above isolates **transport** state. It isolates **no application state**. For a shared
daemon the questions that matter are all about the server behind the bridge:

| shared-daemon hazard | evidence |
|---|---|
| global "selected page" | `chrome-devtools-mcp/src/McpContext.ts:91` `#selectedPage?: McpPage` — one field per process; `:445` setter. Session A's `navigate_page` silently redefines session B's target. |
| global tool serialisation | `src/index.ts:166 const toolMutex = new Mutex()`; `src/ToolHandler.ts:213 const guard = await this.toolMutex.acquire()`. Every tool call in the process takes one lock. |
| one browser profile | *"The user data directory is not cleared between runs … **Only one browser can use it at a time.**"* (`README.md`, §User data directory) — cookies/logins are shared by every session on the daemon. |
| upstream sees one client | *"The upstream sees `mcp-proxy` as its client, not the downstream caller — so does any telemetry keyed on it."* (`punkpeye/mcp-proxy README`, §What does not cross the proxy) |

**Upstream's own answer to the first row**: *"If your client shares a single server instance across
concurrent agents or subagents, start the server with `--experimentalPageIdRouting`. This exposes
`pageId` on page-scoped tools so each agent can route tool calls to the tab it is working with."*
(`chrome-devtools-mcp/README.md`, §Concepts → Concurrent sessions). Flag is `experimental`.

---

## 4. Q2 — Bridge comparison: one child, or one child per connection?

MEASURED with a lab in `/tmp` (fake stdio MCP server that logs its own pid on start; 3 concurrent
HTTP clients driven by curl; upstream children counted with `ps -o ppid`). Lab torn down.

| bridge | upstream children for 3 sessions | when spawned | verdict | evidence |
|---|---|---|---|---|
| **`punkpeye/mcp-proxy`** (TS, HEAD 2026-08-10) | **1** | at proxy start, *before* any client | ✅ **the one that multiplexes** | MEASURED: single child pid 82306; all 3 sessions' `tools/call` returned `server_pid=82306`. Source: `src/bin/mcp-proxy.ts:250` one `StdioClientTransport`, `:268` one `Client`, `:292 createServer` per connection wraps that **shared** client via `proxyServer({client,…})`. |
| **`sparfenyuk/mcp-proxy`** (python, HEAD 2026-05-14) | **1** (source-verified, not measured) | at startup, inside a process-lifetime `AsyncExitStack` | ✅ multiplexes | `src/mcp_proxy/mcp_server.py:178` `stdio_client(default_server_params)`, `:179` one `ClientSession`, `:180` `create_proxy_server(session)` → handed to `StreamableHTTPSessionManager(app=proxy)` (`:88`). Named servers get one child each (`:198`), mounted at `/servers/<name>/`. |
| **`supergateway --outputTransport streamableHttp --stateful`** | **3** | one per `initialize` | ❌ no memory win | MEASURED: pids 27680/27859/27906. Source: `src/gateways/stdioToStatefulStreamableHttp.ts:140` `const child = spawn(stdioCmd, {shell:true})` **inside** the `isInitializeRequest` branch of `app.post`; `:186` `child.kill()` on transport close. |
| **`supergateway … streamableHttp` (stateless, the default)** | **3 for 3 POSTs** | one per HTTP request | ❌❌ pathological | MEASURED: 3 STARTs for 3 POSTs. Source: `stdioToStatelessStreamableHttp.ts:129`, inside `app.post` (`:114`). Comment at `:115-117` says this is deliberate: *"create a new instance of transport and server for each request to ensure complete isolation. A single instance would cause request ID collisions when multiple clients connect concurrently."* For chrome-devtools-mcp that means a Chrome launch **per tool call**. |
| **`supergateway --outputTransport sse`** | **1** | at startup (`stdioToSse.ts:69`) | ❌ **correctness break** | Source `:172-188`: every line of child stdout is fanned out — `for (const [sid, session] of Object.entries(sessions)) session.transport.send(jsonMsg)`. Every session receives every other session's responses. Directly violates *"the server **MUST** send each of its JSON-RPC messages on only one of the connected streams; that is, it **MUST NOT** broadcast the same message across multiple streams"* (2025-06-18 §Multiple Connections 2). |
| **`mcp-remote`** (geelen, HEAD 2026-02-06) | n/a — **wrong direction** | per CC session | ↔ client-side shim only | `src/proxy.ts:82` `new StdioServerTransport()` + `src/lib/utils.ts:434` `StreamableHTTPClientTransport`: it is a *local stdio server* fronting a *remote HTTP* server, with OAuth. Useful only as the per-session shim of §8, ~1 node process/session. README self-labels *"working proof-of-concept … experimental"*. |
| **`chrome-devtools-mcp`'s own `src/daemon/`** | **1** | on first CLI use | ⚠️ existence proof, not usable by CC | `src/daemon/daemon.ts:130` spawns one `chrome-devtools-mcp` stdio child; `:216` `createServer(socket => …)` on a unix socket at `/tmp/chrome-devtools-mcp-<uid>.sock` (`utils.ts:getSocketPath`). But the wire protocol is **not MCP** — `{method:'invoke_tool'|'stop'|'status'}` (`daemon.ts:159-200`), one request per socket connection (`socket.end()` after each response). It serves their CLI, not MCP clients. Google building exactly this shape is the strongest third-party validation of the architecture. |

**Cross-check on the recommended path:** chrome-devtools-mcp's own README documents the bridge
recipe verbatim — `mcp-proxy --transport streamablehttp --port 8080 -- npx -y chrome-devtools-mcp@latest`,
consumed at `http://127.0.0.1:8080/mcp` with transport `HTTP` (`README.md:406`, Katalon Studio
section). Note that recipe's flag spelling is `sparfenyuk`'s; the TS `punkpeye` CLI is
`mcp-proxy --port 8080 -- <cmd>`.

**Why one upstream is *correct*, not just cheap** (2025-era): the proxy's single upstream
`Client`/`ClientSession` mints its **own** JSON-RPC ids and demultiplexes responses by id, so N
downstream sessions cannot collide. `punkpeye` documents the residue honestly rather than hiding
it — elicitation/sampling/roots are **not relayed** on a 2025-era upstream (*"carrying nothing that
says which caller it belongs to, so relaying it means guessing whose screen to put the prompt on"*),
`logging/setLevel` is answered per-connection but never forwarded, and `list_changed` is delivered
to **every** connection (§What does not cross the proxy; §`proxyServer` NOTE). None of these are in
play for chrome-devtools-mcp/browsermcp today, but they are the exact surface to re-check before
fronting a server that samples or elicits.

---

## 5. Q3 — Supervision on this Mac

### 5.1 The local pattern to follow (and where it must be broken)

Repo SSOT is `launchd/*.plist`, mirrored to `~/Library/LaunchAgents/`; a `launchd-parity-lint`
/Users/chrisren/.claude/bin/cc-bats test compares `plutil -p` output, so **edit the repo copy** (XML comments are not compared —
verified in `launchd/com.claude.dispatcher.plist` header). Every unit here follows the same shape:
`bash -c` wrapper (launchd expands neither `~` nor `$HOME` in `ProgramArguments`), PATH hardened on
line 1, `RunAtLoad false`, a long doc-comment stating *why*, an operator-loads-it C10 activation
step, and a kill-switch file.

**Three of those local conventions are wrong for this daemon and must be inverted:**

| local convention | why it exists | why it breaks an MCP daemon |
|---|---|---|
| `ProcessType Background` (dispatcher, devserver-gc, …) | batch sweeps must not disturb the user | *"Background jobs are generally processes that do work that was not directly requested by the user."* An MCP tool call **is** the user's request. Man page: *"If left unspecified, the system will apply light resource limits to the job, throttling its CPU usage and I/O bandwidth"* — so omitting it is also wrong. Use **`Interactive`** (*"run with the same resource limitations as apps, that is to say, none"*). `Adaptive` is not usable: it *"move[s] between the Background and Interactive classifications based on activity over XPC connections"* and node opens none, so it would sit Background. |
| `Nice 5/10` + `LowPriorityIO true` | same | same — drop both. Man page states ProcessType *"is preferable to using the HardResourceLimits, SoftResourceLimits and Nice keys."* |
| default fd limit | never mattered for a sweep | MEASURED: `launchctl limit maxfiles` = **256** soft (this shell has 1048576). ~100 sessions × (keep-alive socket + response stream) + upstream pipes blows past 256. Set `SoftResourceLimits { NumberOfFiles: 8192 }` — the one place the man page's preference must be overridden. |

`RunAtLoad true` **is** right here (unlike every existing unit): the daemon must be listening before
any session's first tool call.

### 5.2 Recipe — `launchd/com.claude.mcp-chrome-devtools.plist` (sketch)

```xml
<key>Label</key>            <string>com.claude.mcp-chrome-devtools</string>
<key>ProgramArguments</key>
<array>
  <string>/bin/bash</string><string>-c</string>
  <string>export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin";
     exec npx -y mcp-proxy@&lt;PINNED&gt; --host 127.0.0.1 --port 8391 --no-eventStore \
       --sessionIdleTimeout 900000 --apiKey "$(cat "$HOME/.claude/secrets/mcp-daemon.key")" \
       -- node "$HOME/.claude/vendor/chrome-devtools-mcp/build/src/index.js" \
            --experimentalPageIdRouting --isolated</string>
</array>
<key>RunAtLoad</key>        <true/>
<key>KeepAlive</key>        <dict><key>SuccessfulExit</key><false/></dict>
<key>ProcessType</key>      <string>Interactive</string>
<key>ThrottleInterval</key> <integer>10</integer>
<key>ExitTimeOut</key>      <integer>20</integer>
<key>SoftResourceLimits</key><dict><key>NumberOfFiles</key><integer>8192</integer></dict>
<key>StandardOutPath</key>  <string>/Users/chrisren/.claude/logs/mcp-chrome-devtools.out.log</string>
<key>StandardErrorPath</key><string>/Users/chrisren/.claude/logs/mcp-chrome-devtools.out.log</string>
```

Notes, each load-bearing:

- **`--host 127.0.0.1` is mandatory, not hygiene.** MEASURED in the lab: both bridges bind **all
  interfaces** by default — `lsof` reported `TCP *:9977 (LISTEN)` for `mcp-proxy` and `TCP *:9978`
  for supergateway. Spec: *"When running locally, servers **SHOULD** bind only to localhost
  (127.0.0.1) rather than all network interfaces"* (both revisions, §Security).
- **`--apiKey` is also mandatory** — see §7.3. `mcp-proxy`'s CORS default is `origin: "*"`
  (`src/startHTTPServer.ts:580`, README §CORS *"Origin: `*` (allow all origins)"*), and
  `applyCorsHeaders` **returns early when there is no `Origin` header** (`:570`), so it performs no
  DNS-rebinding rejection at all. Pair with `--corsAddAllowedHeader` for `X-API-Key` only if a
  browser client is ever needed; otherwise leave CORS at defaults and rely on the key.
- **`--no-eventStore`** kills the per-session replay buffer (default 1000 events/session,
  `--eventStoreMaxEvents`) — 100 idle sessions × 1000 buffered events is a real resident cost and
  CC does not need `Last-Event-ID` replay against a local daemon.
- **`--sessionIdleTimeout`** (default 1800000 ms) bounds the abandoned-session leak the README
  documents: *"Each session left behind holds a server instance, a transport, and an event store
  that goes on buffering notifications it can no longer deliver."* 15 min is enough here because a
  CC session that comes back just re-initialises (§6.2).
- **Pin the version, drop `npm exec`.** `npx -y mcp-proxy@latest` re-resolves on every restart and
  costs a resident wrapper process; the upstream server should be a **vendored, pinned build path**,
  not `npx -y chrome-devtools-mcp@latest` (MEASURED cost of that wrapper: 46–156 MB, ×3 chains).
- **`KeepAlive {SuccessfulExit: false}`** ⇒ crash restarts, a deliberate `exit 0` (drain/rotate)
  stays down until `launchctl kickstart`. `ThrottleInterval 10` is the default anyway
  (*"jobs will not be spawned more than once every 10 seconds"*) — leave it explicit so a
  crash-loop is visibly rate-limited rather than mysteriously slow.
- **`AbandonProcessGroup` deliberately omitted** (default false): *"When a job dies, launchd kills
  any remaining processes with the same process group ID as the job."* That is what garbage-collects
  Chrome when the daemon dies — and it is also why a daemon restart **destroys every session's
  browser state**. Name it in the restart policy; do not set it true (an orphaned 470 MB Chrome with
  no controller is worse).
- **One unit per server-type, distinct port.** Do **not** use `sparfenyuk`'s named-servers mount to
  put browsermcp and chrome-devtools behind one process: it shares a single process's fate and a
  single fd budget for two unrelated blast radii.

### 5.3 Socket activation + idle-exit — viable, but not with plain node

- launchd supports it: *"This optional key is used to specify launch on demand sockets that can be
  used to let `launchd` know when to run the job. The job must check-in to get a copy of the file
  descriptors using the `launch_activate_socket(3)` API"* (`man 5 launchd.plist`, `Sockets`). A TCP
  listener is `SockNodeName` + `SockServiceName` + `SockFamily`; launchd owns the listening socket,
  so the job may exit when idle and be restarted by the next connection.
- **Node cannot call `launch_activate_socket` natively.** The only binding is npm
  `socket-activation@3.2.0`, **last published 2019-04-28**, dependencies `nan@^2.13.2` +
  `prebuilt-bindings` (registry metadata). NAN is the pre-Node-API generation; no arm64/Node 22
  prebuilds are plausible at that vintage, so it would compile locally on every install. Taking a
  2019 NAN addon onto the critical path of every browser tool call is a worse risk than the resident
  memory it saves.
- **Escape hatch, mechanism verified, end-to-end UNTESTED**: the symbol is reachable from libSystem
  without any addon — `python3 -c "import ctypes; print(bool(getattr(ctypes.CDLL(None),
  'launch_activate_socket', None)))"` → **True** (MEASURED). A ~20-line C or ctypes shim can
  activate the socket, `dup2` the fd to 3, and `exec` node, which listens with
  `server.listen({fd: 3})`. Worth building only if §6 shows resident memory actually hurts.
- **Recommendation: skip it for v1.** The daemon's idle cost is small *until a browser is launched*
  (MEASURED: 144 MB pre-browser vs 581 MB post-browser). The lever that matters is **closing the
  browser when idle**, which is an application-level policy inside the daemon, not a launchd one —
  and it does not risk a cold-start on the interactive path.
- **Middle path with zero native code:** `RunAtLoad false` + `KeepAlive false`, started on demand by
  `launchctl kickstart -k gui/$UID/com.claude.mcp-chrome-devtools` from whatever runs first in a CC
  session. That gets on-demand start; it does **not** get on-demand start triggered by a *connection*,
  so it only works if something client-side can run the kickstart (→ sibling, §8).

---

## 6. Q4 — Multi-day growth of a shared daemon, and the policy

### 6.1 Where growth actually lives

1. **Chrome, overwhelmingly.** MEASURED 468 MB for one browser family with a handful of tabs. A
   daemon that never closes the browser accumulates tabs from 100 sessions; nothing in
   chrome-devtools-mcp reaps a tab a session abandoned. `--experimentalIncludeAllPages` makes it
   worse by widening what each session sees.
2. **Proxy-side session residue.** Bounded by `--sessionIdleTimeout` + `--no-eventStore` (§5.2).
   Without those two flags this is the leak.
3. **Node heap in the server itself.** `PageCollector` / `ServiceWorkerCollector` /
   `HeapSnapshotManager` (`src/*.ts`) accumulate per-page observers; unmeasured over days here.
4. **fd creep** — see the 256 limit, §5.1.

### 6.2 Policy

- **A scheduled restart window is legitimate *because* restart is cheap and spec-defined.**
  MEASURED: a request bearing an unknown `Mcp-Session-Id` gets **HTTP 404** from the proxy; the spec
  makes the client's response mandatory — *"When a client receives HTTP 404 … it **MUST** start a
  new session by sending a new `InitializeRequest`"*. Under 2026-07-28 there is no session to lose
  at all. So: nightly `launchctl kickstart -k`, off the hour used by the existing sweeps.
- **RSS watchdog, not a restart timer alone.** Model it on the units this repo already ships —
  `capacity-alarm.sh`, `compressor-sentinel.sh`, `devserver-census.sh` / `devserver-gc-run.sh`
  (hourly, 30-minute birth grace, observe-only by default until the operator arms `DEVGC_ACT=1`),
  `qos-census.sh`, `store-bounds-census.sh` (names only, per brief). The devserver-gc precedent is
  the right one to copy wholesale: an hourly census that *logs what it would reap*, armed by an
  explicit operator env flag, with a `touch ~/.claude/autonomy/<name>.disabled` kill switch.
- **Never reap mid-call.** The watchdog must read the daemon's own in-flight count, not RSS alone —
  killing a daemon during a 100-session-shared tool call fails 1 call and, because of the global
  mutex, delays every queued one. (Local precedent for exactly this class of error:
  `liveness-proxy-cannot-be-output-age.md` in MEMORY.md — stamp-age as liveness goes false during
  the slow runs that matter.)
- **`EnablePressuredExit` — do not set.** It opts the job into being killed under memory pressure,
  which on this box (four kernel panics from compressor-segment exhaustion, per the devserver-gc
  plist header) means the daemon dies exactly when 100 sessions are most likely to be mid-call.

---

## 7. Q5 — Concurrency reality: one node process, 100 sessions

### 7.1 The event loop is not the bottleneck; the mutex is

- For bursty, low-QPS, I/O-bound MCP traffic, one node process serving 100 sessions is unremarkable:
  each tool call is a CDP round trip, the loop is idle between them, and HTTP/SSE fan-out is cheap.
- **But `chrome-devtools-mcp` serialises every tool call process-wide** (`src/index.ts:166` +
  `src/ToolHandler.ts:213`). Today that lock is per-session because each session has its own process,
  so it costs nothing. Behind one daemon it becomes a **global queue**: a `performance_start_trace`
  or a `navigate_page` waiting on a 30 s timeout blocks *every other session's* next tool call for
  its full duration. This is the single most important number in this document and it is
  **structural, not tunable** — no flag disables the mutex.
- Rough sizing: if the mean tool call is ~1 s wall and 100 sessions each issue one call per minute,
  offered load is ~1.7 calls/s against a strictly serial server → ~100% utilisation with unbounded
  queueing. The design only works if either (a) calls are much faster than 1 s, or (b) the daemon
  count is > 1 (§7.2).

### 7.2 Mitigation: shard, don't scale up

The right unit is **a small pool of daemons, not one** — e.g. 4 chrome-devtools daemons on
8391–8394, sessions assigned round-robin (or by worktree hash). Memory becomes 4 browsers (~1.9 GB)
instead of 100 (~47 GB), and the serial queue is 4-way parallel. This also bounds blast radius
(§7.4) to 25 sessions per failure. It costs the ability to say "one canonical browser".

### 7.3 Security is materially worse in the shared shape

- MEASURED: both bridges bind `*:port`, i.e. every interface, not loopback (§5.2).
- `mcp-proxy` sets `origin: "*"` by default and does not reject on Origin mismatch — it only
  *chooses which ACAO header to emit*, and skips entirely when the header is absent
  (`startHTTPServer.ts:570,580`). Spec (both revisions): *"Servers **MUST** validate the `Origin`
  header on all incoming connections to prevent DNS rebinding attacks."*
- The asset behind that port is **a real Chrome with a persistent profile**. Per-session stdio has an
  implicit capability boundary (a child process only its parent can write to); an HTTP daemon on
  `*:8391` with permissive CORS is reachable by any local process and, for simple no-credential
  requests, by any web page the operator has open. `--apiKey` + `--host 127.0.0.1` are the minimum;
  a unix-domain socket would be strictly better if the client supported one (it does not).

### 7.4 Failure modes that get worse, not better

| | per-session stdio (today) | one shared daemon |
|---|---|---|
| server crash | 1 session loses its tools | **all N** lose them simultaneously |
| slow tool call | affects 1 session | affects **all N** (global mutex) |
| daemon restart | n/a | every session 404s and must re-initialise; `AbandonProcessGroup` default kills Chrome, so **all** browser state is lost at once |
| log attribution | 1 log per session | one log for N; upstream telemetry sees `mcp-proxy` as the only client (README) |
| a session that wedges the browser | blast radius 1 | blast radius N |

---

## 8. Dependencies handed to the client-side sibling

1. **Does CC re-initialise on HTTP 404?** MEASURED that the daemon returns 404 for an unknown
   session id, and the 2025-06-18 spec makes re-initialisation a client **MUST**. If CC does not
   implement it, every daemon restart hard-breaks every session until each is restarted — which
   would make restart-window policy (§6.2) and any idle-exit design (§5.3) unusable, and would push
   the answer to 2026-07-28-only (no sessions to lose).
2. **Does CC hold a standalone GET SSE stream (2025-era)?** If yes, a daemon exit closes N streams at
   once and the reconnect behaviour is the whole ballgame. Under 2026-07-28 the GET stream does not
   exist.
3. **Which protocol revision does CC's client negotiate?** This decides whether §3.3's cross-session
   hazards are transport-level (2025) or purely application-level (2026-07-28).
4. **Can anything client-side run `launchctl kickstart` before first use?** That is the entire
   difference between "always resident" and "resident only while used" without native code (§5.3).
5. **Config shape is available**: `claude mcp add --transport http <name> <url>` with `--header`
   (from `claude mcp add --help` on the live 2.1.220 binary), and `"type":"http"` MCP servers are
   already configured in this fleet (`~/.claude.json`, `reso-management-app/.mcp.json`,
   `reso-qa-runner/.mcp.json`). If native HTTP turns out unusable, the fallback is a per-session
   `mcp-remote` stdio shim at ~40–50 MB/session — still ~10× better than 380 MB/session, but it
   re-introduces a per-session process.

---

## 9. Adversarial pass — where a shared daemon makes things worse

Run explicitly; each item was investigated with a tool call, not assumed.

1. **The global `toolMutex` (§7.1)** — the finding that most threatens the design. Verified in
   source. Sharding (§7.2) is the only mitigation.
2. **`#selectedPage` cross-session hijack (§3.3)** — real, and upstream's own fix is an
   *experimental* flag. A v1 that shares a daemon **without** `--experimentalPageIdRouting` will
   produce silent wrong-page reads, not errors.
3. **Shared cookie jar / login state** — one profile means session A's authenticated session is
   session B's. For agents doing authenticated work this may be desirable *or* a leak; it is a
   policy decision, not a technical one, and it is invisible today because `--isolated` gives each
   session a throwaway profile.
4. **Network exposure (§7.3)** — `*:port` + `origin:"*"` measured. Per-session stdio has no port at
   all. This is a genuine regression in attack surface that the memory win must be weighed against.
5. **browsermcp is a different problem, and the daemon does not fix it.** Its server *listens* for
   the Chrome extension: `defaultWsPort: 9009` and `createWebSocketServer`/`WebSocketServer` in
   `@browsermcp/mcp@0.1.3` `dist/index.js` (tarball inspected in /tmp). Two concurrent instances
   contend for one fixed port, so it is **already** structurally single-instance — a daemon is the
   *honest* shape for it, but every session then drives the one tab the extension has connected.
   Also last published **2025-04-11** (registry) — 16 months stale, with an unpinned wrapper at
   `~/bin/browsermcp-wrapper.sh`.
6. **The axis I initially assumed irrelevant: the `npm exec` wrapper.** It turned out to be
   46–156 MB × 3 chains of pure overhead (§1.5) and is fixable *without* any daemon. A design review
   that only argues daemon-vs-stdio would have missed a third of the current footprint.
7. **The other axis I nearly missed: launchd's own defaults.** `ProcessType` unset ⇒ throttled CPU
   and I/O; `maxfiles` 256; `AbandonProcessGroup` false ⇒ restart kills Chrome. All three are silent
   and all three would have been inherited by copying an existing plist in this repo verbatim.
8. **Counter-argument to my own verdict:** if only a handful of sessions ever load a browser MCP
   server, none of this is needed — the cheap fix is *scoping the server to the sessions that need
   it* plus the `npx` removal. The daemon earns its complexity only if browser tooling is genuinely
   fleet-wide. MEASURED datapoint: 3 chains live out of ~10 concurrent claude processes, i.e. it is
   **not** currently universal.

---

## 10. Blockers / uncertainties (named, not hedged)

- **UNMEASURED**: multi-day RSS growth of a shared `mcp-proxy` + `chrome-devtools-mcp` daemon. No
  long-run data exists; the §6.2 policy is precautionary, sized from the devserver-gc precedent.
- **UNMEASURED**: `sparfenyuk/mcp-proxy`'s single-child model was read from source, not run. The TS
  `punkpeye` variant was run.
- **UNTESTED**: the ctypes/C socket-activation shim (§5.3). Only the symbol's reachability is
  measured.
- **UNTESTED**: `--experimentalPageIdRouting` under real concurrent load. It is upstream's
  documented answer, flagged experimental, and it is the load-bearing assumption of any
  shared-chrome-devtools design.
- **OUT OF SCOPE, blocking**: items 1–4 of §8. Without the client-side answers the supervision
  policy cannot be finalised — specifically, restart windows and any idle-exit variant both depend
  on CC honouring the 404 → re-initialise contract.
- **Not investigated**: whether a *unix-domain-socket* MCP transport is reachable from CC (would
  dissolve §7.3 entirely). The 2026-07-28 spec explicitly blesses stdio framing over unix sockets —
  *"Custom transports that run over a reliable bidirectional byte stream (e.g., Unix domain sockets
  or TCP) **SHOULD** reuse the stdio framing"* — so the protocol permits it; client support is the
  open question.
