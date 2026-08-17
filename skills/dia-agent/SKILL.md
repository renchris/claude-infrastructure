---
name: dia-agent
description: Drive your real warm, logged-in Dia (The Browser Company, Chromium 149) over the Chrome DevTools Protocol with navigator.webdriver=false. PRIMARY = your REAL Dia via dia://inspect#remote-debugging + chrome-devtools-mcp --autoConnect; SECONDARY = an isolated CLEAN dedicated-profile Dia via ~/bin/dia-cdp-launch.sh; plain Chrome = labeled fallback only (Dia is the requirement). Use when the user wants to "drive my real/warm Dia", "attach an agent to my Dia", "use dia://inspect", "allow remote debugging", "autoConnect to Dia", "drive my logged-in Dia tabs", or launch/kill/check the agent Dia (or types /dia). Covers consent-dialog approval, the ephemeral WS-only port, browserContextId space-scoping, security lifecycle (UNCHECK the toggle when done), the dedicated-profile launcher, and troubleshooting. Deep CDP capability map + provenance in memory dia-agent-browser-cdp-entrypoint.md.
allowed-tools: Bash, Read
---

# dia-agent — agent-controlled Dia browser

Drive **Dia** (The Browser Company, Chromium 149) from an agent over CDP, with
`navigator.webdriver === false`. **Dia is the requirement** (not Chrome).

Two paths to Dia, plus a last-resort fallback:

1. **PRIMARY — your REAL warm Dia** via `dia://inspect#remote-debugging`. No separate
   launch; your real logged-in sessions across all Spaces. **Start here.**
2. **SECONDARY — an isolated clean dedicated Dia profile** via `~/bin/dia-cdp-launch.sh`.
   Use when you want isolation and do NOT want to expose the real Dia.
3. **FALLBACK (NOT the supported path) — plain Chrome.** Only if Dia is unavailable.

For the full CDP capability catalog, detection surface, alternatives (OpenDia extension,
Dia native agent-server), onboarding internals, and launchd: read memory
`dia-agent-browser-cdp-entrypoint.md`.

## Status — autonomy verified on Dia 1.37.1 / chrome-devtools-mcp 1.4.0 (2026-06-29)

**For AUTONOMOUS (no-modal) operation, use the SECONDARY/CLI path — NOT the PRIMARY `dia://inspect`
path.** The "Allow debugging connection?" modal is a STOCK Chromium 144+ per-connect gate (Dia inherits
it, not a TBC-custom layer), fired ONLY on the `dia://inspect` runtime-request flow, and it is
**non-persistable BY DESIGN** — no remember/flag/policy/plist/token bypasses it (chrome-devtools-mcp
GH#825 is the open, declined request). chrome-devtools-mcp re-opens a NEW CDP connection on every WS drop
(`if browser?.connected return`; no keepalive, GH#978), and **each reconnect re-fires the modal** — so on
the warm ~50-tab Dia it pops "every few seconds" (deny→retry loop + single-WS overload).

The CLI `--remote-debugging-port` path is **CONSENT-FREE end-to-end** (attach + createTarget + navigate,
proven 0.00–2.3 s, zero modals): a port you open at launch has no runtime-request gate.

**Launcher fixes applied 2026-06-29** (`~/bin/dia-cdp-launch.sh`):
- **`nohup` → `open -n`**: a shell-backgrounded Dia is REAPED within seconds on 1.37.1; `open -n` survives
  — **but ONLY from a FOREGROUND shell** (a backgrounded shell/daemon `open -n` is also reaped). Run
  `launch`/`supervise` in the foreground; there is intentionally NO background supervisor daemon.
- **`supervise [ttl]`** (new): foreground launch (Dia persists across your shell commands) + a DETACHED
  watchdog that auto-kills the port after `ttl` (default 3600 s). `kill` works from any context (unlike
  launch), so the teardown is enforced even if the agent crashes/forgets — the load-bearing control for an
  unauthenticated open port.
- **`--remote-allow-origins` scoped to `http://127.0.0.1:9222`** by default (override `DIA_ALLOW_ORIGINS=*`):
  verified that chrome-devtools-mcp `--browserUrl`, agent-browser, AND the raw no-Origin client all connect
  under the scoped allowlist on Chromium 149 — **this DISPROVES the old "`*` is required" hard fact below** —
  while a localhost-served web page's Origin is rejected, closing the one residual `*` left open.

**100p autonomous recipe:** `~/bin/dia-cdp-launch.sh supervise 3600` (foreground) → drive via
`chrome-devtools-mcp --browserUrl http://127.0.0.1:9222` (next session; restart-stable /json discovery) or
`agent-browser --cdp 9222` (this session, zero-config) → `~/bin/dia-cdp-launch.sh kill` when done. Sign into
agent-scoped sites in the clean profile ONCE (persists). Re-run a drive smoke test after each Dia auto-update.
Warm logins WITHOUT a modal → OpenDia extension (extension-API-capped, side-loaded, human-in-loop); the Dia
native agent-server (`:54271`) is Bearer-gated/internal — not a drivable surface.

## Primary — drive your real warm Dia (dia://inspect)

The supported path: your actual logged-in Dia, every session warm, no launcher.

1. In Dia, open `dia://inspect#remote-debugging`. Check
   **"Allow remote debugging for this browser instance."**
2. Dia starts a CDP server on an **ephemeral** `127.0.0.1:<port>` shown on that page.
   It is **WS-only** — there is NO `/json` HTTP discovery (`/json/version` 404s), so
   `--browserUrl` / `/json`-based clients do NOT work here. Re-read the port from the
   page each time (it changes when you cycle the toggle).
3. Attach with **`chrome-devtools-mcp --autoConnect --userDataDir "$HOME/Library/Application Support/Dia/User Data"`**
   (the manual/`.mcp.json` form of the page's "connecting to Chrome DevTools MCP" link).
   `--userDataDir` is **mandatory**: it makes chrome-devtools-mcp read Dia's `DevToolsActivePort`
   file and build the `ws://` endpoint — **bare `--autoConnect` defaults to Chrome's profile dir and
   connects to Chrome (or throws), never Dia**. Re-reading the file each run auto-tracks the
   ephemeral port across toggle cycles. If those MCP tools are not in your tool list, start a NEW
   Claude Code session with the toggle active, or use the raw-socket fallback below.
4. **Approve the consent dialog(s).** On connect, Dia pops permission dialog(s) that
   **stack** (up to ~3 queued). The connection **HANGS until you approve them** — this
   is normal, NOT a failure. Switch to the Dia window and approve each. Retrying before
   approving just queues more.
5. Scope your ACTIONS to ONE Space: enumerate with `Target.getTargets()` and read the target
   Space's actual `browserContextId` — a **runtime hex GUID** (e.g. `E03DADB5`), NOT the on-disk
   profile name (Agent-Access lives in on-disk `Profile 16`, but its CDP `browserContextId` is a
   different runtime hex). Then `Target.createTarget({ url, browserContextId })`.

   ⚠️ **`Target.createTarget` works only for a context DevTools itself owns — NOT for a sibling
   Space's.** Measured 2026-08-03 on Dia 1.35.2 against the warm personal instance: passing a
   `browserContextId` read off another profile's live page target is refused with
   `-32000 Failed to find browser context with id …`, even though `Target.getTargets` reports that
   very id. (`Target.getBrowserContexts` returns `[]` there — the tell: the browser session
   enumerates every Space's targets but owns none of their contexts.) **To open a URL in another
   Space, script a page that already lives in it:** `Target.attachToTarget` on any http(s) target
   whose `browserContextId` matches, then `Runtime.evaluate({expression: "window.open(…)",
   userGesture: true})`. The new tab inherits its opener's profile by construction. Verified
   end-to-end: an artifact that rendered "Page not found" in the personal Space rendered correctly
   when opened this way into the account's own Space.

   Two neighbouring dead ends, so nobody re-walks them: **Dia's binary cannot hand a URL to a
   running Dia at all** — `Dia --profile-directory="Profile 15" <url>` AND the same launch with no
   flag both sit alive 60 s+ and open nothing (the process-singleton relaunch forward that upstream
   Chromium implements does not work here). Only LaunchServices (`open -b company.thebrowser.dia`)
   reaches the live app, and it takes no profile argument — which is exactly why the profile-correct
   link router (`bin/cc-url-open`) has to go through CDP.
6. **When done: UNCHECK the toggle** (see Security — the PRIMARY-path equivalent of `kill`).
   Verify closure, never assume it: `lsof -nP -iTCP -sTCP:LISTEN | grep -i Dia` — a Dia PID on an
   EPHEMERAL `127.0.0.1` port means it's still ON (re-uncheck until that line is gone). Dia's fixed
   native agent-server on `127.0.0.1:54271` is a separate expected listener — ignore it.

**Raw-socket fallback (no MCP):** connect `ws://127.0.0.1:<port>/devtools/browser/` with
**`suppress_origin=True`** — any `Origin` header → `403`. Then scope via
`Target.createTarget({browserContextId})` as above. (`about:blank` reports `complete`
instantly — don't break a navigation wait on it.)

> The repo `.mcp.json` ships only `chrome-devtools` with `--isolated`, which spawns a THROWAWAY
> Chrome and will NOT attach to Dia — so this raw-socket fallback (no MCP) is the zero-config way
> to drive real Dia *this* session. The dia://inspect page shows the connect command for the
> current ephemeral port; treat it as the source of the command, not as something that edits `.mcp.json`.

## Secondary — isolated dedicated Dia profile (launcher)

Use when you want isolation. Tradeoff: a CLEAN profile — warm only for the sites you sign
into in it.

```bash
~/bin/dia-cdp-launch.sh          # launch OR reattach (idempotent); first run seeds a clean profile
~/bin/dia-cdp-launch.sh status   # is OUR Dia on the port? (see caveat)
~/bin/dia-cdp-launch.sh kill     # close the port when done
~/bin/dia-cdp-launch.sh doctor   # health check: profiles, port, locks, LaunchAgent
~/bin/dia-cdp-launch.sh supervise 3600  # foreground launch + auto-kill after TTL
```

> **⚠ LaunchAgent PERMANENTLY DISABLED (2026-07-09):** The keep-warm LaunchAgent at
> `~/Library/LaunchAgents/com.chrisren.dia-cdp.plist.disabled` caused profile corruption and
> GUI registration aborts when loaded from launchd. **Never load it.** Use `supervise` in a
> foreground shell for on-demand automation only.

First launch creates a clean dedicated Dia Agent profile at
`~/Library/Application Support/Dia-Agent` — sign into ONLY the sites the agent needs (they
persist). Onboarding splash auto-suppressed; coexists with your primary Dia.

Caveats (documented — these are NOT reasons to use Chrome):
- The Dia/TBC account does NOT transplant to a fresh `--user-data-dir` → expect a one-time
  interactive sign-in (passkey/magic-link) if you need the Dia account. CDP drives arbitrary
  web targets without it — skip the wizard.
- A second Dia instance is flaky on macOS (shell-launched instances get reaped; the window
  buries behind your primary Dia). If the window won't surface, that's the known issue.
- ⚠️ `:9222` may be held by the Chrome fallback. `status`/`launch` now **identify the owner**
  (`listener_is_dia`): `status` prints `PORT BUSY` and `launch` errors out if `:9222` is held by a
  non-Dia (or non-dedicated-profile) browser. Run `~/bin/dia-cdp-launch.sh status` rather than
  eyeballing the `json/version` build (Dia masquerades as a generic `Chrome/149` UA and Sparkle
  bumps the build every few days). To free a Chrome-held port: `pkill -f "remote-debugging-port=9222"`
  (or set `DIA_CDP_PORT=9223`) — the launcher's `kill` only stops *our dedicated* Dia, by design.
  Manual build hint if ever needed: Dia 1.35.2 = `…7827.115`, Chrome fallback = `…7827.103`.

Attach (this port HAS `/json` discovery):
- `chrome-devtools-dia --browserUrl http://127.0.0.1:9222` — a LOCAL `.mcp.json` entry that
  may be ABSENT in a given checkout; confirm or add it. The default `chrome-devtools`
  (`--isolated`) server spawns a throwaway Chrome and will NOT attach to this endpoint.
- `agent-browser --cdp 9222 snapshot -i` — fast, zero-code, usable this session.
- puppeteer-core `puppeteer.connect({ browserURL: 'http://127.0.0.1:9222', defaultViewport: null })`
  → `browser.targets()` (not `browser.pages()`).

To clone your full personal profile (warm everywhere, large cookie blast radius —
**DISCOURAGED**): `DIA_SEED_FROM_DEFAULT=1 ~/bin/dia-cdp-launch.sh`.

## Fallback (last resort — NOT the supported path): plain Chrome

Dia is the requirement; use this ONLY if Dia is unavailable (not installed / both Dia paths
blocked). A dedicated-profile Chrome:

```bash
open -n -a "Google Chrome" --args --remote-debugging-port=9222 --remote-allow-origins=* \
  --user-data-dir="$HOME/Library/Application Support/Chrome-Agent" --no-first-run --no-default-browser-check
```

An attach to `:9222` today is THIS fallback unless Dia was explicitly launched there.
**Chrome is the fallback, not the requirement.**

## Security (load-bearing — differs per path)

- **PRIMARY (dia://inspect) exposes the ENTIRE Dia** — every Space, including your personal
  Default/"Personaly" Space (health/financial/email cookies). It is **per-INSTANCE, not
  per-space**: `Target.createTarget({browserContextId})` scopes only your ACTIONS, not the
  exposure — other Spaces' cookies stay readable via `Network.getAllCookies`, which returns the
  ENTIRE persisted cookie STORE for every domain ever visited in that session (not just open-tab
  cookies; closing a tab does not remove them). The port is unauthenticated. **UNCHECK "Allow remote debugging" the moment you stop driving real
  Dia** — this is the load-bearing control. Prefer SECONDARY when you don't want this exposure.
- **SECONDARY (launcher) is scoped to the clean dedicated profile** — only the sites you
  deliberately logged into (minimal blast radius). Still unauthenticated on `:9222`: run
  `~/bin/dia-cdp-launch.sh kill` when done; never `DIA_SEED_FROM_DEFAULT=1` for anything
  sensitive; don't run it 24/7. **Never load the LaunchAgent** — it is permanently disabled
  (Jul 9 2026 incident: profile wipe, GUI abort from background launch).
- **Personal multi-Space profile is sacred** — daily browsing uses Dock/Spotlight launch only.
  Never use `DIA_SEED_FROM_DEFAULT=1` or `--onboarding-skip-wizard` on the personal profile.

Bind is loopback (`127.0.0.1`) by default; `--remote-allow-origins=*` only relaxes the
Origin/CSRF check — it does NOT widen the bind. **24/7 LaunchAgent daemonization is FORBIDDEN**
(plist disabled Jul 9 2026 — see `com.chrisren.dia-cdp.plist.disabled`). Use `supervise` instead.

## Hard facts (don't relearn these)

- **[SECONDARY only]** Non-default `--user-data-dir` is mandatory — Chrome-136+ blocks
  remote-debugging on the default profile; Dia inherits it. The launcher uses the dedicated
  dir. (PRIMARY needs none — it attaches to your already-running Dia.)
- **[SECONDARY only]** `--remote-allow-origins` — **CORRECTED 2026-06-29:** it CAN be scoped to
  `http://127.0.0.1:9222` (launcher default now). On Chromium 149 the no-Origin agent clients
  (chrome-devtools-mcp `--browserUrl`, agent-browser, raw CDP) all connect under a scoped allowlist,
  and a localhost-served web page's Origin is then rejected (defense-in-depth `*` lacked). `*` is the
  fallback (`DIA_ALLOW_ORIGINS=*`). Scoping addresses only web-page Origins, NOT same-user local
  processes → still compensate with kill-when-done. (PRIMARY's port is exposed by Dia's toggle, not a CLI flag.)
- **[SECONDARY only]** DNS-rebinding from the public web is blocked by Chromium's Host-header
  validation (bug 813540): WS upgrades to `:9222` require `Host: localhost`/IP regardless of Origin.
  Residual risk: a page served from `localhost` (e.g. `http://localhost:3000`) opened in the agent
  profile CAN reach `ws://localhost:9222` — avoid untrusted local servers in the agent profile
  while the port is live.
- **[PRIMARY only]** Ephemeral, WS-only port — `/json/version` 404s; use the `ws://` URL from
  the page; the port changes when you cycle the toggle.
- **[PRIMARY only]** Dia writes `DevToolsActivePort` to
  `~/Library/Application Support/Dia/User Data/DevToolsActivePort` while the toggle is ON (line 1 =
  port, line 2 = `/devtools/browser/<uuid>`); absent when OFF. `--autoConnect --userDataDir` reads
  it; `--wsEndpoint ws://127.0.0.1:<port>/devtools/browser/<id>` derived from it is an equivalent
  explicit alternative.
- **[PRIMARY only]** The ephemeral port's `403` on any `Origin` header is a SECURITY property, not
  just a quirk: browser JS always sends `Origin`, so no Dia tab (even a compromised one) can attach
  — only native clients that suppress `Origin` can. (The SECONDARY `:9222` port with
  `--remote-allow-origins=*` is NOT immune.)
- **Headed only** — `--headless` breaks Dia's native window layer (both paths).
- **`webdriver === false`** holds because `--enable-automation` is never passed (raw CDP attach).

## Troubleshooting

| Symptom | Path | Fix |
|---|---|---|
| Connection hangs after connect / ws:// | PRIMARY | Approve the stacked Dia permission dialog(s) in the Dia window — they queue silently and block the handshake. |
| `403` on ws:// connect | PRIMARY | You sent an `Origin` header — suppress it (`suppress_origin=True`). |
| Port not responding after toggle | PRIMARY | Toggle off/on in `dia://inspect`; the port is ephemeral. The FIRST connect right after an off→on cycle goes through with NO consent prompt (verified 2026-06-17; re-verify per Dia update) — do the whole job in ONE persistent connection per cycle. With `--autoConnect --userDataDir`, 2nd+ reconnects re-pop consent — approve each. A new CC session is only needed if the MCP tools are absent. |
| MCP tools not in tool list | PRIMARY / SECONDARY | Start a NEW Claude Code session while the port is up; MCP loads at session start. Else use `agent-browser --cdp <port>` / a raw CDP client. |
| `status` says PORT BUSY (non-Dia owner on :9222) | SECONDARY | `:9222` is the Chrome fallback — free it with `pkill -f "remote-debugging-port=9222"` (or `DIA_CDP_PORT=9223`); the launcher's `kill` only stops *our* Dia, by design — then relaunch. |
| Port down / MCP "disconnected" | SECONDARY | `~/bin/dia-cdp-launch.sh` (relaunch); the MCP server has no auto-reconnect. |
| `agent-browser --cdp` hangs | SECONDARY | macOS bug #1193 on some builds — `pkill -f agent-browser`, retry, or use a raw CDP client. |
| Onboarding splash | SECONDARY | cold profile — re-run the launcher (sets `hasPresentedOnboardingIntro`). Harmless, not a CDP blocker. |
| Site not logged in | SECONDARY | clean profile by design — log in once in the agent window; it persists. |
| Neither Dia path works (Dia not installed / both blocked) | FALLBACK | Chrome-Agent is the labeled fallback — see § Fallback. Chrome is the fallback, not the requirement. |

## Verify the connection (optional)

- **PRIMARY:** after connecting and approving consent, call `Target.getTargets()` — you should
  see your real tabs across Spaces. Identify the target Space's `browserContextId`, then
  `Target.createTarget({ url, browserContextId })` to open a tab in that Space.
- **SECONDARY:** `~/bin/dia-cdp-launch.sh status`; then `agent-browser --cdp 9222 snapshot -i`
  returns an a11y tree in <10s and `navigator.webdriver === false`. After you've logged a
  site in, that site shows as authenticated.
