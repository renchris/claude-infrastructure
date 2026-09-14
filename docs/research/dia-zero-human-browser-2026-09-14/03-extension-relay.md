# Extension-based CDP relays for zero-human operation on Dia

Research date 2026-09-14. Read-only: Dia, its profile and this machine were not touched.
All source line numbers are from `microsoft/playwright@main` as fetched 2026-09-14.

---

## VERDICT

**Playwright MCP `--extension` is the only rail that is architecturally capable of zero-human
operation, and it is genuinely capable of it — a 32-byte token bypasses the connect dialog
entirely, in shipped first-party code. But its Dia compatibility is UNPROVEN and there is one
specific, dated, first-party data point saying the thing it depends on (`chrome.debugger`) is
broken in Dia.**

Ranked:

| # | Rail | Zero-human? | Dia? | Verdict |
|---|---|---|---|---|
| 1 | **Playwright MCP `--extension`** | **YES** — token bypass, no click, no modal | **UNPROVEN, one adverse data point** | Adopt *if* the 10-minute probe in § Dia passes |
| 2 | **Claude in Chrome** | Partial — no per-connect click, but infobar + site perms | **MEASURED: a11y works, CDP does not** | Already-degraded fallback; not a CDP rail on Dia |
| 3 | **OpenDia** | NO — human-in-loop | Likely (avoids CDP entirely) | Not a CDP relay at all; a11y/scripting ceiling |
| 4 | **Browser MCP** | **NO — hard-blocked by design** | n/a | **Rule out.** Click-per-tab, 17 months stale, no auth |
| 5 | BrowserOS / Nanobrowser | n/a | n/a | **Rule out** — not relays (in-browser agents / a fork) |
| 6 | Generic `/json/version` relays | varies | n/a | **None exists** at usable maturity — see § (b) |

**The load-bearing recommendation is a test, not a tool.** Everything about rail 1 checks out on
paper — security posture, token bypass, capability ceiling, maintenance. The single unknown is
whether `chrome.debugger.attach` works in Dia at all, and that is cheap to settle and impossible
to settle from documents. Run § Dia's probe first; the answer partitions the whole decision.

---

## TWO PREMISE CORRECTIONS

**1. The consent modal is NOT Dia's, and it is not unavoidable.** The brief says the per-connection
dialog is "implemented in Dia's Swift binary." The operator's own prior research refutes this:

> "The 'Allow debugging connection?' modal is a STOCK Chromium 144+ per-connect gate (Dia inherits
> it, not a TBC-custom layer), fired **ONLY on the `dia://inspect` runtime-request flow**, and it is
> non-persistable BY DESIGN… The CLI `--remote-debugging-port` path is **CONSENT-FREE end-to-end**
> — a port you open at launch has no runtime-request gate."
> — `~/.claude/skills/dia-agent/SKILL.md:27-40`

So "avoid the port to avoid the modal" is a false trade. The modal attaches to the *runtime-request*
flow, not to the port.

**2. The real reason to want an extension relay is Chrome 136, not the modal.** Since Chrome 136,
`--remote-debugging-port` is **ignored on the default user-data-dir**
([developer.chrome.com/blog/remote-debugging-port](https://developer.chrome.com/blog/remote-debugging-port)).
That is why the consent-free launch-flag path costs you a *dedicated clean profile* — i.e. cold
logins — and why `dia://inspect` (modal) or an extension relay are the only two routes to the
**warm personal profile**. `chrome.debugger` is a different API with no user-data-dir constraint, so
an extension relay sidesteps the restriction structurally. *That* is the prize here.

---

## RAIL 1 — Playwright MCP `--extension` (Playwright Extension / CDPRelayServer)

**Mechanism.** Three processes, two WebSockets, one of which is a real CDP endpoint.

```
MCP server ──ws://localhost:<eph>/cdp/<uuid>──► CDPRelayServer ──ws:…/extension/<uuid>──► extension
   (playwright.chromium.connectOverCDP)            (translates)        (chrome.debugger.*)
```

- The relay is the MCP server's own in-process WS server, ephemeral port, **two paths only**:
  `/cdp/<uuid>` and `/extension/<uuid>` (`cdpRelay.ts:96-97`, `isAllowedPathname` at `:73`).
- The extension is a **thin reflective RPC shim**, not a CDP speaker. It accepts exactly five
  methods — `chrome.debugger.attach|detach|sendCommand`, `chrome.tabs.create|remove`
  (`relayConnection.ts:41-47`, `ALLOWED_CHROME_COMMANDS`) — and forwards four events back
  (`:50-55`). Anything else → `throw new Error('Unknown method')` (`:282-283`).
- **All CDP semantics live server-side** in `browserModel.ts` / `cdpRelayV2.ts`. The extension never
  parses CDP. This is why the DeepWiki description (`forwardCDPCommand`, `attachToTab`, protocol
  v1) is stale — that is the *old* wire protocol; current is v2 reflective RPC.
- Playwright attaches with `playwright.chromium.connectOverCDP(relay.cdpEndpoint(), {isLocal: true,
  timeout: 0, noDefaults: true})` (`extensionContextFactory.ts:43`).

**Connect handshake — and the click.**

1. MCP server `spawn(executablePath, [...args, href])` where `href` =
   `chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/connect.html?mcpRelayUrl=…&client=…&protocolVersion=2[&token=…]`
   (`cdpRelay.ts:114-154`). If the browser is already running this is just "open this URL".
2. `connect.html` validates the relay host is **`127.0.0.1` or `[::1]`** or refuses (`connect.tsx:60-64`).
3. Version gate: `SUPPORTED_PROTOCOL_VERSION = 2` (`connect.tsx:28`); higher → mismatch error,
   lower → "Update Playwright MCP or CLI" (`:77-91`).
4. **The bypass.** `connect.tsx:96-101`:
   ```ts
   const expectedToken = getOrCreateAuthToken();
   const token = params.get('token');
   if (token === expectedToken) {
     await handleConnectToTab();   // ← no tab arg, no click, no dialog
     return;
   }
   ```
   With a matching token the page auto-connects on load. **No human click, per connect or ever.**
   Without a token it renders a tab picker with per-tab "Allow & select" buttons (`:179-197`).
5. Extension opens the relay WS (`pendingConnection.ts:46-54`), pushes `chrome.tabs.onCreated` per
   initial tab, then `extension.initialized` (`relayConnection.ts:91-93`); relay holds Playwright's
   CDP traffic until then so `Target.setAutoAttach` sees a populated model (`cdpRelayV2.ts:23-27`).

**The token.** 32 `crypto.getRandomValues` bytes, base64url, in `localStorage['auth-token']` of the
extension origin, persistent across restarts (`authToken.tsx:49-72`). Server reads it from
**`PLAYWRIGHT_MCP_EXTENSION_TOKEN`** (`cdpRelay.ts:86`). The dialog prints the exact
`PLAYWRIGHT_MCP_EXTENSION_TOKEN=<tok>` line with a copy button (`authToken.tsx:45-47`).

> **Bootstrap costs exactly one human visit, ever.** `getOrCreateAuthToken()` *mints* a token on
> first connect-page load, so the server cannot know it in advance. One-time: trigger a tokenless
> connect, copy the line, set the env var. Every subsequent connect is silent. (A zero-click
> bootstrap by reading the profile's extension `localStorage` leveldb is possible but fragile and
> not worth it for a one-time cost.)

The code confirms the intent — the timeout is asymmetric on the token's presence
(`cdpRelay.ts:101-102`): `const deadline = this._token ? monotonicTime() + extensionConnectionTimeout : 0;`
— *"Without a token the user has to approve the connection in the browser, which can take
arbitrarily long."*

**Prompts per launch / per action.** Zero and zero, with one caveat that is not a prompt: Chrome's
`chrome.debugger` **infobar** ("X started debugging this browser"). It does not gate anything, but
**its Cancel button detaches the debugger** — and that is a live hazard for a human-shared browser.
Suppression, two ways, both primary-sourced:
- `--silent-debugger-extension-api` at launch — per-launch, needs a full Cmd-Q first, so a Dock
  launch brings it back.
- **`ExtensionInstallForcelist` enterprise policy** — policy-installed extensions don't show the
  banner. **Persistent, survives Dock launches, and the better rail.** On macOS that is a managed
  preferences plist. Both discussed at
  [anthropics/claude-code#69287](https://github.com/anthropics/claude-code/issues/69287)
  (closed not-planned, no maintainer reply).

**Capability vs raw CDP.**

| Capability | Status | Source |
|---|---|---|
| Page/DOM/Runtime/Input on attached tabs | Full — raw `chrome.debugger.sendCommand` at protocol `'1.3'` | `browserModel.ts:_attachTab` |
| Multiple tabs, one client | Yes — tab group is the targeting model; drag in/out attaches/detaches | `connectedTabGroup.ts:64-71,131-155` |
| Multiple agents, one browser | **Yes** — `Map<id, ConnectedTabGroup>`, distinct group title+colour per client; a tab may not be in two clients | `background.ts:42,106-115`; `uniqueGroupStyle` |
| Multiple CDP clients per relay | **No** — second is refused `'Another CDP client already connected'` | `cdpRelay.ts:208-211` |
| `Target.createTarget` / `closeTarget` | Yes → `chrome.tabs.create/remove` | `cdpRelayV2.ts:105-108` |
| Browser-level cmds (`Storage.*`, `Browser.*`, `Network.getAllCookies`) | **Works** — routed through an arbitrary attached tab's debugger session | `browserModel.ts:164-171` |
| `Browser.getVersion` | **Faked** — `product: 'Chrome/Extension-Bridge'` | `cdpRelay.ts:276-281` |
| `Browser.setDownloadBehavior` | **No-op stub returning `{}`** → downloads silently unconfigurable | `cdpRelay.ts:283-285` |
| **Browser-level target / `Target.getTargets`** | **Absent** — there is no browser target; only synthetic `pw-tab-N` page sessions | `browserModel.ts:213` |
| **Incognito / `Target.createBrowserContext`** | **Unavailable** *(inference)* — no browser target to receive it; `chrome.debugger` also cannot reach incognito tabs unless the extension is incognito-enabled | structural |
| `chrome:`, `edge:`, `devtools:` pages | Filtered from picker, never attached | `connectedTabGroup.ts:23,26-28` |
| Chrome Web Store / other extensions' pages | **Not filtered → attach is attempted and Chrome refuses.** This is the `#16239` error class | `connectedTabGroup.ts:23` (gap) |

**Security — strong, and better than an open `:9222`.**
- Bind is **loopback-only by default**: `hostname ??= 'localhost'` (`packages/utils/wsServer.ts:69`);
  a caller must explicitly pass `'0.0.0.0'`. `CDPRelayServer` passes `undefined`.
- **Random UUID paths are the capability**; `isAllowedPathname` rejects everything else.
- **Host header + Origin validation** (`wsServer.ts:104-110,145-156`); Origin is checked only when
  present, so native no-Origin clients pass and web pages from other origins are rejected — the
  same model as the operator's verified `--remote-allow-origins` scoping.
- Extension-side loopback enforcement (`connect.tsx:60-64`), independent of the server.
- 32-byte token for the silent path.
- Residual, and it is the same one the operator already documented for `:9222`: **none of this
  stops another same-user local process.** The UUID path narrows the window (fresh per relay start,
  not discoverable), which is a real improvement over a fixed port.
- Honest blast radius, in the product's own words (`connect.tsx:167-172`): *"Allowing this
  connection exposes the entire browser to the client, including any signed-in sessions, cookies,
  and content in other tabs and windows. Once approved, the client may also be able to reconnect
  later without showing this dialog again, unless you regenerate the token below and then restart
  the browser."*

**Maintenance — the best of any rail here.** Microsoft-published, Web Store v0.4.0 updated
**2026-09-01**, 100,000 users, 4.8/5 (14 ratings),
[listing](https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm).
Source moved *into* the playwright monorepo 2026 (`playwright-mcp#1564`); `playwright-mcp/src/README.md`
now just points at `packages/playwright-core/src/tools/mcp`. Extension source at
`packages/extension/`. Dozens of extension-mode bugs filed and **closed** in the 1550-1750 range —
active maintenance, and a signal the mode is under real load.

**Version coupling — a named hazard, but fail-loud.** Server `protocol.VERSION = 2`
(`protocol.ts:20`) must equal the extension's `SUPPORTED_PROTOCOL_VERSION = 2` (`connect.tsx:28`).
Currently aligned. But the Web Store extension auto-updates on Google's schedule and the npm server
on yours, so a future skew is a matter of time. Both directions produce an explicit error rather
than silent misbehaviour — good polarity, but it *will* break the rail with no fallback when it
happens. Pin the MCP server version and re-smoke after any extension update.

---

## RAIL 2 — Claude in Chrome (already runs in Dia)

- **Mechanism**: MV3 extension using `chrome.debugger`/CDP for the `computer` tool, and the
  accessibility tree for `read_page` / `get_page_text`.
- **Zero-human**: no per-connect click, but per-site permissions must be granted in the extension,
  and the infobar appears (§ Rail 1 suppression applies).
- **Dia — the single best measured data point in this whole report**, from
  [anthropics/claude-code#78763](https://github.com/anthropics/claude-code/issues/78763)
  (Dia **v1.40.1**, Claude in Chrome v1.0.81, Claude Code v2.1.214, macOS 27.0; closed
  *not planned*, labelled `stale`, `has repro`, no maintainer reply):

  | Tool | API | Status |
  |---|---|---|
  | `tabs_context_mcp`, `navigate` | Chrome tabs API | ✅ works |
  | `read_page`, `get_page_text` | accessibility tree | ✅ works |
  | `computer` (`screenshot`, `zoom`) | **chrome.debugger (CDP)** | ❌ **fails 100%** — `Failed to capture screenshot via CDP` |

  Reporter ruled out: extension conflicts, all-other-extensions-disabled, full Cmd-Q restart,
  reinstall, window focus, and a competing debugger client (OpenCLI).
- **Sibling Dia issues, all closed not-planned**: **#19268 — Dia lacks full `chrome.tabGroups` API
  support**; #34830 Dia support request; #36410 Dia detection/native-messaging-host path; #16239
  `Cannot access a chrome-extension:// URL of different extension` (a *different* CDP failure).
- **Verdict**: on Dia this is an accessibility-tree rail, not a CDP rail. Useful as a fallback for
  navigate/read; cannot deliver the CDP capability the brief wants.

---

## RAIL 3 — OpenDia (`aeonfun/opendia`, formerly `aaronjmars/opendia`)

- **Not a CDP relay.** Its manifest declares **no `debugger` permission at all** —
  `["tabs","activeTab","storage","scripting","bookmarks","history"]` + content scripts on
  `<all_urls>` (`opendia-extension/manifest-chrome.json`). It automates via the scripting API and
  content scripts.
- **Consequence, and it cuts both ways**: ruled out as a CDP rail — but it is the *most likely to
  work in Dia*, precisely because it avoids the API that is broken there. No infobar either.
- **Ceiling** (operator's prior measurement, `memory/dia-agent-browser-cdp-entrypoint.md:67-69`):
  *"capped below CDP (no getAllCookies/network domains/low-level input), side-loaded unpacked,
  human-in-loop, Dia-compat unverified."*
- **Zero-human: no.** Human-in-loop per the same note.
- **Maintenance: excellent** — 1,921 stars, pushed **2026-09-13** (one day before this research),
  0 open issues, MIT, topics include `dia`. Actively developed.

---

## RAIL 4 — Browser MCP (`BrowserMCP/mcp`) — RULE OUT

Three independent disqualifiers, each sufficient:

1. **A human click is required, by design, and it is hardcoded in the server's own error string**
   (`src/context.ts:8`):
   > `No connection to browser extension. In order to proceed, you must first connect a tab by
   > clicking the Browser MCP extension icon in the browser toolbar and clicking the 'Connect'
   > button.`

   There is no token, no auto-connect, no bypass anywhere in the protocol.
2. **Unmaintained**: last push **2025-04-24** (~17 months stale as of 2026-09-14), 150 open issues.
   The extension is **closed-source** — the repo states it *"cannot yet be built on its own due to
   dependencies on utils and types from the monorepo where it's developed"*, so its `chrome.debugger`
   usage cannot even be audited.
3. **No auth and a hostile singleton**: `createWebSocketServer` is a bare
   `new WebSocketServer({ port })` with no token, no Host check, no Origin check — and it calls
   **`killProcessOnPort(port)`** first, then spins until the port frees (`src/ws.ts`). It kills
   whatever holds its default port. This independently reproduces the operator's own retirement
   note for BrowserMCP ("port-9009 `kill -9` singleton", retired 2026-08-11, 0 invocations /
   3,504 transcripts / 30 d).

Direction is also inverted vs Playwright's: here the **MCP server is the WS server on a fixed
port** and the extension dials in — so the port is long-lived and guessable rather than ephemeral
and UUID-gated.

Dia registry presence (`bjfgambnhccakkhmkepdoekmckoijdlc` v1.3.4) proves it *installs* in Dia. It
proves nothing about whether it works, and the click requirement makes that moot.

---

## RAIL 5 — BrowserOS / Nanobrowser — RULE OUT (category error)

Neither is a relay. Nanobrowser runs the agent **inside** the browser as an extension (no external
CDP endpoint for an MCP client to attach to); BrowserOS is a **full Chromium fork**, i.e. a
replacement for Dia, not a bridge to it. Targeted searching surfaced no relay architecture or
`/json/version`-style endpoint for either. Both fail the brief's core requirement — "clients are
Claude Code MCP servers / CLIs on the same Mac" attaching to *the user's existing Dia*.

---

## ANSWERS TO THE SPECIFIC QUESTIONS

### (a) Playwright extension mode — protocol, click, Target mapping, missing domains

- **Relay URL**: not `ws://127.0.0.1:<port>/extension/<token>` as hypothesised. It is
  `ws://localhost:<ephemeral>/extension/<random-uuid>`, with the token passed **separately as a URL
  query param on the connect page**, not in the WS path. Two distinct secrets: the path UUID
  (capability for the socket) and the auth token (capability for the silent connect).
- **Click per session**: **not required** with `PLAYWRIGHT_MCP_EXTENSION_TOKEN` set. Required once,
  ever, to read the token out of the dialog.
- **Target mapping**: one `chrome.debugger` tab attach = one synthetic CDP page session
  `pw-tab-<N>` (`browserModel.ts:213`). `targetInfo` is fetched from the real
  `Target.getTargetInfo` at attach and replayed as a synthesised `Target.attachedToTarget` with
  `waitingForDebugger: false` (`:216-219`). Child sessions (workers, OOPIFs) keep their **own** CDP
  sessionIds, tracked per tab so commands route correctly (`:112-116`). `Target.setAutoAttach` on
  the root session is intercepted and turned into "attach to every known tab"
  (`cdpRelayV2.ts:99-104`); on a child session it falls through to the real browser.
- **Unavailable / degraded**: no browser-level target at all (so no `Target.getTargets`,
  no `Target.createBrowserContext`, no incognito contexts); `Browser.getVersion` faked;
  `Browser.setDownloadBehavior` a no-op stub. **`Network.getAllCookies` DOES work** — it is routed
  as a browser-level command through an arbitrary attached tab (`browserModel.ts:164-171`), which
  is the classic route and returns the whole profile's cookies. `Storage.*` commands that require
  an explicit `browserContextId` will fail for want of one.

### (b) Is there a generic `/json/version` + `ws://…/devtools/browser` extension relay?

**No — not at any usable maturity.** Three candidates, all ruled out:

- **Playwright's own `CDPRelayServer` is the closest thing that exists** and it deliberately is not
  this: HTTP requests return **404** unconditionally (`cdpRelay.ts:67-70`), so there is **no
  `/json/version`, no `/json/list`**. It exposes only `ws://localhost:<eph>/cdp/<uuid>`.
  **Practical consequence**: a client that accepts a raw `browserWSEndpoint` works
  (`playwright.chromium.connectOverCDP(<ws url>)`, `puppeteer.connect({browserWSEndpoint})`); a
  client that *discovers* via HTTP — `puppeteer.connect({browserURL})`,
  `chrome-devtools-mcp --browserUrl`, `agent-browser --cdp <port>` — **cannot attach**. That last
  one matters: the operator's whole existing Dia toolchain is `--browserUrl`/`--cdp`-shaped and
  would need a shim (a tiny local HTTP server answering `/json/version` with
  `webSocketDebuggerUrl` pointing at the relay's `/cdp/<uuid>`). Also note the relay accepts
  **one** CDP client only (`:208-211`).
- **`frederico-kluser/chromium-controller`** — right architecture (MV3 `chrome.debugger` + Node WS
  relay, port 7777, protocol 1.3), **0 stars, created 2026-08-20**, MIT. An existence proof, not a
  rail.
- **`axiom.ai` "Chrome API"** — surfaced by search as a token-authenticated relay with a
  `/devtools/browser/<guid>` shape, but reading the docs it is a **cloud browser**
  (`wss://cdp-lb.axiom.ai/?token=…`), explicitly *"no persistent state across sessions"*,
  datacentre IP. It is the opposite of "my warm logged-in browser". Ruled out.

### (c) Loading in Dia

- **Web Store install works.** Dia is Chromium and accepts Web Store installs; the operator's own
  registry read already shows a Web Store extension (Browser MCP v1.3.4) resident in Dia. The
  Playwright Extension is a normal Web Store item.
- **The extension ID is pinned**, so an *unpacked* load gets the same ID: `manifest.json` carries a
  `"key"` field, and `tools/utils/extension.ts:20-21` comments *"Also pinned via the 'key' field in
  packages/extension/manifest.json"* with `playwrightExtensionId = 'mmlmfjhmonkocbjadbfplnigmagldckm'`.
  This matters because the server hardcodes `chrome-extension://<that id>/connect.html` — an
  unpacked load still resolves. **Web Store install is nonetheless preferable**: it also satisfies
  the server's profile precheck, which looks for `<profile>/Extensions/<id>` and notes that
  `--load-extension` *"only leaves a settings record in the preferences"* (`extension.ts:68-79`).
- **The profile precheck is skippable, and this is the key Dia enabler.** `createExtensionBrowser`
  sets `userDataDir = customUserDataDir ?? (executablePath ? undefined : defaultUserDataDirForChannel(channel))`
  and gates the precheck on `if (userDataDir && !executablePath && …)`
  (`extensionContextFactory.ts:32-35`). **Passing `--executable-path` disables the Chrome-profile-layout
  assumption entirely** — the stated reason is a cross-filesystem case (WSL2), and it applies equally
  to a browser whose profile layout Playwright does not know. `registry.findExecutable(channel)` is
  likewise never reached when `executablePath` is set (`cdpRelay.ts:130-138`). So:
  `--extension --executable-path /Applications/Dia.app/Contents/MacOS/Dia` (or
  `PLAYWRIGHT_MCP_EXECUTABLE_PATH`) is the shape to try.
- **`chrome.debugger` in Dia: the open question.** See § Dia below.
- **Infobar + `--silent-debugger-extension-api`**: the switch does suppress the banner, confirmed by
  multiple independent sources incl. `claude-code#69287`; it is per-launch and requires a full
  Cmd-Q. `ExtensionInstallForcelist` is the persistent alternative.

### (d) Failure modes

- **DevTools opening detaches the agent, permanently, and can kill the whole session.** Chrome
  allows one debugger client per target. The relay only re-attaches on detach reason
  `'target_closed'` (`relayConnection.ts:186`) — a DevTools-caused detach (`canceled_by_user`) is
  **not** retried, and if it was the last attached tab the connection closes outright:
  `_checkLastTabDetached()` → `close('All controlled tabs detached')` (`:170-173`). Same for the
  infobar's **Cancel** button. **In a browser shared with a human this is the most likely real-world
  breakage**, and it is silent from the agent's side beyond a closed socket.
- **MV3 service-worker suspension: NOT a risk.** Two independent protections, both applicable to
  Dia (Chromium 149), from
  [the MV3 lifecycle doc](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle):
  *"Sending or receiving messages across a `WebSocket` in an extension service worker resets the
  service worker's idle timer"* (Chrome 116+), and **Chrome 118+: active debugger sessions prevent
  timeout**. Base idle timeout is 30 s. The extension additionally hand-rolls a 20 s keepalive ping
  from the connect page for the *pending-approval* window only (`connect.tsx:114-120`,
  `background.ts:95-98`) — which is exactly the window the token bypass eliminates.
- **Service-worker restart loses all connection state** and is handled: `cleanupStalePlaywrightGroups()`
  runs at construction and ungroups orphaned Playwright tab groups (`background.ts:52`,
  `connectedTabGroup.ts:49-62`).
- **Per-tab exclusivity, not a limit**: a tab may belong to only one client —
  `'This tab is already connected to another client'` (`background.ts:106-107`). No cap on tabs per
  client or clients per browser.
- **Restricted pages**: `chrome:`, `edge:`, `devtools:` are filtered (`connectedTabGroup.ts:23`).
  **The Chrome Web Store is not**, so attach is attempted and refused — this is the `#16239` error
  family. **`dia:` is also not in the list**, so a `dia://` internal page would pass the filter and
  fail at attach. A tab that navigates *to* a non-debuggable URL is detached on `onUpdated`
  (`:127-128`); one that navigates away re-attaches (`:148-149`).
- **Popup handling**: only popups whose `openerTabId` is an attached tab are forwarded
  (`relayConnection.ts:243-248`).
- **Re-attach thrash guard**: 150 ms delay, 2.5 s verify, 3 s cooldown; a tab that re-detaches
  inside the cooldown is not retried (`relayConnection.ts:57-59,192-204`).

---

## DIA COMPATIBILITY — the evidence, and the one test that settles it

**What is measured.** `chrome.debugger`-based CDP screenshot fails 100% in Dia v1.40.1 while
accessibility-tree and `chrome.tabs` tools work (`claude-code#78763`). `chrome.tabGroups` is
reported incomplete in Dia (`#19268`).

**Why that is not yet a verdict.** The failure is reported at the level of one command
(`Page.captureScreenshot`) inside one product's tool. Two readings are consistent with it and they
have **opposite** consequences:

- **(i) `chrome.debugger.attach` itself fails in Dia** → the entire extension-relay rail is dead on
  Dia, and rail 1's score collapses to zero.
- **(ii) attach works; `Page.captureScreenshot` specifically fails** → plausibly Dia's custom
  Swift/native window shell breaking the compositor capture path, which is exactly the kind of
  thing a fork with a bespoke tab UI breaks. Then rail 1 works for navigation, DOM, Runtime, Input
  and cookies, and loses only screenshots.

The issue does not distinguish them, no maintainer replied, and it is closed `not planned`. **This
is the one question no amount of further document research can answer** — and it is the question the
decision turns on. Do not infer either reading from the absence of the other.

**Two Dia-specific structural risks beyond attach**, both from reading the code against `#19268`:

1. **`tabGroups` is load-bearing, not cosmetic.** The manifest requires the `"tabGroups"` permission,
   and `connectedTabGroup.ts:64-71` states *"The Chrome tab group is the single source of truth for
   which tabs the client targets."* `cleanupStalePlaywrightGroups()` calls `chrome.tabGroups.query({})`.
   If Dia's `tabGroups` support is partial, the extension's whole targeting model is affected even
   if `chrome.debugger` is fine. **This is an independent failure axis and it has its own adverse
   data point.**
2. **The connect page arrives as an argv.** The server does
   `spawn(diaBinary, ['chrome-extension://…/connect.html?…'])`. A custom Swift shell may not route a
   `chrome-extension://` argv to a tab the way Chrome does. Untested; cheap to test.

**The probe.** Read-only, ~10 minutes, settles (i) vs (ii) and both risks above, in Dia, without
installing any MCP server. Lead runs it; I did not.

1. In Dia, install the Playwright Extension from the Web Store (the one install this needs).
2. Open `dia://extensions`, open the extension's service-worker DevTools console.
3. In that console — **this is the discriminating call, and it needs no relay at all**:
   ```js
   const [tab] = await chrome.tabs.query({active:true, currentWindow:true});
   await chrome.debugger.attach({tabId: tab.id}, '1.3');           // ← (i) vs (ii)
   await chrome.debugger.sendCommand({tabId: tab.id}, 'Runtime.evaluate', {expression:'location.href'});
   await chrome.debugger.sendCommand({tabId: tab.id}, 'Page.captureScreenshot');  // expected to fail
   await chrome.tabGroups.query({});                                // ← risk 1
   await chrome.debugger.detach({tabId: tab.id});
   ```
   Attach throws ⇒ reading (i), rail 1 is dead on Dia, fall back to the launch-flag port on a
   dedicated profile. Attach succeeds and `Runtime.evaluate` returns ⇒ reading (ii), rail 1 is
   viable; screenshots become a known gap to route around (`Page.captureScreenshot` is not needed
   for most agent work, and a11y snapshots cover the rest).
4. Only if step 3 passes: `open -a Dia 'chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/connect.html?mcpRelayUrl=ws://127.0.0.1:1/extension/x&client=%7B%22name%22:%22probe%22%7D&protocolVersion=2'`
   — tests risk 2. It should render the dialog and then fail to reach the fake relay; rendering at
   all is the pass.

---

## ADVERSARIAL PASS — what I nearly got wrong

Findings from deliberately attacking my own draft, each investigated with real calls and folded
into the body above:

- **DeepWiki's protocol description is stale and I initially believed it.** It describes
  `forwardCDPCommand` / `attachToTab` / protocol v1 with the CDP translation in the extension.
  Current shipped code is a reflective `chrome.*` RPC with translation server-side, protocol v2.
  Reading the actual source changed the capability analysis materially — the five-command allowlist
  is a much tighter attack surface than a generic CDP forwarder, and it relocates every "which
  domain is missing?" question from the extension to `browserModel.ts`.
- **I assumed the relay bound to all interfaces.** `listen(0, undefined, '')` looks like a
  wide-open bind. It is not: `hostname ??= 'localhost'` at `packages/utils/wsServer.ts:69`, plus
  Host and Origin validation. Had I not chased the `@utils/wsServer` alias through the repo tree I
  would have published a false security defect. **The bind is correct; the residual is
  same-user local processes only.**
- **I nearly rated `axiom.ai` as a generic local relay** on the strength of a search summary that
  described a token-authenticated `/devtools/browser/<guid>` relay. The docs say it is a *cloud
  browser* with no persistent state — the exact opposite of the requirement. Search summaries
  conflate architectures; the doc fetch refuted it.
- **The brief's framing "avoid the port to avoid the modal" is a false trade** and I initially
  accepted it. The operator's own skill says the modal is stock Chromium 144+ and fires only on the
  `dia://inspect` runtime-request flow, while a launch-flag port is consent-free. The *actual*
  motivation for an extension relay is the Chrome 136 default-profile block — which is a stronger
  argument, not a weaker one, and it reframes the fallback: if rail 1 dies on Dia, the fallback is
  not "live with the modal", it is "dedicated profile + launch flag, and pay in cold logins".
- **I under-weighted `tabGroups`.** My first pass treated `#19268` as a minor sibling issue. It is
  an independent failure axis with its own adverse Dia data point, because the tab group *is* the
  targeting model in this extension. Added as risk 1 and to the probe.
- **I nearly reported OpenDia as a weak CDP relay.** Reading its manifest shows no `debugger`
  permission at all — it is not a CDP relay in any degree. The correct framing inverts the
  conclusion: its avoidance of CDP is precisely why it is the *most* likely to work in Dia.
- **A gap I could not close and am not papering over**: there is **zero** Dia-specific evidence in
  `playwright-mcp` or `playwright` issues (searched; 0 hits). Nobody has published a Playwright-
  extension-on-Dia result. The probe is the only way to know.

---

## BLOCKERS AND UNCERTAINTIES (named)

1. **BLOCKER — `chrome.debugger.attach` in Dia is unverified**, with one adverse first-party data
   point at command level (`#78763`). Resolvable only by the § Dia probe. Everything else about
   rail 1 is conditional on this.
2. **BLOCKER — `chrome.tabGroups` completeness in Dia is unverified**, with an adverse data point
   (`#19268`), and it is load-bearing for tab targeting.
3. **UNTESTED — whether Dia routes a `chrome-extension://` argv to a tab.** The connect page arrives
   only this way.
4. **UNTESTED — `--executable-path` against a non-registry Chromium fork.** The code path is clear
   (precheck and registry both skipped) but no Dia instance has exercised it.
5. **NO `/json/version`** on the relay, so `chrome-devtools-mcp --browserUrl` and
   `agent-browser --cdp` — the operator's existing toolchain — cannot attach without a small
   HTTP shim. Playwright/puppeteer with a raw `browserWSEndpoint` can.
6. **One CDP client per relay**; N agents need N relays (which is supported, with per-client tab
   groups) — not N clients on one relay.
7. **Version-skew fragility** between the auto-updating Web Store extension and the pinned npm
   server. Fail-loud, but rail-breaking when it fires.
8. **DevTools / infobar-Cancel silently and permanently detaches** — the realistic failure in a
   human-shared browser. Suppress the infobar via `ExtensionInstallForcelist` and treat "human
   opened DevTools" as a reconnect trigger, not an error.
9. **Incognito unavailability is an inference**, not a measurement — structurally there is no
   browser target to receive `Target.createBrowserContext`, and `chrome.debugger` cannot reach
   incognito tabs unless the extension is incognito-enabled. Not tested.
10. **`#78763` is closed `not planned` and `stale`** — Dia is not a supported target for any of
    these tools. Nothing here will be fixed on request; every rail is use-at-own-risk on Dia.

---

## ALTERNATIVES CONSIDERED AND RULED OUT

| Option | Ruled out because |
|---|---|
| Browser MCP | Human click per tab, hardcoded in the server's error string; 17 months stale; no auth; kills whatever holds its port |
| OpenDia as a *CDP* rail | No `debugger` permission at all — scripting/content-script ceiling, no cookies/network/low-level input |
| BrowserOS | A Chromium fork — replaces Dia rather than bridging to it |
| Nanobrowser | In-browser agent; exposes no endpoint for an external MCP client |
| `axiom.ai` Chrome API | Cloud browser, datacentre IP, no persistent state — not the warm local profile |
| `frederico-kluser/chromium-controller` | 0 stars, created 2026-08-20; existence proof only |
| Dia native agent-server `:54271` | Bearer-gated / product-internal; confirmed dead surface (operator's prior measurement) |
| Hammerspoon auto-approver for the `dia://inspect` modal | Already refuted as a default by the operator: nullifies the only gate, TOCTOU race, consent is web-rendered (AX-opacity risk). Last resort only |
| `--remote-debugging-port` on the warm default profile | Blocked since Chrome 136 — the constraint that makes this whole question necessary |

---

## SOURCES

Primary source (read directly, `microsoft/playwright@main`, 2026-09-14):
`packages/extension/manifest.json` · `packages/extension/src/{background,relayConnection,pendingConnection,connectedTabGroup}.ts` ·
`packages/extension/src/ui/{connect,authToken}.tsx` ·
`packages/playwright-core/src/tools/mcp/{cdpRelay,cdpRelayV2,browserModel,extensionContextFactory,protocol,config}.ts` ·
`packages/playwright-core/src/tools/utils/extension.ts` · `packages/utils/wsServer.ts` ·
`BrowserMCP/mcp` `src/{ws,context}.ts` · `aeonfun/opendia` `opendia-extension/manifest-chrome.json`

Local prior research (operator's, lead-adjacent):
`~/.claude/skills/dia-agent/SKILL.md:18-60,233` ·
`~/.claude/projects/-Users-chrisren-Development-reso-management-app/memory/dia-agent-browser-cdp-entrypoint.md:60-75,118-132`

Web:
- https://playwright.dev/mcp/configuration/browser-extension
- https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm
- https://github.com/anthropics/claude-code/issues/78763 (Dia CDP failure; also #19268, #16239, #34830, #36410)
- https://github.com/anthropics/claude-code/issues/69287 (infobar suppression)
- https://developer.chrome.com/blog/remote-debugging-port (Chrome 136 default-profile block)
- https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle (MV3 idle timer, WS + debugger exemptions)
- https://developer.chrome.com/docs/extensions/reference/api/debugger
- https://github.com/microsoft/playwright-mcp/issues/{1564,1590,1662,1708,1712,1732}
- https://github.com/frederico-kluser/chromium-controller · https://axiom.ai/docs/developer-hub/api/cdp/
- https://deepwiki.com/microsoft/playwright-mcp/7-browser-extension-integration (**stale — describes protocol v1; retained only to mark the trap**)
