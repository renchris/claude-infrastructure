# Claude in Chrome + `--chrome` driving Dia — rail card and setup

Read-only investigation, 2026-09-14. Nothing on this machine, in Dia, or in any config was changed.
`[C]` = cited (file:line / URL / binary offset). `[I]` = inferred, mechanism named.

**Headline:** the mechanism is *not* the native-messaging manifest. In 2.1.260 every tool call travels
`Claude Code MCP server → wss://bridge.claudeusercontent.com → extension`, matched by claude.ai
account UUID — the local unix socket exists and is **not** the tool-call path. So Dia's absence from
CC's hardcoded browser list costs you the manifest write, the extension-detection indicator, and
`open -a` targeting — **none of which gate tool execution**. The real gate is whether Dia's extension
opens its bridge WebSocket, and the last primary measurement (2026-07-18, this operator's own issue
#78763) says it does: `tabs_context_mcp`, `navigate`, `read_page`, `get_page_text` all worked in Dia;
only the CDP-backed `computer` tool (screenshot/zoom) failed 100%.

---

## Rail card

| Field | Finding |
|---|---|
| **Mechanism** | Extension (`fcoeoabgfenejglbffodgkkbkcdhcgfn`) ↔ `wss://bridge.claudeusercontent.com` ↔ CC's `claude-in-chrome` MCP server (CC re-spawns itself: `{type:"stdio",command:process.execPath,args:["--claude-in-chrome-mcp"],scope:"dynamic"}`). Transport chosen by `TUn(e)= e.bridgeConfig ? bridge : (e.getSocketPaths ? socketPool : singleSocket)`; `bridgeConfig:{url:…}` is set unconditionally in the server-context factory ⇒ **bridge always wins**. `[C: claude.exe @160164500, @170541570, @170557488, @170555754]` Corroborated independently by socat-MITM + lsof in issue #34364 ("Local bridge sockets … are NOT used for tool calls"). `[C: gh#34364]` Extension drives the page via `chrome.debugger` (CDP) + accessibility tree. `[C: support.claude.com/en/articles/12012173 permission table]` |
| **Prompts per browser launch** | **1, unavoidable, once per Dia launch if you want the banner gone**: Dia must be started with `--silent-debugger-extension-api`, else Chromium paints **"Claude started debugging this browser"** on every tab, persistently. `[C: gh#69287]` Verified no process on this box currently carries that flag (census run with the pattern in the environment, not argv). Otherwise: **0** prompts at launch. |
| **Prompts per action** | **0 with `CLAUDE_CHROME_PERMISSION_MODE=skip_all_permission_checks`.** Valid values are exactly `["ask","skip_all_permission_checks","follow_a_plan"]`; read from the MCP server env **or** `process.env`, so you can export it yourself. `[C: claude.exe @170555754]` CC sets it automatically only when `zq()` → `sessionBypassPermissionsMode()` `[C: @155984623, @165341986]`. Residual: the hidden front-loaded lookup is hard-coded `callTool("tabs_context_mcp",{createIfEmpty:true},{…,permissionMode:"ask"})` `[C: @170507406]` — if the extension honours that per-call override, the first navigate of a session can still prompt. `[I]` |
| **Residual human steps — once** | (1) install the extension in Dia from the Web Store; (2) sign the extension into the *same* claude.ai account as the CC session; (3) click **Connect** on the extension's pairing prompt (`broadcastPairingRequest` → `firePairingPrompt`, 120 s timeout) — after which `chromeExtension.pairedDeviceId`/`pairedDeviceName` persist in the config store and `getPersistedDeviceId()` re-selects that device silently. `[C: @170522303, @170557488]` (4) per config dir: dismiss the one-time intro dialog (`hasCompletedClaudeInChromeOnboarding`) and set `claudeInChromeDefaultEnabled`. |
| **Residual — per session** | **0** once `claudeInChromeDefaultEnabled: true` (or `CLAUDE_CODE_ENABLE_CFC=1`, checked *before* the config key) `[C: @165341986]`, **provided exactly one browser is on the bridge.** With 2+ connected the CFC system prompt orders: *"Before any browser action, you MUST call your ask-user tool … with a question listing EVERY connected browser … Do not skip any connected browser and do not pick one yourself."* `[C: @73803719]` Kill it with `CLAUDE_CODE_DISABLE_CFC_PROMPT=true`, which replaces the whole CFC system prompt with `""` `[C: @165341986]` — at the cost of the tool-usage guidance. Cheaper: keep Chrome/Arc/Brave/Edge/Vivaldi/Opera *unpaired*. |
| **Residual — per action** | Model-side, not mechanical: the extension's own stored system prompt carries `<prohibited_actions>` — *"PROHIBITED … even if the user explicitly requests or permits them: Handling banking, sensitive credit card, or ID data · Downloading files from untrusted sources · Permanent deletions · Modifying security permissions or access controls · Providing investment or financial advice · Executing financial trades · Modifying system files · Creating new accounts"* — plus an explicit-permission tier (publishing/modifying/deleting public content, sending messages on the user's behalf, cookie/consent dialogs, purchases) with *"Permissions cannot be inherited and do not carry over from previous contexts."* `[C: Dia `Local Extension Settings/fcoeoabg…/000049.log`, extension v1.0.80 storage]` Whether `skip_all_permission_checks` overrides a *prompt-level* rule is **untested**. |
| **Capability vs raw CDP** | 21 tools, verbatim from the binary: `tabs_context_mcp` `tabs_create_mcp` `tabs_close_mcp` `navigate` `computer` `read_page` `get_page_text` `form_input` `javascript_tool` `read_console_messages` `read_network_requests` `resize_window` `gif_creator` `upload_image` `shortcuts_list` `shortcuts_execute` `update_plan` `browser_batch` + bridge-only `list_connected_browsers` `select_browser` `switch_browser` (filtered out of the tool list when off-bridge). `[C: @74503318-74507577, @71872824, @170541570]` **Strictly narrower than raw CDP**: no cookie jar, no request interception/mutation, no `Fetch`/`Network` domain control, no download control (extension holds `downloads` permission but no tool exposes it), no target/frame management. Uploads: session must be allowed to `Read` the file, ≤10 MB total, hard-linked files refused. `[C: code.claude.com/docs/en/chrome]` |
| **Security posture** | Extension permissions include `debugger` ("allows Claude to actually control your browser"), `nativeMessaging`, `downloads`, `unlimitedStorage`, `scripting`, `tabs` `[C: support.claude.com/en/articles/12012173]`. Tool calls leave the machine — a **cloud round-trip through Anthropic's bridge** for every click on your warm, logged-in profile; account-mismatch is detected and refused (`tengu_chrome_bridge_account_mismatch`). Local socket dir is validated 0700/0600 and ownership-checked `[C: @73187915]`. `CLAUDE_CODE_OAUTH_TOKEN` in the shell **breaks it**: the OAuth scope check requires `user:profile`/`user:office`/`user:ccr_inference` and *"env-var and setup-token sessions default to `user:inference` only"* → Chrome integration is force-disabled even with `--chrome` `[C: @165340977; docs "Chrome integration also requires signing in with /login"]`. This intersects our own memory rule *[Correction inherits the claim's burden]* — the env token **takes precedence** over the keychain login, so exporting it silently disables this feature. Verified `CLAUDE_CODE_OAUTH_TOKEN` is **unset** in this shell and absent from `~/.zshrc`. Whole feature also sits behind server gate `Pt("allow_claude_browser_extension")` and managed `deniedMcpServers` `[C: @165340434; docs]`. |
| **Dia-verified?** | **Partially, by a primary report from this machine.** 2026-07-18, Dia 1.40.1 / ext 1.0.81 / CC 2.1.214: `tabs_context_mcp` ✅ `navigate` ✅ `read_page` ✅ `get_page_text` ✅ `computer(screenshot,zoom)` ❌ *"Failed to capture screenshot via CDP"*, 100% of the time, every page. `[C: gh#78763]` Earlier failures are superseded, not standing: 2026-01 `chrome.tabGroups` absent blocked everything `[C: gh#19268]`; 2026-03 the extension-side gate `chrome_ext_bridge_enabled` evaluated false for non-Chrome, `mcpConnected:false` `[C: gh#34364 (Arc), gh#36410 (Dia — filed from this box: socket path `/tmp/claude-mcp-browser-bridge-chrisren/<PID>.sock`)]`. Sibling caution: Arc at 2026-07-25 **connected but every command timed out** `[C: gh#81200]` — and Dia is built on the same `ArcCore.framework` (confirmed in Dia's live helper argv). |
| **One-command check** | `CLAUDE_CHROME_PERMISSION_MODE=skip_all_permission_checks claude --chrome --debug -p 'Call mcp__claude-in-chrome__tabs_context_mcp with createIfEmpty true, then mcp__claude-in-chrome__computer action screenshot on example.com. Report which succeeded. Ask me nothing.' 2>&1 \| grep -E 'Claude in Chrome\|Bridge URL\|screenshot\|tabId'` — the one probe that settles both open questions (does Dia reach the bridge; does `computer` still fail). Costs one small session's quota. |
| **Evidence** | Binary read: `~/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (2.1.260, Mach-O arm64), offsets cited above. Docs: `code.claude.com/docs/en/chrome`, `support.claude.com/en/articles/12012173`. Chromium: `chrome/common/chrome_paths.cc` — `DIR_USER_NATIVE_MESSAGING` = `DIR_USER_DATA` + `"NativeMessagingHosts"`. Issues: anthropics/claude-code #78763, #81200, #34364, #36410, #34830, #19268, #69287, #18075, #21829. |

---

## Corrections to the brief's premises

| Brief said | Measured |
|---|---|
| manifest present under `…/{Chrome-Agent,AgentBrowser-Warm}/NativeMessagingHosts/` | **False** — both dirs exist and are **empty**. CC wrote 8 manifests: Google Chrome, Chromium, Microsoft Edge, Vivaldi, `com.operasoftware.Opera`, `BraveSoftware/Brave-Browser`, **`Arc/User Data`** and **`Arc`** (two). All 290 bytes, byte-identical. |
| `~/Library/Application Support/Dia/NativeMessagingHosts/` would be sufficient | **Wrong dir, probably.** Chromium resolves the user manifest dir as `DIR_USER_DATA + NativeMessagingHosts`, and Dia's live helpers run `--user-data-dir=/Users/chrisren/Library/Application Support/Dia/User Data` ⇒ `**Dia/User Data/NativeMessagingHosts**`, exactly mirroring CC's own `arc` entry. gh#36410 asserts the non-`User Data` path and reports a successful `connectNative` pong, so write **both** (harmless, 290 B each). |
| a fixed dir list, an env var, or a flag? | **A fixed list, with no override.** `C=["chrome","brave","arc","edge","chromium","vivaldi","opera"]` and a parallel `Sos` for extension detection; `Tos()` → `Phn()` iterates it. No `CLAUDE_CODE_CHROME_PATH` / `CLAUDE_CODE_BROWSER` exists — still an open feature request (#18075, open since 2026-01-14; #21829 closed unimplemented). `[C: @160164500, @165340434]` |
| — | **Native messaging is currently broken for all 8 browsers on this box.** `~/.claude/chrome/chrome-native-host` execs `~/.claude-versions/2.1.80/…/cli.js`, which **does not exist** (only 2.1.113/114/183 remain). No `/tmp/claude-mcp-browser-bridge-*` dir. Any chrome-enabled session rewrites the wrapper and the 8 manifests idempotently, so this self-heals on first `--chrome` run. `[C: cat of the wrapper; `vos()` @165340434]` |
| — | The Claude extension **is uninstalled** in Dia (registry entry retains only `has_started_service_worker:true`, `service_worker_registration_info.version:"1.0.80"`, `debugger.onEvent`/`onDetach` listeners; no `manifest`, no `state`, no `path`). No evidence Dia blocks it: 0 hits for the id in Dia's 9.3 MB `BlockList.json`, no extension allow/blocklist policy in `Local State`, `allowlist:1` (Safe-Browsing allowlisted), and Dia runs three other Web Store extensions today. |
| — | `hasCompletedClaudeInChromeOnboarding:true` and `cachedChromeExtensionInstalled:false` live in **`$HOME/.claude.json` only**; all five `~/.claude*/.claude.json` config-dir stores have **no** chrome keys ⇒ the intro dialog and the default-enable flag are **per config dir** and must be set 5× for a 4-account fleet. |

---

## Setup procedure

Each step cites what makes it necessary. Steps 1–3 are the minimum; 4–7 are what buys *zero prompts*.

1. **Restore the native host by running one chrome-enabled session** —
   `claude --chrome` once (any config dir). `pde()` fires `vos()`, which regenerates
   `<config-dir>/chrome/chrome-native-host` against the *live* binary and rewrites all 8 manifests
   idempotently (it skips a manifest whose content already matches). Required because today's wrapper
   points at a deleted 2.1.80 `cli.js`. `[C: @165340434]` Note the wrapper is per-config-dir while a
   browser dir holds exactly one manifest ⇒ **the last enabling session's config dir wins**; decide
   which account owns the browser rail. `[I: wrapper found at `~/.claude/chrome/`, `Tos()` returns only browser dirs]`

2. **Copy the manifest into Dia — both candidate dirs** (CC will never write them, and will never
   delete them either, so this is stable across upgrades):
   `mkdir -p "$HOME/Library/Application Support/Dia/User Data/NativeMessagingHosts" "$HOME/Library/Application Support/Dia/NativeMessagingHosts"`
   then copy `com.anthropic.claude_code_browser_extension.json` from
   `…/Google/Chrome/NativeMessagingHosts/` into each. Cited by Chromium `chrome_paths.cc`
   (`DIR_USER_NATIVE_MESSAGING = DIR_USER_DATA + "NativeMessagingHosts"`) + Dia's live
   `--user-data-dir`; the second path because gh#36410 reports a working `connectNative` pong against it.
   *Strictly speaking optional* — the bridge, not native messaging, carries tool calls — but it is the
   documented mechanism, it costs 580 bytes, and it is what `/chrome`'s reconnect flow expects.

3. **Install the extension in Dia and sign it into the same claude.ai account** as the CC session
   (`chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn`, ≥1.0.36 required).
   Account identity is the bridge's matching key; a mismatch yields *"the OAuth token Claude Code is
   using belongs to a different claude.ai account"*. `[C: docs Prerequisites; @170557488]`

4. **Unpair / don't pair every other browser.** Chrome, Arc, Brave, Edge, Vivaldi, Opera all hold a
   working manifest after step 1. Two connected browsers ⇒ the CFC system prompt *mandates* an
   ask-user question before any browser action. `[C: @73803719]` If a second browser must stay
   connected, set `CLAUDE_CODE_DISABLE_CFC_PROMPT=true` (drops the entire CFC system prompt) and rely
   on the persisted `pairedDeviceId`. `[C: @165341986, @170557488]`

5. **Export the two env vars in the launcher** (not `settings.json` → `env`, because both are read
   from `process.env` and the MCP server inherits):
   `CLAUDE_CHROME_PERMISSION_MODE=skip_all_permission_checks` (the only value that removes per-action
   checks; `ask` and `follow_a_plan` are the alternatives) and `CLAUDE_CODE_ENABLE_CFC=1` (evaluated
   *before* the config key, so it survives a fresh config dir). `[C: @170555754, @165341986]`
   Do **not** export `CLAUDE_CODE_OAUTH_TOKEN` — it ranks above the `/login` keychain credential and
   its `user:inference`-only scope force-disables Chrome integration. `[C: @165340977; docs/en/authentication § Authentication precedence]`

6. **Per config dir, set the two config keys** so no dialog and no flag are needed:
   `claudeInChromeDefaultEnabled: true` and `hasCompletedClaudeInChromeOnboarding: true` in that
   dir's `.claude.json` (both are in CC's own recognised-key list `Vzt`). The supported route is
   `/chrome` → **"Enabled by default"**. `[C: @158225431, @186219868]`

7. **Add explicit allow rules** so `defaultMode:"auto"`'s classifier is not in the loop. The
   whole-server shorthand `mcp__claude-in-chrome` is the documented convention but I did not verify it
   verbatim this pass `[I]`; the belt-and-braces form uses the tool names read out of the binary:
   `mcp__claude-in-chrome__tabs_context_mcp`, `…__tabs_create_mcp`, `…__tabs_close_mcp`,
   `…__navigate`, `…__computer`, `…__read_page`, `…__get_page_text`, `…__form_input`,
   `…__javascript_tool`, `…__read_console_messages`, `…__read_network_requests`, `…__resize_window`,
   `…__gif_creator`, `…__upload_image`, `…__shortcuts_list`, `…__shortcuts_execute`,
   `…__browser_batch`. `[C: @74503318-74507577]` Per our own measured rule, an allow rule cannot
   silence a PreToolUse hook's `ask` — but no hook in this repo matches `mcp__claude-in-chrome__*`,
   so these rules are sufficient on the CC side.

8. **Relaunch Dia with the banner suppressed** (only if the infobar is unacceptable):
   quit Dia, then `open -a Dia --args --silent-debugger-extension-api`. Verified read-only that no
   process on this box currently carries the flag. `[C: gh#69287]` A shared human+agent browser means
   the human sees the banner on every tab otherwise.

9. **Verify with the one-command check** in the rail card. `/chrome` shows `Status: Enabled`,
   `Extension: Installed`, `Browser: <name>`; expect **`Extension: Not detected`** even on success,
   because the filesystem probe `wos()` scans only the 7 hardcoded profile roots and will never look
   in `Dia/User Data/Default/Extensions/`. `[C: @165340434]` Judge on a tool call, not the indicator.

---

## Blockers and open questions, named

1. **`computer` (screenshot / coordinate click / zoom) failed 100% in Dia** as of 2026-07-18 on
   Dia 1.40.1 — Dia is now 1.48.0, so this is *stale, not refuted*. If it still fails, the extension
   cannot see the page visually in Dia, and every visual-verification workflow must fall back.
   `[C: gh#78763]`
2. **Arc — same ArcCore engine — connected but every command timed out** two months ago, unfixed and
   closed stale. That is the worst plausible Dia outcome: a browser that pairs and then does nothing.
   `[C: gh#81200]`
3. **The extension-side bridge gate is unverifiable from here.** `chrome_ext_bridge_enabled` is
   evaluated in the *extension* (0 occurrences in the CC binary), server-side, and historically
   returned false for non-Chrome. CC's own gate `allow_claude_browser_extension` is likewise remote —
   `~/.claude/statsig/` holds only `session_id`/`stable_id`, no gate values. Neither can be
   pre-checked; only the live probe answers.
4. **Every click leaves the machine.** A cloud round-trip per action on the operator's warm,
   logged-in profile is a materially different posture from local CDP, and it is unavoidable: the
   bridge is selected whenever `bridgeConfig` is present, which is unconditional in the context
   factory I read. I did not locate a caller that omits it. `[I, mechanism named]`
5. **`permissionMode:"ask"` is hard-coded on the front-loaded `tabs_context_mcp` lookup.** If the
   extension honours a per-call override, `skip_all_permission_checks` will not cover the first
   navigate of a session. Untested. `[C: @170507406]`
6. **Multi-account fleet friction.** One manifest per browser dir, one wrapper per config dir, one
   `pairedDeviceId` per config dir, one `claudeInChromeDefaultEnabled` per config dir. Four accounts
   sharing one Dia means four pairings and a manifest that points at whichever config dir last ran
   `--chrome`.

---

## Alternatives considered and ruled out

| Alternative | Ruled out because |
|---|---|
| **`chrome-devtools-mcp --browserUrl` against Dia's live CDP** (the `dia-agent` / `autonomous-authenticated-web-access` incumbent) | **Not ruled out — it is the stronger option on every axis the brief asks about, and it already works.** Dia is running with `DevToolsActivePort` = `9222` right now. Full CDP: screenshots (which the extension *cannot* do in Dia), cookies, network interception, downloads, targets. Zero cloud round-trip, no account matching, no bridge gate, no per-action permission layer, no bridge-vs-socket ambiguity. Its cost is the `dia://inspect` consent toggle once per Dia launch — one step against this rail's nine. Recommend it as the primary and Claude-in-Chrome as a complement for the tools CDP lacks a nice shape for (`read_page` accessibility tree, `gif_creator`, `shortcuts_*`). |
| Add Dia to CC's browser list via config/env | No such lever exists; #18075 open since January, #21829 closed unimplemented. |
| Patch the binary to add a `dia` entry | It is a 203 MB compiled Mach-O, replaced on every auto-update; and the entry buys only the manifest write + `open -a` targeting, neither of which gates tool calls. |
| Rename/symlink Dia's profile dir to impersonate Arc | Would make CC write Arc's manifest into Dia's tree, but CC's `arc` entry also drives `open -a "Arc"` and the extension-detection scan; collides with the real Arc install, which is present on this box. |
| Run the extension in a second Chromium (Chrome-Agent / AgentBrowser-Warm profiles already exist here) | Defeats the stated goal — one browser, warm logins, shared by human and agents — and adds a second connected browser, which triggers the mandatory browser-selection question. |
| `claude setup-token` / `CLAUDE_CODE_OAUTH_TOKEN` for unattended sessions | Explicitly incompatible: that credential's scope is `user:inference` only, and CC force-disables Chrome integration for it even with `--chrome`. |
| Force the local unix-socket transport instead of the bridge | No flag reaches it. `USE_LOCAL_OAUTH` / `LOCAL_BRIDGE` only redirect the bridge URL to `ws://localhost:8765` — they do not switch transport, and they point at a server that does not exist here. |
