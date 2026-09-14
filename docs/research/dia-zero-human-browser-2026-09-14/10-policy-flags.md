# Policy / managed-prefs / flags levers for a Dock-launched agent-ready Dia

Scope: whether Chromium enterprise policy, macOS managed preferences, persisted `chrome://flags`, or
feature flags can (a) remove/pre-answer the remote-debugging consent, (b) restore HTTP `/json`
discovery, (c) force-install + pre-authorize a relay extension and its native-messaging host, or
(d) otherwise make Dia agent-ready with no human. Read-only; Dia never launched, never connected to.

## Verdict

**(a) No. (b) No. (c) Partly — force-install yes, native-messaging host no. (d) Yes, but by a route
the brief's framing excludes: `chrome.debugger` via `ExtensionInstallForcelist`, which never opens a
remote-debugging connection and therefore never reaches the consent dialog.**

Three independent reasons (a) is structurally closed, each measured:

1. The consent is not in Chromium's policy-gated path. It is
   `arc::BrowserContext::Delegate::DevToolsNeedsConfirmation` /
   `arc::WebContents::DevTools::Delegate::DevToolsNeedsConfirmation` — a TBC delegate callback out of
   `../../arc/browser/web_contents/devtools_impl.cc` into an Objective-C
   `ArcDevToolsConnectionDialog`. No policy handler exists for a delegate callback.
2. The build's own enum of reasons the server does not start is
   `kDisabledByAdmin · kDisabledByLocalSettings · kDisabledByPolicy · kDisabledByUser` —
   **four ways to forbid, zero to force on.** Policy is a veto surface here, not a grant surface.
3. `RemoteDebuggingAllowed` already defaults to `true`
   ([RemoteDebuggingAllowed.yaml](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/policy/resources/templates/policy_definitions/Miscellaneous/RemoteDebuggingAllowed.yaml):
   `default: true`, `dynamic_refresh: true`, `per_profile: false`, `chrome.*:93-`), so setting it
   buys nothing that is not already true. Upstream's own request to persist the approval
   ([chrome-devtools-mcp#825](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/825))
   is **closed as not planned**.

### Premise corrections from the brief

| Brief said | Measured |
|---|---|
| "Chromium ~150 fork" | **Chromium 153.0.8010.37** — `Chrome/153.0.8010.37` UA in `ArcCore` |
| consent "implemented by TBC in Swift" | TBC renders it, but the mechanism is **upstream M144 approval mode** — histograms `DevTools.RemoteDebugging.ConnectionPermission` and `DevTools.RemoteDebugging.ServerAction` are Chromium's. TBC supplies only the UI via the delegate. This *widens* the finding: the upstream "not planned" decision governs, not a TBC choice we might lobby to change. |
| (implied) a normal Chromium bundle layout | Chromium is inside **`ArcCore.framework`** (233 MB binary), helpers at `ArcCore.framework/Versions/A/Helpers/Browser Helper*.app`. The 128 MB `Contents/MacOS/Dia` is Swift/ObjC and links **system `WebKit.framework` 622.2.11** for non-web-content UI. Any `strings`/`otool` recipe aimed at `Contents/Frameworks/*Framework.framework` finds nothing and reads as "not Chromium". |

## Lever table

`YES` = can pre-answer or suppress the per-connection consent. Verification commands are read-only
unless marked. All Dia-local paths below are relative to
`/Applications/Dia.app/Contents/Frameworks/ArcCore.framework/Versions/A/ArcCore` (= `$CORE`).

| Lever | What it controls | Pre-answers consent? | How to apply to Dia on macOS | Verification | Evidence |
|---|---|---|---|---|---|
| `RemoteDebuggingAllowed` | Whether `--remote-debugging-port` / `--remote-debugging-pipe` / the M144 toggle are permitted at all. Boolean, **default `true`** | **NO** — veto only. Already effectively on | `/Library/Managed Preferences/<user>/<bundle-id>.plist` via MDM/mobileconfig (see B1 for the bundle id) | `strings -a "$CORE" \| grep -x RemoteDebuggingAllowed` → 1; then `dia://policy` | [yaml](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/policy/resources/templates/policy_definitions/Miscellaneous/RemoteDebuggingAllowed.yaml) · [enterprise](https://chromeenterprise.google/policies/remote-debugging-allowed/) · [admx](https://gpedit.tplant.com.au/en-us/policy/chrome/RemoteDebuggingAllowed/) |
| `DeveloperToolsAvailability` | DevTools frontend + element inspection. `0` (default) = allowed **except in the context of policy-installed extensions**; `1` = allowed everywhere; `2` = blocked | **NO** — never mentions remote debugging or CDP. Relevant only as a *hazard*: at the default `0` you cannot inspect your own force-installed relay | same managed-prefs path; set `1` if you must debug the relay | `dia://policy` after applying | [admx](https://gpedit.tplant.com.au/en-us/policy/chrome/DeveloperToolsAvailability/) |
| `DeveloperToolsDisabled` | Deprecated predecessor of the above | **NO** — forbid-only | n/a | `strings -a "$CORE" \| grep -x DeveloperToolsDisabled` → 1 | policy name block in `$CORE` |
| `ExtensionInstallForcelist` | Silent install of an extension id + update URL. **"install silently, without user interaction, and which users can't uninstall or turn off"**; **"Permissions are granted implicitly"** | **NO** for the CDP consent — but **this is the route that works** (see § The route that works). Grants the relay's `debugger` permission with no prompt | managed prefs, array of `<id>;https://clients2.google.com/service/update2/crx` | `dia://extensions` shows the item as policy-installed and non-removable | [admx](https://gpedit.tplant.com.au/en-us/policy/chrome/ExtensionInstallForcelist/) |
| `ExtensionSettings` (`toolbar_pin`, `runtime_allowed_hosts`, `installation_mode`) | Per-extension pinning and policy-granted host permissions | **NO** | managed prefs, dict keyed by extension id or `"*"` | `dia://policy` → the dict renders under Extensions | policy name present in `$CORE`; schema per Chrome Enterprise |
| `NativeMessagingAllowlist` / `NativeMessagingBlocklist` | Which already-installed native-messaging hosts may be used | **NO** | managed prefs | — | policy names present in `$CORE` |
| `NativeMessagingUserLevelHosts` | **"Enabled or unset means Google Chrome can use native messaging hosts installed at the user level. Disabled means … only … system level."** Does **not create or register** a manifest | **NO** | managed prefs | — | [admx](https://gpedit.tplant.com.au/en-us/policy/chrome/NativeMessagingUserLevelHosts/) |
| Native-messaging host **manifest** | The actual registration. Must pre-exist as a JSON file on disk; **no policy can create it** | **NO** | Write the manifest yourself. Dirs compiled into `$CORE`: `/Library/Google/Chrome/NativeMessagingHosts` and `/Library/Application Support/Chromium/NativeMessagingHosts`. **Neither is Dia-named**, and `~/Library/Application Support/Dia/NativeMessagingHosts` does not exist on this Mac | `strings -a "$CORE" \| grep -i NativeMessagingHosts` → the two dirs above, no Dia dir | measured in `$CORE`; see B1 — the dir name and the policy bundle id share a branding origin |
| `RemoteAccessHost*` (20 policies) | **Chrome Remote Desktop host.** Unrelated to CDP | **NO** | n/a | — | full list enumerated from `$CORE`; `RemoteAccessHostAllowRemoteAccessConnections` etc. |
| Any **new M144 policy** | — | **NONE EXISTS.** The alphabetical policy-name block in `$CORE` runs `RemoteAccessHostUdpPortRange → RemoteDebuggingAllowed → ReportExtensionsAndPluginsData`. No `RemoteDebugging{Enabled,Approval,Consent}*`, no consent policy of any name | n/a | `strings -a "$CORE" \| grep -Ex 'Remote[A-Za-z]+' \| sort -u` | measured; 153's policy list is stock Chrome |
| macOS **managed preferences** (`/Library/Managed Preferences/<user>/<id>.plist`) | The only path CFPreferences reports as *forced* | Carrier only — carries the policies above, none of which can grant | MDM / signed `.mobileconfig` | `dia://policy` shows level `Mandatory` | [policy_loader_mac.mm](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/policy/core/common/policy_loader_mac.mm): `PolicyLevel level = forced ? POLICY_LEVEL_MANDATORY : POLICY_LEVEL_RECOMMENDED;` |
| `defaults write <bundle-id> <Key>` (user level) | **Loads as RECOMMENDED / `POLICY_SCOPE_USER`, not mandatory** — `CFPreferencesAppValueIsForced` is false for user defaults | **NO** | — | `dia://policy` would show level `Recommended` | same file. `_CFPreferencesAppValueIsForced` **is imported by `ArcCore`** (`nm -u "$CORE"`), so the discriminator is linked in |
| `/Library/Preferences/<bundle-id>.plist` (root-owned) | Commonly assumed to be "managed". It is not — CFPreferences only reports MCX/managed sources as forced | **NO** | — | as above | `policy_loader_mac.mm` forced-value semantics |
| Persisted `chrome://flags` → `Local State` `browser.enabled_labs_experiments` | Applies declared `FeatureEntry`s at startup | **NO** | Editing Local State is a write; not attempted | `strings -a "$CORE" \| grep -Ex '[a-z0-9-]*remote-debug[a-z0-9-]*'` → only `remote-debugging-{port,pipe,targets}` (switches) + one optimization-guide flag. **No flag entry exists for remote debugging** | measured. Flags storage can only replay entries that a `FeatureEntry` declares; it is not a generic switch-injection channel |
| `--remote-debugging-port` at a Dock launch | — | **Unreachable.** ArcCore's ObjC initializer is `init:argv:profilePath:applicationID:isProduction:sessionRestorationPolicy:shouldLoadAllProfilesAtStartup:quitRunLoopOnTermination:userDefaultsSuiteName:` — **the Swift shell composes Chromium's `argv`.** The only named injection param is `arcCoreCommandLineArgsForTest:` (test-scoped) | — | `strings -a Contents/MacOS/Dia \| grep -F arcCoreCommandLineArgs` | measured |
| Dia's own launch-argument surface | `FeatureFlagOverrideCollection+LaunchArguments.swift`, `applyingTransientOverrides(launchArgument:)`, `transientFeatureFlagOverrides` | **NO** — these are **TBC feature flags, not Chromium switches**; no key matching devtools/debug/remote exists | — | `strings -a Contents/MacOS/Dia \| grep -iE 'FeatureFlagOverride\|transientOverrides'` | measured |
| `--remote-allow-origins` | WS handshake `Origin` allowlist (M111+) | **NO** — and not needed: a raw WS client sends no `Origin` | — | present in `$CORE` | switch string measured |
| `--silent-debugger-extension-api` | Suppresses the *"…is debugging this browser"* infobar for `chrome.debugger` | **NO** for CDP consent — but it is the cosmetic half of the route that works | switch; unreachable at a Dock launch. Prefer no banner suppression over a wrapper app | present in `$CORE` | measured |
| M136 default-user-data-dir restriction | Refuses `--remote-debugging-port` on the default profile dir | **Still in force in 153.** Verbatim in the binary: `DevTools remote debugging requires a non-default data directory. Specify this using --user-data-dir.` (and `DevTools remote debugging is disallowed by the system admin.`) | — | `strings -a "$CORE" \| grep -i 'remote debugging'` | measured |

## (b) HTTP `/json` discovery — compiled in, not reachable by configuration

`DevToolsHttpHandler` and its payload fields are all present in the build: `/json/list`,
`/json/version`, `/json/new?%s`, `webSocketDebuggerUrl` (×2), `devtoolsFrontendUrl` (×2),
`Protocol-Version`, `V8-Version`, `WebKit-Version`, and the guard string
`Using unsafe HTTP verb %s to invoke /json/new. This action supports only PUT verb.`

So the lead's runtime WS-only observation is a **start-path** decision, not a build omission: the
approval-mode server is started without the HTTP handler that `--remote-debugging-port` starts with.
**No pref, flag, policy or switch name in the build selects between them** — the two prefs are
`devtools.remote_debugging.allowed` (policy-backed) and `devtools.remote_debugging.user-enabled`
(the toggle), and neither is about transport.

Practical consequence: an agent must learn the browser-target WS URL some other way (the
`dia://inspect` page renders it) rather than by `GET /json/version`.

Correction worth recording: `devtools_http_service_handler.cc` appears in the build and looks like
the `/json` server. It is not — upstream it is DevTools' **outbound** HTTP/OAuth helper. The `/json`
strings come from `content/browser/devtools/devtools_http_handler.cc` (`DevToolsHttpHandler`).
Likewise `set-remote-debugging-enabled` reads like a command-line switch and is not: it sits in the
alphabetical `chrome://inspect` WebUI message list beside `set-port-forwarding-enabled`,
`set-discover-usb-devices-enabled` and `inspect-browser`. It is the JS→C++ message the toggle sends.

## The route that works (adversarial pass — the brief's framing excluded it)

The brief scopes every lever to the *remote-debugging connection*. But Dia ships the extension
debugger API:

- `debugger.attach`, `debugger.detach`, `debugger.sendCommand`, `debugger.getTargets`,
  `debugger.onEvent`, `debugger.onDetach`
- `../../chrome/browser/extensions/api/debugger/debugger_api.cc`
- `silent-debugger-extension-api`

An extension holding the `debugger` permission speaks CDP **in-process**: no port, no WS server, no
`devtools.remote_debugging.user-enabled`, no M136 user-data-dir check, and **no
`ArcDevToolsConnectionDialog`** — the consent is wired to the remote-debugging connection path, which
this route never takes. `ExtensionInstallForcelist` then supplies the missing half: install is
silent, the user cannot disable it, and **"Permissions are granted implicitly"** — so `debugger` is
granted with no prompt.

That makes the chain: `ExtensionInstallForcelist` (relay extension, `debugger` permission) →
`chrome.debugger` → agent. Its cost is that the relay needs a transport off-box, and the two obvious
ones are both constrained: a **native-messaging host** needs a manifest no policy can create (and
whose directory name is unresolved — see B1), while a **WebSocket to localhost** from the extension's
service worker needs a listener you control but no policy at all. The second is the cheaper one and
sidesteps B1 entirely.

Two hazards on this route, both measured:
- `DeveloperToolsAvailability` at its **default `0`** blocks DevTools *in the context of
  policy-installed extensions* — you cannot inspect your own relay. Set `1` if you need to debug it.
- The whole chain is gated behind B1/B2: without a working policy channel there is no forcelist.
  An unpacked / developer-mode load is the fallback and needs a human once.

## Dead ends, with the reason

| Lever | Why dead |
|---|---|
| Any policy to pre-approve/suppress the consent | **None exists.** 153's policy list has exactly one remote-debugging policy and it is forbid-only. Upstream feature request closed **not planned**. |
| `RemoteDebuggingAllowed = true` | Default is already `true`. Setting it changes nothing. `can_be_recommended` is absent from the yaml, so it is a mandatory-only policy — which only matters for the *disable* direction we do not want. |
| `defaults write company.thebrowser.dia <Policy>` | Loads **RECOMMENDED**, not mandatory. Also pointless — see the row above. |
| `/Library/Preferences/<id>.plist` as root | Not "forced" under CFPreferences ⇒ RECOMMENDED. A common and wrong assumption. |
| Persisted `chrome://flags` to inject `--remote-debugging-port` | Flags storage replays only declared `FeatureEntry`s. **No remote-debugging flag entry exists** in the build. Even if injected, the M136 default-dir refusal is still compiled in. |
| `--remote-debugging-pipe` | Needs inherited file descriptors. A Dock launch has none to inherit. |
| `--remote-allow-origins` | Solves a browser-origin `Origin` check an agent's raw WS client never triggers. |
| `RemoteAccessHost*` | Chrome Remote Desktop, not CDP. 20 policies, zero relevance. |
| `DeveloperToolsDisabled` / `DeveloperToolsAvailability` | Forbid-only; neither mentions remote debugging. |
| `NativeMessaging*` policies as a way to register a host | They allow/block hosts that already exist. The manifest is a file you must write. |
| `remote-debugging-targets` | A command-line switch for `chrome://inspect`'s TCP target discovery, not a consent or transport lever. |
| Editing `Info.plist` / shipping a wrapper `.app` to add argv | Not a policy, breaks the code signature, and out of the read-only boundary. The honest statement is that **macOS offers no supported way to give a Dock launch extra argv** without modifying the bundle or interposing a launcher. |

## Blockers and named uncertainties

- **B1 — the policy application id is unresolved, and it gates every policy row above.**
  `chrome_browser_policy_connector.cc` hardcodes `com.google.Chrome` for Google-branded builds and
  `com.google.ChromeForTesting` for CfT, **else `base::apple::BaseBundleID()`**. Dia is neither, so
  it takes `BaseBundleID()` — whose non-branded compile-time default is `org.chromium.Chromium`.
  Evidence *for* `company.thebrowser.dia`: ArcCore's initializer takes an explicit `applicationID:`,
  so the Swift shell supplies one. Evidence *against*: the only `company.thebrowser.dia` strings in
  ArcCore are sandbox cache paths, and the native-messaging dirs compiled in are Chrome's and
  **Chromium's**, with no Dia-named dir — which is exactly what a `BaseBundleID()`-default build
  looks like. The binary is stripped (2,932 symbols), so `SetBaseBundleID` cannot be resolved
  statically. **Falsifier, cheap and read-only: open `dia://policy`.** The WebUI is present —
  `components/policy/core/browser/webui/policy_status_provider.cc`, `getPoliciesJson`,
  `ExportPlatformPoliciesJson`, `copyPoliciesJSON`, `Enterprise.PolicyUI.ButtonUsage.ReloadPolicies`.
  Install one harmless test policy under each candidate id and read back which one appears, with its
  level and scope.
- **B2 — whether Dia instantiates the platform policy provider at all.**
  `chrome_browser_policy_connector.cc` is **absent** from ArcCore's source-file string set while many
  sibling `chrome/browser/policy/*` files are present. That is weak evidence either way — `__FILE__`
  strings only survive where a `CHECK`/`DCHECK`/`LOG` captures them — and it is contradicted by two
  positives: `_CFPreferencesAppValueIsForced` is imported, and the child-process sandbox profile
  explicitly grants reads of `/Library/Managed Preferences/<bundle-id>.plist` and
  `.GlobalPreferences.plist`. Same falsifier as B1. **Do not treat the absent string as absence.**
- **B3 — upstream design intent on `/json` omission is unverified.** The authoritative tracker,
  [crbug 41077112](https://issues.chromium.org/issues/41077112) *"Enable remote-debugging endpoint by
  default, and prompt user for incoming connections"*, requires sign-in; WebFetch received only the
  sign-in page. The WS-only behaviour is the lead's runtime measurement plus my build evidence that
  the HTTP handler exists — the *reason* is inferred, not read.
- **B4 — `chrome.debugger` reachability in Dia is inferred from API strings, not exercised.** TBC
  could blocklist the permission or the API in their extension surface. Falsifier: force-install (or
  developer-load) a minimal extension declaring `"permissions": ["debugger"]` and call
  `chrome.debugger.attach` against a tab.
- **B5 — `chrome://policy` vs `dia://policy` scheme.** ArcCore carries `chrome://inspect/` and
  `chrome://inspect#remote-debugging` verbatim while the operator reaches the page as
  `dia://inspect#remote-debugging`, so the scheme is remapped. Try `dia://policy` first,
  `chrome://policy` second.

## What I did not test, and why

- Never launched Dia, never wrote a plist, never connected to `127.0.0.1:9222` — boundary.
- Did not attempt `chrome://policy` myself — it requires launching Dia.
- Did not enumerate `ExtensionSettings`' full schema field-by-field; `toolbar_pin` and
  `runtime_allowed_hosts` are cosmetic/permission conveniences that cannot reach the consent, so
  depth there would not change the verdict.

## Provenance of local claims

All local measurements are read-only `strings`/`nm`/`otool`/`ls` against
`/Applications/Dia.app` (Dia 1.48.0, `company.thebrowser.dia`, Chromium 153.0.8010.37).
Cached string dumps for re-derivation:
`…/scratchpad/arccore.strings` (806,015 lines) and `…/scratchpad/dia.strings`.
