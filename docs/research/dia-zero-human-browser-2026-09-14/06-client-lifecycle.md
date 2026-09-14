# 06 — Client CDP connection lifecycle: chrome-devtools-mcp 1.7.0 vs agent-browser 0.27.1

Measured 2026-09-14 from installed sources + upstream source at pinned tags. No client was run against
127.0.0.1:9222; nothing on this machine was changed.

Paths: `NM = /Users/chrisren/Library/Application Support/fnm/node-versions/v22.21.1/installation/lib/node_modules`
(i.e. `npm root -g`). Upstream reads via `gh api` at `vercel-labs/agent-browser@v0.27.1`,
`chromium/chromium@main`, `microsoft/playwright@main`.

---

## 0. The rule that makes connection count the whole problem — now a code fact, not an observation

Dia is running Chromium's **`RemoteDebuggingServerMode::kWithApprovalOnly`**. Two independently
observed facts identify that mode uniquely, and both live in `content/browser/devtools/devtools_http_handler.cc`:

| Observed on Dia | Chromium source | Line |
|---|---|---|
| HTTP `/json/*` → 404 | `if (mode_ == kWithApprovalOnly) { Send404(connection_id); return; }` — three separate handlers (`/json/version`, `/json/list`, `/json/new`) | `:588-589`, `:761-762`, `:779-780` |
| consent modal per new WS | `delegate_->AcceptDebugging(BindOnce(&HandleDebuggingApproval, …))` | `:833-846` |

The load-bearing consequences, all from source:

- **Any path starting with `/devtools/browser` is accepted, and the GUID is NOT checked.** The code
  comment is literal: *"If we require user approval, we do not require guid."*
  (`devtools_http_handler.cc:832-840`). So **bare `ws://host:port/devtools/browser` works**, and so does
  any UUID suffix, correct or stale. ⚠️ This CONTRADICTS the non-approval path at `:848`
  (`StartsWith(request.path, browser_guid_)`), which is where the UUID matters — a `WebFetch`
  summarisation of this same file told me bare paths 404, and reading the raw source refuted it. Do not
  take this from a paraphrase.
- **Every other WS path is 403, not 404**: `Send403(connection_id, "Connection rejected")` (`:844`). So
  `/devtools/page/<targetId>` is **unreachable** on Dia — per-page upstream sockets are impossible, and
  any client that wants one must use flat sessions over the browser socket.
- **The approval is never cached.** `AcceptDebugging` in Chrome's own delegate calls
  `DevToolsConnectionDialog::Show(...)` unconditionally — no "remember", no allowlist, no pref
  (`chrome/browser/devtools/chrome_devtools_manager_delegate.cc:529-549`). The interface header says the
  same: *"the AcceptDebugging() method is called for each connection"*
  (`content/public/browser/devtools_manager_delegate.h:43-45`). **N upstream connections = N modals.**
- **An `Origin` request header not in `--remote-allow-origins` is a 403** (`:819-831`). Node `ws`
  (puppeteer) and `tokio-tungstenite` (agent-browser) send none; a Node-based mux that passes client
  headers through would break itself.
- `delegate_->SetActiveWebSocketConnections(count)` (`:896-898`) is how the UI counts attachments;
  `count == 0` closes the "being debugged" infobar (`chrome_devtools_manager_delegate.cc:551-554`).

---

## 1. chrome-devtools-mcp 1.7.0 — one WS per connected browser, re-established silently per tool call

Stack: bundled **puppeteer-core** (`$NM/chrome-devtools-mcp/build/src/third_party/index.js`, 7.1 MB rollup).

| Operation | Upstream WS opened | Endpoint form required | Reconnect trigger | Idle/daemon lifetime | file:line |
|---|---|---|---|---|---|
| MCP server start | **0** — connection is lazy | — | — | process lives as long as the MCP client keeps stdin open | `bin/chrome-devtools-mcp-main.js:63-68` (no connect); `index.js:68` `getContext` only reached from the tool handler |
| **any tool call** (all ~30 tools) | **0 if `browser?.connected`, else 1** | per flag below | `!browser.connected` ⇒ full `puppeteer.connect` | — | `ToolHandler.js:145` → `index.js:81-95` → `browser.js:37-38`, `:104` |
| `--wsEndpoint ws://…` | **1, no HTTP at all** | `ws://` or `wss://` URL (coerce rejects anything else) | as above | — | `browser.js:48-52`; `third_party/index.js:67072-67079`; coerce `bin/chrome-devtools-mcp-cli-options.js:38-61` |
| `--browserUrl http://…` | **1 WS + 1 HTTP GET `/json/version`** | http(s) URL; the WS it uses is whatever `webSocketDebuggerUrl` the HTTP reply names | as above | — | `third_party/index.js:67081`, `:67132-67135` (`new URL('/json/version', browserURL)` + `globalThis.fetch`) |
| `--autoConnect --userDataDir <dir>` | **1, no HTTP** — reads `DevToolsActivePort`, builds `ws://127.0.0.1:<port><path>` itself | a user-data dir containing `DevToolsActivePort` | as above | — | `browser.js:62-81` |
| `--autoConnect` alone (no `--userDataDir`) | **1, no HTTP** — puppeteer resolves the *default* user-data dir for `--channel` (default `stable`) and reads its `DevToolsActivePort` | — | as above | — | `index.js:86-88`; `third_party/index.js:67088-67123` |
| Nth page / tab / iframe / worker | **0** | — | — | — | all attaches are `Target.attachToTarget{flatten:true}` / `Target.setAutoAttach{flatten:true}` ⇒ `sessionId` multiplexing on the one socket: `third_party/index.js:57083-57086`, `:64536-64540`, `:64738-64742` |
| MCP client closes stdin / SIGTERM/INT/HUP | **-1** — `disconnect()` for an attached browser (never `Browser.close`) | — | — | 5 s forced-exit backstop | `bin/chrome-devtools-mcp-main.js:29-61`; `browser.js:224-241` |

Mechanics that matter:

- **`connected` is purely transport state**: `get connected() { return !this.#connection._closed; }`
  (`third_party/index.js:65247`), and `_closed` flips only in `Connection.#onClose()`, driven by
  `transport.onclose` (`:56935`, `:57058-57070`). So `Target.detached`, a closed tab, a crashed
  renderer, `--isolated`, and any CDP error do **not** drop it. Only the WS closing (or an explicit
  `disconnect()`/`dispose()`) does.
- **No client-side keepalive.** `NodeWebSocketTransport.create` sets `followRedirects:true`,
  `perMessageDeflate:false`, `maxPayload:256 MB` and a `User-Agent`, and installs **no ping timer**
  (`third_party/index.js:71950-71968`). The `ws` library answers server pings automatically but sends
  none. The socket stays up only because nothing closes it.
- **Reconnect is silent-by-design, surfaced as a note.** A dropped socket on the next tool call runs a
  fresh `puppeteer.connect` (⇒ a new consent modal), builds a new `McpContext`, and sets
  `reconnected: true` (`index.js:112-115`), which becomes a one-shot line in that tool's response
  (`ToolHandler.js:156-158`). No exception is raised; the model sees a note.
- **Calls are serialised** by a single `toolMutex` (`index.js:127`, `ToolHandler.js:138`), so two
  concurrent tool calls cannot race into two `puppeteer.connect` calls.
- **No keepalive/reconnect/retry/ping flag exists in 1.7.0.** Full flag set (`grep` over
  `bin/chrome-devtools-mcp-cli-options.js`): `autoConnect browserUrl wsEndpoint wsHeaders headless
  executablePath isolated userDataDir channel logFile viewport proxyServer acceptInsecureCerts
  experimentalPageIdRouting experimentalDevtools experimentalVision memoryDebugging
  experimentalStructuredContent experimentalToonFormat experimentalDataFormat
  experimentalIncludeAllPages experimentalInteropTools experimentalScreencast experimentalFfmpegPath
  categoryExperimentalWebmcp chromeArg blockedUrlPattern allowedUrlPattern ignoreDefaultChromeArg
  categoryEmulation categoryPerformance categoryNetwork categoryExtensions
  categoryExperimentalThirdParty performanceCrux usageStatistics clearcutEndpoint
  clearcutForceFlushIntervalMs clearcutIncludePidHeader screenshotFormat screenshotQuality
  screenshotMaxWidth screenshotMaxHeight slim viaCli redactNetworkHeaders allowUnrestrictedPaths`.
  `--wsHeaders` **implies `--wsEndpoint`** (`:65`), i.e. auth headers are unavailable on the
  `--browserUrl` path.

---

## 2. agent-browser 0.27.1 — pure Rust, and its discovery costs an EXTRA throwaway connection

🚨 **The brief's premise is refuted: 0.27.1 does not use Playwright.** It is a Rust binary
(`$NM/agent-browser/bin/agent-browser-darwin-arm64`, 10 MB; `bin/agent-browser.js` is only a
platform-dispatch `spawn`) with its own CDP client over **tokio-tungstenite 0.24.0**. Crate
fingerprints from `strings`: `tokio-1.49.0, tungstenite-0.24.0, tokio-tungstenite-0.24.0, reqwest-0.12.28,
rustls-0.23.37` — no puppeteer, no playwright, no chromiumoxide. README:77 says it outright: *"No
Playwright or Node.js required for the daemon."*

| Operation | Upstream WS opened | Endpoint form required | Reconnect trigger | Idle/daemon lifetime | file:line (`cli/src/…` @ v0.27.1) |
|---|---|---|---|---|---|
| any command, daemon not yet holding a browser | triggers the connect path below | — | — | daemon starts on first command | `native/actions.rs:1240-1264` → `auto_launch` `:1516` |
| **any command, browser already held** | **0** — but sends `Browser.getVersion` with a **3 s** bound as a liveness probe on **every** command | — | probe false ⇒ `close()` + full re-connect | — | `native/actions.rs:1244-1246`; `native/browser.rs:834-847` |
| `--cdp <port>` / `connect <port>` on a **WS-only** endpoint | **2**: a probe that connects, sends `Browser.getVersion`, then **closes**, followed by the real connect | port ⇒ tries `http://h:p/json/version`, then `/json/list`, then bare `ws://h:p/devtools/browser`; **2 s** timeout each | as above | — | `native/browser.rs:1681-1712` → `native/cdp/discovery.rs:20-65`, probe at `:163-201`; real connect `native/browser.rs:457` |
| `--cdp <port>` where HTTP discovery **works** | **1** | `/json/version` (or `/json/list`) answering with a `webSocketDebuggerUrl`; host/port in that URL are rewritten to the target | as above | — | `discovery.rs:36-53`, `rewrite_ws_host` `:96-104` |
| **`--cdp ws://…` (explicit WS URL)** | **1 — the only single-connection path** | any `ws://`/`wss://` URL, passed through untouched; a query string is preserved | as above | — | `native/browser.rs:1682-1684` (`starts_with("ws://") ⇒ Ok(as-is)`) |
| `--cdp http(s)://host` with no port and empty path | **1** | scheme rewritten to ws/wss, connected directly (provider shape) | as above | — | `native/browser.rs:1687-1698` |
| `--auto-connect` | **2** (probe + real), and it **cannot see Dia at all** — see §2.1 | reads `DevToolsActivePort` from a fixed dir list, else probes ports 9222, 9229 | as above | — | `native/cdp/chrome.rs:662-684`, `resolve_cdp_from_active_port` `:690-706`, `verify_ws_endpoint` `:712-733` |
| Nth page / tab / iframe | **0** — `Target.attachToTarget{flatten:true}`, `Target.setAutoAttach{flatten:true}` | — | — | — | `native/browser.rs:531-534`, `:558-561`, `:610-620`, `:907-910`, `:1045-1048` |
| `--auto-connect` first command | also **opens a new tab** in the user's browser and `Page.bringToFront`s it | — | — | — | `native/actions.rs:1505-1514` |
| `agent-browser close` | **-1**, disconnect only — `Browser.close` is sent **only** when agent-browser launched the browser itself | — | next command re-runs the whole connect path (⇒ modals again) | — | `native/browser.rs:802-822` |
| daemon idle | **0** | — | — | **no default timeout**: `idle_timeout_ms: Option<u64>` from `AGENT_BROWSER_IDLE_TIMEOUT_MS` / `--idle-timeout`; every idle arm is gated `if idle_timeout_ms.is_some()` ⇒ unset means the daemon and its socket live until killed | `native/daemon.rs:115-127`, `:187-188`, `:222-241` |
| keepalive | — | — | — | **WS `Ping` every 30 s** + TCP `SO_KEEPALIVE` | `native/cdp/client.rs:19` (`WS_KEEPALIVE_INTERVAL_SECS = 30`), `:84`, `:176-193` |
| upstream WS closes mid-session | reader loop `break`s, clears all pending senders | — | callers get **`CDP response channel closed`** immediately (not a 30 s wait); keepalive task stops | — | `client.rs:110-128`, `:167-173`, `:239-243` |

### 2.1 `--auto-connect` structurally cannot find Dia

`get_chrome_user_data_dirs()` on macOS scans exactly
`~/Library/Application Support/{Google/Chrome, Google/Chrome Canary, Chromium, BraveSoftware/Brave-Browser}`
(`native/cdp/chrome.rs`, the macOS `cfg` block). **`Dia/User Data` is not in the list** and the string
`Dia` appears nowhere in `chrome.rs`. So `--auto-connect` skips the DevToolsActivePort branch entirely
and falls to probing ports 9222/9229 through `discover_cdp_url` — i.e. the 404/404/bare-WS-probe path,
which costs **2 modals**. The `#1218`/`#1210` "single prompt on M144+" optimisation
(`chrome.rs:684-688`: *"This order avoids triggering duplicate remote-debugging permission prompts"*)
only fires for browsers in that dir list, and even then `verify_ws_endpoint` is still a
connect-verify-close followed by a second real connect.

### 2.2 The probe's 2 s bound versus a human-answered modal

Both probes (`discovery.rs:166` and `chrome.rs:711`) wrap the connect **and** the `Browser.getVersion`
round trip in a **2 s** `tokio::time::timeout`. In approval-only mode the WS handshake is not completed
until `HandleDebuggingApproval` runs (`devtools_http_handler.cc:812-830` → `AcceptWebSocket` only on
`kAllow`), so a modal a human has not yet clicked makes the probe expire and report
`Timeout connecting to WebSocket at ws://…`. That is the most likely mechanism behind the `--cdp` hang
class of reports, and it means **the probe is not merely wasteful — on Dia it is likely to fail while
appearing to be a dead endpoint.**

---

## 3. Known issues, with status as of 2026-09-14

| # | Repo | State | Title / what it establishes |
|---|---|---|---|
| [#1094](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/1094) | cdp-mcp | **closed** 2026-03-30 (not reproduced; a user reports it live again 2026-04-28) | *"Long-running MCP sessions lose Chrome connection and trigger repeated approval prompts with `--autoConnect`"* — the exact failure mode. Maintainer (OrKoN): **"The start/restart of the MCP server is controlled by the MCP client, i.e. Codex CLI, not Chrome DevTools MCP."** Reporter saw `Starting Chrome DevTools MCP Server v0.18.1` many times in one session. |
| [#825](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/825) | cdp-mcp | **closed** 2026-03-19, still updated 2026-09-01, labels `collecting-feedback`/`feature` | *"Allow persisting remote debugging permission approval"* — the feature that would make a mux unnecessary. Not shipped; Chrome's delegate still shows the dialog unconditionally. |
| [#978](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/978) | cdp-mcp | **closed** 2026-02-23 | *"Connection drops when opening multiple browser pages — no graceful degradation."* |
| [#1272](https://github.com/vercel-labs/agent-browser/issues/1272) | agent-browser | **OPEN** (filed 2026-04-19) | *"CDP connection fails silently when external browser restarts (new webSocketDebuggerUrl)."* Note: in approval-only mode the UUID is not checked, so the *UUID* rotation is harmless — the **port** is what moves, because `chrome://inspect` remote debugging uses a dynamic port. |
| [#1193](https://github.com/vercel-labs/agent-browser/issues/1193) | agent-browser | closed 2026-04-08 (same day) | *"`--cdp` attach to existing Chrome hangs indefinitely on macOS (Chrome 139)."* |
| [#1206](https://github.com/vercel-labs/agent-browser/issues/1206) | agent-browser | closed 2026-04-15 | *"Is it normal to always have to allow **twice** when connecting to an existing Chrome instance via `--auto-connect`?"* — user-side confirmation of the probe+real double connect. Body/comments are empty; the code is the evidence. |
| [#1210](https://github.com/vercel-labs/agent-browser/issues/1210) | agent-browser | closed 2026-04-15 | *"Prefer DevToolsActivePort websocket path first in `--auto-connect` to avoid duplicate remote-debugging prompts."* Shipped as CHANGELOG `#1218`; **reorders discovery, does not remove the probe.** |
| CHANGELOG `#1133` | agent-browser | shipped | *"CDP attach hang on Chrome 144+ … Targets paused waiting for the debugger after attach are now resumed with `Runtime.runIfWaitingForDebugger`."* A mux must not swallow that. |
| CHANGELOG `#936` | agent-browser | shipped | WS Ping + TCP `SO_KEEPALIVE` "to prevent CDP connections from being silently dropped by intermediate proxies" — **a mux IS such a proxy**; it must not drop idle sockets. |
| CHANGELOG `#873`, `#861` | agent-browser | shipped | the WS fallback and the `/json/list` fallback that make the 3-method ladder. |
| CHANGELOG `#971` | agent-browser | shipped | *"Fixed auto-connect triggering when the daemon is already running, preventing duplicate connections."* |

**Claude Code and stdio MCP servers (question d).** Official docs (<https://code.claude.com/docs/en/mcp>)
state: *"Stdio servers are local processes, and Claude Code doesn't reconnect them automatically"*, and
scope automatic reconnection to remote servers — *"Claude Code reconnects a remote server that drops
mid-session and retries an HTTP or SSE server's first connection after a transient error."* `/mcp` →
**Reconnect** is the manual lever. The same page documents an idle window of *"30 minutes for stdio
servers"*. **Uncertainty, named:** I could not corroborate the 30-minute stdio idle window against the
binary — the on-disk build here is 2.1.183 and ships a 216 MB native executable
(`~/.claude-versions/2.1.183/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude`), not a
greppable `cli.js`, and the live binary is 2.1.260. So whether that window *terminates the process*
(⇒ a new WS and a new modal on the next tool call) or merely aborts a tool call is **unverified**.
What is certain: the MCP process dying for any reason — crash, client restart, `/mcp` reconnect —
produces a fresh `puppeteer.connect` and therefore a fresh modal, and #1094 is exactly that loop.

---

## 4. Verdict — the endpoint shape a mux must expose

**Serve all three of these on one fixed local port, and both clients reduce to exactly one upstream
connection for the whole session:**

1. **`GET /json/version`** returning `{"webSocketDebuggerUrl":"ws://127.0.0.1:<muxport>/devtools/browser/<anything>", …}`
   — answered by the mux from its own state, never proxied upstream (upstream 404s it).
   This single endpoint is what collapses agent-browser from 2 connections to 1: `/json/version`
   succeeding means `discover_cdp_url` returns at `discovery.rs:36-39` and the bare-WS probe never runs.
   It is also the whole of what `--browserUrl` needs (`third_party/index.js:67132-67135`).
   **Also serve `/json/version/` with a trailing slash** — Playwright builds exactly that path
   (`playwright/packages/playwright-core/src/server/chromium/chromium.ts:459-467`), so the trailing-slash
   variant costs one route and buys Playwright compatibility.
2. **`GET /json/list`** returning a `[{"type":"browser","webSocketDebuggerUrl": …}]` array — strictly a
   belt-and-braces second rung for agent-browser (`discovery.rs:131-158`); free to add.
3. **A WS listener that accepts BOTH `/devtools/browser` (bare) and `/devtools/browser/<anything>`** —
   bare because agent-browser's fallback and `read_devtools_active_port`'s default use it
   (`discovery.rs:164`, `chrome.rs:657`), suffixed because that is what `/json/version` hands back and
   what `--wsEndpoint` is documented to take. Do not require a matching UUID; upstream does not either.

**Per-client invocation once the mux exists:**

| Client | Invocation | Upstream connections |
|---|---|---|
| chrome-devtools-mcp | `--browserUrl http://127.0.0.1:<muxport>` (or `--wsEndpoint ws://127.0.0.1:<muxport>/devtools/browser`) | 0 new — the mux's single socket |
| agent-browser | `--cdp ws://127.0.0.1:<muxport>/devtools/browser` — **the explicit-WS form, which bypasses discovery entirely** (`browser.rs:1682-1684`). `--cdp <port>` also works once `/json/version` is served; **never `--auto-connect`**, which ignores the mux and re-probes 9222/9229. | 0 new |

**Non-negotiable mux properties, each forced by something measured above:**

- **Rewrite `id` on every message.** puppeteer starts at 1 (`createIncrementalIdGenerator`) and
  agent-browser starts at 1 (`client.rs:48` `AtomicU64::new(1)`). Two clients on one upstream socket
  **collide on their first command**. Precedent inside agent-browser itself: its `inspect` proxy shares
  the one socket and allocates from `static ATTACH_ID: AtomicI64 = AtomicI64::new(-1000)`
  (`native/inspect_server.rs:13-14`) precisely to avoid this — i.e. a working CDP mux over one upstream
  socket already exists in this codebase as a reference implementation
  (`inspect_server.rs:16-22`, `client.rs:116-122`).
- **Demux by `sessionId`, and broadcast browser-level events to every client.** Each client's
  `Target.attachToTarget` yields its own `sessionId`, so ownership is trackable; target/browser-domain
  events have no `sessionId` and must fan out.
- **Never send an `Origin` header upstream, and never forward a client's.** `devtools_http_handler.cc:819-831`
  403s it.
- **Never connect upstream to anything but a `/devtools/browser*` path.** Everything else is 403 in
  approval-only mode (`:844`).
- **Keep the upstream socket alive and answer pings.** puppeteer sends no pings and will notice nothing;
  agent-browser pings every 30 s and treats a failed send as death (`client.rs:176-193`).
- **Hold one upstream socket for the mux's whole life, and re-resolve the PORT on reconnect.** The port
  is dynamic under `chrome://inspect` remote debugging; read
  `~/Library/Application Support/Dia/User Data/DevToolsActivePort` yourself so clients keep a stable
  address. Every upstream reconnect costs exactly one modal — that is the irreducible floor, and the
  mux's entire value is making it one per Dia launch instead of one per client reconnect.
- **Absorb, don't propagate, a client's disconnect.** `agent-browser close`, an MCP server restart, a
  `/mcp` reconnect, and `browser.connected === false` must all be local events. Today each of them is a
  modal.
- **Budget for agent-browser's per-command 3 s `Browser.getVersion` probe** (`actions.rs:1244-1246`,
  `browser.rs:834-847`): the mux adds latency in front of it, and a probe that misses 3 s makes the
  daemon tear down and re-connect. That path is safe for the user's browser (`close()` withholds
  `Browser.close` for external connections, `browser.rs:802-812`) but on Dia it costs a modal — so the
  mux must answer `Browser.getVersion` fast, ideally from a cached `Browser.getVersion` result rather
  than a round trip.

**Alternatives considered and ruled out**

- *Point both clients at Dia directly and accept the modals.* Ruled out by arithmetic: agent-browser
  `--auto-connect` alone is 2 modals per connect and cannot even find Dia's profile (§2.1); cdp-mcp adds
  one per reconnect/restart, and #1094 shows that is unbounded in a long session.
- *Wait for upstream to persist the approval (cdp-mcp #825).* Closed 2026-03-19 without shipping; Chrome's
  delegate still calls `DevToolsConnectionDialog::Show` unconditionally today.
- *Have the mux be a dumb byte pipe.* Works for exactly one client at a time; guaranteed `id` collision
  with two (see above).
- *Serve only the WS and skip `/json/version`.* Works for cdp-mcp `--wsEndpoint` and for agent-browser
  `--cdp ws://…`, but leaves agent-browser's `--cdp <port>` form on the probe path (2 connections) and
  loses Playwright entirely. The HTTP endpoint is ~20 lines for a large reduction in footguns.
- *Use `--isolated` / a second Chrome for one of the clients.* Out of scope: the requirement is the
  warm logged-in Dia profile.

**Open uncertainties (named, not hedged)**

1. Whether Dia 1.48.0 (Chromium 149) patches `ChromeDevToolsManagerDelegate::AcceptDebugging` to cache a
   grant. Upstream Chromium does not, and Dia's binary was not inspected. If it *does* cache per session,
   agent-browser's double connect becomes cosmetic — but the mux is still required for the reconnect
   loop.
2. Whether the consent modal blocks the WS **handshake** (my reading of `AcceptWebSocket` being called
   only from `HandleDebuggingApproval`) or completes the handshake and defers traffic. This decides
   whether agent-browser's 2 s probes fail on Dia or merely waste a modal. Settleable with one
   instrumented connection, which this brief forbade.
3. Claude Code's 30-minute stdio idle window: whether it kills the server process. See §3.
