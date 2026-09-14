# 09 — Prior art: how shipping products achieve prompt-free unattended browser control

Research date 2026-09-14. Read-only web survey. Machine unchanged.

## THE HEADLINE, BEFORE THE TABLE

**The M144 dialog approves the *connection*, once — not the action.** Chrome's own control-plane
documentation states the Allow/Deny prompt "approves the _connection_, once" and that "no per-call
approval exists"
(<https://agenticcontrolplane.com/mcp-controls/chrome-devtools>). Chrome's DevTools docs agree the
dialog fires "every time the Chrome DevTools MCP server **requests** a remote debugging session"
(<https://developer.chrome.com/docs/devtools/agents/get-started/configuration>).

So **"dozens per session" is a symptom of connection churn in the client, not a property of Chrome.**
Two independent implementations have already collapsed it to one:

- `chrome-mcp-proxy` — "Persistent WebSocket connection to Chrome — the remote debugging popup only
  appears once, ever" (<https://github.com/henu-wang/chrome-mcp-proxy>)
- `chrome-cdp-skill` — "On first access to a tab, a lightweight background daemon is spawned that
  holds the session open"; "the modal fires once" per tab
  (<https://github.com/pasky/chrome-cdp-skill>)

These two disagree on the *unit* (once ever vs once per tab) and both are correct: the dialog gates
one WS attach to the browser-level endpoint. `chrome-mcp-proxy` holds one for the whole process;
`chrome-cdp-skill` spawns one daemon **per tab**, hence one attach per tab. **The unit of consent is
the connection you hold open.**

**Neither vendor will fix it upstream.** Both requests are closed:
- "Allow persisting remote debugging permission approval" — **closed as not planned**
  (<https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/825>)
- "started debugging this browser banner … please add a built-in way to suppress it" — **closed as
  not planned / stale** (<https://github.com/anthropics/claude-code/issues/69287>)

## COMPARISON TABLE

| Product | Control mechanism | Where the agent runs | What the user approves, how often | Isolation from the human's tabs | Runs in an arbitrary Chromium fork? | Evidence |
|---|---|---|---|---|---|---|
| **Anthropic Claude in Chrome** | Extension `chrome.debugger` (CDP from inside the browser) — confirmed: "that extension attaches over CDP, so the bar fires" | Model in Anthropic cloud; execution in the extension service worker, in your browser | Install once; then per-site **"Always allow actions on this site"**; 3 modes (manual / auto / skip) **persist across sessions**; downloads, sensitive input and authorizations *always* re-prompt regardless of mode | **Tab-group only.** New tabs collected into a session-bound tab group. No storage boundary — it *is* your logged-in state | **Yes, where the fork does MV3 + native messaging.** Chrome + Edge official; Brave/Arc/Vivaldi/Opera detected. **Dia is NOT in the registry** | [permissions guide](https://support.claude.com/en/articles/12902446-claude-in-chrome-permissions-guide) · [#69287](https://github.com/anthropics/claude-code/issues/69287) |
| **Claude Code `--chrome`** | Same extension, reached by a **native messaging host** JSON per browser config dir | CLI drives the extension over the native host | One-time intro dialog; then `Claude in Chrome wants to` with **"allow all actions on that site for the session"** | Session tab group; closed on `/clear` if empty | Reads `NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json` from **each browser's own config dir** → fork-portable by construction. Dia blocked only by a hardcoded browser list | [docs](https://code.claude.com/docs/en/chrome) · [#34830](https://github.com/anthropics/claude-code/issues/34830) |
| **OpenAI ChatGPT Atlas (OWL)** | Native in-browser agent | In the browser it ships | Logged-in vs logged-out mode is the grant; pauses on sensitive sites (financial) to make you watch | **Best in class.** Chromium **StoragePartition** in-memory data stores, *not* Incognito; discarded at session end; multiple concurrent isolated sessions, each its own tab | N/A — it is the browser | [bytebytego teardown](https://blog.bytebytego.com/p/the-architecture-behind-atlas-openais) · [help center](https://help.openai.com/en/articles/12628199-using-ask-chatgpt-sidebar-and-chatgpt-agent-on-atlas) |
| **Perplexity Comet** | **Bundled extension** `comet-agent` calling `chrome.debugger`; reads pages via `Accessibility.getFullAXTree` | 700 KB service worker in-browser, RPC'd from Perplexity backend; Sidecar is UI only | Enable browser control once, with an **"Always Allow"** option; admins can set per-domain read-only | Acts in your real session. Guard is a **code-level blocklist** (`isUrlBlocked`, `isInternalPage`), not a storage boundary | N/A | [Zenity Labs reversing](https://labs.zenity.io/post/perplexity-comet-a-reversing-story) · [permissions](https://www.perplexity.ai/help-center/en/articles/13531023-managing-comet-assistant-permissions) |
| **Google Gemini in Chrome / Auto Browse** | Native in-browser (Project Mariner **shut down 2026-05-04**, folded in) | In Chrome | Consumer path — the browser already holds the auth, "reduces the trust gap" | Not documented as a storage boundary | N/A | [Mariner shutdown](https://www.androidheadlines.com/2026/05/google-shuts-down-project-mariner-ai-agent.html) · [landscape](https://nohacks.co/blog/agentic-browser-landscape-2026) |
| **Microsoft Copilot Mode in Edge (Actions + Journeys)** | Native in-browser; screenshots + on-page interaction | In Edge | Permission grant, then **per-sensitive-action elevation**; wallet/passwords need explicit consent; enterprise DLP applies | Uses the signed-in session; credential store gated | N/A | [SiliconANGLE](https://siliconangle.com/2025/11/18/copilot-mode-makes-edge-business-enterprise-ready-agentic-browser/) |
| **Opera Neon (Neon Do)** | Hybrid: cloud agents + **Neon Do executes locally** | Split device/cloud | Per-Task activation | "mini-browser for each task"; runs in your logged-in session so "no need to share passwords with cloud services" | N/A | [Opera press](https://press.opera.com/2025/09/30/opera-neon-ai-agentic-browser-release/) |
| **BrowserOS neo** (ex BrowserClaw, AGPL-3.0) | **Chromium fork that exposes MCP to external agents** — Claude Code, Codex, Cursor, Cowork | Your machine; "nothing goes to a server we own" | "Link … via MCP. No config files, no CLI." Then continuous oversight: watch live, replay any session | **The stated invariant:** "Every agent opens its own tabs to work in and **never touches the ones you already have open**. It cannot close the doc you are writing." Uses your real logins | It *is* a purpose-built fork — the closest shipping analogue to the operator's goal | <https://www.browseros.com/> · <https://github.com/browseros-ai/BrowserOS> |
| **Nanobrowser** | MV3 extension, BYO LLM key, planner→navigator→validator | Entirely local, in the extension | Extension install + host permissions. No per-connection consent | Own tabs, your profile | **Yes** — any Chromium with MV3 (incl. Dia, which dropped MV2 at v1.17) | <https://github.com/nanobrowser/nanobrowser> |
| **Playwright MCP `--extension`** | Extension service worker → `chrome.debugger.attach()` → **WS to a local relay** → CDP forwarded both ways | MCP server local; execution in-browser | **Pick which tab** per connection, + the debugger banner | One bound tab; reuses your logins, cookies, extensions. `chrome.debugger` blocked on `chrome://` and Web Store pages | **Officially Chrome or Edge only** ("Install the extension in Chrome or Edge") | [docs](https://playwright.dev/mcp/configuration/browser-extension) · [DeepWiki](https://deepwiki.com/microsoft/playwright-mcp/7-browser-extension-integration) |
| **chrome-devtools-mcp** | CDP. Three modes: self-launched **dedicated profile** (default, `~/.cache/chrome-devtools-mcp/chrome-profile`) · `--isolated` temp dir · `--autoConnect`/`--browserUrl` onto a warm browser | Local MCP server | **Self-launched: nothing.** Warm attach: one Allow **per connection**, unpersistable | Dedicated profile by default. Warm attach = **none**: "all open windows for the selected profile" | CDP works on any Chromium exposing a debug endpoint — but M144's `chrome://inspect` variant is **WS-only with no HTTP discovery**, which breaks naive clients | [config](https://developer.chrome.com/docs/devtools/agents/get-started/configuration) · [control model](https://agenticcontrolplane.com/mcp-controls/chrome-devtools) |
| **agent-browser (Vercel Labs)** | CDP: `--cdp <port \| ws(s) URL>`, `--auto-connect`, persistent daemon, `--pin-tab` | Local daemon | One Allow per connection on the warm path | **Tab-level only.** Binding by CDP target id, persisted across daemon restarts; `tab_gone` rather than silent tab-switch. **Storage is NOT isolated** — shared default BrowserContext leaks cookies/localStorage between agents | Yes if the fork exposes CDP. **`--auto-connect` is broken on M144+** | [CDP mode](https://agent-browser.dev/cdp-mode) · [#516](https://github.com/vercel-labs/agent-browser/issues/516) · [#1068 OPEN](https://github.com/vercel-labs/agent-browser/issues/1068) |
| **Browser Use** | CDP to system Chrome via `Browser.from_system_chrome(profile_directory=…)` | Local | None beyond launching | Profile-level; **"You may need to fully close Chrome before running"** — i.e. it wants the browser to itself | Chromium generally | [real-browser docs](https://docs.browser-use.com/open-source/customize/browser/real-browser) · [#1520](https://github.com/browser-use/browser-use/issues/1520) |
| **Stagehand / Skyvern** | Playwright `connectOverCDP` | Local or cloud | None | Whatever profile you point at | Yes | [Skyvern browser config](https://www.skyvern.com/docs/developers/self-hosted/browser) |
| **`chrome-cdp-skill`** (relay pattern) | Persistent **daemon per tab** over the `chrome://inspect` WS | Local daemons | **Modal once per tab**; daemons auto-exit after 20 min idle | Per-tab | Auto-detects Chrome, Chromium, **Brave, Edge, Vivaldi** — not Dia | <https://github.com/pasky/chrome-cdp-skill> |
| **`chrome-mcp-proxy`** (multiplexer pattern, **built for Claude Code**) | `Claude Code → chrome-devtools-mcp → CDP Proxy → Chrome`; one persistent WS | Local broker | **"the remote debugging popup only appears once, ever"** | Request-ID remapping (no collisions across clients); **event routing by sessionId** so each agent sees only its own targets; blocks `Target.activateTarget` / `Page.bringToFront`; forces `Target.createTarget` background | Any Chromium with a debug endpoint | <https://github.com/henu-wang/chrome-mcp-proxy> |
| **Dia's own agent** | Native: Skills + an agent builder with **Visit Page / Extract / API Call** nodes for scheduled DOM loops | In Dia | Nothing per run | Native, undocumented | It *is* Dia — and Dia ships Chrome Web Store MV3 extension support, MV2 dropped at v1.17 | [review](https://dynalord.com/blog/dia-browser-review) · [extensions](https://www.superchargebrowser.com/library/dia-browser-vs-chrome-extensions/) |
| **Arc Max** | Right-click actions, no agentic loop | — | — | — | — | superseded; TBC → Dia → Atlassian ($610M, 2025-10-21) |

## DIRECT ANSWERS

### (b) Which of these can run inside Dia?

**Can:** anything that is an MV3 extension — Nanobrowser, the Claude in Chrome extension itself
(reporter of [#34830](https://github.com/anthropics/claude-code/issues/34830) confirms "The Claude
Browser Extension … installs and runs correctly in Dia" and "the sidebar works fine, confirming
**Native Messaging is functional**"). Also anything that speaks raw CDP to `dia://inspect`.

**Cannot:** every native in-browser agent (Atlas, Comet, Gemini/Auto Browse, Copilot Mode, Neon,
BrowserOS neo) — they are browsers, not components. Playwright MCP `--extension` is Chrome/Edge-only
by its own docs.

**The Dia-specific blocker is a hardcoded list, not a capability gap.** Claude Code registers native
messaging hosts for Chrome, Chromium, Edge, Arc, Vivaldi, Brave, Opera. Dia (`company.thebrowser.dia`,
`~/Library/Application Support/Dia/`) is absent, and `switch_browser` therefore does not offer it
**even after the host config is copied into Dia's own directory**. #34830 was **closed as duplicate
with no workaround and no maintainer reply**.

### (c) The emerging standard answer to 136+ / M144

There are **four** answers in the wild, and they are not equivalent:

1. **Non-default `--user-data-dir`** — Chrome's own only prescription: the switches "will no longer be
   respected if attempting to debug the default Chrome data directory"; use "a custom user data dir
   … to isolate any debugging from any real profiles", or Chrome for Testing
   (<https://developer.chrome.com/blog/remote-debugging-port>). **Self-launching this way has NO
   consent dialog at all.** The dialog is the price of the *warm default profile*, nothing else.
2. **Copy the profile** (`cdb`): `rsync -a --delete` the signed-in user-data-dir to `/tmp`, launch
   from the copy with CDP on. Explicitly "preserving cookies/logins" and keeping automation "from
   mutating the live default Chrome profile". Re-sync is **manual** (`cdb --fresh`) after any login
   change (<https://gist.github.com/heyalexej/26d734579cab5e616dcf0599e235ba21>).
3. **Extension relay over `chrome.debugger`** — `--remote-debugging-port` is not involved at all, so
   the 136 restriction is structurally inapplicable. Playwright MCP `--extension`, Browser MCP,
   `opencode-chrome`, Comet, Claude in Chrome. This is what every *shipping consumer product* chose.
4. **"Just click Allow", once, and hold the connection** — `chrome-mcp-proxy`, `chrome-cdp-skill`.

**Not an answer:** waiting for upstream. #825 closed not planned; #69287 closed not planned;
Playwright's M144 `chrome://inspect` support request ([#40027](https://github.com/microsoft/playwright/issues/40027))
is **closed**, and the WS handshake "times out waiting for expected protocol messages" — so
`connectOverCDP` against `ws://127.0.0.1:9222/devtools/browser/<id>` is not a drop-in today.

### (d) Products that run a local broker for many agent clients

Three exist, all young, all single-maintainer:
- **`chrome-mcp-proxy`** — the closest to the operator's design, explicitly "Built for Claude Code",
  with multi-agent isolation *and* the anti-focus-stealing behaviour a shared warm browser needs.
- **`agent-browser` daemon + `--pin-tab`** — bindings survive daemon restarts.
- **`chrome-cdp-skill`** — daemon *per tab*; "handles 100+ tabs reliably".
- Adjacent: `browserbase/ModCDP` (CDP middleware that also exposes `chrome.*` extension APIs to
  Playwright/Stagehand drivers), `chromedp-proxy` (logging only).

## WHAT 100th-PERCENTILE LOOKS LIKE (10 lines)

1. The agent's browser is the **human's warm browser**, because reusing real sessions is the entire
   value; every serious product refuses the sandbox ("automate your real work instead of poking a
   sandbox" — BrowserOS neo).
2. Control enters through a capability the browser **already trusts** — a bundled or force-installed
   extension's `chrome.debugger`, or a native agent — never an externally-opened debug port.
3. Exactly **one** long-lived connection exists, held by a local broker; agents are multiplexed onto
   it by sessionId, so consent is paid once for the life of the browser.
4. Consent is **coarse and durable**: a mode that persists across sessions, plus per-origin
   "always allow", plus a small always-prompt set (downloads, credentials, payments, authorizations).
5. The agent's work is **storage-isolated inside the same window**: Atlas's per-session
   StoragePartition, whose CDP equivalent is `Target.createBrowserContext` with `disposeOnDetach`.
6. Below that ceiling, the hard floor is **own-tabs-only**: the agent creates its tabs, adopts none,
   activates none, and cannot close yours.
7. Tab bindings are **durable identifiers** (CDP target id) persisted across broker restarts, and a
   vanished tab is an **error**, never a silent re-target.
8. Focus is never stolen — `Target.activateTarget` and `Page.bringToFront` are blocked, new targets
   forced background — because an unattended agent that raises windows is unusable beside a human.
9. A **visible, non-modal** indicator persists for the whole session (debugger infobar, "controlled
   by automated test software", a cockpit tab) — the human trades modals for ambient awareness.
10. Sessions are **replayable** after the fact (BrowserOS neo), because oversight of unattended work
    is audit, not approval.

**The three architectural invariants shared by the best implementations:**

- **I1 — Consent is priced per connection, so hold one connection.** The unit of approval is the
  attach, never the action. Every implementation that got to zero prompts did it by never
  reconnecting, not by suppressing a dialog.
- **I2 — Execute from inside the browser's own trust boundary.** Extension `chrome.debugger` or a
  native agent. The external debug port is the path both Google and Anthropic have now declined to
  make quieter, and it is the only path Chrome actively restricts.
- **I3 — Isolate by storage partition, not by browser instance.** A second browser loses the logins;
  a shared default context leaks them between agents. The correct boundary is a context inside the
  warm browser — "the context is a storage boundary, not a windowing boundary".

## ADVERSARIAL PASS — what I checked because it would have broken the above

- **"Is the dialog really per-connection, or per-action?"** Checked three independent sources. It is
  per **connection attempt**. This inverts the framing of the whole problem: the operator's
  multiplexer does not need a *gated auto-approver* at all — it needs to stop reconnecting. A
  gated auto-approver is engineering around a self-inflicted wound.
- **"Does the extension path have its own hidden prompt?"** Yes, but it is an **infobar, not a
  modal**: "started debugging this browser", shown on every tab until all debuggers detach. Two
  suppressions exist — `--silent-debugger-extension-api` (per launch, so a Dock launch brings it
  back) and **`ExtensionInstallForcelist` force-install, under which policy-managed extensions
  "never raise the bar at all"**. The banner is also the *only visible sign* something holds full
  DevTools access to every session you are logged into; suppressing it on a shared machine is a
  worse idea than on this one.
- **"Does the cloned-profile option actually keep the logins?"** Contested, and I could not settle
  it. `cdb` claims yes in practice via `rsync`. Chrome's 136 blog claims a non-standard data dir
  "uses a different encryption key", and on macOS the passphrase lives in the login keychain as
  "Chrome Safe Storage" — accessible to the same app binary, so a copy launched by the *same* Chrome
  should decrypt, while a third-party reader cannot. **Unresolved; needs a one-command empirical
  test before the option is costed.** (And for Dia the keychain item would be Dia's, not Chrome's.)
- **"Does the extension route survive unattended operation?"** **No, and this is the strongest
  argument against it.** Claude Code's own docs: "The Chrome extension's service worker can go idle
  during extended sessions, which breaks the connection… run `/chrome` and select 'Reconnect
  extension'." Claude in Chrome's scheduler cannot wake a browser either — "Scheduled tasks demand an
  open Chrome browser; close it, and they pause until relaunch." An MV3 service worker is a worse
  host for a long-lived unattended relay than a local daemon is.
- **"Is the extension route even reachable from Claude Code today?"** Not reliably.
  [#92571 (OPEN)](https://github.com/anthropics/claude-code/issues/92571): the site-approval prompt
  **never fires on the MCP channel** — every `mcp__claude-in-chrome__*` call returns "This site is
  blocked by your site permissions" for **every site including google.com**, side-panel approvals do
  **not** propagate ("the two surfaces appear to keep separate site-permission stores with no prompt
  path on the Claude Code side"), and the settings page offers no way to add a site by hand. Seven
  debugging steps, no resolution, no maintainer reply, on CC 2.1.263.
- **"Is CDP-level storage isolation actually available, or only in Atlas?"** Available:
  `Target.createBrowserContext` on the **browser-level** session, `disposeOnDetach: true`, then
  `Target.createTarget` with `browserContextId`. agent-browser simply has not exposed it
  ([#1068, OPEN](https://github.com/vercel-labs/agent-browser/issues/1068)), which is why its
  parallel agents leak cookies today.
- **Axis I initially assumed irrelevant and was wrong about:** *whose* profile the default is.
  chrome-devtools-mcp's default is **not** the operator's mental model of "attach to my browser" — it
  silently launches its own Chrome on a persistent dedicated profile, and "anything the agent logs
  into is still logged in next session, for whatever prompt-injected task comes along later". A
  dedicated profile is not automatically the safe choice; a *persistent* dedicated profile is an
  accumulating credential store with no owner.

## ALTERNATIVES CONSIDERED AND RULED OUT

| Option | Ruled out because |
|---|---|
| Wait for Chrome to add "Always allow from this computer" | #825 **closed as not planned**. |
| Wait for Anthropic to suppress the debugger banner | #69287 **closed as not planned / stale**. |
| Playwright `connectOverCDP` against the M144 WS endpoint | #40027 **closed**; the WS connects then "times out waiting for expected protocol messages". |
| Playwright MCP `--extension` in Dia | Its docs scope it to **Chrome or Edge**; `chrome.debugger` is also blocked on internal pages. |
| Adopt a native agentic browser (Atlas / Comet / Neon / Copilot Mode) | They are browsers, not components — cannot be driven by Claude Code, and would replace Dia rather than serve it. |
| Project Mariner as a reference implementation | **Shut down 2026-05-04**; capabilities folded into Gemini Agent + Chrome Auto Browse. |
| `--silent-debugger-extension-api` as the durable fix | Per-launch only; a Dock launch restores the banner. Force-install policy is the durable form. |

## BLOCKERS AND UNCERTAINTIES (named)

1. **Unverified for Dia specifically:** whether `dia://inspect` is the M144 WS-only variant (Dia 1.48
   on Chromium 149 implies yes) and therefore whether one held connection collapses the operator's
   "dozens" to one. **Falsifier:** attach once with a persistent daemon and count dialogs over 30
   minutes of activity. This is the cheapest high-value test available and it decides between the
   multiplexer and the extension relay.
2. **Unverified:** whether Dia honours Chromium managed policy (`ExtensionInstallForcelist` via
   `defaults write company.thebrowser.dia`). If it does, force-install gives a bannerless extension
   relay. If it does not, the extension route always shows the infobar.
3. **Unverified:** whether a `rsync`'d Dia profile yields working logins (keychain/encryption-key
   question above). Decides the cloned-profile option.
4. **Not tested by me:** every tool in the table. This is a documentation and issue-tracker survey;
   no code was run and nothing on this machine was changed.
5. **Single-maintainer risk** on all three broker implementations; `chrome-mcp-proxy` is the closest
   fit and the least battle-tested. Its README says nothing about M144 or about forks, so its "once,
   ever" claim is untested against `dia://inspect`.
6. **Weak sources flagged:** Atlas internals come from a third-party teardown plus OpenAI's help
   center — `openai.com/index/building-chatgpt-atlas/` returned **HTTP 403** to the fetcher, so the
   StoragePartition claim rests on <https://blog.bytebytego.com/p/the-architecture-behind-atlas-openais>
   rather than the primary. Gemini/Auto Browse and Copilot Mode rest on press, not vendor engineering
   docs.
