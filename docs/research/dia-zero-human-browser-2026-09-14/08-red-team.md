# 08 — Red team: zero-human rails for driving the operator's real warm Dia

Live facts (read-only, this box): Dia 1.48.0 pid 1902 LISTEN 127.0.0.1:9222;
`Local State` `devtools.remote_debugging.user-enabled:true`; `DevToolsActivePort`=**9222 FIXED**
(memory said "ephemeral <port>" — drift). Dia loads Web Store extensions (GoFullPage present) and a
`nativeMessaging`-capable one (`mcbpbloc…`). Dia is NOT in Claude Code's supported/detect list
(Chrome, Edge, Brave, Arc, Vivaldi, Opera — docs).

## R1 — dia://inspect :9222 + one-WS multiplexer + Hammerspoon auto-approver
- **Kills it (soundness):** the approval dialog does NOT identify the connecting client.
  `AcceptDebugging → DevToolsConnectionDialog::Show(last_active, cb)` (chrome_devtools_manager_delegate.cc):
  no client pid/name in the UI, **no queue, no timeout**, each request spawns its own dialog
  independently. So an auto-approver cannot bind "the Allow I press" to "the daemon's connection." The
  only pre-approval filter is the HTTP `Origin` header (devtools_http_handler.cc); **local processes
  send none → never filtered.** The `lsof` sole-pending-peer test is TOCTOU: the socket is accepted
  before the dialog resolves, so a same-user process racing the daemon's reconnect gets its own
  auto-Allowed dialog. This nullifies the only gate — same defect the June-2026 refutation named,
  unchanged by the dialog being native/AX.
- **Degrades it:** WS on ~50 tabs dies (no keepalive, chrome-devtools-mcp #978) → reconnect
  re-fires consent (#1094) → the approver is armed **continuously**, not once, widening the TOCTOU
  window per drop. Dialog attaches to `last_active` window = the human's active Space; a dialog on a
  non-active Space is **invisible to Hammerspoon** (`hs.window.allWindows` = current Space only) → approver
  silently no-ops → hang. Sparkle restart (~3–5d) re-arms :9222 (pref persists) and re-prompts.
- **Residual after mitigation (peer-pid auth):** macOS has no reliable peer-cred gate on TCP loopback
  and "no OS control selectively blocks same-user processes" (memory). Residual = **any same-user
  process (infostealer, e.g. VoidStealer CDP-attach) reads `Network.getAllCookies` for the whole warm
  jar** the instant a connection is approved.
- **VERDICT: RISKY-BUT-GATEABLE** (against accidents; DEAD as a default against a same-user adversary).

## R2 — extension relay via chrome.debugger (Playwright Bridge / custom)
- **Kills it (coexistence):** the "**<ext> started debugging this browser**" infobar is **global across
  every tab** and only suppressed by launching with `--silent-debugger-extension-api` (restart required)
  or enterprise force-install (GH#69287, closed not-planned). On the operator's *daily* browser this is
  a permanent banner on every tab — user-hostile, and the flag can't be set on a Sparkle-relaunched Dia.
- **Degrades it:** chrome.debugger refuses chrome:// pages, other extensions, and any tab where the
  human has DevTools open ("Another debugger is already attached", debugger_api.cc). MV3 SW dies at 30s
  idle unless something holds it (debugger keeps it alive Chrome 118; WS Chrome 116) — so before attach
  the relay WS can drop. Chrome Web Store has removed debugger-automation extensions (policy risk);
  custom/unpacked side-load needs Dia dev-mode.
- **Residual after token gating:** relay is loopback-validated but the **token is the sole gate**
  (`PLAYWRIGHT_MCP_EXTENSION_TOKEN` bypasses the approve dialog); a custom relay with no token is
  hijackable by any local process; token leaks via extension UI / env.
- **VERDICT: RISKY-BUT-GATEABLE** (token-gated), but the global banner makes it unfit for the *daily* browser.

## R3 — Claude in Chrome extension + `claude --chrome` native messaging into Dia
- **Kills it (isolation + support):** by design it drives the **warm profile** and "shares your
  browser's login state… any site you're already signed into" (docs) — zero isolation from
  health/financial/email sessions; same global debugger banner as R2. **Dia is not supported/detected**
  (docs list excludes Dia); connection also traverses a **remote bridge `bridge.claudeusercontent.com`**
  (docs error table) — not purely local.
- **Degrades it:** requires `/login` — an API key / `setup-token` session keeps Chrome integration OFF
  even with `--chrome` (docs). NMH manifest must be hand-placed at
  `~/Library/Application Support/Dia/User Data/NativeMessagingHosts/` (DIR_USER_DATA + /NativeMessagingHosts,
  chrome_paths.cc) — **currently absent**; detection into Dia unverified. SW idle → "Receiving end does
  not exist" needs `/chrome` reconnect.
- **Residual after profile scoping:** none available — the feature has no clean-profile mode; it is the
  warm browser or nothing, so the full-jar exposure is irreducible.
- **VERDICT: DEAD** for the real warm Dia (no isolation, unsupported browser, remote bridge).

## R4 — 2nd Dia on a cloned warm profile + `--remote-debugging-port` (consent-free)
- **Kills it (security):** a launch-time `--remote-debugging-port` is **consent-free end-to-end**
  (memory, proven) → open 9222 + full CDP = **`Network.getAllCookies` for ANY local process, ungated**;
  the clone carries the full jar (memory: 4526 cookies / 1005 domains incl paypal/aetna/amazon),
  decryptable because the "Dia Safe Storage" Keychain key is **binary-bound, not path-bound**. This IS
  the credential-theft path policy forbids.
- **Degrades it:** cloning while live Dia runs risks the 2026-07-09 profile-corruption class (Spaces
  lost); `Target.createTarget({browserContextId})` throws `-32602/-32000` on some Dia contexts →
  unreliable Space scoping; snapshot clone misses IndexedDB/localStorage.
- **Residual after clean-profile substitution:** using a *clean* dedicated profile removes the jar but
  then it is **no longer the warm browser** (defeats the objective) and 9222 stays ungated to same-user
  processes (kill-port-when-done is the only control).
- **VERDICT: DEAD** as "warm profile" (it is the infostealer path); the clean-profile variant is a
  different rail, not this one.

## Ranked residual risk (worst first)
1. **R4 warm-clone** — ungated full-jar theft by any local process; irreducible. DEAD.
2. **R3** — warm-jar exposure + remote bridge + unsupported; no isolation mode. DEAD.
3. **R1** — same-user TOCTOU nullifies the sole gate; gateable only vs. accidents. RISKY.
4. **R2** — token-gateable, but permanent global debug banner on the daily browser. RISKY.

Uncertainty/blockers: no connection to :9222 or AX presses were made (read-only brief).
Dia-into-Claude-Code detection (R3) is UNVERIFIED (unsupported browser). Whether Dia's dialog is
AX-actionable on the *active* Space is asserted by the brief, not re-measured here.
