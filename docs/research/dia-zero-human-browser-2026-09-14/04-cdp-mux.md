# 04 — CDP multiplexer: one consent-approved upstream socket, many clients

**Verdict: BUILD. ~700-900 LOC Node/`ws`.** No maintained OSS candidate implements multi-client
session virtualization over one upstream browser connection. The two closest implementations
(`chrome-pipe-proxy`, Playwright's `cdpRelay`) are each ~400-760 LOC and each prove one half of the
design; neither is adoptable as-is. **One upstream design choice is not optional and rules the
simpler prior art out: sessions must be attached PER CLIENT, not shared.** Mechanism + citation in
§3.1.

---

## 1. Candidate table

| Name | Repo | ⭐ | Last push | Multi-client puppeteer over ONE upstream? | `/json` shim | Keepalive / reconnect | License | Ruled out because |
|---|---|---|---|---|---|---|---|---|
| **chrome-pipe-proxy** | `mimkorn/chrome-pipe-proxy` | 0 | 2026-05-04 | **Partly** — caches `targetCreated`/`attachedToTarget`, replays on each client's browser-level `setAutoAttach` | **Yes** (`/json/version`, `/json/list`; comment at `pipe-cdp-proxy.mjs:325` says explicitly "so chrome-devtools-mcp's `--browserUrl` probe succeeds") | none / spawns Chrome itself | MIT | Upstream is `--remote-debugging-pipe`, i.e. it **launches** Chrome — unusable against an already-running WS-only Dia. And it **shares** one real session per target across clients (`:229`) → breaks client #2 (§3.1) |
| **Playwright cdpRelay** | `microsoft/playwright` `packages/playwright-core/src/tools/mcp/cdpRelay.ts` (391 L) + `cdpRelayV2.ts` (121 L) + `browserModel.ts` (247 L) | 80k (repo) | live | **No** — single CDP client by construction (`/cdp/guid` endpoint, one `_cdpConnection`) | no | n/a (upstream is `chrome.debugger`) | Apache-2.0 | Single-client. **But it is the reference implementation of the interception boundary** — `cdpRelayV2.ts:99-103` intercepts browser-level `Target.setAutoAttach` and no-ops the nested one; `browserModel.ts:212` mints synthetic `pw-tab-N` sessionIds and emits `Target.attachedToTarget` |
| **chrome-mcp-proxy** | `henu-wang/chrome-mcp-proxy` | 1 | 2026-03-31 (created same minute — single commit) | **No** — `sessionOwners: sessionId → clientWs` is a **single-owner** map (`cdp-proxy.mjs:106,161-162,177`). That is *tab isolation between agents*, not two clients on one target | Yes (`:262` version, `:272` list, `:286` new) | 5 s reconnect loop; 60 s pending-request GC; **no ping** | **none** (README claims MIT; GitHub API reports `license: null` → no LICENSE file) | Never issues a per-client attach, so two puppeteer clients cannot both see a target. Also 420 LOC, 1 star, zero test files — adopting it means owning it |
| crmux | `sidorares/crmux` | 124 | 2024-06-20 | **No** — pre-flatten design (id translate only); open issue #8 "Cannot attach two devtools sessions to same page/tab" | partial | none | MIT | Predates flatten sessions (`flatten` shipped ~Chrome 74). Its whole premise is the *legacy* per-target `/devtools/page/<id>` socket, which is genuinely exclusive |
| chrome-remote-multiplex | `johnspackman/chrome-remote-multiplex` | 26 | 2017-10-18 | No | no | none | MIT | **Archived**, 9 years stale |
| devtools-proxy | `bayandin/devtools-proxy` | 67 | 2019-01-29 | No (Selenium/ChromeDriver framing) | yes | none | MIT | **Archived**, Python, 7 years stale |
| browserless | `browserless/browserless` | 13,695 | live | **No** — 1 client : 1 Chrome router. `gh` code search for `setAutoAttach` in that repo returns **zero** hits; `attachToTarget` appears only in `src/browsers/browsers.cdp.ts` | yes (`/json/{list,new,version,protocol}`) | per-session lifecycle | NOASSERTION (SSPL-ish) | Not a session mux at all — it *allocates* browsers, it does not share one. Also wrong license posture |
| chrome-remote-interface | `cyrus-and/chrome-remote-interface` | 4,553 | 2026-02-09 | No — client library. Issue #186 is a *request* for this, unimplemented | n/a | n/a | MIT | Library, not a proxy. Useful only as the upstream client if we prefer it over raw `ws` |
| @rebrowser/rebrowser-puppeteer | `rebrowser/rebrowser-puppeteer` | 40 | 2025-05-08 | No | no | no | none | Anti-detection patchset; orthogonal |
| npm registry sweep | `search?text=cdp proxy multiplex` | — | 2026-09-14 | **zero** relevant packages | — | — | — | Search space saturated: no published npm CDP multiplexer exists |

**Nothing in the maintained set does the job.** The two 2026-vintage attempts (`chrome-pipe-proxy`,
`chrome-mcp-proxy`) are single-author, ≤1 star, unlicensed-or-uncertain, ≤505 LOC — i.e. adopting
either is indistinguishable in cost from writing ours, minus the review burden of code we did not
design.

---

## 2. Protocol semantics — what the mux must honour

### 2.1 Multiple concurrent sessions on ONE target are supported by construction

The load-bearing premise, verified three independent ways:

- **Protocol contract**: `Target.detachedFromTarget` is documented *"Can be issued multiple times per
  target if multiple sessions have been attached to it."* (`browser_protocol.json`, Target domain,
  fetched from `ChromeDevTools/devtools-protocol@master`).
- **Chromium source**: `DevToolsAgentHostImpl::AttachClient()` fails **only** if that *same client*
  object is already attached (`if (SessionByClient(client)) return false;`), and
  `AttachInternal()` pushes onto a `sessions_` **vector** with
  `if (sessions_.size() == 1) NotifyAttached();` — >1 is the expected case
  (`content/browser/devtools/devtools_agent_host_impl.cc`). Each `Target.attachToTarget` under
  flatten creates a distinct `Session` object as the client
  (`content/browser/devtools/protocol/target_handler.cc:499`).
- **Maintainer statement**: OrKoN (Chrome DevTools) on `ChromeDevTools/chrome-devtools-mcp#1763`:
  *"Generally, Puppeteer and Chrome DevTools MCP supports multiple concurrent connections to the
  same browser instance."*

### 2.2 Which messages carry `sessionId`, and where the interception boundary sits

| Direction | Shape | Mux action |
|---|---|---|
| client → mux, **no** `sessionId` | root-browser-session command | **Intercept** if in the root-state set (below); else rewrite `id` and forward |
| client → mux, **with** `sessionId` | scoped to a session **that client exclusively owns** | Rewrite `id` only; forward verbatim |
| mux ← upstream, has `id` | response | Map `id` → (client, originalId); rewrite back |
| mux ← upstream, has `sessionId`, no `id` | event on a session | Route to that session's owning client (single lookup) |
| mux ← upstream, neither | root-level event (`Target.targetCreated/Destroyed/InfoChanged`, `Inspector.*`) | Fan out to every client that has discovery enabled |

**Root-session state that MUST be intercepted, never forwarded**, because the single upstream socket
has exactly one root session and these mutate it globally:

- `Target.setAutoAttach` (no `sessionId`). `setAutoAttach(autoAttach:false)` from client B would
  **detach every session client A holds**. The protocol doc adds that it *"clears all targets added
  by `autoAttachRelated`"*, and `autoAttachRelated` in turn *"cancels the effect of any previous
  `setAutoAttach`"* — two clients sharing this state cannot both be correct.
- `Target.setDiscoverTargets` (no `sessionId`) — same class; per-session state on the shared root.
- `Browser.close`, `Browser.crash`, `Browser.crashGpuProcess` — **hard-deny**. One of these burns the
  browser launch and therefore the single consent grant.
- `Target.activateTarget`, `Page.bringToFront` — deny or gate. Focus-stealing on the operator's warm
  browser. Both `chrome-mcp-proxy` (`:50`) and OrKoN independently reach this conclusion; OrKoN on
  #1763: *"this is not suitable because it would focus the targets on connection interrupting other
  tasks"*.
- `Target.createTarget` — force `background:true` (and consider `hidden:true`, which
  `browser_protocol.json` documents as *"observable via protocol, but not present in the tab UI
  strip"*) so an agent cannot yank the operator's window.

**Nested `setAutoAttach` (with `sessionId`) is forwarded verbatim** — that session belongs to exactly
one client, so its auto-attach state is private. Playwright's relay reaches the identical split:
`cdpRelayV2.ts:99-103` — `case 'Target.setAutoAttach': if (sessionId) return undefined;` (fall
through to forward) `else await this._model.enableAutoAttach()`.

### 2.3 What the two clients actually send (measured from installed sources)

**puppeteer-core 25.3.0** (`src/cdp/TargetManager.ts:145-161`), used by chrome-devtools-mcp:

```
Target.setDiscoverTargets {discover:true, filter:[{}]}
Target.setAutoAttach {waitForDebuggerOnStart:true, flatten:true, autoAttach:true,
                      filter:[{type:'page', exclude:true}, {}]}       // ← EXCLUDES pages
```
then, per attached session (`:443-450`): `Target.setAutoAttach {…, filter: discoveryFilter}` +
`Runtime.runIfWaitingForDebugger`.

**This is the detail most likely to be missed**: puppeteer auto-attaches at browser level to **tab**
targets only, then reaches the *page* through a nested `setAutoAttach` on the tab session. A mux that
only models browser→page misses the tab tier and `puppeteer.connect()` never resolves —
`#targetsIdsForInit` (`:99-106`) holds the `initializeDeferred` open until every tab target has
reported a sub-target.

**playwright-core 1.56** (`lib/server/chromium/crBrowser.js:77-87`), used by agent-browser
`connectOverCDP`:

```
Browser.getVersion
Target.setAutoAttach {autoAttach:true, waitForDebuggerOnStart:true, flatten:true}   // NO filter
```
Playwright expects **page** targets at browser level; puppeteer excludes them. The mux must satisfy
both from one cached target model — which is only possible because it synthesizes the
`attachedToTarget` stream per client rather than forwarding one.

`Target.receivedMessageFromTarget` / `Target.sendMessageToTarget` (legacy non-flatten): both clients
pass `flatten:true` unconditionally, so the legacy envelope never appears. **Do not implement it.**
Chromium itself notes the non-flat path is JSON-only and mutually exclusive with binary mode
(`target_handler.cc:567-571`). If a raw CDP script ever needs it, translate at the edge.

### 2.4 `waitForDebuggerOnStart` with N clients — safe, and this is the good news

Each `Target.attachToTarget` under flatten creates its own `Session` with its own `Throttle`
registered on the `NavigationHandle` (`target_handler.cc:393` `throttles_.insert(this)`; `:485-488`
binds a per-Session `ResumeIfThrottled`; `:559-564` clears only *that* session's throttle;
`:704-714` `Throttle::Clear()` calls `Resume()` on its own deferral). Navigation resumes only when
**every** deferring throttle releases. So client A's `Runtime.runIfWaitingForDebugger` cannot
un-pause a target before client B has installed its instrumentation. No mux-side barrier is needed.

---

## 3. Design spec

### 3.1 Session virtualization — PER-CLIENT ATTACH (decisive)

The tempting design is the `chrome-pipe-proxy` one: mux attaches once per target, caches the
`attachedToTarget` events, replays them to each joining client, and forwards per-session traffic to
the single shared real session (`pipe-cdp-proxy.mjs:155,204-213,286,310-313`; its comment at `:229`
accepts that "clients ignore events for sessionIds they don't know"). **It is broken for the second
puppeteer or Playwright client, and the failure is silent.**

`V8RuntimeAgentImpl::enable()` (v8 `src/inspector/v8-runtime-agent-impl.cc`) opens with:

```cpp
Response V8RuntimeAgentImpl::enable() {
  if (m_enabled) return Response::Success();
  ...
  m_session->reportAllContexts(this);   // ← never reached on re-enable
```

`m_enabled` lives on the `V8RuntimeAgentImpl`, i.e. **per CDP session**. On a shared session, client
B's `Runtime.enable` returns `{}` and **no `Runtime.executionContextCreated` is ever emitted**, so
puppeteer/Playwright build no `ExecutionContext` and every `page.evaluate` / selector query hangs or
throws against a browser that looks perfectly healthy. Same shape for the buffered-console replay in
the same function. A **fresh** per-client session re-reports all contexts and all buffered messages.

Therefore:

```
State the mux holds
  targets:   Map targetId → { targetInfo, tier: 'tab'|'page'|'worker'|..., suspect: bool }
  clients:   Map clientId → { ws, discover: bool, autoAttach: {on,waitForDebugger,filter},
                              sessions: Map realSessionId → { targetId, parentSessionId|null },
                              inflight: Map upstreamId → clientOriginalId }
  owner:     Map realSessionId → clientId          // the ONLY routing table needed
  upstreamId: monotonic counter, global
```

**Session ids are NOT rewritten.** Every real `attachToTarget` returns a globally unique sessionId
owned by exactly one client, so `owner.get(sessionId)` is a complete routing function. This is a
genuine simplification over the brief's assumption — rewriting buys nothing and costs a
bidirectional map plus a class of aliasing bugs. (Playwright's relay *does* mint synthetic ids, but
only because its upstream — `chrome.debugger` — hands it tab ids, not sessionIds.)

**Client `Target.setAutoAttach` (browser-level) handler:**
1. Record `{on, waitForDebuggerOnStart, filter}` on the client. Reply `{}` immediately.
2. For every known target matching the client's filter **and** the mux's own admission filter
   (§3.4), issue a real `Target.attachToTarget {targetId, flatten:true}` upstream.
3. On each real `attachedToTarget`, record `owner[sessionId]=clientId` and **forward the event
   verbatim** to that client. `waitingForDebugger` passes through unchanged.
4. `setAutoAttach(autoAttach:false)` ⇒ detach **only that client's** sessions; never forward.

**Client disconnect:** `Target.detachFromTarget` for every sessionId that client owns, then drop its
rows. This is the cleanest property of per-client attach — a crashed client cannot leave the browser
instrumented, and cannot take another client's sessions down with it.

**New target appears** (`Target.targetCreated` upstream): fan the event out to discovery-enabled
clients; for each client with `autoAttach.on` and a matching filter, issue its own attach.

**`Target.targetDestroyed` / `targetCrashed`**: fan out; the upstream also sends
`detachedFromTarget` per session, which routes by owner and clears the row.

**Nested sessions** (workers, OOPIFs) arrive as `attachedToTarget` **with** an outer `sessionId`
belonging to a client's session. Record `owner[child]=sameClient` and forward. Playwright's relay
tracks exactly this with a per-tab `childSessions: Set` (`browserModel.ts:56-57,115-122`).

**Request-id rewriting is mandatory.** Puppeteer's `Connection` keeps one flat `CallbackRegistry`
keyed on small monotonic integers and, on a response whose `id` it does not hold, *iterates every
session looking for the callback* (`src/cdp/Connection.ts:59,120,#callbacks`, `onMessage` fallback
loop). Two clients both starting at `id:1` would cross-deliver. Rewrite to a global counter; map
back on the response.

### 3.2 HTTP discovery shim

Authoritative shapes from `content/browser/devtools/devtools_http_handler.cc` (fetched at
`chromium/src@main`):

- **`/json/version`** (`:619-632`): `Protocol-Version`, `WebKit-Version`, `Browser`, `User-Agent`,
  `V8-Version`, `webSocketDebuggerUrl` = `ws://<Host header><browser_guid>`. **Echo the client's own
  `Host` header** so `--browserUrl=http://127.0.0.1:<muxport>` yields a mux-pointing WS URL, and fill
  the version fields from a cached upstream `Browser.getVersion`.
- **`/json/list`** (`:644-657`) — per-target descriptor from `SerializeDescriptor` (`:1033-1061`):
  `id`, `parentId` (omitted when empty), `type`, `title` (HTML-escaped), `description`, `url`,
  `faviconUrl` (only if valid), `webSocketDebuggerUrl` = `ws://<host>/devtools/page/<id>`,
  `devtoolsFrontendUrl`. Build from the mux's cached `Target.getTargets`. Supports a `?for_tab`
  query that switches the tier.
- **`/json/new`** (`:659-690`) — **`PUT` only**; Chromium returns `405` for any other verb with the
  message *"Using unsafe HTTP verb %s to invoke /json/new."* URL is the first query component,
  URL-unescaped. Implement as `Target.createTarget` with `background:true`, then reply with the same
  descriptor shape.
- **`/json/activate`**, **`/json/close`** (`:694+`) — `/json/<cmd>/<targetId>`. `activate` should be
  denied or no-op'd (focus). `close` → `Target.closeTarget`.
- **`/json/protocol`** — serve the bundled `browser_protocol.json`; cheap, and some tooling probes it.

Also serve `ws://<mux>/devtools/page/<targetId>` as a **synthetic per-target endpoint**: accept the
socket, immediately `attachToTarget` on behalf of that client, and relay with `sessionId` stripped in
both directions. This is what makes a raw CDP script or a `chrome://inspect`-style frontend work
without knowing the mux exists. ~40 LOC, high leverage.

### 3.3 Keepalive and reconnect

**Corrected premise: Chromium's DevTools HTTP/WS server has no idle timeout.** `grep -niE
"timeout|idle|keepalive|ping|TimeDelta"` over the full 1,063-line `devtools_http_handler.cc` returns
**zero** hits. So the 2026-06 drops were not an idle reaper, and a ping is not their cure (§4, A1).

What a ping *does* buy: dead-peer detection. **Chromium's WS server answers ping frames with pong** —
`net/server/web_socket.cc:146-149`: `if (result == WebSocketParseResult::FRAME_PING) { Send(*message,
WebSocketFrameHeader::kOpCodePong, …); }`, with the opcodes handled in
`net/server/web_socket_encoder.cc:148-152,364-367`. So use **`ws` protocol-level `ping()` every
20 s, declare dead after 2 missed pongs** — it costs no CDP round-trip, cannot be queued behind a
hung renderer, and needs no `Browser.getVersion`. A `Browser.getVersion` heartbeat is strictly worse:
it is a CDP command on the root session that can be starved by the very fan-out it is meant to
monitor.

**Match puppeteer's socket options exactly** (`src/node/NodeWebSocketTransport.ts:21-25`):
`perMessageDeflate: false`, `maxPayload: 256 * 1024 * 1024`. A smaller `maxPayload` on either the
mux's server or its client silently kills the socket on a large `Page.captureScreenshot` or
`Network.getResponseBody` — `ws` defaults to 100 MiB, which is under Chromium's practical ceiling.

**Reconnect:** on upstream close, re-read `DevToolsActivePort` (first line = port, second =
`/devtools/browser/<uuid>`), then `GET /json/version` on the discovered port to obtain the current
`webSocketDebuggerUrl` — the browser guid rotates per launch, so a cached URL is stale after a
browser restart. **Reconnect pops a fresh consent dialog**, so it must be rate-limited and *loud*
(this is precisely `chrome-devtools-mcp#1094`: *"Reconnect churn causes repeated Chrome approval
prompts"*). Do not auto-retry in a tight loop the way `chrome-mcp-proxy` does at 5 s.

**Client-facing behaviour on upstream loss** is a policy decision the mux must make, not dodge:
close every client socket with `1011`, so each client's own reconnect logic re-drives discovery
against a rebuilt target model. Holding client sockets open across an upstream reconnect would leave
them holding sessionIds that no longer exist.

**Backpressure:** per-client outbound queue with a high-water mark (say 64 MiB / 5,000 messages);
on breach, close that client with `1013` rather than letting `ws` buffer unbounded and OOM the mux.
The upstream socket must never be paused — pausing it head-of-line-blocks every other client.

### 3.4 Admission filter — the highest-value feature, and it is not multiplexing

`chrome-devtools-mcp#1763` diagnoses the real failure mode on a busy browser, and it is not socket
count. On **discarded** tabs (Arc/Dia-style memory reclaim) the renderer is gone;
`NetworkHandler::Enable()` returns `Response::FallThrough()`, the command queues for a renderer-side
agent, `RenderFrameDevToolsAgentHost::EnsureAgent()` fails for want of a live `frame_host_`, and the
command **hangs indefinitely**. `Target.getTargetInfo` exposes no lifecycle state, so there is no
CDP-visible way to tell a discarded tab from a live one before sending a command. Reporter's
measurement: 27 page targets, `Network.enable` with a 3 s bound — **18 OK, 9 hung**. Puppeteer
attaches to *everything* during `connect()`, so one discarded tab stalls the whole connect past the
180 s `protocolTimeout` (`src/cdp/Connection.ts:62`). OrKoN notes a Chromium fix landed
(`chromium-review …/7557410`) and that Arc-family browsers are unsupported — Dia is in that family.

The mux is the only place this can be fixed for a warm browser: probe each target once with a
short-bounded `Network.enable`/`Runtime.evaluate` on a mux-owned throwaway session, mark the
non-responders `suspect`, and **omit them from `/json/list` and from every client's synthesized
`attachedToTarget` stream** until they respond. Puppeteer's own `targetFilter` (used by
chrome-devtools-mcp `build/src/browser.js:19,41`) runs in `#onAttachedToTarget` — *after* the attach
— so it cannot prevent the hang. Filtering at the mux is strictly stronger.

### 3.5 Sizing

Grounded against three real implementations: `chrome-pipe-proxy` 505 L (shared-session, spawns
Chrome, `/json` shim); Playwright relay 391 + 121 + 247 = 759 L (single client, full synthetic target
model); `chrome-mcp-proxy` 420 L (id remap + owner routing + `/json`, no autoAttach virtualization).

| Component | LOC |
|---|---|
| `ws` server + HTTP server + upstream client bootstrap + `DevToolsActivePort` read | 90 |
| id rewrite + inflight registry | 60 |
| root-command interception table (autoAttach, discoverTargets, getTargets, attach/detach, create/close/activate, `Browser.*` denies) | 150 |
| per-client attach orchestration + target model + tab/page tier handling | 140 |
| event routing by owner + child-session tracking + fan-out | 90 |
| client-disconnect teardown | 50 |
| `/json/*` shim incl. PUT semantics + synthetic `/devtools/page/<id>` socket | 110 |
| ping keepalive, reconnect, client eviction, backpressure | 80 |
| admission filter (§3.4) | 70 |
| status endpoint + structured log | 60 |
| **core total** | **~800** |
| tests (protocol-level fixtures, two-client `Runtime.enable` regression, id-collision, discarded-target) | +250 |

One file is defensible at that size; three (`upstream.mjs`, `mux.mjs`, `httpShim.mjs`) is better.
Dependencies: `ws` only.

### 3.6 Riskiest edge cases, in descending order

1. **`Runtime.enable` on a shared session** — §3.1. Mitigated *only* by per-client attach. If anyone
   later "simplifies" the mux to share sessions, this is the regression, and it presents as a hang,
   not an error. Pin it with a two-client test that asserts client B receives
   `Runtime.executionContextCreated`.
2. **Renderer-global state that per-session attach does NOT isolate.** `Emulation.setDeviceMetrics
   Override`, `Emulation.setUserAgentOverride`, `Network.emulateNetworkConditions`,
   `Page.setBypassCSP` reach a single shared widget/renderer. Two clients emulating different
   viewports on one target **will** fight, and the mux cannot fix it. **Name it as a constraint, not
   a bug:** partition by target (one client per tab) or accept last-write-wins.
3. **`Fetch.enable` from two clients on one target.** Both receive `Fetch.requestPaused`; both try to
   continue; the second `Fetch.continueRequest` fails on a consumed `interceptionId`, and the request
   may hang until timeout. Recommend the mux **deny a second `Fetch.enable`** on a target that
   already has one, with an explicit error, rather than allowing a nondeterministic stall.
4. **Puppeteer's tab-tier expectation** (§2.3). Getting the browser-level filter wrong makes
   `puppeteer.connect()` hang forever rather than fail — `#initializeDeferred` never resolves.
5. **Consent on reconnect.** Every upstream reconnect costs an operator dialog. The mux must treat
   "upstream socket alive" as its single most precious resource; log every reconnect with a cause.
6. **`Target.getTargets` result must be synthesized, not passed through**, once the admission filter
   is live — otherwise a client sees a target in `getTargets` that it was never auto-attached to, and
   puppeteer's target bookkeeping diverges from the mux's.
7. **Event volume.** N clients × M targets ⇒ N× the upstream event traffic on one socket.
   `chrome-devtools-mcp#978` (closed not-reproducible, but the analysis stands) names exactly this.
   The admission filter is the mitigation; a per-client target allowlist is the escape valve.

---

## 4. Adversarial pass

**A1 — "keepalive fixes the drops" was the brief's hypothesis and the evidence refutes it.**
No idle timeout exists in Chromium's devtools server (zero timeout hits in 1,063 lines of
`devtools_http_handler.cc`). The measured cause on busy browsers is **discarded targets hanging
`Network.enable` indefinitely** (#1763, with a 27-target 18/9 split and the Chromium call path named
down to `EnsureAgent()`). Shipping a ping and calling the problem solved would have left the real
fault in place. The ping is still correct — for dead-peer detection — but §3.4 is the fix.

**A2 — is the mux needed at all?** Three alternatives, each ruled out on a fact:
- *Persist the consent grant.* `chrome-devtools-mcp#825` asked for exactly this and was closed
  **`not_planned`** on 2026-03-19. Not available.
- *`--remote-debugging-pipe`.* Sidesteps consent entirely (it is why `chrome-pipe-proxy` exists —
  `pipe-cdp-proxy.mjs:7` cites "bypassing the macOS NSApplication-activation"). But it requires
  **launching** the browser, and the requirement here is a **warm, already-running, logged-in** Dia
  on a fixed WS-only port. Unavailable for this use case; worth keeping for any
  clean-profile/dedicated-browser tier.
- *Run exactly one client, ever.* Viable and cheapest — but the stated requirement is
  chrome-devtools-mcp **and** agent-browser **and** raw scripts concurrently, and
  chrome-devtools-mcp reconnects on `browser.connected === false` (`build/src/browser.js:37,208,229`),
  each reconnect costing a dialog. A mux converts N×reconnects into 1 upstream socket, which is the
  whole value.

**A3 — the axis I initially assumed irrelevant: request-id rewriting might be unnecessary if each
client got its own root session.** It cannot. One WebSocket = one root browser session in Chromium,
and the root session is where `id` lives. Confirmed by reading `Connection.onMessage` — puppeteer's
id space is per-*connection*, starting at 1, with a cross-session fallback scan. Rewriting is
mandatory. Conversely, **sessionId** rewriting — which the brief assumed necessary — is *not*, because
real sessionIds are already globally unique and single-owner. Net: one map added, one map deleted.

**A4 — what a hostile reviewer would still catch.** `chrome-mcp-proxy`'s README claims MIT while the
repo carries no LICENSE file (GitHub API `license: null`). Had we adopted it on the README's word we
would have vendored unlicensed code. Verified by API, not by reading the README.

---

## 5. Blockers and uncertainties (named, not hedged)

1. **Consent granularity is UNVERIFIED for Dia.** The brief states each new *WebSocket connection*
   pops the dialog. I did not verify whether `Target.attachToTarget` (no new socket) also triggers it
   — the boundary was read-only, and this probe requires touching a browser. **If Dia gates on
   attach rather than on socket, per-client attach multiplies dialogs and the whole design inverts.**
   Cheap discriminator someone with write access should run: one socket, then two sequential
   `attachToTarget` calls on the same target; count dialogs. Chromium's own per-attach gate is
   `DevToolsManagerDelegate::AllowInspectingTarget()`
   (`devtools_agent_host_impl.cc`, `AttachInternal`) — a fork could hang a prompt there.
2. **Chromium CL 7557410** is cited by OrKoN as fixing the discarded-target hang. Whether Dia 1.48.0
   (Chromium 149) contains it is unknown; Dia is a fork on its own cadence, and OrKoN explicitly
   disclaims Arc-family support. Until measured, assume **not** fixed and keep §3.4.
3. **Dia's `Target.getTargets` tier behaviour** (does it expose `type:'tab'` targets, i.e. is it
   Chrome ≥116 semantics?) is unverified. Puppeteer's connect path depends on it. Chromium 149 says
   yes, a fork could differ.
4. **`chrome-pipe-proxy` was not executed**, only read. Its shared-session defect is derived from V8
   source semantics, which is strong, but it is a derivation and not a run.
5. **No LOC estimate survives contact unscathed.** The 800 figure is anchored on three real
   implementations of adjacent scope; the admission filter (§3.4) is the component with no prior art
   and therefore the widest error bar.

---

## 6. Sources

Local, read at HEAD: `puppeteer-core@25.3.0` `src/cdp/TargetManager.ts`, `src/cdp/Connection.ts`,
`src/node/NodeWebSocketTransport.ts` (under `/Users/chrisren/.npm/_npx/bf675e4b8f9df2c5/node_modules/`);
`playwright-core@1.56` `lib/server/chromium/crBrowser.js`, `crConnection.js`
(`/Users/chrisren/Development/shadcn-dashboard/node_modules/`); `chrome-devtools-mcp@1.6.0`
`build/src/browser.js` (`/Users/chrisren/.npm/_npx/15c61037b1978c83/node_modules/`).

Fetched to `…/scratchpad/`: `dhh.cc` (`content/browser/devtools/devtools_http_handler.cc`), `th.cc`
(`content/browser/devtools/protocol/target_handler.cc`), `dahi.cc`
(`content/browser/devtools/devtools_agent_host_impl.cc`), `ws.cc` (`net/server/web_socket.cc`),
`wse.cc` (`net/server/web_socket_encoder.cc`), `v8r.cc`
(v8 `src/inspector/v8-runtime-agent-impl.cc`), `bp.json` (`devtools-protocol/json/browser_protocol.json`),
`cdpRelay.ts` / `cdpRelayV2.ts` / `browserModel.ts` (microsoft/playwright),
`cpp-pipe-cdp-proxy.mjs` (mimkorn/chrome-pipe-proxy), `cmp-cdp-proxy.mjs` (henu-wang/chrome-mcp-proxy).

Issues: [chrome-devtools-mcp#1763](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/1763) ·
[#978](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/978) ·
[#825](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/825) ·
[#1094](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/1094) ·
[crmux#8](https://github.com/sidorares/crmux/issues/8) ·
[chrome-remote-interface#186](https://github.com/cyrus-and/chrome-remote-interface/issues/186)
