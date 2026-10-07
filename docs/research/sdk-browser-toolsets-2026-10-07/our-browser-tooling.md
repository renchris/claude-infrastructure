# How this fleet automates browsers today

Source: repo `/Users/chrisren/Development/.worktrees/wt-feat-haiku55-cc-upgrade` (called `R/` below), read 2026-10-07.
Files read in full: the five named `SKILL.md` files, `bin/cc-authbrowser`, `bin/cc-relogin`.
Read in part (headers and grep hits only): `bin/cc-relogin-poll`, `bin/cc-url-open`, `bin/dia-cdp-launch.sh`,
`scripts/browser-spin-guard.sh`, `scripts/chromium-bundle-lint.sh`, `scripts/relogin-probes/README.md`,
`scripts/cloud-create-api.py`, `scripts/limit-recover/lr-probe.sh`, `scripts/dl-sweep.sh`, `scripts/jev/jev-batch.sh`.
Anything those files do not say is marked NOT STATED. Nothing was executed against a browser; this is a reading of the code and docs.

## 1. One-paragraph picture

Every browser tool here is driven one of two ways: (a) a Claude Code session types CLI commands into its Bash tool
(`agent-browser ...`, `osascript ...`, `~/bin/dia-cdp-launch.sh ...`) and reads the text that comes back, or (b) a
plain Python script with no model in it speaks raw Chrome DevTools Protocol (CDP) over one websocket
(`bin/cc-relogin`, `bin/cc-url-open`). There is no script in `bin/` or `scripts/` that runs a model tool loop against
the Claude API to drive a browser, and no use of the Anthropic SDK at all (section 6). The model mostly sees an
accessibility snapshot as text, not screenshots.

## 2. The tools

| Tool | What it is for | How it is driven | What the model sees | Logged-in sessions |
|---|---|---|---|---|
| `agent-browser` CLI (vercel-labs) | "The live, default browser tool": navigate, click, fill, screenshot, extract (`R/skills/agent-browser/SKILL.md:3`) | CLI from a Bash tool call; skill allows only Bash (`SKILL.md:4`). Loop is open -> `snapshot -i` -> act on `@e1` refs -> re-snapshot (`SKILL.md:25-30`) | Accessibility tree as text with element refs (`SKILL.md:45-49`); screenshots are an optional command (`SKILL.md:74-76`) | None by default: "Uses bundled Chromium (not existing Chrome sessions)" (`SKILL.md:11`). `--cdp 9222` attaches to a running browser to reuse its cookies (`SKILL.md:103-122`). Named isolated sessions via `--session` (`SKILL.md:89-93`) |
| Dia AppleScript rail | Tabs, windows, Spaces (profiles) and in-page JS on the operator's real warm Dia, "no port, no consent dialog" (`R/skills/dia-agent/SKILL.md:27-34`) | `osascript` from Bash (`SKILL.md:36-40`, `65-78`) | Whatever the JS returns, as a JSON-encoded string (`SKILL.md:86-87`). No screenshots, no accessibility tree (`SKILL.md:89-91`) | Uses the operator's real logged-in Dia directly (`SKILL.md:12-13`) |
| Dia CDP, primary path (`dia://inspect#remote-debugging`) | Trusted input, screenshots, network, cookies on the real warm Dia (`SKILL.md:13-18`) | `chrome-devtools-mcp --autoConnect --userDataDir ...` as MCP tools, or a raw websocket client (`SKILL.md:160-166`, `203-206`) | CDP data; `Accessibility.getFullAXTree` and screenshots are available here (`SKILL.md:89-91`) | All real sessions in every Space. Needs the operator to approve a consent modal (`SKILL.md:16-18`, `167-170`) |
| Dia CDP, secondary path (`~/bin/dia-cdp-launch.sh`) | Unattended CDP work in an isolated clean Dia profile on port 9222 (`SKILL.md:19-20`, `218-224`; `R/bin/dia-cdp-launch.sh:3-15`) | Launcher from Bash, then `agent-browser --cdp 9222` or `chrome-devtools-mcp --browserUrl http://127.0.0.1:9222` or puppeteer-core (`SKILL.md:143-146`, `249-255`) | `agent-browser --cdp 9222 snapshot -i` "returns an a11y tree in <10s" (`SKILL.md:344-345`) | Clean profile at `~/Library/Application Support/Dia-Agent`; sign in once per site and it persists (`SKILL.md:231-233`, `336`) |
| Plain Chrome fallback | Only if Dia is unavailable (`SKILL.md:260-271`) | `open -n -a "Google Chrome" --args --remote-debugging-port=9222 ...` (`SKILL.md:265-268`) | Same as CDP | Dedicated `Chrome-Agent` profile (`SKILL.md:267`) |
| `chrome-devtools-mcp` | MCP tool surface over CDP, used "when a task genuinely needs the MCP tool surface" (`R/skills/browsermcp/SKILL.md:10-12`) | MCP tools inside a Claude Code session; they load at session start, so a new session is needed if absent (`R/skills/dia-agent/SKILL.md:331`) | NOT STATED in these files (tool list not described) | Attaches to Dia via the two CDP paths above |
| BrowserMCP | Retired 2026-08-11; kept as history only (`R/skills/browsermcp/SKILL.md:6-13`) | Was MCP tools (`SKILL.md:20-27`) | Was an accessibility snapshot (`SKILL.md:21`) | Was a Chrome extension connected per tab (`SKILL.md:32`) |
| `cc-authbrowser` | One dedicated Chrome per Claude account, only for OAuth re-login (`R/bin/cc-authbrowser:2-11`) | Python script; called by `cc-relogin`, not by a model. `--start/--stop/--status` (`cc-authbrowser:4-6`) | No model involved | Persistent profile `~/.claude/auth-profiles/<acct>` (`cc-authbrowser:227-230`); "deleting one logs the account out" (`R/scripts/growth-coverage.conf:163`) |
| `cc-relogin` | Unattended OAuth re-auth of one Claude Max account (`R/bin/cc-relogin:2-10`) | Python script with its own minimal CDP client over one websocket (`cc-relogin:412-453`). Runs by hand or hourly from `cc-relogin-poll` under launchd (`R/bin/cc-relogin-poll:3-4`) | No model involved. It reads `location.href` plus `document.body.innerText` and matches regexes (`cc-relogin:400-409`, `528-531`) | Relies on the auth profile's claude.ai session being warm (`cc-relogin:526-527`, `532-539`) |
| `cc-url-open` | kitty link handler that opens a claude.ai link in the Dia Space of the account that owns the pane (`R/bin/cc-url-open:2-9`) | Python script: AppleScript first, CDP second (`cc-url-open:22-38`) | No model involved | The operator's real Dia profiles |

Where a path is the default: the session-start hook checks that `agent-browser` is installed and tells the session
"Use agent-browser skill for browser automation" (`R/hooks/session-start.sh:407-426`).

The repo worktree has no `.mcp.json` (measured: `ls R/.mcp.json` returned "No such file or directory"), although
`R/skills/dia-agent/SKILL.md:208-211` says the repo `.mcp.json` ships only `chrome-devtools` with `--isolated`.
Which is current is NOT STATED.

## 3. How a model drives a browser (CLI versus API tool loop)

- CLI from Bash inside a Claude Code session: `agent-browser`, the Dia AppleScript rail, the Dia launcher. This is
  the main path (`R/skills/agent-browser/SKILL.md:4`, `R/skills/dia-agent/SKILL.md:4`).
- MCP tools inside a Claude Code session: `chrome-devtools-mcp` only, and only when attached to a running browser
  (`R/skills/browsermcp/SKILL.md:10-12`).
- A file-queue daemon pattern for the warm browser: a long-lived process holds one approved CDP connection and the
  agent appends commands to `in.jsonl` and tails `out.jsonl` (`R/skills/autonomous-authenticated-web-access/SKILL.md:73-79`).
  The skill names `cdp_daemon.py` and `sq.py` as a "reference implementation pattern"; whether those files exist in
  this repo is NOT STATED.
- API tool loop (a script calling the Messages API with a computer-use or browser tool): none found (section 6).

## 4. Screenshots versus DOM or accessibility snapshot

- `agent-browser`: accessibility tree is the working surface; `snapshot -i` (interactive elements only) is
  "recommended" (`R/skills/agent-browser/SKILL.md:45-49`). Screenshots exist as a command and are used for visual
  checks, for example `agent-browser screenshot /tmp/s$i.png` in `R/skills/demo-recording/SKILL.md:392-393`.
- Dia AppleScript: DOM by JavaScript only (`R/skills/dia-agent/SKILL.md:74-75`).
- Raw CDP recipes: locate by accessibility tree or DOM query, get coordinates from `DOM.getBoxModel` or
  `getBoundingClientRect()`, then send a trusted mouse event
  (`R/skills/account-relogin/SKILL.md:102-104`; `R/skills/autonomous-authenticated-web-access/SKILL.md:61-66`).
- `cc-relogin`: DOM query for a button whose text matches `authorize|approve|allow` (`R/bin/cc-relogin:403-407`),
  then `DOM.getBoxModel` plus `Input.dispatchMouseEvent`, with `el.click()` as fallback (`cc-relogin:501-517`).
- No file read describes a model choosing click coordinates from a screenshot. Screenshot-verify appears only as a
  human-side check in the semi-manual re-login fallback (`R/skills/account-relogin/SKILL.md:105-108`).

## 5. Logged-in sessions

Decision rule (`R/skills/autonomous-authenticated-web-access/SKILL.md:16-34`): tier 1 API token and plain `curl`,
"Always try first"; tier 2 clean dedicated profile over CDP, log in once; tier 3 the user's warm browser, "last
resort" because of the consent modal.

- Clean profile, persistent login: Dia-Agent profile (`R/skills/dia-agent/SKILL.md:231-233`) and per-account Chrome
  auth profiles (`R/bin/cc-authbrowser:227-230`).
- Warm real browser: Dia AppleScript (no prompt) or `dia://inspect` CDP (prompt) (`R/skills/dia-agent/SKILL.md:12-18`).
- Cloning the personal profile is "DISCOURAGED" (`R/skills/dia-agent/SKILL.md:257-258`).
- Cookie or keychain extraction to get in is out of scope by policy
  (`R/skills/autonomous-authenticated-web-access/SKILL.md:101-102`).
- Read-only rule for authenticated surfaces: no create, update or delete (`same file:96-97`).

## 6. Plan quota versus API key

Measured with `rg -n "ANTHROPIC_API_KEY|messages\.create|import anthropic|from anthropic|@anthropic-ai/sdk|claude_agent_sdk|claude-agent-sdk" R/bin R/scripts R/hooks R/skills`:

- SDK imports or `messages.create`: zero hits.
- `ANTHROPIC_API_KEY`: two hits, both in `R/bin/claude-kimi` (lines 247 and 318), and both are about unsetting it
  for a Moonshot/Kimi launcher. No script sets or reads an Anthropic API key to call Claude.
- The brief's broader grep (`anthropic|ANTHROPIC_API_KEY|messages.create`) lists 30 files; the ones sampled match on
  package paths or hostnames, not API-key calls: `R/scripts/smoke-test.sh:192-193` (npm package path),
  `R/scripts/limit-recover/lr-probe.sh:40` ("No Authorization header, no API key, no body, HEAD by default"),
  `R/scripts/cloud-create-api.py:101,220,231,265` (posts to `api.anthropic.com` with the account's OAuth access
  token read from the keychain, to create cloud Claude Code sessions; not a Messages call).
  Only those three were opened; the other 27 files were not individually read.
- Headless model use from scripts is `claude -p` on a plan account, for example `R/scripts/dl-sweep.sh:9` ("piped on
  stdin into `claude -p --tools \"\"`") with the account picked by `claude-accounts --rank general` (`dl-sweep.sh:17`).
  That flow reads mail, it does not drive a browser.

So, by flow:

| Flow | Driven by | Billing |
|---|---|---|
| General browsing, testing, extraction with `agent-browser` | Claude Code session, Bash tool | Plan quota |
| Dia AppleScript and Dia CDP work | Claude Code session, Bash or MCP tools | Plan quota |
| Authenticated read-only capture (tiers 1 to 3) | Claude Code session; tier 1 is `curl` with the vendor's token | Plan quota for the session |
| Account re-login (`cc-relogin`, `cc-relogin-poll`, `cc-authbrowser`) | Python and launchd, no model | None (no model call) |
| Link routing (`cc-url-open`) | Python, no model | None |
| Browser driven by a script calling the Claude API with an API key | None found | Not applicable |

## 7. Recorded pain points

Bot walls and detection
- No file read records a specific bot wall, CAPTCHA or Cloudflare block (measured: case-insensitive grep for
  `bot.?wall|cloudflare|captcha|turnstile|anti-bot` across the five skills and the browser scripts returned no hits).
  NOT STATED beyond the items below.
- Hardened single-page apps ignore synthetic clicks because handlers check `event.isTrusted`; the fix is CDP
  `Input.dispatchMouseEvent` and `Input.insertText` (`R/skills/autonomous-authenticated-web-access/SKILL.md:61-66`).
  Dia's AppleScript JS is `isTrusted=false` (`R/skills/dia-agent/SKILL.md:89-90`).
- Values hidden in shadow DOM need a shadow-tree walk or a clipboard read (`autonomous-...SKILL.md:67-72`).
- `navigator.webdriver === false` holds on Dia only because `--enable-automation` is never passed
  (`R/skills/dia-agent/SKILL.md:322`). A "detection surface" catalog is said to live in a memory file not in this
  repo path (`SKILL.md:23-25`); its content is NOT STATED here.
- HeadlessChrome user agent: `--headless=new` "advertises a HeadlessChrome user-agent, the wrong posture for an
  OAuth sign-in", so `cc-authbrowser` defaults to a headed window parked offscreen at `-32000,-32000`
  (`R/bin/cc-authbrowser:13-15`, `498`, `501-502`). Whether headed Chrome survives launchd is an open probe that the
  README says has not been run (`R/scripts/relogin-probes/README.md:3-5`, `15`;
  `R/scripts/relogin-probes/e2-launchd-browser-survival.sh:9-10`).
- Dia is headed only: "`--headless` breaks Dia's native window layer" (`R/skills/dia-agent/SKILL.md:321`).
- `agent-browser` itself is described as a "Headless browser automation CLI" (`R/skills/agent-browser/SKILL.md:11`);
  what user agent it sends is NOT STATED.

Consent dialogs
- Dia's "Allow debugging connection?" modal fires per connection on the `dia://inspect` path and cannot be persisted
  by any flag or policy (`R/skills/dia-agent/SKILL.md:119-125`).
- Client reconnects multiply it: chrome-devtools-mcp reconnects on every transport drop, and agent-browser 0.27.1's
  port discovery "probes, closes, then connects = two modals" (`SKILL.md:98-103`). Dialogs stack and the connection
  hangs until approved (`SKILL.md:167-170`).
- Never auto-press it: the dialog carries no pid, port or origin (`SKILL.md:108-110`). A timed-out handshake strands
  a modal sheet on the operator's browser (`SKILL.md:111-112`).
- This blocked `cc-url-open`'s CDP leg on and off, which is why it now tries AppleScript first
  (`R/bin/cc-url-open:22-38`).
- `cc-relogin` avoids the dialog by using a dedicated Chrome profile; its exit 7 "consent-gate" is retained but never
  emitted (`R/bin/cc-relogin:50-53`; `R/skills/account-relogin/SKILL.md:22-25`).

Leaked and runaway browser processes
- 2026-08-17: an `agent-browser` daemon held a headless Chrome with every service process at 86-103% CPU for a day
  and a half; load average 244 (`R/scripts/browser-spin-guard.sh:4-10`).
- 2026-08-20: same class, 500% aggregate CPU for 2 days 20 hours, about 340 CPU-hours; the alarm fired on every tick
  and nobody acted (`browser-spin-guard.sh:61-75`). The guard now reaps on a schedule (`browser-spin-guard.sh:51`, `98`).
- The guard's old reap ran `agent-browser close --all` and caused about 26 fleet-wide browser wipes, 12 in 71
  minutes, closing every live session's warm browser while killing zero spinning processes
  (`browser-spin-guard.sh:292-296`). It now closes one named session.
- The `agent-browser` daemon is meant to outlive the session that started it (`browser-spin-guard.sh:20-25`), so an
  old or orphaned browser is normal and cannot be told from a leak by age or parent.
- 2026-10-05: a 60-second timeout killed `cc-authbrowser --start` between launch and state write, orphaning next4's
  Chrome on port 9344; "the next nine hourly relogin attempts all exited 4" (`R/bin/cc-authbrowser:408-414`). Fixed
  by an orphan reclaim step (`cc-authbrowser:456-461`).
- An open CDP port must never outlive a run: detached TTL watchdog, default 300 s, with a pid-recycle guard
  (`cc-authbrowser:17-20`, `94`, `599-610`). The Dia launcher has the same idea in `supervise [ttl]`
  (`R/skills/dia-agent/SKILL.md:134-137`).
- Fixed CDP ports 9341-9344 collided with per-worktree Node `--inspect` debuggers, so phase 2 "had never once
  succeeded" until a free-port fallback was added (`cc-authbrowser:467-474`).
- An untracked automation Chrome tree (`sevenrooms-bridge/sidecar`, 11 processes, 528 MB) sat outside every watcher
  (`R/scripts/capacity-alarm.sh:1146-1155`).
- A shell-backgrounded Dia is reaped within seconds; `open -n` survives only from a foreground shell
  (`R/skills/dia-agent/SKILL.md:131-133`). The keep-warm LaunchAgent is permanently disabled after it corrupted a
  profile (`SKILL.md:226-229`).
- `agent-browser --cdp` can hang on macOS, "bug #1193" (`SKILL.md:334`).
- Enabling the CDP Network domain on a busy tab runs the daemon out of memory
  (`R/skills/autonomous-authenticated-web-access/SKILL.md:80-83`).
- Launching the full Chromium.app bundle per screenshot makes the operator's Dock flicker; `--headless=new` on that
  bundle was worse and 3.5 times slower (`R/scripts/chromium-bundle-lint.sh:5-14`).

Steps that are not automated
- The email-code leg of a re-login. When the auth profile's claude.ai session is cold the page lands on `/login`
  and `cc-relogin` exits 6 with "the email-code leg is NOT automated. REMAINING HUMAN STEP: open that URL, sign in
  ... take the emailed code" (`R/bin/cc-relogin:532-539`). The runbook lists three ways to fetch the code (same
  profile's Outlook webmail, Microsoft Graph, human paste) but the Graph token cache "currently covers ONE mailbox"
  (`R/skills/account-relogin/SKILL.md:132-140`). Microsoft password or 2FA is "out of scope, never automate it"
  (`SKILL.md:142-143`).
- The dedicated profiles go cold by design: "browsers nobody uses, so their claude.ai sessions only age"; `next`
  was signed in as the right account and still bounced to `/login?reauth=1` (`R/bin/cc-relogin:640-643`).
- The `--dia` route needs one human click on Authorize, because Dia "cannot be CLICKED unattended here"
  (`cc-relogin:644-648`, `727-728`). Note the conflict: `R/skills/dia-agent/SKILL.md:52-53` says the AppleScript JS
  launch flag is enabled on this machine as of 2026-09-14. Which holds today is NOT STATED.
- Each failed hourly attempt left a dead "Sign in - Claude" tab in the operator's Dia: 84 attempts against next2,
  31 of them exit 6 (`R/bin/cc-relogin-poll:42-46`). The poller now stops retrying after the first exit 6
  (`cc-relogin-poll:34-39`, `48`).
- The warm-Dia CDP path needs the operator at the screen to approve the modal and to uncheck the toggle afterward
  (`R/skills/dia-agent/SKILL.md:16-18`, `198-201`).
- A fresh Dia-Agent profile needs a one-time interactive sign-in per site (`SKILL.md:236-238`, `336`).
- API token bootstrap is "One bootstrap human action (create app / approve OAuth)"
  (`R/skills/autonomous-authenticated-web-access/SKILL.md:18`).

Security notes recorded
- The `dia://inspect` port is unauthenticated and exposes every Space's full cookie store, not just the Space being
  driven (`R/skills/dia-agent/SKILL.md:275-281`). `cc-url-open` therefore never turns it on (`R/bin/cc-url-open:40-44`).
- The clean-profile port on 9222 is also unauthenticated; kill it when done (`SKILL.md:282-286`).

## 8. NOT STATED in the files read

- Any per-site success rate, latency or token cost for `agent-browser` runs.
- Whether any flow uses a model reading screenshots to pick click targets.
- The `chrome-devtools-mcp` tool list and whether its results are snapshots or images.
- Which user agent `agent-browser`'s bundled Chromium sends.
- Any named bot wall, CAPTCHA or Cloudflare block hit by this fleet.
- Whether `cdp_daemon.py` and `sq.py` exist in this repo.
- Whether the current repo config registers any `chrome-devtools` MCP server.
- The contents of the 27 files from the brief's API grep that were not individually opened.
