# Assessment: what the SDK computer-use and browser-use toolsets change for us

Written 2026-10-07 by one read-only worker. Nothing was installed, no API call was made, no account was touched.

## Bottom line

No change. The launch ships two abstract SDK classes, not a browser and not a driver. Using them means running a
second agent loop in a script that holds an Anthropic API key and is billed per token. Our loop already runs inside
Claude Code on plan quota, and `agent-browser` already gives the model the same kind of working surface (a text
snapshot with element refs). Nothing in the sources addresses any pain point we have on record.

## What this rests on

Named sources, checked against the primary text:
- Docs page: `/tmp/browser-sdk/browser-use-sdk.md` (cited as `docs L<n>`). I re-read the ranges I rely on.
- Quickstart: `/tmp/browser-sdk/cq/computer-toolset/` (README, `run.py`, `run.ts`, `exercise.py`, `requirements.txt`,
  `package.json` read directly).
- Video: `/tmp/browser-sdk/notes/video.md`; I opened frames f-017, f-025 and f-030 to confirm the captions I quote.
- Our tooling: `/tmp/browser-sdk/notes/our-browser-tooling.md` (cited as `tooling §<n>`).

Supplementary, outside the named sources, labeled "FLEET COPY" wherever used. These are local files in
`/Users/chrisren/Development/.worktrees/wt-feat-haiku55-cc-upgrade` (called `R/`), read to identify "our gate" and to
find where the model requirement comes from. I did not re-fetch the pages they copy.
- `R/docs/research/haiku55-upgrade-2026-10-07/pack/{migration-guide.md, whats-new-haiku-5-5.md, pricing.md, announcement.txt}`
- `R/docs/research/haiku55-upgrade-2026-10-07/UPGRADE.md` and `gate/`
- `R/docs/research/opus55-utilization-2026-09-22/notes/`, `R/docs/research/sonnet55-utilization-2026-09-28/notes/` (our own notes, not page copies)
- `R/scripts/cc-upgrade-gate.sh`, `R/lib/cc-upgrade-gate/`, `R/skills/agent-browser/SKILL.md`

Not read: the browser toolset CDP quickstart. The docs point to it (docs L11) and the repo index lists it
(`/tmp/browser-sdk/cq/README.md:41-45`), but only `computer-toolset/` is in our checkout.

---

## A. Anything to adopt now? No change. Conviction 88%.

Flows considered, each with the reason it does not get measurably better:

| Our flow | Verdict | Why |
|---|---|---|
| General browsing, testing, extraction: Claude Code session runs `agent-browser` from Bash (tooling §2, §6) | No change | The loop and the ref-based snapshot already exist. The toolset would add a second, API-billed loop. |
| Dia AppleScript rail and Dia CDP work (tooling §2) | No change | The docs tell you not to drive a signed-in profile (docs L271, L813). The Dia consent modal is a Dia behavior the SDK cannot touch. |
| Authenticated read-only capture, tiers 1 to 3 (tooling §5) | No change | Same signed-in-profile conflict. Tier 1 is `curl` with a token and has no browser in it. |
| Account re-login: `cc-relogin`, `cc-relogin-poll`, `cc-authbrowser` (tooling §2) | No change | No model is involved today. The open gap is the emailed-code leg and cold profiles (tooling §7), which is a credential and policy problem, not a loop problem. |
| Link routing: `cc-url-open` | No change | No model is involved. |
| Demo-recording screenshots with `agent-browser screenshot` (tooling §4) | No change | A plain capture step. |

Evidence:
1. Nothing ships that you can switch on. "The SDK doesn't include a browser, a desktop, a ready-made driver, or a URL
   policy." (docs L11; repeated for the computer class at L836). Browser Use, Browserbase, Daytona and E2B are outbound
   links only (docs L19-38).
2. The model loop needs an API key. See B.
3. The working surface is one we already have. The video's browser demo is `read_page` returning refs, then
   `form_input` and `left_click` by ref (video f-013 to f-019). Our loop is `snapshot -i` returning `@e` refs, then
   `click @e` and `fill @e` (`R/skills/agent-browser/SKILL.md:23-30`).
4. None of our recorded pains is covered. Ours are leaked and runaway browser processes, the Dia consent modal, cold
   login profiles, and CDP port collisions (tooling §7). The SDK does not own browser lifetime: "The runner never
   closes the toolset" (docs L263). Sign-in, bot walls and consent dialogs: NOT STATED anywhere in the sources.
5. The safety model points the other way from our authenticated flows: a fresh profile, no credentials, one container
   or VM per session (docs L805-813).
6. The sources give no comparison against any other way of driving a browser. The only performance figure is the
   video caption "Three handwritten cards. 67 calls, 46 seconds, no typos." (frame f-025, viewed). What the 46 seconds
   covers and which driver ran it are NOT STATED.

The one free hint in the material is model choice, not this SDK: every demo figure is labeled `CLAUDE-HAIKU-5-5`
(video headers). Which model drives browser steps in our sessions belongs to the Haiku 5.5 upgrade lane
(`R/docs/research/haiku55-upgrade-2026-10-07/UPGRADE.md`), so I make no recommendation on it here.

What would move this: the operator authorizes API spend, and a named flow needs a model-driven browser with no
Claude Code session behind it, or pixel-level work on a canvas, map or 3D view (video FIG 1 and FIG 2). Neither is on
record today (tooling §3, §4, §6).

## B. Can the SDK browser toolset run without API billing? Per the sources, no. Conviction 85%.

What the sources state:
- The quickstart requires "an Anthropic API key in `ANTHROPIC_API_KEY`" (`README.md:24`; also `run.py:12`, `run.ts:14`).
- Every example builds the plain client and calls the Messages API: `client = Anthropic()` then
  `client.beta.messages.tool_runner(...)` (docs L139-141; `run.py:47,57`; `run.ts:32,53`).
- The docs say the calling code "holds your API key and the conversation" (docs L816).
- Claude Code, the Agent SDK, OAuth, subscription or plan auth: NOT STATED. Measured with `grep -c` on the docs page:
  0 lines each for "Claude Code", "Agent SDK", "OAuth", "subscription", "auth_token". The quickstart does not mention
  them either: 0 hits over its 11 files (measured with
  `grep -rn -i -E "claude code|agent sdk|agent-sdk|oauth|subscription|auth_token|max plan|\bplan\b"`).
- Pricing: NOT STATED on the docs page or in the quickstart (0 lines for "pricing").

What does run with no key and no billing: the driver half. "`exercise` needs no API key" (`README.md:68`). It sends
hand-built `tool_use` blocks through `computer.tool_result(...)` (`exercise.py:39-40`). So a driver can be built and
tested for free; only the model loop is billed.

Why not 100%:
- `run.py:51` has a comment, "There is no SDK profile, or no usable VNC server." What an "SDK profile" is, and
  whether it can carry anything other than an API key, is NOT STATED.
- The four SDK guides the docs link (docs L14, L1247) were not among the files given to me.

FLEET COPY, relevant to the cost gate but not a way around it: the Haiku 5.5 announcement says a monthly API credit
is rolling out "this week" to Max and Team subscribers, "$100 in credits per month" for Max 5x and "$200" for Max 20x,
usable "on any of our models" (`pack/announcement.txt:230`). That is still API-key, per-token usage drawn from a
credit. Whether to claim or spend it is the operator's decision; we hold no authorization to spend API credits.

## C. Is a driver for agent-browser or a CDP-attached Chrome worth writing? Not now. Conviction 80%.

Does the interface fit? Yes.
- You subclass one class and write one method per member; a member you leave out is sent as disabled (docs L7, L263).
- A browser "you reach at a DevTools URL" is a named case (docs L822).
- The browser members named on the page (`navigate`, `screenshot`, `left_click`, `read_page`, `get_page_text`,
  `find`, `read_console`, the tab members; docs L351-357) line up with `agent-browser` commands (`open`, `back`,
  `forward`, `reload`, `screenshot`, `click`, `snapshot`, `get text`, `console`;
  `R/skills/agent-browser/SKILL.md:34-99`). That mapping is my reading; no source states it.
- Effort: NOT STATED for a browser driver. The computer example driver is "a few hundred lines" (`README.md:5`).

What it would buy over what we have:
1. A model-driven browser run with no Claude Code session behind it, for example a script under launchd. We have none
   today (tooling §3, §6). This is exactly the API-billed path.
2. Several actions per turn, run in order, optionally started while the response is still streaming
   (docs L391-399, L1253). Speed gain over Claude Code Bash calls: not measured by anyone.
3. Code-level gates: `confirm` before every call, a URL policy on `navigate`, a file policy (docs L511). Claude Code
   already has its own permission prompts and hooks. The URL policy sees only `navigate`, not clicks, redirects or
   subresources (docs L1251).
4. The model is offered first-party member tools instead of composing CLI strings. Whether that raises accuracy over
   `agent-browser`: NOT STATED.
5. With the computer class, pixel actions (drag, zoom on a region) for canvas, map and 3D pages that a text snapshot
   cannot reach (video FIG 1, FIG 2). No recorded flow of ours picks click targets from a screenshot (tooling §4).

What it would not buy: browser process lifetime (docs L263), login state, relief from the Dia consent modal, image
resizing (docs L1083), request interception, egress control or sandboxing (docs L511).

What it would cost:
- An API key and per-token billing for every step (B).
- Toolset definition overhead of "about 6,600 input tokens" per request for the browser toolset and "about 4,500"
  for the computer toolset, plus screenshots billed as image input (FLEET COPY `pack/pricing.md:383,403`). The named
  sources give no pricing.
- A driver we own on a beta interface (docs L14).
- For a CDP-attached warm Chrome or Dia, running against written guidance: "The browser profile must not be signed in
  to any account whose data or actions you wouldn't hand to Claude" (docs L813).
- A newer SDK than the one on this Mac. The quickstart needs `anthropic>=1.12.0` (`requirements.txt:2`); the installed
  one is 0.105.2 (measured with `python3 -c "import anthropic; print(anthropic.__version__)"`).

If the cost gate ever opens, a driver that speaks CDP directly is the better shape than one that shells out to the
`agent-browser` CLI, because wrapping the CLI inherits its long-lived daemon, the source of our runaway-process
incidents (tooling §7). That is my inference, not a statement in the sources.

## D. Does the launch change computer-use tool requirements for 5.5 models in a way that touches Claude Code or our gate? No. Conviction 90%.

Named sources:
- The docs page states no model requirement, no wire `type` string and no beta header. Measured with `grep -c`:
  0 lines for `computer_20`, `computer_toolset`, `browser_toolset`, `betas`. The only model id on the page is
  `claude-opus-5-5`, 8 occurrences (measured with `grep -o` and `uniq -c`).
- The quickstart names the type `computer_toolset_20260801` once, in prose (`README.md:3`), and defaults to
  `claude-sonnet-5-5` (`run.py:58`).
- Whether older tool types are rejected: NOT STATED in the named sources.

FLEET COPY: the requirement is real, but it came with the models, not with this SDK launch.
- Haiku 5.5: "supports computer use only through the `computer_toolset_20260801` toolset, and a request that declares
  `computer_20250124` returns a 400 error", on the Claude API and Google Cloud (`pack/migration-guide.md:115`).
- Opus 5.5 and Sonnet 5.5: our own notes dated 2026-09-22 and 2026-09-28 already record that `computer_20251124` is
  rejected on the Claude API and Google Cloud and only `computer_toolset_20260801` is accepted
  (`opus55-utilization-2026-09-22/notes/c9-announce-whatsnew-migration.md:117`,
  `sonnet55-utilization-2026-09-28/notes/vendor-docs.md:177`). These are our notes, not page copies.
- So the SDK launch adds helper classes for a toolset the 5.5 models already required. It adds no new requirement
  that I can find.

Why it does not touch us:
- The requirement applies to a Messages request that declares a computer-use tool. No fleet code declares one: zero
  hits for SDK imports or `messages.create` in `R/bin`, `R/scripts`, `R/hooks`, `R/skills` (tooling §6). Our sessions
  run `agent-browser` through the ordinary Bash tool.
- Claude Code binary: 0 occurrences of `computer_toolset_20260801`, `browser_toolset_20260801`, `computer_20251124`
  and `computer_20250124` in both the 2.1.293 candidate and the 2.1.284 pin, with the positive control
  `claude-opus-5` at 139 in each (measured with a Python `mmap` byte count over
  `~/.claude-293/.../claude-code-darwin-arm64/claude` and the `~/.claude-284` equivalent). A zero byte count is
  evidence, not proof; a string can be built at run time.
- Whether Claude Code's own computer use or Claude in Chrome features use the toolset types: NOT STATED.
- Our gate is `cc-upgrade-gate`, 15 checks (binary, entitlement, automode, effort, launcher, depth, teams, workflow,
  subagent, hooks, permission, resume, mcp, authstore, depth_effect; `R/lib/cc-upgrade-gate/`). None of them exercises
  a computer-use, browser or toolset path: 0 hits for `computer|browser|toolset|ANTHROPIC_API_KEY` in the gate script
  and library (measured with `rg -n -i`). The gate read GREEN, 14 pass, 0 fail, 1 skip, on 2.1.293 with
  `claude-haiku-5-5` and with `claude-opus-5-5` today (`UPGRADE.md`). No gate change is called for.

## E. Smallest probe for the largest open question. Conviction 70% that this is the right probe.

The decision in A does not wait on this. Run it only if the operator wants the question closed.

Largest open question: would the SDK-run loop beat our Claude Code plus `agent-browser` loop on a real task by
enough to matter? The sources give one unqualified number (67 calls, 46 seconds, no typos). We have no number of our
own: per-site success rate, latency and token cost for `agent-browser` runs are not recorded anywhere (tooling §8).
With no baseline, "measurably better" cannot be judged in either direction.

Smallest probe: measure our own baseline, with no API key.
1. Write one local static HTML page shaped like the video's FIG 3: a lead form with the same 9 inputs (5 text boxes,
   1 select, 1 number, 1 radio pair, 1 notes box) and a Save button, plus 3 lead cards shown as images so the model
   has to read them from a screenshot.
2. Drive it with what we already run: one Claude Code session on Haiku 5.5 (gate GREEN on 2.1.293), `agent-browser`
   0.27.1 (measured with `agent-browser --version`), bundled Chromium, one named `--session`, closed by name at the end.
3. Record three things per run, 3 runs: tool calls, wall-clock seconds, wrong fields.
4. Fix the reading before the run. Suggested: zero wrong fields and a median time within 3 times the video's
   46 seconds (138 seconds) closes the question as "no change". Anything worse means the gap is real, and whether to
   pay for the comparison becomes the operator's call.

Cost of the probe:
- API dollars: 0. No key is used.
- Plan quota: one short Haiku 5.5 session. Estimated under 100 tool calls (method: 3 runs times about 30 actions,
  scaled from the video's 67 calls for 3 cards). Not measured.
- Time: estimated 30 to 60 minutes including writing the page (my estimate; no source).

What it cannot settle: how the SDK loop would do on the same page. That needs the paid half: a current SDK, a small
CDP driver, an API key and operator authorization. Estimated $0.30 per run on Haiku 5.5 (method: 67 calls times an
assumed 40,000 input tokens of context per request times the $0.10 per million input-token list price in FLEET COPY
`pack/pricing.md:34`, no caching; the assumed context size is mine). The rate is 5 times higher for prompts over
100,000 tokens (`pack/pricing.md:35`), and Sonnet 5.5 and Opus 5.5 list at $2 and $4 per million input tokens
(`pack/pricing.md:21,29`), so the same run is an estimated $5 to $11 there. Small in dollars, but it is API spend we
are not authorized to make.

A sub-question already closed here at zero cost: the installed Claude Code binaries carry neither toolset type
string (D), so there is no sign that Claude Code offers these toolsets as a plan-quota route.

---

## NOT STATED in the sources

- Whether the SDK toolsets can run through Claude Code, the Agent SDK, or Max plan auth.
- What the "SDK profile" in `run.py:51` is.
- Pricing or token cost (docs page and quickstart).
- A supported-model list, the wire `type` string for the browser toolset as sent, and any beta header.
- Whether older computer tool types are rejected (stated only in the fleet copies, not in the named sources).
- Any comparison of the toolsets with CLI-driven or MCP-driven browser tools.
- What the video's 46 seconds covers, which driver ran the demos, and where the browser ran.
- How to attach to an existing browser, reuse a persistent profile, or bring a logged-in session.
- How any partner integration is configured or priced.
- Whether Claude Code's own computer use or Claude in Chrome features use the toolset types.
- The effort to write a browser driver.

## Deviations from the brief

- I read files in the fleet worktree beyond the four notes, to identify "our gate" and to trace the model
  requirement in D. Every such fact is labeled FLEET COPY or cited to an `R/` path.
- I ran three read-only local measurements that are not source readings: the byte count over the two installed
  Claude Code binaries, `agent-browser --version`, and the Python `anthropic` version check.
- I did not read the browser toolset CDP quickstart, because it is not in the local checkout.
