# Chromium chrome://inspect#remote-debugging consent: mechanism, and whether it can be skipped

Sources fetched 2026-09-14 from `chromium.googlesource.com/chromium/src/+/main/<path>?format=TEXT`.
**All `file:line` citations are against `main` as of that date** — re-derive before quoting in code.
Gitiles `+log` pages are 403 (sign-in required); history came from the Gerrit changes API instead.

---

## VERDICT (answer first)

1. **There is no consent-skipping or consent-remembering mechanism in upstream Chromium.** Not a pref, not
   an enterprise policy, not a feature param, not a `chrome://flags` entry, not a token in the WS path, not
   a trusted-client exemption. The prior session's conclusion **survives falsification on this axis**.
2. **But its framing was wrong in one load-bearing way.** The M136 "default user-data-dir" refusal that
   makes `--remote-debugging-port` unusable on the real profile is **compile-time gated on
   `BUILDFLAG(GOOGLE_CHROME_BRANDING)`** and is **inert on Chromium-branded builds** — which Dia almost
   certainly is. If so, `--remote-debugging-port` / `--remote-debugging-pipe` work on Dia's **default**
   profile, in `kDefault` mode, with **full `/json/*` discovery and no dialog at all**. That is a
   prompt-free route to the warm profile the prior conclusion says does not exist. INFERRED, not cited —
   one relaunch settles it (§7).
3. **The cheap, certain win regardless:** the dialog is per-**WebSocket-upgrade**, and one approved
   `/devtools/browser` socket is a full-privilege browser session. Approve once, hold the socket, drive
   everything through `Target.attachToTarget {flatten:true}`. This is the Chrome team's own
   recommendation, verbatim.

---

## trigger → hook → persistence

| # | Trigger | Hook / code path | Persistence |
|---|---|---|---|
| T1 | Browser launch, `devtools.remote_debugging.user-enabled` already `true` | `RemoteDebuggingServer::GetInstance` → `StartHttpServerInApprovalModeIfEnabled` → `MaybeStartOrStopServerForPrefChange` → `StartHttpServer(..., kWithApprovalOnly)` (`remote_debugging_server.cc:399-417, 216-226, 251-283, 228-249`) | **Pref persists** in Local State (`devtools.remote_debugging.user-enabled`, `chrome/common/pref_names.h:1778-1779`; app-wide, not per-profile). Port persists via `DevToolsActivePort` line 1, else 9222 (`remote_debugging_server.cc:194-214`, `rds.h:26`) |
| T2 | Toggle flipped at runtime on `chrome://inspect#remote-debugging` | `InspectMessageHandler::HandleSetRemoteDebuggingEnabled` → `InspectUI::SetRemoteDebuggingEnabled` → `local_state->SetBoolean(kDevToolsRemoteDebuggingEnabled, …)` (`chrome/browser/ui/webui/inspect/inspect_ui.cc:475-480, 692-712`); a `PrefChangeRegistrar` starts/stops the server live | Same pref. Server start/stop is immediate, no restart |
| T3 | **Each WebSocket upgrade** to a path starting `/devtools/browser` | `ServerWrapper::OnWebSocketRequest` (host check, `devtools_http_handler.cc:514-526`) → `DevToolsHttpHandler::OnWebSocketRequest` (`:812-873`) → origin check (`:817-831`) → `delegate_->AcceptDebugging(cb)` (`:836-841`) → `ChromeDevToolsManagerDelegate::AcceptDebugging` (`chrome_devtools_manager_delegate.cc:529-549`) → `DevToolsConnectionDialog::Show` (`devtools_connection_dialog.cc:26-30`) | **NONE.** Self-destructing dialog, `RunCallbackAndDie` + `delete this` (`devtools_connection_dialog.cc:107-120`). No pref read, no pref write, no "remember" checkbox, no cache in the delegate |
| T4 | WS upgrade to any **other** path (incl. `/devtools/page/<id>`) in approval mode | `devtools_http_handler.cc:842-843` | `403 "Connection rejected"`, **no dialog**. Per-target attach is structurally impossible in this mode |
| T5 | Any `GET /json*` | `ServerWrapper::OnHttpRequest:470` → `DevToolsHttpHandler::OnJsonRequest:584-590` → unconditional `Send404` when `mode_ == kWithApprovalOnly` | n/a — hard mode compare, no switch/pref/feature escape |
| T6 | `GET /` (discovery page) | `OnDiscoveryPageRequest:759-764` → `Send404` | n/a |
| T7 | `GET /devtools/<frontend resource>` | `OnFrontendResourceRequest:776-782` → `Send404`; approval mode also passes an **empty** `debug_frontend_dir` ("We do not support hosting DevTools in this mode", `remote_debugging_server.cc:241-246`) | n/a |
| T8 | Approval returns `kAllow` | `HandleDebuggingApproval:792-810` → `DevToolsAgentHost::CreateForBrowser` + `AcceptWebSocket` | **The socket persists.** One prompt buys a full browser-target session for the socket's lifetime |
| T9 | Active-connection count changes | `delegate_->SetActiveWebSocketConnections(n)` from `AcceptWebSocket:1018-1031`, `OnClose:892-899`, `~DevToolsHttpHandler:404-417` → Chrome shows/hides a `GlobalConfirmInfoBar` (`chrome_devtools_manager_delegate.cc:551-564`) | Infobar lives while count > 0; purely advisory |
| T10 | `--remote-debugging-port` / `--remote-debugging-pipe` present | `GetInstance:353-395` → `IsRemoteDebuggingAllowed` → `StartHttpServer(..., kDefault)` / `StartPipeHandler` | **`kDefault` = no approval ever, full `/json/*`.** Takes precedence: approval mode is skipped (`:397-400`) |
| T11 | Policy `RemoteDebuggingAllowed=false` set at runtime | `BrowserProcessImpl::OnDevToolsRemoteDebuggingAllowedChanged` (`browser_process_impl.cc:1120-1137`) → `ClearPref(kDevToolsRemoteDebuggingEnabled)` + `StopServer()` | **Clears** the user pref — an explicit re-enable is then required |

---

## (a) Which path, and exactly what triggers the consent

- **Server owner**: `RemoteDebuggingServer` (`chrome/browser/devtools/remote_debugging_server.{h,cc}`), constructed once from
  `BrowserProcessImpl::CreateDevToolsProtocolHandler` (`chrome/browser/browser_process_impl.cc:1087-1117`).
  It delegates to the content layer: `content::DevToolsAgentHost::StartRemoteDebuggingServer(factory, output_dir, debug_frontend_dir, mode)`
  (`remote_debugging_server.cc:311-318`; enum at `content/public/browser/devtools_agent_host.h:46-56`).
  The HTTP/WS server itself is stock `content::DevToolsHttpHandler` in **both** modes — the only difference is `mode_`.
- **Trigger granularity: each WebSocket upgrade.** Not the first message, not per client identity, not per endpoint
  type beyond the browser/page split. CL 7123788's own words: *"each new WebSocket connection needs to be approved.
  In this mode, the server only accepts WebSocket connections and does not respond to HTTP endpoints."*
  (<https://chromium-review.googlesource.com/c/chromium/src/+/7123788>, submitted 2025-11-19, `refs/heads/main@{#1547150}`)
- **Only `/devtools/browser*` is eligible.** `devtools_http_handler.cc:834-844`. Two consequences:
  - `/devtools/page/<targetId>` gets `403 Connection rejected` with **no dialog** — so page-scoped clients cannot work.
  - The UUID is **not checked**: the code comment is literally *"If we require user approval, we do not require guid."*
    Any path with the `/devtools/browser` prefix prompts. (`browser_guid_` is still generated and written to
    `DevToolsActivePort` line 2 — `:901-913`, `:298-308` — it is just not a gate.)
- **Embedder hook** = `virtual void content::DevToolsManagerDelegate::AcceptDebugging(AcceptCallback)`
  (`content/public/browser/devtools_manager_delegate.h:181-188`), with
  `enum class AcceptConnectionResult { kDeny, kAllow }` (`:43-51`). Companion advisory hook
  `virtual void SetActiveWebSocketConnections(size_t)` (`:186-188`).
  **The base implementation denies**: `devtools_manager_delegate.cc:131-134` runs the callback with `kDeny`.
  `ChromeDevToolsManagerDelegate` is the **only** override in the tree — I checked headless, content_shell,
  android_webview and chromecast delegates: 0 hits for `AcceptDebugging` in each. So an embedder that starts
  approval mode without overriding it rejects everything; **Dia must have overridden it, and did** (§6).
- **Chrome's dialog carries no state**: three buttons — Allow (`kAllow`), Cancel (`kDeny`), and an extra
  **Disable** button that navigates to `chrome://inspect#remote-debugging` and denies
  (`devtools_connection_dialog.cc:56-77, 93-100`). Initially-focused field is **Cancel**, default button is
  `kNone` (`:75-76`). Every exit path funnels through `RunCallbackAndDie` which `delete this` (`:107-120`).
- **A no-window browser auto-denies**: if `GetLastActiveBrowser()` is null the dialog constructor denies
  immediately (`devtools_connection_dialog.cc:37-41`; pinned by the `NullBrowser` browsertest,
  `devtools_connection_dialog_browsertest.cc:25-32`). The browsertest file has **no** persistence/second-connection
  case — consistent with there being nothing to persist.
- Outcome is recorded to UMA `DevTools.RemoteDebugging.ConnectionPermission` (`chrome_devtools_manager_delegate.cc:529-542`,
  enum at `:89-96`) and the toggle to `DevTools.RemoteDebugging.ServerAction` (`inspect_ui.cc:84-89`).
- Official user-facing confirmation: *"Every time the Chrome DevTools MCP server requests a remote debugging
  session, Chrome will show a dialog to the user and ask for their permission"* —
  <https://developer.chrome.com/blog/chrome-devtools-mcp-debug-your-browser-session>

## (b) Why `/json/*` is absent, and whether anything restores it

- It is a **hard mode check with no escape hatch.** `ServerWrapper::OnHttpRequest` routes any path starting
  `/json` to `OnJsonRequest` (`devtools_http_handler.cc:470-475`), whose **first statement** is
  `if (mode_ == kWithApprovalOnly) { Send404; return; }` (`:584-590`). Same shape for `/` (`:759-764`) and
  `/devtools/<resource>` (`:776-782`). `mode_` is a constructor-time value (`:901-907`) set in exactly two
  places in `remote_debugging_server.cc` — `kDefault` for the switches (`:394`), `kWithApprovalOnly` for the
  pref path (`:247`). **No switch, pref, feature, feature-param or env var selects the mode.**
- Design intent, cited: the server *"does not respond to HTTP endpoints"* (CL 7123788). Rationale is discovery
  suppression — unauthenticated `/json/list` leaks every open tab's title and URL to any local process.
- The **only** way to get `/json/*` back is to run the server in `kDefault` mode, i.e. via
  `--remote-debugging-port` — see (c).
- Practical corollary for the lead: a client must be told the port and endpoint out-of-band. `DevToolsActivePort`
  in the user-data-dir is that channel (line 1 = port, line 2 = `/devtools/browser/<uuid>`;
  `devtools_http_handler.cc:298-308`), and the uuid is decorative in this mode.

## (c) The M136 default-user-data-dir refusal — path comparison, and gated on branding

- **It is a PATH COMPARISON, not switch-presence.** `chrome::IsUsingDefaultDataDirectory()` returns
  `user_data_dir == default_user_data_dir` over resolved `base::FilePath`s (`chrome/common/chrome_paths.cc:524-540`;
  declaration + contract at `chrome/common/chrome_paths_internal.h:29-32`). It returns `std::nullopt` if either
  lookup fails, and the caller does `is_default_user_data_dir.value_or(true)` — **fail-closed**
  (`remote_debugging_server.cc:176-180`).
- 🚨 **The check is compiled out on Chromium-branded builds.**
  ```
  #if BUILDFLAG(GOOGLE_CHROME_BRANDING)
    constexpr bool default_user_data_dir_check_enabled = true;
  #else
    const bool default_user_data_dir_check_enabled =
        g_enable_default_user_data_dir_check_for_chromium_branding_for_testing;
  #endif
  ```
  `remote_debugging_server.cc:168-181`; that global is `false` at `:51-52` and its only setter is
  `EnableDefaultUserDataDirCheckForTesting()`, documented as *"Enables the default user data dir check even for
  non-Chrome branded builds, **for testing**"* (`remote_debugging_server.h:46-50`). So on any build without
  Google Chrome branding, `--remote-debugging-port` on the **default** profile is **not refused**.
- **The runtime kill switch for this protection was deliberately removed.** CL 6311292 (2025-03-12, M136,
  `refs/heads/main@{#1431612}`) introduced it behind feature `DevToolsDebuggingRestrictions`, *"enabled by default
  for Google Chrome builds but could be used to disable the protection if widespread incompatibilities are
  encountered"*. CL 6762416 (2025-07-16, `@{#1487951}`) removed that feature: *"No production functional behavior
  change is expected from this CL, **except that it is no longer possible to disable the feature dynamically on
  the command line**."* ⇒ on a Google-Chrome-branded build there is **no** `--enable-features`/`--disable-features`
  route back. On a Chromium-branded build there is nothing to disable.
- **`--user-data-dir` spelling tricks do not work.** `InitializeUserDataDir` passes the switch value to
  `PathService::OverrideAndCreateIfNeeded(chrome::DIR_USER_DATA, dir, /*is_absolute=*/false, /*create=*/true)`
  (`chrome/app/chrome_main_delegate.cc:633-636`), and with `is_absolute=false` that applies
  `MakeAbsoluteFilePath` = POSIX `realpath(3)` (`base/path_service.cc:293-300`). Trailing slashes, `//`,
  relative paths and symlink aliases are all canonicalised, so they still compare equal and are still refused.
  *(INFERRED residual: `GetDefaultUserDataDirectory()` is **not** realpath'd, so on a machine whose canonical
  default path contains a symlinked component, `--user-data-dir=<that same path>` yields resolved-vs-unresolved
  and would compare unequal. Not verified; test with `realpath` against the literal default path.)*
- 🚨 **TRAP the lead must not walk into: passing `--remote-debugging-port` on a build where the check IS active
  kills the toggle-based server too, for that whole browser run.** `GetInstance` early-returns
  `base::unexpected(kDisabledByDefaultUserDataDir)` at `:384-388`, **before** the approval-mode block at
  `:399-417`; `CreateDevToolsProtocolHandler` then prints *"DevTools remote debugging requires a non-default
  data directory. Specify this using --user-data-dir."* to stderr and creates **no** server at all
  (`browser_process_impl.cc:1108-1114`). Recoverable by relaunching without the switch.
- **A persisted `chrome://flags` / Local State switch would not change this**, and in any case
  `kDevToolsAcceptDebuggingConnections` has **no `chrome://flags` entry** — 0 hits for it in
  `chrome/browser/about_flags.cc` (14,467 lines, fetch verified non-empty). `chrome://flags` selections are
  replayed as `--enable-features` at launch, which is exactly the lever CL 6762416 removed for the
  user-data-dir check and which cannot select `kDefault` mode in any case.

## (d) Every candidate bypass / persistence mechanism, with a verdict

| Candidate | Verdict | Evidence |
|---|---|---|
| A "remember this choice" pref | **Does not exist** | No pref read/written anywhere in `AcceptDebugging` → `DevToolsConnectionDialog` (`chrome_devtools_manager_delegate.cc:529-549`; `devtools_connection_dialog.cc` entire file, 120 lines) |
| Policy `RemoteDebuggingAllowed` | **Disable-only.** Maps to `devtools.remote_debugging.allowed`, checked 3× before start; cannot pre-enable, cannot auto-approve. Setting it `false` even **clears** the user pref | `chrome/browser/policy/configuration_policy_handler_list_factory.cc:549-551`; `remote_debugging_server.cc:164-167, 236-239, 257-261, 338-340, 406-409`; `browser_process_impl.cc:1120-1137` |
| Any policy mapping to `devtools.remote_debugging.user-enabled` | **None exists** | Full grep of the policy handler list: only `kRemoteDebuggingAllowed` and the two `DeveloperToolsAvailability*` list handlers appear |
| `DeveloperToolsAvailability` / `…Allowlist` / `…Blocklist` | **Wrong subsystem** — governs DevTools *frontend* availability, maps to `kDeveloperToolsAvailability*`, not to either remote-debugging pref | `configuration_policy_handler_list_factory.cc:2730-2740` |
| Feature flag / feature param on `kDevToolsAcceptDebuggingConnections` | **Plain on/off, no params.** Disabling it hides the toggle entirely and never starts the server; it cannot select `kDefault` | `chrome/browser/devtools/features.cc:203-211`; `inspect_ui.cc:874-881`; `remote_debugging_server.cc:252-253, 400-402` |
| `kDevToolsEnableDurableMessages` | **Unrelated** — Network panel response-body retention | `features.cc:200-201` |
| A token / secret in the WS path | **No.** The browser guid is explicitly not required in approval mode | `devtools_http_handler.cc:834-836` + its comment |
| `--remote-allow-origins` | **An additional restriction, never a bypass.** Checked *before* approval, and skipped entirely when the client sends no `Origin` header — which non-browser CDP clients do not | `devtools_http_handler.cc:817-831` |
| "Trusted CDP client" exemption | **Post-attach privilege, not a connection gate.** `DevToolsAgentHostClient::IsTrusted()` defaults to `true` and `DevToolsAgentHostClientImpl` does not override it — so an approved remote socket is *already* fully trusted; there is nothing further to unlock | `content/public/browser/devtools_agent_host_client.cc:18-21`; `devtools_agent_host_client.h:41-46`; no `IsTrusted` in `devtools_http_handler.cc` |
| DevTools-own / `chrome://inspect` connections | **Never traverse the HTTP server**, so they never prompt — and they only open the DevTools UI, they are not a scriptable CDP endpoint | `inspect_ui.cc` inspect commands operate on `DevToolsAgentHost` in-process |
| `--remote-debugging-pipe` | **Prompt-free by construction** — `StartRemoteDebuggingPipeHandler` never constructs a `DevToolsHttpHandler`, so no `mode_`, no `AcceptDebugging`. Still subject to the policy + (branding-gated) default-dir check. Requires launching the browser yourself with fds 3/4 | `remote_debugging_server.cc:325-332, 353-361` |
| `--remote-debugging-port` | **Prompt-free, full `/json/*`** (`kDefault`), and takes precedence over approval mode | `remote_debugging_server.cc:363-395, 397-400` |
| `--remote-debugging-targets` | **Red herring** — a legacy `chrome://inspect` *discovery* switch, unrelated to the server |  present in Dia's binary; no reference in `inspect_ui.cc` server paths |
| Editing Local State `user-enabled` by hand | **Starts the server, changes nothing about consent.** Also only read at launch/pref-change; a running browser will overwrite | `remote_debugging_server.cc:216-226` |
| Clicking Allow programmatically (accessibility/computer-use) | **Works, and is what the community does** — but it is unscopable: it approves *any* local process that attaches | `chrome-devtools-mcp#825` comments (domdomegg, dev-newb) |

**Chrome team's position, verbatim** (<https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/825>, closed
`NOT_PLANNED`, labels `collecting-feedback,feature`):
- OrKoN: *"We have been discussing it a lot. There is no simple solution that also would not allow any program on
  the machine to easily access your data in Chrome. For now, we recommend to have longer connection sessions to
  avoid the reconnect dialog."*
- OrKoN: *"For development and testing, I'd suggest setting up a dedicated profile for such use cases and running
  it with `--remote-debugging-port=9222 --user-data-dir=/path/to/profile` … In this case, there will be no dialogs."*
- natorion: *"+1. Closing this FR"*. Later asks for a bounded `Allow for 1 hour` grant (DenisSergeevitch, PaulRBerg)
  went unanswered.
- Issue **#1094** (also `NOT_PLANNED`) is reconnect churn, not a consent mechanism; **#978** is unrelated
  (WS saturation, closed not-reproducible). Neither adds a persistence surface.

## Feature history (Gerrit changes API; `+log` is 403)

| CL | Submitted | What it did |
|---|---|---|
| [6311292](https://chromium-review.googlesource.com/c/chromium/src/+/6311292) | 2025-03-12 | M136: refuse remote debugging on the default user-data-dir, behind feature `DevToolsDebuggingRestrictions`, *"enabled by default for Google Chrome builds"* |
| [6335679](https://chromium-review.googlesource.com/c/chromium/src/+/6335679) | 2025-03-10 | added `IsUsingDefaultDataDirectory()` |
| [6762416](https://chromium-review.googlesource.com/c/chromium/src/+/6762416) | 2025-07-16 | removed that feature ⇒ *"no longer possible to disable the feature dynamically on the command line"*; replaced by the branding buildflag |
| [7123788](https://chromium-review.googlesource.com/c/chromium/src/+/7123788) | 2025-11-19 | content: `kWithApprovalOnly` mode — per-WS-upgrade approval, no HTTP endpoints |
| [7157626](https://chromium-review.googlesource.com/c/chromium/src/+/7157626) | 2025-11-20 | chrome: start the server in approval mode at launch, behind a then-disabled flag |
| [7183381](https://chromium-review.googlesource.com/c/chromium/src/+/7183381) | 2025-11-24 | the `chrome://inspect` pref + policy + `PrefChangeRegistrar` lifecycle |
| [7200659](https://chromium-review.googlesource.com/c/chromium/src/+/7200659) / [7204537](https://chromium-review.googlesource.com/c/chromium/src/+/7204537) | 2025-11-26/27 | ephemeral-port fallback; **reuse the last port** from `DevToolsActivePort` |
| [7588378](https://chromium-review.googlesource.com/c/chromium/src/+/7588378) / 7595615 | 2026-02-18/19 | fix: server was not listening for pref changes (backported to M146) |
| [7684633](https://chromium-review.googlesource.com/c/chromium/src/+/7684633) | 2026-03-19 | validate the `Host` header on WS upgrades |
| [8285861](https://chromium-review.googlesource.com/c/chromium/src/+/8285861) | 2026-08-27 | dynamic refresh of the `RemoteDebuggingAllowed` policy |

## 6. Dia 1.48.0 — measured, read-only (no launch, no socket, no profile write)

Chromium lives inside `/Applications/Dia.app/Contents/Frameworks/ArcCore.framework/Versions/A/ArcCore`
(233 MB) — there is **no** separate `Chromium Framework.framework`. `strings -a` on it and on
`/Applications/Dia.app/Contents/MacOS/Dia` (128 MB Swift binary):

- **Stock content-layer approval mode, unpatched.** ArcCore contains `Connection rejected`
  (the approval-mode `Send403` at `devtools_http_handler.cc:842-843`), `No such target id: `,
  `DevTools listening on ws://%s%s`, `Using unsafe HTTP verb %s to invoke /json/new…`, the full
  `--remote-allow-origins` rejection message, `devtools.remote_debugging.user-enabled`,
  `devtools.remote_debugging.allowed`, `kDevToolsAcceptDebuggingConnections`,
  `remote-debugging-port`, `remote-debugging-pipe`, `set-remote-debugging-enabled`, and
  `DevTools remote debugging requires a non-default data directory…`.
- **The delegate is replaced, and only the delegate.** The stock Views dialog strings
  (`IDS_DEV_TOOLS_CONNECTION_DIALOG_*` — "Allow remote debugging?", "Disable remote debugging") are
  **absent from ArcCore**; the Swift binary carries `ArcDevToolsConnectionDialog` plus
  `Allow debugging connection?` and `Only allow this if you trust the source of this connection.`
  ⇒ Dia overrides `DevToolsManagerDelegate::AcceptDebugging` with an AppKit dialog and inherits everything
  else, exactly matching (a). It therefore inherits the **per-WS-upgrade** granularity too.
- **No pre-authorization lever in Dia.** Nothing matching `remember | always allow | pre-authori | trusted
  client | skip approval | allow for N hours` in either binary; no `arc-`/`dia-` switch mentioning
  debugging beyond the stock set. `DevToolsDebuggingRestrictions` is **absent** ⇒ base is post-M139,
  consistent with ~M150.
- Dia's own `ADK*DevTools*` Swift classes (`ADKBrowserContextDevToolsWrapper`,
  `WebContentDevToolsController`, `addPreloadScriptViaDevTools`, `getNetworkResponseBodyViaDevTools`) are
  **in-process** embedder CDP clients for Dia's own features. They bypass the HTTP server entirely and are
  not reachable by an external client.
- **Branding: strong but not airtight.** Only **7** `Google Chrome` occurrences in ArcCore, and they are
  `com.google.Chrome` / `com.google.Chrome.canary` bundle-id constants (present in unbranded builds, used by
  default-browser / import code). A genuinely `is_chrome_branded=true` build carries hundreds of product-name
  strings. Bundle id `company.thebrowser.dia`, version `1.48.0`. `GOOGLE_CHROME_BRANDING` additionally
  requires the non-public `src-internal` dependency. **Conviction ~85%** that
  `default_user_data_dir_check_enabled == false` in Dia.

## 7. Routes to the warm default profile, ranked — with the discriminating experiments

**E1 — settle the branding gate (decisive, ~1 relaunch, no profile mutation).**
Quit Dia, relaunch once from a shell with `--remote-debugging-port=9333` **and no `--user-data-dir`**, then
read stderr and the new `DevToolsActivePort`:
- If the port opens and `GET http://127.0.0.1:9333/json/version` returns **200 JSON** ⇒ the check is inert,
  Dia runs in `kDefault` mode on the real profile, **no dialog ever**, `/json/*` restored. This falsifies the
  prior session's "dedicated profile is the only no-dialog route".
- If stderr prints *"DevTools remote debugging requires a non-default data directory"* ⇒ the check is active;
  relaunch **without** the switch to get the toggle-based server back (per the §(c) trap, that run has no
  server at all). Cost: one Dia restart; Dia restores its tabs. Nothing is written to the profile by the test.

**E2 — confirm Dia is stock approval mode without opening a socket to a real endpoint (the lead owns this).**
In stock mode the responses are diagnostic and dialog-free:
`GET /` → **404**; `GET /json/version` → **404**; WS upgrade to `/devtools/page/xyz` → **403 "Connection
rejected"** with **no dialog**; WS upgrade to bare `/devtools/browser` **with no uuid at all** → **dialog**.
That last pair is the sharpest discriminator between "stock `kWithApprovalOnly`" and "a Dia-specific patch",
and it costs one prompt.

**E3 — one prompt, then never again for that socket (works today, no restart).**
Approve once on `/devtools/browser`, then keep the socket open and fan out with
`Target.setDiscoverTargets` + `Target.attachToTarget {flatten:true}` — sessions multiplex on the approved
socket, so no new upgrade and no new prompt. This is `HandleDebuggingApproval:792-810` creating one
browser-level `DevToolsAgentHost` whose client `IsTrusted()` is `true`. It is also literally what the Chrome
team recommends ("longer connection sessions"). The failure mode to engineer against is client *restart*
(issue #1094), not client *idle*: run the CDP client as a long-lived daemon, never per-tool-call.

**E4 — `--remote-debugging-pipe` on the default profile.** Prompt-free by construction (no HTTP handler at
all), same branding-gated precondition as E1. Requires you to own the launch and wire fds 3/4 — which means
the agent, not the Dock, starts Dia. Worth it only if E1 says the gate is inert *and* you want to avoid an
open localhost port.

**E5 — ruled out / not recommended.** Dedicated clean profile (loses the warm state that is the whole point;
the `dia-agent` skill already has this as SECONDARY). Auto-clicking Allow via computer-use (works; approves
*any* local attacher, so it is strictly weaker than persistence and it is what `dev-newb`'s tray app does).
Extension with the `debugger` permission (a real no-dialog CDP-ish path on the warm profile, but it is the
`chrome.debugger` API surface, not raw CDP, shows its own infobar, and needs an unpacked extension loaded into
Dia — not investigated here; flagged as the one unexplored alternative).

## 8. Adversarial pass — what a hostile reviewer would say I missed, and what I found

| Challenge | Result |
|---|---|
| "You only read `main`; the prior session may have been right for the version Dia ships." | Partly fair and handled by measurement instead of inference: I read Dia's own binary and found the stock M14x-era strings and no `DevToolsDebuggingRestrictions`, so its base is post-M139 and pre/post does not move any conclusion here. **Residual: I did not fetch a release-branch tree** — gitiles `+log` is 403 and I did not guess branch-head refs. Named as a blocker. |
| "You assumed Dia is Chromium-branded — that is the whole finding." | Correct, and it is labelled INFERRED at ~85% with E1 as the settling test. I did **not** present it as fact. |
| "Maybe another embedder returns `kAllow` unconditionally and that is the precedent." | Checked four: headless, content_shell, android_webview, chromecast — **0** `AcceptDebugging` hits each. Chrome's is the only override; the base **denies**. |
| "A feature param could flip the mode." | Checked: `kDevToolsAcceptDebuggingConnections` is a bare `BASE_FEATURE` with no `FeatureParam` (`features.cc:203-211`), and no `chrome://flags` entry exists. |
| "`kDevToolsEnableDurableMessages` sounds like session resumption." | It is Network-panel response-body retention (`features.cc:200-201`). Ruled out. |
| "`--remote-allow-origins=*` might be the pre-authorization." | It is checked *before* `AcceptDebugging` and is skipped outright when no `Origin` header is sent (`:817-831`). It can only ever *reject*. |
| "A `--user-data-dir` spelling variant defeats a string comparison." | Ruled out for the naive cases — `MakeAbsoluteFilePath`/`realpath` normalises (`path_service.cc:293-300`). One asymmetric residual named as INFERRED (default path is not realpath'd). |
| "`IsTrusted` / 'trusted CDP clients' (CL 7656906) sounds like an exemption." | It is post-attach privilege and it already defaults to `true` for remote sockets — there is nothing to unlock, and it gates nothing at connect time. |
| "Did you check the *first message* rather than the upgrade?" | Yes — `OnWebSocketMessage:884-891` only forwards to an existing client; the decision is made in `OnWebSocketRequest:812-873`, before any message. |
| "Does the browsertest suite prove per-connection-ness?" | It proves the four dialog outcomes and the null-browser deny; it contains **no** second-connection or persistence case. That is absence of a test, which corroborates but does not prove. The proof is the call site plus CL 7123788's wording. |
| "You did not check whether Dia patched `OnJsonRequest`." | ArcCore contains the stock `/json/new` unsafe-verb string and the stock 403 text, and the operator already measured 404 on `/json/*` — jointly consistent with stock. E2 is the clean discriminator. |
| "A running Dia will ignore a relaunch switch." | Named in E1: Dia is single-instance, so the switch requires a genuine quit-and-relaunch; forwarding to a live instance drops it silently. |

## 9. Blockers and uncertainties, named

- **BLOCKER (instrument):** gitiles `+log` and history pages return `403: Forbidden — Please sign in`. Commit
  history came from the Gerrit `/changes/?q=file:…` API. I could not diff a release branch against `main`, so
  every `file:line` is `main` @ 2026-09-14 only.
- **INFERRED, not cited (~85%):** Dia is not `GOOGLE_CHROME_BRANDING`, therefore the default-user-data-dir
  refusal is inert in Dia. E1 settles it in one relaunch.
- **INFERRED (low confidence, unverified):** the realpath asymmetry between `DIR_USER_DATA` and
  `GetDefaultUserDataDirectory()` could make `--user-data-dir=<canonical default>` pass on a machine whose
  default path traverses a symlink.
- **NOT INVESTIGATED:** the `chrome.debugger` extension route as an alternative no-dialog CDP path on the warm
  profile (E5); and whether Dia's own `ADK` in-process CDP surface is reachable from a Dia extension.
- **NOT REPRODUCED:** `chrome-devtools-mcp#825` carries a user report (`Simplereally`) of *"an already
  authorized session will, on MAC, always keep re-requesting allow/deny"*, which `domdomegg` triages as a
  separate bug. If it is real, E3's "one prompt per socket" degrades on macOS specifically. Single anecdote,
  no upstream bug id — treat as unverified, and watch for it during E3.
- **Boundary respected:** no WebSocket or HTTP connection was made to 127.0.0.1:9222; Dia was not launched;
  nothing under the Dia profile was read or written. Binary inspection was `ls`/`strings`/`PlistBuddy` only.
