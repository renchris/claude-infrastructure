# Dia 1.48 automation surfaces — sanctioned + documented map

Measured 2026-09-14 against Dia **1.48.0 build 86796** (`company.thebrowser.dia`), read-only.
No connection was made to 127.0.0.1:9222 or to any agent-server port.

**Headline: the highest-value surface is not CDP. Dia ships a first-party AppleScript
dictionary with an `execute javascript` command, which drives tabs with no debugging port,
no consent dialog, and no extension.** It is gated by one pref that is currently OFF.

**Two corrections to the lead's context, both measured:**

| Lead's context | Measured | Evidence |
|---|---|---|
| "Chromium ~150" | **153.0.8010.37** | `strings -a` ArcCore → `Chrome/153.0.8010.37`; corroborated by changelog 1.42.0 "Chromium M151" (Jul 29) → M153 by Sep is the normal cadence |
| "`/json/*` 404" implied absent | handlers are **compiled in** (`/json/list`, `/json/version`, `/devtools/page/` all present in ArcCore strings) — the 404 is a deliberate gate, not missing code | see § Remote debugging |

Instrument note: macOS `strings` without `-a` read only loaded sections (5 MB of a 128 MB
binary). All string claims below use `strings -a`, validated with a positive control (the
legacy `You must run Arc with --remote-debugging-port=<number>` string, found) and a
negative control (a nonsense token, 0 hits in all four dumps).

---

## Surface 1 — AppleScript / Apple Events (first-party, sanctioned, port-free)

Declared in the bundle, so this is a supported product surface, not a leftover.

- `NSAppleScriptEnabled = 1` — `/Applications/Dia.app/Contents/Info.plist:143`
- `OSAScriptingDefinition = Dia.sdef` — `/Applications/Dia.app/Contents/Info.plist:179`
- Dictionary: `/Applications/Dia.app/Contents/Resources/Dia.sdef` (9,175 bytes), suite
  `Dia Suite` code `DiaS`, described in its own words as **"Automation support for Dia."**

What the dictionary exposes:

| Capability | sdef location | Notes |
|---|---|---|
| `execute <tab> javascript "<code>"` → text | `Dia.sdef:167`, wired at `:135` | Command code `CrSuExJa` — the **same four-char code Chrome/Safari use**, i.e. inherited Chromium Suite semantics. Returns the JS result as text. |
| Navigate a tab | `Dia.sdef:114` — `URL` property, `access="rw"` | Set the property to navigate; no CDP needed |
| Enumerate/open/close tabs | `Dia.sdef:56`, `:148` — `tabs` element `access="rw"`; `close` at `:90`, `make` at `:76` | Per window and per profile |
| `focus` a tab or profile | `Dia.sdef:156` | Brings window forward |
| `move` tab between profiles | `Dia.sdef:160` | Without changing focus |
| Read tab state | `Dia.sdef:106-134` | `id`, `title`, `URL`, `loading`, `isPinned`, `isFocused` |
| Profiles as first-class objects | `Dia.sdef:140` | "A Dia profile (a space of tabs)" — matches the CDP `browserContextId` space-scoping the `dia-agent` skill documents |
| `start trace` / `stop trace` (Perfetto) | `Dia.sdef:175`, `:181` | Explicitly **"non-production builds only"** — will not work on this Release build |

🚨 **The one gate, and it is currently CLOSED.** Dia carries Chrome's Apple-Events JS
guard. Three strings in the binaries:

- `browser.allow_javascript_apple_events` (the pref key)
- `isJavaScriptFromAppleEventsAllowed`, `toggleJavaScriptFromAppleEventsAllowed`
- `developerMenu`, `developerMenuItem`, `setDeveloperMenuItem:` — a native NSMenuItem
  Developer menu, i.e. the same View ▸ Developer placement Chrome uses

Measured state: the key is **absent from every prefs file** —
`grep -l allow_javascript_apple_events` over `User Data/Local State`, every
`*/Preferences` and every `*/Secure Preferences` returns nothing, and `Local State` has
**no `browser` dict at all**. Chromium's default for that pref is false, so
`execute … javascript` will fail today until the Developer-menu item is toggled once.
Everything else in the table above (enumerate, navigate by URL, open, close, focus, move)
needs no such gate.

Second gate, unavoidable and standard: the first `osascript` targeting Dia raises the
macOS TCC "wants to control Dia" prompt (Automation permission), once per client app.

---

## Surface 2 — Remote debugging / CDP

- **Live right now**: `Dia` PID 1902 holds `TCP 127.0.0.1:9222 (LISTEN)` (`lsof -nP -a -p 1902 -i`).
- **The toggle is PERSISTED, not per-session** —
  `~/Library/Application Support/Dia/User Data/Local State` →
  `{"devtools":{"remote_debugging":{"user-enabled":true}}}`. So `dia://inspect#remote-debugging`
  writes a pref and survives restart. This matters for the `dia-agent` skill's security
  lifecycle ("UNCHECK the toggle when done") — unchecking is a real state change, and
  leaving it checked persists the listener across reboots.
- Canonical URL in the binary is **`chrome://inspect#remote-debugging`**; `dia://inspect`
  is an alias. The literal `dia://` strings present are only user-facing pages
  (`dia://settings`, `dia://extensions`, `dia://history`, `dia://bookmarks`,
  `dia://downloads`, `dia://memory-settings`, `dia://assistant/`, `dia://payment-history`,
  `dia://cancel-downgrade`). Since `dia://inspect` works (lead-verified) but appears in no
  string, `dia://` is a generic scheme rewrite — **inference**, which implies
  `dia://flags`, `dia://policy` and `dia://version` should also resolve. Untested.
- Toggle plumbing: `set-remote-debugging-enabled`, `SetRemoteDebuggingEnabled`,
  `updateRemoteDebuggingEnabled`, prefs `devtools.remote_debugging.user-enabled` **and
  `devtools.remote_debugging.allowed`** (the second is the policy-controlled one).
- Consent dialog is a real Swift class: `ArcDevToolsConnectionDialog`,
  `initWithDevToolsConnectionDialog:`, user-facing string **"Allow debugging connection?"**,
  with a three-state result type `DevToolsConnectionDialog{"accepted","denied","disabled"}`
  and a feature key `kDevToolsAcceptDebuggingConnections`. **No "remember this choice" or
  always-allow string exists** — consistent with the per-connection prompt the lead saw.
- TBC instruments this deliberately: UMA histograms `DevTools.RemoteDebugging.ConnectionPermission`
  and `DevTools.RemoteDebugging.ServerAction`. A measured feature, not an accident.
- WS-only behaviour: `DevTools listening on ws://%s%s`, `ws://%s:%i`, and
  `Cannot start http server for devtools.` coexist with `/json/list`, `/json/version`,
  `/devtools/page/`. The HTTP endpoints exist in code and are gated off — so treat the 404
  as policy that could change per build, not as an architectural guarantee.
- `remote-debugging-pipe` is present — **CDP over fd 3/4, no TCP port at all**. Untested
  here (needs a flag launch) but it is the port-free CDP transport if flags ever become
  viable.
- Switch strings present: `remote-debugging-port`, `remote-debugging-pipe`,
  `remote-allow-origins`, `remote-debugging-targets`, `enable-automation`, `headless`,
  `user-data-dir`, `no-first-run`, `load-extension`, `disable-extensions-except`,
  `silent-debugger-extension-api`, `allow-internal-debugging-urls`, `disable-blink-features`.

---

## Surface 3 — Extensions (Web Store yes; developer mode present but never enabled)

Measured from `User Data/*/Secure Preferences` (extension state lives there, not in
`Preferences` — `extensions.settings` in `Preferences` is empty, which would read as "no
extensions" if you looked in the obvious place).

- **Chrome Web Store installs work and are in use.** Three `location=1 from_webstore=true`
  entries in the `Default` profile: uBlock Origin Lite (`ddkjiahejlhfcafbddmgiahcphecmpfh`),
  GoFullPage (`fdpohaocaechififmbbbbbknoalclacl`), "Take Webpage Screenshots Entirely"
  (`mcbpblocgmgfnpjjppndjkmgjaogfceg`). Update URL `https://clients2.google.com/service/update2/crx`
  and `chromewebstore.google.com/` are both present.
- **All installed extensions are MV3**; only Dia's own component extensions are MV2
  (Chromium PDF Viewer, Google Hangouts). `isAffectedByMV2Deprecation` and
  `unsupportedManifestVersion` plumbing present, plus a switch
  `allow-legacy-extension-manifests`.
- Dia's own UI ships as `location=5` (COMPONENT) extensions: **`Dia chat`**
  (`cnmkapobonpnoi…`), **`Dia Internal Extension`** (`ldciclpbkaobfb…`), **`Dia Home Surface
  internal extension`** (`odeipjeilffnjb…`) — present in all four profiles.
- **`developer_mode` is unset (`None`) in all four profiles** (`Default`, `Profile 13/15/17`)
  — developer mode has never been turned on here.
- Full `developerPrivate` API is compiled in, including `loadUnpacked`, `loadDirectory`,
  `packDirectory`, `choosePath`, and a `ProfileInfo` carrying
  **`canLoadUnpacked` / `inDeveloperMode` / `isDeveloperModeControlledByPolicy`**. So
  `dia://extensions` has the standard toggle + "Load unpacked", and developer mode is
  policy-controllable.
- Guard strings that would bite: `Must be in developer mode to load unpacked extensions.`,
  `When enabled, disable unpacked extensions if developer mode is off.` (the upstream
  feature that disables unpacked extensions when the toggle flips off).
- 🚨 **`chrome.debugger` is fully present** — the whole API schema
  (`attach`, `detach`, `sendCommand`, `getTargets`, `onEvent`, `onDetach`, `Debuggee`,
  `DebuggerSession`) plus `permission:debugger` and `silent-debugger-extension-api`. **An
  unpacked extension with the `debugger` permission drives CDP with no port, no 9222 and no
  per-connection consent dialog.** This is the mechanism Claude in Chrome / Browser MCP use,
  and it explains why those worked in Dia previously.
- `nativeMessaging` is present and one installed extension already holds the permission
  (`mcbpblocgmgfnpjjppndjkmgjaogfceg`). Host manifest dirs found are **Chromium's and
  Chrome's only** — `/Library/Application Support/Chromium/NativeMessagingHosts` and
  `/Library/Google/Chrome/NativeMessagingHosts`. **No Dia-specific NativeMessagingHosts path
  string was found**, so which directory Dia actually reads is unresolved (see Unknowns).
- No extension allowlist restriction observed beyond upstream policy names
  (`ExtensionAllowlist`, `ExtensionInstallForcelist`, `NativeMessagingAllowlist/Blocklist`).

---

## Surface 4 — First-party agent runtime: Dia runs Claude Code locally

This is the largest undocumented finding, and it answers question (e).

- `/Applications/Dia.app/Contents/Resources/agent-server-resources/dist/info.json`:
  ```json
  {"name":"agent-server","version":"1.0.0","platform":"darwin","arch":"arm64",
   "buildDate":"2026-09-09T22:31:00Z","commitHash":"96feaff909b",
   "claudeCodeVersion":"2.1.250 (Claude Code)"}
  ```
  `commitHash` matches `Info.plist` `BCNYCommitInfo Release-86796-96feaff909b3…`.
- `dist/claude` is a **206 MB executable** — a bundled Claude Code. `dist/agent-server`
  (69 MB, Mach-O arm64, Bun-compiled) is the host. `dist/handler` (69 MB).
- **Three live processes right now**, one per profile:
  `dist/agent-server --app-name Dia --data-dir "…/User Data/Profile 13/AgentServer" --agents-dir …/dist/agents`
  (PIDs 861 / 877 / 1593 for Profiles 13 / 15 / 17).
- Each listens on **two** endpoints (`lsof`, read-only):
  - an ephemeral localhost TCP port — 61619 / 61631 / 61687 (the lead's ":54271" was this,
    at an earlier ephemeral draw; it is not a fixed port)
  - a unix socket `/tmp/dia-agent.server.<Profile N>.<8-hex>.sock`
- 🔒 **The unix socket is not reachable by path**: `lsof` reports the name but `ls /tmp` and
  `ls /private/tmp` show no such directory entry — consistent with bind-then-unlink. New
  clients cannot connect by path.
- Auth exists on the TCP side: `getHostAuthToken`, `getOAuthToken`,
  `abortHandshake(response, 401)` in the WebSocket upgrade path. Whether an unauthenticated
  local client is refused was **not tested** (see Blockers).
- The protocol is the **Claude Agent SDK control protocol**, not generic MCP:
  `subtype:"initialize"`, `tools/list`, `tools/call`, `notifications/tools/list_changed`,
  and an init payload carrying `sdkMcpServers`, `sdkMcpServerConfigs`, `hooks`, `agents`,
  `skills`, `systemPrompt`, `appendSubagentSystemPrompt`, `planModeInstructions`,
  `toolAliases`, `perTaskStopAffordance`.
- Tools the bundled runtime registers: `betaBashTool`, `betaEditTool`, `betaReadTool`,
  `betaWriteTool`, `betaGlobTool`, `betaGrepTool`, `BashSession`,
  `betaAgentToolset20260401`, plus `setupSkills` / `extractSkillArchive` /
  `resolveSkillVersion`. Host feature flags gate them:
  **`agent-server-bash-tool-enabled`**, `agent-server-powershell-tool-enabled`.
- Sandbox profiles ship beside it: `dist/agent.sb` (7,813 B) and
  **`dist/agent-claude-code.sb`** (9,066 B) — seatbelt profiles, so the bundled Claude Code
  is sandboxed rather than free-running.
- `dist/agents/` holds 40+ named agents (`home-task-execution`, `task-workspace`,
  `external-person-research`, `desk-intake`, `mission-suggest`,
  `task-list-proactive-opus`, `unit-home`, …) and `dist/prompts/`.
- **Direction of MCP is client-only.** 67 `McpServer` occurrences but **no**
  `StdioServerTransport` / `SSEServerTransport` / `StreamableHTTPServerTransport` strings —
  i.e. in-process SDK-MCP servers (`sdkMcpServers`), plus a real MCP *client* stack in the
  Swift layer (`MCPServerRegistry.swift`, `MCPServerRegistryController.swift`,
  `MCPAuth/MCPServerAuthController.swift`, `AppProviderMCPServer`, `_connectMCPServer`,
  UI string *"Connect to this app's MCP server to use more advanced tools and actions"*).
  **Dia consumes MCP; it does not advertise a third-party-connectable MCP endpoint.**

### The cached tool schemas (read-only summary)

`~/Library/Application Support/Dia/AgentServer/tool-schemas/` — written by
`AgentServer.ToolSchemaCacheManager`, keyed by etag in `.tools_cache_manifest`
(`servicesEnvironment: production`).

- `dia.json` — `mcp_version 2025-11-25`, `server_name dia`, `vendor dia`, `updated_at 2026-09-09`,
  **59 tools**. Browser-control subset: **`read_tabs`** (metadata + full text for content
  panes; pane types `webContent` / `assistantChat` / `newTabPage`), **`open_tabs`** (array of
  URLs), **`close_tabs`** (by content-pane ID), `upload_artifact` (opens a local
  `index.html` in a tab). Memory subset: `memory_query`, `memory_search` (full-text over raw
  browsing history and conversation content, filterable by domain and date window).
  Remaining ~50 are connector reads: Slack, Teams, Outlook, Gmail, Google Drive/Calendar,
  Notion, Figma, Canva, Salesforce, SharePoint, Linear, GitHub, Atlassian, LinkedIn,
  `search_web`, `fetch_web_content`, `get_current_focus`, `lookup_person`.
- Per-vendor caches: `notion.json` (392 KB), `zoom.json`, `atlassian.json`,
  `amplitude.json`, `granola.json`, `salesforce.json`.
- ⚠️ These are the schemas Dia's **own** agent consumes. `read_tabs`/`open_tabs`/`close_tabs`
  are served by the Dia host back to its agent — they are not an API a third party is
  offered. The sanctioned way to extend that agent is to register an MCP server, not to
  drive it.

### Skills

- Per profile: `custom_skills_database.db` + `skills_history_database.db` (+ `-wal`, `-shm`).
- 🔒 **Encrypted.** Header bytes `8828 d2fc 64b9 b4ce …`, `file` says `data`, `sqlite3` says
  `file is not a database` — while Chromium's own `History` in the same profile starts
  `SQLite format 3`. (GRDB.framework is bundled, so likely SQLCipher.) **Skills cannot be
  read or authored on disk by a third party.**
- Skills are a GUI-authored step pipeline: `SkillBuilder.CanvasView`, `AddStepView`,
  `LLMStepView`, `SkillsV3PreferencePane*`, `_createOrUpdateSkill`, `_getAutoFireSkill`,
  `_preinstalledSkill`, `_presentSkillsHub`. Changelog: "Natural Language Skill Builder"
  (1.2.0), "Skills without slashes" (0.48.0).
- Also present: `_presentAgentServerDashboardWindow`, `_exportAgentServerLogs` — an internal
  debug UI, and `company.thebrowser.dia.home-bridge.ws`, an unexplored WebSocket bridge name.

---

## Surface 5 — Command-line switches and flag persistence

- The running Dia was launched **with no flags** (`ps -p 1902 -o command=` is the bare
  bundle path), matching the Dock launch.
- **Flags do not persist today.** `Local State` has **no `browser` key**, therefore no
  `browser.enabled_labs_experiments`; the string `enabled_labs_experiments` appears nowhere
  in `Local State`. So nothing is pinned via `dia://flags`, and the mechanism is untested
  here.
- `chrome://flags` machinery is present (`chrome://flags/#…` strings), so `dia://flags`
  should resolve via the scheme rewrite (inference).
- Whether `--remote-debugging-port` is still honoured on 1.48 is **unresolved**. Evidence
  cuts both ways: the switch string is present, and a community project documents it working
  — but the string may be legacy (the neighbouring `You must run Arc with
  --remote-debugging-port=<number>` is Arc-era), and TBC clearly moved to the `dia://inspect`
  toggle + fixed 9222 + consent dialog. Deciding it requires quitting Dia and relaunching
  with flags, which the read-only boundary forbids.

---

## Surface 6 — Enterprise policy / managed preferences

Documented, and this is the clearest first-party statement TBC makes about control surfaces:

- <https://www.diabrowser.com/forwork> — verbatim: *"Dia supports standard Chromium
  enterprise policies, including Google Chrome Cloud Management, and also provides
  Dia-specific MDM policies such as AI controls and managed updates."* Also *"You can also
  use Dia's MDM policies to restrict sign-ins to approved email domains"*, and MDM controls
  to *"disable all AI-powered features on specific websites."* Links out to
  <https://chromeenterprise.google/policies/> and
  <https://chromeenterprise.google/products/chrome-enterprise-core/>, plus
  <https://trust.diabrowser.com/>.
- <https://www.diabrowser.com/security> repeats *"Dia supports standard Chromium enterprise
  policies"*; adds *"your conversations, history, bookmarks, and files are encrypted and
  stored locally on your device"* (corroborating the encrypted Skills DB) and, on agent
  actions, *"the assistant only sees what you saw and approved."*

Binary evidence the policy stack is real and the relevant policies exist:

- Policy names present: **`RemoteDebuggingAllowed`**, `DeveloperToolsAvailability`,
  `DeveloperToolsAvailabilityAllowlist/Blocklist`, `DeveloperToolsDisabled`,
  `ExtensionInstallCloudPolicyChecksEnabled`, `ExtensionAllowlist`,
  `NativeMessagingAllowlist/Blocklist/UserLevelHosts`, `CloudPolicyOverridesPlatformPolicy`.
- Pref `devtools.remote_debugging.allowed` sits beside the user toggle — so
  `RemoteDebuggingAllowed` is the policy that can force the toggle off.
- Machinery: `components/policy/core/common/async_policy_loader.cc`, `chrome://policy`,
  `Enterprise.PolicyServiceInitTime`, `MachineLevelUserCloudPolicy*`,
  `ExtensionInstallPolicyService`.
- The mac management path **ran**: `Local State` → `{"management":{"platform":{"enterprise_mdm_mac":0}}}`
  and `{"policy":{"last_statistics_update":…}}`. A written value proves the code executed and
  found no MDM enrollment.

Current state on this machine: **no policy is applied.** `/Library/Managed Preferences/`
contains no `company.thebrowser.dia.plist` (and no per-user subdirectory at all);
`/Library/Preferences/company.thebrowser.dia.plist` absent; `defaults read
company.thebrowser.dia` returns only window frames and app chrome — no policy keys.

⚠️ **Honest limit:** I did **not** find a `policy_loader_mac.cc` / `PolicyLoaderMac` string,
so I cannot assert from the binary that Dia reads `company.thebrowser.dia` managed prefs
specifically. That absence is weak evidence — Chromium file-path strings only appear where
`__FILE__` is used (DCHECK/log sites) — so it is *not* a refutation. The claim rests on
TBC's own documentation plus the live-written `enterprise_mdm_mac` key. **The cheap
falsifier: open `dia://policy` (or `chrome://policy`) and read what it enumerates** — it
names the loaded sources directly, costs nothing, and settles it.

---

## Changelog: version → remote-debugging-relevant change (1.37 → 1.48)

Source <https://www.diabrowser.com/changelog>; individual notes at `/changelog/mac/{1-48-0}`.

| Version | Date | Title | Remote-debugging-relevant content |
|---|---|---|---|
| 1.48.0 | 2026-09-09 | Microsoft Tools in Chat, Slack Voice Transcripts | none |
| 1.47.2 | — | (appcast only) | none |
| 1.47.1 | 2026-09-02 | Outlook Live Calendar, Tool Requests | none |
| 1.46.0 | 2026-08-26 | Release Notes Postcard, Slack Improvements | **"Upgrades to Dia's Agent systems"** — closest touch; unspecified |
| 1.45.1 | 2026-08-19 | Cast Content, Zoom Integration | none |
| 1.44.0 | 2026-08-12 | Stability and Performance | none |
| 1.43.1 | 2026-08-05 | Swipeable Profiles, Bundle Size Reduction | none |
| 1.42.0 | 2026-07-29 | **Chromium M151**, Thinking UI Redesign | Chromium base bump (CDP surface moves with it) |
| 1.41.0 | 2026-07-22 | Custom Search Labels, Tool Suggestions | none |
| 1.40.0 | 2026-07-15 | Back/Forward Cache, Memory Optimization | none |
| 1.39.0 | 2026-07-08 | Sidebar Navigation, Settings Redesign | none |
| 1.38.0 | 2026-07-01 | Tab Page Auto-Clear, Workspace Selection | none |
| 1.37.0 | 2026-06-24 | Release Notes Window, Google Account Switching | none |

**Verdict on question (a): TBC has never documented any of it.** Across all 12 entries,
the help/security/forwork pages, and the Sparkle appcast, there is **zero** mention of
remote debugging, `dia://inspect`, port 9222, the consent dialog, or "agent access". The
ephemeral→fixed-9222 port change and the `ArcDevToolsConnectionDialog` are **undocumented
product changes**; their version boundary cannot be dated from public sources.

Relevant older entries found while enumerating: **1.29.0 "Synced Browser Extensions"**
(pinned order + enabled/disabled state sync) and **1.10.1 "Chromium Side Panel support"** —
extensions are a first-class, maintained feature, not tolerated legacy.

⚠️ **The appcast cannot answer changelog questions.** `SUFeedURL`
(`Info.plist:185` → <https://releases.diabrowser.com/BoostBrowser-updates.xml>) is a
**rolling 4-entry window** — today 1.48.0, 1.47.2, 1.47.1, 1.46.0 only. Use the website
changelog for history; the appcast is for update-checking and 1.47.2 appears *only* there
(it has no website entry).

---

## TBC's stance and community tooling (question f)

- **No prohibition on automation or scripting is published** on the security or forwork
  pages. The opposite, implicitly: shipping `Dia.sdef` with a suite literally described as
  "Automation support for Dia" is an affirmative sanction of AppleScript control. No ToS
  clause on scripting was located (not exhaustively searched — see Unknowns).
- **`github.com/eladrave/dia-browser-control`** — CDP-on-9222 Claude control for Dia.
  Requires quitting Dia and relaunching:
  `/Applications/Dia.app/Contents/MacOS/Dia --remote-debugging-port=9222`, then
  `curl http://localhost:9222/json`. **Stale on three counts**: targets "Dia 0.38.0 or
  later" (pre-1.0 numbering), knows nothing of `dia://inspect` or the consent dialog, and
  relies on `/json` which now 404s. Its flag-launch premise is exactly what the current
  toggle replaced. macOS arm64 + Node ≥16.
- **`github.com/aeonfun/opendia`** — "Connect your browser to AI models. Just use Dia on
  Chrome, Arc or Firefox": an **extension**-based MCP bridge, not CDP. Confirms the
  extension route (Surface 3) is the one the community actually ships for Dia.
- No Dia-specific AppleScript tooling found. The nearest validated analog is
  **`github.com/dominion525/familiar`** — "Control your real macOS Chrome via AppleScript —
  no DevTools Protocol, no Playwright", a Claude Code skill. Its whole thesis is Surface 1,
  and Dia's `execute`/`URL`/`tabs` vocabulary is Chrome's, so the pattern ports.
- `github.com/pasky/chrome-cdp-skill`, `achiya-automation/safari-mcp` (97 AppleScript
  tools), `kazuph/mcp-browser-tabs` — adjacent prior art, not Dia-specific.

---

## Adversarial pass — what I nearly got wrong

Three gaps I went back and closed with real tool calls, each of which changed a conclusion:

1. **I almost reported the AppleScript surface as free.** It is gated by
   `browser.allow_javascript_apple_events`, and I only found it by asking specifically
   whether Dia inherited Chrome's Apple-Events guard. Checking the pref then *explained* an
   earlier anomaly — `Local State` having no `browser` dict — so two observations
   reconciled. Reporting `execute javascript` as ready-to-use would have sent the lead into
   a silent failure.
2. **I almost reported `/json/*` as architecturally absent.** The handler strings are
   compiled in. That reframes the 404 as a per-build gate rather than a guarantee.
3. **I almost asserted "no mac policy loader".** The missing `PolicyLoaderMac` string is a
   blind-instrument null (Chromium only emits `__FILE__` at DCHECK sites). I downgraded it
   to unknown and named the one-command falsifier (`dia://policy`).

Two further hostile questions I raised and answered: *"is the agent-server's unix socket a
back door?"* — no, it is unlinked after bind, unreachable by path. *"Are the 59 tool schemas
an API for us?"* — no, they are the schemas Dia's own agent consumes; the direction of MCP
is client-only, so the sanctioned extension point is registering an MCP server.

**Alternatives considered and ruled out**

| Option | Ruled out because |
|---|---|
| Connect to 127.0.0.1:9222 to enumerate targets | Brief boundary forbids it. Lead already verified WS-only + 404 + consent dialog. |
| Connect to the agent-server TCP port (61619/…) to probe auth | Live agent runtime on the operator's own account — a probe could spawn work or spend his Dia quota. Not read-only in effect. Named as a blocker instead. |
| Launch Dia with `--remote-debugging-port` to test switch handling | Requires quitting the operator's running browser with 4 live profiles. Violates "leave Dia unchanged". |
| `sqlite3` the Skills DBs in place | WAL-mode open can write `-shm`. Copied to scratchpad first; source untouched. (Turned out encrypted anyway.) |
| Enable developer mode / toggle the Apple-Events pref to verify | Both are state changes to the operator's profile. Reported as gates, not tested. |
| Read Dia's cookies/credentials to reach the cloud agent API | Out of scope by policy; no credential material was read. |

---

## Unknown / not documented

**Not documented by TBC anywhere (undocumented product behaviour):**
1. Remote debugging in any form — `dia://inspect`, 9222, the consent dialog, "agent access".
2. The ephemeral→fixed-9222 port change: which version shipped it. Undatable publicly.
3. `ArcDevToolsConnectionDialog` and its accepted/denied/**disabled** third state — what
   puts it in `disabled`, and whether that is policy or a hidden pref.
4. That Dia bundles **Claude Code 2.1.250** and runs a per-profile agent-server with
   Bash/Edit/Write tools. Nowhere in the changelog or security page.
5. Which Dia-specific MDM policy **keys** exist. `forwork` asserts they exist but publishes
   no key list, no plist example, no MDM guide, no `policy_templates` download.
6. Whether `dia://extensions` renders the developer-mode toggle in Dia's own chrome (the
   API supports it; the UI was not opened).

**Unresolved by measurement (needs an action the boundary forbids):**
7. Does 1.48 still honour `--remote-debugging-port` / `--remote-debugging-pipe`, and is
   there a switch filter? Strings present, behaviour untested.
8. Does the agent-server's ephemeral TCP port refuse an unauthenticated local client? Auth
   plumbing exists (`401` on WS upgrade); not probed.
9. Does Dia read `/Library/Managed Preferences/company.thebrowser.dia.plist`? Documented
   claim + `enterprise_mdm_mac` written, but no direct binary proof.
   **Falsifier: open `dia://policy`.**
10. Which `NativeMessagingHosts` directory Dia reads — only Chromium's and Chrome's paths
    appear in strings; no Dia-specific path found.
11. Whether `dia://flags` / `dia://policy` / `dia://version` resolve (scheme-rewrite
    inference, untested), and whether lab flags persist into a Dock launch.
12. What `company.thebrowser.dia.home-bridge.ws` is.
13. TBC's ToS/AUP text on automation — the security and forwork pages are silent; the legal
    terms were not retrieved.

---

## Bottom line for a local Claude Code driving Dia's tabs

Ranked by cost, with the port-free options first:

1. **AppleScript via `osascript`** — first-party, sanctioned, survives restarts, no port, no
   consent dialog, no extension. Gives tab enumeration + read (`title`/`URL`/`loading`),
   navigation (set `URL`), open/close/focus/move, and profile awareness **immediately**.
   Full JS execution needs one one-time Developer-menu toggle
   (`browser.allow_javascript_apple_events`, currently off) plus the one-time macOS
   Automation grant. **This is the surface the existing `dia-agent` skill does not use and
   probably should.**
2. **Unpacked extension with the `debugger` permission** — full CDP, no port, no
   per-connection dialog. Costs: enabling developer mode (a persistent profile change that
   also risks the "disable unpacked extensions if developer mode is off" behaviour) and
   maintaining an extension.
3. **CDP on 9222 via `dia://inspect`** — what the `dia-agent` skill documents today. Works,
   but: WS-only (no `/json` discovery), a native consent dialog per connection, and the
   toggle is a *persisted* pref, so "uncheck when done" is load-bearing rather than
   cosmetic.
4. **Dia's own agent / Skills / tool schemas** — not a third-party API. Dia is an MCP
   *client*; the schemas are what its agent consumes; Skills are encrypted on disk. The only
   sanctioned extension point is registering an MCP server for Dia's agent to call — which
   inverts control (Dia drives you), so it does not satisfy "Claude Code drives tabs".
