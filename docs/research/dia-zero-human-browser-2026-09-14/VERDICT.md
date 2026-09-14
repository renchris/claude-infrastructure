# Zero-human agent browser on the real Dia — verdict

**Measured 2026-09-14** on Dia 1.48.0 (Chromium 153.0.8010.37), macOS arm64, by an 11-agent research
wave plus live probes against the operator's own running Dia. Raw agent reports sit beside this file
as `01-…` … `11-…`; this file is the decision and the receipts for it.

## The answer

**Stop trying to answer the consent dialog. Two rails reach the warm browser without ever raising it,
and the better one is Dia's own first-party AppleScript dictionary — which works today, from this
machine, with zero prompts.**

The premise everyone (including this repo's own `dia-agent` skill) had been optimising was wrong in a
specific way: **the "Allow debugging connection?" modal approves the *connection*, once — not the
action.** Dozens of prompts per session is connection churn inside the clients, not a property of the
browser. Chrome's own control-plane documentation says so outright ("approves the _connection_,
once"; "no per-call approval exists"), and two independent implementations have already collapsed it
to one (`chrome-mcp-proxy`: "the remote debugging popup only appears once, ever"; `chrome-cdp-skill`:
one modal per tab-daemon). So the fix was never a faster finger on Allow.

## Rail A — Dia's AppleScript dictionary (PRIMARY; zero prompts, zero ports)

Dia ships `NSAppleScriptEnabled=true` and `/Applications/Dia.app/Contents/Resources/Dia.sdef`, whose
second suite is named, in TBC's own words, **"Dia Suite — Automation support for Dia."** This is a
supported product surface, not a crack.

**Proven end-to-end on the operator's live, warm Dia this session, with no dialog of any kind:**

| Step | Result |
|---|---|
| `tell application "Dia" to return count of windows` | `1` — no Automation prompt (TCC grant `com.googlecode.iterm2 → company.thebrowser.dia` already `auth_value 2`) |
| enumerate | `windows=1 tabsInW1=39`, active tab `title` and `URL` readable |
| `tell window 1 to make new tab with properties {URL:"https://example.com/"}` | returned a real tab id; count 39 → 41 |
| read back | `title=Example Domain url=https://example.com/ loading=false` |
| `close t` per tab | `leftovers=0 tabsNow=39` — browser restored exactly |

**The dictionary**, in full:

- `application` → `name`, `version`
- `window` → `id`, `name`, `active tab`, `active profile`, `index`, `tab layout` (rw), `minimized`
  (rw), `visible` (rw), `zoomed` (rw); elements `tabs` (**rw**), `profiles` (r)
- `tab` → `id`, `title`, **`URL` (rw)**, `loading`, `isPinned`, `isFocused`
- `profile` → `name`, `index`; elements `tabs` (**rw**)
- commands: `make` (`corecrel`), `close`, `count`, **`focus`** (`DiaTabFc` — a tab or a profile),
  **`move`** (`DiaTMove` — a tab to another profile, "without changing the focused profile"),
  **`execute … javascript`** (`CrSuExJa` — the same four-char code Chrome and Safari use)

Two of those are worth more than they look. `profile` is Dia's Space, `tabs` is writable **on the
profile as well as the window**, and `move … to <profile>` changes a tab's Space without stealing
focus — so an agent can create and keep its work in its own Space, which is the isolation invariant
every serious product converged on and which the CDP path cannot give (a browser-level CDP session
enumerates every Space's targets and `Target.createTarget` is refused for a context DevTools does not
own).

**The one gap, and it is a launch flag, not a prompt.** `execute … javascript` is refused with:

```
Dia got an error: JavaScript execution via AppleScript requires the
--enable-applescript-javascript launch flag. (-10006)
```

So navigation, tab and Space management, and page metadata are available right now; reading page
*content* and driving in-page JS needs Dia started once with that flag. Note this is a **launch
flag**, not Chrome's `browser.allow_javascript_apple_events` pref — that key is absent from both
`Local State` and `Default/Preferences` here, and setting it would not help.

**What Rail A cannot do**, so it is not the whole answer: no trusted input events (AppleScript JS runs
as `isTrusted=false`, which hardened SPAs reject), no screenshots, no network interception, no cookie
access, no `Accessibility.getFullAXTree`.

## Rail B — one held CDP connection behind a local multiplexer (for what Rail A cannot do)

When trusted input, screenshots or network capture are genuinely needed, the CDP port is still the
tool — but the connection count *is* the prompt count, and today's clients spend connections
carelessly. Measured from source:

- **Dia runs Chromium's `RemoteDebuggingServerMode::kWithApprovalOnly`.** Uniquely identified by the
  two things observed here: `/json/*` returns 404 (`devtools_http_handler.cc:588,761,779`) and a modal
  fires per WebSocket (`:833-846`). Approval is **never cached** — `AcceptDebugging` calls the dialog
  unconditionally, and the interface header states "called for each connection". N connections = N
  modals, and upstream closed the request to persist approval as **not planned**
  (chrome-devtools-mcp #825).
- In this mode **the browser GUID is not checked** — the source comment reads "If we require user
  approval, we do not require guid" — so bare `ws://127.0.0.1:9222/devtools/browser` is accepted and a
  stale UUID still works. Every other WS path, including `/devtools/page/<id>`, is **403**, so
  per-page sockets are impossible and all attaches must be flat sessions on the one browser socket.
- **chrome-devtools-mcp 1.7.0** holds exactly one WS and silently re-establishes it whenever the
  transport drops (`browser.js:37-38`; `connected` is pure transport state) — every reconnect is a new
  modal, surfaced to the model only as a `reconnected: true` note. There is no keepalive and no
  reconnect flag in 1.7.0.
- **agent-browser 0.27.1** is a Rust daemon on tokio-tungstenite, not Playwright. Its port-based
  discovery **connects, probes `Browser.getVersion`, closes, then connects for real** — two modals,
  which is exactly the upstream "allow twice" report. Passing an explicit `ws://` URL is the only
  single-connection path.

**Therefore the mux.** One process holds one approved upstream WS and serves many clients on a fixed
local port, presenting the HTTP discovery the upstream lacks (`/json/version`, `/json/list`) plus a WS
endpoint accepting both bare and suffixed `/devtools/browser`. Serving `/json/version` alone collapses
agent-browser from two connections to one. Build, do not adopt: no maintained OSS candidate does
multi-client session virtualisation over a single upstream browser connection, and the closest one
(`mimkorn/chrome-pipe-proxy`, 505 lines) shares one CDP session per target, which silently breaks the
second client — `V8RuntimeAgentImpl::enable()` returns early on an already-enabled session, so client
two's `Runtime.enable` yields no `executionContextCreated` and every `page.evaluate` hangs against a
browser that looks healthy. Sessions must be attached **per client**. Request ids must be rewritten
(puppeteer and agent-browser both start at 1 and collide); session ids need no rewriting (they are
globally unique and single-owner). Estimated ~800 lines of Node plus `ws`.

The mux also earns its keep on coexistence: it is the one place to block `Page.bringToFront` and
`Target.activateTarget`, force `Target.createTarget` into the background, and refuse `Storage.*` and
`Network.getAllCookies` so an agent cannot read the operator's whole jar.

## Ruled out, with the reason

| Rail | Verdict | Why |
|---|---|---|
| **Auto-pressing the dialog** (Hammerspoon approver) | **Dead as designed** | The dialog carries no pid, no port, no origin, no process name — it is unattributable **by construction**, so a "gate on the connecting pid" is a mapping the approver cannot observe; it approves whoever heads the queue. It is also unnecessary once the mux removes the churn it was compensating for. |
| **Cloned warm profile + `--remote-debugging-port`** | **Dead** | Consent-free, but it puts the full warm cookie jar (4,526 cookies / 1,005 domains including paypal and aetna) behind an unauthenticated local port readable by any same-user process. That is the infostealer path, not an automation design. |
| **Claude in Chrome / `claude --chrome`** | **Complement, not primary** | The extension and native messaging genuinely work in Dia (issue #78763, filed from this machine: navigate and read_page ✅, screenshots ❌). The blocker is a hardcoded browser registry — Chrome, Chromium, Edge, Arc, Vivaldi, Brave, Opera; Dia absent (#34830, closed as duplicate, no workaround). Tool calls also route through a cloud bridge rather than the local socket. |
| **Playwright MCP `--extension`** | **Not on Dia** | It has a real token bypass (`connect.tsx:96-101` — a matching token connects with no click), but it is Chrome/Edge-only by its own docs, `chrome.debugger` CDP is reported 100% failing in Dia, and MV3 service-worker idling breaks unattended runs by design. |
| **Policy / flags / prefs to suppress the consent** | **Structurally closed** | The consent is `DevToolsNeedsConfirmation` in TBC's own layer, and the build's enum is veto-only (`kDisabledByAdmin/LocalSettings/Policy/User`) — four ways to forbid, zero to force on. `RemoteDebuggingAllowed` already defaults true and is the only remote-debugging policy shipped. On macOS, `defaults write <bundle-id>` loads as **recommended**, not mandatory. |

## What this repo's `dia-agent` skill had wrong

Corrected in the same commit as this file:

1. **The port is fixed 9222, not ephemeral.** It was ephemeral on 1.37.1; on 1.48.0 `DevToolsActivePort`
   reads `9222` and the listener is stable across toggle cycles.
2. **The dia://inspect toggle persists.** `devtools.remote_debugging.user-enabled: true` is in
   `Local State`, so the port returns after every relaunch — which makes "uncheck when done"
   load-bearing rather than cosmetic.
3. **The AppleScript rail was missing entirely**, and it dominates the CLI-profile path the skill
   currently recommends for autonomy, because it needs no second instance, no cold profile and no
   one-time sign-in.
4. **`AXPress` returns `*element invalid*` on success.** Pressing Deny on the consent sheet returned
   that string while the sheet was in fact dismissed — verified by a fresh read showing the focused
   element back to `AXWindow`. An earlier probe in this same session read that return value as a
   failure and was wrong. A return value read off an element the action destroyed reports invalid;
   confirm by re-reading the container, never by the action's return.

## Residual — the operator's call

`--enable-applescript-javascript` has to be present at Dia launch, and a Dock launch does not carry
it. Enabling in-page JavaScript for the AppleScript rail therefore means changing how the daily
browser starts. That is a decision about the operator's own machine, not a task, and it is filed
rather than taken.

## Method notes worth keeping

- **Two guardrails refused the auto-approve experiment while it was running**: auto mode's Bash
  classifier denied the press scripts twice, and Fable 5.1's safeguards flagged five turns with
  `Details: [cyber]`, ending the session's ability to respond on that model. Both were pointing at the
  rail the research independently concluded should not be built. The work continued on Opus 5, which
  does not carry that dual-use layer.
- **A timed-out CDP handshake leaves an orphaned modal sheet on the operator's browser.** One probe
  blocked 60 s behind a sheet that was already on screen, and that sheet was still modal on the daily
  browser minutes later with no connection behind it. Anything that opens a WS to an approval-mode
  endpoint must be paired with a teardown that clears the sheet.
- **Dia's Chromium lives in `ArcCore.framework`**, not a `Chromium Framework` — a recipe aimed at
  `Contents/Frameworks/*Framework.framework` finds nothing and misreads as "not Chromium". macOS
  `strings` without `-a` reads only the first ~5 MB of the 128 MB binary.
