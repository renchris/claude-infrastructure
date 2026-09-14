# 05 — AX auto-approve of Dia's "Allow debugging connection?" dialog

Measured 2026-09-14 on macOS 15.7.9 (24G830), Hammerspoon 1.1.1 (build Feb 26 2026), Dia 1.48.0
(`company.thebrowser.dia`, main pid 1902, listening `127.0.0.1:9222 (LISTEN)` on fd 819).
All Dia probes read-only. No press, no keystroke, no :9222 connection.

---

## 0. Three headline corrections to the brief's premises — read these first

### 0.1 🚨 The two "button AX descriptions" are TRANSLATOR COMMENTS, not AXDescriptions. Conviction 95%.

The brief states the Allow/Deny buttons carry AX descriptions
`"DevTools connection dialog allow button"` / `"DevTools connection dialog deny button"`.
A recipe keyed on those will match nothing, ever.

Evidence chain, three independent arms:

1. **Literal-pool adjacency is the Swift `String(localized:comment:)` layout.** Dumping
   `strings -a -t d /Applications/Dia.app/Contents/MacOS/Dia` around offset 97850688 gives a strict
   value→comment interleave:

   ```
   97850688 Allow debugging connection?
   97850720 DevTools connection dialog title
   97850768 An application is requesting access to debug this browser. This gives it full access…
   97850903 Only allow this if you trust the source of this connection.
   97850976 DevTools connection dialog message
   97851024 DevTools connection dialog deny button
   97851072 DevTools connection dialog allow button
   ```

   The neighbouring block is unambiguous about which side is which —
   `Dia Artifact import-conflict dialog button: open the existing copy` is a sentence addressed to a
   translator, not a label a screen reader would speak.

2. **POSITIVE CONTROL against the live AX tree.** The same binary, at offset 97626208, holds
   `Title for the application's 'About' menu item, including the app's name`. Dia's menu bar **is**
   AX-readable right now (`ax:attributeValue("AXMenuBar")` → 11 children). The live element reads:

   ```
   item[1] title=About Dia   desc=nil   role=AXMenuItem
   ```

   The comment string is neither the title nor the `AXDescription` (which is `nil`). Strings of this
   shape in this binary are comments. This is the load-bearing arm: it tests the mechanism on an
   element I can read, rather than reasoning about one I cannot.

3. **No shipped app sets an AXDescription that VoiceOver would speak as "DevTools connection dialog
   allow button, button".** Dia ships **zero** `.strings`/`.loctable`/`.xcstrings` resources
   (`find /Applications/Dia.app/Contents/Resources -name '*.strings' -o -name '*.loctable'` → empty),
   and `grep -rl "Allow debugging connection" /Applications/Dia.app/` → **no resource file**. The
   pair exists only in `__TEXT,__cstring`, exactly where Swift emits localization comments.

**Use instead**: `AXDefaultButton` on the dialog window (§3), with the *value* strings
`"Allow debugging connection?"` and `"Only allow this if you trust the source of this connection."`
as the identity check. Falsifier for the lead's live run: when the dialog is up, dump every
descendant's `AXDescription` and confirm the comment strings are absent.

### 0.2 `AXWindows == 0` is a Chromium-family property, NOT a Dia bug — and `AXEnhancedUserInterface` does not fix it.

| App | bundle id | `AXWindows` | `app:allWindows()` | `AXFocusedWindow` | FW subrole |
|---|---|---|---|---|---|
| Finder | com.apple.finder | **1** | 1 | yes | AXStandardWindow |
| kitty | net.kovidgoyal.kitty | **2** | 2 | yes | AXStandardWindow |
| **Dia** | company.thebrowser.dia | **0** | 0 | yes | AXStandardWindow |
| **Chrome** | com.google.Chrome | **0** | 0 | yes | AXStandardWindow |
| **Cursor** (Electron) | com.todesktop.230313mzl4w4u92 | **0** | 0 | yes | AXStandardWindow |

All three Chromium/Electron apps had a real, visible, focused `AXStandardWindow` and reported
`AXWindows = 0`. `attributeValueCount("AXWindows")` (a separate AX call) also returned 0, and the
lead's independent `osascript` System Events probe agrees — so the instrument is corroborated twice.

**Lever test, run on Chrome (not Dia, to keep Dia read-only):**

```
BEFORE  AXEUI=false AXWindows=0
set     -> ret=nil  err="Function or method not implemented"
AFTER   AXEUI=true  AXWindows=0     (+1.2 s)
RESTORED AXEUI=false
```

Two findings:
- **`setAttributeValue` returns `nil` + `"Function or method not implemented"` and the set STILL
  LANDS.** Read-back showed `true`. That fully explains the lead's "setting
  `AXEnhancedUserInterface` returned nil" — the return is a red herring; always read back.
  (`isAttributeSettable("AXEnhancedUserInterface")` → `true` on Dia.)
- **`AXWindows` stayed 0 with `AXEUI=true`.** So the lever is useless here. Caveat: one arm, 1.2 s
  wait; a 5 s re-test wedged the `hs` CLI (see §8 instrument note) so the longer-wait arm is
  unmeasured. It does not matter, because §0.3 gives a route that already works.

**Do NOT set `AXEnhancedUserInterface` on Dia.** Dia's binary carries `isHandlingSendEvent_`
(offset 97626080) immediately beside `AXManualAccessibility` (97626288) and
`AXEnhancedUserInterface` (97626320) inside `_TtC15BoostBrowserMac10BrowserApp` — that symbol is
the well-known AppKit workaround for the window-drag breakage `AXEnhancedUserInterface` induces.
Dia also ships `ArcAccessibilityObserver` / `ADK.AccessibilityObserver`,
`accessibilityMode`, `accessibilityModeChangedCallbacks`, `accessibilityModeChanged:` — i.e. it
actively reacts to the flag. Flipping it buys nothing measured and risks degrading the operator's
browser.

### 0.3 The enumeration problem is already solved — by three routes that work today.

| Route | Measured on Dia | Verdict |
|---|---|---|
| `appElement:attributeValue("AXFocusedWindow")` | resolves; 18 children; full attr set incl. `AXDefaultButton`, `AXCancelButton`, `AXModal`, `AXSubrole`, `AXIdentifier` | **PRIMARY** |
| `app:mainWindow()` / `app:focusedWindow()` (hs wrappers over AXMainWindow/AXFocusedWindow) | both return `Personaly: Microsoft 365…` | works |
| **`hs.window.filter`** | `hs.window.filter.new(false):setAppFilter("Dia",{visible=true}):getWindows()` → **1 window** (`id=80329`, `AXWindow/AXStandardWindow`, `std=true`, `vis=true`) | **works — contradicts `allWindows()==0`** |
| `hs.axuielement` → `hs.window` round trip | `axFW:asHSWindow()` → `id=80329` | works |
| `hs.window.allWindows()` / `app:allWindows()` / `hs.window.find("Personaly")` | 2 / 0 / **nil** | blind to Dia |
| `systemWideElement():attributeValue("AXFocusedUIElement")` | resolves (→ kitty's `AXTextArea`, with working `AXWindow` and `AXTopLevelUIElement`) | **BACKSTOP** |
| `hs.application.watcher` | app-level only; no window/dialog event | not usable |

🚨 **`hs.window.filter.allowedWindowRoles` (measured) = `{AXDialog=true, AXStandardWindow=true,
AXSystemDialog=true}`.** `AXSheet` is **absent**. So `hs.window.filter` will see the dialog if it is
a panel/dialog window and will be **structurally blind if it is a sheet**. Do not make it the only
detector.

---

## 1. AX findings table (measured, Dia pid 1902)

| Element / attribute | Value | Note |
|---|---|---|
| app `AXRole` / `AXTitle` | `AXApplication` / `Dia` | — |
| app attribute names | `AXFunctionRowTopLevelElements, AXFrame, AXChildren, AXFocusedUIElement, AXFrontmost, AXRole, AXExtrasMenuBar, AXMainWindow, AXFocusedWindow, AXTitle, AXChildrenInNavigationOrder, AXEnhancedUserInterface, AXPreferredLanguage, AXRoleDescription, AXHidden, AXMenuBar, AXWindows, AXSize, AXPosition` | no `AXManualAccessibility` in the list, but `attributeValue` on it returns `nil` rather than erroring |
| app `actionNames()` | **empty** | app element has no actions |
| app `AXChildren` | **1** — only `AXMenuBar` | this is the lead's `osascript` observation, reproduced via AX |
| app `AXWindows` | `{}` (count 0, `attributeValueCount` 0) | §0.2 |
| app `AXEnhancedUserInterface` | `false`, `isAttributeSettable` → `true` | do not set (§0.2) |
| app `AXManualAccessibility` | `nil`, `isAttributeSettable` → `nil` | Electron-only lever; absent here |
| `AXFocusedWindow` | `AXWindow` / `AXStandardWindow`, title `Personaly: Microsoft 365…` | works |
| FW `AXIdentifier` | `bigBrowserWindow_9590B106-F092-4625-A96F-D9BBE4F26E8E` | **browser windows carry a `bigBrowserWindow_<UUID>` identifier — a free negative discriminator: the dialog will not have it** |
| FW attribute names | includes `AXDefaultButton`, `AXCancelButton`, `AXModal`, `AXSubrole`, `AXIdentifier`, `AXSections`, `AXProxy`, `AXTitleUIElement` | |
| FW `AXModal` | `false` | discriminator: the dialog should read `true` |
| FW `AXDefaultButton` | `nil` | attribute present, unset on a browser window — so a non-nil read is itself a signal |
| FW **`AXSheets` attribute** | **absent from the attribute-name list** | also absent on Finder, kitty, Chrome, Cursor — so this is normal AppKit (added when a sheet attaches) and cannot be pre-verified. **Named uncertainty.** |
| `AXPress` availability | Finder's `AXCloseButton`: `role=AXButton actions=AXPress` | `performAction("AXPress")` is the correct verb for AppKit buttons |
| observer creation | `hs.axuielement.observer.new(1902)` → OK, `isRunning()` → true | |
| `addWatcher` on the **app element** | `AXWindowCreated, AXSheetCreated, AXFocusedWindowChanged, AXMainWindowChanged, AXUIElementDestroyed, AXCreated, AXApplicationActivated, AXDrawerCreated, AXFocusedUIElementChanged, AXValueChanged, AXTitleChanged, AXLayoutChanged, AXAnnouncementRequested, AXMenuOpened` — **all 14 registered OK** | registration ≠ firing (§8) |
| element methods present | `elementSearch, buildTree, matchesCriteria, allDescendantElements, childrenWithRole, performAction, actionNames, attributeNames, isAttributeSettable, attributeValueCount, asHSWindow, asHSApplication, path, pid` | |
| `elementSearch` | **ASYNC** — returns a searchObject; `criteria` must be a function from `hs.axuielement.searchCriteriaFunction`, a plain table raises `criteria must be a function, if specified` | **do not use it on the press path**; use `childrenWithRole` / a bounded manual walk |
| `hs.eventtap.isSecureInputEnabled` | **DOES NOT EXIST** in HS 1.1.1 | the keystroke fallback cannot even self-check whether it will be swallowed (§6) |
| `hs.caffeinate.watcher` events | `screensDidLock=10, screensDidUnlock=11, screensDidSleep=3, screensDidWake=4, screensaverDidStart=7, sessionDidResignActive=5, …` | the lock gate (§5) |
| Dia argv (pid 1902) | `/Applications/Dia.app/Contents/MacOS/Dia` — **no `--remote-debugging-port`** | the port came from the in-app `dia://inspect#remote-debugging` toggle, so the consent dialog is Arc's own gate layered on that toggle, not a Chromium built-in |

**Dialog implementation shape (from the binary).** `ArcDevToolsConnectionDialog` is an **Objective-C**
class (`So27ArcDevToolsConnectionDialogC` — Swift's `So` prefix = imported ObjC class; `C` = class),
handed to a delegate method whose ObjC type encoding `v24@0:8@"ArcDevToolsConnectionDialog"16` sits
in the `ArcBrowserApplicationDelegate` / `ArcNotificationCenter` / `ArcAccessibilityObserver` block
at offset 97640400 — i.e. it is an ArcCore (AppKit) object, not a SwiftUI view. `NSAlert` metadata
(`So7NSAlertCSgXw`), `beginSheetModalForWindow:completionHandler:` and `runModal` are all present in
the binary. **But** Dia also ships a `BoostBrowser_Dialog.bundle`, so a custom dialog surface exists
too. The three candidate shapes are therefore all live and §3 covers all three.

---

## 2. Gating design

**Threat model, stated honestly up front.** This gate is a **correctness** boundary, not a security
boundary. Any process running as this user can read the token file's format, write a token, and be
approved. The actual security boundary is (a) :9222 is bound to loopback only —
`lsof` shows `TCP 127.0.0.1:9222 (LISTEN)`, not `*:9222` — and (b) the dialog exists at all. The
gate's job is to stop *accidental* and *non-cooperating* clients (a stray `curl`, a second MCP
server, a page's own fetch) from being auto-approved, and to make every approval auditable.

### 2.1 Peer→pid mapping via `lsof` — measured, and it works

An established loopback connection appears as **two rows, each with its own pid**, joined by the
reversed port pair:

```
node    4719 chrisren 19u  IPv4 … TCP 127.0.0.1:58575->127.0.0.1:58571 (ESTABLISHED)
Google  4762 chrisren 102u IPv4 … TCP 127.0.0.1:58571->127.0.0.1:58575 (ESTABLISHED)
```

So the client pid is directly readable. Parse the machine-readable form, **not** the columns:

```
lsof -nP -iTCP:9222 -FpcnT
p1902
cDia
f819
n127.0.0.1:9222
TST=LISTEN
TQR=0
TQS=0
```

`-F` emits `p`/`c` once per process then `f`/`n`/`T` per file, so the parser must carry the current
pid forward. `TST=` gives the TCP state. Runs as uid 501 with **no sudo**. `-sTCP:ESTABLISHED` and
`-sTCP:SYN_SENT` are both accepted (rc 0).

**TCP-state note:** Dia raises the dialog on the DevTools *WebSocket upgrade*, i.e. after the HTTP
request has been received — so the connection is already `ESTABLISHED` when the dialog appears.
SYN-state handling is unnecessary; filter on `ESTABLISHED`.

`nettop` (`/usr/bin/nettop`, no sudo) was checked and is **worse**: it keys rows on
`process.pid` with no peer-port field, so for a loopback pair it cannot join the two ends. Ruled out.

### 2.2 The admission predicate — all five must hold

1. **Exactly one non-Dia peer** on :9222 in state `ESTABLISHED`. Two or more ⇒ the dialog is
   unattributable (§4) ⇒ refuse.
2. That peer's pid ∈ the authorized set. Resolve the set from the daemon's own process tree
   (`daemon pid` + `pgrep -P` descendants), not a single pid — a multiplexer that forks per client
   would otherwise be refused.
3. **Intent token present and valid.** 🚨 **Do not use file mtime for freshness.** The lead's own
   `hsc/clock.lua:11-17` records the measurement: `hs.fs.attributes` truncates all four timestamps
   to **whole seconds** (python reads `1789059550.804981` where Hammerspoon reads `1789059550`). A
   sub-second freshness window is unimplementable that way. Instead the daemon writes the stamp
   **inside** the file and Hammerspoon compares it to `hs.timer.secondsSinceEpoch()`:

   ```
   {"pid":12345,"nonce":"<32 hex>","wall":1789059550.804981,"ttl":15}
   ```

4. **Token is single-use.** `os.remove` it *before* the press, not after — a crash between press and
   cleanup must not leave a live token.
5. **Not locked / not screensaved** (§5), and the token's `pid` still exists
   (`hs.application.applicationForPID` or `kill -0`).

Any failure ⇒ **do nothing to the dialog** (leaving it up is the safe state: the operator can answer
it, and Dia's own timeout/Deny path is unchanged) + `log.emit("devtools_refuse", {...})` +
`hs.notify` so the refusal is visible rather than silent.

---

## 3. Recipe (Hammerspoon Lua) — `hsc/devtools_consent.lua`

Matches the repo idiom: module-scope state, no globals, `start/stop/stats`, `hsc.log` + `hsc.clock`
(per `init.lua:15-30` and `hsc/clock.lua`). Observer-driven with a 400 ms backstop (above the 250 ms
floor).

```lua
-- hsc/devtools_consent.lua — auto-approve ONLY our own multiplexer's DevTools consent dialog.
--
-- Detection is observer-first with a coarse backstop poll.  Identity is the dialog's own TITLE
-- STRING, never an AXDescription: the strings "DevTools connection dialog allow button" and
-- "... deny button" found in Dia's binary are Swift String(localized:comment:) COMMENTS and are
-- not exposed at runtime (proved against Dia's live menu bar, whose AXDescription is nil while the
-- binary holds "Title for the application's 'About' menu item...").  The press target is
-- AXDefaultButton, which is title- and locale-independent.
local log   = require("hsc.log")
local clock = require("hsc.clock")

local M = {}

local BUNDLE      = "company.thebrowser.dia"
local PORT        = 9222
local TITLE       = "Allow debugging connection?"
local MSG_FRAG    = "Only allow this if you trust the source of this connection."
local TOKEN_PATH  = os.getenv("HOME") .. "/.local/state/dia-cdp/intent.json"
local BACKSTOP_MS = 400          -- floor is 250 ms; 400 keeps idle cost near zero
local SETTLE_MS   = 120          -- let the window finish becoming key before we read buttons
local MAX_ROUNDS  = 3            -- stacked dialogs: Dia queues up to 3

local st = { obs = nil, appw = nil, timer = nil, lock = nil, locked = false,
             pid = nil, busy = false,
             n_seen = 0, n_pressed = 0, n_refused = 0, last = nil }

-- ── identity ────────────────────────────────────────────────────────────────────────────────────
-- A candidate is our dialog iff its title matches, OR a static-text descendant carries MSG_FRAG.
-- Negative discriminator, measured: every Dia BROWSER window carries
-- AXIdentifier = "bigBrowserWindow_<UUID>".  The dialog will not.
local function isOurDialog(el)
  if not el then return false end
  local ok, role = pcall(function() return el:attributeValue("AXRole") end)
  if not ok or not role then return false end                      -- element already invalid
  local id = el:attributeValue("AXIdentifier")
  if type(id) == "string" and id:match("^bigBrowserWindow_") then return false end
  if el:attributeValue("AXTitle") == TITLE then return true end
  -- bounded walk: an alert is shallow, so depth 4 is generous and cannot wander into web content
  local function walk(e, d)
    if d > 4 then return false end
    for _, c in ipairs(e:attributeValue("AXChildren") or {}) do
      local v = c:attributeValue("AXValue")
      if type(v) == "string" and v:find(MSG_FRAG, 1, true) then return true end
      if c:attributeValue("AXTitle") == TITLE then return true end
      if walk(c, d + 1) then return true end
    end
    return false
  end
  return walk(el, 1)
end

-- Collect every candidate container: the focused window, its sheets, the system-wide focused
-- element's window, and hs.window.filter's view.  Covers all three possible dialog shapes
-- (separate AXDialog window · AXSheet on the browser window · overlay inside the browser window).
local function candidates(ax)
  local out, seen = {}, {}
  local function add(e)
    if not e then return end
    local k = tostring(e)
    if not seen[k] then seen[k] = true; out[#out + 1] = e end
  end
  local fw = ax:attributeValue("AXFocusedWindow")
  add(fw)
  if fw then
    for _, s in ipairs(fw:attributeValue("AXSheets") or {}) do add(s) end
    for _, c in ipairs(fw:attributeValue("AXChildren") or {}) do
      local r = c:attributeValue("AXRole")
      if r == "AXSheet" or r == "AXDialog" or r == "AXWindow" then add(c) end
    end
  end
  add(ax:attributeValue("AXMainWindow"))
  for _, w in ipairs(ax:attributeValue("AXWindows") or {}) do add(w) end   -- 0 today; free if fixed
  local sw = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if sw then
    add(sw:attributeValue("AXWindow"))
    add(sw:attributeValue("AXTopLevelUIElement"))
  end
  return out
end

-- ── press target ────────────────────────────────────────────────────────────────────────────────
-- AXDefaultButton first (Allow is the default button, ⏎).  Fall back to a titled AXButton that is
-- NOT the AXCancelButton — never to "the first button", whose order is not contractual.
local function allowButton(dlg)
  local db = dlg:attributeValue("AXDefaultButton")
  if db then return db, "AXDefaultButton" end
  local cancel = dlg:attributeValue("AXCancelButton")
  local cancelKey = cancel and tostring(cancel) or nil
  local best
  local function walk(e, d)
    if d > 4 or best then return end
    for _, c in ipairs(e:attributeValue("AXChildren") or {}) do
      if c:attributeValue("AXRole") == "AXButton" and tostring(c) ~= cancelKey then
        local t = c:attributeValue("AXTitle")
        if type(t) == "string" and t ~= "" and not t:lower():find("den") and not t:lower():find("cancel") then
          best = c; return
        end
      end
      walk(c, d + 1)
    end
  end
  walk(dlg, 1)
  return best, "titled-button-fallback"
end

-- ── gate ────────────────────────────────────────────────────────────────────────────────────────
-- lsof -F: p/c are per-PROCESS and must be carried forward across the per-FILE f/n/T lines.
local function peersOnPort()
  local out = hs.execute(("/usr/sbin/lsof -nP -iTCP:%d -sTCP:ESTABLISHED -FpcnT 2>/dev/null")
                         :format(PORT)) or ""
  local rows, pid, cmd, name = {}, nil, nil, nil
  for line in out:gmatch("[^\n]+") do
    local tag, val = line:sub(1, 1), line:sub(2)
    if     tag == "p" then pid, name = tonumber(val), nil
    elseif tag == "c" then cmd = val
    elseif tag == "n" then name = val
    elseif tag == "T" then
      if val == "ST=ESTABLISHED" and name and name:find("->", 1, true) then
        local lp, rp = name:match("127%.0%.0%.1:(%d+)%->127%.0%.0%.1:(%d+)")
        if lp then rows[#rows + 1] = { pid = pid, cmd = cmd, lport = tonumber(lp), rport = tonumber(rp) } end
      end
    end
  end
  -- the client is the end whose REMOTE port is 9222; Dia's own row has lport == 9222
  local clients = {}
  for _, r in ipairs(rows) do if r.rport == PORT then clients[#clients + 1] = r end end
  return clients, rows
end

local function authorizedPids(tokenPid)
  local set = { [tokenPid] = true }
  local kids = hs.execute(("/usr/bin/pgrep -P %d 2>/dev/null"):format(tokenPid)) or ""
  for p in kids:gmatch("%d+") do set[tonumber(p)] = true end
  return set
end

-- Token freshness lives INSIDE the file.  hs.fs.attributes truncates mtime to whole seconds
-- (hsc/clock.lua:11-17), so an mtime-based TTL is unimplementable at sub-second resolution.
local function consumeToken()
  local f = io.open(TOKEN_PATH, "r"); if not f then return nil, "no-token" end
  local raw = f:read("*a"); f:close()
  os.remove(TOKEN_PATH)                              -- single-use, consumed BEFORE the press
  local ok, t = pcall(hs.json.decode, raw)
  if not ok or type(t) ~= "table" then return nil, "token-unparseable" end
  if type(t.pid) ~= "number" or type(t.wall) ~= "number" then return nil, "token-malformed" end
  local age = clock.wall() - t.wall
  if age < -2 or age > (t.ttl or 15) then return nil, ("token-stale age=%.2fs"):format(age) end
  if not hs.application.applicationForPID(t.pid) then return nil, "token-pid-dead" end
  return t, nil
end

local function admit()
  if st.locked then return nil, "screen-locked" end
  local t, err = consumeToken(); if not t then return nil, err end
  local clients = peersOnPort()
  if #clients == 0 then return nil, "no-established-peer" end
  if #clients > 1 then return nil, ("ambiguous-%d-peers"):format(#clients) end
  local c = clients[1]
  if not authorizedPids(t.pid)[c.pid] then
    return nil, ("peer-pid-%d(%s)-not-in-token-tree-%d"):format(c.pid, tostring(c.cmd), t.pid)
  end
  return { token = t, peer = c }, nil
end

-- ── the act ─────────────────────────────────────────────────────────────────────────────────────
local function tryOnce()
  local app = hs.application.get(BUNDLE); if not app then return false end
  local ax = hs.axuielement.applicationElement(app); if not ax then return false end
  local dlg
  for _, cand in ipairs(candidates(ax)) do if isOurDialog(cand) then dlg = cand; break end end
  if not dlg then return false end
  st.n_seen = st.n_seen + 1

  local grant, why = admit()
  if not grant then
    st.n_refused = st.n_refused + 1
    st.last = "refused: " .. why
    log.emit("devtools_consent_refuse", { why = why, at = clock.stamp() })
    hs.notify.new({ title = "Dia DevTools consent REFUSED",
                    informativeText = why, withdrawAfter = 0 }):send()
    return true                                     -- handled: deliberately leave the dialog up
  end

  local btn, how = allowButton(dlg)
  if not btn then
    log.emit("devtools_consent_noallow", { at = clock.stamp() })
    return true
  end
  local acts = btn:actionNames() or {}
  local pressable = false
  for _, a in ipairs(acts) do if a == "AXPress" then pressable = true end end
  if not pressable then
    log.emit("devtools_consent_nopress", { actions = table.concat(acts, ","), how = how })
    return true
  end

  local t0 = clock.mono()
  btn:performAction("AXPress")

  -- CONFIRM, two independent arms.  (1) the dialog element goes INVALID: attributeValue on a dead
  -- AXUIElement returns nil/errors.  (2) the peer's ESTABLISHED row survives — a Deny makes Dia
  -- close the socket, so persistence is positive evidence of Allow.
  hs.timer.doAfter(0.35, function()
    local ok, role = pcall(function() return dlg:attributeValue("AXRole") end)
    local gone = (not ok) or (role == nil) or (not isOurDialog(dlg))
    local clients = peersOnPort()
    local still = false
    for _, c in ipairs(clients) do if c.pid == grant.peer.pid then still = true end end
    st.n_pressed = st.n_pressed + 1
    st.last = ("pressed via %s gone=%s peer_up=%s %.0fms"):format(how, tostring(gone), tostring(still),
                                                                  clock.msSince(t0))
    log.emit("devtools_consent_press", { how = how, dialog_gone = gone, peer_still_established = still,
                                         peer_pid = grant.peer.pid, peer_cmd = grant.peer.cmd,
                                         ms = clock.msSince(t0), at = clock.stamp() })
  end)
  return true
end

-- Stacked dialogs: Dia's delegate takes one ArcDevToolsConnectionDialog per call, so they queue.
-- Drain up to MAX_ROUNDS, each with its OWN token — one token may never approve two connections.
local function drain()
  if st.busy then return end
  st.busy = true
  local round = 0
  local function step()
    round = round + 1
    if round > MAX_ROUNDS then st.busy = false; return end
    if tryOnce() then hs.timer.doAfter(SETTLE_MS / 1000, step) else st.busy = false end
  end
  hs.timer.doAfter(SETTLE_MS / 1000, step)
end

-- ── lifecycle ───────────────────────────────────────────────────────────────────────────────────
local function bind(pid)
  if st.obs then st.obs:stop(); st.obs = nil end
  if not pid then st.pid = nil; return end
  local app = hs.application.applicationForPID(pid); if not app then return end
  local ax = hs.axuielement.applicationElement(app); if not ax then return end
  local ok, obs = pcall(hs.axuielement.observer.new, pid)
  if not ok or not obs then log.emit("devtools_consent_obs_fail", { pid = pid }); return end
  obs:callback(function() drain() end)
  -- All 14 of these registered OK on Dia 1.48.0.  windowCreated/sheetCreated/focusedWindowChanged
  -- are posted BY the application element with the new element as the callback's subject, which is
  -- why they are registered here and not on a window (a window registration dies with the window).
  for _, n in ipairs({ "AXWindowCreated", "AXSheetCreated", "AXFocusedWindowChanged",
                       "AXMainWindowChanged", "AXFocusedUIElementChanged", "AXCreated",
                       "AXLayoutChanged", "AXDrawerCreated" }) do
    pcall(function() obs:addWatcher(ax, n) end)
  end
  obs:start()
  st.obs, st.pid = obs, pid
  log.emit("devtools_consent_bound", { pid = pid })
end

function M.start()
  bind((hs.application.get(BUNDLE) or {}).pid and hs.application.get(BUNDLE):pid() or nil)
  -- Dia restarting invalidates the observer's pid; rebind rather than silently going deaf.
  st.appw = hs.application.watcher.new(function(_, ev, app)
    if not app or app:bundleID() ~= BUNDLE then return end
    if ev == hs.application.watcher.launched then bind(app:pid())
    elseif ev == hs.application.watcher.terminated then bind(nil) end
  end); st.appw:start()
  st.lock = hs.caffeinate.watcher.new(function(ev)
    local w = hs.caffeinate.watcher
    if ev == w.screensDidLock or ev == w.screensaverDidStart or ev == w.sessionDidResignActive then
      st.locked = true
    elseif ev == w.screensDidUnlock or ev == w.screensaverDidStop or ev == w.sessionDidBecomeActive then
      st.locked = false
    end
  end); st.lock:start()
  -- BACKSTOP.  Registration is not firing (§8): every addWatcher succeeded, but nothing on this box
  -- has yet OBSERVED windowCreated fire for a Chromium app whose AXWindows is empty.
  st.timer = hs.timer.doEvery(BACKSTOP_MS / 1000, function()
    if st.busy then return end
    local f = io.open(TOKEN_PATH, "r")     -- cheap: no AX traffic unless an intent is pending
    if not f then return end
    f:close(); drain()
  end)
  log.emit("devtools_consent_start", { backstop_ms = BACKSTOP_MS, token = TOKEN_PATH })
  return M
end

function M.stop()
  if st.timer then st.timer:stop(); st.timer = nil end
  if st.appw  then st.appw:stop();  st.appw  = nil end
  if st.lock  then st.lock:stop();  st.lock  = nil end
  if st.obs   then st.obs:stop();   st.obs   = nil end
  log.emit("devtools_consent_stop", st.stats and st.stats() or {})
  return M
end

function M.stats()
  return { pid = st.pid, observing = st.obs ~= nil and st.obs:isRunning() or false,
           locked = st.locked, seen = st.n_seen, pressed = st.n_pressed,
           refused = st.n_refused, last = st.last }
end

return M
```

**Why the backstop is gated on the token file's existence**: idle cost is one `io.open` every 400 ms
and **zero AX round trips** until the daemon actually declares intent. That keeps the poll off Dia's
main thread in the 99.99% case, which matters because an AX read is a synchronous IPC into Dia.

---

## 4. TOCTOU analysis

| # | Race | Severity | Mitigation | Residual |
|---|---|---|---|---|
| T1 | **The dialog is unattributable by construction.** Measured from the binary: the title is `Allow debugging connection?` and the body is `An application is requesting access to debug this browser…` / `Only allow this if you trust the source of this connection.` — **no pid, no port, no origin, no process name anywhere.** So nothing in the dialog binds it to a connection. | **HIGH — unclosable from the AX side** | require **exactly one** non-Dia `ESTABLISHED` peer; refuse on ≥2 | with two near-simultaneous connections the gate refuses rather than guessing. Correct, but a legitimate connect can be refused if anything else is attached. |
| T2 | Peer set changes between the `lsof` read and the `AXPress` | MEDIUM | `lsof` is re-read in the 350 ms post-press confirm; a mismatch is logged as an anomaly | the press has already happened. Detection, not prevention. A pre-press *second* `lsof` read narrows the window to ~5 ms but cannot close it. |
| T3 | Token replayed to approve a *second* connection | MEDIUM | token consumed (`os.remove`) **before** the press; `drain()` demands a fresh token per round | a daemon that writes a token and then crashes leaves the token consumed — correct failure direction (refuse). |
| T4 | Token forged by another local process | **accepted** | none possible | stated in §2 as a design limit, not a gap. Anything running as uid 501 can forge it. The boundary is loopback + the dialog's existence. |
| T5 | `lsof` misses the connection because the state is `SYN_RCVD`/`CLOSE_WAIT` at read time | LOW | the dialog fires on the WebSocket upgrade, after the request is received ⇒ already `ESTABLISHED` | if Dia ever moves the prompt earlier, the gate refuses (`no-established-peer`) — fail-closed, and the log line names it. |
| T6 | Stale `AXUIElement` reference: the dialog is dismissed by the operator between detection and press, and a *new* dialog occupies the same screen position | LOW | the press targets the captured element, not coordinates; a dead element's `performAction` fails rather than hitting a successor | a `hs.eventtap` coordinate click would NOT have this property — one more reason §6 ranks it last. |
| T7 | Observer callback storms (`AXLayoutChanged` fires constantly in a browser) | LOW (cost, not safety) | `st.busy` latch + the token-existence pre-check in the backstop | — |

**The one honest verdict**: T1 means this can never be a *proof* that the approved dialog belongs to
the approved connection. It is a strong correlation under a one-peer constraint. If that is not good
enough, the only real fix is upstream: a dialog that names the requesting peer.

---

## 5. Reliability questions (c)

| Question | Answer | Basis |
|---|---|---|
| Per-window or app-modal? | **Unknown — the recipe is shape-agnostic.** `NSAlert` + `runModal` + `beginSheetModalForWindow:completionHandler:` are all in the binary, so Arc could be doing either. `candidates()` covers a separate window, a sheet on the focused window, and an in-window overlay. | binary strings at 100833114 / 100930715 / 101314580 |
| Active Space only? | The recipe never uses `hs.spaces` and never filters by space. `AXFocusedWindow` and `systemWideElement` are space-agnostic. **`hs.window.filter` is deliberately not on the detection path** partly for this reason (its `currentSpace` semantics) and partly because `allowedWindowRoles` omits `AXSheet`. | measured `allowedWindowRoles = {AXDialog, AXStandardWindow, AXSystemDialog}` |
| Screen locked? | **Treated as a hard refuse** (`st.locked`). AX reads generally survive a lock, but a consent grant taken while the operator is away and cannot see the notification is exactly the case a human would want to review. Detected via `hs.caffeinate.watcher` `screensDidLock`(10) / `screensDidUnlock`(11) / `screensaverDidStart`(7) / `sessionDidResignActive`(5). **Not measured** — the lead should lock the screen and read `M.stats().locked`. | `hs.caffeinate.watcher` constants dumped live |
| Display asleep (not locked)? | AX is unaffected — no display dependency in `AXUIElementCopyAttributeValue`/`AXUIElementPerformAction`. `hs.caffeinate` is **not** needed. This is a first-class argument for AX over `hs.eventtap`. | mechanism; not measured |
| Stacked dialogs (up to 3)? | Handled by `drain()`, `MAX_ROUNDS=3`, **one fresh token per round**. The ObjC delegate signature takes a single `ArcDevToolsConnectionDialog` per call, so they queue rather than stack; if Dia genuinely stacks them, `candidates()` returns several and each round takes the first match. | `v24@0:8@"ArcDevToolsConnectionDialog"16` at 97640400 |
| Dia restarts? | `hs.application.watcher` rebinds the observer on `launched` / clears on `terminated`. An observer is pid-bound; without this it goes permanently deaf after a Dia restart and `stats().observing` would still read `true`. | design |

---

## 6. Fallbacks, ranked worst-last, with the reason each loses

| Fallback | Why it is worse |
|---|---|
| **`osascript` System Events `click button …`** | Measured dead on this target: `process "Dia"` exposes **one** child, `AXMenuBar` (`app AXChildren count=1`). Same AX tree, strictly less expressive, no observer, no element handles — and it spawns a process per attempt (~80-150 ms). Nothing it can reach that `hs.axuielement` cannot. |
| **`hs.eventtap.keyStroke({}, "return")`** | (1) Fires at **whatever is key**, not at a captured element — if the dialog loses focus in the interval the Return lands in a web page or a terminal. (2) **Secure input swallows it** and HS 1.1.1 has **no `hs.eventtap.isSecureInputEnabled`** (measured missing), so the module cannot even detect that it failed. (3) Dead while the screen is locked. (4) Requires Input Monitoring on top of Accessibility. (5) No confirmation channel — a swallowed keystroke and a successful one look identical. |
| **`hs.eventtap` synthetic click at the button's `AXFrame`** | Inherits every keystroke problem **plus** coordinate staleness (T6): a dismissed-and-replaced dialog at the same position gets clicked blind. Also breaks on display-scale/Space changes. |
| **Set `AXEnhancedUserInterface = true` to populate `AXWindows`** | **Measured not to work** (Chrome: `AXEUI=true`, `AXWindows=0`), and it carries a known AppKit window-drag side effect that Dia itself ships a workaround for (`isHandlingSendEvent_` beside the two attribute names at 97626080-97626320). Cost with no benefit. |
| **`AXManualAccessibility = true`** | Electron-only lever. On Dia `isAttributeSettable` → `nil` and the read is `nil`. Not applicable. The openai/codex report is the cautionary precedent: both attributes "return success but read back nil (ignored)" there. |
| **`--force-renderer-accessibility` / relaunching Dia with flags** | Wrong layer entirely: the dialog is a native AppKit object in `ArcCore`, not renderer content. Also destroys the warm logged-in profile that is the whole point of using Dia. And measured: pid 1902's argv carries **no** debugging flags at all — the port came from the in-app `dia://inspect#remote-debugging` toggle, so a flagged relaunch changes the consent path in unknown ways. |
| **Turn the consent dialog off / patch Dia** | Out of scope and removes the only real security boundary (§2). |

---

## 7. Precedents

- **openai/codex #25740** — "macOS desktop app exposes no Accessibility (AX) interface — breaks all
  window managers." A *stricter* form of the same class: there `AXWindows` returns `nil` and the
  attribute list is empty, and the reporter measured that **both** `AXManualAccessibility = true` and
  `AXEnhancedUserInterface = true` "return success but read back `nil` (ignored)." Dia is the milder
  case: the set *does* land (read-back `true`) and `AXFocusedWindow` works.
  <https://github.com/openai/codex/issues/25740>
- **Hammerspoon `hs.axuielement`** — module docs and the observer API surface.
  <https://www.hammerspoon.org/docs/hs.axuielement.html> ·
  <https://www.hammerspoon.org/docs/hs.axuielement.observer.html> ·
  notification-name table read from
  <https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/axuielement/observer.m>
  (camelCase keys — `windowCreated`, `sheetCreated`, `focusedWindowChanged`,
  `focusedUIElementChanged`, `uIElementDestroyed`, … — whose *values* are the `AX…` strings I
  registered with directly).
- **`hs._asm.axuielement` (asmagill)** — the upstream of the in-tree module, and the source of the
  general rule that a module "can only support those features an application makes available."
  <https://github.com/asmagill/hs._asm.axuielement> ·
  <https://github.com/asmagill/hs._asm.axuielement/blob/master/Queries.md>
- **Kent Sutherland, "Using Hammerspoon to fix Revert Changes"** — the closest published pattern to
  what is wanted here: search a window for a button and `AXPress` it.
  <https://ksuther.com/2017/05/13/using-hammerspoon-to-fix-revert-changes>
- **No precedent found** for automating Arc's or Dia's DevTools consent dialog specifically, nor a
  Keyboard Maestro recipe for it. Searched; nothing. Treat this as new ground.

---

## 8. Adversarial pass — what I could not settle, and the lead's checklist

Three gaps I went looking for after drafting, plus the instrument scars.

**G1 — Registration is not firing, and I could not test firing.** All 14 `addWatcher` calls returned
OK and `isRunning()` was `true`, but **nothing created a Dia window during the observation window**,
so `__probeHits` was 0 — an uninformative null, not a negative. Apple's convention is that
`kAXWindowCreatedNotification` is posted *by the application element* with the new window as the
callback's subject, which is why the module registers on the app element and not on a window (a
window registration dies with that window). But "Chromium suppresses `AXWindows`" and "Chromium
still posts `AXWindowCreated`" are independent claims and I verified only the first. **This is why
the 400 ms backstop is not optional.** Falsifier for the lead: with the module running, open any new
Dia window and check whether `devtools_consent` logged an observer callback before the backstop tick.

**G2 — The dialog shape is genuinely unresolved, and the evidence points both ways.**
`ArcDevToolsConnectionDialog` is an ObjC class in the ArcCore/AppKit layer and `NSAlert` + `runModal`
+ `beginSheetModalForWindow:` are all present — but Dia also ships `BoostBrowser_Dialog.bundle`
(a custom dialog surface, Assets.car only). I could not find the presenting function: the strings
around offset 97850688 sit in `browserApplicationController`/`windowCoordinationController`
territory, nowhere near the `presentDiaArtImportConflictDialog(dialogUtilities:…)` family, so the
DevTools dialog does **not** go through Dia's `DialogUtilities`. Consequence: `candidates()` must
stay broad, and **`AXSheets` could not be pre-verified** — it is absent from the attribute-name list
of Dia's, Finder's, kitty's, Chrome's and Cursor's focused windows alike, which is normal AppKit
(added on attach) but means the sheet arm of the recipe is untested code.

**G3 — The `AXEnhancedUserInterface` refutation rests on one short-wait arm.** Chromium's a11y
activation is asynchronous; my successful measurement waited 1.2 s, and the 5 s re-test wedged the
`hs` CLI before printing. Chrome's state was verified restored afterwards
(`AXEUI=false AXManual=nil`) and Dia was confirmed untouched (`AXEUI=false AXManual=nil
AXWindows=0`). The claim survives because it does not matter: `AXFocusedWindow` already works, so no
route depends on `AXWindows` ever populating.

**Instrument scars worth carrying (they cost me three calls):**
- **Never block in `hs -c`.** An `hs.timer.usleep(5s)` chain returned
  `error communicating with Hammerspoon: receive timeout` and later crashed the CLI client with
  `NSDestinationInvalidException … target thread exited while waiting for the perform`. The
  **Hammerspoon process survived** (`pgrep -x Hammerspoon` → alive) — it is the `hs` client that
  dies. Use `hs.timer.doAfter` writing to a file, or separate invocations.
- **`hs -c` printing nothing is not a null result.** Two probes returned zero bytes; a trivial
  `return "PONG"` and a trivial `dofile` both worked immediately after, and the culprit was
  `elementSearch` (async, and it raises `criteria must be a function, if specified` on a plain
  table). Isolate before believing an empty output.
- **`setAttributeValue`'s return value is not its verdict.** `nil` + `"Function or method not
  implemented"` accompanied a set that landed. Read back.

**Checklist for the live-dialog run** — with the dialog up, dump and record:

1. `ax:attributeValue("AXWindows")` count — does the dialog appear where browser windows do not?
2. `fw = ax:attributeValue("AXFocusedWindow")` → `AXRole`, `AXSubrole`, `AXTitle`, `AXModal`,
   `AXIdentifier`. Is the title `Allow debugging connection?` and is `AXIdentifier` free of the
   `bigBrowserWindow_` prefix?
3. `fw:attributeValue("AXSheets")` — present and non-empty? (settles G2)
4. `dlg:attributeValue("AXDefaultButton")` → its `AXTitle`, `AXDescription`, `AXIdentifier`,
   `actionNames()`. **Confirm `AXDescription` is NOT `"DevTools connection dialog allow button"`** —
   that is the §0.1 falsifier.
5. Every descendant's `AXRole`/`AXTitle`/`AXDescription`/`AXIdentifier` to depth 4 — the ground truth
   for a tighter identity check.
6. `systemWideElement():attributeValue("AXFocusedUIElement")` → is it the Allow button?
7. `lsof -nP -iTCP:9222 -sTCP:ESTABLISHED -FpcnT` **at dialog time** — confirm the client pid is
   readable while the prompt is pending (the whole gate rests on this).
8. Whether the observer callback fired at all before the backstop tick (settles G1).
